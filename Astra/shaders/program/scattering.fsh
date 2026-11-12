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
//     RG16F keeps the air density in R and source visibility in G; underwater
//     shafts keep RGBA16F because they add radiance RGB and ray length A;
//   - godraysExposure (view-angle x offscreen x time-of-day, all CPU-side per
//     design.md 4.4) is already folded into the exposure, NOT into this value;
//   - GODRAYS_STRENGTH is likewise NOT applied here - it belongs to the stage-2
//     composite, so that changing the slider does not require re-running this pass;
//   - with GODRAYS_SUN_OCCLUSION or planar clouds, texel (0,0) carries source
//     visibility for the whole frame instead of the density broadcast. In the air
//     RG16F configuration that scalar is written to G; only when underwater shafts
//     are compiled in (RGBA16F, where A is otherwise the water ray length) does it
//     live in A. Stage 2 reads back the matching channel with texelFetch; the other
//     texels are written but read by nobody.
// Water output: RGB = refracted additive linear VL, A = min(ray length,48) / 128
// World-space tree shafts instead store direct-scattering weight in R and
// their own positive view endpoint depth in G for silhouette-safe reconstruction.
// in the overworld budget (otherwise the full endpoint / 128). The consumer
// interpolates radiance directly and rejects mismatched corner distances.
// The same-frame world optical field is independent of temporal radiance history.
// design.md 3.2 layer 2: program files provide the lib entry.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/global/water/medium_state.glsl"
#if defined ASTRA_UNDERWATER_SHAFTS || defined ASTRA_GODRAYS_CLOUD_OCCLUSION || defined ASTRA_TREE_SHAFTS
    #include "/program/scene.glsl"
#endif
#define ASTRA_TREE_SHAFT_MARCH_PASS
#include "/global/post/godrays.glsl"
#ifdef ASTRA_GODRAYS_CLOUD_OCCLUSION
    #include "/global/atmosphere/clouds_screen.glsl"
#endif
#ifdef UNDERWATER_LIGHT_SHAFTS
#ifdef ASTRA_UNDERWATER_SHAFTS
    #define ASTRA_SHAFT_MARCH_PASS
    #include "/global/water/light_shafts.glsl"
#endif
#endif
in vec2 texcoord;
in vec2 lightScreenPos;
flat in int scatteringThinSheet;

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
			clear += float(textureLod(depthtex1, tapUV, 0.0).r >= SKY_DEPTH);
		}
	}
	// No tap on screen means no information, so attenuate nothing.
	return probed > 0.0 ? clear / probed : 1.0;
}
#endif

// Air-only scattering needs just density + one source-visibility scalar, so it uses
// RG16F. Underwater shafts add radiance RGB and a distance in A, which keeps the
// existing RGBA16F carrier. The token declarations stay in the #ifndef pattern used
// by the other format sites.
#ifdef ASTRA_UNDERWATER_SHAFTS
#ifndef RGBA16F
const int RGBA16F=0;
#endif
const int colortex1Format=RGBA16F;
#else
#ifndef RG16F
const int RG16F=0;
#endif
const int colortex1Format=RG16F;
#endif
const bool colortex1Clear = true;
const vec4 colortex1ClearColor = vec4(0.0,0.0,0.0,0.0);
/* RENDERTARGETS: 1 */

void main() {
	if (isEyeInWater != 0 && scatteringThinSheet == 0) {
		#ifdef ASTRA_UNDERWATER_SHAFTS
			if (isEyeInWater == 1) {
                // Thin sheets take the air path above. Integrate the bounded
                // water interval once; no scene colour enters this attachment.
                vec3 endpoint;
                float marchLength;
                vec4 volume=water_shafts_march(texcoord,endpoint,marchLength);
                // Composition compares distances inside the integration window;
                // cap alpha to the exact marker used by the one-read far path.
#ifdef ASTRA_OVERWORLD_OPTIMIZED
                volume.a = min(volume.a * WATER_SHAFT_MAX_DISTANCE, astraWaterShaftRange)
                         / WATER_SHAFT_MAX_DISTANCE;
#endif
                gl_FragData[0] = volume;
				return;
			}
		#endif
		gl_FragData[0] = vec4(0.0);
		return;
	}
	#if !defined GODRAYS || defined ASTRA_VOLUME_FOG
		// The volume owns air scattering. This pass can still be scheduled for
		// underwater shafts, but air pixels must not march unused screen godrays.
		gl_FragData[0] = vec4(0.0);
		return;
	#endif
    #ifdef ASTRA_TREE_SHAFTS
    if (SUNLIGHT_STRENGTH <= 0 || astraSunSource < 0.5 || astraDirectLightGate <= 0.0 || blindness > 0.0001) {
        gl_FragData[0] = vec4(0.0);
        return;
    }
    gl_FragData[0] = vec4(astra_tree_shafts(texcoord),0.0,0.0);
    return;
    #endif
	if (godraysExposure <= 0.0 || blindness > 0.0001 || GODRAYS_STRENGTH == 0) {
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
	#if defined GODRAYS_SUN_OCCLUSION || defined ASTRA_GODRAYS_CLOUD_OCCLUSION
		// Texel (0,0) carries the frame's sun visibility. gl_FragCoord and program/
		// final.fsh's texelFetch share the buffer origin, so neither side needs the
		// buffer extent or a UV-flip assumption, and that holds at both
		// size.buffer.colortex1 scales.
		if (all(lessThan(gl_FragCoord.xy, vec2(1.0)))) {
            float sourceVisibility = 1.0;
            #ifdef GODRAYS_SUN_OCCLUSION
            sourceVisibility = godrays_sun_visibility(lightScreenPos);
            #endif
            #ifdef ASTRA_GODRAYS_CLOUD_OCCLUSION
            // Reuse the SAME resolved coverage that attenuates the visible disc.
            // Four filtered reads once per frame, not a new cloud march per beam.
            // Outside the viewport there is no screen-cloud information: the
            // existing CPU offscreen fade still owns that case.
            if (sourceVisibility > 0.0
                && all(greaterThanEqual(lightScreenPos, vec2(0.0)))
                && all(lessThanEqual(lightScreenPos, vec2(1.0))))
                sourceVisibility *= 1.0 - clamp(astra_screen_cloud_sample(lightScreenPos).a, 0.0, 1.0);
            #endif
            #ifdef ASTRA_UNDERWATER_SHAFTS
			gl_FragData[0].a = sourceVisibility;
            #else
            gl_FragData[0].g = sourceVisibility;
            #endif
		}
	#endif
}
