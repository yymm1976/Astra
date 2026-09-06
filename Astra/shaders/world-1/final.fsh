#version 400 compatibility
#define DIMENSION_NETHER

#include "/program/final.fsh"
// SC-27: buffer formats intentionally left at Iris defaults. Iris 1.11.2 never
// rewrites colortexNFormat tokens (rounds 4-6: lib/program/entry all C1503), and
// every working reference pack on this Iris ships them commented out (Complementary
// pipelineSettings.glsl, Mellow release). Re-visit precision tuning after load.
