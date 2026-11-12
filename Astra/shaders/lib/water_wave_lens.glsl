#ifndef ASTRA_WATER_WAVE_LENS_GLSL
#define ASTRA_WATER_WAVE_LENS_GLSL
// Astra's bed/interface optical wave field; the Solas noise asset supplies B.
// Gradient supplies the submerged interface and volume entry refraction;
// Hessian focuses bed caustics. Volume flux has its own finite-depth ray map.
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
    float resolvedB = 1.0 - smoothstep(0.3, 0.7, footprint*1.35);
    vec2 slopeA = vec2(0.0), slopeB = vec2(0.0);
    vec3 a = vec3(0.0), b = vec3(0.0);
    if (resolvedA > 0.0)
        astra_wave_lens_octave(worldXZ*0.65 + time*vec2(0.24, 0.19), slopeA, a);
    if (resolvedB > 0.0)
        astra_wave_lens_octave(rotation*worldXZ*1.35 + time*vec2(-0.18, 0.23), slopeB, b);
    float waveHeight = WATER_WAVE_HEIGHT * 0.01;
    slope = waveHeight * (0.22*0.65*resolvedA*slopeA
                         + 0.045*1.35*resolvedB*transpose(rotation)*slopeB);
    curvature = waveHeight * ((0.22*0.65*0.65*resolvedA)*mat2(a.x,a.y,a.y,a.z)
                            + (0.045*1.35*1.35*resolvedB)*transpose(rotation)
                              * mat2(b.x,b.y,b.y,b.z)*rotation);
    #endif
}
// Bounded convergence for the bed caustics; no volume-beam consumer.
float astra_water_wave_focus(mat2 curvature) {
    mat2 landing = mat2(1.0)+curvature*2.0;
    float area = landing[0][0]*landing[1][1]-landing[0][1]*landing[1][0];
    return 0.30+0.70*clamp(1.0/max(abs(area),0.25),0.25,4.0);
}
#endif
