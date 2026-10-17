#ifndef ASTRA_SURFACE_EMISSION_GLSL
#define ASTRA_SURFACE_EMISSION_GLSL
#include "/lib/settings.glsl"
#include "/lib/encoding.glsl"

#ifdef ORE_GLOW
// Original Astra texture masks. Block identity gates the operation first;
// colour only separates mineral flecks from that ore's surrounding rock.
// Input is the unlit sRGB texture, so shadows/AO never extinguish emission.
vec3 astra_ore_emission(uint oreType, vec3 texel) {
    if (oreType == 0u) return vec3(0.0);
    float r = texel.r, g = texel.g, b = texel.b;
    float mask = 0.0;
    float strength = 2.2;
    if (oreType == 1u) {
        // Warm iron grains; neutral stone and deepslate do not pass.
        mask = smoothstep(0.07, 0.18, r - b) * smoothstep(0.015, 0.065, r - g)
             * smoothstep(0.25, 0.50, r);
        strength = 1.2;
    } else if (oreType == 2u) {
        mask = smoothstep(0.10, 0.27, min(r, g) - b) * smoothstep(0.18, 0.48, g);
    } else if (oreType == 3u) {
        mask = smoothstep(0.10, 0.30, r - max(g, b)) * smoothstep(0.20, 0.48, r);
    } else if (oreType == 4u) {
        mask = smoothstep(0.06, 0.20, b - max(r, g)) * smoothstep(0.20, 0.48, b);
    } else if (oreType == 5u) {
        mask = smoothstep(0.07, 0.22, min(g, b) - r) * smoothstep(0.28, 0.62, max(g, b));
    } else if (oreType == 6u) {
        mask = smoothstep(0.07, 0.23, g - max(r, b)) * smoothstep(0.23, 0.55, g);
    } else if (oreType == 7u) {
        // Pale quartz against red netherrack; brightness alone is insufficient.
        mask = smoothstep(0.70, 0.86, min(g, b) / max(r, 0.001))
             * smoothstep(0.38, 0.68, min(g, b));
        strength = 1.4;
    } else if (oreType == 8u) {
        // Restrained warm highlights on debris, leaving its dark grooves intact.
        mask = smoothstep(0.025, 0.09, r - b) * smoothstep(0.30, 0.57, r)
             * smoothstep(0.16, 0.37, g);
        strength = 0.8;
    }
    return srgb_decode(max(texel, vec3(0.0))) * (mask * strength * (EMISSIVE_STRENGTH * 0.01));
}
#endif

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
