#ifndef ASTRA_GLOBAL_DIMENSION_END_GLSL
#define ASTRA_GLOBAL_DIMENSION_END_GLSL

// Astra v1 — global/dimension/end.glsl
// The End's independent sky, void fog and lighting path (design.md 4.5).
//
// Why this file exists as a SEPARATE path rather than as branches inside the overworld modules:
// the End has no sun, no weather, no clouds and no usable skylight, so C1's diffuse_lighting()
// has nothing to compute here either — its shadow-mapped direct term and its sun/moon ambient
// blend are both meaningless. design.md 4.5 asks for 真空暗天空 + 褪色环境光, not for a tinted
// copy of the overworld path. The strongest available evidence that this needs its own path is
// a negative one: Steadfast 0.8.0 — the pack this project borrows its atmosphere from — has no
// End code at all. Its environment/lighting/diffuse.glsl:320-326 leaves a 0.125/16 direct-light
// floor with the comment "This is also the only reason why there is any light in the End", i.e.
// an acknowledged TODO. Mellow v3.4 and Solas V2.2b both write a real End path, and both do it
// by switching the sun/sky/cloud helpers off at the source rather than by branching inside them
// (Mellow program/deferred1.fsh:51-56 calls get_stars() for OVERWORLD||END and the cloud/aurora
// helpers for OVERWORLD only; Solas lib/common.glsl:344-366 #undefs MILKY_WAY/RAINBOW/AURORA/
// VC/STARS/PLANAR_CLOUDS/... under `#ifndef OVERWORLD`). Astra does the same by handing E1 a whole
// End composer and sky function to call INSTEAD of the overworld ones.
//
// Provenance (see THIRD-PARTY.md; Solas licence is undeclared = default copyright, Mellow MIT,
// Refrax proprietary — idea-level only):
//   - Mellow v3.4 (MIT) by TheCMK, idea + palette values:
//       lib/colors.glsl:42-44      -> the dark-violet sky base (0.15, 0.10, 0.20) sRGB
//       lib/colors.glsl:70-72      -> the faded ambient (0.20, 0.17, 0.25) sRGB
//       lib/colors.glsl:74-76      -> the up-facing "direct" light (0.30, 0.23, 0.45) sRGB
//       lib/colors.glsl:78-84      -> the teal / amber light bands (0, 0.45, 0.25) / (0.45, 0.30, 0.10)
//       global/atmosphere/sky.glsl:105-131  -> the End sky is a dark base + horizon-banded light
//                                              bands that crush to black below the horizon line
//       global/atmosphere/sky.glsl:54-64    -> the star field is a quantized-coordinate hash
//                                              thresholded toward 1.0, faded near the horizon
//       global/atmosphere/fog.glsl:37-50    -> the void fog: saturates by ~32 blocks, a small
//                                              residual so nothing is ever quite fully gone, and a
//                                              10-block height ramp anchored at Y=30 (END_FOG_START_HEIGHT)
//       global/lighting/lighting.glsl:80-81, 127 -> the End's directional term is simply
//                                              max(0, N dot up) with the shadow machinery
//                                              bypassed (Shadow = vec3(1))
//       global/lighting/lighting.glsl:44-46 -> lightmap.y is forced to 1 outside the overworld,
//                                              which is why skyLight is NOT a parameter here
//     License: MIT - see THIRD-PARTY.md
//   - Structure-level borrowing from Solas V2.2b (licence undeclared):
//       lib/atmosphere/skyEffects.glsl:48-91 -> two independently thresholded noisetex octave
//                                              stacks on a projected sky plane, counter-drifting,
//                                              masked by a horizon band, additive into the sky
//       lib/atmosphere/skyEffects.glsl:6-27  -> the nebula density dims the stars behind it
//     PROVENANCE: rewritten for Astra - REWRITE REQUIRED before distribution (design.md 9.3, SC-14).
//     Solas runs 5 + 3 octaves (9 noisetex fetches) plus a spiral domain warp anchored to a
//     synthetic sun vector; the End has no such vector (see ⚠ FROM E1 below) and design.md 4.5
//     asks for a 低配版, so Astra runs 2 + 2 octaves (4 fetches) with no warp.
//   - Refrax v1.3.1 (proprietary — no expression, constant or literal ported):
//       lib/atmosphere.glsl:390 + 406-407 -> the sky is mixed toward the FOG colour by a horizon-band
//                                            weight, so distant terrain and sky meet without a seam
//       lib/atmosphere.glsl:395-396        -> the nebula is confined to a band about a fixed
//                                            world-space axis, not about the camera's horizon
//       lib/atmosphere.glsl:174-209        -> the star LAYER STRUCTURE: a presence hash on a cell id
//                                            with an early return, the surviving fraction normalized
//                                            to a magnitude, a brightness rising as the cube of that
//                                            magnitude, a jittered disc centre and a radial profile
//                                            that saturates at the cell edge, plus a two-sine twinkle
//                                            with a per-star amplitude and phase.
//     PROVENANCE: structure-level borrowing from a proprietary pack - REWRITE REQUIRED before
//     distribution (design.md 9.3, SC-14). Astra's implementation differs in the parts that matter
//     for cost and for look — a 3D lattice over the rotated direction instead of Refrax's six
//     warped cube faces, two layers instead of one, a pixel-footprint widening instead of a
//     magnitude-scaled radius, its own palette, thresholds, rates and amplitudes — but the skeleton
//     above is recognizably Refrax's, and the file must be rewritten before any distribution.
//   - Complementary r5.9 (Reimagined/Unbound — identical in every cited line) by Complementary
//     Development, Complementary License Agreement 1.7 (redistribution/modification outside
//     Normal Usage; treat like Refrax for publishing):
//       lib/lighting/mainLighting.glsl:507-512 -> the End's directional shading: NdotUM /
//                                              NdotNM / NdotEM multiplied into directionShade.
//                                              Axis mapping is exact: its eastVec/northVec are
//                                              normalize(gbufferModelView[0/2].xyz)
//                                              (program/gbuffers_terrain.glsl:57-58), i.e. the
//                                              world +X/+Z axes carried into view space, and dot
//                                              products are rotation-invariant, so in Astra's
//                                              world-space interface NdotE = worldNormal.x,
//                                              NdotN = worldNormal.z, NdotU = worldNormal.y.
//       lib/lighting/mainLighting.glsl:613     -> directionShade enters the diffuse as
//                                              pow2(directionShade * vanillaAO); Astra's End
//                                              interface carries no vanilla AO, so the ported
//                                              gate is pow2(directionShade) only (handoff noted
//                                              in docs/handoffs/end.md). Comp's sqrt() fold of
//                                              blocklight into the sum (:613-616) is NOT ported:
//                                              Astra's BLOCKLIGHT_COLOR is SC-34-calibrated for a
//                                              linear add and a sqrt would re-tune it blind.
//       lib/lighting/minimumLighting.glsl:2    -> `#if !defined END`: the End has NO dark-side
//                                              minimum-light floor, so end_lighting() no longer
//                                              adds MIN_AMBIENT_COLOR (the MIN_AMBIENT option is
//                                              overworld/nether-only now).
//       program/deferred1.glsl:386             -> the End sky (base + stars) is dimmed by
//                                              (1.0 - maxBlindnessDarkness);
//                                              maxBlindnessDarkness = max(blindness,
//                                              darknessFactor) (shaders.properties:275). Astra
//                                              freezes only `blindness` (lib/uniforms.glsl:48),
//                                              so the port substitutes it and the Warden
//                                              darknessFactor half is a handoff item.
//     Considered and NOT ported, with evidence:
//       lib/common.glsl:817 endSkyColor = vec3(0.095,0.07,0.15)*1.65 and
//       lib/colors/lightAndAmbientColors.glsl:82-87 endLightColor = vec3(0.68,0.51,1.07):
//         magnitudes live in Comp's own pre-tonemap pipeline (its endSkyColor is ~8x Astra's
//         linear END_VOID_COLOR); a verbatim magnitude port cannot be verified without both
//         tonemaps, so it stays a handoff question. The HUES need no port: Astra's
//         END_AMBIENT_COLOR normalized is (1, 0.72, 1.54) vs Comp's endLightColor (1, 0.75,
//         1.57) — already the same violet. The 0.2*vsBrightness balancer additionally needs the
//         screenBrightness uniform, which Astra does not freeze (lib/uniforms.glsl) -> handoff.
//       lib/atmospherics/enderStars.glsl: its visibility shape (zenith-dim band + a
//         camera-altitude gate on END_BEAM_CENTER_ALT) exists to make room for Comp's volumetric
//         ender beams, which Astra does not have; Astra's rotating 3D-lattice field below is the
//         deliberate own design. Unchanged.
//     PROVENANCE: verbatim expression porting from a pack under Complementary License Agreement
//     1.7 - REWRITE REQUIRED before distribution (design.md 9.3, SC-14), same gate as Refrax.
//   - Astra's own (no reference does these):
//       the star field's rigid rotation about a tilted celestial pole (see end_rotate_sky), the
//       3D cell lattice instead of a projected 2D grid, the nadir-stereographic sky projection,
//       the depth-crushed void tint ramp, the travelling portal-beam glow, and the void-fog
//       strength floor above the island level.
//   Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Design note — the star field rotates, and not in the way any reference does.
//   design.md 4.5 asks for 稠密星野（缓慢旋转）. No reference rotates its field. Mellow
//   (sky.glsl:56) adds `frameTimeCounter * 0.001` to the X component of a projected plane
//   coordinate, Solas (skyEffects.glsl:17) adds the same scalar to both components of its plane
//   coordinate, and Refrax (atmosphere.glsl:174-208) reads the direction with no time term at all
//   — its only drift is a translation inside the nebula's noise argument (:397). A translation of
//   the lookup grid is not a rotation of the pattern: on any projection whose cell area grows with
//   angle, a fixed shift in plane units is a different angular shift at the pole than at the
//   horizon, so the grid shears, the per-solid-angle star density changes as the grid slides, and
//   the pattern visibly moves sideways instead of turning. Astra instead hashes a 3D lattice laid
//   over the view direction and rotates the direction itself. Rotation of the argument of a 3D
//   lattice is a rigid motion, so density is preserved everywhere on the sphere and there is no
//   projection singularity to shear at — and because the lattice is built from a unit direction,
//   the same cell is sampled at the same density no matter where the player is standing.
//   This is one documented deviation from design.md 5's "噪声优先查表（noisetex）而非 hash": a
//   256² bilinear-filtered table cannot express a sparse point process — every texel of a smooth
//   table is nonzero, so thresholding it gives blobs, not stars. The alternative would be a new
//   star texture asset, which design.md 3.3/8 does not budget. The hash is used ONLY for the star
//   point process (a handful of integer multiplies on the ~1.4% of cells that survive the density
//   test); the nebula, which IS a continuous field, keeps using noisetex lookups.
//
// Uniforms: cameraPosition, frameTimeCounter, noisetex (via lib/noise.glsl), borderFogDistance,
//           blindness, isEyeInWater (all frozen in lib/uniforms.glsl).
// Consts:   END_FOG_DENSITY, SKY_FOG_STRENGTH, BORDER_FOG, STARS, END_NEBULA, BLOCKLIGHT_STRENGTH,
//           HANDHELD_LIGHTING, EMISSIVE_STRENGTH (lib/settings.glsl);
//           noiseTextureResolution (ENGINE KNOB, lib/settings.glsl); BLOCKLIGHT_COLOR
//           (lib/colors.glsl). The END_* tuning constants below are local to this module.
//           MIN_AMBIENT / MIN_AMBIENT_COLOR were dropped on 2026-09-10: Complementary r5.9's
//           minimumLighting.glsl:2 gates the dark-side floor behind `#if !defined END`.
// Owner: C4. Consumers: program/lit.fsh, program/deferred.fsh, program/sky.fsh (and clouds.fsh /
//                       scattering.fsh) — all via the E1 composition boundary program/scene.glsl
//                       (scene.glsl:34 end_sky, :107 end_fog, :182 end_lighting).
// Requires (NOT included here — program/* guarantees the order, design.md 3.2 layer 2/3, matching
//   lib/colors.glsl and global/dimension/nether.glsl which likewise include no settings/uniforms):
//     lib/settings.glsl               -> the option macros listed above
//     lib/uniforms.glsl               -> the uniforms listed above
//     global/lighting/blocklight.glsl (C1, SIBLING) -> held_light_strength()
//   globals may not include globals (SC-10), so C1's helper arrives by program-ordered inclusion:
//   scene.glsl includes /global/lighting/blocklight.glsl BEFORE this file (scene.glsl:9, 21).
//   global/lighting/diffuse.glsl is NO LONGER required here: the End's directional shaping moved
//   from C1's ambient_strength() to Complementary's directionShade on 2026-09-10 (see the
//   provenance block) — one owner, one definition, now the reference pack's. C4 re-derives the
//   handheld ramp from no one: it still calls held_light_strength(), same as C3.
//
// Interface contract (E1 unfrozen — every non-frozen input is a documented parameter):
//   No new uniforms are required from E1 by this module. Unlike the nether, the End has no biome
//   fog colour to read, so `uniform vec3 fogColor` (the ⚠ REQUIRED FROM E1 item in
//   global/dimension/nether.glsl) is NOT needed here: vanilla's End fog is a constant and the
//   黑紫 below is a spec'd palette, authored locally, not a derivation.
//   worldViewDir — NORMALIZED player-relative world-space view direction (y is up).
//   worldNormal  — player-relative world space, normalized (same convention as C1/B1/C3).
//   playerPos    — camera-relative world space; absolute Y is playerPos.y + cameraPosition.y and
//                  drives the whole void-depth model.
//   blockLight   — 0..1 lightmap (1 = light level 15). skyLight is deliberately absent: the End's
//                  lightmap skylight channel is constant 15 (Mellow forces `LightmapCoords.y = 1`
//                  for every non-overworld dimension, lighting.glsl:44-46), so a skyLight
//                  parameter here could only ever be a second name for "1".
//   emissiveMask / portalMask — E1-resolved material categories, 0.0 or 1.0, exactly as in C3's
//                  nether_lighting contract.
//   time         — frameTimeCounter (frozen); the caller may scale it.
//   RESOLVED (SC-18, verified 2026-09-10): DIMENSION_END reaches the terrain pass through
//                  world1/gbuffers_terrain.fsh:1-4 (`#define DIMENSION_END` then
//                  `#include "/program/lit.fsh"`), and lit.fsh:81 calls astra_light() which
//                  dispatches to end_lighting() at scene.glsl:182. sky.fsh:61 -> astra_sky() ->
//                  end_sky() (scene.glsl:34); deferred.fsh:18 -> astra_apply_medium() ->
//                  astra_fog() -> end_fog() (scene.glsl:107). Same shell pattern serves C3's
//                  nether_lighting().
//   ⚠ FROM E1 (design.md 4.5 preamble): 按维度裁剪无关 pass. shaders.properties currently has no
//                  per-dimension pass list, so cutting the overworld's cloud/sun-moon/godray work
//                  in world1/ is an E1-side properties + pipeline change. C4 cuts nothing; it
//                  simply never references those features, so E1's cut has no C4 dependency to keep.
//   ⚠ OPTIONAL FROM E1: the emissive/portal boost below is a FACTOR on the surface albedo, which
//                  keeps one multiply and matches C3's shape. If the near-black end_gateway /
//                  obsidian albedo then still fails to clear the bloom threshold, the fix is an
//                  ADDITIVE emissive colour — which changes what a dimension composer returns and
//                  so must be decided for the nether and the End together, not per dimension.
//   Separability from D2: this module owns the End star field because design.md 4.5 assigns 稠密星野
//                  to the End path and because there is no END_STARS option to add without breaking
//                  the settings.glsl <-> shaders.properties bijection (check_pack.py 2) and the
//                  60-80 option budget. So the gate is the shared `#ifdef STARS`. If D2 later
//                  generalizes global/atmosphere/stars.glsl to both dimensions, end_star_field() is
//                  the function to delete — nothing else in this file depends on it.
//   All three profiles ship STARS and END_NEBULA enabled (shaders.properties:36-38) and none ships
//                  VOXY_SUPPORT, so there is no profile-side interpolation to honour here: every
//                  END_* constant below is a factory value for all three tiers.
//
// Perf (task acceptance: 截图可独立辨识为"设计过" at the same frame-rate bar as the overworld):
// the End path is cheaper than the overworld one — no shadow-map sample (there is no light source
// to shadow), no Minishita optical-depth evaluation, no cloud or weather terms. The sky costs 4
// noisetex fetches for the nebula plus ~2 integer hashes per pixel for the star layers (the
// density test rejects ~98.6% of cells before the remaining hashes run), and every expensive term
// sits behind an early-out or a compile-time #ifdef. design.md 5's early-out rule is followed;
// note that dFdx/dFdy-dependent work (the star footprint, via fwidth) is deliberately hoisted
// ABOVE the occupancy branch, because implicit derivatives inside divergent control flow are
// undefined behaviour, not just slow.

