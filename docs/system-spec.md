# HomeComputer 6502—System Specification

Basis for the new firmware. All information is derived from the Eagle schematic (`eagle/homecomputer-6502.sch`, revision *Final*), the existing firmware (`firmware/`), the `terminal/` script, and the project page at <http://www.grappendorf.net/projects/6502-home-computer/>.

Sources: repository <https://github.com/grappendorf/homecomputer-6502> (local: `../homecomputer-6502`), data sheets in `../homecomputer-6502-datasheets`.

Notation: Unmarked statements are supported by the schematic or code. **[Assumption]** means plausible but not conclusively supported. **[Open]** must be clarified before firmware design (see section 11).

---

## 1. Overview

| Property | Value |
|---|---|
| CPU | **MOS 6502AD** (NMOS, 8-bit, “A” selection rated for 2 MHz); firmware is assembled with `--cpu 6502` |
| Clock | **1 MHz** (TTL crystal-oscillator module in a 14-pin can), 1 cycle = 1 µs |
| RAM | 32 KB static RAM (UM61256, 32K×8) |
| ROM | 32 KB EEPROM (Atmel AT28C256) |
| Serial interface | **R6551** ACIA (Rockwell, NMOS), 19200 baud 8N1 (1.8432 MHz crystal), TX/RX/GND on a header (external FT232 USB-to-serial adapter) |
| I/O | 2× 6522 VIA (chip markings reported by the user as “8520A” and “8520PD”—**[Open]**: exact type/vendor remains unclear; see section 11) |
| Sound | **SID 8580** (9 V version; the schematic symbol is still named 6581) |
| Display | 4×40-character LCD (EA W404B-NLW, 2× HD44780-compatible controllers), 4-bit connection through VIA1 |
| Input | 14×8 keyboard matrix (PC-like German keyboard, 22-pin connection) |
| Interrupts | IRQ: VIA1 + VIA2 + ACIA (wired OR); NMI: push button/jumper (JP3) |
| Reset | NE555 monostable (~0.5 s) + push button (JP2) |
| Power | 5 V (barrel jack J1 or JP1), **+9 V** only for the SID (JP7 / T1 amplifier stage; the schematic net is named “+12V” but has the value “+9V”) |
| Video | None |
| Mass storage | None (programs are loaded from and saved to a PC over the serial interface) |

The 160 × 100 mm board is fully populated according to the author: there is no expansion port and no unused VIA pins except VIA1 PB6/PB7 (see 5.2).

---

## 2. Memory Map

Address decoding uses 74LS04 / 74LS30 / 74LS00 / 74LS137; see section 3.

```
$0000 ┌──────────────────────────────┐
      │ Zero Page             256 B  │  RAM
$0100 ├──────────────────────────────┤
      │ Hardware stack        256 B  │  RAM   (S = $FF after reset)
$0200 ├──────────────────────────────┤
      │ Usable RAM          32000 B  │  RAM   ($0200–$7EFF)
      │  (firmware: DATA, BSS,       │
      │   heap, C software stack)    │
$7F00 ├──────────────────────────────┤
      │ I/O page              256 B  │  overlays the top 256 B of RAM
$8000 ├──────────────────────────────┤
      │ ROM (EEPROM)        32768 B  │  $8000–$FFFF, read-only in-system
$FFFA │  Vectors: NMI, RESET, IRQ    │
$FFFF └──────────────────────────────┘
```

| Range | Size | Device | Note |
|---|---|---|---|
| `$0000–$00FF` | 256 B | RAM | Zero page |
| `$0100–$01FF` | 256 B | RAM | 6502 hardware stack. Under BASIC only through `$01FA`; `$01FB–$01FF` belong to the line buffer (15.4) |
| `$0200–$7EFF` | 32,000 B | RAM | Available to firmware/programs |
| `$7F00–$7FFF` | 256 B | I/O | Peripheral registers; underlying RAM is inaccessible because `/CS_RAM` is inhibited on the bus |
| `$8000–$FFFF` | 32,768 B | ROM | Code, constants, DATA initializers, vectors |

Total RAM is 32,768 B, of which 32,512 B are usable after the I/O overlay.

### 2.1 I/O Page `$7F00–$7FFF`

A 74LS137 (3-to-8) divides the I/O page into 32-byte blocks using A7..A5:

| Block | Addresses | `/CS` | Device | Register select | Mirroring |
|---|---|---|---|---|---|
| Y0 | `$7F00–$7F1F` | `/CS_ACIA` | 6551 ACIA | A1..A0 (4 registers) | Registers repeat every 4 bytes (8×) |
| Y1 | `$7F20–$7F3F` | `/CS_VIA1` | 6522 VIA1 | A3..A0 (16 registers) | Mirror at `$7F30–$7F3F` (2×) |
| Y2 | `$7F40–$7F5F` | `/CS_VIA2` | 6522 VIA2 | A3..A0 (16 registers) | Mirror at `$7F50–$7F5F` (2×) |
| Y3 | `$7F60–$7F7F` | `/CS_SID` | SID 8580 | A4..A0 (32 addresses, 29 registers) | None |
| Y4 | `$7F80–$7F9F` | – | Free (output not connected) | | |
| Y5 | `$7FA0–$7FBF` | – | Free | | |
| Y6 | `$7FC0–$7FDF` | – | Free | | |
| Y7 | `$7FE0–$7FFF` | – | Free | | |

Firmware should use only the base addresses (`$7F00`, `$7F20`, `$7F40`, `$7F60`) and not their mirrors.

