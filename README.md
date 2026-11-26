# j2k-aarch64-perf-lab

Public measurement lab for the FFmpeg JPEG 2000 AArch64 SIMD work.

## The question

The `jpeg2000-aarch64-neon` branch adds NEON versions of the inverse ICT
(9/7 float) and RCT (5/3 integer) multi-component transforms, plus checkasm
coverage for partial vector sizes. On an Apple M1 Pro it is correct and
bit-exact, but full-decode performance is neutral (CPU 0.994x to 1.004x).

This lab separates two effects on non-Apple AArch64 hardware:

1. Is the NEON kernel faster than C when the data is hot in cache (checkasm)?
2. Does that translate into full-decode time (memory-bound pipeline)?

If (1) is a win and (2) is not, the bottleneck is memory traffic and the next
step is fusion or a different hot loop. If (1) is also neutral, the kernel
itself needs work.

A local `sample` profile of the 240-frame DCI 4K corpus on an M1 Pro puts
`ff_dwt_decode` at roughly 68% of active CPU, tier-1/MQ at roughly 16%,
inlined dequant plus `write_frame` at roughly 16%, and `ff_ict_float_neon` at
roughly 0.5%. That is the reason a faster MCT kernel cannot move full-decode
time much: the pass is a small share to begin with.

## Contents

- `patches/aarch64-neon.patch`: the two-commit series (checkasm test plus
  NEON ICT/RCT).
- `patches/checkasm-mct-sizes.patch`: the standalone test-only commit.
- `samples/dci4k-24f.j2kpipe`: 24 frames of 4096x1714 XYZ 12-bit DCI 4K,
  extracted losslessly from the local corpus.
- `scripts/build.sh`: builds stock and patched FFmpeg at a pinned revision.
- `scripts/checkasm.sh`: runs the `jpeg2000dsp` checkasm benchmark.
- `scripts/bench.sh`: interleaved decode benchmark, default versus
  `-cpuflags 0`, so the same binary is compared with and without NEON.

## Pinned revision

FFmpeg `94cafa1805620244885192f3d9d020e2a425099d`.

## Run locally

```sh
./scripts/build.sh
RUNS=5 ./scripts/checkasm.sh
THREADS=1 ROUNDS=7 ./scripts/bench.sh
THREADS=4 ROUNDS=7 ./scripts/bench.sh
```

The first build clones FFmpeg and creates two worktrees under `work/`.
Re-running `build.sh` is incremental.

## Reading the numbers

`checkasm` reports a per-function ratio. Above 1.0 means the NEON kernel is
faster with hot data. `bench.sh` reports `rtime`, `utime`, and `stime` from
FFmpeg's `-benchmark`. The `neon` build in `default` mode uses NEON; the same
build in `c` mode runs with `-cpuflags 0` and selects the C fallback.

The meaningful comparison is `neon/default` versus `neon/c`. The `stock`
build is a control for patch regressions and machine noise.

## License

The patches are FFmpeg patches and carry FFmpeg's LGPL license headers. The
sample is derived from local test content and is included only for
benchmarking.
