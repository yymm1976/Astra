#ifndef ASTRA_GLOBAL_WATER_REFRACTION_GLSL
#define ASTRA_GLOBAL_WATER_REFRACTION_GLSL
// Astra-authored projected Snell ray / depth-plane iteration.
// Historical provenance: From Solas V2.2b (licence undeclared), SC-24 screen
// offset implementation. That implementation has been replaced; retain its
// attribution record in THIRD-PARTY.md rather than silently removing history.
// The ray is supplied by the interface. No second normal or screen perturbation.
// Returns a projected UV; the caller validates each colour/depth sample together.
vec2 refract_trace(sampler2D depthBuffer, vec3 viewPos, vec3 direction, float maxDistance) {
    vec2 originalUV = view_screen(viewPos).xy;
    ivec2 size = textureSize(depthBuffer, 0);
    vec2 uv = originalUV;
    for (int i = 0; i < 4; ++i) {
        if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) break;
        ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
        float depth = texelFetch(depthBuffer, pixel, 0).r;
        float travel = maxDistance;
        if (depth < 0.999999 && direction.z < -1e-4) {
            vec2 pixelUV = (vec2(pixel) + 0.5) / vec2(size);
            float sceneZ = screen_view(vec3(pixelUV, depth)).z;
            travel = clamp((sceneZ - viewPos.z) / direction.z, 0.0, maxDistance);
        }
        vec4 projected = gbufferProjection * vec4(viewPos + direction * travel, 1.0);
        if (projected.w <= 1e-4) return vec2(-1.0);
        uv = projected.xy / projected.w * 0.5 + 0.5;
    }
    return uv;
}
#endif
