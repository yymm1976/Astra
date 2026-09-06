#ifndef ASTRA_GLOBAL_LIGHTING_WIND_GLSL
#define ASTRA_GLOBAL_LIGHTING_WIND_GLSL

// Astra v1 — global/lighting/wind.glsl
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot
//   source: _analysis/Steadfast-0.8.0/shaders/environment/wind.glsl (WindDisplacement)
//           + program/world/lit.vsh (WaveFoliage)
// This file is a derivative of Steadfast and is licensed under the GNU General Public
// License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
// _analysis/Steadfast-0.8.0/LICENSE.md, including Steadfast's Section 7 additional terms.
// Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Astra changes:
//   - Steadfast's WaveFoliage lives inside lit.vsh because it needs the material ID;
//     Astra puts a material-agnostic version here so E1 can call it from the unified
//     lit entry without this module knowing how material IDs are packed.
//   - WAVING_FOLIAGE_STRENGTH is applied here (Steadfast has no such option).
//   - All wind parameters are CPU custom uniforms (Z3, design.md 5); the only
//     per-vertex cost left is three sines, which cannot be precomputed because they
//     depend on the block position.
//
// Uniforms: windStrength, windTheta, cameraPosition (lib/uniforms.glsl)
// Consts:   WAVING_FOLIAGE_STRENGTH (lib/settings.glsl)
// Owner: B3. Consumer: program/lit.vsh (E1 owns the vertex stage and its varyings).

// Astra's `windStrength` custom uniform carries the value Steadfast calls
// windStrengthHalf (0.09 * (1 + 0.5 * rainStrength) / 2): the magnitude sine below is
// remapped from [-1, 1] to [0, 2 * half], so peak displacement is 2 * windStrength —
// 0.09 blocks at rest, 0.135 in rain, before the user's strength slider.
//
// Straightforward but convincing: magnitude cycles between 0 and the wind strength
// with a positional phase shift, so the wind moves in patches rather than uniformly;
// direction is three sines with their own phase shifts. Vertical phase shift is halved
// and vertical displacement halved too, because wind is horizontal and columns of
// leaves reading as one unit looks better than each layer doing its own thing.
vec3 wind_displacement(vec3 worldPos) {
	float halfStrength = windStrength * (WAVING_FOLIAGE_STRENGTH * 0.01);

	float magnitude = sin(windTheta.w + worldPos.y + worldPos.z) * halfStrength + halfStrength;
	vec2 windPhaseShift = (worldPos.x + worldPos.z) * vec2(1.5, 0.75);
	vec3 direction = sin(windTheta.xyz + windPhaseShift.xyx);

	return vec3(magnitude, magnitude * 0.5, magnitude) * direction;
}

// Call-site helper for the lit vertex stage. E1 passes the classification it decoded
// from the packed material ID; block.properties maps it to
//   10002 leaves            -> isLeaves
//   10004 / 10005 / 10006   -> isGroundFoliage (small plants and double-plant halves;
//                              crops are in 10004)
// topOfFoliage is `at_midBlock.y < 0.0`: only the upper vertices of a plant move, so
// the base stays planted in the block below instead of the whole plant sliding.
// playerPos is camera-relative world space (Mellow convention, as in lib/distort.glsl).
void wave_foliage(
	bool isLeaves,
	bool isGroundFoliage,
	bool topOfFoliage,
	inout vec3 playerPos
) {
	if (isLeaves || (isGroundFoliage && topOfFoliage)) {
		vec3 worldPos = playerPos + cameraPosition;
		vec3 displacement = wind_displacement(worldPos);

		// Ground foliage is anchored; only full blocks (leaves) lift vertically.
		displacement.y = isGroundFoliage ? 0.0 : displacement.y;

		playerPos += displacement;
	}
}

#endif
