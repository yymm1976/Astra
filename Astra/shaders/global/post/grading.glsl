#ifndef ASTRA_GLOBAL_POST_GRADING_GLSL
#define ASTRA_GLOBAL_POST_GRADING_GLSL

#include "/lib/encoding.glsl"
#include "/lib/dither.glsl"
#include "/lib/tonemap.glsl"

// ============================================================
//  Astra v1 - global/post/grading.glsl
//  The style layer (design.md 4.4): exposure, colour temperature, vibrance,
//  saturation, contrast, the optional vignette, and the IGN output dither.
//  Design 4.4 makes this file the single place the pack's LOOK is tuned, so any
//  constant that decides what Astra looks like belongs here, not in a pass.
//  Owner: C6.  Consumer: program/final.fsh (E1 wires it).
//
//  Requires by program order: /lib/settings.glsl (POST block) plus the dimension
//  macro the top-level shell injects (DIMENSION_NETHER / DIMENSION_END).
// ============================================================
//
// --- INTERFACE CONTRACT: four slots, and the space each one runs in ---------
//
//   vec3 apply_exposure(vec3 linearHDR)
//       LINEAR / scene-referred. Must run BEFORE the tonemap: exposure is a
//       sensor gain, and applying it after the tone curve changes which
//       highlights get compressed instead of how bright the scene is.
//
//   vec3 apply_tonemap(vec3 hdr)                  [lib/tonemap.glsl, not here]
//
//   vec3 apply_grading(vec3 displayColor)
//       DISPLAY-referred (gamma-encoded) - see "why display space" below.
//
//   vec3 apply_vignette(vec3 displayColor, vec2 screenUV)
//       DISPLAY space. screenUV is 0..1 (texcoord). The function always exists
//       and returns its input untouched when VIGNETTE is undefined, so the call
//       site needs no #ifdef of its own.
//
//   vec3 apply_output_dither(vec2 screenPos, vec3 displayColor)
//       DISPLAY space, LAST, and deliberately AFTER apply_grading's clamp.
//       screenPos is gl_FragCoord.xy in device pixels, not 0..1.
//
// Full §2.2 final-chain order, therefore:
//   colortex0 -> apply_exposure -> tonemap -> sRGB encode -> apply_grading
//             -> apply_vignette (optional) -> apply_output_dither -> gl_FragData[0]
//
// --- why display space ------------------------------------------------------
// apply_contrast pivots at 0.5, which is middle grey only in display space (0.5
// linear reads as 0.735 on screen), and the factory numbers below are Refrax
// values, which Refrax calibrates on display-referred pixels (its grade pass ends
// `colorGrade(applyTonemap(hdr))`, and its applyTonemap returns display space).
// Grading in linear space would make those three sliders mean something else.
//
// SC-16 is resolved: apply_tonemap returns display-linear RGB for every operator.
// AgX's internal power is its output linearisation, not a second sRGB transfer.
// final performs exactly one srgb_encode before display-space grading.
// ============================================================

// ------------------------------------------------------------
// PRESET - the look of the pack in one block.
// Factory values began with Refrax v1.3.1's calibration and were adjusted after
// the first two Iris visual rounds. Matching Refrax still needs the user's
// visual verdict; source-level adjustments do not settle the final look.
//
// All three GUI profiles currently ship IDENTICAL grading values, and they do it
// in shaders.properties (profile.PERFORMANCE/BALANCED/ULTRA set the slider macros
// directly) - not by interpolating anything in this file. Per-profile looks are a
// shaders.properties change; what follows is only the neutral default.
// ------------------------------------------------------------

const float GRADING_EXPOSURE_NETHER = 1.05;
// Multiplied ON TOP of the user's EXPOSURE slider, so the user can still dial
// past it. The nether is a pure-ambient dimension (C3's nether_lighting has no
// sun term), so a curve calibrated on daylight reads dark there.
const float GRADING_EXPOSURE_END = 1.05;
// Same reason, same amount: the End's light is faint skylight plus void fog.

const vec3 GRADING_TINT_WARM = vec3(1.055, 1.0, 0.945);
const vec3 GRADING_TINT_COOL = vec3(0.945, 1.0, 1.055);
// A symmetric pair on purpose: a tint that only raised red would also raise
// luminance and read as an exposure change rather than a temperature change.
const float GRADING_TEMPERATURE_FULL_SCALE = 50.0;
// COLOR_TEMPERATURE spans -50..50; this is the value that means "full tint", i.e.
// either end of the slider applies GRADING_TINT_* at weight 1.0.

const float GRADING_BLUE_GUARD = 3.0;
// How fast a blue-dominant pixel resists the temperature tint: saturates once
// blue leads the strongest other channel by 1/GRADING_BLUE_GUARD. Without it a
// warm tint washes a clear sky and snow towards grey, and a cool tint does the
// same to lava and netherrack. Set 0.0 to disable the guard (user always wins).
// UNVERIFIED: Refrax uses slope 3.5 for the equivalent term.

const float GRADING_DITHER_STRENGTH = 1.0 / 128.0;
// Total span is 2 LSB of the 8-bit backbuffer (1/128 = 0.0078 vs 1 LSB = 1/255),
// i.e. plus or minus one LSB around the exact value. Design 2.4: with no AA pass,
// banding has to be broken here or nowhere.

#ifdef VIGNETTE
const float VIGNETTE_STRENGTH = 0.55;
const float VIGNETTE_FALLOFF = 2.0;
// At these two values corners darken about 15% and edge midpoints about 7%.
#endif

