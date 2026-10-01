#!/bin/sh
# Builds the lighting lab's fixer against contract-lbfgsb's L-BFGS-B driver on its CPU backend,
# from the goal manifest's sibling checkouts.
#   tools/lighting_fit/build.sh <out>
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WEFT=${WEFT_ROOT:-$(cd "$HERE/../../../.." && pwd)}
LB="$WEFT/2-contract/lbfgsb"
c++ -O2 -std=c++17 -ffp-contract=off -pthread -Wall -Wno-unused-function \
  -I"$LB/guest/drape" -I"$WEFT/2-contract/guest-runtime/guest/avbd/slang-rt" \
  "$HERE/fit.cpp" "$LB/guest/drape/lbfgsb.cpp" "$LB/guest/drape/vec_cpu.cpp" -o "${1:?usage: build.sh <out>}"
