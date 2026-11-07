#!/usr/bin/env bash
# Rent a Vast GPU, upload a segment, train, pull results, destroy the instance.
# Usage: scripts/vast_run.sh <offer_id> <local segment dir containing images/> [iters]
set -euo pipefail
OFFER="$1"; SEG="$(realpath "$2")"; ITERS="${3:-30000}"
VAST="$(dirname "$0")/../.venv/bin/vastai"
# Prebuilt image from CI (gpu-image workflow). Set IMAGE=pytorch/pytorch:2.7.0-cuda12.8-cudnn9-devel to install from scratch.
IMAGE="${IMAGE:-ghcr.io/mpenelange/cta-splat-gpu:latest}"; KEY=~/.ssh/cta_splat_vast
SSHO=(-i "$KEY" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
ID=$("$VAST" create instance "$OFFER" --image "$IMAGE" \
      --disk 150 --ssh --direct --raw | python3 -c 'import json,sys;print(json.load(sys.stdin)["new_contract"])')
echo "instance $ID"; echo "$ID" > "$SEG/.vast_instance"
cleanup(){ echo "destroying $ID"; "$VAST" destroy instance "$ID" -y >/dev/null || "$VAST" destroy instance "$ID"; }
trap cleanup EXIT
for i in $(seq 1 90); do
  st=$("$VAST" show instance "$ID" --raw | python3 -c 'import json,sys;print(json.load(sys.stdin).get("actual_status"))')
  [ "$st" = running ] && break; sleep 20
done
[ "$st" = running ] || { echo "instance never started ($st)"; exit 1; }
read -r HOST PORT < <("$VAST" ssh-url "$ID" | sed -E 's#ssh://[^@]+@([^:]+):([0-9]+)#\1 \2#')
for i in $(seq 1 30); do ssh "${SSHO[@]}" -p "$PORT" root@"$HOST" true 2>/dev/null && break; sleep 10; done
R="$(dirname "$0")/../remote"
tar -cf - -C "$SEG" images -C "$(realpath "$R")" setup_gpu.sh train_segment.sh \
  | ssh "${SSHO[@]}" -p "$PORT" root@"$HOST" "mkdir -p /root/seg && tar -C /root/seg -xf -"
rc=0
ssh "${SSHO[@]}" -p "$PORT" root@"$HOST" "cd /root/seg && { ( python -c \"import gsplat, nerfstudio\" 2>/dev/null || bash setup_gpu.sh ) && bash train_segment.sh /root/seg $ITERS; } 2>&1 | tee job.log; exit \${PIPESTATUS[0]}" || rc=$?
mkdir -p "$SEG/out"
ssh "${SSHO[@]}" -p "$PORT" root@"$HOST" "tar -C /root/seg --exclude=images --exclude='processed/images*' -cf - ." | tar -C "$SEG/out" -xf -
echo "job exit $rc; results in $SEG/out"; exit $rc
