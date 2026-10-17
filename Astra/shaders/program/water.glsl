#ifndef ASTRA_PROGRAM_WATER_GLSL
#define ASTRA_PROGRAM_WATER_GLSL
// SC-34 follow-up: colour, depth, interface side and path length are inseparable.
// Above water uses Steadfast Fresnel and refraction; the underwater interface
// uses ITT waves and sky-window optics, with every mixture in linear light.
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot:
// historical translucent.glsl composition adaptation. Source at
// _analysis/Steadfast-0.8.0/shaders/environment/lighting/translucent.glsl.
// This derivative retains GPL-3.0-or-later and its Section 7 terms; see
// Astra/LICENSE and THIRD-PARTY.md. Dielectric and path reconstruction below
// remain for non-water transparent surfaces.
#include "/global/water/surface.glsl"
#include "/global/water/raytrace.glsl"
#include "/global/water/refraction.glsl"
#include "/lib/celestial_sprite.glsl"
uniform sampler2D colortex4;
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
uniform sampler2D colortex28;
flat in vec3 waterGlintRadiance;
#include "/lib/water_entity_record.glsl"
#endif
// Scene filtering below applies the overworld budget after endpoint selection.
// Its smaller footprint keeps body depth, interface side and C*T+S together.

// Discontinuous footprints transport each tap BEFORE combining it. Coherent
// footprints may share a matching anchor's transfer after geometric acceptance;
// silhouettes never associate bilinear RGB with the farthest of four depths.
// A reflection cone uses a centre-inclusive Gaussian footprint and may span
// different visible objects. Empty taps keep their sky-fallback coverage.
//
// SC-35: scene queries pair the deferred opaque colour copy with depthtex1, the
// depth snapshot that excludes translucent geometry. depthtex0 includes the
// translucent layer and can therefore return the water surface being shaded.
// Returns a soft validity in [0,1]: taps crossing the interface fade out over a
// two-centimetre reconstruction band instead of a binary cut. A rejected
// refracted hit blends to the unshifted opaque path in astra_water(), never
// directly to a saturated deep-water colour.
float water_side_acceptance(float side, vec3 point, vec3 origin, vec3 faceNormal) {
    return smoothstep(-0.02, 0.02, side * dot(point - origin, faceNormal));
}
vec3 water_reflected_direction(vec3 incident, vec3 normal, vec3 faceNormal) {
    vec3 ray = reflect(incident,normal);
    float facing = dot(ray,faceNormal);
    #if defined DIMENSION_NETHER || defined DIMENSION_END
    if (facing <= 0.0) ray = reflect(incident,faceNormal);
    #else
    // A wave normal can put a grazing ray on the wrong geometric side. Keep
    // its tangential direction and approach the horizon continuously instead
    // of abruptly replacing the entire direction with the flat-face mirror.
    if (facing < 0.001)
        ray = normalize(ray+faceNormal*(0.001-facing));
    #endif
    return ray;
}

// Absorption depth for a surface seen from air: the perpendicular distance from the
// water face's OWN plane to the background hit. On a top face that is the real water
// column and unbounded; on a side face the same dot is just the camera-to-background
// distance, so looking across a canal absorbed it as if the whole view were water.
// A water block only renders a side face when the neighbour along that normal is not
// water, so the slab along that normal is at most one block. Steadfast 0.8.0 bounds the
// same quantity with a skylight proxy (absorption_refraction.glsl: (1 - skylight/16)
// blocks); this reaches the same range from geometry alone, without a third buffer.
// faceNormal is the unit, camera-facing geometric normal in view axes.
// topSurface is classified once for the complete filtering footprint.
float water_surface_absorption_depth(vec3 origin, vec3 point, vec3 faceNormal, bool topSurface) {
    float depth = dot(origin - point, faceNormal);
    return topSurface ? depth : min(depth, 1.0);
}
// Deferred's colour snapshot can precede entity draws. Select a receiver once,
// keeping its raw radiance and linear view depth together on the same raster ray.
// The late record also covers opaque entity programs, not just skin features.
void water_scene_endpoint_position(ivec2 pixel, ivec2 size, float depth,
                                   float entityDepth, out vec3 point,
                                   out float chosenEntityDepth) {
    chosenEntityDepth = 0.0;
    if (depth >= 0.999999 && entityDepth <= 0.0) {
        point = vec3(0.0);
        return;
    }
    vec2 pixelUV = (vec2(pixel)+0.5)/vec2(size);
    point = water_screen_view(vec3(pixelUV,min(depth,0.999999)));
    float tolerance = max(0.004,entityDepth*0.0005);
    if (entityDepth > 0.0 && (depth >= 0.999999 || entityDepth <= -point.z+tolerance)) {
        // Keep the selected entity colour on this same raster ray. Scaling
        // around zero displaced its endpoint when projection bobbing moved the eye.
        vec3 eye = projection_view_origin();
        vec3 ray = point - eye;
        if (abs(ray.z) > 0.000001) {
            float travel = (-entityDepth - eye.z) / ray.z;
            if (travel > 0.0) {
                point = eye + ray * travel;
                chosenEntityDepth = entityDepth;
            }
        }
    }
}
void water_scene_endpoint(ivec2 pixel, ivec2 size, float depth,
                          float knownEntityDepth, out vec3 point, out vec4 entity) {
    entity = vec4(0.0);
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Zero from a packed-depth gather proves the cell contains no entity record.
    // Positive values and the negative unknown sentinel need its RGB payload.
    vec4 record = knownEntityDepth == 0.0 ? vec4(0.0)
        : water_entity_decode(texelFetch(colortex28,pixel,0).rg);
    float chosenEntityDepth;
    water_scene_endpoint_position(pixel,size,depth,record.a,point,chosenEntityDepth);
    if (chosenEntityDepth > 0.0) entity = record;
    #else
    float unusedEntityDepth;
    water_scene_endpoint_position(pixel,size,depth,0.0,point,unusedEntityDepth);
    #endif
}
void water_scene_endpoint(ivec2 pixel, ivec2 size, float depth,
                          out vec3 point, out vec4 entity) {
    water_scene_endpoint(pixel,size,depth,-1.0,point,entity);
}
vec3 water_scene_color(ivec2 pixel, vec4 entity) {
    return entity.a > 0.0 ? entity.rgb : texelFetch(colortex4,pixel,0).rgb;
}
// pairedEntityDepth forwards the caller's own texel entity view depth whenever
// the query accepted that same texel, so the paired transmission can skip its
// colortex28 fetch. -1 means the accepted texel is a different one and the
// record must be read there. The saving is one fetch, and only when the accepted
// texel is the caller's own AND that texel's entity depth is zero: a nonzero
// depth still needs its colour read. The zero-displacement case returns from
// this wrapper before the colortex28 probe, so it carries -1 and the paired
// transmission fetches normally, exactly as before this parameter existed.
vec2 water_refracted_scene_uv(vec3 viewPos, vec3 incident, vec3 normalDelta, vec2 rasterUV,
                              out float acceptedDepth, out float pairedEntityDepth) {
    acceptedDepth = -1.0;
    pairedEntityDepth = -1.0;
    if (REFRACTION_STRENGTH == 0 || dot(normalDelta,normalDelta) <= 0.0) return rasterUV;
    float entityViewDepth = -1.0;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    ivec2 size = textureSize(colortex28,0);
    ivec2 pixel = clamp(ivec2(rasterUV*vec2(size)),ivec2(0),size-1);
    entityViewDepth = water_entity_depth(texelFetch(colortex28,pixel,0).g);
    #endif
    return water_refracted_uv(depthtex1,viewPos,incident,normalDelta,rasterUV,entityViewDepth,
                             acceptedDepth,pairedEntityDepth);
}
vec2 water_refracted_scene_uv(vec3 viewPos, vec3 normalDelta, vec2 rasterUV,
                              out float acceptedDepth) {
    acceptedDepth = -1.0;
    if (REFRACTION_STRENGTH == 0 || dot(normalDelta,normalDelta) <= 0.0) return rasterUV;
    float unusedEntityDepth;
    return water_refracted_scene_uv(viewPos,normalize(viewPos),normalDelta,rasterUV,acceptedDepth,
                                    unusedEntityDepth);
}
vec2 water_refracted_scene_uv(vec3 viewPos, vec3 normalDelta, vec2 rasterUV) {
    float unusedDepth;
    return water_refracted_scene_uv(viewPos,normalDelta,rasterUV,unusedDepth);
}
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
// An anisotropic lobe in world-space reflection angles. The long axis lies in
// the light/normal plane, so perspective stretches the image along the water
// toward the source. The 3/2 longitudinal profile tapers its ends; wave normals
// supply the natural motion rather than a screen-aligned ellipse.
float water_source_glint(vec3 reflected, vec3 source, vec3 geometric, float roughness) {
    float alignment = dot(reflected,source);
    if (alignment <= 0.70) return 0.0;
    vec3 across;
    if (all(equal(geometric.xz,vec2(0.0)))) {
        // Reversing the horizontal face reverses both axes; the squared/absolute
        // profiles below are invariant. Share the frame's already unit axis.
        across = vec3(astraWaterGlintFrame.x,0.0,astraWaterGlintFrame.y);
    } else {
        across = cross(geometric,source);
        float axisSquared = dot(across,across);
        across = axisSquared > 1e-8 ? across*inversesqrt(axisSquared) : vec3(1.0,0.0,0.0);
    }
    vec3 along = cross(source,across);
    vec3 difference = reflected-source;
    float softness = clamp(roughness*6.0,0.0,1.0);
    float x = dot(difference,across)/mix(0.055,0.090,softness);
    float y = abs(dot(difference,along))/mix(0.21,0.34,softness);
    return exp(-(x*x+y*sqrt(y))) * smoothstep(0.70,0.95,alignment);
}
#endif
// Carry the same actual endpoint through absorption and detail softening.
// Thin vertical sheets retain their short path and their late-entity colour.
void water_surface_path_transfer(vec3 origin, vec3 endpoint, vec3 faceNormal,
                                 bool topSurface, float receiverDistance, vec3 incidentLight,
                                 out vec3 transmission, out vec3 scattering) {
    float haze = topSurface
        ? astra_water_surface_haze(length(endpoint - origin), receiverDistance) : 0.0;
    water_surface_transfer(water_surface_absorption_depth(origin, endpoint, faceNormal, topSurface),
                           incidentLight, haze, transmission, scattering);
}
// A path is affine in radiance: C*T+S. Keep the endpoint that produced both
// terms; raw late-entity radiance uses this SAME transfer, never bypasses water.
void water_scene_path_transfer(vec3 origin, vec3 endpoint, vec3 faceNormal,
                               bool inWater, bool inAir, bool topSurface,
                               float receiverDistance, vec3 incidentLight, float skylight,
                               out vec3 transmission, out vec3 scattering) {
    transmission = vec3(1.0);
    scattering = vec3(0.0);
    if (inWater) {
        if (isEyeInWater == 0) {
            water_surface_path_transfer(origin,endpoint,faceNormal,topSurface,receiverDistance,
                                        incidentLight,transmission,scattering);
        } else {
            vec3 extinction = water_extinction();
            transmission = exp(-max(length(endpoint-origin),0.0)*extinction);
            scattering = incidentLight*water_scattering_coefficient()
                       / max(extinction,vec3(0.000001))*(1.0-transmission);
        }
    } else if (inAir) {
        // The underwater display owns camera blindness for the complete scene.
        if (isEyeInWater == 1 && blindness > 0.0001) return;
        #ifdef ASTRA_VOLUME_FOG
        if (blindness <= 0.0001) {
            vec4 volume = astra_volume_path_medium(view_camera_relative(origin),
                                                   view_camera_relative(endpoint));
            volume = astra_volume_border(volume,length(endpoint-origin));
            transmission = vec3(volume.a);
            scattering = volume.rgb;
            return;
        }
        #endif
        vec4 fog = astra_air_fog(view_player(endpoint-origin),skylight,
                            cameraPosition.y+view_camera_relative(endpoint).y);
        transmission = vec3(1.0-fog.a);
        scattering = fog.rgb*fog.a;
    }
}

