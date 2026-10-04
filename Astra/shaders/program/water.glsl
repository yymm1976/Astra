#ifndef ASTRA_PROGRAM_WATER_GLSL
#define ASTRA_PROGRAM_WATER_GLSL
// SC-34 follow-up: colour, depth, interface side and path length are inseparable.
// Above water uses Steadfast Fresnel and refraction; underwater retains Solas
// waves/colour domain with an ITT-inspired refracted sky and critical-angle window.
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
// A reflection cone uses a centre-inclusive Gaussian footprint and may span
// different visible objects. Empty taps keep their sky-fallback coverage.
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

// Absorption depth for a surface seen from air: the perpendicular distance from the
// water face's OWN plane to the background hit. On a top face that is the real water
// column and unbounded; on a side face the same dot is just the camera-to-background
// distance, so looking across a canal absorbed it as if the whole view were water.
// A water block only renders a side face when the neighbour along that normal is not
// water, so the slab along that normal is at most one block. Steadfast 0.8.0 bounds the
// same quantity with a skylight proxy (absorption_refraction.glsl: (1 - skylight/16)
// blocks); this reaches the same range from geometry alone, without a third buffer.
// faceNormal is the unit, camera-facing geometric normal in view axes.
// topSurface is classified once for the complete filtering footprint.
float water_surface_absorption_depth(vec3 origin, vec3 point, vec3 faceNormal, bool topSurface) {
    float depth = dot(origin - point, faceNormal);
    return topSurface ? depth : min(depth, 1.0);
}
float water_sample_path(vec2 uv, vec3 origin, vec3 faceNormal, bool reflected,
                        bool inWater, float radius, float skylight,
                        float knownAnchorDepth, out vec3 radiance) {
    radiance = vec3(0.0);
    ivec2 size = textureSize(depthtex1, 0);
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) return 0.0;
    ivec2 anchorPixel = ivec2(uv * vec2(size));
    // SSR supplies the accepted depth at this exact nearest texel. Other paths
    // pass a negative sentinel and retain their own paired depth lookup.
    float anchorDepth = knownAnchorDepth >= 0.0
        ? knownAnchorDepth : texelFetch(depthtex1, anchorPixel, 0).r;
    if (anchorDepth >= 0.999999) return 0.0;
    vec3 anchor = screen_view(vec3((vec2(anchorPixel) + 0.5) / vec2(size), anchorDepth));
    float side = reflected ? 1.0 : -1.0;
    float anchorSide = water_side_acceptance(side, anchor, origin, faceNormal);
    if (anchorSide <= 0.0) return 0.0;
    vec3 anchorColor = texelFetch(colortex4, anchorPixel, 0).rgb;
    vec3 mediumIncident=vec3(0.0);
    if(inWater) mediumIncident=astra_water_incident(skylight);
    // All contributors share the same geometric interface and absorption rule.
    bool topSurface=inWater && isEyeInWater==0 && view_player(faceNormal).y>0.9;
    // The centre footprint always includes this nearest texel. Transport its
    // unchanged colour/path once, including any repeats in the wider cone.
    vec3 anchorRadiance = anchorColor;
    if (inWater) anchorRadiance = isEyeInWater == 0
        ? water_surface_medium(anchorColor,
            water_surface_absorption_depth(origin, anchor, faceNormal, topSurface),
            mediumIncident)
        : water_medium(anchorColor, length(anchor - origin), mediumIncident);
    vec3 endpoint = vec3(0.0);
    float weights = 0.0;
    float sideSum = 0.0;
    // Four isolated corners leave the middle of a wide cone completely unsampled.
    // The weighted cross/grid includes its centre and transitions continuously
    // as the projected footprint grows. Subpixel cones use one footprint.
    #if WATER_EFFECT_QUALITY == 0
    const int maxFootprints = 1;
    #elif WATER_EFFECT_QUALITY == 2
    const int maxFootprints = 9;
    #else
    const int maxFootprints = 5;
    #endif
    int footprints = reflected && radius > 0.35 ? maxFootprints : 1;
    for (int cone = 0; cone < 9; ++cone) {
        if (cone >= footprints) break;
        ivec2 node = ivec2(cone % 3,cone / 3)-1;
        // A centre plus four axis neighbours retain a continuous symmetric
        // footprint. sqrt(1.5) compensates the cross kernel's smaller variance.
        if(footprints == 5) {
            if(cone == 0) node=ivec2(0);
            else if(cone == 1) node=ivec2(-1,0);
            else if(cone == 2) node=ivec2(1,0);
            else if(cone == 3) node=ivec2(0,-1);
            else node=ivec2(0,1);
        }
        float spread = footprints == 5 ? 0.91855865 : 0.75;
        vec2 offset = footprints > 1 ? vec2(node)*radius*spread : vec2(0.0);
        float kernel = footprints > 1 ? float((node.x==0 ? 2 : 1)*(node.y==0 ? 2 : 1)) : 1.0;
        vec2 location = uv * vec2(size) - 0.5 + offset;
        ivec2 corner = ivec2(floor(location));
        vec2 f = fract(location);
        for (int y = 0; y < 2; ++y) {
            for (int x = 0; x < 2; ++x) {
                ivec2 pixel = corner + ivec2(x,y);
                vec2 sw = mix(vec2(1.0)-f,f,vec2(x,y));
                float geometricWeight = sw.x*sw.y*kernel;
                if (geometricWeight <= 0.0) continue;
                // Renormalizing rejected reflection taps to full coverage made
                // leaf silhouettes jump. Missing coverage belongs to the fallback.
                if (reflected) sideSum += geometricWeight;
                if (any(lessThan(pixel, ivec2(0))) || any(greaterThanEqual(pixel, size))) continue;
                // The nearest anchor also belongs to the central bilinear footprint.
                // Reuse only an identical texel; all other corners retain their own path.
                bool anchorSample = all(equal(pixel, anchorPixel));
                float depth = anchorSample ? anchorDepth : texelFetch(depthtex1, pixel, 0).r;
                if (depth >= 0.999999) {
                    if (reflected && !inWater) {
                        // Sky holes between leaves are part of a reflection
                        // footprint. Renormalizing them away expands thin leaves
                        // and makes the whole cone jump when its last leaf exits.
                        float weight = geometricWeight;
                        radiance += texelFetch(colortex4, pixel, 0).rgb * weight;
                        endpoint += anchor * weight;
                        weights += weight;
                    }
                    continue;
                }
                vec3 point = anchorSample ? anchor
                    : screen_view(vec3((vec2(pixel) + 0.5) / vec2(size), depth));
                float accept = anchorSample ? anchorSide
                    : water_side_acceptance(side, point, origin, faceNormal);
                if (accept <= 0.0) continue;
                float weight = geometricWeight * accept;
                vec3 color = anchorSample ? anchorRadiance : texelFetch(colortex4, pixel, 0).rgb;
                if (inWater && !anchorSample) color = isEyeInWater == 0
                    ? water_surface_medium(color,
                        water_surface_absorption_depth(origin, point, faceNormal, topSurface),
                        mediumIncident)
                    : water_medium(color, length(point - origin), mediumIncident);
                radiance += color * weight;
                endpoint += point * weight;
                weights += weight;
                if (!reflected) sideSum += geometricWeight;
            }
        }
    }
    float validity;
    if (weights < 1e-5) {
        // Every footprint tap failed the interface-side rejection: transport the
        // nearest-depth anchor alone instead of jumping to the deep fallback.
        radiance = anchorRadiance;
        endpoint = anchor;
        validity = anchorSide;
    } else {
        radiance /= weights;
        endpoint /= weights;
        validity = clamp(weights / max(sideSum, 1e-5), 0.0, 1.0);
    }
    if (!inWater && (isEyeInWater == 0 || water_is_thin_sheet())) {
        #ifdef ASTRA_VOLUME_FOG
        // Preserve the interface's altitude and position for this OTHER air
        // leg. Treating endpoint-origin as a camera endpoint moves the volume
        // back to the eye and evaluates a different density/cloud-shadow field.
        if (blindness <= 0.0001) {
            radiance = astra_volume_apply(radiance,
                astra_volume_path_medium(view_camera_relative(origin), view_camera_relative(endpoint)));
        } else
        #endif
        {
            vec4 fog = astra_fog(view_player(endpoint - origin), skylight);
            radiance = mix(radiance, fog.rgb, fog.a);
        }
    }
    return validity;
}

