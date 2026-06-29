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

BIN="$OUT/afl/$PROGRAM"
if nm "$BIN" | grep -E '^[0-9a-f]+\s+[Ww]\s+main$'; then
    ARGS="-"
fi

echo "[+] Binary: $BIN"

mkdir -p "$SHARED/bin"
cp "$BIN" "$SHARED/bin"

## 1. Process the target file
BB_FILE="$OUT/tmp-$PROGRAM/BBtargets.txt"

if [[ ! -f "$BB_FILE" ]]; then
    echo "[-] Error: BB target file not found: $BB_FILE"
    exit 1
fi

# 2. Loop through all lines in BBtargets.txt and accumulate ranges
echo "[*] Calculating dominator ranges via angr for all targets..."
ALL_RANGES=()

while IFS= read -r line || [[ -n "$line" ]]; do
    # Clean carriage returns (\r) from the line
    TARGET_ADDR=$(echo "$line" | tr -d '\r')

    # Skip empty lines
    [[ -z "$TARGET_ADDR" ]] && continue

    echo "[+] Processing target address: $TARGET_ADDR"
    RANGES_STR=$(python3 "$FUZZER/cfg.py" "$BIN" --target "$TARGET_ADDR")

    # Check if python script failed or threw an error
    if [[ $? -ne 0 || -z "$RANGES_STR" || "$RANGES_STR" == *"Error"* ]]; then
        echo "[-] Warning: Failed to calculate ranges for $TARGET_ADDR. Skipping."
        continue
    fi

    ALL_RANGES+=("$RANGES_STR")
done < "$BB_FILE"

# Join all collected ranges into a single comma-separated string
COMBINED_RANGES=$(IFS=,; echo "${ALL_RANGES[*]}")

if [[ -z "$COMBINED_RANGES" ]]; then
    echo "[-] Critical Error: No valid instrumentation ranges were calculated!"
    exit 1
fi

echo "[+] Combined target ranges: $COMBINED_RANGES"

# Save it to a file for tracking/debugging purposes
echo "$COMBINED_RANGES" > "$OUT/afl/qemu_ranges"

mkdir -p "$SHARED/findings"
flag_cmplog=(-m none -c 0)

export AFL_SKIP_CPUFREQ=1
export AFL_NO_AFFINITY=1
export AFL_NO_UI=1
export AFL_DRIVER_DONT_DEFER=1

# --- QEMU PERSISTENT MODE CONFIGURATION ---
# (Uncomment and adjust these if domfuzz relies on in-memory persistent fuzzing loops)
#TARGET_ADDR=$(nm "$OUT/afl/$PROGRAM" | grep "T LLVMFuzzerTestOneInput" | awk '{print $1}')
#export AFL_QEMU_PERSISTENT_ADDR="0x$TARGET_ADDR"
#export AFL_QEMU_PERSISTENT_HOOK="$FUZZER/repo/utils/aflpp_driver/aflpp_qemu_driver_hook.so"
# ------------------------------------------

# 4. Launching the Master fuzzer process (Backgrounded, output redirected)
(
  # AFL++ QEMU checks this variable to restrict coverage tracing to these specific blocks
  export AFL_QEMU_INST_RANGES="$COMBINED_RANGES"
  echo "Launching AFL++ Master on Core 1..."
  "$FUZZER/repo/afl-fuzz" -M master -Q -i "$TARGET/corpus/$PROGRAM" -o "$SHARED/findings" \
    "${flag_cmplog[@]}" -d \
    $FUZZARGS -- "$BIN" $ARGS > "$SHARED/master.log" 2>&1 &
)
# Give the master a brief window to create the shared memory structures
sleep 2

# 5. Launching the Slave fuzzer process
# Backgrounded as well, so your script doesn't indefinitely hang on foreground execution
echo "Launching AFL++ Slave on Core 2..."
"$FUZZER/repo/afl-fuzz" -S slave1 -Q -i "$TARGET/corpus/$PROGRAM" -o "$SHARED/findings" \
    "${flag_cmplog[@]}" -d \
    $FUZZARGS -- "$BIN" $ARGS > "$SHARED/slave1.log" 2>&1 &

echo "[+] Fuzzing campaign initiated successfully."
echo "[*] Tracking master status via: tail -f $SHARED/master.log"

# Keep script alive if running inside an interactive container lifecycle tracking mechanism
wait