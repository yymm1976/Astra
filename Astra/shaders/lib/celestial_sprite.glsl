#ifndef ASTRA_CELESTIAL_SPRITE_GLSL
#define ASTRA_CELESTIAL_SPRITE_GLSL
// Reconstruct the active resource-pack sprite in linear light. Explicit texels
// soften the nearest-filtered colour bands without changing the square outline
// or Minecraft's phase coordinates. Premultiplied filtering keeps transparent
// texture borders from adding a dark fringe.
vec4 astra_celestial_sprite(sampler2D sprite, vec2 uv) {
    ivec2 size = textureSize(sprite,0);
    vec2 location = uv*vec2(size)-0.5;
    ivec2 base = ivec2(floor(location));
    vec2 f = fract(location);
    vec4 result = vec4(0.0);
    for (int y=0;y<2;++y) for (int x=0;x<2;++x) {
        vec2 axis = mix(1.0-f,f,bvec2(x==1,y==1));
        vec4 tap = texelFetch(sprite,clamp(base+ivec2(x,y),ivec2(0),size-1),0);
        result += vec4(srgb_decode(max(tap.rgb,vec3(0.0)))*tap.a,tap.a)*axis.x*axis.y;
    }
    if (result.a > 0.0) result.rgb /= result.a;
    return result;
}
#endif
