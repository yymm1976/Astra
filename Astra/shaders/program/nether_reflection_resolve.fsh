// Adapted from Complementary composite1 + reflectionBlurFilter by EminGT.
// Filter reflection pixels on the receiving rock, never the emitter image.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/encoding.glsl"
#include "/lib/transforms.glsl"
#include "/lib/nether_reflection_metadata.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D colortex9;
uniform sampler2D colortex28;
#include "/global/dimension/nether_reflection.glsl"
in vec2 texcoord;
/* RENDERTARGETS: 0 */
void main() {
    vec3 source = textureLod(colortex0,texcoord,0.0).rgb;
    gl_FragData[0] = vec4(source,1.0);
#ifdef NETHER_ROCK_REFLECTIONS
    if (DEBUG_VERTEX_AO != 0 || isEyeInWater != 0) return;
    ivec2 receiverPixel = clamp(ivec2(texcoord * vec2(textureSize(depthtex0,0))),
                                ivec2(0),textureSize(depthtex0,0)-1);
    vec4 material = texelFetch(colortex3,receiverPixel,0);
    // R packs skylight plus the hand bit, not a material ID. Receiver eligibility
    // additionally uses roughness, the current opaque mask, normal and plane.
    uint flags = uint(round(material.r*255.0));
    if ((flags & 128u) != 0u || material.a <= 0.01) return;
    float depth = texelFetch(depthtex0,receiverPixel,0).r;
    if (depth >= 0.999999 || depth != texelFetch(depthtex1,receiverPixel,0).r) return;
    {
        vec3 worldNormal = decode_unit_vector(material.gb*2.0-1.0);
        vec2 receiverUV = (vec2(receiverPixel)+0.5) / vec2(textureSize(depthtex0,0));
        vec3 viewPos = screen_view(vec3(receiverUV,depth));
        float fresnel = clamp(1.0+dot(normalize(player_view(worldNormal)),normalize(viewPos)),0.0,1.0);
        float f = nether_rock_fresnel(fresnel,length(viewPos),material.a);
        if (f > 0.002) {
            vec2 size = vec2(textureSize(colortex9,0));
            float radius = 12.0*(1.0-0.75*pow8(material.a));
            #if NETHER_REFLECTION_QUALITY == 2
            vec2 stride = 0.5*radius/size;
            #endif
            ivec2 extent = textureSize(colortex9,0);
            // Move the rotation out of the per-contributor plane comparison.
            vec3 planeNormal = transpose(mat3(gbufferModelViewInverse))*worldNormal;
            // Compare the contributor to this plane in homogeneous space.
            // |n.point-d| <= tolerance is |planeClip.ndc| <= tolerance*|w|;
            // no full XYZ reconstruction or divide is needed for each tap.
            mat4 inverseRows = transpose(gbufferProjectionInverse);
            vec4 planeClip = inverseRows * vec4(planeNormal,-dot(viewPos,planeNormal));
            vec4 inverseWRow = inverseRows[3];
            vec2 jitter = astra_jitter_uv();
            // exp(-x*x/12.5), for |x|=0,1,2. The 2D Gaussian is separable.
            const float kernelAxis[3] = float[3](1.0,0.9231163464,0.7261490371);
            vec4 sum = vec4(0.0); float total = 0.0;
            #if NETHER_REFLECTION_QUALITY < 2
            #if NETHER_REFLECTION_QUALITY == 0
            // Five footprints on the 2x2 lattice: at most 20 contributors.
            // Match the nine-footprint kernel's energy and per-axis variance;
            // diagonal isolated reflections may contribute less. Keep every
            // contributor's receiver/depth checks before colour interpolation.
            for (int tap=0;tap<5;tap++) {
                vec2 offset = tap == 0 ? vec2(0.0)
                    : (tap == 1 ? vec2(-1.0,0.0) : (tap == 2 ? vec2(1.0,0.0)
                    : (tap == 3 ? vec2(0.0,-1.0) : vec2(0.0,1.0))));
                // sqrt(2)*0.943634 keeps variance at 0.5*(0.943634*radius)^2.
                vec2 location = (texcoord*size-0.5+offset*(radius*1.33450000))*0.5;
                ivec2 basePixel = ivec2(floor(location))*2;
                vec2 fraction = fract(location);
                float kernel = tap == 0 ? 0.5 : 0.125;
            #else
            // Nine regions retain diagonal highlights on the same sparse ray
            // lattice. The separable weights sum to one and match the low
            // kernel's per-axis variance without broadening its blur.
            for (int y=-1;y<=1;y++) for (int x=-1;x<=1;x++) {
                vec2 offset=vec2(x,y)*(radius*0.943634);
                vec2 location=(texcoord*size-0.5+offset)*0.5;
                ivec2 basePixel=ivec2(floor(location))*2;
                vec2 fraction=fract(location);
                float kernel=(x==0 ? 0.5 : 0.25)*(y==0 ? 0.5 : 0.25);
            #endif
                const int contributorStride = 2;
            #else
            for (int y=-2;y<=2;y++) for (int x=-2;x<=2;x++) {
                vec2 uv = texcoord+vec2(x,y)*stride;
                if (any(lessThan(uv,0.5/size)) || any(greaterThan(uv,1.0-0.5/size))) continue;
                vec2 location = uv*size-0.5;
                ivec2 basePixel = ivec2(floor(location));
                vec2 fraction = fract(location);
                float kernel = kernelAxis[abs(x)]*kernelAxis[abs(y)];
                const int contributorStride = 1;
            #endif
                // Validate the contributors of each footprint before combining
                // their colours. Filtered flags/normals can invent a receiver
                // between rock and a foreground silhouette.
                for (int cy=0;cy<2;cy++) for (int cx=0;cx<2;cx++) {
                    vec2 axis = mix(1.0-fraction,fraction,bvec2(cx==1,cy==1));
                    float weight = kernel*axis.x*axis.y;
                    if (weight <= 0.000001) continue;
                    ivec2 pixel = basePixel+ivec2(cx,cy)*contributorStride;
                    if (any(lessThan(pixel,ivec2(0))) || any(greaterThanEqual(pixel,extent))) continue;
                    // The CURRENT-frame record proves opaque receiver eligibility
                    // and carries the same material flags as the original source.
                    // Use that eligibility before fetching geometry or colour.
                    vec4 metadata = texelFetch(colortex28,pixel,0);
                    if (!astra_nether_receiver_valid(metadata)
                        || astra_nether_receiver_flags(metadata) != flags) continue;
                    bool sameReceiver = all(equal(pixel,receiverPixel));
                    // Reject the producer's normal before querying depth.
                    vec3 otherNormal = sameReceiver ? worldNormal : astra_nether_receiver_normal(metadata);
                    vec3 normalDelta = worldNormal-otherNormal;
                    if (dot(normalDelta,normalDelta) > 0.1*0.1) continue;
                    // The producer only writes this record after smoothness > .01,
                    // opaque depth and hand checks. No repeated material read.
                    float z = sameReceiver ? depth : texelFetch(depthtex0,pixel,0).r;
                    if (z >= 0.999999) continue;
                    vec2 pixelUV = (vec2(pixel)+0.5)/size;
                    // Preserve coplanar rocks across perspective depth changes,
                    // while rejecting detached ledges.
                    if (!sameReceiver) {
                        vec4 ndc = vec4((pixelUV-jitter)*2.0-1.0,z*2.0-1.0,1.0);
                        if (abs(dot(planeClip,ndc)) > 0.15*abs(dot(inverseWRow,ndc))) continue;
                    }
                    vec4 carrier = texelFetch(colortex9,pixel,0);
                    if (any(isnan(carrier)) || any(isinf(carrier))) continue;
                    sum += vec4(carrier.rgb,metadata.a)*weight;
                    total += weight;
                }
            }
            // Without a surviving contributor the original blend weight is zero.
            // Keep the source already written above and skip both colour conversions.
            if (total <= 0.0) return;
            vec4 reflected = sum/max(total,0.0001);
            // Valid receiver normals can carry a fully missed reflection. Their
            // weights still participate above, but zero coverage cannot blend colour.
            if (reflected.a <= 0.0) return;
            vec3 base = srgb_encode(max(source,vec3(0.0)));
            vec3 color = reflected.rgb/max(reflected.a,0.0001);
            color = mix(color,max(base,color),0.7);
            // Restore the reference response now that rough directions accumulate.
            // No emitter intensity is increased, and the original texture remains.
            source = srgb_decode(mix(base,color,f*reflected.a));
        }
    }
#endif
    gl_FragData[0] = vec4(source,1.0);
}
