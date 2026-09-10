// Astra Nether integration: Complementary r5.9 mainLighting/common biome palette.
// Homogeneous fog shares the biome palette with lighting; no endpoint noise.
// The two directionShade squares are intentional reference behavior.
#ifndef ASTRA_GLOBAL_DIMENSION_NETHER_GLSL
#define ASTRA_GLOBAL_DIMENSION_NETHER_GLSL

#include "/lib/colors.glsl"
#include "/lib/encoding.glsl"
#include "/lib/noise.glsl"

struct NetherParams {
	vec3  biomeFogColor;   // vanilla fogColor (sRGB-ish 0..1), per nether biome — E1 supplies
	float nightVision;     // built-in (not frozen): 0..1, lifts the ambient floor only
	float heldLightBase;   // CPU pow(heldBlockLightValue / 15, 4), 0..1 — see C1 blocklight.glsl
};

const vec3  NETHER_LAVA_LIGHT_COLOR = vec3(0.15, 0.06, 0.01);

#define NETHER_VS_BRIGHTNESS clamp(screenBrightness, 0.0, 1.0)

const vec3  NETHER_FLOOR_TINT = vec3(0.45, 0.475, 0.6);
const vec3  NETHER_NIGHT_VISION_TINT_REF = vec3(0.5, 0.5, 0.75);

const float NETHER_FOG_NEAR_COEFF = 0.0040;
const float NETHER_FOG_FAR_COEFF  = 6.0;
const float NETHER_FOG_FAR_EXP    = 4.0;
const float NETHER_FOG_TINT       = 0.25;      // Solas: fogCol = netherColSqrt * 0.25

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
vec3 nether_atmosphere_tint(vec3 biomeFogColor) { return to_linear(nether_palette(biomeFogColor)); }
vec3 nether_color(vec3 biomeFogColor) { return to_linear(nether_palette(biomeFogColor)); }
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

	vec3 fogColor = tint * NETHER_FOG_TINT;

	fogColor = tint;
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
	float intensity = pow(blockLight, NETHER_BLOCKLIGHT_EXPONENT) * (BLOCKLIGHT_STRENGTH * 0.01);

	#ifdef HANDHELD_LIGHTING
		intensity += pow(heldLight, NETHER_BLOCKLIGHT_EXPONENT);
	#endif

	return BLOCKLIGHT_COLOR * min(1.0, intensity);
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
	NetherParams params
) {

	vec3 netherCol = nether_color(params.biomeFogColor);

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

	vec3 blockLighting = nether_block_lighting(
		blockLight,
		held_light_strength(params.heldLightBase, playerPos));

	float emission = nether_emissive_boost(emissiveMask, portalMask, time);

	float vanillaAO = 1.0;
	vec3 finalDiffuse = directionShade * directionShade * vanillaAO * vanillaAO
	                  * (blockLighting + sceneLighting * sceneLighting + minLighting)
	                  + emission * emission;
	finalDiffuse = sqrt(max(finalDiffuse, vec3(0.0)));

	return surfaceColor * finalDiffuse;
}

#endif
