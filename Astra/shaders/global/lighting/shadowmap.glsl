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
// Opaque main-world casters conservatively correct warped triangle depth.
// Native receivers project their original plane and bound its correction.
// Both modes pair corner visibility with its
// caster texel; only the depth comparison runs in GLSL or in the texture unit.
#include "/lib/distort.glsl"
#include "/lib/transforms.glsl"
#include "/lib/water_palette.glsl"

const float WATER_HEIGHT_NONE = 1.0;

// Quantization of the origin keeps small relative heights accurate. The target
// is rebuilt each frame, so crossing an origin boundary does not reuse old codes.
float water_height_origin() {
    return floor(cameraPosition.y / 16.0) * 16.0;
}
float encode_water_height(float worldY) {
    float localY = worldY - water_height_origin();
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    // The optical target is already RGBA16F, not the historical R8 carrier.
    // Signed /1024 height covers a 2047-block window with at most half-block
    // FP16 spacing; reserve 1 for non-water and avoid rounding into that marker.
    // The ordinary Overworld's complete vertical range fits even from its floor.
    if (localY < -1024.0 || localY > 1023.0) return WATER_HEIGHT_NONE;
    return localY * (1.0 / 1024.0);
    #else
    if (localY < -64.0 || localY > 63.0) return WATER_HEIGHT_NONE;
    return (localY + 64.0) / 127.5;
    #endif
}
float decode_water_height(float encoded) {
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    return encoded * 1024.0 + water_height_origin();
    #else
    return encoded * 127.5 - 64.0 + water_height_origin();
    #endif
}
vec4 decode_water_height(vec4 encoded) {
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    return encoded * 1024.0 + water_height_origin();
    #else
    return encoded * 127.5 - 64.0 + water_height_origin();
    #endif
}

#ifdef SHADOWS
#if ASTRA_SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
uniform sampler2DShadow shadowtex0;
uniform sampler2DShadow shadowtex1;
#else
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
#endif
#endif
#if defined SHADOWS || defined WATER_CAUSTICS
// R: water height/type. Overworld water A: bed focus, GB reserved/unused.
// Non-water casters and other dimensions retain GBA transmission RGB.
uniform sampler2D shadowcolor0;
vec4 shadow_caster_data(vec2 uv) {
    ivec2 size = textureSize(shadowcolor0, 0);
    return texelFetch(shadowcolor0, clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1), 0);
}
#if !defined DIMENSION_NETHER && !defined DIMENSION_END && defined WATER_CAUSTICS
vec4 shadow_water_caustic_gain(vec4 heights, vec4 focus, float receiverWorldY) {
    vec4 depth = max(decode_water_height(heights) - receiverWorldY, vec4(0.0));
    vec4 depthSquared = depth * depth;
    vec4 depthWeight = depthSquared / (depthSquared + 16.0);
    vec4 deviation = max(focus, vec4(0.0)) - 1.0;
    // A one-block pool retains only a faint lens response. Compress bright
    // ridges as a scalar, so RGB clipping cannot turn cyan patches white.
    // Shore-side contrast is deliberately lower to keep clear shallow floors
    // from looking cluttered; underwater retains its separately calibrated gain.
    float contrast = isEyeInWater == 1 ? 0.90 : 0.65;
    return 1.0 + depthWeight * contrast * deviation / (1.0 + abs(deviation) * 0.60);
}
#endif
vec3 shadow_water_transmission(vec4 caster, float receiverWorldY) {
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        #ifdef WATER_CAUSTICS
        // The water medium owns spectral colouring. Surface caustics change
        // light intensity only, avoiding a second cyan pattern on the bed.
        return vec3(shadow_water_caustic_gain(vec4(caster.r), vec4(caster.a), receiverWorldY).x);
        #else
        return vec3(1.0);
        #endif
    #else
    return caster.gba;
    #endif
}
#endif

const float shadowTexelSpread = SHADOW_SOFTNESS * (1.0 / shadowMapResolution);

