// Solas 3.7b voxel-source / empty-cell propagation pattern, adapted to Astra's bounded
// same-frame volume (64^3 around the player, eight diffusion steps, no history).
//
// Occupancy encoding written by program/shadow.vsh through imageAtomicMax:
//   bit 8    solid geometry rendered this frame (needed so walls block diffusion)
//   bit 16   frame stamp; flips every frame, which retires cells that were not
//            rendered this frame (unloaded chunks, unloaded terrain)
//   bits 0-7 light species: 0 = empty, 1 = solid/unlit, 2..8 = coloured block light
//            (2-8 mirrored from block.properties groups), 9-11 = fire, soul fire, lava
layout(local_size_x=8,local_size_y=8,local_size_z=8) in;
const ivec3 workGroups=ivec3(8,8,8);
uniform usampler3D astraVoxelSampler;
uniform sampler3D astraLightSamplerA,astraLightSamplerB;
layout(rgba16f) uniform writeonly image3D astraLightA,astraLightB;
uniform float frameTimeCounter;
uniform int frameCounter;
uint astra_frame_stamp() {
    return (uint(frameCounter) & 1u) << 16;
}
vec3 emission(uint id) {
    if(id==2u) return vec3(1.0,0.04,0.01);
    if(id==3u || id==9u) return vec3(1.0,0.30,0.045)*(0.96+0.04*sin(frameTimeCounter*2.1));
    if(id==4u) return vec3(1.0,0.66,0.22);
    if(id==5u) return vec3(0.32,1.0,0.43);
    if(id==6u) return vec3(0.3,0.85,1.0);
    if(id==7u || id==10u) return vec3(0.055,0.62,1.0)*(0.97+0.03*sin(frameTimeCounter*1.7));
    if(id==8u) return vec3(0.64,0.20,1.0);
    if(id==11u) return vec3(1.0,0.18,0.025);
    return vec3(0.0);
}
void main() {
    ivec3 p=ivec3(gl_GlobalInvocationID);
    uint raw=texelFetch(astraVoxelSampler,p,0).r;
    uint id=raw & 255u;
    bool fresh=(raw & 0x30000u) == astra_frame_stamp();
    bool solid=(raw & 256u) != 0u;
    // Cells that were not written this frame contribute nothing at all.
    vec3 color=fresh ? emission(id)*1.5 : vec3(0.0);
    #if ASTRA_LIGHT_STEP > 0
    {
        // Only empty cells diffuse; solids keep the light field from crossing them,
        // and stale neighbours (unloaded chunks) are skipped so light cannot leak
        // across regions that were never captured.
        bool empty = (raw == 0u);
        if(empty) {
            const ivec3 dirs[6]=ivec3[6](ivec3(1,0,0),ivec3(-1,0,0),ivec3(0,1,0),ivec3(0,-1,0),ivec3(0,0,1),ivec3(0,0,-1));
            for(int i=0;i<6;i++) {
                ivec3 q=p+dirs[i];
                if(any(lessThan(q,ivec3(0))) || any(greaterThanEqual(q,ivec3(64)))) continue;
                uint nraw=texelFetch(astraVoxelSampler,q,0).r;
                if((nraw & 0x30000u) != astra_frame_stamp()) continue;
                if((nraw & 256u) != 0u) continue;
                #if ASTRA_LIGHT_STEP % 2 == 1
                vec3 adjacent=texelFetch(astraLightSamplerA,q,0).rgb;
                #else
                vec3 adjacent=texelFetch(astraLightSamplerB,q,0).rgb;
                #endif
                color=max(color,adjacent*0.72);
            }
        }
    }
    #endif
    #if ASTRA_LIGHT_STEP % 2 == 0
    imageStore(astraLightA,p,vec4(color,1.0));
    #else
    imageStore(astraLightB,p,vec4(color,1.0));
    #endif
}
