#ifndef ASTRA_GLOBAL_LIGHTING_DIFFUSE_GLSL
#define ASTRA_GLOBAL_LIGHTING_DIFFUSE_GLSL

// Astra v1 — global/lighting/diffuse.glsl
// The main surface-lighting composer (design.md 4.1): ambient sky + local light + direct
// sun/moon, summed and multiplied into the surface albedo. This is the single "lit" entry
// E1 calls from program/lit.fsh for every shaded material.
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot
//   source: _analysis/Steadfast-0.8.0/shaders/environment/lighting/diffuse.glsl
//           (AmbientStrength, AmbientSkyLighting, DirectLighting, DiffuseLighting).
// This file is a derivative of Steadfast and is licensed under the GNU General Public
// License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
// _analysis/Steadfast-0.8.0/LICENSE.md. Redistribution is permitted only under that
// license including Steadfast's Section 7 additional terms.
// Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Acceptance mapping (design.md 4.1 / tasks-advanced-2.md C1):
//   仿原版方向性环境光  -> ambient_strength() (0.67 + N.y*0.33) applied to BOTH ambient terms
//   skylight 立方衰减   -> ambient_sky_lighting(): pow(skyLight, 3.0)
//   日光压制生效无跳变   -> block_lighting() sqrt(skyLight) suppression (blocklight.glsl)
//   洞底 minAmbient 正确 -> MIN_AMBIENT_COLOR floor (lib/colors.glsl), never fully black
//   "清爽"观感基线      -> the whole tuned sum below; HDR light colours fold back in C6
//
// Astra changes (naming per design.md 3.2; interface per B-series precedent):
//   - Steadfast's SurfaceFragment struct is NOT reproduced. E1 owns the flat-uint GBuffer
//     (design.md 2.3) and the material-ID enum, both unfrozen, so the per-fragment inputs
//     arrive as explicit parameters and the material categories as caller booleans (same
//     adaptation as B1 shadow_mapping's `bool subsurfaceScatter` and wind.glsl's caller
//     bools — "materialID 判据改为调用方布尔参数，待 E1 接线").
//   - worldLightVector is NOT a uniform (not in the frozen set). It is derived in-shader
//     from the frozen `lightVector` (view space) via lib/transforms.glsl view_player().
//   - The light COLOURS that belong to the atmosphere model (skyAmbient, directLightSurface
//     — Steadfast computes these on the CPU from the Minishita sky) are D2/E1-owned and
//     arrive via LightParams, exactly as B2's fog.glsl takes its D2-owned FogParams colours.
//   - NIGHT_DESATURATION_EFFECT (Steadfast) is dropped: not in Astra design.md 4.1.
//   - Underwater-terrain absorption (Steadfast's isEyeInWater==1 branch) is NOT done here.
//     It is C2's global/water/absorption.glsl body, integrated by E2 ("与水面的总成集成归
//     E2，不越界"). block_lighting() is exposed separately so E2 can perform Steadfast's
//     blocklight-not-absorbed remix without C1 owning the underwater composition.
//
// Uniforms: lightVector (lib/uniforms.glsl, frozen). Requires lib/settings.glsl
//           (SKYLIGHT_STRENGTH, SSS_STRENGTH, LIGHTNING_FLASH) and lib/colors.glsl
//           (MIN_AMBIENT_COLOR) — program/* guarantees order.
// Consts:   none local.
// Owner: C1. Consumer: program/lit.fsh (E1).
// Include order (E1 / program/lit.fsh), all BEFORE this file:
//   lib/settings.glsl -> lib/uniforms.glsl -> lib/transforms.glsl ->
//   global/lighting/shadowmap.glsl (B1) -> global/lighting/sss.glsl ->
//   global/lighting/blocklight.glsl -> global/lighting/diffuse.glsl.
//   (global/* never includes global/*; the program is the composer — design.md 3.2.)
// Calls (declared by the siblings above): shadow_mapping(), sss_wrap(),
//   held_light_strength(), block_lighting(), lightning_point_light().
//
// LightParams — the non-frozen, per-frame inputs E1 supplies. Rationale mirrors B2 FogParams:
// the Z3 custom-uniform set is frozen (SC-14), so any light colour / built-in not in
// lib/uniforms.glsl is a documented parameter rather than a privately-declared uniform.
//   skyAmbient            — D2/E1: Minishita sky ambient colour, HDR, day/night/rain baked
//                           in (Steadfast skyAmbient). SKYLIGHT_STRENGTH is applied HERE.
//   directLightSurface    — D2/E1: combined sun+moon direct colour above water (Steadfast
//                           directLightSurface). NOTE: SUNLIGHT_STRENGTH / MOONLIGHT_STRENGTH
//                           must be applied by the PRODUCER while sun and moon are still
//                           separate colours; C1 receives them already combined and cannot
//                           re-split them, so it does not scale them. (Interface requirement
//                           for D2/E1 — flagged in the handoff, not a C1 defect.)
//   nightVision           — built-in (not frozen): 0..1, boosts ambient sky only.
//   blocklightSuppression — CPU (Steadfast blocklightSuppression), 0..1; see blocklight.glsl.
//   heldLightBase         — CPU pow(heldBlockLightValue/15, 4), 0..1; see blocklight.glsl.
//   heldLightSuppression  — CPU smooth(eyeBrightness.y/240, .4, .4), 0..1; see blocklight.glsl.
//   lightningBolt         — lightningBoltPosition (vec4), xyz + w gate; see blocklight.glsl.
struct LightParams {
	vec3  skyAmbient;
	vec3  directLightSurface;
	float nightVision;
	float blocklightSuppression;
	float heldLightBase;
	float heldLightSuppression;
	vec4  lightningBolt;
};

