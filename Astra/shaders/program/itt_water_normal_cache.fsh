// Single current-frame producer: collision flux from ITT's moving six-layer slopes.
// Neither permanent entry apertures nor a depth-dependent inverse solver exists.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/global/water/optics.glsl"
#include "/global/water/medium_state.glsl"
#include "/lib/itt_water_field.glsl"
#include "/lib/itt_water_waves.glsl"
#ifndef RG16F
const int RG16F = 0;
#endif
const int colortex29Format = RG16F;
const bool colortex29Clear = false;
flat in vec4 ittWaterFieldWindow;
flat in vec3 ittWaterFieldLight;
/* RENDERTARGETS: 29 */
void main() {
    if (isEyeInWater != 1) discard;
    // Coverage and the volume pass use the same current-frame water state.
    if (all(equal(ivec2(gl_FragCoord.xy),ivec2(0)))) {
        gl_FragData[0] = vec4(ittWaterFieldWindow.zw,0.0,0.0);
        return;
    }
    vec2 worldXZ = (ittWaterFieldWindow.xy+gl_FragCoord.xy)*ITT_WATER_FIELD_CELL;
    vec2 slope = itt_water_wave_slope(worldXZ,ITT_WATER_FIELD_CELL);
    gl_FragData[0] = vec4(water_shaft_collision_light(slope,ittWaterFieldLight),0.0,0.0,0.0);
}
