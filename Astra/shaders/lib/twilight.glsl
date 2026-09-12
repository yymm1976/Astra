#ifndef ASTRA_TWILIGHT_GLSL
#define ASTRA_TWILIGHT_GLSL
// Shared astronomical envelope for the sky, cloud palette and diffuse terrain.
float astra_twilight_strength() {
    float elevation=worldSunVector.y;
    return smoothstep(-0.16,-0.035,elevation)
         * (1.0-smoothstep(0.08,0.32,elevation)) * (1.0-0.7*rainStrength);
}
vec3 astra_twilight_tint() {
    return mix(vec3(0.32,0.085,0.035),vec3(0.29,0.16,0.10),
               smoothstep(-0.03,0.16,worldSunVector.y));
}
vec3 astra_twilight_sky(vec3 direction) {
    vec2 sun=worldSunVector.xz/max(length(worldSunVector.xz),1e-5);
    vec2 view=direction.xz/max(length(direction.xz),1e-5);
    float facing=dot(view,sun);
    float horizon=exp(-abs(direction.y-0.045)*9.0)
                 * smoothstep(-0.22,-0.04,direction.y);
    float warm=pow(max(0.0,0.5+0.5*facing),3.0);
    float opposite=pow(max(-facing,0.0),2.0);
    return astra_twilight_strength()*horizon*
        (astra_twilight_tint()*warm + vec3(0.026,0.016,0.044)*opposite);
}
#endif