float water_sample_path(vec2 uv, vec3 origin, vec3 faceNormal, bool reflected,
                        bool inWater, float radius, float skylight, out vec3 radiance) {
    return water_sample_path(uv, origin, faceNormal, reflected, inWater,
                             radius, skylight, -1.0, radiance);
}

// ITT composite1/2: a water-to-air refracted sky window closes at total internal
// reflection. Retain Solas' colour domain, but use Astra's dielectric equations
// rather than its former capped Fresnel and fixed surface opacity.
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
vec4 astra_vertical_water_interface(vec3 playerPos, vec3 viewPos, vec3 normal, vec3 faceNormal,
                                    float skylight, float roughness) {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    #ifdef SCREENSPACE_REFRACTION
        uv = water_refracted_uv(depthtex1, viewPos, normal - faceNormal, uv);
    #endif
    vec3 transmitted;
    // Behind a falling sheet is air, not an arbitrarily deep water column.
    // Keep the existing paired colour/depth footprint and shoreline rejection.
    float validity = water_sample_path(uv, viewPos, faceNormal, false,
                                      false, 0.0, skylight, transmitted);
    if (validity < 1.0)
        transmitted = mix(max(textureLod(colortex4, uv, 0.0).rgb, vec3(0.0)), transmitted, validity);
    bool submerged = isEyeInWater == 1;
    if (!submerged || water_is_thin_sheet()) {
        float waterLength = submerged ? min(length(viewPos), 1.0) : 1.0;
        transmitted = water_surface_medium(transmitted, waterLength, astra_water_incident(skylight));
    }
    // Both sheen and reflected radiance are zero without sky access.
    // Keep the transported background and the same camera medium.
    if (skylight <= 0.0)
        return vec4(astra_apply_medium(max(transmitted, vec3(0.0)), playerPos, skylight), 1.0);
    // Turbulent vertical block sheets use a small continuous sheen rather than
    // a planar critical-angle window. The horizontal ocean interface below
    // keeps its exact dielectric response and total reflection.
    vec3 incident = normalize(viewPos);
    float noV = clamp(dot(-incident, normal), 0.0, 1.0);
    float sheen = (0.025 + 0.075 * pow5(1.0 - noV)) * skylight;
    vec3 reflectedRay = reflect(incident, normal);
    if (dot(reflectedRay, faceNormal) <= 0.0) reflectedRay = reflect(incident, faceNormal);
    vec3 reflection = astra_reflection_sky(normalize(view_player(reflectedRay)), max(roughness, 0.08));
    reflection = astra_scene_highlights(reflection) * skylight;
    vec3 result = max(mix(transmitted, reflection, sheen), vec3(0.0));
    return vec4(astra_apply_medium(result, playerPos, skylight), 1.0);
}

