// Astra v1 - program/composite.fsh (godrays: half-resolution R8 density map)
// Uniforms: godraysExposure (lib/uniforms.glsl); colortex1 is 0.5x via shaders.properties.
//
// Stage 1 of the two-stage godrays (design.md 2.2 / 4.4). Stage 2 - smoothing and
// upsample back to full resolution - happens in the final chain and belongs to E1/C6,
// because the pass order and the buffers that final reads are E1's resolution
// (design.md 2.2, tasks-advanced-1.md cooperative rule 2).
//
// Output contract for stage 2:
//   - colortex1 holds the raw accumulated density in [0, 1], deliberately unscaled so
//     the R8 buffer's full precision is used (Steadfast's note: scaling here and
//     unscaling later is pure precision loss, since the value gets smoothed anyway);
//   - godraysExposure (view-angle x offscreen x time-of-day, all CPU-side per
//     design.md 4.4) is already folded into the exposure, NOT into this value;
//   - GODRAYS_STRENGTH is likewise NOT applied here - it belongs to the stage-2
//     composite, so that changing the slider does not require re-running this pass.
// design.md 3.2 layer 2: program/* is the only lib entry
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/global/post/godrays.glsl"
in vec2 texcoord;
in vec2 lightScreenPos;

/* RENDERTARGETS: 1 */

void main() {
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
	gl_FragData[0] = vec4(godrays_density(texcoord, lightScreenPos));
}
