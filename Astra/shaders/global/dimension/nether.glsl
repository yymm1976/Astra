// Astra Nether integration: Complementary r5.9 mainLighting/common biome palette.
// Homogeneous fog shares the biome palette with lighting; no endpoint noise.
// The two directionShade squares are intentional reference behavior.
#ifndef ASTRA_GLOBAL_DIMENSION_NETHER_GLSL
#define ASTRA_GLOBAL_DIMENSION_NETHER_GLSL

#include "/lib/colors.glsl"
#include "/lib/encoding.glsl"
// Included from scene.glsl, which already guards on DIMENSION_NETHER; the option
// itself uses a plain #ifdef so Iris registers the boolean (SC-28).
#ifdef NETHER_VOXEL_LIGHT
    #ifdef SHADOWS
        #include "/global/dimension/nether_colored_light.glsl"
    #endif
#endif

struct NetherParams {
	vec3  biomeFogColor;   // vanilla fogColor (sRGB-ish 0..1), per nether biome — E1 supplies
	float nightVision;     // built-in (not frozen): 0..1, lifts the ambient floor only
	float heldLightBase;   // CPU pow(heldBlockLightValue / 15, 4), 0..1 — see C1 blocklight.glsl
};

const vec3  NETHER_LAVA_LIGHT_COLOR = vec3(0.15, 0.06, 0.01);

#define NETHER_VS_BRIGHTNESS clamp(screenBrightness, 0.0, 1.0)

const vec3  NETHER_FLOOR_TINT = vec3(0.45, 0.475, 0.6);
const vec3  NETHER_NIGHT_VISION_TINT_REF = vec3(0.5, 0.5, 0.75);

// Border fog: linear-plus-border ramp to the view limit
// (docs/2026-09-10-complementary-r5.9-nether-report.md:451-467:
// fog = lPos / min(renderDistance, NETHER_VIEW_LIMIT)). The 0.0120/3.0 pair was
// fitted to the reference's 12.5%/25%/50% at 16/32/64 blocks
// (qa/tools/nether_fog_probe.py Part 1), but the user ruled that fit the wrong
// direction ("fog shallower and less"): 0.0080/6.0 reads lighter than the fit at
// every range while keeping the deep-distance depth cue. FAR_EXP stays 4 - only
// the scale moved, not the ramp shape. NETHER_FOG_TINT colours the lava-side fog (isEyeInWater == 1) and is
// applied to nether_palette() output directly: the Solas line it cites
// (lib/atmosphere/fog.glsl:61) works from sqrt(sqrt(normalize(fogColor))), which lifts
// the same source colour to luminance 0.197, while the un-rooted palette at *0.25 gave
// 0.047. 0.50 halves that gap and keeps lava-side fog dim on purpose.
const float NETHER_FOG_NEAR_COEFF = 0.0080;
const float NETHER_FOG_FAR_COEFF  = 6.0;
const float NETHER_FOG_FAR_EXP    = 4.0;
const float NETHER_FOG_TINT       = 0.50;      // Solas: fogCol = netherColSqrt * 0.25

const float NETHER_BLOCKLIGHT_EXPONENT = 2.75;

const float NETHER_EMISSIVE_BOOST    = 1.35;
const float NETHER_PORTAL_BOOST      = 2.20;
const float NETHER_PORTAL_SHIMMER    = 0.12;   // ±12% on the portal boost
const float NETHER_PORTAL_SHIMMER_RATE = 1.7;  // rad/s

