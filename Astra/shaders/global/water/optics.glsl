#ifndef ASTRA_GLOBAL_WATER_OPTICS_GLSL
#define ASTRA_GLOBAL_WATER_OPTICS_GLSL
// Written for Astra: dielectric interface equations, in world space.
// eta is incident IOR / transmitted IOR. No artistic F0 or skylight multiplier.
const float WATER_IOR = 1.333;
float water_fresnel(float cosIncident, float eta, out bool totalReflection) {
    float ci = clamp(cosIncident, 0.0, 1.0);
    float st2 = eta * eta * (1.0 - ci * ci);
    totalReflection = st2 >= 1.0;
    if (totalReflection) return 1.0;
    float ct = sqrt(max(1.0 - st2, 0.0));
    float rs = (eta * ci - ct) / max(eta * ci + ct, 1e-6);
    float rp = (ci - eta * ct) / max(ci + eta * ct, 1e-6);
    return clamp(0.5 * (rs * rs + rp * rp), 0.0, 1.0);
}
#endif
