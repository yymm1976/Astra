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
// Producer writes native triangle depth. Surface coordinates are projected at
// vertices, then interpolated. Exact caster texels are paired with their depths.
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
    // SC-35 shadow round: 16/4 -> 24/8. The old band ended 4 blocks inside
    // the map edge and faded the last visible shadows on top of the larger
    // 256-block map; the wider band keeps coverage gradual instead of popping.
    return 1.0 - smoothstep(shadowDistance - 24.0, shadowDistance - 8.0,
                            shadow_box_distance(playerPos));
}
float shadow_uv_coverage(vec3 shadowPos) {
    float border = min(min(shadowPos.x, 1.0 - shadowPos.x),
                       min(shadowPos.y, 1.0 - shadowPos.y));
    float margin = shadowTexelSpread + 1.5 / float(shadowMapResolution);
    if (shadowPos.z <= 0.0 || shadowPos.z >= 1.0) return 0.0;
    float radialBorder = 0.5 * (1.0 - length(shadowPos.xy * 2.0 - 1.0));
    return smoothstep(margin, margin * 2.0, min(border, radialBorder));
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
// Volume samples have no receiver plane. Filter visibility, never raw depth,
// so a texel crossing cannot switch an entire integrated light column at once.
float shadow_opaque_visibility(vec3 shadowPos) {
    ivec2 size = textureSize(shadowtex1, 0);
    vec2 location = shadowPos.xy * vec2(size) - 0.5;
    ivec2 corner = ivec2(floor(location));
    vec2 f = fract(location);
    float visibility = 0.0;
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            ivec2 pixel = clamp(corner + ivec2(x,y), ivec2(0), size - 1);
            vec2 w = mix(vec2(1.0) - f, f, vec2(x,y));
            visibility += step(shadowPos.z, texelFetch(shadowtex1, pixel, 0).r) * w.x * w.y;
        }
    }
    return visibility;
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
#endif

vec3 shadow_map_position(vec3 playerPos, vec3 worldNormal, float ndotl) {
    vec3 raw = player_shadow(playerPos);
    // Steadfast's normal offset is paired with its radial projection. All PCF
    // taps compare the same Z; no screen-derivative plane inversion is involved.
    float bias = 1.5 * length(raw.xy)
               + SHADOW_DISTORT_FACTOR * (1.0 - max(ndotl, 0.0));
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
