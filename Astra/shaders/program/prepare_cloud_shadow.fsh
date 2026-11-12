#include "/lib/settings.glsl"
// prepare has already written the environment. Generate once in this existing
// following pass, before opaque geometry; the producer must not generate stale mips.
#if defined ROUGH_SKY_REFLECTIONS && CLOUD_MODE == CLOUD_PLANAR
const bool colortex11MipmapEnabled = true;
#endif
#include "/program/cloud_shadow_cache.fsh"
