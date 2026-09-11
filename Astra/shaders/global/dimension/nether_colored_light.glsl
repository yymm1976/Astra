#ifndef ASTRA_NETHER_COLORED_LIGHT
#define ASTRA_NETHER_COLORED_LIGHT
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
    vec3 p=playerPos+fract(cameraPosition)+vec3(32.0)+normal*0.65;
    float edge=min(min(p.x,p.y),min(p.z,min(64.0-p.x,min(64.0-p.y,64.0-p.z))));
    if(edge <= 1.0) return vec3(0.0);
    vec3 g=p-0.5;
    ivec3 cell=ivec3(floor(g)); vec3 f=fract(g); vec3 color=vec3(0.0);
    for(int z=0;z<2;z++) for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        ivec3 q=cell+ivec3(x,y,z);
        if(any(lessThan(q,ivec3(0))) || any(greaterThanEqual(q,ivec3(64)))) continue;
        vec3 w=mix(1.0-f,f,vec3(x,y,z));
        color+=texelFetch(astraLightSamplerA,q,0).rgb*w.x*w.y*w.z;
    }
    return color*astra_nether_alignment(edge);
}
#endif
