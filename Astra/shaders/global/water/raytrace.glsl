#ifndef ASTRA_GLOBAL_WATER_RAYTRACE_GLSL
#define ASTRA_GLOBAL_WATER_RAYTRACE_GLSL

// Astra v1 - water/ice screen-space reflections.
// New Astra implementation based on the project specification and Khronos GLSL
// texture-gather/projection semantics; no source shader code was incorporated.
// Primary language reference (texture gather functions, section 8.7):
// https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.4.00.pdf
//
// Uniforms: gbufferProjection, gbufferProjectionInverse (lib/uniforms.glsl).
// The caller supplies depthtex1 and consumes the matching raw colour separately.
// Returns UV/depth and confidence; colour and optical length stay paired in the caller.

#if WATER_EFFECT_QUALITY == 0
const int ASTRA_WATER_TRACE_BUDGET = 16;
const int ASTRA_WATER_REFINE_STEPS = 4;
#elif WATER_EFFECT_QUALITY == 2
const int ASTRA_WATER_TRACE_BUDGET = 40;
const int ASTRA_WATER_REFINE_STEPS = 8;
#else
const int ASTRA_WATER_TRACE_BUDGET = 30;
const int ASTRA_WATER_REFINE_STEPS = 6;
#endif
const int ASTRA_WATER_COARSE_STEPS = ASTRA_WATER_TRACE_BUDGET - ASTRA_WATER_REFINE_STEPS;

