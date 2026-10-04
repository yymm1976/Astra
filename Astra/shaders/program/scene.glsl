#ifndef ASTRA_PROGRAM_SCENE_GLSL
#define ASTRA_PROGRAM_SCENE_GLSL
// E1 composition boundary. Positions are camera-relative, world axes.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/encoding.glsl"
#include "/lib/transforms.glsl"
// Integer-power helpers (square/cube/pow4../power). Included before every consumer:
// global/lighting/sss.glsl's transmission lobe, global/atmosphere/sky_gradient.glsl's
// runtime sky factors. See lib/pow.glsl for why this exists and what was measured.
#include "/lib/pow.glsl"
// twilight.glsl first: global/atmosphere/fog.glsl's directional term reuses
// astra_twilight_sky() and astra_twilight_strength().
#include "/lib/twilight.glsl"
#include "/global/lighting/shadowmap.glsl"
#include "/global/lighting/blocklight.glsl"
#include "/global/lighting/sss.glsl"
#include "/global/water/absorption.glsl"
#include "/global/water/optics.glsl"
#include "/global/water/medium_state.glsl"
#include "/lib/solas_water.glsl"
#include "/global/lighting/diffuse.glsl"
#include "/global/atmosphere/fog.glsl"
#if defined DIMENSION_NETHER
    #include "/global/dimension/nether.glsl"
#elif defined DIMENSION_END
    // Non-buffer sky queries run inside material/fog branches and need an
    // analytic footprint; the full-screen End producer supplies its derivatives.
    #define ASTRA_END_REFLECTION_FOOTPRINT
    #include "/global/dimension/end.glsl"
#else
    #include "/global/atmosphere/sky_minishita.glsl"
    #include "/global/atmosphere/sky_gradient.glsl"
    #include "/global/atmosphere/stars.glsl"
    #include "/global/atmosphere/clouds_planar.glsl"
    #include "/global/dimension/overworld.glsl"
    #if CLOUD_MODE == CLOUD_PLANAR
        #include "/global/atmosphere/cloud_shadow_cache.glsl"
    #endif
    #include "/global/atmosphere/weather.glsl"
    // R2/H3: the optional overworld volume march. Included last so its source terms
    // (astra_direct_light, astra_sky_ambient, cloud shadow, shadow map) exist; it owns
    // the ordinary overworld air segment when VOLUMETRIC_FOG is on and compiles to
    // nothing otherwise (bare #ifdef VOLUMETRIC_FOG inside).
    #include "/global/atmosphere/volume_fog.glsl"
#endif

