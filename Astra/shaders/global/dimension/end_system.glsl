#ifndef ASTRA_END_SYSTEM_GLSL
#define ASTRA_END_SYSTEM_GLSL
uniform sampler2D colortex8;
#define ASTRA_END_BODY_CACHE
#include "/global/dimension/end_geometry.glsl"
float end_eclipse() {
    #ifdef ASTRA_END_BODY_CACHE
    vec4 illumination=texelFetch(colortex8,ivec2(0),0);
    return illumination.a>0.5 ? illumination.r : 0.0;
    #else
    return 0.0;
    #endif
}
// Elliptical pixel footprint in the star chart. The lensed Jacobian resolves
// tangential star arcs without smearing them into isotropic blobs.
float end_star_profile(vec2 delta,float radius,vec2 dx,vec2 dy) {
    float c00=radius*radius+0.30*(dx.x*dx.x+dy.x*dy.x);
    float c11=radius*radius+0.30*(dx.y*dx.y+dy.y*dy.y);
    float c01=0.30*(dx.x*dx.y+dy.x*dy.y);
    float det=max(c00*c11-c01*c01,1e-9);
    float metric=(c11*delta.x*delta.x-2.0*c01*delta.x*delta.y+c00*delta.y*delta.y)/det;
    return exp(-metric)*radius*radius*inversesqrt(det);
}
vec3 end_starfield_filtered(vec3 direction,float cone,vec3 rayDx,vec3 rayDy) {
    float rotation=radians(end_cycle_seconds(1296000.0)/3600.0);
    vec3 dir=end_rotate_y(direction,rotation);
    vec3 dirDx=end_rotate_y(rayDx,rotation), dirDy=end_rotate_y(rayDy,rotation);
    vec3 a=abs(dir); float dominant=max(a.x,max(a.y,a.z));
    vec3 stars=vec3(0);
    for(int axis=0;axis<3;axis++) {
        float component=axis==0 ? a.x : axis==1 ? a.y : a.z;
        if(component<max(dominant*(1.0-clamp(cone*3.0,0.02,0.25)),0.0001)) continue;
        vec2 uv=axis==0 ? dir.yz/component : axis==1 ? dir.xz/component : dir.xy/component;
        float signAxis=axis==0 ? dir.x : axis==1 ? dir.y : dir.z;
        float face=float(axis*2)+(signAxis>0.0 ? 0.0 : 1.0);
        vec2 p=(uv*0.5+0.5)*256.0, cell=floor(p);
        vec2 faceDx=axis==0 ? dirDx.yz : axis==1 ? dirDx.xz : dirDx.xy;
        vec2 faceDy=axis==0 ? dirDy.yz : axis==1 ? dirDy.xz : dirDy.xy;
        float normalDx=axis==0 ? dirDx.x : axis==1 ? dirDx.y : dirDx.z;
        float normalDy=axis==0 ? dirDy.x : axis==1 ? dirDy.y : dirDy.z;
        vec2 dx=128.0*(faceDx-uv*normalDx*sign(signAxis))/component;
        vec2 dy=128.0*(faceDy-uv*normalDy*sign(signAxis))/component;
        // The 3x3 neighbour support is bounded; attenuate unresolved footprints.
        float extent=max(length(dx),length(dy));
        float resolved=min(1.0,1.2/max(extent,0.0001));
        dx*=resolved; dy*=resolved;
        for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
            vec2 c=cell+vec2(x,y);
            if(any(lessThan(c,vec2(0))) || any(greaterThanEqual(c,vec2(256)))) continue;
            // Two populations share the cube-face grid: a dense faint field and a sparse
            // bright layer on a much smaller threshold. Keeping the existing per-face
            // projection is what stops the field from swirling or pinching at the cube
            // corners, and it is the structural difference from a volumetric cell hash -
            // here density is per face area, not per 3D cell.
            vec2 h=end_hash2(c+face*401.0);
            // The dense field is three times denser than the old 0.12 cut. At 0.12 the
            // chart carried ~47k stars over the whole sphere, which is why the reference
            // field reads crowded and this one read as an empty sky.
            if(h.x<0.34) {
                vec2 center=c+0.15+0.7*end_hash2(c+face*419.0+37.0);
                // Power law in the star's own hash: most stars sit at the dim end (rank^3),
                // so the field is a deep texture rather than a wall of equally bright
                // points. The exponent is softer than rank^5 so the mid range is populated.
                float rank=pow(h.y,3.0);
                float radius=0.085+0.085*rank;
                // The old floor of 0.004 sits below the display black point (~0.006
                // linear), so almost the whole population was invisible; it is raised.
                float flux=(0.010+0.085*rank)*(0.30+0.70*h.y);
                float profile=end_star_profile(p-center,radius,dx,dy)*resolved;
                // Colour temperature, one star in six warm: the blue-white majority makes
                // the void read as cold, and the orange minority is the only warm note in
                // the field away from the accretion disc.
                float temperature=h.y>0.86 ? mix(3000.0,5200.0,h.x/0.34) : mix(5600.0,12000.0,h.y);
                stars+=astra_blackbody_rgb(temperature)*flux*profile;
            }
            vec2 hb=end_hash2(c+face*613.0+911.0);
            if(hb.x<0.006) {
                vec2 center=c+0.15+0.7*end_hash2(c+face*673.0+41.0);
                float rank=pow(hb.y,3.0);
                float radius=0.15+0.24*rank;
                float flux=0.30*(0.30+0.70*rank);
                float core=end_star_profile(p-center,radius,dx,dy)*resolved;
                // A fixed halo fraction: a bright star reads as a point with a small bloom
                // instead of a single hot pixel, and the halo scales with the core so the
                // brightest star is the one with the widest edge.
                float halo=0.040*end_star_profile(p-center,radius*2.5,dx,dy)*resolved;
                // The brightest few carry a thin pair of diffraction arms. Fading them
                // with 'resolved' stops an unresolved footprint from aliasing the arms
                // into a flickering line.
                vec2 delta=p-center;
                float arms=hb.y>0.72 ? 0.05*resolved*(exp(-abs(delta.x)*2.2-abs(delta.y)*0.16)
                                                     +exp(-abs(delta.x)*0.16-abs(delta.y)*2.2)) : 0.0;
                stars+=astra_blackbody_rgb(mix(3400.0,9000.0,hb.y))*flux*(core+halo+arms);
            }
        }
    }
    return stars;
}
// Reflection paths use a conservative isotropic chart footprint. The main
// deferred pass supplies its actual ray derivatives before any divergent branch.
vec3 end_starfield(vec3 direction,vec3 unusedLightDir,float cone) {
    mat3 b=end_basis(direction);
    return end_starfield_filtered(direction,cone,b[0]*cone,b[1]*cone);
}
vec3 end_background(vec3 direction,float cone) {
    vec3 sky=vec3(0.000015,0.000025,0.00006);
    #ifndef ASTRA_END_SKY_BUFFER
    sky+=end_starfield(direction,end_light_direction(),cone);
    #endif
    return sky;
}
#endif
