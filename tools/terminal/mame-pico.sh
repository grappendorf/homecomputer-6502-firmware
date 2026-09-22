#!/bin/bash
# PicoCom on the emulated ACIA PTY (19200 8N1). Monitor echoes, so no --echo.
#
# Usage:
#   mame-pico                 # PTY from last MAME start (/tmp/homecomputer6502.pty)
#   mame-pico /dev/pts/N
set -euo pipefail

dev="${1:-}"
if [[ -z "$dev" ]]; then
	if [[ -f /tmp/homecomputer6502.pty ]]; then
		dev="$(tr -d ' \t\r\n' </tmp/homecomputer6502.pty)"
	fi
	if [[ -z "$dev" || ! -e "$dev" ]]; then
		echo "error: no PTY. Start MAME (scripts/run-mame.sh) or pass /dev/pts/N" >&2
		exit 1
	fi
	echo "PTY $dev"
fi

# Slave PTY comes up in canonical mode: keys sit in the line discipline
# until NL, and Enter is LF not CR. Raw so each key reaches the ACIA.
stty -F "$dev" 19200 raw -echo -icrnl -inlcr -ocrnl -onlcr cs8 2>/dev/null || true

exec picocom --b 19200 --imap lfcrlf --omap crlf "$dev"
