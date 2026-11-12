#include "/lib/settings.glsl"
#if CLOUD_MODE == CLOUD_PLANAR && defined ASTRA_SSAO && defined ASTRA_VOLUME_FOG && VOLUME_FOG_DENSITY > 0
    #include "/program/volume_main.fsh"
#else
    #include "/program/deferred.fsh"
#endif
