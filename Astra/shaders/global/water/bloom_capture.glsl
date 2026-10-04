// Astra underwater adapter to the existing HDR bloom prefilter/downsample.
// Replaces the Solas whole-scene pyramid: its unthresholded, LDR input spreads
// ordinary water fog across silhouettes. Borrowing is in global/post/bloom.glsl
// (Refrax source); see THIRD-PARTY.md for current provenance.
#include "/global/post/bloom.glsl"

vec3 computeBloom(sampler2D scene, vec2 texCoord) {
    return bloom_capture(scene, texCoord);
}
