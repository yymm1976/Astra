#ifndef ASTRA_SMAA_BUFFER_GLSL
#define ASTRA_SMAA_BUFFER_GLSL
// Edge and weight passes alternate the two physical sides of attachment 7.
// Both overwrite every pixel. Only SMAA allocates this native-sized RGBA8 pair.
#ifndef RGBA8
const int RGBA8 = 0;
#endif
const int colortex7Format = RGBA8;
const bool colortex7Clear = false;
#endif
