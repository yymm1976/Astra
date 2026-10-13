// Compact live content in the existing cache layout: seven island silhouettes.
// Retain slot addresses for consumers; retired orbital bodies are zero-filled.
// Slots 294..314 cache the ID-only island shape params and 315 the frame's star
// rotation. This pass has no body-cache sampler, so it always computes the params
// analytically and writes them; see the layout note in global/dimension/end_geometry.glsl.
#include "/lib/settings.glsl"
#include "/global/dimension/end_geometry.glsl"
#include "/global/dimension/end_disc_profile.glsl"
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
    // ID-only island shape data and the frame's star rotation. Handle these before
    // the slot>=75 basis branch below: that branch indexes id=(slot-75)/3 and would
    // otherwise read these slots as out-of-range body ids.
    if (slot >= ASTRA_END_SHAPE_SLOT_BASE && slot < ASTRA_END_STAR_ROTATION_SLOT) {
        int index=slot-ASTRA_END_SHAPE_SLOT_BASE;
        int part=index%3;
        EndBodyShapeParams params=end_body_shape_params(ASTRA_END_BODY_FIRST_ID+index/3);
        if(part==0) gl_FragData[0]=params.towerHeight;
        else if(part==1) gl_FragData[0]=params.towerZ;
        else gl_FragData[0]=vec4(params.shardZ,0.0);
        return;
    }
    if (slot == ASTRA_END_STAR_ROTATION_SLOT) {
        float a=end_star_rotation();
        gl_FragData[0]=vec4(cos(a),sin(a),0.0,1.0);
        return;
    }
    if (slot >= 75) {
        int id=(slot-75)/3;
        if(id<66) { gl_FragData[0]=vec4(0.0); return; }
        mat3 basis=end_body_basis(end_body(id).xyz,id);
        gl_FragData[0]=vec4(basis[(slot-75)%3],1.0);
        return;
    }
    if (slot > 0) {
        gl_FragData[0] = slot<=66 ? vec4(0.0) : end_body(slot - 1);
        return;
    }
    // Source quadrature follows the enlarged tilted disc. No separate dust-ring
    // extinction: only the surviving foreground islands can occult the emitter.
    mat3 disc=end_disc_basis();
    vec3 source=end_source_position();
    float visible=0.0, total=0.0;
    vec4 islands[7];
    for(int j=0;j<7;j++) islands[j]=end_body(j+66);
    for(int i=0;i<32;i++) {
        float f=float(i);
        float a=f*2.39996323;
        float radius=sqrt(mix(0.95*0.95,5.20*5.20,(f+0.5)/32.0));
        vec3 offset=(disc[0]*cos(a)+disc[1]*sin(a))*radius*END_SOURCE_DISTANCE*END_SHADOW_TAN;
        vec3 target=source+offset;
        float limit=length(target); vec3 ray=target/limit;
        float transmission=1.0;
        for(int j=66;j<END_BODY_COUNT;j++) {
            float hit,epsilon; vec3 localHit;
            if(end_body_hit(vec3(0.0),ray,limit,islands[j-66],j,0.0001,hit,localHit,epsilon)) {
                transmission=0.0; break;
            }
        }
        float weight=end_disc_flux(radius);
        visible+=transmission*weight;
        total+=weight;
    }
    float blocked=clamp(1.0-visible/max(total,0.00001),0.0,1.0);
    float eclipse=smoothstep(0.0,0.28,blocked);
    gl_FragData[0]=vec4(eclipse,blocked,1.0-blocked,1.0);
}
