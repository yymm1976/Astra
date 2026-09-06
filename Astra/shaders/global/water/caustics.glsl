#ifndef ASTRA_GLOBAL_WATER_CAUSTICS_GLSL
#define ASTRA_GLOBAL_WATER_CAUSTICS_GLSL

// Astra v1 — global/water/caustics.glsl
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot
//   source: _analysis/Steadfast-0.8.0/shaders/environment/water/caustics_noise.glsl
//           + caustics_noise_waves.glsl (the CAUSTICS[6] table) + lib/valueNoise.glsl
// This file is a derivative of Steadfast and is licensed under the GNU General
// Public License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
// _analysis/Steadfast-0.8.0/LICENSE.md. Redistribution is permitted only under that
// license including Steadfast's Section 7 additional terms.
// Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Six-layer crest caustics (design.md 4.3: shadow map 中编码的水面高度 → 反推水深 →
// 6 层 crest 噪声焦散). The crest pattern is Steadfast's verbatim; Astra adds the
// water-depth decode + gating that turns the raw pattern into a contribution on a
// specific submerged fragment.
//
// Adaptations for Astra (design.md 3.2 / 4.3 / 5):
//   - Functions renamed to snake_case; the const data tables (CAUSTICS / causticsStretch /
//     causticsScroll / causticsExponents / causticsLogMagnitude / causticsTotalWeight) keep
//     Steadfast's camelCase because they are data, and keeping them verbatim minimises
//     transcription risk in an expression-level GPL port. CausticNoiseWave stays PascalCase
//     (design.md 3.2 type naming).
//   - NUM_CAUSTICS is fixed at 6: Astra exposes WATER_CAUSTICS as an on/off bool, not a
//     wave-count slider, so Steadfast's `#if NUM_CAUSTICS > n` ladders collapse to the full
//     six-term sums (dead branches removed).
//   - Value noise is INLINED here rather than added to lib/noise.glsl: lib/noise.glsl is a
//     Mellow (MIT) port owned elsewhere, and folding a Steadfast (GPL) function into it would
//     muddy that file's single-source provenance and risk its existing consumers. Only the
//     single-channel smooth_noise_2d that caustics uses is kept; the x3 / channel-weighted
//     overloads are dropped. `fade` is renamed caustics_fade so it cannot collide with any
//     other fade() in lit.fsh's shared compilation unit.
//   - Steadfast's valueNoise declares `const int noiseTextureResolution = 64` and
//     `uniform sampler2D noisetex`; Astra already provides BOTH (noisetex frozen in
//     lib/uniforms.glsl, noiseTextureResolution = 256 in lib/settings.glsl ENGINE KNOBS), so
//     neither is redeclared. A value-noise cell is exactly one texel regardless of resolution
//     (integer steps in `at` advance one texel), so 64 -> 256 only lengthens the wrap period
//     (less visible tiling); the wave table's metric tile sizes are resolution-independent and
//     the look is preserved. This is design.md 5's "噪声优先查表（noisetex 硬件双线性）".
//
// Cross-module dependency (B1 — global/lighting/shadowmap.glsl, a SIBLING global):
//   globals may not include globals (SC-10), so water_caustics CONSUMES B1 by program-ordered
//   inclusion: lit.fsh must include /global/lighting/shadowmap.glsl BEFORE this file. From B1
//   it uses decode_water_height(), shadow_map_fade(), and the shadowcolor0 sampler.
//   ⚠ INTERFACE NOTE for E1/E2 (not an architecture change, no new buffer): B1 declares
//   `uniform sampler2D shadowcolor0;` only under `#ifdef COLORED_SHADOWS`, but the water-height
//   read needs that sampler whenever WATER_CAUSTICS is on, independent of colored shadows. The
//   shadow pass always WRITES the height to shadowcolor0.R (B1 header), so only the declaration
//   is gated. E1/E2 must widen B1's guard to `#if defined(COLORED_SHADOWS) || defined(WATER_CAUSTICS)`
//   (or declare the sampler in the includer). C2 does not re-declare it — that would be a second
//   declaration of the same buffer in one unit (redefinition error) and a private buffer opening.
//
// Uniforms: noisetex, cameraPosition, frameTimeCounter (lib/uniforms.glsl); shadowcolor0 (B1).
// Consts:   noiseTextureResolution (ENGINE KNOBS, settings.glsl); WATER_CAUSTICS_DISTANCE /
//           WATER_CAUSTICS_DEPTH (local tuning constants, below).
// Owner: C2. Consumer: E1/E2 (the lit water path applies this to the submerged direct light).
// Requires (NOT included here — program/* guarantees order, design.md 3.2 layer 2/3, matching
//   lib/colors.glsl and global/lighting/diffuse.glsl which likewise include no settings/uniforms):
//     lib/settings.glsl   -> WATER_CAUSTICS, noiseTextureResolution
//     lib/uniforms.glsl   -> noisetex, cameraPosition
//     global/lighting/shadowmap.glsl (B1, sibling) -> decode_water_height, shadow_map_fade, shadowcolor0
//   This file includes no lib/* helper: the value noise is inlined (see provenance note above),
//   and it calls no colors/transforms/distort/noise function. global/* never includes global/*,
//   so B1 arrives by program-ordered inclusion, not by an #include here.

