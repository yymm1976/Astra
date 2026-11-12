// Astra screen-cloud cache. Uses the existing Complementary-derived cloud model.
// Separate from the spherical reflection environment: this projection follows the view.
#define ASTRA_SCREEN_CLOUD_WRITE
// Overworld only: the matching vertex stage (program/cloud_screen.vsh) declares
// and writes the same flat water kind. The cloud sky lookup consumes it per ray;
// reusing the draw-wide value removes the per-pixel colortex6 fetch.
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
#define ASTRA_WATER_STATE_FRAME_READ
#endif
#include "/program/scene.glsl"
in vec2 texcoord;
#ifdef CLOUD_TEMPORAL
#ifdef ASTRA_CLOUD_TEMPORAL
// R6/T3: independent temporal history for this cloud (colortex24/25). See
// docs/archive/实现与取证.md#record-081. Every consumer uses colortex24
// on this path, so no duplicate raw sheet needs to be written or cleared.
// This path writes colortex24/25, so it declares RGBA16F here for the module; the
// raw colortex12 path below gets the same token from cloud_buffer_formats.glsl.
#ifndef RGBA16F
const int RGBA16F = 0;
#endif
const bool colortex12Clear = false;
#include "/global/atmosphere/cloud_temporal.glsl"
#endif
#endif
#ifdef ASTRA_CLOUD_TEMPORAL
/* RENDERTARGETS: 24,25 */
#else
uniform sampler2D colortex12;
#include "/lib/cloud_buffer_formats.glsl"
/* RENDERTARGETS: 12 */
#endif
// Return premultiplied colour and opacity, with an opacity-weighted world
// representative for reprojection. High averages four quarter-pixel rays now,
// so anti-aliasing also works with cloud history or scene TAA disabled.
vec4 astra_screen_cloud_current(vec2 uv, vec3 centreRay, vec2 centreInterval,
                               float footprint, out vec3 representative,
                               out bool sampledVisible) {
    representative = vec3(0.0);
    sampledVisible = false;
    #if CLOUD_QUALITY == 2
    vec2 texel = 1.0/vec2(textureSize(
        #ifdef ASTRA_CLOUD_TEMPORAL
        colortex24,
        #else
        colortex12,
        #endif
        0));
    vec4 sum = vec4(0.0);
    AstraCloudFrame frameCloud = astra_cloud_frame();
    for (int sampleIndex=0;sampleIndex<4;++sampleIndex) {
        vec2 offset=vec2((sampleIndex & 1)==0 ? -0.25 : 0.25,
                         (sampleIndex & 2)==0 ? -0.25 : 0.25)*texel;
        vec3 sampleRay=normalize(view_player(screen_view(vec3(uv+offset,1.0))));
        vec2 sampleInterval=astra_cloud_interval(sampleRay);
        if (sampleInterval.y <= sampleInterval.x) continue;
        sampledVisible = true;
        vec3 sampleRepresentative;
        vec4 cloud=astra_planar_cloud(sampleRay,1e20,sampleRepresentative,
                                     footprint*0.5,sampleInterval,frameCloud);
        sum += vec4(cloud.rgb*cloud.a,cloud.a);
        representative += sampleRepresentative*cloud.a;
    }
    if (sum.a>0.0) representative /= sum.a;
    return sum*0.25;
    #else
    sampledVisible = centreInterval.y > centreInterval.x;
    if (!sampledVisible) return vec4(0.0);
    vec4 cloud=astra_planar_cloud(centreRay,1e20,representative,footprint,centreInterval);
    return vec4(cloud.rgb*cloud.a,cloud.a);
    #endif
}
void main() {
    // These conditions are uniform for the draw. Preserve the empty output and
    // current history stamp without reconstructing rays or probing opaque depth.
    // Derivatives below therefore still run in uniform control flow.
    if (!(isEyeInWater < 2 && blindness <= 0.0001)) {
        #ifdef ASTRA_CLOUD_TEMPORAL
        vec4 cloudMeta;
        gl_FragData[0] = astra_cloud_temporal_resolve(vec4(0.0), vec3(0.0), vec3(0.0),
                                                    false, texcoord, cloudMeta);
        gl_FragData[1] = cloudMeta;
        #else
        gl_FragData[0] = vec4(0.0);
        #endif
        return;
    }
    vec2 sampleUV = texcoord;
    #ifdef ASTRA_CLOUD_TEMPORAL
    sampleUV += astra_cloud_grid_offset(frameCounter, textureSize(colortex24, 0));
    #endif
    vec3 ray = normalize(view_player(screen_view(vec3(sampleUV, 1.0))));
    float angularFootprint = max(length(dFdx(ray)), length(dFdy(ray)));
    vec2 interval = astra_cloud_interval(ray);
    bool visibleCloud = interval.y > interval.x;
    bool occluded = false;
    // A ray missing the slab has no cloud endpoint to compare with terrain.
    // Keep derivatives above and the empty/history output below unchanged.
    if (visibleCloud) {
        // Expand the low-resolution footprint by one texel around silhouettes.
        // An open corner keeps the complete cloud ray, including cloud over a ridge.
        vec2 pad = 1.0 / vec2(textureSize(
            #ifdef ASTRA_CLOUD_TEMPORAL
            colortex24,
            #else
            colortex12,
            #endif
            0));
        vec2 edge = 0.5 / vec2(textureSize(depthtex0, 0));
        vec2 lo = clamp(texcoord - pad, edge, 1.0 - edge);
        vec2 hi = clamp(texcoord + pad, edge, 1.0 - edge);
        float farthestDepth = textureLod(depthtex0, lo, 0.0).r;
        // A sky corner already proves this tile must retain its complete cloud ray.
        // Remaining values are irrelevant once opaque rejection is disabled.
        if (farthestDepth < 0.999999)
            farthestDepth = max(farthestDepth, textureLod(depthtex0, hi, 0.0).r);
        if (farthestDepth < 0.999999)
            farthestDepth = max(farthestDepth, textureLod(depthtex0, vec2(lo.x, hi.y), 0.0).r);
        if (farthestDepth < 0.999999)
            farthestDepth = max(farthestDepth, textureLod(depthtex0, vec2(hi.x, lo.y), 0.0).r);
        // Include every depth texel inside the producing tile, so small canopy
        // openings between the outer guard corners cannot be rejected as opaque.
        // Low cloud quality uses the quarter grid, so four corner gathers
        // cover its 4x4 native depths. Higher qualities use their own grids.
        #if CLOUD_QUALITY == 0
        for (int corner = 0; corner < 4; ++corner) {
            // One sky texel already disables opaque rejection for the whole tile.
            if (farthestDepth >= 0.999999) break;
            vec2 offset = vec2((corner & 1) == 0 ? -1.0 : 1.0,
                               (corner & 2) == 0 ? -1.0 : 1.0) * pad * 0.25;
            vec4 depths = textureGather(depthtex0, clamp(texcoord + offset, edge, 1.0 - edge), 0);
            farthestDepth = max(farthestDepth, max(max(depths.x, depths.y), max(depths.z, depths.w)));
        }
        #else
        if (farthestDepth < 0.999999) {
            vec4 depths = textureGather(depthtex0, texcoord, 0);
            farthestDepth = max(farthestDepth, max(max(depths.x, depths.y), max(depths.z, depths.w)));
        }
        #endif
        if (farthestDepth < 0.999999) {
            float opaqueDistance = length(screen_view(vec3(texcoord, farthestDepth)));
            occluded = opaqueDistance + 8.0 + interval.x * angularFootprint * 2.0 < interval.x;
        }
    }
    vec3 representative = vec3(0.0);
    vec4 current = vec4(0.0);
    bool sampledVisible = false;
    if (!occluded)
        current = astra_screen_cloud_current(sampleUV,ray,interval,angularFootprint,
                                              representative,sampledVisible);
    #ifdef ASTRA_CLOUD_TEMPORAL
    // The resolve blends with the real-previous-frame reprojection and reports the
    // metadata (representative distance, stamp, viewport fingerprint) for colortex25.
    vec4 cloudMeta;
    gl_FragData[0] = astra_cloud_temporal_resolve(current,
                                                representative, ray, sampledVisible, texcoord, cloudMeta);
    gl_FragData[1] = cloudMeta;
    #else
    // Premultiplication keeps empty texels from bleeding black into cloud edges.
    gl_FragData[0] = current;
    #endif
}
