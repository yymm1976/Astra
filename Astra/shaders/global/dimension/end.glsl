#ifndef ASTRA_GLOBAL_DIMENSION_END_GLSL
#define ASTRA_GLOBAL_DIMENSION_END_GLSL
#include "/global/dimension/end_blackhole.glsl"
// Solas V2.2b: common.glsl End palette, skyEffects.glsl stars/nebula,
// fog.glsl distance curve and gbuffersLighting.glsl shadow mix.
// Astra: linear HDR boundary, full-screen sky, emissive stellar disc instead
// of vortex, and no atmospheric cloud layers. See THIRD-PARTY.md.
#include "/lib/colors.glsl"
#include "/lib/encoding.glsl"
#include "/lib/solas_water.glsl"
struct EndParams { float nightVision; float heldLightBase; };
const vec3 END_SKY_LIGHT_COLOR = vec3(0.34,0.39,0.52);
const vec3 END_AMBIENT_COLOR = vec3(0.032,0.043,0.067);
const vec3 END_VOID_COLOR = vec3(0.000015,0.000025,0.00006);
vec3 end_void_tint(float y) { return END_VOID_COLOR; }
vec3 end_sky(vec3 dir, vec3 voidTint, float time) {
    vec3 sky=vec3(0);
    astra_end_blackhole(sky,normalize(dir),end_light_direction());
    return sky*(1.0-max(blindness,darknessFactor));
}
vec4 end_fog(out float skyFogStrength, float distanceToEye, float borderDistance, vec3 playerPos) {
    skyFogStrength = 0.0;
    float f = 1.0 - exp(-2.0 * pow(borderDistance / max(borderFogDistance, 1.0), 4.0) * (END_FOG_DENSITY * 0.01));
    vec3 c = END_VOID_COLOR;
    float dark = max(blindness, darknessFactor);
    if (dark > 0.0) { f = max(f, 1.0-exp(-distanceToEye * dark * 0.1)); c *= 1.0-dark; }
    if (isEyeInWater == 2) { f = 1.0-exp(-distanceToEye*2.0); c=vec3(1.0,0.05,0.0); }
    return vec4(c, f);
}
vec3 end_lighting(vec3 albedo, vec3 normal, vec3 playerPos, vec3 shadowPos,
                  float blockLight, float emissive, float portal, float time, EndParams params) {
    float ndotl = max(dot(normal, end_light_direction()), 0.0);
    float visibility = 1.0;
    #ifdef SHADOWS
    float alignment=dot(normalize(view_player(lightVector)),end_light_direction());
    // Engine shadows follow its own light orbit. Suppress conflicting hard shadows
    // rather than allowing them to contradict the fixed astronomical source.
    float shadowStrength=mix(0.025,1.0,smoothstep(0.995,0.9995,alignment));
    visibility = mix(1.0, shadow_opaque_visibility(shadowPos), shadow_coverage(playerPos, shadowPos)*shadowStrength);
    #endif
    // Solas shadow mixing and palette. Astra uses a brighter diffuse response
    // below to keep the island readable with its separate exposure/tonemap.
    // This response is an artistic adaptation, not a color-space conversion.
    vec3 scene = mix(END_AMBIENT_COLOR, END_SKY_LIGHT_COLOR, visibility * ndotl) * 0.25;
    scene += solasMinLight + params.nightVision * vec3(0.2,0.3,0.2);
    vec3 factor = sqrt(max(scene, vec3(0.0))) * 1.22;
    vec3 local = block_lighting(0.0, blockLight, held_light_strength(params.heldLightBase, playerPos), 0.0, 0.0);
    return albedo * (factor * (1.0 - 0.18 * end_eclipse()) + local + (emissive + portal * 2.0) * (EMISSIVE_STRENGTH * 0.01));
}
#endif
