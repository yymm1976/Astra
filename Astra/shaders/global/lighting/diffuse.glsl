#ifndef ASTRA_GLOBAL_LIGHTING_DIFFUSE_GLSL
#define ASTRA_GLOBAL_LIGHTING_DIFFUSE_GLSL
#include "/lib/twilight.glsl"
#ifdef DIRECTIONAL_SKYLIGHT
#if defined ASTRA_DIRECTIONAL_SKYLIGHT && !defined ASTRA_SKY_SH_WRITE
#include "/lib/sky_directional.glsl"
#endif
#endif

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
// 2026-09-16 visual-experience round (docs/2026-09-16-shader-visual-experience-study.md):
//   - night is expressed by lit colour and a light-protected desaturation, not by an
//     extra distance darkening on top of the sky ambient (see night_desaturation()).
//   - foliage gained the view-dependent transmission term the study asks for; it lives
//     in sss.glsl and is blended into `visibility` here, so no second shadow read.
//
// Acceptance mapping (design.md 4.1 / tasks-advanced-2.md C1):
//   仿原版方向性环境光  -> ambient_strength() (0.67 + N.y*0.33) applied to BOTH ambient terms
//   skylight 二次衰减   -> ambient_sky_lighting(): skyLight * skyLight (晨昏调整)
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
//   heldLightBase         — CPU heldBlockLightValue/15, 0..1; see blocklight.glsl.
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

// Sky ambient with a quadratic skylight falloff (September 12 visual adjustment) and the
// cave-floor minimum so unlit interiors are dim-blue, never pure black. Directional form
// (ambientStrength scales BOTH the floor and the sky term) — this is the "仿原版方向性环境光"
// the acceptance asks for; Steadfast's non-directional variant is not exposed in Astra.
vec3 ambient_sky_lighting(float skyLightStrength, float ambientStrength, vec3 skyAmbient) {
	// Solas retains quadratic sky exposure under tree shade; the cubic response
	// crushed partially exposed faces during the direct-light handoff.
	float skyLight = skyLightStrength * mix(0.25, 1.0, skyLightStrength);
	return ambientStrength * (MIN_AMBIENT_COLOR + skyLight * skyAmbient * (SKYLIGHT_STRENGTH * 0.01));
}

