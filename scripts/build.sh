#!/usr/bin/env bash
# Build stock and patched FFmpeg at a pinned revision.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REV=${FFMPEG_REV:-94cafa1805620244885192f3d9d020e2a425099d}
SRC=${FFMPEG_SRC:-$ROOT/.ffmpeg-src}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}

CFG=(
    --disable-everything
    --disable-autodetect
    --disable-doc
    --disable-network
    --disable-stripping
    --disable-x86asm
    --enable-decoder=jpeg2000
    --enable-parser=jpeg2000
    --enable-demuxer=image2pipe
    --enable-demuxer=image_j2k_pipe
    --enable-muxer=null
    --enable-encoder=wrapped_avframe
    --enable-protocol=file
    --enable-protocol=pipe
    --enable-checkasm
    --extra-cflags="-O3 -g"
)

if [ ! -d "$SRC/.git" ]; then
    mkdir -p "$SRC"
    git -C "$SRC" init -q
    git -C "$SRC" remote add origin https://github.com/FFmpeg/FFmpeg.git
    git -C "$SRC" fetch --depth=1 origin "$REV"
    git -C "$SRC" checkout -q FETCH_HEAD
fi

build_one() {
    local name=$1
    shift
    local dir="$ROOT/work/$name"

    if [ ! -d "$dir" ]; then
        git -C "$SRC" worktree add --detach "$dir" "$REV"
    fi

    (
        cd "$dir"
        for patch in "$@"; do
            if git apply --check "$patch" 2>/dev/null; then
                git apply "$patch"
            fi
        done
        if [ ! -f config.h ]; then
            ./configure "${CFG[@]}"
        fi
        make -j"$JOBS" ffmpeg tests/checkasm/checkasm
    )
}

mkdir -p "$ROOT/work"
build_one stock
build_one neon "$ROOT/patches/aarch64-neon.patch"
