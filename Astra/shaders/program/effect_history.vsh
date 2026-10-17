// Frame metadata is uniform over the draw. Read it before rasterization;
// receiver reprojection and per-texel history rejection stay in the fragment.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/transforms.glsl"
#include "/lib/effect_history.glsl"

out vec2 texcoord;
flat out int effectFrameValid;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vec4 previousEffects;
    effectFrameValid = int(astra_effect_history_valid(previousEffects));
}
