#ifndef ASTRA_PROGRAM_WATER_GLSL
#define ASTRA_PROGRAM_WATER_GLSL
// SC-34 follow-up: colour, depth, interface side and path length are inseparable.
// Above water uses Steadfast Fresnel and refraction; underwater uses Solas
// normal/Fresnel/alpha composition, adapted to the existing scene targets.
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot:
// historical translucent.glsl composition adaptation. Source at
// _analysis/Steadfast-0.8.0/shaders/environment/lighting/translucent.glsl.
// This derivative retains GPL-3.0-or-later and its Section 7 terms; see
// Astra/LICENSE and THIRD-PARTY.md. Dielectric and path reconstruction below
// remain for non-water transparent surfaces.
#include "/global/water/surface.glsl"
#include "/global/water/raytrace.glsl"
#include "/global/water/refraction.glsl"
uniform sampler2D colortex4;

// A filtered scene lookup transports each tap BEFORE combining it. Refractive
// silhouettes must never associate bilinear RGB with the farthest of four depths.
// A reflection cone uses four footprints and may span different visible objects.
//
// SC-35: scene queries pair the deferred opaque colour copy with depthtex1, the
// depth snapshot that excludes translucent geometry. depthtex0 includes the
// translucent layer and can therefore return the water surface being shaded.
// Returns a soft validity in [0,1]: taps crossing the interface fade out over a
// two-centimetre reconstruction band instead of a binary cut. A rejected
// refracted hit blends to the unshifted opaque path in astra_water(), never
// directly to a saturated deep-water colour.
float water_side_acceptance(float side, vec3 point, vec3 origin, vec3 faceNormal) {
    return smoothstep(-0.02, 0.02, side * dot(point - origin, faceNormal));
}
float water_sample_path(vec2 uv, vec3 origin, vec3 faceNormal, bool reflected,
                        bool inWater, float radius, float skylight, out vec3 radiance) {
    radiance = vec3(0.0);
    ivec2 size = textureSize(depthtex1, 0);
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) return 0.0;
    ivec2 anchorPixel = ivec2(uv * vec2(size));
    float anchorDepth = texelFetch(depthtex1, anchorPixel, 0).r;
    if (anchorDepth >= 0.999999) return 0.0;
    vec3 anchor = screen_view(vec3((vec2(anchorPixel) + 0.5) / vec2(size), anchorDepth));
    float side = reflected ? 1.0 : -1.0;
    float anchorSide = water_side_acceptance(side, anchor, origin, faceNormal);
    if (anchorSide <= 0.0) return 0.0;
    vec3 endpoint = vec3(0.0);
    float weights = 0.0;
    float sideSum = 0.0;
    int footprints = reflected ? 4 : 1;
    for (int cone = 0; cone < 4; ++cone) {
        if (cone >= footprints) break;
        vec2 offset = reflected ? vec2((cone & 1) == 0 ? -radius : radius,
                                      (cone & 2) == 0 ? -radius : radius) : vec2(0.0);
        vec2 location = uv * vec2(size) - 0.5 + offset;
        ivec2 corner = ivec2(floor(location));
        vec2 f = fract(location);
        for (int y = 0; y < 2; ++y) {
            for (int x = 0; x < 2; ++x) {
                ivec2 pixel = corner + ivec2(x,y);
                if (any(lessThan(pixel, ivec2(0))) || any(greaterThanEqual(pixel, size))) continue;
                float depth = texelFetch(depthtex1, pixel, 0).r;
                if (depth >= 0.999999) {
                    if (reflected && !inWater) {
                        // Sky holes between leaves are part of a reflection
                        // footprint. Renormalizing them away expands thin leaves
                        // and makes the whole cone jump when its last leaf exits.
                        vec2 sw = mix(vec2(1.0) - f, f, vec2(x,y));
                        float weight = sw.x * sw.y;
                        radiance += texelFetch(colortex4, pixel, 0).rgb * weight;
                        endpoint += anchor * weight;
                        weights += weight;
                        sideSum += weight;
                    }
                    continue;
                }
                vec3 point = screen_view(vec3((vec2(pixel) + 0.5) / vec2(size), depth));
                float accept = water_side_acceptance(side, point, origin, faceNormal);
                if (accept <= 0.0) continue;
                vec2 sw = mix(vec2(1.0) - f, f, vec2(x,y));
                float weight = sw.x * sw.y * accept;
                vec3 color = texelFetch(colortex4, pixel, 0).rgb;
                if (inWater) color = isEyeInWater == 0
                    ? water_surface_medium(color, dot(origin - point, faceNormal))
                    : water_medium(color, length(point - origin), astra_water_incident(skylight));
                radiance += color * weight;
                endpoint += point * weight;
                weights += weight;
                sideSum += sw.x * sw.y;
            }
        }
    }
    float validity;
    if (weights < 1e-5) {
        // Every footprint tap failed the interface-side rejection: transport the
        // nearest-depth anchor alone instead of jumping to the deep fallback.
        vec3 color = texelFetch(colortex4, anchorPixel, 0).rgb;
        if (inWater) color = isEyeInWater == 0
            ? water_surface_medium(color, dot(origin - anchor, faceNormal))
            : water_medium(color, length(anchor - origin), astra_water_incident(skylight));
        radiance = color;
        endpoint = anchor;
        validity = anchorSide;
    } else {
        radiance /= weights;
        endpoint /= weights;
        validity = clamp(weights / max(sideSum, 1e-5), 0.0, 1.0);
    }
    if (!inWater && isEyeInWater == 0) {
        vec4 fog = astra_fog(view_player(endpoint - origin), skylight);
        radiance = mix(radiance, fog.rgb, fog.a);
    }
    return validity;
}

