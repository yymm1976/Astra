// Adapted from Solas V2.2b volumetricLight.glsl and composite3/5 by Septonious.
// See THIRD-PARTY.md. Astra uses a bounded 40-block march and distance-aware resolve.
// Colour absorption and hue-preserving compression live in lib/water_light_field.glsl.
// Static sampling noise is intentional: there is no temporal accumulation.
#ifndef ASTRA_GLOBAL_WATER_LIGHT_SHAFTS_GLSL
#define ASTRA_GLOBAL_WATER_LIGHT_SHAFTS_GLSL
#include "/lib/transforms.glsl"
#include "/lib/water_light_field.glsl"
uniform sampler2D colortex3;
const float WATER_SHAFT_MAX_DISTANCE = 128.0;

vec3 water_shafts_view(vec2 uv, out float rayLength) {
    ivec2 size = textureSize(depthtex0, 0);
    ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    float depth = texelFetch(depthtex0, pixel, 0).r;
    if (depth < 0.999999) {
        uint flags = uint(round(texelFetch(colortex3, pixel, 0).r * 255.0));
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
vec4 water_shafts_march(vec2 uv) {
    float rayLength;
    vec3 viewPos = water_shafts_view(uv, rayLength);
    vec3 ray = normalize(view_player(viewPos));
    float eyeDistance = max(length(viewPos), 1e-4);
    float sun = solas_sun_visibility();
    float time = astraSolasTimeBrightness;
    vec3 sunWorld = normalize(view_player(lightVector));
    float VoL = astra_water_phase(ray,sunWorld);
    float sunGate = smoothstep(-0.02, 0.16, worldSunVector.y);
    float visibility = sunGate * 0.85;
    #ifdef UNDERWATER_SHAFT_CALIBRATION
    visibility *= (1.0 + 2.0 * VoL * VoL) * (0.25 + 1.75 * sun) * 0.075;
    #else
    visibility *= mix(0.25 + VoL * 0.25, VoL * 0.45, time);
    #endif
    visibility *= 1.0 - clamp(blindness, 0.0, 1.0);
    if (visibility <= 0.0) return vec4(vec3(0.0),rayLength / 128.0);

    const float maxDist = 40.0;
    float minDist = maxDist / float(UNDERWATER_SHAFT_SAMPLES);
    float maxCurrentDist = min(rayLength, maxDist);
    float dither = texture(solasWaterNoise, gl_FragCoord.xy / 512.0).b;
    vec3 integral = vec3(0.0);
    for (int i = 0; i < UNDERWATER_SHAFT_SAMPLES; ++i) {
        #ifdef UNDERWATER_SHAFT_CALIBRATION
        float u = (float(i) + dither) / float(UNDERWATER_SHAFT_SAMPLES);
        float currentDist = maxDist * (exp2(u) - 1.0);
        #else
        float currentDist = (float(i) + dither) * minDist;
        #endif
        if (currentDist > maxCurrentDist) break;
        vec3 point = view_camera_relative(viewPos * (currentDist / eyeDistance));
        vec3 pos = distort(player_shadow(point)) * 0.5 + 0.5;
        if (max(abs(pos.x * 2.0 - 1.0), abs(pos.y * 2.0 - 1.0)) >= 1.0) continue;
        float weight = pow((currentDist / maxDist) / float(UNDERWATER_SHAFT_SAMPLES),
                           1.0 - time * 0.5);
        #if SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
        float shade = shadow_opaque_visibility(pos);
        #else
        float shade = clamp((texture(shadowtex1, pos.xy).r - pos.z) * 65536.0, 0.0, 1.0);
        #endif
        if (shade <= 0.0) continue;
        float caustic = solas_water_caustics(point + cameraPosition);
        shade *= clamp(1.0 + ASTRA_CAUSTIC_SHAFT_CONTRAST * (caustic - ASTRA_CAUSTIC_MEDIAN),
                       0.25, 2.5);
        shade /= max(2.0, currentDist * 0.06);
        vec3 col = texture(shadowcolor0, pos.xy).gba;
        vec3 beamTint = astra_water_beam_tint(col,currentDist);
        #ifdef UNDERWATER_SHAFT_CALIBRATION
        beamTint = mix(beamTint, normalize(skyColor + 0.00001), time * 0.75);
        #endif
        integral += shade * beamTint * weight;
    }
    integral *= visibility;
    integral *= mix(solasWaterSqrt, solasWaterSqrt * solasWeather, wetness)
             * mix(0.8, 4.2, sun);
    integral = astra_water_beam_limit(integral);
    return vec4(pow(clamp(integral / 128.0, 0.0, 1.0), vec3(0.25)), rayLength / 128.0);
}
#else
vec3 water_shafts_resolve(sampler2D shaftMap, vec2 uv, float rayLength) {
    vec2 pixel = 1.0 / vec2(textureSize(shaftMap, 0));
    vec3 encoded = vec3(0.0);
    float weights = 0.0;
    const vec2 offsets[4] = vec2[4](vec2(1.5, 0.5), vec2(-0.5, 1.5), vec2(-1.5, -0.5), vec2(0.5, -1.5));
    for (int i = 0; i < 4; ++i) {
        vec2 tapUV = clamp(uv + offsets[i] * pixel, pixel * 0.5, 1.0 - pixel * 0.5);
        vec4 tap = textureLod(shaftMap, tapUV, 0.0);
        float tapDist = tap.a * WATER_SHAFT_MAX_DISTANCE;
        float weight = exp(-min(abs(tapDist - rayLength), 24.0) * 0.25);
        encoded += tap.rgb * weight;
        weights += weight;
    }
    return pow(encoded / max(weights, 1e-5), vec3(4.0)) * 128.0;
}
#endif
#endif
