#ifndef ASTRA_GLOBAL_POST_BLOOM_GLSL
#define ASTRA_GLOBAL_POST_BLOOM_GLSL

// Astra v1 — global/post/bloom.glsl
// Two-pass bloom (design.md 4.4): composite1 captures a half-resolution, soft-knee
// prefiltered image into colortex2 with mipmaps on, and the final chain reads several
// mip levels of it. The mip chain replaces the 6-pass downsample pyramid that Mellow
// ships, which is where the four saved passes come from.
//
// PROVENANCE: adapted from Refrax v1.3.1 (proprietary) - structure borrowed from
//   lib/bloom.glsl (bloomPrefilter soft knee) and program/bloom_downsample.fsh.glsl
//   (13-tap dual-filter downsample). REWRITE REQUIRED before distribution.
//   Registered in THIRD-PARTY.md per design.md 9.2. Refrax builds a 6-level atlas and
//   blurs each level with two extra passes; Astra instead lets the driver build the
//   levels (colortex2MipmapEnabled) and spends its two passes on capture + composite.
//
// Uniforms: none (the source is passed in as a sampler parameter)
// Consts:   BLOOM_STRENGTH (lib/settings.glsl) is applied by the caller in the final
//           chain, not here - see bloom_composite's strength argument.
// Owner: B5. Consumers: program/composite1.fsh (capture), program/final.fsh (composite,
//           E1/C6's side of the chain).

// --- prefilter tuning (HDR, pre-tonemap; colortex0 is R11F_G11F_B10F) ---
// Anything at or below white contributes nothing, which is what keeps bloom off the
// midtones and stops it from turning into a grey haze over the whole frame.
const float BLOOM_THRESHOLD = 1.0;
// Soft knee width, in the same units. Without it, pixels crossing the threshold pop
// in and out as the sun or a light source moves, which is very visible without TAA.
const float BLOOM_KNEE = 0.5;
// Ceiling on how much a single pixel may contribute. Without TAA there is nothing to
// average out a one-frame specular firefly, so clamping here is the anti-flicker
// measure for the 0.5x capture (regression checklist item 18).
const float BLOOM_SOURCE_CLAMP = 16.0;

// Capture buffer scale. THIS MUST MATCH size.buffer.colortex2 IN shaders.properties.
// It exists because the 13-tap offsets below are expressed in SOURCE texels, so the
// filter's screen-space footprint is fixed only as long as the capture resolution is
// fixed. Shrinking the capture buffer without widening the taps makes every output texel
// gather from a footprint smaller than the screen area it represents, which under-samples
// and lets bright pixels pop in and out between frames - exactly the flicker the
// BLOOM_SOURCE_CLAMP above cannot catch.
const float BLOOM_CAPTURE_SCALE = 0.25;

// 13-tap dual-filter downsample offsets / weights (sum = 1.0). The ring radii are
// 1, 2 and 2*sqrt(2) texels, which is what lets a single pass drop resolution by
// exactly 2x without either aliasing or over-blurring.
const ivec2 BLOOM_TAP[13] = ivec2[13](
	ivec2( 0,  0),
	ivec2(-1, -1), ivec2( 1, -1), ivec2(-1,  1), ivec2( 1,  1),
	ivec2(-2,  0), ivec2( 2,  0), ivec2( 0, -2), ivec2( 0,  2),
	ivec2(-2, -2), ivec2( 2, -2), ivec2(-2,  2), ivec2( 2,  2));

const float BLOOM_TAP_WEIGHT[13] = float[13](
	0.125,
	0.125, 0.125, 0.125, 0.125,
	0.0625, 0.0625, 0.0625, 0.0625,
	0.03125, 0.03125, 0.03125, 0.03125);

// Soft-knee brightness prefilter. Returns the part of `color` that is above the
// threshold, scaled so that the transition across the knee is continuous in both value
// and slope - that continuity is the whole reason for the knee's existence.
//
//   below threshold - knee  -> 0
//   inside the knee         -> quadratic ramp (soft * soft / (4 * knee))
//   above threshold + knee  -> color * (brightness - threshold) / brightness
vec3 bloom_prefilter(vec3 color) {
	float brightness = max(color.r, max(color.g, color.b));
	if (brightness <= 1e-5) {
		return vec3(0.0);
	}

	// The knee starts at the threshold. The former +/- knee began at 0.5,
    // making ordinary sand a bloom emitter and spreading a white fringe.
    float soft = clamp(brightness - BLOOM_THRESHOLD, 0.0, 2.0 * BLOOM_KNEE);
	soft = soft * soft / (4.0 * BLOOM_KNEE + 1e-4);

	float excess = min(max(soft, brightness - BLOOM_THRESHOLD - BLOOM_KNEE), BLOOM_SOURCE_CLAMP);
	return color * (excess / brightness);
}

