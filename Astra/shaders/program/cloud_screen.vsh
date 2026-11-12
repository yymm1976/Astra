#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
// The cloud sheet is produced in the overworld only. Resolve the frame-wide
// water kind once per quad vertex; the fragment stage reuses it as a flat
// varying instead of re-fetching colortex6 for every cloud-hit pixel.
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
#define ASTRA_WATER_STATE_FRAME_WRITE
#include "/global/water/medium_state.glsl"
#endif
#ifdef ASTRA_CLOUD_TEMPORAL
#include "/lib/cloud_history_frame.glsl"
flat out int cloudFrameValid;
#endif
out vec2 texcoord;
void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    waterMaterialThinSheet = int(water_is_thin_sheet());
    #endif
    #ifdef ASTRA_CLOUD_TEMPORAL
    cloudFrameValid = int(astra_cloud_history_frame_valid());
    #endif
}
