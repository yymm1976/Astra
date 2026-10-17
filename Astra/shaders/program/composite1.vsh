// Shared full-screen quad; main-world bloom also prepares the current water kind.
// design.md 3.2 layer 2: program/* is the only lib entry
#include "/lib/settings.glsl"
#ifdef ASTRA_WATER_BLOOM_CAPTURE
#include "/lib/uniforms.glsl"
#include "/global/water/medium_state.glsl"
flat out int bloomOrdinaryWater;
#endif
out vec2 texcoord;
void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    #ifdef ASTRA_WATER_BLOOM_CAPTURE
    bloomOrdinaryWater = int(isEyeInWater == 1 && !water_is_thin_sheet());
    #endif
}
