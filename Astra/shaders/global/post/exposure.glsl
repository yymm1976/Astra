#ifndef ASTRA_GLOBAL_POST_EXPOSURE_GLSL
#define ASTRA_GLOBAL_POST_EXPOSURE_GLSL

#include "/lib/encoding.glsl"
#include "/global/water/medium_state.glsl"

// ============================================================
//  Astra v1 - global/post/exposure.glsl
//  Auto-exposure: a bounded scene gain measured from the assembled frame, with a
//  one-texel history that adapts over time (design.md SC-41, survey 6 P0-3).
//  Owner: C6.  Consumers: program/exposure.fsh (writes the history) and
//  global/post/grading.glsl -> program/final.fsh (reads it).
//
//  Both sides live in this one file on purpose: the format of the history texel is
//  the whole contract between the two programs, so there is exactly one place that
//  knows how the gain is stored.
//
//  Requires: lib/uniforms.glsl (isEyeInWater) and a colortex0 holding the assembled
//  linear HDR scene. Every number here is calibrated on Astra's own scene scale -
//  the reference packs' keys are not transferable, because their radiance units are.
// ============================================================

// The history texel. colortex10 is a 1x1 buffer (shaders.properties size.buffer), so
// the metering pass reads and writes the same texel every frame; global/water/
// medium_state.glsl already relies on that for colortex6.
uniform sampler2D colortex10;
// Retain the previous frame and enough precision for small adaptation steps.
// An RGBA8 history rounds those steps away long before the target is reached.
#ifndef RGBA32F
const int RGBA32F = 0;
#endif
const int colortex10Format = RGBA32F;
const bool colortex10Clear = false;
const vec4 colortex10ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

const int   AE_GRID           = 8;
// 8x8 = 64 taps of the assembled frame. Not a full-frame read: a screen-space gain has
// to be one number per frame, and 64 taps already averages away the difference between
// two neighbouring blocks.
const float AE_WEIGHT_FALLOFF = 2.1;
// Gaussian-ish centre weight, chosen so a corner tap weighs exp(-0.5 * 2.1) = 0.35 of
// the centre tap: what the player is aiming at matters about three times as much as
// what is at the edge of the screen, and the frame still does not ignore the sky.
const float AE_KEY            = 0.18;
// Middle grey on Astra's scale, where apply_exposure's factory value is 1.0 and the
// tonemap reads 1.0 as "the white of the scene". UNVERIFIED: needs an in-game check
// that an ordinary daylight frame settles near gain 1.0 (qa/regression-checklist.md).
const float AE_MIN_GAIN       = 0.60;
const float AE_MAX_GAIN       = 2.20;
// The bound is what makes this safe to expose at all: the gain can never take the
// picture further than 0.73 stops down or 1.14 stops up from the user's slider.
const float AE_CLIP           = 4.0;
// Per-tap ceiling before the log. One lava block or the sun's disc is not the scene,
// and without this clamp a single pixel in the 64 can push the whole frame down.
const float AE_FLOOR          = 1e-4;
const float AE_RATE_FAST      = 2.5;
const float AE_RATE_SLOW      = 0.5;
// Time constants, not per-frame weights: 1/2.5 = 0.4 s while the picture gets darker,
// 1/0.5 = 2 s while it gets brighter. The asymmetry is deliberate in that direction
// because the two cases are not equally bad - a frame that stays too bright is a
// washed-out screen the player is squinting at, while a frame that resolves slowly out
// of darkness reads as eyes adjusting, which is the effect worth having.
const float AE_LOG_MIN        = -0.73697;
const float AE_LOG_SPAN       = 1.87444;
const float AE_LOG_SNAP       = 0.00735;
// log2(AE_MIN_GAIN) and log2(AE_MAX_GAIN) - log2(AE_MIN_GAIN), written out as numbers
// for the bounded log encoding. Snap within 0.51% of the target; the float history
// preserves per-frame increments until this window is reached.

float astra_ae_encode(float gain) {
	return clamp((log2(clamp(gain, AE_MIN_GAIN, AE_MAX_GAIN)) - AE_LOG_MIN) / AE_LOG_SPAN,
	             0.0, 1.0);
}

float astra_ae_decode(float code) {
	return exp2(AE_LOG_MIN + clamp(code, 0.0, 1.0) * AE_LOG_SPAN);
}

