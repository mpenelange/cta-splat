#!/usr/bin/env bash
# Open nvtop on a running Vast instance (installs it if missing). Usage: scripts/vast_nvtop.sh <instance_id>
VAST="$(dirname "$0")/../.venv/bin/vastai"
read -r HOST PORT < <("$VAST" ssh-url "$1" | sed -E 's#ssh://[^@]+@([^:]+):([0-9]+)#\1 \2#')
SSHO=(-i ~/.ssh/cta_splat_vast -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
until ssh "${SSHO[@]}" -p "$PORT" root@"$HOST" true 2>/dev/null; do echo "waiting for instance $1 ssh..."; sleep 10; done
exec ssh -t "${SSHO[@]}" -p "$PORT" root@"$HOST" \
  'command -v nvtop >/dev/null || until DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nvtop >/dev/null 2>&1 || (apt-get update -qq >/dev/null 2>&1; false); do echo "installing nvtop (waiting for apt)..."; sleep 5; done; nvtop'
