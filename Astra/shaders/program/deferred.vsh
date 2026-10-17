// Shared full-screen quad; scene/volume consumers reuse the current water kind.
// design.md 3.2 layer 2: program/* is the only lib entry
#include "/lib/settings.glsl"
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
#include "/lib/uniforms.glsl"
#define ASTRA_WATER_STATE_FRAME_WRITE
#include "/global/water/medium_state.glsl"
#endif
out vec2 texcoord;
void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Scene/volume composition shares this draw-wide water kind with all
    // fog consumers. Other uses of this quad stage have no matching input.
    waterMaterialThinSheet = int(water_is_thin_sheet());
    #endif
}
