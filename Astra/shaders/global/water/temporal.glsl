#ifndef ASTRA_GLOBAL_WATER_TEMPORAL_GLSL
#define ASTRA_GLOBAL_WATER_TEMPORAL_GLSL
// Astra v1 - global/water/temporal.glsl
// RETIRED: no active include or ASTRA_WATER_TEMPORAL definition. Its historical
// colortex28/29 slots now belong to Nether reflection metadata / underwater shafts.
// Reusing this module requires new attachments and new producer/consumer wiring.
// Written for Astra; no reference shader code was incorporated. The buffer-flip
// read-previous-frame pattern follows the pack's own taa_resolve.fsh <-> colortex15
// and cloud_screen.fsh <-> colortex24/25 precedents.
//
// R5/T3 - temporal history for ONE water sub-signal: the SSR HIT RADIANCE of the
// above-water water surface. Handoff: docs/handoffs/2026-09-27-R5-water-temporal.md
//
// Scope. The final surface colour, the analytic sky-reflection fallback, the
// refraction background and the underwater (solas_underwater_interface) interface
// have NO history of their own yet; they keep the current frame verbatim. This
// module must not be read as "water is temporally resolved".
//
// What is accumulated. program/water.glsl astra_water() marches a reflection ray
// (water_raytrace) and transports the OPAQUE snapshot (colortex4 + depthtex1) at
// the hit through water_sample_path. That transported hit radiance is noisy
// (growing strides, footprint taps, edge rejections) while the reflected field is
// piecewise smooth, so it is the one water signal where accumulation pays. The
// hit position, its correspondence and a validity ride along so old contributions
// are REJECTED, not just faded.
//
// What is deliberately NOT used as motion. The wave field is a normal-only
// perturbation (global/water/surface.glsl rewrites surface.normal and never the
// geometry), so a water surface point is geometrically static and its camera
// reprojection is exact. Wave phase speed and normal change are never converted
// into a vertex velocity anywhere below; wave motion between two frames is
// measured by where the consecutive rays actually land (the hit tolerance), and
// when that slide cannot be bounded the chain falls back to the current frame.
//
// INACTIVE: the geometry-stage self-read/write used here has no composite
// ping-pong boundary. program/lit.fsh no longer includes or enables this module.
// A future resolve needs a separate post-geometry producer and history targets;
// it must never attach the 1x1 inactive TAA buffer to a full-size water draw.
//
// The chain is independent of ASTRA_TAA: with TAA off the pack does not declare
// the previous-frame matrices (lib/uniforms.glsl), so this module declares them
// itself and keeps maintaining its own state.
#ifdef ASTRA_WATER_TEMPORAL

// ---- buffer registration ----
// Formats and clear state are declared by the including pass (program/lit.fsh,
// ASTRA_WATER_PASS block): Iris's preprocessor evaluates #ifndef on non-option
// tokens as always-true, so a second guarded RGBA16F definition here would
// collide with the pass's own (R6 compile finding).
// colortex28: rgb = blended SSR hit radiance (HDR, pre-Fresnel, pre-shoulder),
//             a   = blended validity in [0,1]; 0 marks "no valid hit history".
// colortex29: rgb = stored hit point MINUS the producing surface point, in
//                   player-relative world axes (a frame-independent difference
//                   anchored to the static surface point; magnitude is bounded by
//                   water_raytrace's 64-128 block range, so half floats hold it),
//             a   = time stamp fract(frameTimeCounter/64)*64. This is the REAL
//                   previous-frame time value: the wrap-corrected delta gates the
//                   chain below, and any future sub-chain that must re-evaluate
//                   the wave field at the previous frame takes
//                   prevTime = frameTimeCounter - dt from it (the wave evaluation
//                   is a pure function of world position and time, so the
//                   previous frame's waveform is exactly reproducible).
uniform sampler2D colortex28;
uniform sampler2D colortex29;

#ifndef ASTRA_TAA
uniform mat4  gbufferPreviousModelView;
uniform mat4  gbufferPreviousProjection;
uniform vec3  previousCameraPosition;
#endif

