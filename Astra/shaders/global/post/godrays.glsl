#ifndef ASTRA_GLOBAL_POST_GODRAYS_GLSL
#define ASTRA_GLOBAL_POST_GODRAYS_GLSL

// Astra v1 — global/post/godrays.glsl
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot
//   source: _analysis/Steadfast-0.8.0/shaders/program/post/noisy_godrays.fsh
// This file is a derivative of Steadfast and is licensed under the GNU General Public
// License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
// _analysis/Steadfast-0.8.0/LICENSE.md, including Steadfast's Section 7 additional terms.
// Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Astra changes:
//   - the pass body stays in program/composite.fsh; this module holds only the
//     algorithm, so the second stage (final-pass smoothing + upsample, E1/C6's side)
//     and this one can be reviewed and tuned independently.
//   - the Bayer8 start jitter comes from Astra's own lib/bayer.glsl (public-domain
//     recursive matrix, escalations.md SC-7) instead of Steadfast's bayer8.glsl.
//   - depthtex0 is declared in lib/uniforms.glsl, not here.
//
// Uniforms: depthtex0, godraysExposure (lib/uniforms.glsl)
// Consts:   none
// Owner: B4. Consumer: program/composite.fsh.

#include "/lib/bayer.glsl"

// The sky has no geometry, so it keeps the far-plane depth. This is one of the few
// places where an == comparison on a depth buffer is reliable.
const float SKY_DEPTH = 1.0;

// Depth comparison done by hand: Iris gives us depthtex0 as a plain sampler, so we
// reproduce GL_LEQUAL against the stored depth instead of using a shadow sampler.
float depth_compare_sample(vec3 texCoord) {
	if (any(lessThan(texCoord.xy, vec2(0.0))) || any(greaterThan(texCoord.xy, vec2(1.0)))) {
		return 0.0;
	}
	return float(texCoord.z <= texture(depthtex0, texCoord.xy).r);
}

// Screen-space light shafts after GPU Gems 3, "Volumetric Light Scattering as a
// Post-Process":
//   https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows
//
// Two departures from the chapter, both Steadfast's:
//   1. march the DEPTH buffer instead of the colour buffer, so occlusion is decided
//      by geometry rather than by how bright the occluder happens to be;
//   2. jitter the start position with ordered dithering, which turns the banding of a
//      low sample count into noise - 8 samples with a Bayer8 offset looks like far
//      more, and the noise is removed by the second (final-pass) smoothing stage.
//
// screenCoord is normalised coordinates of the HALF-RESOLUTION godrays buffer;
// lightScreenPos is the shadow light's position in the same space (0..1, may be
// off-screen - the CPU-side offscreen fade in godraysExposure handles that).
float godrays_density(vec2 screenCoord, vec2 lightScreenPos) {
	#ifdef ASTRA_VOLUME_FOG
	// R2/H3: with the optional overworld volume on, the ray march owns this air
	// segment's solar in-scatter (per-step shadow map, cloud shadow and phase lobe).
	// Keeping the screen-space beam would scatter the same air twice (handoff R2
	// section 4.3), so the legacy path yields nothing while the volume option is on.
	// godraysExposure / GODRAYS_STRENGTH stay display-side and need no change; the
	// underwater arm of composite2 is a different medium and keeps working.
	return 0.0;
	#else
	const float NUM_SAMPLES = 8.0;
	const float DENSITY = 0.83;
	const float DECAY = pow(0.5, 1.0 / NUM_SAMPLES);

	vec2 texCoord = screenCoord;

	// Step from this pixel towards the light, scaled by the density control factor.
	vec2 deltaTexCoord = texCoord - lightScreenPos;
	deltaTexCoord *= 1.0 / NUM_SAMPLES * DENSITY;

	texCoord += deltaTexCoord * 1.5 * bayer8(gl_FragCoord.xy);

	float accumulated = 0.0;
	float illuminationDecay = 1.0;

	for (uint i = uint(0); i < uint(NUM_SAMPLES); i++) {
		texCoord -= deltaTexCoord;
		float depthSample = depth_compare_sample(vec3(texCoord, SKY_DEPTH));
		depthSample *= illuminationDecay;
		accumulated += depthSample;
		illuminationDecay *= DECAY;
	}

	return accumulated / NUM_SAMPLES;
	#endif
}

#endif
