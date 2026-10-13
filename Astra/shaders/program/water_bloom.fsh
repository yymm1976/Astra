// Main-world air highlights and underwater HDR share the quarter-size capture.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/global/water/medium_state.glsl"
uniform sampler2D colortex9;
uniform sampler2D colortex0;
#include "/global/water/bloom_capture.glsl"
in vec2 texcoord;
/* RENDERTARGETS: 2,7 */
void main() {
    bool ordinaryWater = isEyeInWater == 1 && !water_is_thin_sheet();
    gl_FragData[0] = vec4(0.0, 0.0, 0.0, 1.0);
    gl_FragData[1] = vec4(0.0, 0.0, 0.0, 1.0);
    if (ordinaryWater)
        gl_FragData[1] = vec4(computeBloom(colortex9, texcoord), 1.0);
    else
        gl_FragData[0] = vec4(bloom_capture(colortex0, texcoord, false), 1.0);
}
