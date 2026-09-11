#ifndef ASTRA_END_RING_GLSL
#define ASTRA_END_RING_GLSL
#include "/global/dimension/end_geometry.glsl"
float end_ring_density(float u,float aa) {
    float d=0.045*end_window(u,0.0,0.18,aa);
    d+=0.82*end_window(u,0.18,0.42,aa);
    d+=0.03*end_window(u,0.42,0.50,aa);
    d+=0.58*end_window(u,0.50,0.78,aa);
    d+=0.05*end_window(u,0.78,0.82,aa);
    d+=0.06*end_window(u,0.82,1.0,aa);
    for(int j=0;j<4;j++) d*=1.0-0.92*end_window(u,0.545+float(j)*0.052,0.551+float(j)*0.052,aa);
    return d*(1.0-smoothstep(0.85,1.0,u));
}
// Geometric plane crossing, from any point on a curved or straight ray.
bool end_ring_hit(vec3 origin,vec3 ray,float limit,out float t,out vec3 position) {
    vec3 n=end_ring_axis(); float denominator=dot(ray,n);
    t=END_FAR; position=vec3(0);
    if(abs(denominator)<1e-7) return false;
    t=-(dot(origin,n)+END_RING_HEIGHT)/denominator;
    if(t<=0.00001 || t>=limit) return false;
    position=origin+ray*t;
    float radius=length(position+n*END_RING_HEIGHT);
    return radius>=END_RING_INNER && radius<=END_RING_INNER+END_RING_SPAN;
}
float end_ring_material(vec3 position,float footprint,out float line) {
    vec3 n=end_ring_axis(); mat3 b=end_basis(n);
    vec3 radial=position+n*END_RING_HEIGHT;
    float radius=length(radial), u=(radius-END_RING_INNER)/END_RING_SPAN;
    float aa=max(footprint/END_RING_SPAN,0.00008);
    float az=atan(dot(radial,b[1]),dot(radial,b[0]));
    float flow=az-end_orbit_phase(3600.0/mix(1.0,0.62,clamp(u,0.0,1.0)),0.0);
    vec3 material=vec3(cos(flow),sin(flow),u*3.0);
    float resolved=1.0-smoothstep(0.003,0.018,footprint/max(radius,0.1));
    float grit=mix(0.5,end_noise3(material*90.0),resolved);
    float density=end_ring_density(u,aa)*mix(0.76,1.0,grit);
    density*=mix(0.78,1.0,end_noise3(material*17.0));
    float clearing=1.0;
    for(int i=0;i<2;i++) {
        vec3 moon=end_orbit_position(b,end_shepherd_radius(i),end_shepherd_phase(i));
        float diameter=i==0 ? 2.2 : 1.8;
        float moonRadius=length(moon)*tan(radians(diameter*0.5));
        float halo=length(moon)*tan(radians(0.6));
        float localClear=smoothstep(moonRadius,moonRadius+halo,length(position-moon));
        float behind=mod(end_shepherd_phase(i)-az+END_TAU,END_TAU);
        float radialClear=1.0-smoothstep(0.018,0.055,abs(u-end_shepherd_radius(i)));
        float wake=radialClear*(1.0-smoothstep(0.0,radians(12.0),behind));
        clearing*=min(localClear,1.0-0.85*wake);
    }
    density*=mix(0.03,1.0,clearing);
    line=end_window(u,0.458,0.460,aa)+end_window(u,0.798,0.800,aa);
    line*=smoothstep(0.2,0.6,sin(flow*9.0+u*15.0))*clearing;
    return density;
}
vec3 end_ring_transmission(vec3 position,vec3 ray,float footprint) {
    float line;
    return exp(-end_ring_material(position,footprint,line)*vec3(2.5,3.4,4.5));
}
float end_ring_self_shadow(vec3 position,vec3 light) {
    vec3 n=end_ring_axis();
    float thickness=0.012*length(position+n*END_RING_HEIGHT);
    float reach=min(2.0,thickness/max(abs(dot(n,light)),0.015));
    float tau=0.0;
    for(int i=0;i<6;i++) {
        vec3 p=position+light*((float(i)+0.5)*reach/6.0);
        float height=abs(dot(p,n)+END_RING_HEIGHT);
        float radius=length(p-n*dot(p,n));
        tau+=end_ring_density((radius-END_RING_INNER)/END_RING_SPAN,0.001)
             *(1.0-smoothstep(thickness*0.5,thickness,height))*reach/6.0;
    }
    return exp(-tau*5.0);
}
vec3 end_ring_radiance(vec3 position,float footprint) {
    vec3 light=normalize(end_source_position()-position);
    vec3 radial=normalize(position+end_ring_axis()*END_RING_HEIGHT);
    float line;
    float density=end_ring_material(position,footprint,line);
    float warm=smoothstep(cos(radians(25.0)),1.0,dot(normalize(position),end_light_direction()));
    vec3 tint=mix(vec3(0.62,0.66,0.78),vec3(0.95,0.80,0.62),warm);
    float facing=0.20+0.80*max(dot(radial,end_light_direction()),0.0);
    float lighting=(0.012+0.15*facing)*end_ring_self_shadow(position,light);
    return tint*lighting*density+vec3(0.006,0.009,0.014)*line;
}
mat3 end_disc_basis() {
    mat3 b=end_basis(end_light_direction());
    vec3 n=normalize(b[1]*0.953939+end_light_direction()*0.30);
    return mat3(b[0],normalize(cross(n,b[0])),n);
}
#endif
