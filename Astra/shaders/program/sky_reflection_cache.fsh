// Current-frame environment for overworld water, ice and standing-water reflections.
// Cache scheduling/composition is Astra's; sky/cloud modules keep their own provenance.
#define ASTRA_SKY_CACHE_WRITE
#include "/program/scene.glsl"
#include "/lib/sky_reflection_cache.glsl"
#include "/lib/water_buffer_formats.glsl"

#ifndef RGBA16F
// Iris reads the named format directive; GLSL still needs a declared token.
const int RGBA16F = 0;
#endif
// RGB retains the shared environment; alpha carries cloud transmittance so
// transmitted sun/stars can use that same footprint without another cloud march.
const int colortex11Format = RGBA16F;
// Every cache texel, including longitude gutters, is produced before geometry.
const bool colortex11Clear = false;
/* RENDERTARGETS: 11 */
void main() {
    vec3 direction = astra_sky_cache_direction(gl_FragCoord.xy);
    vec3 sky = astra_sky_radiance(direction);
    float cloudTransmittance = 1.0;
    #if CLOUD_MODE == CLOUD_PLANAR
        // Resolve edges over this sphere's angular texel footprint, rather than
        // treating a coarse reflected texel as an infinitely narrow ray.
        vec3 unusedRepresentative;
        float cloudFootprint = max(2.0 * ASTRA_SKY_CACHE_PI / ASTRA_SKY_CACHE_CORE.x,
                                  ASTRA_SKY_CACHE_PI / ASTRA_SKY_CACHE_CORE.y);
        vec4 cloud = astra_planar_cloud(direction, 1e20, unusedRepresentative, cloudFootprint);
        sky = mix(sky, cloud.rgb, cloud.a);
        cloudTransmittance = 1.0-cloud.a;
    #endif
    gl_FragData[0] = vec4(max(sky, vec3(0.0)),cloudTransmittance);
}
