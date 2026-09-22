# Firmware Specification

This is how the HomeComputer 6502 firmware is organized. The hardware is described in [system-spec.md](system-spec.md), the BASIC commands in [basic.md](basic.md), the serial monitor in [monitor.md](monitor.md), and the keyboard in [keyboard-matrix.md](keyboard-matrix.md). This page ties them together: memory, modules, interrupts, startup, and building.

The sources are in `src/`. All files are MIT-licensed. The BASIC core (`src/msbasic/`) is Microsoft's MIT-released BASIC-M6502 V1.1 and includes its copyright notice.

## Overview

- Microsoft BASIC starts after reset. The LCD and keyboard form its console.
- A small hex monitor runs in parallel over the ACIA (19200 baud, 8N1).
- The monitor can hand over the line to serial BASIC (`*BASIC`) or serial “disk storage” (`*DISK`, `tools/disk/disk.rb`).
- A VIA timer drives the SID player, which produces sound while BASIC continues running.
- The ROM image is exactly 32768 bytes. `make` verifies this.

## Memory Layout

| Range | Contents |
|---|---|
| `$0000–$0096` | Microsoft BASIC zero page |
| `$0097–$00C1` | Monitor zero page |
| `$00C2–$00CE` | Serial disk zero page |
| `$00CF` | `LIST` pager |
| `$00D0–$00FF` | SID player, keyboard, line editor, monitor jump vector (see `src/zp.inc65`) |
| `$0100–$01FF` | 6502 stack. `$0100–$010F` is also `FBUFFR`, as in the original BASIC |
| `$0200–$0278` | BASIC line buffer (120 characters + NUL) |
| `$0279–$043F` | Driver RAM (`BSS`, 455 bytes): LCD, SID, serial ring buffer |
| `$0440–$7EFF` | BASIC workspace. The program starts at `$0441` |
| `$7F00–$7FFF` | I/O (ACIA, VIA1, VIA2, SID); see [system-spec.md](system-spec.md) |
| `$8000–$FF7F` | ROM, `CODE` segment |
| `$FF80–$FFF9` | ROM, `KERNAL` segment: fixed jump table |
| `$FFFA–$FFFF` | Vectors (NMI, RESET, IRQ) |

The linker layout is defined in `src/firmware.cfg`. At the time of the latest build, `CODE` occupies `$4DCD` of `$7F80` bytes, leaving well over half of the ROM free.

## Startup Sequence

`src/startup.s65`, label `reset`:

1. `SEI`, `CLD`, set the stack pointer to `$FF`.
2. Fill the entire zero page with 0.
3. Call `lcd_init`, `kb_init`, `sid_init`, `irq_init`, and `mon_init`.
4. `CLI`, then `JMP INIT`—Microsoft BASIC begins here.

The NMI vector points to a single `RTI`, so NMI does nothing.

## Interrupts

`src/irq.s65` contains one shared IRQ handler. It saves A, X, and Y and executes `CLD`.

| Source | Rate | Purpose |
|---|---|---|
| VIA1 Timer 1 | Free-running, 10 ms | Turns off the reset LED after 100 ticks (1 s). The timer keeps running so the monitor can process its outgoing data |
| VIA2 Timer 1 | Free-running, 20 ms (50 Hz) | `sid_tick`: one step of the SID player |
| ACIA | Per character | `mon_irq`: monitor receive and transmit |

Every IRQ calls `mon_irq` to process ACIA interrupts. The monitor's jump into a user program (`G`) does not occur in the IRQ, but between two BASIC statements.

## Modules

| File | Purpose |
|---|---|
| `startup.s65` | Reset and vectors |
| `irq.s65` | IRQ dispatcher and timers |
| `delay.s65` | Delay loops for 1 MHz (`delay_ms`, `sleep_ms`) |
| `lcd.s65` | 4×40 LCD, two HD44780 controllers, 4-bit bus on VIA1 Port A. Screen buffer `lcd_buf` (4×40). R/W is tied to ground, so every command uses a fixed delay. PA7 is the LED and is preserved on every port access. Custom characters (µ, ´, €, ², ³, etc.) occupy CGRAM slots |
| `keyboard.s65` | 14×8 matrix on VIA2. One key at a time. Repeat: 400 ms before the first repeat, then every 50 ms. Caps Lock is latched by the firmware. Arrows, Home, End, Delete, and Insert return the `ED_*` codes from `io.inc65` |
| `sid.s65` | SID 8580. Shadow copies of the registers (which are write-only). Frequency = Hz × 16.777216. Linear filter from 30 Hz to 12 kHz. Player, sounds, and nine effects |
| `monitor.s65` | Hex monitor over the ACIA. Details in [monitor.md](monitor.md) |
| `serio.s65` | Serial BASIC: `#1` = LCD and keyboard, `#2` = ACIA. 48-byte receive ring buffer |
| `disk.s65` | Serial disk: `*DIR`, `*LOAD`, `*SAVE`, and machine programs via `*PRG`. Its counterpart is `tools/disk/disk.rb` |
| `kernal.s65` | Jump table at `$FF80` for loaded programs |
| `msbasic/` | Microsoft BASIC-M6502 V1.1, `REALIO=6` (adapted for this machine) |