// Caustics are a close-up effect: beyond this many blocks the crest tiles (0.15-6 m) are
// sub-pixel and not worth the shadowcolor0 sample. Well inside shadowDistance (128) and far
// inside the ±1024 water-height encode range, which is why B1's clamp never bites (its header
// references this constant by name). UNVERIFIED tuning default — SC-6 (no Iris instance) blocks
// the visual acceptance that would confirm it; E2/visual pass to retune.
const float WATER_CAUSTICS_DISTANCE = 64.0;
const float WATER_CAUSTICS_FADE_START = 48.0;

// The shortest effective table period is 0.15 * 1.5 = 0.225 blocks. A scalar
// world-space pixel footprint is conservative for every layer direction: begin
// removing the complete field at 0.175 period/pixel and reach zero at the
// two-samples-per-period Nyquist limit. Applying this after the original sum keeps
// resolved amplitudes unchanged and never introduces log(0) * 0 in the crest loop.
const float WATER_CAUSTICS_MIN_PERIOD = 0.225;

// Crests sharpen just under the surface and scatter into nothing a few blocks down, so the
// pattern fades over this depth. UNVERIFIED tuning default (SC-6), same caveat as above.
const float WATER_CAUSTICS_DEPTH = 8.0;

// One wave of the caustics field: a sheared, scrolling value-noise tile (Steadfast struct).
struct CausticNoiseWave {
	vec2  tileSize;     // tile size on X and Y, in meters (blocks)
	float shearAngle;   // vertical shear of the tile grid (radians)
	float speed;        // travel speed toward `heading`, meters/second
	float heading;      // travel direction, radians (unit circle with Z as the circle's Y)
	float weight;       // relative magnitude; normalized by the total weight below
	float exponent;     // sharpens this wave's crest
};

// Convenience for the degree measurements in the table; #undef'd straight after so it does
// not leak into the surface/SSR modules that share this compilation unit.
#define Degrees radians(1.0)

