#ifndef ASTRA_END_DISC_PROFILE_GLSL
#define ASTRA_END_DISC_PROFILE_GLSL
// Shared verbatim with the offline path builder. Lengths are shadow-radius units.
// 2026-09-23: 0.414213562 put the silhouette radius at 22.5 degrees, i.e. a 45-degree
// black disc with the whole disc body reaching 65.09 degrees, which the user reads as too
// close and dizzying. 0.32 is a 17.74-degree radius: the body scales to 77.3% linearly
// and the disc's outer edge to 58.99 degrees, so the hole visibly recedes. This constant
// is not read by the offline atlas builder (qa/tools/build_end_transfer.py never
// references it; only END_DISC_INNER/OUTER are shared), so no atlas rebuild is implied,
// and the on-screen |q| stays well inside the 5.99 atlas wall.
const float END_SHADOW_TAN = 0.32; // 17.74-degree apparent shadow radius.
const float END_DISC_INNER = 0.95;
const float END_DISC_OUTER = 5.20;
const float END_DISC_INCLINATION = 0.16;
float end_disc_half_height(float r) {
    float taper=smoothstep(END_DISC_INNER,END_DISC_INNER+0.18,r);
    float innerSupport=0.070*exp(-pow((r-1.40)/0.65,2.0));
    return taper*(r*(0.023+0.018*smoothstep(1.8,5.2,r))+innerSupport);
}
// Zero-stress thin-disc shape. The maximum lies at 49/36 of the chosen inner
// radius, not exactly on its edge. No claim that this visual truncation is ISCO.
float end_disc_flux(float r) {
    float x=max(r/END_DISC_INNER,1.0);
    return (1.0-inversesqrt(x))/(x*x*x*0.0566528);
}
#endif
