#!/bin/bash
# Copies this project's HomeComputer 6502 driver into a MAME source checkout
# and builds a minimal "homecomputer6502" subtarget.
#
# Usage:
#   git clone --depth 1 https://github.com/mamedev/mame.git /path/to/mame
#   ./install.sh /path/to/mame
#   cd /path/to/mame
#   make SUBTARGET=homecomputer6502 -j$(nproc)
#   ./mamehomecomputer6502 -rompath <dir with firmware.bin and hd44780_a00.bin> homecomputer6502
#
# See README.md in this directory for the verified build/run result, known
# simplifications and the hd44780_a00.bin character-set ROM situation.

set -euo pipefail

MAME_DIR="${1:?Usage: $0 <path to a mame source checkout>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$MAME_DIR/src/mame/homecomputer6502" "$MAME_DIR/src/mame/layout"
cp "$HERE/src/homecomputer6502/homecomputer6502.cpp" "$MAME_DIR/src/mame/homecomputer6502/"
cp "$HERE/src/homecomputer6502.lst" "$MAME_DIR/src/mame/"
cp "$HERE/src/layout/homecomputer6502.lay" "$MAME_DIR/src/mame/layout/"
cp "$HERE/scripts/target/mame/homecomputer6502.lua" "$MAME_DIR/scripts/target/mame/"

# MAME's HD44780U font is a BAD_DUMP with a different hash than the transcription
# in roms/homecomputer6502/hd44780u_a00.bin. Leaving that mismatch (or the
# BAD_DUMP flag) makes MAME stop on the red ROM warning at every start.
FONT_CPP="$MAME_DIR/src/devices/video/hd44780.cpp"
if [[ -f "$FONT_CPP" ]] && grep -q 'CRC(8494cb6b)' "$FONT_CPP"; then
	python3 - "$FONT_CPP" << 'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = '\tROMX_LOAD( "hd44780u_a00.bin",    0x0000, 0x1000,  BAD_DUMP CRC(8494cb6b) SHA1(2d4f9cf5ff81f20d2f4e4640f5b8a697a3781eef), ROM_BIOS(0)) // from page 17 of the 1999 HD44780U datasheet\n'
new = (
    "\t// Hash is the homecomputer6502 datasheet transcription (mame-extensions/README.md\n"
    "\t// section 5), not MAME's BAD_DUMP. A mismatch paints the red ROM warning at startup.\n"
    '\tROMX_LOAD( "hd44780u_a00.bin",    0x0000, 0x1000,  CRC(f9cafd2a) SHA1(4497380091e9d249ae907d64084094a68602e8eb), ROM_BIOS(0))\n'
)
if old not in text:
    sys.exit("hd44780.cpp: expected upstream hd44780u_a00.bin line, not found")
path.write_text(text.replace(old, new, 1))
PY
	echo "Pointed hd44780u_a00.bin at the local charset transcription."
fi

# default_rs232_devices in rs232.cpp references every RS232 card (terminals, extra
# CPUs). Compiling that file for the slim subtarget then fails to link even if the
# driver never calls the function. Keep the port implementation; shrink the list.
RS232_CPP="$MAME_DIR/src/devices/bus/rs232/rs232.cpp"
if [[ -f "$RS232_CPP" ]] && grep -q 'option_add("mockingboard"' "$RS232_CPP"; then
	python3 - "$RS232_CPP" << 'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
old_inc = '''#include "adsp2181ekl.h"
#include "auto3a.h"
#include "ie15.h"
#include "heath_h19.h"
#include "hlemouse.h"
#include "keyboard.h"
#include "loopback.h"
#include "mboardd.h"
#include "nss_tvinterface.h"
#include "null_modem.h"
#include "patchbox.h"
#include "printer.h"
#include "pty.h"
#include "rs232_sync_io.h"
#include "s97801.h"
#include "scorpion.h"
#include "sun_kbd.h"
#include "swtpc8212.h"
#include "terminal.h"
#include "votraxtnt.h"
'''
new_inc = '''#include "null_modem.h"
#include "pty.h"
'''
old_fn = '''void default_rs232_devices(device_slot_interface &device)
{
	device.option_add("adsp2181ekl",   ADSP2181EKL);
	device.option_add("auto3a",        SERIAL_TERMINAL_AUTO3A);
	device.option_add("dec_loopback",  DEC_RS232_LOOPBACK);
	device.option_add("h19",           SERIAL_TERMINAL_H19);
	device.option_add("ie15",          SERIAL_TERMINAL_IE15);
	device.option_add("keyboard",      SERIAL_KEYBOARD);
	device.option_add("loopback",      RS232_LOOPBACK);
	device.option_add("mockingboard",  SERIAL_MOCKINGBOARD_D);
	device.option_add("msystems_mouse",MSYSTEMS_HLE_SERIAL_MOUSE);
	device.option_add("nss_tvi",       NSS_TVINTERFACE);
	device.option_add("null_modem",    NULL_MODEM);
	device.option_add("patch",         RS232_PATCH_BOX);
	device.option_add("printer",       SERIAL_PRINTER);
	device.option_add("pty",           PSEUDO_TERMINAL);
	device.option_add("rs232_sync_io", RS232_SYNC_IO);
	device.option_add("rs_printer",    RADIO_SHACK_SERIAL_PRINTER);
	device.option_add("s97801",        SERIAL_TERMINAL_S97801);
	device.option_add("scorpion",      SCORPION_IC);
	device.option_add("sunkbd",        SUN_KBD_ADAPTOR);
	device.option_add("swtpc8212",     SERIAL_TERMINAL_SWTPC8212);
	device.option_add("terminal",      SERIAL_TERMINAL);
	device.option_add("votraxtnt",     SERIAL_VOTRAXTNT);
}
'''
new_fn = '''void default_rs232_devices(device_slot_interface &device)
{
	// Slim list for the homecomputer6502 subtarget (mame-extensions/README.md).
	device.option_add("null_modem", NULL_MODEM);
	device.option_add("pty",        PSEUDO_TERMINAL);
}
'''
if old_inc not in text or old_fn not in text:
    sys.exit("rs232.cpp: expected upstream default_rs232_devices block, not found")
path.write_text(text.replace(old_inc, new_inc, 1).replace(old_fn, new_fn, 1))
PY
	echo "Slimmed default_rs232_devices to pty + null_modem."
fi

echo "Installed into $MAME_DIR"
echo "Now run: cd $MAME_DIR && make SUBTARGET=homecomputer6502 -j\$(nproc)"
