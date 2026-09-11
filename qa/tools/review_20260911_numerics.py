"""Independent review counterexamples; does not modify the shader pack.

The 1D volume is a cross-section of the six-neighbour GPU kernel with all other
neighbours dark. Time-dependent fire gain is omitted; it cannot change zero/nonzero.
"""
import math


def volume(frame, lava=False, seed_air=False):
    stamp = (1 - (frame & 1)) << 16  # actual GLSL expression
    raw = [stamp if seed_air else 0 for _ in range(12)]
    raw[0] = stamp | (11 | 256 if lava else 9)
    light = [0.0] * len(raw)
    for iteration in range(9):
        out = []
        for p, value in enumerate(raw):
            fresh = value & 0x30000 == stamp
            kind = value & 255
            color = 1.5 if fresh and kind in (9, 11) else 0.0
            if iteration and fresh and kind == 0 and not value & 256:
                for q in (p - 1, p + 1):
                    if 0 <= q < len(raw):
                        if raw[q] & 0x30000 != stamp or raw[q] & 256:
                            continue
                        color = max(color, light[q] * 0.72)
            out.append(color)
        light = out
    return light


for frame in (0, 1):
    result = volume(frame)
    print(f'GPU frame={frame} stamp={(1-(frame&1))<<16} fire={result[0]:.4f} adjacent unwritten air={result[1]:.4f}')
assert volume(0)[1] == 0 and volume(1)[1] > 1
print(f'Lava with explicitly fresh air: source={volume(0, True, True)[0]:.4f}, adjacent={volume(0, True, True)[1]:.4f}')
assert volume(0, True, True)[1] == 0
model_odd_stamp = (1 << 16) | (1 << 17)
print(f'Existing model odd stamp={model_odd_stamp}, masked written source={(model_odd_stamp | 9) & (1<<16)}: fresh is always false')

for stored in (0.6, 0.4):
    shade = 1 - min(1, max(0, (stored - 0.5) * 65536))
    print(f'Shaft receiver=.5 stored={stored}: correct visibility={int(stored >= .5)}, current shade={shade}')
distances = [(i + 0.5) * 40 / 7 * 0.5 for i in range(7)]
print(f'Shaft N=7 dither=.5: distances={distances}; attenuation divisors={[max(3,d*.1) for d in distances]}')
print(f'Shaft off-axis: axial distance=8, cos(view angle)=.5, actual distance={8/.5}; exceeds geometry distance=10')
for atlas in (256, 1024):
    print(f'Particle: 8px sprite / {atlas}px atlas / 4px projected size = derivative {8/atlas/4:.6f} < .09')
for focus in (0.2, 1.36):
    print(f'Final-colour caustic: focus={focus}, multiplier={1*.3 + focus*.7:.3f}; also scales ambient/emission')
print(f'ITT atmosphere 512*128*33*RGBA32F = {512*128*33*16/1024**2:.1f} MiB')
print('All counterexample assertions reproduced; this does not establish visual quality.')