// Projection is affine before the divide. Project the origin and direction
// once, including TAA's affine clip offset, then advance in homogeneous space.
bool water_ssr_project_clip(vec4 clip, vec2 halfTexel, out vec2 uv) {
    if (clip.w <= 0.00001) return false;
    vec3 ndc = clip.xyz / clip.w;
    if (any(greaterThan(abs(ndc), vec3(1.0)))) return false;
    uv = ndc.xy * 0.5 + 0.5;
    return all(greaterThanEqual(uv, halfTexel))
        && all(lessThanEqual(uv, vec2(1.0) - halfTexel));
}
// Only view Z and the interface-side plane are needed by the march; do not
// reconstruct a full XYZ point for each depth query.
vec2 water_ssr_receiver(vec2 uv, float depth, vec2 jitter, vec4 sidePlane,
                         vec4 zRow, vec4 wRow, bool depthOnlyZW, bool newPixel,
                         inout vec2 cachedZW) {
    vec4 ndc = vec4((uv - jitter) * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    // In a standard projection Z/W depend only on depth. Repeated texel visits
    // can reuse both, while the interface-side plane still follows the exact UV.
    // Nonstandard projections retain the full reconstruction on every visit.
    if (!depthOnlyZW || newPixel) {
        float inverseW = 1.0 / dot(wRow, ndc);
        cachedZW = vec2(dot(zRow, ndc) * inverseW, inverseW);
    }
    return vec2(cachedZW.x, dot(sidePlane, ndc) * cachedZW.y);
}

vec4 water_raytrace(sampler2D sceneDepth, vec3 viewPos, vec3 rayDirection,
                    vec3 interfaceNormal) {
    rayDirection = normalize(rayDirection);
    float rangeVisibility = 1.0 - smoothstep(64.0, 128.0, length(viewPos));
    if (rangeVisibility <= 0.0) return vec4(0.0);

    vec3 origin = viewPos + rayDirection * 0.02;
    vec4 clipOrigin = astra_jitter_clip(gbufferProjection * vec4(origin, 1.0));
    vec4 clipDirection = astra_jitter_clip(gbufferProjection * vec4(rayDirection, 0.0));
    ivec2 depthSize = textureSize(sceneDepth, 0);
    vec2 halfTexel = 0.5 / vec2(depthSize);
    vec2 jitter = astra_jitter_uv();
    mat4 inverseRows = transpose(gbufferProjectionInverse);
    vec4 sidePlane = inverseRows * vec4(interfaceNormal, -dot(viewPos, interfaceNormal));
    vec4 zRow = inverseRows[2], wRow = inverseRows[3];
    bool depthOnlyZW = all(equal(zRow.xy, vec2(0.0))) && all(equal(wRow.xy, vec2(0.0)));
    // Repeated visits to the same texel need no new read, even during refinement.
    ivec2 cachedPixel = ivec2(-1);
    float cachedDepth = 1.0;
    vec2 cachedZW = vec2(0.0, 1.0);
    float low = 0.0;
    float high = 0.0;
    float previous = 0.0;
    float stride = clamp(-viewPos.z * 0.0025, 0.08, 0.25);
    vec2 hitUV = vec2(0.0);
    float hitDepth = 1.0;
    float sceneZ = 0.0;
    bool found = false;
    // Keep the first depth crossing on the REFLECTED side. A submerged floor
    // must not end an above-water reflection before the ray reaches the shore.
    for (int i = 0; i < ASTRA_WATER_COARSE_STEPS; ++i) {
        float travel = previous + stride;
        vec2 uv;
        if (!water_ssr_project_clip(clipOrigin + clipDirection * travel, halfTexel, uv)) break;
        ivec2 pixel = clamp(ivec2(uv * vec2(depthSize)), ivec2(0), depthSize - 1);
        bool newPixel = any(notEqual(pixel, cachedPixel));
        if (newPixel) {
            cachedDepth = texelFetch(sceneDepth, pixel, 0).r;
            cachedPixel = pixel;
        }
        float depth = cachedDepth;
        if (depth < 0.999999) {
            vec2 receiver = water_ssr_receiver(uv, depth, jitter, sidePlane, zRow, wRow,
                                              depthOnlyZW, newPixel, cachedZW);
            if (receiver.y > 0.0 && origin.z + rayDirection.z * travel <= receiver.x) {
                low = previous;
                high = travel;
                hitUV = uv;
                hitDepth = depth;
                sceneZ = receiver.x;
                found = true;
                break;
            }
        }
        previous = travel;
        stride = min(stride * 1.6, 8.0);
    }
    if (!found) return vec4(0.0);

    // Refine a depth interval, without fitting a plane through unrelated leaves.
    // Fine queries are reserved inside the total budget, including late hits.
    for (int i = 0; i < ASTRA_WATER_REFINE_STEPS; ++i) {
        float middle = 0.5 * (low + high);
        vec2 uv;
        if (!water_ssr_project_clip(clipOrigin + clipDirection * middle, halfTexel, uv)) break;
        ivec2 pixel = clamp(ivec2(uv * vec2(depthSize)), ivec2(0), depthSize - 1);
        bool newPixel = any(notEqual(pixel, cachedPixel));
        if (newPixel) {
            cachedDepth = texelFetch(sceneDepth, pixel, 0).r;
            cachedPixel = pixel;
        }
        float depth = cachedDepth;
        bool behind = false;
        float candidateSceneZ = sceneZ;
        if (depth < 0.999999) {
            vec2 receiver = water_ssr_receiver(uv, depth, jitter, sidePlane, zRow, wRow,
                                              depthOnlyZW, newPixel, cachedZW);
            behind = receiver.y > 0.0 && origin.z + rayDirection.z * middle <= receiver.x;
            candidateSceneZ = receiver.x;
        }
        if (behind) {
            high = middle;
            hitUV = uv;
            hitDepth = depth;
            sceneZ = candidateSceneZ;
        } else {
            low = middle;
        }
    }
    vec3 endpoint = origin + rayDirection * high;
    // The accepted hit already supplies this exact UV/depth reconstruction.
    float footprint = 2.0 * abs(sceneZ) / max(abs(gbufferProjection[1][1]) * viewHeight, 1.0);
    float thickness = max(0.25, footprint * 2.0);
    float residual = abs(sceneZ - endpoint.z);
    float confidence = 1.0 - smoothstep(thickness, thickness * 2.0, residual);
    float edge = min(min(hitUV.x, 1.0-hitUV.x), min(hitUV.y, 1.0-hitUV.y));
    confidence *= smoothstep(0.0, 0.03, edge) * rangeVisibility;
    return vec4(hitUV, hitDepth, confidence);
}

#endif
