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
float solas_water_height(vec3 p, vec2 offset) {
    vec2 wind = vec2(frameTimeCounter) * 0.5 * 1.5;
    p.xz -= p.y * 0.2;
    float a = textureLod(solasWaterNoise, (p.xz - wind) / 256.0 + offset / 256.0, 0.0).g;
    float b = textureLod(solasWaterNoise, (p.xz + wind) / 48.0 + offset / 256.0, 0.0).g;
    return mix(a, b, 0.40);
}
float solas_water_caustics(vec3 p) {
    float h = solas_water_height(p, vec2(0.0));
    float xa = (solas_water_height(p, vec2(1.0, 0.0)) - h);
    float xb = (solas_water_height(p, vec2(-1.0, 0.0)) - h);
    float ya = (solas_water_height(p, vec2(0.0, 1.0)) - h);
    float yb = (solas_water_height(p, vec2(0.0, -1.0)) - h);
    return max((xa * -xb + ya * -yb) * 96.0, 0.0);
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
#endif

// ---------------------------------------------------------------------------
// Geometric caustics, ported from IterationT 3.2.0
// (Lib/BasicFounctions/Sunlight_Shadow.glsl::CalculateWaterCaustics and
//  Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl::CalculateWaterCaustics).
//
// The reference does not tint a shadow map: it asks where the light actually lands.
// Take the wave normal above the receiver, refract the vertical light ray through it,
// and measure how close the refracted ray converges to the receiver. Light that focuses
// there is bright, light that spreads is dark. That is a physical caustic, and it needs
// no shadow-map cooperation - which is exactly why the previous shadow-map-tint attempt
// could not be made to show.
//
// Astra adapter: the reference reads the wave normal from a buffer it stores a tiled
// normal field in (its colortex7). Astra has no such buffer, so the normal is derived
// from the same Solas height field this file already uses, by central differences. Same
// physics, one fewer buffer dependency.
vec3 astra_wave_normal_at(vec3 p) {
    float x = solas_water_height(p, vec2(1.0, 0.0)) - solas_water_height(p, vec2(-1.0, 0.0));
    float z = solas_water_height(p, vec2(0.0, 1.0)) - solas_water_height(p, vec2(0.0, -1.0));
    // Slope scale, calibrated offline against the reference's own focus test.
    // GLSL's refract(I, N, 1.0) degenerates to the mirror formula I - 2*dot(N,I)*N, so the
    // refracted ray's horizontal displacement is about twice the wave slope. The focus
    // test saturates once that displacement leaves roughly +/-0.14, and the raw central
    // difference of this height field has a median magnitude of 0.088. Sweeping the scale
    // against the real texture gives the widest caustic contrast at 0.75 (p10 0.21,
    // p50 0.46, p90 0.72, peak 1.36, dynamic range 3.4x); 6.0 saturated almost every
    // sample to the dark floor, which is what made the first attempt a flat wash.
    return normalize(vec3(-x * 0.75, 1.0, -z * 0.75));
}

float astra_water_caustics_focus(vec3 worldPos) {
    // Static spatial dither. The reference uses a temporal blue-noise offset, which it can
    // afford because it accumulates over frames; Astra has no TAA, so a per-frame offset
    // would simply flicker. The 3x3 tap grid already supplies the spatial spread.
    vec2 dither = vec2(0.5);
    vec3 lookupCenter = worldPos + vec3(0.0, 1.0, 0.0);

    // Light direction refracted through the flat water interface, as the reference does.
    vec3 sunWorld = normalize(view_player(lightVector));   // Astra: world-space sun
    vec3 lightVector = refract(sunWorld, vec3(0.0, -1.0, 0.0), 1.0 / 1.2);

    float caustics = 0.0;
    for (float i = -1.0; i <= 1.0; i++) {
        for (float j = -1.0; j <= 1.0; j++) {
            vec3 lookupPoint = lookupCenter;
            lookupPoint.xz += (dither + vec2(i, j)) * 0.1;

            vec3 wavesNormal = astra_wave_normal_at(lookupPoint);
            vec3 refractVector = refract(vec3(0.0, 1.0, 0.0), wavesNormal, 1.0);
            vec3 collisionPoint = lookupPoint - refractVector / refractVector.y;
            collisionPoint -= worldPos;

            float dist = dot(collisionPoint, collisionPoint) * 7.1;
            caustics += 1.0 - clamp(dist * 7.0, 0.0, 1.0);
        }
    }
    // Reference tail: partly disabled above water, raw underwater.
    return mix(caustics * 0.16 + 0.2, 1.0, 0.3 - 0.3 * float(isEyeInWater));
}

// Underwater shaft modulation. The reference multiplies its volumetric march by
// caustics^3, which is what turns an even cone into the soft banded columns the user
// described. Kept here so shafts and seabed caustics share one field (their world phases
// therefore match, which is the whole point of the reference's shared normal source).
float astra_water_caustics_shaft_at(vec3 poseWorld) {
    float c = astra_water_caustics_focus(poseWorld);
    return c * c * c;
}
