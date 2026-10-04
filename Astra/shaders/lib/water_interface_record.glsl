#ifndef ASTRA_WATER_INTERFACE_RECORD_GLSL
#define ASTRA_WATER_INTERFACE_RECORD_GLSL
// Existing interface target: RG packed world Y, B skylight, A validity.
// Reserve RG=(1,1) for a vertical sheet, outside Minecraft's surface-height
// range. Side records carry no horizontal plane and must never anchor a volume.
uniform sampler2D colortex5;
bool water_interface_is_side(vec4 record) {
    return record.a > 0.5 && all(greaterThanEqual(record.rg, vec2(0.999)));
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
