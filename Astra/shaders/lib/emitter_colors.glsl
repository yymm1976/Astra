#ifndef ASTRA_EMITTER_COLORS_GLSL
#define ASTRA_EMITTER_COLORS_GLSL
// Existing Astra source palette, shared by volume emission and diagnostics.
// Species numbering is the occupancy grid's numbering, not block/item IDs.
vec3 astra_emitter_color(uint id) {
    if (id == 2u) return vec3(1.0, 0.04, 0.01);
    if (id == 3u || id == 9u) return vec3(1.0, 0.30, 0.045);
    if (id == 4u) return vec3(1.0, 0.66, 0.22);
    if (id == 5u) return vec3(0.32, 1.0, 0.43);
    if (id == 6u) return vec3(0.30, 0.85, 1.0);
    if (id == 7u || id == 10u) return vec3(0.055, 0.62, 1.0);
    if (id == 8u) return vec3(0.64, 0.20, 1.0);
    if (id == 11u) return vec3(0.72, 0.24, 0.04);
    return vec3(0.0);
}
#endif
