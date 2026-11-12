#ifndef ASTRA_GLOBAL_WATER_REFRACTION_GLSL
#define ASTRA_GLOBAL_WATER_REFRACTION_GLSL
// Adapted from Steadfast 0.8.0 environment/water/refraction.glsl, coderbot.
// GPL-3.0-or-later with Section 7 terms; see Astra/LICENSE and THIRD-PARTY.md.
// SUMMARY efficiency idea: avoid depth queries when refraction has no displacement.
#ifdef ASTRA_WATER_PASS
flat in int waterProjectionFlags;
#endif
vec3 water_screen_view(vec3 screenPosition) {
    #if defined ASTRA_WATER_PASS && !defined DIMENSION_NETHER && !defined DIMENSION_END
    if ((waterProjectionFlags & 8) != 0) {
        // Same sparse inverse as screen_view; its matrix-shape decision was
        // made by the vertex stage, rather than repeated for every endpoint.
        screenPosition.xy -= astra_jitter_uv();
        vec3 ndc = screenPosition * 2.0 - 1.0;
        vec4 point = gbufferProjectionInverse[2] * ndc.z + gbufferProjectionInverse[3];
        point.xy += vec2(gbufferProjectionInverse[0].x * ndc.x,
                         gbufferProjectionInverse[1].y * ndc.y);
        return point.xyz / point.w;
    }
    #endif
    return screen_view(screenPosition);
}
vec3 water_depth_footprint_values(vec4 footprint, vec2 uv, ivec2 size) {
    vec2 location = clamp(uv,vec2(0.0),vec2(1.0))*vec2(size);
    ivec2 nearestCorner = ivec2(floor(location) - floor(location - 0.5));
    // Cached corners are already (00,10,01,11). Reusing their range never
    // reuses the old nearest corner: the new UV selects its OWN raw depth.
    float nearestDepth = footprint[nearestCorner.x+2*nearestCorner.y];
    return vec3(min(min(footprint.x,footprint.y),min(footprint.z,footprint.w)),
                max(max(footprint.x,footprint.y),max(footprint.z,footprint.w)),nearestDepth);
}
vec3 water_depth_footprint(sampler2D depthBuffer, vec2 uv, out vec4 footprint) {
    uv = clamp(uv,vec2(0.0),vec2(1.0));
    footprint = textureGather(depthBuffer,uv).wzxy;
    return water_depth_footprint_values(footprint,uv,textureSize(depthBuffer,0));
}
// Exact view Z from the same inverse projection as screen_view, using only the
// two rows that divide Z by W.
float water_screen_view_z(vec2 uv, float depth) {
    #if defined ASTRA_WATER_PASS && !defined DIMENSION_NETHER && !defined DIMENSION_END
    if ((waterProjectionFlags & 4) != 0) {
        // No UV or jitter term can enter Z/W when both inverse XY columns
        // have zero Z/W. Column 2/3 offsets and perspective W stay intact.
        float ndcZ = depth * 2.0 - 1.0;
        return (gbufferProjectionInverse[2].z * ndcZ + gbufferProjectionInverse[3].z)
             / (gbufferProjectionInverse[2].w * ndcZ + gbufferProjectionInverse[3].w);
    }
    #endif
    vec4 ndc = vec4((uv - astra_jitter_uv()) * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    mat4 inverseRows = transpose(gbufferProjectionInverse);
    return dot(inverseRows[2],ndc) / dot(inverseRows[3],ndc);
}
// A refracted query reads ONE pixel: the texel containing its UV supplies the
// depth that bounds displacement, the acceptance test and (through the paired
// transmission sampler) the endpoint and colour. No 2x2 footprint crosses this
// path; silhouette corners no longer mix one tap's colour with another's depth.
// pairedEntityDepth reports the caller's own entityViewDepth when the accepted
// texel is the one that already supplied it, letting the paired transmission
// skip its colortex28 fetch. -1 means "unknown, fetch normally".
vec2 water_refracted_uv(sampler2D depthBuffer, vec3 viewPos, vec3 incident, vec3 normalDelta,
                        vec2 rasterUV, float entityViewDepth, out float acceptedDepth,
                        out float pairedEntityDepth) {
    acceptedDepth = -1.0;
    pairedEntityDepth = -1.0;
    // A true zero-displacement path must retain the caller's pixel centre.
    // The accepted texel IS the caller's probe, so its entity depth pairs.
    // A mismatched native projection retains the general projected origin.
    if (REFRACTION_STRENGTH == 0 || dot(normalDelta, normalDelta) <= 0.0) {
        pairedEntityDepth = entityViewDepth;
        return rasterUV;
    }
    vec4 originClip;
    vec2 uv;
    #ifdef ASTRA_WATER_PASS
    if ((waterProjectionFlags & 1) != 0) {
        // Raster XY/W already project this same native point. Refraction only
        // consumes XY/W, so clip Z need not be reconstructed. Keep the general
        // matrix path for hand-water or any other projection mismatch.
        float clipW = 1.0/gl_FragCoord.w;
        uv = rasterUV;
        originClip = vec4(((uv-astra_jitter_uv())*2.0-1.0)*clipW,0.0,clipW);
    } else
    #endif
    {
        originClip = gbufferProjection * vec4(viewPos,1.0);
        uv = originClip.xy / originClip.w;
        uv = uv * 0.5 + 0.5 + astra_jitter_uv();
    }
    ivec2 depthSize = textureSize(depthBuffer,0);
    ivec2 backgroundPixel = clamp(ivec2(clamp(uv,vec2(0.0),vec2(1.0))*vec2(depthSize)),
                                  ivec2(0), depthSize-1);
    float backgroundDepth = texelFetch(depthBuffer,backgroundPixel,0).r;
    float backgroundZ = water_screen_view_z(uv, backgroundDepth);
    // A late body can be much closer than the bed in the deferred snapshot.
    // Its own linear depth must also limit displacement, not just supply RGB
    // after the ray has already been refracted toward a distant background.
    if (entityViewDepth > max(-viewPos.z,0.0)+0.002)
        backgroundZ = max(backgroundZ,-entityViewDepth);
    // The interface already needs this unit viewing direction for Fresnel and
    // reflection. Reuse it without normalizing the same position a second time.
    vec3 direction = normalize(incident + normalDelta * (REFRACTION_STRENGTH * 0.01));
    float distance = min(abs(viewPos.z - backgroundZ), 32.0);
    vec3 directionClip;
    #if defined ASTRA_WATER_PASS && !defined DIMENSION_NETHER && !defined DIMENSION_END
    if ((waterProjectionFlags & 2) != 0) {
        directionClip = vec3(gbufferProjection[0].x * direction.x,
                             gbufferProjection[1].y * direction.y, 0.0)
                      + gbufferProjection[2].xyw * direction.z;
    } else
    #endif
        directionClip = (gbufferProjection * vec4(direction,0.0)).xyw;
    vec3 refractedClip = originClip.xyw + directionClip * distance;
    vec2 refractedUV = refractedClip.xy / refractedClip.z;
    refractedUV = refractedUV.xy * 0.5 + 0.5 + astra_jitter_uv();
    vec2 ndc = abs(refractedUV * 2.0 - 1.0);
    float visibility = clamp((1.0 - max(ndc.x, ndc.y)) / 0.10, 0.0, 1.0);
    refractedUV = mix(uv, refractedUV, visibility);
    ivec2 refractedPixel = clamp(ivec2(clamp(refractedUV,vec2(0.0),vec2(1.0))*vec2(depthSize)),
                                 ivec2(0), depthSize-1);
    // Small displacements usually stay in the texel already read for the
    // background bound. Reuse that exact value instead of fetching the same
    // texel twice.
    float refractedDepth = backgroundDepth;
    if (any(notEqual(refractedPixel,backgroundPixel)))
        refractedDepth = texelFetch(depthBuffer,refractedPixel,0).r;
    // The caller probed colortex28 at rasterUV's own texel. That probe describes
    // the accepted texel only while the accepted texel IS the caller's own, so
    // report it there and keep -1 (unknown) everywhere else.
    ivec2 rasterPixel = clamp(ivec2(clamp(rasterUV,vec2(0.0),vec2(1.0))*vec2(depthSize)),
                              ivec2(0), depthSize-1);
    if (gl_FragCoord.z > refractedDepth) {
        acceptedDepth = backgroundDepth;
        if (all(equal(backgroundPixel,rasterPixel))) pairedEntityDepth = entityViewDepth;
        return uv;
    }
    acceptedDepth = refractedDepth;
    if (all(equal(refractedPixel,rasterPixel))) pairedEntityDepth = entityViewDepth;
    return refractedUV;
}
#endif
