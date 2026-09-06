#ifndef ASTRA_PROGRAM_WATER_GLSL
#define ASTRA_PROGRAM_WATER_GLSL
// E2 owns this composition, C2/C7 own the algorithms; scene.glsl must precede it.
#include "/global/water/surface.glsl"
#include "/global/water/raytrace.glsl"
#include "/global/water/refraction.glsl"
#ifdef ASTRA_SCENE_COPY
uniform sampler2D colortex4;
#endif

vec4 astra_water(vec3 color, float alpha, vec3 playerPos, vec3 viewPos,
                  vec3 normal, float roughness, float skylight, bool water) {
    vec3 incident = normalize(viewPos);
    vec3 viewNormal = normalize(mat3(gbufferModelView) * normal);
    float facing = clamp(dot(-incident, viewNormal), 0.0, 1.0);
    float fresnel = 0.0204 + 0.9796 * pow(1.0 - facing, 5.0);
    vec3 reflection = astra_reflection_sky(normalize(view_player(reflect(incident, viewNormal))), roughness);
    #ifdef SCREENSPACE_REFLECTIONS
        vec4 hit = water_raytrace(colortex4, depthtex1, viewPos, viewNormal, roughness);
        reflection = mix(reflection, hit.rgb, hit.a);
    #endif
    #if defined ASTRA_SCENE_COPY && (defined SCREENSPACE_REFRACTION || WATER_ABSORPTION > 0)
        vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
        vec3 refracted = vec3(uv, texture(depthtex1, uv).r);
        #ifdef SCREENSPACE_REFRACTION
            float eta = isEyeInWater == 1 && water ? 1.333 : 0.7502;
            vec3 ray = refract(incident, viewNormal, eta);
            if (dot(ray, ray) < 1e-6) fresnel = 1.0;
            refracted = refract_trace(depthtex1, viewPos,
                mix(incident, ray, REFRACTION_STRENGTH * 0.01), 32.0);
        #endif
        vec3 backgroundPos = screen_view(refracted);
        float waterLength = 0.0;
        if (water) {
            waterLength = isEyeInWater == 1 ? length(viewPos)
                          : (refracted.z < 0.999999 ? length(backgroundPos - viewPos) : 32.0);
        }
        vec3 transmission = water_absorption(clamp(waterLength / 32.0, 0.0, 1.0));
        vec3 transmitted = textureLod(colortex4, refracted.xy, 0.0).rgb * transmission
                          + astra_underwater_color() * (1.0 - transmission);
        // The background has already been composed here. A=1 prevents blending it twice.
        color = mix(transmitted, reflection, fresnel);
        if (!water) color = mix(color, color * clamp(color + vec3(0.5), 0.0, 1.0), 0.08);
        vec4 fog = astra_fog(playerPos, skylight);
        color = mix(color, fog.rgb, fog.a);
        return vec4(max(color, vec3(0.0)), 1.0);
    #else
        color = mix(color, reflection, fresnel);
        color = astra_apply_medium(color, playerPos, skylight);
        alpha = clamp(alpha + fresnel * (1.0 - alpha), 0.0, 1.0);
        return vec4(max(color, vec3(0.0)), alpha);
    #endif
}
#endif