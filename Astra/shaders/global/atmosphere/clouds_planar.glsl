#ifndef ASTRA_GLOBAL_ATMOSPHERE_CLOUDS_PLANAR_GLSL
#define ASTRA_GLOBAL_ATMOSPHERE_CLOUDS_PLANAR_GLSL
#include "/lib/twilight.glsl"

// ============================================================
//  Astra v1 - planar cloud sheet, shaped and shaded with the
//  Complementary r5.9 (Reimagined) cloud model.
//  Reference root: _analysis/Complementary r5.9/Reimagined/shaders/
//    lib/atmospherics/clouds/cloudCoord.glsl:4-28
//        cloudNarrowness, GetRoundedCloudCoord, ModifyTracePos
//    lib/atmospherics/clouds/reimaginedClouds.glsl:3-5, 17-19, 30-146
//        cloudStretch / cloudTallness / cloudRoundness, the vertical noise
//        threshold, the altitude shading and the two-tap light march
//    lib/atmospherics/clouds/mainClouds.glsl:9-16, 82, 91
//        InterleavedGradientNoiseForClouds, thresholdF, Reimagined ambient trim
//    lib/colors/cloudColors.glsl:1-14
//        cloudRainColor / cloudAmbientColor / cloudLightColor
//    lib/colors/lightAndAmbientColors.glsl:6-79
//        lightColor / ambientColor (the inputs cloudColors.glsl needs)
//
//  WHAT CHANGED SHAPE-WISE: the old Astra sheet sampled one flat plane and
//  thresholded a 3-octave noise sum, so every cloud had the same thickness and
//  no lit tops / dark bottoms. The reference marches the ray between
//  cloudAltitude +/- cloudStretch, tests `noise > threshold * 0.5 + 0.25`
//  with a vertical falloff, and shades by the height of the first hit
//  (cloudShading), which is what produces rounded tops and dark undersides.
//
//  ASTRA ADAPTATIONS (the reference parts that cannot be copied as-is):
//   - Noise source: dedicated complementaryCloudNoise binds the original
//     cloud-water.png; geometry and deferred stages share the same source.
//   - Low/balanced: bounded coarse search plus two screen-edge refinements;
//     the coarser reflection environment uses one. High retains its dense search.
//   - CLOUD_COVERAGE: Astra's own option; the reference has no equivalent. It
//     is applied as an additive bias on the reference's `threshold * 0.5 +
//     0.25` test, zero at the default 50 so the default look is the reference's.
//   - Light march shadowing (`GetShadowOnCloud`) needs the shadow map, which is
//     the integration task's boundary; lightMult stays 1.0.
//   - `skyFade` (above-void / above-cloud fade) has no Astra equivalent, so it
//     is 1.0; every term it feeds collapses to the reference's skyFadeM = 1.0.
//
//  NOT PORTED (needs a public boundary change - see docs/archive/实现与取证.md#record-088):
//   - the mainClouds.glsl:56-78 camera-position precision wrap
//   - AURORA_STYLE / NIGHT_NEBULAE additive terms
//
//  LEFT THIS LIST (2026-09-21): ground shadows from lib/lighting/cloudShadows.glsl are
//   wired in clear weather behind CLOUD_SHADOWS, and the consumer is program/scene.glsl -
//   this file only supplies the density field that astra_cloud_transmission() traces.
//   The reference's gaux4 read-back has no Astra equivalent and nothing was copied.
// ============================================================

#include "/global/atmosphere/sky_gradient.glsl"
uniform sampler2D complementaryCloudNoise;

// lib/atmospherics/clouds/cloudCoord.glsl:4
const float ASTRA_CLOUD_NARROWNESS = 0.07;
// ASTRA ADAPTATION: reference reimaginedClouds.glsl:3-5 uses 4.2 / 0.125.
// Retain the existing Astra 9.0 / 0.48 shape; this is not an exact reference match.
const float ASTRA_CLOUD_STRETCH   = 9.0;
const float ASTRA_CLOUD_TALLNESS  = ASTRA_CLOUD_STRETCH * 2.0;
const float ASTRA_CLOUD_ROUNDNESS = 0.48;
// lib/atmospherics/clouds/mainClouds.glsl:82 (CLOUDS_REIMAGINED branch)
const float ASTRA_CLOUD_THRESHOLD_F = 4000.0;
// Artistic opacity per block at unit density; shared by screen and reflections.
const float ASTRA_CLOUD_DENSITY_EXTINCTION = 0.12;
// lib/common.glsl:838 - CLOUD_ALT1 default 192
const float ASTRA_CLOUD_ALTITUDE = 192.0;
// Cloud quality is independent of the surface/water budget. High integrates
// occupied ray segments in both screen and reflection queries; low/medium
// keep their first-hit approximation.

