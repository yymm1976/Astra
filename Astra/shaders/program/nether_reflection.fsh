// Complementary-style reflection carrier, before receiver-space reconstruction.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/encoding.glsl"
#include "/lib/transforms.glsl"
#include "/lib/scene_buffer_formats.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D colortex9;
uniform sampler2D colortex28;
#include "/lib/effect_history.glsl"
#include "/lib/nether_reflection_metadata.glsl"
// Reuse the native End sky target: that producer never runs in the Nether.
const bool colortex9Clear = false;
const int colortex28Format = RGBA16F;
const bool colortex28Clear = false;
const vec4 colortex9ClearColor = vec4(0.0,0.0,0.0,0.0);
const vec4 colortex28ClearColor = vec4(0.0,0.0,0.0,0.0);
#ifdef NETHER_ROCK_REFLECTIONS
// Mips are generated from the completed scene for the rough reflection lookup.
const bool colortex0MipmapEnabled = true;
#endif
#include "/global/dimension/nether_reflection.glsl"
in vec2 texcoord;
flat in int effectFrameValid;
/* RENDERTARGETS: 9,28 */
void main() {
    vec4 reflection = vec4(0.0);
    vec4 metadata = vec4(0.0);
    gl_FragData[0] = reflection;
    gl_FragData[1] = metadata;
#ifdef NETHER_ROCK_REFLECTIONS
    if (DEBUG_VERTEX_AO != 0 || isEyeInWater != 0) return;
    // Rough rocks need a spatially broad signal, not a ray for every display
    // pixel. Low/balanced use a stable 2x2 receiver lattice; the resolve restores
    // native output only across matching surfaces. Keep the native attachments
    // because the End independently uses target 9 at native resolution.
    ivec2 receiverPixel = ivec2(gl_FragCoord.xy);
    #if NETHER_REFLECTION_QUALITY < 2
    if (any(notEqual(receiverPixel & ivec2(1), ivec2(0)))) return;
    #endif
    vec4 material = texelFetch(colortex3, receiverPixel, 0);
    uint flags = uint(round(material.r * 255.0));
    if ((flags & 128u) != 0u || material.a <= 0.01) return;
    float depth = texelFetch(depthtex0, receiverPixel, 0).r;
    if (depth >= 0.999999) return;
    float opaqueDepth = texelFetch(depthtex1, receiverPixel, 0).r;
    if (depth == opaqueDepth) {
        vec3 worldNormal=decode_unit_vector(material.gb*2.0-1.0);
        vec3 normal = normalize(player_view(worldNormal));
        vec2 receiverUV = (vec2(receiverPixel)+0.5) / vec2(textureSize(depthtex0,0));
        vec3 viewPos = screen_view(vec3(receiverUV, depth));
        // Fresnel, ray setup and virtual-image reprojection share the receiver.
        vec3 viewDirection = normalize(viewPos);
        float viewDistance = length(viewPos);
        float fresnel = clamp(1.0+dot(normal,viewDirection),0.0,1.0);
        float f = nether_rock_fresnel(fresnel,viewDistance,material.a);
        if (f > 0.002) {
            const float golden=1.61803398875;
            // Reduce the integer first so long sessions retain every frame phase.
            float phase=golden*float(frameCounter % 3600);
            float dither=fract(textureLod(solasWaterNoise,gl_FragCoord.xy/512.0,0.0).b+phase);
            vec2 coord=gl_FragCoord.xy/128.0;
            vec3 roughNoise=vec3(textureLod(solasWaterNoise,coord,0.0).r,
                textureLod(solasWaterNoise,coord+0.09375,0.0).r,
                textureLod(solasWaterNoise,coord+0.1875,0.0).r);
            roughNoise=fract(roughNoise+vec3(dither,dither*golden,dither*golden*golden));
            roughNoise=0.3*(1.0-material.a)*(1.0-material.a)*(roughNoise-0.5);
            float refDist;
            vec4 hit=nether_rock_trace(viewPos,viewDirection,viewDistance,
                normalize(normal+roughNoise),fresnel,material.a,dither,refDist);
            float linearZ=astra_effect_linear_depth(opaqueDepth);
            reflection=vec4(srgb_encode(max(hit.rgb,vec3(0.0)))*hit.a,linearZ);
            metadata=astra_nether_receiver_record(material.gb,flags,hit.a);
            if(effectFrameValid != 0) {
                // Complementary's virtual image, not just the receiver position.
                refDist=min(refDist,max(far-viewDistance,0.0));
                vec3 virtualPoint=view_camera_relative(viewPos+refDist*viewDirection);
                vec3 previous=astra_effect_previous_screen(virtualPoint);
                vec2 size=vec2(textureSize(colortex9,0));
                if(!any(isnan(previous)) && !any(isinf(previous))
                    && all(greaterThanEqual(previous,vec3(0.0))) && all(lessThanEqual(previous,vec3(1.0)))) {
                    #if NETHER_REFLECTION_QUALITY < 2
                    const int historyStride = 2;
                    #else
                    const int historyStride = 1;
                    #endif
                    // History locations follow the same lattice, including its
                    // half-pixel source centres. Unwritten pixels are never taps.
                    vec2 grid=(previous.xy*size-0.5)/float(historyStride);
                    vec2 frac=fract(grid);
                    frac=frac*frac*(3.0-2.0*frac);
                    frac=frac*frac*(3.0-2.0*frac);
                    ivec2 base=ivec2(floor(grid))*historyStride;
                    vec3 receiverPrevious=astra_effect_previous_screen(view_camera_relative(viewPos));
                    vec4 previousHeuristic=gbufferProjection*gbufferModelView*vec4(
                        virtualPoint+normalize(previousCameraPosition-cameraPosition-virtualPoint)*refDist,1.0);
                    vec2 heuristicUV=previousHeuristic.xy/max(previousHeuristic.w,0.00001)*0.5+0.5;
                    float expectedZ=astra_effect_linear_depth(receiverPrevious.z);
                    float sharedPenalty=-0.03*length(size*(previous.xy-texcoord))
                        -min(0.75,10.0*sqrt(length(cameraPosition-previousCameraPosition)))
                        -0.003*length(size*(receiverPrevious.xy-texcoord))
                        -10.0*length(heuristicUV-clamp(heuristicUV,0.0,1.0));
                    vec3 colorCorrection=vec3(0.0);
                    float coverageCorrection=0.0;
                    float minimumNewWeight=0.035+0.09*pow8(material.a);
                    // Geometry validity belongs to each texel. Filtering normals
                    // and depth first can fabricate a matching surface at an edge.
                    // Invalid reprojection made every old weight zero already.
                    // Normal/depth penalties are non-positive, so this is the
                    // largest possible validity of any history contributor.
                    // At or below minimumNewWeight every old weight is zero.
                    if(previousHeuristic.w>0.00001 && receiverPrevious.z>=0.0) {
                        float minimumLogValidity=log(minimumNewWeight);
                        if(sharedPenalty>minimumLogValidity) {
                            // Depth can only lower this validity. Reject a normal
                            // whose best possible old weight is already zero before
                            // fetching the separate colour/depth history payload.
                            for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
                                ivec2 pixel=base+ivec2(x,y)*historyStride;
                                if(any(lessThan(pixel,ivec2(0))) || any(greaterThanEqual(pixel,ivec2(size)))) continue;
                                vec2 axis=mix(1.0-frac,frac,bvec2(x==1,y==1));
                                float spatialWeight=axis.x*axis.y;
                                if(spatialWeight<=0.0) continue;
                                vec4 oldMeta=texelFetch(colortex28,pixel,0);
                                if(!astra_nether_receiver_valid(oldMeta)
                                    || astra_nether_receiver_flags(oldMeta)!=flags) continue;
                                vec3 oldNormal=astra_nether_receiver_normal(oldMeta);
                                float normalPenalty=sharedPenalty-12.0*length(worldNormal-oldNormal);
                                if(normalPenalty<=minimumLogValidity) continue;
                                vec4 old=texelFetch(colortex9,pixel,0);
                                if(any(isnan(old)) || any(isinf(old)) || old.a<=0.0) continue;
                                float valid=exp(normalPenalty-abs(old.a-expectedZ)*far);
                                float newWeight=clamp(minimumNewWeight/max(valid,0.00001),0.0,1.0);
                                float weight=spatialWeight*(1.0-newWeight);
                                colorCorrection+=(old.rgb-reflection.rgb)*weight;
                                coverageCorrection+=(oldMeta.a-metadata.a)*weight;
                            }
                        }
                    }
                    reflection.rgb+=colorCorrection;
                    metadata.a+=coverageCorrection;
                }
            }
        }
    }
#endif
    gl_FragData[0] = reflection;
    gl_FragData[1] = metadata;
}
