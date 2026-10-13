#ifndef ASTRA_NETHER_REFLECTION_METADATA_GLSL
#define ASTRA_NETHER_REFLECTION_METADATA_GLSL
// Astra-owned current receiver record: RG retain colortex3's two normal bytes,
// B is 512 + light/hand flags, A is reflection coverage. The new marker rejects
// empty texels and old dense-layout history without an extra target.
vec4 astra_nether_receiver_record(vec2 normalCode, uint flags, float coverage) {
    return vec4(normalCode, 512.0 + float(flags), coverage);
}
bool astra_nether_receiver_valid(vec4 data) {
    return !any(isnan(data)) && !any(isinf(data))
        && all(greaterThanEqual(data.rg, vec2(0.0)))
        && all(lessThanEqual(data.rg, vec2(1.0)))
        && data.b >= 512.0 && data.b <= 639.0 && data.b == round(data.b)
        && data.a >= 0.0 && data.a <= 1.0;
}
uint astra_nether_receiver_flags(vec4 data) {
    return uint(data.b) - 512u;
}
vec3 astra_nether_receiver_normal(vec4 data) {
    // FP16 preserves every source byte: its largest rounding error in [0,1]
    // is below 0.00025, or 0.064 byte units. Recover the original RGBA8 code.
    vec2 normalCode = round(data.rg * 255.0) / 255.0;
    return decode_unit_vector(normalCode * 2.0 - 1.0);
}
#endif
