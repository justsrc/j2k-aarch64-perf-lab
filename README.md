# j2k-aarch64-perf-lab

Public build and correctness lab for the FFmpeg JPEG 2000 AArch64 work, plus
the scripts used for authoritative local timing.

## What this lab is for

Shared CI runners are good at building, linking and running correctness tests
on several operating systems and compilers. They are not a quiet machine:
scheduling, frequency scaling and noisy neighbours move decode times by
several percent. So this lab splits the two jobs:

- **CI** builds stock, NEON-MCT and fused trees at a pinned FFmpeg revision,
  runs `checkasm`, and compares decoded `framemd5` against stock. A patch that
  is not bit-exact fails the job.
- **Local** runs the interleaved A/B timing on a quiet machine. Those are the
  numbers used to decide whether something is worth submitting.

CI also publishes `checkasm --bench` output. Treat it as a kernel-level sanity
check, not as a decode-time result.

## Result so far

The NEON inverse ICT/RCT series is correct and bit-exact, but full-decode
performance is neutral: on an M1 Pro the pass is about 0.5% of active CPU, and
three 4096x1714 float planes are far larger than cache, so the kernel is
DRAM-bound. `checkasm` with hot 6 KiB buffers shows the kernel is fast; the
full decoder does not care.

The useful change is to stop materialising the three MCT planes and instead
apply the inverse ICT while writing the packed output frame. The gain comes
from removing one full read and one full write of the three component planes
per frame and from replacing scalar `lrintf`/`av_clip` plus three strided
stores with one NEON `fcvtns`/clip/`st3` pass.

On top of the DWT+tier-1 tree, 240-frame 4096x1714 XYZ 12-bit corpus,
interleaved on an M1 Pro:

| threads | tree | real (s) | CPU (s) | speedup |
|--------:|------|---------:|--------:|--------:|
| 1 | DWT + tier-1 | 38.209 | 38.161 | 1.000x |
| 1 | DWT + tier-1 + fused output | 35.476 | 35.421 | **1.077x wall, 1.077x CPU** |
| 8 | DWT + tier-1 | 5.948 | 43.887 | 1.000x |
| 8 | DWT + tier-1 + fused output | 5.609 | 41.018 | **1.060x wall, 1.070x CPU** |

The minimal series (`0001` + `0002`) on clean FFmpeg, 24-frame sample, same
machine, against stock at the same pinned revision:

| threads | tree | real (s) | CPU (s) | speedup |
|--------:|------|---------:|--------:|--------:|
| 1 | stock | 10.662 | 10.637 | 1.000x |
| 1 | packed writer + fused ICT | 10.232 | 10.222 | **1.042x wall, 1.041x CPU** |
| 8 | stock | 2.076 | 13.807 | 1.000x |
| 8 | packed writer + fused ICT | 2.002 | 13.460 | **1.037x wall, 1.026x CPU** |

The full 240-frame `framemd5` is identical across stock, the minimal series
and the full fused tree.

## CI runners

The workflow uses the current GitHub-hosted AArch64 images:

- `ubuntu-24.04-arm` and `ubuntu-26.04-arm` (GCC; Clang on 26.04)
- `macos-26` (Xcode 26.x)
- `xcode-27` (public preview image: macOS 26 with Xcode 27)

`macos-15` is intentionally not used. `macos-14` was retired on 2026-11-02.

## Contents

- `patches/0001-packed-writer.patch`: packed 16-bit output in one pass
  (upstreamable refactor).
- `patches/0002-fused-mct-write.patch`: inverse ICT fused into that writer
  (upstreamable on top of 0001).
- `patches/aarch64-neon.patch`: NEON ICT/RCT plus checkasm coverage.
- `patches/checkasm-mct-sizes.patch`: standalone test-only checkasm commit.
- `patches/combined-fused.patch`: the full experimental tree used for the
  fused measurement (DWT blocking, tier-1 rewrite, NEON MCT, fused packed
  output). This is a lab bundle, not a proposed upstream series.
- `samples/dci4k-24f.j2kpipe`: 24 frames of 4096x1714 XYZ 12-bit DCI 4K,
  extracted losslessly from the local corpus.
- `scripts/build.sh`: builds stock, NEON-only, minimal-fusion and full-fusion
  trees.
- `scripts/verify.sh`: checkasm plus `framemd5` equality against stock.
- `scripts/checkasm.sh`: runs the `jpeg2000dsp` checkasm test (`BENCH=1` adds
  `--bench`).
- `scripts/bench.sh`: interleaved decode benchmark for the stock and NEON
  trees, default versus `-cpuflags 0`.
- `scripts/bench-local.sh`: interleaved A/B timing for any two already-built
  binaries. Use this for numbers.

## Pinned revision

FFmpeg `94cafa1805620244885192f3d9d020e2a425099d`.

## Run locally

Builds are cheapest on CI; locally you normally only need the timing script
and binaries you already have:

```sh
A=/path/to/fused/ffmpeg \
B=/path/to/stock/ffmpeg \
SAMPLE=samples/dci4k-24f.j2kpipe \
THREADS=1 ROUNDS=7 ./scripts/bench-local.sh
```

To build and verify everything from scratch:

```sh
./scripts/build.sh
./scripts/verify.sh
```

The first build clones FFmpeg and creates three worktrees under `work/`.
Re-running `build.sh` is incremental.

## Reading the numbers

`checkasm` reports a per-function ratio. Above 1.0 means the patched kernel is
faster with hot data. `bench-local.sh` reports median `rtime`, median CPU time
(`utime + stime`) and the minimum `rtime`, plus the A/B ratio. Alternate the
two binaries every round, as the script does, so thermal drift and background
load hit both equally.

A full-decode win needs both a hot-cache kernel win and a reduction in memory
traffic. The MCT kernel has the first and not the second; the fused writer has
both.

## License

The patches are FFmpeg patches and carry FFmpeg's LGPL license headers. The
sample is derived from local test content and is included only for
benchmarking.
