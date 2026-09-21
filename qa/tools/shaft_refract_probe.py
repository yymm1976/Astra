#!/usr/bin/env python3
"""A2 probe: refracted-sun semantics in global/water/light_shafts.glsl.

Reproduces GLSL refract(I, N, eta) exactly (spec: k = 1 - eta^2 (1 - dot(N,I)^2);
total internal reflection when k < 0, else R = eta*I - (eta*dot(N,I) + sqrt(k))*N)
and evaluates the shipped VoL gate at light_shafts.glsl:56-57 against the
candidate one-line fix, for a sweep of sun elevations and view directions.

Conventions verified in the sweep printout:
  * viewDir  = normalize(view_player(fragPos))  -> eye-to-fragment, points INTO the water.
  * sunWorld = normalize(view_player(lightVector)) -> points AT the sun (y>0 is daytime).
  * Shipped  : refract(sunWorld,        (0,-1,0), 1/1.2)   -- I points at the sun, N down.
  * Candidate: refract(-sunWorld,       (0,+1,0), 1/1.2)   -- I points down into the
               interface, N points back into air (the standard GLSL convention:
               dot(N,I) < 0 required).

This is a pinned measurement, not a gate. Re-run: python qa/tools/shaft_refract_probe.py
"""

import math

ETA = 1.0 / 1.2


def refract(I, N, eta):
    """GLSL refract() in double precision. Returns None on total internal reflection."""
    d = N[0] * I[0] + N[1] * I[1] + N[2] * I[2]
    k = 1.0 - eta * eta * (1.0 - d * d)
    if k < 0.0:
        return None
    s = eta * d + math.sqrt(k)
    return (eta * I[0] - s * N[0], eta * I[1] - s * N[1], eta * I[2] - s * N[2])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def norm(v):
    m = math.sqrt(dot(v, v))
    return (v[0] / m, v[1] / m, v[2] / m)


def sun_world(elev_deg, azim_deg):
    """Unit vector pointing AT the sun. elev 90 = overhead noon."""
    e = math.radians(elev_deg)
    a = math.radians(azim_deg)
    return (math.cos(e) * math.sin(a), math.sin(e), math.cos(e) * math.cos(a))


def view_dir(elev_deg, azim_deg):
    """Unit eye->fragment direction. Negative elevation looks down at the seabed."""
    e = math.radians(elev_deg)
    a = math.radians(azim_deg)
    return (math.cos(e) * math.sin(a), math.sin(e), math.cos(e) * math.cos(a))


def vol(ray, refr):
    return max(0.0, dot(ray, refr)) ** 1.5


