# HomeComputer 6502 Firmware

Firmware for my homemade 6502 home computer (6502 CPU, 2× 6522 VIA, R6551 ACIA, SID 8580, 4×40 LCD, 89-key keyboard), together with a MAME driver that emulates the whole machine.

The project was also an experiment: **the firmware was developed together with an AI agent** (Claude Code). The workflow and lessons learned are described in the article "Firmware development with AI" on [grappendorf.net](https://www.grappendorf.net).

## What's inside

- **BASIC**: Microsoft's open-source BASIC-M6502, ported to this machine (LCD output, keyboard input, LCD/LED/SID commands, `DIR`/`LOAD`/`SAVE`/`DELETE`).
- **Monitor**: a WOZMON-style monitor on the serial port that runs in the background while BASIC runs on the LCD.
- **Virtual floppy drive**: a small Ruby tool on the host that serves a directory as a disk over the serial port.
- **MAME driver**: emulates the complete computer, including case artwork with the live LCD. See [mame-extensions/README.md](mame-extensions/README.md).
- **Flash script**: `scripts/flash.sh` builds the image and writes it to the AT28C256 EEPROM.

## How it was built

1. The AI parsed the old Eagle schematics, datasheets and firmware and wrote a **hardware specification**. Uncertain statements are marked `[Assumption]` or `[Open]` and were resolved in short chat rounds.
2. Together we wrote a **firmware specification**: what runs where (BASIC on LCD/keyboard, monitor on serial, programs on the virtual drive).
3. The AI built an emulator first, so no EEPROM had to be burned for every change, then ported BASIC, and added features in small steps.
4. It builds, runs the emulator and looks at the result, so it finds many of its own mistakes.

Both specifications are plain Markdown files in this repo, so the agent can re-read them at the start of every session.

## Documentation

- [docs/system-spec.md](docs/system-spec.md): hardware and memory map
- [docs/firmware.md](docs/firmware.md): firmware design
- [docs/basic.md](docs/basic.md): BASIC port
- [docs/monitor.md](docs/monitor.md): serial monitor
- [docs/keyboard-matrix.md](docs/keyboard-matrix.md): keyboard matrix

## Quick start

Build the firmware with cc65 and start it in the emulator:

```bash
scripts/run-mame.sh
```

Details on setting up MAME are in [mame-extensions/README.md](mame-extensions/README.md).
