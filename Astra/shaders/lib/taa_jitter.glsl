#ifndef ASTRA_LIB_TAA_JITTER_GLSL
#define ASTRA_LIB_TAA_JITTER_GLSL

// Original Astra implementation. Centered eight-sample Halton (2,3) cycle.
// Offsets are in FULL-resolution pixels, including half-resolution consumers.
// SUMMARY CPU scheduling idea (MakeUp/Mellow/SDV): current/previous offsets are
// prepared once in shaders.properties; other frame indices retain this table.
vec2 astra_jitter_uv_for(int frame) {
    #ifdef ASTRA_TAA
    // The scene resolve rejects history in every non-air camera medium.
    if (isEyeInWater != 0) return vec2(0.0);
    if (frame == frameCounter) return astraJitterCurrent;
    if (frame == frameCounter - 1) return astraJitterPrevious;
    const vec2 offsets[8] = vec2[8](
        vec2(0.0, -1.0/6.0), vec2(-0.25, 1.0/6.0),
        vec2(0.25, -7.0/18.0), vec2(-0.375, -1.0/18.0),
        vec2(0.125, 5.0/18.0), vec2(-0.125, -5.0/18.0),
        vec2(0.375, 1.0/18.0), vec2(-0.4375, 7.0/18.0));
    // Remove the finite cycle's mean, not just the infinite sequence's mean.
    return (offsets[max(frame,0) % 8] + vec2(0.0546875, 0.0))
         / max(vec2(viewWidth, viewHeight), vec2(1.0));
    #else
    return vec2(0.0);
    #endif
}
vec2 astra_jitter_uv() {
    #ifdef ASTRA_TAA
    if (isEyeInWater != 0) return vec2(0.0);
    return astraJitterCurrent;
    #else
    return vec2(0.0);
    #endif
}

vec4 astra_jitter_clip(vec4 clip) {
    clip.xy += 2.0 * astra_jitter_uv() * clip.w;
    return clip;
}

#endif
