#ifndef ASTRA_END_KERR_GLSL
#define ASTRA_END_KERR_GLSL
// Static curved-path transfer with restrained Kerr-like image deformation.
// The atlas is produced by qa/tools/build_end_transfer.py, never traced per frame.
const float END_KERR_SPIN = 0.94;
uniform sampler2D astraEndTransfer;
uniform sampler2D astraEndFlow;
uniform sampler2D astraEndFlowMips;
uniform sampler2D astraEndTransferMeta;
#include "/global/dimension/end_disc_profile.glsl"
mat3 end_kerr_basis() {
    return end_view_basis();
}
vec2 end_kerr_screen(vec3 ray,mat3 b) {
    return vec2(dot(ray,b[0]),dot(ray,b[1]))
           /max(dot(ray,b[2])*END_SHADOW_TAN,0.00001);
}
vec2 end_kerr_screen(vec3 ray) {
    return end_kerr_screen(ray,end_kerr_basis());
}
vec2 end_kerr_impact(vec2 q) {
    vec2 p=q-vec2(-0.055*END_KERR_SPIN,0.0);
    p.x*=1.0+0.025*END_KERR_SPIN*smoothstep(-0.3,0.8,p.x);
    return p;
}
float end_kerr_impact_radius(vec2 p) { return length(p); }
float end_kerr_radius(vec2 q) { return end_kerr_impact_radius(end_kerr_impact(q)); }
vec2 end_decode_transfer(vec4 encoded) {
    return (vec2(dot(encoded.rg,vec2(65280.0,255.0)),
                 dot(encoded.ba,vec2(65280.0,255.0)))/65535.0-0.5)*64.0;
}
// Impact coordinate -> atlas UV. The black-hole caller already holds one impact
// coordinate for both disc orders, so the mapping and its smoothstep are not
// rebuilt once per transfer/frame lookup.
vec2 end_kerr_transfer_uv(vec2 p,float order) {
    return vec2(p.x/12.0+0.5,p.y/12.0+0.25+order*0.5);
}
vec3 end_disc_transfer_impact(vec2 p,float order,float imageFootprint,out float sourceFootprint) {
    sourceFootprint=imageFootprint;
    if(abs(p.x)>5.99 || abs(p.y)>2.99) return vec3(32.0,32.0,0.0);
    vec2 uv=end_kerr_transfer_uv(p,order);
    vec2 atlasSize=vec2(textureSize(astraEndTransfer,0));
    vec2 grid=uv*atlasSize-0.5;
    ivec2 cell=ivec2(floor(grid)); vec2 f=fract(grid);
    // The nearest anchor is one of these same four corners. Retain all corners:
    // even a zero interpolation weight still contributes to radialSpan below.
    vec2 coordinates[4];
    for (int i=0; i<4; ++i)
        coordinates[i]=end_decode_transfer(texelFetch(astraEndTransfer,cell+ivec2(i&1,i>>1),0));
    ivec2 anchorOffset=ivec2(floor(grid+0.5))-cell;
    vec2 anchor=coordinates[anchorOffset.x+2*anchorOffset.y];
    bool anchorValid=max(abs(anchor.x),abs(anchor.y))<31.5;
    vec2 radialDirection=anchor/max(length(anchor),0.001);
    vec2 sum=vec2(0.0); float coordinateWeight=0.0;
    // Never interpolate a captured/missing ray into an emitting disc coordinate.
    // Four bilinear taps plus a branch anchor keep the shadow edge clean.
    float radialSpan=0.0;
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        vec2 at=coordinates[x+2*y];
        float valid=1.0-step(31.5,max(abs(at.x),abs(at.y)));
        // A missing atlas ray has zero coordinate weight and zero radial-span
        // contribution. Keep all four reads for the footprint calculation.
        if (valid <= 0.0) continue;
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
    // inside divergent surface branches. Use the actual atlas resolution.
    sourceFootprint=max(imageFootprint,radialSpan*imageFootprint*(atlasSize.x/12.0));
    return coordinateWeight>0.00001 ? vec3(sum/coordinateWeight,coordinateWeight) : vec3(32.0,32.0,0.0);
}
vec3 end_disc_transfer(vec2 q,float order,float imageFootprint,out float sourceFootprint) {
    return end_disc_transfer_impact(end_kerr_impact(q),order,imageFootprint,sourceFootprint);
}
vec3 end_disc_transfer(vec2 q,float order) {
    float unusedFootprint;
    return end_disc_transfer(q,order,0.0,unusedFootprint);
}
vec4 end_emission_frame_impact(vec2 p,float order) {
    vec2 uv=end_kerr_transfer_uv(p,order);
    vec4 meta=textureLod(astraEndTransferMeta,clamp(uv,vec2(0.0005),vec2(0.9995)),0.0);
    vec3 direction=meta.xyz*2.0-1.0;
    direction/=max(length(direction),0.0001);
    return vec4(direction,meta.a>0.5 ? 1.0 : -1.0);
}
vec4 end_emission_frame(vec2 q,float order) {
    return end_emission_frame_impact(end_kerr_impact(q),order);
}
// One full turn takes 155 s at the inner edge and 244 s at r=1.34. The previous 0.38
// turned the inner disc over in 19 s, which reads as a blur rather than as flow.
// The slow-down is uniform in r, so the differential shear keeps its inward sweep.
float end_orbital_rate(float r) {
    // r is clamped to the inner edge before the 1.5 power, so the algebraic
    // identity x*sqrt(x) replaces pow(x,1.5); rounding can differ.
    float x=max(r,END_DISC_INNER)/END_DISC_INNER;
    return 0.0475/(x*sqrt(x)+0.18*END_KERR_SPIN);
}
float end_frequency_shift(vec2 p,float radius,vec3 toward) {
    // Equatorial Kerr lapse, frame dragging and circular-orbit speed. The baked
    // central-force path supplies a local emission direction, not a screen-side sign.
    // Combining that path with these local factors remains a visual approximation.
    const float mass=0.19245009; // GM/c^2, consistent with atlas horizon=1/2.598.
    float r=max(radius,END_DISC_INNER), a=END_KERR_SPIN*mass;
    float delta=r*r-2.0*mass*r+a*a;
    float area=(r*r+a*a)*(r*r+a*a)-a*a*delta;
    float lapse=sqrt(max(delta*r*r/area,0.01));
    float circumference=sqrt(area)/r;
    float dragging=2.0*mass*a*r/area;
    // r >= END_DISC_INNER > 0 permits the algebraic r*sqrt(r) form.
    float omega=sqrt(mass)/(r*sqrt(r)+a*sqrt(mass));
    float beta=clamp((omega-dragging)*circumference/lapse,0.0,0.82);
    vec2 tangent=vec2(p.y,-p.x)/r; // Same clockwise sense as flow/hotspot advection.
    float lineOfSight=dot(tangent,toward.xy);
    float grav=lapse+dragging*circumference*lineOfSight;
    return clamp(grav*sqrt(1.0-beta*beta)/max(1.0-beta*lineOfSight,0.15),0.25,2.0);
}
float end_orbiting_hotspots(float r,float az,float footprint) {
    float heat=0.0;
    for(int i=0;i<2;i++) {
        float centre=i==0 ? 1.34 : 2.06;
        float width=i==0 ? 0.09 : 0.15;
        float lifetime=i==0 ? 60.0 : 90.0;
        float age=mod(frameTimeCounter+float(i)*23.0,lifetime)/lifetime;
        float envelopeWave=sin(END_PI*age);
        float envelope=envelopeWave*envelopeWave;
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
// `radial` is the pre-stretch offset q - (-0.055*spin,0) that the warm/cool
// balance is defined on, and `r` is the impact radius. Callers that already
// hold both (the black-hole system and the crisp-ring mask) pass them in, so
// the ring's early-out no longer pays for a second impact mapping and length.
vec3 end_photon_radiance_precomputed(vec2 radial,float r,float aa) {
    // Fixed angular thickness, floored by the pixel footprint: the ring reads as
    // a resolved band instead of the one-pixel hairline a pixel-sized width gives.
    float width=max(0.0110,aa*1.60);
    float offset=(r-1.007)/width;
    if(abs(offset)>3.5) return vec3(0.0);
    float approach=clamp(radial.x/max(length(radial),0.0001)*0.5+0.5,0.0,1.0);
    vec3 originalTint=mix(vec3(1.0,0.80,0.62),vec3(0.70,0.87,1.0),approach);
    vec3 tint=mix(vec3(1.0,0.70,0.48),vec3(0.54,0.78,1.0),approach);
    // Retain ring luminance while letting its warm/cool ends remain coloured.
    const vec3 luminanceWeights=vec3(0.2126,0.7152,0.0722);
    tint*=dot(originalTint,luminanceWeights)/dot(tint,luminanceWeights);
    return tint*exp(-offset*offset)*mix(1.7,6.0,approach);
}
vec3 end_photon_radiance(vec2 q,float aa) {
    return end_photon_radiance_precomputed(q-vec2(-0.055*END_KERR_SPIN,0.0),
                                           end_kerr_radius(q),aa);
}
// Main sky keeps the photon ring at native resolution. This cheap mask needs no
// turbulence, and foreground shape queries run only on the narrow ring itself.
vec3 end_crisp_photon_ring(vec3 ray,float cone) {
    if(dot(ray,end_light_direction())<=0.04) return vec3(0.0);
    vec2 q=end_kerr_screen(ray);
    float aa=end_kerr_footprint(q,cone);
    vec3 ring=end_photon_radiance(q,aa);
    if(max(ring.r,max(ring.g,ring.b))<0.00001) return vec3(0.0);
    // The disc lookup and the fade below previously derived this same impact
    // coordinate twice; the ring term keeps its own unstretched radial because
    // it deliberately uses the pre-impact offset.
    vec2 impact=end_kerr_impact(q);
    float unusedFootprint;
    vec3 point=end_disc_transfer_impact(impact,0.0,0.0,unusedFootprint);
    float cover=end_flow_edge(length(point.xy),aa*2.0)*point.z;
    if(point.y>0.0) cover*=smoothstep(1.025,1.065,end_kerr_impact_radius(impact));
    ring*=1.0-cover;
    if(max(ring.r,max(ring.g,ring.b))<0.00001) return vec3(0.0);
    for(int i=66;i<END_BODY_COUNT;i++) {
        float hit,epsilon; vec3 localHit;
        if(end_body_hit(vec3(0.0),ray,END_FAR,end_body(i),i,cone,hit,localHit,epsilon))
            return vec3(0.0);
    }
    return ring;
}
// The black-hole caller already accepted the ray and computed these coordinates.
vec3 end_lensed_background(vec3 ray,mat3 b,vec2 q,float r) {
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
vec3 end_lensed_background(vec3 ray) {
    if(dot(ray,end_light_direction())<=0.04) return ray;
    mat3 b=end_kerr_basis();
    vec2 q=end_kerr_screen(ray,b);
    return end_lensed_background(ray,b,q,end_kerr_radius(q));
}
// Offline-generated periodic mip tiles, each with a one-texel wrap gutter.
// PNG custom textures have no hardware mip chain in this Iris data path.
// `width` is supplied because level+1 halves it; the interpolating lookup below
// therefore needs one exp2 for both levels instead of one per level.
vec4 end_flow_mip_level(vec2 uv,float level,float width) {
    float row=1024.0-2.0*width+2.0*(level-1.0);
    vec2 coord=(fract(uv)*width+vec2(1.0,row+1.0))
               /vec2(textureSize(astraEndFlowMips,0));
    return textureLod(astraEndFlowMips,coord,0.0);
}
vec4 end_flow_sample(vec2 uv,float footprint) {
    float lod=clamp(log2(max(footprint*1024.0,1.0)),0.0,10.0);
    float level=floor(lod);
    if(level<0.5) {
        vec4 lower=textureLod(astraEndFlow,uv,0.0);
        if(lod<0.001) return lower;
        // Level 0 is the untiled base texture; level 1 is the first tiled row.
        return mix(lower,end_flow_mip_level(uv,1.0,512.0),lod);
    }
    float width=exp2(10.0-level);
    vec4 lower=end_flow_mip_level(uv,level,width);
    if(lod-level<0.001 || level>=10.0) return lower;
    // exp2(10-(level+1)) is exactly half of this level's tile width.
    return mix(lower,end_flow_mip_level(uv,level+1.0,width*0.5),lod-level);
}
vec2 end_flow_field(float r,float phase,float footprint) {
    // Advect continuous emitting sheets in the disc plane. Both scales use
    // Cartesian parcels; a polar stripe repeated around each annulus made
    // scale-like bands. Keep a mild, bounded spatial twist without winding
    // progressively narrower filaments as time passes.
    float shear=phase+sqrt(r)*0.18;
    vec2 parcel=vec2(cos(shear),sin(shear))*r;
    vec4 body=end_flow_sample(parcel*0.30+vec2(0.13,0.47),footprint*0.37);
    vec2 warp=(body.rg-0.5)*0.10;
    // Explicit mip interpolation still follows the projected source footprint.
    // No thresholded grain or second high-contrast procedural detail layer.
    vec4 detail=end_flow_sample(parcel*1.4+warp+vec2(0.37,0.19),footprint*4.0);
    return vec2(body.r,detail.g);
}
vec3 end_disc_emission_color(float temperature) {
    vec3 spectral=astra_blackbody_rgb(temperature);
    float warm=1.0-smoothstep(3800.0,6500.0,temperature);
    float cool=smoothstep(6500.0,9500.0,temperature);
    // A restrained depiction accent, driven by observed emission temperature,
    // not screen position. Preserve the original luminance and g^4 energy.
    vec3 tinted=spectral*mix(vec3(1.0),vec3(1.10,0.84,0.70),warm)
                        *mix(vec3(1.0),vec3(0.68,0.86,1.10),cool);
    const vec3 luminanceWeights=vec3(0.2126,0.7152,0.0722);
    return tinted*dot(spectral,luminanceWeights)
                 /max(dot(tinted,luminanceWeights),0.00001);
}
vec4 end_flow_material(vec2 p,float footprint,vec4 frame) {
    float r=length(p);
    float edge=end_flow_edge(r,footprint);
    if(edge<=0.0001) return vec4(0.0);
    float az=atan(p.y,p.x);
    // Advect the dominant detail as well as the sparse hotspots. A turn at the
    // representative emitting radius takes about 244 s, rather than 35 minutes.
    // This bounded coherent advection avoids unbounded differential winding;
    // hotspots still follow their individual radius-dependent orbital rates.
    float phase=az+mod(frameTimeCounter*end_orbital_rate(1.34),END_TAU);
    vec2 flow=end_flow_field(r,phase,footprint);
    // Bounded, soft density modulation. Squared cells,
    // hard patch thresholds and isolated bright grains produced mottled flakes.
    // The radial profile supplies the large-scale contrast instead.
    float structure=0.44+0.10*(flow.x-0.5)+0.16*(flow.y-0.5);
    // Material, hotspots and frequency shift share this same emitting point.
    float heating=1.0+2.5*end_orbiting_hotspots(r,az,footprint);
    float radialFlux=end_disc_flux(r);
    float flux=radialFlux*(0.06+0.95*structure)*heating;
    float g=end_frequency_shift(p,r,frame.xyz);
    // Observed blackbody temperature shifts by g once. Density modulates emitted
    // intensity, not the radial heating profile: dark texture creases should not
    // create a second, exaggerated red/blue boundary. See THIRD-PARTY.md.
    // The source-temperature scale is chosen for a visible-light depiction;
    // cooler outer annuli add colour on both sides without screen-space tinting.
    // Fourth root of a non-negative base: sqrt(sqrt(x)) is exact here and avoids
    // the transcendental pow(x,0.25). Rounding may differ.
    float temperature=6500.0*sqrt(sqrt(max(radialFlux*heating,0.0)))*g;
    float slope=(end_disc_half_height(r+0.002)-end_disc_half_height(r-0.002))/0.004;
    vec3 normal=normalize(vec3(-slope*p/max(r,0.001),frame.w));
    float mu=clamp(dot(normal,frame.xyz),0.0,1.0);
    float limb=0.42+0.58*mu;
    // Integrated intensity transforms as g^4; g^3 belongs to spectral intensity.
    vec3 spectral=end_disc_emission_color(temperature);
    // Colour accents preserve the frequency-shift energy and angular limb.
    vec3 emission=spectral*flux*2.2*g*g*g*g*limb;
    // Inner photosphere stays opaque; the tenuous outer skirt opens between
    // dense turbulent patches and reveals the lensed star field beneath it.
    edge*=mix(1.0,1.0-exp(-structure*3.5),smoothstep(2.4,END_DISC_OUTER,r));
    return vec4(emission,edge);
}
#endif