vec4 astra_underwater_interface(vec3 litWater, vec3 viewPos, vec3 normal, vec3 faceNormal,
                                float skylight, float angularFootprint) {
    vec3 incident = normalize(viewPos);
    bool totalReflection;
    float fresnel = water_fresnel(max(dot(-incident,normal),0.0),WATER_IOR,totalReflection);
    vec3 reflectedRay = reflect(incident, normal);
    if (dot(reflectedRay,faceNormal) <= 0.0)
        reflectedRay = reflect(incident,faceNormal);
    vec3 waterIncident = astra_water_incident(skylight);
    // A missed underwater reflection sees the water medium, not an air sky
    // below the horizon. Only the secondary reflected leg is transported here;
    // the camera-to-interface leg still gets its shared composite fog once.
    vec3 reflection = vec3(0.0);
    float reflectionWeight = 0.0;
    if (fresnel > 0.0) {
        vec4 hit = vec4(0.0);
        #ifdef SCREENSPACE_REFLECTIONS
            hit = water_raytrace(depthtex1, viewPos, reflectedRay, faceNormal);
        #endif
        if (hit.a > 0.0) {
            vec3 hitPoint = screen_view(hit.xyz);
            vec3 radiance = water_medium(max(textureLod(colortex4,hit.xy,0.0).rgb,vec3(0.0)),
                                         length(hitPoint-viewPos),waterIncident);
            reflection = pow(max(radiance,vec3(0.0)),vec3(1.0/2.2));
            reflectionWeight = hit.a;
        }
    }
    // Full-confidence geometry owns the reflected leg. Only misses / partial
    // hits need the long-water fallback and its gamma-domain conversion.
    if (reflectionWeight < 1.0) {
        vec3 fallback = pow(max(water_medium(litWater,48.0,waterIncident),vec3(0.0)),vec3(1.0/2.2));
        reflection = mix(fallback,reflection,reflectionWeight);
    }
    if (totalReflection) return vec4(pow(max(reflection,vec3(0.0)),vec3(2.2)),1.0);
    vec3 refractedRay = refract(incident,normal,WATER_IOR);
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    #ifdef SCREENSPACE_REFRACTION
    #if REFRACTION_STRENGTH > 0
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
    #endif
    vec3 background;
    // Like ITT, sky transmission follows the actual refracted direction. This
    // compresses the sky into Snell's window instead of painting sky everywhere.
    // Geometry retains the depth-guarded screen refraction above.
    if (water_depth_range(depthtex1,uv).x >= 0.999999) {
        vec3 skyDirection = normalize(view_player(refractedRay));
        vec3 sky;
        #if CLOUD_MODE == CLOUD_PLANAR
        // The same current-frame sky/cloud environment used by water above.
        // Near the critical angle refraction magnifies the angular footprint.
        float skyRoughness = clamp(angularFootprint*WATER_IOR
            / max(abs(dot(refractedRay,normal)),0.05),0.0,0.20);
        sky = astra_cached_reflection_sky(skyDirection,skyRoughness);
        #else
        sky = astra_overworld_sky(skyDirection);
        #endif
        background = pow(max(sky,vec3(0.0)),vec3(1.0/2.2));
    } else {
        // A sky ray above used to read and convert the opaque background too,
        // then overwrite it. Geometry alone needs this scene lookup.
        background = pow(max(textureLod(colortex4, uv, 0.0).rgb, vec3(0.0)), vec3(1.0 / 2.2));
    }
    return vec4(pow(max(mix(background,reflection,fresnel),vec3(0.0)),vec3(2.2)),1.0);
}
#endif

