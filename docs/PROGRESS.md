# cta-splat progress

Goal: a CTA Red Line train-driving game whose environment is a gaussian splat built from CTA's
"Ride the Rails" cab-view videos. This file is the hand-off for picking work back up.

_Last updated: 2026-11-07._

## Where things stand

- **The pipeline works end to end** on a 20 s test clip (t01, Cermak-Chinatown, northbound):
  4K frames → COLMAP camera solve → nerfstudio `splatfacto-big` at full 4K → `.ply` → SPZ → a
  browser "cab ride" viewer with power/brake along the solved track path.
- **Two-direction test (t02)** — same stretch, northbound (sunny) + southbound (overcast), solved
  jointly with GPU COLMAP and trained with per-image colour correction (bilateral grid). Finished:
  all 320 frames in one model, viewer at `?seg=t02`. **Not yet reviewed by eye** — that's the first job.

## Source footage (`/srv/cta-splat/raw`, 50 GB, not in git)

| Video id | Line / direction | Year | Res | Length |
|---|---|---|---|---|
| BnG3O1bv_Ao | Red, to Howard (north) | 2025 | 4K30 | 1h28m |
| VoJhzwSpbg0 | Red, to 95th (south) | 2025 | 4K30 | 1h18m |
| UQ7oTzKTJpY | Red, to Howard | ~2014 | 1080p | 1h01m |
| S68x-3Qgczs | Red, to 95th | 2019 | 4K30 | 1h09m |
| tag-0WOzn7o | Purple | 2019 | 4K30 | 1h56m |
| Y8ZzlK34JcA | Purple | 2025 | 4K30 | 1h50m |

No chapters/station markers in the metadata; on-screen station captions appear at stops.
Known timestamps: Cermak-Chinatown ≈ 1495–1535 s in BnG3O1bv_Ao (northbound, greenhouse on right)
and ≈ 3105–3165 s in VoJhzwSpbg0 (southbound station stop; greenhouse on left ≈ 3194–3218 s).
The 2025 northbound day is sunny; the 2025 southbound day is overcast.
Camera: wide GoPro-style lens mounted outside the glass (no cab interior to mask). Solved lens
(OPENCV): fx≈2154, fy≈1949, cx 1920, cy 1080, k1≈−0.19, k2≈0.032. fx≠fy by ~10% suggests a
horizontally stretched capture mode (e.g. GoPro SuperView).

## Layout

- `container/Containerfile` — local prep image (`cta-splat-prep`: yt-dlp, ffmpeg). Run via `scripts/prep.sh`.
- `container/Containerfile.web` — `cta-splat-web`: splat-transform (PLY → SPZ/SOG).
- `remote/Containerfile.gpu` — training image, built by GitHub Actions → `ghcr.io/mpenelange/cta-splat-gpu:latest`
  (public). PyTorch 2.7 / CUDA 12.8 / Ubuntu 22.04, gsplat 1.4.0 and COLMAP 4.2.1 (CUDA) compiled
  for **sm_120 only** (RTX 50xx / RTX PRO Blackwell). Build ≈ 40 min on CI.
- `remote/train_segment.sh` — runs on the GPU host: GPU COLMAP (lens prior, sequential + optional
  `pairs.txt`, global or incremental mapper) unless a solved model is uploaded → `ns-process-data`
  → `splatfacto-big` → eval → export. Logs VRAM (`vram.csv`, `PEAK_VRAM_MIB`), power limit, timings.
  Env knobs: `CACHE_IMAGES` (gpu|cpu), `BILATERAL=1`, `MAPPER` (global|incremental), `CAMERA_PARAMS`.
- `scripts/vast_run.sh <offer_id> <segment_dir> [iters]` — rent, upload, run, pull results, **always
  destroy**. Forwards the env knobs above.
- `scripts/vast_btop.sh` / `scripts/vast_nvtop.sh <instance_id>` — monitors on a running instance.
- `tools/mapper_experiments.sh` — re-run COLMAP mapping locally on a saved database.
- `tools/camera_path.py` — camera path in splat coordinates for the viewer (undo `applied_transform`
  before the dataparser transform — getting this wrong put the camera "above" the scene).
