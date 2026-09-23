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
vec3 water_surface_absorption(float appearanceDepth) {
    // Air-side appearance per block of vertical depth, separate from volume
    // extinction. Two ends interpolated by appearanceDepth (2026-09-21 A1):
    //
    //   shallow end - BLUE absorbed FASTER than green, so green survives and the
    //     transmission is cyan-green. The 2026-09-20 consolidated review (C1) re-ordered
    //     every spectrum so green was absorbed faster at EVERY depth; that fixed the deep
    //     end but left the shallow transmission blue-leaning (g/b = 0.96 at 0 blocks),
    //     so the shallows' cyan could only come from a warm bed - on a neutral bed they
    //     read blue-teal (measured 184.6 deg hue). This end puts the green back.
    //   deep end - green absorbed much faster than blue, by a wider margin than the old
    //     single spectrum (gap 0.25 vs 0.04 per block; Steadfast's equivalent gap is
    //     2/16 = 0.125 per block), so the water converges on deep blue with depth
    //     instead of staying teal (measured 16 blocks: blue/green 1.63 -> 5.48).
    //
    // COLD keeps a single spectrum: it is the "blue from the shallows down" character.
    vec3 shallow, deep;
    #if WATER_CHARACTER == WATER_COLD
        shallow = vec3(1.000, 0.2200, 0.0800);
        deep    = vec3(1.000, 0.2200, 0.0800);
    #elif WATER_CHARACTER == WATER_TROPICAL
        // Strongest red removal; green survives the shallow band for the Caribbean
        // cyan, blue wins the deep end.
        shallow = vec3(2.000, 0.0400, 0.0700);
        deep    = vec3(2.000, 0.2400, 0.0450);
    #else
        // Default: clear cyan-green shallows, teal middle depths, deep blue water.
        shallow = vec3(1.000, 0.0500, 0.0900);
        deep    = vec3(1.000, 0.3000, 0.0500);
    #endif
    // appearanceDepth is depth + 1 capped at 24 (water_surface_medium below), so the
    // blend spans the first 15 blocks and then holds the deep end.
    float blend = clamp((appearanceDepth - 1.0) / 15.0, 0.0, 1.0);
    return mix(shallow, deep, blend) * (WATER_ABSORPTION * 0.01);
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
// Air-side appearance. Historically this branch was pure absorption ("do not add the
// blue underwater volume source") - that prohibition stopped a grey-blue wash but also
// made deep water converge on a black, green-tinted bed: with no in-scatter the water
// never reads as a BODY, and the no-hit fallback path shaded it as exactly zero
// (consolidated review C2 / F-06 / F-40, superseding the old rule; the underwater
// VOLUME source is still not used here - the fill below uses the surface spectrum's
// own equilibrium colour).
// The +1 block offset keeps knee-deep water visibly tinted; the cap at 24 blocks lets
// the deep end keep darkening instead of freezing at 16.
vec3 water_body_color(float appearanceDepth) {
    // The water's own colour as seen from air, scaled by daylight at the call site.
    // 2026-09-22 (four-symptom round): this used to be one constant navy, (0.020, 0.160,
    // 0.300), at EVERY depth - a hue the transmission curve it accompanies never has. At
    // the shallow end it turned even knee-deep water to blue/green 3.31 while the bed it
    // covered was being transmitted at 1.04, and the mismatch is what read as "grey-blue
    // and opaque" from the bank (qa/tools/airside_water_probe.py sections 1-2 measured
    // both ends). The two ends now follow the SAME (appearanceDepth - 1)/15 blend the
    // spectrum uses: the shallow end carries the shallow transmission's own hue (T at 0
    // blocks, (0.368, 0.951, 0.914), normalised to this luma - cyan-green), and the deep
    // end keeps the old navy, so deep water still converges on blue.
    float blend = clamp((appearanceDepth - 1.0) / 15.0, 0.0, 1.0);
    return mix(vec3(0.056, 0.148, 0.142), vec3(0.020, 0.160, 0.300), blend);
}
vec3 water_surface_medium(vec3 radiance, float verticalDepth, vec3 incidentLight) {
    float depth = max(verticalDepth, 0.0);
    float appearanceDepth = clamp(depth + 1.0, 0.0, 24.0);
    vec3 transmission = exp(-appearanceDepth * water_surface_absorption(appearanceDepth));
    // Single-scattering fill: as the bed fades, the water's own colour takes over. Both
    // ends see the same appearance depth, so fill and transmission cannot disagree about
    // how deep this column is.
    return radiance * transmission
         + water_body_color(appearanceDepth) * clamp(incidentLight, 0.0, 2.0)
           * (1.0 - transmission);
}
#endif
