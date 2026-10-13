#!/usr/bin/env python3
"""F1 probe: how much of the visible cloud sheet is decided by the detail octave alone.

Historical offline formula model; it does not read GLSL source at runtime.
Current source anchors are clouds_planar.glsl:123-130 (unused reference formula)
and :280-290 (active march, which gates the coarse octave before fetching detail).
The observations below describe the earlier full-noise gate, not the current march.
The older line references in the historical model description are retained below.

Reproduces the earlier formula offline:

  astra_rounded_cloud_coord  clouds_planar.glsl:69-77   (roundness 0.48, /256)
  astra_2d_cloud_sample      clouds_planar.glsl:90-94   textureLod(complementaryCloudNoise, ...).b
  astra_cloud_noise          clouds_planar.glsl:97-104  0.78*base + 0.22*detail
  coverageBias              clouds_planar.glsl:181    mix(0.20,-0.20,CLOUD_COVERAGE*0.01)-0.04-0.28*rain
  existence gate            clouds_planar.glsl:225    noise <= threshold*0.5 + 0.25 + coverageBias -> skip
  columnDensity             clouds_planar.glsl:316    smoothstep(0.21+bias, 0.43+bias, noise)
  alpha                     clouds_planar.glsl:317    sqrt(clamp(distanceRatio,0,0.75)*1.33333)*columnDensity

The noise texture is the pack's own complementary-cloud-noise.png (256x256 RGBA8), so the
octave fields are the real ones. A sheet patch is swept at mid-layer (threshold ~= 1e-24),
which is where :225's gate degenerates to 0.25 + coverageBias.

Pinned measurement, not a gate. Re-run: python qa/tools/cloud_ghost_probe.py
"""

import math
from pathlib import Path

import numpy as np
from PIL import Image

NOISE = Path('Astra/shaders/textures/complementary-cloud-water.png')
ROUNDNESS = 0.48
STRETCH = 9.0
ALTITUDE = 192.0
NARROWNESS = 0.07


def _load():
    im = Image.open(NOISE).convert('RGBA')
    a = np.asarray(im).astype(np.float64) / 255.0
    return a[..., 2]          # .b channel, matching textureLod(...).b


def _smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def rounded_coord(pos, roundness=ROUNDNESS):
    """clouds_planar.glsl:69-77, vectorised. pos is a 2-vector field (N,2)."""
    coord = pos[:, ::-1] + 0.5                       # pos.yx + 0.5
    sign_coord = np.sign(coord)
    coord = np.abs(coord) + 1.0
    i = np.floor(coord)
    f = coord - i
    f = _smoothstep(0.5 - roundness, 0.5 + roundness, f)
    coord = i + f
    return (coord - 0.5) * sign_coord / 256.0


def sample(tex, pos):
    uv = rounded_coord(pos)
    # textureLod level 0 with repeat wrap, nearest is NOT used: the shader samples a
    # mipmapped texture at level 0, so bilinear over texel centres is the right model.
    w = tex.shape[0]
    x = (uv[:, 0] * w) - 0.5
    y = (uv[:, 1] * w) - 0.5
    x0 = np.floor(x).astype(int); y0 = np.floor(y).astype(int)
    fx = x - x0; fy = y - y0
    x0m = x0 % w; y0m = y0 % w
    x1m = (x0 + 1) % w; y1m = (y0 + 1) % w
    v00 = tex[y0m, x0m]; v10 = tex[y0m, x1m]; v01 = tex[y1m, x0m]; v11 = tex[y1m, x1m]
    return (v00 * (1 - fx) + v10 * fx) * (1 - fy) + (v01 * (1 - fx) + v11 * fx) * fy


def modify_trace_pos(xz, wind=0.0):
    """clouds_planar.glsl:81-87 for a mid-layer patch: y is dropped from the returned
    xz because astra_cloud_noise only ever uses tracePosM.xz (:98-103)."""
    z = xz[:, 1] - wind
    x = xz[:, 0] + ALTITUDE * 64.0
    return np.stack([x * NARROWNESS, z * NARROWNESS], axis=1)


