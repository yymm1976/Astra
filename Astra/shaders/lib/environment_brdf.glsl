#ifndef ASTRA_ENVIRONMENT_BRDF_GLSL
#define ASTRA_ENVIRONMENT_BRDF_GLSL
// Scalar adaptation of Musk Rose 4.1 (Rin, CC0-1.0), getEnvironmentBRDF.
// That source credits the UE4 mobile environment BRDF fit:
// https://www.unrealengine.com/en-US/blog/physically-based-shading-on-mobile
// Source and adaptation boundaries are recorded in THIRD-PARTY.md.
float astra_environment_brdf(float roughness, float grazingFalloff, float f0) {
    vec4 fit = roughness * vec4(-1.0, -0.0275, -0.572, 0.022)
             + vec4(1.0, 0.0425, 1.04, -0.04);
    float grazing = min(fit.x * fit.x, grazingFalloff) * fit.x;
    vec2 scaleBias = vec2(-1.04, 1.04) * grazing + fit.y + fit.zw;
    return max(f0 * scaleBias.x + scaleBias.y, 0.0);
}
float astra_environment_reflection_gain(float roughness, float noV, float f0) {
    #if defined ROUGH_SKY_REFLECTIONS && CLOUD_MODE == CLOUD_PLANAR && !defined DIMENSION_NETHER && !defined DIMENSION_END
    float r = clamp(roughness, 0.0, 1.0);
    float n = clamp(noV, 0.0, 1.0);
    float base = clamp(f0, 0.0, 1.0);
    // Surface composition already applies Fresnel. Use only the relative roughness
    // response to avoid multiplying it twice or raising the existing mirror energy.
    float grazingFalloff = exp2(-9.28 * n);
    float polished = astra_environment_brdf(0.0, grazingFalloff, base);
    return clamp(astra_environment_brdf(r, grazingFalloff, base) / max(polished, 1e-5), 0.0, 1.0);
    #else
    return 1.0;
    #endif
}
#endif
