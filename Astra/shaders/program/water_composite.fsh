// Solas water fog and volume composition before bloom, in reference order.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/solas_water.glsl"
#include "/global/water/light_shafts.glsl"
uniform sampler2D colortex0;
#ifdef ASTRA_UNDERWATER_SHAFTS
uniform sampler2D colortex1;
#endif
in vec2 texcoord;
/* RENDERTARGETS: 0 */
void main() {
    vec3 color = texture(colortex0, texcoord).rgb;
    if (isEyeInWater == 1) {
        float rayLength;
        vec3 viewPos = water_shafts_view(texcoord, rayLength);
        vec3 shafts = vec3(0.0);
        #ifdef ASTRA_UNDERWATER_SHAFTS
            shafts = water_shafts_resolve(colortex1, texcoord, rayLength) * (UNDERWATER_SHAFT_STRENGTH * 0.01);
        #endif
        // The supplied Solas stores its pre-composite gamma scene in normalized
        // color targets. Preserve that bound across Astra's linear HDR storage.
        color = solas_water_composite(clamp(color, 0.0, 1.0), viewPos, shafts)
              * (1.0 - clamp(blindness, 0.0, 1.0));
    }
    gl_FragData[0] = vec4(color, 1.0);
}
