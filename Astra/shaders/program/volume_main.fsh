// R2/H3 production: low-resolution world-ray march of the optional overworld volume.
// One texel per reduced-resolution pixel integrates the camera ray to the nearest
// geometry and stores vec4(S, T) in colortex23 (rgb = integrated in-scatter, a =
// transmittance; empty segment = (0,0,0,1)). The scene compose pass in program/
// deferred.fsh consumes it with an edge-aware upsample and composites scene*T+S.
//
// Sky pixels, underwater/lava/powder-snow cameras and blindness write the identity
// segment: those media stay owned by their existing paths (handoff R2 section 1).
// Ownership table and the deferred/deferred1/deferred2 slot scheduling are in
// docs/archive/实现与取证.md#record-077.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
// Same dimension condition as program/deferred.vsh: Nether/End never declare or
// write this flat water kind, and medium_state.glsl already returns false there.
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
#define ASTRA_WATER_STATE_FRAME_READ
#endif
#include "/program/scene.glsl"
uniform sampler2D colortex3;
uniform sampler2D colortex23;
in vec2 texcoord;
#ifndef RGBA16F
const int RGBA16F = 0;
#endif
const int colortex23Format = RGBA16F;
// Even excluded media, sky and hand pixels write the identity segment.
const bool colortex23Clear = false;
/* RENDERTARGETS: 23 */
void main() {
    vec4 result = astra_volume_identity();
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    if ((isEyeInWater == 0 || water_is_thin_sheet()) && blindness <= 0.0001 && VOLUME_FOG_DENSITY > 0) {
        ivec2 depthSize = textureSize(depthtex0, 0);
        // Use the same grid-centre arithmetic as the resolve, rather than an
        // interpolated UV that can round to the other side of a depth texel.
        vec2 sampleUV = gl_FragCoord.xy / vec2(textureSize(colortex23, 0));
        ivec2 pixel = clamp(ivec2(sampleUV * vec2(depthSize)), ivec2(0), depthSize - 1);
        float depth = texelFetch(depthtex0, pixel, 0).r;
        // Hand depth uses a separate projection scale. It cannot share the
        // terrain volume grid; deferred integrates its corrected endpoint.
        if (depth < 0.999999) {
            uint flags = uint(round(texelFetch(colortex3, pixel, 0).r * 255.0));
            if ((flags & 128u) == 0u) {
                // The low-resolution ray belongs to the full-resolution depth
                // texel actually selected, including odd viewport dimensions.
                vec2 receiverUV = (vec2(pixel) + 0.5) / vec2(depthSize);
                vec3 playerPos = view_camera_relative(screen_view(vec3(receiverUV, depth)));
                float distanceBlocks = length(playerPos);
                result = astra_volume_march(playerPos / max(distanceBlocks, 1e-5), distanceBlocks, true,
                                            ASTRA_VOLUME_STEPS);
            }
        }
    }
    #endif
    gl_FragData[0] = result;
}
