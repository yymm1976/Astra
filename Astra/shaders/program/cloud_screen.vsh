#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#ifdef ASTRA_CLOUD_TEMPORAL
#include "/lib/cloud_history_frame.glsl"
flat out int cloudFrameValid;
#endif
out vec2 texcoord;
void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    #ifdef ASTRA_CLOUD_TEMPORAL
    cloudFrameValid = int(astra_cloud_history_frame_valid());
    #endif
}
