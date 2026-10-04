// Auto-exposure metering: 64 taps of the assembled frame, one stored gain per frame.
// Runs after composite3 (the underwater scene in reused colortex4) and before final, so the frame it
// measures is the frame final displays - minus the bloom, godray and darkness terms
// final adds itself, which is deliberate: effects that exposure would otherwise feed
// back into must not drive their own exposure.
// Uniforms: isEyeInWater (lib/uniforms.glsl), frameTime (declared here: the Z3 uniform
// set in lib/uniforms.glsl is frozen, SC-14, and this is the only pass that needs it).
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/global/post/exposure.glsl"
uniform sampler2D colortex0;
#ifdef ASTRA_BLOOM
uniform sampler2D colortex4;
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
            gl_FragData[0] = astra_ae_frame(colortex4, frameTime);
        else
        #endif
		    gl_FragData[0] = astra_ae_frame(colortex0, frameTime);
    }
	else
		discard;
}
