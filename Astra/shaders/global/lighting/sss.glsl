#ifndef ASTRA_GLOBAL_LIGHTING_SSS_GLSL
#define ASTRA_GLOBAL_LIGHTING_SSS_GLSL

// Astra v1 — global/lighting/sss.glsl
// Subsurface-scattering approximation for vegetation (design.md 4.1: 植被经验近似).
//
// Provenance after the 2026-09 terrain-foliage round (per-category):
//   LEAVES wrap — ported from Complementary r5.9 (Reimagined and Unbound are byte-identical
//     for these lines):
//       source: _analysis/Complementary r5.9/Reimagined/shaders/lib/lighting/mainLighting.glsl
//         :111-113  subsurfaceMode == 2 (leaves.glsl sets it for mat 10009) ->
//                   NdotL = mix(NdotL, 1.0, 0.35)   [the 叶片透光 form the task points at]
//         :118      NdotLmax0 = max0(NdotL)          [reference's own clamp after the wrap]
//     License: "Complementary License Agreement 1.7" (_analysis/Complementary r5.9/
//     Reimagined/License.txt), proprietary — NOT the Steadfast GPL line below. Publish
//     gate (design.md 9.3 + escalations.md SC-14) must be re-decided for this source;
//     raised in docs/handoffs/terrain-foliage.md.
//   GROUND-FOLIAGE wrap + the strength-mix design — from Steadfast 0.8.0 (GPLv3 + Section 7
//     additional terms) by coderbot:
//       source: _analysis/Steadfast-0.8.0/shaders/environment/lighting/diffuse.glsl
//               (DirectLighting, the `if (subsurfaceScatter)` wrap remap).
//     This part of the file remains a derivative of Steadfast and is licensed under the GNU
//     General Public License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
//     _analysis/Steadfast-0.8.0/LICENSE.md.
//
// Reference parts NOT ported (recorded in docs/handoffs/terrain-foliage.md):
//   - The reference's full-shadow-quality leaf model is flatter than any ndotl wrap:
//     mainLighting.glsl:125-130 sets NdotLM = 1.0 for ALL subsurface materials, and the
//     directional look comes from companion terms this file's frozen signature cannot see:
//       :241-254  subsurfaceHighlight = pow(max(dot(-viewDir, lightVec), 0.0), 10.0)
//                 * 0.6 (leaves) / 0.8 (other foliage) — the sun-through-the-leaf glow;
//       :288-289  shadow-edge sky mix: leaves use NdotL * 0.4999 + 0.5, other foliage a
//                 noonFactor-driven constant;
//       :107-110  mode-1 (ground foliage) fallback NdotL = dot(upVec, lightVec) — needs
//                 normal/light components, not ndotl alone.
//     Porting them requires diffuse.glsl (public, C1) to pass view-dependent inputs into
//     the sss call. Until the main task accepts that interface change, sss_wrap keeps its
//     ndotl-only contract and the task-pointed :111-113 leaf form is the faithful subset.
//   - :112 (highlightMult *= NdotL) rides the reference's specular pipeline, not diffuse.
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
// Astra change (kept): Steadfast has no SSS strength slider; Astra adds SSS_STRENGTH
// (settings.glsl, %). sss_wrap() mixes plain Lambert -> full wrap by SSS_STRENGTH*0.01, so
// 100 = the per-category full form and 0 = no forward scatter. SSS_FOLIAGE (bool) is the
// master switch and is resolved by the caller into `subsurfaceScatter` (off => plain
// Lambert). The reference has no equivalent slider.
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
//   isLeaves  — true for LEAVES-class material (Complementary mode-2 wrap, see below),
//               false for other foliage (ground foliage / SSS-class, Steadfast wrap).

// Remap raw NdotL into the "light wraps around the surface" response for a subsurface
// scatterer. ndotl is the plain dot(normal, lightVector) in [-1, 1]; the result is the
// forward-scatter-boosted direct-light factor, still ~[0, 1].
//
// Per-category full-strength forms:
//   leaves (Complementary mainLighting.glsl:113, subsurfaceMode == 2):
//     mix(ndotl, 1.0, 0.35) = ndotl * 0.65 + 0.35 -> 1.0 front, 0.35 at 90°, zero past
//     ndotl = -0.538. The reference clamps it with its own max0 (mainLighting.glsl:118);
//     transcribed as max(..., 0.0) here so the wrap can never return negative and
//     subtract light at partial strength.
//   other foliage (Steadfast DirectLighting wrap, verbatim coefficient):
//     ndotl * 0.35 + 0.65 -> tighter wrap, brighter underside, floors at 0.30.
float sss_wrap(float ndotl, bool isLeaves, float sssStrength) {
	float wrapped = isLeaves ? max(mix(ndotl, 1.0, 0.35), 0.0)
	                         : (ndotl * 0.35 + 0.65);
	// sssStrength = SSS_STRENGTH * 0.01. 0 -> plain Lambert (SSS visually off),
	// 1 -> the full wrap above. Mix from max(ndotl, 0.0), NOT raw ndotl:
	// both `wrapped` forms are floored at 0.0 / 0.30 so they are never negative, and the
	// Lambert end must be clamped too or a back-facing leaf at partial strength would
	// return a negative factor and subtract light.
	return mix(max(ndotl, 0.0), wrapped, sssStrength);
}

#endif
