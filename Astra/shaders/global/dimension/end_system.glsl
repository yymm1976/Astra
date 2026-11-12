#ifndef ASTRA_END_SYSTEM_GLSL
#define ASTRA_END_SYSTEM_GLSL
// cube()/square() chains for the literal-exponent star terms below. Guarded, so
// the scene path that already includes this header pays nothing for the repeat.
#include "/lib/pow.glsl"
uniform sampler2D colortex8;
#define ASTRA_END_BODY_CACHE
#include "/global/dimension/end_geometry.glsl"
#include "/lib/end_star_catalogue.glsl"
float end_eclipse() {
    #ifdef ASTRA_END_BODY_CACHE
    vec4 illumination=texelFetch(colortex8,ivec2(0),0);
    return illumination.a>0.5 ? illumination.r : 0.0;
    #else
    return 0.0;
    #endif
}
// Elliptical pixel footprint in the local spherical tangent plane. The lensed Jacobian resolves
// tangential star arcs without smearing them into isotropic blobs.
float end_star_profile(vec2 delta,float radius,vec3 covariance) {
    float c00=radius*radius+covariance.x;
    float c11=radius*radius+covariance.y;
    float c01=covariance.z;
    float det=max(c00*c11-c01*c01,1e-9);
    float metric=(c11*delta.x*delta.x-2.0*c01*delta.x*delta.y+c00*delta.y*delta.y)/det;
    return exp(-metric)*radius*radius*inversesqrt(det);
}
vec3 end_starfield_filtered(vec3 direction,float cone,vec3 rayDx,vec3 rayDy) {
    // The frame rotation is baked into slot 315 by prepare, which runs ahead of every
    // consumer of this cache. The offline translation units drop ASTRA_END_BODY_CACHE
    // and rebuild the same angle from worldDay/worldTime.
    #ifdef ASTRA_END_BODY_CACHE
    vec2 starRotation=texelFetch(colortex8,ivec2(ASTRA_END_STAR_ROTATION_SLOT,0),0).xy;
    #else
    float starAngle=end_star_rotation();
    vec2 starRotation=vec2(cos(starAngle),sin(starAngle));
    #endif
    vec3 dir=end_rotate_y(direction,starRotation);
    vec3 dirDx=end_rotate_y(rayDx,starRotation), dirDy=end_rotate_y(rayDy,starRotation);
    // Spherical catalogue: latitude rows have circumference-proportional cell
    // counts. Equal angular cells avoid the cube chart's dense corners/face seams.
    // A different phase per row prevents aligned meridians from forming a grid.
    const float rows=END_STAR_ROWS;
    const float chartScale=180.0;
    float latitude=acos(clamp(dir.y,-1.0,1.0));
    // Longitude has no unique value at a pole; avoid undefined atan(0,0).
    float longitude=dot(dir.xz,dir.xz)>1e-10 ? atan(dir.z,dir.x)/END_TAU : 0.0;
    float latitudeCell=floor(latitude*(rows/END_PI));
    latitudeCell=min(latitudeCell,rows-1.0);
    vec3 tangent=vec3(-dir.z,0.0,dir.x);
    tangent=dot(tangent,tangent)>1e-10 ? normalize(tangent) : vec3(1.0,0.0,0.0);
    vec3 bitangent=cross(dir,tangent);
    // dot(dir-center, axis) = dot(dir,axis) - dot(center,axis). The ray's own
    // projections are the same for every catalogue cell this pixel visits, so
    // they are evaluated once instead of once per star. Rounding may differ.
    vec2 dirChart=vec2(dot(dir,tangent),dot(dir,bitangent));
    vec2 dx=chartScale*vec2(dot(dirDx,tangent),dot(dirDx,bitangent));
    vec2 dy=chartScale*vec2(dot(dirDy,tangent),dot(dirDy,bitangent));
    float extent=max(length(dx),length(dy));
    float resolved=min(1.0,1.2/max(extent,0.0001));
    dx*=resolved; dy*=resolved;
    // Every star in this ray shares the same filtered screen footprint.
    vec3 covariance=0.30*vec3(dx.x*dx.x+dy.x*dy.x,
                               dx.y*dx.y+dy.y*dy.y,
                               dx.x*dx.y+dy.x*dy.y);
    vec3 stars=vec3(0);
    for(int y=-1;y<=1;y++) {
        float row=latitudeCell+float(y);
        if(row<0.0 || row>=rows) continue;
        vec3 rowData=end_star_row(row);
        float columns=rowData.x;
        float rowPhase=rowData.y;
        float column=floor(fract(longitude+rowPhase)*columns);
        // Share the row's base angles and column limit. Each star keeps its
        // own catalogue jitter and trigonometric direction evaluation.
        float thetaBase=row*(END_PI/rows);
        float phiBase=-rowPhase*END_TAU;
        float rowColumnLimit=min(columns,3.0);
        for(int x=-1;x<=1;x++) {
            // Wrap the catalogue index, not just the sample coordinate. Stars
            // retain the same identity across the longitude seam.
            if(float(x+1)>=rowColumnLimit) continue;
            vec2 c=vec2(mod(column+float(x)+columns,columns),row);
            vec4 presence=end_star_presence(c.x,rowData.z);
            vec2 h=presence.xy;
            // Current spherical catalogue: 34% ordinary, 0.6% bright population.
            // This is a denser distribution than the retired cube-face catalogue;
            // it is retained here, not presented as an unchanged star population.
            if(h.x<0.34) {
                vec2 jitter=0.15+0.7*end_hash2(c+456.0);
                float theta=thetaBase+jitter.y*(END_PI/rows);
                float phi=(c.x+jitter.x)*(END_TAU/columns)+phiBase;
                vec3 center=vec3(sin(theta)*cos(phi),cos(theta),sin(theta)*sin(phi));
                vec2 delta=chartScale*(dirChart-vec2(dot(center,tangent),dot(center,bitangent)));
                float rank=cube(h.y);
                float radius=0.085+0.085*rank;
                float flux=(0.010+0.085*rank)*(0.30+0.70*h.y);
                float profile=end_star_profile(delta,radius,covariance)*resolved;
                if (profile > 0.0) {
                    float temperature=h.y>0.86 ? mix(3000.0,5200.0,h.x/0.34) : mix(5600.0,12000.0,h.y);
                    stars+=astra_blackbody_rgb(temperature)*flux*profile;
                }
            }
            vec2 hb=presence.zw;
            if(hb.x<0.006) {
                vec2 jitter=0.15+0.7*end_hash2(c+714.0);
                float theta=thetaBase+jitter.y*(END_PI/rows);
                float phi=(c.x+jitter.x)*(END_TAU/columns)+phiBase;
                vec3 center=vec3(sin(theta)*cos(phi),cos(theta),sin(theta)*sin(phi));
                vec2 delta=chartScale*(dirChart-vec2(dot(center,tangent),dot(center,bitangent)));
                float rank=cube(hb.y);
                float radius=0.15+0.24*rank;
                float flux=0.30*(0.30+0.70*rank);
                float core=end_star_profile(delta,radius,covariance)*resolved;
                float halo=0.040*end_star_profile(delta,radius*2.5,covariance)*resolved;
                float arms=hb.y>0.72 ? 0.05*resolved*(exp(-abs(delta.x)*2.2-abs(delta.y)*0.16)
                                                     +exp(-abs(delta.x)*0.16-abs(delta.y)*2.2)) : 0.0;
                float profile=core+halo+arms;
                if (profile > 0.0)
                    stars+=astra_blackbody_rgb(mix(3400.0,9000.0,hb.y))*flux*profile;
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
    #if !defined ASTRA_END_SKY_BUFFER && !defined ASTRA_END_REFLECTION_CACHE_WRITE
    sky+=end_starfield(direction,end_light_direction(),cone);
    #endif
    return sky;
}
#endif
