// Astra Nether integration: Complementary r5.9 mainLighting/common biome palette.
// Homogeneous fog shares the biome palette with lighting; no endpoint noise.
// The two directionShade squares are intentional reference behavior.
#ifndef ASTRA_GLOBAL_DIMENSION_NETHER_GLSL
#define ASTRA_GLOBAL_DIMENSION_NETHER_GLSL

#include "/lib/colors.glsl"
#include "/lib/encoding.glsl"
#include "/lib/nether_fog_density.glsl"
// Included from scene.glsl, which already guards on DIMENSION_NETHER; the option
// itself uses a plain #ifdef so Iris registers the boolean (SC-28).
#ifdef NETHER_VOXEL_LIGHT
    #if defined SHADOWS && BLOCKLIGHT_STRENGTH > 0
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

// Complementary mainFog.glsl: distance / min(renderDistance, 256).
const float NETHER_FOG_TINT = 0.50;

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
    vec3 palette = c / max(w, 0.0001);
    float coverage = clamp(w, 0.0, 1.0);
    if (coverage >= 1.0) return palette;
    return mix(fallback * 0.6 + 0.2 * normalize(fallback + 0.0001), palette, coverage);
}
// Complementary fog is blended before scene decoding; convert at Astra boundary.
vec3 nether_atmosphere_tint(vec3 biomeFogColor) {
    vec3 palette = nether_palette(biomeFogColor);
    return srgb_decode(palette) * ASTRA_TINT_NETHER;
}
vec3 nether_color(vec3 biomeFogColor) { return nether_palette(biomeFogColor); }
vec4 nether_fog(
	out float skyFogStrength,
	NetherParams params,
	float fragDistance,
	float borderFragDistance,
	vec3 playerPos
) {
	skyFogStrength = 0.0;
	// These camera media replace the biome atmosphere completely.
	if (blindness > 0.0001)
		return vec4(vec3(0.0), max(0.85, 1.0 - exp(-pow(fragDistance * blindness * 0.5, 2.0))));
	if (isEyeInWater == 2)
		return vec4(vec3(0.40, 0.13, 0.025), max(0.85, 1.0 - exp(-pow(fragDistance * 0.5, 2.0))));
	vec3 tint = nether_atmosphere_tint(params.biomeFogColor);
	float densityScale = NETHER_FOG_DENSITY * 0.01 * astra_nether_biome_density();

    float fogFactor = 0.0;
    #ifdef BORDER_FOG
        float farM = max(min(borderFogDistance, 256.0), 1.0);
        fogFactor = clamp(fragDistance / farM * densityScale, 0.0, 1.0);
    #endif

	vec3 fogColor = tint;
	if (isEyeInWater == 1) {
		fogFactor = 1.0 - exp(-pow(fragDistance * 0.02 * (UNDERWATER_FOG_DENSITY * 0.01), 2.0));
		fogColor = tint * NETHER_FOG_TINT;
		skyFogStrength = 0.0;
	}

	return vec4(fogColor, fogFactor);
}

vec3 nether_sky(vec3 worldViewDir, vec3 tint) { return tint; }

// Complementary mainLighting: default XLIGHT_CURVE=1, blocklightColors palette.
float nether_lightmap_intensity(float level) {
    if (level <= 0.0) return 0.0;
    float steep = pow(level, 8.0) * (3.8 - 0.6 * NETHER_VS_BRIGHTNESS);
    float calm = level * (1.8 + 0.6 * NETHER_VS_BRIGHTNESS);
    return pow(steep + calm, 2.25);
}
vec3 nether_block_lighting(float blockLight, float heldLight) {
    float blockIntensity = nether_lightmap_intensity(clamp(blockLight, 0.0, 1.0))
                         * (BLOCKLIGHT_STRENGTH * 0.01);
    float heldIntensity = 0.0;
    #ifdef HANDHELD_LIGHTING
        heldIntensity = nether_lightmap_intensity(clamp(heldLight, 0.0, 1.0));
    #endif
    // Preserve the reference hue/curve below the old Astra red-channel ceiling.
    // The uncapped reference peak is 8.56; the runtime feedback requires only
    // reductions, including when handheld and block light are combined.
    return vec3(0.1775, 0.104, 0.077) * ASTRA_TINT_BLOCK * ASTRA_STYLE_BLOCK
         * min(4.4 / 0.1775, sqrt(blockIntensity * blockIntensity + heldIntensity * heldIntensity));
}