// ------------------------------------------------------------
// 1. Exposure - linear, pre-tonemap
// ------------------------------------------------------------
float grading_dimension_exposure() {
	#if defined DIMENSION_NETHER
		return GRADING_EXPOSURE_NETHER;
	#elif defined DIMENSION_END
		return GRADING_EXPOSURE_END;
	#else
		return 1.0;
	#endif
}

vec3 apply_exposure(vec3 linearHDR) {
	return linearHDR * (EXPOSURE * 0.01 * grading_dimension_exposure());
}

// ------------------------------------------------------------
// 2. Colour temperature - display space
// ------------------------------------------------------------
vec3 apply_color_temperature(vec3 color) {
	#if COLOR_TEMPERATURE == 0
		// Compiled out at the factory default, so the guard costs nothing for
		// anyone who never touches the slider.
		return color;
	#else
		float weight = clamp(abs(float(COLOR_TEMPERATURE)) / GRADING_TEMPERATURE_FULL_SCALE, 0.0, 1.0);
		vec3 tint = COLOR_TEMPERATURE > 0 ? GRADING_TINT_WARM : GRADING_TINT_COOL;
		float guard = clamp((color.b - max(color.r, color.g)) * GRADING_BLUE_GUARD, 0.0, 1.0);
		return color * mix(vec3(1.0), tint, weight * (1.0 - guard));
	#endif
}

// ------------------------------------------------------------
// 3. Grading - display space: temperature -> vibrance -> saturation -> contrast
//
// Vibrance before saturation is deliberate and matches Mellow's final chain:
// vibrance is a relative correction that protects already-saturated pixels, so
// running full saturation first would push channels into the range vibrance then
// tries to protect, and the two sliders would fight.
// ------------------------------------------------------------
vec3 apply_grading(vec3 displayColor) {
	vec3 color = apply_color_temperature(displayColor);
	color = apply_vibrance(color, VIBRANCE * 0.01);
	color = apply_saturation(color, SATURATION * 0.01);
	color = apply_contrast(color, CONTRAST * 0.01);
	return clamp(color, vec3(0.0), vec3(1.0));
}

// ------------------------------------------------------------
// 4. Vignette - display space, optional, off by default (design 4.4)
// Exists as a no-op when the macro is undefined so E1's call site stays
// unconditional.
// ------------------------------------------------------------
vec3 apply_vignette(vec3 displayColor, vec2 screenUV) {
	#if defined DIMENSION_END
		vec2 offset=(screenUV-0.5)*2.0;
		float falloff=clamp(dot(offset,offset)*0.5,0.0,1.0);
		return displayColor*(1.0-0.08*falloff);
	#elif defined VIGNETTE
		vec2 offset = screenUV - 0.5;
		// Falloff here is the exponent itself, not Mellow's "2 - falloff"
		// inversion, so larger means tighter. Distance is measured in UV space,
		// which stretches the ellipse with the aspect ratio - acceptable for an
		// off-by-default effect, and it keeps this slot free of a viewSize
		// uniform (the Z3 uniform set is frozen, SC-14).
		float falloff = pow(length(offset) * VIGNETTE_STRENGTH, VIGNETTE_FALLOFF);
		return displayColor * (1.0 - min(falloff, 1.0));
	#else
		return displayColor;
	#endif
}

// ------------------------------------------------------------
// 5. Output dither - display space, last
// Runs after apply_grading's clamp on purpose: pixels pinned at black or white
// still need a per-pixel offset, or they collapse into flat bands right at the
// clip edge. The overshoot is absorbed by the 8-bit write.
// ------------------------------------------------------------
vec3 apply_output_dither(vec2 screenPos, vec3 displayColor) {
	#if defined DIMENSION_END
		// Half an 8-bit code each way, attenuated at black to preserve the void.
		float darkGate=smoothstep(0.0,0.025,max(displayColor.r,max(displayColor.g,displayColor.b)));
		return displayColor+(dither(screenPos)-0.5)*(1.0/255.0)*darkGate;
	#elif defined DITHERING
		// Static IGN: lib/dither.glsl is fixed to animate = false because Astra has
		// no TAA to average temporal noise (design 2.4).
		return displayColor + (dither(screenPos) - 0.5) * GRADING_DITHER_STRENGTH;
	#else
		return displayColor;
	#endif
}

// ------------------------------------------------------------
// PROVENANCE
//
// Idea-level, Mellow v3.4 (MIT) by TheCMK - program/final.fsh:56-76 is where the
// chain ORDER used here comes from (encode, then vibrance, saturation, contrast,
// vignette, then a static IGN offset of the same magnitude), and the shape of the
// vignette formula. The grading primitives are NOT re-ported: they are Astra's
// existing Mellow port in lib/tonemap.glsl. License: MIT - see THIRD-PARTY.md.
//
// PROVENANCE: adapted from Refrax v1.3.1 (proprietary) - IDEA ONLY, no code and
//   no formula transplanted: a per-dimension exposure multiplier that stands
//   outside the user's exposure slider (its sceneExposure / DIMENSION_EXPOSURE),
//   and a blue-dominance guard on a warmth tint (its colorGrade blueDom term).
//   Both rewritten here against Astra's own macros, constants and naming. Astra
//   also drops Refrax's built-in auto-warmth, which design 4.4 does not ask for,
//   and moves the guard onto the user's temperature slider instead. Registered in
//   THIRD-PARTY.md per design.md 9.2.
// ------------------------------------------------------------

#endif // ASTRA_GLOBAL_POST_GRADING_GLSL
