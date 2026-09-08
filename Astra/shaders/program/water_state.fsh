// Runs after translucent geometry, before scattering. One pixel per frame.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/transforms.glsl"
#include "/global/lighting/shadowmap.glsl"
#include "/global/water/medium_state.glsl"
uniform sampler2D colortex5;
/* RENDERTARGETS: 6 */
void main() {
    vec4 best = vec4(0.0);
    float bestDistance = 1e20;
    ivec2 size = textureSize(colortex5, 0);
    // A viewport grid finds the nearest local interface; no fixed sea level.
    for (int y = 0; y < 12; ++y) {
        for (int x = 0; x < 20; ++x) {
            vec2 uv = (vec2(x,y) + 0.5) / vec2(20.0,12.0);
            ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
            vec4 data = texelFetch(colortex5, pixel, 0);
            if (data.a < 0.5) continue;
            float surfaceY = water_unpack_surface_height(data.rg);
            if (isEyeInWater == 1 && surfaceY < cameraPosition.y - 0.25) continue;
            vec3 ray = view_camera_relative(screen_view(vec3(uv, 0.5)));
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
    if (best.a < 0.5 && isEyeInWater == 1) {
        // Looking down hides the interface: retain its last observed world height.
        vec4 previous = water_volume_state();
        if (previous.a > 0.5 && water_unpack_surface_height(previous.rg) >= cameraPosition.y - 0.25)
            best = previous;
        #ifdef SHADOWS
            // First submerged frame can also recover a real surface from the sun map.
            vec3 p = distort(player_shadow(vec3(0.0))) * 0.5 + 0.5;
            if (best.a < 0.5 && shadow_uv_coverage(p) > 0.0) {
                float code = shadow_caster_data(p.xy).r;
                if (code < 0.999) {
                    float h = decode_water_height(code);
                    if (h >= cameraPosition.y - 0.25)
                        best = vec4(water_pack_surface_height(h), float(eyeBrightnessSmooth.y)/240.0, 1.0);
                }
            }
        #endif
    }
    gl_FragData[0] = best;
}
