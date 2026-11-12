#ifndef ASTRA_SMAA_BLEND_GLSL
#define ASTRA_SMAA_BLEND_GLSL
// Neighbourhood weights follow SMAA 1x (Jorge Jimenez et al., MIT-style licence).
// Astra adapts the final one-axis interpolation to encoded display input:
// decode the three contributing texels, blend linear light, then encode once.
// At pixel centres this is the same two bilinear lobes with three scene reads.
vec3 astra_smaa_blend(sampler2D scene,sampler2D weights,vec2 uv) {
    ivec2 size=textureSize(scene,0);
    ivec2 pixel=clamp(ivec2(uv*vec2(size)),ivec2(0),size-1);
    vec3 center=texelFetch(scene,pixel,0).rgb;
    vec4 own=texelFetch(weights,pixel,0);
    vec4 a=vec4(texelFetch(weights,min(pixel+ivec2(1,0),size-1),0).a,
                texelFetch(weights,min(pixel+ivec2(0,1),size-1),0).g,own.b,own.r);
    if (dot(a,vec4(1.0)) < 0.00001) return center;
    bool horizontal=max(a.x,a.z)>max(a.y,a.w);
    vec2 w=horizontal ? a.xz : a.yw;
    ivec2 axis=horizontal ? ivec2(1,0) : ivec2(0,1);
    vec3 positive=texelFetch(scene,min(pixel+axis,size-1),0).rgb;
    vec3 negative=texelFetch(scene,max(pixel-axis,ivec2(0)),0).rgb;
    vec3 linearCenter=srgb_decode(center);
    vec3 color=mix(linearCenter,srgb_decode(positive),w.x)*w.x
              +mix(linearCenter,srgb_decode(negative),w.y)*w.y;
    return srgb_encode(color/max(w.x+w.y,0.00001));
}
#endif
