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
//     raised in docs/archive/实现与取证.md#record-089.
//   GROUND-FOLIAGE wrap + the strength-mix design — from Steadfast 0.8.0 (GPLv3 + Section 7
//     additional terms) by coderbot:
//       source: _analysis/Steadfast-0.8.0/shaders/environment/lighting/diffuse.glsl
//               (DirectLighting, the `if (subsurfaceScatter)` wrap remap).
//     This part of the file remains a derivative of Steadfast and is licensed under the GNU
//     General Public License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
//     _analysis/Steadfast-0.8.0/LICENSE.md.
//
// Reference parts NOT ported before this round (recorded in docs/archive/实现与取证.md#record-089):
//   - :241-254  subsurfaceHighlight = pow(max(dot(-viewDir, lightVec), 0.0), 10.0)
//               * 0.6 (leaves) / 0.8 (other foliage) — the sun-through-the-leaf glow.
//               THIS is what sss_transmission() below now supplies. It needed the
//               view direction at the C1 entry point, which diffuse.glsl passes.
//   - :288-289  shadow-edge sky mix: leaves use NdotL * 0.4999 + 0.5, other foliage a
//               noonFactor-driven constant;
//   - :107-110  mode-1 (ground foliage) fallback NdotL = dot(upVec, lightVec) — needs
//               normal/light components, not ndotl alone.
//     The last two still need inputs the frozen signature cannot see; the
//     transmission term does not depend on them (it is a view/light relation only).
//   - :112 (highlightMult *= NdotL) rides the reference's specular pipeline, not diffuse.
//
// Scope split with B1 (global/lighting/shadowmap.glsl), verbatim from its header:
//   "The forward-scatter boost on top of this is C1's global/lighting/sss.glsl, scaled
//    by SSS_STRENGTH."
// B1 already applies the *in-shadow* factor (foliage in shadow reads as if turned ~45°
// away: cos(pi/4) ~= 0.7071) at the astra_lighting -> direct_lighting call. C1 supplies only the *out-of-shadow*
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

