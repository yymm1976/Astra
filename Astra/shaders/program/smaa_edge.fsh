#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/smaa_buffer.glsl"
#define SMAA_INCLUDE_VS 0
#define SMAA_INCLUDE_PS 1
#include "/lib/smaa_config.glsl"
uniform sampler2D colortex13;
in vec2 texcoord;
in vec4 smaaOffset[3];
/* RENDERTARGETS: 7 */
void main() {
    #if defined DIMENSION_NETHER && DEBUG_NETHER_LIGHT > 0
    gl_FragData[0]=vec4(0.0);
    #else
    gl_FragData[0]=vec4(SMAAColorEdgeDetectionPS(texcoord,smaaOffset,colortex13),0.0,0.0);
    #endif
}
