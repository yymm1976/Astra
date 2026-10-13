#ifndef ASTRA_ITT_WATER_WAVES_GLSL
#define ASTRA_ITT_WATER_WAVES_GLSL
// IterationT 3.2.0 WaterWaves.glsl: six layers, weights, transforms, scrolling
// and AlmostIdentity. Astra differentiates those SAME layers analytically and
// filters unresolved noise before generating light, rather than differencing
// a second unrelated wave field. See THIRD-PARTY.md.
uniform sampler2D ittWaterNoise;

// Value and gradient of ITT's cubic-smoothed bilinear noise. Gather's component
// argument is a literal in each branch, as required by GLSL 4.00.
vec3 itt_wave_noise(vec2 uv, mat2 worldUV, float footprint, int channel) {
    float frequency = 64.0*max(length(worldUV[0]),length(worldUV[1]));
    float resolved = 1.0-smoothstep(0.5,1.25,footprint*frequency);
    // Fully filtered noise is its mean with zero slope. No corner value can
    // contribute, including through the later crest transform.
    if (resolved <= 0.0) return vec3(0.5,0.0,0.0);
    vec2 at = uv*64.0+0.5;
    vec2 cell = floor(at);
    vec2 t = fract(at);
    vec2 f = t*t*(3.0-2.0*t);
    vec2 df = 6.0*t*(1.0-t);
    vec2 centre = (cell-0.5)/64.0;
    vec4 corners;
    if (channel == 2) corners = textureGather(ittWaterNoise,centre,2).wzxy;
    else corners = textureGather(ittWaterNoise,centre,3).wzxy;
    float crossTerm = corners.w-corners.y-corners.z+corners.x;
    float value = corners.x+(corners.y-corners.x)*f.x
                +(corners.z-corners.x)*f.y+crossTerm*f.x*f.y;
    vec2 gradient = df*vec2(corners.y-corners.x+crossTerm*f.y,
                            corners.z-corners.x+crossTerm*f.x)*64.0;
    return vec3(mix(0.5,value,resolved),transpose(worldUV)*gradient*resolved);
}
vec3 itt_wave_crest(vec3 noise) {
    float x = abs(2.0*noise.x-1.0);
    float value, derivative;
    if (x <= 0.2) {
        value = 0.9-2.5*x*x;
        derivative = -5.0*x;
    } else {
        value = 1.0-x;
        derivative = -1.0;
    }
    return vec3(value,noise.yz*(derivative*2.0*sign(2.0*noise.x-1.0)));
}
vec3 itt_water_wave(vec2 worldXZ, float footprint) {
    float time = frameTimeCounter*(0.0035*WATER_WAVE_SPEED*0.01);
    // Spread the world-fixed dominant contours. Compensate their derivative
    // amplitude below so spacing does not reduce the source's wave slopes.
    const float spatialScale = 0.05/1.28;
    vec2 p = worldXZ*spatialScale-vec2(0.05)-3.875*time;
    p.x = -p.x;
    mat2 jacobian = mat2(-spatialScale,0.0,0.0,spatialScale);
    mat2 transform = mat2(2.0,2.1,0.0,1.2);
    vec3 waves = itt_wave_noise(transform*p,transform*jacobian,footprint,3)*2.0;
    p = p*0.475+vec2(-5.16,-7.75)*time;
    jacobian *= 0.475;
    transform = mat2(2.0,-2.1,0.0,1.4);
    waves += itt_wave_noise(transform*p,transform*jacobian,footprint,3)*6.0;
    p *= 0.67;
    p.x += 7.75*time;
    jacobian *= 0.67;
    transform = mat2(1.0,1.1,0.0,1.0);
    waves += itt_wave_noise(transform*p,transform*jacobian,footprint,2)*8.0;
    p *= 0.7;
    p.x -= 2.82*time;
    jacobian *= 0.7;
    transform = mat2(1.0,-1.7,0.0,0.75);
    waves += itt_wave_noise(transform*p,transform*jacobian,footprint,3)*13.0;
    p *= 0.45;
    p.x += time;
    jacobian *= 0.45;
    transform = mat2(1.0,-1.7,0.0,0.8);
    waves += itt_wave_crest(itt_wave_noise(transform*p,transform*jacobian,footprint,2))*30.0;
    p *= 0.5;
    p.x += time;
    jacobian *= 0.5;
    transform = mat2(1.0,1.7,0.0,0.8);
    waves += itt_wave_crest(itt_wave_noise(transform*p,transform*jacobian,footprint,3))*20.0;
    return waves*((1.28/1.08)/79.0);
}
vec2 itt_water_wave_slope(vec2 worldXZ, float footprint) {
    #if !defined WATER_WAVES || WATER_WAVE_HEIGHT == 0
    return vec2(0.0);
    #else
    vec3 wave = itt_water_wave(worldXZ,footprint);
    // ITT's 0.12 difference * 25 * (1.2/12) corresponds to 0.30*d(height).
    return -wave.yz*(0.30*WATER_WAVE_HEIGHT*0.01);
    #endif
}
vec3 itt_water_wave_normal(vec2 worldXZ, float footprint) {
    vec2 slope = itt_water_wave_slope(worldXZ,footprint);
    return normalize(vec3(slope.x,1.0,slope.y));
}
#endif
