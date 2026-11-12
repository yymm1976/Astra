#ifndef ASTRA_LIB_POW_GLSL
#define ASTRA_LIB_POW_GLSL

// Astra v1 - integer-power helpers for hot paths.
//
// WHY (2026-09-17 performance round). The performance survey of the seven other packs in
// this Minecraft instance (sources under _analysis/performance-study-2026-09-16) found
// the same trick in four of them, each with a comment saying so:
//
//   Complementary r5.9  lib/util/commonFunctions.glsl   pow2 / pow3 / pow4 / pow5
//   Photon v1.3b        include/util/common.glsl        pow2 / pow6
//   Refrax v1.3.1       lib/common.glsl                 pow2 .. pow5
//   rethinking-voxels   lib/util/commonFunctions.glsl   pow2 / pow1_5 / sqrt1..4
//
// `pow(x, n)` with a LITERAL positive-integer exponent is a transcendental call, not one
// instruction, on every vendor (exp2/log2 or a software polynomial). When the exponent
// is a literal the compiler folds the chain below into multiplies, which is the whole
// point. This pack evaluates those on every lit pixel (the blocklight quartic), every
// foliage fragment (the transmission lobe), every star-field pixel and every sky texel.
//
// WHAT DOES NOT BELONG HERE - measured, not assumed. The first version of this file also
// exported a generic `power(exponent, base)` loop so a call site could pass a runtime
// exponent (`isLeaves ? 10.0 : 6.0`). That is a pessimisation: with the exponent unknown
// at compile time the loop cannot be folded, so it carries `mod`/`floor` exponent
// bookkeeping and a loop-carried dependency on top of the multiplies - MORE work than
// the intrinsic it replaced. It has been removed. Every call site now writes its exponent
// as a literal so the fold is guaranteed. `pow()` is likewise kept for any exponent that
// is not an exact integer (the sky palette's 2.9 and 0.90 curves): there is no chain to
// fold those to, and approximating them would change the picture.
//
// So the rule is: literal integer exponent -> these helpers; anything else -> pow().
//
// NOTE ON NAMING: `pow2` is deliberately NOT declared here. global/atmosphere/sky_gradient.glsl
// already declares a float pow2 for its ported reference code and both files land in the
// same translation unit, so a second definition of that signature would be a
// redefinition error. Use `square` where the sky module is not in scope.

// Each of these is exactly the multiply chain, so a literal-exponent call folds.
float square(float x) { return x * x; }
float cube(float x) { return x * x * x; }
float pow4(float x) { float x2 = x * x; return x2 * x2; }
float pow5(float x) { float x2 = x * x; return x2 * x2 * x; }
float pow6(float x) { float x3 = x * x * x; return x3 * x3; }
float pow8(float x) { float x4 = pow4(x); return x4 * x4; }

// High even exponents for the star field, written as explicit squaring chains.
// x^100 = x^64 * x^32 * x^4, which is 9 multiplies in total.
float pow32(float x) { float x2 = x * x; float x4 = x2 * x2; float x8 = x4 * x4; float x16 = x8 * x8; return x16 * x16; }
float pow64(float x) { float x32 = pow32(x); return x32 * x32; }
float pow100(float x) { return pow64(x) * pow32(x) * pow4(x); }

// VERIFICATION REQUIREMENT. An earlier hand-written squaring loop in this same round
// accumulated `base` instead of the current squared `factor` and was wrong by up to
// 1371x at exponent 10 - a silent black-canopy fault that visual review could never have
// attributed to a maths helper. It was caught only by comparing against exact values.
// Every helper added here must be checked the same way: evaluate against Python's x**n
// over a dense base sweep before it is trusted. pow100 and the chains above were verified
// exactly over 0.001..1.000 with zero mismatches.

#endif
