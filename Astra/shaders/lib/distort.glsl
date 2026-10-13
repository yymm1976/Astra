#ifndef ASTRA_LIB_DISTORT_GLSL
#define ASTRA_LIB_DISTORT_GLSL

// From Steadfast 0.8.0 lib/distort.glsl, copyright (C) 2026 coderbot.
// GPL-3.0-or-later with its Section 7 additional terms; see Astra/LICENSE
// and THIRD-PARTY.md. Keep this projection paired with shadow_map_position.
#include "/lib/settings.glsl"

// k = this constant * the effective shadowDistance is the block radius at half
// the map edge, and it sets the whole detail profile: blocks/texel =
// 2 * (r + k) ^ 2 / (R * k). Steadfast shipped the plain 0.20 for its own
// 160-block map (k = 32); reusing it at Astra's shipping 256 gives k = 51.2 and
// halves near-field density. Anchoring on blocks keeps detail fixed while
// the selected distance changes only reach - the cost is a wider rim beyond the
// receiver edge, which shadowDistanceRenderMul = 1.5 partly fills upstream.
const float SHADOW_DISTORT_CORE = 25.6;
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
// Iris constructs the projection from shadowDistance after the budget cap,
// not the raw option. Producer, inverse and texel-width conversion share this.
const float SHADOW_DISTORT_FACTOR = SHADOW_DISTORT_CORE / shadowDistance;
#else
const float SHADOW_DISTORT_FACTOR = SHADOW_DISTORT_CORE / float(SHADOW_DISTANCE);
#endif

float get_distort_factor(vec2 pos) {
    return length(pos) + SHADOW_DISTORT_FACTOR;
}

// Shadow clip space distortion: packs resolution near the player
vec3 distort(vec3 pos) {
    #ifdef DIMENSION_END
    return vec3(pos.xy,pos.z*0.5);
    #else
    float factor = get_distort_factor(pos.xy);
    return vec3(pos.xy / factor, pos.z * 0.5);
    #endif
}

vec3 undistort(vec3 pos) {
    #ifdef DIMENSION_END
    return vec3(pos.xy,pos.z/0.5);
    #else
    // Analytic inverse of q = p / (length(p) + a). The image of finite
    // points is the open unit disk; callers must reject its unused corners.
    float factor = SHADOW_DISTORT_FACTOR / max(1.0 - length(pos.xy), 1e-5);
    return vec3(pos.xy * factor, pos.z / 0.5);
    #endif
}

#endif
