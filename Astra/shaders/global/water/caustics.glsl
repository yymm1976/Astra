#ifndef ASTRA_GLOBAL_WATER_CAUSTICS_GLSL
#define ASTRA_GLOBAL_WATER_CAUSTICS_GLSL
// Historical source: Solas V2.2b waterCaustics.glsl (licence undeclared).
// The former independent noise derivative pattern is superseded by Astra's
// water_sun_focus in optics.glsl, shared with solar volume scattering.
// Keep the source history in THIRD-PARTY.md; no distribution decision is made.
// Inputs: camera-relative receiver, shadow lookup, world footprint in blocks.
// scene.glsl provides shadowmap, medium_state and optics before this module.
const float WATER_CAUSTICS_DISTANCE = 64.0;
const float WATER_CAUSTICS_FADE_START = 48.0;
const float WATER_CAUSTICS_DEPTH = 8.0;

// Signed multiplier on DIRECT radiance only. Sun occlusion is already included
// in directRadiance at the caller, so neither dark troughs nor bright crests
// change ambient or local lights, and no focus can create light inside shadows.
float water_caustics(vec3 playerPos, vec3 shadowPos, float time, float pixelFootprint) {
    #ifndef WATER_CAUSTICS
        return 0.0;
    #else
        float coverage = shadow_coverage(playerPos, shadowPos);
        float distanceFade = 1.0 - smoothstep(WATER_CAUSTICS_FADE_START,
                                               WATER_CAUSTICS_DISTANCE, length(playerPos));
        if (coverage <= 0.0 || distanceFade <= 0.0) return 0.0;
        vec3 worldPos = playerPos + cameraPosition;
        vec4 volume = water_volume_state();
        float surfaceY;
        if (isEyeInWater == 1 && volume.a > 0.5) {
            surfaceY = water_unpack_surface_height(volume.rg);
        } else {
            float code = shadow_caster_data(shadowPos.xy).r;
            if (code >= 0.999) return 0.0;
            surfaceY = decode_water_height(code);
        }
        float depth = surfaceY - worldPos.y;
        if (depth <= 0.0) return 0.0;
        float depthFade = smoothstep(0.2, 1.5, depth)
                        * (1.0 - smoothstep(1.5, WATER_CAUSTICS_DEPTH, depth));
        vec3 lightDir = water_light_direction(normalize(view_player(lightVector)));
        vec3 surfacePos = worldPos + lightDir * (depth / max(lightDir.y, 1e-4));
        float footprintFade = 1.0 - smoothstep(0.25, 0.75, pixelFootprint);
        return (water_sun_focus(surfacePos) - 1.0) * footprintFade
             * depthFade * coverage * distanceFade;
    #endif
}
#endif
