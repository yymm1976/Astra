#ifndef ASTRA_WEATHER_GLSL
#define ASTRA_WEATHER_GLSL
#include "/lib/noise.glsl"
float astra_rain_exposure(float skyLight) {
    // pow(.., 16) required skyLight > 0.95, i.e. fully exposed noon terrain, which made
    // both puddles and the water impact rings vanish under any overcast sky. The user's
    // rain round is exactly that situation, so the curve is relaxed to a still-selective
    // but usable range.
    return pow(clamp(skyLight, 0.0, 1.0), 4.0)
         * smoothstep(0.0, 0.15, rainfall) * smoothstep(0.10, 0.20, temperature);
}
// Short rain envelope. Both wet signals - standing water and damp ground - are driven
// by astraRainFactor rather than by the engine's `wetness` memory, so both appear with
// the rain and both clear when it stops. Previously the puddle mask used
// `max(wetness, astraRainFactor * 0.8)` while its own envelope was applied separately,
// which let the engine's long-lived memory keep the mask alive after the rain had
// visibly stopped - the user's "停雨后长时间泛白的反射块". astraRainFactor is smoothed
// over a few seconds (shaders.properties), so this still ramps rather than switching.
float astra_rain_response() {
    return smoothstep(0.02, 0.55, astraRainFactor);
}
float astra_puddle(vec3 worldPos, vec3 normal, float skyLight) {
    // Coverage only: how much standing water has collected here, 0..1. The damp
    // ground that surrounds the patch is a separate signal (astra_wet_ground) because
    // the two must not behave the same way - see the header of astra_wet_ground.
    //
    // Smaller, separated patches; visible standing water follows the short
    // rain envelope rather than the engine's long-lived wetness memory.
    float n = texture(solasWaterNoise, worldPos.xz * 0.00075).b * 0.65
            + texture(solasWaterNoise, worldPos.xz * 0.00150).b * 0.35;
    // Only about one third of stable ten-block regions can accumulate puddles.
    vec2 cell = floor(worldPos.xz * 0.1);
    float choice = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
    vec2 edge = smoothstep(vec2(0.0), vec2(0.08),
                          min(fract(worldPos.xz * 0.1), 1.0 - fract(worldPos.xz * 0.1)));
    float coverage = (1.0 - step(0.33, choice)) * edge.x * edge.y;
    return coverage * smoothstep(0.48, 0.64, n) * astraRainFactor
         * astra_rain_response() * 0.85
         * astra_rain_exposure(skyLight) * smoothstep(0.86, 0.999, normal.y);
}
// ---------------------------------------------------------------------------
// Damp ground: the everywhere-effect that the puddle above is the exception to.
//
// The study's item E splits rain into two materials ("普通潮湿：轻微暗化、适度改变高光
// 或粗糙度" vs "真正积水：才出现明显天空和物体反射"), which is BSL's arrangement:
// rainPuddles.glsl:78-86 ApplyPuddleToMaterial darkens the albedo, raises smoothness
// and raises f0, and it does all three with the PUDDLE factor - in BSL the wet look and
// the standing water share one mask. Astra cannot do that, because its puddle mask is
// deliberately narrow (one third of ten-block cells, an edge fade inside each, plus a
// noise threshold) so that puddles stay sparse. Driving general wetness from it would
// leave most ground bone dry in the rain; driving the REFLECTION from a broad mask is
// what put a shiny sheet over everything.
//
// So the two are separated:
//   astra_puddle()     - sparse, sky-exposed, up-facing. Drives the REFLECTION.
//   astra_wet_ground() - broad and rain-envelope driven. Drives DARKENING and a small
//                        gloss change only, never a reflection by itself.
//
// skyLight still gates it, so a roofed or underground surface does not go glossy when
// it rains overhead. This value darkens the albedo and sets the gloss only; it is NOT
// what drives the reflection - that is astra_puddle(), which program/lit.fsh carries to
// program/deferred.fsh in colortex3.a. Keeping the two apart is the point of this pair.
// ---------------------------------------------------------------------------
float astra_wet_ground(vec3 normal, float skyLight) {
    float wet = clamp(astraRainFactor, 0.0, 1.0);
    // Up-facing surfaces hold water; a wall sheds it.
    float facing = smoothstep(0.55, 0.95, normal.y);
    return wet * facing * astra_rain_response()
         * smoothstep(0.25, 0.75, astra_rain_exposure(skyLight));
}
// Rain impact ripples.
//
// Astra generates its own flipbook rather than shipping anyone else's artwork: three
// 128x7680 sheets (sixty 128x128 frames) built by qa/tools/gen_rain_ripple.py from an
// explicit model of expanding, decaying circular wavelets, differentiated into a normal
// map. Local UV stays inside one frame; only the frame index selects time.
// Use the sparse first sheet, with a restrained second layer in heavy rain.
const float ASTRA_RIPPLE_TILE = 4.0;

