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
// Solas V2.2b volumetricLight.glsl, marched in Astra's world/shadow transforms.
// 2026-09-11 rewrite. The previous version read as a solid, hard-edged spotlight:
//   - it started sampling AT the camera (i=0 -> distance 0) with a near-constant weight,
//     so the near medium was painted solid all the way to the eye;
//   - it HARD-SKIPPED fully shadowed samples (`if (shadow1 >= 1.0) continue`), so with
//     4-10 samples the shadow boundary became a hard wedge instead of a gradient.
// The reference does neither: its first sample sits minDist away and the weight grows
// with distance, which is why Solas' shafts dissolve as you approach and stay soft.
vec4 water_shafts_march(vec2 uv) {
    float rayLength;
    vec3 viewPos = water_shafts_view(uv, rayLength);
    vec3 ray = normalize(view_player(viewPos));
    // True distance from the eye to this fragment. The march below must scale by this, not
    // by -viewPos.z: scaling by the Z component made currentDist an axial depth, so at a
    // grazing angle a sample labelled 8 blocks sat 16 blocks from the eye and could land
    // behind visible geometry that the loop then happily accumulated.
    float eyeDistance = max(length(viewPos), 1e-4);
    float sun = solas_sun_visibility();
    float time = astraSolasTimeBrightness;
    float VoU = 1.0 - pow(clamp(ray.y, 0.0, 1.0), 1.5);
    float VoL = pow(clamp(dot(ray, normalize(view_player(lightVector))), 0.0, 1.0), 1.5);
    // Forward scattering only, and daylight only: shafts must not appear when looking
    // away from the sun, and must not peak at dusk.
    float sunGate = smoothstep(-0.02, 0.16, worldSunVector.y);
    float visibility = sunGate * 0.85;
    visibility *= pow(VoU, 1.5);
    visibility *= mix(0.25 + VoL * 0.25, VoL * 0.45, time);
    visibility *= 1.0 - clamp(blindness, 0.0, 1.0);

    // IterationT 3.2 underwater volumetric fog uses a 40-block range rather than Solas'
    // 128; the shorter range plus the 1/max(3, d*0.1) attenuation below is what makes its
    // beams vanish as the camera approaches rather than sticking to the view.
    // maxDist is a TRUE distance now. Note the coverage this layout actually gives: with
    // the reference's step of maxDist/samples*0.5 the last sample sits at
    // maxDist/2 - step, i.e. about 17 blocks for the 7-sample preset, not 40. Starting
    // away from the eye is deliberate (it is the "walk closer and the beam vanishes"
    // behaviour), but the range label must not overstate the reach.
    const float maxDist = 40.0;
    float minDist = maxDist / float(UNDERWATER_SHAFT_SAMPLES) * 0.5;
    float maxCurrentDist = min(rayLength, maxDist);
    float dither = texture(solasWaterNoise, gl_FragCoord.xy / 512.0).b;
    vec3 integral = vec3(0.0);
    for (int i = 0; i < UNDERWATER_SHAFT_SAMPLES; ++i) {
        float currentDist = (float(i) + dither) * minDist;
        if (currentDist > maxCurrentDist) break;
        // Scale by the ray length so currentDist is measured along the view ray.
        vec3 point = view_camera_relative(viewPos * (currentDist / eyeDistance));
        vec3 pos = distort(player_shadow(point)) * 0.5 + 0.5;
        if (length(pos.xy * 2.0 - 1.0) >= 1.0) continue;
        // Distance-weighted: far samples dominate, which is the reference's soft falloff.
        float weight = pow((currentDist / maxDist) / float(UNDERWATER_SHAFT_SAMPLES),
                           1.0 - time * 0.5);
        // Smooth accumulation. shadowtex1 (opaque only) reports how much light reaches
        // this point, and it is multiplied in rather than used as a hard skip: that is
        // what turns the old wedges into a gradient.
        // R4 FIX: this was `1.0 - clamp(...)`, which is inverted. shadowtex1 stores the
        // depth of the nearest opaque caster from the light, so a sample is LIT when its
        // own depth is not greater than the stored one, i.e. when
        // (stored - pos.z) > 0. The old form therefore accumulated light exactly where
        // geometry blocked it and lit nothing where the ray was open - no amount of
        // softening, caustics or phase work could fix a reversed visibility term.
        // Matches global/lighting/shadowmap.glsl (`step(referenceDepth, stored)`) and the
        // reference's own texture2DShadow.
        #if SHADOW_FILTER_MODE == 1
        float shade = shadow_opaque_visibility(pos);
        #else
        float shade = clamp((texture(shadowtex1, pos.xy).r - pos.z) * 65536.0, 0.0, 1.0);
        #endif
        // Reference design point 1: modulate the beam by the water-surface caustics, cubed.
        // This is what turns an even cone into the soft banded columns the reference shows,
        // and because the same function drives the seabed caustics their phases agree.
        shade *= astra_water_caustics_shaft_at(point + cameraPosition);
        // Reference design point 2: distance attenuation. Near the camera the beam is
        // crushed, which is the "walk closer and it disappears" behaviour.
        shade /= max(3.0, currentDist * 0.1);
        vec3 col = texture(shadowcolor0, pos.xy).gba;
        integral += shade * clamp(col * col, 0.0, 4.0) * weight;
    }
    integral *= visibility;
    // Reference design point 3: the scattering phase uses the sun direction REFRACTED
    // through the water interface, not the air sun direction. Getting this wrong splits
    // the beam peak away from the sun the surface and sky agree on.
    vec3 sunWorld = normalize(view_player(lightVector));
    vec3 refractSun = refract(sunWorld, vec3(0.0, -1.0, 0.0), 1.0 / 1.2);
    integral *= mix(0.35, 1.0, pow(clamp(dot(refractSun, ray), 0.0, 1.0), 2.0));
    integral *= mix(solasWaterSqrt, solasWaterSqrt * solasWeather, wetness) * (4.0 + sun * 8.0);
    // Positive exponent keeps the zero-light case defined at extreme settings.
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
