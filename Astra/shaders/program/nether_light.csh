// Solas 3.7b voxel-source / empty-cell propagation pattern, adapted to Astra's bounded
// same-frame volume (64^3 around the player, eight diffusion steps, no history).
//
// Occupancy encoding written by program/shadow.vsh through imageAtomicMax:
//   bit 8    solid geometry rendered this frame (needed so walls block diffusion)
// The image is cleared every frame (clear=true in the image directive), so an unwritten
// cell reads as 0 and 0 means air. No frame stamp is involved - see the note in
// program/shadow.vsh for why the previous stamp was both unnecessary and parity-broken.
//   bits 0-7 light species: 0 = no emission, 1 = reserved (not written),
//            2..8 = coloured block light (mirrored from block.properties groups),
//            9-11 = fire, soul fire, lava
// Species 0 is also used by non-emitting solids; bit 8 alone blocks diffusion.
#include "/lib/nether_voxel_grid.glsl"
#include "/lib/emitter_colors.glsl"
layout(local_size_x=8,local_size_y=8,local_size_z=8) in;
const ivec3 workGroups=ivec3(8,8,8);
uniform usampler3D astraVoxelSampler;
uniform sampler3D astraLightSamplerA,astraLightSamplerB;
layout(rgba16f) uniform writeonly image3D astraLightA,astraLightB;
#if ASTRA_LIGHT_STEP == 0
// Two words describe the emitting 16^3 tiles of the freshly captured volume.
// Reduce within each 8^3 workgroup, avoiding a new global atomic per source vertex.
layout(r32ui) uniform uimage2D astraNetherSourceTiles;
shared uint astraGroupHasSource;
#else
uniform usampler2D astraNetherSourceSampler;
shared uint astraGroupCanReceive;
bool astra_nether_group_has_source(uvec2 sources) {
    if (all(equal(sources, uvec2(0u)))) return false;
    if (all(equal(sources, uvec2(0xffffffffu)))) return true;
    // A step crosses at most one axial neighbour. This expanded workgroup box
    // contains every possible source path, including ones blocked by walls.
    ivec3 start = ivec3(gl_WorkGroupID) * 8;
    ivec3 low = max(start - ivec3(ASTRA_LIGHT_STEP), ivec3(0)) >> 4;
    ivec3 high = min(start + ivec3(7 + ASTRA_LIGHT_STEP), ivec3(ASTRA_NETHER_VOXEL_SIZE - 1)) >> 4;
    uint xMask = ((1u << uint(high.x - low.x + 1)) - 1u) << uint(low.x);
    for (int z = low.z; z <= high.z; ++z) {
        uint word = z < 2 ? sources.x : sources.y;
        for (int y = low.y; y <= high.y; ++y) {
            uint rowMask = xMask << uint((4 * y + 16 * z) & 31);
            if ((word & rowMask) != 0u) return true;
        }
    }
    return false;
}
#endif
void astra_nether_store_light(ivec3 p, vec3 color) {
    #if ASTRA_LIGHT_STEP % 2 == 0
    imageStore(astraLightA,p,vec4(color,1.0));
    #else
    imageStore(astraLightB,p,vec4(color,1.0));
    #endif
}
// Frame-only source flicker, shared by all cells and all nine dispatches.
uniform vec2 astraNetherEmissionPulse;
vec3 emission(uint id) {
    // Most cells are air or non-emitting solids; neither has a source palette.
    if(id<=1u) return vec3(0.0);
    vec3 color=astra_emitter_color(id);
    if(id==3u || id==9u) color*=astraNetherEmissionPulse.x;
    if(id==7u || id==10u) color*=astraNetherEmissionPulse.y;
    return color;
}
void main() {
    ivec3 p=ivec3(gl_GlobalInvocationID);
    #if ASTRA_LIGHT_STEP == 0
    if (gl_LocalInvocationIndex == 0u) astraGroupHasSource = 0u;
    barrier();
    #else
    if (gl_LocalInvocationIndex == 0u) {
        uvec2 sources = uvec2(texelFetch(astraNetherSourceSampler, ivec2(0,0), 0).r,
                             texelFetch(astraNetherSourceSampler, ivec2(1,0), 0).r);
        astraGroupCanReceive = astra_nether_group_has_source(sources) ? 1u : 0u;
    }
    // Every invocation participates before any group-wide early return.
    barrier();
    if (astraGroupCanReceive == 0u) {
        // Write zeros rather than leave last frame's light in the ping-pong field.
        astra_nether_store_light(p, vec3(0.0));
        return;
    }
    #endif
    uint raw=texelFetch(astraVoxelSampler,p,0).r;
    uint id=raw & 255u;
    bool solid=(raw & 256u) != 0u;
    // One multiplier for every species cannot reproduce the reference's per-kind
    // radiance (lib/vx/blocklightColor.glsl: torch/soul/candle *3.5, shroomlight *4.5,
    // lava/portal *5.0, glowstone/froglight *5.5, magma/amethyst *2.0). At *1.5 every
    // family was compared in a historical probe (now retired; not current evidence).
    // 3.5 matched the reference's torch family, but the user ruled the Nether glow
    // down ("lava must not glow red", overall brightness slightly lower), so 2.0
    // pre-tunes toward that instead of toward the reference.
    vec3 color=emission(id)*2.0;
    #if ASTRA_LIGHT_STEP == 0
    if (id >= 2u && id <= 11u) atomicOr(astraGroupHasSource, 1u);
    barrier();
    if (gl_LocalInvocationIndex == 0u && astraGroupHasSource != 0u) {
        ivec3 tile = ivec3(gl_WorkGroupID) >> 1;
        uint index = uint(tile.x + 4 * tile.y + 16 * tile.z);
        imageAtomicOr(astraNetherSourceTiles, ivec2(int(index >> 5), 0), 1u << (index & 31u));
    }
    #endif
    #if ASTRA_LIGHT_STEP > 0
    // Fetch only for air receivers. The archive's 09-25 GPU timings favoured
    // this direct path over loading a halo tile for every workgroup.
    // Keep the nine dispatches, source ping-pong and six-neighbour max field.
    if(!solid) {
        const ivec3 dirs[6]=ivec3[6](ivec3(1,0,0),ivec3(-1,0,0),ivec3(0,1,0),ivec3(0,-1,0),ivec3(0,0,1),ivec3(0,0,-1));
        vec3 incoming=vec3(0.0);
        for(int i=0;i<6;i++) {
            ivec3 q=p+dirs[i];
            if(!astra_nether_voxel_in_bounds(q)) continue;
            #if ASTRA_LIGHT_STEP % 2 == 1
            vec3 neighbour=texelFetch(astraLightSamplerA,q,0).rgb;
            #else
            vec3 neighbour=texelFetch(astraLightSamplerB,q,0).rgb;
            #endif
            incoming=max(incoming,neighbour);
        }
        // The light field is nonnegative. The same positive attenuation
        // preserves max ordering, so apply it once after the six neighbours.
        color=max(color,incoming*0.72);
    }
    #endif
    astra_nether_store_light(p, color);
}
