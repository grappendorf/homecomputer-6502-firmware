// license:MIT
// copyright-holders:Dirk Grappendorf
/**********************************************************************************************

    HomeComputer 6502

    Self-built 6502 home computer. See ../../../../docs/system-spec.md for the full hardware
    specification this driver is derived from.

    Memory map ($0000-$FFFF):
        $0000-$7EFF  32000 bytes RAM
        $7F00-$7F1F  ACIA (MOS 6551, base $7F00)
        $7F20-$7F3F  VIA1 (6522, base $7F20) - LCD (PA0-6), LED (PA7), keyboard rows 8-13 (PB0-5)
        $7F40-$7F5F  VIA2 (6522, base $7F40) - keyboard columns (PA0-7), keyboard rows 0-7 (PB0-7)
        $7F60-$7F7F  SID (8580, base $7F60)
        $8000-$FFFF  32768 bytes ROM (AT28C256 EEPROM)

    Status: first attempt at a driver skeleton, not yet verified to boot correctly.
    Known simplifications / TODO, see docs/system-spec.md and mame/README.md:
        - LCD is modelled as two independent HD44780U controllers sharing the data/RS lines
          with separate enable lines (E1 -> lines 0/1, E2 -> lines 2/3), as on the real
          hardware, composited into one 4x40 screen by screen_update_lcd() below.
        - Keyboard matrix uses the scancodes from docs/keyboard-matrix.md; all 87 assigned
          scancodes are entered (see INPUT_PORTS_START below).
        - Fn+Windows hard reset key combination not implemented (those two keys are outside
          the 87-key scan matrix in the first place, see docs/keyboard-matrix.md section 7).
        - Serial (ACIA) is wired to an RS232 slot with a slim device list (pty + null_modem).
          Default attachment is pty, so host tools like picocom can open the PTY MAME prints
          at start. /CTS /DSR /DCD stay tied low like the real JP4 (TX/RX/GND only).

**********************************************************************************************/

#include "emu.h"

#include "cpu/m6502/m6502.h"
#include "bus/rs232/null_modem.h"
#include "bus/rs232/pty.h"
#include "bus/rs232/rs232.h"
#include "machine/6522via.h"
#include "machine/mos6551.h"
#include "machine/input_merger.h"
#include "sound/mos6581.h"
#include "video/hd44780.h"
#include "dipty.h"
#include "emupal.h"
#include "emuopts.h"
#include "fileio.h"
#include "screen.h"
#include "speaker.h"

#include "homecomputer6502.lh"

#include <SDL2/SDL.h>

#include <cstdio>
#include <string>


namespace {

class homecomputer6502_state : public driver_device
{
public:
	homecomputer6502_state(const machine_config &mconfig, device_type type, const char *tag)
		: driver_device(mconfig, type, tag)
		, m_maincpu(*this, "maincpu")
		, m_via1(*this, "via1")
		, m_via2(*this, "via2")
		, m_acia(*this, "acia")
		, m_sid(*this, "sid")
		, m_lcd1(*this, "lcd1")
		, m_lcd2(*this, "lcd2")
		, m_row(*this, "ROW%u", 0U)
		, m_fn_win(*this, "RESET")
		, m_led(*this, "led0")
	{ }

	void homecomputer6502(machine_config &config);

	// Fn + Windows key held together -> hard reset. These two keys are outside the 14x8 scan
	// matrix (see docs/keyboard-matrix.md section 7); on the real hardware they are wired
	// directly into the reset circuit (system-spec.md 5.6/7), not read through VIA2/VIA1 like
	// the other 87 keys, so this is modelled as a separate input port + change handler instead
	// of a matrix position. Public because PORT_CHANGED_MEMBER binds it from outside the class.
	DECLARE_INPUT_CHANGED_MEMBER(fn_win_reset);

private:
	virtual void machine_start() override ATTR_COLD;

	void mem_map(address_map &map) ATTR_COLD;

	// Composites both HD44780U controllers (2 lines x 40 chars each) into one 4x40 screen:
	// lcd1 -> display lines 0/1, lcd2 -> display lines 2/3 (see system-spec.md 5.5).
	uint32_t screen_update_lcd(screen_device &screen, bitmap_ind16 &bitmap, const rectangle &cliprect);

