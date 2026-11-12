#ifndef ASTRA_AO_MATERIAL_GLSL
#define ASTRA_AO_MATERIAL_GLSL
#include "/global/water/medium_state.glsl"
bool astra_ao_receiver(uint material) {
    // First release: opaque terrain, excluding foliage, emitters, ice and glass.
    return (isEyeInWater == 0 || water_is_thin_sheet())
        && (material == 0u || material >= 11u);
}
#endif
