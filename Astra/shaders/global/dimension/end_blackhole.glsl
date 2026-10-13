#ifndef ASTRA_END_BLACKHOLE_GLSL
#define ASTRA_END_BLACKHOLE_GLSL
#include "/lib/pow.glsl"
// Original Astra three-band emission tint. The normalized wavelength ratio
// avoids large spectral intermediates; three exponentials replace nine per star.
// The wavelength vector is const so the fifth power below stays a constant
// expression: pow() on a non-const local is a runtime transcendental on drivers
// that do not propagate constants, while the multiply chain folds with the const.
const vec3 ASTRA_BLACKBODY_WAVELENGTHS=vec3(610.0,545.0,465.0);
vec3 astra_blackbody_rgb(float temperature) {
    const vec3 ratio=vec3(545.0)/ASTRA_BLACKBODY_WAVELENGTHS;
    const vec3 ratio2=ratio*ratio;
    const vec3 ratio5=ratio2*ratio2*ratio;   // positive constant base, x^5 = x^4 * x
    vec3 rgb=ratio5/(exp(vec3(1.4387769e7)/(ASTRA_BLACKBODY_WAVELENGTHS*max(temperature,1800.0)))-1.0);
    // Balance the three wavelength proxies at 6500 K. Without calibration their
    // unequal spectral samples falsely tint even the receding warm side blue.
    rgb*=vec3(1.23031549,1.09004696,1.0);
    return rgb/max(max(rgb.r,rgb.g),rgb.b);
}
#include "/global/dimension/end_system.glsl"

