#ifndef ASTRA_END_GEOMETRY_GLSL
#define ASTRA_END_GEOMETRY_GLSL
#include "/lib/pow.glsl"
#include "/lib/end_light.glsl"
#include "/global/dimension/end_disc_profile.glsl"
// Original Astra geometry. All lengths are virtual sky units, never world blocks.
// The observer is always (0,0,0), including on the outer islands and in reflections.
// Retained research: bodies 0..65 and end_solid_hit/end_solid_hit_subset belong
// to the retired ring catalogue. Active sky/occlusion callers use IDs 66..72.
// END_LENS_RADIUS, END_HORIZON, end_noise3 and end_window are also retained
// research symbols, with no active callers. They do not schedule GPU work.
const float END_PI = 3.14159265359;
const float END_TAU = 6.28318530718;
const float END_FAR = 10000.0;
const float END_RING_HEIGHT = 0.90;
const float END_RING_INNER = 2.0;
const float END_RING_SPAN = 5.6;
// Both shepherds are in front of the source; the outer dust still extends behind it.
const float END_SOURCE_DISTANCE = 6.8;
const float END_SOURCE_SCALE = END_SOURCE_DISTANCE/4.4*1.12;
const float END_LENS_RADIUS = END_SOURCE_DISTANCE*0.5*1.12;
const float END_HORIZON = 0.1847*END_SOURCE_SCALE;
const int END_BODY_COUNT = 73;
uniform int worldDay;
uniform int worldTime;

// colortex8 layout (RGBA32F, width 316 in shaders.properties). program/end_illumination.fsh
// writes every texel each frame, so the pre-existing 0..293 addresses are unchanged:
//   0        End eclipse quadrature (eclipse, blocked, 1-blocked, 1)
//   1..73    body records (id + 1): vec4(true centre, model scale)
//   74       ring axis
//   75..293  cached body bases keyed by id (3 texels each); ids 0..65 are
//            zero-filled, 66..72 carry the active basis
//   294..314 cached ID-only island shape params for ids 66..72 (3 texels each:
//            towerHeight, towerZ, vec4(shardZ, filler))
//   315      star-field rotation vec4(cos(a), sin(a), 0, 1)
#define ASTRA_END_BODY_FIRST_ID 66
#define ASTRA_END_SHAPE_SLOT_BASE 294
#define ASTRA_END_STAR_ROTATION_SLOT 315