// Geometric mean of the tap luminances, i.e. their average taken in the log domain.
// A mean of light values would be dominated by the brightest tap in the lattice -
// the log domain is where exposure arithmetic belongs, which is also why the tap is
// clamped rather than discarded when it is too bright.
float astra_ae_meter(sampler2D scene) {
	ivec2 size = textureSize(scene, 0);
	float logSum = 0.0;
	float weightSum = 0.0;
	for (int i = 0; i < AE_GRID * AE_GRID; ++i) {
		ivec2 cell = ivec2(i % AE_GRID, i / AE_GRID);
		ivec2 pos = clamp((cell * 2 + 1) * size / (2 * AE_GRID), ivec2(0), size - 1);
		vec3 color = max(texelFetch(scene, pos, 0).rgb, vec3(0.0));
		float lum = clamp(get_luminance(color), AE_FLOOR, AE_CLIP);
		vec2 d = (vec2(cell) + 0.5) / float(AE_GRID) - 0.5;
		float weight = exp(-dot(d, d) * AE_WEIGHT_FALLOFF);
		logSum += log2(lum) * weight;
		weightSum += weight;
	}
	float avgLum = exp2(logSum / max(weightSum, 1e-4));
	// A NaN anywhere in the tapped pixels reaches here. Neutral beats a plausible
	// number that happens to be garbage: the display chain then equals the manual slider.
	if (isnan(avgLum)) return 1.0;
	return clamp(AE_KEY / max(avgLum, AE_FLOOR), AE_MIN_GAIN, AE_MAX_GAIN);
}

// One frame of adaptation, returned ready to store. The caller is the only fragment of
// a 1x1 pass, so "per frame" and "per invocation" are the same thing here.
vec4 astra_ae_frame(sampler2D scene, float deltaTime) {

	// .a is a validity flag, not a spare channel. Without it a never-written texel
	// would decode as AE_MIN_GAIN and the first frame of every world load would start
	// by darkening the picture.
	vec4 history = texelFetch(colortex10, ivec2(0), 0);
    // Bodies of water keep their own display curve. Thin sheets use the air
    // curve, so their exposure must continue adapting with the surrounding scene.
    if (isEyeInWater != 0 && !water_is_thin_sheet()) {
        float code = history.a > 0.5 && !isnan(history.r)
            ? history.r : astra_ae_encode(1.0);
        return vec4(code, 0.0, 0.0, 1.0);
    }
    float target = astra_ae_meter(scene);
	float current = history.a > 0.5 && astraTimeDiscontinuity == 0
        ? astra_ae_decode(history.r) : target;
	if (isnan(current)) current = target;

	// Air and thin sheets share the same adaptive display path.
	float currentLog = log2(max(current, AE_FLOOR));
	float targetLog = log2(max(target, AE_FLOOR));
	if (abs(targetLog - currentLog) <= AE_LOG_SNAP) {
		// Finish imperceptibly small changes instead of leaving an endless tail.
		current = target;
	} else {
		float rate = target < current ? AE_RATE_FAST : AE_RATE_SLOW;
		// frameTime is seconds (bliss-shader / iterationT calibrate it as a shutter
		// time), so the rate is per second and the response is frame-rate neutral.
		float blend = clamp(1.0 - exp(-max(deltaTime, 1e-4) * rate), 0.0, 1.0);
		// Exponential blend in the log domain preserves perceptual adaptation.
		current = exp2(mix(currentLog, targetLog, blend));
	}
	return vec4(astra_ae_encode(current), 0.0, 0.0, 1.0);
}

// The consumed form: a scene-referred multiplier, neutral whenever there is no usable
// history, which is also the state of every dimension whose metering pass is disabled.
float astra_ae_gain() {
	vec4 history = texelFetch(colortex10, ivec2(0), 0);
	if (history.a < 0.5 || isnan(history.r)) return 1.0;
	return astra_ae_decode(history.r);
}

// ------------------------------------------------------------
// PROVENANCE
//
// PROVENANCE: idea-level, Refrax v1.3.1 (proprietary) - IDEA ONLY, no code and no
//   formula transplanted: the shape of a screen-space auto-exposure (meter a small
//   weighted grid of the assembled frame, keep the running value in a fixed texel of
//   a low-res buffer, clamp the gain to a bounded interval, blend it with different
//   rates in the two directions, and leave dimensions with a hand-set exposure out of
//   it entirely). Everything below the shape is Astra's own: the geometric mean is
//   weighted by a centre falloff Astra chooses, the history is a validity-flagged
//   log2 code instead of a raw linear float (which fixes both the "no history yet
//   reads as the darkest setting" and the "gain bottoming out reads as invalid"
//   cases), the blend runs in the log domain, and the water case freezes the history
//   instead of metering through it. Registered in THIRD-PARTY.md per design.md 9.2.
//
// The three robustness properties this file is written to are the ones the survey's
// Photon citation lists (design.md SC-41): clamp highlights instead of trusting a
// plain mean, guard against NaN, and use asymmetric rise/fall rates.
// ------------------------------------------------------------

#endif // ASTRA_GLOBAL_POST_EXPOSURE_GLSL
