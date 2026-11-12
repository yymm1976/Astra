// Runs after translucent geometry, before scattering. One scan and two state texels.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/transforms.glsl"
#include "/global/lighting/shadowmap.glsl"
#include "/global/water/medium_state.glsl"
#include "/lib/water_interface_record.glsl"
#ifndef RGBA32F
const int RGBA32F = 0;
#endif
// The first texel retains the packed-height/kind contract. The other two need
// exact frame indices and world-space camera coordinates, not normalized bytes.
const int colortex6Format = RGBA32F;
/* RENDERTARGETS: 6 */
bool water_previous_volume_valid() {
    if (frameCounter <= 1 || astraTimeDiscontinuity != 0) return false;
    vec4 viewport = texelFetch(colortex6, ivec2(1, 0), 0);
    if (viewport.z != float((frameCounter - 1) % 4096) || viewport.w != 1.0
        || any(notEqual(viewport.xy, vec2(viewWidth, viewHeight)))) return false;
    vec4 cameraTime = texelFetch(colortex6, ivec2(2, 0), 0);
    if (any(isnan(cameraTime)) || any(isinf(cameraTime))) return false;
    vec3 travel = cameraPosition - cameraTime.xyz;
    float elapsed = frameTimeCounter - cameraTime.w;
    return dot(travel, travel) <= 64.0 && elapsed >= 0.0 && elapsed <= 0.25;
}
void main() {
    int stateSlot = int(gl_FragCoord.x);
    if (stateSlot == 1) {
        gl_FragData[0] = vec4(viewWidth, viewHeight, float(frameCounter % 4096), float(isEyeInWater));
        return;
    }
    if (stateSlot == 2) {
        gl_FragData[0] = vec4(cameraPosition, frameTimeCounter);
        return;
    }
    vec4 best = vec4(0.0);
    float bestDistance = 1e20;
    vec4 nearestSide = vec4(0.0);
    float sideDistance = 1e20;
    int nearSides = 0;
    ivec2 size = textureSize(colortex5, 0);
    // A viewport grid finds the nearest local interface; no fixed sea level.
    for (int y = 0; y < 12; ++y) {
        for (int x = 0; x < 20; ++x) {
            vec2 uv = (vec2(x,y) + 0.5) / vec2(20.0,12.0);
            ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
            vec4 data = texelFetch(colortex5, pixel, 0);
            if (data.a < 0.5) continue;
            if (water_interface_is_side(data)) {
                // Later glass/particles can replace depthtex0 without replacing
                // this water record. Use the side's own distance, not their depth.
                float distanceToSide = water_interface_side_distance(data);
                if (distanceToSide < 1.5) ++nearSides;
                if (distanceToSide < sideDistance) {
                    sideDistance = distanceToSide;
                    // colortex6 is a volume-kind record, not colortex5's interface
                    // sentinel encoding. RG is unused for a thin-sheet kind.
                    nearestSide = vec4(0.0, 0.0, data.b, 0.25);
                }
                continue;
            }
            float surfaceY = water_unpack_surface_height(data.rg);
            if (isEyeInWater == 1 && surfaceY < cameraPosition.y - 0.25) continue;
            // The record is point-fetched, so its ray must use that same texel centre.
            vec2 interfaceUV = (vec2(pixel) + 0.5) / vec2(size);
            vec3 ray = view_camera_relative(screen_view(vec3(interfaceUV, 0.5)));
            if (abs(ray.y) < 1e-4) continue;
            float t = (surfaceY - cameraPosition.y) / ray.y;
            if (t <= 0.0) continue;
            float distanceToSurface = length(ray * t);
            if (distanceToSurface < bestDistance) {
                bestDistance = distanceToSurface;
                best = data;
            }
        }
    }
    // A nearby water wall with no nearby top is a thin sheet, not an ocean
    // extending to the horizon. Also identify it while approaching from air,
    // so opaque lighting has this record on the first submerged frame.
    // A known horizontal interface remains a volume even when it is far away.
    if (nearSides >= 3 && best.a == 0.0) best = nearestSide;
    if (best.a == 0.0 && isEyeInWater == 1) {
        // Looking down hides the interface: retain its last observed world height.
        // A previous pool/sheet is usable only across consecutive submerged frames
        // at the same viewport and without a camera/time jump. Current interfaces
        // and the real shadow-map fallback remain independent of this history.
        if (water_previous_volume_valid()) {
            vec4 previous = water_volume_state();
            if (previous.a > 0.125 && previous.a < 0.375)
                best = previous;
            else if (previous.a > 0.5 && water_unpack_surface_height(previous.rg) >= cameraPosition.y - 0.25)
                best = previous;
        }
        #ifdef SHADOWS
            // First submerged frame can also recover a real surface from the sun map.
            vec3 p = distort(player_shadow(vec3(0.0))) * 0.5 + 0.5;
            if (best.a == 0.0 && shadow_uv_coverage(p) > 0.0) {
                float code = shadow_caster_data(p.xy).r;
                if (code < WATER_HEIGHT_NONE) {
                    float h = decode_water_height(code);
                    if (h >= cameraPosition.y - 0.25)
                        best = vec4(water_pack_surface_height(h), float(eyeBrightnessSmooth.y)/240.0, 1.0);
                }
            }
        #endif
    }
    gl_FragData[0] = best;
}
