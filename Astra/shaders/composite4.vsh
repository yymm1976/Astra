#version 400 compatibility
#include "/lib/settings.glsl"
// Both air highlights and underwater HDR are captured by this draw.
#ifndef ASTRA_CELESTIAL_BLOOM
#define ASTRA_WATER_BLOOM_CAPTURE
#endif
#include "/program/composite1.vsh"
