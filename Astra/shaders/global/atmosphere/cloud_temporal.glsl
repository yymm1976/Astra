#ifndef ASTRA_CLOUD_TEMPORAL_GLSL
#define ASTRA_CLOUD_TEMPORAL_GLSL
// R6/T3 - independent temporal history for the SCREEN-VISIBLE planar cloud only.
// Handoff: docs/handoffs/2026-09-27-R6-cloud-temporal.md
//
// colortex11 (spherical reflection board) and colortex14 (world cloud shadow) use
// different coordinates, depths and production timing; they do NOT share this
// history and have none of their own yet.
//
// Read/write ordering: the only pass touching colortex24/25 is program/
// cloud_screen.fsh (deferred). It reads both through Iris's buffer flip - a program
// sampling a buffer it also renders to sees the PREVIOUS frame's attachment (the
// pack's established pattern, taa_resolve.fsh <-> colortex15) - and writes the new
// history. Nothing assumes same-draw visibility of its own writes. Consumers
// (program/deferred.fsh via clouds_screen.glsl) read colortex24 in later deferred
// slots of the same frame, after opaque-depth-aware cloud production has finished.
//
// The chain is deliberately independent of ASTRA_TAA: with TAA off the pack does
// not declare the previous-frame matrices (lib/uniforms.glsl), so this module
// declares them itself and keeps maintaining its own state.
#ifdef ASTRA_CLOUD_TEMPORAL

// ---- buffer registration (single home; consumers only sample colortex24) ----
// RGBA16F is provided by the including pass (program/cloud_screen.fsh). Iris's
// preprocessor evaluates #ifndef on non-option tokens as always-true, so a second
// guarded definition here would conflict with the pass's own (compile finding).
// Resolved screen cloud AND its colour history: rgb = premultiplied radiance,
// a = coverage. Zero coverage is the empty-cloud zero, so a cleared buffer simply
// falls back to the current frame.
const int colortex24Format = RGBA16F;
const bool colortex24Clear = false;
const vec4 colortex24ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
// Per-texel representative metadata: r = representative distance along the
// producing ray, g = frameCounter modulo 2048 (exact in half float), b = viewWidth
// fingerprint, a = coverage (>0 marks a valid representative).
const int colortex25Format = RGBA16F;
const bool colortex25Clear = false;
const vec4 colortex25ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

uniform sampler2D colortex24;
uniform sampler2D colortex25;
uniform float frameTime;

#ifndef ASTRA_TAA
uniform mat4  gbufferPreviousModelView;
uniform mat4  gbufferPreviousProjection;
uniform vec3  previousCameraPosition;
#endif

// History share of the exponential blend. Source-derived initial value; needs
// in-game A/B like every constant in this module.
const float ASTRA_CLOUD_TEMPORAL_WEIGHT = 0.90;

