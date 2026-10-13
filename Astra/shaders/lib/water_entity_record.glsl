#ifndef ASTRA_WATER_ENTITY_RECORD_GLSL
#define ASTRA_WATER_ENTITY_RECORD_GLSL
// Main-world late opaque receivers, stored in RG32F (8 bytes, like RGBA16F).
// RGB and view Z retain half precision. Alpha is only a fragment coverage bit:
// zero outputs preserve earlier bodies under ONE / ONE_MINUS_SRC_ALPHA blend.
// Bias the packed bit pattern into normal finite floats, so blending by 0 or 1
// preserves its payload without denormal flushing or NaN canonicalisation.
const uint WATER_ENTITY_PACK_BIAS = 0x00800000u;
vec4 water_entity_record(vec3 color, float viewDepth) {
    color = clamp(color,vec3(0.0),vec3(65504.0));
    viewDepth = clamp(viewDepth,0.0,65504.0);
    uvec2 payload = uvec2(packHalf2x16(color.rg),
                          packHalf2x16(vec2(color.b,viewDepth)));
    return vec4(uintBitsToFloat(payload+uvec2(WATER_ENTITY_PACK_BIAS)),0.0,1.0);
}
float water_entity_depth(float packedDepth) {
    if (packedDepth == 0.0) return 0.0;
    return unpackHalf2x16(floatBitsToUint(packedDepth)-WATER_ENTITY_PACK_BIAS).y;
}
vec4 water_entity_decode(vec2 packedRecord) {
    if (packedRecord.y == 0.0) return vec4(0.0);
    uvec2 payload = floatBitsToUint(packedRecord)-uvec2(WATER_ENTITY_PACK_BIAS);
    return vec4(unpackHalf2x16(payload.x),unpackHalf2x16(payload.y));
}
#endif
