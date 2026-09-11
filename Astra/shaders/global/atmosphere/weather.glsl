#ifndef ASTRA_WEATHER_GLSL
#define ASTRA_WEATHER_GLSL
#include "/lib/noise.glsl"
float astra_rain_exposure(float skyLight) {
    // pow(.., 16) required skyLight > 0.95, i.e. fully exposed noon terrain, which made
    // both puddles and the water impact rings vanish under any overcast sky. The user's
    // rain round is exactly that situation, so the curve is relaxed to a still-selective
    // but usable range.
    return pow(clamp(skyLight, 0.0, 1.0), 7.5)
         * smoothstep(0.0, 0.15, rainfall) * smoothstep(0.10, 0.20, temperature);
}
float astra_puddle(vec3 worldPos, vec3 normal, float skyLight) {
    // Solas generatedPBR: wetness, sky light, upward face and two noise scales.
    float n = texture(solasWaterNoise, worldPos.xz * 0.00025).b
            * texture(solasWaterNoise, worldPos.xz * 0.00050).b;
    return smoothstep(0.43, 0.66, n) * wetness
         * astra_rain_exposure(skyLight) * smoothstep(0.86, 0.999, normal.y);
}
// Rain impact ripples, ported from IterationT 3.2 Lib/IndividualFounctions/Ripple.glsl.
//
// The reference does not generate ripples procedurally: it ships three 60-frame flipbooks
// and plays them by scrolling V in sixty discrete steps (frame = fract(floor(t*60)/60)),
// which is why they read as sharp expanding rings rather than noise. Three layers are
// blended by a downfall mask, and the layer sharpness follows wetness (a dry surface shows
// crisper rings than a soaked one).
//
// Astra adapters: the reference reads a downfall noise for the layer mask, this uses the
// rain exposure already computed for puddles, and the LOD attenuation uses fwidth of the
// world position. Ramps are deliberately not used.
vec2 astra_ripple_layer(sampler2D sheet, vec2 coord, float rp) {
    vec2 n = textureLod(sheet, coord, 0.0).rg * 2.0 - 1.0;
    n = pow(abs(n), vec2(rp)) * sign(n);
    return n;
}
vec2 astra_rain_ripple(vec3 worldPos, float strength) {
    if (strength <= 1e-4) return vec2(0.0);
    vec2 p = worldPos.xz * 0.5;
    float frame = fract(floor(frameTimeCounter * 60.0) / 60.0);
    vec2 coord = vec2(p.x, fract(p.y / 60.0) - frame);
    float w = clamp(wetness, 0.0, 1.0);
    float rp = 2.0 - pow(w, 4.0) * 1.2;
    vec2 n = astra_ripple_layer(astraRipple1, coord, rp);
    n += astra_ripple_layer(astraRipple2, coord, rp) * clamp(strength * 2.0, 0.0, 1.0);
    n += astra_ripple_layer(astraRipple3, coord, rp) * clamp(strength * 2.0 - 1.0, 0.0, 1.0);
    float lod = dot(fwidth(worldPos.xz), vec2(1.0));
    n /= lod * 5.0 + 1.0;
    return n * strength;
}
// Same cloud field as the visible layer; ray starts at the receiving world point.
float astra_cloud_transmission(vec3 worldPos, vec3 lightDir) {
    if (lightDir.y <= 0.01) return 0.0;
    float t = (ASTRA_CLOUD_ALTITUDE-worldPos.y)/lightDir.y;
    if(t <= 0.0) return 1.0;
    vec3 hit = worldPos + lightDir*t;
    float n = astra_cloud_noise(hit, ASTRA_CLOUD_ALTITUDE);
    float threshold = 0.25 + mix(0.20,-0.20,CLOUD_COVERAGE*0.01) - 0.28*astraRainFactor;
    float cloud = smoothstep(threshold-0.025,threshold+0.025,n);
    return mix(1.0, 0.07, cloud);
}
#endif
