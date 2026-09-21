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
    // Forward scattering against the sun direction REFRACTED through the flat water
    // interface. The previous gate used the AIR sun vector: at noon the eye-to-pixel
    // ray points down while the sun points up, so dot(ray, airSun) <= 0 for every
    // seabed view and the beams were exactly zero at the hour they should be
    // strongest (consolidated review B1 / Qoder F-03 / Hunyuan B1; convention note:
    // sunAngle 0.25 = noon). That fix shipped with both refract inputs reversed, which
    // left the gate pointing at the wrong half-space -- corrected below.
    //
    // Refraction sign (2026-09-21, algebra and sweep in qa/tools/shaft_refract_probe.py):
    // refract(I, N, eta) takes the PROPAGATION direction (pointing into the interface)
    // with N on the incidence side. This call passes the pointing-at-the-sun vector with
    // N = (0,-1,0), i.e. both inputs reversed, so refract's raw output is the unit vector
    // pointing at the sun as seen from underwater (the apparent sun, y >= 0 in daytime,
    // Snell-correct). Negating it yields the propagation direction of sunlight inside
    // the water - downward and anti-solar in xz - which is the axis this gate phases
    // against now, so looking down at the seabed sits on the positive side and noon
    // returns VoL = 0 for it no longer.
    vec3 sunWorld = normalize(view_player(lightVector));
    vec3 refractSun = -refract(sunWorld, vec3(0.0, -1.0, 0.0), 1.0 / 1.2);
    float VoL = pow(clamp(dot(ray, refractSun), 0.0, 1.0), 1.5);
    // Forward scattering only, and daylight only: shafts must not appear when looking
    // away from the sun, and must not peak at dusk.
    float sunGate = smoothstep(-0.02, 0.16, worldSunVector.y);
    float visibility = sunGate * 0.85;
    #ifdef UNDERWATER_SHAFT_CALIBRATION
    // Solas V3.7b intensity calibration (idea only; expression written for Astra, ARR).
    // A soft VoL^2 lobe riding on a sun-visibility floor keeps a base level across the
    // forward hemisphere instead of collapsing to zero off the sun axis, so noon beams
    // do not vanish just off the exact sun direction. The 0.075 (=0.45/6) renormalizes
    // the raw peak (VoL=1,sun=1 -> 6) to the shipped noon peak (0.45), so the toggle
    // reshapes the falloff without changing overall brightness. Absolute weight + floor
    // are a starting point pending in-game A/B. Overrides the forward-scatter-only gate.
    visibility *= (1.0 + 2.0 * VoL * VoL) * (0.25 + 1.75 * sun) * 0.075;
    #else
    visibility *= mix(0.25 + VoL * 0.25, VoL * 0.45, time);
    #endif
    visibility *= 1.0 - clamp(blindness, 0.0, 1.0);
    if (visibility <= 0.0) return vec4(vec3(0.0),rayLength / 128.0);

    // IterationT 3.2 underwater volumetric fog uses a 40-block range rather than Solas'
    // 128; the shorter range plus the 1/max(3, d*0.1) attenuation below is what makes its
    // beams vanish as the camera approaches rather than sticking to the view.
    // maxDist is a TRUE distance now. Note the coverage this layout actually gives: with
    // the reference's step of maxDist/samples*0.5 the last sample sits at
    // maxDist/2 - step, i.e. about 17 blocks for the 7-sample preset, not 40. Starting
    // away from the eye is deliberate (it is the "walk closer and the beam vanishes"
    // behaviour), but the range label must not overstate the reach.
    const float maxDist = 40.0;
    // Samples span the full [0, maxDist] interval. The previous "* 0.5" placed the last
    // sample near maxDist/2, leaving the outer half of the beam unsampled
    // (consolidated review B2 / Hunyuan 11.1.3).
    float minDist = maxDist / float(UNDERWATER_SHAFT_SAMPLES);
    float maxCurrentDist = min(rayLength, maxDist);
    float dither = texture(solasWaterNoise, gl_FragCoord.xy / 512.0).b;
    vec3 integral = vec3(0.0);
    for (int i = 0; i < UNDERWATER_SHAFT_SAMPLES; ++i) {
        #ifdef UNDERWATER_SHAFT_CALIBRATION
        // Solas V3.7b sampling calibration (idea only; written for Astra): a jittered
        // geometric march. The stride doubles along the ray (exp2 over u in [0,1]), so
        // samples concentrate in the near field where the beam reads brightest; the
        // dither keeps sub-step coverage. Endpoints still span [0, maxDist).
        float u = (float(i) + dither) / float(UNDERWATER_SHAFT_SAMPLES);
        float currentDist = maxDist * (exp2(u) - 1.0);
        #else
        float currentDist = (float(i) + dither) * minDist;
        #endif
        if (currentDist > maxCurrentDist) break;
        // Scale by the ray length so currentDist is measured along the view ray.
        vec3 point = view_camera_relative(viewPos * (currentDist / eyeDistance));
        vec3 pos = distort(player_shadow(point)) * 0.5 + 0.5;
        // Square bounds: the distorted shadow map fills the full [0,1] square and the
        // End receiver branch already treats it that way. The old inscribed circle
        // unconditionally discarded the 21.5% of samples that land near the edges
        // (consolidated review B2 / Hunyuan 11.1.3).
        if (max(abs(pos.x * 2.0 - 1.0), abs(pos.y * 2.0 - 1.0)) >= 1.0) continue;
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
        #if SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
        float shade = shadow_opaque_visibility(pos);
        #else
        float shade = clamp((texture(shadowtex1, pos.xy).r - pos.z) * 65536.0, 0.0, 1.0);
        #endif
        if (shade <= 0.0) continue;
        // Caustic banding from the cheap 5-height curvature field: 10 fetches instead
        // of the 72-fetch 3x3 focus that previously ran per sample (504-720 fetches per
        // pixel). Clamped to [0.25, 1] so the field shapes the beam without crushing
        // it. Independent of WATER_CAUSTICS - the shadow-colour tint below carries that
        // option's contribution (consolidated review B3 / Qoder F-04 #1).
        float caustic = clamp(solas_water_caustics(point + cameraPosition), 0.0, 1.0);
        shade *= mix(0.25, 1.0, caustic);
        // Distance attenuation. Near the camera the beam is crushed, which is the
        // "walk closer and it disappears" behaviour; floor 3.0 -> 2.0 and slope
        // 0.1 -> 0.06 as part of the 2026-09-20 recalibration (consolidated review B4,
        // needs in-game A/B).
        shade /= max(2.0, currentDist * 0.06);
        vec3 col = texture(shadowcolor0, pos.xy).gba;
        #ifdef UNDERWATER_SHAFT_CALIBRATION
        // Solas V3.7b colour calibration (idea only; written for Astra): drift the beam
        // tint toward the sky colour through the day, so noon beams pick up a little of
        // the ambient blue instead of staying pure caster colour. Magnitude-preserving
        // mix (Solas' *0.1 is a source-domain scale that does not transfer to Astra's
        // col*col tint pipeline); the blend weight is a starting point for in-game A/B.
        col = mix(col, normalize(skyColor + 0.00001), time * 0.75);
        #endif
        integral += shade * clamp(col * col, 0.0, 4.0) * weight;
    }
    integral *= visibility;
    // The gate above already phases against the REFRACTED sun direction; the previous
    // second phase term applied the same direction twice with two different interface
    // normals and is gone (consolidated review B1).
    integral *= mix(solasWaterSqrt, solasWaterSqrt * solasWeather, wetness)
             * (6.0 + sun * 14.0);
    // Positive exponent keeps the zero-light case defined at extreme settings.
    integral = pow(integral, vec3(max(1.0 - pow(length(integral), 1.25) * 0.25, 0.01)));
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
        // Distance-aware weights, per design.md SC-33 ("distance-weighted
        // reconstruction"): a tap whose own geometry sits at a very different depth
        // than this pixel's ray length belongs to another surface and must not bleed
        // into the beam. The rayLength parameter was previously accepted and ignored
        // (consolidated review B5 / Qoder F-13).
        float tapDepth = textureLod(depthtex0, tapUV, 0.0).r;
        float tapDist = tapDepth < 1.0 ? length(screen_view(vec3(tapUV, tapDepth))) : 1.0e5;
        float weight = exp(-abs(tapDist - rayLength) * 0.25);
        encoded += textureLod(shaftMap, tapUV, 0.0).rgb * weight;
        weights += weight;
    }
    return pow(encoded / max(weights, 1e-5), vec3(4.0)) * 128.0;
}
#endif
#endif
