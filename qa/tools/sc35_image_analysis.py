#!/usr/bin/env python3
"""SC-35 screenshot evidence extraction: profiles + reference colour targets.

Reads the six user-provided screenshots from the WorkBuddy clipboard cache and
writes luminance/hue profiles plus cropped PNGs to qa/sc35-probe/ so the shader
fixes can be checked against measured numbers instead of eyeballing JPEGs.
"""
from pathlib import Path
import numpy as np
from PIL import Image

CLIP = Path.home() / ".workbuddy" / "clipboard-images"
OUT = Path(__file__).resolve().parents[2] / "qa" / "sc35-probe"
OUT.mkdir(parents=True, exist_ok=True)

FILES = {
    "img1_astra_underwater": "clipboard-2026-09-07T16-00-31-255Z-98720911.jpg",
    "img2_astra_grass_lake": "clipboard-2026-09-07T16-00-31-259Z-bdb8c24f.jpg",
    "img3_astra_waterline": "clipboard-2026-09-07T16-00-31-263Z-c765707e.jpg",
    "img4_ref_surface": "clipboard-2026-09-07T16-00-31-266Z-f31e4bb7.jpg",
    "img5_astra_underwater2": "clipboard-2026-09-07T16-00-31-270Z-079a07fe.jpg",
    "img6_ref_underwater": "clipboard-2026-09-07T16-00-31-274Z-40fbc143.jpg",
}
IMS = {k: np.asarray(Image.open(CLIP / f).convert("RGB"), dtype=np.float32)
       for k, f in FILES.items()}


def lum(a):
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722


def save_crop(name, im, x0, y0, x1, y1, scale=3):
    crop = Image.fromarray(im[y0:y1, x0:x1].astype(np.uint8))
    crop = crop.resize(((x1 - x0) * scale, (y1 - y0) * scale), Image.NEAREST)
    crop.save(OUT / f"{name}.png")


def profile_x(name, im, y, x0, x1, step=8):
    line = lum(im)[y, x0:x1]
    pts = [f"{x0+i}:{line[i]:.0f}" for i in range(0, len(line), step)]
    print(f"{name} y={y}: " + " ".join(pts))


def region(im, x0, y0, x1, y1):
    r = im[y0:y1, x0:x1].reshape(-1, 3)
    return np.median(r, 0).round(1)


print("=== IMG2 pond edge: vertical profile through the white halo ===")
im = IMS["img2_astra_grass_lake"]
# The pond sits lower-left; scan several columns for a bright rim hugging the waterline.
for x in (320, 420, 520):
    profile_x("pond_col_x", im.T[x], 0, 1) if False else None
    line = lum(im)[:, x]
    pts = [f"{y}:{line[y]:.0f}" for y in range(600, 1080, 40)]
    print(f"x={x}: " + " ".join(pts))
save_crop("img2_pond_edge", im, 250, 700, 800, 1080)

print()
print("=== IMG2 bright blob: horizontal scan at y=350 ===")
line = lum(im)[350, :]
pts = [f"{x}:{line[x]:.0f}" for x in range(400, 1000, 40)]
print("y=350: " + " ".join(pts))
save_crop("img2_blob", im, 450, 250, 900, 500)

print()
print("=== IMG3 seam: vertical profile at lower-left ===")
im3 = IMS["img3_astra_waterline"]
for x in (150, 300, 500):
    line = lum(im3)[:, x]
    pts = [f"{y}:{line[y]:.0f}" for y in range(550, 1000, 30)]
    print(f"x={x}: " + " ".join(pts))
save_crop("img3_seam", im3, 0, 550, 700, 1080)

print()
print("=== IMG5 underwater plant rims ===")
im5 = IMS["img5_astra_underwater2"]
save_crop("img5_plants", im5, 300, 550, 1100, 1000)
# scan across a bright-rim candidate zone
for y in (700, 800):
    line = lum(im5)[y, 400:900]
    pts = [f"{400+i}:{line[i]:.0f}" for i in range(0, len(line), 40)]
    print(f"y={y}: " + " ".join(pts))

print()
print("=== Reference water colour targets (IMG4 surface / IMG6 underwater) ===")
im4, im6 = IMS["img4_ref_surface"], IMS["img6_ref_underwater"]
print("img4 shallow cyan  ", region(im4, 150, 480, 450, 620))
print("img4 mid teal      ", region(im4, 700, 350, 1100, 480))
print("img4 deep centre   ", region(im4, 850, 500, 1250, 650))
print("img4 far shore     ", region(im4, 700, 180, 1200, 260))
print("img6 open water col", region(im6, 200, 300, 700, 500))
print("img6 shaft zone    ", region(im6, 900, 100, 1500, 300))
print("img6 lit sand      ", region(im6, 900, 700, 1400, 900))
print("img6 seagrass lit  ", region(im6, 500, 800, 800, 1000))
print("img6 deep shadow   ", region(im6, 100, 700, 350, 900))

print()
print("=== Astra underwater (IMG1/IMG5) for the same quantities ===")
im1 = IMS["img1_astra_underwater"]
print("img1 open water col", region(im1, 200, 300, 700, 500))
print("img1 upper glow    ", region(im1, 800, 150, 1100, 350))
print("img1 terrain       ", region(im1, 900, 700, 1400, 900))
print("img5 open water col", region(im5, 100, 200, 500, 400))
print("img5 sand          ", region(im5, 900, 800, 1400, 1000))
print("img5 upper right   ", region(im5, 1400, 100, 1800, 300))
