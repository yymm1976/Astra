#ifndef ASTRA_GLOBAL_WATER_CAUSTICS_GLSL
#define ASTRA_GLOBAL_WATER_CAUSTICS_GLSL
// Adapted from Solas V2.2b lib/water/waterCaustics.glsl by Septonious.
// Uses its supplied noise image and defaults; see THIRD-PARTY.md.
// solasWaterNoise is declared in lib/uniforms.glsl.
float solas_water_height(vec3 p, vec2 offset) {
    vec2 wind = vec2(frameTimeCounter) * 0.5 * 1.5;
    p.xz -= p.y * 0.2;
    float a = textureLod(solasWaterNoise, (p.xz - wind) / 256.0 + offset / 256.0, 0.0).g;
    float b = textureLod(solasWaterNoise, (p.xz + wind) / 48.0 + offset / 256.0, 0.0).g;
    return mix(a, b, 0.40) * 0.4;
}
float solas_water_caustics(vec3 p) {
    float h = solas_water_height(p, vec2(0.0));
    float xa = (solas_water_height(p, vec2(0.5, 0.0)) - h) / 0.5;
    float xb = (solas_water_height(p, vec2(-0.5, 0.0)) - h) / 0.5;
    float ya = (solas_water_height(p, vec2(0.0, 0.5)) - h) / 0.5;
    float yb = (solas_water_height(p, vec2(0.0, -0.5)) - h) / 0.5;
    return max((xa * -xb + ya * -yb) * 48.0, 0.0);
}
// Solas waterNormals: four parallax steps, then the same height field used by caustics.
vec3 solas_water_normal(vec3 worldPos, vec3 face, vec3 tangent, vec3 binormal,
                        vec3 viewVector, float viewDistance, float fresnel) {
    for (int i = 0; i < 4; ++i) {
        float height = -1.25 * solas_water_height(worldPos, vec2(0.0)) + 0.25;
        worldPos.xz += height * viewVector.xy / max(viewDistance, 0.0001);
    }
    float x = (solas_water_height(worldPos, vec2(-0.5, 0.0)) - solas_water_height(worldPos, vec2(0.5, 0.0))) / 0.5;
    float y = (solas_water_height(worldPos, vec2(0.0, -0.5)) - solas_water_height(worldPos, vec2(0.0, 0.5))) / 0.5;
    return normalize(tangent * x + binormal * y + face * (1.0 - x*x - y*y - fresnel * 0.5));
}
#endif
