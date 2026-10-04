#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/transforms.glsl"
#include "/lib/effect_history.glsl"
#ifndef RGBA32F
const int RGBA32F=0;
#endif
const int colortex30Format=RGBA32F;
const bool colortex30Clear=false;
const vec4 colortex30ClearColor=vec4(0.0,0.0,0.0,0.0);
/* RENDERTARGETS: 30 */
void main() {
    int x=int(gl_FragCoord.x);
    if(x==0) gl_FragData[0]=vec4(viewWidth,viewHeight,float(frameCounter),float(isEyeInWater));
    else if(x==1) gl_FragData[0]=vec4(blindness,darknessFactor,frameTimeCounter,0.0);
    else gl_FragData[0]=vec4(astraEffectDimension,0.0,0.0,4.0);
}
