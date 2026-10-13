// Disc/plasma/geometry. Native-resolution lensed stars and photon ring are
// composed later; A stores the background transmission through this scene.
#define ASTRA_END_SKY_BUFFER
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/scene_buffer_formats.glsl"
#include "/program/scene.glsl"
in vec2 texcoord;
/* RENDERTARGETS: 9 */
void main() {
    vec3 ray = normalize(view_player(screen_view(vec3(texcoord, 1.0))));
    end_sky_ray_cone = max(length(dFdx(ray)),length(dFdy(ray)));
    // colortex9 now shares depthtex0's native grid (shaders.properties).
    // Deferred reads the exact same texel, so geometry needs no sky neighbourhood.
    ivec2 pixel = clamp(ivec2(gl_FragCoord.xy), ivec2(0), textureSize(depthtex0, 0)-1);
    float skyDepth = texelFetch(depthtex0, pixel, 0).r;
    if (skyDepth < 0.999999) { gl_FragData[0] = vec4(0.0); return; }
    vec3 color = astra_sky(ray);
    gl_FragData[0] = vec4(color, end_star_visibility);
}
