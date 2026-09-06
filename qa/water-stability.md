# Water stability: no-TAA mathematical record

This note covers only the deterministic spatial-frequency and SSR-boundary properties of
the current water code. It is not Minecraft visual evidence and cannot establish that the
result has no visible shimmer. Runtime acceptance remains separate.

The numbers are reproduced by `python qa/tools/water_stability.py` using the constants in
`shaders/global/water/surface.glsl`.

## Analytic wave field

At `WATER_WAVE_HEIGHT=100` and `WATER_WAVE_SPEED=100`, the five layers are:

| layer | wavelength (blocks) | direction XZ | amplitude (blocks) | speed factor | angular speed (rad/s) | period (s) |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 18.0 | (0.970143, 0.242536) | 0.100 | 0.36 | 0.666179 | 9.432 |
| 1 | 9.0 | (-0.554700, 0.832050) | 0.052 | 0.48 | 1.256158 | 5.002 |
| 2 | 4.5 | (0.196116, -0.980581) | 0.025 | 0.64 | 2.368635 | 2.653 |
| 3 | 2.2 | (0.780869, 0.624695) | 0.011 | 0.86 | 4.552097 | 1.380 |
| 4 | 1.1 | (-0.894427, -0.447214) | 0.004 | 1.12 | 8.383901 | 0.749 |

For wave number `k=2*pi/wavelength`, the shader estimates phase change across a pixel as

```text
p = max(abs(k * dot(direction, dFdx(worldPos.xz))),
        abs(k * dot(direction, dFdy(worldPos.xz))))
```

and multiplies its analytic slope by

```text
w(p) = 1 - smoothstep(0.35*pi, pi, p).
```

Attenuation therefore begins when the directional pixel footprint is `0.175*wavelength`
and reaches zero at `0.5*wavelength`, the two-samples-per-cycle Nyquist boundary:

| wavelength | attenuation starts (blocks/pixel) | zero detail (blocks/pixel) |
|---:|---:|---:|
| 18.0 | 3.1500 | 9.0000 |
| 9.0 | 1.5750 | 4.5000 |
| 4.5 | 0.7875 | 2.2500 |
| 2.2 | 0.3850 | 1.1000 |
| 1.1 | 0.1925 | 0.5500 |

`smoothstep` has value and first derivative equal at both clamped boundaries. Consequently
`w`, the weighted analytic slope, and the complementary roughness contribution are C1 at
`0.35*pi` and `pi`. This statement applies to the transfer function. The GPU derivative
estimate itself is local to fragment quads and can change across primitive boundaries.

No `frameCounter` or random temporal offset enters the wave field. Time appears only in the
continuous phase term `sqrt(9.81*k) * speed * time`.

## Defined grazing-view example

The following table is strictly limited to this pinhole-camera model:

- 1920x1080 image with square pixels and 70-degree vertical FOV;
- the image-centre ray points 10 degrees below the horizontal plane (a grazing view);
- distance is blocks along that centre ray to a horizontal water plane;
- no view bob, projection jitter, lens distortion, or triangle-edge discontinuity;
- `dx` is the adjacent horizontal-pixel footprint and `dz` is the larger of the two
  adjacent vertical-pixel footprints on the plane.

For centre-ray distance `s`, elevation `beta`, camera height `h=s*sin(beta)`, forward
distance `z=s*cos(beta)`, and one-pixel angular increment
`delta=atan(2*tan(FOVy/2)/1080)`, the script evaluates:

```text
dx = s * tan(delta)
dz = max(abs(h*cot(beta+delta)-z), abs(h*cot(beta-delta)-z)).
```

The per-layer entries below are `p/pi`, followed by the actual resolved weight `w(p)`.

| distance | dx | dz | phase/pi layers 0..4 | resolved weight layers 0..4 | roughness at height 100 |
|---:|---:|---:|---|---|---:|
| 32 | 0.04149 | 0.24072 | 0.006, 0.045, 0.105, 0.137, 0.196 | 1.000, 1.000, 1.000, 1.000, 1.000 | 0.035000 |
| 64 | 0.08299 | 0.48145 | 0.013, 0.089, 0.210, 0.273, 0.391 | 1.000, 1.000, 1.000, 1.000, 0.988 | 0.035498 |
| 128 | 0.16598 | 0.96289 | 0.026, 0.178, 0.420, 0.547, 0.783 | 1.000, 1.000, 0.968, 0.780, 0.260 | 0.078451 |
| 256 | 0.33195 | 1.92579 | 0.052, 0.356, 0.839, 1.094, 1.566 | 1.000, 1.000, 0.153, 0.000, 0.000 | 0.166521 |

