#ifndef ASTRA_END_BLACKHOLE_GLSL
#define ASTRA_END_BLACKHOLE_GLSL
// Astra's finite directional scene and null-ray integrator. No texture/model assets.
// The retained blackbody helper below is the existing IterationT derivative;
// its source/provenance remains registered in THIRD-PARTY.md.
vec3 bh_Blackbody(float temperature) {
    const mat2x4 splineX=mat2x4(-0.2661293e9,-0.2343589e6,0.8776956e3,0.179910,
                               -3.0258469e9,2.1070479e6,0.2226347e3,0.240390);
    const mat3x4 splineY=mat3x4(-1.1063814,-1.34811020,2.18555832,-0.20219683,
                               -0.9549476,-1.37418593,2.09137015,-0.16748867,
                               3.0817580,-5.87338670,3.75112997,-0.37001483);
    float rt=1.0/temperature;
    float x=dot(vec4(rt*rt*rt,rt*rt,rt,1.0),temperature<4000.0 ? splineX[0] : splineX[1]);
    vec4 coeff=vec4(x*x*x,x*x,x,1.0);
    float z=1.0/dot(coeff,temperature<2222.0 ? splineY[0] : temperature<4000.0 ? splineY[1] : splineY[2]);
    vec3 xyz=vec3(x*z,1.0,z); xyz.z-=xyz.x+1.0;
    const mat3 xyzToSrgb=mat3(3.24097,-0.96924,0.05563,-1.53738,1.87597,-0.20398,-0.49861,0.04156,1.05697);
    return max(xyzToSrgb*xyz,vec3(0));
}
#include "/global/dimension/end_system.glsl"

// Ray-march budget. Both of these were effectively unbounded before: 256 steps with two
// geometry sweeps each. The reference implementation this orbit borrows from marches 50
// steps and intersects no geometry inside the loop at all, so 48 strided sweeps of the
// ring is already more thorough than the reference while staying inside a per-pixel
// budget a laptop GPU can actually retire.
const int END_MARCH_STEPS       = 48;
const int END_GEOMETRY_STRIDE   = 4;

