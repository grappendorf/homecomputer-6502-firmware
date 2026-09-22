# Serial Monitor

A small WOZMON-style hex monitor operating over the ACIA (`$7F00`, 19200 baud, 8N1). Microsoft BASIC runs in parallel on the LCD and keyboard. Monitor input and output are handled in the IRQ; the jump into a user program (`G`) occurs between two BASIC statements. Source: `src/monitor.s65`. While `tools/disk/disk.rb` is connected, the monitor hands over the line; see below. The intended design was described in specification sections 15.1/15.2; this version does not include the register display or `JMP` behavior.

The on-device console remains assigned to BASIC. See [basic.md](basic.md).

## Connection

Physical hardware: JP4 (GND/TXD/RXD), FT232, **19200** 8N1.

In the MAME emulator, the ACIA is connected to a host PTY (default `-rs232 pty`). After starting `scripts/run-mame.sh`, run:

```bash
mame-pico
```

The script is located at `tools/terminal/mame-pico.sh` and is also installed as `mame-pico` on the PATH (`~/.local/bin`). It reads the PTY path from `/tmp/homecomputer6502.pty`, where MAME writes it on startup. Alternatively, use `mame-pico /dev/pts/N`. On the physical computer, at 19200 8N1 and with `/dev/ttyUSB0` as the default:

```bash
tools/terminal/serial-pico.sh
```

PicoCom runs without `--echo`; the monitor echoes its own input. The port is placed in raw mode first, because otherwise Linux buffers the line and sends Return as LF.

Banner after reset:

```
MON 6502
*
```

The input line is limited to 31 characters. The prompt is `*`.

## Commands

Spaces are allowed between components. Hexadecimal digits are `0–9A–Fa–f`. Addresses are 16 bits; bytes are 8 bits and may be written with one or two digits.

| Input | Effect |
|---|---|
| `A` | Display 16 bytes starting at address `A` as hexadecimal and ASCII |
| `A.B` | Dump from `A` through `B`, inclusive |
| `A: hh hh …` | Write bytes starting at `A`, advancing the address |
| `AG` | `JSR` to `A`; the routine must return with `RTS` |
| Return by itself | Display the next 16 bytes from the current address |
| `?` | One-line help |
| Backspace / Delete | Delete the last input character |
| Ctrl+C | Abort a dump or input line and show a new prompt |

Return may be CR, LF, or CRLF. CRLF counts as one line ending.

Example:

```
*8000
8000 78 D8 A2 FF 9A A9 00 AA 95 00 E8 D0 FB 20 72 80  x............ r.
*
```

`$8000` is the firmware's reset entry point (`SEI`, `CLD`, `LDX #$FF`, `TXS`, …).

Write and read back:

```
*400: 4C 00 80
*
*400
0400 4C 00 80 ...
```

Invalid input produces `?` and a new prompt.

If a key is pressed while a dump or help text is still being transmitted, it aborts that output and becomes the first character of a new input line. Ctrl+C does the same but displays only `*`.

## `G`—Calling Machine Code

`8000G` (or `8000 G`) sets the target address and calls it through `JMP (mon_goad)` as soon as BASIC calls `HCISCNTC` between two statements or waits for a key in `HCINCH`. This does **not** happen in the IRQ, so that the SID tick and keyboard can continue running and the 6502 stack belongs to BASIC execution.

The routine must end with `RTS`. The `*` prompt then reappears. Without `RTS`, the CPU remains there and BASIC does not continue. Registers A, X, Y, P, and S are neither displayed nor restored.

## Operation in Parallel with BASIC

| Path | BASIC | Monitor |
|---|---|---|
| Display / keyboard | Yes | No |
| ACIA `$7F00` | No | Yes |
| Execution context | Interpreter main loop | IRQ (VIA1 every 10 ms and ACIA receive); `G` in `HCISCNTC` / `HCINCH` |

