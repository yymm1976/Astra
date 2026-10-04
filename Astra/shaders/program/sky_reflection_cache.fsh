// Current-frame environment for overworld water, ice and standing-water reflections.
// Cache scheduling/composition is Astra's; sky/cloud modules keep their own provenance.
#define ASTRA_SKY_CACHE_WRITE
#include "/program/scene.glsl"
#include "/lib/sky_reflection_cache.glsl"
#include "/lib/water_buffer_formats.glsl"

const int colortex11Format = R11F_G11F_B10F;
/* RENDERTARGETS: 11 */
void main() {
    vec3 direction = astra_sky_cache_direction(gl_FragCoord.xy);
    vec3 sky = astra_sky_radiance(direction);
    #if CLOUD_MODE == CLOUD_PLANAR
        vec4 cloud = astra_planar_cloud(direction);
        sky = mix(sky, cloud.rgb, cloud.a);
    #endif
    gl_FragData[0] = vec4(max(sky, vec3(0.0)), 1.0);
}
