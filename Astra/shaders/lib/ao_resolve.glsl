#ifndef ASTRA_AO_RESOLVE_GLSL
#define ASTRA_AO_RESOLVE_GLSL
#include "/lib/sky_directional.glsl"
#include "/global/water/medium_state.glsl"
uniform sampler2D colortex19;
uniform sampler2D colortex20;
uniform sampler2D colortex21;
#ifdef ASTRA_DIRECTIONAL_SKYLIGHT
uniform sampler2D colortex26;
uniform sampler2D colortex27;
#endif

// R1: bentNormal is the edge-aware reconstruction of the half-resolution bent
// normal (colortex26, produced by the AO pass). It rides the exact same 4-tap
// bilinear weights and accept tests as the scalar visibility - depth and
// geometric-normal agreement decide which half-res texels contribute, so the
// direction cannot bleed across silhouettes. With no matching sample, or when
// the directional-sky feature is off, it falls back to the passed geometric
// normal (which then makes the SH swap below a no-op).
float astra_ao_visibility(vec2 uv, float viewDepth, vec3 normal, out vec3 bentNormal) {
    ivec2 size=textureSize(colortex21,0);
    vec2 coordinate=uv*vec2(size)-0.5;
    ivec2 base=ivec2(floor(coordinate));
    vec2 fraction=fract(coordinate);
    float sum=0.0, weightSum=0.0;
    vec3 bentSum=vec3(0.0); float bentWeight=0.0;
    float depth=log2(1.0+max(viewDepth,0.0));
    for(int y=0;y<2;++y) for(int x=0;x<2;++x) {
        vec2 axis=mix(1.0-fraction,fraction,bvec2(x==1,y==1));
        float spatialWeight=axis.x*axis.y;
        if(spatialWeight <= 0.0) continue;
        ivec2 p=clamp(base+ivec2(x,y),ivec2(0),size-1);
        vec4 ao=texelFetch(colortex21,p,0);
        float depthDifference=abs(ao.g-depth);
        if(ao.g < 0.0 || depthDifference > 0.05) continue;
        vec3 sampleNormal=decode_unit_vector(ao.ba*2.0-1.0);
        float agreement=max(dot(normal,sampleNormal),0.0);
        if(agreement < 0.85) continue;
        float weight=spatialWeight*exp2(-64.0*depthDifference)*pow(agreement,8.0);
        sum+=ao.r*weight; weightSum+=weight;
        #ifdef ASTRA_DIRECTIONAL_SKYLIGHT
        vec3 sampleBent=decode_unit_vector(texelFetch(colortex26,p,0).rg*2.0-1.0);
        bentSum+=sampleBent*weight; bentWeight+=weight;
        #endif
    }
    #ifdef ASTRA_DIRECTIONAL_SKYLIGHT
    bentNormal = bentWeight > 0.00001 && dot(bentSum,bentSum) > 1e-8
        ? normalize(bentSum) : normal;
    #else
    bentNormal = normal;
    #endif
    return weightSum > 0.00001 ? sum/weightSum : 1.0;
}

vec3 astra_apply_ambient_ao(vec3 scene, vec2 uv, float viewDepth, vec3 skyPalette) {
    ivec2 p=ivec2(uv*vec2(textureSize(colortex20,0)));
    vec4 normal=texelFetch(colortex20,p,0);
    if(normal.a < 0.5 || (isEyeInWater != 0 && !water_is_thin_sheet())) return scene;
    float vertexAO=clamp((round(normal.a*255.0)-128.0)/127.0,0.0,1.0);
    if(vertexAO <= 0.0) return scene;
    vec3 geometryNormal=normalize(normal.rgb*2.0-1.0);
    vec3 bentNormal;
    float visibility=astra_ao_visibility(uv,viewDepth,geometryNormal,bentNormal);
    vec3 skySwap=vec3(0.0);
    #ifdef ASTRA_DIRECTIONAL_SKYLIGHT
    // R1: re-evaluate the SH sky at the bent normal. colortex27.rgb carries the
    // directional-sky share of the rendered ambient WITHOUT the SH direction
    // (albedo x sky access x night/ramp factors, written by lit), so this swap
    // touches only that share: cave floor, block light, direct light and
    // emission are untouched, and colortex19 is never rescaled wholesale.
    // The palette matches LightParams.skyAmbient (same astra_sky_ambient() the
    // lit pass used) and the geometric normal comes from the full-resolution
    // colortex20, so S_SH(geo) here equals the term that was rendered.
    vec3 response=texelFetch(colortex27,p,0).rgb;
    if(response.r+response.g+response.b > 0.0 && any(notEqual(bentNormal,geometryNormal))) {
        vec3 coefficients[9];
        for(int i=0;i<9;++i) coefficients[i]=texelFetch(colortex18,ivec2(i,0),0).rgb;
        vec3 skyGeometry=astra_directional_sky_coeffs(coefficients,geometryNormal,skyPalette);
        vec3 skyBent=astra_directional_sky_coeffs(coefficients,bentNormal,skyPalette);
        // AO bookkeeping: the scene already contains sky(geo)*vertexAO; the
        // scalar removal below takes ambient*extra with extra = vertexAO - min.
        // Adding the swapped share at min(vertexAO, SSAO) cancels the old
        // geometric-normal term completely and leaves sky(bent)*min.
        skySwap=response*(skyBent-skyGeometry)*min(vertexAO,visibility);
    }
    #endif
    // Geometry already applied vertex AO to ambient once. Add only the excess
    // screen-space occlusion: min(vertex AO, SSAO), not their product.
    float extra=max(vertexAO-min(vertexAO,visibility),0.0);
    // Vertex AO often already supplies all the scalar occlusion required here.
    vec3 ambient=extra>0.0 ? texelFetch(colortex19,p,0).rgb : vec3(0.0);
    return max(scene-ambient*extra+skySwap,vec3(0.0));
}
#endif
