# Astra P0-1 diagnostic: replicate astra_minishita_sky + gradient sky + final chain
# (exposure -> uchimura -> srgb_encode -> saturation 112 -> contrast 104 -> clamp)
# Goal: quantify how dark the Minishita zenith is at ~noon vs the gradient palette,
# and size a calibration gain for sky_minishita.glsl.
import math

PI = math.pi
PLANET_RADIUS = 1.0
ATMOS_RADIUS = 1.035
RAYLEIGH_HEIGHT = 0.010
MIE_HEIGHT = 0.0040
BETA_R = (5.6, 12.8, 30.0)
BETA_M = 3.4
MIE_G = 0.76

def vadd(a, b): return tuple(x + y for x, y in zip(a, b))
def vmul(a, b): return tuple(x * y for x, y in zip(a, b))
def vs(a, s): return tuple(x * s for x in a)
def vdot(a, b): return sum(x * y for x, y in zip(a, b))
def vlen(a): return math.sqrt(vdot(a, a))
def vnorm(a):
    l = vlen(a)
    return tuple(x / l for x in a)

def atmos_exit(origin, direction, radius):
    b = vdot(origin, direction)
    c = vdot(origin, origin) - radius * radius
    return max(0.0, -b + math.sqrt(max(0.0, b * b - c)))

def atmos_density(pos):
    h = max(0.0, vlen(pos) - PLANET_RADIUS)
    return (math.exp(-h / RAYLEIGH_HEIGHT), math.exp(-h / MIE_HEIGHT))

def phase_rayleigh(ct):
    return 3.0 * (1.0 + ct * ct) / (16.0 * PI)

def phase_mie(ct):
    g2 = MIE_G * MIE_G
    base = max(1.0 + g2 - 2.0 * MIE_G * ct, 0.006)
    return 3.0 * (1.0 - g2) * (1.0 + ct * ct) / (8.0 * PI * (2.0 + g2) * base * math.sqrt(base))

def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)

def minishita_sky(world_dir, sun_y, sky_visibility_day=1.0, rain=0.0):
    vd = vnorm((world_dir[0], max(world_dir[1], -0.045), world_dir[2]))
    observer = (0.0, PLANET_RADIUS + 0.0008, 0.0)
    dist_top = atmos_exit(observer, vd, ATMOS_RADIUS)
    daylight = 1.0 if sun_y >= 0.0 else 0.0
    src = vnorm(vs((0.0, 1.0, 0.0), 1.0)) if daylight else vnorm((0.0, -1.0, 0.0))
    # general sun direction: sun at elevation asin(sun_y) along +Z for simplicity
    el = math.asin(min(1.0, max(-1.0, sun_y)))
    src = (0.0, math.sin(el), math.cos(el)) if daylight else (0.0, -math.sin(el), -math.cos(el))
    src = vnorm(src)
    source_strength = 1.0 if daylight else 0.055 + 0.025 * 0.5
    mu = vdot(vd, src)
    pr = phase_rayleigh(mu)
    pm = phase_mie(mu)
    opt_view = [0.0, 0.0]
    scat_r = [0.0, 0.0, 0.0]
    scat_m = 0.0
    segment = dist_top * 0.5
    for i in range(2):
        pos = vadd(observer, vs(vd, segment * (i + 0.5)))
        dens = atmos_density(pos)
        opt_view[0] += dens[0] * segment
        opt_view[1] += dens[1] * segment
        ld = atmos_exit(pos, src, ATMOS_RADIUS)
        d2 = atmos_density(vadd(pos, vs(src, 0.5 * ld)))
        opt_light = (d2[0] * ld, d2[1] * ld)
        optical = (opt_view[0] + opt_light[0], opt_view[1] + opt_light[1])
        ext = tuple(math.exp(-(BETA_R[c] * optical[0] + BETA_M * optical[1])) for c in range(3))
        for c in range(3):
            scat_r[c] += dens[0] * ext[c] * segment
        scat_m += dens[1] * ((ext[0] + ext[1] + ext[2]) / 3.0) * segment  # approx: shader uses per-channel extinction
    # NOTE: shader applies per-channel extinction to Mie too; do it properly:
    # (recompute Mie per channel)
    opt_view = [0.0, 0.0]
    scat_m_ch = [0.0, 0.0, 0.0]
    for i in range(2):
        pos = vadd(observer, vs(vd, segment * (i + 0.5)))
        dens = atmos_density(pos)
        opt_view[0] += dens[0] * segment
        opt_view[1] += dens[1] * segment
        ld = atmos_exit(pos, src, ATMOS_RADIUS)
        d2 = atmos_density(vadd(pos, vs(src, 0.5 * ld)))
        optical = (opt_view[0] + d2[0] * ld, opt_view[1] + d2[1] * ld)
        ext = tuple(math.exp(-(BETA_R[c] * optical[0] + BETA_M * optical[1])) for c in range(3))
        for c in range(3):
            scat_m_ch[c] += dens[1] * ext[c] * segment
    radiance = tuple((scat_r[c] * BETA_R[c] * pr + scat_m_ch[c] * BETA_M * pm) * source_strength for c in range(3))
    night = 1.0 - sky_visibility_day
    night_add = 0.35 + 0.65 * max(vd[1], 0.0)
    radiance = vadd(radiance, vs((0.0035, 0.0065, 0.014), night * night_add))
    radiance = vs(radiance, 1.0 + (0.58 - 1.0) * rain)
    ground = tuple(g + (r - g) * 0.32 for g, r in zip((0.008, 0.011, 0.016), radiance))
    t = smoothstep(-0.045, 0.018, world_dir[1])
    out = tuple(max(0.0, g + (r - g) * t) for g, r in zip(ground, radiance))
    return out

