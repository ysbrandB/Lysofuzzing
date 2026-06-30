#!/bin/bash
set -e

##
# Pre-requirements:
# - env FUZZER: path to fuzzer work dir
# - env TARGET: path to target work dir
# - env MAGMA: path to Magma support files
# - env OUT: path to directory where artifacts are stored
# - env CFLAGS and CXXFLAGS must be set to link against Magma instrumentation
##
get_target() {
    cd $OUT
    source "$TARGET/configrc"
    for p in "${PROGRAMS[@]}"; do (
        folder=$OUT/tmp-$p
        if [ ! -d $folder ]; then
             mkdir $folder
        fi
        DRIVER=$(basename "$TARGET")
        if [[ -d "$FUZZER/targets/$DRIVER" ]]; then
              cp -r "$FUZZER/targets/$DRIVER/BBtargets.txt" "$folder/BBtargets.txt"
        fi
    )
    echo "copy the target to tmp file"
    done
}

export CC="clang"
export CXX="clang++"
export AS="llvm-as"

#export LIBS="$LIBS -lc++ -lc++abi $FUZZER/repo/utils/aflpp_driver/libAFLDriver.a"
export LIBS="$LIBS -lc++ -lc++abi $FUZZER/repo/utils/aflpp_driver/libAFLQemuDriver.a"

# AFL++'s driver is compiled against libc++
export CXXFLAGS="$CXXFLAGS -stdlib=libc++"

# Build the AFL-only instrumented version
(
    AFL_DONT_OPTIMIZE=1
    export OUT="$OUT/afl"
    export LDFLAGS="-no-pie $LDFLAGS -L$OUT"
    export CFLAGS="-g -O0 $CFLAGS"
    export CXXFLAGS="-g -O0 $CXXFLAGS"
    "$MAGMA/build.sh"
    "$TARGET/build.sh"
)

get_target
# NOTE: We pass $OUT directly to the target build.sh script, since the artifact
#       itself is the fuzz target. In the case of Angora, we might need to
#       replace $OUT by $OUT/fast and $OUT/track, for instance.