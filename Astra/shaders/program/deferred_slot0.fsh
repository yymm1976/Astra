// First dimension-neutral deferred selector. Nether/End override their entry
// shells in world-1/ and world1/; see design.md 2.2/3.1.
// Planar clouds use current opaque depth in this first slot. Other cloud modes
// start with optional AO / volume, or directly with scene composition.
#include "/lib/settings.glsl"
#if DEBUG_VERTEX_AO == 1
#include "/program/deferred.fsh"
#elif CLOUD_MODE == CLOUD_PLANAR
#include "/program/cloud_screen.fsh"
#elif defined ASTRA_SSAO
#include "/program/ssao.fsh"
#elif defined ASTRA_VOLUME_FOG && VOLUME_FOG_DENSITY > 0
#include "/program/volume_main.fsh"
#else
#include "/program/deferred.fsh"
#endif
