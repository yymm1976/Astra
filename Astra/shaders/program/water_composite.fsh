// Solas water fog and volume composition before bloom, in reference order.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/solas_water.glsl"
#include "/global/water/light_shafts.glsl"
#include "/lib/water_diffusion.glsl"
uniform sampler2D colortex0;
#ifdef ASTRA_UNDERWATER_SHAFTS
uniform sampler2D colortex1;
#endif
in vec2 texcoord;
// Geometry has finished consuming the opaque snapshot. Reuse its alternate
// attachment for the composed underwater scene; air consumers keep colortex0.
/* RENDERTARGETS: 4 */
void main() {
    if (isEyeInWater != 1 || DEBUG_VERTEX_AO != 0) discard;
    vec3 color = texture(colortex0, texcoord).rgb;
    // Every underwater texel is written before any consumer selects colortex4.
    float rayLength;
    vec3 viewPos = water_shafts_view(texcoord, rayLength);
    color = water_diffuse_scene(colortex0, texcoord, texcoord, color, rayLength);
    vec3 shafts = vec3(0.0);
    #ifdef ASTRA_UNDERWATER_SHAFTS
    if (!water_is_thin_sheet())
        shafts = water_shafts_resolve(colortex1, texcoord, rayLength) * (UNDERWATER_SHAFT_STRENGTH * 0.01);
    #endif
    // Preserve solar and focused-light peaks until the display tone curve.
    color = solas_water_composite(max(color, vec3(0.0)), viewPos, shafts, texcoord)
          * (1.0 - clamp(blindness, 0.0, 1.0));
    gl_FragData[0] = vec4(color, 1.0);
}
