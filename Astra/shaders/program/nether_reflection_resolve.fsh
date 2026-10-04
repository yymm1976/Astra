// Adapted from Complementary composite1 + reflectionBlurFilter by EminGT.
// Filter reflection pixels on the receiving rock, never the emitter image.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/encoding.glsl"
#include "/lib/transforms.glsl"
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
#ifdef SCREENSPACE_REFLECTIONS
    if (DEBUG_VERTEX_AO != 0 || isEyeInWater != 0) return;
    vec4 material = textureLod(colortex3,texcoord,0.0);
    uint flags = uint(round(material.r*255.0));
    if ((flags & 128u) != 0u || material.a <= 0.01) return;
    float depth = textureLod(depthtex0,texcoord,0.0).r;
    if (depth >= 0.999999 || depth != textureLod(depthtex1,texcoord,0.0).r) return;
    {
        vec3 worldNormal = decode_unit_vector(material.gb*2.0-1.0);
        vec3 viewPos = screen_view(vec3(texcoord,depth));
        float fresnel = clamp(1.0+dot(normalize(player_view(worldNormal)),normalize(viewPos)),0.0,1.0);
        float f = nether_rock_fresnel(fresnel,length(viewPos),material.a);
        if (f > 0.002) {
            vec2 size = vec2(textureSize(colortex9,0));
            vec2 stride = 6.0*(1.0-0.75*pow(material.a,8.0))/size;
            ivec2 extent = textureSize(colortex9,0);
            // Move the rotation out of the per-contributor plane comparison.
            vec3 planeNormal = transpose(mat3(gbufferModelViewInverse))*worldNormal;
            // exp(-x*x/12.5), for |x|=0,1,2. The 2D Gaussian is separable.
            const float kernelAxis[3] = float[3](1.0,0.9231163464,0.7261490371);
            vec4 sum = vec4(0.0); float total = 0.0;
            for (int y=-2;y<=2;y++) for (int x=-2;x<=2;x++) {
                vec2 uv = texcoord+vec2(x,y)*stride;
                if (any(lessThan(uv,0.5/size)) || any(greaterThan(uv,1.0-0.5/size))) continue;
                vec2 location = uv*size-0.5;
                ivec2 basePixel = ivec2(floor(location));
                vec2 fraction = fract(location);
                float kernel = kernelAxis[abs(x)]*kernelAxis[abs(y)];
                // Validate the contributors of each footprint before combining
                // their colours. Filtered flags/normals can invent a receiver
                // between rock and a foreground silhouette.
                for (int cy=0;cy<2;cy++) for (int cx=0;cx<2;cx++) {
                    vec2 axis = mix(1.0-fraction,fraction,bvec2(cx==1,cy==1));
                    float weight = kernel*axis.x*axis.y;
                    if (weight <= 0.000001) continue;
                    ivec2 pixel = basePixel+ivec2(cx,cy);
                    if (any(lessThan(pixel,ivec2(0))) || any(greaterThanEqual(pixel,extent))) continue;
                    // composite's metadata is CURRENT-frame data here. A unit
                    // normal is written only for an opaque, non-hand receiver
                    // with depthtex0 == depthtex1; all other pixels write zero.
                    // Use that eligibility before fetching geometry or colour.
                    vec4 metadata = texelFetch(colortex28,pixel,0);
                    if (any(isnan(metadata)) || any(isinf(metadata))
                        || dot(metadata.rgb,metadata.rgb) <= 0.81
                        || metadata.a < 0.0 || metadata.a > 1.0) continue;
                    // Reject the producer's normal before querying material/depth.
                    vec3 otherNormal = metadata.rgb;
                    vec3 normalDelta = worldNormal-otherNormal;
                    if (dot(normalDelta,normalDelta) > 0.1*0.1) continue;
                    vec4 other = texelFetch(colortex3,pixel,0);
                    if (other.a <= 0.01 || uint(round(other.r*255.0)) != flags) continue;
                    float z = texelFetch(depthtex0,pixel,0).r;
                    if (z >= 0.999999) continue;
                    vec2 pixelUV = (vec2(pixel)+0.5)/size;
                    vec3 point = screen_view(vec3(pixelUV,z));
                    // Preserve coplanar rocks across perspective depth changes,
                    // while rejecting detached ledges.
                    if (abs(dot(point-viewPos,planeNormal)) > 0.15) continue;
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
