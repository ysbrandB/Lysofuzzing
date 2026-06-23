#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
##

if [ ! -d "$FUZZER/repo" ]; then
    echo "fetch.sh must be executed first."
    exit 1
fi

cd "$FUZZER/repo"
export CC=clang
export CXX=clang++
export AFL_NO_X86=1
export PYTHON_INCLUDE=/
make -j$(nproc) || exit 1
(cd qemu_mode && ./build_qemu_support.sh)
make -C utils/aflpp_driver || exit 1
mkdir -p "$OUT/afl"
mkdir -p "$OUT/cmplog"
cp "$FUZZER/repo/utils/aflpp_driver/aflpp_qemu_driver_hook.so" "$OUT/afl/"