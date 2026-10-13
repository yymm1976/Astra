#ifndef ASTRA_TWILIGHT_GLSL
#define ASTRA_TWILIGHT_GLSL
// Shared astronomical envelope for the sky, cloud palette and diffuse terrain.
float astra_twilight_strength() {
    // Pre-dawn from -9 to -4 degrees; warm light fades from +4 to +14.
    // shaders.properties evaluates the shared envelope once per frame on those
    // same ends and midpoints, but with a flatter, slower integral-easing curve
    // (peak slope 4/3 instead of smoothstep's 3/2) so the sunrise/sunset change
    // is gentler without moving any sun angle. Every consumer reads this factor.
    // Unlike sunrise, this factor must stay active for underwater sky rays too.
    return astraTwilightFactor;
}
vec3 astra_twilight_sunlight() {
    // Linear-light calibration of Complementary's warm light/ambient split.
    // The red/green ratio must survive multiplication by green grass albedo.
    return mix(vec3(2.20,0.72,0.18),vec3(1.55,0.87,0.40),
               smoothstep(0.06,0.48,worldSunVector.y));
}
vec3 astra_twilight_atmosphere(vec3 baseSky, vec3 direction) {
    float twilight = astra_twilight_strength();
    if (twilight <= 0.0) return baseSky;
    float facing=dot(direction.xz,worldSunVector.xz)
                 /max(length(direction.xz)*length(worldSunVector.xz),1e-5);
    // Integer exponents as squaring chains per lib/pow.glsl; the 180/1400 halo
    // exponents below stay on pow() - they have no foldable chain.
    float solar=square(square(square(square(max(dot(direction,worldSunVector),0.0)))));
    float warm=square(clamp(0.5+0.5*facing,0.0,1.0));
    float height=max(direction.y,0.0);
    vec3 horizon=mix(vec3(0.34,0.22,0.23),vec3(1.12,0.57,0.22),warm);
    vec3 middle=mix(vec3(0.22,0.20,0.28),vec3(0.62,0.32,0.20),warm);
    vec3 upper=vec3(0.12,0.17,0.28);
    vec3 morning=mix(horizon,middle,smoothstep(0.0,0.38,height));
    morning=mix(morning,upper,smoothstep(0.30,0.92,height));
    morning+=vec3(0.17,0.105,0.04)*solar;
    morning*=smoothstep(-0.208,-0.045,worldSunVector.y);
    // Replace the broad pale lobe rather than layering more light onto it.
    return mix(baseSky,morning,twilight*0.94);
}
vec3 astra_twilight_tint() {
    return mix(vec3(0.32,0.085,0.035),vec3(0.29,0.16,0.10),
               smoothstep(-0.03,0.16,worldSunVector.y));
}
vec3 astra_twilight_sky(vec3 direction) {
    float twilight = astra_twilight_strength();
    if (twilight <= 0.0) return vec3(0.0);
    vec2 sun=worldSunVector.xz/max(length(worldSunVector.xz),1e-5);
    vec2 view=direction.xz/max(length(direction.xz),1e-5);
    float facing=dot(view,sun);
    float horizon=exp(-abs(direction.y-0.025)*7.0)
                 * smoothstep(-0.30,-0.08,direction.y);
    float warm=cube(max(0.0,0.5+0.5*facing));
    float opposite=square(max(-facing,0.0));
    float forward=max(dot(direction,worldSunVector),0.0);
    float f2=forward*forward; float f4=f2*f2; float f8=f4*f4;
    float halo=f8*f8*f8;
    float gold=pow(forward,180.0);
    float core=pow(forward,1400.0);
    float upper=smoothstep(0.10,0.65,direction.y);
    return twilight*
        (horizon*(astra_twilight_tint()*(0.30+1.25*warm)
                   +vec3(0.032,0.035,0.065)*opposite)
         +vec3(0.048,0.017,0.007)*halo
         +vec3(0.10,0.058,0.018)*gold
         +vec3(0.18,0.14,0.08)*core
         +vec3(0.012,0.026,0.050)*upper);
}
// ---------------------------------------------------------------------------
// Highlight shoulder. ONE implementation, and it is the original peak-relative form.
//
// SC-39 (2026-09-17 correction). The first version of this round replaced the
// peak-relative scaling below with a per-channel shoulder rescaled by luminance:
//
//     shoulder = knee + excess/(1 + softness*excess)   per channel
//     return color * luma(color) / luma(max(shoulder, color))
//
// That is wrong twice over, and both errors are measurable rather than aesthetic:
//
//   1. It DARKENS MIDTONES. For a grey input below the knee, shoulder == color, so
//      norm == color and the ratio is luma(color)/luma(color) == 1 - no dimming. But
//      for any chromatic midtone the ratio is NOT 1, because the per-channel shoulder
//      is not proportional to the channel: vec3(0.6,0.5,0.35) comes back at exactly
//      0.601x of its input, vec3(1.0,0.15,0.1) at 0.376x, vec3(0.1,0.25,1.0) at
//      0.321x, and even flat grey 0.5 at 0.588x. The diagonal grey case is the only
//      one that survives, which is why it was not caught by eye: the formula silently
//      multiplied a large part of the ORDINARY range - every saturated midtone in the
//      frame - by 0.3..0.6, and did it under a comment claiming to preserve luminance.
//
//   2. The "peaking" variant AMPLIFIED instead of compressing. `shoulder - knee +
//      color` is not a peak function; for an input above the knee it exceeds the
//      input. The sun disc at vec3(8.0,7.0,5.2) came out at vec3(6.68,5.85,4.34) -
//      i.e. a value 6.7x above the tonemapper's ceiling, produced by a function whose
//      stated job was to give the disc a ceiling.
//
// What is kept from that attempt is only the observation that per-channel clamping
// shifts hue. The fix is the thing the file already shipped: scale every channel by
// ONE peak-relative factor, which preserves the channel ratios exactly, and make the
// gate monotone so the function can never raise a value:
//
//     peak   = max channel
//     excess = max(peak - knee, 0)
//     peakNew= knee + excess/(1 + softness*excess)     <= peak, equal below the knee
//     return color * peakNew/peak
//
// Below the knee peakNew == peak and the ratio is 1, so the ordinary range - including
// every saturated midtone - passes through untouched. Above it the whole triple is
// scaled down by the same number, so a warm highlight stays exactly as warm. The
// residual cost is that a highlight sitting far above the knee converges its ratios
// towards white as it approaches the ceiling; that is inherent to single-factor
// scaling, it is what Steadfast/Solas-style shoulders do, and it beats both errors
// above. No caller may take the peak above zero, so the division is guarded.
// ---------------------------------------------------------------------------
float astra_highlight_shoulder(float value, float knee, float softness) {
    float excess = max(value - knee, 0.0);
    return knee + excess / (1.0 + softness * excess);
}
// `strength` blends the compression in (0 = untouched). It exists so a caller can make
// the ceiling fade with the twilight envelope without duplicating the maths; the
// original astra_twilight_highlights did this with mix(color, compressed, twilight),
// which is the same thing written differently. Values above 1 clamp to the full form.
vec3 astra_highlight_shoulder_peak(vec3 color, float knee, float softness, float strength) {
    color = max(color, vec3(0.0));
    float peak = max(max(color.r, color.g), color.b);
    if (peak <= knee || strength <= 0.0) return color;
    float shoulder = astra_highlight_shoulder(peak, knee, softness);
    float factor = mix(1.0, shoulder / max(peak, 1e-5), clamp(strength, 0.0, 1.0));
    return color * factor;
}
// Compress radiance without independently clipping channels to white.
vec3 astra_twilight_highlights(vec3 color) {
    float twilight = astra_twilight_strength();
    if (twilight <= 0.0) return color;
    return astra_highlight_shoulder_peak(color, 0.85, 0.65, twilight);
}
// The same shoulder, applied by the scene assembly to direct highlights the sky does
// not own: the sun/moon sprite and the sun's image on water. It runs ungated because
// those are emitters at every time of day - there is no twilight window in which a
// specular sun should be allowed to run away.
vec3 astra_scene_highlights(vec3 color) {
    return astra_highlight_shoulder_peak(color, 1.0, 0.60, 1.0);
}
#endif
