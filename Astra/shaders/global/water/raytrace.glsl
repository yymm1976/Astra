#ifndef ASTRA_GLOBAL_WATER_RAYTRACE_GLSL
#define ASTRA_GLOBAL_WATER_RAYTRACE_GLSL
#include "/lib/water_surface_budget.glsl"

// Astra v1 - water screen-space reflections (ice uses the environment path).
// New Astra implementation based on the project specification and Khronos GLSL
// texture-gather/projection semantics; no source shader code was incorporated.
// Primary language reference (texture gather functions, section 8.7):
// https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.4.00.pdf
//
// Uniforms: gbufferProjection, gbufferProjectionInverse (lib/uniforms.glsl).
// The caller supplies depthtex1 and consumes the matching raw colour separately.
// Returns UV/depth and confidence; colour and optical length stay paired in the caller.

// Raw WATER_EFFECT_QUALITY budgets: what every dimension and OVERWORLD_BUDGET 0
// keep. The overworld budget below is a ceiling applied on top of these; it
// never raises them.
#if WATER_EFFECT_QUALITY == 0
const int ASTRA_WATER_RAW_BUDGET = 12;
const int ASTRA_WATER_RAW_REFINE = 4;
#elif WATER_EFFECT_QUALITY == 2
const int ASTRA_WATER_RAW_BUDGET = 40;
const int ASTRA_WATER_RAW_REFINE = 8;
#else
const int ASTRA_WATER_RAW_BUDGET = 20;
const int ASTRA_WATER_RAW_REFINE = 4;
#endif
// Approved overworld budget: a ceiling of 20 queries (16 coarse + 4 refine)
// inside 32 blocks and 16 (12 coarse + 4 refine) beyond. Air-side horizontal
// water halves the latter coarse ceiling across its fading window: at most 8
// coarse near, 6 coarse far, tapering down to 4. Its original four
// refinements, the 128-block visible projected segment, and the four-query
// prefetch are retained. Because it is a ceiling,
// QUALITY 0 keeps its own 12 queries with four refinements and is never lifted
// to 20, and its lighter single-footprint filtering stays single
// (program/water.glsl). The coarse constant holds the near-side maximum; the far
// ceiling is applied at run time below, so the 32-block boundary rides the
// existing queryCoverage handoff. Native water spreads those queries over
// its full visible projected segment; the ceiling no longer caps object height.
#if defined ASTRA_OVERWORLD_OPTIMIZED
#if WATER_EFFECT_QUALITY == 0
const int ASTRA_WATER_TRACE_BUDGET = ASTRA_WATER_RAW_BUDGET;
const int ASTRA_WATER_REFINE_STEPS = ASTRA_WATER_RAW_REFINE;
#else
const int ASTRA_WATER_TRACE_BUDGET = 20;
const int ASTRA_WATER_REFINE_STEPS = 4;
#endif
const int ASTRA_WATER_FAR_COARSE_STEPS = 12;
#else
const int ASTRA_WATER_TRACE_BUDGET = ASTRA_WATER_RAW_BUDGET;
const int ASTRA_WATER_REFINE_STEPS = ASTRA_WATER_RAW_REFINE;
#endif
const int ASTRA_WATER_COARSE_STEPS = ASTRA_WATER_TRACE_BUDGET - ASTRA_WATER_REFINE_STEPS;
// The taper serves the optimized budget even when the user has raised
// WATER_EFFECT_QUALITY, because the constants above still cap the march.
#if !defined DIMENSION_NETHER && !defined DIMENSION_END && (WATER_EFFECT_QUALITY < 2 || defined ASTRA_OVERWORLD_OPTIMIZED)
    #define ASTRA_WATER_ADAPTIVE_TRACE
#endif

// Projection is affine before the divide. Project the origin and direction
// once, including TAA's affine clip offset, then advance in homogeneous space.
// Reuse those clip endpoints instead of rebuilding and projecting every point.
bool water_ssr_project_ray(vec4 origin, vec4 direction, float travel,
                           vec2 halfTexel, out vec2 uv, out float projectedDepth) {
    projectedDepth = 1.0;
    float clipW = origin.w + direction.w * travel;
    if (clipW <= 0.00001) return false;
    vec2 ndcXY = (origin.xy + direction.xy * travel) / clipW;
    uv = ndcXY * 0.5 + 0.5;
    if (any(lessThan(uv, halfTexel)) || any(greaterThan(uv, vec2(1.0) - halfTexel)))
        return false;
    float ndcZ = (origin.z + direction.z * travel) / clipW;
    if (abs(ndcZ) > 1.0) return false;
    projectedDepth = ndcZ * 0.5 + 0.5;
    return true;
}

