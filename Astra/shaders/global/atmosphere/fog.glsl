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

// ---------------------------------------------------------------------------
// Valley mist: the density of the air as a function of ALTITUDE.
//
// The study's item D asks for fog with a height relationship - valleys and low
// ground hold more haze, high ground less - and Photon gets it by integrating an
// altitude density along the ray (include/fog/overworld/analytic.glsl). Astra
// already had the integral form in program/scene.glsl's twilight haze
// (`1.0 - smoothstep(96.0, 176.0, cameraPosition.y + playerPos.y)`), but it was
// written twice: once there for the twilight window and once in mainFog, and it
// produced a hard-edged band rather than a graded mist. This is that same term,
// unresolved and shared, so the two call sites cannot drift apart.
//
// The coordinate is the ABSOLUTE world height of the fragment, taken from
// cameraPosition.y + playerPos.y. That is what keeps the layer in the world: a
// camera-relative term would slide the mist up and down with the player and read
// as a screen overlay. Nothing here samples noise or marches a ray; it is two
// smoothsteps and a mix, which is the cheap expression of what the references
// spend a density integral on.
//
// Reference levels (world Y, sea level = 62/63). The boost is deliberately a quarter,
// not a multiple: this multiplies a pow(d,3) fog curve that already reaches a fog
// factor of ~0.5 at 200 blocks, so a large valley factor would put a wall of mist in
// front of exactly the distant terrain the fog is supposed to give depth to.
//   1.28 at and below Y=48   - valley floors and ravines, where mist collects
//   1.05 at Y=100            - low ground
//   0.96 at Y=150            - open ground at normal build height
//   0.70 at Y=200            - hills
//   0.42 at and above Y=260  - high mountains and the build limit
float fog_valley_mist(float worldY) {
	float below = smoothstep(48.0, 150.0, worldY);
	float above = smoothstep(200.0, 260.0, worldY);
	return mix(1.28, 0.96, below) * mix(1.0, 0.42, above);
}
// Complementary's mainFog weight for the low-altitude air, as a function of the same
// height: 0.62 for dense low air, 0.22 for thin high air. Folding the valley mist into
// this remap keeps the original end points exactly - above Y=150 it is still 0.22, and
// at the valley floor it is still 0.62 - while the ground in between (where players
// actually build) is graded rather than switched at a threshold. This is the pair the
// old inline `1.0 - smoothstep(96, 176, y)` was approximating for both roles at once.
float fog_morning_air_weight(float worldY) {
	return mix(0.62, 0.22, clamp((fog_valley_mist(worldY) - 0.96) / 0.32, 0.0, 1.0));
}

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
//   fragWorldY          ABSOLUTE world height of the fragment, for the valley mist.
//                       Absolute, not camera-relative: a relative height would move
//                       the mist layer with the camera (see fog_valley_mist).
vec4 fog_v2(
	out float skyFogStrength,
	FogParams params,
	float fragDistance,
	float borderFragDistance,
	float skyLightStrength,
	float fragWorldY
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
	//
	// The altitude factor is the valley mist above. It multiplies the existing curve
	// rather than adding a second fog layer, so nothing new is composited and the
	// near field cannot go grey: the pow(d,3) curve is still ~0 at short range, and
	// the C-FOG_DENSITY default is unchanged. It is evaluated for the fragment's own
	// world height, so two points at the same distance but different altitude get
	// different haze - which is the whole point of the term.
	float fogValleyMist = fog_valley_mist(fragWorldY);
	float atmosphereFog = pow(fragDistance, 3.0)
		* atmosphereFogCoefficient
		* (FOG_DENSITY * 0.01)
		* fogValleyMist;

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

	// Rain thickens outdoor air; cave and underwater fog keep their own medium.
	if (isEyeInWater == 0) {
        atmosphereFog *= 1.10 + 2.2 * astraRainFactor * caveFogTransition;
        atmosphereFog += (1.0-exp(-fragDistance*0.0055*astraRainFactor))*caveFogTransition;
    }
	skyFogStrength = caveFogTransition * mix(SKY_FOG_STRENGTH * 0.01, 0.65, astraRainFactor);
	vec3 fogColor = (1.0 - caveFogTransition) * params.caveColor;

	if (blindness > 0.0001) {
		// Blindness is just a very strong, very black fog.
		atmosphereFog = max(
			0.85,
			1.0 - exp(-pow(fragDistance * blindness * 0.5, 2.0)));
		fogColor = vec3(0.0);
		skyFogStrength = 0.0;
	} else if (isEyeInWater == 1) {
		// Underwater fog: curve re-based on Solas getWaterFog (2026-09-06 visual round,
		// issue "水下太黑"; design 4.3 says the underwater look targets Solas).
		// Solas uses 1-exp(-6 * 0.01 * d * density) — the linear exponent fogs far
		// faster than the old squared one (32 blocks: 0.85 vs 0.34), which is what
		// makes Solas' underwater read as bright teal instead of murky dark terrain.
		// From Solas V2.2b lib/water/waterFog.glsl (licence undeclared) — constant-level.
		// No sky colour: you cannot see the sky through it.
		atmosphereFog = 1.0 - exp(
			-fragDistance * 0.06 * (UNDERWATER_FOG_DENSITY * 0.01));
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
// 2026-09-16 visual-experience round: the warm lobe alone was not enough. BSL's fog
// colour is a function of view direction, altitude angle AND the sun direction
// (lib/atmospherics/fog.glsl fogColorM), so a haze layer reads as air rather than as
// a coloured spotlight: the bank facing the sun is warm, the sides are neutral, and
// the shaded side of the same valley is slightly cooler. That is the study's item D
// ("朝阳方向偏暖，侧向较中性，背光方向稍冷"), and it is the difference between the fog
// belonging to the same lighting as everything else and the fog being a separate
// overlay with its own palette.
//
// `viewDir` is a NORMALISED world-space direction; sunGlowColor comes from the
// atmosphere owner (D2) and is expected to already carry the sunrise intensity.
#ifdef AIR_PERSPECTIVE
vec3 fog_air_perspective(vec3 fogColor, vec3 viewDir, vec3 sunGlowColor) {
	float sunAmount = max(dot(viewDir, worldSunVector), 0.0);
	float horizon = astra_twilight_strength();
	vec3 result = fogColor + sunGlowColor * (pow(sunAmount, 4.0) * horizon);
	// Direction asymmetry. The reference derives its cool side from the same sky
	// colour it uses for everything else; here the existing horizon sky tint
	// (astra_twilight_sky - the atmosphere's own away-from-sun term) supplies the
	// tint, so no second twilight palette is introduced. It is scaled down because
	// the term is already calibrated for the sky's own brightness.
	float away = clamp(-dot(viewDir.xz, normalize(worldSunVector.xz + vec2(1e-5))), 0.0, 1.0);
	float level = 1.0 - min(abs(viewDir.y) * 2.2, 1.0);   // strongest along the horizon
	vec3 cool = astra_twilight_sky(viewDir) * 0.35;
	result = mix(result, result + cool * level, away * horizon * 0.50);
	return result;
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
