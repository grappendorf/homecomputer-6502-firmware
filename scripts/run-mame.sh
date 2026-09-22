#!/bin/bash
# Starts the HomeComputer in MAME. Rebuilds the driver and the firmware first,
# but only when their sources are newer than the last build. If both are
# up to date, MAME starts immediately.
#
# The MAME source checkout lives in mame/ at the repo root (gitignored).
# That is the default. Pass another directory, or set MAME_DIR, to use a
# checkout elsewhere. The driver sources live in mame-extensions/. This
# script copies them into the checkout and builds when the binary is
# missing or those sources differ.
#
# Usage:
#   scripts/run-mame.sh [extra mame args...]
#   scripts/run-mame.sh /other/mame [extra mame args...]
#   MAME_DIR=/other/mame scripts/run-mame.sh
#
# Extra args are passed straight through to MAME, e.g.:
#   scripts/run-mame.sh -video none -sound none -seconds_to_run 5
#
# Runs windowed (-window) by default, not fullscreen - fullscreen mode has been seen to not
# grab keyboard focus reliably on some window managers, which then looks like "the keyboard
# doesn't work". Pass -nowindow (or your own -window/-nowindow) to override.
#
# The emulated screen is only 240x36 pixels (4x40 character LCD), so MAME's default windowed
# size would end up far wider than tall; -resolution below instead picks a fixed initial size
# at 1920px wide, matching the case+keyboard artwork view's 1120x640 aspect ratio (see
# mame-extensions/src/layout/homecomputer6502.lay). Pass your own -resolution WxH to override.
#
# -nofilter disables MAME's default bilinear smoothing of that low native resolution: without
# it, the dot-matrix LCD text looks blurry once scaled up into the case artwork. With it, each
# source pixel of the HD44780 dot pattern stays crisp instead of blending into its neighbors.
# Pass your own -filter to override.
#
# If keys still don't reach the emulated keyboard: click into the MAME window first (it needs
# focus like any other window - actually clicking, not just Alt-Tabbing to it, since SDL's
# input focus here only kicks in once the pointer has actually entered the window), and make
# sure Scroll Lock is off - MAME uses it by default to toggle between the emulated machine and
# MAME's own UI, and while toggled to the UI side the emulated keyboard is unreachable.
#
# SDL_VIDEODRIVER=x11 is forced below. On a Wayland desktop, SDL2 otherwise defaults to its
# native Wayland backend, and in testing that produced a window whose keyboard input never
# reached the emulation at all (confirmed with synthetic X11 key events + driver-side logging:
# forcing x11 fixed it, the native Wayland path did not, even with correct window focus). Unset
# SDL_VIDEODRIVER (or export a different value) before calling this script to try another backend.

set -euo pipefail

export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-x11}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" && -d "${1:-}" ]]; then
	MAME_DIR="$1"
	shift
fi
MAME_DIR="${MAME_DIR:-$HERE/mame}"
if [[ ! -f "$MAME_DIR/makefile" ]]; then
	echo "error: $MAME_DIR has no makefile. Pass a MAME source checkout." >&2
	exit 1
fi

MAME_BIN="$MAME_DIR/mamehomecomputer6502"

# Driver sources in this repo, and where install.sh copies them.
declare -a DRIVER_SRC=(
	"$HERE/mame-extensions/src/homecomputer6502/homecomputer6502.cpp"
	"$HERE/mame-extensions/src/homecomputer6502.lst"
	"$HERE/mame-extensions/src/layout/homecomputer6502.lay"
	"$HERE/mame-extensions/scripts/target/mame/homecomputer6502.lua"
)
declare -a DRIVER_DST=(
	"$MAME_DIR/src/mame/homecomputer6502/homecomputer6502.cpp"
	"$MAME_DIR/src/mame/homecomputer6502.lst"
	"$MAME_DIR/src/mame/layout/homecomputer6502.lay"
	"$MAME_DIR/scripts/target/mame/homecomputer6502.lua"
)

CONTENT_STALE=0
for i in "${!DRIVER_SRC[@]}"; do
	if [[ ! -f "${DRIVER_DST[$i]}" ]] || ! cmp -s "${DRIVER_SRC[$i]}" "${DRIVER_DST[$i]}"; then
		CONTENT_STALE=1
		break
	fi
done

FONT_CPP="$MAME_DIR/src/devices/video/hd44780.cpp"
if [[ -f "$FONT_CPP" ]] && grep -q 'CRC(8494cb6b)' "$FONT_CPP"; then
	CONTENT_STALE=1
fi
RS232_CPP="$MAME_DIR/src/devices/bus/rs232/rs232.cpp"
if [[ -f "$RS232_CPP" ]] && grep -q 'option_add("mockingboard"' "$RS232_CPP"; then
	CONTENT_STALE=1
fi
if [[ "$CONTENT_STALE" -eq 1 ]]; then
	echo "Installing MAME driver into $MAME_DIR..."
	"$HERE/mame-extensions/install.sh" "$MAME_DIR"
fi
if [[ "$CONTENT_STALE" -eq 1 || ! -x "$MAME_BIN" ]]; then
	echo "Building MAME (SUBTARGET=homecomputer6502)..."
	# Lua file list changes (RS232 sources, etc.) are invisible to make unless
	# the project files are regenerated.
	regen=()
	if [[ "$CONTENT_STALE" -eq 1 ]]; then
		regen=(REGENIE=1)
	fi
	make -C "$MAME_DIR" SUBTARGET=homecomputer6502 "${regen[@]}" -j"$(nproc)"
fi

# Firmware in src/. make -q is silent when the image is already current.
export CC65_HOME="${CC65_HOME:-/opt/cc65}"
export PATH="$CC65_HOME/bin:$PATH"
if ! make -C "$HERE/src" -q all; then
	echo "Building firmware..."
	make -C "$HERE/src"
fi

ROM_DIR="$HERE/mame-extensions/roms/homecomputer6502"
mkdir -p "$ROM_DIR"
if [[ ! -f "$ROM_DIR/firmware.bin" ]] || ! cmp -s "$HERE/build/firmware.bin" "$ROM_DIR/firmware.bin"; then
	cp "$HERE/build/firmware.bin" "$ROM_DIR/firmware.bin"
fi

# PipeWire's own default sink on this machine is the Jabra headset, while the
# desktop default (the output other programs actually play on) is the USB sound
# card. MAME's pipewire backend follows the former, so the SID is inaudible.
# The pulse backend follows the desktop default. A later -sound on the command
# line still overrides this.
echo "Starting MAME..."
exec "$MAME_BIN" -rompath "$HERE/mame-extensions/roms" homecomputer6502 -window -resolution 1920x1097 -nofilter -sound pulse "$@"
