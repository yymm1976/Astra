// composite1 follows the current water-state scan. Air and thin sheets have no
// ITT field consumer; clip before rasterisation without relying on prior state.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/global/water/medium_state.glsl"
#include "/lib/itt_water_field.glsl"
flat out vec4 ittWaterFieldWindow;
flat out vec3 ittWaterFieldLight;
void main() {
    gl_Position = ftransform();
    if (isEyeInWater != 1 || water_is_thin_sheet()) {
        gl_Position = vec4(-2.0,-2.0,0.0,1.0);
        return;
    }
    #if !defined WATER_WAVES || WATER_WAVE_HEIGHT == 0
    gl_Position = vec4(-2.0,-2.0,0.0,1.0);
    return;
    #endif
    ittWaterFieldLight = itt_water_light_direction(shadowModelViewInverse);
    if (itt_water_source_visibility(ittWaterFieldLight) <= 0.0) {
        gl_Position = vec4(-2.0,-2.0,0.0,1.0);
        return;
    }
    vec3 down = refract(-ittWaterFieldLight,vec3(0.0,1.0,0.0),1.0/WATER_IOR);
    vec4 state = water_volume_state();
    float depth = state.a > 0.5
        ? max(water_unpack_surface_height(state.rg)-cameraPosition.y,0.0) : 0.0;
    vec2 centre = cameraPosition.xz-down.xz*(depth/max(-down.y,0.2));
    vec2 originCell = floor((centre/ITT_WATER_FIELD_CELL-ITT_WATER_FIELD_SIZE*0.5)/16.0)*16.0;
    ittWaterFieldWindow = vec4(originCell,originCell-floor(cameraPosition.xz/ITT_WATER_FIELD_CELL));
}
