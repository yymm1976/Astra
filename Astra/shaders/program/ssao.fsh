// Original Astra current-frame contact AO. Opaque terrain only; no TAA dependency.
// R1: with DIRECTIONAL_SKYLIGHT also on, the same kernel additionally produces a
// bent normal (colortex26) - the visibility-weighted mean direction of the sampled
// unoccluded set around the geometric normal, consumed by the deferred2 SH sky
// re-evaluation. AO alone is unchanged and never pays for it.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/transforms.glsl"
#include "/lib/encoding.glsl"
#include "/global/water/medium_state.glsl"
uniform sampler2D colortex20;
in vec2 texcoord;
#ifndef RGBA16F
const int RGBA16F = 0;
#endif
const int colortex21Format = RGBA16F;
#ifdef ASTRA_DIRECTIONAL_SKYLIGHT
const int colortex26Format = RGBA16F;
/* RENDERTARGETS: 21,26 */
#else
/* RENDERTARGETS: 21 */
#endif
// Fixed golden-angle disk. Keep the original expressions as constants rather
// than rounded coordinates; every receiver uses the same twelve offsets.
const vec2 ASTRA_AO_SAMPLE_DISK[12] = vec2[12](
    vec2(cos(0.0*2.39996323),sin(0.0*2.39996323))*sqrt((0.0+0.5)/12.0),
    vec2(cos(1.0*2.39996323),sin(1.0*2.39996323))*sqrt((1.0+0.5)/12.0),
    vec2(cos(2.0*2.39996323),sin(2.0*2.39996323))*sqrt((2.0+0.5)/12.0),
    vec2(cos(3.0*2.39996323),sin(3.0*2.39996323))*sqrt((3.0+0.5)/12.0),
    vec2(cos(4.0*2.39996323),sin(4.0*2.39996323))*sqrt((4.0+0.5)/12.0),
    vec2(cos(5.0*2.39996323),sin(5.0*2.39996323))*sqrt((5.0+0.5)/12.0),
    vec2(cos(6.0*2.39996323),sin(6.0*2.39996323))*sqrt((6.0+0.5)/12.0),
    vec2(cos(7.0*2.39996323),sin(7.0*2.39996323))*sqrt((7.0+0.5)/12.0),
    vec2(cos(8.0*2.39996323),sin(8.0*2.39996323))*sqrt((8.0+0.5)/12.0),
    vec2(cos(9.0*2.39996323),sin(9.0*2.39996323))*sqrt((9.0+0.5)/12.0),
    vec2(cos(10.0*2.39996323),sin(10.0*2.39996323))*sqrt((10.0+0.5)/12.0),
    vec2(cos(11.0*2.39996323),sin(11.0*2.39996323))*sqrt((11.0+0.5)/12.0));
