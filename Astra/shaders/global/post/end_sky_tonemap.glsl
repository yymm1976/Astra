#ifndef ASTRA_END_SKY_TONEMAP_GLSL
#define ASTRA_END_SKY_TONEMAP_GLSL
// Astra sky-only chromaticity-preserving shoulder. Per-channel shoulders drove
// the shifted disc's three bright bands toward the same white ceiling.
vec3 astra_end_sky_tonemap(vec3 hdr) {
    hdr=max(hdr,vec3(0.0));
    float luminance=dot(hdr,vec3(0.2126,0.7152,0.0722));
    float mapped=apply_tonemap(vec3(luminance)).r;
    vec3 color=hdr*(mapped/max(luminance,0.000001));
    // Fit the display gamut with one scalar, preserving ratios. Do not clip
    // individual colour channels back to a neutral white highlight.
    return color/max(max(color.r,max(color.g,color.b)),1.0);
}
#endif