### 2.2 Vectors

| Address | Vector | Old firmware |
|---|---|---|
| `$FFFA/B` | NMI | `nmi_handler` (sets `_interrupted = $FF`, Break key/signal) |
| `$FFFC/D` | RESET | `_init` |
| `$FFFE/F` | IRQ/BRK | `irq_handler` (VIA1 Timer 1) |

---

## 3. Address Decoding in Detail

Derived from the netlist (IC2 = 74LS00, IC3 = 74LS04, IC4 = 74LS30, IC5 = 74LS137).

```
/CS_ROM = NOT A15                                   (IC3B)          -> ROM $8000–$FFFF
/CS_IO  = NAND(A14..A8, /CS_ROM)                    (IC4, 8-input)  -> active when A15=0 and A14..A8=1 => $7F00–$7FFF
RAM_SEL = NOT NAND(/CS_ROM, /CS_IO)                 (IC2A, IC3E)    -> A15=0 and not I/O
/CS_RAM = NAND(RAM_SEL, PHI2)                       (IC2B)          -> RAM only during PHI2 high
74LS137: G1 = VCC, /G2 = /CS_IO, GL = GND (transparent), C/B/A = A7/A6/A5
         Y0 /CS_ACIA, Y1 /CS_VIA1, Y2 /CS_VIA2, Y3 /CS_SID, Y4–Y7 free
```

Additional wiring:

- **ROM AT28C256:** `/CE` and `/OE` both connect to `/CS_ROM` and are not gated by PHI2; `/WE` is tied to VCC, so the ROM is **not writable in-system**. It must be programmed externally with the **Minipro TL866CS** (`scripts/flash.sh` builds `build/firmware.bin` and writes it with `minipro -p AT28C256 -u -w`).
- **RAM UM61256:** `/CE` and `/OE` connect to `/CS_RAM`; `/WE` connects to `R/W`.
- **VIA1/VIA2:** `CS1` = VCC; `/CS2` = the respective decoder output.
- **ACIA:** `CS0` = VCC; `/CS1` = `/CS_ACIA`; clock = PHI2.
- **SID:** `/CS` = `/CS_SID`; clock = PHI2 (1 MHz).
- All peripherals receive active-low `/RESET` from the reset circuit.
- Each IC has a 100 nF decoupling capacitor.

---

## 4. 6502 CPU

| Pin | Connection |
|---|---|
| PHI0 (clock in) | Oscillator (`CLK`, 1 MHz) |
| PHI2 (clock out) | `PHI2` to RAM decoding, VIA1, VIA2, ACIA, SID |
| `/RESET` | Reset circuit (section 7) |
| `/IRQ` | Wired-OR line `!IRQ`, 3.3 kΩ pull-up (R5) |
| `/NMI` | JP3 (2-pin header, pin 2 = GND), 3.3 kΩ pull-up (R6); shorting to GND triggers NMI |
| RDY | 3.3 kΩ pull-up (R4), otherwise unused (no wait-state logic) |
| SO | 3.3 kΩ pull-up (R7), unused |
| R/W | RAM `/WE`, VIA, ACIA, SID |
| A0..A15, D0..D7 | Address/data buses connected directly to all devices |

Firmware consequences:

- Assume the **NMOS instruction set**: no `PHX/PHY/PLX/PLY`, `BRA`, `STZ`, `INC A`, or unindexed `(zp)`. The old firmware emulates `PHX/PHY`, etc. with macros (`macros.inc65`). The installed NMOS **6502AD** does not provide the 65C02 instruction set.
- Decimal mode is disabled at startup with `CLD`.
- D-flag handling at reset/interrupt is undefined on NMOS 6502; IRQ/NMI handlers should execute `CLD` if decimal mode is used anywhere.
- At 1 MHz, cycle budgets are tight: 10 ms = 10,000 cycles.

---

## 5. Peripherals

### 5.1 ACIA 6551 (`$7F00`)

Serial interface to the PC/terminal.

| Address | Read | Write |
|---|---|---|
| `$7F00` | Receive data | Transmit data |
| `$7F01` | Status | Programmed reset |
| `$7F02` | Command register | Command register |
| `$7F03` | Control register | Control register |

- Q1 is a 1.8432 MHz crystal on XTAL1/XTAL2 (27 pF on XTAL2), enabling the internal baud-rate generator; control flag `ACIA_CLOCK_INT`.
- Previous configuration: **19200 baud, 8 data bits, 1 stop bit, no parity**, echo off, receive IRQ **off**, transmit IRQ off, DTR low, RTS low. Control register `$1F` (bits 3–0 = `$F`).
- `/CTS`, `/DSR`, and `/DCD` are tied to GND. RTS/DTR are not exposed.
- External connector JP4 “SERIAL”: pin 1 GND, pin 2 TXD, pin 3 RXD. It uses an FT232 adapter and no hardware handshake.
- `/IRQ` connects to the shared IRQ line, so receive interrupts are possible although the old firmware did not use them.
- The old firmware polls `ACIA_STATUS_TX_EMPTY` (bit 4) before every transmitted character and `RX_FULL` (bit 3) when receiving. This works with the installed **R6551** (NMOS); the W65C51 whose bit 4 is unreliable is not installed. Polling TX Empty is therefore valid, including for an interrupt-driven transmit buffer (TX IRQ controlled through the command register).

Bit definitions from `io.inc65`:

