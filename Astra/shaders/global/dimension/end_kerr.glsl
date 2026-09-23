#ifndef ASTRA_END_KERR_GLSL
#define ASTRA_END_KERR_GLSL
// Static curved-path transfer with restrained Kerr-like image deformation.
// The atlas is produced by qa/tools/build_end_transfer.py, never traced per frame.
const float END_KERR_SPIN = 0.94;
uniform sampler2D astraEndTransfer;
uniform sampler2D astraEndFlow;
uniform sampler2D astraEndTransferMeta;
#include "/global/dimension/end_disc_profile.glsl"
mat3 end_kerr_basis() {
    return end_view_basis();
}
vec2 end_kerr_screen(vec3 ray) {
    mat3 b=end_kerr_basis();
    return vec2(dot(ray,b[0]),dot(ray,b[1]))
           /max(dot(ray,b[2])*END_SHADOW_TAN,0.00001);
}
vec2 end_kerr_impact(vec2 q) {
    vec2 p=q-vec2(-0.055*END_KERR_SPIN,0.0);
    p.x*=1.0+0.025*END_KERR_SPIN*smoothstep(-0.3,0.8,p.x);
    return p;
}
float end_kerr_radius(vec2 q) { return length(end_kerr_impact(q)); }
vec2 end_decode_transfer(vec4 encoded) {
    return (vec2(dot(encoded.rg,vec2(65280.0,255.0)),
                 dot(encoded.ba,vec2(65280.0,255.0)))/65535.0-0.5)*64.0;
}
vec3 end_disc_transfer(vec2 q,float order,float imageFootprint,out float sourceFootprint) {
    sourceFootprint=imageFootprint;
    vec2 p=end_kerr_impact(q);
    if(abs(p.x)>5.99 || abs(p.y)>2.99) return vec3(32.0,32.0,0.0);
    vec2 uv=vec2(p.x/12.0+0.5,p.y/12.0+0.25+order*0.5);
    vec2 grid=uv*2048.0-0.5;
    ivec2 cell=ivec2(floor(grid)); vec2 f=fract(grid);
    vec2 anchor=end_decode_transfer(texelFetch(astraEndTransfer,ivec2(floor(grid+0.5)),0));
    bool anchorValid=max(abs(anchor.x),abs(anchor.y))<31.5;
    vec2 radialDirection=anchor/max(length(anchor),0.001);
    vec2 sum=vec2(0.0); float coordinateWeight=0.0;
    float radialSpan=0.0;
    // Never interpolate a captured/missing ray into an emitting disc coordinate.
    // Four bilinear taps plus a branch anchor keep the shadow edge clean.
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        vec2 at=end_decode_transfer(texelFetch(astraEndTransfer,cell+ivec2(x,y),0));
        float valid=1.0-step(31.5,max(abs(at.x),abs(at.y)));
        float weight=(x==0 ? 1.0-f.x : f.x)*(y==0 ? 1.0-f.y : f.y)*valid;
        // Front/underside branch boundaries are discontinuous even when both
        // hits are valid. Blending their coordinates would invent glowing seams.
        float sameBranch=(!anchorValid || distance(at,anchor)<0.65) ? 1.0 : 0.0;
        sum+=at*weight*sameBranch; coordinateWeight+=weight*sameBranch;
        if(anchorValid && valid*sameBranch>0.5)
            radialSpan=max(radialSpan,abs(dot(at-anchor,radialDirection)));
    }
    // The same taps also measure radial magnification. Compressed front-disc
    // texture must fade before it aliases, without extra atlas reads or derivatives
    // inside divergent surface branches. One atlas texel spans 12/2048 image units.
    sourceFootprint=max(imageFootprint,radialSpan*imageFootprint*(2048.0/12.0));
    return coordinateWeight>0.00001 ? vec3(sum/coordinateWeight,coordinateWeight) : vec3(32.0,32.0,0.0);
}
vec3 end_disc_transfer(vec2 q,float order) {
    float unusedFootprint;
    return end_disc_transfer(q,order,0.0,unusedFootprint);
}
vec4 end_emission_frame(vec2 q,float order) {
    vec2 p=end_kerr_impact(q);
    vec2 uv=vec2(p.x/12.0+0.5,p.y/12.0+0.25+order*0.5);
    vec4 meta=textureLod(astraEndTransferMeta,clamp(uv,vec2(0.0005),vec2(0.9995)),0.0);
    vec3 direction=meta.xyz*2.0-1.0;
    direction/=max(length(direction),0.0001);
    return vec4(direction,meta.a>0.5 ? 1.0 : -1.0);
}
// One full turn takes 155 s at the inner edge and 244 s at r=1.34. The previous 0.38
// turned the inner disc over in 19 s, which reads as a blur rather than as flow.
// The slow-down is uniform in r, so the differential shear keeps its inward sweep.
float end_orbital_rate(float r) {
    return 0.0475/(pow(max(r,END_DISC_INNER)/END_DISC_INNER,1.5)+0.18*END_KERR_SPIN);
}
float end_frequency_shift(vec2 p,vec3 toward) {
    // Equatorial Kerr lapse, frame dragging and circular-orbit speed. The baked
    // central-force path supplies a local emission direction, not a screen-side sign.
    // Combining that path with these local factors remains a visual approximation.
    const float mass=0.19245009; // GM/c^2, consistent with atlas horizon=1/2.598.
    float r=max(length(p),END_DISC_INNER), a=END_KERR_SPIN*mass;
    float delta=r*r-2.0*mass*r+a*a;
    float area=(r*r+a*a)*(r*r+a*a)-a*a*delta;
    float lapse=sqrt(max(delta*r*r/area,0.01));
    float circumference=sqrt(area)/r;
    float dragging=2.0*mass*a*r/area;
    float omega=sqrt(mass)/(pow(r,1.5)+a*sqrt(mass));
    float beta=clamp((omega-dragging)*circumference/lapse,0.0,0.82);
    vec2 tangent=vec2(p.y,-p.x)/r; // Same clockwise sense as flow/hotspot advection.
    float lineOfSight=dot(tangent,toward.xy);
    float grav=lapse+dragging*circumference*lineOfSight;
    return clamp(grav*sqrt(1.0-beta*beta)/max(1.0-beta*lineOfSight,0.15),0.25,2.0);
}
float end_orbiting_hotspots(vec2 p,float footprint) {
    float r=length(p), az=atan(p.y,p.x), heat=0.0;
    for(int i=0;i<2;i++) {
        float centre=i==0 ? 1.34 : 2.06;
        float width=i==0 ? 0.09 : 0.15;
        float lifetime=i==0 ? 60.0 : 90.0;
        float age=mod(frameTimeCounter+float(i)*23.0,lifetime)/lifetime;
        float envelope=pow(sin(END_PI*age),2.0);
        float phase=az+frameTimeCounter*end_orbital_rate(centre)+float(i)*2.4;
        // Differential shear stretches a patch into an arc over its finite lifetime.
        phase+=age*(r-centre)*3.5;
        float angularWidth=mix(0.10,0.34,age);
        float radialWidth=width*width+footprint*footprint;
        float angularVariance=angularWidth*angularWidth+footprint*footprint/(r*r);
        float spotWeight=exp(-(r-centre)*(r-centre)/radialWidth
                        -2.0*(1.0-cos(phase))/angularVariance);
        heat+=envelope*spotWeight*width*width/radialWidth;
    }
    return heat;
}
float end_kerr_footprint(vec2 q,float cone) {
    return max(cone/END_SHADOW_TAN*(1.0+dot(q,q)*END_SHADOW_TAN*END_SHADOW_TAN),0.0006);
}
float end_flow_edge(float r,float footprint) {
    float aa=max(footprint,0.003);
    return smoothstep(END_DISC_INNER-aa,END_DISC_INNER+0.12+aa,r)
           *(1.0-smoothstep(END_DISC_OUTER-1.10-aa,END_DISC_OUTER+aa,r));
}
vec3 end_photon_radiance(vec2 q,float aa) {
    float r=end_kerr_radius(q);
    // Fixed angular thickness, floored by the pixel footprint: the ring reads as
    // a resolved band instead of the one-pixel hairline a pixel-sized width gives.
    float width=max(0.0110,aa*1.60);
    float offset=(r-1.007)/width;
    if(abs(offset)>3.5) return vec3(0.0);
    vec2 radial=q-vec2(-0.055*END_KERR_SPIN,0.0);
    float approach=clamp(radial.x/max(length(radial),0.0001)*0.5+0.5,0.0,1.0);
    vec3 tint=mix(vec3(1.0,0.80,0.62),vec3(0.70,0.87,1.0),approach);
    return tint*exp(-offset*offset)*mix(1.7,6.0,approach);
}
// Main sky keeps the photon ring at native resolution. This cheap mask needs no
// turbulence, and foreground shape queries run only on the narrow ring itself.
vec3 end_crisp_photon_ring(vec3 ray,float cone) {
    if(dot(ray,end_light_direction())<=0.04) return vec3(0.0);
    vec2 q=end_kerr_screen(ray);
    float aa=end_kerr_footprint(q,cone);
    vec3 ring=end_photon_radiance(q,aa);
    if(max(ring.r,max(ring.g,ring.b))<0.00001) return vec3(0.0);
    vec3 point=end_disc_transfer(q,0.0);
    float cover=end_flow_edge(length(point.xy),aa*2.0)*point.z;
    if(point.y>0.0) cover*=smoothstep(1.025,1.065,end_kerr_radius(q));
    ring*=1.0-cover;
    if(max(ring.r,max(ring.g,ring.b))<0.00001) return vec3(0.0);
    for(int i=66;i<END_BODY_COUNT;i++) {
        float hit,coverage; vec3 normal;
        if(end_body_intersect(vec3(0.0),ray,END_FAR,end_body(i),i,cone,hit,normal,coverage))
            return vec3(0.0);
    }
    return ring;
}
vec3 end_lensed_background(vec3 ray) {
    float facing=dot(ray,end_light_direction());
    if(facing<=0.04) return ray;
    mat3 b=end_kerr_basis();
    vec2 q=end_kerr_screen(ray);
    float r=end_kerr_radius(q);
    float influence=1.0-smoothstep(3.0,6.5,r);
    if(influence<=0.0) return ray;
    // Inverse image map: tangential stretching forms local galaxy/star arcs.
    // The small spin twist decays rapidly instead of rotating the whole sky.
    float bend=1.85/max(r*r-0.23,0.22);
    float drag=END_KERR_SPIN*0.13/(1.0+r*r*r);
    vec2 warped=q*(1.0-bend)+vec2(-q.y,q.x)*drag;
    vec3 mapped=normalize(b[2]+(b[0]*warped.x+b[1]*warped.y)*END_SHADOW_TAN);
    return normalize(mix(ray,mapped,influence));
}
vec3 end_flow_field(float r,float phase) {
    // Follow fluid parcels in the disc plane. Cartesian eddies avoid the long
    // coherent bands produced by repeating a polar strip around every radius.
    vec2 uv=vec2(r*0.34,phase/END_TAU);
    vec4 body=textureLod(astraEndFlow,uv,0.0);
    vec2 parcel=vec2(cos(phase),sin(phase))*r*0.36;
    vec2 warp=(body.rg-0.5)*0.24;
    // Differential orbital advection shears these finite cells into arcs.
    // Three reads per advected phase remain.
    vec4 strands=textureLod(astraEndFlow,parcel*4.7+warp,0.0);
    vec4 grains=textureLod(astraEndFlow,parcel*4.2+warp*1.7,0.0);
    return vec3(body.r*0.40+strands.r*0.60,strands.g,grains.a);
}
vec4 end_flow_material(vec2 p,float footprint,vec4 frame) {
    float r=length(p);
    float edge=end_flow_edge(r,footprint);
    if(edge<=0.0001) return vec4(0.0);
    float az=atan(p.y,p.x);
    float omega=end_orbital_rate(r);
    // Renew fluid structures smoothly: differential rotation never winds them
    // into subpixel rings after a long game session. Both sampled terms (the polar
    // strip and the cartesian parcel) are exactly periodic in phase with period
    // END_TAU, so wrapping the phase itself is an exact identity -- it bounds the
    // argument for free instead of crossfading two ages. The old crossfade mixed a
    // sample 12 s apart, i.e. 223 degrees of pattern rotation at the inner edge, and
    // the two overlapping copies were the ghost image; wrapping advances one copy.
    float phase=az+mod(frameTimeCounter*omega,END_TAU);
    vec3 flow=end_flow_field(r,phase);
    float resolved=1.0-smoothstep(0.018,0.080,footprint);
    flow.y=mix(0.5,flow.y,resolved);
    flow.z=mix(0.5,flow.z,1.0-smoothstep(0.010,0.055,footprint));
    // A narrow level-set band of the advected strand field reads as thin arcs
    // rather than the broad blobs the same field makes with a wide ramp. The band
    // sits above the 0.5 the unresolved field decays to, so a coarse footprint
    // loses the ridges instead of gaining a uniform outer glow.
    float filament=pow(smoothstep(0.50,0.66,flow.y),5.0);
    float patches=smoothstep(0.30,0.65,flow.x);
    float sparks=pow(smoothstep(0.50,0.72,flow.z),4.0)*(0.25+patches);
    float structure=0.15+0.38*patches+1.6*filament*patches+sparks*1.2;
    float heating=1.0+2.5*end_orbiting_hotspots(p,footprint);
    float flux=end_disc_flux(r)*(0.06+0.95*structure)*heating;
    float g=end_frequency_shift(p,frame.xyz);
    // Photosphere scale sets the observed colour temperature: the bulk of the disc
    // lands blue-white, and only the dim tail of the outer, receding flow drops
    // below the 6500 K white point into the ember tint.
    // Normalising the blackbody return does not preserve luminance, because the
    // 610/545/465 nm proxies rebalance with temperature and lose red/green once
    // divided by the blue peak. This 26000 K scale therefore costs about 18% of
    // the disc radiance against a 10500 K one; the emission coefficient below
    // carries the matching compensation.
    float temperature=26000.0*pow(max(flux,0.0),0.25)*g;
    float slope=(end_disc_half_height(r+0.002)-end_disc_half_height(r-0.002))/0.004;
    vec3 normal=normalize(vec3(-slope*p/max(r,0.001),frame.w));
    float mu=clamp(dot(normal,frame.xyz),0.0,1.0);
    float limb=0.42+0.58*mu;
    // Integrated intensity transforms as g^4; g^3 belongs to spectral intensity.
    // Temperature shifts by g while the same heating law supplies T^4 and flux.
    // Expand the small RGB difference between neighbouring blackbody colours
    // around their luminance. Otherwise the display shoulder makes both sides
    // near-white even though their observed temperatures differ strongly.
    vec3 spectral=astra_blackbody_rgb(temperature);
    float luminance=dot(spectral,vec3(0.2126,0.7152,0.0722));
    spectral=max(vec3(luminance)+(spectral-vec3(luminance))*2.4,vec3(0.0));
    // 2.6908 = 2.2*1.2231: folds back the luminance the 26000 K colour scale loses.
    vec3 emission=spectral*flux*2.6908*g*g*g*g*limb;
    // Inner photosphere stays opaque; the tenuous outer skirt opens between
    // dense turbulent patches and reveals the lensed star field beneath it.
    edge*=mix(1.0,1.0-exp(-structure*3.5),smoothstep(2.4,END_DISC_OUTER,r));
    return vec4(emission,edge);
}
#endif
