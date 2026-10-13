#ifndef ASTRA_GLOBAL_WATER_CAUSTICS_GLSL
#define ASTRA_GLOBAL_WATER_CAUSTICS_GLSL
// Adapted from Solas V2.2b waterNormals.glsl / waterCaustics.glsl by Septonious.
// Solas bump, offsets and noise scales remain for side faces/other dimensions.
// Bed caustics retain Astra's optical wave-lens model. The submerged interface
// and the volume use the ITT wave-normal implementation in itt_water_waves.glsl.
#include "/lib/water_palette.glsl"
#include "/lib/water_wave_lens.glsl"
// Surface-only band limit.
// Solas samples implicitly; the earlier Astra adapter forced LOD 0 everywhere.
// A custom noise image has no mip chain, so fade unresolved octave variance
// toward its mean rather than asking textureGrad for unavailable mip levels.
float solas_water_surface_height_resolved(vec3 p, vec2 offset, vec2 resolved) {
    vec2 wind=vec2(frameTimeCounter*0.75*(WATER_WAVE_SPEED*0.01));
    p.xz-=p.y*0.2;
    offset/=256.0;
    // Fully filtered octaves retain their mean without reading their noise.
    float a=0.5, b=0.5;
    if(resolved.x>0.0)
        a=mix(0.5,textureLod(solasWaterNoise,(p.xz-wind)/256.0+offset,0.0).g,resolved.x);
    if(resolved.y>0.0)
        b=mix(0.5,textureLod(solasWaterNoise,(p.xz+wind)/48.0+offset,0.0).g,resolved.y);
    return mix(a,b,0.40)*0.4*(WATER_WAVE_HEIGHT*0.01);
}
float solas_water_surface_height(vec3 p, vec2 offset, vec2 footprint) {
    vec2 resolved=vec2(1.0)-smoothstep(vec2(0.5),vec2(2.0),footprint);
    return solas_water_surface_height_resolved(p,offset,resolved);
}
vec3 solas_water_normal(vec3 worldPos, vec3 face, vec3 tangent, vec3 binormal,
                        vec3 viewVector, float viewDistance, float fresnel, vec2 footprint) {
    // Four parallax heights and four finite-difference heights share this filter.
    vec2 resolved=vec2(1.0)-smoothstep(vec2(0.5),vec2(2.0),footprint);
    // A constant height field has zero finite differences. Its normal remains
    // the supplied face, so distant pixels need no parallax or height arithmetic.
    if (all(lessThanEqual(resolved, vec2(0.0)))) return face;
    vec2 parallaxStep = viewVector.xy / max(viewDistance, 0.0001);
    for (int i = 0; i < 4; ++i) {
        float height = -1.25 * solas_water_surface_height_resolved(worldPos,vec2(0.0),resolved) + 0.25;
        worldPos.xz += height * parallaxStep;
    }
    float x = (solas_water_surface_height_resolved(worldPos,vec2(-0.5,0.0),resolved) - solas_water_surface_height_resolved(worldPos,vec2(0.5,0.0),resolved)) / 0.5;
    float y = (solas_water_surface_height_resolved(worldPos,vec2(0.0,-0.5),resolved) - solas_water_surface_height_resolved(worldPos,vec2(0.0,0.5),resolved)) / 0.5;
    return normalize(tangent * x + binormal * y + face * (1.0 - x*x - y*y - fresnel * 0.5));
}
// Water shadow records cache only the bed's scalar caustic focus. Volume beams
// build a separate water-entry optical cache, so a caster's GB has no reader.
// The unused slope lets the compiler omit gradient-only work
// when this surface helper builds the cached focus.
float astra_water_caustic_focus(vec3 worldPos, float footprint) {
    #ifndef WATER_CAUSTICS
    return 1.0;
    #else
    vec2 slope;
    mat2 curvature;
    astra_water_wave_lens(worldPos.xz, footprint, slope, curvature);
    // A wave's curvature changes the area of the refracted mapping. Bounded
    // reciprocal area makes broad moving ridges and dim gaps, rather than
    // independent high-frequency bright dots.
    return astra_water_wave_focus(curvature);
    #endif
}
#endif
