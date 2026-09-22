#!/bin/bash
# Serial BASIC on the ACIA. Picocom is the terminal; basic-host.rb copies
# it to the machine and answers *LOAD, *SAVE, *DIR and *DELETE.
# 19200 8N1. When Picocom exits, the host sends QUIT so the console returns
# to the LCD and the ACIA returns to the monitor.
#
#   mame-basic                       # examples, PTY from MAME
#   mame-basic /dev/ttyUSB0          # examples on that device
#   mame-basic /path/to/dir          # that directory, PTY from MAME
#   mame-basic /path/to/dir /dev/pts/N
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
exec ruby "$here/basic-host.rb" "$@"
