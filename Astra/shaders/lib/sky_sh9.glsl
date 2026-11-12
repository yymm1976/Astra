#ifndef ASTRA_LIB_SKY_SH9_GLSL
#define ASTRA_LIB_SKY_SH9_GLSL

// ============================================================
//  Astra v1 - lib/sky_sh9.glsl
//  Nine-term real spherical-harmonic (SH9) projection and evaluation of a
//  directional sky radiance field, for H1 (directional sky light).
//
//  This is a pure math module: no sampler, no image, no uniform, no frame state.
//  It does NOT sample the sky, does NOT decide the sampling layout, does NOT know
//  about sun/moon discs, the lower hemisphere, clouds or weather art parameters.
//  The H1 producer stages supply all of that and hand this module unit directions,
//  radiance and a solid-angle weight per sample.
// ============================================================
//
//  CONVENTION - index order, axes, normalization
//  ---------------------------------------------
//  Directions are in PLAYER-RELATIVE WORLD SPACE (same space as worldNormal and
//  the astra_sky_radiance()/worldDir argument), and are expected NORMALIZED.
//  +Y is up, matching every other Astra world-space consumer (worldNormal.y,
//  worldSunVector.y). +X / +Z are the horizontal axes; their sign only has to be
//  consistent between projection and evaluation, which it is because both use the
//  single astra_sh9_basis() below.
//
//  Index   Basis function                  Coefficient meaning
//  -----   ------------------------------  -------------------
//    0     K0                              constant / ambient
//    1     K1 * y                          up-down dipole (+y up, polar)
//    2     K1 * z                          z dipole
//    3     K1 * x                          x dipole
//    4     K2 * x*y                        xy quadrupole
//    5     K2 * y*z                        yz quadrupole
//    6     K20 * (3*y*y - 1)               y quadrupole (polar)
//    7     K2 * x*z                        xz quadrupole
//    8     K22 * (x*x - z*z)               (x*x - z*z) quadrupole
//
//  The ordering enumerates l=0, then the three l=1 terms, then the five l=2
//  terms, with every basis function written directly in world axes and the
//  polar axis at world +Y. Textbook Y_l^m superscripts are deliberately NOT
//  attached to the indices: once the polar axis moves from +Z to +Y the m
//  numbering is convention-dependent, and no consumer of this module needs it
//  - projection and evaluation share the single astra_sh9_basis() below. If a
//  future integration must exchange coefficients with an external SH library,
//  match by the polynomial column above, not by index.
//
//  Normalization constants (orthonormal over the unit sphere: integral Y_i^2 dOmega = 1):
const float ASTRA_SH9_K0  = 0.2820947918; // 1/(2*sqrt(pi))
const float ASTRA_SH9_K1  = 0.4886025119; // sqrt(3/(4*pi))
const float ASTRA_SH9_K2  = 1.0925484306; // sqrt(15/(4*pi))
const float ASTRA_SH9_K20 = 0.3153915653; // sqrt(5/(16*pi))
const float ASTRA_SH9_K22 = 0.5462742153; // sqrt(15/(16*pi))
const float ASTRA_SH9_PI  = 3.1415926536;

// Cosine-kernel (clamped-cosine) SH convolution factors A_l used by
// astra_sh9_irradiance(): a_zonal = 2*pi * ∫_0^1 P_l(u) u du
//   A_0 = pi,  A_1 = 2*pi/3,  A_2 = pi/4
// They are NOT used for plain radiance reconstruction (astra_sh9_radiance),
// which uses the unmodified Y_i.
const float ASTRA_SH9_A0 = 3.1415926536;          // pi
const float ASTRA_SH9_A1 = 2.0943951024;          // 2*pi/3
const float ASTRA_SH9_A2 = 0.7853981634;          // pi/4

// ------------------------------------------------------------
//  The shared basis. Projection and evaluation both go through this one function
//  so the ordering/axis/normalization convention can never drift between them.
//  `direction` is normalized by the caller (astra_sh9_accumulate / the evaluation
//  entry points normalize defensively).
// ------------------------------------------------------------
void astra_sh9_basis(vec3 direction, out float basis[9]) {
	float x = direction.x;
	float y = direction.y;
	float z = direction.z;

	basis[0] = ASTRA_SH9_K0;
	basis[1] = ASTRA_SH9_K1 * y;
	basis[2] = ASTRA_SH9_K1 * z;
	basis[3] = ASTRA_SH9_K1 * x;
	basis[4] = ASTRA_SH9_K2 * x * y;
	basis[5] = ASTRA_SH9_K2 * y * z;
	basis[6] = ASTRA_SH9_K20 * (3.0 * y * y - 1.0);
	basis[7] = ASTRA_SH9_K2 * x * z;
	basis[8] = ASTRA_SH9_K22 * (x * x - z * z);
}

// ------------------------------------------------------------
//  astra_sh9_clear - zero the accumulator before a projection pass.
// ------------------------------------------------------------
void astra_sh9_clear(out vec3 coefficients[9]) {
	for (int i = 0; i < 9; ++i) {
		coefficients[i] = vec3(0.0);
	}
}