float shadow_box_distance(vec3 playerPos) {
    return max(abs(playerPos.x), max(abs(playerPos.y), abs(playerPos.z)));
}
float shadow_map_fade(vec3 playerPos) {
    #ifdef DIMENSION_END
    // The End uses a snapped orthographic square in light-view XY, not the
    // overworld's camera-space cube or its full SHADOW_DISTANCE radius.
    vec2 xy = abs(end_shadow_view(playerPos).xy);
    float extent = end_shadow_extent();
    return 1.0 - smoothstep(extent - 24.0, extent - 8.0, max(xy.x, xy.y));
    #else
    // SC-35 shadow round: 16/4 -> 24/8. The old band ended 4 blocks inside
    // the map edge and faded the last visible shadows on top of the larger
    // 256-block map; the wider band keeps coverage gradual instead of popping.
    return 1.0 - smoothstep(shadowDistance - 24.0, shadowDistance - 8.0,
                            shadow_box_distance(playerPos));
    #endif
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
    float fade = shadow_map_fade(playerPos);
    if (fade <= 0.0) return 0.0;
    return fade * shadow_uv_coverage(shadowPos);
}

#ifdef SHADOWS
#ifdef ASTRA_SURFACE_SHADOW_FRAGMENT
vec2 astraSurfaceShadowOrigin = vec2(0.0);
vec2 astraSurfaceRawOrigin = vec2(0.0);
vec2 astraSurfaceRawPlane = vec2(0.0);
float astraSurfaceShadowPixelWorldSquared = 0.0;
void astra_surface_shadow_set_plane(vec3 pos,vec3 planeNormal) {
    // Interpolate raw NDC before adding the texture-space half offset. Adding
    // it in the vertex stage loses small Z differences, amplified at low sun.
    vec3 dx = dFdx(pos), dy = dFdy(pos);
    float determinant = dx.x*dy.y-dx.y*dy.x;
    astraSurfaceRawOrigin = pos.xy*0.5+0.5;
    astraSurfaceRawPlane = abs(planeNormal.z) > 1e-6
        ? -0.5*planeNormal.xy/planeNormal.z
        : (abs(determinant) > 1e-20
        ? 0.5*vec2(dy.y*dx.z-dx.y*dy.z,dx.x*dy.z-dy.x*dx.z)/determinant
        : vec2(0.0));
    // Reproject the actual point, independently of the quad's diagonal.
    vec2 raw = pos.xy;
    float radius = length(raw);
    float scale = radius+SHADOW_DISTORT_FACTOR;
    astraSurfaceShadowOrigin = raw/scale*0.5+0.5;
}
void astra_surface_shadow_set_plane(vec3 pos,vec3 playerPos,vec3 planeNormal) {
    // Keep derivatives before discard; only mixed filtering needs the root.
    vec3 dx=dFdx(playerPos), dy=dFdy(playerPos);
    astraSurfaceShadowPixelWorldSquared=max(dot(dx,dx),dot(dy,dy));
    astra_surface_shadow_set_plane(pos,planeNormal);
}
#endif
// Gather returns (01,11,10,00); reorder to (00,10,01,11), matching the
// original software corners. Compare every depth BEFORE weighting it.
vec4 shadow_corner_weights(vec2 f) {
    return vec4((1.0-f.x)*(1.0-f.y), f.x*(1.0-f.y),
                (1.0-f.x)*f.y, f.x*f.y);
}
#if ASTRA_SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
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
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
// Surface callers have already established positive shadow_coverage. Its
// border exceeds SHADOW_SOFTNESS + 1.5 texels, while every lobe moves at most
// SHADOW_SOFTNESS / 2 per axis. The lobe and all four corners are therefore
// inside the map: prepare its size once and avoid repeating boundary work.
#if ASTRA_SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
vec4 shadow_gather_visibility_inside(sampler2DShadow depths, vec2 uv, float referenceDepth) {
    return textureGather(depths, uv, referenceDepth).wzxy;
}
#else
vec4 shadow_gather_visibility_inside(sampler2D depths, vec2 uv, float referenceDepth) {
    return step(vec4(referenceDepth), textureGather(depths, uv, 0).wzxy);
}
#endif
// Build references once per lobe; both paired depth textures use these values.
vec4 shadow_surface_reference_depths(vec2 uv,float referenceDepth,ivec2 size) {
    #ifdef ASTRA_SURFACE_SHADOW_FRAGMENT
    // An exactly level receiver has the same reference at every corner.
    if (all(equal(astraSurfaceRawPlane,vec2(0.0)))) return vec4(referenceDepth);
    vec2 corner=floor(uv*vec2(size)-0.5);
    vec4 x=(corner.x+vec4(0.5,1.5,0.5,1.5))/float(size.x);
    vec4 y=(corner.y+vec4(0.5,0.5,1.5,1.5))/float(size.y);
    x=x*2.0-1.0;
    y=y*2.0-1.0;
    vec4 factor=SHADOW_DISTORT_FACTOR/max(1.0-sqrt(x*x+y*y),vec4(1e-5));
    x=x*factor*0.5+0.5;
    y=y*factor*0.5+0.5;
    // A filter corner can lie outside this finite face (e.g. below a step).
    // Extrapolation may move its reference behind the actual receiver and turn
    // a lower, sunlit neighbour into a blocker. Never increase reference Z.
    return min(vec4(referenceDepth),
        referenceDepth+(x-astraSurfaceRawOrigin.x)*astraSurfaceRawPlane.x
                      +(y-astraSurfaceRawOrigin.y)*astraSurfaceRawPlane.y);
    #else
    return vec4(referenceDepth);
    #endif
}
#if ASTRA_SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
vec4 shadow_surface_visibility_inside(sampler2DShadow depths, vec2 uv, vec4 references) {
#else
vec4 shadow_surface_visibility_inside(sampler2D depths, vec2 uv, vec4 references) {
#endif
    #ifdef ASTRA_SURFACE_SHADOW_FRAGMENT
    #if ASTRA_SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
    // Hardware gather accepts only one reference. Select each corner from its
    // own comparison gather; results stay binary even at non-power-of-two sizes.
    // Bilinear texture() at a rounded centre would contaminate caster identity.
    if (all(equal(references,vec4(references.x)))) {
        return textureGather(depths,uv,references.x).wzxy;
    }
    vec4 visible;
    for (int i=0;i<4;++i) {
        vec4 comparisons = textureGather(depths,uv,references[i]).wzxy;
        visible[i] = comparisons[i];
    }
    return visible;
    #else
    return step(references,textureGather(depths,uv,0).wzxy);
    #endif
    #else
    return shadow_gather_visibility_inside(depths,uv,references.x);
    #endif
}
vec3 shadow_lobe_light_inside(vec2 uv, float referenceDepth, float receiverWorldY, ivec2 size,
                            bool opaqueFirst) {
#else
vec3 shadow_lobe_light(vec2 uv, float referenceDepth, float receiverWorldY) {
    ivec2 size = textureSize(shadowtex0, 0);
    vec2 edge = 0.5 / vec2(size);
    uv = clamp(uv, edge, 1.0-edge);
#endif
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Iris copies opaque depth to shadowtex1 before translucent casters extend
    // shadowtex0. A fully blocked opaque footprint cannot transmit any light.
    // Skylight selects the cheaper query order only; it never decides visibility.
    vec4 referenceDepths=shadow_surface_reference_depths(uv,referenceDepth,size);
    vec4 opaqueVisibility = vec4(1.0);
    if (opaqueFirst) {
        opaqueVisibility = shadow_surface_visibility_inside(shadowtex1, uv, referenceDepths);
        if (all(equal(opaqueVisibility, vec4(0.0)))) {
            return vec3(0.0);
        }
    }
    vec4 allVisibility = shadow_surface_visibility_inside(shadowtex0, uv, referenceDepths);
    if (all(equal(allVisibility, vec4(1.0)))) {
        return vec3(1.0);
    }
    #else
    vec4 allVisibility = shadow_gather_visibility(shadowtex0, uv, referenceDepth);
    #endif
    // Only mixed footprints need interpolation weights and caster identities.
    vec2 location = uv * vec2(size) - 0.5;
    vec4 weights = shadow_corner_weights(fract(location));
    vec3 light = vec3(dot(allVisibility, weights));

    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    if (!opaqueFirst)
        opaqueVisibility = shadow_surface_visibility_inside(shadowtex1, uv, referenceDepths);
    #else
    if (all(equal(allVisibility, vec4(1.0)))) return light;
    vec4 opaqueVisibility = shadow_gather_visibility(shadowtex1, uv, referenceDepth);
    #endif
    vec4 transparentWeight = max(opaqueVisibility-allVisibility, vec4(0.0)) * weights;
    // Preserve each corner's discrete caster, including mixed water/glass edges.
    if (any(greaterThan(transparentWeight, vec4(0.0)))) {
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END && !defined COLORED_SHADOWS && !defined WATER_CAUSTICS
        // Both caster responses are white with these options off. The paired
        // depths already supply the complete result, with no caster payload.
        return light + vec3(dot(transparentWeight, vec4(1.0)));
        #endif
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        // Open water occupies many shoreline receivers. Gather just height and
        // focus rather than reading four full RGBA caster records per lobe.
        // Sparse edges already need fewer than four caster reads. Keep their
        // original path instead of paying for gathers that cannot save work.
        if (all(greaterThan(transparentWeight, vec4(0.0)))) {
          vec4 waterHeights = textureGather(shadowcolor0, uv, 0).wzxy;
          if (all(lessThan(waterHeights, vec4(WATER_HEIGHT_NONE)))) {
            #ifdef WATER_CAUSTICS
            vec4 focus = textureGather(shadowcolor0, uv, 3).wzxy;
            vec4 gain = shadow_water_caustic_gain(waterHeights, focus, receiverWorldY);
            light += vec3(dot(gain, transparentWeight));
            #else
            light += vec3(dot(vec4(1.0), transparentWeight));
            #endif
            return light;
          }
        }
        #endif
        ivec2 corner = ivec2(floor(location));
        for (int i=0; i<4; ++i) {
            if (transparentWeight[i] <= 0.0) continue;
            #if !defined DIMENSION_NETHER && !defined DIMENSION_END
            ivec2 pixel = corner+ivec2(i & 1, (i >> 1) & 1);
            #else
            ivec2 pixel = clamp(corner+ivec2(i & 1, (i >> 1) & 1), ivec2(0), size-1);
            #endif
            vec4 caster = texelFetch(shadowcolor0, pixel, 0);
            vec3 transmission = vec3(1.0);
            #ifdef COLORED_SHADOWS
                transmission = caster.gba;
            #endif
            if (caster.r < WATER_HEIGHT_NONE) {
                transmission = shadow_water_transmission(caster, receiverWorldY);
            }
            light += transmission * transparentWeight[i];
        }
    }
    return light;
}
// Volume samples have no receiver plane. Filter visibility, never raw depth,
// so a texel crossing cannot switch an entire integrated light column at once.
float shadow_opaque_visibility(vec3 shadowPos) {
    ivec2 size = textureSize(shadowtex1, 0);
    #if ASTRA_SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
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
    #ifdef ASTRA_SURFACE_SHADOW_PLANE
    // Carry raw NDC; fragment conversion preserves the small differences used
    // to recover the plane, especially on grazing surfaces near sunset.
    return player_shadow(playerPos);
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
    #endif
}

float static_shadow(float skyLight) {
    return smoothstep(13.5 / 15.0, 14.5 / 15.0, skyLight);
}
#endif