vec3 nether_palette(vec3 fallback) {
    float w = astraNetherWastes + astraNetherCrimson + astraNetherWarped + astraNetherBasalt + astraNetherSoul;
    vec3 c = astraNetherWastes * vec3(0.4, 0.14, 0.06)
           + astraNetherCrimson * vec3(0.36, 0.07, 0.05)
           + astraNetherWarped * vec3(0.18, 0.1, 0.25)
           + astraNetherBasalt * vec3(0.25, 0.235, 0.23)
           + astraNetherSoul * vec3(0.1, 0.24, 0.24);
    return mix(fallback * 0.6 + 0.2 * normalize(fallback + 0.0001), c / max(w, 0.0001), clamp(w, 0.0, 1.0));
}
// Complementary feeds this palette directly to both ambient light and mainFog.
// Do not decode just the fog: that gave the same biome two different intensities.
vec3 nether_atmosphere_tint(vec3 biomeFogColor) { return nether_palette(biomeFogColor); }
vec3 nether_color(vec3 biomeFogColor) { return nether_palette(biomeFogColor); }
vec4 nether_fog(
	out float skyFogStrength,
	NetherParams params,
	float fragDistance,
	float borderFragDistance,
	vec3 playerPos
) {
	vec3 tint = nether_atmosphere_tint(params.biomeFogColor);
	float densityScale = NETHER_FOG_DENSITY * 0.01;

	float fogDensity = fragDistance * NETHER_FOG_NEAR_COEFF;
	#ifdef BORDER_FOG
		float farRatio = borderFragDistance > 0.0 ? borderFragDistance / borderFogDistance : 0.0;
		fogDensity += NETHER_FOG_FAR_COEFF * pow(farRatio, NETHER_FOG_FAR_EXP);
	#endif
	float fogFactor = 1.0 - exp(-fogDensity * densityScale);

	vec3 fogColor = tint;
	skyFogStrength = 0.0;
	if (blindness > 0.0001) {
		fogFactor = max(0.85, 1.0 - exp(-pow(fragDistance * blindness * 0.5, 2.0)));
		fogColor = vec3(0.0);
		skyFogStrength = 0.0;
	} else if (isEyeInWater == 1) {
		fogFactor = 1.0 - exp(-pow(fragDistance * 0.02 * (UNDERWATER_FOG_DENSITY * 0.01), 2.0));
		fogColor = tint * NETHER_FOG_TINT;
		skyFogStrength = 0.0;
	} else if (isEyeInWater == 2) {
		fogFactor = max(0.85, 1.0 - exp(-pow(fragDistance * 0.5, 2.0)));
		fogColor = vec3(1.0, 0.05, 0.0);
		skyFogStrength = 0.0;
	}

	if (skyFogStrength > 0.0) {
		fogFactor *= smoothstep(0.01, 0.015, fogFactor);
	}

	return vec4(fogColor, fogFactor);
}

vec3 nether_sky(vec3 worldViewDir, vec3 tint) { return tint; }

vec3 nether_block_lighting(float blockLight, float heldLight) {
	float blockIntensity = pow(blockLight, NETHER_BLOCKLIGHT_EXPONENT) * (BLOCKLIGHT_STRENGTH * 0.01);
	float heldIntensity = 0.0;
	#ifdef HANDHELD_LIGHTING
		heldIntensity = pow(heldLight, NETHER_BLOCKLIGHT_EXPONENT);
	#endif
	// Reference combines two independent sources as sqrt(block^2 + held^2)
	// (Complementary mainLighting.glsl:765). Adding them straight instead reached
	// min(1.0, ...) earlier whenever a light was held, flattening the Nether toward one
	// brightness; the two forms agree exactly when nothing is held
	// (qa/tools/nether_light_probe.py Part 2).
	return BLOCKLIGHT_COLOR * min(1.0, sqrt(blockIntensity * blockIntensity
	                                        + heldIntensity * heldIntensity));
}

float nether_emissive_boost(float emissiveMask, float portalMask, float time) {
	if (emissiveMask < 0.0001 && portalMask < 0.0001) { return 0.0; }

	float boost = (EMISSIVE_STRENGTH * 0.01)
	            * mix(NETHER_EMISSIVE_BOOST, NETHER_PORTAL_BOOST, portalMask);

	boost *= 1.0 + NETHER_PORTAL_SHIMMER * portalMask * sin(time * NETHER_PORTAL_SHIMMER_RATE);

	return boost * max(emissiveMask, portalMask);
}

