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
    int footprints = reflected && radius > 0.0 ? 4 : 1;
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
    // From below, reflectance climbs toward total internal reflection at grazing angles.
    // The reference floors this at 0.5 and the user reported the kelp reflection as "不太
    // 明显", so the ceiling is raised to let the reflected underwater scene through.
    float fresnel = clamp(1.0 + dot(normal, incident), 0.0, 0.88);
    vec3 surface = pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));
    vec3 reflection = mix(surface, solas_water_sky(view_player(reflect(incident, normal))), skylight);
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
        // A hard if() here switched the whole ray between displaced and undisplaced per
        // pixel, which reads as shattered/torn water when looking up at the surface from
        // below (the user's "水下看水面的破碎多", explicitly not a wave-amplitude issue).
        // Blending across the depth test keeps the displaced path but removes the tear.
        float candidateDepth = water_depth_range(depthtex1, candidate).x;
        float accept = smoothstep(gl_FragCoord.z - 0.0015, gl_FragCoord.z + 0.0015, candidateDepth);
        uv = mix(uv, candidate, accept);
    #endif
    vec3 background = pow(max(texture(colortex4, uv).rgb, vec3(0.0)), vec3(1.0 / 2.2));
    return vec4(pow(mix(background, surface, alpha), vec3(2.2)), 1.0);
}

vec4 astra_water(vec3 color, float alpha, vec3 playerPos, vec3 viewPos,
                 vec3 normal, float roughness, float skylight, bool water,
                 bool ice, vec3 geometricNormal) {
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
        // Preserve the bed instead of imposing a ten-percent sky coating.
        fresnel = (0.025 + 0.975 * pow(clamp(1.0 + dot(incident, viewNormal), 0.0, 1.0), 5.0)) * skylight;
    }
    vec3 reflectedRay = reflect(incident, viewNormal);
    if (dot(reflectedRay, viewGeometric) <= 0.0) reflectedRay = reflect(incident, viewGeometric);
    vec3 reflectedWorld = normalize(view_player(reflectedRay));
    // Ice is a separate material, so it gets a separate surface response: its own
    // wider, weaker solar glint instead of water's, and a twilight-aware reflection
    // tint so it joins the same sunrise/sunset lighting as the terrain beside it
    // rather than staying a neutral sky mirror. Its texture still leads - this is a
    // glint on top of the lit cel, not a coating over it.
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    if (ice && !belowWater) {
        float iceAlign = max(dot(reflectedWorld, worldSunVector), 0.0);
        float iceSharpness = mix(72.0, 30.0, clamp(roughness * 3.0, 0.0, 1.0));
        float iceGlint = pow(iceAlign, iceSharpness) * solas_sun_visibility();
        if (iceGlint > 0.002) {
            // gated on the sun's own elevation, exactly as the water glint is: a
            // sunset glint on ice is a real thing, a midnight one is not.
            iceGlint *= smoothstep(0.0, 0.10, worldSunVector.y);
            vec3 iceGlintColor = mix(vec3(1.00, 0.97, 0.92), vec3(1.30, 0.86, 0.46),
                                     astra_twilight_strength());
            color += iceGlintColor * (iceGlint * 0.22 * skylight);
        }
    }
    #endif
    if (!water) {
        // Ice retains its lit texture; alpha blending supplies transmission.
        // It needs neither the fluid refraction march nor its absorption.
        vec3 iceReflection=astra_reflection_sky(reflectedWorld,roughness)*skylight;
        color=mix(color,iceReflection,clamp(fresnel,0.035,0.28));
        return vec4(max(astra_apply_medium(color,playerPos,skylight),vec3(0.0)),
                    clamp(alpha,0.86,0.96));
    }
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
        vec3 fallback;
        if (belowWater) {
            fallback=astra_water_segment(vec3(0.0),playerPos,playerPos+reflectedWorld*96.0,skylight);
        } else {
            // One atmosphere for the visible sky and reflected sky, all day.
            fallback=astra_reflection_sky(reflectedWorld,roughness)*skylight;
        }
        reflection += fallback * (1.0 - reflectionWeight);
    }
    // Solar glint. waterRef_SkyColor carries the reference's atmospheric Mie lobe, which
    // is broad, so on the surface the sun reads as a weak wash (user: "太阳在水面上的反射
    // 有点弱"). This adds the narrow specular lobe: sharp when the waves are smooth, wider
    // as roughness grows, and gated by the sun's elevation.
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        if (water && !belowWater) {
            float sunAlign = max(dot(reflectedWorld, worldSunVector), 0.0);
            // Softer and wider than the first attempt: at 2.6x with a 340 exponent this was
            // a blinding point. A gentler lobe still reads as the sun on the water without
            // searing the view.
            float sharpness = mix(150.0, 42.0, clamp(roughness * 6.0, 0.0, 1.0));
            float glint = pow(sunAlign, sharpness) * solas_sun_visibility();
            // Complementary's solar highlight is shadow-gated. A shaded bank
            // must not get the same bright reflection stripe as open water.
            if (glint>0.002) {
                vec3 source=normalize(view_player(lightVector));
                vec3 sunShadow=shadow_map_position(playerPos,geometric,dot(geometric,source));
                vec3 visibility=surface_shadow_light(playerPos,sunShadow,skylight);
                glint*=dot(visibility,vec3(0.2126,0.7152,0.0722));
            }
            // The warm light belongs in the REFLECTION, not spread over the river
            // surface. The reflected sky already carries the sunrise lobe
            // (astra_sky_radiance -> astra_twilight_sky), so a sunrise river warms
            // through the sky path by itself. This lobe is the direct solar image on the
            // water, which is why it may take the sun's own colour - and the sun's
            // colour is already desaturated by astra_twilight_highlights() (twilight.glsl),
            // which preserves luminance while compressing the peak. Reusing that here
            // instead of a private (1.45, 0.83, 0.30) keeps ONE definition of "how warm
            // the twilight sun is" and stops the glint from carrying more red than the
            // sun it is a reflection of.
            vec3 glintColor=mix(vec3(1.00,0.96,0.88),
                                astra_twilight_highlights(astra_twilight_sunlight()),
                                astra_twilight_strength());
            // 0.85 -> 0.72: the glint is the narrowest, highest-energy term on the
            // surface, so it is the one that should lose energy at dawn rather than
            // gain it on top of a sky that is already bright.
            reflection += glintColor * glint * skylight * mix(0.72,0.52,astra_twilight_strength());
        }
    #endif
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
        // A fully accepted path needs no fallback scene/medium evaluation.
        if (valid < 1.0) {
            vec3 straight = vec3(0.0);
            float straightValid=0.0;
            if (!airMiss)
                straightValid=water_sample_path(uv,viewPos,viewGeometric,false,
                                               !belowWater,0.0,skylight,straight);
            vec3 geometricFallback=straight;
            if (straightValid < 1.0) {
                vec3 deepFallback=belowWater
                    ? astra_water_air_sky(transmittedWorld)
                    : astra_water_segment(vec3(0.0),playerPos,
                                          playerPos+transmittedWorld*96.0,skylight);
                geometricFallback=mix(deepFallback,straight,straightValid);
            }
            transmitted=mix(geometricFallback,transmitted,valid);
        }
    }
    color = mix(transmitted, reflection, fresnel);
    // Exactly one eye-to-interface leg. Solar scattering for this leg is added
    // by composite/final, bounded by depthtex0, after translucent geometry.
    color = astra_apply_medium(color, playerPos, skylight);
    return vec4(max(color, vec3(0.0)), 1.0);
}
#endif