// Solas underwater interface composition, adapted to Astra's linear scene copy.
// The reference sky/SSR implementations are not replaced by this adapter.
vec4 solas_underwater_interface(vec3 color, vec3 viewPos, vec3 normal, vec3 faceNormal, float skylight) {
    vec3 incident = normalize(viewPos);
    float fresnel = clamp(1.0 + dot(normal, incident), 0.0, 0.5);
    vec3 surface = pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));
    vec3 reflection = mix(surface, pow(max(astra_reflection_sky(view_player(reflect(incident, normal)), 0.0),
                                        vec3(0.0)), vec3(1.0 / 2.2)), skylight);
    #ifdef SCREENSPACE_REFLECTIONS
        vec4 hit = water_raytrace(depthtex1, viewPos, reflect(incident, normal), faceNormal);
        if (hit.a > 0.0) {
            vec3 scene = pow(max(texture(colortex4, hit.xy).rgb, vec3(0.0)), vec3(1.0 / 2.2));
            reflection = mix(reflection, scene, hit.a);
        }
    #endif
    surface = mix(surface, reflection, fresnel);
    float alpha = mix(0.70, 1.0, fresnel);
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    #ifdef SCREENSPACE_REFRACTION
        // Solas composite4: normal displacement, FOV and eight-block minimum.
        vec2 displacement = (normal.xy - faceNormal.xy) * (0.6 * REFRACTION_STRENGTH * 0.01);
        displacement *= vec2(viewHeight / viewWidth, 1.0) * (gbufferProjection[1][1] / 1.37) / max(length(viewPos), 8.0);
        vec2 candidate = clamp(uv + displacement, vec2(0.0), vec2(1.0));
        if (water_depth_range(depthtex1, candidate).x >= gl_FragCoord.z) uv = candidate;
    #endif
    vec3 background = pow(max(texture(colortex4, uv).rgb, vec3(0.0)), vec3(1.0 / 2.2));
    return vec4(pow(mix(background, surface, alpha), vec3(2.2)), 1.0);
}

