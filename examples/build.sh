#!/bin/bash
# Assemble every *.s65 here into a .prg (load address, BASIC stub, code).
set -euo pipefail
cd "$(dirname "$0")"
CC65_HOME="${CC65_HOME:-/opt/cc65}"
export PATH="${CC65_HOME}/bin:${PATH}"
shopt -s nullglob
found=0
for src in *.s65; do
  found=1
  base="${src%.s65}"
  ca65 --cpu 6502 -o "${base}.o" "${src}"
  ld65 -C prg.cfg -o "${base}.prg" "${base}.o"
  rm -f "${base}.o"
  echo "${base}.prg"
done
if [[ "${found}" -eq 0 ]]; then
  echo "no .s65 files" >&2
  exit 1
fi