vec2 astra_ripple_layer(sampler2D sheet, vec2 localUV, float frame) {
    vec2 uv = clamp(localUV, vec2(0.5 / 128.0), vec2(127.5 / 128.0));
    float current = floor(frame);
    vec2 a = vec2(uv.x, (mod(current, 60.0) + uv.y) / 60.0);
    vec2 b = vec2(uv.x, (mod(current + 1.0, 60.0) + uv.y) / 60.0);
    vec2 n = mix(textureLod(sheet, a, 0.0).rg,
                 textureLod(sheet, b, 0.0).rg, fract(frame)) * 2.0 - 1.0;
    // Remove the half-byte bias of the neutral RG8 normal.
    return sign(n) * max(abs(n) - vec2(1.0 / 255.0), vec2(0.0));
}
// graze = |dot(surface normal, view direction)|: 1 seen straight on, 0 at the horizon.
// BSL damps ripple normals at grazing angles for the same reason this does
// (rainPuddles.glsl:61-62, normalStrength = 0.35 * (1 - fresnel)): a shallow view
// compresses the whole ripple field into a few pixels, and the perturbation then reads
// as broken noise rather than as water. Reducing the amplitude there is the honest
// response - the ripples are still there, they simply stop being aliased - and it is
// the NORMAL that is damped, so the amount of water cannot change with the view.
//
// `puddleFraction` (0..1) is the standing-water coverage at this fragment. It scales the
// whole field, which is what carries the sparse mask to the reflection stage: the
// perturbation is full strength in standing water, faint on damp ground, and exactly
// zero on dry ground, so the deferred pass can read "is there water here" straight off
// the normal it already receives (program/lit.fsh, program/deferred.fsh).
//
// The existing footprint filter is unchanged and still removes rings the screen cannot
// resolve, and the second sheet still only joins in heavy rain.
vec2 astra_rain_ripple(vec3 worldPos, float strength, float footprint, float graze,
                       float puddleFraction) {
    strength *= smoothstep(0.01, 0.8, astraRainFactor) * clamp(puddleFraction, 0.0, 1.0);
    vec2 p = worldPos.xz / ASTRA_RIPPLE_TILE;
    float phase = fract(sin(dot(floor(p), vec2(127.1, 311.7))) * 43758.5453);
    float frame = mod(frameTimeCounter * 0.65, 1.0) * 60.0 + phase * 60.0;
    vec2 uv = fract(p);
    vec2 n = astra_ripple_layer(astraRipple1, uv, frame);
    n += astra_ripple_layer(astraRipple2, uv, frame + 23.0)
       * smoothstep(0.75, 1.0, strength) * 0.15;
    // Fade unresolved rings and tile boundaries rather than aliasing across frames.
    vec2 edge = smoothstep(vec2(0.0), vec2(0.06), min(uv, 1.0 - uv));
    float resolved = 1.0 - smoothstep(0.015, 0.08, footprint);
    float grazing = mix(0.42, 1.0, clamp(graze, 0.0, 1.0));
    return n * strength * 0.28 * edge.x * edge.y * resolved * grazing;
}
// Same cloud field as the visible layer; ray starts at the receiving world point.
float astra_cloud_transmission(vec3 worldPos, vec3 lightDir) {
    #if CLOUD_MODE != CLOUD_PLANAR
    // Only the procedural sheet has a density field to project.
    return 1.0;
    #else
    if (lightDir.y <= 0.01) return 0.0;
    float t = (ASTRA_CLOUD_ALTITUDE-worldPos.y)/lightDir.y;
    if(t <= 0.0) return 1.0;
    vec3 hit = worldPos + lightDir*t;
    float n = astra_cloud_noise(hit, ASTRA_CLOUD_ALTITUDE);
    float threshold = 0.21 + mix(0.20,-0.20,CLOUD_COVERAGE*0.01) - 0.28*astraRainFactor;
    float cloud = smoothstep(threshold-0.025,threshold+0.025,n);
    return mix(1.0, 0.07, cloud);
    #endif
}
#endif
