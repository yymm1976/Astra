#ifndef ASTRA_ROCK_MATERIAL_GLSL
#define ASTRA_ROCK_MATERIAL_GLSL
// Texture-driven dielectric response, informed by Complementary r5.9's
// terrain material dispatch. Netherrack scales the reference expression; other
// ranges are Astra mappings.
// Input is the original texture colour, before AO and illumination.
float astra_rock_smoothness(uint material, vec3 textureColor) {
    if (material == 11u)
        return mix(0.06, 0.48, smoothstep(0.45, 0.95, textureColor.r));
    if (material == 12u)
        return 0.80 * min(textureColor.r * textureColor.r * 1.5, 1.0);
    if (material == 13u)
        return mix(0.18, 0.58, smoothstep(0.08, 0.48, textureColor.r));
    if (material == 14u)
        return mix(0.08, 0.38, smoothstep(0.12, 0.65, textureColor.g));
    if (material == 15u)
        return mix(0.04, 0.25, smoothstep(0.24, 0.85, textureColor.g));
    return 0.0;
}
#endif