// lib/atmospherics/clouds/cloudCoord.glsl:7-15 - "Thanks to SixthSurge"
vec2 astra_rounded_cloud_coord(vec2 pos, float cloudRoundness) {
	vec2 coord = pos.yx + 0.5;
	vec2 signCoord = sign(coord);
	coord = abs(coord) + 1.0;
	vec2 i, f = modf(coord, i);
	f = smoothstep(0.5 - cloudRoundness, 0.5 + cloudRoundness, f);
	coord = i + f;
	return (coord - 0.5) * signCoord / 256.0;
}

// lib/atmospherics/clouds/cloudCoord.glsl:17-28
// CLOUD_SPEED_MULT == 100 in the reference, so `wind = syncedTime` (seconds).
vec3 astra_modify_trace_pos(vec3 tracePos, float cloudAltitude) {
	float wind = frameTimeCounter;   // ASTRA MAP: syncedTime
	tracePos.z -= wind;
	tracePos.x += cloudAltitude * 64.0;
	tracePos.xz *= ASTRA_CLOUD_NARROWNESS;
	return tracePos.xyz;
}

// lib/atmospherics/clouds/reimaginedClouds.glsl:22-28 (Astra noise source, see header)
float astra_2d_cloud_sample(vec2 pos) {
	// Density is sampled inside divergent cloud marches and sky visibility
	// branches. Its base-level lookup must not depend on implicit derivatives.
	return textureLod(complementaryCloudNoise, astra_rounded_cloud_coord(pos, ASTRA_CLOUD_ROUNDNESS), 0.0).b;
}

// lib/atmospherics/clouds/reimaginedClouds.glsl:7-20, without the colortex3 branch
// ---------------------------------------------------------------------------
// F1 (2026-09-21) single source of truth for the sheet density contract.
// Before this, four readers each carried their own copy of the numbers: the march
// existence test (:225), its column-density ramp (:316), the shadow arm (weather.glsl)
// and the reflection board (overworld.glsl). Worse, the existence test judged the SUM of
// both octaves, so the rotated detail octave could create cloud by itself: measured at
// 30.66% of all cloud pixels at the default coverage, with a dominant pattern axis 33
// degrees away from the body (qa/tools/cloud_ghost_probe.py). That is the off-axis,
// washed-out second layer users reported. Existence is now decided by the COARSE octave
// alone; the detail octave only changes how dense an existing cloud is.
float astra_cloud_coverage_bias() {
    return mix(0.20, -0.20, CLOUD_COVERAGE * 0.01) - 0.04 - 0.28 * astraRainFactor;
}
float astra_cloud_existence_gate(float layerThreshold, float coverageBias) {
    return 0.25 + layerThreshold * 0.5 + coverageBias;
}
float astra_cloud_existence_gate(float layerThreshold) {
    return astra_cloud_existence_gate(layerThreshold, astra_cloud_coverage_bias());
}
float astra_cloud_saturation(float coverageBias) {
    return 0.43 + coverageBias;
}
float astra_cloud_saturation() {
    return astra_cloud_saturation(astra_cloud_coverage_bias());
}
float astra_cloud_coarse(vec3 tracePos, float cloudAltitude) {
    vec3 tracePosM = astra_modify_trace_pos(tracePos, cloudAltitude);
    return 0.78 * astra_2d_cloud_sample(tracePosM.xz);
}

// Reference formula for the historical Python cloud probes; they do not read
// or call this GLSL function. The active cloud march evaluates the octaves inline.
float astra_cloud_noise(vec3 tracePos, float cloudAltitude) {
	vec3 tracePosM = astra_modify_trace_pos(tracePos, cloudAltitude);
    // Broad density plus a smaller, rotated octave: soften Reimagined's
    // square cells using Unbound's multi-scale density idea, without its
    // nested 3D-noise march. The existing pack-owned noise stays in use.
    vec2 detail=mat2(0.8,-0.6,0.6,0.8)*tracePosM.xz*2.7+vec2(31.7,9.3);
	return 0.78*astra_2d_cloud_sample(tracePosM.xz)+0.22*astra_2d_cloud_sample(detail);
}

// lib/atmospherics/clouds/mainClouds.glsl:9-16, non-TAA branch
float astra_cloud_ign() {
	#ifdef ASTRA_SKY_CACHE_WRITE
        // Stable midpoint for the low-resolution environment and its seam gutters.
        return 0.5;
	#else
    // Stable per-pixel phase, shared by every query of one frame: the coarse
    // lattice, the lighting offset and the sky dither. The old screen-cloud
    // branch rotated this phase by `frameCounter * 0.618` every frame, which
    // slid the first hit up to one coarse step along the ray each frame; a
    // screen-space reprojection can undo a subpixel ray shift but not an
    // along-ray shift, so a thin cloud in front of the sun flickered instead of
    // being averaged. Subpixel coverage AA still comes from the
    // reprojection-aligned screen grid offset (astra_cloud_grid_offset), so the
    // lattice phase itself can stay fixed without locking coverage into sheets.
    return fract(52.9829189 * fract(0.06711056 * gl_FragCoord.x + 0.00583715 * gl_FragCoord.y));
	#endif
}