// Forward perspective has P[2][3] = -1 and P[3][3] = 0. With depth-only
// inverse rows, Z(d) = (zRow.z*d + zRow.w)/(wRow.z*d + wRow.w).
// Require positive W on [-1,1) and decreasing view Z with increasing depth;
// this also handles floating-point roundoff in the usual [0,0,0,-1] Z row.
bool water_ssr_standard_vw(vec4 zRow, vec4 wRow) {
    return gbufferProjection[2][3] == -1.0
        && gbufferProjection[3][3] == 0.0
        && wRow.z < 0.0
        && wRow.w >= -wRow.z
        && zRow.z*wRow.w-zRow.w*wRow.z < 0.0;
}

// Only view Z and the inverse W are needed by the general march; do not
// reconstruct a full XYZ point for each depth query. The caller evaluates the
// side plane separately with the new sampled depth; the depth-only cache can
// still reuse Z and inverse W for a repeated texel.
float water_ssr_inverse_zw(vec4 ndc, vec4 zRow, vec4 wRow,
                           bool depthOnlyZW, bool newPixel, inout vec2 cachedZW) {
    // In a standard projection Z/W depend only on depth. Repeated texel visits
    // can reuse both, while the interface-side plane still follows the exact UV.
    // Nonstandard projections retain the full reconstruction on every visit.
    if (!depthOnlyZW || newPixel) {
        float inverseW = 1.0 / dot(wRow, ndc);
        cachedZW = vec2(dot(zRow, ndc) * inverseW, inverseW);
    }
    return cachedZW.x;
}

// Clip the geometric ray once. Query count controls sampling density, not
// which height of a shoreline object the reflected ray is allowed to reach.
float water_ssr_visible_end(vec4 origin, vec4 direction, float maxTravel) {
    float end=min(maxTravel,128.0);
    vec4 side=vec4(origin.w-origin.x,origin.w+origin.x,
                   origin.w-origin.y,origin.w+origin.y);
    vec4 slope=vec4(direction.w-direction.x,direction.w+direction.x,
                    direction.w-direction.y,direction.w+direction.y);
    for (int axis=0;axis<4;++axis)
        if (slope[axis]<0.0) end=min(end,-side[axis]/slope[axis]);
    vec2 depthSide=vec2(origin.w-origin.z,origin.w+origin.z);
    vec2 depthSlope=vec2(direction.w-direction.z,direction.w+direction.z);
    for (int axis=0;axis<2;++axis)
        if (depthSlope[axis]<0.0) end=min(end,-depthSide[axis]/depthSlope[axis]);
    return max(end*0.9999,0.0);
}

