// Display inputs that are constant across the full-screen draw.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#if !defined DIMENSION_NETHER && !defined DIMENSION_END && !defined ASTRA_BLOOM
#define ASTRA_WATER_FOG_FRAME_WRITE
#include "/lib/solas_water_frame.glsl"
#endif
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
#include "/global/water/medium_state.glsl"
flat out int displayOrdinaryWater;
#ifdef ASTRA_TREE_SHAFTS
#include "/lib/color_controls.glsl"
flat out vec3 displayTreeShaftLight;
#endif
#if defined GODRAYS && GODRAYS_STRENGTH > 0 && !defined ASTRA_VOLUME_FOG && !defined ASTRA_TREE_SHAFTS && (defined GODRAYS_SUN_OCCLUSION || defined ASTRA_GODRAYS_CLOUD_OCCLUSION)
uniform sampler2D colortex1;
flat out float displayGodraysVisibility;
#endif
#ifdef AUTO_EXPOSURE
#include "/global/post/exposure.glsl"
flat out float displayExposureGain;
#endif
#endif
out vec2 texcoord;
void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END && !defined ASTRA_BLOOM
    waterFogFrameMedium = vec3(0.0);
    waterInterfaceIncident = vec3(0.0);
    #if DEBUG_VERTEX_AO == 0 && (!defined ASTRA_DISPLAY_FINAL || !defined ASTRA_SPATIAL_AA)
    if (isEyeInWater == 1) {
        vec3 fogBase;
        vec2 fogResponse;
        solas_water_fog_frame_parameters(fogBase, fogResponse);
        waterFogFrameMedium = solas_water_medium_linear(fogBase, fogResponse.x);
        waterInterfaceIncident = solas_water_interface_incident();
    }
    #endif
    #endif
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    displayOrdinaryWater = int(isEyeInWater == 1 && !water_is_thin_sheet());
    #ifdef ASTRA_TREE_SHAFTS
    displayTreeShaftLight = astra_sun_shaft_source();
    #endif
    #if defined GODRAYS && GODRAYS_STRENGTH > 0 && !defined ASTRA_VOLUME_FOG && !defined ASTRA_TREE_SHAFTS && (defined GODRAYS_SUN_OCCLUSION || defined ASTRA_GODRAYS_CLOUD_OCCLUSION)
    displayGodraysVisibility = 1.0;
    #if DEBUG_VERTEX_AO == 0 && (!defined ASTRA_DISPLAY_FINAL || !defined ASTRA_SPATIAL_AA)
    // Scattering has already written this draw-wide source visibility.
    // Ordinary water uses the same texel's alpha as distance, so never read it here.
    if ((isEyeInWater == 0 || (isEyeInWater == 1 && displayOrdinaryWater == 0))
        && godraysExposure > 0.0 && blindness <= 0.0001)
        #ifdef ASTRA_UNDERWATER_SHAFTS
        displayGodraysVisibility = texelFetch(colortex1, ivec2(0), 0).a;
        #else
        displayGodraysVisibility = texelFetch(colortex1, ivec2(0), 0).g;
        #endif
    #endif
    #endif
    #ifdef AUTO_EXPOSURE
    displayExposureGain = 1.0;
    // Spatial AA's final draw consumes the display prepared by composite8 already.
    #if DEBUG_VERTEX_AO == 0 && (!defined ASTRA_DISPLAY_FINAL || !defined ASTRA_SPATIAL_AA)
    if (displayOrdinaryWater == 0) displayExposureGain = astra_ae_gain();
    #endif
    #endif
    #endif
}
