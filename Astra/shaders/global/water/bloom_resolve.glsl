// Read the thresholded, linear HDR pyramid captured after water composition.
// There is no scene-colour replacement or contrast-space average here.
// Shared bloom implementation/provenance: global/post/bloom.glsl.
void getBloom(inout vec3 color, vec2 coord) {
    color += bloom_composite(colortex7, coord, BLOOM_STRENGTH * 0.0025);
}
