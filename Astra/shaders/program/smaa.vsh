#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#define SMAA_INCLUDE_VS 1
#define SMAA_INCLUDE_PS 0
#include "/lib/smaa_config.glsl"
out vec2 texcoord;
#ifdef ASTRA_SMAA_WEIGHT_PASS
out vec2 smaaPixel;
#endif
out vec4 smaaOffset[3];
void main() {
    gl_Position=ftransform();
    texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
    #ifdef ASTRA_SMAA_WEIGHT_PASS
    SMAABlendingWeightCalculationVS(texcoord,smaaPixel,smaaOffset);
    #else
    SMAAEdgeDetectionVS(texcoord,smaaOffset);
    #endif
}
