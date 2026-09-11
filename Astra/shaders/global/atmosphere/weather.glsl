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
// Rain impact ripples.
//
// Astra generates its own flipbook rather than shipping anyone else's artwork: three
// 128x7680 sheets (sixty 128x128 frames) built by qa/tools/gen_rain_ripple.py from an
// explicit model of expanding, decaying circular wavelets, differentiated into a normal
// map. The shader plays them by scrolling V in sixty discrete steps, so no .mcmeta
// animation section is involved and the sheets stay a plain 2D texture.
//
// Sheet 1 is the drizzle layer, sheets 2 and 3 fade in as the rain deepens, and ring
// sharpness follows wetness (a soaked surface holds softer ripples than a damp one).
//
// World scale: one sheet repeat spans ASTRA_RIPPLE_TILE blocks, chosen so a ring in the
// sheet lands at roughly one to two blocks - the size a raindrop impact actually is.
const float ASTRA_RIPPLE_TILE = 4.0;

vec2 astra_ripple_layer(sampler2D sheet, vec2 coord, float rp) {
    vec2 n = textureLod(sheet, coord, 0.0).rg * 2.0 - 1.0;
    n = pow(abs(n), vec2(rp)) * sign(n);
    return n;
}
vec2 astra_rain_ripple(vec3 worldPos, float strength) {
    if (strength <= 1e-4) return vec2(0.0);
    vec2 p = worldPos.xz / ASTRA_RIPPLE_TILE;
    float frame = fract(floor(frameTimeCounter * 60.0) / 60.0);
    // Z offsets the animation phase so neighbouring tiles do not ripple in lockstep.
    vec2 coord = vec2(p.x, fract(p.y * 0.25) - frame);
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