const CausticNoiseWave CAUSTICS[6] = CausticNoiseWave[](
	CausticNoiseWave (
		// Tile 3.0 x 4.0 m; shear 30°; speed 3.0 m/s; heading 243° (-X/-Z).
		// This heading is the exact middle of the two large ripple waves, so the three
		// move together and form the primary wave shape.
		vec2(3.0, 4.0) * (3.0 / 2.0),
		30.0 * Degrees,
		3.0 * (2.0 / 3.0),
		180.0 * Degrees + 63.0 * Degrees,
		0.25,
		6.0
	),
	CausticNoiseWave (
		// Tile 6.0 x 8.0 m (double: very low frequency); shear -30° (opposite of wave 0);
		// speed 12.0 m/s (fast but subtle, breaks up the obvious tiling of the main crest);
		// heading 252° (-X/-Z), same as the first ripple wave.
		vec2(6.0, 8.0) * (3.0 / 2.0),
		-30.0 * Degrees,
		12.0 * (2.0 / 3.0),
		180.0 * Degrees + 72.0 * Degrees,
		0.15,
		6.0
	),
	CausticNoiseWave (
		// Tile 1.5 x 2.0 m; shear 30°; speed 1.5 m/s; heading 252° (-X/-Z).
		vec2(1.5, 2.0) * (3.0 / 2.0),
		30.0 * Degrees,
		1.5 * (2.0 / 3.0),
		180.0 * Degrees + 72.0 * Degrees,
		0.15,
		5.0
	),
	CausticNoiseWave (
		// Tile 1.0 x 1.5 m; shear -36°; speed 3.0 m/s; heading 234° (-X/-Z).
		vec2(1.0, 1.5) * (3.0 / 2.0),
		-36.0 * Degrees,
		3.0 * (2.0 / 3.0),
		180.0 * Degrees + 54.0 * Degrees,
		0.15,
		5.0
	),
	CausticNoiseWave (
		// Tile 0.30 x 0.40 m; shear 45°; speed 1.5 m/s; heading overridden to 243°.
		vec2(0.30, 0.40) * (3.0 / 2.0),
		45.0 * Degrees,
		1.5 * (2.0 / 3.0),
		180.0 * Degrees + 63.0 * Degrees,
		0.15,
		1.25
	),
	CausticNoiseWave (
		// Tile 0.15 x 0.20 m; shear -45°; speed 0.5 m/s; heading overridden to 234°.
		vec2(0.15, 0.20) * (3.0 / 2.0),
		-45.0 * Degrees,
		0.5 * (2.0 / 3.0),
		180.0 * Degrees + 54.0 * Degrees,
		0.15,
		1.25
	)
);

#undef Degrees

// Per-wave inverse tile size + the shear's cross term (Steadfast's derived tables, verbatim).
const vec3 causticsStretch[6] = vec3[](
	vec3(1.0 / CAUSTICS[0].tileSize.x, 1.0 / CAUSTICS[0].tileSize.y,
		(1.0 / tan(CAUSTICS[0].shearAngle)) / CAUSTICS[0].tileSize.x),
	vec3(1.0 / CAUSTICS[1].tileSize.x, 1.0 / CAUSTICS[1].tileSize.y,
		(1.0 / tan(CAUSTICS[1].shearAngle)) / CAUSTICS[1].tileSize.x),
	vec3(1.0 / CAUSTICS[2].tileSize.x, 1.0 / CAUSTICS[2].tileSize.y,
		(1.0 / tan(CAUSTICS[2].shearAngle)) / CAUSTICS[2].tileSize.x),
	vec3(1.0 / CAUSTICS[3].tileSize.x, 1.0 / CAUSTICS[3].tileSize.y,
		(1.0 / tan(CAUSTICS[3].shearAngle)) / CAUSTICS[3].tileSize.x),
	vec3(1.0 / CAUSTICS[4].tileSize.x, 1.0 / CAUSTICS[4].tileSize.y,
		(1.0 / tan(CAUSTICS[4].shearAngle)) / CAUSTICS[4].tileSize.x),
	vec3(1.0 / CAUSTICS[5].tileSize.x, 1.0 / CAUSTICS[5].tileSize.y,
		(1.0 / tan(CAUSTICS[5].shearAngle)) / CAUSTICS[5].tileSize.x));

