# cta-splat

CTA Red Line train-driving game; environment = gaussian splats trained from CTA cab-view videos.

**Start here:** read `docs/PROGRESS.md` (status, layout, how to run, lessons, next steps).

Working rules for this repo:
- Local work runs in podman containers (`scripts/prep.sh`, `cta-splat-web`); don't install on the host.
- GPU work runs on Vast.ai via `.venv/bin/vastai` (already authenticated). Confirm the offer and price
  with the user before renting. `scripts/vast_run.sh` always destroys the instance; double-check with
  `.venv/bin/vastai show instances` after any failure.
- The training image only supports Blackwell (`compute_cap=1200`). Prefer hosts with ≥64 GB RAM.
- Large data lives in `/srv/cta-splat` (symlinked as `data/`), never in git.
- Commit as `mpenelange` with the GitHub noreply email (repo-local git config is set). Add `[skip ci]`
  to commits that touch `remote/` only when the image doesn't need rebuilding.
