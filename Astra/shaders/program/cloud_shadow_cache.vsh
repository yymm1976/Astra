// Dedicated vertex stage for prepare2's cloud-shadow cache. It mirrors
// program/cloud_shadow_cache.fsh: when every fragment would write the neutral
// transmission 1.0, the draw is moved off screen instead of rasterizing a
// full-screen target that no valid reader consumes. The rough-sky-reflection mip
// request in program/prepare_cloud_shadow.fsh still belongs to this pass.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
out vec2 texcoord;
void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    #if CLOUD_MODE == CLOUD_PLANAR
    #if !defined CLOUD_SHADOWS && !defined ASTRA_VOLUME_FOG
    // Rainy lighting is the only consumer unless surface shadows or the volume
    // march need the cloud transmission in clear weather too.
    if (astraRainFactor < 0.01) {
        gl_Position = vec4(-2.0,-2.0,0.0,1.0);
        return;
    }
    #endif
    if (astraCloudShadowFade <= 0.0) {
        gl_Position = vec4(-2.0,-2.0,0.0,1.0);
        return;
    }
    #endif
}
