#ifndef ASTRA_GLOBAL_WATER_LIGHT_SHAFTS_GLSL
#define ASTRA_GLOBAL_WATER_LIGHT_SHAFTS_GLSL
// Written for Astra (SC-33). Idea reference: Solas V2.2b
// lib/atmosphere/volumetricLight.glsl and program/shadow.glsl: integrate light-space
// occlusion along the water view ray, modulated by water-surface focusing.
// The bounded quadrature, broad focus field and pixel-exact reconstruction are
// self-authored; Solas' computeVL expressions and temporal noise are not ported.
// Uniforms: depthtex0/1, colortex3, noisetex, cameraPosition, eyeBrightnessSmooth,
// worldSunVector, frameTimeCounter, rainStrength, skyVisibilityDay, blindness.
// March consumer also needs B1 shadow samplers/transforms and astra_direct_light().
#include "/lib/transforms.glsl"
#include "/lib/bayer.glsl"

uniform sampler2D colortex3;
// Solas marches to 128 blocks; Astra's 48 stopped shafting well inside the
// distance the thinned fog now reveals, so distant water had no shafts at all.
// 96 keeps the encoded step at 4 blocks for the default 24 samples.
const float WATER_SHAFT_MAX_DISTANCE = 96.0;

vec3 water_shafts_view(vec2 uv, out float rayLength) {
    ivec2 size = textureSize(depthtex0, 0);
    ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    float depth = texelFetch(depthtex0, pixel, 0).r;
    if (depth < 0.999999) {
        uint flags = uint(round(texelFetch(colortex3, pixel, 0).r * 255.0));
        // A nearer translucent surface can cover the opaque hand marker. Correct
        // the hand projection only when this is still the same opaque depth.
        if ((flags & 128u) != 0u && depth == texelFetch(depthtex1, pixel, 0).r)
            depth = ((depth * 2.0 - 1.0) / MC_HAND_DEPTH) * 0.5 + 0.5;
    }
    vec2 pixelUV = (vec2(pixel) + 0.5) / vec2(size);
    vec3 viewPos = screen_view(vec3(pixelUV, min(depth, 0.999999)));
    rayLength = min(length(viewPos), WATER_SHAFT_MAX_DISTANCE);
    return viewPos;
}

#ifdef ASTRA_SHAFT_MARCH_PASS
// Both the interface paths and this camera path consume the same solar source.
// No second blue tint, independent extinction, angular glow or empirical gain.
vec4 water_shafts_march(vec2 uv) {
    float rayLength;
    vec3 viewPos = water_shafts_view(uv, rayLength);
    float encodedDepth = rayLength / WATER_SHAFT_MAX_DISTANCE;
    vec3 integral = vec3(0.0);
    vec3 rayDir = normalize(view_player(viewPos));
    vec3 rayOrigin = view_camera_relative(vec3(0.0));
    vec3 extinction = water_extinction();
    vec4 state = water_volume_state();
    float surfaceHeight = state.a > 0.5 ? water_unpack_surface_height(state.rg) : -20000.0;
    vec3 albedo = vec3(water_scattering_coefficient()) / max(extinction, vec3(1e-6));
    // Cover the visible segment uniformly: far samples must resolve the same
    // surface-focused columns as near samples, not skip across whole light bands.
    for (int i = 0; i < UNDERWATER_SHAFT_SAMPLES; ++i) {
        float ta = float(i) / float(UNDERWATER_SHAFT_SAMPLES);
        float tb = float(i + 1) / float(UNDERWATER_SHAFT_SAMPLES);
        float begin = rayLength * ta;
        float end = rayLength * tb;
        float distanceAlongRay = 0.5 * (begin + end);
        vec3 source = astra_water_sun_source(rayOrigin + rayDir * distanceAlongRay, rayDir, surfaceHeight);
        vec3 weight = (exp(-extinction * begin) - exp(-extinction * end)) * albedo;
        integral += source * weight;
    }
    integral *= 1.0 - clamp(blindness, 0.0, 1.0);
    return vec4(sqrt(clamp(integral * 0.25, 0.0, 1.0)), encodedDepth);
}

#else
vec3 water_shafts_resolve(sampler2D shaftMap, vec2 uv, float rayLength) {
    ivec2 size = textureSize(shaftMap, 0);
    // Producer and consumer now share the full-resolution pixel and ray endpoint.
    // No neighbour can donate light across a block edge, and no depth rejection
    // can erase the sun on a sloping surface.
    ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    vec3 encoded = texelFetch(shaftMap, pixel, 0).rgb;
    return encoded * encoded * 4.0;
}
#endif
#endif
