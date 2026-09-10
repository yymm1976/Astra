#ifndef ASTRA_GLOBAL_WATER_LIGHT_SHAFTS_GLSL
#define ASTRA_GLOBAL_WATER_LIGHT_SHAFTS_GLSL
// Adapted from Solas V2.2b volumetricLight.glsl and composite3/5 by Septonious.
// Astra adapters: full-resolution transport, static noise (no TAA), GBA tint.
#include "/lib/transforms.glsl"
uniform sampler2D colortex3;
const float WATER_SHAFT_MAX_DISTANCE = 128.0;

vec3 water_shafts_view(vec2 uv, out float rayLength) {
    ivec2 size = textureSize(depthtex0, 0);
    ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    float depth = texelFetch(depthtex0, pixel, 0).r;
    if (depth < 0.999999) {
        uint flags = uint(round(texelFetch(colortex3, pixel, 0).r * 255.0));
        // A nearer translucent surface can cover the opaque hand marker. Correct
        // the hand projection only when this is still the same opaque depth.
        if ((flags & 128u) != 0u && depth == texelFetch(depthtex1, pixel, 0).r)
            depth = ((depth * 2.0 - 1.0) / MC_HAND_DEPTH) * 0.5 + 0.5;
    }
    vec2 pixelUV = (vec2(pixel) + 0.5) / vec2(size);
    vec3 viewPos = screen_view(vec3(pixelUV, min(depth, 0.999999)));
    rayLength = min(length(viewPos), WATER_SHAFT_MAX_DISTANCE);
    return viewPos;
}

#ifdef ASTRA_SHAFT_MARCH_PASS
#include "/global/water/caustics.glsl"
// Solas V2.2b computeVL underwater branch; positions use Astra's shadow matrix.
vec4 water_shafts_march(vec2 uv) {
    float rayLength;
    vec3 viewPos = water_shafts_view(uv, rayLength);
    vec3 ray = normalize(view_player(viewPos));
    float time = astraSolasTimeBrightness;
    float sun = solas_sun_visibility();
    float VoU = 1.0 - pow(clamp(ray.y, 0.0, 1.0), 1.5);
    VoU = mix(VoU, 1.0, time * 0.75);
    // 2026-09-11 user round: "不要搞一大堆光束打到玩家脸上". The old weighting kept a
    // floor of 0.35 + 0.35*VoL whatever the view direction was, so beams covered the
    // whole frame. The reference concentrates them on the sun side instead: this keeps
    // only the directional term, weighted by how steeply the view looks toward the sun,
    // so beams stay near the sun's azimuth and fade out when looking away from it.
    float VoL = pow(clamp(dot(ray, normalize(view_player(lightVector))), 0.0, 1.0), 2.6);
    float visibility = astraSolasShadowFade;
    // Sun shafts must stay visible through the near medium. The earlier build also
    // multiplied this by float(depthtex0.r > 0.56), a hard cut that removed every ray
    // terminating within ~6 blocks, which emptied the effect in exactly the range the
    // reference image shows beams. A smooth near ramp keeps the user's "close to the
    // camera it fades out" rule without deleting the visible depth range.
    visibility *= smoothstep(1.0, 3.5, rayLength);
    visibility *= pow(VoU, 1.5) * (1.0 - VoL) * 0.9;
    visibility *= (2.0 - sun) * 0.5 * (1.0 - clamp(blindness, 0.0, 1.0));
    float endDistance = min(-viewPos.z, WATER_SHAFT_MAX_DISTANCE);
    float dither = texture(solasWaterNoise, gl_FragCoord.xy / 512.0).b;
    vec3 integral = vec3(0.0);
    for (int i = 0; i < UNDERWATER_SHAFT_SAMPLES; ++i) {
        float sampleIndex = float(i) + dither;
        float distance = mix(sampleIndex * (128.0 / float(UNDERWATER_SHAFT_SAMPLES) * 0.5),
                             exp2(sampleIndex) - 0.95, time);
        if (distance > endDistance) break;
        vec3 point = view_camera_relative(viewPos * (distance / max(-viewPos.z, 0.0001)));
        vec3 pos = distort(player_shadow(point)) * 0.5 + 0.5;
        if (length(pos.xy * 2.0 - 1.0) >= 1.0 || pos.z <= 0.0 || pos.z >= 1.0) continue;
        // shadowtex1 holds opaque casters only. shadowtex0 also contains translucent
        // geometry, and since every underwater sample sits below the water surface the
        // water itself shadowed the whole volume: shadow0 >= 1 skipped every sample and
        // the shafts integrated to exactly zero. Opaque depth is the correct occluder
        // for light coming down through the surface; the coloured shadow still comes
        // from shadowcolor0.
        float shadow1 = clamp((texture(shadowtex1, pos.xy).r - pos.z) * 65536.0, 0.0, 1.0);
        if (shadow1 >= 1.0) continue;
        vec3 color = texture(shadowcolor0, pos.xy).gba;
        float weight = pow((distance / 128.0) / float(UNDERWATER_SHAFT_SAMPLES), 1.0 - time * 0.5);
        integral += clamp(color * color, 0.0, 8.0) * weight;
    }
    integral *= visibility * 1.75;
    integral *= mix(solasWaterSqrt, solasWaterSqrt * solasWeather, wetness) * (4.0 + sun * 8.0);
    // A positive exponent keeps the zero-light case defined at extreme settings.
    integral = pow(integral, vec3(max(1.0 - pow(length(integral), 1.25) * 0.25, 0.01)));
    return vec4(pow(clamp(integral / 128.0, 0.0, 1.0), vec3(0.25)), rayLength / 128.0);
}
#else
vec3 water_shafts_resolve(sampler2D shaftMap, vec2 uv, float rayLength) {
    vec2 pixel = 1.0 / vec2(textureSize(shaftMap, 0));
    vec3 encoded = vec3(0.0);
    const vec2 offsets[4] = vec2[4](vec2(1.5, 0.5), vec2(-0.5, 1.5), vec2(-1.5, -0.5), vec2(0.5, -1.5));
    for (int i = 0; i < 4; ++i) {
        vec2 offset = offsets[i];
        encoded += texture(shaftMap, clamp(uv + offset * pixel, pixel * 0.5, 1.0 - pixel * 0.5)).rgb;
    }
    return pow(encoded * 0.25, vec3(4.0)) * 128.0;
}
#endif
#endif
