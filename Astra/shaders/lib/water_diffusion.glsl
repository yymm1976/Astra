#ifndef ASTRA_WATER_DIFFUSION_GLSL
#define ASTRA_WATER_DIFFUSION_GLSL
// Written for Astra: a small, deterministic scene diffusion before water fog
// and shafts. Uses existing water-interface and hand records; no history or
// new render target. light_shafts.glsl supplies the colortex3 declaration.
#include "/lib/water_interface_record.glsl"

float water_diffusion_view_depth(float depth) {
    float ndc = depth * 2.0 - 1.0;
    return abs((gbufferProjectionInverse[2].z * ndc + gbufferProjectionInverse[3].z)
             / (gbufferProjectionInverse[2].w * ndc + gbufferProjectionInverse[3].w));
}

vec3 water_diffuse_scene(sampler2D scene, vec2 colourUV, vec2 depthUV,
                        vec3 centre, float rayLength) {
    #if UNDERWATER_FOG_DENSITY <= 0
        return centre;
    #else
        if (water_is_thin_sheet()) return centre;
        float distanceBlend = smoothstep(3.0, 28.0, rayLength);
        float strength = distanceBlend * 0.28
                       * clamp(float(UNDERWATER_FOG_DENSITY) / 40.0, 0.0, 1.5);
        if (strength <= 0.0) return centre;

        ivec2 size = textureSize(depthtex0, 0);
        ivec2 pixel = clamp(ivec2(depthUV * vec2(size)), ivec2(0), size - 1);
        // The head-level window and its total-reflection border retain their
        // wave detail. Diffusion affects the submerged scenery, not the lens.
        if (water_interface_is_horizontal(texelFetch(colortex5, pixel, 0))) return centre;
        uint flags = uint(round(texelFetch(colortex3, pixel, 0).r * 255.0));
        if ((flags & 128u) != 0u) return centre;

        float centreDepth = water_diffusion_view_depth(texelFetch(depthtex0, pixel, 0).r);
        float depthTolerance = 0.5 + centreDepth * 0.025;
        // Radius scales with output height so resolution does not change the
        // apparent softness. The nearby scene remains clear.
        vec2 radius = vec2(mix(0.6, 1.4, distanceBlend) * viewHeight / 1080.0)
                    / vec2(size);
        const vec2 directions[4] = vec2[4](vec2(1.0, 0.0), vec2(-1.0, 0.0),
                                         vec2(0.0, 1.0), vec2(0.0, -1.0));
        vec2 edge = 0.5 / vec2(size);
        vec3 sum = centre;
        float weights = 1.0;
        for (int i = 0; i < 4; ++i) {
            vec2 offset = directions[i] * radius;
            vec2 tapDepthUV = clamp(depthUV + offset, edge, 1.0 - edge);
            ivec2 tapPixel = clamp(ivec2(tapDepthUV * vec2(size)), ivec2(0), size - 1);
            float tapDepth = water_diffusion_view_depth(texelFetch(depthtex0, tapPixel, 0).r);
            float difference = abs(tapDepth - centreDepth) / depthTolerance;
            float weight = 1.0 / (1.0 + difference * difference);
            // TAA colour is unjittered while depth remains rasterized. Carry
            // the same offset on each grid, rather than shifting scene colour.
            vec2 tapColourUV = clamp(colourUV + offset, edge, 1.0 - edge);
            sum += max(textureLod(scene, tapColourUV, 0.0).rgb, vec3(0.0)) * weight;
            weights += weight;
        }
        return mix(centre, sum / weights, strength);
    #endif
}
#endif
