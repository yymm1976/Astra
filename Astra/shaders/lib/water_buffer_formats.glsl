#ifndef ASTRA_WATER_BUFFER_FORMATS_GLSL
#define ASTRA_WATER_BUFFER_FORMATS_GLSL
// Steadfast declares the format name as a GLSL constant as well as using it
// in Iris directives. Iris reads the identifier; GLSL needs a declaration.
// Leaving every format at its default clipped the linear scene before absorption.
#ifndef R11F_G11F_B10F
const int R11F_G11F_B10F = 0;
#endif
#ifndef RGBA16
const int RGBA16 = 0;
#endif
const int colortex0Format = R11F_G11F_B10F;
// Bloom prefilter carries HDR energy. Packed RGB float uses the same 32 bits
// per texel as default RGBA8, while preserving radiance above one.
const int colortex2Format = R11F_G11F_B10F;
// Geometry/refraction snapshot stays 32-bit in air. Underwater HDR composition
// has its own colortex9 carrier, so its precision does not tax every water tap.
const int colortex4Format = R11F_G11F_B10F;
#endif
