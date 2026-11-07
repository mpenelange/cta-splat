#!/usr/bin/env bash
# Runs ON the GPU host. Usage: train_segment.sh <workdir with images/> [iters]
# 1. COLMAP (sequential matching for video), thread count capped by available RAM so 4K frames don't OOM.
# 2. nerfstudio splatfacto at full resolution, images cached in host RAM (GPU memory kept for gaussians).
# 3. Export the splat as .ply.
set -euo pipefail
W="$1"; ITERS="${2:-30000}"
cd "$W"
mem_bytes=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
[ "$mem_bytes" = max ] && mem_bytes=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) * 1024 ))
mem_gb=$(( mem_bytes / 1024 / 1024 / 1024 ))
THREADS=$(( mem_gb / 4 )); NPROC=$(nproc); (( THREADS > NPROC )) && THREADS=$NPROC; (( THREADS < 1 )) && THREADS=1
echo "host: ${mem_gb} GB RAM, ${NPROC} cpus -> COLMAP threads ${THREADS}; $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader)"

DB=processed/colmap/database.db; mkdir -p processed/colmap/sparse
t0=$(date +%s)
colmap feature_extractor --database_path "$DB" --image_path images \
  --ImageReader.single_camera 1 --ImageReader.camera_model OPENCV \
  --SiftExtraction.use_gpu 0 --SiftExtraction.num_threads "$THREADS" \
  --SiftExtraction.max_image_size 3840 --SiftExtraction.max_num_features 16384 2>&1 | tail -3
colmap sequential_matcher --database_path "$DB" --SiftMatching.use_gpu 0 \
  --SiftMatching.num_threads "$THREADS" --SequentialMatching.overlap 20 \
  --SequentialMatching.loop_detection 0 2>&1 | tail -3
colmap mapper --database_path "$DB" --image_path images --output_path processed/colmap/sparse \
  --Mapper.num_threads "$NPROC" --Mapper.ba_global_function_tolerance 1e-6 2>&1 | tail -5
echo "colmap models: $(ls processed/colmap/sparse)"; for m in processed/colmap/sparse/*; do
  echo "model $m: $(colmap model_analyzer --path "$m" 2>&1 | grep -E 'Registered images|Points|Mean reprojection' | tr '\n' ' ')"; done
echo "SFM_SECONDS=$(( $(date +%s) - t0 ))"

# Largest model -> sparse/0 for nerfstudio.
best=$(for m in processed/colmap/sparse/*; do echo "$(colmap model_analyzer --path "$m" 2>&1 | awk '/Registered images/{print $NF}') $m"; done | sort -n | tail -1 | cut -d' ' -f2)
[ "$best" != processed/colmap/sparse/0 ] && { mv processed/colmap/sparse/0 processed/colmap/sparse/_0 2>/dev/null || true; mv "$best" processed/colmap/sparse/0; }
ns-process-data images --data images --output-dir processed --skip-colmap \
  --colmap-model-path colmap/sparse/0 --num-downscales 0 2>&1 | tail -5

t1=$(date +%s)
ns-train splatfacto-big --data processed --output-dir runs \
  --max-num-iterations "$ITERS" --viewer.quit-on-train-completion True \
  --pipeline.datamanager.cache-images cpu \
  nerfstudio-data --downscale-factor 1 2>&1 | grep -vE '^\s*$' | awk 'NR%50==1 || /Error|error|Saving|Finished|Traceback/'
echo "TRAIN_SECONDS=$(( $(date +%s) - t1 ))"
CFG=$(ls -t runs/*/*/*/config.yml | head -1)
ns-eval --load-config "$CFG" --output-path eval.json 2>&1 | tail -2 || true
ns-export gaussian-splat --load-config "$CFG" --output-dir export 2>&1 | tail -3
nvidia-smi --query-gpu=memory.used --format=csv
ls -la export
