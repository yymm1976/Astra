#ifndef ASTRA_GLOBAL_LIGHTING_SHADOWMAP_GLSL
#define ASTRA_GLOBAL_LIGHTING_SHADOWMAP_GLSL

// Astra v1 — global/lighting/shadowmap.glsl
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot
//   source: _analysis/Steadfast-0.8.0/shaders/environment/lighting/shadowmap.glsl
//           (+ program/world/lit.vsh ShadowMapPosition, program/shadow/shadow.vsh)
// This file is a derivative of Steadfast and is licensed under the GNU General
// Public License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
// _analysis/Steadfast-0.8.0/LICENSE.md. Redistribution is permitted only under that
// license including Steadfast's Section 7 additional terms.
// Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Adaptations for Astra (all naming per design.md 3.2):
//   - shadowMapResolution / shadowDistance / entityShadowDistanceMul /
//     shadowHardwareFiltering live in lib/settings.glsl ENGINE KNOBS, not here
//     (design.md 2.3 + SC-13), so they are NOT redeclared.
//   - distortion comes from lib/distort.glsl (Mellow port), not Steadfast's.
//   - water-height encode/decode is pulled out of the shadow pass into this module so
//     producer and consumer share one definition (Steadfast's "TODO: Make this a
//     common function" in shadow.fsh).
//   - caustics are NOT sampled here: C2's global/water/caustics.glsl consumes
//     decode_water_height() + shadow_map_fade() and owns WATER_CAUSTICS.
//
// Uniforms: shadowModelView, shadowProjection, gbufferModelViewInverse (lib/uniforms.glsl);
//           shadowDistance, shadowMapResolution, SHADOW_SOFTNESS (lib/settings.glsl).
// Consts:   none local.
// Owner: B1. Consumer: program/lit.fsh (E1 owns the varying that carries shadowPos).

#include "/lib/distort.glsl"

// Fixed part of the adaptive normal-offset bias. Steadfast exposes this as a user
// option (default 0.20); Astra keeps it a compile-time constant because it interacts
// with the distortion shape and is not something a user can tune meaningfully.
#ifndef SHADOW_DISTORT_FACTOR
#define SHADOW_DISTORT_FACTOR 0.20
#endif

// ---------------------------------------------------------------------------
// Water surface height in shadowcolor0.R (design.md 2.3)
//
// The shadow map stores, per texel, the Y of the topmost water surface along the
// light ray. C2's caustics subtract the fragment Y from it to get water depth, which
// is why this has to be readable from both the pass that writes it and the pass that
// samples it. Range is ±1024 blocks around Y=0; caustics are distance-limited far
// below that (WATER_CAUSTICS_DISTANCE), so the clamp never bites in practice.
// ---------------------------------------------------------------------------
const float SHADOW_WATER_HEIGHT_RANGE = 1024.0;

// Sentinel written by every non-water caster: decodes to -1024, i.e. "the water
// surface is 1024 blocks below you", which the caustics smoothstep zeroes out.
const float WATER_HEIGHT_NONE = 1.0;

float encode_water_height(float worldY) {
	return 0.5 - 0.5 * clamp(worldY / SHADOW_WATER_HEIGHT_RANGE, -1.0, 1.0);
}

float decode_water_height(float encoded) {
	return (1.0 - 2.0 * encoded) * SHADOW_WATER_HEIGHT_RANGE;
}

// ---------------------------------------------------------------------------
// Samplers (design.md 4.1: sampler2DShadow + hardware PCF)
//
// Iris convention: shadowtex0 holds every shadow caster, shadowtex1 holds opaque
// casters only. Colored shadows need both, because the difference between them is
// exactly "how much of the blocking is done by translucent geometry".
// ---------------------------------------------------------------------------
#ifdef SHADOWS
uniform sampler2DShadow shadowtex0;

#ifdef COLORED_SHADOWS
uniform sampler2DShadow shadowtex1;
#endif
#endif

#if defined(COLORED_SHADOWS) || defined(WATER_CAUSTICS)
uniform sampler2D shadowcolor0;      // R = water height, GBA = translucent tint
#endif

