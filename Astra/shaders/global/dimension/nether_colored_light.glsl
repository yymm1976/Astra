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

float astra_nether_light_facing(vec3 playerPos, vec3 normal, vec3 field) {
    #ifdef DIRECTIONAL_LOCAL_LIGHTING
    // Estimate the direction toward increasing radiance in the existing volume.
    // This is a diffuse-field approximation, not visibility or a point-source map.
    // Keep the scalar sampler above unchanged for fog and diagnostic consumers.
    float signal=max(field.r,max(field.g,field.b));
    if (signal <= 0.002) return 1.0;
    vec3 p=astra_nether_voxel_position(playerPos,fract(cameraPosition))+normal*0.65;
    float edge=astra_nether_voxel_edge(p);
    if (edge <= 2.0) return 1.0;
    const vec3 luma=vec3(0.2126,0.7152,0.0722);
    vec3 uv=astra_nether_voxel_normalized(p);
    float stepSize=ASTRA_NETHER_VOXEL_INV_SIZE;
    vec3 dx=vec3(stepSize,0.0,0.0);
    vec3 dy=vec3(0.0,stepSize,0.0);
    vec3 dz=vec3(0.0,0.0,stepSize);
    // Reuse the centre already fetched by the ordinary field lookup.
    float center=dot(field,luma)/astra_nether_alignment(edge);
    vec3 positive=vec3(dot(textureLod(astraLightSamplerA,uv+dx,0.0).rgb,luma),
                       dot(textureLod(astraLightSamplerA,uv+dy,0.0).rgb,luma),
                       dot(textureLod(astraLightSamplerA,uv+dz,0.0).rgb,luma));
    vec3 negative=vec3(dot(textureLod(astraLightSamplerA,uv-dx,0.0).rgb,luma),
                       dot(textureLod(astraLightSamplerA,uv-dy,0.0).rgb,luma),
                       dot(textureLod(astraLightSamplerA,uv-dz,0.0).rgb,luma));
    // A zero cell may be a wall rather than a direction away from the source.
    // Use the available one-sided difference when that neighbour is empty.
    for (int axis=0;axis<3;++axis) {
        if (positive[axis] <= 0.00001) positive[axis]=center;
        if (negative[axis] <= 0.00001) negative[axis]=center;
    }
    vec3 gradient=positive-negative;
    float g2=dot(gradient,gradient);
    if (g2 > 0.00000001) {
        float facing=dot(normal,gradient*inversesqrt(g2));
        float confidence=smoothstep(0.02,0.20,sqrt(g2)/max(center,0.0001));
        confidence*=smoothstep(2.0,5.0,edge)*smoothstep(0.002,0.04,signal);
        // Bounded +/-20% modulation, faded at the field boundary. Missing volume
        // coverage retains the ordinary lightmap support in nether_lighting().
        return 1.0+0.20*facing*confidence;
    }
    #endif
    return 1.0;
}
#endif
