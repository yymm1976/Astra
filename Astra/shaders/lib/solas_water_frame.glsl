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
void solas_water_fog_frame_parameters(out vec3 fogBase, out vec2 fogResponse) {
    float eyeSky = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
    // Share the surface body's middle-depth cyan and its incident lighting.
    // Weather belongs to that lighting, never a separate grey colour overlay.
    fogBase = astra_water_body_palette(vec2(1.0, 0.0)) * solas_water_interface_incident();
    // Camera blindness is applied once to the complete underwater composite.
    fogResponse = vec2(0.65 + 0.35 * eyeSky, 0.0);
}
// Inputs are already linear. Keep the surface hue without a second palette,
// grey weather mix, or nonlinear colour conversion before the display curve.
vec3 solas_water_medium_linear(vec3 fogBase, float responseX) {
    return fogBase * responseX;
}
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
    #ifdef ASTRA_WATER_FOG_FRAME_WRITE
    flat out vec3 waterInterfaceIncident;
    flat out vec3 waterFogFrameMedium;
    #elif defined ASTRA_WATER_FOG_FRAME_READ
    flat in vec3 waterInterfaceIncident;
    flat in vec3 waterFogFrameMedium;
    #endif
#endif
#endif
