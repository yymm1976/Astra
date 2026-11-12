#ifndef ASTRA_CLOUD_HISTORY_FRAME_GLSL
#define ASTRA_CLOUD_HISTORY_FRAME_GLSL
uniform float frameTime;
#ifndef ASTRA_TAA
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform vec3 previousCameraPosition;
#endif
#include "/lib/history_frame.glsl"

// These predicates depend only on frame uniforms, never on a cloud column.
bool astra_cloud_history_frame_valid() {
    if (astraTimeDiscontinuity != 0 || frameCounter <= 1
        || isnan(frameTime) || isinf(frameTime) || frameTime < 0.0 || frameTime > 0.5)
        return false;
    return astra_history_frame_inputs_valid();
}
#endif