Include files: `io.inc65` (register addresses and key constants), `zp.inc65` (zero-page layout), `kernal.inc65` (API addresses), and `disk.inc65` (status values).

## Machine-Program API (Kernal)

Fixed entry points beginning at `$FF80`, each containing one `JMP`. A, X, and Y are destroyed unless otherwise noted.

| Address | Name | Function |
|---|---|---|
| `$FF80` | `API_CLS` | Clear the LCD |
| `$FF83` | `API_LOCATE` | A = row 0..3, X = column 0..39 |
| `$FF86` | `API_POKE` | Write the character in A. The LCD address advances |
| `$FF89` | `API_CURSOR` | A = 0 disables the underline cursor; any other value enables it |
| `$FF8C` | `API_KEY` | A = ASCII or 0. X and Y are preserved |
| `$FF8F` | `API_DELAY` | A = milliseconds |
| `$FF92` | `API_QUIET` | Close all SID gates |
| `$FF95` | `API_EFFECT` | A = 1..9, sound effect |

Programs are loaded at `$0441`. They start through a BASIC prefix containing the `SYS` token (`$AD`). Examples and the build scaffold are in `examples/` (`build.sh` turns every `*.s65` file into a `.prg`).

## Serial Line

The ACIA (`$7F00`) runs at 19200 baud, 8N1, using its internal baud-rate generator. It has three operating modes:

1. **Monitor** (default).
2. **Serial BASIC:** the host sends `*BASIC`. `PRINT` and `INPUT` then use the ACIA by default. `QUIT` returns the line.
3. **Disk:** the host sends `*DISK`. BASIC uses the old line protocol (`*SAVE`, `*LOAD`, `*DIR`, `*EOF`, `!NOTFOUND`). `*EJECT` or a dead host ends the mode.

The 6551 holds only one byte. During a disk transfer, receive IRQs are disabled and the main loop polls the line.

## Building and Programming

```bash
cd src && make          # produces build/firmware.bin, exactly 32768 bytes
```

- Toolchain: cc65 (`ca65 --cpu 6502`, `ld65`). `CC65_HOME` points to `/opt/cc65`.
- BASIC is assembled with `-D REALIO=6`.
- The result is checked for an exact size of 32768 bytes. The build fails otherwise.

For the hardware:

```bash
scripts/flash.sh        # programs the EEPROM in the TL866CS
```

The AT28C256 is socketed and cannot be written in the computer (`/WE` is tied to VCC). Remove the chip to program it. Instructions are included at the top of `scripts/flash.sh`.

In the emulator:

```bash
scripts/run-mame.sh /path/to/mame
```

See `mame/README.md` for more information.

## PC Tools

| Path | Purpose |
|---|---|
| `tools/disk/disk.rb`, `mame-disk.sh`, `serial-disk.sh` | PC as a “disk”: load and save programs |
| `tools/terminal/basic-host.rb`, `mame-basic.sh`, `serial-basic.sh` | Serial BASIC |
| `tools/terminal/mame-pico.sh`, `serial-pico.sh` | Simple terminal (picocom) |
| `tools/msbasic-convert/Converter.java` | Converter for the Microsoft BASIC source code |
| `examples/*.bas`, `examples/*.s65` | BASIC and machine-language examples |

## Difference from the Original Plan

Section 15 of [system-spec.md](system-spec.md) proposed a monitor with a register display and `JMP`. The implemented monitor is the smaller WOZMON variant: `G` calls the program like a `JSR`, and it must end with `RTS`. There is no register display. The serial interface runs at 19200 baud rather than the previously assumed 9600 baud.
