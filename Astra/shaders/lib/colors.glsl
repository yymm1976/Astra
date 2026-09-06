#ifndef ASTRA_LIB_COLORS_GLSL
#define ASTRA_LIB_COLORS_GLSL

// Astra v1 — lib/colors.glsl
// Light-source palette (design.md 3.1: 调色板 / 光色常量). C1 owns the *lighting*
// section populated here; the atmosphere/sky palette (sunlight, moonlight, skyAmbient
// colour curves) is D2's and is NOT baked into constants — it arrives per-frame as the
// LightParams fields documented in global/lighting/diffuse.glsl.
//
// Provenance (dual source — see THIRD-PARTY.md):
//   - BLOCKLIGHT_COLOR, MIN_AMBIENT_TINT: From Steadfast 0.8.0 (GPLv3 + Section 7
//     additional terms) by coderbot, source: _analysis/Steadfast-0.8.0/shaders/
//     shaders.properties (blocklightColor ORANGER_BLOCKLIGHT default; minAmbientMinishita).
//     This file is a derivative of Steadfast and is licensed under the GNU General Public
//     License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
//     _analysis/Steadfast-0.8.0/LICENSE.md. Redistribution is permitted only under that
//     license including Steadfast's Section 7 additional terms.
//   - LIGHTNING_TINT: adapted from Refrax v1.3.1 (proprietary), source:
//     _analysis/Refrax_v1.3.1/shaders/lib/thunder.glsl (THUNDER_TINT).
//     PROVENANCE: adapted from Refrax v1.3.1 (proprietary) - REWRITE REQUIRED before distribution
//   Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Uniforms: none. Requires lib/settings.glsl included first (MIN_AMBIENT) — program/*
//           guarantees the order (design.md 3.2 layer 2).
// Consts:   BLOCKLIGHT_COLOR, MIN_AMBIENT_TINT, MIN_AMBIENT_COLOR, LIGHTNING_TINT.
// Owner: C1. Consumers: global/lighting/blocklight.glsl, global/lighting/diffuse.glsl.

// Block-light emission colour (torch / glowstone / fire). HDR-bright on purpose: the
// value exceeds 1.0 and is folded back by the tonemap operator (lib/tonemap.glsl) in the
// final pass chain (program/final.fsh); global/post/grading.glsl (C6) owns the exposure and
// display-space grading wrapped around it.
// This is Steadfast's ORANGER_BLOCKLIGHT default — the profile Steadfast ships for
// MINISHITA / PARAGON / SEMI_NATURAL, i.e. the "warm orange" look, not the paler
// non-oranger vec3(6.4, 2.88, 0.768). BLOCKLIGHT_STRENGTH scales the *intensity* that
// fills this colour (see blocklight.glsl), not the colour itself.
const vec3 BLOCKLIGHT_COLOR = vec3(8.0, 2.0, 0.2);

// Cave-floor minimum ambient. Two parts:
//   MIN_AMBIENT_TINT  — the cool blue-ish direction of "darkness that is not pure black"
//                       (Steadfast minAmbientMinishita = 0.005 * vec3(0.33, 0.8, 1.0)).
//   MIN_AMBIENT       — the user option (settings.glsl, default 5 = 0.05).
// The product reproduces Steadfast's minAmbientMinishita exactly at MIN_AMBIENT = 5:
//   (5 * 0.001) * vec3(0.33, 0.8, 1.0) = vec3(0.00165, 0.004, 0.005).
const vec3 MIN_AMBIENT_TINT  = vec3(0.33, 0.8, 1.0);
const vec3 MIN_AMBIENT_COLOR = (MIN_AMBIENT * 0.001) * MIN_AMBIENT_TINT;

// Lightning flash tint — cool blue-white (Refrax THUNDER_TINT). Applied by
// blocklight.glsl:lightning_point_light(); LIGHTNING_FLASH gates it in diffuse.glsl.
const vec3 LIGHTNING_TINT = vec3(0.80, 0.87, 1.00);

#endif
