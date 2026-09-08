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
vec3 water_light_direction(vec3 toLight) {
    return -refract(-normalize(toLight), vec3(0.0, 1.0, 0.0), 1.0 / WATER_IOR);
}
float water_light_entry(vec3 toLight) {
    bool tir;
    return 1.0 - water_fresnel(max(toLight.y, 0.0), 1.0 / WATER_IOR, tir);
}
// A surface-anchored focusing field is constant along an incoming refracted ray.
// It modulates actual visible solar energy; occluded samples still contribute zero.
float water_sun_focus(vec3 surfaceWorld) {
    #ifdef WATER_CAUSTICS
        vec2 drift = vec2(frameTimeCounter * 0.18, -frameTimeCounter * 0.11);
        float broad = textureLod(noisetex, (surfaceWorld.xz + drift) / 512.0, 0.0).g;
        float fine = textureLod(noisetex, (surfaceWorld.xz - drift) / 256.0, 0.0).g;
        // Narrow connected crests and dark intervals create actual columns when
        // this surface field is transported along the refracted sun direction.
        // The former broad smoothstep mostly raised the uniform medium. Explicit
        // LOD keeps its spatial frequency identical in terrain and volume passes.
        float crest = max(1.0 - abs(mix(broad, fine, 0.3) - 0.5) * 8.0, 0.0);
        return 0.12 + 6.0 * crest * crest;
    #else
        return 1.0;
    #endif
}
// Henyey-Greenstein phase per steradian; average over the sphere is 1/(4*pi).
float water_phase(float cosine) {
    const float g = 0.60;
    float denominator = max(1.0 + g*g - 2.0*g*clamp(cosine, -1.0, 1.0), 1e-4);
    return (1.0 - g*g) / (12.5663706144 * denominator * sqrt(denominator));
}
#endif
