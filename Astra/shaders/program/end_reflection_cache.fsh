// Original Astra. The End owns colortex11 in this dimension; the overworld
// retains its existing format, producer, projection and optional mip behavior.
#define ASTRA_END_REFLECTION_CACHE_WRITE
#define ASTRA_SKY_CACHE_WRITE
#include "/program/scene.glsl"
#include "/lib/sky_reflection_cache.glsl"
#ifndef RGBA16F
const int RGBA16F=0;
#endif
const int colortex11Format=RGBA16F;
/* RENDERTARGETS: 11 */
void main() {
    vec3 ray=astra_sky_cache_direction(gl_FragCoord.xy);
    vec2 pixelCone=2.0/max(abs(vec2(gbufferProjection[0][0],gbufferProjection[1][1]))
                          *vec2(viewWidth,viewHeight),vec2(1.0));
    end_sky_ray_cone=max(max(pixelCone.x,pixelCone.y),0.00002);
    vec3 sky=end_sky(ray);
    gl_FragData[0]=vec4(sky,end_star_visibility);
}
