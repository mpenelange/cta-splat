"""Extract the training-camera path in the splat's coordinate system (nerfstudio world).

Usage: python camera_path.py <processed/transforms.json> <dataparser_transforms.json> <out.json>
Each camera: position + 3x3 rotation (OpenGL convention: looks down -Z, +Y up), the same convention
three.js cameras use, so the viewer can set camera.matrix directly. Cameras are ordered along the track.
"""
import json, sys
import numpy as np

tf = json.load(open(sys.argv[1]))
dp = json.load(open(sys.argv[2]))
T = np.eye(4); T[:3, :] = np.array(dp["transform"]); s = dp["scale"]

cams = []
for fr in tf["frames"]:
    c2w = T @ np.array(fr["transform_matrix"])
    c2w[:3, 3] *= s
    cams.append((fr["file_path"], c2w))

P = np.array([c[1][:3, 3] for c in cams])
# Order along the dominant direction of travel (robust to out-of-order source frames).
d = np.linalg.svd(P - P.mean(0))[2][0]
fwd = -np.mean([c[1][:3, 2] for c in cams], 0)        # cameras look down -Z
if d @ fwd < 0: d = -d
order = np.argsort((P - P.mean(0)) @ d)
cams = [cams[i] for i in order]
P = P[order]
seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
up = np.mean([c[1][:3, 1] for c in cams], 0); up /= np.linalg.norm(up)

out = {
    "convention": "nerfstudio world; camera rotation columns = right, up, back (OpenGL)",
    "world_up": up.round(5).tolist(),
    "length": float(seg.sum()),
    "fov_y_deg": float(np.degrees(2 * np.arctan(tf["h"] / 2 / tf["fl_y"]))),
    "aspect": tf["w"] / tf["h"],
    "cameras": [{"file": f, "p": c[:3, 3].round(6).tolist(), "R": c[:3, :3].round(6).tolist()} for f, c in cams],
}
json.dump(out, open(sys.argv[3], "w"))
print(f"{len(cams)} cameras, path length {seg.sum():.4f} units, step min/median/max "
      f"{seg.min():.4f}/{np.median(seg):.4f}/{seg.max():.4f}, world up {up.round(3)}, fov_y {out['fov_y_deg']:.1f} deg")