// Horizontal-bed transmission from an air camera reads ONE pixel: colour, depth
// and entity selection stay paired at that texel, with one medium transfer for
// its accepted endpoint. This replaces the former 2x2 footprint transport in
// every build, so the overworld budget no longer needs a separate route.
// knownAnchorEntityDepth is the late-body view depth for that same texel: 0
// proves no record and skips the colortex28 fetch, -1 means unknown.
float water_transmission_sample(vec2 uv, vec3 origin, vec3 faceNormal, float skylight,
                                float knownAnchorDepth, float knownAnchorEntityDepth,
                                out vec3 radiance) {
    radiance = vec3(0.0);
    ivec2 size = textureSize(depthtex1,0);
    if (any(lessThan(uv,vec2(0.0))) || any(greaterThanEqual(uv,vec2(1.0)))) return 0.0;
    ivec2 anchorPixel = ivec2(uv*vec2(size));
    float depth = knownAnchorDepth >= 0.0 ? knownAnchorDepth : texelFetch(depthtex1,anchorPixel,0).r;
    vec3 endpoint;
    vec4 entity;
    water_scene_endpoint(anchorPixel,size,depth,knownAnchorEntityDepth,endpoint,entity);
    if (depth >= 0.999999 && entity.a <= 0.0) return 0.0;
    float acceptance = water_side_acceptance(-1.0,endpoint,origin,faceNormal);
    if (acceptance <= 0.0) return 0.0;
    float receiverDistance = length(origin);
    vec3 incidentLight = astra_water_incident(skylight);
    vec3 transmission,scattering;
    water_surface_path_transfer(origin,endpoint,faceNormal,true,receiverDistance,
                                incidentLight,transmission,scattering);
    radiance = water_scene_color(anchorPixel,entity)*transmission+scattering;
    return acceptance;
}
float water_transmission_sample(vec2 uv, vec3 origin, vec3 faceNormal, float skylight,
                                float knownAnchorDepth, out vec3 radiance) {
    return water_transmission_sample(uv,origin,faceNormal,skylight,knownAnchorDepth,-1.0,
                                     radiance);
}
// The overworld budget uses one continuous 2x2 footprint at a reflection hit
// instead of five separate 2x2 cones. Sharp water keeps its object reflection;
// its broad microfacet blur is approximated by this small footprint. Raw tiers
// retain their cone. Each accepted corner still owns colour, depth and
// interface side.
// Steadfast's accepted-footprint/single-colour structure, with Astra's optical
// bounds and late-body protection. Continuous water and air paths reconstruct
// four endpoints with shared inverse-projection terms;
// each corner keeps its own raw depth, never a filtered synthetic depth.
#ifdef ASTRA_OVERWORLD_OPTIMIZED
bool water_surface_fast_sample(vec2 uv, ivec2 size, vec3 origin, vec3 faceNormal,
                               bool airReflection, bool submergedReflection, bool airTransmission,
                               float receiverDistance, float skylight, inout vec4 depths,
                               out vec4 entityRecords, out vec4 points[4],
                               out bool pointsValid, out vec3 radiance) {
    entityRecords = vec4(-1.0);
    pointsValid = false;
    radiance = vec3(0.0);
    vec2 location = uv*vec2(size)-0.5;
    ivec2 corner = ivec2(floor(location));
    if (any(lessThan(corner,ivec2(0))) || any(greaterThanEqual(corner+ivec2(1),size)))
        return false;
    vec2 gatherUV = (vec2(corner)+1.0)/vec2(size);
    if (depths.x < 0.0) depths = textureGather(depthtex1,gatherUV,0).wzxy;
    entityRecords = textureGather(colortex28,gatherUV,1).wzxy;
    // Any body/skin record or sky corner keeps the paired general path.
    if (any(notEqual(entityRecords,vec4(0.0))) || any(greaterThanEqual(depths,vec4(0.999999))))
        return false;
    vec2 ndc = ((vec2(corner)+0.5)/vec2(size)-astra_jitter_uv())*2.0-1.0;
    const vec4 x = vec4(0.0,1.0,0.0,1.0);
    const vec4 y = vec4(0.0,0.0,1.0,1.0);
    vec4 px,py,pz;
    #ifdef ASTRA_WATER_PASS
    if ((waterProjectionFlags & 8) != 0) {
        // The vertex stage proved these inverse-matrix cross terms are zero.
        // Reconstruct all four actual depths without four general XY/Z/W sums.
        vec4 z = depths*2.0-1.0;
        vec4 w = gbufferProjectionInverse[2].w*z+gbufferProjectionInverse[3].w;
        if (any(lessThanEqual(w,vec4(0.000001)))) return false;
        vec4 inverseW = 1.0/w;
        px = (gbufferProjectionInverse[0].x*(vec4(ndc.x)+x*(2.0/float(size.x)))
            +gbufferProjectionInverse[2].x*z+gbufferProjectionInverse[3].x)*inverseW;
        py = (gbufferProjectionInverse[1].y*(vec4(ndc.y)+y*(2.0/float(size.y)))
            +gbufferProjectionInverse[2].y*z+gbufferProjectionInverse[3].y)*inverseW;
        pz = (gbufferProjectionInverse[2].z*z+gbufferProjectionInverse[3].z)*inverseW;
    } else
    #endif
    {
        vec4 base = gbufferProjectionInverse*vec4(ndc,-1.0,1.0);
        vec4 stepX = gbufferProjectionInverse[0]*(2.0/float(size.x));
        vec4 stepY = gbufferProjectionInverse[1]*(2.0/float(size.y));
        vec4 depthOffset = depths*2.0;
        vec4 w = vec4(base.w)+stepX.w*x+stepY.w*y+gbufferProjectionInverse[2].w*depthOffset;
        if (any(lessThanEqual(w,vec4(0.000001)))) return false;
        vec4 inverseW = 1.0/w;
        px = (vec4(base.x)+stepX.x*x+stepY.x*y+gbufferProjectionInverse[2].x*depthOffset)*inverseW;
        py = (vec4(base.y)+stepX.y*x+stepY.y*y+gbufferProjectionInverse[2].y*depthOffset)*inverseW;
        pz = (vec4(base.z)+stepX.z*x+stepY.z*y+gbufferProjectionInverse[2].z*depthOffset)*inverseW;
    }
    vec4 column = vec4(dot(origin,faceNormal))-(px*faceNormal.x+py*faceNormal.y+pz*faceNormal.z);
    if (airReflection || submergedReflection) column=-column;
    float columnMin = min(min(column.x,column.y),min(column.z,column.w));
    float columnMax = max(max(column.x,column.y),max(column.z,column.w));
    float tolerance = min(0.02,0.01/max(float(WATER_ABSORPTION)*0.01,0.05));
    vec2 f=fract(location);
    vec4 weights=vec4((1.0-f.x)*(1.0-f.y),f.x*(1.0-f.y),(1.0-f.x)*f.y,f.x*f.y);
    #ifndef ASTRA_VOLUME_FOG
    if ((airReflection || airTransmission) && columnMin>=0.02) {
        // Air paths share one transfer only for a continuous depth
        // footprint with no late body record. Silhouettes retain paired taps.
        float depthRange=max(max(pz.x,pz.y),max(pz.z,pz.w))
                        -min(min(pz.x,pz.y),min(pz.z,pz.w));
        float maximumRange = airTransmission ? 0.06 : 0.12;
        if (depthRange <= maximumRange) {
            vec3 endpoint=vec3(dot(px,weights),dot(py,weights),dot(pz,weights));
            float path=length(endpoint-origin);
            float depthLimit = airTransmission ? min(0.06,0.015+path*0.0005)
                                               : min(0.12,0.03+path*0.001);
            if (depthRange<=depthLimit) {
                vec3 transmission,scattering;
                water_scene_path_transfer(origin,endpoint,faceNormal,false,true,false,
                    0.0,vec3(0.0),skylight,transmission,scattering);
                radiance=textureLod(colortex4,uv,0.0).rgb*transmission+scattering;
                return true;
            }
        }
    }
    #endif
    if (submergedReflection && columnMin >= 0.02) {
        float depthRange=max(max(pz.x,pz.y),max(pz.z,pz.w))
                        -min(min(pz.x,pz.y),min(pz.z,pz.w));
        // No path can raise the continuity limit above 0.12. Reject depth
        // breaks before computing lengths; only the two extrema need sqrt.
        if (depthRange <= 0.12) {
            vec4 dx=px-origin.x, dy=py-origin.y, dz=pz-origin.z;
            vec4 pathSquared=dx*dx+dy*dy+dz*dz;
            float shortest=sqrt(min(min(pathSquared.x,pathSquared.y),min(pathSquared.z,pathSquared.w)));
            float longest=sqrt(max(max(pathSquared.x,pathSquared.y),max(pathSquared.z,pathSquared.w)));
            vec3 extinction=water_extinction();
            // Share homogeneous water transport only when all actual corner paths
            // differ from their midpoint by less than 0.2% transmission;
            // silhouettes retain own taps. The full path range is twice this bound.
            if (depthRange <= min(0.12,0.03+shortest*0.001)
                && (longest-shortest)*max(max(extinction.r,extinction.g),extinction.b) <= 0.004) {
                vec3 transmission=exp(-0.5*(shortest+longest)*extinction);
                vec3 scattering=astra_water_incident(skylight)*water_scattering_coefficient()
                    /max(extinction,vec3(0.000001))*(1.0-transmission);
                radiance=textureLod(colortex4,uv,0.0).rgb*transmission+scattering;
                return true;
            }
        }
    }
    if (!airReflection && !submergedReflection && !airTransmission
        && columnMin >= 0.02 && columnMax-columnMin <= tolerance) {
        vec4 dx = px-origin.x, dy = py-origin.y, dz = pz-origin.z;
        vec4 pathSquared = dx*dx+dy*dy+dz*dz;
        float hazeMin = astra_water_surface_haze(sqrt(min(min(pathSquared.x,pathSquared.y),
                                                         min(pathSquared.z,pathSquared.w))),receiverDistance);
        float hazeMax = astra_water_surface_haze(sqrt(max(max(pathSquared.x,pathSquared.y),
                                                         max(pathSquared.z,pathSquared.w))),receiverDistance);
        if (hazeMax-hazeMin <= 0.002*(1.0-hazeMax)) {
            vec3 transmission, scattering;
            water_surface_transfer(dot(column,weights),astra_water_incident(skylight),
                                   0.5*(hazeMin+hazeMax),transmission,scattering);
            radiance = textureLod(colortex4,uv,0.0).rgb*transmission+scattering;
            return true;
        }
    }
    // Only failed sharing consumes these records. The accepted continuous bed
    // returns before constructing four fallback records and side fade values.
    // Retain the original absolute endpoints for every failed optical check.
    for (int tap=0;tap<4;++tap)
        points[tap] = vec4(px[tap],py[tap],pz[tap],smoothstep(-0.02,0.02,column[tap]));
    pointsValid = true;
    return false;
}
#endif
float water_sample_path(vec2 uv, vec3 origin, vec3 faceNormal, bool reflected,
                        bool inWater, float radius, float skylight,
                        float knownAnchorDepth, vec4 knownFootprint, out vec3 radiance) {
    bool topSurface = inWater && isEyeInWater == 0 && view_player(faceNormal).y > 0.9;
    radiance = vec3(0.0);
    ivec2 size = textureSize(depthtex1,0);
    if (any(lessThan(uv,vec2(0.0))) || any(greaterThanEqual(uv,vec2(1.0))))
        return 0.0;
    ivec2 anchorPixel = ivec2(uv*vec2(size));
    vec2 anchorUV = (vec2(anchorPixel)+0.5)/vec2(size);
    // One camera distance serves the continuous surface and every paired fallback.
    // Other paths do not consume it.
    float receiverDistance = topSurface ? length(origin) : 0.0;
    bool airReflection=reflected && !inWater && isEyeInWater==0;
    bool submergedReflection=reflected && inWater && isEyeInWater==1;
    bool airTransmission=!reflected && !inWater && isEyeInWater==1;
    vec4 firstDepths = knownFootprint, firstEntityRecords = vec4(-1.0);
    vec4 points[4];
    bool firstPointsValid = false;
    #ifdef ASTRA_OVERWORLD_OPTIMIZED
    if (((topSurface && !reflected) || airReflection || submergedReflection || airTransmission)
        && any(notEqual(uv,anchorUV))
        && water_surface_fast_sample(uv,size,origin,faceNormal,airReflection,submergedReflection,airTransmission,receiverDistance,skylight,
                                     firstDepths,firstEntityRecords,points,
                                     firstPointsValid,radiance)) return 1.0;
    #endif
    vec2 firstLocation = uv*vec2(size)-0.5;
    ivec2 firstCorner = ivec2(floor(firstLocation));
    ivec2 anchorCorner = anchorPixel-firstCorner;
    int anchorIndex = anchorCorner.x+2*anchorCorner.y;
    float anchorDepth = knownAnchorDepth >= 0.0
        ? knownAnchorDepth : (firstDepths.x >= 0.0 ? firstDepths[anchorIndex]
                                                 : texelFetch(depthtex1,anchorPixel,0).r);
    vec3 anchor;
    vec4 anchorEntity;
    float knownEntityDepth = -1.0;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    if (firstEntityRecords.x >= 0.0)
        knownEntityDepth = water_entity_depth(firstEntityRecords[anchorIndex]);
    #endif
    if (firstPointsValid) {
        anchor = points[anchorIndex].xyz;
        anchorEntity = vec4(0.0);
    } else {
        water_scene_endpoint(anchorPixel,size,anchorDepth,knownEntityDepth,anchor,anchorEntity);
    }
    bool anchorValid = anchorDepth < 0.999999 || anchorEntity.a > 0.0;
    float side = reflected ? 1.0 : -1.0;
    float anchorSide = anchorValid ? water_side_acceptance(side,anchor,origin,faceNormal) : 0.0;
    // A rejected nearest texel does not reject its bilinear neighbours. Each
    // accepted corner below keeps its own endpoint, colour and medium transfer.
    vec3 incidentLight = inWater ? astra_water_incident(skylight) : vec3(0.0);
    // This secondary leg is in air even when the eye itself is underwater.
    bool inAir = !inWater;
    vec3 anchorTransmission = vec3(0.0), anchorScattering = vec3(0.0);
    #ifdef ASTRA_OVERWORLD_OPTIMIZED
    // Surface transport depends on water-column depth and actual path haze,
    // not the lateral distance between two points on the same submerged floor.
    // Compute these once for the anchor, including late-body anchors.
    float anchorColumn = 0.0, anchorHaze = 0.0;
    if (anchorSide > 0.0 && topSurface) {
        anchorColumn = max(water_surface_absorption_depth(origin,anchor,faceNormal,true),0.0);
        anchorHaze = astra_water_surface_haze(length(anchor-origin),receiverDistance);
        water_surface_transfer(anchorColumn,incidentLight,anchorHaze,
                               anchorTransmission,anchorScattering);
    } else
    #endif
    if (anchorSide > 0.0) water_scene_path_transfer(origin,anchor,faceNormal,inWater,inAir,topSurface,
                              receiverDistance,incidentLight,skylight,anchorTransmission,anchorScattering);
    #if WATER_EFFECT_QUALITY == 0 || defined ASTRA_OVERWORLD_OPTIMIZED
    const int maxFootprints = 1;
    #elif WATER_EFFECT_QUALITY == 2
    const int maxFootprints = 9;
    #else
    const int maxFootprints = 5;
    #endif
    int footprints = reflected && radius > 0.35 ? maxFootprints : 1;
    // An unshifted transmitted ray already has its exact paired endpoint.
    // A one-footprint reflected ray at that centre can use the same result.
    if (footprints == 1 && all(equal(uv,anchorUV))) {
        if (anchorSide <= 0.0) return 0.0;
        radiance = water_scene_color(anchorPixel,anchorEntity)*anchorTransmission+anchorScattering;
        return anchorSide;
    }
    // Terrain with matching transport may reuse the anchor's transfer. Body
    // corners and medium discontinuities always keep their own transfer; a
    // locally shadowed air volume cannot be inferred from a nearby endpoint.
    #if defined DIMENSION_NETHER || defined DIMENSION_END
    bool shareTransfer = false;
    #else
    bool shareTransfer = anchorSide >= 1.0;
    #endif
    #ifdef ASTRA_VOLUME_FOG
    if (inAir) shareTransfer = false;
    #endif
    float coherentRadius = inWater
        ? min(0.12,0.03/max(0.50*(WATER_ABSORPTION*0.01),0.05))
        : clamp(0.06+0.025*length(anchor-origin),0.06,0.75);
    float coherentRadiusSquared = coherentRadius*coherentRadius;
    #ifdef ASTRA_OVERWORLD_OPTIMIZED
    // One centimetre at 100% absorption, at most two at weaker settings.
    // Haze is compared relative to its remaining transmission below, so an
    // almost-opaque path cannot borrow a visibly clearer corner's transport.
    float columnTolerance = min(0.02,0.01/max(float(WATER_ABSORPTION)*0.01,0.05));
    #endif
    // A coherent footprint needs only its filtered RGB, without an unused
    // separate anchor fetch. Discontinuous footprints read the anchor once.
    vec3 anchorRadiance = vec3(0.0);
    bool anchorColorRead = false;
    float weights = 0.0, sideSum = 0.0;
    vec2 centreLocation = uv*vec2(size)-0.5;
    for (int cone=0;cone<maxFootprints;++cone) {
        if (cone >= footprints) break;
        ivec2 node = ivec2(cone%3,cone/3)-1;
        if (footprints == 5) {
            if (cone == 0) node = ivec2(0);
            else if (cone == 1) node = ivec2(-1,0);
            else if (cone == 2) node = ivec2(1,0);
            else if (cone == 3) node = ivec2(0,-1);
            else node = ivec2(0,1);
        }
        float spread = footprints == 5 ? 0.91855865 : 0.75;
        vec2 offset = footprints > 1 ? vec2(node)*radius*spread : vec2(0.0);
        bool centreFootprint = all(equal(offset,vec2(0.0)));
        float kernel = footprints > 1
            ? float((node.x==0 ? 2 : 1)*(node.y==0 ? 2 : 1)) : 1.0;
        vec2 location = centreLocation+offset;
        ivec2 corner = ivec2(floor(location));
        vec2 f = fract(location);
        bool inside = all(greaterThanEqual(corner,ivec2(0)))
                   && all(lessThan(corner+ivec2(1),size));
        vec4 depths = vec4(1.0), packedEntityDepths = vec4(-1.0);
        if (inside) {
            vec2 gatherUV = (vec2(corner)+1.0)/vec2(size);
            // Gather's native (01,11,10,00) is reordered ONCE to (00,10,01,11).
            depths = centreFootprint && firstDepths.x >= 0.0
                ? firstDepths : textureGather(depthtex1,gatherUV,0).wzxy;
            #if !defined DIMENSION_NETHER && !defined DIMENSION_END
            packedEntityDepths = centreFootprint && firstEntityRecords.x >= 0.0
                ? firstEntityRecords : textureGather(colortex28,gatherUV,1).wzxy;
            #endif
        }
        // Keep only the chosen entity depths across the two loops. Four live
        // RGBA records otherwise inflate registers for every terrain pixel.
        vec4 chosenEntityDepths = vec4(0.0);
        vec4 cornerWeights = vec4((1.0-f.x)*(1.0-f.y),f.x*(1.0-f.y),
                                  (1.0-f.x)*f.y,f.x*f.y);
        bool sameTransport = shareTransfer && inside && anchorEntity.a <= 0.0;
        for (int tap=0;tap<4;++tap) {
            bool cachedPoint = centreFootprint && firstPointsValid;
            if (!cachedPoint) points[tap] = vec4(0.0);
            if (cornerWeights[tap] <= 0.0) continue;
            ivec2 pixel = corner+ivec2(tap%2,tap/2);
            if (any(lessThan(pixel,ivec2(0))) || any(greaterThanEqual(pixel,size))) {
                sameTransport = false;
                continue;
            }
            bool anchorSample = all(equal(pixel,anchorPixel));
            float entityDepth = -1.0;
            #if !defined DIMENSION_NETHER && !defined DIMENSION_END
            // Zero-weight, cached and anchor corners need no record decoding.
            if (inside && !cachedPoint && !anchorSample)
                entityDepth = water_entity_depth(packedEntityDepths[tap]);
            #endif
            float depth = anchorSample ? anchorDepth
                : (inside ? depths[tap] : texelFetch(depthtex1,pixel,0).r);
            depths[tap] = depth;
            vec3 endpoint;
            vec4 entity;
            if (cachedPoint) {
                endpoint = points[tap].xyz;
                entity = vec4(0.0);
            } else if (anchorSample) {
                endpoint = anchor;
                entity = anchorEntity;
            } else if (entityDepth >= 0.0) {
                // The gather already supplied this entity's own linear depth.
                // Its colour is needed only after side/coverage acceptance in
                // the second loop, where the chosen record is read once.
                float chosenEntityDepth;
                water_scene_endpoint_position(pixel,size,depth,entityDepth,
                                               endpoint,chosenEntityDepth);
                entity = vec4(0.0,0.0,0.0,chosenEntityDepth);
            } else {
                water_scene_endpoint(pixel,size,depth,entityDepth,endpoint,entity);
            }
            chosenEntityDepths[tap] = entity.a;
            if (depth >= 0.999999 && entity.a <= 0.0) {
                sameTransport = false;
                continue;
            }
            float accept = cachedPoint ? points[tap].w : (anchorSample ? anchorSide
                : water_side_acceptance(side,endpoint,origin,faceNormal));
            points[tap] = vec4(endpoint,accept);
            if (sameTransport) {
                sameTransport = entity.a <= 0.0 && accept >= 1.0;
                if (sameTransport && !anchorSample) {
                    #ifdef ASTRA_OVERWORLD_OPTIMIZED
                    if (topSurface) {
                        float column = max(water_surface_absorption_depth(origin,endpoint,faceNormal,true),0.0);
                        sameTransport = abs(column-anchorColumn) <= columnTolerance;
                        if (sameTransport) {
                            float haze = astra_water_surface_haze(length(endpoint-origin),receiverDistance);
                            sameTransport = abs(haze-anchorHaze) <= 0.002*(1.0-max(haze,anchorHaze));
                        }
                    } else
                    #endif
                    {
                        vec3 separation = endpoint-anchor;
                        sameTransport = dot(separation,separation) <= coherentRadiusSquared;
                    }
                }
            }
        }
        if (sameTransport) {
            // All active corners are ordinary geometry with the same accepted
            // side and nearly identical transport. One colour read is sufficient.
            vec3 color = textureLod(colortex4,(location+0.5)/vec2(size),0.0).rgb;
            radiance += (color*anchorTransmission+anchorScattering)*kernel;
            weights += kernel;
            sideSum += kernel;
            continue;
        }
        if (!anchorColorRead && anchorSide > 0.0) {
            anchorRadiance = water_scene_color(anchorPixel,anchorEntity)*anchorTransmission+anchorScattering;
            anchorColorRead = true;
        }
        for (int tap=0;tap<4;++tap) {
            float geometricWeight = cornerWeights[tap]*kernel;
            if (geometricWeight <= 0.0) continue;
            // Rejected geometry/sky still owns its fraction of the footprint.
            // Transmission callers need that missing coverage for the sky
            // window or straight-path fallback, just as reflected rays do.
            sideSum += geometricWeight;
            ivec2 pixel = corner+ivec2(tap%2,tap/2);
            if (any(lessThan(pixel,ivec2(0))) || any(greaterThanEqual(pixel,size))) continue;
            if (depths[tap] >= 0.999999 && chosenEntityDepths[tap] <= 0.0) {
                if (reflected && !inWater) {
                    // Sky holes retain their own coverage between leaf silhouettes.
                    radiance += texelFetch(colortex4,pixel,0).rgb*geometricWeight;
                    weights += geometricWeight;
                }
                continue;
            }
            float accept = points[tap].w;
            if (accept <= 0.0) continue;
            float weight = geometricWeight*accept;
            vec3 color;
            if (all(equal(pixel,anchorPixel))) {
                color = anchorRadiance;
            } else {
                #if !defined DIMENSION_NETHER && !defined DIMENSION_END
                color = chosenEntityDepths[tap] > 0.0
                    ? water_entity_decode(texelFetch(colortex28,pixel,0).rg).rgb
                    : texelFetch(colortex4,pixel,0).rgb;
                #else
                color = texelFetch(colortex4,pixel,0).rgb;
                #endif
                vec3 transmission, scattering;
                water_scene_path_transfer(origin,points[tap].xyz,faceNormal,inWater,inAir,
                    topSurface,receiverDistance,incidentLight,skylight,transmission,scattering);
                color = color*transmission+scattering;
            }
            radiance += color*weight;
            weights += weight;
        }
    }
    if (weights < 0.00001) {
        radiance = anchorRadiance;
        return anchorSide;
    }
    radiance /= weights;
    return clamp(weights/max(sideSum,0.00001),0.0,1.0);
}
float water_sample_path(vec2 uv, vec3 origin, vec3 faceNormal, bool reflected,
                        bool inWater, float radius, float skylight,
                        float knownAnchorDepth, out vec3 radiance) {
    return water_sample_path(uv,origin,faceNormal,reflected,inWater,radius,skylight,
                             knownAnchorDepth,vec4(-1.0),radiance);
}
float water_sample_path(vec2 uv, vec3 origin, vec3 faceNormal, bool reflected,
                        bool inWater, float radius, float skylight, out vec3 radiance) {
    return water_sample_path(uv,origin,faceNormal,reflected,inWater,radius,skylight,
                             -1.0,radiance);
}
// ITT composite1/2: a water-to-air refracted sky window closes at total internal
// reflection. Retain Solas' colour domain, but use Astra's dielectric equations
// rather than its former capped Fresnel and fixed surface opacity.
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
vec4 astra_vertical_water_interface(vec3 playerPos, vec3 viewPos, vec3 normal, vec3 faceNormal,
                                    float skylight, float roughness) {
    bool submerged = isEyeInWater == 1;
    // Looking through a nearby stream from inside must not wobble the entire
    // background. Horizontal surfaces retain their separate wave/Snell path.
    if (submerged) normal = faceNormal;
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    #ifdef SCREENSPACE_REFRACTION
    if (!submerged)
        uv = water_refracted_scene_uv(viewPos,normal-faceNormal,uv);
    #endif
    vec3 transmitted;
    // Behind a falling sheet is air, not an arbitrarily deep water column.
    // Keep the existing paired colour/depth footprint and shoreline rejection.
    float validity = water_sample_path(uv, viewPos, faceNormal, false,
                                      false, 0.0, skylight, transmitted);
    if (validity < 1.0)
        transmitted = mix(max(textureLod(colortex4, uv, 0.0).rgb, vec3(0.0)), transmitted, validity);
    if (!submerged || water_is_thin_sheet()) {
        float waterLength = submerged ? min(length(viewPos), 1.0) : 1.0;
        transmitted = water_surface_medium(transmitted, waterLength, astra_water_incident(skylight));
    }
    // Both sheen and reflected radiance are zero without sky access.
    // Keep the transported background and the same camera medium.
    if (skylight <= 0.0)
        return vec4(astra_apply_medium(max(transmitted, vec3(0.0)), playerPos, skylight), 1.0);
    // Turbulent vertical block sheets use a small continuous sheen rather than
    // a planar critical-angle window. The horizontal ocean interface below
    // keeps its exact dielectric response and total reflection.
    vec3 incident = normalize(viewPos);
    float noV = clamp(dot(-incident, normal), 0.0, 1.0);
    float sheen = (0.025 + 0.075 * pow5(1.0 - noV)) * skylight;
    vec3 reflectedRay = water_reflected_direction(incident,normal,faceNormal);
    vec3 reflection = astra_reflection_sky(normalize(view_player(reflectedRay)), max(roughness, 0.08));
    reflection = astra_scene_highlights(reflection) * skylight;
    vec3 result = max(mix(transmitted, reflection, sheen), vec3(0.0));
    return vec4(astra_apply_medium(result, playerPos, skylight), 1.0);
}

