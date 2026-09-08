#ifndef ASTRA_LIB_DISTORT_GLSL
#define ASTRA_LIB_DISTORT_GLSL

// From Mellow v3.4 (MIT) by TheCMK - lib/shadow_distort.glsl
// Mechanical port (names normalized per design.md 3.2). License: MIT - see THIRD-PARTY.md.
// Uniforms: isEyeInWater, cameraPosition (lib/uniforms.glsl)
// Consts:   shadowDistance, shadowMapResolution (ENGINE KNOBS in lib/settings.glsl)
// Requires: dimension macros from the world shells (DIMENSION_OVERWORLD for compute_bias)

// SUN_PATH_ROTATION: kept as a build-time constant (0 = box distortion footprint).
// Promote to a user option if B1 finds rotated sun paths necessary.
#ifndef SUN_PATH_ROTATION
#define SUN_PATH_ROTATION 0
#endif

const float shadow_map_bias = 1.0 - 25.6 / shadowDistance;

float get_distort_factor(vec2 pos) {
    #if SUN_PATH_ROTATION == 0
        return max(abs(pos.x), abs(pos.y)) * shadow_map_bias + (1.0 - shadow_map_bias);
    #else
        return length(pos.xy) * shadow_map_bias + (1.0 - shadow_map_bias);
    #endif
}

// Shadow clip space distortion: packs resolution near the player
vec3 distort(vec3 pos) {
    float factor = get_distort_factor(pos.xy);
    return vec3(pos.xy / factor, pos.z * 0.2);
}

vec3 undistort(vec3 pos) {
    // Invert q = p / (a + b * norm(p)); evaluating the forward factor at q
    // is not its inverse. Both box and radial norms are homogeneous.
    float radius;
    #if SUN_PATH_ROTATION == 0
        radius = max(abs(pos.x), abs(pos.y));
    #else
        radius = length(pos.xy);
    #endif
    float factor = (1.0 - shadow_map_bias) / max(1.0 - shadow_map_bias * radius, 1e-5);
    return vec3(pos.xy * factor, pos.z / 0.2);
}

// Adaptive normal-offset bias (adapted from Complementary Shaders with Emin's
// explicit permission, as noted in the Mellow source)
vec3 compute_bias(vec3 player_pos, vec3 world_normal, float ndotl, float skylight, float ao) {
    float distance_bias = pow(dot(player_pos, player_pos), 0.75);
    distance_bias = 0.12 + 0.0008 * distance_bias;
    vec3 bias = world_normal * distance_bias * (2.0 - 0.95 * max(ndotl, 0.0));

    #ifdef DIMENSION_OVERWORLD
        skylight = max(skylight, ao);
        if (skylight < 0.5 && isEyeInWater != 1) {
            vec3 edge_factor = 0.2 * (0.5 - fract(player_pos + cameraPosition + world_normal * 0.01));
            bias += max(1.0 - skylight, 0.0) * edge_factor;
        }
    #endif

    return bias;
}

#endif