#include "/lib/colors.glsl"
#include "/lib/encoding.glsl"
#include "/lib/noise.glsl"

// Everything this module needs that is not a frozen uniform. Same idiom as B2's FogParams, C1's
// LightParams and C3's NetherParams: data travels as a struct, never as a privately opened uniform.
struct EndParams {
	float nightVision;     // built-in (not frozen): 0..1, lifts the ambient floor only
	float heldLightBase;   // CPU pow(heldBlockLightValue / 15, 4), 0..1 — see C1 blocklight.glsl
};

// ---------------------------------------------------------------------------
// Tuning constants. All End-local: none of them belongs in grading.glsl (C6 owns the image-wide
// style layer) or in lib/colors.glsl (C1 owns the SHARED light palette; these colours are used by
// this dimension only and would be dead weight everywhere else).
//
// The palette values are Mellow's shipped End colours, run through Astra's to_linear() because
// Astra's lighting is linear HDR end to end. to_linear() is a macro of pure arithmetic
// (lib/encoding.glsl:12), so it is legal in a constant initializer and the derivation stays
// auditable at the call site instead of hiding behind a decimal literal.
// ---------------------------------------------------------------------------

// Vacuum sky base — and, deliberately, the same constant the fog fades to. Mellow keeps these
// separate (SkyT in sky.glsl:106 versus multiply-to-black in fog.glsl:49); making them one value
// is what removes the sky/fog horizon seam (the Refrax idea cited above).
const vec3  END_VOID_COLOR = to_linear(vec3(0.15, 0.10, 0.20));