// The reflection environment intentionally excludes celestial discs. A
// transmitted underwater sky needs its source on the actual refracted ray.
// Resource location is bound by Iris from the active Minecraft resource pack.
#if SUN_MOON_MODE == SUN_MOON_VANILLA
uniform sampler2D astraSunTexture;
#endif
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
flat in vec3 waterSunCentre;
#if SUN_MOON_MODE == SUN_MOON_VANILLA
flat in vec3 waterSunRight;
flat in vec3 waterSunVertical;
#endif
#endif
vec3 water_transmitted_sun(vec3 direction, float angularFootprint, float cloudTransmittance) {
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    vec3 centre=waterSunCentre;
    #else
    vec3 centre=normalize(worldSunVector);
    #endif
    float alignment=dot(direction,centre);
    // A finite sprite may remain above the horizon after its centre crosses it.
    // Continuous source visibility below owns the fade, as for the exterior sky.
    if (alignment<=0.0) return vec3(0.0);
    vec3 source;
    #if SUN_MOON_MODE == SUN_MOON_VANILLA
    // Minecraft's sun quad has half-size 30 at distance 100; lit.vsh scales
    // its X/Z axes by 1.12. Preserve the same exterior angular footprint and
    // orbit-oriented square, actual sprite texels and exterior light colour.
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    vec3 right=waterSunRight;
    vec3 vertical=waterSunVertical;
    #else
    vec3 right=vec3(0.0,sin(radians(sunPathRotation)),cos(radians(sunPathRotation)));
    right=normalize(right-centre*dot(right,centre));
    vec3 vertical=cross(right,centre);
    #endif
    vec2 spriteUV=vec2(dot(direction,right),dot(direction,vertical))/(0.672*alignment)+0.5;
    if (any(lessThan(spriteUV,vec2(0.0))) || any(greaterThan(spriteUV,vec2(1.0))))
        return vec3(0.0);
    vec4 sprite=astra_celestial_sprite(astraSunTexture,spriteUV);
    source=astra_scene_highlights(sprite.rgb
        *mix(vec3(2.0,1.90,1.65),vec3(2.0,1.28,0.56),astra_twilight_strength()))*sprite.a;
    #else
    const float radius=0.028;
    float edge=max(2e-6,angularFootprint*radius);
    float mask=smoothstep(cos(radius)-edge,cos(radius)+edge,alignment);
    if (mask<=0.0) return vec3(0.0);
    source=astra_scene_highlights(mix(vec3(8.0,7.0,5.2),
                            vec3(6.2,4.2,1.8),astra_twilight_strength()))*mask;
    #endif
    if (max(max(source.r,source.g),source.b)<=0.001) return vec3(0.0);
    float visibility=mix(1.0,0.25,astraRainFactor)*solas_sun_visibility();
    if (visibility == 0.0) return vec3(0.0);
    visibility*=cloudTransmittance;
    return source*visibility;
}

