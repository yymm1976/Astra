#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#define ASTRA_WATER_FOG_FRAME_WRITE
#include "/lib/solas_water_frame.glsl"
#include "/global/water/medium_state.glsl"
out vec2 texcoord;
flat out int waterCompositeOrdinary;
void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    waterCompositeOrdinary = int(!water_is_thin_sheet());
    // Only Bloom consumes this composed attachment. Without it, display owns
    // the underwater composition. Air pixels never consume it in either mode.
    #ifndef ASTRA_BLOOM
    gl_Position=vec4(-2.0,-2.0,0.0,1.0);
    #else
    if (isEyeInWater!=1 || DEBUG_VERTEX_AO!=0)
        gl_Position=vec4(-2.0,-2.0,0.0,1.0);
    #endif
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    waterFogFrameMedium = vec3(0.0);
    waterInterfaceIncident = vec3(0.0);
    if (isEyeInWater == 1 && DEBUG_VERTEX_AO == 0) {
        vec3 fogBase;
        vec2 fogResponse;
        solas_water_fog_frame_parameters(fogBase, fogResponse);
        waterFogFrameMedium = solas_water_medium_linear(fogBase, fogResponse.x);
        waterInterfaceIncident = solas_water_interface_incident();
    }
    #endif
}
