#ifndef ASTRA_GLOBAL_WATER_ABSORPTION_GLSL
#define ASTRA_GLOBAL_WATER_ABSORPTION_GLSL
// Historical references: Solas waterFog.glsl and Steadfast water absorption
// presets. The current block-distance transport and spectral values are written
// for Astra; prior source history remains documented in THIRD-PARTY.md.
// SC-34, written for Astra. Beer-Lambert extinction in inverse blocks. All
// consumers use distance in blocks, with no 32-block plateau and no second fog
// multiplier. Absorption and scattering have independent user controls.
//
// Water character is the ABOVE-water appearance of the transmitted bed. It must
// not turn the submerged camera's entire medium green. Separate this artistic
// interface-path spectrum from the clearer cyan volume and incoming illumination.
vec3 water_absorption_coefficient() {
    #ifdef DEBUG_DISABLE_WATER_ABSORPTION
    return vec3(0.0);
    #else
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    return vec3(0.032, 0.014, 0.012) * (WATER_ABSORPTION * 0.01);
    #else
    return vec3(0.055, 0.028, 0.010) * (WATER_ABSORPTION * 0.01);
    #endif
    #endif
}
vec3 water_surface_absorption(vec2 depthBlend) {
    // Continuous depth response without separate ramps meeting at five blocks.
    // A modest shallow extinction retains body while the bed stays readable.
    vec3 shallow = vec3(0.240, 0.045, 0.060);
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    // A one-block pool/stream retains a light cyan body instead of looking
    // like air. Keep the same continuous middle/deep blends and spectra.
    shallow = vec3(0.320, 0.050, 0.065);
    #endif
    vec3 middle, deep;
    #if WATER_CHARACTER == WATER_COLD
        middle = vec3(0.230, 0.050, 0.035);
        deep   = vec3(0.380, 0.180, 0.050);
    #elif WATER_CHARACTER == WATER_TROPICAL
        middle = vec3(0.290, 0.020, 0.085);
        deep   = vec3(0.460, 0.180, 0.040);
    #else
        middle = vec3(0.250, 0.025, 0.080);
        deep   = vec3(0.420, 0.200, 0.045);
    #endif
    return mix(mix(shallow, middle, depthBlend.x), deep, depthBlend.y)
         * (WATER_ABSORPTION * 0.01);
}
// Spectral single-scattering coefficient (100% fog-density reference point).
// Main-world medium keeps red present and green/blue close, for pale cyan
// rather than a saturated deep-blue background. Other dimensions keep theirs.
vec3 water_scattering_coefficient() {
    #ifdef DEBUG_DISABLE_UNDERWATER_FOG
    return vec3(0.0);
    #else
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    return vec3(0.026, 0.045, 0.048) * (UNDERWATER_FOG_DENSITY * 0.01);
    #else
    return vec3(0.011, 0.032, 0.076) * (UNDERWATER_FOG_DENSITY * 0.01);
    #endif
    #endif
}
vec3 water_extinction() {
    return water_absorption_coefficient() + water_scattering_coefficient();
}
vec3 water_transmission(float distanceInWater) {
    return exp(-max(distanceInWater, 0.0) * water_extinction());
}
vec3 water_transport(vec3 radiance, float distanceInWater, vec3 incidentLight, vec3 extinction) {
    vec3 transmission = exp(-max(distanceInWater, 0.0) * extinction);
    // Single-scattering source term: sigma_s / sigma_t * (1 - T). At density
    // zero this adds nothing; at zero total extinction it returns the input.
    vec3 scatteringAlbedo = vec3(water_scattering_coefficient()) / max(extinction, vec3(1e-6));
    return radiance * transmission + incidentLight * scatteringAlbedo * (1.0 - transmission);
}
vec3 water_medium(vec3 radiance, float distanceInWater, vec3 incidentLight) {
    return water_transport(radiance, distanceInWater, incidentLight, water_extinction());
}
// Air-side fill follows the same continuous response as transmission. Existing
// underwater absorption, scattering and wave optics remain independent.
vec3 water_body_color(vec2 depthBlend) {
    #ifdef DEBUG_DISABLE_UNDERWATER_FOG
    return vec3(0.0);
    #else
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    return mix(mix(vec3(0.065, 0.148, 0.150), vec3(0.056, 0.148, 0.142), depthBlend.x),
               vec3(0.055, 0.165, 0.180), depthBlend.y);
    #else
    return mix(mix(vec3(0.065, 0.148, 0.150), vec3(0.056, 0.148, 0.142), depthBlend.x),
               vec3(0.020, 0.160, 0.300), depthBlend.y);
    #endif
    #endif
}
// Astra: coherent footprints reuse this affine transfer while keeping the
// continuous shallow/middle/deep spectrum and a real representative endpoint.
void water_surface_transfer(float verticalDepth, vec3 incidentLight, float haze,
                            out vec3 transmission, out vec3 scattering) {
    // Use the actual column thickness; an artificial extra block would tint
    // even ankle-deep water and hide the neutral bed in a one-block pool.
    float appearanceDepth = max(verticalDepth, 0.0);
    float depthSquared = appearanceDepth * appearanceDepth;
    // Shared by extinction and fill; no duplicate ramp or added exponential.
    vec2 depthBlend = vec2(appearanceDepth / (appearanceDepth + 4.0),
                          depthSquared / (depthSquared + 324.0));
    // The fill keeps the real extinction even under the absorption bypass, so
    // the absorption and fog diagnostic switches stay independently readable.
    vec3 pathTransmission = exp(-appearanceDepth * water_surface_absorption(depthBlend))
                          * (1.0 - haze);
    scattering = water_body_color(depthBlend) * clamp(incidentLight, 0.0, 2.0)
               * (1.0 - pathTransmission);
    #ifdef DEBUG_DISABLE_WATER_ABSORPTION
    transmission = vec3(1.0 - haze);
    #else
    transmission = pathTransmission;
    #endif
}
void water_surface_transfer(float verticalDepth, vec3 incidentLight,
                            out vec3 transmission, out vec3 scattering) {
    water_surface_transfer(verticalDepth, incidentLight, 0.0, transmission, scattering);
}
vec3 water_surface_medium(vec3 radiance, float verticalDepth, vec3 incidentLight, float haze) {
    vec3 transmission, scattering;
    water_surface_transfer(verticalDepth, incidentLight, haze, transmission, scattering);
    return radiance * transmission + scattering;
}
vec3 water_surface_medium(vec3 radiance, float verticalDepth, vec3 incidentLight) {
    vec3 transmission, scattering;
    water_surface_transfer(verticalDepth, incidentLight, transmission, scattering);
    return radiance * transmission + scattering;
}
#endif