// History share of the exponential blend before validity and change clamps.
// Source-derived initial value; needs in-game A/B like every constant here.
const float ASTRA_WATER_TEMPORAL_WEIGHT = 0.85;

// lib/taa_jitter.glsl is hardwired to the CURRENT frameCounter. The history was
// written at the previous frame's own raster position - the unjittered
// reprojection PLUS the previous frame's jitter - so the Halton table (mean
// correction included) is replicated here for frameCounter - 1. With TAA off
// astra_jitter_uv() is zero and this vanishes.
vec2 astra_water_previous_jitter_uv() {
    #ifdef ASTRA_TAA
    const vec2 offsets[8] = vec2[8](
        vec2(0.0, -1.0/6.0), vec2(-0.25, 1.0/6.0),
        vec2(0.25, -7.0/18.0), vec2(-0.375, -1.0/18.0),
        vec2(0.125, 5.0/18.0), vec2(-0.125, -5.0/18.0),
        vec2(0.375, 1.0/18.0), vec2(-0.4375, 7.0/18.0));
    return (offsets[(frameCounter + 7) % 8] + vec2(0.0546875, 0.0))
         / max(vec2(viewWidth, viewHeight), vec2(1.0));
    #else
    return vec2(0.0);
    #endif
}

// hasHit            - this frame's march found a hit (hit.a > 0).
// currentRadiance   - this frame's transported hit radiance (0 without a hit).
// currentConfidence - hit.a * path validity for this frame (0 without a hit).
// hitViewPos        - screen_view(hit.xyz) of this frame's march (0 without).
// surfaceWorld      - this fragment's water surface point, world axes
//                     (playerPos + cameraPosition). Static geometry anchor.
// Returns vec4(blended radiance, blended validity) for colortex28 and writes the
// metadata for colortex29 through metaOut. EVERY rejected condition falls back to
// the current frame: with a hit the current radiance re-seeds the slot alone,
// without one the slot is invalidated (validity 0), so a stale contribution can
// never survive into a later frame through a rejected transition.
vec4 astra_water_ssr_temporal(bool hasHit, vec3 currentRadiance, float currentConfidence,
                              vec3 hitViewPos, vec3 surfaceWorld, out vec4 metaOut) {
    float stampNow = fract(frameTimeCounter / 64.0) * 64.0;
    vec3 surfacePlayer = surfaceWorld - cameraPosition;
    vec3 hitOffset = vec3(0.0);
    if (hasHit) hitOffset = view_player(hitViewPos) - surfacePlayer;
    metaOut = vec4(hitOffset, stampNow);

    // SSR lost its hit: nothing to validate a correspondence against, so the
    // slot is invalidated instead of consumed (the analytic sky fallback owns
    // this frame's reflection entirely, as before this module existed).
    if (!hasHit || frameCounter <= 1) return vec4(0.0, 0.0, 0.0, 0.0);

    // Projection identity: FOV, aspect or near/far changes break every mapping
    // (same per-column criterion as lib/taa_state.glsl / cloud_temporal.glsl).
    for (int i = 0; i < 4; ++i) {
        if (any(greaterThan(abs(gbufferProjection[i] - gbufferPreviousProjection[i]),
                            vec4(0.0001))))
            return vec4(currentRadiance, currentConfidence);
    }

    // Fetch the previous frame's slot for THIS surface point. The buffer grid is
    // each frame's own jittered raster grid, so the fetch position is the
    // unjittered previous-frame reprojection of the static surface point plus
    // the PREVIOUS frame's jitter offset.
    vec4 prevClip = gbufferPreviousProjection
                  * (gbufferPreviousModelView * vec4(surfaceWorld - previousCameraPosition, 1.0));
    vec2 prevUV = prevClip.xy / max(prevClip.w, 0.00001) * 0.5 + 0.5
                + astra_water_previous_jitter_uv();
    vec2 margin = 1.5 / vec2(textureSize(colortex28, 0));
    if (prevClip.w <= 0.0
        || any(lessThan(prevUV, margin)) || any(greaterThan(prevUV, 1.0 - margin)))
        return vec4(currentRadiance, currentConfidence);   // surface left/entered the screen

    ivec2 metaSize = textureSize(colortex29, 0);
    vec4 meta = texelFetch(colortex29, clamp(ivec2(prevUV * vec2(metaSize)),
                                             ivec2(0), metaSize - 1), 0);
    vec4 history = textureLod(colortex28, prevUV, 0.0);
    float storedValidity = history.a;
    if (storedValidity <= 0.0 || any(isnan(history)) || any(isinf(history))
        || any(isnan(meta)) || any(isinf(meta)))
        return vec4(currentRadiance, currentConfidence);   // nothing valid accumulated there

    // State stamp: the wrap-corrected delta must look like a real frame step.
    // The 0.07 slack covers RGBA16F quantisation of the stamp (ulp <= 0.03125
    // in [32,64)); anything beyond it is /time set, a pause, a dimension round
    // trip longer than the window, or a (re)cleared buffer.
    float dt = stampNow - meta.a;
    if (dt < -32.0) dt += 64.0; else if (dt > 32.0) dt -= 64.0;
    if (dt < -0.07 || dt > 0.5) return vec4(currentRadiance, currentConfidence);

    // Hit correspondence, in two parts, one tolerance. The stored hit was a
    // WORLD point; expected is it re-expressed on this frame's camera-relative
    // axes. tolerance gives the wave-driven slide of consecutive landing points
    // room (the wave normal is the only thing that moves) while still rejecting
    // object changes; the 0.25 floor sits above the march's own precision
    // (24 growing strides + 6 subdivisions leave <= 1/8 block).
    vec3 expected = surfacePlayer + meta.rgb;
    float tolerance = 0.25 + 0.05 * length(meta.rgb);
    // 1) the CURRENT ray's landing point must sit where the stored one did:
    //    a reflected object crossing the ray forces current-frame-only instead
    //    of smearing it into the history (and out again when it leaves).
    if (distance(view_player(hitViewPos), expected) > tolerance)
        return vec4(currentRadiance, currentConfidence);
    // 2) the STORED hit must still be the scene at its own position: project it
    //    into this frame WITH the current jitter (depthtex1 rasterises jittered)
    //    and require the same opaque geometry to still be there.
    //    off-screen -> the reflected object left the screen; sky -> it is gone;
    //    a reconstructed world point farther than tolerance -> it changed.
    vec4 hitClip = astra_jitter_clip(gbufferProjection * vec4(player_view(expected), 1.0));
    if (hitClip.w <= 0.00001) return vec4(currentRadiance, currentConfidence);
    vec3 hitNdc = hitClip.xyz / hitClip.w;
    if (any(greaterThan(abs(hitNdc), vec3(1.0))))
        return vec4(currentRadiance, currentConfidence);
    vec2 hitUV = hitNdc.xy * 0.5 + 0.5;
    vec2 hitSize = vec2(textureSize(depthtex1, 0));
    float hitDepth = texelFetch(depthtex1, clamp(ivec2(hitUV * hitSize), ivec2(0),
                                                 ivec2(hitSize) - 1), 0).r;
    if (hitDepth >= 0.999999) return vec4(currentRadiance, currentConfidence);
    if (distance(view_player(screen_view(vec3(hitUV, hitDepth))), expected) > tolerance)
        return vec4(currentRadiance, currentConfidence);

    // Brightness drift (time of day, weather palette, a hit sliding across a
    // bright edge) lowers the history share instead of being smeared - same
    // shape as cloud_temporal.glsl.
    float curY  = dot(max(currentRadiance, vec3(0.0)), vec3(0.25, 0.5, 0.25));
    float histY = dot(max(history.rgb, vec3(0.0)), vec3(0.25, 0.5, 0.25));
    float weight = ASTRA_WATER_TEMPORAL_WEIGHT * storedValidity
                 * (1.0 - smoothstep(0.20, 0.80, abs(histY - curY) / max(max(histY, curY), 0.05)));
    return vec4(mix(currentRadiance, history.rgb, weight),
                mix(currentConfidence, storedValidity, weight));
}
#endif
#endif
