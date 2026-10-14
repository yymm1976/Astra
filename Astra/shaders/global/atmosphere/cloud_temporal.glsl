#ifndef ASTRA_CLOUD_TEMPORAL_GLSL
#define ASTRA_CLOUD_TEMPORAL_GLSL
// R6/T3 - independent temporal history for the SCREEN-VISIBLE planar cloud only.
// Handoff: docs/archive/实现与取证.md#record-081
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
#include "/lib/cloud_sample_grid.glsl"

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
#include "/lib/cloud_history_frame.glsl"
flat in int cloudFrameValid;

// History share of the exponential blend. Source-derived initial value; needs
// in-game A/B like every constant in this module.
#if CLOUD_QUALITY == 2
const float ASTRA_CLOUD_TEMPORAL_WEIGHT = 0.75;
#else
const float ASTRA_CLOUD_TEMPORAL_WEIGHT = 0.90;
#endif
// A thin cloud can miss the half-resolution ray in one phase of its subpixel
// footprint while the column is still there. That phase reuses the reprojected
// history at a higher share so the sun does not flick fully open for one frame.
const float ASTRA_CLOUD_TEMPORAL_EMPTY_WEIGHT = 0.95;
// Coverage-jump tolerance floor, in coverage units. The jump test must not be
// scale-free near zero: a change that is a small part of the sheet range is a
// large fraction of a wisp's own coverage, and that is exactly where the sun
// shows through, so the ratio is floored by a thin-cloud coverage instead.
const float ASTRA_CLOUD_TEMPORAL_COVERAGE_FLOOR = 0.15;

