#ifndef ASTRA_SOLAS_WATER_FRAME_GLSL
#define ASTRA_SOLAS_WATER_FRAME_GLSL
#include "/lib/water_palette.glsl"
// The thin-sheet incident colour is built from compile-time palette macros, so
// the vertex stages need them too. Guarded, so the fragment include is a no-op.
#include "/lib/colors.glsl"
// Shared draw-constant part of the existing Solas water expression. Kept free
// of fragment-only interface reads so full-screen vertex stages can prepare it.
const vec3 solasWaterSqrt = astraWaterTintSqrt;
const vec3 solasWeather = vec3(175.0, 185.0, 255.0) / 255.0 * 0.60;
const vec3 solasMinLightSqrt = vec3(125.0, 130.0, 135.0) * (0.40 / 255.0);
const vec3 solasMinLight = solasMinLightSqrt * solasMinLightSqrt * 0.1;
uniform float wetness;
uniform float astraSolasTimeBrightness;
uniform float astraSolasShadowFade;
uniform float astraSolasTimeAngle;

float solas_sun_visibility() {
    return clamp(worldSunVector.y + 0.1, 0.0, 0.25) * 4.0;
}
void solas_water_fog_frame_parameters(out vec3 fogBase, out vec2 fogResponse) {
    fogBase = mix(mix(solasWaterSqrt * solasWaterSqrt,
                      normalize(fogColor + 0.00001) * 0.5, 0.10),
                  solasWeather * 0.25, wetness * 0.25);
    float eyeSky = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
    #ifdef ASTRA_UNDERWATER_SHAFTS
    // The shadowed volume owns directional sunlight. Its previous unshadowed
    // fog glare painted a broad bright patch even where no beam could pass.
    fogResponse = vec2(0.5 + 0.5 * eyeSky
                       + 0.12 * astraSolasTimeBrightness * eyeSky, 0.0);
    #else
    fogResponse = vec2(0.5 + 0.5 * eyeSky, 0.35 * astraSolasTimeBrightness * eyeSky);
    #endif
    fogBase *= (0.1 + solas_sun_visibility() * 0.4) * (1.0 - clamp(blindness, 0.0, 1.0));
}
// Linear medium radiance. The old composite blended fog in a pow(..., 1/4.4)
// domain and decoded with pow(..., 4.4), so it reached the frame as
// fogBase ^ 2.2. That value is kept as the intensity reference, so the current
// sky/weather/cave/blindness brightness response is unchanged. The hue now
// follows ITT 3.2 composite1.fsh:54-55 (vec3(0.05,0.6,1.0), wetness graying
// toward vec3(0.5)), renormalised to the legacy luma so the shift cannot
// brighten the medium on its own. All inputs are draw constants, so this runs
// once per vertex instead of once per pixel.
vec3 solas_water_medium_linear(vec3 fogBase, float responseX, float weatherAmount) {
    vec3 legacy = pow(max(fogBase * responseX, vec3(0.0)), vec3(2.2));
    float intensity = dot(legacy, vec3(0.2126, 0.7152, 0.0722));
    vec3 ratio = mix(vec3(0.05, 0.6, 1.0), vec3(0.5), clamp(weatherAmount, 0.0, 1.0) * 0.6);
    float ratioLuma = max(dot(ratio, vec3(0.2126, 0.7152, 0.0722)), 1e-5);
    return ratio * (intensity / ratioLuma);
}
// Frame-constant thin-sheet incident light: the same ambient hue as
// astra_sky_ambient(), through the shared natural-look gain in
// lib/color_controls.glsl. Every input is a uniform, so a full-screen vertex
// stage can prepare it once; the per-pixel water leg stays in the fragment.
vec3 solas_water_interface_incident() {
    vec3 outdoor = astraAmbientPalette * ASTRA_TINT_AMBIENT * ASTRA_STYLE_AMBIENT
                 * ASTRA_OVERWORLD_AMBIENT_GAIN
                 * (SKYLIGHT_STRENGTH * 0.01);
    float access = smoothstep(0.0, 0.40, float(eyeBrightnessSmooth.y) / 240.0);
    return mix(MIN_AMBIENT_COLOR, outdoor, access);
}
#ifdef ASTRA_OVERWORLD_OPTIMIZED
    #ifdef ASTRA_WATER_FOG_FRAME_WRITE
    flat out vec3 waterFogFrameBase;
    flat out vec2 waterFogFrameResponse;
    flat out vec3 waterInterfaceIncident;
    #ifdef ASTRA_UNDERWATER_SHAFTS
    flat out vec3 waterFogFrameMedium;
    #endif
    #elif defined ASTRA_WATER_FOG_FRAME_READ
    flat in vec3 waterFogFrameBase;
    flat in vec2 waterFogFrameResponse;
    flat in vec3 waterInterfaceIncident;
    #ifdef ASTRA_UNDERWATER_SHAFTS
    flat in vec3 waterFogFrameMedium;
    #endif
    #endif
#endif
#endif