// Static light-path transfer plus animated emission: runtime contains no light-ray march.
#include "/global/dimension/end_kerr.glsl"
#include "/global/dimension/end_plasma.glsl"
float end_star_visibility = 0.0;
#if defined ASTRA_END_SKY_BUFFER || defined ASTRA_END_REFLECTION_CACHE_WRITE
float end_sky_ray_cone;
#endif
vec3 end_blackhole_system(vec3 ray,float cone,out float backgroundVisibility) {
    backgroundVisibility=1.0;
    if(dot(ray,end_light_direction())<=0.04) return end_background(ray,cone);
    // Build the sky frame once and reuse it for the screen mapping and the
    // lensed background; both previously rebuilt the same basis per pixel.
    mat3 kerrBasis=end_kerr_basis();
    vec2 q=end_kerr_screen(ray,kerrBasis);
    // Every impact-coordinate consumer below reuses this one
    // evaluation instead of re-deriving it in the radius, transfer and frame calls.
    vec2 impact=end_kerr_impact(q);
    float r=end_kerr_impact_radius(impact);
    if(r>7.0) return end_background(ray,cone);
    float aa=end_kerr_footprint(q,cone);
    float outside=smoothstep(1.0-aa,1.0+aa,r);
    // One critical-curve fade for the front- and rear-image coverages below.
    float rearReveal=smoothstep(1.025,1.065,r);
    backgroundVisibility=outside;
    vec3 color=vec3(0.0);

    // Atlas intersections are now the entering faces of a finite photosphere.
    // The first surface hides later intersections rather than drawing a dark copy.
    float primaryFootprint;
    vec3 primary=end_disc_transfer_impact(impact,0.0,aa,primaryFootprint);
    vec4 primaryFrame=vec4(0.0,0.0,1.0,1.0);
    vec4 front=vec4(0.0);
    if(primary.z>0.00001) {
        primaryFrame=end_emission_frame_impact(impact,0.0);
        // Behind-hole high-order images share the critical-curve fade, even
        // when a grazing ray misses the front disc and stores them as first hit.
        float frontVisibility=primary.y>0.0 ? outside*rearReveal : 1.0;
        if (frontVisibility > 0.0) {
            front=end_flow_material(primary.xy,primaryFootprint,primaryFrame);
            front.a*=frontVisibility;
        }
    }
    float frontCover=front.a*primary.z;
    float sourceZ=-100.0;
    if(primary.z>=0.001)
        sourceZ=-primary.y*0.987117
                +primaryFrame.w*end_disc_half_height(length(primary.xy))*END_DISC_INCLINATION;
    vec4 behind,ahead;
    end_plasma_layers(q,sourceZ,outside,behind,ahead);
    color=behind.rgb;
    backgroundVisibility*=behind.a;
    if(frontCover<1.0 && outside>0.00001 && rearReveal>0.0) {
        float secondaryFootprint;
        vec3 secondary=end_disc_transfer_impact(impact,1.0,aa,secondaryFootprint);
        if(secondary.z>0.00001) {
            vec4 back=end_flow_material(secondary.xy,secondaryFootprint,end_emission_frame_impact(impact,1.0));
            // At an atlas branch transition the two hits exchange image order.
            // Their pixel coverages are correlated, not independent alpha layers.
            // Condition the rear coverage on the unresolved front branch, so the
            // same rear surface does not acquire a dark seam at the disc cutoff.
            float available=primary.z>0.00001 ? min(primary.z,1.0-frontCover) : 1.0;
            float rearCoverage=clamp(secondary.z/max(available,0.00001),0.0,1.0);
            float backCover=back.a*outside*rearCoverage*rearReveal;
            color=mix(color,back.rgb,backCover);
            backgroundVisibility*=1.0-backCover;
        }
    }
    #ifndef ASTRA_END_SKY_BUFFER
    // The ring keeps the pre-stretch offset it was defined on; q and r are
    // already in hand here, so this costs one subtraction instead of a second
    // impact mapping and length inside the ring function.
    color+=end_photon_radiance_precomputed(q-vec2(-0.055*END_KERR_SPIN,0.0),r,aa);
    #endif
    color=mix(color,front.rgb,frontCover);
    backgroundVisibility*=1.0-frontCover;
    color=color*ahead.a+ahead.rgb;
    backgroundVisibility*=ahead.a;
    // Disc material can hide the launch region. The pole always shares its axis.
    if(frontCover!=1.0)
        color+=end_polar_jet(q,aa,outside)*(1.0-frontCover);
    if(backgroundVisibility>0.00001)
        color+=end_background(end_lensed_background(ray,kerrBasis,q,r),cone)*backgroundVisibility;
    return color;
}
void astra_end_blackhole(inout vec3 color,vec3 originalRay,vec3 unusedLightDirection) {
    #if defined ASTRA_END_SKY_BUFFER || defined ASTRA_END_REFLECTION_CACHE_WRITE
    float cone=max(end_sky_ray_cone,0.00002);
    #elif defined ASTRA_END_REFLECTION_FOOTPRINT
    // Reflections and medium queries may execute after discard or in divergent
    // material flow. Use the projection's bounded angular pixel size there.
    vec2 pixelCone=2.0/max(abs(vec2(gbufferProjection[0][0],gbufferProjection[1][1]))
                           *vec2(viewWidth,viewHeight),vec2(1.0));
    float cone=max(max(pixelCone.x,pixelCone.y),0.00002);
    #else
    float cone=max(max(length(dFdx(originalRay)),length(dFdy(originalRay))),0.00002);
    #endif
    // Only seven distant island silhouettes remain. The previous independent dust
    // ring and 66 foreground asteroids no longer compete with the accretion flow.
    float closest=END_FAR;
    vec3 nearestLocal=vec3(0.0);
    float nearestEpsilon=0.0;
    vec4 nearest=vec4(0.0);
    int nearestId=-1;
    for(int i=66;i<END_BODY_COUNT;i++) {
        vec4 body=end_body(i);
        float hit,epsilon; vec3 localHit;
        if(end_body_hit(vec3(0.0),originalRay,closest,body,i,cone,hit,localHit,epsilon)) {
            closest=hit; nearestLocal=localHit; nearestEpsilon=epsilon;
            nearest=body; nearestId=i;
        }
    }
    if(nearestId>=0) {
        vec3 normal=end_body_normal(nearestLocal,nearestEpsilon,nearest,nearestId);
        vec3 position=originalRay*closest;
        vec3 light=normalize(end_source_position()-position);
        float lit=max(dot(normal,light),0.0);
        // Backlit silhouettes have no diffuse term to shadow.
        float visibility=lit>0.0
            ? end_body_shadow(position+normal*nearest.w*0.012,light,nearest,nearestId) : 1.0;
        // Literal exponent: x^5 = x^4 * x, the multiply chain lib/pow.glsl exists for.
        float rim=pow5(1.0-max(dot(normal,-originalRay),0.0));
        color=vec3(0.0007,0.0010,0.0019)+vec3(0.065,0.072,0.085)*lit*visibility
              +vec3(0.018,0.021,0.027)*rim*lit;
        end_star_visibility=0.0;
    } else {
        // Opaque islands hide the entire expensive emission/background path.
        color=end_blackhole_system(originalRay,cone,end_star_visibility);
    }
    color*=1.0-0.18*end_eclipse();
}
#endif