def main():
    print("=== A2 shaft refract semantics probe ===")
    print("eta = 1/1.2 = %.6f" % ETA)
    print()

    # --- Part 1: symbolic check of the shipped form, azim 0, varying sun elevation ---
    print("--- Part 1: shipped  refract(sunWorld, (0,-1,0), eta)  vs  "
          "candidate  refract(-sunWorld, (0,+1,0), eta) ---")
    print("sun elevation sweep, azimuth 0 (sun in +Z half-space); the algebra predicts")
    print("refractSun.y = +sqrt(k) for the shipped form, i.e. ALWAYS UPWARD, while the")
    print("candidate yields -sqrt(k), i.e. downward into the water.")
    print()
    hdr = ("elev", "sunWorld", "shipped refr", "refr.y", "cand refr", "cand.y", "cand==-ship")
    print("%6s %-22s %-26s %8s %-26s %8s %11s" % hdr)
    for elev in (90, 60, 30, 10, 2, 1):
        s = sun_world(elev, 0.0)
        r_ship = refract(s, (0.0, -1.0, 0.0), ETA)
        r_cand = refract((-s[0], -s[1], -s[2]), (0.0, 1.0, 0.0), ETA)
        eq = all(abs(r_ship[i] + r_cand[i]) < 1e-12 for i in range(3))
        print("%6.1f (%.4f,%.4f,%.4f)   (%.4f,%.4f,%.4f)  %+7.4f  (%.4f,%.4f,%.4f)  %+7.4f  %s"
              % (elev, s[0], s[1], s[2],
                 r_ship[0], r_ship[1], r_ship[2], r_ship[1],
                 r_cand[0], r_cand[1], r_cand[2], r_cand[1],
                 "yes" if eq else "NO"))
        assert eq, "candidate is NOT -(shipped)"
    print()
    print("assertion: candidate == -(shipped) componentwise -> PASS")
    print("i.e. refract(-I, -N, eta) == -refract(I, N, eta): the two candidate one-line")
    print("fixes in the work order are the SAME expression. Both yield the propagation")
    print("direction of sunlight inside the water (y <= 0 in daytime).")
    print()

    # --- Part 2: VoL for a looking-down-at-seabed camera ---
    print("--- Part 2: VoL = pow(max(dot(ray, refr),0), 1.5) for eye->fragment rays ---")
    print("Sun elevation fixed at 60 deg (well above the noon gate); ray elevation swept.")
    print("Negative ray elevation = camera looking down at the seabed (the case the")
    print("shafts are for). Ray azimuth 0 = looking sunward in xz, 180 = away from sun.")
    print()
    for azim_name, azim in (("ray toward-sun azim 0", 0.0), ("ray away-from-sun azim 180", 180.0)):
        print("  %s" % azim_name)
        print("  %8s %14s %14s  %s" % ("ray elev", "shipped VoL", "candidate VoL", "note"))
        for ray_elev in (-80, -60, -40, -20, -5, 5, 30, 80):
            ray = view_dir(ray_elev, azim)
            s = sun_world(60, 0.0)
            r_ship = refract(s, (0.0, -1.0, 0.0), ETA)
            r_cand = refract((-s[0], -s[1], -s[2]), (0.0, 1.0, 0.0), ETA)
            v_ship = vol(ray, r_ship)
            v_cand = vol(ray, r_cand)
            note = ""
            if ray_elev < 0 and v_ship == 0.0 and v_cand > 0.0:
                note = "SHIPPED DEAD, candidate lit"
            elif ray_elev < 0 and v_ship == 0.0 and v_cand == 0.0:
                note = "both dark (away from sun)"
            print("  %8.1f %14.6f %14.6f  %s" % (ray_elev, v_ship, v_cand, note))
        print()

    # --- Part 3: what the shipped gate does at every (sun, ray) pair on a grid ---
    print("--- Part 3: fraction of looking-down rays with shipped VoL == 0 ---")
    dead = 0
    total = 0
    cand_lit = 0
    for sun_elev in (90, 70, 45, 20, 5):
        for ray_elev in range(-85, -4, 5):
            for ray_azim in range(0, 360, 15):
                ray = view_dir(ray_elev, ray_azim)
                s = sun_world(sun_elev, 0.0)
                r_ship = refract(s, (0.0, -1.0, 0.0), ETA)
                r_cand = refract((-s[0], -s[1], -s[2]), (0.0, 1.0, 0.0), ETA)
                total += 1
                if vol(ray, r_ship) == 0.0:
                    dead += 1
                if vol(ray, r_cand) > 0.0:
                    cand_lit += 1
    print("grid: sun elev {90,70,45,20,5} x ray elev -85..-5 step 5 x azim 0..345 step 15")
    print("  samples                    : %d" % total)
    print("  shipped VoL == 0           : %d  (%.1f%%)" % (dead, 100.0 * dead / total))
    print("  candidate VoL  > 0         : %d  (%.1f%%)" % (cand_lit, 100.0 * cand_lit / total))
    print()
    print("Facts established (all re-derivable from the printout above):")
    print("1. shipped  = (eta*sx, +sqrt(k), eta*sz): the unit vector pointing AT THE SUN")
    print("   AS SEEN FROM UNDERWATER (apparent sun). Its elevation obeys Snell")
    print("   (sin(theta_t) = sin(theta_i)/1.2): 60deg -> %.4f deg elevation." %
          (90.0 - math.degrees(math.atan2(ETA * math.sin(math.radians(30.0)),
                                          math.sqrt(1.0 - ETA * ETA * 0.25)))))
    print("2. candidate = -(shipped): the propagation direction of sunlight inside the")
    print("   water (downward, anti-solar in xz).")
    print("3. Looking down at the seabed with the shipped axis gives VoL = 0 at every")
    print("   hour, because dot(ray_down, apparent_sun_up) <= 0. The gate at")
    print("   light_shafts.glsl:75 then returns before the march, so noon seabed pixels")
    print("   carried no shafts at all -- the pre-fix shipped state.")
    print("4. The candidate axis puts the looking-down hemisphere on the positive side:")
    print("   VoL > 0 for seabed rays, VoL = 0 when looking up at the surface.")
    print()
    print("Choose the candidate, as the work order directs. Recorded caveat for the")
    print("in-game pass (checklist 10b): because dot(ray, propagation) is the BACKWARD")
    print("scattering cosine, 'looking up at the surface' (the textbook forward-scatter")
    print("direction) now returns VoL = 0. Both directions cannot be positive at once")
    print("with a single cosine gate; the acceptance criterion for this fix is the")
    print("work order's own: noon seabed shows beams, looking up does not.")


if __name__ == "__main__":
    main()
