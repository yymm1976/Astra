#ifndef ASTRA_NETHER_COLORED_LIGHT
#define ASTRA_NETHER_COLORED_LIGHT
#include "/lib/nether_voxel_grid.glsl"
// Solas V3.7b voxel light architecture adapted to a bounded, same-frame volume.
// Geometry captures emitting and solid cells; diffusion crosses empty cells only.
// Occupancy is cleared every frame; step 0 rebuilds light before propagation.
// There is no temporal light history or frame stamp.
uniform sampler3D astraLightSamplerA;
float astra_nether_alignment(float raw) {
    float w = clamp((raw - 1.0) / 4.0, 0.0, 1.0);
    return w * w * (3.0 - 2.0 * w);
}
vec3 astra_nether_colored_light(vec3 playerPos, vec3 normal) {
    vec3 p=astra_nether_voxel_position(playerPos,fract(cameraPosition))+normal*0.65;
    float edge=astra_nether_voxel_edge(p);
    if(edge <= 1.0) return vec3(0.0);
    // Iris custom RGBA16F images use GL_LINEAR (integer occupancy uses NEAREST).
    // astra_nether_voxel_normalized (p/size) addresses the same eight texels as
    // floor(p-0.5), with hardware trilinear weights. The edge guard keeps the
    // footprint in bounds. Explicit LOD is needed in divergent lighting/volume
    // branches. The compute propagation still uses texelFetch and therefore keeps
    // point access.
    vec3 color=textureLod(astraLightSamplerA,astra_nether_voxel_normalized(p),0.0).rgb;
    return color*astra_nether_alignment(edge);
}
#endif
