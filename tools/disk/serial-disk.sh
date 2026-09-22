#!/bin/bash
# Serial floppy on the real ACIA.
#
#   serial-disk [DIRECTORY] [DEVICE]
#
# Without DIRECTORY, uses ../../examples next to this repo.
# DEVICE defaults to /dev/ttyUSB0. Picocom must not hold the port.
# Ctrl-C sends *EJECT and the monitor prompt comes back.
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

exec ruby "$here/disk.rb" "$dir" "$dev"