// Four taps, each one a hardware 2x2 PCF tap, so a single kernel touches up to 16
// texels. SHADOW_SOFTNESS widens the kernel (texels); it never adds taps — that is
// what keeps the cost flat across the three profiles (design.md 4.1, SC-13).
//
// Written as a macro because GLSL sampler function parameters are legal but have a
// long history of driver bugs; the macro keeps one kernel definition per sampler.
#define SHADOW_PCF4(TEX, SPREAD) ( \
	    0.25 * texture(TEX, vec3(shadowPos.xy + vec2( SPREAD,  SPREAD), shadowPos.z)) \
	  + 0.25 * texture(TEX, vec3(shadowPos.xy + vec2(-SPREAD,  SPREAD), shadowPos.z)) \
	  + 0.25 * texture(TEX, vec3(shadowPos.xy + vec2( SPREAD, -SPREAD), shadowPos.z)) \
	  + 0.25 * texture(TEX, vec3(shadowPos.xy + vec2(-SPREAD, -SPREAD), shadowPos.z)))

// Kernel radius in shadow-map UV. Written with a reciprocal because a bare
// SHADOW_SOFTNESS / shadowMapResolution is integer division for every value in the
// slider's list and would collapse the kernel to zero width.
const float shadowTexelSpread = SHADOW_SOFTNESS * (1.0 / shadowMapResolution);

#ifdef SHADOWS
// 1.0 = fully lit, 0.0 = fully shadowed. Every caster counts.
float sample_shadows(vec3 shadowPos) {
	return SHADOW_PCF4(shadowtex0, shadowTexelSpread);
}

#ifdef COLORED_SHADOWS
// Same, but the light that had to cross a translucent caster comes out tinted.
//   nothing blocking:  all=1, opaque=1 -> 1          (no tint applied)
//   opaque blocking:   all=0, opaque=0 -> 0          (opaque transmits nothing)
//   translucent only:  all=0, opaque=1 -> tint       (stained glass colors the shadow)
vec3 sample_shadows_tinted(vec3 shadowPos) {
	float visibilityAll    = SHADOW_PCF4(shadowtex0, shadowTexelSpread);
	float visibilityOpaque = SHADOW_PCF4(shadowtex1, shadowTexelSpread);
	vec3 tint = texture(shadowcolor0, shadowPos.xy).gba;
	return visibilityAll + tint * visibilityOpaque * (1.0 - visibilityAll);
}
#endif
#endif

// ---------------------------------------------------------------------------
// Vertex stage: shadow-map sample position with an adaptive normal-offset bias.
//
// Bias method after Complementary Reimagined (Emin) and Photon (SixthSurge); the
// "vary the offset along the normal in proportion to the distortion" observation is
// Steadfast's, and their 1.5 multiplier exists to kill acne on distant mountaintops.
// ---------------------------------------------------------------------------
vec3 shadow_map_position(vec3 playerPos, vec3 worldNormal, float ndotl) {
	// playerPos is camera-relative. Iris' shadowModelView expects the translated
	// player-space origin represented by the inverse gbuffer view matrix; absolute
	// cameraPosition must never enter this transform.
	vec3 shadowPlayerPos = playerPos + gbufferModelViewInverse[3].xyz;

	// Variable term: grows with distance from the shadow-map centre, because
	// distortion stretches texels there and a constant offset stops covering them.
	vec4 shadowViewPosDistort = shadowModelView * vec4(shadowPlayerPos, 1.0);
	vec3 shadowPosDistort = (shadowProjection * shadowViewPosDistort).xyz;
	float distanceFactor = 1.5 * length(shadowPosDistort.xy);

	// Fixed term, dialled down on faces turned towards the light: at close range a
	// full fixed offset makes the shadow pop in and out at block edges.
	distanceFactor += SHADOW_DISTORT_FACTOR * (1.0 - max(ndotl, 0.0));

	vec4 shadowViewPos = shadowModelView * vec4(shadowPlayerPos + worldNormal * distanceFactor, 1.0);
	vec3 shadowPos = (shadowProjection * shadowViewPos).xyz;

	shadowPos = distort(shadowPos);
	shadowPos = shadowPos * 0.5 + 0.5;   // NDC -> texture space

	// Very small constant depth bias; the normal-offset term above does the real work.
	shadowPos.z -= 0.00001;

	return shadowPos;
}

