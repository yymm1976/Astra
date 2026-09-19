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
// vertices, then interpolated. Software pairs caster texels with their depths;
// optional hardware PCF compares depth first and resolves centre material separately.
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
#if SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
uniform sampler2DShadow shadowtex0;
uniform sampler2DShadow shadowtex1;
const int SHADOW_FILTER_TAPS = 4;
#else
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
const int SHADOW_FILTER_TAPS = 16;
#endif
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
    #ifdef DIMENSION_END
    return smoothstep(margin,margin*2.0,border);
    #else
    float radialBorder = 0.5 * (1.0 - length(shadowPos.xy * 2.0 - 1.0));
    return smoothstep(margin, margin * 2.0, min(border, radialBorder));
    #endif
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
    ShadowTap tap;
    tap.caster = vec4(1.0,0.0,0.0,0.0);
    #if SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
    vec2 edge = 0.5 / vec2(size);
    vec2 coord = clamp(uv, edge, 1.0-edge);
    tap.allVisibility = texture(shadowtex0, vec3(coord, referenceDepth));
    // Opaque casters are a subset of all casters. A fully visible footprint
    // cannot acquire an opaque shadow in the second map.
    tap.opaqueVisibility = 1.0;
    if (tap.allVisibility < 1.0)
        tap.opaqueVisibility = texture(shadowtex1, vec3(coord, referenceDepth));
    // Material data is resolved once by the surface consumer, after all four lobes.
    #else
    ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    tap.allVisibility = step(referenceDepth, texelFetch(shadowtex0, pixel, 0).r);
    tap.opaqueVisibility = 1.0;
    if (tap.allVisibility < 1.0)
        tap.opaqueVisibility = step(referenceDepth, texelFetch(shadowtex1, pixel, 0).r);
    // No tint/height can contribute when both visibility results agree. Air-side
    // water still needs R even with coloured shadows off, to preserve transmission.
    if (tap.opaqueVisibility > tap.allVisibility)
        tap.caster = texelFetch(shadowcolor0, pixel, 0);
    #endif
    return tap;
}
#if SHADOW_FILTER_MODE == 0
// Gather returns (01,11,10,00); reorder to (00,10,01,11), matching the
// original software corners. Compare every depth BEFORE weighting it.
vec4 shadow_corner_weights(vec2 f) {
    return vec4((1.0-f.x)*(1.0-f.y), f.x*(1.0-f.y),
                (1.0-f.x)*f.y, f.x*f.y);
}
vec4 shadow_gather_visibility(sampler2D depths, vec2 uv, float referenceDepth) {
    vec2 edge = 0.5 / vec2(textureSize(depths, 0));
    return step(vec4(referenceDepth), textureGather(depths, clamp(uv,edge,1.0-edge), 0).wzxy);
}
vec3 shadow_lobe_light(vec2 uv, float referenceDepth) {
    ivec2 size = textureSize(shadowtex0, 0);
    vec2 edge = 0.5 / vec2(size);
    uv = clamp(uv, edge, 1.0-edge);
    vec2 location = uv * vec2(size) - 0.5;
    vec4 weights = shadow_corner_weights(fract(location));
    vec4 allVisibility = shadow_gather_visibility(shadowtex0, uv, referenceDepth);
    vec3 light = vec3(dot(allVisibility, weights));
    if (all(equal(allVisibility, vec4(1.0)))) return light;

    vec4 opaqueVisibility = shadow_gather_visibility(shadowtex1, uv, referenceDepth);
    vec4 transparentWeight = max(opaqueVisibility-allVisibility, vec4(0.0)) * weights;
    // Preserve each corner's discrete caster, including mixed water/glass
    // edges. The hardware mode's centre-material approximation is not used.
    if (any(greaterThan(transparentWeight, vec4(0.0)))) {
        ivec2 corner = ivec2(floor(location));
        for (int i=0; i<4; ++i) {
            if (transparentWeight[i] <= 0.0) continue;
            ivec2 pixel = clamp(corner+ivec2(i & 1, (i >> 1) & 1), ivec2(0), size-1);
            vec4 caster = texelFetch(shadowcolor0, pixel, 0);
            vec3 transmission = vec3(0.0);
            #ifdef COLORED_SHADOWS
                transmission = caster.gba;
            #endif
            if (caster.r < 0.999)
                transmission = isEyeInWater == 1 ? caster.gba : vec3(1.0);
            light += transmission * transparentWeight[i];
        }
    }
    return light;
}
#endif
// Volume samples have no receiver plane. Filter visibility, never raw depth,
// so a texel crossing cannot switch an entire integrated light column at once.
float shadow_opaque_visibility(vec3 shadowPos) {
    ivec2 size = textureSize(shadowtex1, 0);
    #if SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
    // Hardware compares each of the four depths BEFORE linear filtering.
    vec2 edge = 0.5 / vec2(size);
    return texture(shadowtex1, vec3(clamp(shadowPos.xy,edge,1.0-edge),shadowPos.z));
    #else
    vec2 edge = 0.5 / vec2(size);
    vec2 location = clamp(shadowPos.xy, edge, 1.0-edge) * vec2(size) - 0.5;
    vec2 f = fract(location);
    return dot(shadow_gather_visibility(shadowtex1, shadowPos.xy, shadowPos.z),
               shadow_corner_weights(f));
    #endif
}
// Same four lobe positions in both modes: four hardware comparison coordinates,
// or sixteen software corners. Material IDs and height codes are never interpolated.
vec2 shadow_filter_uv(vec3 shadowPos, int index, out float weight) {
    #if SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
    vec2 offset = vec2((index & 1) == 0 ? -1.0 : 1.0,
                       (index & 2) == 0 ? -1.0 : 1.0) * (float(SHADOW_SOFTNESS) * 0.5);
    weight = 0.25;
    return shadowPos.xy + offset / float(shadowMapResolution);
    #else
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
    #endif
}
#endif

vec3 shadow_map_position(vec3 playerPos, vec3 worldNormal, float ndotl) {
    #ifdef DIMENSION_END
    // Fixed world-space offset; a camera-relative radial bias moves the edge.
    float bias=end_shadow_texel_size()*0.30+0.015;
    #else
    vec3 raw = player_shadow(playerPos);
    // Steadfast's normal offset is paired with its radial projection. All PCF
    // taps compare the same Z; no screen-derivative plane inversion is involved.
    float bias = 1.5 * length(raw.xy)
               + SHADOW_DISTORT_FACTOR * (1.0 - max(ndotl, 0.0));
    #endif
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
