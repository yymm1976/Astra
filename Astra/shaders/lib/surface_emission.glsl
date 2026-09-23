#ifndef ASTRA_SURFACE_EMISSION_GLSL
#define ASTRA_SURFACE_EMISSION_GLSL
#include "/lib/settings.glsl"

// Material identities come from block.properties, never from the albedo colour.
vec3 astra_end_stone_emission(uint material, vec3 albedo) {
    if (material != 11u) return vec3(0.0);
    float textureLight = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
    // A bounded warm emission preserves the diffuse texture and shadow contrast.
    // Bloom uses this separate source; the surface need not exceed white to glow.
    float pores = smoothstep(0.35, 0.75, textureLight);
    return vec3(0.16, 0.19, 0.08) * (0.25 + 0.75 * pores)
         * (END_STONE_GLOW * 0.01);
}

vec3 astra_rock_emission(uint material, vec3 albedo, vec3 worldPos,
                         vec3 normal, vec3 playerPos, float blockLight) {
    if (material < 12u || material > 15u) return vec3(0.0);
    float emitter = smoothstep(0.55, 0.95, blockLight);
    if (emitter <= 0.0) return vec3(0.0);
    vec3 tint;
    float peak, gain;
    if (material == 12u) { tint=vec3(1.00,0.34,0.08); peak=4.80; gain=1.00; }
    else if (material == 13u) { tint=vec3(0.90,0.72,0.55); peak=0.145; gain=1.30; }
    else if (material == 14u) { tint=vec3(0.78,0.70,0.64); peak=0.105; gain=0.80; }
    else { tint=vec3(0.95,0.78,0.55); peak=0.100; gain=0.95; }
    float tone = dot(albedo, vec3(0.299,0.587,0.114));
    float texGloss = clamp(gain * (0.55 + (tone-0.08)*2.0), 0.0, 1.0);
    float grain = fract(sin(dot(floor(worldPos*4.0),vec3(12.9898,78.233,37.719)))*43758.5453);
    grain = smoothstep(0.45,0.92,grain);
    float farFade = smoothstep(16.0,48.0,length(playerPos));
    grain = mix(grain,0.5,farFade);
    float gloss = clamp(texGloss*mix(0.55,1.45,grain),0.0,1.0);
    float grazing = 1.0-clamp(dot(-normalize(playerPos),normal),0.0,1.0);
    float graze = grazing*grazing*grazing*grazing*grazing;
    float lavaFacing = mix(mix(1.40,0.75,normal.y*0.5+0.5),1.0,farFade);
    // Keep the current look available at 100%; expose it instead of guessing a new peak.
    float strength = material == 12u ? NETHERRACK_GLOW * 0.01 : 1.0;
    return tint * min(peak*gloss*emitter*(0.22+0.78*graze)*lavaFacing,2.60) * strength;
}
#endif