	// EA W404B-NLW is a blue-negative STN LCD: white/pale text on a dark blue background,
	// see homecomputer-6502-images/ea-w404b-nlw-lcd.png in the hardware repo.
	void palette_init(palette_device &palette);

	// VIA1 port A: LCD data/control (PA0-3 = D4-D7, PA4 = RS, PA5 = E1, PA6 = E2) and LED (PA7)
	void via1_pa_w(uint8_t data);
	// VIA1 port B: keyboard row select, rows 8-13 (PB0-5)
	void via1_pb_w(uint8_t data);

	// VIA2 port A: keyboard column read (PA0-7)
	uint8_t via2_pa_r();
	// VIA2 port B: keyboard row select, rows 0-7 (PB0-7)
	void via2_pb_w(uint8_t data);

	required_device<m6502_device> m_maincpu;
	required_device<via6522_device> m_via1;
	required_device<via6522_device> m_via2;
	required_device<mos6551_device> m_acia;
	required_device<mos8580_device> m_sid;
	required_device<hd44780u_device> m_lcd1;
	required_device<hd44780u_device> m_lcd2;
	required_ioport_array<14> m_row;
	required_ioport m_fn_win;

	// status LED (VIA1 PA7, see system-spec.md 5.7), driven from via1_pa_w() and read by
	// the "led0" element in mame/src/layout/homecomputer6502.lay
	output_finder<> m_led;

