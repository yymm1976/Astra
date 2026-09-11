"""Generate Astra's own rain-ripple flipbook (no borrowed artwork).

Model: a field of expanding circular wavelets. Each wavelet is born at a random frame and
position, expands at a constant rate, and decays over its life. The summed height field is
differentiated into a normal map. Life is shorter than the sheet and centres wrap, so the
animation loops seamlessly in both time and space.

The three sheets differ in wavelet count, expansion rate and ring width so the shader can
stack them by rain intensity.
"""
import numpy as np
from PIL import Image

S = 128
F = 60
yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)

def make_sheet(n_wavelets, speed, ring_w, amp, life_frac, seed):
    rng = np.random.default_rng(seed)
    cx = rng.uniform(0, S, n_wavelets)
    cy = rng.uniform(0, S, n_wavelets)
    birth = rng.uniform(0, F, n_wavelets)
    spd = speed * rng.uniform(0.85, 1.15, n_wavelets)
    gain = rng.uniform(0.75, 1.0, n_wavelets)
    life = F * life_frac

    frames = np.empty((F, S, S), np.float64)
    for f in range(F):
        h = np.zeros((S, S), np.float64)
        for k in range(n_wavelets):
            age = (f - birth[k]) % F
            if age > life:
                continue
            radius = spd[k] * age
            # periodic distance -> the sheet tiles in space
            dx = np.abs(xx - cx[k]); dx = np.minimum(dx, S - dx)
            dy = np.abs(yy - cy[k]); dy = np.minimum(dy, S - dy)
            r = np.sqrt(dx * dx + dy * dy)
            ring = np.exp(-((r - radius) / ring_w) ** 2)
            decay = (1.0 - age / life) ** 1.6
            h += amp * gain[k] * ring * decay
        frames[f] = h
    return frames

def to_normal(frames, slope):
    gx = np.gradient(frames, axis=2)
    gy = np.gradient(frames, axis=1)
    nx = -gx * slope
    ny = -gy * slope
    nz = np.ones_like(frames)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    enc = np.empty((F, S, S, 4), np.uint8)
    enc[..., 0] = np.clip(nx / ln * 0.5 + 0.5, 0, 1) * 255
    enc[..., 1] = np.clip(ny / ln * 0.5 + 0.5, 0, 1) * 255
    enc[..., 2] = np.clip(nz / ln * 0.5 + 0.5, 0, 1) * 255
    enc[..., 3] = 255
    return enc

# sheet 1 is the light-rain layer (sparse, small), sheet 3 the downpour layer (dense, large)
specs = [
    ("astra-ripple-1.png",  7, 0.75, 1.9, 0.55, 0.60, 2.6, 101),
    ("astra-ripple-2.png", 14, 1.00, 2.2, 0.50, 0.65, 2.4, 202),
    ("astra-ripple-3.png", 24, 1.30, 2.6, 0.45, 0.70, 2.2, 303),
]
for name, n, speed, ring_w, amp, life_frac, slope, seed in specs:
    fr = make_sheet(n, speed, ring_w, amp, life_frac, seed)
    enc = to_normal(fr, slope)
    tall = np.concatenate([enc[f] for f in range(F)], axis=0)
    path = f"Astra/shaders/textures/{name}"
    Image.fromarray(tall, "RGBA").save(path)
    # report how strong the rings actually are
    nz = enc[..., 2].astype(np.float64) / 255.0
    print(f"{path}: {n} wavelets, tilt p99 = {np.degrees(np.arccos(np.percentile(nz, 1))):.1f} deg")