| Register | Bits |
|---|---|
| Status | 7 IRQ, 6 DSR, 5 DCD, 4 TX Empty, 3 RX Full, 2 Overrun, 1 Framing Error, 0 Parity Error |
| Command | 7–6 parity mode, 5 parity enable, 4 echo, 3–2 TX control/RTS, 1 RX IRQ **disabled** (1 = disabled), 0 DTR |
| Control | 7 stop bits, 6–5 word length, 4 clock source (1 = internal), 3–0 baud rate (`$E` = 9600, `$F` = 19200) |

### 5.2 VIA1 6522 (`$7F20`)

| Offset | Register | | Offset | Register |
|---|---|---|---|---|
| +0 | ORB/IRB | | +8 | T2C-L |
| +1 | ORA/IRA | | +9 | T2C-H |
| +2 | DDRB | | +10 | SR |
| +3 | DDRA | | +11 | ACR |
| +4 | T1C-L | | +12 | PCR |
| +5 | T1C-H | | +13 | IFR |
| +6 | T1L-L | | +14 | IER |
| +7 | T1L-H | | +15 | ORA/IRA (no handshake) |

| Pin | Function |
|---|---|
| PA0–PA3 | LCD D4–D7 |
| PA4 | LCD RS |
| PA5 | LCD E1 (controller 1, rows 0–1) |
| PA6 | LCD E2 (controller 2, rows 2–3) |
| PA7 | LED1 (active high, 270 Ω, `LED_OUT`/`LED_DDR` in `io.inc65`) |
| PB0–PB5 | Keyboard rows 8–13 (outputs) |
| PB6, PB7 | **Free** (not routed to a connector) |
| CA1/CA2/CB1/CB2 | Not connected |
| `/IRQ` | Shared IRQ line |

Timer 1 provides the **system tick** (section 6.2).

### 5.3 VIA2 6522 (`$7F40`)

| Pin | Function |
|---|---|
| PA0–PA7 | Keyboard columns 0–7 (inputs, bit 0 = column 0), JP6 pins 22..15 |
| PB0–PB7 | Keyboard rows 0–7 (outputs), JP6 pins 14..7 |
| CA1/CA2/CB1/CB2 | Not connected |
| Timer 1, Timer 2, shift register | **Entirely free** |
| `/IRQ` | Shared IRQ line |

### 5.4 SID 8580 (`$7F60`)

- Clock PHI2 = 1 MHz. Frequency register: `Fn = f_Hz × 16.777216`. Example: C4 (261.6 Hz) → `$1114`, as in the `sid.s65` table.
- Supplies: 5 V (JP7 pin 1) and **+9 V** (JP7 pin 3, GND pin 2; schematic net named “+12V” but valued “+9V”, appropriate for the 8580). Audio output → 1k → ferrite → 2N2222 transistor T1 as emitter follower → 10 µF → jack/header JP8 (`SID_OUT`).
- Two 22 nF filter capacitors (Cap1, Cap2), the correct value for the 8580.
- Firmware-relevant differences from 6581: a more linear and predictable filter; 6581 cutoff tables sound different; the ADSR delay bug is fixed; combined waveforms differ; digital sample playback through the volume register is practically inaudible.
- POTX/POTY are not connected; **there are no paddles**, and they are ignored.

| Address | Register |
|---|---|
| `$7F60/61` | Voice 1 frequency L/H |
| `$7F62/63` | Voice 1 pulse width L/H |
| `$7F64` | Voice 1 control |
| `$7F65` | Voice 1 attack/decay |
| `$7F66` | Voice 1 sustain/release |
| `$7F67–$7F6D` | Voice 2 (same layout) |
| `$7F6E–$7F74` | Voice 3 (same layout) |
| `$7F75/76` | Filter cutoff L/H |
| `$7F77` | Resonance / filter routing |
| `$7F78` | Mode / volume |
| `$7F79/7A` | POTX / POTY (read-only) |
| `$7F7B` | OSC3 (read-only) |
| `$7F7C` | ENV3 (read-only) |

SID registers are write-only except `$7F79–$7F7C`. Firmware needs shadow copies to modify individual bits.

### 5.5 4×40 LCD (via VIA1 Port A)

- EA W404B-NLW (see `homecomputer-6502-datasheets/EA Blueline Dot Matrix Displays.pdf`), 4 rows × 40 characters, with **two HD44780 controllers**, each driving two rows. They share data lines but have separate enable lines (E1 rows 0/1, E2 rows 2/3).
- **4-bit mode:** PA0–PA3 = D4–D7, RS = PA4, E1 = PA5, E2 = PA6.
- The LCD **R/W pin is tied to GND** (JP5 pins 5/6/7/8/10/13/18 are GND; pin 14 is VCC, confirmed by the author). The display is write-only and its busy flag cannot be read. Firmware uses fixed delays (`write_4bits` waits only about 20 × 5 cycles, while commands such as *Clear Display* require much longer, about 1.6 ms).
- Contrast: 10k potentiometer R8 on JP5 pin 12; backlight through 150 Ω R9 on JP5 pin 17. The author confirmed the pinout.
- DDRAM per controller: rows 0/2 start at `$00`, rows 1/3 at `$40`, 40 characters each. The old firmware keeps `display_data[4×40]` in RAM for scrolling and `lcd_getc`.
- Initialization: enter 4-bit mode with 3× `$3` + `$2`; Function Set for 2 rows/5×7; Display On; incrementing Entry Mode; Clear; Home. Both enable lines are asserted together for the first commands.

### 5.6 Keyboard (JP6, 22 Pins)

