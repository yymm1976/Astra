#version 430 compatibility
// 430 (not the 400 used by the other dimensions' shells): the nether voxel capture
// below declares a uimage3D and calls imageAtomicMax, which needs GLSL 420+
// (consolidated review E11 / Qoder F-23).
#define DIMENSION_NETHER

#include "/program/shadow.vsh"