// 褪色环境光: washed-out violet-grey. Mellow applies its END_AMBIENT palette unmultiplied, so the
// intensity below is a scale on an ALREADY ABSOLUTE colour rather than a gain on a unit hue —
// 1.0 would be Mellow's look; 0.85 leaves a little headroom for the sky term under it.
const vec3  END_AMBIENT_COLOR      = to_linear(vec3(0.20, 0.17, 0.25));
const float END_AMBIENT_INTENSITY  = 0.85;

// The End's only "directional" light: the sky itself, from above. Mellow's END_DIRECT palette at
// roughly half strength — full strength flattens the dimension into a single violet ramp, and
// Astra wants the shape to come from the sky/nebula and the blocklight pools instead.
const vec3  END_SKY_LIGHT_COLOR     = to_linear(vec3(0.30, 0.23, 0.45));
const float END_SKY_LIGHT_INTENSITY = 0.50;

// Night vision lifts the ambient only, never the emissive or the fog. Cool rather than green:
// vanilla's night-vision overlay is green, but a green lift reads as a filter over a violet
// dimension, so it is tinted toward the sky instead. UNVERIFIED (SC-6).
const vec3  END_NIGHT_VISION_TINT = vec3(0.22, 0.20, 0.30);

// Blocklight curve. C1 uses 4.0, C3's nether 2.75. The End has neither the overworld's sun to
// compete with nor the nether's near-total darkness, so it sits between them: tighter than the
// nether's (there IS ambient to fight the pool) but looser than the overworld's (torch light is
// the only thing that reads as "placed light" here). UNVERIFIED (SC-6).
const float END_BLOCKLIGHT_EXPONENT = 3.50;

// Emissive / portal brightening (design.md 4.5: 传送门/折跃光柱的辉光处理). Both multiply on top
// of the user's EMISSIVE_STRENGTH, so the End boost is a relative lift, not an override — same
// shape as C3's, for the reason given in the ⚠ OPTIONAL FROM E1 note above. HDR on purpose: the
// gateway and the pillar beams are the only things that should reach the bloom threshold here.
const float END_EMISSIVE_BOOST      = 1.25;
const float END_PORTAL_BOOST        = 3.20;
const float END_PORTAL_SHIMMER      = 0.15;   // ±15% on the portal boost
const float END_PORTAL_SHIMMER_RATE = 1.9;    // rad/s
// The beams are vertical, so their glow travels along Y: a slow rising band reads as energy moving
// up the column. Requires no world anchor (only the fragment's own height), which is why it is
// implementable at all — see the scope note on end_emissive_boost().
const float END_BEAM_TRAVEL_SCALE  = 0.35;    // radians per block of height
const float END_BEAM_TRAVEL_RATE   = 1.10;    // rad/s, downward-reading when combined with sin()
const float END_BEAM_TRAVEL_DEPTH  = 0.25;    // ±25% travelling modulation on portal surfaces

const float END_TAU = 6.28318530718;

