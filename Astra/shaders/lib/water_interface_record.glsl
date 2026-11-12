#ifndef ASTRA_WATER_INTERFACE_RECORD_GLSL
#define ASTRA_WATER_INTERFACE_RECORD_GLSL
// Existing interface target: RG packed world Y, B skylight, A validity.
// R=1 reserves a vertical sheet; G stores its OWN d/(1+d) distance. Horizontal
// height packing never uses high byte 255. Side records carry no horizontal plane.
uniform sampler2D colortex5;
bool water_interface_is_side(vec4 record) {
    return record.a > 0.5 && record.r >= 0.999;
}
float water_interface_side_distance(vec4 record) {
    // A saturated far side remains far, rather than aliasing a nearby sheet.
    return record.g >= 1.0 ? 1e20 : record.g / max(1.0 - record.g, 1e-5);
}
bool water_interface_is_horizontal(vec4 record) {
    return record.a > 0.5 && !water_interface_is_side(record);
}
vec4 water_interface_at(vec2 uv) {
    ivec2 size = textureSize(colortex5, 0);
    ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    return texelFetch(colortex5, pixel, 0);
}
#endif
