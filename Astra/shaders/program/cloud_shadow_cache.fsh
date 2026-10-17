#define ASTRA_CLOUD_SHADOW_WRITE
#include "/program/scene.glsl"
in vec2 texcoord;
#ifndef R16
const int R16 = 0;
#endif
const int colortex14Format = R16;
// Active draws overwrite the complete map. When the vertex stage skips a
// neutral draw, cloud_shadow_at returns 1 before it can read this attachment.
const bool colortex14Clear = false;
/* RENDERTARGETS: 14 */
void main() {
    float transmission = 1.0;
    #if CLOUD_MODE == CLOUD_PLANAR
        #if !defined CLOUD_SHADOWS && !defined ASTRA_VOLUME_FOG
        // Rainy lighting is the only consumer unless surface shadows or the
        // volume march need the cloud transmission in clear weather too.
        if (astraRainFactor < 0.01) {
            gl_FragData[0] = vec4(1.0);
            return;
        }
        #endif
        if (astraCloudShadowFade > 0.0) {
            vec2 worldXZ = astra_cloud_shadow_anchor()+(texcoord-0.5)*ASTRA_CLOUD_SHADOW_EXTENT;
            transmission = astra_cloud_plane_transmission(vec3(worldXZ.x,ASTRA_CLOUD_ALTITUDE,worldXZ.y));
        }
    #endif
    gl_FragData[0] = vec4(transmission,0.0,0.0,1.0);
}
