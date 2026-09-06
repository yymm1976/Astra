#ifndef ASTRA_PROGRAM_SCENE_GLSL
#define ASTRA_PROGRAM_SCENE_GLSL
// E1 composition boundary. Positions are camera-relative, world axes.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/encoding.glsl"
#include "/lib/transforms.glsl"
#include "/global/lighting/shadowmap.glsl"
#include "/global/lighting/blocklight.glsl"
#include "/global/lighting/sss.glsl"
#include "/global/lighting/diffuse.glsl"
#include "/global/atmosphere/fog.glsl"
#include "/global/water/absorption.glsl"
#if defined DIMENSION_NETHER
    #include "/global/dimension/nether.glsl"
#elif defined DIMENSION_END
    #include "/global/dimension/end.glsl"
#else
    #include "/global/atmosphere/sky_minishita.glsl"
    #include "/global/atmosphere/sky_gradient.glsl"
    #include "/global/atmosphere/stars.glsl"
    #include "/global/atmosphere/clouds_planar.glsl"
    #include "/global/dimension/overworld.glsl"
#endif

vec3 astra_sky(vec3 worldDir) {
    #if defined DIMENSION_NETHER
        return nether_sky(worldDir, nether_atmosphere_tint(fogColor));
    #elif defined DIMENSION_END
        return end_sky(worldDir, end_void_tint(cameraPosition.y), frameTimeCounter);
    #else
        vec3 sky = astra_overworld_sky(worldDir);
        #if CLOUD_MODE == CLOUD_PLANAR
            vec4 cloud = astra_planar_cloud(worldDir, astra_direct_light(), astra_sky_ambient());
            sky = mix(sky, cloud.rgb, cloud.a);
        #endif
        return sky;
    #endif
}
vec3 astra_reflection_sky(vec3 worldDir, float roughness) {
    #if defined DIMENSION_NETHER
        return nether_sky(worldDir, nether_atmosphere_tint(fogColor));
    #elif defined DIMENSION_END
        // No high frequency star field in reflections without temporal filtering.
        return mix(END_VOID_COLOR, END_SKY_LIGHT_COLOR * 0.1, max(worldDir.y, 0.0));
    #else
        return astra_sky_reflection(worldDir, roughness);
    #endif
}
vec3 astra_underwater_color() {
    #if WATER_CHARACTER == WATER_COLD
        vec3 waterTint = vec3(0.015, 0.10, 0.16);
    #elif WATER_CHARACTER == WATER_TROPICAL
        vec3 waterTint = vec3(0.01, 0.22, 0.18);
    #else
        vec3 waterTint = vec3(0.015, 0.14, 0.17);
    #endif
    float skylight = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
    return waterTint * mix(0.10, 1.0, skylight * mix(0.15, 1.0, dayUnderwaterFogFade));
}
vec4 astra_fog(vec3 playerPos, float skylight) {
    float distanceToCamera = length(playerPos);
    vec3 direction = playerPos / max(distanceToCamera, 1e-5);
    float skyStrength;
    vec4 fog;
    #if defined DIMENSION_NETHER
        NetherParams params = NetherParams(fogColor, nightVision, astraHeldLightBase);
        fog = nether_fog(skyStrength, params, distanceToCamera, distanceToCamera, playerPos);
    #elif defined DIMENSION_END
        fog = end_fog(skyStrength, distanceToCamera, distanceToCamera, playerPos);
    #else
        FogParams params = FogParams(MIN_AMBIENT_COLOR, astra_underwater_color(),
                                     clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0));
        fog = fog_v2(skyStrength, params, distanceToCamera, distanceToCamera, skylight);
    #endif
    if (skyStrength > 0.0 && fog.a > 0.0) {
        vec3 sky = astra_reflection_sky(direction, 1.0);
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
            #ifdef AIR_PERSPECTIVE
                sky = fog_air_perspective(sky, direction, astra_direct_light());
            #endif
            #ifdef BIOME_TINT
                sky = fog_biome_tint(sky, srgb_decode(max(fogColor, vec3(0.0))));
            #endif
        #endif
        fog.rgb += sky * skyStrength;
    }
    if (isEyeInWater == 1 && blindness <= 0.0001) fog.rgb = astra_underwater_color();
    return vec4(max(fog.rgb, vec3(0.0)), clamp(fog.a, 0.0, 1.0));
}
vec3 astra_apply_medium(vec3 color, vec3 playerPos, float skylight) {
    if (isEyeInWater == 1) color *= water_absorption(clamp(length(playerPos) / 32.0, 0.0, 1.0));
    vec4 fog = astra_fog(playerPos, skylight);
    return mix(color, fog.rgb, fog.a);
}
vec3 astra_light(vec3 albedo, vec3 normal, vec3 playerPos,
                 float skylight, float blocklight, uint material) {
    float emissive = material == 10u ? 1.0 : 0.0;
    float portal = material == 7u ? 1.0 : 0.0;
    #if defined DIMENSION_NETHER
        NetherParams params = NetherParams(fogColor, nightVision, astraHeldLightBase);
        return nether_lighting(albedo, normal, playerPos, blocklight, emissive, portal,
                               frameTimeCounter, params);
    #elif defined DIMENSION_END
        EndParams params = EndParams(nightVision, astraHeldLightBase);
        return end_lighting(albedo, normal, playerPos, blocklight, emissive, portal,
                            frameTimeCounter, params);
    #else
        LightParams params = LightParams(astra_sky_ambient(), astra_direct_light(),
            nightVision, astraBlocklightSuppression, astraHeldLightBase,
            astraHeldLightSuppression, lightningBoltPosition);
        bool sss = material >= 2u && material <= 6u;
        #ifndef SSS_FOLIAGE
            sss = false;
        #endif
        vec3 shadowPos = shadow_map_position(playerPos, normal,
                            dot(normal, normalize(view_player(lightVector))));
        vec3 color = diffuse_lighting(albedo, normal, playerPos, shadowPos,
                         skylight, blocklight, sss, material == 2u, material == 8u, params);
        return color + albedo * ((emissive + portal) * (EMISSIVE_STRENGTH * 0.01));
    #endif
}
#endif
