#ifndef ASTRA_NETHER_FOG_DENSITY_GLSL
#define ASTRA_NETHER_FOG_DENSITY_GLSL
#include "/lib/uniforms.glsl"

// ITT 3.2 biome-dependent fog: idea only. Coefficients and blending are Astra's.
// Reuse the palette's smoothed biome weights, including its unknown-biome fallback.
float astra_nether_biome_density() {
    float weight = astraNetherWastes + astraNetherCrimson + astraNetherWarped
                 + astraNetherBasalt + astraNetherSoul;
    float density = astraNetherWastes + 1.05 * astraNetherCrimson
                  + 0.85 * astraNetherWarped + 1.20 * astraNetherBasalt
                  + 0.80 * astraNetherSoul;
    return mix(1.0, density / max(weight, 0.0001), clamp(weight, 0.0, 1.0));
}
#endif