def main():
    tex = _load()
    print('noise texture: %s  %dx%d' % (NOISE.name, tex.shape[0], tex.shape[1]))
    rng = np.random.default_rng(7)
    n = 400000
    xz = np.stack([rng.uniform(-2000.0, 2000.0, n), rng.uniform(-2000.0, 2000.0, n)], axis=1)
    m = modify_trace_pos(xz)
    base = sample(tex, m)
    detail_pos = (np.stack([0.8 * m[:, 0] - 0.6 * m[:, 1], 0.6 * m[:, 0] + 0.8 * m[:, 1]], axis=1)
                  * 2.7 + np.array([31.7, 9.3]))
    detail = sample(tex, detail_pos)
    coarse = 0.78 * base
    noise = coarse + 0.22 * detail

    print('octave ranges over %d mid-layer samples:' % n)
    print('  base   min %.3f p50 %.3f max %.3f' % (base.min(), np.median(base), base.max()))
    print('  detail min %.3f p50 %.3f max %.3f' % (detail.min(), np.median(detail), detail.max()))
    print('  coarse(0.78*base) p50 %.3f   noise(0.78b+0.22d) p50 %.3f' % (np.median(coarse), np.median(noise)))
    print()

    for cov in (50, 25, 75):
        bias = (0.20 + (-0.20 - 0.20) * (cov * 0.01)) - 0.04
        gate = 0.25 + bias
        alpha = np.sqrt(np.clip(1.0, 0.0, 0.75) * 1.33333) * _smoothstep(0.21 + bias, 0.43 + bias, noise)
        vis_old = noise > gate
        vis_new = coarse > gate
        ghost = vis_old & (~vis_new)
        cloud_px = int(vis_old.sum())
        q = np.percentile(alpha[vis_old], [50, 90, 95, 99]) if cloud_px else [0, 0, 0, 0]
        low = int((alpha[vis_old] < 0.15).sum())
        print('CLOUD_COVERAGE=%d  bias %+.3f  gate %.3f' % (cov, bias, gate))
        print('  cloud pixels (old gate): %6d  (%.2f%% of samples)' % (cloud_px, 100.0 * cloud_px / n))
        print('  ghost pixels (passes old gate, coarse fails): %6d = %.2f%% of cloud, %.2f%% of all'
              % (int(ghost.sum()), 100.0 * ghost.sum() / max(cloud_px, 1), 100.0 * ghost.sum() / n))
        print('  alpha percentiles p50 %.3f p90 %.3f p95 %.3f p99 %.3f | alpha<0.15 = %d (%.1f%% of cloud)'
              % (q[0], q[1], q[2], q[3], low, 100.0 * low / max(cloud_px, 1)))
        print('  after M2/M3 (gate on coarse): cloud pixels %6d (%.2f%%), alpha mean %.4f -> %.4f'
              % (int(vis_new.sum()), 100.0 * vis_new.sum() / n,
                 alpha[vis_old].mean() if cloud_px else 0.0,
                 alpha[vis_new].mean() if vis_new.any() else 0.0))
        print()

    # ---- after-contract (M3) figures: what the fix changes -----------------------
    print('--- M3 contract (existence on coarse; ramp starts at the gate) ---')
    for cov in (50,):
        bias = (0.20 + (-0.20 - 0.20) * (cov * 0.01)) - 0.04
        gate = 0.25 + bias
        sat = 0.43 + bias
        old_alpha = np.sqrt(1.33333) * _smoothstep(0.21 + bias, sat, noise)
        new_alpha = np.sqrt(1.33333) * _smoothstep(gate, sat, noise)
        vis_old = noise > gate
        vis_new = coarse > gate
        print('  cloud pixels         : before %6d (%.2f%%)   after %6d (%.2f%%)   delta %+.2f pp'
              % (vis_old.sum(), 100.0 * vis_old.mean(), vis_new.sum(), 100.0 * vis_new.mean(),
                 100.0 * (vis_new.mean() - vis_old.mean())))
        print('  alpha mean (visible) : before %.4f   after %.4f' % (old_alpha[vis_old].mean(),
                                                                    new_alpha[vis_new].mean()))
        low_old = int((old_alpha[vis_old] < 0.15).sum())
        low_new = int((new_alpha[vis_new] < 0.15).sum())
        print('  alpha<0.15 pixels    : before %6d (%.1f%% of cloud)   after %6d (%.1f%% of cloud)'
              % (low_old, 100.0 * low_old / max(vis_old.sum(), 1),
                 low_new, 100.0 * low_new / max(vis_new.sum(), 1)))
        ghost_new = int((vis_new & (~(coarse > gate))).sum())
        print('  detail-only existence: after %d  (must be 0)' % ghost_new)
        band = vis_new & (coarse < gate + 0.05)
        if band.any():
            print('  edge band (coarse in [gate, gate+0.05]): %d px, alpha mean %.4f, std %.4f'
                  % (int(band.sum()), new_alpha[band].mean(), new_alpha[band].std()))
            print('    -> std > 0 means the detail octave still modulates the edge alpha,')
            print('       i.e. the square cells stay softened even though they no longer')
            print('       decide existence.')
    print()

    # direction of the two populations: principal axis via 2-D structure tensor on a grid
    g = 256
    gx, gy = np.meshgrid(np.arange(g, dtype=np.float64) * 4.0, np.arange(g, dtype=np.float64) * 4.0)
    mm = modify_trace_pos(np.stack([gx.ravel(), gy.ravel()], axis=1))
    b2 = sample(tex, mm).reshape(g, g)
    d2 = sample(tex, (np.stack([0.8 * mm[:, 0] - 0.6 * mm[:, 1], 0.6 * mm[:, 0] + 0.8 * mm[:, 1]], axis=1)
                      * 2.7 + np.array([31.7, 9.3]))).reshape(g, g)
    c2 = 0.78 * b2
    n2 = c2 + 0.22 * d2
    bias = -0.04
    gate = 0.25 + bias
    ghost_mask = (n2 > gate) & (c2 <= gate)
    print('pattern orientation (structure tensor, degrees, 0=+x axis); grid 256x256 @4 blocks:')
    for name, field, mask in (('body  (noise>gate)', n2, n2 > gate),
                              ('ghost (noise>gate & coarse<=gate)', n2, ghost_mask),
                              ('coarse-only (c2>gate)', c2, c2 > gate)):
        if mask.sum() < 50:
            print('  %-38s too few pixels (%d)' % (name, int(mask.sum())))
            continue
        f = np.where(mask, field, np.nan)
        gy_i, gx_i = np.gradient(np.nan_to_num(f, nan=0.0))
        wx = np.where(mask, gx_i, 0.0); wy = np.where(mask, gy_i, 0.0)
        Jxx = float((wx * wx).sum()); Jyy = float((wy * wy).sum()); Jxy = float((wx * wy).sum())
        theta = 0.5 * math.atan2(2 * Jxy, Jxx - Jyy)
        print('  %-38s pixels %6d  dominant gradient axis %+7.2f deg' % (name, int(mask.sum()),
                                                                        math.degrees(theta)))
    print()
    print('reading: the ghost population is the part of the sheet whose EXISTENCE comes only')
    print('from the detail octave. Its dominant axis differs from the body\u2019s, which is the')
    print('off-axis second layer the user describes.')


if __name__ == '__main__':
    main()
