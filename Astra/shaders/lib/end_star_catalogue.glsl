#ifndef ASTRA_END_STAR_CATALOGUE_GLSL
#define ASTRA_END_STAR_CATALOGUE_GLSL
// Original Astra GPU catalogue. Keep the existing generators and FP32 values;
// only move the fixed row and presence data out of the per-ray loops.
const float END_STAR_ROWS = 512.0;
const float END_STAR_EQUATOR_CELLS = 1200.0;
const int END_STAR_CATALOGUE_WIDTH = 1024;
const int END_STAR_METADATA_COUNT = 512;
#ifndef RGBA32F
const int RGBA32F = 0;
#endif
const int colortex31Format = RGBA32F;
const bool colortex31Clear = false;
#ifndef ASTRA_END_STAR_CATALOGUE_WRITE
uniform sampler2D colortex31;
vec3 end_star_row(float row) {
    return texelFetch(colortex31, ivec2(int(row),0), 0).rgb;
}
vec4 end_star_presence(float column, float rowOffset) {
    int slot=int(rowOffset)+int(column);
    return texelFetch(colortex31,
        ivec2(slot%END_STAR_CATALOGUE_WIDTH,slot/END_STAR_CATALOGUE_WIDTH),0);
}
#endif
#endif
