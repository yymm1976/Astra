#ifndef ASTRA_WATER_MEDIUM_STATE_GLSL
#define ASTRA_WATER_MEDIUM_STATE_GLSL
// Water volume identity comes from the visible interface, independently of the
// first sun-facing caster. A tree covering water must not turn water into air.
// RG: world height at 1/16 block over [-1024,3072); B: sky access; A: validity.
uniform sampler2D colortex6;
vec2 water_pack_surface_height(float worldY) {
    float q = clamp(floor((worldY + 1024.0) * 16.0 + 0.5), 0.0, 65535.0);
    return vec2(floor(q / 256.0), mod(q, 256.0)) / 255.0;
}
float water_unpack_surface_height(vec2 code) {
    vec2 q = floor(code * 255.0 + 0.5);
    return (q.x * 256.0 + q.y) / 16.0 - 1024.0;
}
vec4 water_volume_state() {
    return texelFetch(colortex6, ivec2(0), 0);
}
#endif
