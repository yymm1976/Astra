// Auto-exposure metering: 64 taps of the assembled HDR scene, one stored gain per frame.
// Schedule: after composite3 (water composition in colortex9) and before composite6's
// TAA resolve, hence before composite8/final. Without TAA it meters the same HDR buffer the
// display stage starts from; with ANTIALIASING == 2 it meters the jittered pre-resolve frame.
// The display stage applies its own terms later (bloom halo, screen-space godray scattering,
// frame-wide Darkness attenuation as a multiply), so none of them drives its own exposure.
// Beams are not excluded wholesale: the ASTRA_BLOOM + isEyeInWater == 1 meter reads colortex9,
// already carrying composite3's water medium and shafts; a non-air camera medium other than a
// thin sheet (isEyeInWater != 0 && !water_is_thin_sheet(); lava, powder snow too) keeps the gain.
// Uniforms: isEyeInWater (lib/uniforms.glsl), frameTime (declared here: the Z3 uniform
// set in lib/uniforms.glsl is frozen, SC-14, and this is the only pass that needs it).
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/global/post/exposure.glsl"
uniform sampler2D colortex0;
#ifdef ASTRA_BLOOM
uniform sampler2D colortex9;
#endif
uniform float frameTime;
/* RENDERTARGETS: 10 */
void main() {
	// colortex10 is 1x1, so this pass already runs once; the predicate keeps it at one
	// execution even if the buffer scale is ever widened. program/scattering.fsh's
	// broadcast texel uses the same corner test, and the vector comparison has to be
	// all(lessThan(...)) - GLSL ES has no < for vectors (survey 11.F-9).
	if (all(lessThan(gl_FragCoord.xy, vec2(1.0)))) {
        #ifdef ASTRA_BLOOM
        if (isEyeInWater == 1 && DEBUG_VERTEX_AO == 0)
            gl_FragData[0] = astra_ae_frame(colortex9, frameTime);
        else
        #endif
		    gl_FragData[0] = astra_ae_frame(colortex0, frameTime);
    }
	else
		discard;
}
