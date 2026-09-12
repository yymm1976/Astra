#ifndef ASTRA_WEATHER_GLSL
#define ASTRA_WEATHER_GLSL
#include "/lib/noise.glsl"
float astra_rain_exposure(float skyLight) {
    // pow(.., 16) required skyLight > 0.95, i.e. fully exposed noon terrain, which made
    // both puddles and the water impact rings vanish under any overcast sky. The user's
    // rain round is exactly that situation, so the curve is relaxed to a still-selective
    // but usable range.
    return pow(clamp(skyLight, 0.0, 1.0), 4.0)
         * smoothstep(0.0, 0.15, rainfall) * smoothstep(0.10, 0.20, temperature);
}
float astra_puddle(vec3 worldPos, vec3 normal, float skyLight) {
    // Smaller, separated patches; visible standing water follows the short
    // rain envelope rather than the engine's long-lived wetness memory.
    float n = texture(solasWaterNoise, worldPos.xz * 0.00075).b * 0.65
            + texture(solasWaterNoise, worldPos.xz * 0.00150).b * 0.35;
    // Only about one third of stable ten-block regions can accumulate puddles.
    vec2 cell = floor(worldPos.xz * 0.1);
    float choice = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
    vec2 edge = smoothstep(vec2(0.0), vec2(0.08),
                          min(fract(worldPos.xz * 0.1), 1.0 - fract(worldPos.xz * 0.1)));
    float coverage = (1.0 - step(0.33, choice)) * edge.x * edge.y;
    return coverage * smoothstep(0.48, 0.64, n) * max(wetness, astraRainFactor * 0.8)
         * smoothstep(0.02, 0.55, astraRainFactor) * 0.85
         * astra_rain_exposure(skyLight) * smoothstep(0.86, 0.999, normal.y);
}
// Rain impact ripples.
//
// Astra generates its own flipbook rather than shipping anyone else's artwork: three
// 128x7680 sheets (sixty 128x128 frames) built by qa/tools/gen_rain_ripple.py from an
// explicit model of expanding, decaying circular wavelets, differentiated into a normal
// map. Local UV stays inside one frame; only the frame index selects time.
// Use the sparse first sheet, with a restrained second layer in heavy rain.
const float ASTRA_RIPPLE_TILE = 4.0;

vec2 astra_ripple_layer(sampler2D sheet, vec2 localUV, float frame) {
    vec2 uv = clamp(localUV, vec2(0.5 / 128.0), vec2(127.5 / 128.0));
    float current = floor(frame);
    vec2 a = vec2(uv.x, (mod(current, 60.0) + uv.y) / 60.0);
    vec2 b = vec2(uv.x, (mod(current + 1.0, 60.0) + uv.y) / 60.0);
    vec2 n = mix(textureLod(sheet, a, 0.0).rg,
                 textureLod(sheet, b, 0.0).rg, fract(frame)) * 2.0 - 1.0;
    // Remove the half-byte bias of the neutral RG8 normal.
    return sign(n) * max(abs(n) - vec2(1.0 / 255.0), vec2(0.0));
}
vec2 astra_rain_ripple(vec3 worldPos, float strength) {
    strength *= smoothstep(0.01, 0.8, astraRainFactor);
    vec2 p = worldPos.xz / ASTRA_RIPPLE_TILE;
    float footprint = max(length(dFdx(p)), length(dFdy(p)));
    float phase = fract(sin(dot(floor(p), vec2(127.1, 311.7))) * 43758.5453);
    float frame = mod(frameTimeCounter * 0.65, 1.0) * 60.0 + phase * 60.0;
    vec2 uv = fract(p);
    vec2 n = astra_ripple_layer(astraRipple1, uv, frame);
    n += astra_ripple_layer(astraRipple2, uv, frame + 23.0)
       * smoothstep(0.75, 1.0, strength) * 0.15;
    // Fade unresolved rings and tile boundaries rather than aliasing across frames.
    vec2 edge = smoothstep(vec2(0.0), vec2(0.06), min(uv, 1.0 - uv));
    float resolved = 1.0 - smoothstep(0.015, 0.08, footprint);
    return n * strength * 0.28 * edge.x * edge.y * resolved;
}
// Same cloud field as the visible layer; ray starts at the receiving world point.
float astra_cloud_transmission(vec3 worldPos, vec3 lightDir) {
    if (lightDir.y <= 0.01) return 0.0;
    float t = (ASTRA_CLOUD_ALTITUDE-worldPos.y)/lightDir.y;
    if(t <= 0.0) return 1.0;
    vec3 hit = worldPos + lightDir*t;
    float n = astra_cloud_noise(hit, ASTRA_CLOUD_ALTITUDE);
    float threshold = 0.21 + mix(0.20,-0.20,CLOUD_COVERAGE*0.01) - 0.28*astraRainFactor;
    float cloud = smoothstep(threshold-0.025,threshold+0.025,n);
    return mix(1.0, 0.07, cloud);
}
#endif
