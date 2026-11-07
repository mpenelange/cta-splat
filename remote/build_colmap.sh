#!/usr/bin/env bash
# Build COLMAP with CUDA (GPU SIFT extraction/matching + built-in global mapper) for Blackwell (sm_120).
# Ubuntu's packaged colmap is CPU-only because distros can't ship CUDA builds.
set -euo pipefail
COLMAP_VERSION="${COLMAP_VERSION:-4.2.1}"
CUDA_ARCHS="${CUDA_ARCHS:-120}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends git ninja-build build-essential \
  libboost-program-options-dev libboost-graph-dev libboost-system-dev libeigen3-dev \
  libopenimageio-dev openimageio-tools libmetis-dev libgoogle-glog-dev libgflags-dev \
  libsqlite3-dev libglew-dev libcgal-dev libceres-dev libsuitesparse-dev \
  libcurl4-openssl-dev libssl-dev libopenexr-dev >/dev/null
mkdir -p /usr/include/opencv4   # Ubuntu's OpenImageIO CMake config expects this dir
git clone -q --depth 1 --branch "$COLMAP_VERSION" https://github.com/colmap/colmap.git /tmp/colmap
# Conda's cmake 4.x (knows sm_120) but link against system libs, not the conda copies in the PyTorch image.
unset CONDA_PREFIX
cmake -S /tmp/colmap -B /tmp/colmap/build -GNinja -DCMAKE_BUILD_TYPE=Release \
  -DCUDA_ENABLED=ON -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCHS" \
  -DGUI_ENABLED=OFF -DOPENGL_ENABLED=OFF -DTESTS_ENABLED=OFF -DONNX_ENABLED=OFF \
  -DCCACHE_ENABLED=OFF -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_IGNORE_PREFIX_PATH=/opt/conda -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc
ninja -C /tmp/colmap/build -j "${MAX_JOBS:-4}"
ninja -C /tmp/colmap/build install >/dev/null
rm -rf /tmp/colmap
colmap help 2>&1 | head -3
colmap help 2>&1 | grep -q 'with CUDA' && echo "COLMAP built with CUDA"
