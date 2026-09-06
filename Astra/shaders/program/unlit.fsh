// Astra E1. Texture and vertex color pass through in linear HDR.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/encoding.glsl"
in vec2 texcoord;
in vec4 tint;
/* RENDERTARGETS: 0 */
void main() {
    #ifdef ASTRA_BASIC
        vec4 color = tint;
    #else
        vec4 color = texture(gtexture, texcoord) * tint;
    #endif
    if (color.a < alphaTestRef) discard;
    color.rgb = srgb_decode(max(color.rgb, vec3(0.0)));
    #if defined ASTRA_BEAM && defined FANCY_TRANSLUCENTS
        color.rgb *= color.a;
    #endif
    gl_FragData[0] = color;
}