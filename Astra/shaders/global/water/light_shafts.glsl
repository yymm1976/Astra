// Adapted from IterationT 3.2.0 UnderwaterVolumetricFog.glsl: water-entry
// projection, wave-normal collision irradiance, colour extinction and phase.
// Solas supplies incident/occluded light separation and distance/daylight roles.
// Astra: one moving normal image, screen-footprint filtering, actual water
// entry shadows and shared ITT normals at the submerged horizontal interface.
// Solas keeps the water fog/display, not the additive volume's colour domain.
// See THIRD-PARTY.md. Bed caustics remain on their separate surface path.
#ifndef ASTRA_GLOBAL_WATER_LIGHT_SHAFTS_GLSL
#define ASTRA_GLOBAL_WATER_LIGHT_SHAFTS_GLSL
#include "/lib/transforms.glsl"
#include "/global/water/shaft_layout.glsl"
uniform sampler2D colortex3;
const float WATER_SHAFT_MAX_DISTANCE = 128.0;
// Sentinel for an unread material record; legal colortex3 flags are 0..255.
const uint WATER_SCENE_FLAGS_UNSET = 256u;
#ifdef ASTRA_SHAFT_MARCH_PASS
// The projection eye and its world transform are identical for the whole draw.
flat in vec3 waterShaftViewOrigin;
flat in vec3 waterShaftWorldOrigin;
#endif

// Four visibility samples per interval; each represents an integrated wave span.
#if !defined ASTRA_OVERWORLD_OPTIMIZED || UNDERWATER_SHAFT_SAMPLES < 7
    #define ASTRA_SHAFT_SAMPLES UNDERWATER_SHAFT_SAMPLES
#else
    #define ASTRA_SHAFT_SAMPLES 7
#endif

vec3 water_shafts_view_origin() {
    // The runtime composes camera bobbing into the PROJECTION matrix, while
    // model-view is its separate rotation. The perspective eye is the inverse
    // projection of the homogeneous clip Z axis, not necessarily view (0,0,0).
    // In a usual perspective projection this reduces exactly to that zero.
    #ifdef ASTRA_SHAFT_MARCH_PASS
    return waterShaftViewOrigin;
    #else
    return projection_view_origin();
    #endif
}

vec3 water_shafts_view(vec2 uv, out float rayLength, out float sceneDepth,
                       out uint sceneFlags, out float mediumDistance) {
    ivec2 size = textureSize(depthtex0, 0);
    ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    float depth = texelFetch(depthtex0, pixel, 0).r;
    // Preserve raw scene depth separately from the hand-projection adjustment.
    sceneDepth = depth;
    // Sky pixels keep the sentinel: they read no material record here, and the
    // consumer must not assume a value for them.
    sceneFlags = WATER_SCENE_FLAGS_UNSET;
    if (depth < 0.999999) {
        uint flags = uint(round(texelFetch(colortex3, pixel, 0).r * 255.0));
        sceneFlags = flags;
        if ((flags & 128u) != 0u && depth == texelFetch(depthtex1, pixel, 0).r)
            depth = ((depth * 2.0 - 1.0) / MC_HAND_DEPTH) * 0.5 + 0.5;
    }
    vec2 pixelUV = (vec2(pixel) + 0.5) / vec2(size);
    vec3 viewPos = screen_view(vec3(pixelUV, min(depth, 0.999999)));
    mediumDistance = length(viewPos-water_shafts_view_origin());
    rayLength = min(mediumDistance, WATER_SHAFT_MAX_DISTANCE);
    return viewPos;
}
vec3 water_shafts_view(vec2 uv, out float rayLength, out float sceneDepth, out uint sceneFlags) {
    float unusedMediumDistance;
    return water_shafts_view(uv,rayLength,sceneDepth,sceneFlags,unusedMediumDistance);
}
vec3 water_shafts_view(vec2 uv, out float rayLength, out float sceneDepth) {
    uint unusedSceneFlags;
    return water_shafts_view(uv, rayLength, sceneDepth, unusedSceneFlags);
}
vec3 water_shafts_view(vec2 uv, out float rayLength) {
    float unusedSceneDepth;
    return water_shafts_view(uv, rayLength, unusedSceneDepth);
}

