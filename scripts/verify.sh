#!/usr/bin/env bash
# Verify that the patched trees are bit-exact with stock and pass checkasm.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SAMPLE=${SAMPLE:-$ROOT/samples/dci4k-24f.j2kpipe}
OUT=${OUT:-$ROOT/results}

sha() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1"
    else
        shasum -a 256 "$1"
    fi
}

mkdir -p "$OUT"

for build in stock neon min fused; do
    bin="$ROOT/work/$build/ffmpeg"

    if [ ! -x "$bin" ]; then
        echo "missing $bin; run scripts/build.sh first" >&2
        exit 1
    fi

    "$bin" -hide_banner -nostdin -threads 1 \
        -f image2pipe -c:v jpeg2000 -i "$SAMPLE" -f framemd5 - \
        2>/dev/null | grep -v '^#' > "$OUT/$build.md5"

    echo "$build: $(sha "$OUT/$build.md5" | cut -d' ' -f1) ($(wc -l < "$OUT/$build.md5") frames)"
done

cmp "$OUT/stock.md5" "$OUT/neon.md5"
cmp "$OUT/stock.md5" "$OUT/min.md5"
cmp "$OUT/stock.md5" "$OUT/fused.md5"
echo "bit-exact: stock == neon == min == fused"

for build in neon min fused; do
    "$ROOT/work/$build/tests/checkasm/checkasm" --test=jpeg2000dsp
    echo "checkasm passed: $build"
done
