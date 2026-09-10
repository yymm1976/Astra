#ifndef ASTRA_GLOBAL_LIGHTING_WIND_GLSL
#define ASTRA_GLOBAL_LIGHTING_WIND_GLSL

// Astra v1 — global/lighting/wind.glsl
// Reference port (2026-09 terrain-foliage round): the wave shape is transcribed from
// Complementary r5.9 (Reimagined and Unbound are byte-identical for this file).
//   source: _analysis/Complementary r5.9/Reimagined/shaders/lib/materials/
//           materialMethods/wavingBlocks.glsl
//     - wind_wave_shape() <- GetRawWave            (wavingBlocks.glsl:5-16, coefficients verbatim)
//     - wind_wave()       <- GetWave               (wavingBlocks.glsl:18-33)
//     - leaves branch     <- DoWave_Leaves         (wavingBlocks.glsl:52-67)
//     - ground branch     <- DoWave_Foliage        (wavingBlocks.glsl:35-50)
//   reference option defaults: lib/common.glsl:228-230 (WAVING_SPEED 1.00, WAVING_I 1.00,
//   WAVING_I_RAIN_MULT 100).
// License: the ported math is under the "Complementary License Agreement 1.7"
//   (_analysis/Complementary r5.9/Reimagined/License.txt) — proprietary, and NOT the
//   GPLv3 + Section 7 terms this file carried before the 2026-09-10 re-sourcing.
//   Historical provenance: the previous wave shape was an expression-level port of Steadfast
//   0.8.0 (`environment/wind.glsl` WindDisplacement + `program/world/lit.vsh` WaveFoliage, by
//   coderbot). No Steadfast expression survives in this file — the shape, the coefficient set
//   and the amplitude chain are all Complementary r5.9 now — so nothing here is Steadfast
//   derived; the row remains in Astra/THIRD-PARTY.md because this module was Steadfast
//   derived up to that date. The publish gate (design.md 9.3 + escalations.md SC-14) must be
//   re-decided for the Complementary source before any publication — raised in
//   docs/handoffs/terrain-foliage.md.
//
// Port basis — 照抄形状 (copy the shape), not 照抄每方块参数 (per-block parameters):
// the reference waves every block class with its own call-site parameters inside DoWave()
// (wavingBlocks.glsl:110-213). Astra's frozen caller hands this module only the booleans
// isLeaves / isGroundFoliage / topOfFoliage, i.e. two wave shapes: leaves (mat 10009 family
// -> block.properties 10002) and grounded foliage (mat 10005/10021 family -> 10004/10005/10006).
// Both shapes, the shared GetRawWave and the amplitude chain are transcribed verbatim below;
// the per-block extras the Astra slots cannot express are listed under "NOT ported".
//
// Astra-owned design kept (not in the reference, or Astra-specific):
//   - the wave_foliage() caller-bool interface and the topOfFoliage anchor gate. The
//     reference does its per-vertex gating inside DoWave (gl_MultiTexCoord0.t vs
//     mc_midTexCoord.t, wavingBlocks.glsl:121); Astra gates the same way in the callers
//     via at_midBlock.y < 0.0, so this module's job is only the displaced shape.
//   - the rain amplitude factor. The reference rain boost is OFF by default
//     (WAVING_I_RAIN_MULT 100, common.glsl:230); Astra keeps its own Steadfast-era rain
//     response instead — the CPU formula of shaders.properties:222,
//     windStrength = 0.09*(1 + 0.5*rainStrength)/2, normalised to its base value 0.045,
//     i.e. the factor (1.0 + 0.5*rainStrength) inlined below.
//   - WAVING_I maps to WAVING_FOLIAGE_STRENGTH * 0.01. The reference default WAVING_I is
//     1.00 (common.glsl:229) and Astra's slider default is 100, so both agree at 100%.
//
// NOT ported (blocked by the frozen interface or Astra material classes; all recorded in
// docs/handoffs/terrain-foliage.md):
//   - vine reduced amplitude 0.75 (wavingBlocks.glsl:150-152): Astra maps
//     vine/pale_hanging_moss/pale_moss_carpet into the leaves class 10002, so this module
//     cannot see vines.
//   - the NO_WAVING_INDOORS lightmap gate (wavingBlocks.glsl:43-46 and :60-63, default ON
//     in the reference). wave_foliage() has no lightmap parameter and the callers
//     (program/lit.vsh, program/shadow.vsh) are public. The non-gated else branch
//     (wave *= 0.1, :47-49 / :64) is used, which is the reference's behaviour when the
//     option is off (and its Nether override, common.glsl:597).
//   - the inSnowy leaf zeroing (wavingBlocks.glsl:58): Astra has no SNOWY_WORLD.
//   - DO_MORE_FOLIAGE_WAVING per-block extras — torchflower / open eyeblossom ride the
//     generic ground shape (they are in Astra's class 10004), and the firefly bush's
//     distinct wave mix (wavingBlocks.glsl:130-139) cannot be selected from this file.
//   - nether vine voxel-occlusion waveMult (wavingBlocks.glsl:154-171): needs the voxel
//     lighting system the reference gates on COLORED_LIGHTING_INTERNAL > 0.
//
// What the CPU uniforms did before: windStrength / windTheta (lib/uniforms.glsl:26-27,
// defined in shaders.properties:222-233) drove the old Steadfast wind. The reference shape
// needs only a scalar time, so both are now unused in this module; deleting them is a
// public shaders.properties change and was handed to the main task. frameTimeCounter
// (lib/uniforms.glsl:38) is in the frozen uniform set and is delivered identically to the
// terrain and shadow passes, so the leaf casting stays exactly consistent with the
// visible model.
//
// Per-vertex cost: FOUR sines, unchanged in count from the previous implementation. wind_wave_shape()
// is called once per displaced vertex and issues 1 magnitude sine + 3 direction sines; the old
// wind_displacement() issued the same 1 + 3. What changed is the phase basis: the old version fed
// all four from the CPU-precomputed windTheta/windStrength uniforms, while the reference drives the
// three direction sines' cross-coupling (d0/d1/d2) from frameTimeCounter directly — so three
// time-only sines that used to be hoisted onto the CPU once per frame now evaluate per vertex. They
// depend on frameTimeCounter alone (no position term) and could be hoisted again by the main task if
// this ever shows up in a profile. Corrected 2026-09-10: an earlier revision of this header claimed
// "seven sines vs three", which double-counted the phase terms and understated the old cost.
//
// NOTE `frameTimeCounter` is in SECONDS, not ticks: Iris's SystemTimeUniforms accumulates
// delta/1000 per frame and wraps at 3600 (read from the shipped iris-neoforge jar's bytecode,
// 2026-09-10). That is why the reference's `wind = frameTimeCounter * waveSpeed * WAVING_SPEED` can
// be used here unchanged, with the inline 170.0 from wavingBlocks.glsl:38/:55 and WAVING_SPEED =
// 1.00 (common.glsl:228). No ticks->seconds conversion belongs in this file.
//
// Uniforms: frameTimeCounter, rainStrength, cameraPosition (lib/uniforms.glsl)
// Consts:   WAVING_FOLIAGE_STRENGTH (lib/settings.glsl)
// Owner: B3. Consumers: program/lit.vsh (terrain) and program/shadow.vsh (casting) — both
// call this same function with the same classification, which is what keeps leaf shadows
// and leaf models in lockstep.

