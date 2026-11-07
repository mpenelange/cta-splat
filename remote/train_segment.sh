#!/usr/bin/env bash
# Runs ON the Vast instance (nerfstudio image). Usage: train_segment.sh <workdir with images/> [iters]
# Solves camera poses with COLMAP (sequential matching, suited to video), trains splatfacto, exports a .ply.
set -euo pipefail
W="$1"; ITERS="${2:-15000}"
cd "$W"
ns-process-data images --data images --output-dir processed \
  --matching-method sequential --camera-type perspective --no-gpu --num-downscales 2 2>&1 | tee log_sfm.txt
ns-train splatfacto --data processed --output-dir runs \
  --max-num-iterations "$ITERS" --viewer.quit-on-train-completion True \
  --pipeline.datamanager.camera-res-scale-factor 0.5 \
  nerfstudio-data --downscale-factor 1 2>&1 | tee log_train.txt
CFG=$(ls -t runs/*/splatfacto/*/config.yml | head -1)
ns-export gaussian-splat --load-config "$CFG" --output-dir export 2>&1 | tee log_export.txt
ls -la export
