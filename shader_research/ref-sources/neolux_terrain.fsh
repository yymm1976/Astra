#version 120

/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16;
const int colortex2Format = RGBA8;
const int colortex3Format = RGB16F;
const int colortex4Format = RGB16F;
const int colortex5Format = RGBA8;
*/


#include "/lib/common.glsl"
#include "/lib/water.glsl"

uniform sampler2D texture;
uniform float wetness;
uniform float rainBiome;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 tint;
varying vec3 viewNormal;
varying float matID;
varying vec3 worldPosV;
varying float upFacing;

/* DRAWBUFFERS:125 */
void main() {
    vec4 col = texture2D(texture, texcoord) * tint;
    if (col.a < ALPHA_CUTOUT) discard;

    gl_FragData[0] = vec4(nlEncodeNormal(viewNormal), lmcoord.x, 1.0);
    gl_FragData[1] = vec4(col.rgb, 1.0);
    // Standing water after rain: only on solid blocks facing up under the
    // open sky. The deferred pass darkens the ground under it, composite
    // mirrors the surroundings in it.
    float puddle = 0.0;
#ifdef PUDDLES
    if (matID < 0.25 && upFacing > 0.9)
        puddle = nlPuddleMask(worldPosV.xz, wetness * rainBiome * PUDDLE_AMOUNT)
               * smoothstep(0.86, 0.96, lmcoord.y);
#endif

    gl_FragData[2] = vec4(lmcoord.y, matID, puddle, 1.0);
}
