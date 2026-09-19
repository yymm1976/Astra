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
    // Air-side appearance per block of vertical depth, separate from volume
    // extinction. The balanced/tropical spectra retain green alongside blue;
    // neither the daylight sky nor depth absorption should erase cyan shallows.
    #if WATER_CHARACTER == WATER_COLD
        // Colder water retains relatively more blue than the other types.
        vec3 coefficient = vec3(1.000, 0.2200, 0.0800);
    #elif WATER_CHARACTER == WATER_TROPICAL
        // Strongest red removal and longest green transport length.
        vec3 coefficient = vec3(2.000, 0.0550, 0.0800);
    #else
        // Default: clear cyan shallows, teal middle depths, dark deep water.
        vec3 coefficient = vec3(1.000, 0.0600, 0.1000);
    #endif
    return coefficient * (WATER_ABSORPTION * 0.01);
}
// Spectral single-scattering coefficient (100% fog-density reference point).
// Kept small in red so the teal selectivity bought above is not diluted.
// Raised alongside the absorption cut so the lost transmission comes back as
// in-scattered water colour instead of simply going darker.
vec3 water_scattering_coefficient() {
    return vec3(0.011, 0.032, 0.076) * (UNDERWATER_FOG_DENSITY * 0.01);
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
// Air-side appearance: the reference uses (vertical depth + 1) / 16, not the
// much longer grazing view path. Do not add the blue underwater volume source
// to this branch.
vec3 water_surface_medium(vec3 radiance, float verticalDepth) {
    float depth = max(verticalDepth, 0.0);
    float appearanceDepth = clamp(depth + 1.0, 0.0, 16.0);
    return radiance * exp(-appearanceDepth * water_surface_absorption());
}
#endif