void main() {
    gl_FragData[0] = vec4(1.0, -1.0, 0.5, 0.5);
    #ifdef ASTRA_DIRECTIONAL_SKYLIGHT
    // Never read where colortex21.g < 0 (the scalar record is equally invalid
    // here), so the fallback payload only has to be a decodable direction.
    gl_FragData[1] = vec4(0.5, 0.5, 0.0, 1.0);
    #endif
    if (isEyeInWater != 0 && !water_is_thin_sheet()) return;
    ivec2 size = textureSize(depthtex0, 0);
    ivec2 base = ivec2(gl_FragCoord.xy) * 2;
    ivec2 pixel = clamp(base, ivec2(0), size-1);
    float depth = 1.0;
    vec3 encodedNormal = vec3(0.5, 1.0, 0.5);
    // Pair normal and depth from the same nearest eligible full-resolution texel.
    for (int y=0; y<2; ++y) for (int x=0; x<2; ++x) {
        ivec2 p = clamp(base + ivec2(x,y), ivec2(0), size-1);
        float d = texelFetch(depthtex0,p,0).r;
        // Farther candidates cannot replace the selected receiver.
        if (d >= depth) continue;
        vec4 n = texelFetch(colortex20,p,0);
        if (n.a > 0.5 && d < depth) {
            pixel=p; depth=d; encodedNormal=n.rgb;
        }
    }
    if (depth >= 0.999999) return;
    vec3 worldNormal=normalize(encodedNormal*2.0-1.0);
    vec2 uv=(vec2(pixel)+0.5)/vec2(size);
    vec3 centre=screen_view(vec3(uv,depth));
    vec3 normal=normalize(player_view(worldNormal));
    float radius=AO_RADIUS*0.01;
    vec2 screenRadius=radius*0.5*vec2(gbufferProjection[0][0],gbufferProjection[1][1])
                    /max(-centre.z,0.2);
    screenRadius=min(screenRadius,vec2(0.125));
    float blocked=0.0;
    #ifdef ASTRA_DIRECTIONAL_SKYLIGHT
    // Bent-normal estimator. visibleDir accumulates sum(v_i * dir_i) over the
    // FORWARD hemisphere only; each contributing direction is the unit direction
    // to a real scene sample weighted by that direction's own unoccluded
    // fraction - never an unweighted depth difference.
    vec3 visibleDir=vec3(0.0);
    float visibleWeight=0.0;
    #endif
    for(int i=0;i<12;++i) {
        vec2 sampleUV=uv+ASTRA_AO_SAMPLE_DISK[i]*screenRadius;
        if(any(lessThan(sampleUV,vec2(0.0))) || any(greaterThanEqual(sampleUV,vec2(1.0)))) continue;
        ivec2 q=ivec2(sampleUV*vec2(size));
        // This exact receiver would reconstruct delta=0 and be rejected below.
        if (all(equal(q,pixel))) continue;
        #ifdef ASTRA_DIRECTIONAL_SKYLIGHT
        // Eligibility must precede the visible-direction accumulation below.
        if(texelFetch(colortex20,q,0).a < 0.5) continue;
        #endif
        float d=texelFetch(depthtex0,q,0).r;
        if(d >= 0.999999) continue;
        vec2 sampleCentre=(vec2(q)+0.5)/vec2(size);
        vec3 delta=screen_view(vec3(sampleCentre,d))-centre;
        float distanceSquared=dot(delta,delta);
        if(distanceSquared < 0.0001) continue;
        #ifdef ASTRA_DIRECTIONAL_SKYLIGHT
        vec3 direction=delta*inversesqrt(distanceSquared);
        bool forward=dot(normal,direction) > 0.0;
        if(distanceSquared >= radius*radius) {
            // Beyond the kernel radius there is no occluder information; the
            // scalar AO below also treats that as unoccluded, so the direction
            // counts as fully visible (forward hemisphere only).
            if (forward) { visibleDir+=direction; visibleWeight+=1.0; }
            continue;
        }
        #else
        if(distanceSquared >= radius*radius) continue;
        // Scalar AO has no contribution below this existing angular bias.
        // Bent-normal mode still needs those visible forward directions.
        if(dot(normal,delta) <= 0.035) continue;
        // Scalar AO has no contribution until all geometric rejections pass.
        if(texelFetch(colortex20,q,0).a < 0.5) continue;
        #endif
        float angleWeight=max(dot(normal,delta)-0.035,0.0)*inversesqrt(distanceSquared);
        #ifdef ASTRA_DIRECTIONAL_SKYLIGHT
        float sampleBlocked=angleWeight*(1.0-distanceSquared/(radius*radius));
        blocked+=sampleBlocked;
        if (forward) {
            // Same (2.5/12)-scale convention as the scalar resolve: one sample
            // spanning the kernel along a direction reaches v=0. AO_STRENGTH is
            // deliberately excluded - the bent direction stays a geometric
            // quantity independent of the strength slider.
            float seen=1.0-min(sampleBlocked*2.5,1.0);
            visibleDir+=direction*seen; visibleWeight+=seen;
        }
        #else
        blocked+=angleWeight*(1.0-distanceSquared/(radius*radius));
        #endif
    }
    float visibility=clamp(1.0-blocked*(2.5/12.0)*(AO_STRENGTH*0.01),0.25,1.0);
    gl_FragData[0]=vec4(visibility,log2(1.0+max(-centre.z,0.0)),
                        encode_unit_vector(worldNormal)*0.5+0.5);
    #ifdef ASTRA_DIRECTIONAL_SKYLIGHT
    // Degenerate -> the selected texel's geometric normal: no substantially
    // visible sample (enclosed corner), or no net direction (flat/symmetric
    // ring where the weighted sum cancels). view_player is direction-only, so
    // the result is a player-relative world-space unit vector.
    vec3 bentWorld=worldNormal;
    if (visibleWeight > 0.5 && length(visibleDir) > 0.25)
        bentWorld=normalize(view_player(visibleDir));
    gl_FragData[1]=vec4(encode_unit_vector(bentWorld)*0.5+0.5,visibleWeight,1.0);
    #endif
}
