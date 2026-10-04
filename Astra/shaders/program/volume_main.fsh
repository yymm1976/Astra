// R2/H3 production: low-resolution world-ray march of the optional overworld volume.
// One texel per half-resolution pixel integrates the camera ray to the nearest
// geometry and stores vec4(S, T) in colortex23 (rgb = integrated in-scatter, a =
// transmittance; empty segment = (0,0,0,1)). The scene compose pass in program/
// deferred.fsh consumes it with an edge-aware upsample and composites scene*T+S.
//
// Sky pixels, underwater/lava/powder-snow cameras and blindness write the identity
// segment: those media stay owned by their existing paths (handoff R2 section 1).
// Ownership table and the deferred/deferred1/deferred2 slot scheduling are in
// docs/handoffs/2026-09-27-R2-overworld-volume.md.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/program/scene.glsl"
uniform sampler2D colortex3;
in vec2 texcoord;
#ifndef RGBA16F
const int RGBA16F = 0;
#endif
const int colortex23Format = RGBA16F;
/* RENDERTARGETS: 23 */
void main() {
    vec4 result = astra_volume_identity();
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    if ((isEyeInWater == 0 || water_is_thin_sheet()) && blindness <= 0.0001 && VOLUME_FOG_DENSITY > 0) {
        float depth = textureLod(depthtex0, texcoord, 0.0).r;
        // Hand depth uses a separate projection scale. It cannot share the
        // terrain volume grid; deferred integrates its corrected endpoint.
        if (depth < 0.999999) {
            ivec2 pixel = clamp(ivec2(texcoord * vec2(textureSize(depthtex0, 0))),
                                ivec2(0), textureSize(depthtex0, 0) - 1);
            uint flags = uint(round(texelFetch(colortex3, pixel, 0).r * 255.0));
            if ((flags & 128u) == 0u) {
                // Same reconstruction convention as the deferred compose (jitter-aware).
                vec3 playerPos = view_camera_relative(screen_view(vec3(texcoord, depth)));
                result = astra_volume_march(normalize(playerPos), length(playerPos), true,
                                            ASTRA_VOLUME_STEPS);
            }
        }
    }
    #endif
    gl_FragData[0] = result;
}