// --- celestial rotation -------------------------------------------------------------------------
// The whole sky (stars AND nebula) turns once per ~30 minutes: 0.0035 rad/s = one turn in 1795 s.
// Slow enough to be invisible frame to frame, fast enough to read as "the sky is alive" across a
// screenshot pair. UNVERIFIED (SC-6).
const float END_SKY_ROTATION_RATE = 0.0035;
// The animated pole is tilted off the zenith, because a star field circling straight overhead reads
// as a turntable. end_rotate_sky() applies Rz(tilt) AFTER Ry(angle), so the rotated frame's zenith
// sits at (sin(tilt), cos(tilt), 0) at time zero and then revolves around the world zenith on a
// tilt-degree cone once per turn: the celestial pole itself wanders instead of spinning about one
// fixed star. Accepted for v1 because it costs two multiplies and keeps the horizon band's posture
// changing over a session; if it reads as a wobble rather than as a sky at SC-6, the fix is local
// to end_rotate_sky() - rotate about the constant axis normalize(vec3(TILT_SIN, TILT_COS, 0)) with
// Rodrigues, which holds the pole still for three more multiplies. Tilt = 16 degrees = 0.279253
// rad; the two literals below are its sine and cosine, written out because a const initializer may
// not call sin()/cos().
const float END_SKY_TILT_SIN = 0.275637;
const float END_SKY_TILT_COS = 0.961262;

// --- star field ---------------------------------------------------------------------------------
// Two layers, where every reference ships one (Mellow 1 hash on a projected grid, Solas 3 hashes on
// one projected grid, Refrax 1 cutoff hash per cell of a six-face cube lattice): a sparse bright
// near layer and a dense faint far layer. Two layers is what gives the field depth ordering — the
// far layer fills the gaps between near stars instead of sharing their lattice.
// "occupancy" is the rejection threshold on the presence hash, so the fraction of cells that hold a
// star is (1 - occupancy): near 1.4%, far 0.5%. The product is a 稠密 star field whose bright stars
// still have dark sky between them.
const float END_STAR_NEAR_DENSITY     = 96.0;
const float END_STAR_NEAR_OCCUPANCY   = 0.986;
const float END_STAR_NEAR_BRIGHTNESS  = 5.00;
const float END_STAR_FAR_DENSITY      = 176.0;
const float END_STAR_FAR_OCCUPANCY    = 0.995;
const float END_STAR_FAR_BRIGHTNESS   = 1.60;
// Disc radius in CELL units, and the widest it may be stretched to fight sub-pixel flicker. The
// two must satisfy END_STAR_MAX_RADIUS + END_STAR_JITTER * 0.5 <= 0.5 so a disc can never cross a
// cell face — that is what keeps the field seam-free without sampling neighbours.
const float END_STAR_RADIUS      = 0.16;
const float END_STAR_MAX_RADIUS  = 0.34;
const float END_STAR_JITTER      = 0.28;   // -> max offset 0.14; 0.14 + 0.34 = 0.48 < 0.5
// Brightness distribution: many faint, few bright, from the same hash that gated the cell. The
// cube is Refrax's shape (atmosphere.glsl:192-194 normalizes the excess over the cutoff then cubes
// it); Mellow's is linear in the same excess (sky.glsl:64) and Solas clamps a three-hash product
// linearly (skyEffects.glsl:20-23). The cube is what keeps a bright star rare enough to read as
// one star rather than as a patch of glow.
const float END_STAR_MIN_BRIGHTNESS   = 0.20;
const float END_STAR_BRIGHTNESS_RANGE = 1.00;
// Twinkle. Restrained on purpose — design.md 2.4 bans TAA and an AA pass, so animation that
// changes luminance per frame at the pixel level is exactly what must stay small.
const float END_STAR_TWINKLE_AMPLITUDE = 0.30;
const float END_STAR_TWINKLE_RATE_A    = 1.30;   // rad/s
const float END_STAR_TWINKLE_RATE_B    = 0.79;   // rad/s, deliberately not a ratio of A
// Star colour scatter, keyed by a per-star hash: cool violet-white to pale gold.
const vec3  END_STAR_COOL_TINT = vec3(0.72, 0.80, 1.00);
const vec3  END_STAR_WARM_TINT = vec3(1.00, 0.86, 0.68);
// Overall visibility: Solas uses 0.4 in the End, and dims the field by half per unit of nebula
// density behind which the star sits. Astra keeps the relationship with its own numbers.
const float END_STAR_VISIBILITY      = 0.42;
const float END_NEBULA_STAR_DIMMING  = 0.21;

// --- nebula -------------------------------------------------------------------------------------
// lib/noise.glsl takes coordinates in TEXEL space (fbm_fast divides by noiseTextureResolution =
// 256 internally), so the scale constants are in texels of the projected plane, not in texture
// space. The projection is stereographic from the nadir, for which |plane| == tan(theta / 2) where
// theta is the angle from the sky pole: 1 plane unit at the horizon, so one noisetex texel spans
// 1 / END_NEBULA_SCALE plane units and a 4-texel noise feature reads as roughly 2*atan(4/30) ~ 15
// degrees of sky. The second layer is 1.55x finer, which is where the filament detail comes from.
// UNVERIFIED (SC-6) — the real feature size of MC's noisetex is not measured on this machine.
const float END_SKY_PROJECTION_MIN_DENOM = 0.06;
const float END_NEBULA_SCALE          = 30.0;
const float END_NEBULA_SCALE_SECOND   = 46.5;   // 1.55x the primary layer
const float END_NEBULA_DRIFT          = 0.00015;
// fbm_fast(detail=2) sums weights 0.5 + 0.25 over a texture that averages ~0.5, so its mean is
// ~0.375 and its range is 0..0.75. Thresholding just above the mean and gaining is what carves
// filaments out of it; Solas does the same at -0.7 / -0.8 on a stack whose mean is ~1.06, i.e. the
// same position relative to its own mean.
const float END_NEBULA_THRESHOLD_PRIMARY  = 0.34;
const float END_NEBULA_THRESHOLD_SECOND   = 0.38;
const float END_NEBULA_GAIN               = 3.00;
const float END_NEBULA_BAND_EXP           = 3.0;   // pow of (1 - |rotated latitude|)
const float END_NEBULA_SECOND_WEIGHT      = 0.35;
// 0.30 against Solas's shipped 1.25: design.md 4.5 asks for 微弱 / 默认开低强度. Astra's own knob
// (Complementary r5.9 ships no End nebula to copy); cut 0.35 -> 0.30 on 2026-09-10 for the
// 减少泛亮 pass — the nebula is additive over the whole rotated band, so its brightness is part
// of the sky's washout budget. UNVERIFIED (SC-6).
const float END_NEBULA_BRIGHTNESS         = 0.30;
const vec3  END_NEBULA_VIOLET = to_linear(vec3(0.30, 0.23, 0.45));
const vec3  END_NEBULA_TEAL   = to_linear(vec3(0.00, 0.45, 0.25));
const vec3  END_NEBULA_AMBER  = to_linear(vec3(0.45, 0.30, 0.10));

