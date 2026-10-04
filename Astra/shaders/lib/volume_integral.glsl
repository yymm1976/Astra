#ifndef ASTRA_LIB_VOLUME_INTEGRAL_GLSL
#define ASTRA_LIB_VOLUME_INTEGRAL_GLSL

// Astra v1 - lib/volume_integral.glsl
//
// Segmented single-scattering integrator for the optional overworld volumetric fog (H3).
//
// WHAT THIS IS. A pure, closed-form integrator for ONE uniform (homogeneous) segment of
// participating medium, plus composition of adjacent segments and the final composite
// over a background. It declares no sampler, image, uniform or frame state, so it can be
// dropped into any stage or shader. It does NOT march a ray, sample a density field,
// trace shadows, evaluate cloud shadows, reconstruct depth or apply a phase function.
// The caller supplies, per segment, an already-prepared source term and an extinction
// coefficient; this module only does the integral and the ordering.
//
// ---------------------------------------------------------------------------------
// REPRESENTATION. A medium segment is a vec4:
//     .rgb = S  integrated in-scattered radiance that reaches the segment's observer-
//               side end, in the same units as the background radiance
//     .a   = T  transmittance of the whole segment, guaranteed to lie in [0, 1]
//
// This is NOT the "alpha = opacity" convention. An empty (vacuum) segment is S = 0,
// T = 1, i.e. vec4(0, 0, 0, 1), which is exactly astra_volume_identity().
//
// UNITS. Distances are in blocks, extinctionPerLength is per block, and sourcePerLength
// is per block (radiance added per unit length by single scattering). The caller must
// have ALREADY multiplied the source by the scattering coefficient and by the incident
// light / phase-weighted radiance for that segment. This module multiplies the source
// only by a LENGTH (see the integral below): it never re-treats it as a sky colour to be
// scaled by a density.
//
// ---------------------------------------------------------------------------------
// PHYSICS (uniform segment: length L, extinction sigma, source J).
//
//   T = exp(-sigma * L)
//   S = integral_0^L J * exp(-sigma * s) ds = J * (1 - exp(-sigma * L)) / sigma
//
// where s is distance from the observer's end of the segment, so the far end is the most
// attenuated. Consequences written down so callers can rely on them:
//   * L = 0                  -> S = 0, T = 1 (identity).
//   * J = 0                  -> S = 0, T unchanged (an absorbing-only segment still dims
//                               the background through astra_volume_apply).
//   * sigma = 0, J != 0      -> S = J * L, T = 1. The limit is taken analytically; sigma
//                               is NOT clamped to an epsilon, which would wrongly convert
//                               a zero-extinction but non-zero-source segment into one
//                               with an artificial absorption floor.
//   * sigma -> infinity      -> T -> 0 and S -> J / sigma: both stay finite.
//
// STABILITY.
//   * Small optical depth: tau = sigma * L is factored out and the factor
//     f(tau) = (1 - exp(-tau)) / tau is evaluated from its Taylor series below 1e-3,
//     because the direct 1 - exp(-tau) loses all significant digits for tiny tau. S is
//     then J * L * f(tau), which is exact at tau = 0.
//   * Outside the small-tau branch, use (1-T)/sigma directly. Factoring through
//     L/tau would lose the finite 1/sigma limit when finite sigma*L overflows.
//     Inputs must be finite and the resulting radiance representable as a float.
//
// INPUT CONTRACT FOR DEGENERATE VALUES (deliberate, gentle handling).
//   * Negative distanceBlocks is clamped to 0, i.e. an identity segment. We do not let a
//     negative length run the integral backwards.
//   * Negative extinctionPerLength is clamped to 0, i.e. no attenuation and no
//     amplification: T can never exceed 1.
//   * sourcePerLength is NOT clamped or modified. It is radiance-per-block and is
//     expected non-negative from the caller; clipping it would hide caller mistakes.
//
// ---------------------------------------------------------------------------------
// COMPOSITION ORDER. Segments are combined near-to-observer first:
//
//   compose(near, far):  S = S_near + T_near * S_far ;  T = T_near * T_far
//
// The far segment's in-scatter is attenuated by the near segment, but the near segment's
// in-scatter is not attenuated by the far one (it is already between the observer and the
// far medium). Feeding the arguments in the opposite order would wrongly dim the near
// scatter. Final composite over the scene:
//
//   apply(background, volume) = background * T + S
//
// which adds the in-scatter exactly once while the medium attenuates what is behind it.

// An empty segment: no scattering, full transmittance.
vec4 astra_volume_identity() {
	return vec4(0.0, 0.0, 0.0, 1.0);
}

// Integrate one uniform segment.
//   sourcePerLength     per block. Radiance added by single scattering per unit length;
//                       the caller has already folded in the scattering coefficient and
//                       the incident radiance. Not clamped.
//   extinctionPerLength per block. Negative values are treated as zero.
//   distanceBlocks      segment length in blocks. Negative values give the identity.
// Returns vec4(S, T) with T in [0, 1].
vec4 astra_volume_segment(vec3 sourcePerLength, float extinctionPerLength, float distanceBlocks) {
	float L = max(distanceBlocks, 0.0);
	if (L == 0.0) return astra_volume_identity();
	float sigma = max(extinctionPerLength, 0.0);
	float tau = sigma * L;
	float T = exp(-tau);

	// f = (1 - exp(-tau)) / tau, with the tau -> 0 limit equal to 1.
	float integratedLength;
	if (tau < 1.0e-3) {
		// Taylor to O(tau^2): cancellation-free for small optical depth.
		integratedLength = L * (1.0 - tau * (0.5 - tau * (1.0 / 6.0)));
	} else {
		// tau >= 1e-3 implies sigma > 0 for finite non-negative inputs.
		integratedLength = (1.0 - T) / sigma;
	}

	vec3 S = sourcePerLength * integratedLength;
	return vec4(S, T);
}

// Combine two adjacent segments, near (observer side) first.
//   S = S_near + T_near * S_far ;  T = T_near * T_far
// The near scatter is NOT attenuated by the far segment.
vec4 astra_volume_compose(vec4 nearSegment, vec4 farSegment) {
	return vec4(nearSegment.rgb + nearSegment.a * farSegment.rgb,
	            nearSegment.a * farSegment.a);
}

// Composite a medium over the scene radiance behind it:
//   background * T + S, adding the in-scatter once.
vec3 astra_volume_apply(vec3 background, vec4 volume) {
	return background * volume.a + volume.rgb;
}

#endif
