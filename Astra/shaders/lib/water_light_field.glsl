#ifndef ASTRA_WATER_LIGHT_FIELD_GLSL
#define ASTRA_WATER_LIGHT_FIELD_GLSL
// Shared by the live volume and the GPU arithmetic probe.
float astra_water_phase(vec3 ray, vec3 sunWorld) {
    vec3 apparentSun = refract(sunWorld,vec3(0.0,-1.0,0.0),1.0/1.333);
    return mix(pow(clamp(dot(ray,apparentSun),0.0,1.0),1.5),0.5,0.25);
}
vec3 astra_water_beam_tint(vec3 caster, float distanceInWater) {
    // Water attenuates even a white caster. Keep chroma independent of caustic gain.
    vec3 transmission = exp(-vec3(0.14,0.035,0.018)*max(distanceInWater,1.0));
    return clamp(caster,0.0,2.2)*transmission;
}
vec3 astra_water_beam_limit(vec3 integral) {
    // Scalar compression preserves hue. Per-channel pow(x, near-zero) whitened beams.
    float peak = max(integral.r,max(integral.g,integral.b));
    return integral / (1.0 + peak);
}
#endif
