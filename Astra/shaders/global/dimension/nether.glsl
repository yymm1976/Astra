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
	float heldLightBase;   // CPU heldBlockLightValue / 15, 0..1 — see C1 blocklight.glsl
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
    if (astraNetherCoverage >= 1.0) return astraNetherPalette;
    // Unknown/custom biomes retain the original per-call fallback colour.
    return mix(fallback * 0.6 + 0.2 * normalize(fallback + 0.0001),
               astraNetherPalette, astraNetherCoverage);
}
// Complementary fog is blended before scene decoding; convert at Astra boundary.
vec3 nether_atmosphere_tint(vec3 biomeFogColor) {
    if (astraNetherCoverage >= 1.0) return astraNetherPaletteLinear * ASTRA_TINT_NETHER;
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
    // scene.glsl blends blindness after the ordinary fog colour is assembled.
	if (isEyeInWater == 2) {
		float lavaFog=fragDistance*0.5;
		return vec4(vec3(0.40, 0.13, 0.025), max(0.85, 1.0 - exp(-lavaFog*lavaFog)));
	}
	vec3 tint = nether_atmosphere_tint(params.biomeFogColor);
	// The water branch replaces the border term entirely, so it is resolved
	// before the biome density is read and before the border factor is built.
	if (isEyeInWater == 1) {
		float waterFog=fragDistance*0.02*(UNDERWATER_FOG_DENSITY*0.01);
		return vec4(tint * NETHER_FOG_TINT, 1.0 - exp(-waterFog*waterFog));
	}
	float densityScale = NETHER_FOG_DENSITY * 0.01 * astra_nether_biome_density();
    // fragDistance is Euclidean length, deliberately retaining Astra's distance
    // convention rather than the reference max(horizontal, vertical) metric.

    float fogFactor = 0.0;
    #ifdef BORDER_FOG
        float farM = max(min(borderFogDistance, 256.0), 1.0);
        fogFactor = clamp(fragDistance / farM * densityScale, 0.0, 1.0);
    #endif

	return vec4(tint, fogFactor);
}

vec3 nether_sky(vec3 worldViewDir, vec3 tint) { return tint; }

// Complementary mainLighting: default XLIGHT_CURVE=1, blocklightColors palette.
float nether_lightmap_intensity(float level) {
    if (level <= 0.0) return 0.0;
    float steep = pow8(level) * (3.8 - 0.6 * NETHER_VS_BRIGHTNESS);
    float calm = level * (1.8 + 0.6 * NETHER_VS_BRIGHTNESS);
    // Both terms are non-negative, so x^2.25 = x^2 * x^(1/4) is an exact identity
    // here. Two hardware square roots replace the transcendental pow(), matching the
    // pack's existing x^1.5 -> x*sqrt(x) substitution. Rounding may differ.
    float base = steep + calm;
    return base * base * sqrt(sqrt(base));
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
            // Voxel emitters retain their species colours; tint/style controls
            // currently apply to lightmap/held light rather than this field.
            vec3 coloredLight=voxel*(BLOCKLIGHT_STRENGTH*0.01);
            const vec3 localLumaWeights=vec3(0.2126,0.7152,0.0722);
            float coloredLuma=dot(coloredLight,localLumaWeights);
            float supportLuma=dot(blockLighting,localLumaWeights);
            // The short-range field provides local hue; the lightmap still
            // supplies missing intensity. Replacing a stronger lightmap with
            // weak voxel radiance otherwise darkens lit fortress receivers.
            if (coloredLuma>0.00001)
                coloredLight*=max(coloredLuma,supportLuma)/coloredLuma;
            coloredLight*=astra_nether_light_facing(playerPos,worldNormal,voxel);
            blockLighting = mix(blockLighting,coloredLight,coverage*0.75);
        }
    #endif
        // Keep hand-held light separate from volume coverage, as Solas does.
        float held = held_light_strength(params.heldLightBase, playerPos);
        if (held > 0.0) blockLighting += nether_block_lighting(0.0, held)
            * astra_held_light_tint() * astra_held_light_facing(playerPos, worldNormal);
        blockLighting *= localShare;
    }

	float emission = nether_emissive_boost(emissiveMask, portalMask, time);

    // Complementary terrain AO lift, Nether exponent and residual floor.
    float vanillaAO = clamp(vertexAO + 0.08, 0.0, 1.0);
	vanillaAO = pow(vanillaAO, 1.5 + max(NdotU, 0.0) * 0.75);
	vanillaAO = vanillaAO * 0.9 + 0.1;

	vec3 finalDiffuse = directionShade * directionShade * vanillaAO * vanillaAO
	                  * (blockLighting + sceneLighting * sceneLighting + minLighting)
	                  + emission * emission;
    // Preserve the reference colour-domain response and bound its hot edge.
    vec3 lightRoot = sqrt(max(finalDiffuse, vec3(0.0)));
    vec3 color = surfaceColor * lightRoot;
    // Above unit illumination the IEC decode response grows at least linearly,
    // so the existing min cap already chooses this linear branch. Bright lava,
    // portals and fully lit surfaces need neither sRGB transfer here.
    if (any(lessThan(lightRoot, vec3(1.0)))) {
        vec3 referenceColor = srgb_decode(srgb_encode(surfaceColor) * lightRoot);
        color = min(referenceColor, color);
    }
    if (emissiveMask <= 0.0001 && portalMask <= 0.0001) {
        // Soft indirect illumination belongs to ordinary receivers only. Use
        // orientation and partial occlusion so cavities retain shape, and fade
        // it out in well-lit areas instead of lifting exposure or emitters.
        float dim = 1.0 - smoothstep(0.20, 0.90,
            dot(lightRoot, vec3(0.2126, 0.7152, 0.0722)));
        float occlusion = 0.35 + 0.65 * vanillaAO;
        color += surfaceColor * vec3(0.18, 0.195, 0.21)
               * directionShade * occlusion * dim
               * (0.7 + 0.3 * NETHER_VS_BRIGHTNESS);
    }
    return color;
}

// Material-specific readability for dark Nether masonry. This is a restrained
// diffuse environment term, not an emitter or a fabricated off-screen reflection.
// Fade it under existing light and preserve the original texture and corner AO.
vec3 nether_masonry_ambient(vec3 litColor,vec3 albedo,vec3 normal,float vertexAO) {
    const vec3 weights=vec3(0.2126,0.7152,0.0722);
    float illumination=dot(litColor,weights)/max(dot(albedo,weights),0.00001);
    float dim=1.0-smoothstep(0.12,0.35,illumination);
    float ao=clamp(vertexAO,0.0,1.0);
    float openness=0.25+0.75*ao*ao;
    float facing=0.8+0.2*max(normal.y,0.0);
    return litColor+albedo*vec3(0.070,0.065,0.075)*dim*openness*facing
                        *(0.7+0.3*NETHER_VS_BRIGHTNESS);
}

#endif
