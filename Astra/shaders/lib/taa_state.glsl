#ifndef ASTRA_LIB_TAA_STATE_GLSL
#define ASTRA_LIB_TAA_STATE_GLSL
#include "/lib/history_frame.glsl"
#ifdef DIMENSION_NETHER
const float astraTaaDimension = 17.0;
#elif defined DIMENSION_END
const float astraTaaDimension = 19.0;
#else
const float astraTaaDimension = 23.0;
#endif

// Metadata lives separately so no scene pixels are sacrificed to bookkeeping.
// The writer runs AFTER the resolve; the resolve always sees the previous stamp.
// Version 5 stores frameCounter modulo 4096, exactly representable in FP32.
bool astra_taa_state_valid(sampler2D state, out vec4 effects, out vec4 identity) {
    effects = vec4(0.0);
    identity = vec4(0.0);
    if (astraTimeDiscontinuity != 0 || frameCounter <= 1
        || !astra_history_frame_inputs_valid()) return false;
    vec4 viewport = texelFetch(state, ivec2(0, 0), 0);
    if (any(isnan(viewport)) || any(isinf(viewport))
        || viewport.z != float((frameCounter - 1) % 4096)
        || any(notEqual(viewport.xy, vec2(viewWidth, viewHeight)))
        || viewport.w != float(isEyeInWater)) return false;
    effects = texelFetch(state, ivec2(1, 0), 0);
    if (any(isnan(effects)) || any(isinf(effects))
        || abs(effects.x - blindness) > 0.02
        || abs(effects.y - darknessFactor) > 0.02
        || abs(effects.w - lightningBoltPosition.w) > 0.01
        || frameTimeCounter < effects.z || frameTimeCounter - effects.z > 0.25)
        return false;
    identity = texelFetch(state, ivec2(2, 0), 0);
    if (any(isnan(identity)) || any(isinf(identity))
        || identity.x != astraTaaDimension || identity.w != 5.0) return false;
    vec3 forward = mat3(gbufferModelViewInverse) * vec3(0.0, 0.0, -1.0);
    if (any(isnan(forward)) || any(isinf(forward))
        || (mat3(gbufferPreviousModelView) * forward).z > -0.5) return false;
    return true;
}
bool astra_taa_state_valid(sampler2D state) {
    vec4 effects, identity;
    return astra_taa_state_valid(state, effects, identity);
}
#endif
