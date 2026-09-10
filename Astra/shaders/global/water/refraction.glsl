#ifndef ASTRA_GLOBAL_WATER_REFRACTION_GLSL
#define ASTRA_GLOBAL_WATER_REFRACTION_GLSL
// Adapted from Steadfast 0.8.0 environment/water/refraction.glsl, coderbot.
// GPL-3.0-or-later with Section 7 terms; see Astra/LICENSE and THIRD-PARTY.md.
vec2 water_depth_range(sampler2D depthBuffer, vec2 uv) {
    vec4 depths = textureGather(depthBuffer, clamp(uv, vec2(0.0), vec2(1.0)));
    return vec2(min(min(depths.x, depths.y), min(depths.z, depths.w)),
                max(max(depths.x, depths.y), max(depths.z, depths.w)));
}
vec2 water_refracted_uv(sampler2D depthBuffer, vec3 viewPos, vec3 normalDelta) {
    vec2 uv = view_screen(viewPos).xy;
    float backgroundDepth = water_depth_range(depthBuffer, uv).y;
    float backgroundZ = screen_view(vec3(uv, backgroundDepth)).z;
    vec3 direction = normalize(normalize(viewPos) + normalDelta * (REFRACTION_STRENGTH * 0.01));
    float distance = min(abs(viewPos.z - backgroundZ), 32.0);
    vec2 refractedUV = view_screen(viewPos + direction * distance).xy;
    vec2 ndc = abs(refractedUV * 2.0 - 1.0);
    float visibility = clamp((1.0 - max(ndc.x, ndc.y)) / 0.10, 0.0, 1.0);
    refractedUV = mix(uv, refractedUV, visibility);
    if (gl_FragCoord.z > water_depth_range(depthBuffer, refractedUV).x) return uv;
    return refractedUV;
}
#endif
