#ifndef ASTRA_SKY_DIRECTIONAL_GLSL
#define ASTRA_SKY_DIRECTIONAL_GLSL
#include "/lib/sky_sh9.glsl"
uniform sampler2D colortex18;

// SH stores sky radiance, including a deliberately dim lower-hemisphere fill.
// The existing palette sets exposure; the integral supplies directional colour.
//
// R1: split into a coefficients-taking core so a caller that needs TWO direction
// evaluations against the same sky (geometric normal vs. the AO bent normal, in
// the deferred2 ambient compose) loads colortex18 once. Identical math in both.
vec3 astra_directional_sky_coeffs(vec3 coefficients[9], vec3 normal, vec3 palette) {
    vec3 mean = coefficients[0] * ASTRA_SH9_K0;
    // Zero order near zero: fall back to the old facing rule. Bounded output
    // (0.34..1.0 * palette), so a bent-vs-geometric difference stays bounded too.
    if (max(mean.r, max(mean.g, mean.b)) < 0.00001) return palette * (0.67 + normal.y * 0.33);
    vec3 diffuse = max(astra_sh9_diffuse_radiance(coefficients, normal), vec3(0.0));
    // 0.67 is the average of the old directional multiplier over the sphere.
    return palette * 0.67 * clamp(diffuse / max(mean, vec3(0.00001)), 0.0, 2.0);
}

vec3 astra_directional_sky(vec3 normal, vec3 palette) {
    vec3 coefficients[9];
    for (int i = 0; i < 9; ++i) coefficients[i] = texelFetch(colortex18, ivec2(i,0), 0).rgb;
    return astra_directional_sky_coeffs(coefficients, normal, palette);
}
#endif
