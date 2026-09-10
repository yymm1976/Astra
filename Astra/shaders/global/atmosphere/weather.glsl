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
vec3 astra_puddle_normal(vec3 worldPos) {
    // Expanding local rings; random cell phases prevent synchronized stripes.
    vec2 grid = worldPos.xz * 1.3;
    vec2 slope = vec2(0.0);
    for (int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        vec2 id = floor(grid) + vec2(x,y);
        float seed = fract(sin(dot(id,vec2(127.1,311.7))) * 43758.5453);
        vec2 delta = grid - (id + vec2(seed,fract(seed*73.31)));
        float radius = length(delta);
        float age = fract(frameTimeCounter * 0.85 + seed);
        float ring = radius - age * 1.6;
        slope += delta / max(radius,0.02) * sin(ring*28.0)
               * exp(-ring*ring*80.0) * (1.0-age) * smoothstep(0.0,0.1,age);
    }
    // Amplitude raised for the user's "rings on water are missing" round. The old
    // 0.018 perturbation was below the threshold where a specular highlight reads as a
    // ring, especially at the grazing angles a shoreline view produces.
    return normalize(vec3(slope.x * 0.055 * astraRainFactor, 1.0, slope.y * 0.055 * astraRainFactor));
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
