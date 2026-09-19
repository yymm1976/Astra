#ifndef ASTRA_GLOBAL_DIMENSION_END_GLSL
#define ASTRA_GLOBAL_DIMENSION_END_GLSL
#include "/global/dimension/end_blackhole.glsl"
// Solas V2.2b: common.glsl End palette, skyEffects.glsl stars/nebula,
// fog.glsl distance curve and gbuffersLighting.glsl shadow mix.
// Astra: linear HDR boundary, full-screen sky, emissive stellar disc instead
// of vortex, and no atmospheric cloud layers. See THIRD-PARTY.md.
#include "/lib/colors.glsl"
#include "/lib/encoding.glsl"
#include "/lib/solas_water.glsl"
struct EndParams { float nightVision; float heldLightBase; };
const vec3 END_SKY_LIGHT_COLOR = vec3(0.34,0.39,0.52);
const vec3 END_AMBIENT_COLOR = vec3(0.043,0.055,0.077);
const vec3 END_VOID_COLOR = vec3(0.000015,0.000025,0.00006);
vec3 end_void_tint(float y) { return END_VOID_COLOR; }
// The voidTint/time parameters were never consumed by the body and are gone
// (consolidated review E5 / Qoder F-52).
vec3 end_sky(vec3 dir) {
    vec3 sky=vec3(0);
    astra_end_blackhole(sky,normalize(dir),end_light_direction());
    return sky*(1.0-max(blindness,darknessFactor));
}
vec4 end_fog(out float skyFogStrength, float distanceToEye, float borderDistance, vec3 playerPos) {
    skyFogStrength = 0.0;
    float f = 1.0 - exp(-2.0 * pow4(borderDistance / max(borderFogDistance, 1.0)) * (END_FOG_DENSITY * 0.01));
    vec3 c = END_VOID_COLOR;
    float dark = max(blindness, darknessFactor);
    if (dark > 0.0) { f = max(f, 1.0-exp(-distanceToEye * dark * 0.1)); c *= 1.0-dark; }
    if (isEyeInWater == 2) { f = 1.0-exp(-distanceToEye*2.0); c=vec3(1.0,0.05,0.0); }
    return vec4(c, f);
}
vec3 end_lighting(vec3 albedo, vec3 normal, vec3 playerPos, vec3 shadowPos,
                  float blockLight, float emissive, float portal, float time, EndParams params) {
    vec3 surfaceLight = end_light_direction();
    float ndotl = max(dot(normal, surfaceLight), 0.0);
    float visibility = 1.0;
    #ifdef SHADOWS
    // Caster and receiver now share the fixed black-hole shadow projection.
    float coverage = shadow_coverage(playerPos, shadowPos);
    if (ndotl > 0.0 && coverage > 0.0)
        visibility = mix(1.0, shadow_opaque_visibility(shadowPos), coverage);
    #endif
    // Solas shadow mixing and palette. Astra uses a brighter diffuse response
    // below to keep the island readable with its separate exposure/tonemap.
    // This response is an artistic adaptation, not a color-space conversion.
    //
    // The mix WEIGHT used to be `visibility * ndotl` with no floor and no ceiling, so a
    // face turned away from the black hole settled at 0.0108 while a face pointing at it
    // reached 0.109 - a 3.7x step decided entirely by orientation, which is why end-stone
    // detail vanished on back walls. The weight now spans [0.15, 0.62].
    //
    // SC-39 CORRECTION (2026-09-17), and the second attempt at it. What shipped first in
    // this round also dropped the 0.25 scene scale and the 1.22 response on the stated
    // reasoning that 0.65 reproduced both endpoints. The arithmetic was right and the
    // conclusion wrong: 0.62 is not the maximum of the old weight (1.0 is), so the
    // strongest-lit face got 0.65 where it used to get 0.305 and the whole island came
    // out ~12% dim. Only the orientation range is meant to change, never the exposure.
    // The second attempt fixed the scale but clamped only the top, so the darkest faces
    // were still exactly as dark as before - the readability gain the change exists for
    // was zero. Only an explicit floor provides it.
    //
    // Chosen from measured values, not by eye: floor 0.15 leaves a fully lit face
    // bit-identical to what shipped (weight 0.62 is what an up-face already produced),
    // makes a black-hole-facing-away face 1.38x brighter, and keeps the light/shadow
    // ratio at 1.58x against the shipped 2.66x - readable without flattening the island
    // or breaking the black-hole-determined shadow direction.
    vec3 scene = mix(END_AMBIENT_COLOR, END_SKY_LIGHT_COLOR,
                     clamp(visibility * ndotl, 0.15, 0.62)) * 0.25;
    scene += solasMinLight + params.nightVision * vec3(0.2,0.3,0.2);
    // Guard against an End highlight reaching the tonemapper through a different
    // expression than the overworld's. It is luminance-preserving (identity below its
    // knee), so it changes nothing here except the very brightest black-hole pixels -
    // it is NOT what sets the island's brightness; the 0.25 * 1.22 above does.
    vec3 factor = astra_scene_highlights(sqrt(max(scene, vec3(0.0))) * 1.22);
    vec3 local = block_lighting(0.0, blockLight, held_light_strength(params.heldLightBase, playerPos), 0.0, 0.0);
    return albedo * (factor * (1.0 - 0.18 * end_eclipse()) + local + (emissive + portal * 2.0) * (EMISSIVE_STRENGTH * 0.01));
}
#endif