float nether_emissive_boost(float emissiveMask, float portalMask, float time) {
	if (emissiveMask < 0.0001 && portalMask < 0.0001) { return 0.0; }

	float boost = (EMISSIVE_STRENGTH * 0.01)
	            * mix(NETHER_EMISSIVE_BOOST, NETHER_PORTAL_BOOST, portalMask);

    // Ordinary emitters have no portal shimmer, so its time sine is unused.
    if (portalMask > 0.0)
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
    vec3 netherCol = nether_palette(params.biomeFogColor) * ASTRA_TINT_NETHER;

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
	                 * NETHER_FLOOR_TINT; // Nether skylight is zero in GetMinimumLighting.
	minLighting += params.nightVision * NETHER_NIGHT_VISION_TINT_REF;

    // Fully emissive receivers discard local light. Keep their scene and
    // emission response, without evaluating light curves that multiply by zero.
    float localShare=1.0-clamp(max(emissiveMask,portalMask),0.0,1.0);
	vec3 blockLighting = vec3(0.0);
    if (localShare > 0.0) {
        #if BLOCKLIGHT_STRENGTH > 0
        blockLighting = nether_block_lighting(blockLight, 0.0);
        #endif
    #if defined NETHER_VOXEL_LIGHT && defined SHADOWS && BLOCKLIGHT_STRENGTH > 0
        // Solas gbuffersLighting replaces the warm block-light term, rather than
        // adding a second copy after diffuse lighting. Astra only reaches eight
        // cells, so fade by available radiance as well as the volume boundary;
        // distant/unrepresented sources retain vanilla block-light support.
        if (emissiveMask < 0.5 && portalMask < 0.5) {
            vec3 voxel = astra_nether_colored_light(playerPos, worldNormal);
            float coverage = smoothstep(0.002, 0.04, max(voxel.r, max(voxel.g, voxel.b)));
            // The bounded voxel field is incomplete. Retain some lightmap support
            // on receivers instead of replacing 95% with a weak local estimate.
            blockLighting = mix(blockLighting, voxel * (BLOCKLIGHT_STRENGTH * 0.01), coverage * 0.75);
        }
    #endif
        // Keep hand-held light separate from volume coverage, as Solas does.
        float held = held_light_strength(params.heldLightBase, playerPos);
        if (held > 0.0) blockLighting += nether_block_lighting(0.0, held);
        blockLighting *= localShare;
    }

	float emission = nether_emissive_boost(emissiveMask, portalMask, time);

    // Complementary terrain AO lift, Nether exponent and residual floor.
    float vanillaAO = clamp(vertexAO + 0.08, 0.0, 1.0);
	vanillaAO = pow(pow(vanillaAO, 1.5), 1.0 + max(NdotU, 0.0) * 0.5);
	vanillaAO = vanillaAO * 0.9 + 0.1;

	vec3 finalDiffuse = directionShade * directionShade * vanillaAO * vanillaAO
	                  * (blockLighting + sceneLighting * sceneLighting + minLighting)
	                  + emission * emission;
    // Preserve the reference colour-domain response and bound its hot edge.
    vec3 lightRoot = sqrt(max(finalDiffuse, vec3(0.0)));
    vec3 referenceColor = srgb_decode(srgb_encode(surfaceColor) * lightRoot);
    vec3 color = min(referenceColor, surfaceColor * lightRoot);
    if (emissiveMask <= 0.0001 && portalMask <= 0.0001) {
        // Soft indirect illumination belongs to ordinary receivers only. Use
        // orientation and partial occlusion so cavities retain shape, and fade
        // it out in well-lit areas instead of lifting exposure or emitters.
        float dim = 1.0 - smoothstep(0.20, 0.90,
            dot(lightRoot, vec3(0.2126, 0.7152, 0.0722)));
        float occlusion = 0.25 + 0.75 * vanillaAO;
        color += surfaceColor * vec3(0.10, 0.115, 0.13)
               * directionShade * occlusion * dim
               * (0.7 + 0.3 * NETHER_VS_BRIGHTNESS);
    }
    return color;
}

#endif
