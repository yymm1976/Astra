#ifndef ASTRA_GLOBAL_LIGHTING_SSS_GLSL
#define ASTRA_GLOBAL_LIGHTING_SSS_GLSL

// Astra v1 — global/lighting/sss.glsl
// Subsurface-scattering approximation for vegetation (design.md 4.1: 植被经验近似).
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot
//   source: _analysis/Steadfast-0.8.0/shaders/environment/lighting/diffuse.glsl
//           (DirectLighting, the `if (subsurfaceScatter)` wrap remap).
// This file is a derivative of Steadfast and is licensed under the GNU General Public
// License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
// _analysis/Steadfast-0.8.0/LICENSE.md. Redistribution is permitted only under that
// license including Steadfast's Section 7 additional terms.
// Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Scope split with B1 (global/lighting/shadowmap.glsl), verbatim from its header:
//   "The forward-scatter boost on top of this is C1's global/lighting/sss.glsl, scaled
//    by SSS_STRENGTH."
// B1 already applies the *in-shadow* factor (foliage in shadow reads as if turned ~45°
// away: cos(pi/4) ~= 0.7071) inside shadow_mapping(). C1 supplies only the *out-of-shadow*
// wrap: raw NdotL is remapped so back-facing leaves still catch light, which is what makes
// a canopy glow instead of going flat-black on the underside. The two are complementary and
// must NOT be double-applied — diffuse.glsl multiplies sss_wrap() by shadow_mapping()'s
// return, never by another 0.7071.
//
// Astra change: Steadfast has no SSS strength slider; Astra adds SSS_STRENGTH (settings.glsl,
// %). sss_wrap() therefore mixes plain Lambert -> full Steadfast wrap by SSS_STRENGTH*0.01,
// so 100 = Steadfast-exact and 0 = no forward scatter. SSS_FOLIAGE (bool) is the master
// switch and is resolved by the caller into `subsurfaceScatter` (off => plain Lambert).
//
// Uniforms: none. Requires lib/settings.glsl (SSS_STRENGTH) — program/* guarantees order.
// Consts:   none.
// Owner: C1. Consumer: global/lighting/diffuse.glsl (same pass).
// Include order (E1 / program/lit.fsh): this file BEFORE diffuse.glsl.
//
// Interface contract (E1 unfrozen — classification taken as caller booleans, NOT a material
// enum; mirrors the B-series wind.glsl precedent "materialID 判据改为调用方布尔参数，待 E1
// 接线"). E1 owns the frozen material-ID enum and resolves materialID -> {subsurfaceScatter,
// isLeaves}; C1 owns the per-category shading math below.
//   isLeaves  — true for LEAVES-class material (wrap 0.50/0.50), false for other foliage
//               (ground foliage / SSS-class, wrap 0.35/0.65).

// Remap raw NdotL into the "light wraps around the surface" response for a subsurface
// scatterer. ndotl is the plain dot(normal, lightVector) in [-1, 1]; the result is the
// forward-scatter-boosted direct-light factor, still ~[0, 1].
//
// Steadfast's two tuned forms (verbatim coefficients):
//   leaves:        ndotl * 0.50 + 0.50   -> [-0.5+0.5, 0.5+0.5] = [0.0, 1.0], back lit at 0.25
//   other foliage: ndotl * 0.35 + 0.65   -> tighter wrap, brighter underside
float sss_wrap(float ndotl, bool isLeaves, float sssStrength) {
	float wrapped = isLeaves ? (ndotl * 0.50 + 0.50)
	                         : (ndotl * 0.35 + 0.65);
	// sssStrength = SSS_STRENGTH * 0.01. 0 -> plain Lambert (SSS visually off),
	// 1 -> the full Steadfast wrap above. Mix from max(ndotl, 0.0), NOT raw ndotl:
	// `wrapped` floors at 0.0 (leaves) / 0.30 (other) so it is never negative, and the
	// Lambert end must be clamped too or a back-facing leaf at partial strength would
	// return a negative factor and subtract light.
	return mix(max(ndotl, 0.0), wrapped, sssStrength);
}

#endif