VIA1 Timer 1 remains active after the reset LED is turned off so the monitor can continue transmitting. `/CTS`, `/DSR`, and `/DCD` are tied to ground as on the board. The monitor configures the ACIA for 19200 baud, 8N1, internal clock, DTR enabled, receive IRQ enabled, and transmit IRQ disabled.

The BASIC program and variables occupy `$0440`–`$7EFF`. Dumping or poking this range changes the running BASIC environment. I/O at `$7F00`–`$7FFF` and ROM at `$8000`–`$FFFF` are accessible; poking ROM has no effect.

## Monitor Memory

The monitor has no separate RAM segment: the BASIC buffer ends at `$0278`, and the remainder of the BSS area through `$03FF` was already full. State and the input line are stored in the zero page above Microsoft BASIC (`$00`–`$96`):

| Address | Contents |
|---|---|
| `$97`–`$B6` | Input line (32 bytes) |
| `$B7`–`$BF` | Length, output state, indices |
| `$C0`–`$C1` | Line-ending marker (CRLF), TX burst |
| `$F8`–`$F9` | Jump vector for `G` (in ZP because of the NMOS `JMP ($xxFF)` bug) |
| `$FA`–`$FD` | Current dump/poke address and range end |
| `$FE` | Intermediate nibble value |

`$FF` remains BASIC's `LOFBUF`. `$D0`–`$F7` belong to the SID, keyboard, and line editor. `$C2`–`$CE` belong to the serial disk (`mon_disk`, transfer, load state, progress).

## Disk Drive

`tools/disk/disk.rb` provides the drive for BASIC `DIR`/`LOAD`/`SAVE`/`DELETE`.

PicoCom must release the serial interface first. Then, with the directory containing the files:

```bash
tools/disk/mame-disk.sh
```

On the physical computer, PicoCom must likewise release the port:

```bash
tools/disk/serial-disk.sh
```

The directory is optional and defaults to `examples`. Without a device argument, `mame-disk.sh` obtains the PTY path from `/tmp/homecomputer6502.pty`; `serial-disk.sh` uses `/dev/ttyUSB0`. Another device may be supplied as the second argument, or by itself as the only argument. The connection is 19200 8N1.

The script sends `*DISK`. The monitor replies with `*OK` and stops interpreting hex commands. BASIC on the LCD can then use `DIR`, `LOAD`, and `SAVE` (see [basic.md](basic.md)). Ctrl+C in the script sends `*EJECT`, after which the monitor again displays `MON 6502` and `*`. Aborting in the middle of LOAD/SAVE cancels the command but leaves the drive mounted. If the host does not respond for too long, the firmware also aborts the command without ejecting the disk, so there is no subsequent `NO DISK`. Killing the host without `*EJECT` leaves disk mode active until reset or the next `*EJECT`.

## BASIC on the Serial Interface

`disk.rb` must not be running. The proxy starts PicoCom and sends `*BASIC`. In the emulator, using the PTY from `/tmp/homecomputer6502.pty`:

```bash
tools/terminal/mame-basic.sh
```

On the physical computer, with `/dev/ttyUSB0` as the default:

```bash
tools/terminal/serial-basic.sh
```

The monitor replies with `*OK` and stops interpreting hex lines. BASIC input and output then use the same terminal; the keyboard and LCD remain inactive. `LOAD`, `SAVE`, `DIR`, and `DELETE` use the same proxy to access `examples`; a directory or device may be supplied as for `disk.rb`. The proxy does not display the protocol lines. `QUIT` in BASIC writes `MON 6502` and `*` and returns the line. The proxy sends the same sequence when PicoCom exits. There is no `*EJECT` in this mode. `*BASIC` is rejected during `*DISK`, and `*DISK` is rejected during `*BASIC`.

The logical terminal size is 80×24 and may be changed with `TERM` (see [basic.md](basic.md)). `PRINT #1` and `INPUT #1` still access the LCD and keyboard.
