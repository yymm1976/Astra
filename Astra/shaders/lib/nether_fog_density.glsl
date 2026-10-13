#ifndef ASTRA_NETHER_FOG_DENSITY_GLSL
#define ASTRA_NETHER_FOG_DENSITY_GLSL
#include "/lib/uniforms.glsl"

// ITT 3.2 biome-dependent fog: idea only. Coefficients and blending are Astra's.
// Reuse the palette's smoothed biome weights, including its unknown-biome fallback.
float astra_nether_biome_density() {
    return astraNetherDensityMul;
}
#endif
