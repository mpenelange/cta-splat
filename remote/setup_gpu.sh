#!/usr/bin/env bash
# Installs the splat training stack on a CUDA 12.8+ PyTorch base (works on Blackwell / sm_120).
# Used both on Vast instances and by remote/Containerfile.gpu (for a home RTX 5080).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq colmap ffmpeg git rsync libgl1 libglib2.0-0 >/dev/null
export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-12.0}" MAX_JOBS="${MAX_JOBS:-8}"
pip install -q nerfstudio
# Compile gsplat's CUDA kernels now for this arch instead of JIT on first use.
pip install -q --no-build-isolation --force-reinstall --no-deps "gsplat==$(pip show gsplat | awk '/^Version/{print $2}')" --no-binary gsplat
python - <<'PY'
import torch, gsplat
print("torch", torch.__version__, "cuda", torch.version.cuda, "gsplat", gsplat.__version__)
print("gpu", torch.cuda.get_device_name(0) if torch.cuda.is_available() else "none (ok at image build time)")
PY
