#ifndef ASTRA_LIB_TAA_REACTIVE_GLSL
#define ASTRA_LIB_TAA_REACTIVE_GLSL
#ifdef ASTRA_TAA
#ifndef R8
const int R8 = 0;
#endif
const int colortex16Format = R8;
const bool colortex16Clear = true;
const vec4 colortex16ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
#endif
#endif
