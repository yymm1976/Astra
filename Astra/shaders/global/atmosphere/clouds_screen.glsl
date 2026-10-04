#ifndef ASTRA_CLOUDS_SCREEN_GLSL
#define ASTRA_CLOUDS_SCREEN_GLSL
// Original Astra half-resolution resolve; requires clouds_planar and transforms.
// No scene colour/depth lives here. Occlusion is evaluated at the receiving pixel.
#ifdef ASTRA_CLOUD_TEMPORAL
// R6/T3: the temporally resolved screen cloud produced by program/cloud_screen.fsh
// (first deferred slot). Same grid and premultiplied semantics as colortex12;
// sampling this instead is what makes deferred and sky.fsh consume the history.
uniform sampler2D colortex24;
#else
uniform sampler2D colortex12;
#endif

vec4 astra_screen_cloud_filter(sampler2D cloudMap, vec2 uv) {
    vec2 size = vec2(textureSize(cloudMap, 0));
    vec2 position = uv * size - 0.5;
    vec2 centre = floor(position + 0.5);
    vec2 f = position - centre;
    vec2 left = 0.5 * (0.5 - f) * (0.5 - f);
    vec2 middle = 0.75 - f * f;
    vec2 right = 0.5 * (0.5 + f) * (0.5 + f);
    vec2 pair = left + middle;
    vec2 edge = 0.5 / size;
    vec2 a = clamp((centre + 0.5 - left / pair) / size, edge, 1.0 - edge);
    vec2 b = clamp((centre + 1.5) / size, edge, 1.0 - edge);
    // Nine positive quadratic weights collapse into four bilinear fetches.
    // Premultiplied colour and coverage share the footprint; scene colour does not.
    return textureLod(cloudMap, a, 0.0) * pair.x * pair.y
         + textureLod(cloudMap, vec2(b.x, a.y), 0.0) * right.x * pair.y
         + textureLod(cloudMap, vec2(a.x, b.y), 0.0) * pair.x * right.y
         + textureLod(cloudMap, b, 0.0) * right.x * right.y;
}
vec4 astra_screen_cloud_sample(vec2 uv) {
    #ifdef ASTRA_CLOUD_TEMPORAL
    return astra_screen_cloud_filter(colortex24, uv);
    #else
    return astra_screen_cloud_filter(colortex12, uv);
    #endif
}

// Returns premultiplied colour and alpha. Geometry inside the slab needs its own
// clipped march; geometry in front must not inherit cloud from neighbouring sky.
vec4 astra_screen_cloud(vec2 uv, vec3 ray, float opaqueDistance) {
    vec2 interval = astra_cloud_interval(ray);
    if (interval.y <= interval.x || opaqueDistance <= interval.x) return vec4(0.0);
    // A small guard around the exit also covers the wider low-resolution footprint.
    if (opaqueDistance < interval.y * 1.02 + 4.0) {
        vec4 cloud = astra_planar_cloud(ray, opaqueDistance);
        return vec4(cloud.rgb * cloud.a, cloud.a);
    }
    return astra_screen_cloud_sample(uv);
}
#endif
