// Thresholded HDR light bloom after water composition. Do not blur ordinary
// underwater colour/fog into a full-scene veil.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/global/water/medium_state.glsl"
uniform sampler2D colortex4;
#include "/global/water/bloom_capture.glsl"
in vec2 texcoord;
/* RENDERTARGETS: 7 */
void main() {
    if (isEyeInWater != 1 || water_is_thin_sheet()) discard;
    gl_FragData[0] = vec4(computeBloom(colortex4, texcoord), 1.0);
}