- `tools/ckpt_to_ply.py` — export a splatfacto checkpoint to `.ply` without nerfstudio/GPU.
- `viewer/index.html` — three.js 0.186.1 + Spark 2.4.0 cab viewer (`?seg=<name>` picks a segment).
- `data` → `/srv/cta-splat` (4 TB SSD): `raw/`, `tests/<seg>/`, `viewer/<seg>/{splat.spz,path.json}`.

## How to run things

```bash
# Viewer (LAN): http://10.0.0.242:8090/?seg=t01
podman run -d --rm --name cta-viewer --userns=keep-id -p 8090:8000 -v /srv/cta-splat/viewer:/srv:ro \
  cta-splat-prep python3 -m http.server 8000 -d /srv
cp viewer/index.html /srv/cta-splat/viewer/

# Find Blackwell offers (image only runs on sm_120)
.venv/bin/vastai search offers 'compute_cap=1200 num_gpus=1 reliability>0.98 cpu_ram>=64 disk_space>=150 direct_port_count>=1 inet_down>=1000' -o dph

# Train a segment dir (default GPU image cache is faster if it fits) containing images/ (optionally pairs.txt or processed/colmap/sparse/0)
BILATERAL=1 MAPPER=global scripts/vast_run.sh <offer_id> /srv/cta-splat/tests/<seg> 30000

# Post-process a run into the viewer
T=/srv/cta-splat/tests/<seg>/out; RUN=$(ls -d $T/runs/processed/splatfacto/*/)
podman run --rm --userns=keep-id -v $PWD/tools:/tools:ro -v /srv/cta-splat:/srv/cta-splat localhost/cta-splat-colmap-test \
  python /tools/camera_path.py $T/processed/transforms.json $RUN/dataparser_transforms.json /srv/cta-splat/viewer/<seg>/path.json [1:160]
podman run --rm --userns=keep-id -v /srv/cta-splat:/srv/cta-splat cta-splat-web splat-transform -w -g cpu \
  $T/export/splat.ply -N -V opacity,gt,0.02 -m /srv/cta-splat/viewer/<seg>/splat.spz
```

`localhost/cta-splat-colmap-test` is a local image (PyTorch base + CUDA COLMAP) used for CPU-side
tools; it isn't in a registry. Rebuild with `remote/build_colmap.sh` on the PyTorch base if missing.

## Results so far

| Test | Data | GPU | SfM | Train | Peak VRAM | Gaussians | Cost |
|---|---|---|---|---|---|---|---|
| t01 | 100 frames, 1 direction, 4K | 5090 (capped 400 W) | local CPU, incremental, 0.51 px | 38 min / 30k | 23.4 GB | 2.28M (1.66M after opacity filter) | ≈ $0.60 |
| t02 | 320 frames, both directions, 4K | RTX PRO 5000 48 GB | GPU COLMAP, global mapper: 320/320 frames, 0.92 px, 20 min | 64 min / 30k (cpu image cache) | 15.9 GB | 1.10M (744K after filter) | ≈ $1.00 |

t01 output: 564 MB PLY → 28 MB SPZ. Viewer feels right on the track path; off-path views break
down quickly (expected from forward-only capture).

### t02 result

- Instance 59533097, RTX PRO 5000 48 GB (300 W), $0.668/hr, 182 GB RAM / 36 CPUs allotted. Destroyed.
- SfM: extraction 0.5 min, sequential matching 1 min, 2,916 cross-direction pairs (`pairs.txt`) 0.4 min,
  `global_mapper` 18 min → **320/320 registered, one model, 270K points, 0.917 px**. Joining both
  directions works.
- Training: 3,844 s for 30k steps at ~130–145 ms/step, with `CACHE_IMAGES=cpu` (CPU-bound, GPU at ~90 %
  util / ~215 W). Peak VRAM 15.9 GB, so GPU caching (320 × ~25 MB ≈ 8 GB more) would still fit 48 GB.
  It might even fit 24 GB.
