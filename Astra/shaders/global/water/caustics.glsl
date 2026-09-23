#ifndef ASTRA_GLOBAL_WATER_CAUSTICS_GLSL
#define ASTRA_GLOBAL_WATER_CAUSTICS_GLSL
// Adapted from Solas V2.2b lib/water/waterCaustics.glsl by Septonious.
// Uses its supplied noise image and defaults; see THIRD-PARTY.md.
// solasWaterNoise is declared in lib/uniforms.glsl.
// The reference evaluates the five-tap curvature on the FULL height field and uses a
// one-unit tap offset (WATER_NORMAL_OFFSET with the same 1/256 normalisation).
// 2026-09-11: Astra had scaled the height by 0.4 and halved the tap offset, which
// shrank the measured caustic field to p90 = 0.06 (max 0.18) - a flat wash instead of
// the reference's bright moving network, which is what the user saw as "no caustics".
//
// 2026-09-23 (underwater rewrite): this height field now drives the VISIBLE water
// surface only (solas_water_normal above, and through it program/water.glsl). The
// caustic field below is a separate analytic wave surface - see the block after it for
// why the noise-derived field could not be turned into a focus network.
float solas_water_height(vec3 p, vec2 offset) {
    vec2 wind = vec2(frameTimeCounter) * 0.5 * 1.5;
    p.xz -= p.y * 0.2;
    float a = textureLod(solasWaterNoise, (p.xz - wind) / 256.0 + offset / 256.0, 0.0).g;
    float b = textureLod(solasWaterNoise, (p.xz + wind) / 48.0 + offset / 256.0, 0.0).g;
    return mix(a, b, 0.40);
}
// Solas waterNormals: four parallax steps, then the same height field used by caustics.
vec3 solas_water_normal(vec3 worldPos, vec3 face, vec3 tangent, vec3 binormal,
                        vec3 viewVector, float viewDistance, float fresnel) {
    for (int i = 0; i < 4; ++i) {
        float height = -1.25 * solas_water_height(worldPos, vec2(0.0)) + 0.25;
        worldPos.xz += height * viewVector.xy / max(viewDistance, 0.0001);
    }
    float x = (solas_water_height(worldPos, vec2(-0.5, 0.0)) - solas_water_height(worldPos, vec2(0.5, 0.0))) / 0.5;
    float y = (solas_water_height(worldPos, vec2(0.0, -0.5)) - solas_water_height(worldPos, vec2(0.0, 0.5))) / 0.5;
    return normalize(tangent * x + binormal * y + face * (1.0 - x*x - y*y - fresnel * 0.5));
}
// The include guard used to close here, leaving the geometric caustics below
// unprotected - any second include of this file would have redefined them
// (consolidated review E1 / Qoder F-19). The guard now closes at end of file.

// Analytic focusing proxy: the determinant of the small-slope landing map.
// This is evaluated at the projected receiver, not an inverse ray-density solve.
// Six nonuniform wave frequencies avoid the old arithmetic frequency ladder;
// their spectrum alone cannot establish the perceived pattern in Minecraft.
const float ASTRA_CAUSTIC_DROP = 6.0;        // effective air column over the receiver, blocks
const float ASTRA_CAUSTIC_JFLOOR = 0.06;     // folded areas saturate here (1/J -> 16.7)
const float ASTRA_CAUSTIC_SCALE = 0.21;      // field units per sqrt(1/|J| - 1)
const float ASTRA_CAUSTIC_MEDIAN = 0.10;     // consumers' shared neutral point (see above)
// The caster tint's own strength. Underwater the tint is the ONLY caustic path, and the
// shadow map's bilinear caster filtering averages the sharpest spots down, so the caster
// gets more headroom than the air-side 0.70; its own clamp is [0.80, 2.60] against
// lit.fsh's [0.70, 1.80].
const float ASTRA_CAUSTIC_CASTER_STRENGTH = 1.90;
// How strongly the field bands the beam along the march (global/water/light_shafts.glsl).
// 1.0 leaves the sample at its unmodulated weight at the neutral point (field 0.10) and
// doubles it at the field's bright half.
const float ASTRA_CAUSTIC_SHAFT_CONTRAST = 1.5;
// Curvature weights are preserved when changing the wavelength spacing.
const vec2 ASTRA_CAUSTIC_DIR[6] = vec2[6](vec2(0.9455, 0.3256),
                                          vec2(0.4226, 0.9063),
                                          vec2(-0.0523, 0.9986),
                                          vec2(-0.4848, 0.8746),
                                          vec2(-0.8387, 0.5446),
                                          vec2(-0.9848, 0.1736));