// Reduce days before adding ticks: old saves must not lose the small orbital steps.
float end_cycle_seconds(float period) {
    float days = mod(float(worldDay / 1024) * mod(1228800.0,period),period);
    return mod(days + mod(float(worldDay % 1024)*1200.0,period)
                    + float(worldTime)*0.05,period);
}
// One star-field rotation for the whole frame. Still the worldDay/worldTime-only
// formula; never frameTimeCounter or a host clock. The cache producer bakes the
// cos/sin pair of this angle into colortex8 slot 315.
float end_star_rotation() {
    return radians(end_cycle_seconds(1296000.0)/3600.0);
}
float end_orbit_phase(float period,float phase) {
    return END_TAU*end_cycle_seconds(period)/period+phase;
}
float end_hash(float p) { return fract(sin(p*127.1+311.7)*43758.5453); }
vec2 end_hash2(vec2 p) {
    return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453);
}
float end_noise3(vec3 p) {
    vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    float n=dot(i,vec3(1,57,113));
    return mix(mix(mix(end_hash(n),end_hash(n+1.0),f.x),mix(end_hash(n+57.0),end_hash(n+58.0),f.x),f.y),
               mix(mix(end_hash(n+113.0),end_hash(n+114.0),f.x),mix(end_hash(n+170.0),end_hash(n+171.0),f.x),f.y),f.z);
}
mat3 end_basis(vec3 n) {
    vec3 x=normalize(cross(abs(n.y)<0.98 ? vec3(0,1,0) : vec3(0,0,1),n));
    return mat3(x,cross(n,x),n);
}
// Shared sky frame and physical disc plane for rendering and illumination.
mat3 end_view_basis() {
    mat3 b=end_basis(end_light_direction());
    vec3 x=b[0]*0.951057-b[1]*0.309017;
    return mat3(x,cross(b[2],x),b[2]);
}
mat3 end_disc_basis() {
    mat3 b=end_view_basis();
    float inclination=END_DISC_INCLINATION;
    vec3 n=b[1]*sqrt(1.0-inclination*inclination)+b[2]*inclination;
    return mat3(b[0],normalize(cross(n,b[0])),n);
}
vec3 end_rotate_y(vec3 p,float a) {
    return vec3(cos(a)*p.x+sin(a)*p.z,p.y,-sin(a)*p.x+cos(a)*p.z);
}
// Same rotation with a precomputed (cos a, sin a) pair: identical arithmetic, used
// where the angle is already known so cos/sin are not re-evaluated per vector.
vec3 end_rotate_y(vec3 p,vec2 cosSin) {
    return vec3(cosSin.x*p.x+cosSin.y*p.z,p.y,-cosSin.y*p.x+cosSin.x*p.z);
}
mat3 end_body_basis(vec3 center,int id) {
    #ifdef ASTRA_END_BODY_CACHE
    int slot=75+id*3;
    return mat3(texelFetch(colortex8,ivec2(slot,0),0).xyz,
                texelFetch(colortex8,ivec2(slot+1,0),0).xyz,
                texelFetch(colortex8,ivec2(slot+2,0),0).xyz);
    #else
    if(id<66) return end_basis(normalize(center));
    vec3 up=vec3(0,1,0);
    vec3 x=normalize(cross(up,center));
    return mat3(x,up,cross(x,up));
    #endif
}
// Even at closest precession alignment, the ring plane stays outside the horizon.
vec3 end_source_position() { return end_light_direction()*END_SOURCE_DISTANCE; }
vec3 end_ring_axis() {
    #ifdef ASTRA_END_BODY_CACHE
    return texelFetch(colortex8,ivec2(74,0),0).xyz;
    #else
    float a=end_orbit_phase(float(END_PRECESSION_MINUTES)*60.0,END_PI-END_TAU*(17.5/36.0));
    return vec3(sin(radians(28.0))*cos(a),cos(radians(28.0)),sin(radians(28.0))*sin(a));
    #endif
}
float end_window(float x,float a,float b,float aa) {
    return smoothstep(a-aa,a+aa,x)*(1.0-smoothstep(b-aa,b+aa,x));
}
float end_shepherd_radius(int i) { return i==0 ? 0.46 : 0.80; }
float end_shepherd_phase(int i) {
    return end_orbit_phase(i==0 ? 2160.0 : 2959.2,float(i)*2.1);
}
vec3 end_orbit_position(mat3 basis,float u,float phase) {
    return (basis[0]*cos(phase)+basis[1]*sin(phase))*(END_RING_INNER+END_RING_SPAN*u)
           -basis[2]*END_RING_HEIGHT;
}
// xyz = true centre, w = model scale. Each object's bounding sphere is 1.65*w.
vec4 end_body(int id) {
    #ifdef ASTRA_END_BODY_CACHE
    return texelFetch(colortex8, ivec2(id + 1, 0), 0);
    #else
    float f=float(id);
    mat3 b=end_basis(end_ring_axis());
    vec3 center; float diameter;
    if(id<64) {
        float s=end_hash(f+7.0);
        float u=s<0.55 ? mix(0.18,0.42,s/0.55) : mix(0.50,0.78,(s-0.55)/0.45);
        if(id>57) u=mix(0.84,0.99,end_hash(f+23.0));
        float phase=end_orbit_phase(3600.0/mix(1.0,0.62,u),f*2.39996323);
        center=end_orbit_position(b,u,phase);
        diameter=id<4 ? mix(2.0,4.0,end_hash(f+19.0)) : mix(0.08,0.75,cube(end_hash(f+11.0)));
    } else if(id<66) {
        int moon=id-64;
        center=end_orbit_position(b,end_shepherd_radius(moon),end_shepherd_phase(moon));
        diameter=moon==0 ? 2.2 : 1.8;
    } else {
        f=float(id-66);
        vec3 n=normalize(vec3(sin(radians(28.0)),cos(radians(28.0)),0.0)
                         +vec3(0.22*sin(f*2.1),0.02,0.25*cos(f*1.7)));
        b=end_basis(n);
        float phase=f*2.39996323+end_orbit_phase(1440.0+f*263.0,0.0)*(id<68 ? -1.0 : 1.0);
        float radius=mix(0.90,1.55,end_hash(f+173.0));
        center=(b[0]*cos(phase)+b[1]*sin(phase))*radius-n*0.07;
        diameter=id==66 ? 4.2 : mix(1.5,3.5,end_hash(f+211.0));
    }
    return vec4(center,length(center)*tan(radians(diameter*0.5)));
    #endif
}
float end_box(vec3 p,vec3 size) {
    vec3 d=abs(p)-size;
    return length(max(d,vec3(0)))+min(max(d.x,max(d.y,d.z)),0.0);
}
// Conservative signed distances to original, genuinely three-dimensional solids.
struct EndBodyShapeParams {
    vec4 towerHeight;
    vec4 towerZ;
    vec3 shardZ;
};
EndBodyShapeParams end_body_shape_params(int id) {
    EndBodyShapeParams params;
    params.towerHeight=vec4(0.0); params.towerZ=vec4(0.0); params.shardZ=vec3(0.0);
    #ifdef ASTRA_END_BODY_CACHE
    // Only ids 66..72 are active islands. Their shape data depends on the ID alone,
    // so the cache producer bakes it once per frame next to the cached bases.
    if(id>=ASTRA_END_BODY_FIRST_ID && id<END_BODY_COUNT) {
        int slot=ASTRA_END_SHAPE_SLOT_BASE+(id-ASTRA_END_BODY_FIRST_ID)*3;
        params.towerHeight=texelFetch(colortex8,ivec2(slot,0),0);
        params.towerZ=texelFetch(colortex8,ivec2(slot+1,0),0);
        params.shardZ=texelFetch(colortex8,ivec2(slot+2,0),0).xyz;
        return params;
    }
    #endif
    if(id>=ASTRA_END_BODY_FIRST_ID) {
        float seed=float(id)+31.0;
        for(int j=0;j<4;j++) {
            float f=float(j);
            params.towerHeight[j]=0.32+0.35*end_hash(seed+f*17.0);
            params.towerZ[j]=0.13*sin(seed+f*2.0);
        }
        for(int j=0;j<3;j++) params.shardZ[j]=0.12*sin(seed+float(j));
    }
    return params;
}
// Island dimensions depend only on the body ID, not on the current march point.
float end_body_shape(vec3 p,int id,EndBodyShapeParams params) {
    float seed=float(id)+31.0;
    if(id>=66) {
        float radial=max(abs(p.x),abs(p.z)*1.35);
        float top=0.12+0.035*sin(p.x*9.0+seed)*cos(p.z*7.0);
        float shape=max((radial-1.0)*0.7,max((radial*0.80-p.y-0.95)*0.6,p.y-top));
        for(int j=0;j<4;j++) {
            float f=float(j), x=-0.67+f*0.44;
            float h=params.towerHeight[j];
            vec3 q=p-vec3(x,h*0.5+0.10,params.towerZ[j]);
            float width=0.065+0.045*clamp(h-p.y,0.0,1.0);
            shape=min(shape,end_box(q,vec3(width,h*0.5,0.075)));
        }
        for(int j=0;j<3;j++) {
            float x=-0.56+float(j)*0.49;
            float bottom=-0.95+abs(x)*0.80;
            vec3 q=p-vec3(x,bottom-0.06,params.shardZ[j]);
            shape=min(shape,end_box(q,vec3(0.065,0.22,0.11)));
            shape=max(shape,-end_box(p-vec3(x+0.14,bottom-0.06,0),vec3(0.04,0.17,0.80)));
        }
        return shape*0.7;
    }
    // Convex plane intersection produces broad flat faces and sharp silhouette edges.
    float shape=-2.0;
    for(int j=0;j<10;j++) {
        float f=float(j), z=1.0-2.0*(f+0.5)/10.0;
        float a=f*2.39996323+seed;
        vec3 normal=vec3(sqrt(1.0-z*z)*cos(a),z,sqrt(1.0-z*z)*sin(a));
        shape=max(shape,dot(p,normal)-(0.72+0.10*end_hash(seed+f)));
    }
    if(id>=64) {
        // Boolean spherical cuts give real crater walls, rims and self-occlusion.
        for(int j=0;j<3;j++) {
            float f=float(j);
            vec3 c=vec3(-0.36+f*0.39,0.25-f*0.20,-0.78);
            shape=max(shape,-(length(p-c)-(0.30-f*0.045)));
        }
    }
    return shape*0.8;
}
float end_body_shape(vec3 p,int id) {
    return end_body_shape(p,id,end_body_shape_params(id));
}
// Keep the march independent of shading: occlusion queries need only a hit,
// and closest-body searches can defer the six shape samples for the normal.
bool end_body_hit(vec3 origin,vec3 ray,float limit,vec4 body,int id,float cone,
                  out float hit,out vec3 localHit,out float epsilon) {
    vec3 offset=origin-body.xyz;
    hit=END_FAR; localHit=vec3(0.0); epsilon=0.0;
    // Reuse the same offset and discriminant root for the entry and exit.
    float along=dot(offset,ray), radius=body.w*1.65;
    float offsetSquared=dot(offset,offset);
    float discriminant=along*along-offsetSquared+radius*radius;
    if(discriminant<0.0) return false;
    float root=sqrt(discriminant);
    float start=max(0.0,-along-root);
    float finish=min(limit,-along+root);
    if(start>=finish) return false;
    mat3 basis=end_body_basis(body.xyz,id);
    mat3 inverseBasis=transpose(basis);
    // `offset` already holds origin-body.xyz; the previous expression rebuilt it.
    vec3 p=inverseBasis*offset/body.w;
    vec3 direction=inverseBasis*ray;
    float t=start/body.w, endT=finish/body.w;
    epsilon=clamp(cone*max(start,0.1)/body.w*0.35,0.0003,0.015);
    float closest=END_FAR, closestT=t;
    bool reached=false;
    EndBodyShapeParams params=end_body_shape_params(id);
    for(int j=0;j<96;j++) {
        vec3 q=p+direction*t;
        float d=end_body_shape(q,id,params);
        if(d<closest) { closest=d; closestT=t; }
        if(d<epsilon) { reached=true; break; }
        t+=max(d,epsilon*0.25);
        if(t>endT) break;
    }
    if(!reached) return false;
    hit=closestT*body.w;
    localHit=p+direction*closestT;
    return hit<limit;
}
vec3 end_body_normal(vec3 q,float epsilon,vec4 body,int id) {
    vec2 e=vec2(max(epsilon*0.5,0.0002),0.0);
    EndBodyShapeParams params=end_body_shape_params(id);
    vec3 gradient=vec3(end_body_shape(q+e.xyy,id,params)-end_body_shape(q-e.xyy,id,params),
                       end_body_shape(q+e.yxy,id,params)-end_body_shape(q-e.yxy,id,params),
                       end_body_shape(q+e.yyx,id,params)-end_body_shape(q-e.yyx,id,params));
    return end_body_basis(body.xyz,id)*normalize(gradient+vec3(1e-9));
}
bool end_body_intersect(vec3 origin,vec3 ray,float limit,vec4 body,int id,float cone,
                        out float hit,out vec3 normal,out float coverage) {
    vec3 localHit; float epsilon;
    normal=vec3(0,1,0); coverage=0.0;
    if(!end_body_hit(origin,ray,limit,body,id,cone,hit,localHit,epsilon)) return false;
    normal=end_body_normal(localHit,epsilon,body,id);
    // Once a solid is reached it is opaque; marching tolerance is not opacity.
    coverage=1.0;
    return hit<limit;
}
// Nearest distance wins, independent of loop order or object category.
bool end_solid_hit(vec3 origin,vec3 ray,float limit,vec4 bodies[END_BODY_COUNT],float cone,
                   out float distanceHit,out vec3 normal,out float coverage,out int objectId) {
    distanceHit=limit; normal=vec3(0,1,0); coverage=0.0; objectId=-1;
    for(int i=0;i<END_BODY_COUNT;i++) {
        float t,c; vec3 n;
        if(end_body_intersect(origin,ray,distanceHit,bodies[i],i,cone,t,n,c)) {
            distanceHit=t; normal=n; coverage=c; objectId=i;
        }
    }
    return objectId>=0;
}
float end_body_shadow(vec3 position,vec3 light,vec4 body,int id) {
    mat3 basis=end_body_basis(body.xyz,id);
    vec3 p=transpose(basis)*(position-body.xyz)/body.w;
    vec3 direction=transpose(basis)*light;
    float t=0.025, visibility=1.0;
    EndBodyShapeParams params=end_body_shape_params(id);
    for(int i=0;i<24;i++) {
        float d=end_body_shape(p+direction*t,id,params);
        if(d<0.001) return 0.0;
        visibility=min(visibility,12.0*d/t);
        t+=max(d,0.01);
        if(t>3.5) break;
    }
    return clamp(visibility,0.0,1.0);
}
bool end_solid_hit_subset(vec3 origin,vec3 ray,float limit,vec4 bodies[END_BODY_COUNT],
                          int bodyIndices[END_BODY_COUNT],int count,float cone,
                          out float distanceHit,out vec3 normal,out float coverage,out int objectId) {
    distanceHit=limit; normal=vec3(0,1,0); coverage=0.0; objectId=-1;
    for(int j=0;j<END_BODY_COUNT;j++) {
        if(j>=count) break;
        int i=bodyIndices[j]; float t,c; vec3 n;
        if(end_body_intersect(origin,ray,distanceHit,bodies[i],i,cone,t,n,c)) {
            distanceHit=t; normal=n; coverage=c; objectId=i;
        }
    }
    return objectId>=0;
}
#endif