vec3 astra_sky(vec3 worldDir) {
    #if defined DIMENSION_NETHER
        return nether_sky(worldDir, nether_atmosphere_tint(fogColor));
    #elif defined DIMENSION_END
        return end_sky(worldDir);
    #else
        vec3 sky = astra_overworld_sky(worldDir);
        #if CLOUD_MODE == CLOUD_PLANAR
            vec4 cloud = astra_planar_cloud(worldDir);
            sky = mix(sky, cloud.rgb, cloud.a);
        #endif
        return sky;
    #endif
}
vec3 astra_reflection_sky(vec3 worldDir, float roughness) {
    #if defined DIMENSION_NETHER
        return nether_sky(worldDir, nether_atmosphere_tint(fogColor));
    #elif defined DIMENSION_END
        vec3 sky=end_sky(normalize(worldDir));
        return mix(sky,END_SKY_LIGHT_COLOR*0.002,clamp(roughness*roughness,0.0,1.0));
    #else
        return astra_sky_reflection(worldDir, roughness);
    #endif
}
#include "/lib/environment_brdf.glsl"
// Ambient incident radiance only. Direct sunlight belongs to the spatial source
// below; putting it here also would scatter an unoccluded sun for a second time.
vec3 astra_water_incident(float skylight) {
    float access = smoothstep(0.0, 0.40, skylight);
    #if defined DIMENSION_NETHER || defined DIMENSION_END
        vec3 outdoor = max(fogColor, vec3(0.0)) * 0.25;
    #else
        vec3 outdoor = astra_sky_ambient() * (SKYLIGHT_STRENGTH * 0.01);
    #endif
    return mix(MIN_AMBIENT_COLOR, outdoor, access);
}
vec3 astra_underwater_color(vec3 viewDir) {
    float eyeSky = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
    vec3 incident = astra_water_incident(eyeSky);
    return incident * water_scattering_coefficient()
         / max(water_extinction(), vec3(1e-6));
}
// Integrate the OTHER leg of a water-surface path (interface to floor, or
// interface to reflected terrain). The camera leg is handled separately.
// start MUST be the actual water/air interface, in camera-relative world axes.
// Its world Y anchors this local column. An upward ray leaving that horizontal
// interface is outside this volume and correctly receives no water sun source.
vec3 astra_water_segment(vec3 radiance, vec3 start, vec3 finish, float skylight) {
    if (isEyeInWater == 0)
        return water_surface_medium(radiance, start.y - finish.y, astra_water_incident(skylight));
    vec3 delta = finish - start;
    float distanceInWater = length(delta);
    vec3 result = water_medium(radiance, distanceInWater, astra_water_incident(skylight));
    return result;
}
vec4 astra_fog(vec3 playerPos, float skylight) {
    float distanceToCamera = length(playerPos);
    vec3 direction = playerPos / max(distanceToCamera, 1e-5);
    // Powder snow is a camera medium in every dimension. Use the engine's
    // medium colour; ordinary atmosphere settings must not remove its occlusion.
    if (isEyeInWater == 3 && blindness <= 0.0001)
        return vec4(srgb_decode(max(fogColor, vec3(0.0))),
                    smoothstep(0.0, 2.0, distanceToCamera));
    #ifdef ASTRA_VOLUME_FOG
    // The ray-marched volume owns the ordinary overworld air segment (handoff R2
    // section 1): fog_v2's atmospheric term, the morning haze, the sky add,
    // AIR_PERSPECTIVE and BIOME_TINT are REPLACED, not stacked on top of it. This
    // entry re-integrates the shared density model for the caller's own endpoint -
    // the buffered half-resolution march is consumed only by the deferred compose.
    // Blindness, lava, powder snow (above) and water legs keep their own paths.
    if ((isEyeInWater == 0 || water_is_thin_sheet()) && blindness <= 0.0001) {
        vec4 volume = astra_volume_border(astra_volume_prefix_medium(playerPos), distanceToCamera);
        // This facade returns a straight fog colour for mix(scene, colour, opacity).
        // The volume stores integrated scattering, already weighted by extinction.
        float opacity = clamp(1.0 - volume.a, 0.0, 1.0);
        return vec4(max(volume.rgb, vec3(0.0)) / max(opacity, 0.000001), opacity);
    }
    #endif
    // Absolute world height of the fragment: the valley mist lives in the world, not
    // in camera space, so it must not move when the camera does.
    float fragWorldY = cameraPosition.y + playerPos.y;
    float skyStrength;
    vec4 fog;
    #if defined DIMENSION_NETHER
        NetherParams params = NetherParams(fogColor, nightVision, astraHeldLightBase);
        fog = nether_fog(skyStrength, params, distanceToCamera, distanceToCamera, playerPos);
    #elif defined DIMENSION_END
        fog = end_fog(skyStrength, distanceToCamera, distanceToCamera, playerPos);
    #else
        vec3 underwaterFog = vec3(0.0);
        if (isEyeInWater == 1 && !water_is_thin_sheet() && blindness <= 0.0001)
            underwaterFog = astra_underwater_color(direction);
        FogParams params = FogParams(MIN_AMBIENT_COLOR, underwaterFog,
                                     clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0));
        fog = fog_v2(skyStrength, params, distanceToCamera, distanceToCamera, skylight,
                     fragWorldY);
    #endif
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        if ((isEyeInWater == 0 || water_is_thin_sheet()) && blindness <= 0.0001) {
            #ifdef CAVE_FOG
                float eyeSky = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
                float outdoorWeight = smoothstep(0.0, 0.25, max(skylight, eyeSky));
            #else
                float outdoorWeight = 1.0;
            #endif
            float morning=astra_twilight_strength()*outdoorWeight;
            // Complementary mainFog: denser low-altitude air and a distance
            // curve, with the down-sky colour as the atmospheric target.
            // The altitude weight is now the shared valley-mist remap (fog.glsl)
            // instead of an inline smoothstep, so the twilight haze, the atmospheric
            // density curve and the morning air all read the same height field and
            // cannot disagree about where the low air is. End points are unchanged:
            // 0.62 at the valley floor, 0.22 above Y=150.
            if (morning > 0.0 && distanceToCamera > 24.0) {
                float fogAirWeight=fog_morning_air_weight(fragWorldY);
                float morningFog=(1.0-exp(-pow((distanceToCamera-24.0)*0.003,1.4)))
                                *morning*fogAirWeight;
                fog.a=1.0-(1.0-fog.a)*(1.0-morningFog);
            }
            if (fog.a<=0.0) return vec4(0.0);
            skyStrength=mix(skyStrength,max(skyStrength,0.78),morning);
            float horizonConvergence = smoothstep(0.68, 0.98, fog.a) * outdoorWeight;
            if (skyStrength <= 0.0 && horizonConvergence <= 0.0)
                return vec4(max(fog.rgb, vec3(0.0)), clamp(fog.a, 0.0, 1.0));
            // Keep a clean sky target for the fully fogged horizon. SKY_FOG_STRENGTH
            // controls the near/mid-distance sky contribution, but must not make
            // fully fogged outdoor terrain darker than the sky behind it.
            vec3 horizonSky = astra_sky_radiance(direction);
            if (skyStrength > 0.0) {
                vec3 localFogSky = horizonSky;
                #ifdef AIR_PERSPECTIVE
                    localFogSky = fog_air_perspective(
                        localFogSky, direction, astra_direct_light());
                #endif
                // The shared sky already contains the sunrise lobe. Do not add
                // a second solar glare to air and turn the valley white again.
                localFogSky=mix(localFogSky,horizonSky,morning);
                #ifdef BIOME_TINT
                    // Biome colour belongs to thin local haze. Fade it away before the
                    // horizon converges to the atmosphere, preventing a persistent
                    // fogColor-derived green/yellow band at long range.
                    float biomeTintWindow = (1.0 - smoothstep(0.35, 0.82, fog.a))*(1.0-0.75*morning);
                    if (biomeTintWindow > 0.0) {
                        vec3 biomeFogSky = fog_biome_tint(
                            localFogSky, srgb_decode(max(fogColor, vec3(0.0))));
                        localFogSky = mix(localFogSky, biomeFogSky, biomeTintWindow);
                    }
                #endif
                fog.rgb += localFogSky * skyStrength;
            }

            fog.rgb = mix(fog.rgb, horizonSky, horizonConvergence);
        }
    #else
        if (skyStrength > 0.0 && fog.a > 0.0) {
            vec3 sky = astra_reflection_sky(direction, 1.0);
            fog.rgb += sky * skyStrength;
        }
    #endif
    // Overworld fog_v2 already returns the identical underwater colour.
    #if defined DIMENSION_NETHER || defined DIMENSION_END
    if (isEyeInWater == 1 && blindness <= 0.0001) {
        fog.rgb = astra_underwater_color(direction);
        // Directional scattering is integrated after translucent geometry (SC-33).
        // This function supplies only the background medium, once per optical path.
    }
    #endif
    return vec4(max(fog.rgb, vec3(0.0)), clamp(fog.a, 0.0, 1.0));
}
vec3 astra_apply_medium(vec3 color, vec3 playerPos, float skylight) {
    if (isEyeInWater == 1 && !water_is_thin_sheet()) {
        #if defined DIMENSION_NETHER || defined DIMENSION_END
            // These dimensions have no underwater composite to apply blindness.
            if (blindness <= 0.0001)
                return astra_water_segment(color, vec3(0.0), playerPos, skylight);
        #else
            // Camera water fog is composed once after all geometry.
            return color;
        #endif
    }
    vec4 fog = astra_fog(playerPos, skylight);
    #ifdef DIMENSION_NETHER
    vec3 result = srgb_decode(mix(srgb_encode(max(color, vec3(0.0))),
                                  srgb_encode(fog.rgb), fog.a));
    #else
    vec3 result = mix(color, fog.rgb, fog.a);
    #endif
    return result;
}
vec3 astra_light(vec3 albedo, vec3 normal, vec3 playerPos, vec3 shadowPos,
                 float skylight, float blocklight, uint material, out vec3 directRadiance,
                 float vertexAO, out vec3 ambientRadiance, out vec3 skyResponse) {
    directRadiance = vec3(0.0);
    ambientRadiance = vec3(0.0);
    // R1: re-evaluable directional-sky share of ambientRadiance (without the SH
    // direction). Zero in the nether/end and whenever the directional sky did
    // not contribute; lit stores it in colortex27 for the deferred2 swap.
    skyResponse = vec3(0.0);
    float emissive = material == 10u ? 1.0 : 0.0;
    float portal = material == 7u ? 1.0 : 0.0;
    #if defined DIMENSION_NETHER
        NetherParams params = NetherParams(fogColor, nightVision, astraHeldLightBase);
        return nether_lighting(albedo, normal, playerPos, blocklight, emissive, portal,
                               frameTimeCounter, params, vertexAO);
    #elif defined DIMENSION_END
        EndParams params = EndParams(nightVision, astraHeldLightBase);
        return end_lighting(albedo, normal, playerPos, shadowPos, blocklight, emissive, portal,
                            frameTimeCounter, params, directRadiance);
    #else
        LightParams params = LightParams(astra_sky_ambient(), astra_direct_light(),
            nightVision, astraBlocklightSuppression, astraHeldLightBase,
            astraHeldLightSuppression, lightningBoltPosition);
        // The bed receives the same incident daylight as the bank. A second
        // reference palette made daytime transmission blue while torchlight
        // stayed cyan. Interface absorption owns the water colour, once.

        #ifdef CLOUD_SHADOWS
            // PROVENANCE: BSL (lib/lighting/shadows.glsl:295-374, All Rights Reserved) +
            //   Complementary Reimagined r5.9 (lib/lighting/cloudShadows.glsl:60, License
            //   1.7) - IDEA ONLY, no code and no formula transplanted: project 2D cloud
            //   density along the light onto the ground, and fade that projection near the
            //   horizon. Every expression and constant below is Astra's own; THIRD-PARTY.md.
            // astraRainFactor is deliberately NOT a weight here: weather.glsl folds it
            // into the cloud density threshold, so multiplying by it again would double-
            // count the storm. static_shadow() is the pack's own "fully open to sky"
            // test - the one diffuse.glsl:253 uses for the shadow-map fallback - so a
            // roofed or underground surface never catches a cloud shadow. The source
            // elevation fade now belongs to the shared cache and field fallback,
            // rather than being evaluated again for every surface fragment.
            vec3 cloudLightDir = astra_world_light_direction();
            float cloudWeight = 0.75 * static_shadow(skylight);
            if ((isEyeInWater == 0 || water_is_thin_sheet()) && cloudWeight > 0.0 && astraCloudShadowFade > 0.0) {
                params.directLightSurface *= mix(1.0,
                    astra_cloud_transmission(playerPos + cameraPosition, cloudLightDir),
                    cloudWeight);
            }
        #else
        if ((isEyeInWater == 0 || water_is_thin_sheet()) && astraRainFactor > 0.01) {
            float cloudLight = astra_cloud_transmission(playerPos + cameraPosition, astra_world_light_direction());
            params.directLightSurface *= mix(1.0, cloudLight, astraRainFactor * 0.75);
        }
        #endif
        bool sss = material >= 2u && material <= 6u;
        #ifndef SSS_FOLIAGE
            sss = false;
        #endif
        vec3 color = diffuse_lighting(albedo, normal, playerPos, shadowPos,
                         skylight, blocklight, sss, material == 2u, material == 8u, params, directRadiance, ambientRadiance, skyResponse);
        return color + albedo * ((emissive + portal) * (EMISSIVE_STRENGTH * 0.01));
    #endif
}
#endif
