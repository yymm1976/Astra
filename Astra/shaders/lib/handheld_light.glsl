#ifndef ASTRA_HANDHELD_LIGHT_GLSL
#define ASTRA_HANDHELD_LIGHT_GLSL
#include "/lib/emitter_colors.glsl"
#ifdef HANDHELD_LIGHTING
#if defined ASTRA_HELD_LIGHT_VERTEX
flat out vec3 astraHeldLightTint;
#elif defined ASTRA_HELD_LIGHT_FRAGMENT
flat in vec3 astraHeldLightTint;
#endif
#endif
vec3 astra_held_item_color(int item) {
    // Ordinary torches retain Astra's current warm light. Other existing item
    // groups share the corresponding volume-source hue; unknown items stay warm.
    if (item >= 10021 && item <= 10027 && item != 10022)
        return astra_emitter_color(uint(item - 10019));
    return vec3(4.4, 2.9, 1.7);
}
vec3 astra_compute_held_light_tint() {
    // Match the existing fourth-power consumer and source cap, while preserving
    // its max-of-two-hands intensity: two torches do not double the brightness.
    vec2 levels = clamp(vec2(heldBlockLightValue, heldBlockLightValue2), 0.0, 14.0) / 15.0;
    vec2 weights = levels * levels;
    weights *= weights;
    float total = weights.x + weights.y;
    if (total <= 0.0) return vec3(1.0);
    vec3 color = (astra_held_item_color(heldItemId) * weights.x
                + astra_held_item_color(heldItemId2) * weights.y) / total;
    const vec3 warm = vec3(4.4, 2.9, 1.7);
    const vec3 luma = vec3(0.2126, 0.7152, 0.0722);
    // Match warm-light luminance where possible, without exceeding its peak.
    float gain = min(dot(warm, luma) / max(dot(color, luma), 0.00001),
                     4.4 / max(max(color.r, color.g), color.b));
    return color * gain / warm;
}
vec3 astra_held_light_tint() {
    #ifndef HANDHELD_LIGHTING
    return vec3(1.0);
    #elif defined ASTRA_HELD_LIGHT_FRAGMENT
    return astraHeldLightTint;
    #else
    return astra_compute_held_light_tint();
    #endif
}
// The player-centred light has a known direction, unlike a scalar lightmap.
// A wide residual keeps back-facing surfaces readable at close range.
float astra_held_light_facing(vec3 playerPos, vec3 normal) {
    #ifdef DIRECTIONAL_LOCAL_LIGHTING
    vec3 toLight = -playerPos - relativeEyePosition;
    float d2 = dot(toLight, toLight);
    if (d2 > 0.0001)
        return 0.75 + 0.25 * max(dot(normal, toLight * inversesqrt(d2)), 0.0);
    #endif
    return 1.0;
}
#endif
