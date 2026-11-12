#ifndef LIB_WATER
#define LIB_WATER

#include "/lib/common.glsl"

// ---- Surface of open water ---------------------------------------------
// The height of the surface comes from three layers of the noise texture,
// a broad swell and two finer chops, each turned against the last and
// drifting its own way. Long sine waves made a regular washboard that read
// as a pattern laid over the lake; noise has no repeat to notice.
float nlWaterSurfaceHeight(vec2 p, float t, float fine) {
    vec2 a = p * 0.42 + vec2(t * 0.21, t * 0.08);
    vec2 b = mat2(0.80, -0.60, 0.60, 0.80) * p * 1.30 - vec2(t * 0.12, -t * 0.25);
    vec2 c = mat2(0.60, 0.80, -0.80, 0.60) * p * 3.60 + vec2(-t * 0.33, t * 0.19);
    float h = nlTexNoise(a) * 0.60 + nlTexNoise(b) * 0.28 * mix(0.35, 1.0, fine);
    if (fine > 0.0) h += nlTexNoise(c) * 0.12 * fine;
    return h;
}

// Normal of the water surface in world space. NdotV is the view against the
// flat surface, dist the distance from the eye.
// Towards grazing angles the waves fade out, so the far part of a lake turns
// into a calm mirror instead of a field of sparkling noise. The finer chops
// fade with distance as well: further than a few dozen blocks they are
// smaller than a pixel, and what reached the screen of them was noise that
// threw every reflection on the open sea into speckles.
vec3 nlWaterSurfaceNormal(vec3 worldPos, float t, float NdotV, float dist) {
    // Layers of water at different heights should not wave in step
    vec2 p = worldPos.xz + worldPos.y * 0.2;
    float fine = 1.0 - smoothstep(12.0, 48.0, dist);
    const float e = 0.04;
    float h  = nlWaterSurfaceHeight(p, t, fine);
    float hx = nlWaterSurfaceHeight(p + vec2(e, 0.0), t, fine);
    float hz = nlWaterSurfaceHeight(p + vec2(0.0, e), t, fine);
    float strength = 0.45 * WATER_ROUGHNESS * (1.0 - pow(1.0 - NdotV, 6.0))
                   * mix(1.0, 0.45, smoothstep(24.0, 120.0, dist));
    return normalize(vec3(-(hx - h) / e * strength, 1.0, -(hz - h) / e * strength));
}

// ---- Rain on standing water --------------------------------------------
// Rings spreading from raindrops. Every cell of a grid half a block wide
// gets one drop at a time, at a random spot near its middle and a random
// moment; the ring grows out from there, flattens and fades, and the next
// drop lands somewhere else. Two grids over each other keep the rhythm
// from showing.
float nlRippleLayer(vec2 p, float t) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    float seed = nlHash12(cell);
    float life = t * 0.85 + seed;
    float age = fract(life);
    vec2 drop = cell + floor(life) * 0.37;
    vec2 at = 0.5 + (vec2(nlHash12(drop + 3.1), nlHash12(drop + 7.7)) - 0.5) * 0.2;
    float d = length(f - at) - age * 0.40;
    float fade = (1.0 - age) * (1.0 - age);
    return exp(-d * d * 900.0) * fade;
}

float nlRippleHeight(vec2 p, float t) {
    return nlRippleLayer(p * 2.0, t) + nlRippleLayer(p * 2.0 + vec2(0.5, 0.31), t + 0.47);
}

// Normal of standing water in world space with the rain rings on it.
// strength 0 gives the flat surface.
vec3 nlRainRippleNormal(vec3 worldPos, float t, float strength) {
    if (strength < 0.001) return vec3(0.0, 1.0, 0.0);
    vec2 p = worldPos.xz;
    const float e = 0.015;
    float h  = nlRippleHeight(p, t);
    float hx = nlRippleHeight(p + vec2(e, 0.0), t);
    float hz = nlRippleHeight(p + vec2(0.0, e), t);
    float s = 0.012 * strength;
    return normalize(vec3(-(hx - h) / e * s, 1.0, -(hz - h) / e * s));
}

// ---- Puddles -----------------------------------------------------------
// Where water stands on the ground while it rains: patches in the low spots
// of a slow noise, on faces open to the sky and turned upwards. amount
// grows with the rain; at the start only the deepest patches fill.
float nlPuddleMask(vec2 worldXZ, float amount) {
    if (amount < 0.001) return 0.0;
    float n = nlTexNoise(worldXZ * 0.09) * 0.65 + nlTexNoise(worldXZ * 0.31 + 17.0) * 0.35;
    return smoothstep(0.50, 0.58, n + (amount - 0.5) * 0.6);
}

#endif
