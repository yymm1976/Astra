// Original Astra producer. Nine signed SH coefficients, before main geometry.
#define ASTRA_SKY_SH_WRITE
#include "/program/scene.glsl"
#include "/lib/sky_sh9.glsl"
#if CLOUD_MODE == CLOUD_PLANAR
#include "/lib/sky_reflection_cache.glsl"
#endif
#ifndef RGBA16F
const int RGBA16F = 0;
#endif
const int colortex18Format = RGBA16F;
/* RENDERTARGETS: 18 */
void main() {
    int coefficient = int(gl_FragCoord.x);
    vec3 sum = vec3(0.0);
    // Pair the original upper/lower cells. Their sky lookup is identical; only
    // the 0.08 ground fill and the sign of the Y-odd basis terms differ.
    // Preserve all 128 solid-angle contributions with 64 radiance queries.
    bool oddY = coefficient == 1 || coefficient == 4 || coefficient == 5;
    float hemisphereWeight = oddY ? 0.92 : 1.08;
    for (int row = 0; row < 4; ++row) for (int column = 0; column < 16; ++column) {
        float y = (float(row) + 0.5) * 0.25;
        float angle = (float(column) + 0.5) * (2.0 * ASTRA_SH9_PI / 16.0);
        float r = sqrt(max(1.0-y*y, 0.0));
        vec3 direction = vec3(r*cos(angle), y, r*sin(angle));
        #if CLOUD_MODE == CLOUD_PLANAR
        vec3 radiance = astra_cached_reflection_sky(direction);
        #else
        vec3 radiance = astra_sky_radiance(direction);
        #endif
        float basis[9];
        astra_sh9_basis(direction, basis);
        sum += max(radiance, vec3(0.0)) * basis[coefficient]
             * (hemisphereWeight * 4.0*ASTRA_SH9_PI/128.0);
    }
    gl_FragData[0] = vec4(sum, 1.0);
}
