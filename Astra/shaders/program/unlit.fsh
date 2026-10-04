// Astra E1. Texture and vertex color pass through in linear HDR.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/encoding.glsl"
#include "/lib/taa_reactive.glsl"
#include "/lib/surface_buffers.glsl"
in vec2 texcoord;
in vec4 tint;
#ifdef ASTRA_TAA
    #ifdef ASTRA_SSAO
    /* RENDERTARGETS: 0,16,19,20 */
    #define ASTRA_UNLIT_AO_SLOT 2
    #define ASTRA_UNLIT_NORMAL_SLOT 3
    #else
/* RENDERTARGETS: 0,16 */
    #endif
#else
    #ifdef ASTRA_SSAO
    /* RENDERTARGETS: 0,19,20 */
    #define ASTRA_UNLIT_AO_SLOT 1
    #define ASTRA_UNLIT_NORMAL_SLOT 2
    #else
/* RENDERTARGETS: 0 */
    #endif
#endif
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
    #ifdef ASTRA_SSAO
    // Unlit overlays have no separately shaded ambient contribution.
    gl_FragData[ASTRA_UNLIT_AO_SLOT] = vec4(0.0);
    gl_FragData[ASTRA_UNLIT_NORMAL_SLOT] = vec4(0.0);
    #endif
    #ifdef ASTRA_TAA
    gl_FragData[1] = vec4(1.0, 0.0, 0.0, 1.0);
    #endif
}
