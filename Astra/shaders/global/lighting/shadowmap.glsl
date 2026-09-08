#ifndef ASTRA_GLOBAL_LIGHTING_SHADOWMAP_GLSL
#define ASTRA_GLOBAL_LIGHTING_SHADOWMAP_GLSL

// Astra v1 — global/lighting/shadowmap.glsl
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot
//   source: _analysis/Steadfast-0.8.0/shaders/environment/lighting/shadowmap.glsl
//           (+ program/world/lit.vsh ShadowMapPosition, program/shadow/shadow.vsh)
// This file is a derivative of Steadfast and is licensed under the GNU General
// Public License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
// _analysis/Steadfast-0.8.0/LICENSE.md. Redistribution is permitted only under that
// license including Steadfast's Section 7 additional terms.
// Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Producer reconstructs depth on the inverse-warped surface plane. Consumers
// compare raw depths at the same texel as the caster data and filter illumination.
#include "/lib/distort.glsl"
#include "/lib/transforms.glsl"

const float WATER_HEIGHT_NONE = 1.0;

// R8 has only 256 codes. Reserve 255 for non-water, and use exact half-block
// increments over a nearby 127-block window. The old +/-1024 encoding lost eight
// blocks per code, putting surface anchors above/below the actual riverbed.
float water_height_origin() {
    return floor(cameraPosition.y / 16.0) * 16.0;
}
float encode_water_height(float worldY) {
    float localY = worldY - water_height_origin();
    if (localY < -64.0 || localY > 63.0) return WATER_HEIGHT_NONE;
    return (localY + 64.0) / 127.5;
}
float decode_water_height(float encoded) {
    return encoded * 127.5 - 64.0 + water_height_origin();
}

#ifdef SHADOWS
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
#endif
#if defined SHADOWS || defined WATER_CAUSTICS
uniform sampler2D shadowcolor0; // R: water height, GBA: transparent-caster tint
vec4 shadow_caster_data(vec2 uv) {
    ivec2 size = textureSize(shadowcolor0, 0);
    return texelFetch(shadowcolor0, clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1), 0);
}
#endif

const float shadowTexelSpread = SHADOW_SOFTNESS * (1.0 / shadowMapResolution);

float shadow_box_distance(vec3 playerPos) {
    return max(abs(playerPos.x), max(abs(playerPos.y), abs(playerPos.z)));
}
float shadow_map_fade(vec3 playerPos) {
    return 1.0 - smoothstep(shadowDistance - 16.0, shadowDistance - 4.0,
                            shadow_box_distance(playerPos));
}
float shadow_uv_coverage(vec3 shadowPos) {
    float border = min(min(shadowPos.x, 1.0 - shadowPos.x),
                       min(shadowPos.y, 1.0 - shadowPos.y));
    float margin = shadowTexelSpread + 1.5 / float(shadowMapResolution);
    if (shadowPos.z <= 0.0 || shadowPos.z >= 1.0) return 0.0;
    return smoothstep(margin, margin * 2.0, border);
}
float shadow_coverage(vec3 playerPos, vec3 shadowPos) {
    return shadow_map_fade(playerPos) * shadow_uv_coverage(shadowPos);
}

#ifdef SHADOWS
struct ShadowTap {
    float allVisibility;
    float opaqueVisibility;
    vec4 caster;
};
ShadowTap shadow_read_tap(vec2 uv, float referenceDepth) {
    ivec2 size = textureSize(shadowtex0, 0);
    ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    ShadowTap tap;
    tap.allVisibility = step(referenceDepth, texelFetch(shadowtex0, pixel, 0).r);
    tap.opaqueVisibility = step(referenceDepth, texelFetch(shadowtex1, pixel, 0).r);
    tap.caster = texelFetch(shadowcolor0, pixel, 0);
    return tap;
}
// Four bilinear lobes, expanded to sixteen exact texels. Every consumer filters
// the completed lighting at these texels, never a material ID or depth code.
vec2 shadow_filter_uv(vec3 shadowPos, int index, out float weight) {
    int lobe = index / 4;
    int corner = index - lobe * 4;
    vec2 offset = vec2((lobe & 1) == 0 ? -1.0 : 1.0,
                       (lobe & 2) == 0 ? -1.0 : 1.0) * (float(SHADOW_SOFTNESS) * 0.5);
    vec2 location = shadowPos.xy * float(shadowMapResolution) - 0.5 + offset;
    vec2 f = fract(location);
    vec2 c = vec2(corner & 1, (corner >> 1) & 1);
    vec2 w = mix(1.0 - f, f, c);
    weight = w.x * w.y * 0.25;
    return (floor(location) + c + 0.5) / float(shadowMapResolution);
}
float shadow_receiver_depth(vec3 shadowPos, vec2 tapUV, vec3 worldNormal) {
    vec3 planeNormal = mat3(shadowModelView) * worldNormal;
    planeNormal /= vec3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]);
    vec3 center = undistort(shadowPos * 2.0 - 1.0);
    vec2 point = undistort(vec3(tapUV * 2.0 - 1.0, 0.0)).xy;
    if (abs(planeNormal.z) < 1e-5) return shadowPos.z;
    float correction = -dot(planeNormal.xy, point - center.xy) / planeNormal.z * 0.1;
    return shadowPos.z + clamp(correction, -0.002, 0.002);
}
#endif

vec3 shadow_map_position(vec3 playerPos, vec3 worldNormal, float ndotl) {
    vec3 raw = player_shadow(playerPos);
    float factor = get_distort_factor(raw.xy);
    // Radial derivative of x/(b*r + a) is a/(b*r+a)^2. Convert a
    // distorted texel back to a conservative world-space footprint.
    float stretch = factor * factor / max(1.0 - shadow_map_bias, 0.05);
    float texelWorld = (2.0 * shadowDistance / float(shadowMapResolution)) * stretch;
    float bias = clamp(texelWorld * (0.30 + 0.45 * (1.0 - max(ndotl, 0.0))), 0.008, 0.12);
    vec3 shadowPos = distort(player_shadow(playerPos + worldNormal * bias)) * 0.5 + 0.5;
    shadowPos.z -= 0.00001;
    return shadowPos;
}

// The texture contains a water surface only when its first caster is water.
// Quantization is half a block, hence the small surface tolerance here.
float shadow_water_depth(vec3 playerPos, vec3 shadowPos) {
    #ifdef SHADOWS
        if (shadow_coverage(playerPos, shadowPos) <= 0.0) return 0.0;
        float encoded = shadow_caster_data(shadowPos.xy).r;
        if (encoded >= 0.999) return 0.0;
        return max(decode_water_height(encoded) - (playerPos.y + cameraPosition.y), 0.0);
    #else
        return 0.0;
    #endif
}

float static_shadow(float skyLight) {
    return smoothstep(13.5 / 15.0, 14.5 / 15.0, skyLight);
}
#endif
