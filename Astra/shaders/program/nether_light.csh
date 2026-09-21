// Solas 3.7b voxel-source / empty-cell propagation pattern, adapted to Astra's bounded
// same-frame volume (64^3 around the player, eight diffusion steps, no history).
//
// Occupancy encoding written by program/shadow.vsh through imageAtomicMax:
//   bit 8    solid geometry rendered this frame (needed so walls block diffusion)
// The image is cleared every frame (clear=true in the image directive), so an unwritten
// cell reads as 0 and 0 means air. No frame stamp is involved - see the note in
// program/shadow.vsh for why the previous stamp was both unnecessary and parity-broken.
//   bits 0-7 light species: 0 = captured air (diffusion passes through), 1 = solid/unlit,
//            2..8 = coloured block light (mirrored from block.properties groups),
//            9-11 = fire, soul fire, lava
layout(local_size_x=8,local_size_y=8,local_size_z=8) in;
const ivec3 workGroups=ivec3(8,8,8);
uniform usampler3D astraVoxelSampler;
uniform sampler3D astraLightSamplerA,astraLightSamplerB;
layout(rgba16f) uniform writeonly image3D astraLightA,astraLightB;
uniform float frameTimeCounter;
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
    bool solid=(raw & 256u) != 0u;
    // One multiplier for every species cannot reproduce the reference's per-kind
    // radiance (lib/vx/blocklightColor.glsl: torch/soul/candle *3.5, shroomlight *4.5,
    // lava/portal *5.0, glowstone/froglight *5.5, magma/amethyst *2.0). At *1.5 every
    // family sat at 26-43% of the reference (qa/tools/nether_light_probe.py Part 1).
    // 3.5 matched the reference's torch family, but the user ruled the Nether glow
    // down ("lava must not glow red", overall brightness slightly lower), so 2.0
    // pre-tunes toward that instead of toward the reference.
    vec3 color=emission(id)*2.0;
    #if ASTRA_LIGHT_STEP > 0
    {
        // Only non-solid cells diffuse. raw == 0 is cleared air and is the common case:
        // ordinary air has no vertices, so nothing ever writes it.
        bool empty = !solid;
        if(empty) {
            const ivec3 dirs[6]=ivec3[6](ivec3(1,0,0),ivec3(-1,0,0),ivec3(0,1,0),ivec3(0,-1,0),ivec3(0,0,1),ivec3(0,0,-1));
            for(int i=0;i<6;i++) {
                ivec3 q=p+dirs[i];
                if(any(lessThan(q,ivec3(0))) || any(greaterThanEqual(q,ivec3(64)))) continue;
                // Solas shadowcomp reads neighbouring radiance directly. Non-emissive
                // solids are exactly zero in every pass (including step 0), so reading
                // their occupancy again cannot change max(color, adjacent * 0.72).
                // This removes six integer-volume reads per propagating cell/pass,
                // while opaque emitters still hand their own light to adjacent air.
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
