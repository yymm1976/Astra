// Shared full-screen quad; main-world bloom also prepares the current water kind.
// design.md 3.2 layer 2: program/* is the only lib entry
#include "/lib/settings.glsl"
#if defined ASTRA_WATER_BLOOM_CAPTURE || defined ASTRA_CELESTIAL_BLOOM
#include "/lib/uniforms.glsl"
#endif
#ifdef ASTRA_WATER_BLOOM_CAPTURE
#include "/global/water/medium_state.glsl"
flat out int bloomOrdinaryWater;
#endif
out vec2 texcoord;
void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    #ifdef ASTRA_CELESTIAL_BLOOM
    // This capture has no underwater consumer; keep water owned by its existing
    // display composition instead of scheduling the full underwater Bloom chain.
    if (isEyeInWater != 0 || blindness >= 1.0)
        gl_Position = vec4(-2.0,-2.0,0.0,1.0);
    #endif
    #ifdef ASTRA_WATER_BLOOM_CAPTURE
    bloomOrdinaryWater = int(isEyeInWater == 1 && !water_is_thin_sheet());
    #endif
}