const float ASTRA_CAUSTIC_WAVENUMBER[6] = float[6](2.0 * 3.14159265359 / 1.500000,
                                                   2.0 * 3.14159265359 / 1.060660,
                                                   2.0 * 3.14159265359 / 0.866025,
                                                   2.0 * 3.14159265359 / 0.670820,
                                                   2.0 * 3.14159265359 / 0.566947,
                                                   2.0 * 3.14159265359 / 0.452267);
const float ASTRA_CAUSTIC_SLOPE[6] = float[6](0.0712000, 0.0430076, 0.0311448,
                                              0.0218889, 0.0170553, 0.0127254);
const float ASTRA_CAUSTIC_SPEED[6] = float[6](1.45, 2.05, 1.72, 2.72, 2.31, 3.28);
const float ASTRA_CAUSTIC_PHASE[6] = float[6](0.0, 1.7, 3.1, 0.9, 4.3, 2.2);

// grad h and the Hessian of the analytic wave surface, in one pass over the trains.
// slope = (dh/dx, dh/dz); hessian = (d2h/dx2, d2h/dz2, d2h/dxdz).
void astra_caustic_wave(vec2 p, float t, out vec2 slope, out vec3 hessian) {
    slope = vec2(0.0);
    hessian = vec3(0.0);
    for (int i = 0; i < 6; ++i) {
        vec2 dir = ASTRA_CAUSTIC_DIR[i];
        float amp = ASTRA_CAUSTIC_SLOPE[i];
        float phase = ASTRA_CAUSTIC_WAVENUMBER[i] * dot(dir, p)
                    + ASTRA_CAUSTIC_SPEED[i] * t + ASTRA_CAUSTIC_PHASE[i];
        float c = cos(phase);
        float second = -amp * ASTRA_CAUSTIC_WAVENUMBER[i] * sin(phase);
        slope += amp * c * dir;
        hessian.xy += vec2(second * dir.x * dir.x, second * dir.y * dir.y);
        hessian.z += second * dir.x * dir.y;
    }
}

// The caustic field. Name kept because program/lit.fsh (read-only in this round) calls it
// by this name; it is no longer the Solas expression.
//
// worldPos is a world-space point. The y term is the reference's own parallax
// convention (Solas waterCaustics.glsl: p.xz -= p.y * 0.2), kept so the network still
// slides with a receiver's depth instead of being one fixed vertical projection. Above
// water that is what makes the pattern track the column; underwater the caster path
// (program/shadow.fsh) samples the SURFACE, and the shadow projection places it on the
// bed, so the slide is not applied twice.
float solas_water_caustics(vec3 worldPos) {
    vec2 p = worldPos.xz - worldPos.y * 0.2;
    vec2 slope;
    vec3 hessian;
    astra_caustic_wave(p, frameTimeCounter, slope, hessian);
    float a = 0.25 * ASTRA_CAUSTIC_DROP;
    float jacobian = (1.0 + a * hessian.x) * (1.0 + a * hessian.y)
                   - (a * hessian.z) * (a * hessian.z);
    float convergence = 1.0 / max(abs(jacobian), ASTRA_CAUSTIC_JFLOOR) - 1.0;
    return ASTRA_CAUSTIC_SCALE * sqrt(max(convergence, 0.0));
}

// How strongly the caustic network modulates the DIRECT sun term. 0 disables the
// modulation, 1 applies the full field. Applied to direct radiance only - see the note in
// program/lit.fsh for why multiplying the finished colour was wrong.
const float ASTRA_CAUSTIC_STRENGTH = 0.70;
#endif