German-layout laptop keyboard with 89 keys, wired as a 14-row active-low output × 8-column input matrix: rows 0–7 = VIA2 PB0–PB7, rows 8–13 = VIA1 PB0–PB5, columns 0–7 = VIA2 PA0–PA7. Scan code = `row × 8 + column`. Firmware drives one row low, reads VIA2 Port A, and inverts it (`eor #$ff`), making a pressed key a set bit.

- **Pull-ups:** no external ones are required. 6522 Port A has permanently active internal pull-ups (MOS data sheet page 3, Figure 2), confirmed for the installed VIAs by the author.
- **Diodes:** none are visible in photographs of the keyboard rear, so ghosting protection is not expected.
- **Not scanned:** Fn and Windows key (87 of 89 keys are in the matrix). Pressing **Fn + Windows key together causes a hard reset**, confirmed by the author, presumably through separate wiring to the reset circuit (JP2/NE555, section 7) rather than NMI (JP3). Exact wiring is undocumented.

The complete matrix, physical layout, scan-code/character-code table, modifier detection, and gaps in the old firmware are documented in [keyboard-matrix.md](keyboard-matrix.md).

Known weaknesses of the old keyboard routine: only one simultaneous key is reported, debounce uses a blocking 20 ms busy loop, there is no auto-repeat or ring buffer, no `Caps Lock`/`Num Lock` state, and no AltGr layer.

### 5.7 LED

One active-high LED on VIA1 PA7 through 270 Ω. It lights for one second after reset. BASIC can then control it with `LED ON` and `LED OFF` (see [basic.md](basic.md)). The first such command ends the reset timer so the light does not turn off after one second. PA7 shares VIA1 Port A with the LCD; writes use only the `lcd_porta` shadow variable.

---

## 6. Shared Resources

### 6.1 Interrupts

- **IRQ** is a wired-OR line from VIA1, VIA2, and ACIA (all open drain), with 3.3 kΩ pull-up R5. A handler must inspect **all three sources** (VIA `IFR`, ACIA status bit 7). The old firmware checks only VIA1 Timer 1 and works solely because that is the only enabled source.
- **NMI** comes from JP3, an external button/jumper to GND. The old firmware only sets a flag used to abort BASIC programs.
- IRQ entry takes seven cycles plus the remainder of the current instruction; the old handler saves A, X, and Y on the stack. At 1 MHz with a 100 Hz tick, handler cycles directly equal CPU percentage: 100 cycles ≈ 1%.

### 6.2 Timers

Old design using VIA1 Timer 1 in free-run mode:

| Register | Value | Meaning |
|---|---|---|
| ACR | `%01000000` | T1 free-run, PB7 output disabled |
| IER | `%11000000` | Timer 1 IRQ enabled |
| T1C-L/H | `<10000` / `>10000` | Counter 10,000 |

Because Timer 1 counts `N + 2` cycles per free-run period, the real period is **10,002 µs** rather than 10,000 µs: 100 Hz with 0.02% error. Reading `T1C-L` acknowledges the interrupt. Each tick increments `_millis` by 10 and advances `_jiffies` (0..99), `_seconds`, `_minutes`, and `_hours`, representing time since reset without a date and drifting 0.02% slow.

A blocking `delay_ms()` busy loop in `utils.s65` is calibrated for exactly 1 MHz. VIA2 Timer 1/2 and VIA1 Timer 2 are free and could be used for sound timing, a software UART, etc.

---

## 7. Reset and Clock

- **Clock:** 1 MHz crystal-oscillator module QG1 (14-pin DIL can, TTL square wave according to the project page), directly connected to PHI0.
- **Reset:** NE555 monostable, R2 47k and C4 10 µF, giving ≈ 1.1 × 47 kΩ × 10 µF ≈ **0.5 s**. It is triggered at power-on by R1 1M/C3 100 nF or by the reset button/JP2. Its output is inverted by 74LS04 IC3A to active-low `/RESET` for CPU, VIA1, VIA2, ACIA, and SID. Firmware may therefore assume all devices begin in reset state.
- **Startup** (`startup.s65`): `SEI`, `CLD`, `S = $FF`; C software-stack pointer at `$7F00` growing downward; clear BSS; copy DATA from ROM to RAM; call `initlib`, `irq_init`, `CLI`, and `main()`.

---

## 8. Memory Organization of the Previous Firmware (cc65)

From `firmware/firmware.cfg` and the map file:

| Segment | Load address | Run address | Size (ca65 V2.14 build, `firmware.map`) |
|---|---|---|---|
| ZEROPAGE | – | `$0000–$002B` | 44 B |
| DATA | ROM `$8000` | RAM `$0200` | 333 B |
| BSS | – | RAM `$034D` | 815 B |
| HEAP | – | After BSS through software stack | Remaining space |
| STARTUP / INIT | ROM `$814D` | ROM | 37 B / 63 B |
| CODE | ROM `$8200` (256-byte aligned) | ROM | 18,745 B |
| RODATA | After CODE | ROM | 1,169 B |
| VECTORS | `$FFFA` | ROM | 6 B |

The ROM image is always 32,768 bytes with fill byte `$FF`; about 20 KB are occupied. The C software stack begins at `$7F00` and grows downward (`__STACKSIZE__ = $0200`).

Old firmware zero-page variables (`zeropage.s65`):

