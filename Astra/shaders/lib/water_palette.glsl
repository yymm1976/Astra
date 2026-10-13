#ifndef ASTRA_WATER_PALETTE_GLSL
#define ASTRA_WATER_PALETTE_GLSL
// Astra's submerged cyan palette. Inspired by ITT 3.2's water colour;
// these values are local tuning, not a reference preset. See THIRD-PARTY.md.
// The first value belongs to Solas' pre-composite sqrt colour domain.
const vec3 astraWaterTintSqrt = vec3(0.35, 0.71, 0.75);
// Light beams are less saturated than the background medium. Preserve a
// pale source highlight against cyan water instead of adding the same wash.
const vec3 astraWaterShaftTintSqrt = mix(vec3(0.75), astraWaterTintSqrt, 0.50);
const vec3 astraWaterTransmissionTint = vec3(0.60, 0.97, 1.0);
const float astraWaterShaftRange = 48.0;
// Underwater distance medium, aligned to ITT 3.2 composite1.fsh::WaterFog.
// The public slider keeps its range: DEFAULT 40 maps to the reference
// WATERFOG_DENSITY = 1, so 0 disables the medium and the near path is identity.
#define ASTRA_WATER_FOG_DENSITY (UNDERWATER_FOG_DENSITY * 0.025)
float astra_water_fog_density() {
    return ASTRA_WATER_FOG_DENSITY;
}
// Reference per-channel scene absorption (composite1.fsh:84-85):
//   pow(vec3(0.1, 0.6, 1.0) * 0.99, vec3(d * 0.04 * WATERFOG_DENSITY))
// with the open-water fogDensity 0.04. Written as base-e transmittance; the
// three constants are ln(0.099)/ln(0.594)/ln(0.99) * 0.04, so the reference
// curve is exact and the fragment needs no per-pixel pow. Both blocks are
// compile-time constants because the slider is a const define.
const vec3 astraWaterAbsorptionPerBlock =
    vec3(-0.0925056, -0.0208350, -0.0004020) * ASTRA_WATER_FOG_DENSITY;
vec3 astra_water_absorption_transmission(float waterDistance) {
    return exp(astraWaterAbsorptionPerBlock * waterDistance);
}
// Reference in-scatter visibility exp2(-d * 0.04 * WATERFOG_DENSITY)
// (composite1.fsh:78-79; ordinary water has no ice mask, so no clamp floor is
// faked). Folded to base e with ln(2).
const float astraWaterVisibilityPerBlock = -0.0277259 * ASTRA_WATER_FOG_DENSITY;
float astra_water_visibility(float waterDistance) {
    return exp(astraWaterVisibilityPerBlock * waterDistance);
}
#endif
