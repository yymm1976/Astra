#ifndef ASTRA_END_LIGHT_GLSL
#define ASTRA_END_LIGHT_GLSL
// Shared by the astronomical source, surface lighting and shadow projection.
// The End arrival platform is east of the central island. Facing the island
// points west, so the accretion flow must rise behind the island in that view.
vec3 end_light_direction() { return vec3(-cos(radians(23.0)),sin(radians(23.0)),0.0); }
#endif
