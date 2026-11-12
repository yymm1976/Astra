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

uniform sampler2D texture;

varying vec2 texcoord;
varying vec4 tint;

/* DRAWBUFFERS:05 */
void main() {
    vec4 col = texture2D(texture, texcoord) * tint;
    float amount = dot(col.rgb, vec3(0.3333)) * col.a;

    // The enchantment shimmer glows on its own instead of being lit with
    // the item. Without a program of its own it fell back to
    // gbuffers_textured, which overwrote the albedo with the glint texture
    // and marked the item as unlit: a flat purple sheet. Added to the albedo
    // instead, it was lit with the item and disappeared at night.
    // Hand, dropped items and armor are drawn before the deferred pass and
    // only reach colortex0 through it, so the amount goes into the alpha of
    // colortex5, which the deferred pass turns into glow (see the blend rules
    // in shaders.properties). Whatever is drawn after the deferred pass gets
    // the glow straight into the scene color.
    gl_FragData[0] = vec4(nlGlintColor() * amount, 0.0);
    gl_FragData[1] = vec4(0.0, 0.0, 0.0, amount);
}
