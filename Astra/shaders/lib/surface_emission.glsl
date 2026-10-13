#ifndef ASTRA_SURFACE_EMISSION_GLSL
#define ASTRA_SURFACE_EMISSION_GLSL
#include "/lib/settings.glsl"

// Material identities come from block.properties, never from the albedo colour.
vec3 astra_end_stone_emission(uint material, vec3 albedo) {
    #if END_STONE_GLOW <= 0
    return vec3(0.0);
    #else
    if (material != 11u) return vec3(0.0);
    float textureLight = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
    // Optional faint pore emission only. Reflection belongs to the material
    // response; a uniform emission floor made every shadowed block glow.
    float pores = smoothstep(0.55, 0.90, textureLight);
    return albedo * (0.025 * pores * (END_STONE_GLOW * 0.01));
    #endif
}

#endif
