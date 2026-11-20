#!/bin/sh
# Build (if needed) and launch DrawingPad.
cd "$(dirname "$0")"
if [ ! -x DrawingPad ] || [ main.swift -nt DrawingPad ]; then
  swiftc -O main.swift -o DrawingPad || exit 1
fi
./DrawingPad
