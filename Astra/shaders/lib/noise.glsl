#ifndef ASTRA_LIB_NOISE_GLSL
#define ASTRA_LIB_NOISE_GLSL

// From Mellow v3.4 (MIT) by TheCMK - lib/noise.glsl (noise / noise_water / fbm_fast)
// Mechanical port; noise_water's WATER_NORMAL_* option macros mapped to Astra's
// WATER_WAVE_SPEED / WATER_WAVE_HEIGHT (design.md 3.2 naming). License: MIT - see THIRD-PARTY.md.
// Uniforms: noisetex, frameTimeCounter (lib/uniforms.glsl);
//           const int noiseTextureResolution (ENGINE KNOBS in lib/settings.glsl)

// Two-octave lookup: base texture minus a high-frequency detail cut
float noise(vec2 coords) {
    float color = texture(noisetex, (coords) / noiseTextureResolution * 0.75).x;
    float detail = texture(noisetex, (coords) / noiseTextureResolution * 5.0).x * 0.1;
    return max(color - detail, 0.0);
}

// Flowing water-surface normal offsets (two drifting lookups, large + small)
vec2 noise_water(vec2 coords) {
    float speed = WATER_WAVE_SPEED * 0.01;
    vec2 color = (texture(noisetex, (coords + frameTimeCounter * 0.2 * speed) / 24.0).yz * 2.0 - 1.0) * 0.05;
    color += (texture(noisetex, (coords - frameTimeCounter * 0.8 * speed) / 64.0).yz * 2.0 - 1.0) * 0.10;
    return color * (WATER_WAVE_HEIGHT * 0.01);
}

// Value FBM on the noisetex hardware bilinear lookup (design.md 5: prefer table lookups over hash)
float fbm_fast(vec2 x, int detail) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    // Rotate to reduce axial bias
    mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (int i = 0; i < detail; ++i) {
        v += a * texture(noisetex, x / noiseTextureResolution).x;
        x = rot * x * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

#endif
