// Disc/galaxy/geometry. Native-resolution lensed stars and photon ring are
// composed later; A stores the background transmission through this scene.
#define ASTRA_END_SKY_BUFFER
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/program/scene.glsl"
#ifndef RGBA16F
const int RGBA16F = 0;
#endif
const int colortex9Format = RGBA16F;
in vec2 texcoord;
/* RENDERTARGETS: 9 */
void main() {
    vec3 ray = normalize(view_player(screen_view(vec3(texcoord, 1.0))));
    end_sky_ray_cone = max(length(dFdx(ray)),length(dFdy(ray)));
    // Include the reconstruction neighbourhood so foreground silhouettes cannot
    // pull unrendered texels into an adjacent sky pixel during upsampling.
    vec2 pixel = 1.0 / vec2(textureSize(depthtex0, 0));
    float skyDepth = texture(depthtex0,texcoord).r;
    // A sky centre already proves this tile must render. Search the conservative
    // neighbourhood only for geometry centres, stopping at the first sky sample.
    if (skyDepth < 0.999999) {
        for (int y=-2; y<=2; ++y) {
            for (int x=-2; x<=2; ++x) {
                skyDepth = max(skyDepth, texture(depthtex0, clamp(texcoord + vec2(x,y)*pixel,
                               pixel*0.5, 1.0-pixel*0.5)).r);
                if (skyDepth >= 0.999999) break;
            }
            if (skyDepth >= 0.999999) break;
        }
    }
    if (skyDepth < 0.999999) { gl_FragData[0] = vec4(0.0); return; }
    vec3 color = astra_sky(ray);
    gl_FragData[0] = vec4(color, end_star_visibility);
}