// Stage 1 (program/composite1.fsh): prefiltered 2x downsample of the HDR scene into
// the half-resolution bloom buffer. One pass, 13 texture fetches, no colour output
// dependency - the buffer Iris produces here is what gets mipmapped.
//
// src is colortex0 at full resolution; texCoord is the half-res pass's own normalised
// coordinate, which is also valid for sampling the full-res source.
vec3 bloom_capture(sampler2D src, vec2 texCoord) {
	// Derived from the source rather than from viewWidth/viewHeight: the capture rate
	// has to track whatever size colortex0 actually is, and Iris resizes it with the
	// render scale.
	vec2 srcTexel = 1.0 / vec2(textureSize(src, 0));

	// How many source texels one capture texel spans. At the classic 0.5x capture this is
	// exactly 2.0, which is the ratio the dual filter is designed around, so tapScale is
	// 1.0 and the filter is unchanged. A smaller capture buffer widens the footprint and
	// the taps scale with it, keeping the gather the same size in screen space.
	float footprint = float(textureSize(src, 0).x)
	                / max(float(viewWidth) * BLOOM_CAPTURE_SCALE, 1.0);
	float tapScale = max(footprint * 0.5, 1.0);

	vec2 pad = 0.5 * srcTexel * tapScale;

	vec3 acc = vec3(0.0);
	for (int i = 0; i < 13; i++) {
		vec2 coord = clamp(texCoord + vec2(BLOOM_TAP[i]) * srcTexel * tapScale,
		                   pad, 1.0 - pad);
		acc += bloom_prefilter(max(textureLod(src, coord, 0.0).rgb, vec3(0.0)))
			* BLOOM_TAP_WEIGHT[i];
	}

	return acc;
}

// Stage 2 (program/final.fsh, E1/C6): combine the mip levels of the capture into the
// bloom that gets added to the scene.
//
// Weights fall off with level on purpose - most of the energy stays in the tighter
// levels, so the result reads as light spilling out of bright pixels rather than a
// uniform veil. Additive, not a mix: mixing would lift the blacks and reintroduce
// exactly the grey-haze look this is supposed to avoid (regression checklist item 18).
//
//   color += bloom_composite(colortex2, texcoord, BLOOM_STRENGTH * 0.01);
vec3 bloom_composite(sampler2D bloomTex, vec2 texCoord, float strength) {
	#ifdef DIMENSION_END
		// Restrict the sky bloom to the two smallest levels; retain sharp stars and gaps.
		vec3 bloom=textureLod(bloomTex,texCoord,0.0).rgb*0.65
		          +textureLod(bloomTex,texCoord,1.0).rgb*0.35;
		return max(bloom,vec3(0))*strength*0.45;
	#else
	// Mip levels compensate for the capture resolution, so these are not arbitrary.
	// A level's texel covers (screen/bloomWidth) * 2^level pixels, so at the 0.5x capture
	// levels 1..4 spanned 4, 8, 16 and 32 pixels. The capture is now 0.25x, which doubles
	// every level's footprint, so the reads shift down one level and land on exactly the
	// same 4, 8, 16, 32 pixel footprints - the weighted mean stays 10.4 px and the bloom
	// radius is unchanged. Reading 1..4 here would silently widen the whole glow to a veil.
	// The one residual difference is that level 0 is the capture itself rather than a mip
	// of it, so the tightest term is marginally crisper; confirm in game.
	vec3 bloom = textureLod(bloomTex, texCoord, 0.0).rgb * 0.40
	           + textureLod(bloomTex, texCoord, 1.0).rgb * 0.30
	           + textureLod(bloomTex, texCoord, 2.0).rgb * 0.20
	           + textureLod(bloomTex, texCoord, 3.0).rgb * 0.10;

	return max(bloom, vec3(0.0)) * strength;
	#endif
}

#endif