// --- void fog -----------------------------------------------------------------------------------
// Y=30 is where the void fog starts (Mellow's END_FOG_START_HEIGHT default, settings.glsl:122),
// over a 10-block band (the hard-coded +10 in fog.glsl:46). Standing on the main island (Y~65) the
// gate is fully open, so only the distance ramp and the residual act; below the island the gate
// closes the sky out and the fog takes over.
const float END_VOID_TOP_Y        = 30.0;
const float END_VOID_HEIGHT_BAND  = 10.0;
const float END_VOID_REACH        = 32.0;   // Mellow: min(Dist / 32, 1)
const float END_VOID_SATURATION   = 3.0;    // Mellow: 1 - exp(-3 * t)
const float END_VOID_RESIDUAL     = 0.05;   // Mellow: + 0.0497
// Astra's addition: above the island the horizon still never reads as clear air, which is what
// makes the End feel airless at any height. mix()'s edge0 < edge1 form keeps the slider monotone.
const float END_VOID_MIN_STRENGTH = 0.55;
// 黑紫 -> 黑 (design.md 4.5). The crush is 0.90 rather than 1.0 so the depth ramp stays visible at
// the bottom of the world instead of clipping to one flat value.
const float END_VOID_TINT_REACH   = 64.0;
const float END_VOID_TINT_CRUSH   = 0.90;
const float END_VOID_FADE_LOW     = 0.0;    // world-horizon start of the sky's void fade
const float END_VOID_FADE_HIGH    = 0.6;    // fully void by ~37 degrees below the horizon
// Border fog: same pow4 shape as C3's, because both dimensions need a ramp that closes in earlier
// than the overworld's pow3 (design.md 4.5 / Mellow fog.glsl:16-30 for the nether, and the End's
// airless horizon wants the same tightening).
const float END_FOG_FAR_COEFF     = 6.0;
const float END_FOG_FAR_EXP       = 4.0;

// ---------------------------------------------------------------------------
// Hashing
// ---------------------------------------------------------------------------

// Integer avalanche hash, three integer inputs to one float in [0, 1).
// Not a port from any of the four reference packs: Mellow (lib/util.glsl:1-3) and Solas
// (skyEffects.glsl:2-4) both use fract(sin(dot(p, k)) * 43758.5453). The structure is kept
// (quantize a coordinate, hash it, threshold toward 1.0) but the function is swapped, because
// this field's cell coordinates reach a few hundred and a sine-based hash spends its whole
// mantissa on the argument reduction there, while an integer madd chain costs less and cannot
// drift with frame state. Constants are the widely published Elias/Hoskins mixing words.
uint end_hash_uint(uvec3 p) {
	uint h = p.x * 1597334677u + p.y * 3812015801u + p.z * 2798796415u;
	h = (h ^ (h >> 16)) * 2246822507u;
	h = (h ^ (h >> 13)) * 3266489909u;
	return h ^ (h >> 16);
}

// The cell lattice is built from a unit direction times the density, so |p| <= END_STAR_FAR_DENSITY
// and the int -> uint reinterpretation is well within range for every cell this file can reach.
float end_hash(ivec3 p) {
	return float(end_hash_uint(uvec3(p))) * (1.0 / 4294967296.0);
}

// ---------------------------------------------------------------------------
// Sky frame
// ---------------------------------------------------------------------------

// Ry(angle) then Rz(tilt): a rigid rotation of the view direction whose effective pole is tilted
// off the zenith. Applied to the direction BEFORE any projection or lattice build, which is the
// whole reason this file can rotate at all (see the design note in the header).
vec3 end_rotate_sky(vec3 dir, float angle) {
	float c = cos(angle);
	float s = sin(angle);

	vec3 yawed = vec3(c * dir.x + s * dir.z,
	                  dir.y,
	                 -s * dir.x + c * dir.z);

	return vec3(END_SKY_TILT_COS * yawed.x - END_SKY_TILT_SIN * yawed.y,
	            END_SKY_TILT_SIN * yawed.x + END_SKY_TILT_COS * yawed.y,
	            yawed.z);
}

// Stereographic sky projection: the direction mapped from the sphere onto the horizon plane,
// projected from the nadir, so plane = xz / (1 + y) and |plane| == tan(theta / 2) with theta the
// angle from the zenith: 0 overhead, 1 at the horizon. Chosen over the two reference forms because
// each of those has a defect exactly where this file needs clean behaviour:
//   - Mellow (sky.glsl:55) uses PlayerPos / (y + length(PlayerPos.xz)). For a unit direction that
//     denominator is zero on the whole ring where y == -length(xz), i.e. 45 degrees BELOW the
//     horizon, and it changes sign across that ring: the lookup grid explodes and mirrors there.
//     Harmless in Mellow because it fades the field to nothing under the horizon anyway; not
//     harmless for a nebula that this file does want to draw down to the horizon.
//   - Solas (skyEffects.glsl:14) uses worldPos.xz / (length(worldPos.y) + length(worldPos.xz)). The
//     absolute value makes it finite everywhere, but it folds the lower hemisphere onto the same
//     disc as the upper one, so every sky direction below the horizon samples the star that is
//     directly above it — which is why that implementation needs its own separate y mask.
// Astra's map is conformal (nebula filaments keep their shape), its zenith-to-horizon scale
// variation is only 2:1, and its single singularity is the nadir — the one direction design.md 4.5
// wants black — with the denominator floor keeping even that finite.
vec2 end_sky_projection(vec3 dir) {
	return dir.xz / max(dir.y + 1.0, END_SKY_PROJECTION_MIN_DENOM);
}

// 1.0 at or below the island level, 0.0 END_VOID_HEIGHT_BAND blocks above it. smoothstep already
// clamps outside its edges, so the whole world column is covered without an explicit clamp.
float end_void_depth_gate(float worldY) {
	return 1.0 - smoothstep(END_VOID_TOP_Y, END_VOID_TOP_Y + END_VOID_HEIGHT_BAND, worldY);
}

// The void's colour as a function of height: dark violet down to (almost) black. Shared by
// end_fog() (as fogColor), end_sky() (as the base AND as what the sky fades to below the horizon)
// and by nothing else, which is what makes the horizon seam disappear. C3 uses the same
// share-the-tint idiom between nether_fog() and nether_sky().
vec3 end_void_tint(float worldY) {
	float depth = clamp((END_VOID_TOP_Y - worldY) * (1.0 / END_VOID_TINT_REACH), 0.0, 1.0);
	return END_VOID_COLOR * (1.0 - END_VOID_TINT_CRUSH * depth);
}

// ---------------------------------------------------------------------------
// Star field
// ---------------------------------------------------------------------------

