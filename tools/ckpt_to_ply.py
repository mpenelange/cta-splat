"""Export a nerfstudio splatfacto checkpoint to a standard 3DGS .ply (INRIA layout).

Usage: python ckpt_to_ply.py <step-XXXX.ckpt> <out.ply>
Works without a GPU. Loads with weights_only=False because nerfstudio checkpoints contain numpy
scalars that PyTorch >= 2.6 rejects by default (only use on checkpoints we produced ourselves).
"""
import sys
import numpy as np
import torch

ckpt = torch.load(sys.argv[1], map_location="cpu", weights_only=False)
sd = ckpt["pipeline"]
pre = next(k for k in sd if k.endswith("gauss_params.means")).rsplit("means", 1)[0]
g = {k[len(pre):]: v.float().numpy() for k, v in sd.items() if k.startswith(pre)}
means, scales, quats, opac = g["means"], g["scales"], g["quats"], g["opacities"].reshape(-1, 1)
f_dc = g["features_dc"].reshape(len(means), 3)
f_rest = g["features_rest"]                      # [N, K, 3] -> INRIA order is channel-major
f_rest = np.transpose(f_rest, (0, 2, 1)).reshape(len(means), -1)
quats = quats / np.linalg.norm(quats, axis=1, keepdims=True)

ok = np.isfinite(np.concatenate([means, scales, quats, opac, f_dc, f_rest], 1)).all(1)
cols = (["x", "y", "z", "nx", "ny", "nz"] + [f"f_dc_{i}" for i in range(3)]
        + [f"f_rest_{i}" for i in range(f_rest.shape[1])] + ["opacity"]
        + [f"scale_{i}" for i in range(3)] + [f"rot_{i}" for i in range(4)])
data = np.concatenate([means, np.zeros_like(means), f_dc, f_rest, opac, scales, quats], 1)[ok].astype("<f4")
with open(sys.argv[2], "wb") as f:
    f.write(("ply\nformat binary_little_endian 1.0\n"
             f"element vertex {len(data)}\n" + "".join(f"property float {c}\n" for c in cols)
             + "end_header\n").encode())
    f.write(data.tobytes())
print(f"gaussians: {len(means)} (kept {ok.sum()}), sh rest coeffs: {f_rest.shape[1]}, "
      f"extent: {np.ptp(means[ok], 0).round(2)}, file: {data.nbytes / 1e6:.0f} MB")
