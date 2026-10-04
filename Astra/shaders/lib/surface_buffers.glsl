#ifndef ASTRA_SURFACE_BUFFERS_GLSL
#define ASTRA_SURFACE_BUFFERS_GLSL
#if defined ASTRA_SSAO || defined ASTRA_TAA
#ifndef RGBA16F
const int RGBA16F = 0;
#endif
#endif
#ifdef ASTRA_SSAO
#include "/lib/water_buffer_formats.glsl"
#ifndef RGBA8
const int RGBA8 = 0;
#endif
// RGB ambient energy; vertex AO shares the normal buffer's validity byte.
const int colortex19Format = R11F_G11F_B10F;
const vec4 colortex19ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
// RGB = geometric normal, A = eligibility bit plus seven-bit vertex AO.
const int colortex20Format = RGBA8;
const vec4 colortex20ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
#endif
#if defined ASTRA_SSAO && defined ASTRA_DIRECTIONAL_SKYLIGHT
// R1: re-evaluable directional-sky response (material-weighted, SH direction
// excluded). Same lifetime as 19/20: written by the opaque gbuffers, consumed
// by deferred2, cleared every frame.
const int colortex27Format = R11F_G11F_B10F;
const vec4 colortex27ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
#endif
#ifdef ASTRA_TAA
const int colortex22Format = RGBA16F;
const vec4 colortex22ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
#endif
#endif
