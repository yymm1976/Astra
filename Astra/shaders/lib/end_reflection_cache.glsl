#ifndef ASTRA_END_REFLECTION_CACHE_GLSL
#define ASTRA_END_REFLECTION_CACHE_GLSL
// Original Astra current-frame environment cache. Stars remain ray-resolved;
// Sharp source regions retain the analytic path. Polished reflections retain
// moving silhouette bounds; rough materials accept the cached broad silhouette.
uniform sampler2D colortex11;
bool end_reflection_cache_read(vec3 ray, float roughness, out vec3 sky) {
    if (dot(ray,end_light_direction()) > 0.04) {
        float radius=end_kerr_radius(end_kerr_screen(ray));
        // Keep the horizon/photon ring and polished disc reflections exact.
        if (radius < 1.4 || (roughness < 0.12 && radius < 7.0)) return false;
    }
    // A rough reflection cannot resolve every small island. Avoid a per-pixel
    // scan of all body records for it; cache visibility still rejects large
    // discontinuities below. Native sky geometry remains ray-resolved.
    if (roughness < 0.20) for (int id=66; id<END_BODY_COUNT; ++id) {
        vec4 body=end_body(id);
        float along=dot(body.xyz,ray);
        float radius=body.w*1.65;
        // Polished reflections use the SAME bounding sphere as end_body_hit,
        // preserving islands smaller than the environment-map footprint.
        if (along>0.0 && dot(body.xyz,body.xyz)-along*along <= radius*radius)
            return false;
    }
    ivec2 size=textureSize(colortex11,0);
    float longitude=dot(ray.xz,ray.xz)>1e-10 ? atan(ray.z,ray.x)/END_TAU+0.5 : 0.5;
    float latitude=asin(clamp(ray.y,-1.0,1.0))/END_PI+0.5;
    #ifdef ROUGH_SKY_REFLECTIONS
    float horizontal=fract(longitude)*float(size.x)-0.5;
    #else
    float horizontal=fract(longitude)*float(size.x-2)+0.5;
    #endif
    float vertical=clamp(latitude*float(size.y)-0.5,0.0,float(size.y-1));
    ivec2 base=ivec2(floor(vec2(horizontal,vertical)));
    vec2 blend=fract(vec2(horizontal,vertical));
    vec4 taps[4];
    vec3 lo=vec3(1e20), hi=vec3(0.0);
    float minVisibility=1.0, maxVisibility=0.0;
    float roughApproximation=smoothstep(0.12,0.50,roughness);
    float visibilityTolerance=mix(0.01,0.08,roughApproximation);
    for (int i=0;i<4;++i) {
        ivec2 pixel=base+ivec2(i&1,i>>1);
        #ifdef ROUGH_SKY_REFLECTIONS
        pixel.x=(pixel.x+size.x)%size.x;
        #endif
        pixel=clamp(pixel,ivec2(0),size-1);
        taps[i]=texelFetch(colortex11,pixel,0);
        lo=min(lo,taps[i].rgb); hi=max(hi,taps[i].rgb);
        minVisibility=min(minVisibility,taps[i].a);
        maxVisibility=max(maxVisibility,taps[i].a);
        // Coverage spread can only grow as more corners are added. Once this
        // footprint must use the analytic sky, remaining cache reads are unused.
        if (maxVisibility-minVisibility>visibilityTolerance) return false;
    }
    vec3 spread=hi-lo;
    float peak=max(hi.r,max(hi.g,hi.b));
    float colourTolerance=mix(0.02,0.20,roughApproximation);
    if (max(spread.r,max(spread.g,spread.b))>max(peak*colourTolerance,0.000001))
        return false;
    vec4 environment=mix(mix(taps[0],taps[1],blend.x),
                         mix(taps[2],taps[3],blend.x),blend.y);
    sky=environment.rgb;
    if (environment.a>0.00001) {
        vec2 pixelCone=2.0/max(abs(vec2(gbufferProjection[0][0],gbufferProjection[1][1]))
                              *vec2(viewWidth,viewHeight),vec2(1.0));
        float cone=max(max(pixelCone.x,pixelCone.y),0.00002);
        sky+=end_starfield(end_lensed_background(ray),end_light_direction(),cone)
            *environment.a*ASTRA_TINT_END_SKY*(1.0-clamp(blindness,0.0,1.0))
            *(1.0-0.18*end_eclipse());
    }
    return true;
}
#endif
