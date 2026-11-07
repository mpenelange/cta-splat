# cta-splat

CTA Red Line train driving game, with the environment built from gaussian splats trained on
CTA "Ride the Rails" cab-view videos.

- `container/` — local preprocessing image (yt-dlp, ffmpeg). Run things via `scripts/prep.sh`.
- `remote/` — GPU training stack (CUDA 12.8, nerfstudio + gsplat for RTX 50xx). Built by GitHub
  Actions into `ghcr.io/mpenelange/cta-splat-gpu`; also usable on a home GPU via `remote/Containerfile.gpu`.
- `scripts/vast_run.sh` — rent a Vast.ai GPU, train one segment, pull results, destroy the instance.
- `data/` — symlink to `/srv/cta-splat` (videos, frames, results; not in git).

Source footage belongs to the CTA; it is not redistributed here.
