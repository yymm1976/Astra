#ifndef ASTRA_NETHER_LIGHT_DEBUG_GLSL
#define ASTRA_NETHER_LIGHT_DEBUG_GLSL
#include "/lib/nether_voxel_grid.glsl"
#include "/lib/emitter_colors.glsl"
#if defined NETHER_VOXEL_LIGHT && defined SHADOWS && BLOCKLIGHT_STRENGTH > 0
#include "/global/dimension/nether_colored_light.glsl"
uniform usampler3D astraVoxelSampler;
uniform sampler2D colortex3;
#endif
vec3 astra_nether_debug_color(vec3 radiance) {
    // A common, hue-preserving display scale, independent of exposure/fog/grade.
    float peak=max(radiance.r,max(radiance.g,radiance.b));
    return srgb_encode(max(radiance,vec3(0.0))/(1.0+peak));
}
vec3 astra_nether_light_debug(vec2 uv) {
    #if defined NETHER_VOXEL_LIGHT && defined SHADOWS && BLOCKLIGHT_STRENGTH > 0
    #if DEBUG_NETHER_LIGHT == 1
    vec2 rasterUV=clamp(uv+astra_jitter_uv(),0.5/vec2(viewWidth,viewHeight),
        1.0-0.5/vec2(viewWidth,viewHeight));
    ivec2 pixel=ivec2(rasterUV*vec2(textureSize(depthtex0,0)));
    float depth=texelFetch(depthtex0,pixel,0).r;
    float opaqueDepth=texelFetch(depthtex1,pixel,0).r;
    if (depth >= 0.999999 || depth != opaqueDepth) return vec3(0.0);
    vec4 material=texelFetch(colortex3,pixel,0);
    uint flags=uint(round(material.r*255.0));
    if ((flags&128u)!=0u) return vec3(0.0);
    vec3 normal=decode_unit_vector(material.gb*2.0-1.0);
    vec2 pixelUV=(vec2(pixel)+0.5)/vec2(textureSize(depthtex0,0));
    vec3 playerPos=view_camera_relative(screen_view(vec3(pixelUV,depth)));
    return astra_nether_debug_color(astra_nether_colored_light(playerPos,normal));
    #else
    // Top-down XZ square, north (-Z) at the top; fixed cells, camera-height Y.
    // Wider screens receive side margins rather than a stretched voxel grid.
    vec2 sliceUV=(uv-0.5)*vec2(viewWidth/viewHeight,1.0)+0.5;
    if (any(lessThan(sliceUV,vec2(0.0))) || any(greaterThanEqual(sliceUV,vec2(1.0))))
        return vec3(0.015);
    ivec2 cell=ivec2(floor(sliceUV*float(ASTRA_NETHER_VOXEL_SIZE)));
    int y=int(floor(ASTRA_NETHER_VOXEL_HALF_EXTENT+fract(cameraPosition.y)));
    ivec3 p=ivec3(cell.x,y,ASTRA_NETHER_VOXEL_SIZE-1-cell.y);
    #if DEBUG_NETHER_LIGHT == 2
    return astra_nether_debug_color(texelFetch(astraLightSamplerA,p,0).rgb);
    #else
    uint occupancy=texelFetch(astraVoxelSampler,p,0).r;
    uint species=occupancy&255u;
    if (species>1u) return astra_nether_debug_color(astra_emitter_color(species)*2.0);
    return (occupancy&256u)!=0u ? vec3(0.35) : vec3(0.0);
    #endif
    #endif
    #else
    // The menu explains the missing prerequisites; no unbound volume is read.
    return vec3(0.0);
    #endif
}
#endif
