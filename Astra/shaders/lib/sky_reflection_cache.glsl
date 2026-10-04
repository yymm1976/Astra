#ifndef ASTRA_SKY_REFLECTION_CACHE_GLSL
#define ASTRA_SKY_REFLECTION_CACHE_GLSL

// ITT 3.2 shared sky/cloud environment: idea only. Original Astra cache mapping.
// Original mode: 258 x 128, including two longitude gutters. Rough mode: 256 x
// 128, with periodic filtering at each mip instead of downsampling narrow gutters.
const vec2 ASTRA_SKY_CACHE_CORE = vec2(256.0, 128.0);
const float ASTRA_SKY_CACHE_PI = 3.14159265359;

vec3 astra_sky_cache_direction(vec2 pixel) {
    #ifdef ROUGH_SKY_REFLECTIONS
    vec2 uv = pixel / ASTRA_SKY_CACHE_CORE;
    #else
    vec2 uv = (pixel - vec2(1.0, 0.0)) / ASTRA_SKY_CACHE_CORE;
    #endif
    // fract also duplicates opposite interior columns into the original mode's gutters.
    float longitude = (fract(uv.x) - 0.5) * (2.0 * ASTRA_SKY_CACHE_PI);
    float latitude = (uv.y - 0.5) * ASTRA_SKY_CACHE_PI;
    float radius = cos(latitude);
    return vec3(radius * cos(longitude), sin(latitude), radius * sin(longitude));
}

#ifndef ASTRA_SKY_CACHE_WRITE
uniform sampler2D colortex11;
#ifdef ROUGH_SKY_REFLECTIONS
// One hardware-filtered query away from the longitude seam. Across the seam,
// interpolate the last/first columns explicitly; latitude stays clamp-to-edge.
vec3 astra_sky_cache_level(vec2 uv, int level) {
    vec2 size = vec2(textureSize(colortex11, level));
    float x = uv.x * size.x - 0.5;
    if (x >= 0.0 && x <= size.x - 1.0)
        return textureLod(colortex11, uv, float(level)).rgb;
    vec3 last = textureLod(colortex11, vec2(1.0 - 0.5 / size.x, uv.y), float(level)).rgb;
    vec3 first = textureLod(colortex11, vec2(0.5 / size.x, uv.y), float(level)).rgb;
    return mix(last, first, fract(x));
}
vec3 astra_sky_cache_filtered(vec2 uv, float lod) {
    int lower = int(floor(lod));
    int upper = int(ceil(lod));
    float halfColumn = 0.5 / float(textureSize(colortex11, upper).x);
    if (uv.x >= halfColumn && uv.x <= 1.0 - halfColumn)
        return textureLod(colortex11, uv, lod).rgb;
    vec3 a = astra_sky_cache_level(uv, lower);
    if (lower == upper) return a;
    return mix(a, astra_sky_cache_level(uv, upper), fract(lod));
}
#endif
vec3 astra_cached_reflection_sky(vec3 direction, float roughness) {
    // Direction is normalized by the reflection facade. Avoid atan(0,0) at poles.
    float longitude = dot(direction.xz, direction.xz) > 1e-10
        ? atan(direction.z, direction.x) / (2.0 * ASTRA_SKY_CACHE_PI) + 0.5 : 0.5;
    float latitude = asin(clamp(direction.y, -1.0, 1.0)) / ASTRA_SKY_CACHE_PI + 0.5;
    #ifdef ROUGH_SKY_REFLECTIONS
    // A squared slope footprint keeps polished surfaces detailed. Stop at the
    // one-latitude-row level, before the final mip mixes the entire sphere.
    float r = clamp(roughness, 0.0, 1.0);
    float lod = log2(1.0 + r * r * (ASTRA_SKY_CACHE_CORE.y - 1.0));
    return astra_sky_cache_filtered(vec2(fract(longitude), latitude), lod);
    #else
    float u = (fract(longitude) * ASTRA_SKY_CACHE_CORE.x + 1.0)
            / (ASTRA_SKY_CACHE_CORE.x + 2.0);
    float halfRow = 0.5 / ASTRA_SKY_CACHE_CORE.y;
    float v = clamp(latitude, halfRow, 1.0 - halfRow);
    return textureLod(colortex11, vec2(u, v), 0.0).rgb;
    #endif
}
vec3 astra_cached_reflection_sky(vec3 direction) {
    // SH irradiance continues to integrate the unblurred environment.
    return astra_cached_reflection_sky(direction, 0.0);
}
#endif
#endif
