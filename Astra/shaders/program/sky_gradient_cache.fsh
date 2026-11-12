// Same-frame low-frequency angular sky table, before any geometry or reflection.
// Sky equations retain their existing Complementary provenance and licence.
#define ASTRA_GRADIENT_SKY_WRITE
#include "/program/scene.glsl"
// Shared colortex12 format declaration (same target as the raw screen-cloud cache).
#include "/lib/cloud_buffer_formats.glsl"
/* RENDERTARGETS: 12 */
void main() {
    vec2 angles = astra_gradient_sky_angles(gl_FragCoord.xy);
    vec3 sky = astra_get_sky_base(angles.x, angles.y, astra_sky_factors(), astra_sky_palette());
    gl_FragData[0] = vec4(sky, 1.0);
}
