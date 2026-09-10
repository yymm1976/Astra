// Solas four-tile bloom, after water fog and volume have been composed.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
uniform sampler2D colortex0;
const bool colortex0MipmapEnabled = true;
#include "/global/water/bloom_capture.glsl"
in vec2 texcoord;
/* RENDERTARGETS: 7 */
void main() {
    if (isEyeInWater != 1) discard;
    gl_FragData[0] = vec4(computeBloom(texcoord), 1.0);
}
