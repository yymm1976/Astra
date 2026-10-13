// ITT-style underwater scene softening uses the existing linear HDR pyramid.
// The shared capture stencil stays unchanged; only this producer bypasses the
// highlight threshold. Air and other dimensions keep their light-only capture.
#define ASTRA_WATER_SCENE_BLOOM
#include "/global/post/bloom.glsl"

vec3 computeBloom(sampler2D scene, vec2 texCoord) {
    return bloom_capture(scene, texCoord);
}
