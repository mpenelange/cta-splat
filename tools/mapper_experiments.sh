#!/usr/bin/env bash
# Re-run COLMAP mapping on an existing feature/match database with different settings (CPU is fine).
# Usage (inside the GPU image): mapper_experiments.sh <segment dir with images/ and out/processed/colmap/database.db> [focal_px...]
set -uo pipefail
SEG="$1"; shift; FOCALS=("${@:-1900}")
SRC="$SEG/out/processed/colmap/database.db"; X="$SEG/mapper_exp"; mkdir -p "$X"
summary(){ colmap model_analyzer --path "$1" 2>&1 | grep -E 'Registered images|Points:|Mean reprojection error|Cameras' | sed 's/^.*\] //' | tr '\n' ';'; }
for f in "${FOCALS[@]}"; do
  for mode in incremental global; do
    D="$X/f${f}_$mode"; rm -rf "$D"; mkdir -p "$D/sparse"; cp "$SRC" "$D/database.db"
    # Set a prior focal length (wide lens) on the single OPENCV camera: fx fy cx cy k1 k2 p1 p2.
    python - "$D/database.db" "$f" <<'PY'
import sqlite3, sys, numpy as np
db, f = sys.argv[1], float(sys.argv[2])
c = sqlite3.connect(db); cid, w, h = c.execute("select camera_id, width, height from cameras").fetchone()
p = np.array([f, f, w/2, h/2, 0, 0, 0, 0], dtype=np.float64)
c.execute("update cameras set params=?, prior_focal_length=1 where camera_id=?", (p.tobytes(), cid)); c.commit()
PY
    t0=$(date +%s)
    if [ $mode = incremental ]; then
      colmap mapper --database_path "$D/database.db" --image_path "$SEG/images" --output_path "$D/sparse" \
        --Mapper.init_min_tri_angle 2 --Mapper.init_max_forward_motion 0.999 --Mapper.ba_refine_focal_length 1 \
        --Mapper.ba_refine_extra_params 1 > "$D/log.txt" 2>&1
    else
      colmap global_mapper --database_path "$D/database.db" --image_path "$SEG/images" --output_path "$D/sparse" > "$D/log.txt" 2>&1
    fi
    rc=$?; dt=$(( $(date +%s) - t0 ))
    for m in "$D"/sparse/*/; do [ -f "$m/cameras.bin" ] && echo "f=$f $mode ${dt}s rc=$rc $(basename $m): $(summary $m)"; done
    ls "$D"/sparse/*/cameras.bin >/dev/null 2>&1 || echo "f=$f $mode ${dt}s rc=$rc: NO MODEL ($(grep -iE 'error|no good|fail' "$D/log.txt" | tail -1))"
  done
done
