#!/usr/bin/env bash
# Interleaved decode benchmark: stock vs patched, NEON vs C.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SAMPLE=${SAMPLE:-$ROOT/samples/dci4k-24f.j2kpipe}
ROUNDS=${ROUNDS:-7}
THREADS=${THREADS:-4}
BUILDS=${BUILDS:-"stock neon"}
OUT=${OUT:-$ROOT/results/bench-$(date +%Y%m%d-%H%M%S)-${THREADS}t.tsv}

mkdir -p "$(dirname "$OUT")"
printf 'round\tbuild\tmode\treal\tuser\tsys\n' > "$OUT"

parse_bench() {
    awk '
        /^bench: utime=/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^utime=/) { u = $i; sub("utime=", "", u); sub("s$", "", u) }
                if ($i ~ /^stime=/) { s = $i; sub("stime=", "", s); sub("s$", "", s) }
                if ($i ~ /^rtime=/) { r = $i; sub("rtime=", "", r); sub("s$", "", r) }
            }
            printf "%s\t%s\t%s\n", r, u, s
        }
    ' "$1" | tail -1
}

run_one() {
    local build=$1 mode=$2 round=$3
    local bin="$ROOT/work/$build/ffmpeg"
    local log="$OUT.$build.$mode.$round.log"
    local -a extra=()

    if [ "$mode" = "c" ]; then
        extra=(-cpuflags 0)
    fi

    "$bin" -hide_banner -nostdin -benchmark -threads "$THREADS" "${extra[@]}" \
        -f image2pipe -c:v jpeg2000 -i "$SAMPLE" -f null - \
        >/dev/null 2>"$log"

    local row
    row=$(parse_bench "$log")
    printf '%s\t%s\t%s\t%s\n' "$round" "$build" "$mode" "$row" >> "$OUT"
    rm -f "$log"
}

# Warmup, one pass per configuration.
for build in $BUILDS; do
    for mode in default c; do
        if [ "$build" = "stock" ] && [ "$mode" = "c" ]; then
            continue
        fi
        run_one "$build" "$mode" 0
    done
done

for round in $(seq 1 "$ROUNDS"); do
    for build in $BUILDS; do
        for mode in default c; do
            if [ "$build" = "stock" ] && [ "$mode" = "c" ]; then
                continue
            fi
            run_one "$build" "$mode" "$round"
            echo "round $round/$ROUNDS $build/$mode" >&2
        done
    done
done

echo
echo "raw results: $OUT"
awk -F'\t' '
    NR > 1 && $1 > 0 {
        key = $2 "/" $3
        n[key]++
        r[key] += $4
        u[key] += $5
        s[key] += $6
    }
    END {
        printf "%-16s %8s %10s %10s %10s\n", "config", "n", "real", "user", "sys"
        for (k in n) {
            printf "%-16s %8d %10.3f %10.3f %10.3f\n", k, n[k], r[k]/n[k], u[k]/n[k], s[k]/n[k]
        }
    }
' "$OUT" | sort