| Address | Size | Name | Purpose |
|---|---|---|---|
| `$00` | 2 | `sp` | cc65 software-stack pointer |
| `$02` | 2 | `sreg` | cc65 runtime 32-bit register |
| `$04` | 4 | `regsave` | cc65 runtime |
| `$08` | 8 | `ptr1..ptr4` | Auxiliary pointers |
| `$10` | 4 | `tmp1..tmp4` | Temporaries |
| `$14` | 6 | `regbank` | cc65 register variables |
| `$1A` | 1 | `tmpstack` | Temporary for PHX/PHY macros |
| `$1B` | 4 | `_millis` | 32-bit millisecond counter |
| `$1F–$22` | 1 each | `_jiffies/_seconds/_minutes/_hours` | Time of day |
| `$23–$26` | 1 each | `key_code, key_modifiers, key_tmp1, key_tmp2` | Keyboard |
| `$27–$2A` | 1 each | `lcd_enable_bits, lcd_cursor, lcd_row, lcd_column` | LCD |
| `$2B` | 1 | `_interrupted` | NMI flag |

Addresses from `$08` onward were reconstructed from declaration order and the map file; linker output is authoritative.

---

## 9. Previous Software (Reference)

The previous firmware (`firmware/`) is a minimal BASIC interpreter in C with assembly drivers.

