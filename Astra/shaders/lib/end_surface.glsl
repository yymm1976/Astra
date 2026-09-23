#ifndef ASTRA_END_SURFACE_GLSL
#define ASTRA_END_SURFACE_GLSL
#include "/lib/end_light.glsl"
// A bounded, integrated disc-light proxy shared by terrain and offline geometry.
// Shadow projection, diffuse and specular use the same world-space direction.
const vec3 END_DISC_IRRADIANCE=vec3(0.56,0.78,1.10);
const vec3 END_DISC_AMBIENT=vec3(0.10,0.12,0.17);
// End-stone emission is identity-gated in lib/surface_emission.glsl.
vec3 end_surface_direct(vec3 normal,float visibility,float eclipse) {
    return END_DISC_IRRADIANCE*max(dot(normal,end_light_direction()),0.0)
           *visibility*(1.0-0.65*eclipse);
}
vec3 end_surface_diffuse(vec3 albedo,vec3 normal,float visibility,float eclipse) {
    float hemisphere=0.65+0.35*max(normal.y,0.0);
    vec3 direct=end_surface_direct(normal,visibility,eclipse);
    return albedo*(END_DISC_AMBIENT*hemisphere+direct);
}
// Tangent displacement on ordinary cube faces. A narrow footprint fade stops
// subpixel block edges from producing a distant grid. This is a shading bevel,
// not a topology-aware exposed-edge detector.
vec3 end_surface_bevel(vec3 normal,vec3 worldPos,float footprint) {
    vec3 cell=fract(worldPos);
    vec3 ridge=smoothstep(vec3(0.96),vec3(1.0),cell)
              -(1.0-smoothstep(vec3(0.0),vec3(0.04),cell));
    vec3 tangent=1.0-normal*normal;
    float near=1.0-smoothstep(0.015,0.04,footprint);
    vec3 tilt=ridge*tangent*0.12*near;
    tilt-=normal*dot(tilt,normal);
    return normalize(normal+tilt);
}
vec3 end_surface_specular(vec3 normal,vec3 view,float roughness,
                          float visibility,float eclipse) {
    vec3 light=end_light_direction();
    float nl=max(dot(normal,light),0.0), nv=max(dot(normal,view),0.0);
    if(nl<=0.0 || nv<=0.0 || visibility<=0.0) return vec3(0.0);
    vec3 halfVector=normalize(light+view+vec3(1e-6));
    float nh=max(dot(normal,halfVector),0.0), vh=max(dot(view,halfVector),0.0);
    // GGX with a roughness floor representing the extended bright inner disc.
    float alpha=max(roughness*roughness,0.085), a2=alpha*alpha;
    float denominator=nh*nh*(a2-1.0)+1.0;
    float distribution=a2/(3.14159265*denominator*denominator);
    float k=(roughness+1.0)*(roughness+1.0)*0.125;
    float masking=1.0/((nv*(1.0-k)+k)*(nl*(1.0-k)+k));
    float grazing=1.0-vh;
    float fresnel=0.04+0.96*grazing*grazing*grazing*grazing*grazing;
    return END_DISC_IRRADIANCE*(distribution*masking*fresnel*nl*0.25)
           *visibility*(1.0-0.65*eclipse);
}
#endif
