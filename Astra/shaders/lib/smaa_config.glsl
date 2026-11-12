#ifndef ASTRA_SMAA_CONFIG_GLSL
#define ASTRA_SMAA_CONFIG_GLSL
// SMAA 1x, upstream high preset: RGB contrast, diagonal search and corner handling.
// Authoritative implementation: iryoku/smaa, master, retrieved 2026-10-17.
// Copyright and MIT-style permission are retained in lib/vendor/smaa/.
#define SMAA_GLSL_4
#define SMAA_PRESET_HIGH
#define SMAA_RT_METRICS vec4(1.0 / viewWidth, 1.0 / viewHeight, viewWidth, viewHeight)
#define SMAA_AREATEX_SELECT(sample) sample.rg
#include "/lib/vendor/smaa/SMAA.glsl"
#endif