vec4 astra_underwater_interface(vec3 litWater, vec3 viewPos, vec3 normal, vec3 faceNormal,
                                float skylight, float angularFootprint) {
    vec3 incident = normalize(viewPos);
    // Iris supplies cameraPosition - player head in world axes. Use that actual
    // offset for the window centre; rotating a third-person camera must not
    // move the submerged player's optical anchor through the pool. Projection,
    // scene depth and the reflected geometric ray still use the real camera.
    // At a crossing, the head can be in air while the camera is submerged.
    // Keep the player's horizontal centre, using the camera's real water depth
    // for that case instead of moving the centre back onto the orbiting camera.
    vec3 headRay = viewPos + player_view(relativeEyePosition);
    float headDepth = dot(-headRay,faceNormal);
    float cameraDepth = max(dot(-viewPos,faceNormal),0.02);
    float windowDepth = mix(cameraDepth,max(headDepth,0.02),smoothstep(-0.08,0.20,headDepth));
    headRay -= faceNormal*(windowDepth-headDepth);
    vec3 windowIncident = normalize(headRay);
    bool totalReflection;
    float cosIncident = clamp(dot(-windowIncident,normal),0.0,1.0);
    float cosTransmitted;
    float fresnel = water_fresnel(cosIncident,WATER_IOR,totalReflection,cosTransmitted);
    // A small object-reflection lift keeps the critical angle and full TIR.
    fresnel=clamp(fresnel+0.012*(1.0-fresnel),0.0,1.0);
    vec3 reflectedRay = water_reflected_direction(incident,normal,faceNormal);
    // A missed underwater reflection sees the water medium, not an air sky
    // below the horizon. Only the secondary reflected leg is transported here;
    // the camera-to-interface leg still gets its shared composite fog once.
    vec3 reflection = vec3(0.0);
    float reflectionWeight = 0.0;
    // Normal-incidence reflections are weak on both sides of the surface.
    // Keep the full reflected scene near the critical angle and under total
    // internal reflection; let the existing water fallback carry weak angles.
    float screenReflectionShare = 1.0;
    #ifdef ASTRA_OVERWORLD_OPTIMIZED
    screenReflectionShare = totalReflection ? 1.0 : smoothstep(0.025,0.055,fresnel);
    #endif
    if (screenReflectionShare > 0.0) {
        vec4 hit = vec4(0.0);
        #ifdef UNDERWATER_SURFACE_REFLECTIONS
            hit = water_raytrace(depthtex1, viewPos, reflectedRay, faceNormal);
        #endif
        if (hit.a > 0.0) {
            // Transport each colour contributor with its own depth and water
            // leg, as above water. A bilinear colour plus one hit depth mixes
            // foreground/background extinction at submerged silhouettes.
            vec3 radiance;
            reflectionWeight = hit.a * screenReflectionShare
                * water_sample_path(hit.xy, viewPos, faceNormal,
                true, true, 0.0, skylight, hit.z, radiance);
            // A complete paired hit owns the full total-internal-reflection ray.
            if (totalReflection && reflectionWeight >= 1.0)
                return vec4(max(radiance,vec3(0.0)),1.0);
            if (reflectionWeight > 0.0)
                reflection = max(radiance,vec3(0.0));
        }
    }
    // Full-confidence geometry owns the reflected leg. Only misses / partial
    // hits need the long-water fallback. Every mixture stays in linear light.
    if (reflectionWeight < 1.0) {
        vec3 waterIncident = astra_water_incident(skylight);
        vec3 fallback = max(water_medium(litWater,48.0,waterIncident),vec3(0.0));
        reflection = mix(fallback,reflection,reflectionWeight);
    }
    if (totalReflection) return vec4(max(reflection,vec3(0.0)),1.0);
    // Fresnel already solved Snell's transmitted cosine. Reuse that root for
    // the same refracted ray instead of solving the interface a second time.
    vec3 refractedRay = WATER_IOR*windowIncident
                      +(WATER_IOR*cosIncident-cosTransmitted)*normal;
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    float transmittedDepth = -1.0;
    vec4 transmittedFootprint = vec4(-1.0);
    #ifdef SCREENSPACE_REFRACTION
    #if REFRACTION_STRENGTH > 0
        // Solas composite4: normal displacement, FOV and eight-block minimum.
        vec2 displacement = (normal.xy - faceNormal.xy) * (0.6 * REFRACTION_STRENGTH * 0.01);
        displacement *= vec2(viewHeight / viewWidth, 1.0) * (gbufferProjection[1][1] / 1.37) / max(length(viewPos), 8.0);
        if (any(notEqual(displacement,vec2(0.0)))) {
            vec2 candidate = clamp(uv + displacement, vec2(0.0), vec2(1.0));
            // A hard if() here switched the whole ray between displaced and undisplaced per
            // pixel, which reads as shattered/torn water when looking up at the surface from
            // below (the user's "水下看水面的破碎多", explicitly not a wave-amplitude issue).
            // Blending across the depth test keeps the displaced path but removes the tear.
            vec4 candidateFootprint;
            vec3 candidateDepths = water_depth_footprint(depthtex1,candidate,candidateFootprint);
            float accept = smoothstep(gl_FragCoord.z - 0.0015, gl_FragCoord.z + 0.0015, candidateDepths.x);
            uv = mix(uv, candidate, accept);
            ivec2 size = textureSize(depthtex1,0);
            if (all(equal(floor(uv*vec2(size)-0.5),floor(candidate*vec2(size)-0.5)))) {
                // The blended query retains its own nearest corner; only the
                // already fetched four depths are shared within this texture cell.
                transmittedFootprint = candidateFootprint;
                transmittedDepth = water_depth_footprint_values(candidateFootprint,uv,size).z;
            }
        }
    #endif
    #endif
    vec3 background;
    // Like ITT, sky transmission follows the actual refracted direction. This
    // compresses the sky into Snell's window instead of painting sky everywhere.
    // Geometry retains the depth-guarded screen refraction above.
    vec3 transmittedGeometry;
    float geometryCoverage = water_sample_path(uv,viewPos,faceNormal,false,
        false,0.0,skylight,transmittedDepth,transmittedFootprint,transmittedGeometry);
    if (geometryCoverage < 1.0) {
        vec3 skyDirection = normalize(view_player(refractedRay));
        vec3 sky;
        float cloudTransmittance = 1.0;
        #if CLOUD_MODE == CLOUD_PLANAR
        // The same current-frame sky/cloud environment used by water above.
        // Near the critical angle refraction magnifies the angular footprint.
        float skyRoughness = clamp(angularFootprint*WATER_IOR
            / max(abs(dot(refractedRay,normal)),0.05),0.0,0.20);
        vec4 environment = astra_cached_reflection_environment(skyDirection,skyRoughness);
        sky = environment.rgb;
        cloudTransmittance = clamp(environment.a,0.0,1.0);
        #ifdef STARS
        // The low-frequency reflection cache deliberately excludes star points.
        // Share the same cloud footprint as the cached sky, with no per-pixel
        // cloud search for either individual stars or the galactic band.
        // A fully closed cloud footprint cannot transmit either layer.
        if (cloudTransmittance > 0.0)
            sky += astra_star_field(skyDirection)*cloudTransmittance;
        #endif
        #else
        sky = astra_overworld_sky(skyDirection);
        #endif
        sky+=water_transmitted_sun(skyDirection,angularFootprint*WATER_IOR
            /max(abs(dot(refractedRay,normal)),0.05),cloudTransmittance);
        background = max(mix(sky,transmittedGeometry,geometryCoverage),vec3(0.0));
    } else {
        // A sky ray above used to read and convert the opaque background too,
        // then overwrite it. Geometry alone needs this scene lookup.
        background = max(transmittedGeometry,vec3(0.0));
    }
    return vec4(max(mix(background,reflection,fresnel),vec3(0.0)),1.0);
}
#endif

