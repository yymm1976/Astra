#!/usr/bin/env python3
"""Independent software/ideal hardware PCF visibility regression; standard library only.

This models the four-lobe QUALITY=2 comparison kernel only, not current QUALITY=0/1,
GPU precision, gather instruction counts, or coloured-material equivalence.
Identical lobe positions imply equal visibility, not necessarily a smoother image.
"""
from __future__ import annotations

import argparse
import math
import random
import statistics
from pathlib import Path


def fetch(field, x, y):
    n = len(field)
    return field[min(n - 1, max(0, y))][min(n - 1, max(0, x))]


def software(field, uv, depth, softness):
    """Original sixteen explicit corner weights, comparisons before accumulation."""
    n = len(field)
    result = 0.0
    for tap in range(16):
        lobe, corner = divmod(tap, 4)
        px = uv[0] * n - 0.5 + (-1 if lobe % 2 == 0 else 1) * softness / 2
        py = uv[1] * n - 0.5 + (-1 if lobe < 2 else 1) * softness / 2
        ix, iy = math.floor(px), math.floor(py)
        fx, fy = px - ix, py - iy
        cx, cy = corner % 2, corner // 2
        wx, wy = (fx if cx else 1 - fx), (fy if cy else 1 - fy)
        result += (depth <= fetch(field, ix + cx, iy + cy)) * wx * wy / 4
    return result


def comparison_linear(field, uv, depth):
    """Independent ideal sampler2DShadow: clamp coordinate, compare, interpolate."""
    n = len(field)
    u, v = (min(1 - 0.5 / n, max(0.5 / n, q)) for q in uv)
    x, y = u * n - 0.5, v * n - 0.5
    left, top = math.floor(x), math.floor(y)
    sx, sy = x - left, y - top
    a = float(depth <= fetch(field, left, top))
    b = float(depth <= fetch(field, left + 1, top))
    c = float(depth <= fetch(field, left, top + 1))
    d = float(depth <= fetch(field, left + 1, top + 1))
    upper, lower = a + sx * (b - a), c + sx * (d - c)
    return upper + sy * (lower - upper)


def hardware(field, uv, depth, softness):
    delta = softness / (2 * len(field))
    samples = [comparison_linear(field, (uv[0] + dx, uv[1] + dy), depth)
               for dx, dy in ((-delta, -delta), (delta, -delta),
                              (-delta, delta), (delta, delta))]
    return math.fsum(samples) / 4


def distribution(values):
    ordered = sorted(values)
    def percentile(q):
        i = (len(ordered) - 1) * q
        lo = math.floor(i)
        return ordered[lo] + (i - lo) * (ordered[math.ceil(i)] - ordered[lo])
    return (percentile(0.1), percentile(0.5), percentile(0.9),
            statistics.fmean(values), statistics.pstdev(values))


def material_light(all_v, opaque_v, caster, coloured, underwater):
    tint = caster[1:] if coloured else (1.0, 1.0, 1.0)
    if caster[0] < 0.999:
        tint = caster[1:] if underwater else (1.0, 1.0, 1.0)
    return tuple(all_v + c * max(opaque_v - all_v, 0) for c in tint)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--mean-tolerance', type=float, default=0.03)
    parser.add_argument('--max-tolerance', type=float, default=1e-12)
    parser.add_argument('--std-tolerance', type=float, default=1e-12)
    args = parser.parse_args()
    lines, failures = [], []
    rng = random.Random(20260911)
    n = 32
    patterns = {
        'hard_edge': [[0.2 if x < n // 2 else 0.8 for x in range(n)] for y in range(n)],
        'slope': [[0.1 + 0.8 * (x + 2 * y) / (3 * (n - 1)) for x in range(n)] for y in range(n)],
        'noise': [[rng.random() for x in range(n)] for y in range(n)],
    }
    points = [(rng.uniform(-0.05, 1.05), rng.uniform(-0.05, 1.05), rng.random()) for _ in range(2048)]
    # Borders, centres, half-texel transitions, and exact comparison equality.
    points += [(x, y, z) for x in (-0.1, 0, 0.5/n, 0.5, 1-0.5/n, 1, 1.1)
               for y in (0, 0.5/n, 0.5, 1-0.5/n, 1) for z in (0, 0.2, 0.5, 0.8, 1)]
    lines.append('Ideal comparison PCF; same four lobes; clamp-to-edge; LEQUAL.')
    lines.append('Each distribution: p10 p50 p90 mean stddev; all softness options covered.')
    worst = 0.0
    for name, field in patterns.items():
        for softness in (1, 2, 4, 8, 16):
            sw = [software(field, (x, y), z, softness) for x, y, z in points]
            hw = [hardware(field, (x, y), z, softness) for x, y, z in points]
            a, b = distribution(sw), distribution(hw)
            error = max(abs(x-y) for x, y in zip(sw, hw))
            worst = max(worst, error)
            passed = (abs(a[3]-b[3]) <= args.mean_tolerance and
                      b[4] <= a[4] + args.std_tolerance and error <= args.max_tolerance)
            lines += [f'{name} softness={softness} n={len(points)}',
                      '  software ' + ' '.join(f'{v:.9f}' for v in a),
                      '  hardware ' + ' '.join(f'{v:.9f}' for v in b),
                      f'  max_abs={error:.3e} ' + ('PASS' if passed else 'FAIL')]
            if not passed:
                failures.append(f'{name}/{softness}')
    # A depth-first implementation gives 1, but comparison-first must give 0.5.
    if comparison_linear([[0.2, 0.8], [0.2, 0.8]], (0.5, 0.5), 0.5) != 0.5:
        failures.append('compare-before-filter')
    # Lazy material fetch must preserve the software output, including air-side water.
    for av, ov in ((0, 0), (0, 1), (1, 1)):
        for caster in ((1.0, 0.2, 0.6, 0.9), (0.4, 0.2, 0.6, 0.9)):
            for coloured in (False, True):
                for underwater in (False, True):
                    lazy = caster if ov > av else (1.0, 0.0, 0.0, 0.0)
                    if material_light(av, ov, caster, coloured, underwater) != material_light(av, ov, lazy, coloured, underwater):
                        failures.append('lazy-material')
    lines.append('Compare-before-filter and default lazy-material contracts: ' + ('FAIL' if failures else 'PASS'))
    lines.append(f'Tolerances: mean={args.mean_tolerance}, max_abs={args.max_tolerance}, std_slack={args.std_tolerance}')
    lines.append(f'Overall max_abs={worst:.3e}; FAIL={len(failures)}')
    lines.append('Scope: ideal visibility only. Use shadow_material_probe.py for actual GPU per-texel RGB equivalence.')
    if failures:
        lines.append('Failures: ' + ', '.join(failures))
    output = '\n'.join(lines) + '\n'
    print(output, end='')
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding='utf-8')
    return int(bool(failures))


if __name__ == '__main__':
    raise SystemExit(main())
