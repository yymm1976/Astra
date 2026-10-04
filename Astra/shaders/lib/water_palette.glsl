#ifndef ASTRA_WATER_PALETTE_GLSL
#define ASTRA_WATER_PALETTE_GLSL
// Astra's submerged cyan palette. Inspired by ITT 3.2's water colour;
// these values are local tuning, not a reference preset. See THIRD-PARTY.md.
// The first value belongs to Solas' pre-composite sqrt colour domain.
const vec3 astraWaterTintSqrt = vec3(0.25, 0.62, 0.73);
// Light columns are less saturated than the background medium. Preserve a
// pale source highlight against cyan water instead of adding the same wash.
const vec3 astraWaterShaftTintSqrt = mix(vec3(0.75), astraWaterTintSqrt, 0.70);
const vec3 astraWaterTransmissionTint = vec3(0.60, 0.97, 1.0);
const float astraWaterShaftRange = 48.0;
float astra_water_haze_density() {
    // Default 40: 0.065/block, with a short smooth transition at the eye.
    return UNDERWATER_FOG_DENSITY * 0.001625;
}
#endif
