// Astra v1 - program/composite1.fsh (bloom capture -> colortex2)
// Uniforms: colortex0 (sampler, declared here). colortex2's extent is declared once,
// under size.buffer.colortex2 in shaders.properties; BLOOM_CAPTURE_SCALE in
// global/post/bloom.glsl has to track that same value.
//
// Stage 1 of the two-pass bloom (design.md 4.4). Stage 2 - reading the mip levels and
// adding them to the scene - is in the final chain and belongs to E1/C6, since the
// pass order and the buffers final reads are E1's resolution (design.md 2.2,
// tasks-advanced-1.md cooperative rule 2).
//
// The mip levels are the multi-scale bloom source: final.fsh requests their generation
// immediately before it reads them. A request here would mipmap the previous contents
// before capture overwrites level zero. bloom_composite() reads four levels. That is
// what lets two passes do the work of Mellow's 6-pass pyramid.
// design.md 3.2 layer 2: program/* is the only lib entry
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/global/water/medium_state.glsl"
#define ASTRA_BLOOM_CAPTURE
#include "/global/post/bloom.glsl"
in vec2 texcoord;

uniform sampler2D colortex0;

/* RENDERTARGETS: 2 */

void main() {
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Underwater final uses the separate colortex7 bloom captured after water
    // composition. Thin sheets retain the air curve and this HDR pyramid.
    // Write a defined value so no framebuffer preservation is required.
    if (isEyeInWater == 1 && !water_is_thin_sheet()) {
        gl_FragData[0] = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }
    #endif
	gl_FragData[0] = vec4(bloom_capture(colortex0, texcoord), 1.0);
}