- Eval (nerfstudio held-out frames): PSNR 17.2, SSIM 0.71, LPIPS 0.46. This is low, but probably
  pessimistic: the bilateral grid's per-image colour correction isn't applied to held-out frames, and
  they mix sunny and overcast lighting. t01 has no eval to compare with (ns-eval failed back then). A
  fair comparison needs the same eval with and without `BILATERAL`.
- Export: 1.10M gaussians, 883K after nerfstudio drops low-opacity ones; 219 MB PLY → 744K after
  `opacity>0.02` → **12.2 MB SPZ**. That's fewer gaussians than t01 (2.28M) despite 3× the frames.
- Viewer: `viewer/t02/path.json` is the **northbound** path (frames 1–160) and `path_sb.json` the
  southbound one (frames 161–320). `camera_path.py` now takes a `first:last` frame range, because
  mixing both directions makes the path flip back and forth. The viewer only loads `path.json` for now.
  Frame numbering: `ns-process-data` renames `nb_*` → `frame_00001–00160` and `sb_*` → `frame_00161–00320`.
- Running Vast total so far ≈ $2.54 invoiced; ≈ $24.93 credit left.

## Lessons (cost real money or time)

- Ubuntu's apt COLMAP is CPU-only: 20 min of CPU matching on a $1.74/hr GPU. Now built with CUDA.
- COLMAP on forward motion needs a wide-lens focal prior (~2000 px, not the 1.2×width default) and
  either the global mapper or `init_min_tri_angle` ≈ 2 for the incremental one.
- Vast containers show the whole host in /proc; real limits are in cgroup v1. Hosts with 16 GB RAM
  OOM COLMAP at 4K. Some hosts power-cap GPUs (a 5090 at 400 W). Check `dlperf`, bandwidth $/GB.
- PyTorch ≥ 2.6 breaks nerfstudio checkpoint loading (`weights_only`); scripts set
  `TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD=1`.
- SOG compression without a GPU is single-threaded and very slow; use SPZ locally.
- `CACHE_IMAGES=cpu` makes the CPU feed one 4K image per step (~23 cores busy, GPU ~214 W of 300 W
  on t02). t02 only used 8 GB of 48 GB VRAM, so GPU caching (the default) would have been faster.
  Use cpu caching only when frames × 25 MB plus expected gaussian memory won't fit.
- Spark needs `three/addons/` in the import map.
- `pgrep -f`/`pkill -f` patterns match their own shell command line; don't use them as waiters.

## Next steps (in rough priority)

1. Review t02 in the viewer (`http://10.0.0.242:8090/?seg=t02`) next to t01 (`?seg=t01`): sharper or
   blurrier? Lighting blotches? Is the southbound track usable? Add a `?path=sb` option to the viewer
   to drive the southbound path.
2. If t02 looks soft: rerun the same solve (upload `processed/colmap/sparse/0`, skips SfM) with GPU
   caching, with and without `BILATERAL`, to separate the effects; maybe 60k steps.
3. Resolution A/B on t02: train at 1080p / 2K / 4K from the same solve; decide per quality vs VRAM.
4. Step-count test (30k vs 60k) — t02 gets only ~94 passes per frame at 30k.
5. Fit the home RTX 5080 (16 GB): t02 peaked at 15.9 GB with CPU caching, so it's right at the edge.
   MCMC strategy with a gaussian budget, and/or shorter segments.
6. Real-world scale: measure track gauge (1.435 m) in the splat; viewer currently assumes 140 m/unit,
   which was eyeballed for t01. nerfstudio rescales every scene differently, so speeds on t02 will be off
   until scale is stored per segment (e.g. `m_per_unit` in path.json).
7. Frame-rate test (4 fps vs 8–15 fps) for near-track detail.
8. Full-route pipeline: segment queue, interruptible Vast instances with checkpoint/resume,
   results to R2, 8+ GPUs in parallel; rank offers by cost per segment.
9. Consider moving the GPU image to Ubuntu 24.04 (nvidia/cuda base + uv Python 3.11) next time it
   needs changes.