These distances do not imply the same footprint for a different FOV, resolution, view
elevation, surface slope, or screen location. In particular, decreasing the 10-degree
elevation increases the vertical footprint rapidly.

Roughness is

```text
clamp(0.035 + 0.030*sum(1-w)
              + 0.55*sum(amplitude*k*(1-w)), 0.035, 0.30).
```

Its lower bound is exactly 0.035. If all five layers are unresolved, the result is 0.207052
at 25% wave height, 0.273209 at 100%, and the 0.30 clamp at 200%. The increase is continuous
because it consumes `1-w`; monotonic distance is expected for a fixed planar projection but
is not asserted for arbitrary geometry or derivative quads.

## Absolute-coordinate precision limit

The phase uses `worldPos.xz` after camera-relative position is added to the float
`cameraPosition`. This preserves chunk-to-chunk phase agreement at ordinary coordinates,
but it cannot preserve fine fractional positions at extreme coordinates. For IEEE-754
binary32, spacing is about 0.0625 block near 1,000,000, 1 block near 10,000,000, and 2 blocks
near 30,000,000. The 1.1-block and 2.2-block layers can therefore quantize or collapse long
before the world border.

Adding the existing float `cameraPosition` in a different order does not recover discarded
bits. A fundamental fix would require a CPU-provided high/low camera split, integer cell plus
fractional coordinates, or another phase-origin contract. That is an interface/architecture
change and is not made here.

## SSR bounded behavior

`water_raytrace` uses at most 24 depth-gather calls: up to 20 coarse candidates with step
length multiplied by 2 (capped at 12 view-space blocks), then up to four binary refinements
after a bracket is found. Each gather obtains the four base-level depth texels. A ray returns alpha
zero when it has no bracket, crosses the near/off-screen boundary, cannot gather inside a
half-texel-safe UV domain, encounters only sky depth, or fails the final view-space checks.

The final acceptance terms are:

```text
thickness   = 0.10 + min(1.50, hitDistance*0.012)
allowedSpan = max(0.35, 2*thickness)
0 <= sceneNearZ-hitRayZ <= thickness
sceneNearZ-sceneFarZ <= allowedSpan
```

The min/max gather span rejects mixed-depth silhouettes rather than accepting an implicitly
filtered depth. These inequalities bound the implemented acceptance rule; they do not prove
that every accepted screen-space hit corresponds to the hidden 3D surface.

Hit confidence uses `smoothstep(0, 0.10, distanceToNearestUvEdge)`: it is zero at the screen
edge and reaches one at 10% of screen width/height from the nearest edge, with continuous
value and first derivative. The module fades confidence rather than mixing colors itself;
E2 uses alpha to blend to the D2 sky result. Roughness similarly fades confidence from one
to zero across roughness 0.18..0.48. Failed hits contain no sky contribution.

The final color lookup is `textureLod(sceneColor, hitUv, 0.0)`. An explicit LOD avoids relying
on implicit derivatives after divergent ray-march control flow.

## Caustics footprint mitigation

`global/water/caustics.glsl` contains six layers, including effective tile sizes as small as
`0.225 x 0.300` blocks after its `3/2` scale. E2 now supplies
`pixelFootprint=max(length(dFdx(playerPos)), length(dFdy(playerPos)))` in world blocks per
pixel. C2 applies one conservative whole-field fade based on the shortest 0.225-block period:

```text
resolutionFade = 1 - smoothstep(0.175*0.225, 0.5*0.225, pixelFootprint).
```

This keeps the original six-layer crest sum and its amplitudes unchanged while resolved,
begins attenuation at 0.039375 block/pixel, and returns exactly zero from 0.1125 block/pixel.
Because the fade is applied after the exponent/log sum, no unresolved weight enters a
`log(0) * 0` expression and the old `-0.33` baseline is also multiplied to zero.

The former 64-block hard cutoff is replaced by
`1-smoothstep(48,64,length(playerPos))`; it reaches zero continuously at 64 blocks. These are
source-level frequency and boundary properties. Their Minecraft visual result has not been
judged, so this section does not claim that caustics are visibly stable.
