#ifndef ASTRA_EFFECT_HISTORY_GLSL
#define ASTRA_EFFECT_HISTORY_GLSL
// Independent effects use previous matrices even when scene TAA is disabled.
#ifndef ASTRA_TAA
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform vec3 previousCameraPosition;
#endif
uniform sampler2D colortex30;
uniform float near;
uniform float far;
#ifdef DIMENSION_NETHER
const float astraEffectDimension = 17.0;
#else
const float astraEffectDimension = 23.0;
#endif
bool astra_effect_history_valid(out vec4 effects) {
    effects = vec4(0.0);
    // Current-frame rejection needs none of the three persistent state texels.
    if (astraTimeDiscontinuity != 0 || frameCounter <= 1
        || length(cameraPosition-previousCameraPosition)>8.0) return false;
    vec4 viewport=texelFetch(colortex30,ivec2(0,0),0);
    if (viewport.z != float(frameCounter-1)
        || any(notEqual(viewport.xy,vec2(viewWidth,viewHeight)))
        || viewport.w != float(isEyeInWater)) return false;
    effects=texelFetch(colortex30,ivec2(1,0),0);
    if (abs(effects.x-blindness)>0.02 || abs(effects.y-darknessFactor)>0.02
        || frameTimeCounter<effects.z || frameTimeCounter-effects.z>0.25) return false;
    vec4 identity=texelFetch(colortex30,ivec2(2,0),0);
    if (identity.x != astraEffectDimension || identity.w != 4.0) return false;
    for(int i=0;i<4;i++)
        if(any(greaterThan(abs(gbufferProjection[i]-gbufferPreviousProjection[i]),vec4(0.0001)))) return false;
    return true;
}
bool astra_effect_history_valid() {
    vec4 effects;
    return astra_effect_history_valid(effects);
}
vec3 astra_effect_previous_screen(vec3 cameraRelativePoint) {
    vec3 previousPoint=cameraRelativePoint+cameraPosition-previousCameraPosition;
    vec4 clip=gbufferPreviousProjection*gbufferPreviousModelView*vec4(previousPoint,1.0);
    if(clip.w<=0.00001) return vec3(-1.0);
    vec3 uv=clip.xyz/clip.w*0.5+0.5;
    uv.xy+=astra_jitter_uv_for(frameCounter-1);
    return uv;
}
float astra_effect_linear_depth(float depth) {
    // Depth textures store [0,1]; the perspective denominator uses NDC [-1,1].
    // Return view depth divided by far, matching the reflection history payload.
    float ndcDepth = depth * 2.0 - 1.0;
    return 2.0*near/max(far+near-ndcDepth*(far-near),0.00001);
}
#endif
