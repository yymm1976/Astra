#version 400 compatibility
#include "/lib/settings.glsl"
#ifdef ASTRA_GRADIENT_SKY_CACHE
#include "/program/sky_gradient_cache.fsh"
#else
#include "/program/sky_reflection_cache.fsh"
#endif
