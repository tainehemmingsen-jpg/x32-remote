#!/bin/bash
# Builds Patrick-Gilles Maillot's X32 emulator (GPL, fetched at CI time, not shipped) for integration tests.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
cd "$ROOT/build"
if [ ! -d X32-Behringer ]; then
  git clone --depth 1 https://github.com/pmaillot/X32-Behringer.git
fi
cd X32-Behringer/X32lib
for f in *.c; do cc -O1 -w -c "$f" -o "${f%.c}.o"; done
ar rcs libX32.a ./*.o
cd ..
cc -O1 -w -IX32lib -o X32emu X32.c -LX32lib -lX32 -lm
echo "emulator built: $ROOT/build/X32-Behringer/X32emu"