// ---------------------------------------------------------------------------
// Forward transmission: the view-dependent half of foliage scattering.
//
// Why the wrap above is not enough: `wrapped` depends only on the surface normal
// and the light, so a leaf seen from the lit side and the same leaf seen with the
// sun behind it receive the same direct light. What makes a canopy read as
// translucent at sunrise is that the second case is the bright one, and that is a
// relation between the VIEW direction and the light direction, not the normal.
//
// Complementary's form (mainLighting.glsl:241-242, 250-254):
//     float VdotL = dot(nViewPos, lightVec);
//     float lightFactor = pow(max(VdotL, 0.0), 10.0) * float(isEyeInWater == 0);
//     ... subsurfaceHighlight = lightFactor * 0.6 (leaves) / 0.8 (other foliage)
//
// Astra adaptation, and why this is a factor on occlusion instead of an added
// light:
//   - the reference applies its lightFactor as extra light on the shadowed side
//     too (its leaves set NdotLM = 1.0 and it multiplies shadowMult by an in-shadow
//     sky mix). Astra has just stopped paying for a flat scene, so this term is
//     returned as a 0..1 factor that diffuse.glsl blends into `visibility`: an
//     occluded leaf keeps a fraction of its direct light, and an unoccluded one can
//     never be brightened past the light it already receives. That also means the
//     effect costs no second shadow read - it reuses the one already fetched.
//   - the normal still gates it (`ndotl > 0` is not required, but a surface the
//     light cannot reach is already handled by the wrap's floor), and sky exposure
//     gates it, so indoor and cave plants do not glow at dawn.
//   - the reference gates it on the camera not being in water; that happens to be
//     right here for a second reason - the underwater path has its own shading.
//   - no noise, no per-frame dithering. The window is a function of the two
//     directions only, so leaves brighten smoothly as the view swings towards the
//     sun and never shimmer.
//
// Per-category (values are the reference's 0.6 / 0.8 with Astra's SSS strength on
// top): leaves get a WIDER and softer lobe, ground foliage (grass blades, ferns,
// flowers - single-layer, so a much longer mean free path) a TIGHTER and stronger
// one. That is the "草叶和树叶分别控制强度、宽度" split.
// SC-39 (2026-09-17 correction). This term was DEAD on arrival. The first version tested
// `dot(viewDir, worldLightVector) > 0`, but diffuse.glsl builds
//
//     vec3 viewDir = normalize(-playerPos);      // surface -> camera
//
// while worldLightVector is `normalize(view_player(lightVector))`, the light direction as
// the shadow matrix sees it, i.e. surface -> light (sunPosition/100 with sunPathRotation
// applied, then the view->world transpose). Its world-space Y is positive at noon: the
// codebase negates it elsewhere for exactly that reason (`worldSunVector.y` is the sun's
// altitude in sky_gradient.glsl, and `vec3(0.72,0.88,1.25) * ... -worldSunVector` is how
// sky.fsh places the moon opposite the sun). So dot(viewDir, worldLightVector) is about
// -0.8 at noon, the `> 0.0` gate rejected it, and the whole transmission returned 0.0 for
// every foliage fragment - the "added" effect was measurably absent, which is also why it
// cost nothing.
//
// The reference's quantity is dot(nViewPos, lightVec) with nViewPos pointing from the
// camera INTO the scene (normalize(viewPos) with viewPos the view-space fragment). That is
// `-viewDir` in Astra's convention, so the correct test is `dot(-viewDir, worldLightVector)
// > 0`, equivalently `dot(viewDir, worldLightVector) < 0`. Backlit foliage - sun behind the
// leaf, camera looking towards the sun - is exactly the case where the light and the
// surface->camera ray point the same way, and that is what this now selects.
float sss_transmission(float ndotl, vec3 viewDir, vec3 worldLightVector, bool isLeaves,
                       float skyLight, float sssStrength) {
	// The existing exposure smoothstep is exactly zero for these cave plants.
	if (sssStrength <= 0.0 || skyLight <= 0.20) return 0.0;
	// Looking towards the light sees through the surface.
	float vdotl = dot(-viewDir, worldLightVector);
	if (vdotl <= 0.0) return 0.0;
	// Leaves: exponent 10 as in the reference, which is already a broad lobe on a
	// flat canopy. Grass: exponent 6, so the blades in a near-sunward view light up
	// as a field rather than only the few leaves aimed exactly at the sun.
	//
	// Each exponent is written as its own literal so the compiler folds it to a
	// multiply chain (lib/pow.glsl). Do NOT collapse these into one call with a
	// ternary or a variable exponent: the generic exponentiation loop has to carry
	// `mod`/`floor` bookkeeping and a loop-carried dependency, which on a foliage
	// fragment costs more than the `pow()` it replaced - that mistake was made and
	// measured in this round.
	// vdotl^10 = (vdotl^2)^5. Written as two literal-exponent calls rather than one
	// runtime exponent so both fold to multiply chains (lib/pow.glsl); a runtime
	// exponent costs more than the pow() it would replace.
	float lobe = isLeaves ? pow5(square(vdotl)) : pow6(vdotl);
	// A grazing surface transmits least: the ray crosses more material. This is the
	// same measured relation the wrap encodes, applied to the transmission.
	float thickness = mix(0.35, 1.0, clamp(ndotl * 0.5 + 0.5, 0.0, 1.0));
	// Sky exposure of the fragment: the lightmap already tells us whether this plant
	// can see the sky at all, which is what excludes cave/interior plants.
	float exposure = smoothstep(0.20, 0.75, skyLight);
	float strength = (isLeaves ? 0.60 : 0.80) * sssStrength;
	return clamp(lobe * thickness * exposure * strength, 0.0, 1.0);
}

#endif
