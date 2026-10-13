#ifndef ASTRA_CLOUD_SAMPLE_GRID_GLSL
#define ASTRA_CLOUD_SAMPLE_GRID_GLSL
// Original Astra: centered subpixel coverage samples in CLOUD-buffer pixels.
// Independent of scene TAA; producer, reprojection and consumers share this grid.
vec2 astra_cloud_grid_offset(int frame, ivec2 size) {
    const vec2 offsets[8] = vec2[8](
        vec2(0.0, -1.0/6.0), vec2(-0.25, 1.0/6.0),
        vec2(0.25, -7.0/18.0), vec2(-0.375, -1.0/18.0),
        vec2(0.125, 5.0/18.0), vec2(-0.125, -5.0/18.0),
        vec2(0.375, 1.0/18.0), vec2(-0.4375, 7.0/18.0));
    return (offsets[max(frame, 0) % 8] + vec2(0.0546875, 0.0))
         / max(vec2(size), vec2(1.0));
}
#endif
