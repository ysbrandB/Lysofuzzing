#!/bin/bash

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
# - env TARGET: path to target work dir
# - env OUT: path to directory where artifacts are stored
# - env SHARED: path to directory shared with host (to store results)
# - env PROGRAM: name of program to run (should be found in $OUT)
# - env ARGS: extra arguments to pass to the program
# - env FUZZARGS: extra arguments to pass to the fuzzer
##

if nm "$OUT/afl/$PROGRAM" | grep -E '^[0-9a-f]+\s+[Ww]\s+main$'; then
    ARGS="-"
fi

mkdir -p "$SHARED/findings"

flag_cmplog=(-m none -c 0)

export AFL_SKIP_CPUFREQ=1
export AFL_NO_AFFINITY=1
export AFL_NO_UI=1
export AFL_DRIVER_DONT_DEFER=1

# --- QEMU PERSISTENT MODE CONFIGURATION ---
#TARGET_ADDR=$(nm "$OUT/afl/$PROGRAM" | grep "T LLVMFuzzerTestOneInput" | awk '{print $1}')
#export AFL_QEMU_PERSISTENT_ADDR="0x$TARGET_ADDR"
#export AFL_QEMU_PERSISTENT_HOOK="$OUT/afl/read_into_rdi.so"
#export AFL_QEMU_PERSISTENT_HOOK="$FUZZER/repo/utils/aflpp_driver/aflpp_qemu_driver_hook.so"
# ------------------------------------------

echo "Launching AFL++ Master on Core 1..."
"$FUZZER/repo/afl-fuzz" -M master -Q -i "$TARGET/corpus/$PROGRAM" -o "$SHARED/findings" \
    "${flag_cmplog[@]}" -d \
    $FUZZARGS -- "$OUT/afl/$PROGRAM" $ARGS > "$SHARED/master.log" 2>&1 &

echo "Launching AFL++ Slave on Core 2..."
"$FUZZER/repo/afl-fuzz" -S slave1 -Q -i "$TARGET/corpus/$PROGRAM" -o "$SHARED/findings" \
    "${flag_cmplog[@]}" -d \
    $FUZZARGS -- "$OUT/afl/$PROGRAM" $ARGS 2>&1
