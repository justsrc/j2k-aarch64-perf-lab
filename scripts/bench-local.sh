#!/usr/bin/env bash
# Interleaved A/B timing for two already-built ffmpeg binaries.
#
# CI runners are shared and noisy. Use this on a quiet machine for numbers
# that mean something. The two binaries are alternated every round so slow
# drift affects both equally.
#
# Usage:
#   A=work/fused/ffmpeg B=work/stock/ffmpeg SAMPLE=samples/dci4k-24f.j2kpipe \
#       THREADS=1 ROUNDS=7 ./scripts/bench-local.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
A=${A:?set A to the first ffmpeg binary}
B=${B:?set B to the second ffmpeg binary}
SAMPLE=${SAMPLE:-$ROOT/samples/dci4k-24f.j2kpipe}
ROUNDS=${ROUNDS:-7}
THREADS=${THREADS:-1}
OUT=${OUT:-$ROOT/results/local-$(date +%Y%m%d-%H%M%S)-${THREADS}t.tsv}

mkdir -p "$(dirname "$OUT")"
printf 'round\tbuild\treal\tuser\tsys\n' > "$OUT"

run_one() {
    local bin=$1 name=$2 round=$3
    local log="$OUT.$name.$round.log"
    local row

    "$bin" -hide_banner -nostdin -benchmark -threads "$THREADS" \
        -f image2pipe -c:v jpeg2000 -i "$SAMPLE" -f null - \
        >/dev/null 2>"$log"

    row=$(awk '
        /^bench: utime=/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^utime=/) { u = $i; sub("utime=", "", u); sub("s$", "", u) }
                if ($i ~ /^stime=/) { s = $i; sub("stime=", "", s); sub("s$", "", s) }
                if ($i ~ /^rtime=/) { r = $i; sub("rtime=", "", r); sub("s$", "", r) }
            }
            printf "%s\t%s\t%s\n", r, u, s
        }
    ' "$log" | tail -1)

    printf '%s\t%s\t%s\n' "$round" "$name" "$row" >> "$OUT"
    rm -f "$log"
}

# Warm up both binaries once.
run_one "$A" A 0
run_one "$B" B 0

for round in $(seq 1 "$ROUNDS"); do
    run_one "$A" A "$round"
    run_one "$B" B "$round"
    echo "round $round/$ROUNDS" >&2
done

echo
echo "raw results: $OUT"
python3 - "$OUT" <<'PY'
import statistics
import sys
from collections import defaultdict

rows = [line.rstrip("\n").split("\t") for line in open(sys.argv[1]) if line.strip()]
data = defaultdict(list)
for round_, name, real, user, sys_ in rows[1:]:
    if int(round_) == 0:
        continue
    data[name].append((float(real), float(user) + float(sys_)))

print(f"{'build':>5} {'n':>3} {'real_med':>9} {'cpu_med':>9} {'real_min':>9}")
for name in ("A", "B"):
    values = data[name]
    print(f"{name:>5} {len(values):>3} "
          f"{statistics.median(v[0] for v in values):>9.3f} "
          f"{statistics.median(v[1] for v in values):>9.3f} "
          f"{min(v[0] for v in values):>9.3f}")

for label, index in (("real", 0), ("cpu", 1)):
    a = statistics.median(v[index] for v in data["A"])
    b = statistics.median(v[index] for v in data["B"])
    delta = (b / a - 1) * 100
    verdict = "faster" if delta > 0 else "slower"
    print(f"{label}: A/B = {a / b:.4f}x (A is {abs(delta):.1f}% {verdict} than B)")
PY
