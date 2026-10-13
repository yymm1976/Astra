#ifndef ASTRA_ITT_WATER_FIELD_GLSL
#define ASTRA_ITT_WATER_FIELD_GLSL
// Same-frame incident wave-collision flux in R (RG16F).
// Flux is filtered AFTER its nonlinear response, preserving fine bright strands.
// Texel 0 carries window offset RG; the 2-block inset keeps even LOD 4 away
// from its footprint. No weather, scene shadow or depth is baked.
#include "/global/water/optics.glsl"
#include "/lib/solas_water_frame.glsl"
const float ITT_WATER_FIELD_SIZE = 1024.0;
const float ITT_WATER_FIELD_EXTENT = 64.0;
const float ITT_WATER_FIELD_CELL = ITT_WATER_FIELD_EXTENT/ITT_WATER_FIELD_SIZE;
vec3 itt_water_light_direction(mat4 shadowInverse) {
    return normalize(shadowInverse[2].xyz);
}
float itt_water_daylight(vec3 lightDirection, float sunSource) {
    return sunSource*smoothstep(0.07,0.35,lightDirection.y);
}
// Shared current-frame light gate for production and consumption. The field is
// generated after the water-state scan, including a newly entered pool.
float itt_water_source_visibility(vec3 lightDir) {
    float clearDay = itt_water_daylight(lightDir,astraSunSource)*(1.0-clamp(wetness,0.0,1.0));
    float sourceStrength = mix(float(MOONLIGHT_STRENGTH),float(SUNLIGHT_STRENGTH),astraSunSource)*0.01;
    float visibility = astraSolasShadowFade*(1.0-clamp(wetness,0.0,1.0)*0.75)*sourceStrength;
    visibility *= mix(0.32,1.35,clearDay)*mix(0.65,1.0,astraSunSource);
    return visibility*(1.0-clamp(blindness,0.0,1.0));
}
vec2 water_shaft_field_origin(vec4 metadata) {
    return (floor(cameraPosition.xz/ITT_WATER_FIELD_CELL)+metadata.rg)*ITT_WATER_FIELD_CELL;
}
float water_shaft_collision_light(vec2 slope, vec3 lightDir) {
    vec3 normal = normalize(vec3(slope.x,1.0,slope.y));
    float cosine = dot(lightDir,normal);
    if (cosine <= 0.0) return 0.0;
    bool totalReflection;
    float transmission = 1.0-water_fresnel(clamp(cosine,0.0,1.0),1.0/WATER_IOR,totalReflection);
    float vertical = 1.0-2.0*normal.y*normal.y;
    float offset = 2.0*normal.y*length(normal.xz)/sqrt(vertical*vertical+0.0625);
    float caustic = 0.24+3.05*offset;
    // Resolve secondary weak strands without amplifying the strongest crests.
    float energy = caustic*caustic*caustic+0.22*offset/(0.15+offset);
    return transmission*energy/(1.0+0.25*energy);
}
#endif
