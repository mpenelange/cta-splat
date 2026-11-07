#!/usr/bin/env bash
# Open nvtop on a running Vast instance. Usage: scripts/vast_nvtop.sh <instance_id>
# Uses conda-forge nvtop in its own env (Ubuntu 22.04's packaged nvtop is old).
VAST="$(dirname "$0")/../.venv/bin/vastai"
read -r HOST PORT < <("$VAST" ssh-url "$1" | sed -E 's#ssh://[^@]+@([^:]+):([0-9]+)#\1 \2#')
SSHO=(-i ~/.ssh/cta_splat_vast -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
until ssh "${SSHO[@]}" -p "$PORT" root@"$HOST" true 2>/dev/null; do echo "waiting for instance $1 ssh..."; sleep 10; done
exec ssh -t "${SSHO[@]}" -p "$PORT" root@"$HOST" '
  [ -x /opt/nvtopenv/bin/nvtop ] || { echo "installing nvtop..."; /opt/conda/bin/conda create -q -y -p /opt/nvtopenv -c conda-forge --override-channels nvtop >/dev/null 2>&1; }
  exec /opt/nvtopenv/bin/nvtop'