// Direct sun/moon contribution as a vec3 multiplier on directLightSurface.
//
// Caller contract (inherits B1 shadow_mapping's contract):
//   - worldNormal, worldLightVector: player-relative world space, normalized.
//   - playerPos: camera-relative world space. shadowPos: from B1 shadow_map_position(),
//     carried through an E1 varying.
//   - the plain-Lambert branch early-outs before the (costly) shadow sample when the face
//     is turned away; foliage samples while its wrap contributes, and glass
//     samples for its fixed top-lit response.
//   - the in-shadow SSS factor (0.7071) is applied once by astra_lighting when calling direct_lighting — this function
//     supplies only the out-of-shadow wrap via sss_wrap(), so the two are never doubled.
vec3 direct_lighting(
	vec3  worldNormal,
	vec3  worldLightVector,
	float ndotl,
	vec3  playerPos,
	vec3  shadowPos,
	float skyLight,
	bool  subsurfaceScatter,
	bool  isLeaves,
	bool  isGlass,
	vec3  visibility,
	vec3  viewDir
) {
	float directLightStrength;
	float sssTransmission = 0.0;

	if (subsurfaceScatter) {
		// Foliage / SSS material: light wraps around the surface (sss.glsl).
		directLightStrength = sss_wrap(ndotl, isLeaves, SSS_STRENGTH * 0.01);
		// The wrap above is independent of where the camera is, which is why a leaf
		// seen against the sun was no brighter than the same leaf seen from the lit
		// side. This is the missing view-dependent half of the reference's leaf
		// model (Complementary mainLighting.glsl:241-254 subsurfaceHighlight), kept
		// as a factor on `visibility` rather than as an added light so it can never
		// escape the occlusion the wrap already paid for.
		sssTransmission = sss_transmission(ndotl, viewDir, worldLightVector, isLeaves,
		                                   skyLight, SSS_STRENGTH * 0.01);
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
		// Blend toward Lambert at low elevations to avoid full-strength grazing bands.
		float highSun = smoothstep(0.15, 0.50, worldLightVector.y);
        float grazing=max(ndotl,0.0);
        #if !defined DIMENSION_END && !defined DIMENSION_NETHER
        // A small forward-facing wrap catches sunrise on grass and stair tops;
        // the existing facing gate still excludes back faces entirely.
        // Complementary mainLighting.glsl: SIDE_SHADOWING uses a wrapped
        // normal response, then sqrt2, instead of extinguishing grazing light.
        float wrapped=clamp((ndotl+0.4)/1.4,0.0,1.0);
        wrapped=wrapped*(2.0-wrapped);
        grazing=mix(grazing,wrapped,astra_twilight_strength()
                         *smoothstep(0.0,0.05,worldSunVector.y));
        #endif
		directLightStrength *= mix(grazing, 1.0, highSun);
		// Turned away from the light -> no direct light and no shadow sample (design.md 5).
		if (directLightStrength < 0.0001) {
			return vec3(0.0);
		}
	}

	// Visibility already comes from the shadow map (and skylight outside its
	// coverage). Multiplying by vanilla skylight here attenuates open water twice.
	//
	// Foliage transmission: a leaf lit from behind still transmits, and the shadow
	// map already says whether the light reaches it. The transmission LIFTS the
	// occlusion toward unshadowed - capped at 1.0 so it can never brighten a
	// fragment past its own unshadowed direct light, and a fully occluded canopy
	// keeps a fraction of the light instead of going black. (The previous form
	// multiplied visibility by a factor below 1.0 for every t < 1 - a darkening
	// term wearing a gain's name; consolidated review D1 / Qoder F-08.)
	if (sssTransmission > 0.0)
		visibility = mix(visibility, vec3(1.0), sssTransmission * 0.35);

	// B1 returns the combined static-fallback + real-time + in-shadow-SSS multiplier as a
	// vec3 (colored shadows tint per channel).
	return directLightStrength * visibility;
}

// ---------------------------------------------------------------------------
// Night expression: a light, local-light-protected desaturation of the surface.
//
// Steadfast expresses night with NIGHT_DESATURATION_EFFECT
// (environment/lighting/diffuse.glsl NightDesaturation/Desaturate, and its
// shaders.properties uniforms: desaturationIntensity = 0.66 * (1 - dayAmbientFade),
// desaturationColor = vec3(0.33, 0.5, 1.0)). The user's complaint that Astra's
// nights were carried by darkening the distance rather than by night colour is the
// gap this closes, so the mechanism is adopted while the constants are not:
//   - intensity 0.66 is a full third of the way to blue-grey; at Astra's ambient
//     floor that reads as a filter over the whole night rather than as moonlight.
//     A third of that is enough to separate moonlit ground from torched ground.
//   - the effect is scaled by sky exposure, so caves, interiors and the dark keep
//     their material colour - Steadfast's skyLight factor, which is also what keeps
//     this off the Nether and off anything the End lights by its own palette.
//   - local light removes it (1.0-clamp(localIntensity,0.0,1.0), the same division of labour
//     Steadfast's max(blockLight, heldLight) performs), so a torch's pool keeps the
//     warm albedo that identifies it as firelight. It touches lit colour only, so
//     emissive blocks and portals are untouched by construction.
//   - it is deliberately NOT a replacement for readout in the dark: shadow
//     interiors still get their light from the ambient rebalance in the composer,
//     not from being left saturated.
const float NIGHT_DESATURATION_INTENSITY = 0.20;
// Kept close to neutral on purpose. Steadfast's vec3(0.33, 0.5, 1.0) drives the
// desaturated result hard towards blue, which is right for its own night palette and
// wrong here: Astra already has a cool night sky ambient, so a strongly blue luma would
// turn the whole night into the "把所有东西染成蓝灰" the task rules out. This only
// takes a little of the warm out, which is enough to tell moonlit ground from
// torchlit ground.
const vec3  NIGHT_DESATURATION_COLOR     = vec3(0.40, 0.50, 0.94);

