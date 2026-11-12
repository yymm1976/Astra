#version 400 compatibility
#include "/lib/settings.glsl"
#ifdef ASTRA_CELESTIAL_BLOOM
#include "/program/composite1.fsh"
#else
#include "/program/water_bloom.fsh"
#endif
