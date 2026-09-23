// Astra - program/scattering.fsh (composite2: air/water light scattering)
// colortex1's size is declared once, in shaders.properties under size.buffer.colortex1.
// This pass writes whatever extent Iris gives it and never assumes full resolution.
//
// Stage 1 of the two-stage godrays (design.md 2.2 / 4.4). Stage 2 - smoothing and
// upsample back to full resolution - happens in the final chain and belongs to E1/C6,
// because the pass order and the buffers that final reads are E1's resolution
// (design.md 2.2, tasks-advanced-1.md cooperative rule 2).
//
// Air output contract for stage 2:
//   - colortex1 holds the raw accumulated density in [0, 1], deliberately unscaled so
//     the buffer's full precision is used (Steadfast's note: scaling here and
//     unscaling later is pure precision loss, since the value gets smoothed anyway);
//     no colortex1Format is declared anywhere in the pack, so this is the Iris default;
//   - godraysExposure (view-angle x offscreen x time-of-day, all CPU-side per
//     design.md 4.4) is already folded into the exposure, NOT into this value;
//   - GODRAYS_STRENGTH is likewise NOT applied here - it belongs to the stage-2
//     composite, so that changing the slider does not require re-running this pass;
//   - with GODRAYS_SUN_OCCLUSION on, texel (0,0)'s alpha carries the sun-disc
//     visibility scalar for the whole frame instead of the density broadcast. Stage 2
//     reads it back with texelFetch; the other texels of alpha are written but read by
//     nobody, air or water.
// Water output: RGB = fourth-root(gamma-domain VL / 128), A = ray length / 128.
// Final reconstructs the RGB with the Solas four-tap pattern before linear conversion.
// Both channels are consumed: water_shafts_resolve takes ITS ray length from depthtex0
// (light_shafts.glsl's water_shafts_view) and reads each of the four taps' own distance
// from the stored alpha, so the two numbers come from the same capped quantity. It does
// NOT rebuild the tap distance from depthtex0 any more - that path could not reject a sky
// texel without also rejecting every real one (see the note in the resolve).
// design.md 3.2 layer 2: program files provide the lib entry.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/global/post/godrays.glsl"
#ifdef UNDERWATER_LIGHT_SHAFTS
#ifdef ASTRA_UNDERWATER_SHAFTS
    #include "/program/scene.glsl"
    #define ASTRA_SHAFT_MARCH_PASS
    #include "/global/water/light_shafts.glsl"
#endif
#endif
in vec2 texcoord;
in vec2 lightScreenPos;

#ifdef GODRAYS_SUN_OCCLUSION
// How much of the solar disc is still open sky, measured once per frame in a window
// around the light. godrays_density decides occlusion per sample point, so a column
// that covers the sun but not the pixel being shaded keeps painting full-intensity
// beams across the sky behind it. This scalar is what closes that gap; the window
// measures one pixel, so the cost is 49 depth reads per frame.
//
// depthtex1 (opaque only), not depthtex0: window panes and water surfaces must not be
// able to kill the effect. Idea from Chocapic13' LIGHT (Sharing Agreement) - read-only
// license, so the window size, the weighting and the carrier are written for Astra.
float godrays_sun_visibility(vec2 lightPos) {
	const int PROBE_TAPS = 7;
	const float PROBE_HALF_WINDOW = 12.0;	// depth-buffer pixels either side of the light
	vec2 halfWindowUV = PROBE_HALF_WINDOW / vec2(viewWidth, viewHeight);
	vec2 tapStep = 2.0 * halfWindowUV / float(PROBE_TAPS - 1);
	float clear = 0.0;
	float probed = 0.0;
	for (int j = 0; j < PROBE_TAPS; ++j) {
		for (int i = 0; i < PROBE_TAPS; ++i) {
			vec2 tapUV = lightPos - halfWindowUV + vec2(i, j) * tapStep;
			if (any(lessThan(tapUV, vec2(0.0))) || any(greaterThan(tapUV, vec2(1.0)))) {
				continue;
			}
			probed += 1.0;
			clear += float(texture(depthtex1, tapUV).r >= SKY_DEPTH);
		}
	}
	// No tap on screen means no information, so attenuate nothing.
	return probed > 0.0 ? clear / probed : 1.0;
}
#endif

/* RENDERTARGETS: 1 */

void main() {
	if (isEyeInWater != 0) {
		#ifdef ASTRA_UNDERWATER_SHAFTS
			if (isEyeInWater == 1) {
				gl_FragData[0] = water_shafts_march(texcoord);
				return;
			}
		#endif
		gl_FragData[0] = vec4(0.0);
		return;
	}
	#ifndef GODRAYS
		gl_FragData[0] = vec4(0.0);
		return;
	#endif
	if (godraysExposure <= 0.0) {
		// Whole-pass early-out (design.md 5). The buffer would otherwise keep whatever
		// uninitialised content it had, which is invisible normally but is undefined
		// behaviour and shows up the moment anyone turns on a buffer debug view.
		gl_FragData[0] = vec4(0.0);
		return;
	}

	// texcoord already spans [0,1] over the 0.5x viewport this pass renders into, which
	// is exactly the normalisation godrays_density wants - Steadfast reaches the same
	// value via gl_FragCoord.xy * windowToScreenGodrays and a custom uniform.
	float density = godrays_density(texcoord, lightScreenPos);
	gl_FragData[0] = vec4(density);
	#ifdef GODRAYS_SUN_OCCLUSION
		// Texel (0,0) carries the frame's sun visibility. gl_FragCoord and program/
		// final.fsh's texelFetch share the buffer origin, so neither side needs the
		// buffer extent or a UV-flip assumption, and that holds at both
		// size.buffer.colortex1 scales.
		if (all(lessThan(gl_FragCoord.xy, vec2(1.0)))) {
			gl_FragData[0].a = godrays_sun_visibility(lightScreenPos);
		}
	#endif
}
