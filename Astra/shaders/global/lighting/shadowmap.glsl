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
// vertices, then interpolated. Both modes pair each corner's visibility with its
// caster texel; only the depth comparison runs in GLSL or in the texture unit.
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
#else
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
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
// Gather returns (01,11,10,00); reorder to (00,10,01,11), matching the
// original software corners. Compare every depth BEFORE weighting it.
vec4 shadow_corner_weights(vec2 f) {
    return vec4((1.0-f.x)*(1.0-f.y), f.x*(1.0-f.y),
                (1.0-f.x)*f.y, f.x*f.y);
}
#if SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
vec4 shadow_gather_visibility(sampler2DShadow depths, vec2 uv, float referenceDepth) {
    vec2 edge=0.5/vec2(textureSize(depths,0));
    // Shadow gather returns four separate comparison results in one lookup.
    // Keep them separate until each corner's tint/water identity is resolved.
    return textureGather(depths,clamp(uv,edge,1.0-edge),referenceDepth).wzxy;
}
#else
vec4 shadow_gather_visibility(sampler2D depths, vec2 uv, float referenceDepth) {
    vec2 edge = 0.5 / vec2(textureSize(depths, 0));
    return step(vec4(referenceDepth), textureGather(depths, clamp(uv,edge,1.0-edge), 0).wzxy);
}
#endif
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
    // Preserve each corner's discrete caster, including mixed water/glass edges.
    if (any(greaterThan(transparentWeight, vec4(0.0)))) {
        ivec2 corner = ivec2(floor(location));
        for (int i=0; i<4; ++i) {
            if (transparentWeight[i] <= 0.0) continue;
            ivec2 pixel = clamp(corner+ivec2(i & 1, (i >> 1) & 1), ivec2(0), size-1);
            vec4 caster = texelFetch(shadowcolor0, pixel, 0);
            vec3 transmission = vec3(1.0);
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
#endif

// Normal offset where light grazes the surface, in world blocks. Deliberately
// not SHADOW_DISTORT_FACTOR: that now tracks the map core and is divided by
// SHADOW_DISTANCE, so borrowing it here would make this offset scale with range.
const float shadowGrazingBias = 0.20;

vec3 shadow_map_position(vec3 playerPos, vec3 worldNormal, float ndotl) {
    #ifdef DIMENSION_END
    // The End map is an orthographic grid projected along the disc direction
    // (lib/transforms.glsl:70 end_shadow_view), so the acne scale is set by the texel
    // footprint alone: inside one texel the nearest caster can sit up to
    // texelSize * tan(angle(normal, light)) away from the receiver's own depth. At the
    // shipping 2048 map / 192-block reach the texel is 0.09375 blocks, so flat ground
    // under the 23-degree disc carries 0.09375 * cot(23) = 0.221 blocks of self-shadow
    // error. The old texel-relative 0.46 offset (0.043 blocks) covered under a fifth of
    // that and did not move with the slope, which is the periodic banding.
    //
    // The offset below tracks that slope. tan(angle(n, L)) = sqrt(1-ndotl^2)/ndotl is
    // exactly the depth error a texel of off-axis footprint hides on a flat receiver, so
    // the 1.30 margin lifts it just past the error at every orientation the disc lights,
    // and the clamps keep a near-edge-on face finite (its own light contribution is
    // already ~0 there). An axis-aligned face pointing at the disc needs almost nothing,
    // which is also true of its depth error.
    float ndotlClamped = max(ndotl, 0.05);
    float grazingBias = end_shadow_texel_size()
        * clamp(1.30 * sqrt(max(1.0 - ndotlClamped * ndotlClamped, 0.0)) / ndotlClamped,
                1.30, 4.50);
    // Residual along-light bias, in world blocks. The orthographic End map does NOT grow
    // its texels with range (lib/distort.glsl disables the radial distortion for
    // DIMENSION_END), so unlike a radial map this is a small safety term rather than a
    // range-tracking one; it still opens with camera distance so the far field keeps its
    // margin. Moving the sample point toward the light is a pure Z offset here: the
    // map axes are perpendicular to the light (transforms.glsl:72-73), so dot(L, right)
    // and dot(L, up) are zero and the footprint does not move.
    float depthBias = end_shadow_texel_size()
        * (0.50 + 1.00 * smoothstep(0.0, 128.0, length(playerPos)));
    vec3 biasedPos = playerPos + worldNormal * grazingBias
                   + end_light_direction() * depthBias;
    return distort(player_shadow(biasedPos)) * 0.5 + 0.5;
    #else
    vec3 raw = player_shadow(playerPos);
    // Steadfast's normal offset is paired with its radial projection. All PCF
    // taps compare the same Z; no screen-derivative plane inversion is involved.
    float bias = 1.5 * length(raw.xy)
               + shadowGrazingBias * (1.0 - max(ndotl, 0.0));
    vec3 shadowPos = distort(player_shadow(playerPos + worldNormal * bias)) * 0.5 + 0.5;
    shadowPos.z -= 0.00001;
    return shadowPos;
    #endif
}

float static_shadow(float skyLight) {
    return smoothstep(13.5 / 15.0, 14.5 / 15.0, skyLight);
}
#endif