- **Files:** `acia.s65`, `lcd.s65`, `keys.s65`, `sid.s65`, `led.s65`, `interrupt.s65`, `startup.s65`, `utils.s65`, `main.c`, `basic.c` (~1,300 lines), `variables.c`, `readline.c`, `debug.c`.
- **Toolchain:** the **cc65 suite** (<http://cc65.github.io/cc65/>):
  - `ca65` assembler for `*.s65` and `*.inc65`, e.g. `ca65 --cpu 6502 -o x.o -l x.lst x.s65`.
  - `cc65` C compiler (`--cpu 6502 -O -t none`), producing assembly for `ca65`.
  - `ld65` linker through `cl65` (`cl65 -C firmware.cfg -m firmware.map -o firmware *.o cc65.lib`), with layout in `firmware.cfg`.
  - The old code uses ca65-specific `.zeropage`/`.globalzp`, `.macro` (for example `phx` and `ld16`), local `@` labels, `.import`/`.export`, and `.segment`. Older revisions in `firmware/versions/` link with `cl65 -C firmware.cfg -t none`.
  - The repository does not name a cc65 version. This machine has cc65 at `/opt/cc65` (ca65 **V2.14**, Git 6df4205). The old firmware builds successfully there and produces a 32,768-byte image with the same map described in section 8 when `/opt/cc65/bin` is on `PATH` and `CC65_HOME=/opt/cc65` is set; without the latter, `cc65` cannot find headers such as `stdio.h`.
  - Programming uses the Minipro TL866CS: `minipro -p at28c256 -w firmware` (`make flash`).
- **BASIC commands:** `goto run led print put list new free save load dir sleep cls home synth let clear input at cursor seed if end edit rem write`. Missing: arrays, GOSUB/RETURN, FOR loops, and the SID commands from the project page.
- **I/O:** keyboard and LCD are the local console; ACIA operates in parallel, with messages written to both.
- **Program storage:** PC script `tools/disk/disk.rb` at 19200 baud over a MAME PTY or `/dev/ttyUSB0`. Its line-oriented handshake is:
  - Computer → PC: `*SAVE "name"` … program lines … `*EOF`
  - Computer → PC: `*LOAD "name"`; PC replies with requested program lines, then `*EOF`, or `!NOTFOUND`
  - Computer → PC: `*DIR`; PC replies with `"%04d name"` lines and `*EOF`; abort with `*BREAK`
  - Example programs: `examples/*.bas`
  - Monitor terminal: `tools/terminal/mame-pico.sh` for PTY and `tools/terminal/serial-pico.sh` for `/dev/ttyUSB0`, 19200 8N1.
- **Emulation:** A fork of the Java Symon 6502 simulator is in `../symon`, with `GrappendorfMachine` (`src/main/java/com/loomcom/symon/machines/GrappendorfMachine.java`) implementing RAM `$0000–$7EFF`, ACIA `$7F00`, VIA1 `$7F20`, VIA2 `$7F40`, SID `$7F60`, and 32 KB ROM at `$8000`. The ROM path is hard-coded to `../homecomputer-6502/firmware/firmware` with a TODO. LCD and keyboard are probably not modeled as devices beyond the VIA registers **[not verified]**; console I/O uses the simulated ACIA. This was the obvious starting point for hardware-free testing.

---

## 10. Observations About the Existing Firmware (Pitfalls)

These issues should not be carried into the rewrite:

1. `_lcd_clear` has no final `rts` and falls through into `_lcd_cursor_on`, unintentionally enabling the cursor.
2. LCD delays are busy loops because R/W is grounded. The required 1.6 ms delay after *Clear Display* is missing.
3. The IRQ handler acknowledges only VIA1 Timer 1; another interrupt source would trap the CPU in the IRQ loop.
4. `keys_update` blocks for 20 ms per detected keypress; nothing else ticks during that busy loop.
5. ACIA receive is polled and blocking (`acia_getc`) with no buffer. Characters are lost at 9600 baud while the CPU is busy, such as during `delay_ms` or keyboard scanning; line handshaking masks this during file upload.
6. `_millis` advances by 10 per tick although the real period is 10,002 µs (see 6.2).
7. In `write_4bits`, `lda tmp1` immediately before `lda VIA1_ORA` is dead code.
8. All LCD routines save A/X/Y using macros and `tmpstack` in zero page, so they are not IRQ-safe.

---

## 11. Open Questions

Items not safely derivable from the repository, to be resolved before firmware design:

1. ~~CPU variant~~—resolved: MOS 6502AD (NMOS).
2. ~~ACIA variant~~—resolved: R6551 (NMOS).
3. ~~Clock frequency~~—decided: **remains 1 MHz**. Tick, `delay_ms`, and LCD timing constants may be fixed at 1 MHz.
4. ~~Keyboard~~—resolved; see [keyboard-matrix.md](keyboard-matrix.md): internal pull-ups on VIA2 Port A, no visible diodes. Fn + Windows are outside the scan matrix and together trigger a hard reset.
5. ~~Goal of new firmware~~—decided; see section 15: port a late Microsoft BASIC variant to the LCD and add a serial monitor. Implementation status is in [firmware.md](firmware.md).
6. ~~Console~~—implemented; see 15.1: LCD for BASIC, serial for the monitor, with `*BASIC` and `*DISK` on request. ACIA receive is interrupt-driven. Details in [firmware.md](firmware.md).
7. ~~SID inputs~~—decided: no paddles; ignore them.
8. ~~Mass storage~~—decided; see 15.3: `SAVE`/`LOAD` BASIC commands through `tools/disk/disk.rb`.
9. ~~VIA type/vendor~~—not relevant and no longer pursued; Port A pull-ups are confirmed (5.6).
10. **Power supply:** irrelevant to firmware; no action needed.

---

## 12. Quick Reference

```
CPU        MOS 6502AD (NMOS) @ 1 MHz (PHI2 = 1 µs/cycle)
RAM        $0000–$7EFF   (zero page $00xx, stack $01xx, free $0200–$7EFF)
I/O        $7F00–$7FFF   ACIA R6551 $7F00, VIA1 $7F20, VIA2 $7F40, SID 8580 $7F60
ROM        $8000–$FFFF   vectors $FFFA–$FFFF
IRQ        VIA1 + VIA2 + ACIA (OR)      NMI: JP3 button
Serial     ACIA 19200 8N1 (1.8432 MHz)  JP4: GND/TXD/RXD
LCD        4×40, 4-bit: PA0–3=D4–D7, PA4=RS, PA5=E1 (rows 0/1), PA6=E2 (rows 2/3), R/W=GND
LED        VIA1 PA7
Keyboard   columns VIA2 PA0–7, rows VIA2 PB0–7 + VIA1 PB0–5 (14×8)
Tick       VIA1 Timer 1, free-run, 10,000 → 100 Hz
Free       VIA1 PB6/PB7, VIA1 T2/SR, VIA2 T1/T2/SR, both VIAs' CA/CB lines, decoder Y4–Y7 ($7F80–$7FFF)
```

---

## 13. Development Process (Decisions)

| Topic | Decision / status |
|---|---|
| ROM socket | The EEPROM is **socketed**. |
| Hardware testing | Every firmware revision must be programmed with the TL866CS (`scripts/flash.sh`: remove, program, reinstall EEPROM). This is slow and consumes AT28C256 write cycles, so hardware tests are reserved for drivers and final acceptance. |
| Emulator | **Implemented: MAME.** Custom driver in `mame-extensions/` for the 4×40 LCD, keyboard matrix, ACIA, SID, and Fn+Windows reset. Start with `scripts/run-mame.sh`; see `mame-extensions/README.md`. The Symon fork is no longer pursued. |
| Debugger / monitor | No in-system debugger. A small serial **hex monitor** is available; see 15.2 and [monitor.md](monitor.md). |
| Debug output | Originally planned as compile-time optional serial statements. **Not implemented**; 13.1 is a draft only. Use the MAME debugger and monitor. |

### 13.1 Debug-Output Requirements (Draft, Not Implemented)

- A `DEBUG` build switch (`ca65 -D DEBUG`, `cc65 -D DEBUG`, e.g. `make DEBUG=1`) should control both assembly and C macros. Without it, macros emit neither code nor strings so the ROM does not grow.
- Debug lines need a distinct prefix such as `#` if the host logs every line. `*` and `!` already identify file-protocol commands/errors (`*SAVE`, `*LOAD`, `*DIR`, `*EOF`, `*BREAK`, `!NOTFOUND`).
- At 19200 baud, one character takes about 0.52 ms (≈520 cycles). Blocking transmission distorts timing measurements, keyboard polling, and interrupt timing. An interrupt-driven transmit buffer may therefore be useful in debug builds; the R6551 supports it (5.1).
- The switch should alter memory layout as little as possible, or bugs may disappear in debug builds and appear only in release builds.

### 13.2 MAME as Emulator (Original Evaluation, Now Implemented)

At decision time, MAME already provided a 6502 core, 6522 VIA, 6551 ACIA, both 6581 and 8580 SID, and HD44780 LCD. Modeling the machine still required a **C++ driver and a custom MAME build**. MAME was not installed then; Arch offered version 0.289. Advantages were accurate emulation, the built-in debugger with breakpoints, trace and memory view, save states, and Lua. The setup effort for two HD44780 controllers and the 14×8 keyboard matrix was higher than extending the Symon fork.

---

## 14. Project Structure and Constraints (Decisions)

| Topic | Decision |
|---|---|
| Toolchain | Continue using **cc65** (ca65, cc65, cl65/ld65); see section 9. |
| License | Software remains under the **MIT License**, like the old firmware. |
| Directories | Separate directories for **firmware source** and the **MAME extension**. |
| Source organization | **Modular:** split by module rather than one large assembly file. |

### 14.1 Directory Structure (Created)

```
homecomputer-6502-firmware/
├── docs/            Specifications (system-spec.md, firmware.md, basic.md, monitor.md, keyboard-matrix.md, tutorial.md)
├── examples/        Example programs (*.bas, *.s65)
├── src/             Firmware source, Makefile, firmware.cfg (see 14.2 and firmware.md)
│   └── msbasic/     Microsoft BASIC-M6502 V1.1
├── mame-extensions/ MAME driver, layout, character set, install.sh
├── mame/            MAME source tree (local, not in Git)
├── scripts/         run-mame.sh, flash.sh
├── tools/           PC tools
│   ├── disk/        disk.rb, mame-disk.sh, serial-disk.sh (BASIC disk)
│   ├── terminal/    mame-pico.sh, serial-pico.sh, mame-basic.sh, serial-basic.sh, basic-host.rb
│   └── msbasic-convert/  Converter.java
├── build/           Build output (firmware.bin, not in Git)
└── LICENSE          MIT
```

The Makefile is in `src/` (`cd src && make`). There is no `DEBUG` switch.

**Decision:** The MAME extension lives in `mame-extensions/` in this project. The MAME source tree itself is in adjacent `mame/` and is not committed.

### 14.2 Module Structure (Implemented)

The actual modules are documented in [firmware.md](firmware.md):

| Layer | Modules | Contents |
|---|---|---|
| Hardware definitions | `io.inc65`, `zp.inc65`, `kernal.inc65`, `disk.inc65` | Register addresses, zero-page layout, API addresses |
| Startup and system | `startup`, `irq`, `delay` | Reset, vectors, IRQ dispatcher for VIA1/VIA2/ACIA, delays |
| Drivers | `lcd`, `keyboard`, `sid` | One device each; `monitor` and `serio` operate the ACIA |
| Application | `msbasic/`, `monitor`, `serio`, `disk`, `kernal` | BASIC, hex monitor, serial BASIC, serial disk, jump table at `$FF80` |

Rules derived from the old firmware observations in section 10:

- Each module has an include file for its public interface (`*.inc65` for assembly, `*.h` for C) and exports only what other modules need.
- Zero-page variables are assigned and documented centrally because the 256-byte space is scarce and partly used by the cc65 runtime.
- Drivers are IRQ-safe; shared registers such as VIA1 Port A (LCD and LED) are accessed only through read-modify-write or a shared shadow variable.
- Each module builds to its own `.o` file and links with the common `firmware.cfg`.

All new source-file license headers reference MIT, with the copyright from the old firmware's `LICENSE-Software.txt`.

---

## 15. Firmware Concept (Target Design)

High-level design agreed with the user. The line editor is specified in 15.5. LCD and SID commands are in [basic.md](basic.md); the filter remains open.

### 15.1 Two Consoles, Two Purposes

| Console | Use | Not intended for |
|---|---|---|
| **Serial (ACIA, `$7F00`)** | **Hex monitor** for displaying/modifying memory and calling a program with `G` (15.2). On host request it hands over to `*BASIC` or `*DISK`. Debug output (13.1) was not implemented. | Standard BASIC is not serial unless requested with `*BASIC`. |
| **LCD + keyboard** | **BASIC only:** line editor for entering/editing programs (15.5), program output, and `INPUT`. | No monitor and no debug output. |

This resolves former open items 5 and 6 in section 11; details are in 15.4.

### 15.2 Serial Monitor

Implemented as a small WOZMON-style monitor:

- Display memory ranges as hex dumps and modify individual locations.
- Start a program at an address: `G` calls it like `JSR`, and it must end with `RTS`.
- **No CPU register display**; it was planned but not implemented.
- Serial-only at 19200 8N1, using the same terminal setup as `serial-pico.sh` / `mame-pico.sh`.
- ACIA receive/transmit run in `mon_irq`.

Commands are in [monitor.md](monitor.md); integration is in [firmware.md](firmware.md).

### 15.3 Porting Microsoft BASIC for the 6502

Instead of extending the hand-written BASIC in `firmware/basic.c`, the design ports **Microsoft BASIC for the 6502**.

**Source (resolved):** In September 2025 Microsoft officially released the original **BASIC-M6502 version 1.1** source under the **MIT License** at <https://github.com/microsoft/BASIC-M6502>, archived read-only since September 5, 2025. This 1976–1978 ancestor of Commodore, Applesoft, and OSI BASIC already supports multiple targets through conditional assembly (Apple II, Commodore PET, OSI, KIM-1) and includes a PDP-10 cross-assembly variant. It consists of one 6,955-line `m6502.asm` file.

**License (resolved):** MIT. Microsoft's copyright notice must remain in the source. This is compatible with the project's MIT license. Later, more capable Commodore BASIC 4.0/7.0 variants are not covered by this release, so the port is based on BASIC-M6502 V1.1.

Firmware extensions over the original:

1. **Serial `SAVE`/`LOAD`**, compatible with `tools/disk/disk.rb` (`*SAVE`, `*LOAD`, `*DIR`; section 9), implemented as BASIC statements.
2. **SID commands:** `VOL`, `TEMPO`, `ENVELOPE`, `WAVE`, `SOUND`, `TUNE`, `PLAY`, `EFFECT`. Melodies/effects run in the background from VIA2 Timer 1 at 50 Hz. See [basic.md](basic.md). A filter command remains open.
3. **LCD commands:** `CLS`, `LOCATE`, `CURSOR`, `DISPLAY`. See [basic.md](basic.md). Defining custom characters remains open.

### 15.4 Remaining Concept Questions

1. ~~Microsoft BASIC source~~—resolved as V1.1 under MIT. The original conditional targets are replaced with one for this machine. ROM/RAM sizing still had to be assessed against the available 32 KB each.
2. ~~License~~—resolved as MIT; preserve Microsoft's notice.
3. **Scope of SID/LCD commands:** LCD includes `CLS`, `LOCATE`, `CURSOR`, `DISPLAY`; SID includes `VOL`, `TEMPO`, `ENVELOPE`, `WAVE`, `SOUND`, `TUNE`, `PLAY`, `EFFECT`. Filter control and custom LCD characters remain open.
4. ~~Monitor versus BASIC~~—decided and implemented: both start after reset, BASIC immediately on LCD/keyboard and the monitor waiting on serial, with no key combination.
5. ~~Memory layout~~—decided:
   - Zero page `$00–$CF` for Microsoft BASIC and `$D0–$FF` for drivers. Driver state that does not fit, because BASIC owns `$FF` as `LOFBUF`, resides in the system buffer.
   - `$0200–$03FF` system buffer. The BASIC line buffer provides 120 editable characters at `$0200`; the terminating NUL makes its complete range `$0200–$0278`. Driver RAM from `$0279` stores LCD/SID shadows, melodies, and instruments. Zero page from `$D0` holds two SID pointers; `$D4` onward holds keyboard, delay, LED, and more SID state; the editor begins at `$E9`; `$FF` remains `LOFBUF`. A 160-character buffer would fill the screen but does not fit alongside LCD/SID state.
   - Hardware stack `$0100–$01FA` (`STKEND = 507`, as on PET and Apple II). `$01FB–$01FF` belong to BASIC: line number and link pointer immediately before `BUF` (`BUF-5` through `BUF-1`), moved by `INSLIN` as one block. With `STKEND = 511`, `STKINI` left S at `$FE`; an IRQ during `STOLOP` at `$8C6B` then wrote return-address high byte `$8C` over the line-number low byte, randomly turning lines into line 140. This affected both serial and LCD input.
   - `$0440–$7EFF` BASIC workspace; `$0279–$043F` driver RAM for LCD, SID, and serial BASIC buffer. `MEMSIZ` is fixed at exclusive end `$7F00`, with `$7EFF` the last RAM byte. BASIC does not ask for `MEMORY SIZE`.
   - Fixed line width 40, matching one LCD row. BASIC does not ask for `WIDTH`.

### 15.5 LCD Line Editor

Replacement for the original `INLIN`, which only used `_` to delete a character and `@` to clear the line. The editor lives in ROM with the interpreter.

Its model is the Commodore screen editor: a program line is displayed as text, the cursor moves through it, and Enter rewrites it in program memory. Because the 4×40 LCD is not a freely addressable C64 screen, this applies to **one logical line** and browsing between program lines, not arbitrary editing of a displayed listing.

#### Buffer

- **120 editable characters**, including the line number and following space. Further keys are ignored; text wraps every 40 characters.
- The terminating NUL occupies the following byte and does not count.
- Enter passes exactly this text to BASIC as if typed; existing `CRUNCH` and line insertion/replacement remain unchanged.

#### Display

- The editor begins at the current BASIC cursor position. Banners, `PRINT`, and errors remain visible; new input starts on the next line.
- Text wraps every 40 characters. Continuation rows belong to the same buffer and have no separate number field. Redrawing occurs with the cursor off so the underline does not travel across the display.
- A program line starts as `LIST` prints it: digits, one space, then the statement.
- The LCD cursor underlines the character at the editor cursor. Enter completes the line and advances to the next display row.

#### Two Input Modes

| Situation | Editor behavior |
|---|---|
| Direct mode after `OK` | Full editor, including program browsing |
| `INPUT` | Same line editing with left/right, Backspace, and Enter, but no program browsing |

#### Keys

Insert mode is the default: a typed character shifts the remainder right.

| Key | Effect |
|---|---|
| Left / Right | Move one character, bounded by the start and end of text. |
| Up / Down | Move one LCD row (40 characters). Crossing the start/end loads the previous/next program line only if the loaded line is unchanged. If the buffer contains only a line number, load that exact line if present, then browse from it. |
| Backspace | Delete the character before the cursor. |
| Delete | Delete the character under the cursor. |
| Home / End | Move to the start or just after the last character. |
| Insert | Toggle overwrite mode. Display blinking indicates overwrite; insert remains the default. |
| Enter | Submit the line to BASIC. |
| Escape | Discard it and submit an empty direct line. |

Up on an empty direct line loads the last program line; Down loads the first. Up from the first line at its start stays there. Down from the last line at its end opens an empty direct line. A typed line number alone makes Up or Down jump to that line; if missing, the typed text remains.

#### Loading a Program Line

An existing line is placed in the buffer exactly as `LIST` would print it: keywords as text rather than tokens, with one space after the line number. The cursor starts on the first character.

Pressing Enter afterward:

- The same line number replaces the line.
- A number alone deletes the line.
- Another number creates that numbered line; the previously displayed line remains, as on the C64.
- Without a leading number, the text is executed as a direct command and is not stored.

#### Out of Scope

Horizontal scrolling, editing multiple program lines at once, and syntax highlighting. `LIST` remains a regular BASIC command writing through the scrolling LCD driver.
