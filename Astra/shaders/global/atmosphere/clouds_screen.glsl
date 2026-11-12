#ifndef ASTRA_CLOUDS_SCREEN_GLSL
#define ASTRA_CLOUDS_SCREEN_GLSL
// Astra cloud-grid resolve; high preserves native subpixel coverage.
// Requires clouds_planar and transforms.
// No scene colour/depth lives here. Occlusion is evaluated at the receiving pixel.
#ifdef ASTRA_CLOUD_TEMPORAL
#include "/lib/cloud_sample_grid.glsl"
// R6/T3: the temporally resolved screen cloud produced by program/cloud_screen.fsh
// (first deferred slot). Same grid and premultiplied semantics as colortex12;
// sampling this instead makes deferred consume the history; sky.fsh draws sprites.
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

float astra_cloud_gather_min(vec4 t) { return min(min(t.x, t.y), min(t.z, t.w)); }
float astra_cloud_gather_max(vec4 t) { return max(max(t.x, t.y), max(t.z, t.w)); }

// Tighten coverage inside a range probed by three diagonal 2x2 gathers.
// This sparse range can miss silhouettes and also detect smooth gradients;
// it is an approximation, with thin coverage protected by a range threshold.
// Include the bilinear coverage itself so shifted footprints cannot create cloud.
// Premultiplied colour and coverage remain paired, without ringing.
vec4 astra_screen_cloud_edge_aware(sampler2D cloudMap, vec2 sampleUV, vec2 rangeUV, vec2 texel) {
    vec2 edge = 0.5 * texel;
    vec4 bilinear = textureLod(cloudMap, sampleUV, 0.0);
    // Producer and resolve bound coverage to [0,1], so a uniform empty or
    // saturated value has no silhouette here and needs no gathers.
    if (bilinear.a <= 0.0 || bilinear.a >= 1.0) return bilinear;
    vec4 g0 = textureGather(cloudMap, rangeUV, 3);
    vec4 gm = textureGather(cloudMap, clamp(rangeUV - 2.0 * texel, edge, 1.0 - edge), 3);
    vec4 gp = textureGather(cloudMap, clamp(rangeUV + 2.0 * texel, edge, 1.0 - edge), 3);
    float amin = min(min(astra_cloud_gather_min(g0), astra_cloud_gather_min(gm)),
                     astra_cloud_gather_min(gp));
    float amax = max(max(astra_cloud_gather_max(g0), astra_cloud_gather_max(gm)),
                     astra_cloud_gather_max(gp));
    // sampleUV carries the coverage jitter while rangeUV does not, so the four
    // texels behind bilinear.a are not guaranteed to be among the sparse
    // probes. Fold the sampled coverage into the interval (no extra fetch) so
    // (bilinear.a - amin) / span can never go negative: an empty sample beside
    // a covered probe must stay empty instead of being lifted to amin.
    amin = min(amin, bilinear.a);
    amax = max(amax, bilinear.a);
    float span = amax - amin;
    float edgeWeight = smoothstep(0.10, 0.30, span);
    if (edgeWeight <= 0.0) return bilinear;
    // Two S-curves inside the probed range tighten the ramp without moving its
    // midpoint and without leaving [amin,amax]. At either extreme the remap is
    // the identity, so it cannot invent coverage or invert the profile.
    float t = smoothstep(0.0, 1.0, (bilinear.a - amin) / span);
    t = smoothstep(0.0, 1.0, t);
    float coverage = mix(bilinear.a, amin + t * span, edgeWeight);
    vec3 colour = bilinear.rgb / max(bilinear.a, 1e-4);
    return vec4(colour * coverage, coverage);
}

vec4 astra_screen_cloud_sample(vec2 uv) {
    #ifdef ASTRA_CLOUD_TEMPORAL
    // History already combines subpixel coverage, so the resolve is not
    // softened a second time by the quadratic footprint. One bilinear fetch
    // still keeps colour/alpha paired; the edge-aware remap tightens the ramp
    // where the sparse probes indicate coverage on both sides of the sample.
    ivec2 size = textureSize(colortex24, 0);
    vec2 texel = 1.0 / vec2(size);
    vec2 edge = 0.5 * texel;
    #if CLOUD_QUALITY == 2
    // Preserve integrated subpixel coverage. Sharpening alpha with two
    // S-curves would turn the anti-aliased silhouette back into hard steps.
    // High has no cloud-grid offset; retain its exact border clamp.
    return textureLod(colortex24, clamp(uv, edge, 1.0 - edge), 0.0);
    #else
    vec2 rangeUV = clamp(uv, edge, 1.0 - edge);
    vec2 sampleUV = clamp(uv - astra_cloud_grid_offset(frameCounter, size), edge, 1.0 - edge);
    return astra_screen_cloud_edge_aware(colortex24, sampleUV, rangeUV, texel);
    #endif
    #else
    #if CLOUD_QUALITY == 2
    // Native high-quality output needs no wide low-resolution reconstruction.
    return textureLod(colortex12, uv, 0.0);
    #else
    return astra_screen_cloud_filter(colortex12, uv);
    #endif
    #endif
}

// Returns premultiplied colour and alpha. Geometry inside the slab needs its own
// clipped march; geometry in front must not inherit cloud from neighbouring sky.
vec4 astra_screen_cloud(vec2 uv, vec3 ray, float opaqueDistance, float angularFootprint) {
    vec2 interval = astra_cloud_interval(ray);
    if (interval.y <= interval.x || opaqueDistance <= interval.x) return vec4(0.0);
    // A small guard around the exit also covers the wider low-resolution footprint.
    if (opaqueDistance < interval.y * 1.02 + 4.0) {
        vec3 representative;
        // `ray` is the caller's unit direction and `interval` is its own slab,
        // solved above: reuse both instead of letting the wrapper redo them.
        vec4 cloud = astra_planar_cloud(ray, opaqueDistance, representative, angularFootprint,
                                        interval);
        return vec4(cloud.rgb * cloud.a, cloud.a);
    }
    return astra_screen_cloud_sample(uv);
}
#endif
