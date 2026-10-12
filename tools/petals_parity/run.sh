#!/bin/sh
# run module_check against a reference file/build: run.sh <ref.json> <build> <log>
cd /Users/ernest.lee/.hermes/cache/scratch/ess-petals
nice -n 10 timeout 400 ../engine/src/bin/godot.macos.editor.double.arm64 --path . --windowed --resolution 320x180 --xr-mode off --script tools/module_check.gd -- "$1" "$2" > "$3" 2>&1
echo "exit $?" >> "$3"
