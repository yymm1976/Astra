// Main-world air highlights and underwater HDR share one quarter-size capture.
// Exactly one branch runs per frame, so both media write the same attachment:
// ordinary water captures the full HDR scene after water composition. Thin
// sheets threshold that same composed scene; air thresholds its own scene.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/global/water/medium_state.glsl"
uniform sampler2D colortex9;
uniform sampler2D colortex0;
#include "/global/water/bloom_capture.glsl"
in vec2 texcoord;
flat in int bloomOrdinaryWater;
/* RENDERTARGETS: 2 */
void main() {
    // Identical to display.vsh's displayOrdinaryWater; both stages must pick the
    // same medium so no pixel reads a capture produced by the other one.
    bool ordinaryWater = bloomOrdinaryWater != 0;
    if (ordinaryWater)
        gl_FragData[0] = vec4(computeBloom(colortex9, texcoord), 1.0);
    else if (isEyeInWater == 1)
        // The completed short-water medium and camera blindness must also
        // attenuate the bloom source, including at full blindness.
        gl_FragData[0] = vec4(bloom_capture(colortex9, texcoord, false), 1.0);
    else
        gl_FragData[0] = vec4(bloom_capture(colortex0, texcoord, false), 1.0);
}