vec4 astra_water(vec3 color, float alpha, vec3 playerPos, vec3 viewPos,
                 vec3 normal, float roughness, float skylight, bool water, vec3 geometricNormal) {
    vec3 incidentWorld = normalize(view_player(viewPos));
    vec3 geometric = normalize(geometricNormal);
    if (dot(incidentWorld, geometric) > 0.0) geometric = -geometric;
    if (dot(normal, geometric) < 0.0) normal = -normal;
    vec3 incident = normalize(viewPos);
    vec3 viewNormal = normalize(player_view(normal));
    vec3 viewGeometric = normalize(player_view(geometric));
    bool belowWater = isEyeInWater == 1;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        if (water && belowWater) return solas_underwater_interface(color, viewPos, viewNormal, viewGeometric, skylight);
    #endif
    float eta = belowWater && water ? WATER_IOR : 1.0 / WATER_IOR;
    bool totalReflection;
    float fresnel = water_fresnel(max(dot(-incident, viewNormal), 0.0), eta, totalReflection);
    if (water && !belowWater) {
        fresnel = (0.1 + 0.9 * pow(clamp(1.0 + dot(incident, viewNormal), 0.0, 1.0), 5.0)) * skylight;
    }
    vec3 reflectedRay = reflect(incident, viewNormal);
    if (dot(reflectedRay, viewGeometric) <= 0.0) reflectedRay = reflect(incident, viewGeometric);
    vec3 reflectedWorld = normalize(view_player(reflectedRay));
    vec3 reflection = vec3(0.0);
    float reflectionWeight = 0.0;
    #ifdef SCREENSPACE_REFLECTIONS
        vec4 hit = water_raytrace(depthtex1, viewPos, reflectedRay, viewGeometric);
        if (hit.a > 0.0) {
            vec3 reflected;
            vec3 hitPos = screen_view(hit.xyz);
            float radius = clamp(roughness * roughness * length(hitPos-viewPos) * viewHeight
                               / max(-hitPos.z, 0.1), 0.0, 12.0);
            reflectionWeight = hit.a * water_sample_path(hit.xy, viewPos, viewGeometric,
                                          true, belowWater, radius, skylight, reflected);
            reflection = reflected * reflectionWeight;
        }
    #endif
    if (reflectionWeight < 1.0) {
        vec3 fallback = belowWater
            ? astra_water_segment(vec3(0.0), playerPos, playerPos + reflectedWorld * 96.0, skylight)
            : astra_reflection_sky(reflectedWorld, roughness) * skylight;
        reflection += fallback * (1.0 - reflectionWeight);
    }
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec3 transmitted = vec3(0.0);
    if (!totalReflection) {
        vec3 refractedRay = refract(incident, viewNormal, eta);
        vec3 transmittedWorld = normalize(view_player(refractedRay));
        float valid = 0.0;
        bool airMiss = false;
        #ifdef SCREENSPACE_REFRACTION
            // Steadfast advances by background depth with the perturbed direction.
            vec2 refractedUV = water_refracted_uv(depthtex1, viewPos, viewNormal - viewGeometric);
            valid = water_sample_path(refractedUV, viewPos, viewGeometric, false,
                                     water && !belowWater, 0.0, skylight, transmitted);
            if (belowWater && valid <= 0.0) {
                airMiss = any(lessThan(refractedUV, vec2(0.0)))
                       || any(greaterThanEqual(refractedUV, vec2(1.0)));
                if (!airMiss) {
                    ivec2 size = textureSize(depthtex1, 0);
                    airMiss = texelFetch(depthtex1, ivec2(refractedUV * vec2(size)), 0).r >= 0.999999;
                }
            }
        #endif
        vec3 deepFallback = belowWater
            ? astra_water_air_sky(transmittedWorld)
            : astra_water_segment(vec3(0.0), playerPos,
                                  playerPos + transmittedWorld * 96.0, skylight);
        vec3 geometricFallback = deepFallback;
        // Geometric misses return to the entire unshifted optical path. This is
        // a fallback only: it must not replace a valid refracted path merely
        // because its own confidence is numerically larger.
        if (!airMiss) {
            vec3 straight = vec3(0.0);
            float straightValid = water_sample_path(uv, viewPos, viewGeometric, false,
                                     water && !belowWater, 0.0, skylight, straight);
            geometricFallback = mix(deepFallback, straight, straightValid);
        }
        transmitted = mix(geometricFallback, transmitted, valid);
    }
    color = mix(transmitted, reflection, fresnel);
    if (!water) color = mix(color, color * clamp(color + vec3(0.5), 0.0, 1.0), 0.08);
    // Exactly one eye-to-interface leg. Solar scattering for this leg is added
    // by composite/final, bounded by depthtex0, after translucent geometry.
    color = astra_apply_medium(color, playerPos, skylight);
    return vec4(max(color, vec3(0.0)), 1.0);
}
#endif