// current = vec4(premultiplied radiance, coverage) straight from this frame's
// march; representativeWorld = the integral's transmittance-weighted first moment
// (high -> opacity-weighted segments; low/medium -> first hit; zero when empty); ray is
// the producer's unit world direction for this texel, used to recover a
// representative for an empty column.
// Returns the blended premultiplied cloud for colortex24 and writes colortex25's
// metadata. Every rejected condition falls back to the CURRENT cloud result.
vec4 astra_cloud_temporal_resolve(vec4 current, vec3 representativeWorld, vec3 ray, bool sampledVisible,
                                  vec2 uv, out vec4 metaOut) {
    float stampNow = float(frameCounter % 2048);
    metaOut = vec4(0.0, stampNow, viewWidth, current.a);
    if (current.a > 0.0) metaOut.r = length(representativeWorld - cameraPosition);

    // Startup / world reload, and non-finite current values: no history at all.
    if (cloudFrameValid == 0 || (current.a <= 0.0 && !sampledVisible)
        || any(isnan(current)) || any(isinf(current))
        || any(isnan(representativeWorld)) || any(isinf(representativeWorld))) return current;

    // A half-float seconds stamp can round into the future at high frame rates.
    // Use an exact frame index for continuity and the engine's frame duration
    // for wind motion. Every texel carries the same index/viewport fingerprint.
    ivec2 msize = textureSize(colortex25, 0);
    ivec2 currentPixel = clamp(ivec2(uv * vec2(msize)), ivec2(0), msize - 1);
    vec4 metaHere = texelFetch(colortex25, currentPixel, 0);
    if (any(isnan(metaHere)) || any(isinf(metaHere))) return current;
    float dt = frameTime;
    if (metaHere.g != float((frameCounter - 1) % 2048)
        || abs(metaHere.b - viewWidth) > 8.0) return current;

    // An empty column is usually a real miss, but at a thin cloud edge one phase
    // of the subpixel footprint can miss while the column is still there, which
    // snaps the sun fully open for that frame. Recover this phase's representative
    // from the previous texel's stored distance along the same ray so the column
    // keeps its history. The metadata written below still carries coverage 0, so
    // a genuinely empty column only holds one frame and then clears. Slab
    // misses, opaque occlusion and camera/status gates never hold old coverage.
    bool emptyCurrent = current.a <= 0.0;
    #if CLOUD_QUALITY == 2
    // Four current-frame rays supply edge coverage. Do not leave a vanished
    // cloud behind solely to fill a missing phase of the old coarse grid.
    if (emptyCurrent) return current;
    #endif
    if (emptyCurrent) {
        if (metaHere.a <= 0.0 || metaHere.r <= 0.0
            || any(isnan(ray)) || any(isinf(ray))) return current;
        representativeWorld = cameraPosition + ray * metaHere.r;
        if (any(isnan(representativeWorld)) || any(isinf(representativeWorld))) return current;
    }

    // astra_modify_trace_pos shifts the noise lookup by -frameTimeCounter BEFORE
    // the 0.07 narrowness scale, so a fixed noise feature sits at z_world = c + t:
    // the field translates +1 world unit per second along +z. Rewind the current
    // hit to where this feature stood last frame, then project it with the REAL
    // previous camera (translation + rotation + projection) - never terrain depth
    // and never a rotation-only reuse.
    vec3 featurePrev = representativeWorld - vec3(0.0, 0.0, dt);
    vec4 prevClip = gbufferPreviousProjection
                  * (gbufferPreviousModelView * vec4(featurePrev - previousCameraPosition, 1.0));
    // Finite matrices can still overflow for an invalid representative distance.
    // Reject before converting a projected coordinate into integer texel indices.
    if (any(isnan(prevClip)) || any(isinf(prevClip))) return current;
    vec2 uvPrev = prevClip.xy / max(prevClip.w, 0.00001) * 0.5 + 0.5;
    // Invert both offsets: screen_view subtracts scene jitter, while the cloud
    // producer adds its own coverage jitter before reconstructing the ray.
    ivec2 historySize = textureSize(colortex24, 0);
    // One previous-frame pair, reused by the empty-edge motion test below. Both
    // are pure functions of (frameCounter, historySize) and neither call mutates
    // state, so the second evaluation was the same two values again.
    vec2 previousJitter = astra_jitter_uv_for(frameCounter - 1);
    vec2 previousGridOffset = astra_cloud_grid_offset(frameCounter - 1, historySize);
    uvPrev += previousJitter;
    uvPrev -= previousGridOffset;
    vec2 margin = 1.5 / vec2(historySize);
    if (prevClip.w <= 0.0
        || any(lessThan(uvPrev, margin)) || any(greaterThan(uvPrev, 1.0 - margin)))
        return current;   // off-screen entry: the current frame stands alone

    // The first visible hit can change at a cloud edge even when coverage and
    // colour happen to match. Compare each stored representative distance with
    // the reprojected feature before filtering; empty neighbours stay current.
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
        // A near-stationary reprojection often includes the identity texel read
        // above. Reuse only that exact texel; retain every footprint weight.
        vec4 meta = all(equal(pixel,currentPixel)) ? metaHere : texelFetch(colortex25,pixel,0);
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
    #if CLOUD_QUALITY == 2
    // Limit opacity lag without separating colour from coverage.
    vec3 historyColor = history.rgb / max(history.a, 1e-4);
    history.a = clamp(history.a, max(current.a-0.10,0.0), min(current.a+0.10,1.0));
    history.rgb = historyColor * history.a;
    #endif

    // Empty-phase protection is local to a slowly moving edge. Remove both
    // sampling jitters before measuring real motion, so fast camera rotation
    // does not retain a vanished cloud for an extra frame.
    float emptyMotionWeight = 1.0;
    if (emptyCurrent) {
        vec2 previousStable = uvPrev - previousJitter + previousGridOffset;
        vec2 currentStable = uv - astra_jitter_uv_for(frameCounter)
            + astra_cloud_grid_offset(frameCounter,historySize);
        float motionPixels = length((previousStable-currentStable)*vec2(viewWidth,viewHeight));
        emptyMotionWeight = 1.0-smoothstep(0.5,2.0,motionPixels);
    }

    // Weather/palette drift and coverage jumps lower the history share instead of
    // being smeared. The change test runs on UN-premultiplied colour; the blend
    // itself stays in premultiplied space, so colour and alpha always share the
    // same effective samples (no dark fringes, no ghosting mismatch). An empty
    // current has no colour or coverage to compare, so it just holds the history.
    vec3 curColor  = current.rgb  / max(current.a,  1e-4);
    vec3 histColor = history.rgb / max(history.a, 1e-4);
    float curY  = dot(curColor,  vec3(0.25, 0.5, 0.25));
    float histY = dot(histColor, vec3(0.25, 0.5, 0.25));
    float weight;
    if (emptyCurrent) {
        weight = ASTRA_CLOUD_TEMPORAL_EMPTY_WEIGHT * emptyMotionWeight * coverage;
    } else {
        weight = ASTRA_CLOUD_TEMPORAL_WEIGHT * coverage;
        weight *= 1.0 - smoothstep(0.20, 0.80, abs(histY - curY) / max(max(histY, curY), 0.05));
        weight *= 1.0 - smoothstep(0.35, 0.90,
                    abs(current.a - history.a)
                    / max(max(current.a, history.a), ASTRA_CLOUD_TEMPORAL_COVERAGE_FLOOR));
    }

    return vec4(mix(current.rgb, history.rgb, weight),
                mix(current.a, history.a, weight));
}
#endif
#endif
