#ifndef ASTRA_GLOBAL_LIGHTING_BLOCKLIGHT_GLSL
#define ASTRA_GLOBAL_LIGHTING_BLOCKLIGHT_GLSL

// Astra v1 — global/lighting/blocklight.glsl
// Local (non-sky) illumination: torch/glowstone block light with daylight suppression,
// the handheld point light, and the lightning flash point light.
//
// Provenance (dual source — see THIRD-PARTY.md):
//   - block_lighting(): From Steadfast 0.8.0 (GPLv3 + Section 7
//     additional terms) by coderbot, source: _analysis/Steadfast-0.8.0/shaders/environment/
//     lighting/diffuse.glsl (HeldLightStrength, BlockLighting).
//     This file is a derivative of Steadfast and is licensed under the GNU General Public
//     License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
//     _analysis/Steadfast-0.8.0/LICENSE.md. Redistribution is permitted only under that
//     license including Steadfast's Section 7 additional terms.
//   - lightning_point_light(): adapted from Refrax v1.3.1 (proprietary), source:
//     _analysis/Refrax_v1.3.1/shaders/lib/thunder.glsl (thunderLight). The distance-falloff
//     point-light-with-wrap idea also appears in Solas V2.2b (lightningFlashEffect, "Thanks
//     to Xonk!"); Refrax's normal-aware terrain form is the one ported here.
//     PROVENANCE: adapted from Refrax v1.3.1 (proprietary) - REWRITE REQUIRED before distribution
//   Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Astra changes (naming per design.md 3.2):
//   - blocklightColor / minAmbient are lib/colors.glsl constants, not custom uniforms (the
//     Z3 uniform set is frozen at SC-14). blocklightSuppression and the handheld base are
//     NOT recomputed here — they are documented parameters supplied by E1 (see contract).
//   - BLOCKLIGHT_STRENGTH / HANDHELD_LIGHT_STRENGTH (%) scale the respective source's
//     contribution to the shared 0..1 intensity. The held-light curve is now original
//     Astra, informed by SUMMARY's continuous falloff and player-centre ideas.
//   - The `heldLight` fragment field is computed here from player-head distance
//     (held_light_strength), not carried in: held light has no lightmap, it is purely
//     "how far is this fragment from the light the player is holding".
//
// Uniforms: none directly. Requires lib/settings.glsl (BLOCKLIGHT_STRENGTH,
//           BLOCKLIGHT_SUPPRESSION, HANDHELD_LIGHTING, HANDHELD_LIGHT_STRENGTH,
//           LIGHTNING_FLASH) and lib/colors.glsl (BLOCKLIGHT_COLOR, LIGHTNING_TINT).
// Consts:   LIGHTNING_LIFT, LIGHTNING_RANGE, LIGHTNING_RANGE2, LIGHTNING_INTENSITY.
// Owner: C1. Consumer: global/lighting/diffuse.glsl (same pass).
// Include order (E1 / program/lit.fsh): lib/colors.glsl, then this file BEFORE diffuse.glsl.
//
// Interface contract (E1 unfrozen — every non-frozen input is a documented parameter):
//   skyLight, blockLight  — 0..1 lightmap values (1 = light level 15), E1-supplied.
//   heldLightBase         — CPU: max of both hands' light levels / 15, clamped 0..1.
//                           The source cap and distance curve are applied below;
//                           the shared light consumer subsequently takes its fourth power.
//   blocklightSuppression — CPU: (1 - nightBlocklightFade) * (1 - pow(rainStrength, 4)),
//                           0..1 (Steadfast blocklightSuppression). 0 = no suppression.
//   heldLightSuppression  — CPU: smooth(eyeBrightness.y / 240, 0.4, 0.4), 0..1 (Steadfast
//                           heldLightSuppression). `smooth()` is an Iris properties-only
//                           function with no GLSL equivalent, hence precomputed.
//   playerPos             — camera-relative world space (Mellow convention, matches
//                           lib/transforms.glsl and B1 shadow_mapping).
//   bolt                  — lightningBoltPosition (vec4): xyz = strike position in the same
//                           space as playerPos, w = flash gate (>0.5 active). Not in the
//                           frozen uniforms.glsl, so E1 passes it through.

#include "/lib/colors.glsl"

// SUMMARY ideas (Hysteria/Insanity/BSL): player-centred continuous falloff and
// a bounded source. Original Astra rational intensity, no reference expression
// copied. The existing fourth-power consumer makes intensity fall as (1+d2/20.25)^-2.
// The source cap is applied before the user's strength multiplier.
float held_light_strength(float heldLightBase, vec3 playerPos) {
	#ifndef HANDHELD_LIGHTING
		return 0.0;
	#else
		float base = min(heldLightBase, 14.0 / 15.0) * (HANDHELD_LIGHT_STRENGTH * 0.01);
        if (base <= 0.0) return 0.0;
        vec3 toLight = playerPos + relativeEyePosition;
		return clamp(base * inversesqrt(1.0 + dot(toLight, toLight) / 20.25), 0.0, 1.0);
	#endif
}

