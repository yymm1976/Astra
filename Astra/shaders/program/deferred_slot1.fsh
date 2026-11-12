// After planar clouds: optional AO / volume, otherwise scene composition.
// Without planar clouds, this remains the original optional volume slot.
#include "/lib/settings.glsl"
#if CLOUD_MODE == CLOUD_PLANAR
    #ifdef ASTRA_SSAO
        #include "/program/ssao.fsh"
    #elif defined ASTRA_VOLUME_FOG && VOLUME_FOG_DENSITY > 0
        #include "/program/volume_main.fsh"
    #else
        #include "/program/deferred.fsh"
    #endif
#else
    #include "/program/volume_slot.fsh"
#endif
