#!/bin/bash
# usage: cmp.sh "<shops list>"   e.g. "" or "cafe" or "cafe,flower,books"
cd /Users/ernest.lee/.hermes/cache/scratch/ess-shopsA-oracle && SHOPS_ONLY="$1" timeout 300 node tools/detail.mjs > /tmp/o.txt 2>&1
cd /Users/ernest.lee/.hermes/cache/scratch/ess-shopsA && SHOPS_ONLY="$1" timeout 400 nice -n 10 ../engine/src/bin/godot.macos.editor.double.arm64 --path . --windowed --resolution 320x180 --xr-mode off --script tools/_shopsA_detail.gd > /tmp/g.log 2>&1
grep -E "SCRIPT ERROR|Parse Error" -A2 /tmp/g.log | head -20
grep -E "^(plain|groups|inst|colliders|total)" /tmp/g.log > /tmp/g.txt
diff /tmp/o.txt /tmp/g.txt && echo SAME