	uint16_t m_row_select = 0; // bit n set = row n driven low (see docs/keyboard-matrix.md section 1.1)
	bool m_lcd_e1 = false;
	bool m_lcd_e2 = false;
};


void homecomputer6502_state::machine_start()
{
	save_item(NAME(m_row_select));
	save_item(NAME(m_lcd_e1));
	save_item(NAME(m_lcd_e2));

	// /CTS, /DSR, /DCD are hard-wired to GND on the real hardware (system-spec.md 5.1), i.e.
	// permanently asserted. MAME's mos6551_device defaults these inputs to the DEASSERTED
	// state, and the transmitter state machine never starts at all while CTS is deasserted -
	// without this, acia_putc()'s "wait for TX_EMPTY" loop in the firmware hangs forever.
	m_acia->write_cts(0);
	m_acia->write_dsr(0);
	m_acia->write_dcd(0);

	// No ROM_LOAD checksum. The image is rebuilt on every firmware change, and a
	// stale CRC is what put MAME's red "ROMs are incorrect" screen in front of a
	// working machine. scripts/run-mame.sh copies it to rompath/homecomputer6502/.
	emu_file firmware(machine().options().media_path(), OPEN_FLAG_READ);
	std::error_condition const ferr = firmware.open("homecomputer6502/firmware.bin");
	if (ferr)
		fatalerror("firmware.bin: %s\n", ferr.message().c_str());
	u32 const got = firmware.read(memregion("maincpu")->base() + 0x8000, 0x8000);
	if (got != 0x8000)
		fatalerror("firmware.bin: expected 32768 bytes, got %u\n", got);

	// PTY slave path is otherwise only in MAME's UI (Pseudo Terminals). Print it so
	// picocom / mame-disk can attach without hunting through the menu.
	for (device_pty_interface &pty : pty_interface_enumerator(*this))
	{
		if (pty.is_open() && !pty.slave_name().empty())
		{
			osd_printf_info("ACIA serial PTY: %s\n", pty.slave_name().c_str());
			if (std::FILE *const out = std::fopen("/tmp/homecomputer6502.pty", "w"))
			{
				std::fprintf(out, "%s\n", pty.slave_name().c_str());
				std::fclose(out);
			}
		}
	}

	// MAME keys are physical positions (US QWERTY names). On a QWERTZ host the
	// key labeled Y is KEYCODE_Z and the key labeled Z is KEYCODE_Y. Other
	// letters sit on the same positions, which is why only this pair was swapped.
	SDL_Keycode const physical_y = SDL_GetKeyFromScancode(SDL_SCANCODE_Y);
	if (physical_y == SDLK_z)
	{
		ioport_field *const y = m_row[0]->field(0x40);
		ioport_field *const z = m_row[3]->field(0x80);
		if (y && z)
		{
			// Live sequences are copied before machine_start, so both must move.
			auto retarget = [] (ioport_field &field, input_code code)
			{
				field.set_defseq(input_seq(code));
				ioport_field::user_settings settings;
				field.get_user_settings(settings);
				settings.seq[SEQ_TYPE_STANDARD] = input_seq(code);
				field.set_user_settings(settings);
			};
			retarget(*y, KEYCODE_Z);
			retarget(*z, KEYCODE_Y);
		}
	}
}


//**************************************************************************
//  Fn + Windows key -> hard reset
//**************************************************************************

// Fires on every change of either key. On the real board both keys must be held together.
// A click on either on-screen key sets both bits (two stacked layout items). A PC keyboard
// has one Windows key, mapped to the Windows bit only, so either bit is enough here: that
// key is the chord. A real hard reset re-runs the whole reset circuit (system-spec.md
// section 7), so every device on /RESET starts over together.
// machine().schedule_soft_reset() is MAME's equivalent (resets all devices, unlike a single
// device's INPUT_LINE_RESET).
INPUT_CHANGED_MEMBER(homecomputer6502_state::fn_win_reset)
{
	if (m_fn_win->read() & 0x03)
		machine().schedule_soft_reset();
}


//**************************************************************************
//  LCD (VIA1 port A)
//**************************************************************************

void homecomputer6502_state::via1_pa_w(uint8_t data)
{
	// PA0-3 = LCD_D4..D7 -> HD44780 DB4..DB7 nibble (upper nibble of the byte passed to db_w)
	uint8_t nibble = (data & 0x0f) << 4;
	m_lcd1->db_w(nibble);
	m_lcd2->db_w(nibble);

	int rs = BIT(data, 4);
	m_lcd1->rs_w(rs);
	m_lcd2->rs_w(rs);

	// R/W is hard-wired to GND on the real hardware (write-only, see system-spec.md 5.5)
	m_lcd1->rw_w(0);
	m_lcd2->rw_w(0);

	bool e1 = BIT(data, 5);
	bool e2 = BIT(data, 6);
	if (e1 != m_lcd_e1)
	{
		m_lcd_e1 = e1;
		m_lcd1->e_w(e1);
	}
	if (e2 != m_lcd_e2)
	{
		m_lcd_e2 = e2;
		m_lcd2->e_w(e2);
	}

	// PA7 = status LED, active high, see system-spec.md 5.7
	m_led = BIT(data, 7);
}


//**************************************************************************
//  Composite 4x40 LCD screen
//**************************************************************************

// hd44780_base_device::render() fills an internal buffer with, for every character position
// (line 0..m_num_line-1, column 0..m_chars-1), m_char_size bytes (one per dot row), each byte
// holding the 5-pixel row in bits 4..0 (bit4 = leftmost). See hd44780.cpp render()/pixel_update
// for the layout this replicates. Both controllers are configured 2 lines x 40 chars, 5x8 font
// (see set_lcd_size() calls below), so char_size=8 and each line is 40*16=640 bytes apart.
void homecomputer6502_state::palette_init(palette_device &palette)
{
	palette.set_pen_color(0, rgb_t(30, 50, 140));   // background: dark blue
	palette.set_pen_color(1, rgb_t(225, 235, 255)); // "on" dots: pale, slightly blue-tinted white
}


uint32_t homecomputer6502_state::screen_update_lcd(screen_device &screen, bitmap_ind16 &bitmap, const rectangle &cliprect)
{
	bitmap.fill(0, cliprect);

	const u8 *buf1 = m_lcd1->render(); // display lines 0/1
	const u8 *buf2 = m_lcd2->render(); // display lines 2/3

	for (int line = 0; line < 2; line++)
	{
		for (int pos = 0; pos < 40; pos++)
		{
			const u8 *src1 = buf1 + 16 * (line * 40 + pos);
			const u8 *src2 = buf2 + 16 * (line * 40 + pos);
			for (int y = 0; y < 8; y++)
			{
				for (int x = 0; x < 5; x++)
				{
					bitmap.pix(line * 9 + y, pos * 6 + x) = BIT(src1[y], 4 - x);
					bitmap.pix((line + 2) * 9 + y, pos * 6 + x) = BIT(src2[y], 4 - x);
				}
			}
		}
	}

	return 0;
}


//**************************************************************************
//  Keyboard matrix (VIA1 PB0-5 = rows 8-13, VIA2 PB0-7 = rows 0-7, VIA2 PA0-7 = columns)
//  See ../../../../docs/keyboard-matrix.md for the full scancode table.
//**************************************************************************

void homecomputer6502_state::via1_pb_w(uint8_t data)
{
	// rows 8-13 -> VIA1 PB0-5, active low
	m_row_select = (m_row_select & 0x00ff) | (uint16_t(data & 0x3f) << 8);
}

void homecomputer6502_state::via2_pb_w(uint8_t data)
{
	// rows 0-7 -> VIA2 PB0-7, active low
	m_row_select = (m_row_select & 0xff00) | data;
}

uint8_t homecomputer6502_state::via2_pa_r()
{
	// Real hardware inverts the raw VIA2 port A read (see keys.s65 "scan": eor #$ff), so a
	// pressed key ends up as a set bit. We build the same polarity directly here: start with
	// all columns "not pressed" (0) and OR in the columns of every row currently driven low.
	// m_row[row]->read() is already 1-bit-per-pressed-key (IP_ACTIVE_HIGH), so no extra
	// inversion belongs here - that would cancel back out and make every idle (unpressed)
	// column read as "pressed" once re-inverted below.
	uint8_t columns = 0;
	for (int row = 0; row < 14; row++)
		if (!BIT(m_row_select, row))
			columns |= m_row[row]->read();

	uint8_t result = columns ^ 0xff;
	if (result != 0xff) // 0xff is the idle level (nothing pressed in any scanned row); only log real events
		logerror("KEY result=%02x\n", result);
	return result; // re-invert: this handler returns the raw (non-inverted) VIA2 PA level
}


//**************************************************************************
//  Address map
//**************************************************************************

void homecomputer6502_state::mem_map(address_map &map)
{
	map(0x0000, 0x7eff).ram();
	map(0x7f00, 0x7f1f).mirror(0x00e0).m(m_acia, FUNC(mos6551_device::map));  // 4 registers, mirrored
	map(0x7f20, 0x7f3f).m(m_via1, FUNC(via6522_device::map));
	map(0x7f40, 0x7f5f).m(m_via2, FUNC(via6522_device::map));
	map(0x7f60, 0x7f7f).rw(m_sid, FUNC(mos8580_device::read), FUNC(mos8580_device::write));
	map(0x8000, 0xffff).rom().region("maincpu", 0x8000);
}


//**************************************************************************
//  Input ports - keyboard matrix
//  All 87 assigned scancodes (0-111, with gaps for unassigned matrix positions) from
//  docs/keyboard-matrix.md section 5 are entered here.
//**************************************************************************

static INPUT_PORTS_START( homecomputer6502 )
	PORT_START("ROW0") // VIA2 PB0: 1 A ^ Q -- ESC Y TAB
	PORT_BIT(0x01, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("1  !") PORT_CODE(KEYCODE_1)
	PORT_BIT(0x02, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("A") PORT_CODE(KEYCODE_A)
	PORT_BIT(0x04, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("^") PORT_CODE(KEYCODE_TILDE)
	PORT_BIT(0x08, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Q") PORT_CODE(KEYCODE_Q)
	PORT_BIT(0x10, IP_ACTIVE_HIGH, IPT_UNUSED)
	PORT_BIT(0x20, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Esc") PORT_CODE(KEYCODE_ESC)
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Y") PORT_CODE(KEYCODE_Y)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Tab") PORT_CODE(KEYCODE_TAB)

	PORT_START("ROW1") // VIA2 PB1: 3 D F2 E -- F4 C F3
	PORT_BIT(0x01, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("3  \xC2\xA7") PORT_CODE(KEYCODE_3)
	PORT_BIT(0x02, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("D") PORT_CODE(KEYCODE_D)
	PORT_BIT(0x04, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("F2") PORT_CODE(KEYCODE_F2)
	PORT_BIT(0x08, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("E") PORT_CODE(KEYCODE_E)
	PORT_BIT(0x10, IP_ACTIVE_HIGH, IPT_UNUSED)
	PORT_BIT(0x20, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("F4") PORT_CODE(KEYCODE_F4)
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("C") PORT_CODE(KEYCODE_C)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("F3") PORT_CODE(KEYCODE_F3)

	PORT_START("ROW2") // VIA2 PB2: 4 F 5 R B G V T
	PORT_BIT(0x01, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("4  $") PORT_CODE(KEYCODE_4)
	PORT_BIT(0x02, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("F") PORT_CODE(KEYCODE_F)
	PORT_BIT(0x04, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("5  %") PORT_CODE(KEYCODE_5)
	PORT_BIT(0x08, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("R") PORT_CODE(KEYCODE_R)
	PORT_BIT(0x10, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("B") PORT_CODE(KEYCODE_B)
	PORT_BIT(0x20, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("G") PORT_CODE(KEYCODE_G)
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("V") PORT_CODE(KEYCODE_V)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("T") PORT_CODE(KEYCODE_T)

	PORT_START("ROW3") // VIA2 PB3: 7 J 6 U N H M Z
	PORT_BIT(0x01, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("7  /") PORT_CODE(KEYCODE_7)
	PORT_BIT(0x02, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("J") PORT_CODE(KEYCODE_J)
	PORT_BIT(0x04, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("6  &") PORT_CODE(KEYCODE_6)
	PORT_BIT(0x08, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("U") PORT_CODE(KEYCODE_U)
	PORT_BIT(0x10, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("N") PORT_CODE(KEYCODE_N)
	PORT_BIT(0x20, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("H") PORT_CODE(KEYCODE_H)
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("M") PORT_CODE(KEYCODE_M)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Z") PORT_CODE(KEYCODE_Z)

	PORT_START("ROW4") // VIA2 PB4: 8 K ' I -- F6 , +
	PORT_BIT(0x01, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("8  (") PORT_CODE(KEYCODE_8)
	PORT_BIT(0x02, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("K") PORT_CODE(KEYCODE_K)
	PORT_BIT(0x04, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("\xC2\xB4  `") PORT_CODE(KEYCODE_EQUALS)
	PORT_BIT(0x08, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("I") PORT_CODE(KEYCODE_I)
	PORT_BIT(0x10, IP_ACTIVE_HIGH, IPT_UNUSED)
	PORT_BIT(0x20, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("F6") PORT_CODE(KEYCODE_F6)
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME(",  ;") PORT_CODE(KEYCODE_COMMA)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("+  *") PORT_CODE(KEYCODE_CLOSEBRACE)

	PORT_START("ROW5") // VIA2 PB5: 0 Oe ss - Ae # Ue
	PORT_BIT(0x01, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("0  =") PORT_CODE(KEYCODE_0)
	PORT_BIT(0x02, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("\xC3\x96") PORT_CODE(KEYCODE_COLON)
	PORT_BIT(0x04, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("\xC3\x9F  ?") PORT_CODE(KEYCODE_MINUS)
	PORT_BIT(0x08, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("P") PORT_CODE(KEYCODE_P)
	PORT_BIT(0x10, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("-  _") PORT_CODE(KEYCODE_SLASH)
	PORT_BIT(0x20, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("\xC3\x84") PORT_CODE(KEYCODE_QUOTE)
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("#  '") PORT_CODE(KEYCODE_BACKSLASH)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("\xC3\x9C") PORT_CODE(KEYCODE_OPENBRACE)

	PORT_START("ROW6") // VIA2 PB6: Druck -- -- Rollen AltGr Alt -- --
	PORT_BIT(0x01, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Druck S-Abf") PORT_CODE(KEYCODE_PRTSCR)
	PORT_BIT(0x06, IP_ACTIVE_HIGH, IPT_UNUSED)
	PORT_BIT(0x08, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Rollen") PORT_CODE(KEYCODE_SCRLOCK)
	PORT_BIT(0x10, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("AltGr") PORT_CODE(KEYCODE_RALT)
	PORT_BIT(0x20, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Alt") PORT_CODE(KEYCODE_LALT)
	PORT_BIT(0xc0, IP_ACTIVE_HIGH, IPT_UNUSED)

	PORT_START("ROW7") // VIA2 PB7: Ende -- Pos1 -- Cursor-Links Cursor-Hoch Pause/Untbr Menue
	PORT_BIT(0x01, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Ende") PORT_CODE(KEYCODE_END)
	PORT_BIT(0x02, IP_ACTIVE_HIGH, IPT_UNUSED)
	PORT_BIT(0x04, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Pos1") PORT_CODE(KEYCODE_HOME)
	PORT_BIT(0x08, IP_ACTIVE_HIGH, IPT_UNUSED)
	PORT_BIT(0x10, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Cursor Links") PORT_CODE(KEYCODE_LEFT)
	PORT_BIT(0x20, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Cursor Hoch") PORT_CODE(KEYCODE_UP)
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Pause Untbr") PORT_CODE(KEYCODE_PAUSE)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Menu") PORT_CODE(KEYCODE_MENU)

	PORT_START("ROW8") // VIA1 PB0: F12 S Einfg W Cursor-Rechts < X CapsLock
	PORT_BIT(0x01, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("F12") PORT_CODE(KEYCODE_F12)
	PORT_BIT(0x02, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("S") PORT_CODE(KEYCODE_S)
	PORT_BIT(0x04, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Einfg") PORT_CODE(KEYCODE_INSERT)
	PORT_BIT(0x08, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("W") PORT_CODE(KEYCODE_W)
	PORT_BIT(0x10, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Cursor Rechts") PORT_CODE(KEYCODE_RIGHT)
	PORT_BIT(0x20, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("<  >") PORT_CODE(KEYCODE_BACKSLASH2)
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("X") PORT_CODE(KEYCODE_X)
	// A plain momentary key, like the real one. The firmware latches Caps Lock itself.
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Caps Lock") PORT_CODE(KEYCODE_CAPSLOCK)

	PORT_START("ROW9") // VIA1 PB1: F10 -- F9 -- Leertaste F5 Enter Backspace
	PORT_BIT(0x01, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("F10") PORT_CODE(KEYCODE_F10)
	PORT_BIT(0x02, IP_ACTIVE_HIGH, IPT_UNUSED)
	PORT_BIT(0x04, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("F9") PORT_CODE(KEYCODE_F9)
	PORT_BIT(0x08, IP_ACTIVE_HIGH, IPT_UNUSED)
	PORT_BIT(0x10, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Leertaste") PORT_CODE(KEYCODE_SPACE)
	PORT_BIT(0x20, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("F5") PORT_CODE(KEYCODE_F5)
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Enter") PORT_CODE(KEYCODE_ENTER)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Backspace") PORT_CODE(KEYCODE_BACKSPACE)

	PORT_START("ROW10") // VIA1 PB2: Bild-Runter L Bild-Hoch O -- -- . F7
	PORT_BIT(0x01, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Bild Runter") PORT_CODE(KEYCODE_PGDN)
	PORT_BIT(0x02, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("L") PORT_CODE(KEYCODE_L)
	PORT_BIT(0x04, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Bild Hoch") PORT_CODE(KEYCODE_PGUP)
	PORT_BIT(0x08, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("O") PORT_CODE(KEYCODE_O)
	PORT_BIT(0x30, IP_ACTIVE_HIGH, IPT_UNUSED)
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME(".  :") PORT_CODE(KEYCODE_STOP)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("F7") PORT_CODE(KEYCODE_F7)

	PORT_START("ROW11") // VIA1 PB3: only Shift left/right assigned
	PORT_BIT(0x3f, IP_ACTIVE_HIGH, IPT_UNUSED)
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Shift rechts") PORT_CODE(KEYCODE_RSHIFT)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Shift links") PORT_CODE(KEYCODE_LSHIFT)

	PORT_START("ROW12") // VIA1 PB4: F11 2 Entf 9 Cursor-Runter F8 Num F1
	PORT_BIT(0x01, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("F11") PORT_CODE(KEYCODE_F11)
	PORT_BIT(0x02, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("2  \"") PORT_CODE(KEYCODE_2)
	PORT_BIT(0x04, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Entf") PORT_CODE(KEYCODE_DEL)
	PORT_BIT(0x08, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("9  )") PORT_CODE(KEYCODE_9)
	PORT_BIT(0x10, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Cursor Runter") PORT_CODE(KEYCODE_DOWN)
	PORT_BIT(0x20, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("F8") PORT_CODE(KEYCODE_F8)
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Num") PORT_CODE(KEYCODE_NUMLOCK)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("F1") PORT_CODE(KEYCODE_F1)

	PORT_START("ROW13") // VIA1 PB5: only Ctrl left/right assigned
	PORT_BIT(0x03, IP_ACTIVE_HIGH, IPT_UNUSED)
	PORT_BIT(0x04, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Strg links") PORT_CODE(KEYCODE_LCONTROL)
	PORT_BIT(0x38, IP_ACTIVE_HIGH, IPT_UNUSED)
	PORT_BIT(0x40, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Strg rechts") PORT_CODE(KEYCODE_RCONTROL)
	PORT_BIT(0x80, IP_ACTIVE_HIGH, IPT_UNUSED)

	// Fn + Windows -> hard reset (see fn_win_reset() above). Not part of the 14x8 scan matrix.
	// "Fn" has no dedicated PC keycode, so the right Windows key stands in for it. The left
	// Windows key is the real Windows key. Either one resets: a PC has a single Windows key,
	// and a click on either on-screen key already does the same.
	PORT_START("RESET")
	PORT_BIT(0x01, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Fn (Annaeherung, siehe Kommentar)") PORT_CODE(KEYCODE_RWIN) PORT_CHANGED_MEMBER(DEVICE_SELF, FUNC(homecomputer6502_state::fn_win_reset), 0)
	PORT_BIT(0x02, IP_ACTIVE_HIGH, IPT_KEYBOARD) PORT_NAME("Windows") PORT_CODE(KEYCODE_LWIN) PORT_CHANGED_MEMBER(DEVICE_SELF, FUNC(homecomputer6502_state::fn_win_reset), 0)
INPUT_PORTS_END


//**************************************************************************
//  Machine config
//**************************************************************************

// Slim slot list. default_rs232_devices also lists terminals and extra CPUs this
// subtarget does not build (see install.sh patch of rs232.cpp and README).
static void homecomputer6502_rs232_devices(device_slot_interface &device)
{
	device.option_add("null_modem", NULL_MODEM);
	device.option_add("pty",        PSEUDO_TERMINAL);
}

// The pty card samples TXD/RXD at this rate. It does not follow the 6551
// control register, and Linux ignores picocom's baud on a PTY. 19200 matches
// the firmware (ACIA control $1F).
static DEVICE_INPUT_DEFAULTS_START(pty_19200)
	DEVICE_INPUT_DEFAULTS("RS232_TXBAUD", 0xff, RS232_BAUD_19200)
	DEVICE_INPUT_DEFAULTS("RS232_RXBAUD", 0xff, RS232_BAUD_19200)
	DEVICE_INPUT_DEFAULTS("RS232_DATABITS", 0xff, RS232_DATABITS_8)
	DEVICE_INPUT_DEFAULTS("RS232_PARITY", 0xff, RS232_PARITY_NONE)
	DEVICE_INPUT_DEFAULTS("RS232_STOPBITS", 0xff, RS232_STOPBITS_1)
DEVICE_INPUT_DEFAULTS_END


void homecomputer6502_state::homecomputer6502(machine_config &config)
{
	// Case + keyboard artwork with the emulated screen composited into the LCD bezel opening
	// (src/mame/layout/homecomputer6502.lay), so the video output shows the whole device
	// instead of just the bare 240x36 pixel screen in an empty window.
	config.set_default_layout(layout_homecomputer6502);

	M6502(config, m_maincpu, 1_MHz_XTAL);
	m_maincpu->set_addrmap(AS_PROGRAM, &homecomputer6502_state::mem_map);

	input_merger_device &irq(INPUT_MERGER_ANY_HIGH(config, "irq")); // wired-OR /IRQ, see system-spec.md 6.1
	irq.output_handler().set_inputline(m_maincpu, M6502_IRQ_LINE);

	MOS6522(config, m_via1, 1_MHz_XTAL);
	m_via1->writepa_handler().set(FUNC(homecomputer6502_state::via1_pa_w));
	m_via1->writepb_handler().set(FUNC(homecomputer6502_state::via1_pb_w));
	m_via1->irq_handler().set("irq", FUNC(input_merger_device::in_w<0>));

	MOS6522(config, m_via2, 1_MHz_XTAL);
	m_via2->readpa_handler().set(FUNC(homecomputer6502_state::via2_pa_r));
	m_via2->writepb_handler().set(FUNC(homecomputer6502_state::via2_pb_w));
	m_via2->irq_handler().set("irq", FUNC(input_merger_device::in_w<1>));

	MOS6551(config, m_acia, 1.8432_MHz_XTAL);
	m_acia->set_xtal(1.8432_MHz_XTAL); // the "clock" ctor arg alone does NOT drive the internal
	                                    // baud generator (m_xtal stays 0 without this call) -
	                                    // without it TDRE never re-sets after the first byte and
	                                    // acia_putc()'s wait-for-TX_EMPTY loop hangs forever
	m_acia->irq_handler().set("irq", FUNC(input_merger_device::in_w<2>));
	// JP4 is TXD/RXD/GND only (system-spec.md 5.1). Do not wire CTS/DSR/DCD from the
	// slot: those stay tied in machine_start(). RTS/DTR are not brought out either.
	m_acia->txd_handler().set("rs232", FUNC(rs232_port_device::write_txd));
	rs232_port_device &rs232(RS232_PORT(config, "rs232", homecomputer6502_rs232_devices, "pty"));
	rs232.set_option_device_input_defaults("pty", DEVICE_INPUT_DEFAULTS_NAME(pty_19200));
	rs232.rxd_handler().set(m_acia, FUNC(mos6551_device::write_rxd));

	SPEAKER(config, "mono").front_center();
	MOS8580(config, m_sid, 1_MHz_XTAL);
	m_sid->add_route(ALL_OUTPUTS, "mono", 1.0);

	// 4x40 character LCD built from two HD44780 controllers with shared data/RS lines and
	// separate enable lines (E1 = lines 0/1, E2 = lines 2/3), see system-spec.md 5.5
	HD44780U(config, m_lcd1, 270'000); // clock not measured, typical value used elsewhere in MAME
	m_lcd1->set_lcd_size(2, 40);

	HD44780U(config, m_lcd2, 270'000);
	m_lcd2->set_lcd_size(2, 40);

	// One composite 4x40 screen: lcd1 (lines 0/1) stacked above lcd2 (lines 2/3), see
	// screen_update_lcd() above. 6 px/char wide (5 dots + 1 gap), 9 px/row tall (8 dots + 1 gap).
	screen_device &screen(SCREEN(config, "screen").set_lcd());
	screen.set_refresh_hz(60);
	screen.set_vblank_time(ATTOSECONDS_IN_USEC(2500));
	screen.set_screen_update(FUNC(homecomputer6502_state::screen_update_lcd));
	screen.set_size(6 * 40, 9 * 4);
	screen.set_visarea_full();
	screen.set_palette("palette");

	PALETTE(config, "palette", FUNC(homecomputer6502_state::palette_init), 2);
}


//**************************************************************************
//  ROM definitions
//**************************************************************************

ROM_START( homecomputer6502 )
	// Firmware is copied in from rompath in machine_start(). Erased here so a
	// missing file cannot execute leftover bytes.
	ROM_REGION(0x10000, "maincpu", ROMREGION_ERASEFF)
ROM_END

} // anonymous namespace


//**************************************************************************
//  Driver
//**************************************************************************

//    YEAR  NAME              PARENT  COMPAT  MACHINE           INPUT             CLASS                     INIT        COMPANY              FULLNAME            FLAGS
COMP( 2026, homecomputer6502, 0,      0,      homecomputer6502, homecomputer6502, homecomputer6502_state,   empty_init, "Dirk Grappendorf",  "HomeComputer 6502", 0 )