vec3 nether_lighting(
	vec3  surfaceColor,
	vec3  worldNormal,
	vec3  playerPos,
	float blockLight,
	float emissiveMask,
	float portalMask,
	float time,
	NetherParams params,
	float vertexAO
) {

	// Complementary uses the palette directly in lighting; the earlier sRGB
    // decode here darkened it again before the squared light combination.
    vec3 netherCol = nether_palette(params.biomeFogColor);

	float NdotU = worldNormal.y;
	float NdotE = worldNormal.x;
	float NdotN = -worldNormal.z;
	float absNdotN = abs(NdotN);

	float NdotUM = 0.75 + abs(NdotU + 0.5) * 0.16666;
	float NdotNM = 1.0 + 0.075 * absNdotN;
	float NdotEM = 1.0 - 0.1 * NdotE * NdotE;
	float directionShade = NdotUM * NdotEM * NdotNM;
	directionShade *= directionShade;                    // mainLighting.glsl:518 (square #1)

	vec3 sceneLighting = (netherCol + 0.5 * NETHER_LAVA_LIGHT_COLOR)
	                   * (0.9 + 0.45 * NETHER_VS_BRIGHTNESS);

	float lavaDir = absNdotN * 0.5 + max(0.0, -NdotU);
	sceneLighting += NETHER_LAVA_LIGHT_COLOR * (lavaDir * lavaDir)
	               * (0.7 + 0.35 * NETHER_VS_BRIGHTNESS);

	vec3 minLighting = vec3(0.005625 + NETHER_VS_BRIGHTNESS * 0.043)
	                 * NETHER_FLOOR_TINT
	                 * (1.0 - blockLight);
	minLighting += params.nightVision * NETHER_NIGHT_VISION_TINT_REF;

	vec3 blockLighting = nether_block_lighting(blockLight, 0.0);
	vec3 heatGlow = vec3(0.0);
    #if defined NETHER_VOXEL_LIGHT && defined SHADOWS
        // Solas gbuffersLighting replaces the warm block-light term, rather than
        // adding a second copy after diffuse lighting. Astra only reaches eight
        // cells, so fade by available radiance as well as the volume boundary;
        // distant/unrepresented sources retain vanilla block-light support.
        if (emissiveMask < 0.5 && portalMask < 0.5) {
            vec3 voxel = astra_nether_colored_light(playerPos, worldNormal);
            float coverage = clamp(max(voxel.r, max(voxel.g, voxel.b)), 0.0, 1.0);
            blockLighting = mix(blockLighting, voxel * (BLOCKLIGHT_STRENGTH * 0.01), coverage * 0.95);
            // Heat glow on rock near lava (2026-09-21 A3). The reference lights the
            // lava rim with an EMISSIVE term (lib/materials/specificMaterials/terrain/
            // lavaEdge.glsl: edgeColor*3.0 feeds `emission`, and lava.glsl runs with
            // noDirectionalShading), so rock beside a lava lake reads as self-lit rather
            // than merely lit. Astra's voxel light above lands in blockLighting, which
            // directionShade and vanillaAO multiply down on faces turned away from the
            // lava, so the rim never warms. The volume's red share is the lava signal
            // (species 11 = (1.0, 0.18, 0.025) -> 0.83 red share; the torch family is
            // 0.74, glowstone 0.53, soul fire 0.03), and the volume's own eight-step
            // falloff already clears distant rock, so no separate distance gate is
            // needed (response table: qa/tools/nether_heat_glow_probe.py).
            float redShare = voxel.r / max(voxel.r + voxel.g + voxel.b, 1e-4);
            float lavaHeat = smoothstep(0.70, 0.85, redShare) * clamp(voxel.r, 0.0, 1.0);
            heatGlow = NETHER_LAVA_LIGHT_COLOR * (lavaHeat * 0.30);
        }
    #endif
    // Keep hand-held light separate from volume coverage, as Solas does.
    blockLighting += nether_block_lighting(0.0, held_light_strength(params.heldLightBase, playerPos));
    blockLighting *= 1.0 - clamp(max(emissiveMask, portalMask), 0.0, 1.0);

	float emission = nether_emissive_boost(emissiveMask, portalMask, time);

	// Vanilla per-vertex AO. Reference: mainLighting.glsl:559 (`vanillaAO = glColor.a`),
	// Nether branch :574-578 (`pow(pow1_5(vanillaAO), 1.0 + NdotUmax0 * 0.5)`), :586
	// (`* 0.9 + 0.1`). The `< 0.1` guard is the reference's own terrain-pass test for
	// "this vertex carries no AO data" (program/gbuffers_terrain.glsl:450-451:
	// `if (glColorRaw.a < 0.1) glColorRaw.a = 1.0;`). The channel arrives as a trailing
	// argument rather than a NetherParams field because it is per-fragment data that only
	// astra_light() has (lit.fsh passes tint.a); nether_fog()'s own NetherParams
	// construction (scene.glsl:121) has no AO to supply, and a struct field would have
	// forced it to invent one.
    // separateAo supplies terrain AO in alpha; other geometry supplies 1.
    // Keep zero occlusion valid rather than treating dark corners as missing data.
    float vanillaAO = clamp(vertexAO,0.0,1.0);
	vanillaAO = pow(pow(vanillaAO, 1.5), 1.0 + max(NdotU, 0.0) * 0.5);
	vanillaAO = vanillaAO * 0.9 + 0.1;

	vec3 finalDiffuse = directionShade * directionShade * vanillaAO * vanillaAO
	                  * (blockLighting + sceneLighting * sceneLighting + minLighting)
	                  + emission * emission;
	finalDiffuse = sqrt(max(finalDiffuse, vec3(0.0)));

	// heatGlow is an EMISSIVE rim term (A3 above), not reflectance, so it must not ride
	// the surface albedo. Inside the product below it is tinted by the rock texture:
	// srgb_decode(0.383) = 0.122 red for netherrack (block_reflect_probe.py table [3]),
	// 0.02 for the blackstone class - which cuts the term A3's own probe documents
	// (peak red 0.045, qa/nether-heatglow-2026-09-21-a3.log) to ~0.005 on netherrack,
	// an order below the "visible warm rim" its acceptance reading assumes. Added after
	// the albedo it delivers the documented magnitude and drops the vanilla-AO weight
	// the albedo carries, so the term reads as self-lit as the A3 note intends.
	return surfaceColor * finalDiffuse + heatGlow;
}

#endif