// `visibility` is the resolved shadow multiplier for this fragment. It gates the
// effect because desaturation is a statement about which light is reaching the
// surface, not about how much sky the surface can see: terrain in the moon's shadow
// must keep its albedo, which is the same rule the local-light term below applies for
// torchlight. Only the moonlit part of the night is allowed to lose its colour.
float night_desaturation(float skyLight, float localAttenuation, vec3 visibility) {
	float night = 1.0 - skyVisibilityDay;
	// Night vision is the player asking for colour to survive the dark.
	night *= 1.0 - clamp(nightVision, 0.0, 1.0);
    // Daylight and fully protected local-light regions keep their material
    // colour; none of them needs the shadow-colour luminance below.
    if (night <= 0.0 || skyLight <= 0.0 || localAttenuation <= 0.0) return 0.0;
	float lit = clamp(dot(visibility, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
	return NIGHT_DESATURATION_INTENSITY * night * skyLight * localAttenuation * lit;
}

vec3 desaturate_surface(vec3 color, float amount) {
	if (amount <= 0.0) return color;
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	return mix(color, luma * NIGHT_DESATURATION_COLOR, amount);
}

// Resolve transparent tint and occlusion from paired depths at the same texel.
//
// Native main-world receivers use four fixed plane-corrected footprints in Q1/Q2.
// A uniform centre alone cannot certify the expanded kernel. Spread is bounded
// in world space below. The legacy water path retains its
// Overworld budget (ASTRA_OVERWORLD_OPTIMIZED, lib/settings.glsl): the footprint
// count is graded by receiver distance instead of by the global SHADOW_FILTER_QUALITY
// tier - two four-corner footprints up to 32 blocks, one beyond. The two near
// offsets converge onto the center across 24..32 blocks, so crossing the threshold
// keeps the result continuous and reduces the two near groups to the one the far side
// already uses; no third footprint is ever introduced. The near spread caps the
// softness basis at 2 (1.0 texel) and keeps a lower raw SHADOW_SOFTNESS instead of
// rounding it up, so the budget never inherits a softer footprint than the raw
// option asked for. Raw SHADOW_FILTER_QUALITY 0 keeps its own single-footprint
// branch and is never raised to two groups by the budget. Other dimensions and
// OVERWORLD_BUDGET 0 keep the original SHADOW_FILTER_QUALITY branch and its
// SHADOW_SOFTNESS untouched.
vec3 surface_shadow_light(vec3 playerPos, vec3 shadowPos, float skyLight) {
    #ifdef STATIC_SHADOW_FALLBACK
        float fallback = static_shadow(skyLight);
    #else
        float fallback = 1.0;
    #endif
    // Solas getFakeShadow explicitly disables sky-derived direct light underwater.
    // Missing shadow coverage must not create an unoccluded sunlight source.
    if (isEyeInWater == 1 && !water_is_thin_sheet()) fallback = 0.0;
    #ifdef SHADOWS
        float coverage = shadow_coverage(playerPos, shadowPos);
        if (coverage <= 0.0) return vec3(fallback);
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        ivec2 shadowSize = textureSize(shadowtex0, 0);
        float receiverWorldY = cameraPosition.y + playerPos.y;
        // Low skylight predicts opaque shade. Full skylight and submerged views
        // keep the existing all-caster-first transmission fast paths.
        bool opaqueFirst = skyLight <= 13.5 / 15.0 && isEyeInWater == 0;
        #endif
        #if defined ASTRA_SURFACE_SHADOW_FRAGMENT && SHADOW_FILTER_QUALITY > 0
        // Retain a stable footprint at every receiver distance. The old
        // 24..32-block collapse made far silhouettes lose edge coverage.
        vec3 filtered = vec3(0.0);
        const int lobeCount = 4;
        #ifdef ASTRA_OVERWORLD_OPTIMIZED
        float spread = min(float(SHADOW_SOFTNESS),2.0)*0.5;
        #else
        float spread = float(SHADOW_SOFTNESS)*0.5;
        #endif
        // Bound world softness, but retain at least half the requested texel
        // spread: shrinking all four lobes onto the same bilinear footprint
        // at the map rim would bring back hard steps on distant leaf shadows.
        // The minimum is texture-relative, fixed across frames, and never
        // exceeds the user's softness. Coarse distant maps can therefore blur
        // beyond the preferred world radius; coverage still fades at the rim.
        float mapRim = max(1.0-length(shadowPos.xy*2.0-1.0),0.0001);
        // Inverse radial derivative: p = a*q/(1-|q|), so dp/d|q| =
        // a/(1-|q|)^2. The squared rim is the widest texel axis, not a duplicate.
        float worldTexel = (2.0*shadowDistance*SHADOW_DISTORT_FACTOR)
                         / (float(shadowMapResolution)*mapRim*mapRim);
        float softRadius=max(0.22,0.75*sqrt(astraSurfaceShadowPixelWorldSquared));
        spread = clamp(softRadius/max(worldTexel,0.0001),0.5*spread,spread);
        if (spread<=0.0) {
            filtered=shadow_lobe_light_inside(shadowPos.xy,shadowPos.z,
                receiverWorldY,shadowSize,opaqueFirst);
            return mix(vec3(fallback),filtered,coverage);
        }
        for (int lobe=0;lobe<lobeCount;++lobe) {
            #if SHADOW_FILTER_QUALITY == 1
            // Fixed radius/weights across texel boundaries. Gating extra lobes
            // on centre visibility clipped their support and made stair bumps.
            vec2 offset=vec2((lobe & 1)==0 ? -1.0 : 1.0,
                             (lobe & 2)==0 ? -1.0 : 1.0)*(0.70710678*spread);
            #else
            vec2 offset = vec2((lobe & 1) == 0 ? -1.0 : 1.0,
                               (lobe & 2) == 0 ? -1.0 : 1.0)*spread;
            #endif
            filtered += shadow_lobe_light_inside(shadowPos.xy+offset/float(shadowMapResolution),
                shadowPos.z,receiverWorldY,shadowSize,opaqueFirst)
                /float(lobeCount);
        }
        #elif defined ASTRA_OVERWORLD_OPTIMIZED && SHADOW_FILTER_QUALITY > 0
        // Distance-graded budget: two footprints near, one far. The far branch
        // stays a full four-corner footprint (1/2/4 lobes are what the whole
        // caster-pairing path is built around; a single texel leaks light).
        // Softness basis capped at 2 (1.0 texel) and never raised above the raw
        // SHADOW_SOFTNESS, shrinking to 0 across 24..32 blocks.
        float budgetNear = 1.0 - smoothstep(24.0, 32.0, length(playerPos));
        vec3 filtered = vec3(0.0);
        if (budgetNear > 0.0) {
            float budgetSpread = min(float(SHADOW_SOFTNESS), 2.0) * 0.5 * budgetNear;
            for (int lobe = 0; lobe < 2; ++lobe) {
                vec2 offset = vec2(lobe == 0 ? -1.0 : 1.0) * budgetSpread;
                vec2 uv = shadowPos.xy + offset / float(shadowMapResolution);
                filtered += shadow_lobe_light_inside(uv, shadowPos.z, receiverWorldY, shadowSize, opaqueFirst) * 0.5;
            }
        } else {
            filtered = shadow_lobe_light_inside(shadowPos.xy, shadowPos.z, receiverWorldY, shadowSize, opaqueFirst);
        }
        #elif SHADOW_FILTER_QUALITY == 0
        // Keep individual depth/caster pairs; a stable bilinear footprint needs
        // neither a rotating sample pattern nor temporal antialiasing.
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        vec3 filtered = shadow_lobe_light_inside(shadowPos.xy, shadowPos.z, receiverWorldY, shadowSize, opaqueFirst);
        #else
        vec3 filtered = shadow_lobe_light(shadowPos.xy, shadowPos.z, cameraPosition.y + playerPos.y);
        #endif
        #else
        vec3 filtered = vec3(0.0);
        #if SHADOW_FILTER_QUALITY == 1
        const int lobeCount = 2;
        #else
        const int lobeCount = 4;
        #endif
        for (int lobe = 0; lobe < lobeCount; ++lobe) {
            #if SHADOW_FILTER_QUALITY == 1
            vec2 offset = vec2(lobe == 0 ? -1.0 : 1.0) * (float(SHADOW_SOFTNESS)*0.5);
            #else
            vec2 offset = vec2((lobe & 1) == 0 ? -1.0 : 1.0,
                               (lobe & 2) == 0 ? -1.0 : 1.0) * (float(SHADOW_SOFTNESS)*0.5);
            #endif
            vec2 uv = shadowPos.xy + offset / float(shadowMapResolution);
            #if !defined DIMENSION_NETHER && !defined DIMENSION_END
            filtered += shadow_lobe_light_inside(uv, shadowPos.z, receiverWorldY, shadowSize, opaqueFirst) / float(lobeCount);
            #else
            filtered += shadow_lobe_light(uv, shadowPos.z, cameraPosition.y + playerPos.y) / float(lobeCount);
            #endif
        }
        #endif
        return mix(vec3(fallback), filtered, coverage);
    #else
        return vec3(fallback);
    #endif
}

// Shared zero-response gate for surface shadows and the caller's cloud visibility.
// Ground foliage retains its positive wrap; glass keeps its fixed top response.
bool astra_direct_facing_away(float ndotl, bool subsurfaceScatter, bool isLeaves,
                             bool isGlass) {
    return !isGlass && (subsurfaceScatter
        ? (isLeaves && ndotl <= -(0.35 / 0.65))
        : ndotl <= -0.05);
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
	out vec3 directRadiance,
    out vec3 ambientRadiance,
    out vec3 directionalSkyRadiance
) {
    ambientRadiance = vec3(0.0);
    // R1 bent normal: the SH-direction-dependent share of `ambientLighting`,
    // with the material response (albedo, sky access, night/ramp factors)
    // already folded in. deferred2 re-evaluates the SH sky at the AO bent
    // normal against this, so the swap cannot touch cave floor, block light,
    // direct light or emission. Zero outside the directional branch.
    directionalSkyRadiance = vec3(0.0);
    vec3 directionalCoef = vec3(0.0);
	// lightVector is view-space (frozen uniform); the lighting math is world-space.
	vec3 worldLightVector = astra_world_light_direction();
    // Steadfast's rule, applied one step earlier than the copy inside direct_lighting():
    // that function already returns black once the facing term collapses
    // (smoothstep(-0.05, 0.05, ndotl) < 1e-4), but by then the caller has already paid for
    // the shadow fetch - surface_shadow_light resolves paired depths/caster data.
    // Native Q1 adds edge footprints, Q2 uses four; water retains distance grading.
    // Evaluating the facing here lets those pixels skip the fetch
    // outright, and in a normal scene about half the visible faces point away from the
    // light. The skip is only valid where the facing term really is the gate:
    // Foliage retains its wrap until that response reaches zero; ground plants
    // have a positive floor, whereas the leaves wrap vanishes below -0.35/0.65.
    // Glass has a fixed positive top-lit response and retains its query.
    // The value handed back for skipped pixels is 1.0
    // because every consumer multiplies it by a facing term that is zero here.
    float facingNdotL = dot(worldNormal, worldLightVector);
    bool thinSheet = water_is_thin_sheet();
    bool volumeWater = isEyeInWater == 1 && !thinSheet;
    // Leaves have a finite wrap too: below -0.35/0.65 both Lambert and wrap
    // are zero. Their transmission only remixes visibility, so it cannot make
    // this zero direct response contribute light. Skip those canopy queries.
    bool facingAway = astra_direct_facing_away(facingNdotL, subsurfaceScatter,
                                              isLeaves, isGlass);
    vec3 visibility = facingAway
        ? vec3(1.0)
        : surface_shadow_light(playerPos, shadowPos, skyLight);
    // The same bank/bed material keeps the same incident sky and sun palette
    // when the eye crosses the interface. Shadow transmission owns the incoming
    // sun's water leg; the final composite owns the camera leg, each once.
    float ambientSkyLight = skyLight;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    if (volumeWater) {
        vec4 waterState = water_volume_state();
        if (waterState.a > 0.5) {
            float waterDepth = max(water_unpack_surface_height(waterState.rg)
                                 - cameraPosition.y - playerPos.y, 0.0);
            float surfaceAccess = clamp(waterState.b, 0.0, 1.0);
            ambientSkyLight = max(ambientSkyLight, surfaceAccess*exp(-waterDepth*0.035));
        }
    }
    #endif

    // Only foliage transmission consumes the view direction.
    bool directContributes = !facingAway && any(notEqual(params.directLightSurface, vec3(0.0)));
    vec3 viewDir = directContributes && subsurfaceScatter && SSS_STRENGTH > 0 && skyLight > 0.20
        ? normalize(-playerPos) : vec3(0.0);
	float ambientStr = ambient_strength(subsurfaceScatter ? 0.7071 : worldNormal.y);
	vec3 lighting = ambient_sky_lighting(max(ambientSkyLight, params.nightVision), ambientStr, params.skyAmbient);
    #if defined ASTRA_DIRECTIONAL_SKYLIGHT && !defined ASTRA_SKY_SH_WRITE
    if ((isEyeInWater == 0 || thinSheet) && !subsurfaceScatter && !isGlass) {
        float access = skyLight * mix(0.25, 1.0, skyLight);
        // Night vision retains its established isotropic/readability behaviour.
        float directionalKeep = 1.0 - clamp(params.nightVision, 0.0, 1.0);
        if (directionalKeep > 0.0) {
            vec3 directional = ambientStr * MIN_AMBIENT_COLOR;
            // Zero sky access keeps the cave floor, without fetching nine SH coefficients.
            if (access > 0.0 && SKYLIGHT_STRENGTH > 0)
                directional += access * astra_directional_sky(worldNormal, params.skyAmbient)
                               * (SKYLIGHT_STRENGTH * 0.01);
            lighting = mix(directional, lighting, 1.0 - directionalKeep);
        }
        // Store the multiplier of SH irradiance for the deferred bent-normal swap.
        directionalCoef = vec3(access * (SKYLIGHT_STRENGTH * 0.01) * directionalKeep);
    }
    #endif

    #if !defined DIMENSION_END && !defined DIMENSION_NETHER
    // Outdoor diffuse fill softens contrast without removing cast shadows.
    // Unexposed interiors still receive only the existing cave floor.
    //
    // Distance behaviour of the night (2026-09-16 visual-experience round). The user's
    // report was "为了表现夜晚压暗远处，导致背光方块没有纹理" - dark distant blocks with
    // no texture. Two terms were doing the same job:
    //   - this floor, which trades cast shadow for ambient fill at night (0.52),
    //   - the moonDistance ramp, applied to the ambient AND again to `direct` below.
    // The ambient ramp keeps the distance gradient; the second application on the
    // direct term was pure layered attenuation and is removed. The floor drops so the
    // shadow the moon casts still reads, which is what puts texture back on the faces
    // that face away from it. Night vision keeps the old forgiving value.
    float night = (1.0-smoothstep(-0.12,0.02,worldSunVector.y))
                * (1.0-clamp(params.nightVision,0.0,1.0));
    float twilightFill=astra_twilight_strength()*skyLight*skyLight
        *(1.0-clamp(params.nightVision,0.0,1.0));
    // The two distance responses overlap at twilight and share one length.
    float ambientDistance=0.0;
    if (night > 0.0 || (twilightFill > 0.0 && SKYLIGHT_STRENGTH > 0))
        ambientDistance=length(playerPos);
    // 2026-09-23: 0.40 -> 0.85. The old floor traded only 40% of the cast shadow for
    // ambient fill, which left the grass/foliage shadows on open ground as distinct
    // dark speckles. The skyLight^2 gate is kept (not widened to skyLight) on purpose:
    // it is what separates a thin caster over fully sky-exposed ground (skyLight ~1,
    // now 85% softened, "草影基本消失") from a real canopy/overhang (skyLight ~0, so
    // the term vanishes and the large-scale tree shade keeps its full contrast).
    // The moonDistance ramp is unchanged.
    // At zero night weight these distance curves are the identity. Keep their
    // entire nonzero path, including the directional ambient coefficient.
    if (night > 0.0) {
        float moonDistance=smoothstep(12.0,128.0,ambientDistance);
        visibility = mix(visibility,vec3(1.0),
                         night*0.85*skyLight*skyLight*(1.0-0.50*moonDistance));
        vec3 caveFloor=ambientStr*MIN_AMBIENT_COLOR;
        float nightRamp=mix(1.0,mix(0.95,0.68,moonDistance),night);
        lighting=caveFloor+(lighting-caveFloor)*nightRamp;
        directionalCoef*=nightRamp;
    }
    // Outdoor horizon fill is independent of shadow visibility, so long
    // shadows keep their shape while shaded terrain retains cool detail.
    if (twilightFill > 0.0 && SKYLIGHT_STRENGTH > 0)
        lighting += vec3(0.025,0.024,0.030)*twilightFill*ambientStr
            *mix(1.0,0.65,smoothstep(32.0,160.0,ambientDistance))
            *(SKYLIGHT_STRENGTH*0.01);
    #endif
	// 2. Local light: block light + handheld (held uses the player-centred light source).
    vec3 ambientLighting = lighting;
	float heldLight = held_light_strength(params.heldLightBase, playerPos);
	vec2 localComponents = local_light_components(
		skyLight,
		blockLight,
		heldLight,
		params.blocklightSuppression,
		params.heldLightSuppression);
    if (localComponents.y > 0.0)
        localComponents.y *= astra_held_light_facing(playerPos, worldNormal);
    float localIntensity = localComponents.x + localComponents.y;
	lighting += astra_local_light_radiance(localComponents);

	// 3. Lightning flash (additive, transient). Gated by LIGHTNING_FLASH.
	#ifdef LIGHTNING_FLASH
		lighting += lightning_point_light(playerPos, worldNormal, skyLight, params.lightningBolt);
	#endif

	// 4. Direct sun/moon, shadow-mapped.
    // The same facing gate already rejected shadow queries. A zero direct
    // response needs neither the SSS view lobe nor the directional solve.
	vec3 direct = directContributes ? direct_lighting(
		worldNormal, worldLightVector, facingNdotL, playerPos, shadowPos,
		skyLight, subsurfaceScatter, isLeaves, isGlass,
		visibility * (subsurfaceScatter ? 0.7071 : 1.0),
		viewDir) : vec3(0.0);
	// The ambient term above already carries the whole night distance ramp
	// (moonDistance); scaling the direct term by it as well darkened exactly the
	// faces the moon was lighting, which is where the missing texture came from.
	// Water tint/caustics are already part of each visibility tap.

	// Night is carried by colour, not by removing light: see night_desaturation().
	// Applied to the albedo, so it reaches ambient, local and direct light alike
	// while the emissive add in program/scene.glsl (albedo * EMISSIVE_STRENGTH) and
	// the block_lighting() emission - both added after this point - keep their own
	// colour. Runs for glass and foliage too: those are exactly the surfaces whose
	// night colour used to be decided entirely by the sky.
	float localAttenuation = 1.0 - clamp(localIntensity, 0.0, 1.0);
	// A skipped shadow query's neutral visibility must not read as fully moonlit.
	surfaceColor = desaturate_surface(
		surfaceColor, facingAway ? 0.0 : night_desaturation(skyLight, localAttenuation, visibility));
	directRadiance = surfaceColor * direct * params.directLightSurface;

    ambientRadiance = surfaceColor * ambientLighting;
    // Same desaturated surfaceColor that multiplies ambientLighting, so the
    // directional share is exactly the SH-direction-dependent part of
    // ambientRadiance (R1).
    directionalSkyRadiance = surfaceColor * directionalCoef;
    return surfaceColor * lighting + directRadiance;
}

#endif