const vec2 causticsScroll[6] = vec2[](
	-mat2(
		causticsStretch[0].x,
		causticsStretch[0].x / tan(CAUSTICS[0].shearAngle),
		0.0,
		causticsStretch[0].y)
	 * CAUSTICS[0].speed
	 * vec2(cos(CAUSTICS[0].heading), sin(CAUSTICS[0].heading)),
	-mat2(
		causticsStretch[1].x,
		causticsStretch[1].x / tan(CAUSTICS[1].shearAngle),
		0.0,
		causticsStretch[1].y)
	 * CAUSTICS[1].speed
	 * vec2(cos(CAUSTICS[1].heading), sin(CAUSTICS[1].heading)),
	-mat2(
		causticsStretch[2].x,
		causticsStretch[2].x / tan(CAUSTICS[2].shearAngle),
		0.0,
		causticsStretch[2].y)
	 * CAUSTICS[2].speed
	 * vec2(cos(CAUSTICS[2].heading), sin(CAUSTICS[2].heading)),
	-mat2(
		causticsStretch[3].x,
		causticsStretch[3].x / tan(CAUSTICS[3].shearAngle),
		0.0,
		causticsStretch[3].y)
	 * CAUSTICS[3].speed
	 * vec2(cos(CAUSTICS[3].heading), sin(CAUSTICS[3].heading)),
	-mat2(
		causticsStretch[4].x,
		causticsStretch[4].x / tan(CAUSTICS[4].shearAngle),
		0.0,
		causticsStretch[4].y)
	 * CAUSTICS[4].speed
	 * vec2(cos(CAUSTICS[4].heading), sin(CAUSTICS[4].heading)),
	-mat2(
		causticsStretch[5].x,
		causticsStretch[5].x / tan(CAUSTICS[5].shearAngle),
		0.0,
		causticsStretch[5].y)
	 * CAUSTICS[5].speed
	 * vec2(cos(CAUSTICS[5].heading), sin(CAUSTICS[5].heading)));

// Pulled out of the struct because some drivers (Steadfast notes macOS) dislike a struct-field
// access nested with another array access; the intermediate array sidesteps it for free.
const float causticsExponents[6] = float[](
	CAUSTICS[0].exponent,
	CAUSTICS[1].exponent,
	CAUSTICS[2].exponent,
	CAUSTICS[3].exponent,
	CAUSTICS[4].exponent,
	CAUSTICS[5].exponent);

#define NUM_CAUSTICS 6

const float causticsTotalWeight = CAUSTICS[0].weight + CAUSTICS[1].weight + CAUSTICS[2].weight
                                + CAUSTICS[3].weight + CAUSTICS[4].weight + CAUSTICS[5].weight;

// log(weight / totalWeight) per wave, so the weighted sum can be folded into the same
// exp(fma) that raises the crest to its exponent (Steadfast's 3-op trick, see the loop).
const float causticsLogMagnitude[6] = float[](
	log(CAUSTICS[0].weight / causticsTotalWeight),
	log(CAUSTICS[1].weight / causticsTotalWeight),
	log(CAUSTICS[2].weight / causticsTotalWeight),
	log(CAUSTICS[3].weight / causticsTotalWeight),
	log(CAUSTICS[4].weight / causticsTotalWeight),
	log(CAUSTICS[5].weight / causticsTotalWeight));

// Reshapes smooth wave-level transitions into visible crests: most of the area stays flat with
// raised lines at the regular grid transitions. 0.5 - 0.5*cos written as mul -> cos -> fma.
float crest_caustics(float h) {
	const float PI = 3.14159265359;
	return (-0.5 * cos(h * (PI * 2.0))) + 0.5;
}

// --- inlined value noise (Steadfast lib/valueNoise.glsl, single-channel variant) ---

