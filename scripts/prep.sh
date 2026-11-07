#!/usr/bin/env bash
# Run a command in the prep container. Mounts the repo at /work and the SSD at the same path, so the data symlink resolves.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec podman run --rm --userns=keep-id -v "$ROOT":/work -v /srv/cta-splat:/srv/cta-splat cta-splat-prep "$@"
