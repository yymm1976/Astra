// Original Astra: frame-wide TAA validity is constant over the quad.
#include "/lib/settings.glsl"
#ifdef ASTRA_TAA
#include "/lib/uniforms.glsl"
#include "/lib/taa_state.glsl"
uniform sampler2D colortex17;
flat out int taaFrameValid;
#endif
out vec2 texcoord;
void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    #ifdef ASTRA_TAA
    #if defined ASTRA_BLOOM && !defined DIMENSION_NETHER && !defined DIMENSION_END
    // The water display consumes colortex4 directly and rejects TAA history.
    // Neither full-screen copy is consumed here. composite7 still stamps the
    // water medium, so the first air frame rejects these untouched histories.
    if (isEyeInWater == 1) {
        taaFrameValid = 0;
        gl_Position = vec4(2.0,2.0,2.0,1.0);
        return;
    }
    #endif
    taaFrameValid = int(astra_taa_state_valid(colortex17));
    #endif
}
