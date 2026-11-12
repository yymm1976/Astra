#ifndef ASTRA_WATER_MEDIUM_STATE_GLSL
#define ASTRA_WATER_MEDIUM_STATE_GLSL
// Water volume identity comes from the visible interface, independently of the
// first sun-facing caster. A tree covering water must not turn water into air.
// RG: world height over [-1024,3072), using high bytes 0..254; B: sky access.
// High byte 255 belongs to side-interface distance, never a horizontal height.
// Texel 0: A=1 horizontal body; A=0.25 nearby vertical sheet; A=0 unknown/air.
// Texels 1/2 belong only to water_state's continuity metadata; optical consumers
// point-fetch texel 0 so widening the state target does not change their footprint.
uniform sampler2D colortex6;
#ifdef ASTRA_WATER_STATE_FRAME_WRITE
flat out int waterMaterialThinSheet;
#elif defined ASTRA_WATER_STATE_FRAME_READ
flat in int waterMaterialThinSheet;
#endif
vec2 water_pack_surface_height(float worldY) {
    // Reserving one high byte changes the height step from 1/16 to 1/15.9375
    // block, while retaining the full world-height range and both existing targets.
    float q = clamp(floor((worldY + 1024.0) * 15.9375 + 0.5), 0.0, 65279.0);
    return vec2(floor(q / 256.0), mod(q, 256.0)) / 255.0;
}
float water_unpack_surface_height(vec2 code) {
    vec2 q = floor(code * 255.0 + 0.5);
    return (q.x * 256.0 + q.y) / 15.9375 - 1024.0;
}
vec4 water_volume_state() {
    return texelFetch(colortex6, ivec2(0), 0);
}
bool water_is_thin_sheet() {
    #if defined DIMENSION_NETHER || defined DIMENSION_END
    return false;
    #elif defined ASTRA_WATER_STATE_FRAME_READ
    return waterMaterialThinSheet != 0;
    #else
    if (isEyeInWater != 1) return false;
    float kind = water_volume_state().a;
    return kind > 0.125 && kind < 0.375;
    #endif
}
#endif