// ---------------------------------------------------------------------------
// Fragment stage: distance bookkeeping + the full direct-light multiplier.
// ---------------------------------------------------------------------------

// shadowDistanceRenderMul culls with an axis-aligned box centred on the camera, so
// the metric that keeps us inside that box is the max per-axis distance.
float shadow_box_distance(vec3 playerPos) {
	return max(abs(playerPos.x), max(abs(playerPos.y), abs(playerPos.z)));
}

// 1 inside the shadow map, 0 at the edge and beyond. Exported for C2's caustics,
// which need water depth from the shadow map and are meaningless without coverage.
float shadow_map_fade(vec3 playerPos) {
	return 1.0 - smoothstep(
		shadowDistance - 5.0,
		shadowDistance,
		shadow_box_distance(playerPos));
}

// Skylight stand-in for real shadows past the shadow distance (design.md 4.1).
// A light level of 13.5–14.5 out of 15 is where vanilla terrain is effectively
// unoccluded, which is what makes this read as "probably in sunlight".
float static_shadow(float skyLight) {
	return smoothstep(13.5 / 15.0, 14.5 / 15.0, skyLight);
}

// Returns the multiplier to apply to the direct light colour.
//
// Caller contract (E1 / C1):
//   - skip the call entirely when NdotL <= 0 (design.md 5 early-out) — this function
//     does not see NdotL and must not be the thing that pays for the samples;
//   - playerPos is camera-relative world space (Mellow convention, matches
//     lib/transforms.glsl which adds the camera translation itself);
//   - shadowPos is shadow_map_position() carried through a varying;
//   - skyLight is 0..1 where 1 is light level 15;
//   - subsurfaceScatter is C1's SSS classification for this material.
vec3 shadow_mapping(
	vec3 playerPos,
	vec3 shadowPos,
	float skyLight,
	bool subsurfaceScatter
) {
	float boxDistance = shadow_box_distance(playerPos);

	#ifdef STATIC_SHADOW_FALLBACK
		float staticShadow = static_shadow(skyLight);
	#else
		// Without the fallback, everything past the shadow distance stays fully lit;
		// the real-time fade below then has nothing to hand over to.
		float staticShadow = 1.0;
	#endif

	#ifndef SHADOWS
		return vec3(staticShadow);
	#else

	// Static shadows fade in first (10 -> 5 blocks from the edge)...
	float staticStrength = smoothstep(shadowDistance - 10.0, shadowDistance - 5.0, boxDistance);
	vec3 shadow = vec3(1.0 - staticStrength * (1.0 - staticShadow));

	// ...then real-time shadows fade out (5 -> 0 blocks). The 5-block overlap is the
	// whole point: it is what keeps the hand-off from showing a hard edge.
	float withinShadowMap = shadow_map_fade(playerPos);
	if (withinShadowMap < 0.0001) {
		return shadow;
	}

	#ifdef COLORED_SHADOWS
		vec3 sampled = sample_shadows_tinted(shadowPos);
	#else
		vec3 sampled = vec3(sample_shadows(shadowPos));
	#endif
	shadow = min(shadow, mix(vec3(1.0), sampled, withinShadowMap));

	// SSS: foliage in shadow behaves as if it were permanently turned ~45 degrees
	// away from the light (cos(pi/4) ~= 0.7071). Foliage fully facing the light reads
	// as far too bright. The forward-scatter boost on top of this is C1's
	// global/lighting/sss.glsl, scaled by SSS_STRENGTH.
	float directLightStrength = 1.0;
	if (subsurfaceScatter) {
		directLightStrength = mix(directLightStrength, 0.7071, withinShadowMap);
	}

	return directLightStrength * shadow;
	#endif
}

#endif
