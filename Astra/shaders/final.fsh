#version 400 compatibility
// Astra v1 - final.fsh: root pass shell = dimension-neutral default (overworld and any
// dimension without an override). Nether/End override in world-1/ world1/. design.md 2.2/3.1
#include "/program/final.fsh"
// SC-27: buffer formats intentionally left at Iris defaults. Iris 1.11.2 never
// rewrites colortexNFormat tokens (rounds 4-6: lib/program/entry all C1503), and
// every working reference pack on this Iris ships them commented out (Complementary
// pipelineSettings.glsl, Mellow release). Re-visit precision tuning after load.