// One layer of the field. Returns the scalar contribution and writes the star's colour key to hue.
// The lattice is 3D and built from the ROTATED direction, so the disc centre is offset in a random
// 3D direction; the radial part of that offset only thickens the shell, which is harmless here.
float end_star_layer(
	vec3  dirRot,
	float time,
	float density,
	float occupancy,
	float brightness,
	out float hue
) {
	hue = 0.0;

	vec3  g     = dirRot * density;
	vec3  cell  = floor(g);
	vec3  local = g - cell - 0.5;
	ivec3 id    = ivec3(cell);

	// fwidth BEFORE the occupancy branch, on purpose: implicit derivatives inside divergent control
	// flow are undefined, not merely unsafe. fwidth() is abs(dFdx) + abs(dFdy) per component, so the
	// max of its three components is a conservative pixel footprint in cell units.
	float pixel = max(max(fwidth(g).x, fwidth(g).y), fwidth(g).z);

	float present = end_hash(id);
	if (present < occupancy) { return 0.0; }          // design.md 5: early-out

	// Brightness comes from how far past the threshold this cell landed: many faint, few bright.
	float mag    = (present - occupancy) * (1.0 / (1.0 - occupancy));
	float bright = END_STAR_MIN_BRIGHTNESS + END_STAR_BRIGHTNESS_RANGE * mag * mag * mag;

	// No TAA and no AA pass (design.md 2.4), so a sub-pixel star must not appear and vanish between
	// frames. The disc is widened to the pixel footprint and its peak is attenuated by the square of
	// the widening, which conserves the flux a star deposits per frame: the eye integrates spatially
	// exactly as an AA pass would, but with no motion vector and no history buffer.
	float radius = min(max(END_STAR_RADIUS, pixel), END_STAR_MAX_RADIUS);
	float spread = END_STAR_RADIUS / radius;

	vec3 jitter = (vec3(end_hash(id + 7), end_hash(id + 31), end_hash(id + 53)) - 0.5)
	            * END_STAR_JITTER;
	vec3  off = local - jitter;
	float d2  = dot(off, off) / (radius * radius);
	float x   = max(0.0, 1.0 - d2);
	// Quartic: reaches exactly 0 at the support edge, and its first derivative does too, which is
	// what makes the clamp to END_STAR_MAX_RADIUS invisible across a cell face.
	float disc = x * x * x * x;

	hue = end_hash(id + 151);

	// Two non-commensurate partials so the beat period is long, driven off one per-star phase so the
	// field never blinks in unison. The second partial runs off the CONJUGATE phase: Refrax's twinkle
	// (atmosphere.glsl:203-205) scales the phase instead, and its shape must not be carried into
	// Astra's file. Amplitude is the only animation touching a single-pixel feature, hence small.
	float phase   = hue * END_TAU;
	float twinkle = 1.0 + END_STAR_TWINKLE_AMPLITUDE * (
		 0.62 * sin(time * END_STAR_TWINKLE_RATE_A + phase)
		+ 0.38 * sin(time * END_STAR_TWINKLE_RATE_B - phase));

	return bright * disc * spread * spread * twinkle * brightness;
}

// Both layers, tinted per star, masked by how much sky the view direction uncovers and by the
// nebula sitting in front of them. Kept free of runtime branches around the derivative calls by the
// caller's #ifdef only.
vec3 end_star_field(vec3 dirRot, vec3 worldViewDir, float nebulaDensity, float time) {
	float hueNear = 0.0;
	float hueFar  = 0.0;

	float nearLayer = end_star_layer(dirRot, time, END_STAR_NEAR_DENSITY,
	                                END_STAR_NEAR_OCCUPANCY, END_STAR_NEAR_BRIGHTNESS, hueNear);
	float farLayer  = end_star_layer(dirRot, time, END_STAR_FAR_DENSITY,
	                                END_STAR_FAR_OCCUPANCY, END_STAR_FAR_BRIGHTNESS, hueFar);

	// Up-facing only: below the world horizon the sky is the void, and Solas/Mellow both fade the
	// field out there (sqrt(VoU) versus smoothstep(0, 0.1, y)); sqrt keeps more of the low sky.
	float up         = clamp(worldViewDir.y, 0.0, 1.0);
	float visibility = sqrt(up) * max(0.0, END_STAR_VISIBILITY - nebulaDensity * END_NEBULA_STAR_DIMMING);

	vec3 tintNear = mix(END_STAR_COOL_TINT, END_STAR_WARM_TINT, hueNear);
	vec3 tintFar  = mix(END_STAR_COOL_TINT, END_STAR_WARM_TINT, hueFar);

	return (tintNear * nearLayer + tintFar * farLayer) * visibility;
}

// ---------------------------------------------------------------------------
// Nebula (design.md 4.5: 可选微弱星云，默认开、低强度 — Solas's structure, low-config)
// ---------------------------------------------------------------------------

// Two thresholded noisetex octave stacks on the rotated sky plane, drifting against each other,
// confined to a band around the sky's great circle. Returns colour; density is the 0..1 coverage
// the caller feeds back into end_star_field() as a dimming term.
// Deliberately absent: Solas's spiral domain warp (skyEffects.glsl:49-58), which is anchored to a
// synthetic End sun vector that Astra does not have and does not want (design.md 4.5 asks for a
// vacuum sky, not a second star).
vec3 end_nebula(vec3 dirRot, float time, out float density) {
	vec2  plane = end_sky_projection(dirRot);
	float drift = time * END_NEBULA_DRIFT;

	// Counter-drift: the two layers move in different directions, which is what makes the overlap
	// read as boiling rather than as one sliding sheet (Solas alternates the sign per octave,
	// skyEffects.glsl:75-84; Mellow counter-rotates its two End bands, sky.glsl:112-113).
	float primary = fbm_fast(plane * END_NEBULA_SCALE        + vec2(drift, -drift * 0.6), 2);
	float second  = fbm_fast(plane * END_NEBULA_SCALE_SECOND - vec2(drift * 1.35, drift * 0.4), 2);

	primary = clamp((primary - END_NEBULA_THRESHOLD_PRIMARY) * END_NEBULA_GAIN, 0.0, 1.0);
	second  = clamp((second  - END_NEBULA_THRESHOLD_SECOND)  * END_NEBULA_GAIN, 0.0, 1.0);

	// Band on the rotated frame's own great circle, not on the world horizon: the stars and this
	// band turn together as one rigid celestial sphere, which is what a sky reads as. Refrax
	// instead anchors its band to a fixed world axis (atmosphere.glsl:395-396) and lets the stars
	// cross it; Astra's frame both tilts and turns, so the band's posture against the horizon drifts
	// over a session either way, and sharing the star frame costs nothing.
	float band = pow(max(0.0, 1.0 - abs(dirRot.y)), END_NEBULA_BAND_EXP);

	float visibility = band * END_NEBULA_BRIGHTNESS;

	vec3 colour = mix(END_NEBULA_VIOLET, END_NEBULA_TEAL, primary) * primary
	            + mix(END_NEBULA_TEAL, END_NEBULA_AMBER, second) * (second * END_NEBULA_SECOND_WEIGHT);

	density = clamp((primary + second) * visibility, 0.0, 1.0);

	return colour * visibility;
}

// ---------------------------------------------------------------------------
// Fog (design.md 4.5: void 雾随深度渐变（黑紫→黑）)
// ---------------------------------------------------------------------------

