#ifndef ASTRA_SKY_GRADIENT_CACHE_GLSL
#define ASTRA_SKY_GRADIENT_CACHE_GLSL
// Original Astra mapping of the two angular inputs to a same-frame HDR table.
// Both zero angles and the domain endpoints have exact table nodes. This table
// contains only the smooth sky base: no glare, sprites, stars, dither or medium.
// Keep these dimensions paired with shaders.properties. Odd sizes retain exact
// zero-angle nodes; sharp sky layers are evaluated outside this smooth table.
// Cloud quality owns this table independently of the surface/water budget.
// Producer and every consumer share the same size and UV mapping.
#if CLOUD_QUALITY == 0
const vec2 ASTRA_GRADIENT_SKY_SIZE = vec2(65.0);
#elif CLOUD_QUALITY == 2
const vec2 ASTRA_GRADIENT_SKY_SIZE = vec2(257.0);
#else
const vec2 ASTRA_GRADIENT_SKY_SIZE = vec2(129.0);
#endif
vec2 astra_gradient_sky_angles(vec2 pixel) {
    return (pixel - 0.5) / (ASTRA_GRADIENT_SKY_SIZE - 1.0) * 2.0 - 1.0;
}
#ifndef ASTRA_GRADIENT_SKY_WRITE
uniform sampler2D colortex12;
vec3 astra_gradient_sky_cached(float viewUp, float viewSun) {
    vec2 coordinate = clamp(vec2(viewUp, viewSun), vec2(-1.0), vec2(1.0)) * 0.5 + 0.5;
    vec2 uv = (coordinate * (ASTRA_GRADIENT_SKY_SIZE - 1.0) + 0.5) / ASTRA_GRADIENT_SKY_SIZE;
    return textureLod(colortex12, uv, 0.0).rgb;
}
#endif
#endif