// ------------------------------------------------------------
//  astra_sh9_accumulate - add one sample to the projection.
//
//  The coefficients are the integral of radiance against the basis over the sphere:
//      c_i = ∫_sphere L(ω) * Y_i(ω) dΩ
//  A finite sample set approximates this as a Riemann/Monte-Carlo sum; the caller
//  supplies the per-sample solid angle, so this module never guesses a sample count
//  and never divides by one. Callers using an unbiased estimator must supply
//  weights whose total solid angle is 4*pi when they cover the whole sphere.
//
//  `solidAngle` is that weight in steradians (radiance is treated as constant over
//  it). It may be a discrete cell solid angle or an importance-sampling weight.
//  A zero weight contributes nothing; no implicit 1/N is applied anywhere.
//
//  Coefficients carry units of radiance * steradian and are allowed to be negative;
//  they must NOT be clamped per-term (see the negative-reconstruction note below).
// ------------------------------------------------------------
void astra_sh9_accumulate(inout vec3 coefficients[9], vec3 unitDirection, vec3 radiance,
                          float solidAngle) {
	float len2 = dot(unitDirection, unitDirection);
	if (len2 < 1.0e-12) {
		// Degenerate direction: contribute nothing rather than produce NaNs.
		return;
	}
	vec3 dir = unitDirection * inversesqrt(len2);

	float basis[9];
	astra_sh9_basis(dir, basis);
	for (int i = 0; i < 9; ++i) {
		coefficients[i] += radiance * basis[i] * solidAngle;
	}
}

// ------------------------------------------------------------
//  astra_sh9_radiance - low-order reconstruction of the radiance field itself:
//      L(d) ≈ Σ_i c_i * Y_i(d)
//  This is NOT a physical output term; it is the truncated radiance field and may
//  be negative where order 2 overshoots (e.g. across a sharp sun/sky boundary).
//  It is provided so callers can inspect / blend the field, and so the projection
//  and evaluation paths demonstrably share one convention.
// ------------------------------------------------------------
vec3 astra_sh9_radiance(vec3 coefficients[9], vec3 unitDirection) {
	float len2 = dot(unitDirection, unitDirection);
	if (len2 < 1.0e-12) return vec3(0.0);
	vec3 dir = unitDirection * inversesqrt(len2);

	float basis[9];
	astra_sh9_basis(dir, basis);

	vec3 result = vec3(0.0);
	for (int i = 0; i < 9; ++i) {
		result += coefficients[i] * basis[i];
	}
	return result;
}

// ------------------------------------------------------------
//  astra_sh9_irradiance - cosine-convolved irradiance on a surface facing unitNormal:
//      E(n) = ∫_hemisphere L(ω) * max(dot(n, ω), 0) dΩ
//           ≈ Σ_i (A_l(i) * c_i) * Y_i(n)        with l(i) the band of index i.
//
//  The clamped-cosine kernel is a zonal function, so its spherical-harmonic
//  convolution diagonalizes: each band l is scaled by A_l and no cross terms appear.
//
//  Sanity checks (why the A_l above are correct):
//    * Constant environment L (c_0 = 2*sqrt(pi)*L, all others 0):
//      E = A_0 * c_0 * Y_0 = pi * (2*sqrt(pi)*L) * (1/(2*sqrt(pi))) = pi*L,
//      independent of the normal. ✓
//    * Zero environment (cleared coefficients): every term is 0. ✓
//
//  Coefficients are not clamped here. The truncated series can reconstruct a
//  slightly negative irradiance where the real field has a very sharp gradient;
//  per the task contract that is handled (if at all) only at the final physical
//  output in the H1 integration, never by clamping individual coefficients. Do not
//  max(.,0) the coefficients - that would bias the reconstruction of every other
//  direction too.
// ------------------------------------------------------------
vec3 astra_sh9_irradiance(vec3 coefficients[9], vec3 unitNormal) {
	float len2 = dot(unitNormal, unitNormal);
	if (len2 < 1.0e-12) return vec3(0.0);
	vec3 n = unitNormal * inversesqrt(len2);

	float basis[9];
	astra_sh9_basis(n, basis);

	return ASTRA_SH9_A0 * coefficients[0] * basis[0]
	     + ASTRA_SH9_A1 * (coefficients[1] * basis[1]
	                     + coefficients[2] * basis[2]
	                     + coefficients[3] * basis[3])
	     + ASTRA_SH9_A2 * (coefficients[4] * basis[4]
	                     + coefficients[5] * basis[5]
	                     + coefficients[6] * basis[6]
	                     + coefficients[7] * basis[7]
	                     + coefficients[8] * basis[8]);
}

// ------------------------------------------------------------
//  astra_sh9_diffuse_radiance - outgoing radiance of a unit-albedo Lambertian
//  surface under the SH sky: the irradiance divided by pi.
//      L_out(n) = E(n) / pi  = albedo * E(n) / pi  with albedo = 1
//
//  Kept separate from astra_sh9_irradiance() on purpose: this is the term that
//  multiplies surface albedo in the lighting composer, so a caller that wants
//  radiance-to-albedo already knows not to multiply by pi again. Check:
//    * Constant environment L: E = pi*L  ->  L_out = L. ✓
//    * Zero environment: 0. ✓
// ------------------------------------------------------------
vec3 astra_sh9_diffuse_radiance(vec3 coefficients[9], vec3 unitNormal) {
	return astra_sh9_irradiance(coefficients, unitNormal) / ASTRA_SH9_PI;
}

#endif
