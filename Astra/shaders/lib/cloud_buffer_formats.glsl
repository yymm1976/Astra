#ifndef ASTRA_CLOUD_BUFFER_FORMATS_GLSL
#define ASTRA_CLOUD_BUFFER_FORMATS_GLSL
// Single declaration site for the shared low-frequency cloud/sky target (colortex12).
// Two producers need the same format spec: program/cloud_screen.fsh writes its raw
// screen-cloud target there when the independent cloud history is off
// (!ASTRA_CLOUD_TEMPORAL), and program/sky_gradient_cache.fsh writes the frame's
// low-frequency sky table there. Target identity and the size schedule stay in
// shaders.properties; this file only removes the duplicate format declaration, and it
// adds no sampler, target or pass.
#ifndef RGBA16F
const int RGBA16F = 0;
#endif
const int colortex12Format = RGBA16F;
#endif
