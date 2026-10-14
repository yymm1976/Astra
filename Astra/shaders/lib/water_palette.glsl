#ifndef ASTRA_WATER_PALETTE_GLSL
#define ASTRA_WATER_PALETTE_GLSL
// Requires: lib/settings.glsl (UNDERWATER_FOG_DENSITY, WATER_ABSORPTION and the
// DEBUG_DISABLE_* diagnostic switches). Every entry that reaches this file has
// already included settings, the same contract lib/tonemap.glsl declares; this
// file does not re-include it, so the settings block stays in one place.
// Astra's submerged cyan palette. Inspired by ITT 3.2's water colour;
// these values are local tuning, not a reference preset. See THIRD-PARTY.md.
// The first value belongs to Solas' pre-composite sqrt colour domain.
const vec3 astraWaterTintSqrt = vec3(0.56, 0.74, 0.75);
// Light beams are less saturated than the background medium. Preserve a
// pale source highlight against cyan water instead of adding the same wash.
const vec3 astraWaterShaftTintSqrt = mix(vec3(0.75), astraWaterTintSqrt, 0.50);
const vec3 astraWaterTransmissionTint = vec3(0.60, 0.97, 1.0);
const float astraWaterShaftRange = 48.0;
// Shared linear water-body palette: surface fill and ordinary underwater fog
// use the same cyan, with illumination and path length applied by consumers.
vec3 astra_water_body_palette(vec2 depthBlend) {
    return mix(mix(vec3(0.065, 0.148, 0.150), vec3(0.056, 0.148, 0.142), depthBlend.x),
               vec3(0.055, 0.165, 0.180), depthBlend.y);
}
// Underwater distance medium. 40% maps to density 1; the clearer default is
// 35%. At zero density distance fog is identity; absorption is independent.
#define ASTRA_WATER_FOG_DENSITY (UNDERWATER_FOG_DENSITY * 0.025)
float astra_water_fog_density() {
    return ASTRA_WATER_FOG_DENSITY;
}
// Astra tuning in inverse blocks: retain some warm material colour and make
// green/blue extinction close enough that long camera legs stay cyan. The
// absorption slider controls this spectrum independently of fog density.
const vec3 astraWaterAbsorptionPerBlock =
    vec3(-0.032, -0.014, -0.012) * (WATER_ABSORPTION * 0.01);
vec3 astra_water_absorption_transmission(float waterDistance) {
    #ifdef DEBUG_DISABLE_WATER_ABSORPTION
    return vec3(1.0);
    #else
    return exp(astraWaterAbsorptionPerBlock * waterDistance);
    #endif
}
// Reference in-scatter visibility exp2(-d * 0.04 * WATERFOG_DENSITY)
// (composite1.fsh:78-79; ordinary water has no ice mask, so no clamp floor is
// faked). Folded to base e with ln(2).
const float astraWaterVisibilityPerBlock = -0.0277259 * ASTRA_WATER_FOG_DENSITY;
float astra_water_visibility(float waterDistance) {
    #ifdef DEBUG_DISABLE_UNDERWATER_FOG
    // Full scene visibility removes the medium blend in composite(): the
    // remaining image is the absorption-transmitted scene alone.
    return 1.0;
    #else
    return exp(astraWaterVisibilityPerBlock * waterDistance);
    #endif
}
#endif
