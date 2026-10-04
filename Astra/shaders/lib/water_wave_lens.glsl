#ifndef ASTRA_WATER_WAVE_LENS_GLSL
#define ASTRA_WATER_WAVE_LENS_GLSL
// Astra's optical wave field; the existing Solas noise asset supplies B.
// Gradient bends submerged light paths; Hessian focuses the same moving waves.
// Quintic interpolation keeps both continuous across lattice boundaries.
void astra_wave_lens_octave(vec2 at, out vec2 slope, out vec3 curvature) {
    vec2 cell = floor(at);
    vec2 t = at - cell;
    vec4 h = textureGather(solasWaterNoise,
        (cell + 0.5) / vec2(textureSize(solasWaterNoise, 0)), 2);
    vec2 f = t*t*t * (t*(t*6.0 - 15.0) + 10.0);
    vec2 df = 30.0*t*t*(t-1.0)*(t-1.0);
    vec2 ddf = 60.0*t*(2.0*t*t - 3.0*t + 1.0);
    float crossTerm = h.y - h.z - h.x + h.w;
    vec2 axis = vec2(h.z-h.w+crossTerm*f.y, h.x-h.w+crossTerm*f.x);
    slope = df * axis;
    curvature = vec3(ddf.x*axis.x, crossTerm*df.x*df.y, ddf.y*axis.y);
}
void astra_water_wave_lens(vec2 worldXZ, float footprint,
                           out vec2 slope, out mat2 curvature) {
    slope = vec2(0.0);
    curvature = mat2(0.0);
    #if WATER_WAVE_HEIGHT != 0
    float time = frameTimeCounter * (WATER_WAVE_SPEED * 0.01);
    const mat2 rotation = mat2(0.8, 0.6, -0.6, 0.8);
    float resolvedA = 1.0 - smoothstep(0.3, 0.7, footprint*0.65);
    float resolvedB = 1.0 - smoothstep(0.3, 0.7, footprint*1.05);
    vec2 slopeA = vec2(0.0), slopeB = vec2(0.0);
    vec3 a = vec3(0.0), b = vec3(0.0);
    if (resolvedA > 0.0)
        astra_wave_lens_octave(worldXZ*0.65 + time*vec2(0.24, 0.19), slopeA, a);
    if (resolvedB > 0.0)
        astra_wave_lens_octave(rotation*worldXZ*1.05 + time*vec2(-0.18, 0.23), slopeB, b);
    float waveHeight = WATER_WAVE_HEIGHT * 0.01;
    slope = waveHeight * (0.22*0.65*resolvedA*slopeA
                         + 0.07*1.05*resolvedB*transpose(rotation)*slopeB);
    curvature = waveHeight * ((0.22*0.65*0.65*resolvedA)*mat2(a.x,a.y,a.y,a.z)
                            + (0.07*1.05*1.05*resolvedB)*transpose(rotation)
                              * mat2(b.x,b.y,b.y,b.z)*rotation);
    #endif
}
#endif
