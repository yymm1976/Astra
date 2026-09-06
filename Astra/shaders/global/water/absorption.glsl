#ifndef ASTRA_GLOBAL_WATER_ABSORPTION_GLSL
#define ASTRA_GLOBAL_WATER_ABSORPTION_GLSL

// Astra v1 — global/water/absorption.glsl
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot
//   source: _analysis/Steadfast-0.8.0/shaders/environment/water/absorption.glsl
// This file is a derivative of Steadfast and is licensed under the GNU General
// Public License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
// _analysis/Steadfast-0.8.0/LICENSE.md. Redistribution is permitted only under that
// license including Steadfast's Section 7 additional terms.
// Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Beer-Lambert transmission through water: each channel decays as exp(depth * coeff),
// red fastest, which is what makes water read blue-green with depth (design.md 4.3).
//
// Adaptations for Astra (design.md 3.2 / 4.3 / SC-1):
//   - Steadfast picks the palette with `#define WATER_CHARACTER BALANCED` (a token
//     macro pasted into the exponent). Astra's WATER_CHARACTER is a NUMERIC enum
//     (0/1/2 = WATER_COLD/WATER_BALANCED/WATER_TROPICAL, settings.glsl), so the three
//     verbatim -vec3 coefficients are selected with #if on the numeric value.
//   - WATER_ABSORPTION (0-100 slider; SC-1: 0 = OFF) scales the optical depth.
//     At 0 the exponent is 0 -> exp(0) = vec3(1) -> unity transmission, which IS the
//     "off" semantics SC-1 asks for, with no separate branch and no discontinuity.
//   - Steadfast's DARK_UNDERWATER brightness-reduction option is not in Astra's option
//     set; its shipped default (1.0) makes the term a multiply-by-one no-op, so it is
//     dropped rather than carried as dead code.
//   - Renamed to snake_case (design.md 3.2).
//
// Uniforms: none — pure function of the caller-supplied depth.
// Requires lib/settings.glsl (WATER_CHARACTER, WATER_ABSORPTION) included first — program/*
//   guarantees the order (design.md 3.2 layer 2), matching lib/colors.glsl. Includes no lib/*.
// Consts:   none local (the coefficient is function-scoped, selected by WATER_CHARACTER).
// Owner: C2. Consumer: E2 (water-surface integration) and the deferred underwater fog.
//   C2 delivers the UNDERWATER BODY ONLY (task directive 不越界): computing `depth`
//   (from the refraction hit or the colortex3 skylight heuristic, design.md 4.3) and
//   applying the transmission to the scene both belong to E2, not here.

// Transmission through normalized optical depth.
//   depth: caller-supplied water path in [0, 1]. E2 maps physical blocks to
//          clamp(pathBlocks / 32, 0, 1) before this call.
// Returns a per-channel factor in [0, 1]: vec3(1) = clear, -> vec3(0) = fully absorbed.
vec3 water_absorption(float depth) {
	// Coefficient magnitudes are Steadfast's verbatim COLD/BALANCED/TROPICAL triples.
	// Negative so exp() decays; red (x) is largest = absorbed first.
	#if WATER_CHARACTER == WATER_COLD
		const vec3 character = -vec3(16.0, 5.0, 1.0);
	#elif WATER_CHARACTER == WATER_TROPICAL
		const vec3 character = -vec3(32.0, 2.0, 0.5);
	#else
		const vec3 character = -vec3(16.0, 3.0, 1.0);   // BALANCED (default)
	#endif

	float absorptionDepth = clamp(depth, 0.0, 1.0) * (WATER_ABSORPTION * 0.01);
	return exp(absorptionDepth * character);
}

#endif
