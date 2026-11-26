#!/usr/bin/env bash
# Run the jpeg2000dsp checkasm test several times.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUNS=${RUNS:-5}
BIN=${BIN:-$ROOT/work/neon/tests/checkasm/checkasm}
EXTRA=()

if [ "${BENCH:-0}" = "1" ]; then
    EXTRA+=(--bench)
fi

if [ ! -x "$BIN" ]; then
    echo "missing $BIN; run scripts/build.sh first" >&2
    exit 1
fi

for i in $(seq 1 "$RUNS"); do
    echo "== checkasm run $i/$RUNS"
    "$BIN" --test=jpeg2000dsp "${EXTRA[@]}"
done
