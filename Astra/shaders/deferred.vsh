#version 400 compatibility
// Astra v1 - deferred.vsh: root pass shell = dimension-neutral default (overworld and any
// dimension without an override). Nether/End override in world-1/ world1/. design.md 2.2/3.1
#include "/lib/settings.glsl"
#if CLOUD_MODE == CLOUD_PLANAR && DEBUG_VERTEX_AO == 0
#include "/program/cloud_screen.vsh"
#else
#include "/program/deferred.vsh"
#endif