// current = vec4(premultiplied radiance, coverage) straight from this frame's
// march; representativeWorld = the integral's transmittance-weighted first moment
// (single-hit model -> the first hit, vec3(0) when the column is empty).
// Returns the blended premultiplied cloud for colortex24 and writes colortex25's
// metadata. Every rejected condition falls back to the CURRENT cloud result.
vec4 astra_cloud_temporal_resolve(vec4 current, vec3 representativeWorld,
                                  vec2 uv, out vec4 metaOut) {
    float stampNow = float(frameCounter % 2048);
    metaOut = vec4(0.0, stampNow, viewWidth, current.a);
    if (current.a > 0.0) metaOut.r = length(representativeWorld - cameraPosition);

    // Startup / world reload, and the empty-column rule: no valid representative
    // position means the current cloud result is used verbatim.
    if (astraTimeDiscontinuity != 0 || frameCounter <= 1 || current.a <= 0.0
        || any(isnan(current)) || any(isinf(current))
        || any(isnan(representativeWorld)) || any(isinf(representativeWorld))
        || length(cameraPosition - previousCameraPosition) > 8.0) return current;

    // Projection identity: FOV, aspect or viewport changes break the mapping
    // (same per-column criterion as lib/taa_state.glsl).
    for (int i = 0; i < 4; ++i) {
        if (any(greaterThan(abs(gbufferProjection[i] - gbufferPreviousProjection[i]),
                            vec4(0.0001))))
            return current;
    }

    // A half-float seconds stamp can round into the future at high frame rates.
    // Use an exact frame index for continuity and the engine's frame duration
    // for wind motion. Every texel carries the same index/viewport fingerprint.
    ivec2 msize = textureSize(colortex25, 0);
    vec4 metaHere = texelFetch(colortex25, clamp(ivec2(uv * vec2(msize)), ivec2(0), msize - 1), 0);
    if (any(isnan(metaHere)) || any(isinf(metaHere))) return current;
    float dt = frameTime;
    if (metaHere.g != float((frameCounter - 1) % 2048)
        || isnan(dt) || isinf(dt) || dt < 0.0 || dt > 0.5
        || abs(metaHere.b - viewWidth) > 8.0) return current;

    // astra_modify_trace_pos shifts the noise lookup by -frameTimeCounter BEFORE
    // the 0.07 narrowness scale, so a fixed noise feature sits at z_world = c + t:
    // the field translates +1 world unit per second along +z. Rewind the current
    // hit to where this feature stood last frame, then project it with the REAL
    // previous camera (translation + rotation + projection) - never terrain depth
    // and never a rotation-only reuse.
    vec3 featurePrev = representativeWorld - vec3(0.0, 0.0, dt);
    vec4 prevClip = gbufferPreviousProjection
                  * (gbufferPreviousModelView * vec4(featurePrev - previousCameraPosition, 1.0));
    vec2 uvPrev = prevClip.xy / max(prevClip.w, 0.00001) * 0.5 + 0.5;
    // The cloud producer stores the jittered scene grid, unlike the TAA output.
    uvPrev += astra_jitter_uv_for(frameCounter - 1);
    vec2 margin = 1.5 / vec2(textureSize(colortex24, 0));
    if (prevClip.w <= 0.0
        || any(lessThan(uvPrev, margin)) || any(greaterThan(uvPrev, 1.0 - margin)))
        return current;   // off-screen entry: the current frame stands alone

    // The first visible hit can change at a cloud edge even when coverage and
    // colour happen to match. Compare each stored representative distance with
    // the reprojected feature before filtering; empty neighbours stay current.
    ivec2 historySize = textureSize(colortex24, 0);
    vec2 location = uvPrev * vec2(historySize) - 0.5;
    ivec2 base = ivec2(floor(location));
    vec2 fraction = fract(location);
    float expectedDistance = length(featurePrev - previousCameraPosition);
    float distanceTolerance = 16.0 + expectedDistance * 0.03;
    vec4 historySum = vec4(0.0);
    float coverage = 0.0;
    for (int y=0; y<2; y++) for (int x=0; x<2; x++) {
        ivec2 pixel = base + ivec2(x,y);
        if (any(lessThan(pixel,ivec2(0))) || any(greaterThanEqual(pixel,historySize))) continue;
        vec2 axis = mix(1.0-fraction,fraction,bvec2(x==1,y==1));
        float sampleWeight = axis.x * axis.y;
        if (sampleWeight <= 0.0) continue;
        vec4 meta = texelFetch(colortex25,pixel,0);
        if (any(isnan(meta)) || any(isinf(meta))
            || meta.a <= 0.0 || meta.r <= 0.0
            || meta.g != metaHere.g || meta.b != metaHere.b
            || abs(meta.r - expectedDistance) > distanceTolerance) continue;
        vec4 sampleCloud = texelFetch(colortex24,pixel,0);
        if (any(isnan(sampleCloud)) || any(isinf(sampleCloud)) || sampleCloud.a <= 0.0) continue;
        historySum += sampleCloud * sampleWeight;
        coverage += sampleWeight;
    }
    if (coverage <= 0.00001) return current;
    vec4 history = historySum / coverage;

    // Weather/palette drift and coverage jumps lower the history share instead of
    // being smeared. The change test runs on UN-premultiplied colour; the blend
    // itself stays in premultiplied space, so colour and alpha always share the
    // same effective samples (no dark fringes, no ghosting mismatch).
    vec3 curColor  = current.rgb  / max(current.a,  1e-4);
    vec3 histColor = history.rgb / max(history.a, 1e-4);
    float curY  = dot(curColor,  vec3(0.25, 0.5, 0.25));
    float histY = dot(histColor, vec3(0.25, 0.5, 0.25));
    float weight = ASTRA_CLOUD_TEMPORAL_WEIGHT * coverage;
    weight *= 1.0 - smoothstep(0.20, 0.80, abs(histY - curY) / max(max(histY, curY), 0.05));
    weight *= 1.0 - smoothstep(0.35, 0.90,
                abs(current.a - history.a) / max(max(current.a, history.a), 1e-4));

    return vec4(mix(current.rgb, history.rgb, weight),
                mix(current.a, history.a, weight));
}
#endif
#endif