#ifdef ASTRA_OVERWORLD_OPTIMIZED
// Air-side standard projection solves all four depth planes together. Each
// candidate must still cross its own texel in the fixed coarse interval,
// on the reflected side and inside the clipped view. No leaf tap is removed.
bool water_ssr_footprint_crossing_batch(sampler2D sceneDepth,vec2 uv,ivec2 pixel,ivec2 depthSize,
    vec2 jitter,vec4 clipOrigin,vec4 clipDirection,vec4 sidePlane,vec2 halfTexel,
    vec2 interval,inout ivec2 cachedCorner,inout vec4 cachedCorners,
    out float ownDepth,out vec4 intersection) {
    ownDepth=1.0;
    intersection=vec4(0.0);
    ivec2 corner=ivec2(floor(uv*vec2(depthSize)-0.5));
    if (all(greaterThanEqual(corner,ivec2(0))) && all(lessThan(corner+ivec2(1),depthSize))) {
        ivec2 offset=pixel-corner;
        if (all(equal(corner,cachedCorner))) {
            ownDepth=cachedCorners[offset.x+2*offset.y];
            return false;
        }
        vec4 depths=textureGather(sceneDepth,(vec2(corner)+1.0)/vec2(depthSize),0).wzxy;
        cachedCorner=corner;
        cachedCorners=depths;
        ownDepth=depths[offset.x+2*offset.y];
        vec4 target=depths*2.0-1.0;
        vec4 denominator=clipDirection.z-target*clipDirection.w;
        bvec4 finiteDenominator=greaterThan(abs(denominator),vec4(1e-7));
        vec4 crossing=(target*clipOrigin.w-clipOrigin.z)/mix(vec4(1.0),denominator,finiteDenominator);
        vec4 w=clipOrigin.w+clipDirection.w*crossing;
        vec4 safeW=max(w,vec4(0.00001));
        vec4 u=(clipOrigin.x+clipDirection.x*crossing)/safeW*0.5+0.5;
        vec4 v=(clipOrigin.y+clipDirection.y*crossing)/safeW*0.5+0.5;
        vec4 z=(clipOrigin.z+clipDirection.z*crossing)/safeW;
        vec4 side=((u-jitter.x)*2.0-1.0)*sidePlane.x
                 +((v-jitter.y)*2.0-1.0)*sidePlane.y+target*sidePlane.z+sidePlane.w;
        vec4 eligible=vec4(lessThan(depths,vec4(0.999999)))*vec4(finiteDenominator)
            *vec4(greaterThanEqual(crossing,vec4(interval.x)))*vec4(lessThanEqual(crossing,vec4(interval.y)))
            *vec4(greaterThan(w,vec4(0.00001)))
            *vec4(greaterThanEqual(u,vec4(halfTexel.x)))*vec4(lessThanEqual(u,vec4(1.0-halfTexel.x)))
            *vec4(greaterThanEqual(v,vec4(halfTexel.y)))*vec4(lessThanEqual(v,vec4(1.0-halfTexel.y)))
            *vec4(lessThanEqual(abs(z),vec4(1.0)))*vec4(greaterThan(side,vec4(0.0)))
            *vec4(equal(floor(u*float(depthSize.x)),vec4(float(corner.x))+vec4(0,1,0,1)))
            *vec4(equal(floor(v*float(depthSize.y)),vec4(float(corner.y))+vec4(0,0,1,1)));
        vec4 candidates=mix(vec4(1e20),crossing,greaterThan(eligible,vec4(0.0)));
        float closest=min(min(candidates.x,candidates.y),min(candidates.z,candidates.w));
        if (closest<1e19) {
            int tap=candidates.x==closest?0:candidates.y==closest?1:candidates.z==closest?2:3;
            intersection=vec4(u[tap],v[tap],depths[tap],closest);
            return true;
        }
        return false;
    }
    ownDepth=texelFetch(sceneDepth,pixel,0).r;
    return false;
}

bool water_ssr_footprint_crossing(sampler2D sceneDepth,vec2 uv,ivec2 pixel,ivec2 depthSize,
    vec2 jitter,vec4 clipOrigin,vec4 clipDirection,vec4 sidePlane,vec2 halfTexel,
    vec2 interval,inout ivec2 cachedCorner,inout vec4 cachedCorners,
    out float ownDepth,out vec4 intersection) {
    ownDepth=1.0;
    intersection=vec4(0.0);

    ivec2 corner=ivec2(floor(uv*vec2(depthSize)-0.5));
    if (all(greaterThanEqual(corner,ivec2(0)))
        && all(lessThan(corner+ivec2(1),depthSize))) {
        ivec2 offset=pixel-corner;
        // This refinement keeps one fixed coarse interval and ray. A failed
        // four-texel footprint cannot acquire a valid crossing when revisited;
        // only the scalar texel selected inside it can change. Success ends
        // the refinement immediately, so only failed footprints are reused.
        if (all(equal(corner,cachedCorner))) {
            ownDepth=cachedCorners[offset.x+2*offset.y];
            return false;
        }
        // One raw-depth gather replaces this refinement's scalar read.
        // Its neighbours are candidates ONLY when the reflected ray
        // crosses that candidate's own texel at its own sampled depth.
        // This preserves cutout leaves without filling their sky holes.
        vec4 depths=textureGather(sceneDepth,(vec2(corner)+1.0)/vec2(depthSize),0).wzxy;
        cachedCorner=corner;
        cachedCorners=depths;
        ownDepth=depths[offset.x+2*offset.y];
        
        float closest=1e20;
        vec2 acceptedUV=vec2(0.0);
        float acceptedDepth=1.0;
        for (int tap=0;tap<4;++tap) {
            if (depths[tap]>=0.999999) continue;
            float target=depths[tap]*2.0-1.0;
            float denominator=clipDirection.z-target*clipDirection.w;
            if (abs(denominator)<=1e-7) continue;
            float crossing=(target*clipOrigin.w-clipOrigin.z)/denominator;
            vec2 candidateUV;
            float candidateDepth;
            if (crossing<interval.x || crossing>interval.y || crossing>=closest
                || !water_ssr_project_ray(clipOrigin,clipDirection,crossing,
                    halfTexel,candidateUV,candidateDepth)) continue;
            ivec2 candidatePixel=corner+ivec2(tap%2,tap/2);
            vec4 candidateNdc=vec4((candidateUV-jitter)*2.0-1.0,target,1.0);
            if (all(equal(ivec2(candidateUV*vec2(depthSize)),candidatePixel))
                && dot(sidePlane,candidateNdc)>0.0) {
                closest=crossing;
                acceptedUV=candidateUV;
                acceptedDepth=depths[tap];
            }
        }
        if (closest<1e19) {
            intersection=vec4(acceptedUV,acceptedDepth,closest);
            return true;
        }
        return false;
    }


    ownDepth=texelFetch(sceneDepth,pixel,0).r;
    return false;
}
#endif