// Drop-in replacement for B2's global/atmosphere/fog.glsl:fog_v2() in the End: same return shape,
// vec4(fogColor, fogFactor) with the sky blend strength as an out parameter, so E1's call site
// stays `mix(sceneColor, fogColor + skyColor * skyFogStrength, fogFactor)` with skyColor coming
// from end_sky(). Identical to nether_fog() in shape on purpose, minus the params struct: the End
// has no biome colour to read, so there is nothing for it to carry.
//
// What is NOT reused from fog_v2, and why (the same list as C3's, with one addition):
//   - atmosphereFogCoefficient / FOG_DENSITY: the overworld's pow(d,3) curve is CPU-precomputed for
//     a sun-lit atmosphere. The End has its own ramp with END_FOG_DENSITY, so neither the uniform nor
//     the overworld slider affects it.
//   - CAVE_FOG / skyLightStrength: no sky light gradient exists here, so there is no cave transition.
//   - AIR_PERSPECTIVE / BIOME_TINT: both are sun-direction effects. There is no sun.
//   - new here: the End's ramp is a LINEAR multiply (Mellow's shape), not an exponent of a density,
//     so END_FOG_DENSITY scales the finished factor and clamps at the top of its range instead of
//     steepening a curve. The slider stays monotone; it just saturates sooner than FOG_DENSITY does.
// The blindness / water / lava overrides ARE kept with B2's and C3's shapes: they are
// dimension-independent player states, and dropping them here would silently remove them from the End.
//
//   fragDistance        distance for the void ramp
//   borderFragDistance  distance for the pow4 border ramp; differs from fragDistance only for Voxy (C5)
//   playerPos           camera-relative fragment position; absolute Y drives the whole depth model
vec4 end_fog(
	out float skyFogStrength,
	float fragDistance,
	float borderFragDistance,
	vec3 playerPos
) {
	float worldY = playerPos.y + cameraPosition.y;

	// Distance ramp, saturating at END_VOID_REACH blocks, plus the residual. The gate is the depth
	// term: 1.0 below the island level, END_VOID_MIN_STRENGTH up in the open sky.
	float t = min(fragDistance * (1.0 / END_VOID_REACH), 1.0);
	float voidFactor = (1.0 - exp(-END_VOID_SATURATION * t) + END_VOID_RESIDUAL)
	                 * mix(END_VOID_MIN_STRENGTH, 1.0, end_void_depth_gate(worldY));

	float fogFactor = voidFactor;

	#ifdef BORDER_FOG
		float farRatio = borderFragDistance > 0.0 ? borderFragDistance / borderFogDistance : 0.0;
		float borderFactor = 1.0 - exp(-END_FOG_FAR_COEFF * pow(farRatio, END_FOG_FAR_EXP));
		// Two independent ramps over the same colour: combine as complementary coverage, so neither
		// one can subtract from the other.
		fogFactor = 1.0 - (1.0 - fogFactor) * (1.0 - borderFactor);
	#endif

	fogFactor = clamp(fogFactor * (END_FOG_DENSITY * 0.01), 0.0, 1.0);

	vec3 fogColor = end_void_tint(worldY);

	skyFogStrength = SKY_FOG_STRENGTH * 0.01;

	if (blindness > 0.0001) {
		fogFactor = max(0.85, 1.0 - exp(-pow(fragDistance * blindness * 0.5, 2.0)));
		fogColor = vec3(0.0);
		skyFogStrength = 0.0;
	} else if (isEyeInWater == 1) {
		// The End has no water source blocks, but a carried bucket or a broken portal can still put
		// the eye in water; keep the override so the case is not unhandled.
		fogFactor = 1.0 - exp(-pow(fragDistance * 0.02 * (UNDERWATER_FOG_DENSITY * 0.01), 2.0));
		fogColor = end_void_tint(worldY);
		skyFogStrength = 0.0;
	} else if (isEyeInWater == 2) {
		// Lava CAN be placed in the End. Submerged: near-zero visibility with the lava's own colour.
		fogFactor = max(0.85, 1.0 - exp(-pow(fragDistance * 0.5, 2.0)));
		fogColor = vec3(1.0, 0.05, 0.0);
		skyFogStrength = 0.0;
	}

	if (skyFogStrength > 0.0) {
		// B2's weak-fog zeroing, kept so the caller's sky path is skipped for nearby terrain.
		fogFactor *= smoothstep(0.01, 0.015, fogFactor);
	}

	return vec4(fogColor, fogFactor);
}

// ---------------------------------------------------------------------------
// Sky (design.md 4.5: 真空暗天空 + 稠密星野（缓慢旋转）+ 微星云)
// ---------------------------------------------------------------------------

// Deliberately absent, item by item: sun, moon, sun/moon discs, vanilla cloud layer, planar clouds,
// aurora, rainbow, air perspective, weather, sky-light scattering, star twinkle from the overworld
// night cycle. That is 主世界云/日光相关特性整体裁剪 (design.md 4.5) taken literally — this function
// does not branch those features off, it never mentions them, so there is nothing for E1 to keep
// alive in world1/. Mellow reaches the same state by only calling get_stars() under
// OVERWORLD||END (program/deferred1.fsh:51-56); Solas #undefs the list wholesale
// (lib/common.glsl:344-366).
//
//   worldViewDir — NORMALIZED player-relative world-space view direction (y is up).
//   voidTint     — end_void_tint(cameraPosition.y + eye height), computed once by the caller and
//                  shared with end_fog() so the horizon seam between sky and distant fog is exact.
//   time         — frameTimeCounter.
vec3 end_sky(vec3 worldViewDir, vec3 voidTint, float time) {
	vec3 dirRot = end_rotate_sky(worldViewDir, time * END_SKY_ROTATION_RATE);

	// The base IS the void colour, so a clear patch of End sky and the fog in front of it are the
	// same value; everything below is additive on top of that.
	vec3 sky = END_VOID_COLOR;

	float nebulaDensity = 0.0;

	#ifdef END_NEBULA
		sky += end_nebula(dirRot, time, nebulaDensity);
	#endif

	#ifdef STARS
		sky += end_star_field(dirRot, worldViewDir, nebulaDensity, time);
	#endif

	// Below the world horizon, the sky becomes the void rather than continuing to be a picture of a
	// distant sky. Mellow does this with a fogify ramp (sky.glsl:128); a smoothstep is used here so
	// the ramp cannot divide by a small width, and mixing toward the CALLER's tint (not toward a
	// constant black) is what keeps the seam exact at every height and every fog density.
	float voidFade = 1.0 - smoothstep(END_VOID_FADE_LOW, END_VOID_FADE_HIGH, -worldViewDir.y);

	// Complementary r5.9 program/deferred1.glsl:386: `color.rgb *= 1.0 - maxBlindnessDarkness;`
	// applied to the composed End sky (base + stars there, base + nebula + stars here).
	// maxBlindnessDarkness = max(blindness, darknessFactor) (shaders.properties:275); Astra's
	// frozen set carries only `blindness` (lib/uniforms.glsl:48), so the Warden darknessFactor
	// half is missing -> docs/handoffs/end.md. Without this term the sky kept full brightness
	// while end_fog() blacked the terrain out under the Blindness effect.
	return mix(voidTint, sky, voidFade) * (1.0 - blindness);
}

// ---------------------------------------------------------------------------
// Lighting (design.md 4.5: 褪色环境光、末地无日光)
// ---------------------------------------------------------------------------

// Blocklight + handheld on the End's own curve. Structurally C1's block_lighting() minus the
// daylight suppression and C3's minus the nether's widened pool: BLOCKLIGHT_SUPPRESSION exists to
// stop torches glowing in daylight, and there is no daylight here.
//
// The #ifdef is a SECOND gate on the handheld term and is deliberate (same reasoning as C3's): it
// compiles the pow out entirely rather than evaluating pow(0.0, e), and it means no caller can
// bypass the option by feeding this function a raw value.
vec3 end_block_lighting(float blockLight, float heldLight) {
	float intensity = pow(blockLight, END_BLOCKLIGHT_EXPONENT) * (BLOCKLIGHT_STRENGTH * 0.01);

	#ifdef HANDHELD_LIGHTING
		intensity += pow(heldLight, END_BLOCKLIGHT_EXPONENT);
	#endif

	return BLOCKLIGHT_COLOR * min(1.0, intensity);
}