// Perlin fade 6t^5 - 15t^4 + 10t^3. C1-continuous, unlike smoothstep — required because the
// caustics animation would otherwise show crease discontinuities at cell boundaries.
vec2 caustics_fade(vec2 t) {
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

// Coherent value noise on the noisetex hardware bilinear lookup. `at` is in cell space: adding
// 1.0 moves exactly one cell (= one texel). Returns [0, 1].
float smooth_noise_2d(vec2 at) {
	vec2 corner = floor(at);
	vec2 offset = at - corner;            // fract(at) without re-calling floor
	at = caustics_fade(offset) + corner;
	// Cell space -> texel space, offset by half a texel so a cell center maps to the center of
	// 4 texels and a cell corner maps to the center of one (Steadfast's alignment, written as a
	// single fma). noiseTextureResolution is the ENGINE KNOB (256); 1.0/ keeps it float division.
	at = at * (1.0 / noiseTextureResolution) + (0.5 / noiseTextureResolution);
	return texture(noisetex, at).x;
}

// The raw six-layer crest field, evaluated at an absolute world position (Steadfast WaterCaustics).
// Returns roughly [-0.33, ~2.17]: flat areas sit slightly negative, focused crests spike high.
float caustics_pattern(vec3 worldPos, float time, float pixelFootprint) {
	float resolutionFade = 1.0 - smoothstep(
		0.175 * WATER_CAUSTICS_MIN_PERIOD,
		0.5 * WATER_CAUSTICS_MIN_PERIOD,
		max(pixelFootprint, 0.0));
	if (resolutionFade <= 0.0) { return 0.0; }

	// Project the 2D field onto the submerged surface with a fixed y-shear. Projecting along the
	// light like the shadow map does looks bad; this simple shear is, per Steadfast, fine.
	worldPos.xz += vec2(-2.0 / 3.0, 2.0 / 3.0) * worldPos.y;

	// Sine deformation so the field animates like changing refraction rather than a scrolled texture.
	worldPos.xz += 0.15 * sin(worldPos.zx * vec2(0.30, 0.25) + time);

	float caustics = 0.0;
	for (int i = 0; i < NUM_CAUSTICS; i++) {
		vec3 stretch = causticsStretch[i];
		vec2 scroll = causticsScroll[i];

		vec2 stretched = vec2(
			worldPos.x * stretch.x,
			dot(worldPos.xz, stretch.zy));
		vec2 at = time * scroll + stretched;

		float noise = crest_caustics(smooth_noise_2d(at));
		float exponent = causticsExponents[i];

		// C * x^P = e^(P*ln(x) + ln C): the magnitude constant folds into the same fma, so each
		// wave costs log -> fma -> exp. (noise=0 -> log=-inf -> exp=0, no NaN.)
		caustics += exp(exponent * log(noise) + causticsLogMagnitude[i]);
	}

	// Square for intermittency, then map to ~66%-250% brightness.
	return ((caustics * caustics) * (1.5 + 0.33) - 0.33) * resolutionFade;
}

// Depth-gated caustics contribution on one submerged fragment (Astra addition over the pattern).
//   playerPos: camera-relative fragment position (Mellow convention, matches B1/C1).
//   shadowPos: light-space shadow-map UV from B1's shadow_map_position, carried by E1's varying;
//              shadowcolor0 is sampled here to read the encoded water-surface height.
//   time:      frameTimeCounter (frozen uniform); the caller may scale it.
//   pixelFootprint: maximum world-space derivative length, in blocks per pixel.
// Returns the caustics brightness to add to the submerged direct light: 0 where there is no water
// above, no shadow-map coverage, or past WATER_CAUSTICS_DISTANCE.
float water_caustics(vec3 playerPos, vec3 shadowPos, float time, float pixelFootprint) {
	#ifndef WATER_CAUSTICS
		return 0.0;
	#else
		// Caustics live in shadowcolor0, so they are meaningless without shadow-map coverage.
		float coverage = shadow_map_fade(playerPos);
		if (coverage < 0.0001) { return 0.0; }
		float distanceFade = 1.0 - smoothstep(
			WATER_CAUSTICS_FADE_START,
			WATER_CAUSTICS_DISTANCE,
			length(playerPos));
		if (distanceFade <= 0.0) { return 0.0; }

		vec3 worldPos = playerPos + cameraPosition;

		// Water-surface Y from the shadow map's R channel (B1 decode). The WATER_HEIGHT_NONE
		// sentinel decodes to -1024, so "no water above" falls straight through the depth test.
		float waterSurfaceY = decode_water_height(texture(shadowcolor0, shadowPos.xy).r);
		float depth = waterSurfaceY - worldPos.y;
		if (depth <= 0.0) { return 0.0; }   // fragment at/above the surface: no caustics

		float depthFade = 1.0 - smoothstep(0.0, WATER_CAUSTICS_DEPTH, depth);
		return caustics_pattern(worldPos, time, pixelFootprint)
			* depthFade * coverage * distanceFade;
	#endif
}

#endif
