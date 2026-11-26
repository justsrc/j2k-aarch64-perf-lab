#!/usr/bin/env bash
# Build stock, NEON-only and fused trees at a pinned FFmpeg revision.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REV=${FFMPEG_REV:-94cafa1805620244885192f3d9d020e2a425099d}
SRC=${FFMPEG_SRC:-$ROOT/.ffmpeg-src}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}
CC=${CC:-cc}

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
    --enable-muxer=framemd5
    --enable-encoder=wrapped_avframe
    --enable-encoder=rawvideo
    --enable-protocol=file
    --enable-protocol=pipe
    --enable-checkasm
    --cc="$CC"
    --extra-cflags="-O3 -g"
)

if [ ! -d "$SRC/.git" ]; then
    mkdir -p "$SRC"
    git -C "$SRC" init -q
    git -C "$SRC" remote add origin https://github.com/FFmpeg/FFmpeg.git
    git -C "$SRC" fetch --depth=1 origin "$REV"
    git -C "$SRC" checkout -q FETCH_HEAD
fi

apply_patch() {
    local patch=$1

    if git apply --check "$patch"; then
        git apply "$patch"
    elif git apply --reverse --check "$patch"; then
        echo "already applied: $patch"
    else
        echo "patch does not apply: $patch" >&2
        exit 1
    fi
}

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
            apply_patch "$patch"
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
build_one min "$ROOT/patches/0001-packed-writer.patch" \
              "$ROOT/patches/0002-fused-mct-write.patch"
build_one fused "$ROOT/patches/combined-fused.patch"
