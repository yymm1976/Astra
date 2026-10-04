#ifndef ASTRA_SCENE_BUFFER_FORMATS_GLSL
#define ASTRA_SCENE_BUFFER_FORMATS_GLSL
// Each dimension must load this directive with its own colortex9 producer.
#ifndef RGBA16F
const int RGBA16F = 0;
#endif
const int colortex9Format = RGBA16F;
#endif