#include "/lib/colors.glsl"
#include "/lib/transforms.glsl"

// Vanilla-style directional ambient: up-faces brighter than down-faces. Steadfast's
// 0.67 + y*0.33 (a top face at y=1 gets 1.0, a bottom face at y=-1 gets 0.34).
float ambient_strength(float worldNormalY) {
	return 0.67 + worldNormalY * 0.33;
}

// Sky ambient with a cubic skylight falloff (design.md 4.1: skylight 立方衰减) and the
// cave-floor minimum so unlit interiors are dim-blue, never pure black. Directional form
// (ambientStrength scales BOTH the floor and the sky term) — this is the "仿原版方向性环境光"
// the acceptance asks for; Steadfast's non-directional variant is not exposed in Astra.
vec3 ambient_sky_lighting(float skyLightStrength, float ambientStrength, vec3 skyAmbient) {
	float skyLight = pow(skyLightStrength, 3.0);
	return ambientStrength * (MIN_AMBIENT_COLOR + skyLight * skyAmbient * (SKYLIGHT_STRENGTH * 0.01));
}

// Direct sun/moon contribution as a vec3 multiplier on directLightSurface.
//
// Caller contract (inherits B1 shadow_mapping's contract):
//   - worldNormal, worldLightVector: player-relative world space, normalized.
//   - playerPos: camera-relative world space. shadowPos: from B1 shadow_map_position(),
//     carried through an E1 varying.
//   - the plain-Lambert branch early-outs before the (costly) shadow sample when the face
//     is turned away; SSS and glass always sample (they receive light from any angle).
//   - the in-shadow SSS factor (0.7071) lives INSIDE shadow_mapping (B1) — this function
//     supplies only the out-of-shadow wrap via sss_wrap(), so the two are never doubled.
vec3 direct_lighting(
	vec3  worldNormal,
	vec3  worldLightVector,
	vec3  playerPos,
	vec3  shadowPos,
	float skyLight,
	bool  subsurfaceScatter,
	bool  isLeaves,
	bool  isGlass,
	vec3  visibility
) {
	float ndotl = dot(worldNormal, worldLightVector);
	float directLightStrength;

	if (subsurfaceScatter) {
		// Foliage / SSS material: light wraps around the surface (sss.glsl).
		directLightStrength = sss_wrap(ndotl, isLeaves, SSS_STRENGTH * 0.01);
	} else if (isGlass) {
		// Transparent: directional shading reads wrong, so use a fixed top-lit response
		// (Steadfast's glass model, 0.2071 = 0.7071*0.33/1.13 tuned constant).
		directLightStrength = worldNormal.y * 0.2071 + 0.5;
	} else {
		// Steadfast's stylized lighting model (DirectLighting, the
		// non-DIRECTIONAL_SKYLIGHT_SHADING branch): faces turned toward the light
		// in nearly any way receive full intensity, and only faces at or past 90
		// degrees fade out. Astra used plain Lambert ("max(ndotl, 0.0)") here.
		//
		// That single difference caused two reported defects at once:
		//   1. "晴天变成阴天" — Lambert leaves every partially lit face dim, so
		//      the whole scene reads as overcast even at noon.
		//   2. "方块边缘的白光" — SSS foliage keeps a 0.65 floor
		//      (ndotl * 0.35 + 0.65). At a grazing angle (ndotl = 0.1) the ground
		//      gets 0.10 under Lambert while the grass beside it gets 0.685:
		//      6.9x brighter. With Steadfast's curve the ground gets 1.0, so the
		//      grass is no longer the brightest thing on screen.
		directLightStrength = smoothstep(-0.05, 0.05, ndotl);
		// Turned away from the light -> no direct light and no shadow sample (design.md 5).
		if (directLightStrength < 0.0001) {
			return vec3(0.0);
		}
	}

	// Visibility already comes from the shadow map (and skylight outside its
	// coverage). Multiplying by vanilla skylight here attenuates open water twice.

	// B1 returns the combined static-fallback + real-time + in-shadow-SSS multiplier as a
	// vec3 (colored shadows tint per channel).
	return directLightStrength * visibility;
}

