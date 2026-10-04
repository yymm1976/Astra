#ifndef ASTRA_WATER_SHAFT_HISTORY_GLSL
#define ASTRA_WATER_SHAFT_HISTORY_GLSL
// Independent volume accumulation. Solas taa.glsl supplies the temporal blend;
// Astra uses a bounded compressed contrast interval instead of its 3x3 YCoCg
// neighbourhood clip. Only VL is accumulated here, not scene colour.
#include "/lib/effect_history.glsl"
#include "/lib/water_palette.glsl"
uniform sampler2D colortex29;
vec4 water_shafts_history(vec4 current,vec2 uv,vec3 endpoint,float marchLength) {
    if (current.a<=0.0) return current;
    vec4 previousEffects;
    if (!astra_effect_history_valid(previousEffects)) return current;
    float rayLength=current.a*128.0;
    vec3 direction=normalize(endpoint);
    // Reproject the actual integration window. The stored full ray length
    // remains the endpoint identity used for foreground/background rejection.
    vec3 midpoint=view_camera_relative(direction*marchLength*0.5);
    vec3 previous=astra_effect_previous_screen(midpoint);
    if (any(isnan(previous)) || any(isinf(previous))
        || previous.z < 0.0 || previous.z > 1.0) return current;
    vec2 size=vec2(textureSize(colortex29,0));
    vec2 edge=0.5/size;
    if(any(lessThan(previous.xy,edge)) || any(greaterThan(previous.xy,1.0-edge))) return current;
    vec3 oldEndpoint=(gbufferPreviousModelView*vec4(
        view_camera_relative(direction*rayLength)+cameraPosition-previousCameraPosition,1.0)).xyz;
    float expectedLength=length(oldEndpoint);
    float motion=length((previous.xy-uv)*size);
    vec2 location=previous.xy*size-0.5;
    ivec2 base=ivec2(floor(location));
    vec2 fraction=fract(location);
    vec3 correction=vec3(0.0);
    // Smooth for a short duration, rather than a fixed number of frames.
    // Fixed 0.9 at rest delayed wave motion most at low frame rates.
    float previousTime=previousEffects.z;
    float elapsed=max(frameTimeCounter-previousTime,0.0);
    float historyWeight=min(exp(-elapsed/0.065),0.94)*(0.78+0.22*exp(-motion));
    vec3 lowerBound=max(current.rgb-0.08,vec3(0.0));
    vec3 upperBound=current.rgb+0.08;
    // Reject each bilinear contributor before interpolating. Interpolated ray
    // lengths can otherwise appear valid between unrelated foreground/background rays.
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        ivec2 pixel=base+ivec2(x,y);
        if(any(lessThan(pixel,ivec2(0))) || any(greaterThanEqual(pixel,ivec2(size)))) continue;
        vec2 axis=mix(1.0-fraction,fraction,bvec2(x==1,y==1));
        float spatialWeight=axis.x*axis.y;
        if(spatialWeight<=0.0) continue;
        vec4 old=texelFetch(colortex29,pixel,0);
        if(old.a<=0.0 || any(isnan(old)) || any(isinf(old))) continue;
        float delta=abs(min(old.a*128.0,astraWaterShaftRange)
                       -min(expectedLength,astraWaterShaftRange));
        if(delta>2.0+rayLength*0.04) continue;
        float blend=spatialWeight*historyWeight*exp(-delta*0.25);
        // Keep the contrast bound in fourth-root storage, before VL decoding.
        vec3 history=clamp(old.rgb,lowerBound,upperBound);
        correction+=(history-current.rgb)*blend;
    }
    // Missing history coverage stays current-frame colour; do not renormalize it.
    current.rgb+=correction;
    return current;
}
#endif
