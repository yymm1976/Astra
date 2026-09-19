#ifndef ASTRA_LIB_ENCODING_GLSL
#define ASTRA_LIB_ENCODING_GLSL

// From Mellow v3.4 (MIT) by TheCMK - lib/util.glsl (encodeUnitVector/decodeUnitVector,
// get_luminance) + lib/transformations.glsl (to_linear)
// Renamed to snake_case per design.md 3.2; exact IEC sRGB encode/decode and the uint
// octahedral quantizers are Astra additions composed around the Mellow cores
// (see THIRD-PARTY.md). License: MIT - see THIRD-PARTY.md.
// Uniforms: none

// Fast polynomial approximation of sRGB -> linear (Mellow)
#define to_linear(sRGB) ( (sRGB) * ( (sRGB) * ( (sRGB) * 0.305306011 + 0.682171111 ) + 0.012522878 ) )

// Exact IEC 61966-2-1 sRGB encode/decode
vec3 srgb_encode(vec3 c) {
    return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 srgb_decode(vec3 c) {
    // Clamped inside so a negative input cannot reach pow() - callers no longer have
    // to remember the guard themselves (consolidated review E8 / Qoder F-39).
    return mix(c / 12.92, pow(max((c + 0.055) / 1.055, vec3(0.0)), vec3(2.4)), step(vec3(0.04045), c));
}

float get_luminance(vec3 color) {
    return 0.299 * color.r + 0.587 * color.g + 0.114 * color.b;
}

// Octahedral unit vector encoding (2D octahedral map, [-1, 1] range)
vec2 encode_unit_vector(vec3 vector) {
    // Scale down to octahedron, project onto XY plane
    vector.xy /= abs(vector.x) + abs(vector.y) + abs(vector.z);
    // Reflect -Z hemisphere folds over the diagonals
    return vector.z <= 0.0 ? (1.0 - abs(vector.yx)) * vec2(vector.x >= 0.0 ? 1.0 : -1.0, vector.y >= 0.0 ? 1.0 : -1.0) : vector.xy;
}

vec3 decode_unit_vector(vec2 encoded) {
    // Extract Z component
    vec3 vector = vec3(encoded, 1.0 - abs(encoded.x) - abs(encoded.y));
    // Reflect -Z hemisphere folds over the diagonals
    float t = max(-vector.z, 0.0);
    vector.xy += vec2(vector.x >= 0.0 ? -t : t, vector.y >= 0.0 ? -t : t);
    // Normalize and return
    return normalize(vector);
}

// --- fixed-point quantization for per-face packing (design.md 5: flat uint face data) ---
// E1 composes these into the final flat-uint layout (octahedral bits + material ID bits).

// Two-axis octahedral quantization into a uint, 'bits' per axis
uint pack_octahedral(vec3 normal, const int bits) {
    vec2 oct = encode_unit_vector(normal) * 0.5 + 0.5;   // [0, 1]
    float q = float((1 << bits) - 1);
    uvec2 qv = uvec2(floor(oct * q + 0.5));
    return (qv.x << bits) | qv.y;
}

vec3 unpack_octahedral(uint data, const int bits) {
    uint mask = uint((1 << bits) - 1);
    float q = float((1 << bits) - 1);
    vec2 oct = vec2((data >> bits) & mask, data & mask) / q * 2.0 - 1.0;
    return decode_unit_vector(oct);
}

// Generic 2x16-bit pack helpers
uint pack_u16(uvec2 v) {
    return ((v.x & 0xFFFFu) << 16) | (v.y & 0xFFFFu);
}

uvec2 unpack_u16(uint v) {
    return uvec2(v >> 16, v & 0xFFFFu);
}

#endif
