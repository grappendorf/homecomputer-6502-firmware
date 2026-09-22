#!/bin/bash
# Serial BASIC on the real ACIA. Picocom is the terminal; basic-host.rb
# copies it to the machine and answers *LOAD, *SAVE, *DIR and *DELETE.
# 19200 8N1. When Picocom exits, the host sends QUIT so the console returns
# to the LCD and the ACIA returns to the monitor.
#
#   serial-basic                       # examples, /dev/ttyUSB0
#   serial-basic /dev/ttyUSB1          # examples on that device
#   serial-basic /path/to/dir          # that directory, /dev/ttyUSB0
#   serial-basic /path/to/dir /dev/ttyUSB1
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
default_dir="$(cd "$here/../../examples" && pwd)"
default_dev="/dev/ttyUSB0"

dir="${1:-$default_dir}"
dev="${2:-$default_dev}"

if [[ ! -d "$dir" ]]; then
	if [[ -z "${2:-}" && -e "$dir" ]]; then
		dev="$dir"
		dir="$default_dir"
	else
		echo "not a directory: $dir" >&2
		exit 1
	fi
fi

exec ruby "$here/basic-host.rb" "$dir" "$dev"