// Resolve transparent tint and occlusion from paired depths at the same texel.
vec3 surface_shadow_light(vec3 playerPos, vec3 shadowPos, float skyLight) {
    #ifdef STATIC_SHADOW_FALLBACK
        float fallback = static_shadow(skyLight);
    #else
        float fallback = 1.0;
    #endif
    #ifdef SHADOWS
        float coverage = shadow_coverage(playerPos, shadowPos);
        if (coverage <= 0.0) return vec3(fallback);
        vec3 filtered = vec3(0.0);
        for (int i = 0; i < 16; ++i) {
            float weight;
            vec2 uv = shadow_filter_uv(shadowPos, i, weight);
            ShadowTap tap = shadow_read_tap(uv, shadowPos.z);
            vec3 transmission = vec3(0.0);
            #ifdef COLORED_SHADOWS
                transmission = tap.caster.gba;
            #endif
            if (tap.caster.r < 0.999) {
                // Steadfast's air-side bed has no second water absorption.
                transmission = isEyeInWater == 1 ? tap.caster.gba : vec3(1.0);
            }
            filtered += (vec3(tap.allVisibility)
                + transmission * max(tap.opaqueVisibility - tap.allVisibility, 0.0)) * weight;
        }
        return mix(vec3(fallback), filtered, coverage);
    #else
        return vec3(fallback);
    #endif
}

// The composer. Returns surfaceColor * (ambient + local + direct), linear HDR.
//
// surfaceColor  — linear albedo incl. AO/tint (E1 unpacks it from the GBuffer).
// worldNormal   — player-relative world space normal.
// playerPos     — camera-relative world space fragment position.
// shadowPos     — B1 shadow_map_position() via E1 varying.
// skyLight/blockLight — 0..1 lightmap (1 = level 15).
// subsurfaceScatter/isLeaves/isGlass — E1-resolved material categories (see sss.glsl contract).
vec3 diffuse_lighting(
	vec3  surfaceColor,
	vec3  worldNormal,
	vec3  playerPos,
	vec3  shadowPos,
	float skyLight,
	float blockLight,
	bool  subsurfaceScatter,
	bool  isLeaves,
	bool  isGlass,
	LightParams params,
	out vec3 directRadiance
) {
	// lightVector is view-space (frozen uniform); the lighting math is world-space.
	vec3 worldLightVector = normalize(view_player(lightVector));

	// 1. Ambient sky. SSS material is shaded as if perpetually at 45° (0.7071) for ambient
	//    too, matching how it is treated for direct light (Steadfast).
	float ambientStr = ambient_strength(subsurfaceScatter ? 0.7071 : worldNormal.y);
	vec3 lighting = ambient_sky_lighting(max(skyLight, params.nightVision), ambientStr, params.skyAmbient);
    vec3 visibility = surface_shadow_light(playerPos, shadowPos, skyLight);
    if (isEyeInWater == 1) {
        // Solas mixes ambient and direct light instead of adding a full outdoor
        // ambient floor under every water texel. The map supplies water caustics.
        vec3 ambient, direct;
        #if defined ASTRA_TERRAIN && !defined ASTRA_WATER_PASS
            solas_water_lighting(ambient, direct, true);
        #else
            solas_water_lighting(ambient, direct, false);
        #endif
        float NoL = max(dot(worldNormal, worldLightVector), 0.0);
        vec3 shadow = clamp(visibility * clamp(NoL * 1.01 - 0.01, 0.0, 1.0), 0.0, 1.0);
        vec3 sceneLight = mix(ambient * skyLight * skyLight, direct,
            shadow * (1.0 - rainStrength * 0.75) * astraSolasShadowFade);
        float vanilla = (0.25 * worldNormal.y + 0.75)
            + (0.667 - abs(worldNormal.x)) * (1.0 - abs(worldNormal.y)) * 0.15;
        vanilla = mix(1.0, vanilla * vanilla, clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0));
        sceneLight += MIN_AMBIENT_COLOR * (1.0 - skyLight) + params.nightVision * vec3(0.2, 0.3, 0.2);
        float held = held_light_strength(params.heldLightBase, playerPos);
        directRadiance = surfaceColor * direct * shadow * vanilla;
        return surfaceColor * (sceneLight * vanilla + block_lighting(skyLight, blockLight, held,
                               params.blocklightSuppression, params.heldLightSuppression));
    }

	// 2. Local light: block light + handheld (held is purely camera-distance based).
	float heldLight = held_light_strength(params.heldLightBase, playerPos);
	lighting += block_lighting(
		skyLight,
		blockLight,
		heldLight,
		params.blocklightSuppression,
		params.heldLightSuppression);

	// 3. Lightning flash (additive, transient). Gated by LIGHTNING_FLASH.
	#ifdef LIGHTNING_FLASH
		lighting += lightning_point_light(playerPos, worldNormal, skyLight, params.lightningBolt);
	#endif

	// 4. Direct sun/moon, shadow-mapped.
	vec3 direct = direct_lighting(
		worldNormal, worldLightVector, playerPos, shadowPos,
		skyLight, subsurfaceScatter, isLeaves, isGlass,
		visibility * (subsurfaceScatter ? 0.7071 : 1.0));
	// Water tint/caustics are already part of each visibility tap.
	directRadiance = surfaceColor * direct * params.directLightSurface;

	return surfaceColor * lighting + directRadiance;
}

#endif
