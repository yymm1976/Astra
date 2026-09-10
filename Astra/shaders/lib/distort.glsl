#ifndef ASTRA_LIB_DISTORT_GLSL
#define ASTRA_LIB_DISTORT_GLSL

// From Steadfast 0.8.0 lib/distort.glsl, copyright (C) 2026 coderbot.
// GPL-3.0-or-later with its Section 7 additional terms; see Astra/LICENSE
// and THIRD-PARTY.md. Keep this projection paired with shadow_map_position.
const float SHADOW_DISTORT_FACTOR = 0.20;

float get_distort_factor(vec2 pos) {
    return length(pos) + SHADOW_DISTORT_FACTOR;
}

// Shadow clip space distortion: packs resolution near the player
vec3 distort(vec3 pos) {
    float factor = get_distort_factor(pos.xy);
    return vec3(pos.xy / factor, pos.z * 0.5);
}

vec3 undistort(vec3 pos) {
    // Analytic inverse of q = p / (length(p) + a). The image of finite
    // points is the open unit disk; callers must reject its unused corners.
    float factor = SHADOW_DISTORT_FACTOR / max(1.0 - length(pos.xy), 1e-5);
    return vec3(pos.xy * factor, pos.z / 0.5);
}

#endif
