#!/usr/bin/env bash
# Open btop (CPU + GPU + memory) on a running Vast instance. Usage: scripts/vast_btop.sh <instance_id>
VAST="$(dirname "$0")/../.venv/bin/vastai"
read -r HOST PORT < <("$VAST" ssh-url "$1" | sed -E 's#ssh://[^@]+@([^:]+):([0-9]+)#\1 \2#')
SSHO=(-i ~/.ssh/cta_splat_vast -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
until ssh "${SSHO[@]}" -p "$PORT" root@"$HOST" true 2>/dev/null; do echo "waiting for instance $1 ssh..."; sleep 10; done
# conda-forge btop (glibc, GPU_SUPPORT) in its own env; the static musl release can't load NVML.
exec ssh -t "${SSHO[@]}" -p "$PORT" root@"$HOST" '
  [ -x /opt/btopenv/bin/btop ] || { echo "installing btop..."; /opt/conda/bin/conda create -q -y -p /opt/btopenv -c conda-forge --override-channels btop >/dev/null 2>&1; }
  mkdir -p ~/.config/btop && sed -i "/^shown_boxes/d" ~/.config/btop/btop.conf 2>/dev/null; echo "shown_boxes = \\"cpu gpu0 mem proc\\"" >> ~/.config/btop/btop.conf
  exec /opt/btopenv/bin/btop'