// lib/colors/lightAndAmbientColors.glsl:6-79 + lib/colors/cloudColors.glsl:1-14
// Resolved at the reference defaults: SPECIAL_BIOME_WEATHER off, RAIN_STYLE = 1,
// SUN_MOON_DURING_RAIN on (so rainShadowVisReduce = 0.0, lines 56-66), and the
// DEFERRED1 branch of nightClearLightColor (line 76), which is the cloud pass.
void astra_cloud_colors(AstraSkyFactors f, AstraSkyPalette p,
                        out vec3 cloudAmbientColor, out vec3 cloudLightColor) {
    // The cited reference's night/day/rain/brightness mixes are view-independent.
    // shaders.properties evaluates them once per frame, in the same order.
    cloudAmbientColor = astraCloudAmbientPalette;
    cloudLightColor = astraCloudLightPalette;
    // Warm illuminated edges over a cooler cloud body during the same twilight
    // envelope used by the sky and terrain (Solas separates these two colours).
    float twilight=astra_twilight_strength();
    cloudLightColor=mix(cloudLightColor,astra_twilight_sunlight()*0.70,twilight);
    cloudAmbientColor=mix(cloudAmbientColor,vec3(0.20,0.16,0.19)
                         *mix(0.35,1.0,f.sunVisibility),twilight);
    cloudLightColor *= mix(ASTRA_TINT_MOON,
                          astra_sun_color_gain(twilight, astraDawnBlend), f.sunVisibility);
    cloudAmbientColor *= ASTRA_TINT_AMBIENT * ASTRA_STYLE_AMBIENT
                       * ASTRA_OVERWORLD_AMBIENT_GAIN;
}

// Inputs shared by the rays traced from one fragment. High-quality screen cloud
// traces four subpixel rays; these values are identical for all four, so prepare
// them once instead of rebuilding them inside every ray march.
struct AstraCloudFrame {
    float coverageBias;
    float saturationBase;
    float dither;
    bool colorsReady;
    vec3 cloudAmbientColor;
    vec3 cloudLightColor;
    float twilight;
};

AstraCloudFrame astra_cloud_frame() {
    AstraCloudFrame ctx;
    ctx.coverageBias = astra_cloud_coverage_bias();
    ctx.saturationBase = astra_cloud_saturation(ctx.coverageBias);
    ctx.dither = 0.0;
    ctx.colorsReady = false;
    ctx.cloudAmbientColor = vec3(0.0);
    ctx.cloudLightColor = vec3(0.0);
    ctx.twilight = 0.0;
    return ctx;
}

void astra_cloud_frame_colors(inout AstraCloudFrame ctx, AstraSkyFactors f, AstraSkyPalette p) {
    if (ctx.colorsReady) return;
    ctx.dither = astra_cloud_ign();
    astra_cloud_colors(f, p, ctx.cloudAmbientColor, ctx.cloudLightColor);
    ctx.twilight = astra_twilight_strength();
    ctx.colorsReady = true;
}

// ------------------------------------------------------------
// Shared slab/cylinder interval for marching and the screen-cloud resolve.
// The input is a unit world direction; an empty interval is returned for a miss.
vec2 astra_cloud_interval(vec3 nPlayerPos) {
	// lib/atmospherics/clouds/reimaginedClouds.glsl:33-41
	float higherPlaneAltitude = ASTRA_CLOUD_ALTITUDE + ASTRA_CLOUD_STRETCH;
	float lowerPlaneAltitude  = ASTRA_CLOUD_ALTITUDE - ASTRA_CLOUD_STRETCH;

	// ASTRA: guard the plane solve first; a horizontal ray makes both distances blow up.
	float minPlaneDistance;
	float maxPlaneDistance;
	if (abs(nPlayerPos.y) < 1e-5) {
		if (cameraPosition.y < lowerPlaneAltitude || cameraPosition.y > higherPlaneAltitude)
			return vec2(0.0);
		// A horizontal ray inside the slab exits at the horizontal distance limit.
		minPlaneDistance = 0.0;
		maxPlaneDistance = ASTRA_CLOUD_THRESHOLD_F;
	} else {
		float inverseVerticalRay = 1.0 / nPlayerPos.y;
		float lowerPlaneDistance = (lowerPlaneAltitude - cameraPosition.y) * inverseVerticalRay;
		float higherPlaneDistance = (higherPlaneAltitude - cameraPosition.y) * inverseVerticalRay;
		minPlaneDistance = max(min(lowerPlaneDistance, higherPlaneDistance), 0.0);
		maxPlaneDistance = max(lowerPlaneDistance, higherPlaneDistance);
	}
	if (maxPlaneDistance < 0.0) return vec2(0.0);
    float horizontalRay = length(nPlayerPos.xz);
    if (minPlaneDistance * horizontalRay > ASTRA_CLOUD_THRESHOLD_F)
        return vec2(0.0);
    // Clip the slab against the horizontal visibility cylinder before marching.
    // Previously horizontal rays distributed 64 samples over mostly invisible space.
    if (horizontalRay > 1e-5)
        maxPlaneDistance = min(maxPlaneDistance,ASTRA_CLOUD_THRESHOLD_F/horizontalRay);
    return vec2(minPlaneDistance, maxPlaneDistance);
}