vec3 end_ray_acceleration(vec3 p,float angularMomentumSquared) {
    float r=length(p);
    // Spatial Schwarzschild null-ray equation, integrated in an affine parameter.
    // Keep velocity unnormalised; normalising every step would destroy its invariant.
    float edge=1.0-smoothstep(1.6*END_SOURCE_SCALE,END_LENS_RADIUS,r);
    return -1.5*END_HORIZON*angularMomentumSquared*p/max(r*r*r*r*r,1e-8)*edge;
}
void end_disc_sample(vec3 p,vec3 ray,float stepLength,mat3 disc,float cone,
                     inout vec3 radiance,inout vec3 transmission) {
    p/=END_SOURCE_SCALE;
    stepLength/=END_SOURCE_SCALE;
    float h=dot(p,disc[2]);
    float radius=length(p-disc[2]*h);
    const float inner=0.56, outer=1.18;
    float edge=smoothstep(inner,inner+0.035,radius)*(1.0-smoothstep(outer-0.06,outer,radius));
    float halfThickness=radius*0.045; // Full thickness = 9% of radius.
    float density=edge*(1.0-smoothstep(halfThickness*0.5,halfThickness,abs(h)));
    if(density<=0.00001) return;
    float a=atan(dot(p,disc[1]),dot(p,disc[0]));
    float u=clamp((radius-inner)/(outer-inner),0.0,1.0);
    // Accretion flow has a visible real-time clock independent of island orbits.
    float spin=a-frameTimeCounter*mix(0.48,0.15,u);
    float turbulence=0.30+0.70*end_noise3(vec3(cos(spin),sin(spin),radius*7.0)*8.0);
    float resolved=1.0-smoothstep(0.20,1.0,cone*(END_SOURCE_DISTANCE/END_SOURCE_SCALE)*55.0);
    float strands=0.78+0.22*sin(radius*55.0+spin*4.0+turbulence*5.0)*resolved;
    float layers=0.86+0.14*cos(h/max(halfThickness,0.0001)*7.0);
    density*=turbulence*layers;
    // Cross-product length is the already computed cylindrical radius.
    vec3 tangent=cross(disc[2],p)/max(radius,1e-6);
    float doppler=1.0+0.5*dot(tangent,-ray);
    vec3 tint=mix(vec3(1.0,0.83,0.61),vec3(1.0,0.46,0.15),u);
    tint=mix(tint,vec3(0.72,0.85,1.0),max(doppler-1.0,0.0)*0.6);
    float alpha=1.0-exp(-density*stepLength*20.0);
    // Put turbulence in emitted radiance too: opacity alone loses all texture
    // once the disc becomes optically thick. Keep detail below the white shoulder.
    float emission=mix(2.4,0.65,u)*(0.35+0.65*turbulence)*strands;
    radiance+=transmission*alpha*tint*doppler*emission;
    transmission*=1.0-alpha;
}
float end_star_visibility = 0.0;
void astra_end_blackhole(inout vec3 color,vec3 originalRay,vec3 unusedLightDirection) {
    float cone=max(max(length(dFdx(originalRay)),length(dFdy(originalRay))),0.00002);
    vec3 source=end_source_position(), light=end_light_direction();
    vec4 bodies[END_BODY_COUNT];
    int bodyIndices[END_BODY_COUNT];
    for(int i=0;i<END_BODY_COUNT;i++) { bodies[i]=end_body(i); bodyIndices[i]=i; }
    vec3 radiance=vec3(0), transmission=vec3(1);
    float projection=dot(source,originalRay);
    float discriminant=projection*projection-dot(source,source)+END_LENS_RADIUS*END_LENS_RADIUS;
    if(discriminant<=0.0 || projection<=0.0) {
        end_scene_segment(vec3(0),originalRay,END_FAR,cone,bodies,bodyIndices,END_BODY_COUNT,radiance,transmission);
        color=(radiance+transmission*end_background(originalRay,cone))*(1.0-0.18*end_eclipse());
        end_star_visibility=dot(transmission,vec3(0.333333));
        return;
    }
    float entry=max(0.0,projection-sqrt(discriminant));
    if(end_scene_segment(vec3(0),originalRay,entry,cone,bodies,bodyIndices,END_BODY_COUNT,radiance,transmission)) {
        color=radiance*(1.0-0.18*end_eclipse()); return;
    }
    vec3 p=originalRay*entry-source, velocity=originalRay;
    vec3 momentum=cross(p,velocity);
    float angularMomentumSquared=dot(momentum,momentum);
    vec3 orbitalNormal=momentum*inversesqrt(max(angularMomentumSquared,1e-12));
    // Only bodies whose bounds touch the lens volume can intersect its curved path.
    // Keep every candidate: there is no fixed small-array overflow or dropped object.
    int candidateCount=0;
    for(int i=0;i<END_BODY_COUNT;i++) {
        // A central-force ray remains in its orbital plane. Exclude bounds that
        // cannot touch that plane before walking hundreds of curved segments.
        float radius=bodies[i].w*1.65;
        if(length(bodies[i].xyz-source)<=END_LENS_RADIUS+radius
           && abs(dot(bodies[i].xyz-source,orbitalNormal))<=radius+0.0001) {
            bodyIndices[candidateCount]=i; candidateCount++;
        }
    }
    mat3 disc=end_disc_basis();
    float angle=acos(clamp(dot(originalRay,light),-1.0,1.0));
    float shellWidth=max(radians(0.055),cone*0.5);
    float criticalAngle=asin(clamp(2.598076211*END_HORIZON/END_SOURCE_DISTANCE,0.0,1.0));
    float shell=exp(-pow((angle-criticalAngle)/shellWidth,2.0));
    float halo=exp(-pow((angle-criticalAngle)/radians(0.65),2.0))*0.10;
    bool shellDrawn=false, terminated=false, escapedLens=false;
    vec3 acceleration=end_ray_acceleration(p,angularMomentumSquared);
    for(int i=0;i<END_MARCH_STEPS;i++) {
        float r=length(p);
        float ds=clamp(r*0.085,0.006*END_SOURCE_SCALE,0.14*END_SOURCE_SCALE);
        // Resolve both faces of the finite-thickness disc, including grazing rays.
        float height=abs(dot(p,disc[2]));
        if(r<1.3*END_SOURCE_SCALE && height<0.14*END_SOURCE_SCALE) ds=min(ds,0.018*END_SOURCE_SCALE);
        vec3 next=p+velocity*ds+acceleration*(0.5*ds*ds);
        vec3 nextAcceleration=end_ray_acceleration(next,angularMomentumSquared);
        vec3 nextVelocity=velocity+(acceleration+nextAcceleration)*(0.5*ds);
        vec3 delta=next-p; float lengthStep=length(delta);
        vec3 ray=delta/max(lengthStep,1e-8);
        vec3 midpoint=(p+next)*0.5;
        // Geometry is consumed at its actual distance, before/after disc emission.
        //
        // COST: this sweep is the single most expensive thing in the pack. It runs
        // candidateCount body tests, each with a bounding-sphere reject and, on a hit,
        // a 96-step surface search. Calling it every step - and twice per step, as it
        // was - reached 512 sweeps per pixel, which is a GPU hang rather than a slow
        // frame: at 1080p a full-screen End sky is on the order of 1e11 iterations.
        // It is therefore strided: one sweep covers END_GEOMETRY_STRIDE segments, and
        // the limit passed is the distance actually spanned since the last sweep, so
        // nothing between sweeps is skipped over.
        if(i % END_GEOMETRY_STRIDE == 0) {
            if(end_scene_segment(source+p,ray,lengthStep*float(END_GEOMETRY_STRIDE),cone,bodies,bodyIndices,candidateCount,radiance,transmission)) { terminated=true; break; }
        }
        end_disc_sample(midpoint,ray,lengthStep,disc,cone,radiance,transmission);
        if(!shellDrawn && (dot(next,nextVelocity)>=0.0 || length(next)<=END_HORIZON)) {
            radiance+=transmission*vec3(1.0,0.88,0.72)*(shell*1.8+halo*0.6);
            shellDrawn=true;
        }
        p=next; velocity=nextVelocity; acceleration=nextAcceleration;
        if(length(p)<=END_HORIZON) {
            // Art-directed compressed secondary star image requested by the brief.
            // This is not light physically escaping the event horizon.
            vec3 secondary=normalize(light+disc[0]*dot(originalRay,disc[0])*8.0
                                           +disc[1]*dot(originalRay,disc[1])*8.0);
            #ifndef ASTRA_END_SKY_BUFFER
            radiance+=transmission*end_starfield(secondary,light,cone*8.0)*0.035;
            #endif
            transmission=vec3(0); terminated=true; break;
        }
        if(max(transmission.r,max(transmission.g,transmission.b))<0.00001) { terminated=true; break; }
        if(length(p)>END_LENS_RADIUS && dot(p,velocity)>0.0) { escapedLens=true; break; }
    }
    if(!terminated && escapedLens) {
        vec3 escaped=normalize(velocity);
        // The same far ring and solids form the warped arc and higher-order images.
        // There is no extra painted Einstein circle or scheduled foreground stripe.
        for(int i=0;i<END_BODY_COUNT;i++) bodyIndices[i]=i;
        end_scene_segment(source+p,escaped,END_FAR,cone,bodies,bodyIndices,END_BODY_COUNT,radiance,transmission);
        radiance+=transmission*end_background(escaped,cone);
        end_star_visibility=dot(transmission,vec3(0.333333));
    }
    // A path still orbiting at the iteration cap must not be mistaken for an
    // escaped ray and expose an unrelated straight background through the shadow.
    color=radiance*(1.0-0.18*end_eclipse());
}
#endif