vec4 water_raytrace(sampler2D sceneDepth, vec3 viewPos, vec3 rayDirection,
                    vec3 interfaceNormal, float maxTravel, float queryImportance,
                    bool underwater, bool surfaceBudget) {
    rayDirection = normalize(rayDirection);
    // Fade with the reflecting surface's own camera distance, length(viewPos),
    // never with the ray's travel length: the march stride grows with distance,
    // so a long ray would otherwise extinguish the reflection of a near surface.
    // The caller mixes in the analytic sky fallback across the whole window, so
    // the sky reflection never disappears here. The overworld budget softens the
    // handoff (water Priority 48..96 blocks, Tightened 32..64). Wet terrain
    // retains 64..96; submerged interfaces, budget 0 and other dimensions
    // retain 64..128.
    float fadeNear = 64.0;
    float fadeFar = 128.0;
#if defined ASTRA_OVERWORLD_OPTIMIZED
    if (!underwater) {
    #if defined ASTRA_OVERWORLD_AGGRESSIVE
        fadeNear = 32.0;
        fadeFar = 64.0;
    #else
        fadeNear = 64.0;
        fadeFar = 96.0;
    #endif
    }
#endif
    float receiverDistance = length(viewPos);
    float surfaceSimplification = 0.0;
    #ifdef ASTRA_OVERWORLD_OPTIMIZED
    if (surfaceBudget && !underwater)
        surfaceSimplification = astra_water_surface_simplification(receiverDistance);
    #endif
    float rangeVisibility = 1.0 - smoothstep(fadeNear, fadeFar, receiverDistance);
    #ifdef ASTRA_OVERWORLD_OPTIMIZED
    if (surfaceBudget && !underwater) rangeVisibility = 1.0 - surfaceSimplification;
    #endif
    if (rangeVisibility <= 0.0) return vec4(0.0);

    vec3 origin = viewPos + rayDirection * 0.02;
    vec4 clipOrigin = astra_jitter_clip(gbufferProjection * vec4(origin, 1.0));
    vec4 clipDirection = astra_jitter_clip(gbufferProjection * vec4(rayDirection, 0.0));
    // A ray with increasing W may still enter the valid half-space later.
    if (clipOrigin.w <= 0.00001 && clipDirection.w <= 0.0) return vec4(0.0);
    ivec2 depthSize = textureSize(sceneDepth, 0);
    vec2 halfTexel = 0.5 / vec2(depthSize);
    vec2 jitter = astra_jitter_uv();
    mat4 inverseRows = transpose(gbufferProjectionInverse);
    vec4 sidePlane = inverseRows * vec4(interfaceNormal, -dot(viewPos, interfaceNormal));
    vec4 zRow = inverseRows[2], wRow = inverseRows[3];
    // Standard inverse Z/W rows depend only on depth; repeated texel visits may
    // reuse the reconstructed Z there. Nonstandard projections recompute.
    bool depthOnlyZW = all(equal(zRow.xy, vec2(0.0))) && all(equal(wRow.xy, vec2(0.0)));
    // Every standard forward projection may compare window depth directly.
    // Nonstandard inverse rows retain the inverse-W construction and side plane.
    bool standardProjection = false;
    #ifdef ASTRA_OVERWORLD_OPTIMIZED
    standardProjection = depthOnlyZW && water_ssr_standard_vw(zRow, wRow);
    #endif
    // Repeated visits to the same texel need no new read, even during refinement.
    ivec2 cachedPixel = ivec2(-1);
    float cachedDepth = 1.0;
    vec2 cachedZW = vec2(0.0, 1.0);
    float low = 0.0;
    float high = 0.0;
    float previous = 0.0;
    float stride = clamp(-viewPos.z * 0.0025, 0.08, 0.25);
    vec2 hitUV = vec2(0.0);
    float hitDepth = 1.0;
    // IDEA ONLY: Mellow allocates refinement from Fresnel. Astra instead keeps
    // precision at accepted hits and shortens the coarse tail for weak far water.
    // Fade a hit in the fractional last query, preserving a continuous handoff
    // to the environment when a budget boundary moves through a distant object.
    #ifdef ASTRA_WATER_ADAPTIVE_TRACE
    float coarseBudget = mix(float(max(6, ASTRA_WATER_COARSE_STEPS / 2)),
                             float(ASTRA_WATER_COARSE_STEPS), clamp(queryImportance, 0.0, 1.0));
    #ifdef ASTRA_OVERWORLD_OPTIMIZED
    // Past 32 blocks the approved budget caps the coarse tail at 12 queries
    // (16 with refinement). The ceiling only ever lowers what queryImportance
    // already selected, so a weak distant reflection keeps its own early exit
    // instead of being cut twice. Easing it in over the last eight blocks on the
    // near side of 32 reuses queryCoverage, so the boundary fades rather than
    // pops; the 12-query ceiling is exact at 32 blocks.
    coarseBudget = min(coarseBudget,
        mix(float(ASTRA_WATER_COARSE_STEPS), (surfaceBudget || underwater)
            ? float(ASTRA_WATER_FAR_COARSE_STEPS) : 8.0,
            smoothstep(24.0, 32.0, receiverDistance)));
    // Only air-side water spends fewer coarse queries as its details fade.
    // Halving its coarse ceiling bottoms out at 4 queries, so the visible
    // segment and refinement keep their reach while tiny reflections drop.
    // Wet terrain and submerged interfaces keep their own original budgets.
    if (surfaceBudget && !underwater)
        coarseBudget = max(4.0, 0.5 * mix(coarseBudget, min(coarseBudget,6.0), surfaceSimplification));
    #endif
    float queryCoverage = 1.0;
    #endif
    bool found = false;
    bool projectedMarch=false;
    float visibleEnd=0.0, endW=1.0;
    float suggestedTravel=-1.0;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    projectedMarch=surfaceBudget || underwater;
    if (projectedMarch) {
        visibleEnd=water_ssr_visible_end(clipOrigin,clipDirection,maxTravel);
        endW=clipOrigin.w+clipDirection.w*visibleEnd;
        if (visibleEnd<=0.0 || endW<=0.00001) return vec4(0.0);
    }
    #endif
    // Keep the first depth crossing on the REFLECTED side. A submerged floor
    // must not end an above-water reflection before the ray reaches the shore.
    for (int i = 0; i < ASTRA_WATER_COARSE_STEPS; ++i) {
        #ifdef ASTRA_WATER_ADAPTIVE_TRACE
        if (float(i) >= coarseBudget) break;
        #endif
        // Prefetch four scheduled depths, consuming only the leading sky or
        // opposite-side queries. A possible receiver keeps sequential plane
        // prediction/refinement; no query positions or hit budgets are removed.
        #if defined ASTRA_OVERWORLD_OPTIMIZED && defined ASTRA_WATER_ADAPTIVE_TRACE
        if (surfaceBudget && !underwater && standardProjection && suggestedTravel<=previous
            && clipOrigin.w>0.00001 && float(i+3)<coarseBudget) {
            vec4 f=vec4(float(i+1),float(i+2),float(i+3),float(i+4))/max(coarseBudget,1.0);
            f=min(f,vec4(1.0));f*=f;
            vec4 t=visibleEnd*f*clipOrigin.w/mix(vec4(endW),vec4(clipOrigin.w),f);
            vec4 w=vec4(clipOrigin.w)+clipDirection.w*t;
            vec4 inverseW=1.0/max(w,vec4(0.00001));
            vec4 u=(vec4(clipOrigin.x)+clipDirection.x*t)*inverseW*0.5+0.5;
            vec4 v=(vec4(clipOrigin.y)+clipDirection.y*t)*inverseW*0.5+0.5;
            vec4 z=(vec4(clipOrigin.z)+clipDirection.z*t)*inverseW;
            if (all(greaterThan(w,vec4(0.00001)))
                && all(greaterThanEqual(u,vec4(halfTexel.x))) && all(lessThanEqual(u,vec4(1.0-halfTexel.x)))
                && all(greaterThanEqual(v,vec4(halfTexel.y))) && all(lessThanEqual(v,vec4(1.0-halfTexel.y)))
                && all(lessThanEqual(abs(z),vec4(1.0))) && t.x>previous) {
                vec4 depths;
                depths.x=texelFetch(sceneDepth,ivec2(u.x*float(depthSize.x),v.x*float(depthSize.y)),0).r;
                depths.y=texelFetch(sceneDepth,ivec2(u.y*float(depthSize.x),v.y*float(depthSize.y)),0).r;
                depths.z=texelFetch(sceneDepth,ivec2(u.z*float(depthSize.x),v.z*float(depthSize.y)),0).r;
                depths.w=texelFetch(sceneDepth,ivec2(u.w*float(depthSize.x),v.w*float(depthSize.y)),0).r;
                vec4 side=(u*2.0-1.0-jitter.x*2.0)*sidePlane.x
                    +(v*2.0-1.0-jitter.y*2.0)*sidePlane.y+(depths*2.0-1.0)*sidePlane.z+sidePlane.w;
                // Keep near-plane roundoff in the original scalar path.
                float sideMargin=0.000001*max(1.0,dot(abs(sidePlane),vec4(1.0)));
                vec4 eligible=vec4(greaterThan(side,vec4(-sideMargin)))
                    *vec4(lessThan(depths,vec4(0.999999)));
                int skip=eligible.x>0.0?0:eligible.y>0.0?1:eligible.z>0.0?2:eligible.w>0.0?3:4;
                int last=max(skip-1,0);
                cachedPixel=ivec2(u[last]*float(depthSize.x),v[last]*float(depthSize.y));
                cachedDepth=depths[last];
                if (skip>0) {
                    previous=t[last];
                    suggestedTravel=-1.0;
                    i+=skip-1;
                    continue;
                }
            }
        }
        #endif
        // The projected march below overwrites this from the visible-segment
        // fraction, so only the raw geometric march consumes the growing stride.
        float travel = projectedMarch ? maxTravel : min(previous + stride, maxTravel);
        if (projectedMarch) {
            #ifdef ASTRA_WATER_ADAPTIVE_TRACE
            float fraction=min(float(i+1)/max(coarseBudget,1.0),1.0);
            #else
            float fraction=float(i+1)/float(ASTRA_WATER_COARSE_STEPS);
            #endif
            // More density near the start, linear movement in projected XY.
            // Convert that screen fraction back to geometric travel through W.
            fraction*=fraction;
            travel=visibleEnd*fraction*clipOrigin.w
                /mix(endW,clipOrigin.w,fraction);
            // A visible depth plane can suggest the next crossing. It is only
            // a query location: reread that pixel and retain all hit guards.
            if (suggestedTravel>previous) travel=suggestedTravel;
            suggestedTravel=-1.0;
            if (travel<=previous) continue;
        }
        if (travel <= previous) break;
        vec2 uv;
        float projectedDepth;
        if (!water_ssr_project_ray(clipOrigin, clipDirection, travel, halfTexel,
                                   uv, projectedDepth)) break;
        ivec2 pixel = clamp(ivec2(uv * vec2(depthSize)), ivec2(0), depthSize - 1);
        bool newPixel = any(notEqual(pixel, cachedPixel));
        if (newPixel) {
            cachedDepth = texelFetch(sceneDepth, pixel, 0).r;
            cachedPixel = pixel;
        }
        float depth = cachedDepth;
        if (depth < 0.999999) {
            vec4 receiverNdc = vec4((uv - jitter) * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
            bool behind = false;
            if (standardProjection) {
                // Same clip/W divide that produced projectedDepth; the interface
                // side still uses the exact sampled depth and UV.
                bool reflectedSide = dot(sidePlane, receiverNdc) > 0.0;
                behind = reflectedSide && projectedDepth >= depth;
                if (projectedMarch && reflectedSide) {
                    float target=depth*2.0-1.0;
                    float denominator=clipDirection.z-target*clipDirection.w;
                    if (abs(denominator)>1e-7) {
                        float crossing=(target*clipOrigin.w-clipOrigin.z)/denominator;
                        vec2 crossingUV;
                        float crossingDepth;
                        // A finite leaf pixel may already contain the exact
                        // plane crossing, although this scheduled query is in
                        // front of it. Its own sampled texel certifies that hit;
                        // do not jump into a cutout hole and discard the leaf.
                        if (crossing>=previous && crossing<=visibleEnd
                            && water_ssr_project_ray(clipOrigin,clipDirection,crossing,
                                halfTexel,crossingUV,crossingDepth)
                            && all(equal(ivec2(crossingUV*vec2(depthSize)),pixel))) {
                            low=crossing;
                            high=crossing;
                            hitUV=crossingUV;
                            hitDepth=depth;
                            #ifdef ASTRA_WATER_ADAPTIVE_TRACE
                            queryCoverage=clamp(coarseBudget-float(i),0.0,1.0);
                            #endif
                            found=true;
                            break;
                        }
                        float proposal=crossing+max(0.002,crossing*0.00002);
                        if (!behind && proposal>travel && proposal<visibleEnd)
                            suggestedTravel=proposal;
                    }
                }
            } else {
                float receiverZ = water_ssr_inverse_zw(receiverNdc, zRow, wRow,
                                                 depthOnlyZW, newPixel, cachedZW);
                behind = dot(sidePlane, receiverNdc) * cachedZW.y > 0.0
                    && origin.z + rayDirection.z * travel <= receiverZ;
            }
            if (behind) {
                low = previous;
                high = travel;
                hitUV = uv;
                hitDepth = depth;
                #ifdef ASTRA_WATER_ADAPTIVE_TRACE
                queryCoverage = clamp(coarseBudget - float(i), 0.0, 1.0);
                #endif
                found = true;
                break;
            }
        }
        previous = travel;
        if (!projectedMarch) {
        #if WATER_EFFECT_QUALITY < 2
        // Spend fewer queries on distant reflections; the existing environment
        // carries misses. Wider steps intentionally omit some thin far objects.
        stride = min(stride * 1.9, 12.0);
        #else
        stride = min(stride * 1.6, 8.0);
        #endif
        }
    }
    if (!found) return vec4(0.0);
    float coarseLow=low, coarseHigh=high;
    #ifdef ASTRA_OVERWORLD_OPTIMIZED
    ivec2 refineCorner=ivec2(-2);
    vec4 refineDepths=vec4(1.0);
    #endif

    // Refine a depth interval, without fitting a plane through unrelated leaves.
    // Fine queries are reserved inside the total budget, including late hits.
    for (int i = 0; i < ASTRA_WATER_REFINE_STEPS && high > low; ++i) {
        float middle = 0.5 * (low + high);
        vec2 uv;
        float projectedDepth;
        bool projectedMiddle = false;
        #ifdef ASTRA_OVERWORLD_OPTIMIZED
        if (standardProjection && i+1 < ASTRA_WATER_REFINE_STEPS) {
            // Solve the accepted texel's depth plane. A different lower texel
            // is safe only if the solved crossing still occupies the hit texel;
            // otherwise keep ordinary refinement across the discontinuity.
            float target = hitDepth*2.0-1.0;
            float denominator = clipDirection.z-target*clipDirection.w;
            if (abs(denominator) > 0.0000001) {
                float crossing = (target*clipOrigin.w-clipOrigin.z)/denominator;
                vec2 exactUV;
                float exactDepth;
                if (crossing >= coarseLow && crossing <= coarseHigh
                    && water_ssr_project_ray(clipOrigin,clipDirection,crossing,
                        halfTexel,exactUV,exactDepth)) {
                    vec4 exactNdc = vec4((exactUV-jitter)*2.0-1.0,target,1.0);
                    // Crossings caused by the interface side rather than depth
                    // keep ordinary refinement, as do nonstandard projections.
                    if (dot(sidePlane,exactNdc) > 0.0
                        && all(equal(ivec2(exactUV*vec2(depthSize)),ivec2(hitUV*vec2(depthSize))))) {
                        high = crossing;
                        hitUV = exactUV;
                        break;
                    }
                    // A canopy's accepted leaf plane often crosses a different
                    // pixel. Spend THIS refinement query there; never treat a
                    // predicted plane as a hit without rereading its own depth.
                    if (crossing >= low && crossing <= high) {
                        middle = crossing;
                        uv = exactUV;
                        projectedDepth = exactDepth;
                        projectedMiddle = true;
                    }
                }
            }
        }
        #endif
        if (!projectedMiddle && !water_ssr_project_ray(
                clipOrigin, clipDirection, middle, halfTexel, uv, projectedDepth)) break;
        ivec2 pixel = clamp(ivec2(uv * vec2(depthSize)), ivec2(0), depthSize - 1);
        bool newPixel = any(notEqual(pixel, cachedPixel));
        #ifdef ASTRA_OVERWORLD_OPTIMIZED
        if (standardProjection && projectedMarch) {
            vec4 intersection;
            bool accepted;
            if (surfaceBudget && !underwater) accepted=water_ssr_footprint_crossing_batch(sceneDepth,uv,pixel,depthSize,jitter,
                clipOrigin,clipDirection,sidePlane,halfTexel,vec2(coarseLow,coarseHigh),
                refineCorner,refineDepths,cachedDepth,intersection);
            else accepted=water_ssr_footprint_crossing(sceneDepth,uv,pixel,depthSize,jitter,
                clipOrigin,clipDirection,sidePlane,halfTexel,vec2(coarseLow,coarseHigh),
                refineCorner,refineDepths,cachedDepth,intersection);
            // ownDepth is an out parameter: cachedDepth has this pixel's depth
            // even when a failed footprint was reused. No scalar reread is needed.
            cachedPixel=pixel;
            newPixel=false;
            if (accepted) {
                hitUV=intersection.xy;hitDepth=intersection.z;high=intersection.w;
                break;
            }
        }
        #endif
        if (newPixel) {
            cachedDepth = texelFetch(sceneDepth, pixel, 0).r;
            cachedPixel = pixel;
        }
        float depth = cachedDepth;
        bool behind = false;
        if (depth < 0.999999) {
            vec4 receiverNdc = vec4((uv - jitter) * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
            if (standardProjection) {
                behind = dot(sidePlane, receiverNdc) > 0.0 && projectedDepth >= depth;
            } else {
                float receiverZ = water_ssr_inverse_zw(receiverNdc, zRow, wRow,
                                                 depthOnlyZW, newPixel, cachedZW);
                behind = dot(sidePlane, receiverNdc) * cachedZW.y > 0.0
                    && origin.z + rayDirection.z * middle <= receiverZ;
            }
        }
        if (behind) {
            high = middle;
            hitUV = uv;
            hitDepth = depth;
        } else {
            low = middle;
        }
    }
    vec3 endpoint = origin + rayDirection * high;
    // Reconstruct scene Z once, from the last accepted hit UV/depth. The
    // general branch rebuilt it per query; the standard branch applies the same
    // inverse projection only here, keeping the march free of that divide.
    vec4 ndc = vec4((hitUV - jitter) * 2.0 - 1.0, hitDepth * 2.0 - 1.0, 1.0);
    float sceneZ = dot(zRow, ndc) / dot(wRow, ndc);
    float footprint = 2.0 * abs(sceneZ) / max(abs(gbufferProjection[1][1]) * viewHeight, 1.0);
    float thickness = max(0.25, footprint * 2.0);
    float residual = abs(sceneZ - endpoint.z);
    float confidence = 1.0 - smoothstep(thickness, thickness * 2.0, residual);
    float edge = min(min(hitUV.x, 1.0-hitUV.x), min(hitUV.y, 1.0-hitUV.y));
    confidence *= smoothstep(0.0, 0.03, edge) * rangeVisibility;
    #ifdef ASTRA_WATER_ADAPTIVE_TRACE
    confidence *= queryCoverage;
    #endif
    return vec4(hitUV, hitDepth, confidence);
}

vec4 water_raytrace(sampler2D sceneDepth, vec3 viewPos, vec3 rayDirection,
                    vec3 interfaceNormal, float maxTravel, float queryImportance) {
    return water_raytrace(sceneDepth, viewPos, rayDirection, interfaceNormal,
                          maxTravel, queryImportance, false, false);
}

vec4 water_raytrace(sampler2D sceneDepth, vec3 viewPos, vec3 rayDirection,
                    vec3 interfaceNormal, float maxTravel) {
    return water_raytrace(sceneDepth, viewPos, rayDirection, interfaceNormal,
                          maxTravel, 1.0, false, false);
}

// Submerged interface path (program/water.glsl astra_underwater_interface): the
// reflected leg keeps the original 64..128 receiver window rather than the
// above-water overworld budget window.
vec4 water_raytrace(sampler2D sceneDepth, vec3 viewPos, vec3 rayDirection,
                    vec3 interfaceNormal) {
    return water_raytrace(sceneDepth, viewPos, rayDirection, interfaceNormal,
                          1e20, 1.0, true, false);
}

#endif
