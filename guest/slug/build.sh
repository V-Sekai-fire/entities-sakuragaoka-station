#!/usr/bin/env bash
# Build slug.elf (guest/slug) for the RISC-V sandbox and drop it at the port root (res://slug.elf),
# next to slug.elf.uid. Modelled on 1-transport/meshing-pen/build.sh.
#
#   ./build.sh                      # configure (once) + build slug.elf
#   RISCV64_SYSROOT=... ./build.sh
#   NATIVE=1 ./build.sh             # the host harness instead (build-native/slug_native)
#
# Needs: cmake, ninja, a clang++ with a riscv64 target (auto-located if the bare clang++ is
# mingw-only), the riscv64 glibc sysroot (5-repository/riscv64-sysroot: toolchain.cmake +
# sysroot/), and slughorn at 3-interactor/slughorn on branch feat/thorvg with its submodules.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEFT="${WEFT_ROOT:-$(cd "$HERE/../../../.." && pwd)}"
SYSROOT="${RISCV64_SYSROOT:-$WEFT/5-repository/riscv64-sysroot}"

NINJA="$(command -v ninja || true)"
[ -n "$NINJA" ] || NINJA="$HOME/.pixi/bin/ninja.exe"
[ -x "$NINJA" ] || { echo "error: ninja not found" >&2; exit 1; }

if [ "${NATIVE:-0}" = 1 ]; then
	BUILD="${BUILD_DIR:-$HERE/build-native}"
	if [ ! -f "$BUILD/build.ninja" ]; then
		cmake -S "$HERE" -B "$BUILD" -G Ninja -DCMAKE_MAKE_PROGRAM="$NINJA" -DCMAKE_BUILD_TYPE=Release \
			-DWEFT_ROOT="$WEFT" ${NATIVE_CXX:+-DCMAKE_CXX_COMPILER="$NATIVE_CXX" -DCMAKE_C_COMPILER="${NATIVE_CC:-$NATIVE_CXX}"}
	fi
	cmake --build "$BUILD" --target slug_native -- -j "${BUILD_JOBS:-8}"
	exit 0
fi

BUILD="${BUILD_DIR:-$HERE/build}"

if [ ! -f "$SYSROOT/toolchain.cmake" ]; then
	echo "error: no toolchain.cmake under RISCV64_SYSROOT=$SYSROOT" >&2
	exit 1
fi

# The toolchain file invokes a bare clang++, so a riscv64-capable one must resolve first on PATH.
has_riscv() { "$1" --print-targets 2>/dev/null | grep -qi riscv64; }
if ! { command -v clang++ >/dev/null 2>&1 && has_riscv clang++; }; then
	FOUND=""
	for c in "$HOME/scoop/apps/llvm/current/bin/clang++" "/c/Program Files/LLVM/bin/clang++"; do
		if [ -x "$c" ] && has_riscv "$c"; then FOUND="$c"; break; fi
	done
	if [ -z "$FOUND" ]; then
		echo "error: no clang++ with a riscv64 target found (a mingw-only clang will not do)" >&2
		exit 1
	fi
	export PATH="$(dirname "$FOUND"):$PATH"
fi

TOOLCHAIN="$(cygpath -m "$SYSROOT/toolchain.cmake" 2>/dev/null || echo "$SYSROOT/toolchain.cmake")"

if [ ! -f "$BUILD/build.ninja" ]; then
	# rv64gc: no V extension (it traps on the Linux addon; the ELF does not need it).
	cmake -S "$HERE" -B "$BUILD" -G Ninja \
		-DWEFT_ROOT="$WEFT" \
		-DCMAKE_MAKE_PROGRAM="$NINJA" \
		-DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
		-DCMAKE_BUILD_TYPE=Release \
		-DSANDBOX_RISCV_EXT_V=OFF \
		-DSANDBOX_RISCV_EXT_C=ON
fi
cmake --build "$BUILD" --target slug -- -j "${BUILD_JOBS:-8}"
ls -la "$HERE/../../slug.elf"
