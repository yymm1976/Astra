// Four pixels of current-frame metadata, written after composite6 consumed history.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#ifdef ASTRA_TAA
#include "/lib/taa_state.glsl"
#ifndef RGBA32F
const int RGBA32F = 0;
#endif
const int colortex17Format = RGBA32F;
const bool colortex17Clear = false;
const vec4 colortex17ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
/* RENDERTARGETS: 17 */
void main() {
    int x = int(gl_FragCoord.x);
    if (x == 0) gl_FragData[0] = vec4(viewWidth, viewHeight, float(frameCounter % 4096), float(isEyeInWater));
    else if (x == 1) gl_FragData[0] = vec4(blindness, darknessFactor, frameTimeCounter, lightningBoltPosition.w);
    // Version 5: exact cyclic frame stamp; historical wind keeps its own distance LOD.
    else if (x == 2) gl_FragData[0] = vec4(astraTaaDimension, rainStrength, WAVING_FOLIAGE_STRENGTH*0.01, 5.0);
    #ifdef WAVING_FOLIAGE
    else gl_FragData[0] = vec4(astraFoliageWindPhases, 1.0);
    #else
    else gl_FragData[0] = vec4(0.0);
    #endif
}
#else
/* RENDERTARGETS: 0 */
void main() { discard; }
#endif