// Block light + handheld, combined into one emission so their overlap has no seam
// (Steadfast's min(1.0, a + b) form). The pow(_, 4.0) gives the strong-but-pleasing
// falloff; BLOCKLIGHT_STRENGTH / HANDHELD_LIGHT_STRENGTH scale each source's fill of the
// shared 0..1 intensity, and BLOCKLIGHT_COLOR (HDR) is the tint folded back by the tonemap.
//
// Daylight suppression (design.md 4.1: replaces auto-exposure): block light is dimmed in
// proportion to sky exposure so torches do not glow in daylight. `sqrt(skyLight)` extends
// the suppression across most sky-lit area. Held light is additionally suppressed by the
// player's OWN sky exposure (heldLightSuppression), so a torch held while standing in
// sunlight does not still bleed into a nearby cave.
float local_light_intensity(
	float skyLight,
	float blockLight,
	float heldLight,
	float blocklightSuppression,
	float heldLightSuppression
) {
	float blockLightIntensity = pow4(blockLight) * (BLOCKLIGHT_STRENGTH * 0.01);
	float heldLightIntensity  = pow4(heldLight);   // heldLight already carries HANDHELD_LIGHT_STRENGTH

	#ifdef BLOCKLIGHT_SUPPRESSION
		blockLightIntensity *= 1.0 - sqrt(skyLight) * blocklightSuppression;

		float heldLightSkyLight = sqrt(max(skyLight, heldLightSuppression));
		heldLightIntensity *= 1.0 - heldLightSkyLight * blocklightSuppression;
	#endif

	return blockLightIntensity + heldLightIntensity;
}

vec3 block_lighting(float skyLight, float blockLight, float heldLight,
                    float blocklightSuppression, float heldLightSuppression) {
    return BLOCKLIGHT_COLOR * min(1.0, local_light_intensity(skyLight, blockLight, heldLight,
                                  blocklightSuppression, heldLightSuppression));
}

// ---------------------------------------------------------------------------
// Lightning flash point light (Refrax thunderLight, formula-level port).
//
// A short-lived cool point light lifted above the strike (lightning comes from the sky,
// not the ground), with inverse-square-ish attenuation, a wrapped NdotL so it grazes
// side-on faces, and a sky-exposure gate so it does not light deep caves. LIGHTNING_FLASH
// (bool) is the master switch and is checked by the caller (diffuse.glsl); Astra exposes
// no lightning % slider, so Refrax's THUNDER_STRENGTH is folded into LIGHTNING_INTENSITY.
// ---------------------------------------------------------------------------
const float LIGHTNING_LIFT      = 24.0;                       // bolt origin raised above the strike point
const float LIGHTNING_RANGE     = 88.0;                       // attenuation half-range, blocks
const float LIGHTNING_RANGE2    = LIGHTNING_RANGE * LIGHTNING_RANGE;
const float LIGHTNING_INTENSITY = 2.5;                        // Refrax THUNDER_STRENGTH * 2.5, strength folded in

// Sky-wide component of a lightning flash.
//
// The bolt is a point light in lightning_point_light(), which lights geometry near the
// strike but leaves the sky untouched - so during a thunderstorm the world lit up while
// the sky it is silhouetted against stayed dark, which reads as wrong. A real bolt makes
// the whole cloud deck glow.
//
// Sky exposure gates it exactly as it gates the point light, so a player under a roof or
// underground does not see the flash. The direction term keeps it from being a flat
// full-screen lift: the glow is strongest looking toward the bolt.
vec3 astra_lightning_sky_flash(vec3 worldDir, float skyLight) {
	if (lightningBoltPosition.w < 0.5) return vec3(0.0);
	float reach = smoothstep(0.02, 0.40, skyLight);
	if (reach <= 0.0) return vec3(0.0);
    vec3 bolt=lightningBoltPosition.xyz;
    vec3 boltDirection=bolt*inversesqrt(max(dot(bolt,bolt),1e-4));
	float facing = clamp(dot(normalize(worldDir), boltDirection), -1.0, 1.0);
	float lobe = 0.35 + 0.65 * smoothstep(-0.4, 0.85, facing);
	// LIGHTNING_INTENSITY is the point light's, tuned for inverse-square falloff over
	// tens of blocks; a sky-wide term needs a far smaller coefficient or it turns the
	// whole frame white.
	return LIGHTNING_TINT * (lobe * reach * 0.06);
}

vec3 lightning_point_light(vec3 playerPos, vec3 worldNormal, float skyLight, vec4 bolt) {
	// w is the flash gate: Iris sets lightningBoltPosition.w > 0 only while a bolt is alive.
	if (bolt.w < 0.5) {
		return vec3(0.0);
	}
	float reach = smoothstep(0.02, 0.40, skyLight);
	if (reach <= 0.0) return vec3(0.0);

	vec3 toBolt = bolt.xyz + vec3(0.0, LIGHTNING_LIFT, 0.0) - playerPos;
	float d2 = dot(toBolt, toBolt);
	vec3 L = toBolt * inversesqrt(max(d2, 1e-4));

	float atten = LIGHTNING_RANGE2 / (LIGHTNING_RANGE2 + d2);
	float wrap  = clamp(dot(worldNormal, L) * 0.55 + 0.45, 0.0, 1.0);
	return LIGHTNING_TINT * (atten * wrap * reach * LIGHTNING_INTENSITY);
}

#endif
