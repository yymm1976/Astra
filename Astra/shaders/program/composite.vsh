// Astra v1 - program/composite.vsh (godrays pass vertex stage)
// Uniforms: gbufferProjection, lightVector (lib/uniforms.glsl)
//
// One extra varying over the Z1 stub: the shadow light's screen-space position.
// Steadfast computes that as a CPU custom uniform (screenLightVector) because its
// custom-uniform language cannot do matrix-vector maths without writing the product
// out component by component. Doing it here instead costs a 4-vertex matrix multiply
// per frame and is plain arithmetic rather than the trig/pow that design.md 5 pushes
// to the CPU, so the CPU-offload rule is not violated and shaders.properties needs no
// new uniform entry (which would disturb the Steadfast borrow accounting that the
// SC-14 gate is holding).
// design.md 3.2 layer 2: program/* is the only lib entry
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/taa_jitter.glsl"

out vec2 texcoord;
out vec2 lightScreenPos;

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	// W = 0: a directional light is a direction, not a position.
	vec4 clipLight = astra_jitter_clip(gbufferProjection * vec4(lightVector, 0.0));

	// Behind the camera the projection flips sign. godraysExposure already folds in an
	// offscreen / behind-camera fade and the pass early-outs before this varying is
	// read, but keep it finite so the varying is never NaN.
	vec2 ndcLight = clipLight.w > 0.0 ? clipLight.xy / max(clipLight.w, 0.0001) : vec2(0.0);
	lightScreenPos = ndcLight * 0.5 + 0.5;
}
