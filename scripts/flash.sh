#!/bin/bash
# Build the 32 KB ROM and write it to the AT28C256 in a TL866CS.
#
# The EEPROM is socketed and not writable in the computer (/WE on VCC).
# Take it out, seat it at the bottom of the ZIF (notch and pin 1 toward
# the lever, empty contacts next to the lever), then:
#
#   scripts/flash.sh
#
# minipro -u clears software data protection, then writes and verifies.
# Put the chip back into the computer afterwards, pin 1 toward the notch.
#
# Needs minipro on PATH (TL866A/CS, firmware 03.2.86). Override the
# device name with CHIP=.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
image="$root/build/firmware.bin"
chip="${CHIP:-AT28C256}"

if ! command -v minipro >/dev/null 2>&1; then
	echo "minipro not found. Install minipro for the TL866CS." >&2
	exit 1
fi

echo "Building firmware"
make -C "$root/src" all

bytes=$(stat -c %s "$image")
if [[ "$bytes" -ne 32768 ]]; then
	echo "firmware.bin is $bytes bytes, the AT28C256 needs 32768." >&2
	exit 1
fi

echo "Programmer"
minipro -k

echo "Writing $chip"
minipro -p "$chip" -u -w "$image"

echo "Done. Put the EEPROM back in the computer, pin 1 toward the notch."