vec4 astra_water(vec3 color, float alpha, vec3 playerPos, vec3 viewPos,
                 vec3 normal, float roughness, float skylight, bool water,
                 bool ice, vec3 geometricNormal, float reflectionAngularFootprint) {
    // The caller evaluates this footprint before divergent material flow.
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    // The world ray only decides a dot-product sign, so its length is irrelevant.
    // lit.fsh's geometric normal is a flat unit face normal with an optional flip.
    vec3 incidentWorld = view_player(viewPos);
    vec3 geometric = geometricNormal;
    #else
    vec3 incidentWorld = normalize(view_player(viewPos));
    vec3 geometric = normalize(geometricNormal);
    #endif
    if (dot(incidentWorld, geometric) > 0.0) geometric = -geometric;
    if (dot(normal, geometric) < 0.0) normal = -normal;
    vec3 incident = normalize(viewPos);
    vec3 viewNormal = normalize(player_view(normal));
    vec3 viewGeometric = normalize(player_view(geometric));
    bool belowWater = isEyeInWater == 1;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        if (water && abs(geometric.y) <= 0.9)
            return astra_vertical_water_interface(playerPos, viewPos, viewNormal, viewGeometric, skylight, roughness);
        if (water && belowWater) return astra_underwater_interface(color,viewPos,viewNormal,viewGeometric,
                                                                  skylight,reflectionAngularFootprint);
    #endif
    float eta = belowWater && water ? WATER_IOR : 1.0 / WATER_IOR;
    bool totalReflection = false;
    float fresnel;
    if (water && !belowWater) {
        // Air-to-water cannot reach total internal reflection. This branch
        // owns the existing Schlick response, so no dielectric solve is needed.
        // Derive the face-on reflection from the same water IOR as refraction.
        // A fixed 4.2% floor overweights neutral sky against a dark water body.
        // The grazing response still reaches one; source glints stay separate.
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        const float waterF0Ratio = (WATER_IOR - 1.0) / (WATER_IOR + 1.0);
        const float waterF0 = waterF0Ratio * waterF0Ratio;
        #else
        const float waterF0 = 0.042;
        #endif
        fresnel = (waterF0 + (1.0-waterF0) * pow5(clamp(1.0 + dot(incident, viewNormal), 0.0, 1.0))) * skylight;
    } else
        fresnel = water_fresnel(max(dot(-incident, viewNormal), 0.0), eta, totalReflection);
    vec3 reflectedRay = water_reflected_direction(incident,viewNormal,viewGeometric);
    vec3 reflectedWorld = normalize(view_player(reflectedRay));
    // Ice is a separate material, so it gets a separate surface response: its own
    // wider, weaker solar glint instead of water's, and a twilight-aware reflection
    // tint so it joins the same sunrise/sunset lighting as the terrain beside it
    // rather than staying a neutral sky mirror. Its texture still leads - this is a
    // glint on top of the lit cel, not a coating over it.
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    if (ice && !belowWater) {
        float iceAlign = max(dot(reflectedWorld, worldSunVector), 0.0);
        float iceSharpness = mix(72.0, 30.0, clamp(roughness * 3.0, 0.0, 1.0));
        float iceGlint = pow(iceAlign, iceSharpness) * solas_sun_visibility();
        if (iceGlint > 0.002) {
            // gated on the sun's own elevation, exactly as the water glint is: a
            // sunset glint on ice is a real thing, a midnight one is not.
            iceGlint *= smoothstep(0.0, 0.10, worldSunVector.y);
            vec3 iceGlintColor = mix(vec3(1.00, 0.97, 0.92), vec3(1.30, 0.86, 0.46),
                                     astra_twilight_strength());
            color += iceGlintColor * (iceGlint * 0.22 * skylight);
        }
    }
    #endif
    if (!water) {
        // Ice retains its lit texture; alpha blending supplies transmission.
        // It needs neither the fluid refraction march nor its absorption.
        vec3 iceReflection=astra_reflection_sky(reflectedWorld,roughness)*skylight;
        iceReflection *= astra_environment_reflection_gain(roughness,
                              max(dot(-incident, viewNormal), 0.0), 0.0204);
        color=mix(color,iceReflection,clamp(fresnel,0.035,0.28));
        return vec4(max(astra_apply_medium(color,playerPos,skylight),vec3(0.0)),
                    clamp(alpha,0.86,0.96));
    }
    vec3 reflection = vec3(0.0);
    float reflectionWeight = 0.0;
    #ifdef SCREENSPACE_REFLECTIONS
    // At a near-normal view the dielectric reflection contributes only a few
    // percent. Blend its screen-space leg into the existing environment over
    // that low-response interval; most directly viewed water then avoids the
    // full depth march and its filtered hit, while grazing/strong reflections
    // retain the complete path. The sun/moon glint is added separately below.
    float screenReflectionShare = 1.0;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END && defined ASTRA_OVERWORLD_OPTIMIZED
    // Air-side horizontal water keeps moderate reflections on the existing
    // sky environment. Below 0.36 no object ray runs; 0.36..0.50 blends it in,
    // and >=0.50 keeps the complete search and filtered hit. This spends fewer
    // fragments on SSR without changing its query positions or leaf guards.
    // `fresnel` already includes skylight, so skylight <=0.36 suppresses object
    // SSR even at grazing angles. This is an intentional low-light loss, not
    // just a view-angle adjustment. Independent gains depend on the scene;
    // their measurement and rejected sampling candidates live in the work page.
    // The submerged-camera and other-dimension windows keep their own paths.
    screenReflectionShare = (!belowWater && geometric.y > 0.9) ? smoothstep(0.36, 0.50, fresnel) : smoothstep(0.045, 0.085, fresnel);
    #endif
    if (screenReflectionShare > 0.0) {
        float queryImportance = 1.0;
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END && WATER_EFFECT_QUALITY < 2
        if (isEyeInWater == 0 && view_player(viewGeometric).y > 0.9) {
            // Near shores and stronger/grazing reflections keep the whole ray.
            // Weak reflections keep early hits (including bright nearby objects)
            // and their full refinement; only the far coarse tail becomes shorter.
            queryImportance = mix(1.0, smoothstep(0.025, 0.18, fresnel),
                                  smoothstep(12.0, 36.0, length(viewPos)));
        }
        #endif
        vec4 hit = water_raytrace(depthtex1, viewPos, reflectedRay, viewGeometric, 1e20, queryImportance,
                                 belowWater, !belowWater && geometric.y > 0.9);
        vec3 reflected = vec3(0.0);
        if (hit.a > 0.0) {
            float radius = 0.0;
            #if !defined ASTRA_OVERWORLD_OPTIMIZED && WATER_EFFECT_QUALITY > 0
            // Only the raw multi-footprint cone consumes hit distance/radius.
            // Budget sampling reconstructs each accepted endpoint itself.
            vec3 hitPos = water_screen_view(hit.xyz);
            float hitDistance = length(hitPos-viewPos);
            radius = clamp(roughness * roughness * hitDistance * viewHeight
                         / max(-hitPos.z, 0.1), 0.0, 12.0);
            float projectedFootprint = 0.5*abs(gbufferProjection[1][1])*viewHeight
                * hitDistance/max(-hitPos.z,0.1)*reflectionAngularFootprint;
            radius = max(radius,clamp(projectedFootprint*0.5,0.0,12.0));
            #endif
            reflectionWeight = hit.a * screenReflectionShare
                * water_sample_path(hit.xy, viewPos, viewGeometric,
                                          true, belowWater, radius, skylight, hit.z, reflected);
            reflection = reflected * reflectionWeight;
        }
    }
    #endif
    if (fresnel > 0.0 && reflectionWeight < 1.0) {
        vec3 fallback;
        if (belowWater) {
            fallback=astra_water_segment(vec3(0.0),playerPos,playerPos+reflectedWorld*96.0,skylight);
        } else {
            // One atmosphere for the visible sky and reflected sky, all day.
            fallback=vec3(0.0);
            if (skylight > 0.0) {
                fallback=astra_reflection_sky(reflectedWorld,roughness)*skylight;
                fallback *= astra_environment_reflection_gain(roughness,
                                max(dot(-incident, viewNormal), 0.0), 0.042);
            }
        }
        reflection += fallback * (1.0 - reflectionWeight);
    }
    // One directional source image: the environment omits both celestial
    // discs, so this lobe owns the sun by day and the moon by night.
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    if (!belowWater && fresnel > 0.0 && skylight > 0.0 && astraDirectLightGate > 0.0) {
        vec3 source = astra_world_light_direction();
        // Disabled light settings and an exactly dark moon cannot contribute.
        float glint = 0.0;
        if (astraWaterGlintFrame.z != 0.0)
            glint = water_source_glint(reflectedWorld,source,geometric,roughness)
                  * astraWaterGlintFrame.z;
        if (glint > 0.002) {
            vec3 sourceShadow = shadow_map_position(playerPos,geometric,dot(geometric,source));
            vec3 visibility = surface_shadow_light(playerPos,sourceShadow,skylight);
            glint *= dot(visibility,vec3(0.2126,0.7152,0.0722));
        }
        if (glint > 0.0) {
            // Palette, highlight shoulder and day/night source energy are
            // identical across this draw; the vertex stage prepared their product.
            reflection += waterGlintRadiance*(glint*skylight);
        }
    }
    #endif
    // 2026-09-22 (four-symptom round): the sky mirror above is bounded by the sky it
    // reflects, but its sum with the narrow solar lobe is not. BLOOM_THRESHOLD = 1.0
    // (global/post/bloom.glsl:27) is this pack's own definition of over-exposure - at or
    // below it a pixel contributes nothing to the bloom prefilter, above it the excess
    // becomes a bloom source - and the far water is where the sum crosses it: the grazing
    // lobe is nearly a mirror (0.64 at 5 degrees, 0.84 at 2) and the glint adds up to
    // another 0.72 (water.glsl:281), so a distant band can arrive as white plus bloom.
    // astra_scene_highlights is the pack's shoulder for exactly this class of emitter -
    // lib/twilight.glsl:131-134 names "the sun's image on water" as its consumer - and it
    // is the identity below 1.0, so the bed, the mid-range water and the twilight river
    // are untouched and only the excess above white is compressed. Before this call
    // program/water.glsl never used it (airside probe section 3), so the water surface was
    // the one emitter outside the shoulder.
    reflection = astra_scene_highlights(reflection);
    vec3 transmitted = vec3(0.0);
    if (!totalReflection) {
        vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
        float valid = 0.0;
        bool airMiss = false;
        bool unshiftedPath = false;
        #ifdef SCREENSPACE_REFRACTION
            // Steadfast advances by background depth with the perturbed direction.
            float refractedDepth;
            float pairedEntityDepth;
            vec3 normalDelta = viewNormal - viewGeometric;
            if (!belowWater && geometric.y > 0.9)
                normalDelta *= 1.0 - astra_water_surface_simplification(length(viewPos));
            vec2 refractedUV = water_refracted_scene_uv(viewPos,incident,normalDelta,uv,refractedDepth,
                                                        pairedEntityDepth);
            if (water && !belowWater && geometric.y > 0.9) {
                // A horizontal bed seen from air: one paired pixel carries colour,
                // depth, entity selection and its own medium transfer. The late-body
                // probe is reused when the accepted texel is this fragment's own.
                valid = water_transmission_sample(refractedUV,viewPos,viewGeometric,
                                                  skylight,refractedDepth,pairedEntityDepth,
                                                  transmitted);
            } else {
                valid = water_sample_path(refractedUV, viewPos, viewGeometric, false,
                                         water && !belowWater, 0.0, skylight, refractedDepth,
                                         vec4(-1.0), transmitted);
            }
            // Ice above water uses a different medium flag for the fallback.
            unshiftedPath = (water || belowWater) && all(equal(refractedUV, uv));
            if (belowWater && valid <= 0.0) {
                airMiss = any(lessThan(refractedUV, vec2(0.0)))
                       || any(greaterThanEqual(refractedUV, vec2(1.0)));
                if (!airMiss) {
                    ivec2 size = textureSize(depthtex1, 0);
                    airMiss = texelFetch(depthtex1, ivec2(refractedUV * vec2(size)), 0).r >= 0.999999;
                }
            }
        #endif
        // A fully accepted path needs no fallback scene/medium evaluation.
        if (valid < 1.0) {
            vec3 straight = vec3(0.0);
            float straightValid=0.0;
            if (!airMiss) {
                bool straightPathCached = unshiftedPath;
                #ifdef SCREENSPACE_REFRACTION
                if (!straightPathCached && water && !belowWater && geometric.y > 0.9) {
                    // This path point-fetches one paired scene pixel. A subpixel
                    // UV shift inside that same pixel cannot change its endpoint,
                    // radiance or acceptance: reuse that query for the fallback,
                    // keeping the original final UV-dependent blend. Other paths
                    // retain their exact-UV requirement. floor excludes offscreen
                    // UVs beside the viewport's first row/column as well.
                    vec2 sceneSize = vec2(textureSize(depthtex1, 0));
                    straightPathCached = all(equal(floor(refractedUV * sceneSize), floor(uv * sceneSize)));
                }
                #endif
                if (straightPathCached) {
                    straight = transmitted;
                    straightValid = valid;
                } else if (water && !belowWater && geometric.y > 0.9) {
                    straightValid=water_transmission_sample(uv,viewPos,viewGeometric,
                                                           skylight,-1.0,straight);
                } else {
                    straightValid=water_sample_path(uv,viewPos,viewGeometric,false,
                                                   !belowWater,0.0,skylight,-1.0,
                                                   vec4(-1.0),straight);
                }
            }
            vec3 geometricFallback=straight;
            if (straightValid < 1.0) {
                // From Steadfast 0.8.0 environment/water/absorption_refraction.glsl:97-117
                // (idea-level; every expression written for Astra): a refracted ray that
                // finds only sky has crossed an unknown column of water, and assuming a
                // LOT of it is right most of the time - except near the camera, where a
                // thin sheet must not read as deep ocean. The ramp is the fragment's own
                // camera distance: 0.25 blocks at the eye, 23 (fully extinct) at 24 blocks.
                //
                // Two parts of the reference are deliberately not copied. Steadfast also
                // multiplies its background by (1 - fadeFactor), because that pack's
                // absorption has no in-scatter term to consume the background; here
                // water_surface_medium already attenuates it by exp(-depth * sigma), so a
                // second fade would double-count and make the far field DARKER than before.
                // And its depth tops out at one block, which is the right bound for the
                // side-face case it models - an unknown column seen through the surface
                // itself is not bounded, so the ramp goes to the full extinction range.
                //
                // The background is the scene copy at this pixel, the same buffer the
                // accepted path reads: deferred.fsh composites astra_sky into it exactly
                // so that refraction has something behind it, and when the miss came from
                // the interface-side rejection instead of sky, it holds the real geometry.
                // An analytic sky here would be a second sky model disagreeing with the
                // rendered one right at the seam with mix(straight, ...): probe modes 16
                // and 21 measure both candidates. The superseded form had no background
                // at all - it handed vec3(0.0) to astra_water_segment, whose air-side
                // depth was that 96-block ray's vertical extent, a function of the
                // refraction angle only, never of how far the miss is: one constant
                // colour at every distance.
                vec3 deepFallback;
                // Other dimensions can contain player-placed water. Their underside
                // has no Overworld solar sprite and uses the dimension's own sky.
                #if defined DIMENSION_NETHER || defined DIMENSION_END
                if (belowWater) {
                    vec3 refractedRay = refract(incident, viewNormal, eta);
                    vec3 transmittedWorld = normalize(view_player(refractedRay));
                    deepFallback = astra_sky(transmittedWorld);
                } else
                #endif
                {
                    float farField = clamp(-viewPos.z * (1.0 / 24.0), 0.0, 1.0);
                    deepFallback = water_surface_medium(textureLod(colortex4, uv, 0.0).rgb,
                        mix(0.25, 23.0, farField), astra_water_incident(skylight),
                        !belowWater && geometric.y > 0.9
                            ? astra_water_surface_haze(0.0, length(viewPos)) : 0.0);
                }
                geometricFallback=mix(deepFallback,straight,straightValid);
            }
            // With no UV shift this is the same path: apply its validity once.
            transmitted=unshiftedPath ? geometricFallback : mix(geometricFallback,transmitted,valid);
        }
    }
    color = mix(transmitted, reflection, fresnel);
    // Exactly one eye-to-interface leg. Solar scattering for this leg is added
    // by composite/final, bounded by depthtex0, after translucent geometry.
    color = astra_apply_medium(color, playerPos, skylight);
    return vec4(max(color, vec3(0.0)), 1.0);
}
#endif
