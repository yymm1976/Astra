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
#include "/lib/end_surface.glsl"
struct EndParams { float nightVision; float heldLightBase; };
const vec3 END_SKY_LIGHT_COLOR = vec3(0.34,0.39,0.52) * ASTRA_TINT_END_LIGHT;
const vec3 END_AMBIENT_COLOR = vec3(0.043,0.055,0.077) * ASTRA_TINT_END_AMBIENT;
const vec3 END_VOID_COLOR = vec3(0.000015,0.000025,0.00006) * ASTRA_TINT_END_SKY;
vec3 end_void_tint(float y) { return END_VOID_COLOR; }
// The voidTint/time parameters were never consumed by the body and are gone
// (consolidated review E5 / Qoder F-52).
vec3 end_sky(vec3 dir) {
    // Uniform camera state: the entire analytic sky is multiplied by zero here.
    // Also clear its side-channel for the screen/reflection cache producers.
    if (blindness >= 1.0) {
        end_star_visibility = 0.0;
        return vec3(0.0);
    }
    vec3 sky=vec3(0);
    astra_end_blackhole(sky,normalize(dir),end_light_direction());
    // Darkness is applied to the assembled frame by program/display.fsh.
    return sky * ASTRA_TINT_END_SKY * (1.0-clamp(blindness,0.0,1.0));
}
vec4 end_fog(out float skyFogStrength, float distanceToEye, float borderDistance, vec3 playerPos) {
    skyFogStrength = 0.0;
    float f = 1.0 - exp(-2.0 * pow4(borderDistance / max(borderFogDistance, 1.0)) * (END_FOG_DENSITY * 0.01));
    vec3 c = END_VOID_COLOR;
    float dark = clamp(blindness,0.0,1.0);
    if (dark > 0.0) { f = max(f, 1.0-exp(-distanceToEye * dark * 0.1)); c *= 1.0-dark; }
    if (isEyeInWater == 2 && blindness <= 0.0001) { f = 1.0-exp(-distanceToEye*2.0); c=vec3(1.0,0.05,0.0); }
    return vec4(c, f);
}
// Reuse the same shadow visibility for surface highlights in the lit pass.
float end_surface_visibility=1.0;
float end_surface_eclipse=0.0;
vec3 end_lighting(vec3 albedo, vec3 normal, vec3 playerPos, vec3 shadowPos,
                  float blockLight, float emissive, float portal, float time,
                  EndParams params,out vec3 directRadiance) {
    float visibility=1.0;
    #ifdef SHADOWS
    if(dot(normal,end_light_direction())>0.0) {
        float coverage=shadow_coverage(playerPos,shadowPos);
        if(coverage>0.0)
            visibility=mix(1.0,shadow_opaque_visibility(shadowPos),coverage);
    }
    #endif
    end_surface_visibility=visibility;
    end_surface_eclipse=end_eclipse();
    // Linear irradiance retains directional contrast; the old clamped/square-root
    // blend flattened both the normal response and the cast shadows.
    vec3 color=end_surface_diffuse(albedo,normal,visibility,end_surface_eclipse,directRadiance);
    vec3 local=block_lighting(0.0,blockLight,held_light_strength(params.heldLightBase,playerPos),0.0,0.0);
    color+=albedo*(solasMinLight+params.nightVision*vec3(0.2,0.3,0.2)
                  +local+(emissive+portal*2.0)*(EMISSIVE_STRENGTH*0.01));
    return color;
}
#endif