vec4 astra_water(vec3 color, float alpha, vec3 playerPos, vec3 viewPos,
                 vec3 normal, float roughness, float skylight, bool water,
                 bool ice, vec3 geometricNormal, float reflectionAngularFootprint) {
    // The caller evaluates this footprint before divergent material flow.
    vec3 incidentWorld = normalize(view_player(viewPos));
    vec3 geometric = normalize(geometricNormal);
    if (dot(incidentWorld, geometric) > 0.0) geometric = -geometric;
    if (dot(normal, geometric) < 0.0) normal = -normal;
    vec3 incident = normalize(viewPos);
    vec3 viewNormal = normalize(player_view(normal));
    vec3 viewGeometric = normalize(player_view(geometric));
    bool belowWater = isEyeInWater == 1;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        if (water && abs(geometric.y) <= 0.9)
            return astra_vertical_water_interface(playerPos, viewPos, viewNormal, viewGeometric, skylight, roughness);
        if (water && belowWater) return astra_underwater_interface(color,viewPos,viewNormal,viewGeometric,
                                                                  skylight,reflectionAngularFootprint);
    #endif
    float eta = belowWater && water ? WATER_IOR : 1.0 / WATER_IOR;
    bool totalReflection = false;
    float fresnel;
    if (water && !belowWater) {
        // Air-to-water cannot reach total internal reflection. This branch
        // owns the existing Schlick response, so no dielectric solve is needed.
        // Preserve the bed instead of imposing a ten-percent sky coating.
        fresnel = (0.025 + 0.975 * pow5(clamp(1.0 + dot(incident, viewNormal), 0.0, 1.0))) * skylight;
    } else
        fresnel = water_fresnel(max(dot(-incident, viewNormal), 0.0), eta, totalReflection);
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
        iceReflection *= astra_environment_reflection_gain(roughness,
                              max(dot(-incident, viewNormal), 0.0), 0.0204);
        color=mix(color,iceReflection,clamp(fresnel,0.035,0.28));
        return vec4(max(astra_apply_medium(color,playerPos,skylight),vec3(0.0)),
                    clamp(alpha,0.86,0.96));
    }
    vec3 reflection = vec3(0.0);
    float reflectionWeight = 0.0;
    #ifdef SCREENSPACE_REFLECTIONS
    if (fresnel > 0.0) {
        vec4 hit = water_raytrace(depthtex1, viewPos, reflectedRay, viewGeometric);
        vec3 reflected = vec3(0.0);
        vec3 hitPos = vec3(0.0);
        if (hit.a > 0.0) {
            hitPos = screen_view(hit.xyz);
            float hitDistance = length(hitPos-viewPos);
            float radius = clamp(roughness * roughness * hitDistance * viewHeight
                               / max(-hitPos.z, 0.1), 0.0, 12.0);
            float projectedFootprint = 0.5*abs(gbufferProjection[1][1])*viewHeight
                * hitDistance/max(-hitPos.z,0.1)*reflectionAngularFootprint;
            radius = max(radius,clamp(projectedFootprint*0.5,0.0,12.0));
            reflectionWeight = hit.a * water_sample_path(hit.xy, viewPos, viewGeometric,
                                          true, belowWater, radius, skylight, hit.z, reflected);
            reflection = reflected * reflectionWeight;
        }
    }
    #endif
    if (fresnel > 0.0 && reflectionWeight < 1.0) {
        vec3 fallback;
        if (belowWater) {
            fallback=astra_water_segment(vec3(0.0),playerPos,playerPos+reflectedWorld*96.0,skylight);
        } else {
            // One atmosphere for the visible sky and reflected sky, all day.
            fallback=astra_reflection_sky(reflectedWorld,roughness)*skylight;
            fallback *= astra_environment_reflection_gain(roughness,
                            max(dot(-incident, viewNormal), 0.0), 0.025);
        }
        reflection += fallback * (1.0 - reflectionWeight);
    }
    // Solar glint. The broad sky reflection above (astra_reflection_sky) carries a wide
    // atmospheric lobe, so on the surface the sun reads as a weak wash (user: "太阳在水面上的反射
    // 有点弱"). This adds the narrow specular lobe: sharp when the waves are smooth, wider
    // as roughness grows, and gated by the sun's elevation.
    // Corrected 2026-09-21: this comment used to blame waterRef_SkyColor for the broad
    // lobe. Nothing in global/water/reference_light.glsl is reachable from this pass.
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        if (water && !belowWater && fresnel > 0.0) {
            float sunAlign = max(dot(reflectedWorld, worldSunVector), 0.0);
            // Softer and wider than the first attempt: at 2.6x with a 340 exponent this was
            // a blinding point. A gentler lobe still reads as the sun on the water without
            // searing the view.
            float sharpness = mix(150.0, 42.0, clamp(roughness * 6.0, 0.0, 1.0));
            float glint = pow(sunAlign, sharpness) * solas_sun_visibility();
            // Complementary's solar highlight is shadow-gated. A shaded bank
            // must not get the same bright reflection stripe as open water.
            if (glint>0.002) {
                vec3 source=astra_world_light_direction();
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
    // 2026-09-22 (four-symptom round): the sky mirror above is bounded by the sky it
    // reflects, but its sum with the narrow solar lobe is not. BLOOM_THRESHOLD = 1.0
    // (global/post/bloom.glsl:27) is this pack's own definition of over-exposure - at or
    // below it a pixel contributes nothing to the bloom prefilter, above it the excess
    // becomes a bloom source - and the far water is where the sum crosses it: the grazing
    // lobe is nearly a mirror (0.64 at 5 degrees, 0.84 at 2) and the glint adds up to
    // another 0.72 (water.glsl:281), so a distant band can arrive as white plus bloom.
    // astra_scene_highlights is the pack's shoulder for exactly this class of emitter -
    // lib/twilight.glsl:131-134 names "the sun's image on water" as its consumer - and it
    // is the identity below 1.0, so the bed, the mid-range water and the twilight river
    // are untouched and only the excess above white is compressed. Before this call
    // program/water.glsl never used it (airside probe section 3), so the water surface was
    // the one emitter outside the shoulder.
    reflection = astra_scene_highlights(reflection);
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec3 transmitted = vec3(0.0);
    if (!totalReflection) {
        float valid = 0.0;
        bool airMiss = false;
        bool unshiftedPath = false;
        #ifdef SCREENSPACE_REFRACTION
            // Steadfast advances by background depth with the perturbed direction.
            vec2 refractedUV = water_refracted_uv(depthtex1, viewPos, viewNormal - viewGeometric, uv);
            valid = water_sample_path(refractedUV, viewPos, viewGeometric, false,
                                     water && !belowWater, 0.0, skylight, transmitted);
            // Ice above water uses a different medium flag for the fallback.
            unshiftedPath = (water || belowWater) && all(equal(refractedUV, uv));
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
            if (!airMiss) {
                if (unshiftedPath) {
                    straight = transmitted;
                    straightValid = valid;
                } else {
                    straightValid=water_sample_path(uv,viewPos,viewGeometric,false,
                                                   !belowWater,0.0,skylight,straight);
                }
            }
            vec3 geometricFallback=straight;
            if (straightValid < 1.0) {
                // From Steadfast 0.8.0 environment/water/absorption_refraction.glsl:97-117
                // (idea-level; every expression written for Astra): a refracted ray that
                // finds only sky has crossed an unknown column of water, and assuming a
                // LOT of it is right most of the time - except near the camera, where a
                // thin sheet must not read as deep ocean. The ramp is the fragment's own
                // camera distance: 0.25 blocks at the eye, 23 (fully extinct) at 24 blocks.
                //
                // Two parts of the reference are deliberately not copied. Steadfast also
                // multiplies its background by (1 - fadeFactor), because that pack's
                // absorption has no in-scatter term to consume the background; here
                // water_surface_medium already attenuates it by exp(-depth * sigma), so a
                // second fade would double-count and make the far field DARKER than before.
                // And its depth tops out at one block, which is the right bound for the
                // side-face case it models - an unknown column seen through the surface
                // itself is not bounded, so the ramp goes to the full extinction range.
                //
                // The background is the scene copy at this pixel, the same buffer the
                // accepted path reads: deferred.fsh composites astra_sky into it exactly
                // so that refraction has something behind it, and when the miss came from
                // the interface-side rejection instead of sky, it holds the real geometry.
                // An analytic sky here would be a second sky model disagreeing with the
                // rendered one right at the seam with mix(straight, ...): probe modes 16
                // and 21 measure both candidates. The superseded form had no background
                // at all - it handed vec3(0.0) to astra_water_segment, whose air-side
                // depth was that 96-block ray's vertical extent, a function of the
                // refraction angle only, never of how far the miss is: one constant
                // colour at every distance.
                vec3 deepFallback;
                // Other dimensions can contain player-placed water. Their underside
                // has no Overworld solar sprite and uses the dimension's own sky.
                #if defined DIMENSION_NETHER || defined DIMENSION_END
                if (belowWater) {
                    vec3 refractedRay = refract(incident, viewNormal, eta);
                    vec3 transmittedWorld = normalize(view_player(refractedRay));
                    deepFallback = astra_sky(transmittedWorld);
                } else
                #endif
                {
                    float farField = clamp(-viewPos.z * (1.0 / 24.0), 0.0, 1.0);
                    deepFallback = water_surface_medium(texture(colortex4, uv).rgb,
                        mix(0.25, 23.0, farField), astra_water_incident(skylight));
                }
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
