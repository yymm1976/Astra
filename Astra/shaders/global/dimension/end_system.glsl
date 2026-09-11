#ifndef ASTRA_END_SYSTEM_GLSL
#define ASTRA_END_SYSTEM_GLSL
#include "/global/dimension/end_ring.glsl"
uniform sampler2D colortex8;
float end_eclipse() {
    vec4 illumination=texelFetch(colortex8,ivec2(0),0);
    return illumination.a>0.5 ? illumination.r : 0.0;
}
vec3 end_starfield(vec3 direction,vec3 lightDir,float cone) {
    vec3 dir=end_rotate_y(direction,radians(end_cycle_seconds(1296000.0)/3600.0));
    vec3 a=abs(dir); float dominant=max(a.x,max(a.y,a.z));
    vec3 stars=vec3(0);
    for(int axis=0;axis<3;axis++) {
        float component=axis==0 ? a.x : axis==1 ? a.y : a.z;
        if(component<max(dominant*(1.0-clamp(cone*3.0,0.02,0.25)),0.0001)) continue;
        vec2 uv=axis==0 ? dir.yz/component : axis==1 ? dir.xz/component : dir.xy/component;
        float signAxis=axis==0 ? dir.x : axis==1 ? dir.y : dir.z;
        float face=float(axis*2)+(signAxis>0.0 ? 0.0 : 1.0);
        vec2 p=(uv*0.5+0.5)*256.0, cell=floor(p);
        float footprint=max(cone*128.0/component,0.01);
        for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
            vec2 c=cell+vec2(x,y);
            if(any(lessThan(c,vec2(0))) || any(greaterThanEqual(c,vec2(256)))) continue;
            vec2 h=end_hash2(c+face*401.0);
            if(h.x>0.87) continue;
            vec2 center=c+0.15+0.7*end_hash2(c+face*419.0+37.0);
            float radius=0.07+0.065*pow(h.y,10.0), width=max(radius,footprint*0.55);
            float flux=0.002+0.055*pow(h.y,14.0);
            float profile=exp(-dot(p-center,p-center)/(width*width))*radius*radius/(width*width);
            float temperature=mix(6500.0,12000.0,h.x/0.87);
            if(h.x<0.87/7.0) temperature=mix(3000.0,6000.0,h.y);
            vec3 tint=bh_Blackbody(temperature);
            tint/=max(max(tint.r,tint.g),tint.b);
            float warm=smoothstep(cos(radians(25.0)),cos(radians(20.0)),dot(direction,lightDir));
            tint=mix(min(tint,vec3(tint.b))+vec3(0.03,0.045,0.06),tint,warm);
            stars+=tint*flux*profile;
        }
    }
    return stars;
}
vec3 end_background(vec3 direction,float cone) {
    vec3 sky=vec3(0.000015,0.000025,0.00006)+end_starfield(direction,end_light_direction(),cone);
    #ifdef END_NEBULA
        sky+=vec3(0.0001,0.0002,0.00045)*smoothstep(0.79,0.97,end_noise3(direction*11.0));
    #endif
    return sky;
}
vec3 end_surface_radiance(vec3 position,vec3 normal,vec3 ray,vec4 body,int id,
                          vec4 bodies[END_BODY_COUNT]) {
    vec3 light=normalize(end_source_position()-position);
    float lambert=max(dot(normal,light),0.0);
    float visibility=end_body_shadow(position+normal*body.w*0.012,light,body,id);
    for(int i=0;i<END_BODY_COUNT;i++) {
        if(i==id) continue;
        float hit,cover; vec3 n;
        if(end_body_intersect(position+normal*body.w*0.02,light,
                              length(end_source_position()-position),bodies[i],i,0.0,hit,n,cover)) visibility=0.0;
    }
    float ringT; vec3 ringP;
    if(end_ring_hit(position+normal*body.w*0.02,light,length(end_source_position()-position),ringT,ringP))
        visibility*=dot(end_ring_transmission(ringP,light,0.003),vec3(0.2126,0.7152,0.0722));
    float opposition=pow(max(dot(-ray,light),0.0),32.0);
    float rim=pow(1.0-max(dot(normal,-ray),0.0),20.0)*max(dot(normal,light),0.0);
    vec3 p=transpose(end_body_basis(body.xyz,id))*(position-body.xyz)/body.w;
    float strata=id>=66 ? 0.84+0.16*smoothstep(0.40,0.60,fract(p.y*13.0)) : 1.0;
    float warm=smoothstep(cos(radians(25.0)),cos(radians(20.0)),dot(normalize(position),end_light_direction()));
    vec3 stone=mix(vec3(0.59,0.65,0.76),vec3(0.85,0.84,0.56),warm);
    vec3 lit=vec3(0.0008,0.0008,0.0015)+stone*strata*(0.11*lambert+0.022*opposition+0.09*rim)*visibility;
    if(id>=66) {
        float angular=body.w/length(body.xyz);
        float overlap=dot(normalize(body.xyz),end_light_direction());
        lit*=1.0-smoothstep(cos(angular*1.4),cos(angular*0.8),overlap);
    }
    return lit;
}
// Nearest solid and any dust before it, in depth order along this ray segment.
bool end_scene_segment(vec3 origin,vec3 ray,float limit,float cone,vec4 bodies[END_BODY_COUNT],
                       int bodyIndices[END_BODY_COUNT],int count,
                       inout vec3 radiance,inout vec3 transmission) {
    float solidT,coverage; vec3 normal; int id;
    bool solid=end_solid_hit_subset(origin,ray,limit,bodies,bodyIndices,count,cone,solidT,normal,coverage,id);
    float ringT; vec3 ringP;
    if(end_ring_hit(origin,ray,solidT,ringT,ringP)) {
        float footprint=cone*length(ringP)/max(abs(dot(ray,end_ring_axis())),0.02);
        radiance+=transmission*end_ring_radiance(ringP,footprint);
        transmission*=end_ring_transmission(ringP,ray,footprint);
    }
    if(solid) {
        vec3 p=origin+ray*solidT;
        radiance+=transmission*end_surface_radiance(p,normal,ray,bodies[id],id,bodies);
        transmission=vec3(0);
    }
    return solid;
}
#endif
