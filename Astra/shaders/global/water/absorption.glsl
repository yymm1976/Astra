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
// interface-path spectrum from the clearer blue volume and incoming illumination.
vec3 water_absorption_coefficient() {
    return vec3(0.055, 0.028, 0.010) * (WATER_ABSORPTION * 0.01);
}
vec3 water_surface_absorption() {
    #if WATER_CHARACTER == WATER_COLD
        // Colder water retains relatively more blue than the other types.
        vec3 coefficient = vec3(0.200, 0.032, 0.020);
    #elif WATER_CHARACTER == WATER_TROPICAL
        // Strongest red removal and longest green transport length.
        vec3 coefficient = vec3(0.320, 0.018, 0.032);
    #else
        // Default: clear cyan shallows, teal middle depths, dark deep water.
        vec3 coefficient = vec3(0.260, 0.022, 0.026);
    #endif
    return coefficient * (WATER_ABSORPTION * 0.01);
}
// Spectral single-scattering coefficient (100% fog-density reference point).
// Kept small in red so the teal selectivity bought above is not diluted.
vec3 water_scattering_coefficient() {
    return vec3(0.008, 0.023, 0.055) * (UNDERWATER_FOG_DENSITY * 0.01);
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
// This is called only for an interface-to-bed/reflected-terrain leg, never for
// the eye-to-interface volume. It preserves zero-distance transparency and the
// bed's texture; it does not tint reflections or the complete screen.
vec3 water_interface_extinction() {
    return isEyeInWater == 0
        ? water_surface_absorption() + water_scattering_coefficient() : water_extinction();
}
vec3 water_interface_medium(vec3 radiance, float distanceInWater, vec3 incidentLight) {
    return water_transport(radiance, distanceInWater, incidentLight, water_interface_extinction());
}
#endif
