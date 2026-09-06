#ifndef ASTRA_GLOBAL_ATMOSPHERE_FOG_GLSL
#define ASTRA_GLOBAL_ATMOSPHERE_FOG_GLSL

// Astra v1 — global/atmosphere/fog.glsl
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot
//   source: _analysis/Steadfast-0.8.0/shaders/environment/fog.glsl (FogV2)
// This file is a derivative of Steadfast and is licensed under the GNU General Public
// License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
// _analysis/Steadfast-0.8.0/LICENSE.md, including Steadfast's Section 7 additional terms.
// Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Astra changes:
//   - the fog COLOURS are parameters, not uniforms. Steadfast precomputes
//     caveFogColor / underwaterFogColor as custom uniforms; Astra's Z3 uniform set is
//     frozen (escalations.md SC-14 gate) and its fog colours belong to the atmosphere
//     chain D2 owns, so this module owns only the curves and the switches.
//   - the legacy Fog() wrapper is dropped: Steadfast kept it only while migrating, and
//     Astra builds the sky-colour add at the call site from skyFogStrength.
//   - FOG_DENSITY / UNDERWATER_FOG_DENSITY / SKY_FOG_STRENGTH are wired in here; they
//     are percentages, so every use site scales by 0.01.
//   - air perspective and biome tint are Astra additions on top of FogV2
//     (design.md 4.2; Refrax is the stated inspiration, the implementation is ours).
//
// Uniforms: atmosphereFogCoefficient, borderFogDistance, isEyeInWater, blindness,
//           worldSunVector, sunrise, moonrise (lib/uniforms.glsl)
// Consts:   FOG_DENSITY, SKY_FOG_STRENGTH, UNDERWATER_FOG_DENSITY, BORDER_FOG,
//           CAVE_FOG, AIR_PERSPECTIVE, BIOME_TINT, BIOME_TINT_STRENGTH (lib/settings.glsl)
// Owner: B2. Consumers: program/lit.fsh (E1), program/sky.fsh (D2), program/deferred.fsh (E2).

// Everything this module needs to know about colour, supplied by the atmosphere /
// lighting owners. Keeping it out of the uniform block is deliberate: fog colour is
// palette data, and palette data is C1/D2's job (design.md 4.2).
struct FogParams {
	vec3  caveColor;        // colour of fog where skylight ~= 0 (caves, deep night)
	vec3  underwaterColor;  // underwater fog colour (C2 picks it from WATER_CHARACTER)
	float eyeSkylight;      // smoothed skylight at the camera, 0..1
};

// FogV2 (Steadfast): atmospheric pow(d,3) fog + render-distance border fog + a
// skylight-driven switch into cave fog, with blindness / water / lava overrides.
//
// Returns vec4(fogColor, fogFactor). The caller does
//   mix(sceneColor, fogColor + skyColor * skyFogStrength, fogFactor)
// — returning the sky contribution separately is what lets the caller skip the
// expensive sky evaluation entirely when skyFogStrength is ~0 (design.md 5 early-out).
//
// Six covered situations (regression checklist item 8): clear air, render-distance
// border, cave, blindness, lava, underwater.
//
//   fragDistance        distance used for the atmospheric pow(d,3) term
//   borderFragDistance  distance used for the border ramp; differs from fragDistance
//                       only for Voxy terrain (C5)
//   skyLightStrength    fragment skylight, 0..1 where 1 is light level 15
vec4 fog_v2(
	out float skyFogStrength,
	FogParams params,
	float fragDistance,
	float borderFragDistance,
	float skyLightStrength
) {
	#ifdef BORDER_FOG
		float borderFog = smoothstep(
			borderFogDistance - 8.0,
			borderFogDistance,
			borderFragDistance);
	#else
		float borderFog = 0.0;
	#endif

	// The pow(d,3) coefficient is precomputed on the CPU including the render-distance
	// normalisation (design.md 5); FOG_DENSITY is the user's percentage on top.
	float atmosphereFog = pow(fragDistance, 3.0)
		* atmosphereFogCoefficient
		* (FOG_DENSITY * 0.01);

	// Caves (and unlit interiors) switch to a dedicated colour. Taking the max of the
	// fragment and camera skylight means a lit pocket inside a cave does not flip fog
	// colour as the camera moves through it.
	#ifdef CAVE_FOG
		float caveFogTransition = smoothstep(
			0.0,
			0.25,
			max(skyLightStrength, params.eyeSkylight));
	#else
		float caveFogTransition = 1.0;
	#endif

	skyFogStrength = caveFogTransition * (SKY_FOG_STRENGTH * 0.01);
	vec3 fogColor = (1.0 - caveFogTransition) * params.caveColor;

	if (blindness > 0.0001) {
		// Blindness is just a very strong, very black fog.
		atmosphereFog = max(
			0.85,
			1.0 - exp(-pow(fragDistance * blindness * 0.5, 2.0)));
		fogColor = vec3(0.0);
		skyFogStrength = 0.0;
	} else if (isEyeInWater == 1) {
		// Underwater fog is far denser than air; this is roughly exp2 fog from the
		// fixed-function pipeline. No sky colour: you cannot see the sky through it.
		atmosphereFog = 1.0 - exp(
			-pow(fragDistance * 0.02 * (UNDERWATER_FOG_DENSITY * 0.01), 2.0));
		fogColor = params.underwaterColor;
		skyFogStrength = 0.0;
	} else if (isEyeInWater == 2) {
		// Lava: same exponential shape, but with a high floor, since you are not meant
		// to see much while submerged in it.
		atmosphereFog = max(0.85, 1.0 - exp(-pow(fragDistance * 0.5, 2.0)));
		fogColor = vec3(1.0, 0.05, 0.0);
		skyFogStrength = 0.0;
	}

	float fogFactor = min(borderFog + atmosphereFog, 1.0);

	if (skyFogStrength > 0.0) {
		// Zero out very weak fog so the caller's sky-colour path (and its cost)
		// disappears for nearby terrain. Skipped for the dense special cases above,
		// where a low value is real fog rather than numerical noise.
		fogFactor *= smoothstep(0.01, 0.015, fogFactor);
	}

	return vec4(fogColor, fogFactor);
}

// Air perspective (design.md 4.2): the fog picks up the light colour as the view
// direction swings towards the sun, which is what gives the horizon its dawn/dusk
// gradient. pow 4 keeps the effect around the sun instead of tinting the whole sky.
//
// viewDir is a NORMALISED world-space direction; sunGlowColor comes from the
// atmosphere owner (D2) and is expected to already carry the sunrise intensity.
#ifdef AIR_PERSPECTIVE
vec3 fog_air_perspective(vec3 fogColor, vec3 viewDir, vec3 sunGlowColor) {
	float sunAmount = max(dot(viewDir, worldSunVector), 0.0);
	float horizon = max(sunrise, moonrise);
	return fogColor + sunGlowColor * (pow(sunAmount, 4.0) * horizon);
}
#endif

// Biome tint (design.md 4.2): a gentle pull of the fog colour towards the biome's
// palette. Temperature/humidity are already temporally smoothed on the CPU (Z3), so
// the caller only has to hand over the resolved colour.
#ifdef BIOME_TINT
vec3 fog_biome_tint(vec3 fogColor, vec3 biomeFogColor) {
	return mix(fogColor, biomeFogColor, BIOME_TINT_STRENGTH * 0.01);
}
#endif

#endif
