// R2/H3: scheduler for the deferred1 slot while VOLUMETRIC_FOG is on (the pass is
// enabled only at positive density, see shaders.properties). With AO separated, deferred1 is the
// volume-march slot - deferred itself runs the AO pass and deferred2 composes the
// scene. Without AO, deferred already marched the volume, so this slot composes the
// scene one pass later than usual. Slot table: docs/handoffs/2026-09-27-R2-overworld-volume.md.
#include "/lib/settings.glsl"
#if defined ASTRA_SSAO && defined ASTRA_VOLUME_FOG
#include "/program/volume_main.fsh"
#else
#include "/program/deferred.fsh"
#endif