// Cloud colors come from the reference sky palette.
// R6/T3: the three-argument form additionally reports the transmittance-weighted
// first moment of the column integral. High uses opacity-weighted occupied
// segments, while low/medium use the first visible hit. Empty columns keep
// vec3(0.0), with no valid representative.
// The return value is unchanged - the two shorter overloads below discard it.
//
// Core entry: the caller already owns a UNIT world direction and its
// astra_cloud_interval slab. Passing them in avoids a second normalize() and a
// second plane solve on the callers that measured both (the screen-cloud
// producer and the clipped-endpoint march). They must be the SAME ray - the
// interval has to be the slab of nPlayerPos - and nPlayerPos has to be unit:
// both the plane solve and VdotU assume it. The 4-argument wrapper below keeps
// the public contract by normalizing once and solving the interval itself.
vec4 astra_planar_cloud(vec3 nPlayerPos, float maxRayDistance, out vec3 representativeWorld,
                       float angularFootprint, vec2 interval, inout AstraCloudFrame ctx) {
    representativeWorld = vec3(0.0);
    float higherPlaneAltitude = ASTRA_CLOUD_ALTITUDE + ASTRA_CLOUD_STRETCH;
    float lowerPlaneAltitude = ASTRA_CLOUD_ALTITUDE - ASTRA_CLOUD_STRETCH;
    float minPlaneDistance = interval.x;
    float maxPlaneDistance = interval.y;
    float planeDistanceDif = maxPlaneDistance-minPlaneDistance;
    if (planeDistanceDif <= 0.0) return vec4(0.0);
    if (minPlaneDistance >= maxRayDistance) return vec4(0.0);
    float VdotU = nPlayerPos.y;
    // Fixed midpoint: pixel noise must not move the cloud's first occupied
    // interval or lighting depth as the camera turns. High coverage comes from
    // segment integration and spatial subpixel samples, not a random hit depth.
    const float marchOffset = 0.5;
    const float skyFadeM = 1.0;
    #if defined ASTRA_SKY_CACHE_WRITE && CLOUD_QUALITY < 2
    // The reflection environment is already a coarse sphere. Preserve the same
    // moving density/lighting field, but spend fewer queries locating its first
    // cloud hit. Screen clouds and terrain endpoints keep their own budgets.
    #if CLOUD_QUALITY == 0
    int sampleCount = clamp(int(ceil(planeDistanceDif/64.0)),4,6);
    #else
    int sampleCount = clamp(int(ceil(planeDistanceDif/48.0)),4,8);
    #endif
    #elif CLOUD_QUALITY == 0
    int sampleCount = clamp(int(ceil(planeDistanceDif/48.0)),4,12);
    #elif CLOUD_QUALITY == 2
    int sampleCount = clamp(int(ceil(planeDistanceDif/4.0)),4,512);
    #else
    int sampleCount = clamp(int(ceil(planeDistanceDif/32.0)),6,16);
    #endif
    #if CLOUD_QUALITY == 2
    // Fixed spacing avoids moving every interior node when ceil(count) changes.
    // At the hard far-field cap spacing varies continuously with the interval.
    float stepMult = max(4.0,planeDistanceDif/512.0);
    #else
    float stepMult = planeDistanceDif/float(sampleCount);
    #endif
    vec3 tracePos;
    float coverageBias = ctx.coverageBias;
    float saturationBase = ctx.saturationBase;

	vec4 volumetricClouds = vec4(0.0);
    #if CLOUD_QUALITY == 2
    vec3 firstCloudColor = vec3(0.0);
    bool cloudColorReady = false;
    // Cache the shared endpoint between adjacent segments. One initial lookup
    // plus one per segment replaces unrelated midpoint columns, without a
    // second density query at every boundary or a per-segment eighth root.
    vec3 initialPosition = cameraPosition+minPlaneDistance*nPlayerPos;
    float previousCoarse = astra_cloud_coarse(initialPosition,ASTRA_CLOUD_ALTITUDE);
    float previousGate = astra_cloud_existence_gate(pow8(clamp(
        abs(initialPosition.y-ASTRA_CLOUD_ALTITUDE)/ASTRA_CLOUD_STRETCH,0.0,1.0)),coverageBias);
    float horizontalRayLength = length(nPlayerPos.xz);
    #endif

	for (int i = 0; i < sampleCount; i++) {
		// Terrain is an opaque endpoint, not merely an entry-plane gate. Keep
		// the sky's sample spacing so a nearer endpoint cannot move an existing
		// visible cloud hit; omit only samples at/behind the terrain surface.
        #if CLOUD_QUALITY == 2
        float segmentStart = minPlaneDistance + float(i) * stepMult;
        float segmentLength = min(stepMult, min(maxRayDistance,maxPlaneDistance)-segmentStart);
        if (segmentLength <= 0.0) break;
        vec3 segmentEndPosition = cameraPosition+(segmentStart+segmentLength)*nPlayerPos;
        float endCoarse = astra_cloud_coarse(segmentEndPosition,ASTRA_CLOUD_ALTITUDE);
        float endGate = astra_cloud_existence_gate(pow8(clamp(
            abs(segmentEndPosition.y-ASTRA_CLOUD_ALTITUDE)/ASTRA_CLOUD_STRETCH,0.0,1.0)),coverageBias);
        float startCoarse = previousCoarse;
        float startSigned = startCoarse-previousGate;
        float endSigned = endCoarse-endGate;
        previousCoarse = endCoarse;
        previousGate = endGate;
        if (max(startSigned,endSigned) <= 0.0) continue;
        // Linear boundary interpolation includes the horizontal density change.
        // Freezing one midpoint's whole vertical column leaves stacked slices
        // at cloud sides even when its top/bottom bounds are clipped exactly.
        float occupiedStart = startSigned < 0.0 ? -startSigned/(endSigned-startSigned) : 0.0;
        float occupiedEnd = endSigned < 0.0 ? startSigned/(startSigned-endSigned) : 1.0;
        float occupiedMiddle = 0.5*(occupiedStart+occupiedEnd);
        float lightingDistance = segmentStart+occupiedStart*segmentLength;
        float sampleDistance = segmentStart+occupiedMiddle*segmentLength;
        segmentLength *= occupiedEnd-occupiedStart;
        tracePos = cameraPosition+sampleDistance*nPlayerPos;
        vec3 tracePosM = astra_modify_trace_pos(tracePos,ASTRA_CLOUD_ALTITUDE);
        float coarse = mix(startCoarse,endCoarse,occupiedMiddle);
        float coarseSample = coarse/0.78;
        float existenceGate = astra_cloud_existence_gate(pow8(clamp(
            abs(tracePos.y-ASTRA_CLOUD_ALTITUDE)/ASTRA_CLOUD_STRETCH,0.0,1.0)),coverageBias);
        #else
        float sampleDistance = minPlaneDistance + (float(i) + marchOffset) * stepMult;
		if (sampleDistance >= maxRayDistance) break;
        tracePos = cameraPosition+sampleDistance*nPlayerPos;

		vec2 horizontalOffset=tracePos.xz-cameraPosition.xz;
        float horizontalDistance2=dot(horizontalOffset,horizontalOffset);
		if (horizontalDistance2 > ASTRA_CLOUD_THRESHOLD_F*ASTRA_CLOUD_THRESHOLD_F) break;

		// lib/atmospherics/clouds/reimaginedClouds.glsl:17-19
		float threshold = clamp(abs(ASTRA_CLOUD_ALTITUDE - tracePos.y) / ASTRA_CLOUD_STRETCH, 0.001, 0.999);
		      threshold = pow2(pow2(pow2(threshold)));
		// F1: existence is the COARSE octave only. noise (both octaves) is still the
		// column-density input below, so the detail octave keeps softening the edge
		// without ever creating cloud on its own. The gate is the shared one.
		vec3 tracePosM = astra_modify_trace_pos(tracePos, ASTRA_CLOUD_ALTITUDE);
		float coarseSample = astra_2d_cloud_sample(tracePosM.xz);
		float coarse = 0.78*coarseSample;
		float existenceGate = astra_cloud_existence_gate(threshold, coverageBias);
		if (coarse <= existenceGate) continue;
        #endif
        // Coverage belongs to the occupied coarse column. Moving the shading
        // point onto its boundary must not erase that column's opacity.
        float densityCoarse = coarse;
        float densityGate = existenceGate;
        #if CLOUD_QUALITY < 2
        // Refine only an occupied coarse interval. Preserve the broad cell
        // field and its first visible side, spending work on the boundary
        // rather than on every empty sample. Very narrow distant wisps may
        // disappear; the main volume and colour model remain shared.
        float lowDistance = max(minPlaneDistance,sampleDistance-stepMult);
        float highDistance = sampleDistance;
        #ifdef ASTRA_SKY_CACHE_WRITE
        const int refineCount = 1;
        #else
        const int refineCount = 2;
        #endif
        for (int refine=0; refine<refineCount; ++refine) {
            float middle = 0.5*(lowDistance+highDistance);
            vec3 candidate = cameraPosition+middle*nPlayerPos;
            float layer = clamp(abs(ASTRA_CLOUD_ALTITUDE-candidate.y)/ASTRA_CLOUD_STRETCH,0.001,0.999);
            float candidateGate = astra_cloud_existence_gate(pow8(layer), coverageBias);
            vec3 candidateM = astra_modify_trace_pos(candidate,ASTRA_CLOUD_ALTITUDE);
            float candidateSample = astra_2d_cloud_sample(candidateM.xz);
            float candidateCoarse = 0.78*candidateSample;
            if (candidateCoarse > candidateGate) {
                highDistance = middle;
                tracePos = candidate;
                tracePosM = candidateM;
                coarseSample = candidateSample;
                coarse = candidateCoarse;
                existenceGate = candidateGate;
            } else lowDistance = middle;
        }
        sampleDistance = highDistance;
        horizontalOffset = tracePos.xz-cameraPosition.xz;
        horizontalDistance2 = dot(horizontalOffset,horizontalOffset);
        #endif
        // F1 alpha ramp: the coarse octave alone can already reach the ramp's
        // upper edge. smoothstep then clamps to exactly 1 for every possible
        // detail value (that octave is non-negative), so the detail lookup and
        // its rounded-coordinate math cannot change the result. `saturation`
        // is the same expression the column-density ramp below consumes.
        float saturation = max(saturationBase, densityGate + 0.02);
        float noise = densityCoarse;
        if (noise < saturation) {
            vec2 detailUv = mat2(0.8,-0.6,0.6,0.8)*tracePosM.xz*2.7+vec2(31.7,9.3);
            noise += 0.22*astra_2d_cloud_sample(detailUv);
        }

        float columnDensity=smoothstep(densityGate,saturation,noise);
        float edgeWidth = clamp(sampleDistance * angularFootprint
                                * ASTRA_CLOUD_NARROWNESS * 0.35, 0.02, 0.10);
        columnDensity *= smoothstep(densityGate, densityGate + edgeWidth, densityCoarse);
        #if CLOUD_QUALITY == 2
        float lTracePosXZ=sampleDistance*horizontalRayLength;
        #else
        float lTracePosXZ=sqrt(horizontalDistance2);
        #endif
        #if CLOUD_QUALITY == 2
        float distanceRatio = clamp((ASTRA_CLOUD_THRESHOLD_F-lTracePosXZ)
                                    /ASTRA_CLOUD_THRESHOLD_F,0.0,0.75);
        float sampleAlpha = (1.0-exp(-columnDensity*segmentLength*ASTRA_CLOUD_DENSITY_EXTINCTION))
                          *sqrt(distanceRatio*1.33333);
        float weight = (1.0-volumetricClouds.a)*sampleAlpha;
        if (weight <= 0.0) continue;
        volumetricClouds.a += weight;
        representativeWorld += tracePos*weight;
        // Preserve the existing first-visible-surface lighting. Further
        // occupied segments change opacity, not the sky/lighting computation.
        if (cloudColorReady) {
            if (volumetricClouds.a >= 0.995) break;
            continue;
        }
        // Shade the continuous entry surface, rather than the midpoint of the
        // first occupied slice. Density still belongs to the integration point.
        tracePos = cameraPosition+lightingDistance*nPlayerPos;
        tracePosM = astra_modify_trace_pos(tracePos,ASTRA_CLOUD_ALTITUDE);
        coarseSample = mix(startCoarse,endCoarse,occupiedStart)/0.78;
        #endif

        // Empty rays need density only, not the sky palette and cloud lighting.
        // Evaluate the colour at the first visible hit. High reuses it while
        // integrating opacity; low/medium return that single hit immediately.
        float VdotS = dot(nPlayerPos, astraSunDirection);
        // Uniform-only sky records stay local to this ray's shading. Keep only
        // the derived cloud colours live across the four potentially long marches.
        AstraSkyFactors f=astra_sky_factors();
        AstraSkyPalette p=astra_sky_palette();
        astra_cloud_frame_colors(ctx, f, p);
        vec3 cloudAmbientColor=ctx.cloudAmbientColor;
        vec3 cloudLightColor=ctx.cloudLightColor;
        float twilight=ctx.twilight;
		// :94-95 - height within the sheet drives the lit-top / dark-bottom look
		float cloudShading = 1.0 - (higherPlaneAltitude - tracePos.y) / ASTRA_CLOUD_TALLNESS;
		      cloudShading = pow(max0(cloudShading), 0.8);
		// :96
		float VdotSM1 = max0(f.sunVisibility > 0.5 ? VdotS : -VdotS);

		// :99-120, CLOUD_QUALITY >= 2 branch.
		// cloudShadingM uses the non-DEFERRED1 form (Astra has no such pass define)
		// and lightMult stays 1.0 because GetShadowOnCloud needs the shadow map.
		float cloudShadingM = 1.0 - cloudShading;
        float gradientNoise = marchOffset;

		vec3 cLightPos = tracePosM;
		// lightVec (composite.glsl:26) == Astra's lightVector (sun by day, moon by night)
		// Cloud lighting uses the main-view world direction, including Voxy draws.
		vec3 cLightPosAdd = astraWorldLightDirection * 0.08 * f.shadowTime;
        // The offset is zero only when the shadow light is exactly vertical or
        // shadowTime is exactly 0 (the sun on the horizon). shadowTime is 1 at
        // night as well as by day and the night source is the moon, so this
        // reuse is normally inactive and the sample below still runs. When it
        // does hold, reuse the raw sample at the CURRENT refined shading point -
        // never densityCoarse, which keeps the occupied coarse column's coverage.
        bool unshiftedLight = all(equal(cLightPosAdd.xz, vec2(0.0)));

		float light = 2.0;
        #if CLOUD_QUALITY < 2
        // One sample at the mean of the old two light positions. Rounded,
        // low-frequency cloud density supports this cheaper illumination.
        cLightPos += (1.0+1.5*gradientNoise)*cLightPosAdd;
        light -= 2.0*(unshiftedLight ? coarseSample : astra_2d_cloud_sample(cLightPos.xz))*cloudShadingM;
        #else
		cLightPos += (1.0 + gradientNoise) * cLightPosAdd;
		    light -= (unshiftedLight ? coarseSample : astra_2d_cloud_sample(cLightPos.xz)) * cloudShadingM;
		cLightPos += gradientNoise * cLightPosAdd;
		    light -= (unshiftedLight ? coarseSample : astra_2d_cloud_sample(cLightPos.xz)) * cloudShadingM;
        #endif

		float VdotSM2 = VdotSM1 * f.shadowTime * 0.25;
		      VdotSM2 += 0.5 * cloudShading + 0.08;
		cloudShading = VdotSM2 * light;

		// :122
		vec3 colorSample = cloudAmbientColor * 0.95 * (1.0 - 0.35 * cloudShading)
		                 + cloudLightColor  * 0.9  * (0.1 + cloudShading);
        // Outside the existing twilight envelope this entire palette has zero
        // blend weight. Keep the cloud body/light march and sky convergence.
        if (twilight > 0.0) {
            float sunward=cube(max(0.0,0.5+0.5*VdotS));
            float horizonWarm=exp(-abs(VdotU)*3.0);
            float litEdge=clamp(cloudShading,0.0,1.0);
            float upperLayer=clamp((tracePos.y-lowerPlaneAltitude)
                                  /max(2.0*ASTRA_CLOUD_STRETCH,1.0),0.0,1.0);
            // Two-source edge lighting, one power each. The previous form keyed the warm
            // edge off the SUN direction only, so at night the lit edge of a cloud pointed
            // at a sun below the horizon and the moonlit side stayed flat. There is no
            // second light march here: `light` and the two density samples above are
            // unchanged, and this only decides which colour the existing lit edge takes.
            // The moon lobe is the sun lobe evaluated about -worldSunVector, the moon's own
            // direction - the same vector program/sky.fsh draws the disc along.
            float moonward=cube(max(0.0,0.5-0.5*VdotS));
            // Cooler body: the volume and the underside keep their own (blue-leaning)
            // colour rather than drifting towards the sky's white, which is what let the
            // cloud sheet dissolve into the sky at range.
            vec3 coolBody=cloudAmbientColor*vec3(0.72,0.82,1.04)
                         *mix(0.70,0.94,upperLayer);
            // Warmer, tighter edge: a lower constant floor (0.18 -> 0.14) and a stronger
            // litEdge coefficient (0.85 -> 0.95) so the rim separates from the body, and a
            // light-facing gate that the moon can also satisfy. `litEdge` is cloudShading,
            // i.e. light actually reaching the top of the first hit, so the underside of a
            // cloud and a cloud turned away from the light cannot be brightened by this.
            vec3 warmEdge=cloudLightColor*vec3(1.10,0.74,0.44)
                         *(0.14+0.95*litEdge)*(0.30+0.70*max(sunward,moonward*0.70));
            warmEdge+=astra_twilight_tint()*sunward*horizonWarm*(0.12+0.5*litEdge);
            colorSample=mix(colorSample,coolBody+warmEdge,twilight*0.72);
        }
		// :123 - doGlare = isEyeInWater == 0, doGround = false (same as the sky)
        // This colour depends on the view ray, never on the marching sample.
        // Evaluate once, and only for rays that actually encounter a cloud.
        vec3 cloudSkyColor=astra_get_sky(VdotU,VdotS,ctx.dither,
            isEyeInWater==0 || water_is_thin_sheet(),false,f,p);
        // Converge toward the same tinted atmosphere as the visible sky. Keep
        // the smooth shared table unmodified: each consumer owns this gain.
        cloudSkyColor=astra_twilight_atmosphere(cloudSkyColor,nPlayerPos);
        cloudSkyColor*=astra_sky_color_gain(VdotU,skyVisibilityDay,twilight,astraDawnBlend);
        cloudSkyColor=astra_twilight_highlights(cloudSkyColor);
        colorSample=astra_twilight_highlights(colorSample);

		// :127-132
		float cloudDistanceRatio = (ASTRA_CLOUD_THRESHOLD_F - lTracePosXZ) / ASTRA_CLOUD_THRESHOLD_F;
		float cloudFogFactor = pow2(clamp(cloudDistanceRatio, 0.0, 1.0)) * 0.707;
		      cloudFogFactor = mix(1.0, cloudFogFactor, skyFadeM);
		colorSample *= 1.0 - 0.2 * (1.0 - skyFadeM) * max(f.sunVisibility2, f.nightFactor);
        // Keep the nearby cloud's shaded body; the previous factor mixed at
        // least half of the bright sky into even the nearest cloud.
        // The ceiling drops 0.88 -> 0.80 for the same reason the body colour was
        // cooled: at 0.88 a twilight cloud was four fifths sky, which is how the edge,
        // the body and the sky became one white sheet. The distance-driven part of the
        // blend is untouched - a distant cloud still converges to the atmosphere, which
        // is what the perspective needs.
		colorSample = mix(cloudSkyColor, colorSample, clamp(cloudFogFactor * mix(0.707,1.18,twilight),0.0,0.80));
		// :132 - Astra's blindness is the vanilla darkness effect in [0,1]
		colorSample *= pow2(1.0 - blindness);

		// :134-137 - cloudMult is 1.0 (the lViewPosM branch has no Astra equivalent)
		float cloudDistanceFactor = clamp(cloudDistanceRatio, 0.0, 0.75);
        // F1: the ramp starts exactly at the existence gate, so the visible alpha reaches 0
        // on the boundary instead of jumping straight to a 0.087 film below it.
        // Near the sheet's upper/lower boundary the existence threshold can
        // exceed the nominal saturation. smoothstep requires ordered edges.
        // `saturation` was resolved above the detail-octave gate, which uses it
        // to skip the detail lookup whenever it cannot change this ramp.
        // The detail octave must not turn the coarse existence gate into an
        // alpha step. Cover its boundary continuously over the pixel footprint.
        // Interior density and the two lighting samples keep their original form.
        #if CLOUD_QUALITY == 2
        // Integrate opacity over actual segment lengths. A first-hit alpha
        // changed with the sampling lattice; interval integration remains
        // continuous when a boundary moves between adjacent sample positions.
        firstCloudColor = colorSample;
        cloudColorReady = true;
        if (volumetricClouds.a >= 0.995) break;
        #else
        volumetricClouds.a = sqrt(cloudDistanceFactor * 1.33333)*columnDensity;
        volumetricClouds.rgb = colorSample;
        representativeWorld = tracePos;
        break;
        #endif
	}

    #if CLOUD_QUALITY == 2
    if (volumetricClouds.a > 0.0) {
        // Every occupied segment uses this same colour. Its weighted sum
        // divided by total opacity is the colour itself; integrate only the
        // opacity and representative position needed by temporal reprojection.
        volumetricClouds.rgb = firstCloudColor;
        representativeWorld /= volumetricClouds.a;
    }
    #endif

	// :144 - skyFadeM is 1.0
	volumetricClouds.a *= 0.5 + 0.5 * skyFadeM;

	return volumetricClouds;
}

