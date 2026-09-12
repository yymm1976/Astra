// Per-frame scene data: irradiance, 73 bodies, ring axis and 73 orientation bases.
#include "/lib/settings.glsl"
#include "/global/dimension/end_ring.glsl"
// Iris reads the format identifier; GLSL still needs its declaration.
// The guard also supports hosts that supply the name as a macro.
#ifndef RGBA32F
const int RGBA32F = 0;
#endif
// Signed world-space centres and their radii require floating-point storage.
const int colortex8Format = RGBA32F;
const vec4 colortex8ClearColor = vec4(0.0,0.0,1.0,1.0);
/* RENDERTARGETS: 8 */
void main() {
    int slot = int(gl_FragCoord.x);
    if (slot == 74) {
        gl_FragData[0] = vec4(end_ring_axis(),1.0);
        return;
    }
    if (slot >= 75) {
        int id=(slot-75)/3;
        mat3 basis=end_body_basis(end_body(id).xyz,id);
        gl_FragData[0]=vec4(basis[(slot-75)%3],1.0);
        return;
    }
    if (slot > 0) {
        gl_FragData[0] = end_body(slot - 1);
        return;
    }
    vec4 bodies[END_BODY_COUNT];
    for(int i=0;i<END_BODY_COUNT;i++) bodies[i]=end_body(i);
    mat3 disc=end_disc_basis();
    vec3 source=end_source_position();
    float visible=0.0, total=0.0;
    // Fixed quadrature over the emitting annulus; no temporal randomness or timers.
    for(int i=0;i<256;i++) {
        float f=float(i);
        float a=f*2.39996323;
        float radius=sqrt(mix(0.56*0.56,1.18*1.18,(f+0.5)/256.0));
        vec3 offset=(disc[0]*cos(a)+disc[1]*sin(a))*radius*END_SOURCE_SCALE;
        vec3 target=source+offset;
        float limit=length(target); vec3 ray=target/limit;
        float hit,cover; vec3 normal; int id;
        float transmission=1.0;
        if(end_solid_hit(vec3(0),ray,limit,bodies,0.0001,hit,normal,cover,id)) transmission=0.0;
        float ringT = 0.0; vec3 ringP = vec3(0.0);
        if(transmission>0.0 && end_ring_hit(vec3(0),ray,limit,ringT,ringP))
            transmission=dot(end_ring_transmission(ringP,ray,0.015),vec3(0.2126,0.7152,0.0722));
        float u=(radius-0.56)/0.62;
        float edge=smoothstep(0.0,0.08,u)*(1.0-smoothstep(0.90,1.0,u));
        float doppler=1.0+0.5*dot(normalize(cross(disc[2],offset)),-ray);
        float weight=edge*doppler/(limit*limit);
        visible+=transmission*weight;
        total+=weight;
    }
    float blocked=clamp(1.0-visible/max(total,0.00001),0.0,1.0);
    // Preserve the requested restrained 18% maximum scene response. Small grazing
    // occultations remain small; only broad coverage reaches the full response.
    float eclipse=smoothstep(0.0,0.28,blocked);
    gl_FragData[0]=vec4(eclipse,blocked,1.0-blocked,1.0);
}