#ifdef ASTRA_SHAFT_MARCH_PASS
#include "/lib/itt_water_field.glsl"
uniform sampler2D colortex29;
// Iris generates the just-produced collision-flux mip chain before this draw.
const bool colortex29MipmapEnabled = true;
flat in vec4 waterShaftSource;
flat in vec2 waterShaftSurface;
flat in vec2 waterShaftFieldOrigin;
flat in vec3 waterShaftIllumination;
#if CLOUD_MODE == CLOUD_PLANAR && defined CLOUD_SHADOWS
flat in vec3 waterShaftAirSource;
#endif
float water_shaft_phase(vec3 ray, vec3 source) {
    float cosine = clamp(dot(ray,source),-1.0,1.0);
    const float g = 0.7;
    float base = 1.0+g*g-2.0*g*cosine;
    float directional = (0.1193662*(1.0-g*g)/(2.0+g*g))
                      * (1.0+cosine*cosine)/(base*sqrt(base));
    // ITT's forward lobe with a small side response for Astra's visibility goal.
    return mix(0.07957747,directional,0.8);
}
bool water_shaft_wave_segment(vec2 entry, vec2 direction, inout float begin, inout float end) {
    // World-space coverage only; no periodic wrapping of unrelated entries.
    vec2 local = entry-waterShaftFieldOrigin;
    for (int axis=0;axis<2;++axis) {
        if (abs(direction[axis]) < 0.000001) {
            if (local[axis] < 2.0 || local[axis] > ITT_WATER_FIELD_EXTENT-2.0) return false;
        } else {
            vec2 distances = (vec2(2.0,ITT_WATER_FIELD_EXTENT-2.0)-local[axis])/direction[axis];
            begin = max(begin,min(distances.x,distances.y));
            end = min(end,max(distances.x,distances.y));
        }
    }
    return end > begin;
}
float water_shaft_path_visibility(vec3 point, vec3 entry,
                                  vec4 surfaceClip, vec4 pointClip) {
    // Look just BELOW the interface to distinguish passing through water from
    // open air or glass. Pair each depth comparison with its OWN water caster.
    vec3 insideEntry = entry-vec3(0.0,0.18,0.0);
    vec3 surfaceShadow = distort(surfaceClip.xyz/surfaceClip.w)*0.5+0.5;
    float coverage = shadow_coverage(insideEntry,surfaceShadow);
    if (coverage <= 0.0) return 0.0;
    vec4 opaque = shadow_gather_visibility_inside(shadowtex1,surfaceShadow.xy,surfaceShadow.z);
    if (all(equal(opaque,vec4(0.0)))) return 0.0;
    vec4 allCasters = shadow_gather_visibility_inside(shadowtex0,surfaceShadow.xy,surfaceShadow.z);
    vec4 through = max(opaque-allCasters,vec4(0.0));
    if (all(equal(through,vec4(0.0)))) return 0.0;
    vec4 heights = textureGather(shadowcolor0,surfaceShadow.xy,0).wzxy;
    vec4 water = vec4(lessThan(heights,vec4(WATER_HEIGHT_NONE)));
    water *= vec4(lessThan(abs(decode_water_height(heights)
                  -vec4(entry.y+cameraPosition.y)),vec4(0.75)));
    vec2 location = surfaceShadow.xy*vec2(textureSize(shadowtex0,0))-0.5;
    float incident = coverage*dot(through*water,shadow_corner_weights(fract(location)));
    if (incident <= 0.0) return 0.0;
    #if CLOUD_MODE == CLOUD_PLANAR && defined CLOUD_SHADOWS
    incident *= astra_cloud_transmission(entry+cameraPosition,
                    waterShaftAirSource);
    if (incident <= 0.0) return 0.0;
    #endif
    vec3 pos = distort(pointClip.xyz/pointClip.w)*0.5+0.5;
    float receiverCoverage = shadow_coverage(point,pos);
    if (receiverCoverage <= 0.0) return 0.0;
    return incident*receiverCoverage*shadow_opaque_visibility(pos);
}
float water_shaft_wave_span(vec2 localEntry, vec2 entryRay, float begin, float span,
                            float angularFootprint) {
    // The outer Gauss nodes lie on camera-centred shells. Evaluating the fine
    // wave field ONLY there aliases it into curved bands, even with no shadows.
    // Integrate along the ray inside the node's weight-sized cell instead.
    // Average collision LIGHT, not slopes: averaging normals first erases the
    // nonlinear wave response. No cross-ray blur, noise or history is involved.
    const float nodes[8] = float[8](
        0.0198550718,0.1016667613,0.2372337950,0.4082826788,
        0.5917173212,0.7627662050,0.8983332387,0.9801449282);
    const float weights[8] = float[8](
        0.0506142681,0.1111905172,0.1568533229,0.1813418917,
        0.1813418917,0.1568533229,0.1111905172,0.0506142681);
    float end = begin+span;
    // Every fine node is inside this span. Constant portions of the filters
    // need neither eight repeated ramps nor eight repeated base-LOD logs.
    bool nearFade = begin < WATER_SHAFT_NEAR_END;
    bool farFade = end > WATER_SHAFT_FAR_START;
    bool filtered = angularFootprint*end > ITT_WATER_FIELD_CELL;
    bool coarsest = angularFootprint*begin >= ITT_WATER_FIELD_CELL*16.0;
    vec2 localBegin = localEntry+entryRay*begin;
    vec2 localEnd = localEntry+entryRay*end;
    vec2 borderRange = min(min(localBegin,localEnd),
                          ITT_WATER_FIELD_EXTENT-max(localBegin,localEnd));
    bool borderFade = min(borderRange.x,borderRange.y) < 3.0;
    float light = 0.0;
    for (int i=0;i<8;++i) {
        float distance = begin+nodes[i]*span;
        vec2 local = localEntry+entryRay*distance;
        float lod = coarsest ? 4.0 : 0.0;
        if (filtered && !coarsest) {
            float footprint = max(ITT_WATER_FIELD_CELL,angularFootprint*distance);
            lod = clamp(log2(footprint/ITT_WATER_FIELD_CELL),0.0,4.0);
        }
        float irradiance = textureLod(colortex29,local/ITT_WATER_FIELD_EXTENT,lod).r;
        // The field contains nonnegative flux; an exact zero stays zero after
        // every border/distance filter and contributes nothing to this span.
        if (irradiance == 0.0) continue;
        if (borderFade) {
            vec2 border = min(local,ITT_WATER_FIELD_EXTENT-local);
            irradiance *= smoothstep(2.0,3.0,min(border.x,border.y));
        }
        if (nearFade)
            irradiance *= smoothstep(WATER_SHAFT_NEAR_START,WATER_SHAFT_NEAR_END,distance);
        if (farFade)
            irradiance *= 1.0-smoothstep(WATER_SHAFT_FAR_START,WATER_SHAFT_FAR_END,distance);
        light += weights[i]*irradiance;
    }
    return light;
}
vec4 water_shafts_march(vec2 uv, out vec3 viewPos, out float marchLength) {
    float rayLength, sceneDepth;
    uint sceneFlags;
    viewPos = water_shafts_view(uv,rayLength,sceneDepth,sceneFlags);
    vec3 viewOrigin = water_shafts_view_origin();
    vec3 worldOrigin = waterShaftWorldOrigin;
    vec3 ray = normalize(view_player(viewPos-viewOrigin));
    // Derivatives must be evaluated before per-pixel hand/depth early returns.
    vec3 rayDx = dFdx(ray), rayDy = dFdy(ray);
    marchLength = min(rayLength,min(astraWaterShaftRange,WATER_SHAFT_FAR_END));
    vec4 empty = vec4(vec3(0.0),rayLength/WATER_SHAFT_MAX_DISTANCE);
    if (sceneFlags != WATER_SCENE_FLAGS_UNSET && (sceneFlags & 128u) != 0u) return empty;
    #if !defined WATER_WAVES || WATER_WAVE_HEIGHT == 0
    return empty;
    #endif
    if (waterShaftSource.w <= 0.0 || waterShaftSurface.y < 0.5) return empty;
    vec3 source = waterShaftSource.xyz;
    float depth = waterShaftSurface.x-worldOrigin.y;
    if (ray.y > 0.0001) marchLength = min(marchLength,depth/ray.y);
    float begin = WATER_SHAFT_NEAR_START, end = marchLength;
    // ITT's projection onto the light-facing wave plane, referenced to the
    // CURRENT real water height. Camera rotation only changes the observed ray.
    vec3 entry = worldOrigin+source*(depth/source.y);
    vec3 entryRay = ray-source*(ray.y/source.y);
    vec2 absoluteEntry = cameraPosition.xz+entry.xz;
    if (!water_shaft_wave_segment(absoluteEntry,entryRay.xz,begin,end)) return empty;
    vec2 localEntry = absoluteEntry-waterShaftFieldOrigin;
    // Both paths are straight in homogeneous shadow space. Project their
    // origins and directions once; keep division, distortion and all shadow
    // comparisons at each node's actual point. Direction W stays zero before
    // projection, so translated and non-unit-W matrices remain supported.
    vec4 shadowOrigin = shadowProjection*(shadowModelView*vec4(worldOrigin,1.0));
    vec4 shadowRay = shadowProjection*(shadowModelView*vec4(ray,0.0));
    vec4 shadowEntry = shadowProjection*(shadowModelView*vec4(entry-vec3(0.0,0.18,0.0),1.0));
    vec4 shadowEntryRay = shadowProjection*(shadowModelView*vec4(entryRay,0.0));
    // Blue previously lost almost no light (0.00016/block at density 40), so
    // longer, deeper rays accumulated radiance without appreciable extinction.
    // Incoming light and the camera leg have different lengths below. Retain
    // spectral absorption, with neutral out-scattering in every channel.
    vec3 incidentExtinction = water_absorption_coefficient()
        + vec3(0.025)*(UNDERWATER_FOG_DENSITY*0.025);
    vec3 viewExtinction = water_absorption_coefficient()
        + vec3(0.012)*(UNDERWATER_FOG_DENSITY*0.025);
    float incidentPath = depth/source.y;
    float stepLength = min(astraWaterShaftRange,WATER_SHAFT_FAR_END)/float(ASTRA_SHAFT_SAMPLES);
    const vec4 nodes = vec4(0.0694318442,0.3300094782,0.6699905218,0.9305681558);
    const vec4 weights = vec4(0.1739274226,0.3260725774,0.3260725774,0.1739274226);
    vec2 projectedDx = rayDx.xz-source.xz*(rayDx.y/source.y);
    vec2 projectedDy = rayDy.xz-source.xz*(rayDy.y/source.y);
    float angularFootprint = max(length(projectedDx),length(projectedDy));
    float phase = water_shaft_phase(ray,source);
    vec3 integral = vec3(0.0);
    for (int interval=0;interval<ASTRA_SHAFT_SAMPLES;++interval) {
        float segmentBegin = max(float(interval)*stepLength,begin);
        float segmentEnd = min(float(interval+1)*stepLength,end);
        if (segmentEnd <= segmentBegin) {
            // Once the endpoint is behind this interval, every later interval
            // is empty too. Earlier intervals outside the field still advance.
            if (float(interval)*stepLength >= end) break;
            continue;
        }
        float segmentLength = segmentEnd-segmentBegin;
        float cellBegin = segmentBegin;
        for (int node=0;node<4;++node) {
                // Weight-sized cells tile the complete clipped interval once.
                // Shadow and spectral transport retain their original Gauss
                // locations; visibility is a constant approximation per cell.
                float cellLength = weights[node]*segmentLength;
                float waveBegin = cellBegin;
                cellBegin += cellLength;
                float distance = segmentBegin+nodes[node]*segmentLength;
                float visibility = water_shaft_path_visibility(worldOrigin+ray*distance,entry+entryRay*distance,
                    shadowEntry+shadowEntryRay*distance,shadowOrigin+shadowRay*distance);
                if (visibility <= 0.0) continue;
                float irradiance = water_shaft_wave_span(localEntry,entryRay.xz,
                    waveBegin,cellLength,angularFootprint);
                if (irradiance == 0.0) continue;
                float lightPath=max(incidentPath-ray.y*distance/source.y,0.0);
                vec3 transmission = exp(-incidentExtinction*lightPath-viewExtinction*distance);
                // The complete integration is bounded to 26 blocks, so the
                // original max(3.0,distance*0.1) is always exactly 3.0 here.
                integral += transmission*(irradiance*visibility*cellLength);
        }
    }
    // One phase and normalization belong to the complete ray, rather than
    // being multiplied into each of its up to 28 visibility-node weights.
    integral *= waterShaftIllumination*(phase/3.0);
    return vec4(max(integral,vec3(0.0)),rayLength/WATER_SHAFT_MAX_DISTANCE);
}
#else
vec3 water_shafts_resolve(sampler2D shaftMap, vec2 uv, float rayLength, uint sceneFlags) {
    // Reject the full-resolution hand even if the coarse scattering footprint
    // missed it. Material flags were already read with this endpoint's depth.
    if (sceneFlags != WATER_SCENE_FLAGS_UNSET && (sceneFlags & 128u) != 0u)
        return vec3(0.0);
    ivec2 size = textureSize(shaftMap, 0);
    vec2 edge = 0.5/vec2(size);
    vec2 boundedUV = clamp(uv,edge,1.0-edge);
    float referenceLength = min(clamp(rayLength, 0.0, WATER_SHAFT_MAX_DISTANCE), astraWaterShaftRange);
    // A neighbouring long low-resolution ray cannot light an endpoint inside
    // the same camera clearance used by the producer.
    if (referenceLength <= WATER_SHAFT_NEAR_START) return vec3(0.0);
#ifdef ASTRA_OVERWORLD_OPTIMIZED
    // All producer alphas are capped to the exact 48/128 FP16 marker. A linear
    // read can equal it only when every contributing texel covers the complete
    // window (apart from zero-weight contributors). No nonlinear decode follows.
    if (referenceLength >= astraWaterShaftRange) {
        vec4 volumeSample = textureLod(shaftMap,boundedUV,0.0);
        if (volumeSample.a == astraWaterShaftRange/WATER_SHAFT_MAX_DISTANCE)
            return max(volumeSample.rgb,vec3(0.0));
    }
#endif
    vec2 position = boundedUV*vec2(size)-0.5;
    ivec2 base = ivec2(floor(position));
    vec2 fraction = fract(position);
    vec3 radiance = vec3(0.0);
    float weights = 0.0;
    // Radiance uses a bilinear footprint. Keep each corner's own endpoint to
    // reject geometry discontinuities before combining the volume.
    for (int y=0;y<2;++y) for (int x=0;x<2;++x) {
        vec2 axis = mix(1.0-fraction,fraction,bvec2(x==1,y==1));
        float spatialWeight = axis.x*axis.y;
        if (spatialWeight <= 0.0) continue;
        vec4 tap = texelFetch(shaftMap,clamp(base+ivec2(x,y),ivec2(0),size-1),0);
        float delta = abs(min(tap.a*WATER_SHAFT_MAX_DISTANCE,astraWaterShaftRange)-referenceLength);
        float depthWeight = max(1.0-delta*0.25,0.0);
        float weight = spatialWeight*depthWeight*depthWeight;
        radiance += tap.rgb*weight;
        weights += weight;
    }
    // Very weak endpoint support must fade out rather than amplify a single
    // almost-rejected bright tap back to full intensity on a moving silhouette.
    return max(radiance/max(weights,0.25),vec3(0.0))
         * smoothstep(WATER_SHAFT_NEAR_START,WATER_SHAFT_NEAR_END,referenceLength);
}
#endif
#endif
