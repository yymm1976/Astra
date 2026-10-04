#ifndef ASTRA_FXAA_GLSL
#define ASTRA_FXAA_GLSL
// Adapted from Arc v0.15.2, shaders/lib/fxaa_2.glsl (FXAA edge search).
// Astra: display RGB + luma in alpha, clamped coordinates, bounded search,
// softer subpixel weight. No HDR/log decode or exposure multiplication here.
// SPDX-License-Identifier: MIT; Copyright (c) 2022 Minecraft / Shaders
// Full license: /lib/vendor/arc/LICENSE.txt

vec4 astra_fxaa_sample(sampler2D source, vec2 uv, vec2 texel) {
    return textureLod(source,clamp(uv,0.5*texel,1.0-0.5*texel),0.0);
}
vec3 astra_fxaa(sampler2D source, vec2 uv, bool geometryOnly) {
    vec2 texel = 1.0/vec2(textureSize(source,0));
    vec4 center = astra_fxaa_sample(source,uv,texel);
    if (geometryOnly) {
        // Underwater caustics and block texels are colour detail, not geometry
        // edges. Restrict AA to depth silhouettes instead of shifting all detail.
        float depth = textureLod(depthtex0, uv, 0.0).r;
        float delta = max(max(abs(textureLod(depthtex0, uv+vec2(texel.x,0),0.0).r-depth),
                              abs(textureLod(depthtex0, uv-vec2(texel.x,0),0.0).r-depth)),
                          max(abs(textureLod(depthtex0, uv+vec2(0,texel.y),0.0).r-depth),
                              abs(textureLod(depthtex0, uv-vec2(0,texel.y),0.0).r-depth)));
        if (delta < max((1.0-depth)*0.08, 0.00001)) return center.rgb;
    }
    float m = center.a;
    float n = astra_fxaa_sample(source,uv+vec2(0.0,texel.y),texel).a;
    float s = astra_fxaa_sample(source,uv-vec2(0.0,texel.y),texel).a;
    float e = astra_fxaa_sample(source,uv+vec2(texel.x,0.0),texel).a;
    float w = astra_fxaa_sample(source,uv-vec2(texel.x,0.0),texel).a;
    float low = min(m,min(min(n,s),min(e,w)));
    float high = max(m,max(max(n,s),max(e,w)));
    float contrast = high-low;
    if (contrast < max(0.0312,high*0.125)) return center.rgb;
    float ne = astra_fxaa_sample(source,uv+texel,texel).a;
    float nw = astra_fxaa_sample(source,uv+texel*vec2(-1.0,1.0),texel).a;
    float se = astra_fxaa_sample(source,uv+texel*vec2(1.0,-1.0),texel).a;
    float sw = astra_fxaa_sample(source,uv-texel,texel).a;
    float horizontal = abs(nw+sw-2.0*w)+2.0*abs(n+s-2.0*m)+abs(ne+se-2.0*e);
    float vertical = abs(nw+ne-2.0*n)+2.0*abs(w+e-2.0*m)+abs(sw+se-2.0*s);
    bool alongX = horizontal >= vertical;
    float first = alongX ? s : w;
    float second = alongX ? n : e;
    float g1 = first-m, g2 = second-m;
    bool useFirst = abs(g1) >= abs(g2);
    float gradient = max(abs(g1),abs(g2))*0.25;
    float localAverage = 0.5*(m+(useFirst ? first : second));
    vec2 across = alongX ? vec2(0.0,texel.y) : vec2(texel.x,0.0);
    if (useFirst) across = -across;
    vec2 along = alongX ? vec2(texel.x,0.0) : vec2(0.0,texel.y);
    vec2 edgeCenter = uv+0.5*across;
    float distanceA = 1.0, distanceB = 1.0;
    float deltaA = 0.0, deltaB = 0.0;
    bool doneA = false, doneB = false;
    // At most 24 luma reads. Never advance a distance after its final sampled point.
    for (int i=0;i<12;i++) {
        if (!doneA) {
            deltaA = astra_fxaa_sample(source,edgeCenter-along*distanceA,texel).a-localAverage;
            doneA = abs(deltaA) >= gradient;
        }
        if (!doneB) {
            deltaB = astra_fxaa_sample(source,edgeCenter+along*distanceB,texel).a-localAverage;
            doneB = abs(deltaB) >= gradient;
        }
        if ((doneA && doneB) || i==11) break;
        float stride = i < 4 ? 1.0 : (i==4 ? 1.5 : (i<9 ? 2.0 : 4.0));
        if (!doneA) distanceA += stride;
        if (!doneB) distanceB += stride;
    }
    bool closerA = distanceA < distanceB;
    bool validEdge = (closerA ? doneA : doneB)
                  && (((closerA ? deltaA : deltaB) < 0.0) != (m < localAverage));
    float edgeOffset = validEdge ? 0.5-min(distanceA,distanceB)/(distanceA+distanceB) : 0.0;
    float average = (2.0*(n+s+e+w)+ne+nw+se+sw)/12.0;
    float subpixel = clamp(abs(average-m)/contrast,0.0,1.0);
    subpixel = subpixel*subpixel*(3.0-2.0*subpixel);
    float offset = geometryOnly ? edgeOffset : max(edgeOffset,subpixel*subpixel*0.5);
    if (offset <= 0.0) return center.rgb;
    return astra_fxaa_sample(source,uv+across*offset,texel).rgb;
}
#endif