// Emissive / portal / beam glow, as a scalar multiplier on the surface's own albedo — the same
// factor-not-colour shape as C3's nether_emissive_boost(), for the reason given there (the
// composer ends in one `surfaceColor * lighting` multiply, so passing the albedo in would square
// it). See the ⚠ OPTIONAL FROM E1 note in the interface contract for the case this cannot cover.
//
// Two modulations, both HDR enough to reach the bloom threshold: a slow uniform shimmer on every
// portal surface (an open gateway flickers), and a travelling vertical band, which is the
// 折跃光柱 reading — the obsidian pillars' beams and the gateway columns are vertical, so height IS
// their axis of motion. No world anchor is used, only the fragment's own height, because the frozen
// uniform set has none for the pillars or the dragon's beam.
float end_emissive_boost(float emissiveMask, float portalMask, float time, vec3 playerPos) {
	if (emissiveMask < 0.0001 && portalMask < 0.0001) { return 0.0; }

	float boost = (EMISSIVE_STRENGTH * 0.01)
	            * mix(END_EMISSIVE_BOOST, END_PORTAL_BOOST, portalMask);

	boost *= 1.0 + END_PORTAL_SHIMMER * portalMask * sin(time * END_PORTAL_SHIMMER_RATE);
	boost *= 1.0 + END_BEAM_TRAVEL_DEPTH * portalMask
	             * sin(playerPos.y * END_BEAM_TRAVEL_SCALE + time * END_BEAM_TRAVEL_RATE);

	return boost * max(emissiveMask, portalMask);
}

// The End lighting composer — the counterpart of C1's diffuse_lighting() and C3's nether_lighting(),
// and what E1 calls INSTEAD of them under DIMENSION_END.
//
// Terms, in design.md 4.5's order: 褪色环境光 (faded ambient) + 天空漫射 (an up-facing hemispherical
// term standing in for a sun, gated by how much sky the point can see), the sum shaped by
// Complementary r5.9's directionShade (ported, see below) + 方块光 (blocklight, own curve) +
// 发光体/传送门辉光 (emissive). There is no sun/moon term and therefore no shadow-map sample:
// nothing here could cast a shadow that the shadow map could represent, and Mellow reaches the same
// conclusion by setting Shadow = vec3(1) for the End (lighting.glsl:127, in the branch opened at
// :89). Solas does shadow the End, against a synthetic sun (lib/common.glsl:313-325) —
// Astra's 真空暗天空 brief is the reason not to follow it, and it is also why this path is
// cheaper per fragment than the overworld's.
//
// Two deliberate departures from the pre-2026-09-10 shape, both Complementary r5.9 ports:
//   - NO cave floor minimum: minimumLighting.glsl:2 puts the whole term behind `#if !defined END`.
//     Undersides and caves may now reach (near-)black against the starfield, which is what gives
//     the islands their silhouette (保持地形轮廓可辨). MIN_AMBIENT stays meaningful in the
//     overworld and the nether only.
//   - Directional shaping is Complementary's directionShade, not C1's ambient_strength(): one
//     definition of "up-faces are brighter" per dimension, now the reference pack's for the End.
//     Relief relative to the old 0.67+0.33y shape: up-face unchanged at 1.0, E/W side 0.675² ≈
//     0.456, N/S side 0.806² ≈ 0.650, down-face 0.5² = 0.25 — roughly double the old directional
//     contrast, which is the 减少泛亮 mechanism: the flat ambient floor is gone, not lowered.
// Night vision, blocklight and the emissive/portal boost stay LINEAR and unshaded: Comp folds its
// blocklight into a sqrt (mainLighting.glsl:613-616), but Astra's BLOCKLIGHT_COLOR is
// SC-34-calibrated for exactly this linear add, and Comp's emission is unshaded too
// (sqrt(pow2(emission)) == emission).
//
// Returns surfaceColor * lighting, linear HDR, ready for the tonemap in global/post/grading.glsl.
vec3 end_lighting(
	vec3  surfaceColor,
	vec3  worldNormal,
	vec3  playerPos,
	float blockLight,
	float emissiveMask,
	float portalMask,
	float time,
	EndParams params
) {
	float worldY = playerPos.y + cameraPosition.y;

	// 1. Faded ambient + sky diffusion, the sceneLighting sum. The sky term is the violet
	//    hemisphere above, from Mellow's up-facing NdotL with the shadow machinery dropped, gated
	//    by the same depth term the fog uses, so a point under the island — where the sky is void —
	//    loses the term and falls back to blocklight alone.
	vec3 sceneLighting = END_AMBIENT_COLOR * END_AMBIENT_INTENSITY;

	float skyExposure = 1.0 - end_void_depth_gate(worldY);
	sceneLighting += END_SKY_LIGHT_COLOR
	                 * (END_SKY_LIGHT_INTENSITY * max(0.0, worldNormal.y) * skyExposure);

	// Complementary r5.9 lib/lighting/mainLighting.glsl:507-512, verbatim (the `!defined NETHER`
	// branch, which is the branch the End takes there):
	//     float NdotUM = 0.75 + NdotU * 0.25;
	//     float NdotNM = 1.0 + 0.075 * absNdotN;
	//     float NdotEM = 1.0 - 0.1 * absNdotE2;
	//     directionShade = NdotUM * NdotEM * NdotNM;
	// Axis mapping: its NdotE/NdotN are dotted against eastVec/northVec, which are
	// normalize(gbufferModelView[0].xyz) / normalize(gbufferModelView[2].xyz)
	// (program/gbuffers_terrain.glsl:57-58) — the world +X/+Z axes carried into view space.
	// Dot products are rotation-invariant, so in Astra's player-relative WORLD-space interface
	// the same products are simply the normal's components.
	float NdotUM = 0.75 + worldNormal.y * 0.25;
	float NdotNM = 1.0 + 0.075 * abs(worldNormal.z);
	float NdotEM = 1.0 - 0.1 * abs(worldNormal.x) * abs(worldNormal.x);
	float directionShade = NdotUM * NdotEM * NdotNM;

	// mainLighting.glsl:613: `pow2(directionShade * vanillaAO)` gates the whole scene sum there.
	// Astra's End interface carries no per-vertex AO (glColor.a never reaches scene.glsl), so the
	// gate is directionShade² alone -> docs/handoffs/end.md asks E1 for the AO channel.
	sceneLighting *= directionShade * directionShade;

	// Night vision lifts the ambient only, never the emissive or the fog. Flat and unshaded, as
	// Astra tuned it (Comp's nightVision add sits inside its shaded minLighting slot instead —
	// not followed: a visibility aid that dims on down-faces defeats its purpose).
	vec3 lighting = sceneLighting
	              + params.nightVision * END_NIGHT_VISION_TINT;

	// 2. Blocklight + handheld, on the End curve. C1's held_light_strength() is the one definition
	//    of the handheld ramp (it already applies HANDHELD_LIGHT_STRENGTH and self-gates on
	//    HANDHELD_LIGHTING), so it is called rather than re-derived.
	lighting += end_block_lighting(
		blockLight,
		held_light_strength(params.heldLightBase, playerPos));

	// 3. Emissive / portal / beam glow.
	lighting += end_emissive_boost(emissiveMask, portalMask, time, playerPos);

	return surfaceColor * lighting;
}

#endif