def gradient_sky(world_dir, sky_visibility_day=1.0):
    up = min(1.0, max(0.0, world_dir[1]))
    horizon = 2.0 ** (-7.0 * up)
    day = sky_visibility_day
    nz, nh = (0.004, 0.009, 0.024), (0.018, 0.024, 0.045)
    dz, dh = (0.075, 0.20, 0.52), (0.40, 0.58, 0.78)
    sky = tuple((nzc + (dzc - nzc) * day) * (1 - horizon) + (nhc + (dhc - nhc) * day) * horizon
                for nzc, dzc, nhc, dhc in zip(nz, dz, nh, dh))
    below = tuple(b + (s - b) * 0.28 for b, s in zip((0.006, 0.009, 0.014), sky))
    t = smoothstep(-0.04, 0.025, world_dir[1])
    return tuple(max(0.0, b + (s - b) * t) for b, s in zip(below, sky))

def uchimura(x):
    P, a, m, l, c, b = 1.0, 1.0, 0.22, 0.4, 1.33, 0.0
    l0 = ((P - m) * l) / a
    L0 = m - m / a
    L1 = m + (1.0 - m) / a
    S0 = m + l0
    S1 = m + a * l0
    C2 = (a * P) / (P - S1)
    CP = -C2 / P
    out = []
    for v in x:
        w0 = 1.0 - smoothstep(0.0, m, v)
        w2 = 1.0 if v >= m + l0 else 0.0
        w1 = 1.0 - w0 - w2
        T = m * (v / m) ** c + b if v > 0 else b
        S = P - (P - S1) * math.exp(CP * (v - S0))
        L = m + a * (v - m)
        out.append(T * w0 + L * w1 + S * w2)
    return tuple(out)

def srgb_encode(c):
    out = []
    for v in c:
        if v < 0.0031308:
            out.append(v * 12.92)
        else:
            out.append(1.055 * max(v, 0.0) ** (1.0 / 2.4) - 0.055)
    return tuple(out)

def luminance(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]

def final_chain(linear_hdr, exposure=1.0, saturation=1.12, contrast=1.04):
    x = vs(linear_hdr, exposure)
    x = uchimura(x)          # uchimura returns display-referred
    x = srgb_encode(x)       # Astra double-encodes (SC-16 open issue) - replicate as-is
    lum = luminance(x)
    x = tuple(lum + (v - lum) * saturation for v in x)
    x = tuple((v - 0.5) * contrast + 0.5 for v in x)
    return tuple(min(1.0, max(0.0, v)) for v in x)

SUN_Y = 0.985  # ~11:17, sun ~10 deg off zenith
print("view-elev | minishita linear -> display          | gradient linear -> display")
for ey, name in [(1.0, "zenith "), (0.5, "elev30 "), (0.2, "elev11 "), (0.05, "horizon")]:
    d = vnorm((0.0, ey, 1.0))
    m = minishita_sky(d, SUN_Y)
    g = gradient_sky(d)
    md = final_chain(m)
    gd = final_chain(g)
    print(f"{name} | ({m[0]:.4f},{m[1]:.4f},{m[2]:.4f}) -> ({md[0]:.3f},{md[1]:.3f},{md[2]:.3f}) | "
          f"({g[0]:.3f},{g[1]:.3f},{g[2]:.3f}) -> ({gd[0]:.3f},{gd[1]:.3f},{gd[2]:.3f})")

# gain needed for minishita zenith luminance to match gradient zenith luminance (linear)
mz = minishita_sky((0.0, 1.0, 0.0), SUN_Y)
gz = gradient_sky((0.0, 1.0, 0.0))
gain = luminance(gz) / luminance(mz)
print(f"\nzenith linear lum: minishita {luminance(mz):.5f}  gradient {luminance(gz):.4f}  -> gain x{gain:.2f}")
mh = minishita_sky(vnorm((0.0, 0.05, 1.0)), SUN_Y)
gh = gradient_sky(vnorm((0.0, 0.05, 1.0)))
print(f"horizon linear lum: minishita {luminance(mh):.5f}  gradient {luminance(gh):.4f}  -> gain x{luminance(gh)/luminance(mh):.2f}")

# try candidate gains: show display values at zenith/elev30/horizon
for gain_try in (8.0, 10.0, 12.0):
    row = []
    for ey in (1.0, 0.5, 0.05):
        m = minishita_sky(vnorm((0.0, ey, 1.0)), SUN_Y)
        row.append(final_chain(vs(m, gain_try)))
    print(f"gain {gain_try:>4}: zenith ({row[0][0]:.3f},{row[0][1]:.3f},{row[0][2]:.3f}) "
          f"elev30 ({row[1][0]:.3f},{row[1][1]:.3f},{row[1][2]:.3f}) horizon ({row[2][0]:.3f},{row[2][1]:.3f},{row[2][2]:.3f})")
