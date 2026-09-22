#!/bin/bash
# PicoCom on the real ACIA (19200 8N1). Monitor echoes, so no --echo.
#
#   serial-pico                 # /dev/ttyUSB0
#   serial-pico /dev/ttyUSB1
set -euo pipefail

dev="${1:-/dev/ttyUSB0}"
if [[ ! -e "$dev" ]]; then
	echo "error: no such device: $dev" >&2
	exit 1
fi

# The adapter comes up cooked: keys sit until NL, and Enter is LF not CR.
# Raw so each key reaches the ACIA.
stty -F "$dev" 19200 raw -echo -icrnl -inlcr -ocrnl -onlcr cs8 2>/dev/null || true

exec picocom --b 19200 --imap lfcrlf --omap crlf "$dev"
