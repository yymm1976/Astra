#ifndef ASTRA_RAIN_PARTICLES_GLSL
#define ASTRA_RAIN_PARTICLES_GLSL
// Photon (SixthSurge) and Hysteria (nvb-uy) identify vanilla splash particles by
// their blue texture*tint colour in the particle program. Mechanism reference:
// Photon program/gbuffers_all_solid.fsh; Hysteria program/gbuffer/solid.glsl,
// both in their PROGRAM_GBUFFERS_PARTICLES branch.
// Astra limits the filter to rainy Overworld particle entries, with its own gate.
// Iris has no per-particle type ID here; matching blue particles can also be hidden.
#if defined ASTRA_PARTICLE && !defined DIMENSION_NETHER && !defined DIMENSION_END
bool astra_splash_blue(vec3 gammaColour) {
    return gammaColour.b > 0.74
        && all(lessThan(gammaColour.rg, vec2(0.30,0.46)));
}
bool astra_hide_rain_splash(vec3 gammaColour, vec3 gammaTint) {
    // Splash identity is independent of the camera's medium: underwater views
    // through the refracted window must discard the same sprites as air views.
    return rainStrength > 0.01
        // Vanilla supplies the blue tint for the whole splash. Include it so
        // darker sprite texels cannot survive as a residual particle outline.
        && (astra_splash_blue(gammaTint) || astra_splash_blue(gammaColour));
}
#endif
#endif