// GetRawWave, verbatim from wavingBlocks.glsl:5-16. `wind` is the reference's scalar wind
// time (see wind_wave). The magnitude cycles [0, 0.08] with a positional phase; the three
// direction sines carry that magnitude and cross-couple through d0/d1/d2 so the gusts
// whip instead of rotating monotonously.
vec3 wind_wave_shape(vec3 pos, float wind) {
	float magnitude = sin(wind * 0.0027 + pos.x + pos.y) * 0.04 + 0.04;
	float d0 = sin(wind * 0.0127);
	float d1 = sin(wind * 0.0089);
	float d2 = sin(wind * 0.0114);
	vec3 wave;
	wave.x = magnitude * sin(wind*0.0224 + d1 + d2 + pos.x - pos.z + pos.y);
	wave.y = magnitude * sin(wind*0.0015 + d2 + d0 + pos.x);
	wave.z = magnitude * sin(wind*0.0063 + d0 + d1 - pos.x + pos.z + pos.y);

	return wave;
}

// GetWave, verbatim in shape from wavingBlocks.glsl:18-33. The reference builds
// wind = frameTimeCounter * waveSpeed * WAVING_SPEED (:19); WAVING_SPEED defaults to 1.00
// (common.glsl:228) and Astra has no speed option, so the multiplier is 1. The rain
// re-sample block (:22-28) is inert at the reference default WAVING_I_RAIN_MULT = 100, so
// only the intensity line (:30-32) is transcribed — with Astra's own rain factor (see the
// header "Astra-owned design kept").
vec3 wind_wave(vec3 pos, float waveSpeed) {
	float wind = frameTimeCounter * waveSpeed;
	vec3 wave = wind_wave_shape(pos, wind);

	float wavingIntensity = (WAVING_FOLIAGE_STRENGTH * 0.01) * (1.0 + 0.5 * rainStrength);

	return wave * wavingIntensity;
}

// Call-site helper for the foliage vertex stages. E1 passes the classification it decoded
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

		if (isLeaves) {
			// DoWave_Leaves, verbatim from wavingBlocks.glsl:52-67 (waveMult 1.0, :149).
			// The position squeeze slows the spatial phase so a canopy moves in large
			// patches; the component mix then makes leaves sweep sideways (x*4, z*8)
			// more than they bounce (y*3). :58 (inSnowy) and the :60-62 indoor gate are
			// not portable here — see the header. The else branch constant 0.1 (:64) is.
			vec3 leafWorldPos = worldPos * vec3(0.75, 0.375, 0.75);
			vec3 wave = wind_wave(leafWorldPos, 170.0);
			wave *= vec3(4.0, 3.0, 8.0);
			wave *= 0.1;
			playerPos += wave;
		} else {
			// DoWave_Foliage, verbatim from wavingBlocks.glsl:35-50 (waveMult 1.0, :122).
			// Halving worldPos.y first stretches the gust along the column so a plant
			// reads as one unit. wave.y = 0 keeps the base planted. The "+ wave.y * 4.0"
			// term on :41 is transcribed as-is; it is dead because :40 zeroes wave.y one
			// line earlier — the reference itself leaves it there.
			vec3 groundWorldPos = worldPos;
			groundWorldPos.y *= 0.5;
			vec3 wave = wind_wave(groundWorldPos, 170.0);
			wave.x = wave.x * 3.0;
			wave.y = 0.0;
			wave.z = wave.z * 8.0 + wave.y * 4.0;
			wave *= 0.1;
			playerPos += wave;
		}
	}
}

#endif
