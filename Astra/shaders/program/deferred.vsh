// Shared full-screen quad; scene/volume consumers reuse the current water kind.
// design.md 3.2 layer 2: program/* is the only lib entry
#include "/lib/settings.glsl"
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
#include "/lib/uniforms.glsl"
#define ASTRA_WATER_STATE_FRAME_WRITE
#include "/global/water/medium_state.glsl"
#ifndef ASTRA_VOLUME_FOG
#include "/lib/color_controls.glsl"
flat out vec3 deferredRainAirSource;
#endif
#endif
out vec2 texcoord;
void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Scene/volume composition shares this draw-wide water kind with all
    // fog consumers. Other uses of this quad stage have no matching input.
    waterMaterialThinSheet = int(water_is_thin_sheet());
    #ifndef ASTRA_VOLUME_FOG
    deferredRainAirSource = vec3(0.0);
    // These gates and the eye access are identical across this draw. The
    // fragment still evaluates every eligible ray's own clouds and occluders.
    if (astraRainFactor >= 0.01 && skyVisibilityDay > 0.0 && blindness <= 0.0001
        && (isEyeInWater == 0 || waterMaterialThinSheet != 0)) {
        float access = smoothstep(0.35,0.85,float(eyeBrightnessSmooth.y)/240.0);
        if (access > 0.0)
            deferredRainAirSource = astra_sun_shaft_source()
                *(0.003*astraRainFactor*access*skyVisibilityDay);
    }
    #endif
    #endif
}
