#!/usr/bin/env bash
# Download source videos (best video-only stream, up to 2160p) into data/raw/<id>.<ext>.
set -euo pipefail
cut -d' ' -f1 data/sources.txt | while read -r url; do
  yt-dlp --no-warnings --no-progress -f "bv*[height<=2160]" \
    --download-archive data/raw/.archive --write-info-json \
    -o "data/raw/%(id)s.%(ext)s" "$url"
done
