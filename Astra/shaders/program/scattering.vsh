// Current water height, refracted celestial direction and wave-image coverage.
// Animated source contours belong to ITT waves, never fixed emitter geometry.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/transforms.glsl"
#include "/global/water/medium_state.glsl"
flat out int scatteringThinSheet;
#ifdef ASTRA_UNDERWATER_SHAFTS
#include "/lib/solas_water_frame.glsl"
#include "/lib/itt_water_field.glsl"
#include "/global/water/optics.glsl"
uniform sampler2D colortex29;
flat out vec4 waterShaftSource;
flat out vec2 waterShaftSurface;
flat out vec2 waterShaftFieldOrigin;
flat out vec3 waterShaftIllumination;
flat out vec3 waterShaftViewOrigin;
flat out vec3 waterShaftWorldOrigin;
#if CLOUD_MODE == CLOUD_PLANAR && defined CLOUD_SHADOWS
flat out vec3 waterShaftAirSource;
#endif
uniform vec3 astraSolasSurfaceDirect;
#endif
out vec2 texcoord;
out vec2 lightScreenPos;
void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
    bool thinSheet = water_is_thin_sheet();
    scatteringThinSheet = int(thinSheet);
    #ifdef ASTRA_UNDERWATER_SHAFTS
    waterShaftSource = vec4(0.0);
    waterShaftSurface = vec2(0.0);
    waterShaftFieldOrigin = vec2(0.0);
    waterShaftIllumination = vec3(0.0);
    waterShaftViewOrigin = vec3(0.0);
    waterShaftWorldOrigin = vec3(0.0);
    #if CLOUD_MODE == CLOUD_PLANAR && defined CLOUD_SHADOWS
    waterShaftAirSource = vec3(0.0);
    #endif
    #endif
    bool airCamera = isEyeInWater == 0 || thinSheet;
    #if !defined GODRAYS || GODRAYS_STRENGTH == 0 || defined ASTRA_VOLUME_FOG
    bool skipAir = true;
    #elif defined ASTRA_TREE_SHAFTS
    bool skipAir = SUNLIGHT_STRENGTH <= 0 || astraSunSource < 0.5 || astraDirectLightGate <= 0.0 || blindness > 0.0001;
    #else
    bool skipAir = godraysExposure <= 0.0 || blindness > 0.0001;
    #endif
    // These air fragments would all write the attachment's clear value, including
    // its solar metadata. Skip rasterization using the same fragment conditions.
    lightScreenPos = vec2(0.5);
    if (airCamera && skipAir) {
        gl_Position = vec4(-2.0,-2.0,0.0,1.0);
        return;
    }
    // The water branch returns before any screen-light consumer in scattering.fsh.
    if (airCamera) {
        #ifndef ASTRA_TREE_SHAFTS
        vec4 clipLight = astra_jitter_clip(gbufferProjection*vec4(lightVector,0.0));
        vec2 ndcLight = clipLight.w > 0.0 ? clipLight.xy/max(clipLight.w,0.0001) : vec2(0.0);
        lightScreenPos = ndcLight*0.5+0.5;
        #endif
    }
    #ifdef ASTRA_UNDERWATER_SHAFTS
    #if !defined GODRAYS || GODRAYS_STRENGTH == 0 || defined ASTRA_VOLUME_FOG
    // With no air consumer, the remaining non-water camera media need no
    // fragments either. Air/thin-sheet views were already clipped above.
    if (isEyeInWater != 1 || thinSheet) {
        gl_Position = vec4(-2.0,-2.0,0.0,1.0);
        return;
    }
    #endif
    if (isEyeInWater != 1 || thinSheet) return;
    #if !defined WATER_WAVES || WATER_WAVE_HEIGHT == 0
    gl_Position = vec4(-2.0,-2.0,0.0,1.0);
    return;
    #endif
    vec4 waterState = water_volume_state();
    if (waterState.a <= 0.5) {
        gl_Position = vec4(-2.0,-2.0,0.0,1.0);
        return;
    }
    vec3 viewOrigin = projection_view_origin();
    vec3 worldOrigin = view_camera_relative(viewOrigin);
    float surfaceY = water_unpack_surface_height(waterState.rg)-cameraPosition.y;
    if (surfaceY-worldOrigin.y <= 0.032) {
        gl_Position = vec4(-2.0,-2.0,0.0,1.0);
        return;
    }
    vec3 lightDir = itt_water_light_direction(shadowModelViewInverse);
    vec3 waterLightDir = -refract(-lightDir,vec3(0.0,1.0,0.0),1.0/WATER_IOR);
    float visibility = itt_water_source_visibility(lightDir);
    if (visibility <= 0.0) {
        gl_Position = vec4(-2.0,-2.0,0.0,1.0);
        return;
    }
    waterShaftSource = vec4(waterLightDir,visibility);
    waterShaftViewOrigin = viewOrigin;
    waterShaftWorldOrigin = worldOrigin;
    #if CLOUD_MODE == CLOUD_PLANAR && defined CLOUD_SHADOWS
    waterShaftAirSource = lightDir;
    #endif
    waterShaftSurface = vec2(surfaceY,1.0);
    waterShaftFieldOrigin = water_shaft_field_origin(texelFetch(colortex29,ivec2(0),0));
    vec3 tint = astraWaterShaftTintSqrt*astraWaterShaftTintSqrt;
    waterShaftIllumination = max(astraSolasSurfaceDirect,vec3(0.0))
        *mix(tint,tint*solasWeather,wetness)*astraWaterTransmissionTint*(visibility*0.0935);
    #endif
}
