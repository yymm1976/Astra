// Frame metadata is uniform over the draw. Read it before rasterization;
// receiver reprojection and per-texel history rejection stay in the fragment.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/transforms.glsl"
#include "/lib/effect_history.glsl"

out vec2 texcoord;
out vec2 lightScreenPos;
flat out int effectFrameValid;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vec4 clipLight = astra_jitter_clip(gbufferProjection * vec4(lightVector, 0.0));
    vec2 ndcLight = clipLight.w > 0.0
        ? clipLight.xy / max(clipLight.w, 0.0001) : vec2(0.0);
    lightScreenPos = ndcLight * 0.5 + 0.5;
    vec4 previousEffects;
    effectFrameValid = int(astra_effect_history_valid(previousEffects));
}