vec4 astra_planar_cloud(vec3 nPlayerPos, float maxRayDistance, out vec3 representativeWorld,
                       float angularFootprint, vec2 interval) {
    AstraCloudFrame ctx = astra_cloud_frame();
    return astra_planar_cloud(nPlayerPos, maxRayDistance, representativeWorld,
                              angularFootprint, interval, ctx);
}

vec4 astra_planar_cloud(vec3 worldDir, float maxRayDistance, out vec3 representativeWorld,
                        float angularFootprint) {
    vec3 nPlayerPos = normalize(worldDir);
    return astra_planar_cloud(nPlayerPos, maxRayDistance, representativeWorld, angularFootprint,
                              astra_cloud_interval(nPlayerPos));
}

vec4 astra_planar_cloud(vec3 worldDir, float maxRayDistance, out vec3 representativeWorld) {
    return astra_planar_cloud(worldDir, maxRayDistance, representativeWorld, 0.0);
}

vec4 astra_planar_cloud(vec3 worldDir, float maxRayDistance) {
    vec3 unusedRepresentative;
    return astra_planar_cloud(worldDir, maxRayDistance, unusedRepresentative);
}

vec4 astra_planar_cloud(vec3 worldDir) {
    return astra_planar_cloud(worldDir, 1e20);
}

#endif
