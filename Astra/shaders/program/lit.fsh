// Astra E1/E2. Single lit fragment entry for native geometry.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/program/scene.glsl"
#include "/lib/surface_emission.glsl"
#include "/lib/rock_material.glsl"
#include "/lib/wet_material.glsl"
#include "/lib/taa_reactive.glsl"
#include "/lib/surface_buffers.glsl"
#include "/lib/ao_material.glsl"
#include "/lib/rain_particles.glsl"
#ifdef ASTRA_WATER_PASS
    #include "/lib/water_interface_record.glsl"
    #include "/program/water.glsl"
    #include "/global/water/caustics.glsl"
    in vec3 waterTangent;
    in vec3 waterBinormal;
    in vec3 waterViewVector;
    in float waterViewDistance;
#endif
in vec2 texcoord;
in vec2 lightcoord;
in vec4 tint;
in float vertexAO;
flat in uint faceData;
#ifdef ASTRA_TAA
in vec4 taaPreviousClip;
in float taaPreviousViewDepth;
flat in float taaFoliageValid;
#endif
#ifdef ASTRA_WATER_PASS
    #ifdef ASTRA_TAA
    /* RENDERTARGETS: 0,5,16 */
    #else
    /* RENDERTARGETS: 0,5 */
    #endif
#elif defined ASTRA_TRANSLUCENT
    #ifdef ASTRA_TAA
    /* RENDERTARGETS: 0,16 */
    #else
    /* RENDERTARGETS: 0 */
    #endif
#else
    #ifdef ASTRA_TAA
        #ifdef ASTRA_SSAO
            #ifdef ASTRA_DIRECTIONAL_SKYLIGHT
            /* RENDERTARGETS: 0,3,16,22,19,20,27 */
            #define ASTRA_AMBIENT_SLOT 4
            #define ASTRA_NORMAL_SLOT 5
            #define ASTRA_SKY_RESPONSE_SLOT 6
            #else
            /* RENDERTARGETS: 0,3,16,22,19,20 */
            #define ASTRA_AMBIENT_SLOT 4
            #define ASTRA_NORMAL_SLOT 5
            #endif
        #else
        /* RENDERTARGETS: 0,3,16,22 */
        #endif
    #else
        #ifdef ASTRA_SSAO
            #ifdef ASTRA_DIRECTIONAL_SKYLIGHT
            /* RENDERTARGETS: 0,3,19,20,27 */
            #define ASTRA_AMBIENT_SLOT 2
            #define ASTRA_NORMAL_SLOT 3
            #define ASTRA_SKY_RESPONSE_SLOT 4
            #else
            /* RENDERTARGETS: 0,3,19,20 */
            #define ASTRA_AMBIENT_SLOT 2
            #define ASTRA_NORMAL_SLOT 3
            #endif
        #else
        /* RENDERTARGETS: 0,3 */
        #endif
    #endif
#endif

in vec3 cameraRelativePosition;
in vec3 surfaceShadowPosition;

#ifdef ASTRA_WEATHER
// Keep translucent rain alpha; clipping is explicitly handled before lighting.
layout(location = 0) out vec4 weatherColor;
#ifdef ASTRA_TAA
layout(location = 1) out vec4 weatherReactive;
#endif
#define ASTRA_LIT_COLOR weatherColor
#else
#define ASTRA_LIT_COLOR gl_FragData[0]
#endif
void main() {
    #if defined ASTRA_WEATHER && (defined DIMENSION_NETHER || defined DIMENSION_END)
    // These dimensions have no precipitation; reject before material sampling.
    discard;
    #endif
    // Use the rasterized surface itself for lighting and waves. A depth-buffer
    // reconstruction is unnecessary here and can disagree with per-pass projection.
    vec3 playerPos = cameraRelativePosition;
    // Needed by the rain normal before the reflection footprint is evaluated.
    vec2 lightLevel = clamp((lightcoord * 256.0 - 8.0) / 240.0, 0.0, 1.0);
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Before alpha rejection and material branches, for the entire quad.
    float rippleFootprint = 0.0;
    #if (defined ASTRA_TERRAIN && !defined ASTRA_TRANSLUCENT) || defined ASTRA_WATER_PASS
    // Weather and camera medium are uniform across the draw; derivatives still
    // precede alpha rejection and every material-dependent branch.
    if (astraRainFactor > 0.001 && isEyeInWater == 0) {
        vec2 rippleCoord = playerPos.xz / ASTRA_RIPPLE_TILE;
        rippleFootprint = max(length(dFdx(rippleCoord)), length(dFdy(rippleCoord)));
    }
    #endif
    #endif
    vec3 viewPos = camera_relative_view(playerPos);
    // faceData is flat and never rewritten, so this two-axis decode is evaluated once
    // and the water branches below reuse it. They previously decoded the identical
    // face normal twice more (lit.fsh:75 and lit.fsh:86).
    vec3 faceNormal = unpack_octahedral(faceData, 9);
    vec3 normal = faceNormal;
    uint material = (faceData >> 18) & 15u;
    bool water = material == 1u;
    bool ice = material == 9u;
    bool iceTop = ice && normal.y > 0.99;
    #ifdef ASTRA_WATER_PASS
        vec2 waveCoord=playerPos.xz-playerPos.y*0.2;
        float wavePixel=max(length(dFdx(waveCoord)),length(dFdy(waveCoord)));
        float noiseSize=float(textureSize(solasWaterNoise,0).x);
        vec2 waveFootprint=wavePixel*noiseSize/vec2(256.0,48.0);
        // Evaluate derivatives before alpha rejection or divergent material flow.
        // The air interface keeps its filtered waves. The submerged horizontal
        // interface shares the optical lens field with caustics and shafts.
        WaterSurface waves = water_surface(playerPos + cameraPosition, normal,
                                           frameTimeCounter, water && isEyeInWater != 1);
        if (water) {
            normal = waves.normal;
            #ifdef WATER_WAVES
            if (isEyeInWater == 1) {
                #if !defined DIMENSION_NETHER && !defined DIMENSION_END
                if (abs(faceNormal.y) > 0.9) {
                    vec2 waveSlope;
                    mat2 curvature;
                    astra_water_wave_lens(playerPos.xz+cameraPosition.xz,wavePixel,waveSlope,curvature);
                    normal = normalize(vec3(-waveSlope.x,1.0,-waveSlope.y));
                    if (dot(normal,faceNormal) < 0.0) normal = -normal;
                } else
                #endif
                {
                    float fresnel = clamp(1.0 + dot(faceNormal, normalize(playerPos)), 0.0, 1.0);
                    normal = solas_water_normal(playerPos + cameraPosition, faceNormal,
                        waterTangent, waterBinormal, waterViewVector, waterViewDistance, fresnel,waveFootprint);
                }
            }
            #endif
        }
    #endif
    // Sodium/fluid underside vertices can retain an upward attribute normal.
    // Orient the geometric side from the actual ray, independent of winding.
    vec3 geometricNormal = faceNormal;
    #ifdef ASTRA_WATER_PASS
        if (water) {
            if (dot(geometricNormal, playerPos) > 0.0) geometricNormal = -geometricNormal;
            if (dot(normal, geometricNormal) < 0.0) normal = -normal;
        }
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        if (water && isEyeInWater == 0 && geometricNormal.y > 0.9 && astraRainFactor > 0.01) {
            float exposure = astra_rain_exposure(lightLevel.y);
            float waterGraze = abs(dot(geometricNormal, normalize(playerPos)));
            vec2 ripple = astra_rain_ripple(playerPos + cameraPosition, exposure,
                                            rippleFootprint, waterGraze, 1.0);
            normal = normalize(normal + vec3(ripple.x, 0.0, ripple.y));
        }
        #endif
        // Every invocation supplies the footprint before alpha rejection and
        // the water/ice branch, including the rain perturbation above.
        // astra_water must not take derivatives there.
        vec3 footprintRay = reflect(normalize(viewPos), normalize(player_view(normal)));
        float reflectionAngularFootprint = max(length(dFdx(footprintRay)), length(dFdy(footprintRay)));
    #endif
    vec4 textureColor = texture(gtexture, texcoord);
    vec4 albedo = textureColor * tint;
    #if defined DIMENSION_NETHER || defined DIMENSION_END
    float rockSmoothness = astra_rock_smoothness(material, textureColor.rgb);
    #endif
    #if defined ASTRA_PARTICLE && !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Before sRGB decoding and lighting; both Iris particle layers use this path.
    if (astra_hide_rain_splash(albedo.rgb, tint.rgb)) discard;
    #endif
#if defined ASTRA_WEATHER && !defined DIMENSION_NETHER && !defined DIMENSION_END
    if (temperature > 0.15) {
        // Keep only stronger texture streaks, then lower their opacity and tint.
        // The threshold is independent of time, so rain does not randomly flicker.
        if (albedo.a < 0.32) discard;
        float curtain = albedo.a * clamp(astraRainFactor, 0.0, 1.0) * 0.24;
        albedo = vec4(vec3(0.55, 0.59, 0.64),
                      curtain * smoothstep(0.6, 1.7, length(playerPos)));
    } else {
        // SNOW keeps the lit treatment. This is the one place we deliberately differ from
        // the reference, whose single black path would render snow as a dark curtain.
        if (albedo.a < alphaTestRef) discard;
    }
    #else
    if (albedo.a < alphaTestRef) discard;
    #endif
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    if (water && isEyeInWater == 1) {
        albedo.rgb = mix(tint.rgb, solasWaterSqrt * solasWaterSqrt, 0.5);
        albedo.a = 0.70;
    }
    #endif
    albedo.rgb = srgb_decode(max(albedo.rgb, vec3(0.0)));
    #if defined DIMENSION_NETHER && defined ASTRA_TERRAIN
    bool netherLava = (faceData & (1u << 25)) != 0u;
    if (netherLava) {
        float red = albedo.r;
        albedo.rgb *= vec3(0.82, 1.0, 1.0);
        albedo.rgb += red * vec3(0.0, 0.025, 0.004);
    }
    #endif
    #ifdef ASTRA_ENTITY
        albedo.rgb = mix(albedo.rgb, srgb_decode(max(entityColor.rgb, vec3(0.0))), entityColor.a);
    #endif
    // Damp ground and standing water are separate signals (global/atmosphere/weather.glsl):
    //   surfaceWet  - how damp, drives darkening and gloss only.
    //   puddle      - sparse standing water, the only thing that drives a REFLECTION.
    // Both are gated on the same rain envelope, so both clear when the rain stops.
    //
    // Carry only the sparse puddle mask in colortex3.a. colortex0 is RGB-only.
    // Ripple amplitude follows that same puddle mask; broad dampness alone
    // must never invoke the expensive deferred reflection trace.
    float puddle = 0.0;
    float surfaceWet = 0.0;
    vec3 wetResponse = astra_wet_material((faceData >> 23) & 3u);
    vec3 puddleNormal = geometricNormal;
    #if defined ASTRA_TERRAIN && !defined ASTRA_TRANSLUCENT && !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Rock material classes retain the same wet-ground behaviour as generic
    // terrain. Their dry-surface response is independent of rain and puddles.
    if ((material == 0u || (material >= 12u && material <= 15u))
            && isEyeInWater == 0 && astraRainFactor > 0.001) {
        surfaceWet = astra_wet_ground(geometricNormal, lightLevel.y);
        vec3 wetWorldPos = playerPos + cameraPosition;
        // Standing water: unchanged coverage. The sky-exposure gate is applied inside
        // astra_puddle on the fragment's own lightmap, so an overhanging leaf does not
        // grow a puddle.
        puddle = astra_puddle(wetWorldPos, geometricNormal, lightLevel.y);
        // Ripple strength follows sparse standing water. `graze` damps it at shallow view
        // angles (see astra_rain_ripple) - computed from the rasterized geometric
        // normal, so it is derivative-free and safe on shoreline quads.
        // Zero puddle coverage and fully filtered ripples return the same flat
        // normal; neither needs the view normalization or a flipbook query.
        puddleNormal = vec3(0.0, 1.0, 0.0);
        if (puddle > 0.0 && rippleFootprint < 0.08) {
            float graze = abs(dot(geometricNormal, normalize(playerPos)));
            vec2 ripple = astra_rain_ripple(wetWorldPos, astra_rain_exposure(lightLevel.y),
                                            rippleFootprint, graze, puddle);
            puddleNormal = normalize(vec3(ripple.x, 1.0, ripple.y));
        }
        // Broad dampness follows the block family's response. Standing water keeps
        // its own coverage and darkening; soil does not turn into a broad mirror.
        albedo.rgb *= 1.0 - wetResponse.x * surfaceWet - 0.16 * puddle;
    }
    #endif
    vec3 directRadiance = vec3(0.0);
    vec3 ambientRadiance = vec3(0.0);
    vec3 skyResponse = vec3(0.0);
    vec3 color = vec3(0.0);
    #if defined ASTRA_WEATHER && !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Precipitation uses diffuse sky and block light directly. Surface lighting
    // (including shadow/SH queries) would be overwritten by this same result.
    color = albedo.rgb * (astra_sky_ambient() * lightLevel.y
          + block_lighting(lightLevel.y, lightLevel.x, 0.0,
                           astraBlocklightSuppression, astraHeldLightSuppression));
    #else
    #ifdef ASTRA_WATER_PASS
    // Only the submerged horizontal interface consumes a lit water layer.
    // Vertical sheets transport the opaque background and a small sky sheen.
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    if (!water || (isEyeInWater == 1 && abs(geometricNormal.y) > 0.9))
    #else
    if (!water || isEyeInWater == 1)
    #endif
    #endif
    color = astra_light(albedo.rgb, water && isEyeInWater == 1 ? -normal : normal, playerPos, surfaceShadowPosition,
                             lightLevel.y, lightLevel.x, material, directRadiance,
                             vertexAO, ambientRadiance, skyResponse);
    #endif
    #if defined DIMENSION_NETHER && defined ASTRA_TERRAIN
    if (netherLava) {
        // Restrained amber emission with a smooth scalar highlight shoulder.
        // Retain the animated texture's contrast instead of clipping RGB channels.
        float peak = max(color.r, max(color.g, color.b));
        color *= 0.80 / (1.0 + peak * 0.18);
    }
    #endif
    #if defined ASTRA_SSAO && !defined ASTRA_TRANSLUCENT
    gl_FragData[ASTRA_AMBIENT_SLOT] = vec4(0.0);
    gl_FragData[ASTRA_NORMAL_SLOT] = vec4(0.0);
    #ifdef ASTRA_DIRECTIONAL_SKYLIGHT
    // Alpha 1 so the write replaces the previous value with or without a
    // blend override on 27 (the default gbuffers blend would otherwise keep
    // the stale texel under this zero fill).
    gl_FragData[ASTRA_SKY_RESPONSE_SLOT] = vec4(0.0, 0.0, 0.0, 1.0);
    #endif
    #if defined ASTRA_TERRAIN && !defined ASTRA_HAND
    if (astra_ao_receiver(material)) {
        // Apply the same seven-bit AO that deferred2 will recover, so the
        // directional-sky replacement uses a consistent ambient contribution.
        float aoLevel = round(clamp(vertexAO, 0.0, 1.0) * 127.0);
        float storedAO = aoLevel / 127.0;
        color -= ambientRadiance * (1.0 - storedAO);
        gl_FragData[ASTRA_AMBIENT_SLOT] = vec4(max(ambientRadiance, vec3(0.0)), 1.0);
        // High bit = eligible receiver, low seven bits = vertex AO. Existing
        // normal.a > 0.5 eligibility queries still include fully occluded faces.
        float aoByte = (128.0 + aoLevel) / 255.0;
        gl_FragData[ASTRA_NORMAL_SLOT] = vec4(geometricNormal * 0.5 + 0.5, aoByte);
        #ifdef ASTRA_DIRECTIONAL_SKYLIGHT
        // R1: the SH-direction-dependent share of ambientRadiance, kept apart
        // so deferred2 can re-evaluate the SH sky at the bent normal without
        // rescaling colortex19 or touching any other light term.
        gl_FragData[ASTRA_SKY_RESPONSE_SLOT] = vec4(max(skyResponse, vec3(0.0)), 1.0);
        #endif
    }
    #endif
    #endif
    #if defined ASTRA_TERRAIN && !defined ASTRA_TRANSLUCENT && !defined DIMENSION_NETHER && !defined DIMENSION_END
    if (surfaceWet > 0.001) {
        // Reuse the existing shadowed direct term, including its albedo and weather
        // attenuation. This bounded gloss adds no environment or SSR samples.
        float gloss = astra_wet_gloss(geometricNormal, -normalize(playerPos),
                                     astra_world_light_direction(), wetResponse);
        color += directRadiance * (gloss * surfaceWet * (1.0 - puddle));
    }
    #endif
    #ifdef DIMENSION_END
    bool endObsidian=(faceData&(1u<<22))!=0u;
    if((material==11u || endObsidian) && dot(normal,end_light_direction())>0.0) {
        float tone=dot(textureColor.rgb,vec3(0.2126,0.7152,0.0722));
        float roughness=endObsidian ? mix(0.39,0.23,smoothstep(0.0,0.35,tone))
                                    : 1.0-rockSmoothness;
        float surfaceVisibility=end_surface_visibility;
        color+=end_surface_specular(normal,-normalize(playerPos),roughness,
                                   surfaceVisibility,end_surface_eclipse);
    }
    #endif
    #if defined ASTRA_TERRAIN && !defined ASTRA_TRANSLUCENT
    #ifdef DIMENSION_END
    color += astra_end_stone_emission(material,albedo.rgb);
    #endif
    #endif
    #ifdef ASTRA_WATER_PASS
        if (water || iceTop) {
            // Ice is NOT water with a different colour, and it must not share water's
            // surface response: 0.08 was a near-mirror, which is exactly the "透明洞"
            // read (the sky reflection swamped the texture). 0.24 sits inside the range
            // astra_sky_reflection() already handles - it is bluer and softer than
            // water's 0.035..0.135 and keeps the cel surface texture as the dominant
            // signal. Below this, astra_water()'s !water branch uses `roughness` for the
            // single reflection blend, so the whole ice response follows from here.
            float roughness = water ? waves.roughness : 0.24;
            vec4 surface = astra_water(color, albedo.a, playerPos, viewPos, normal,
                                       roughness, lightLevel.y, water, ice, geometricNormal,
                                       reflectionAngularFootprint);
            color = surface.rgb;
            albedo.a = surface.a;
        } else {
            color = astra_apply_medium(color, playerPos, lightLevel.y);
        }
    #else
        // Opaque ice precedes the copy; its top uses analytic reflection (design 4.3).
        if (iceTop) {
            vec3 incident = normalize(playerPos);
            vec3 ray = reflect(incident, normal);
            float noV = max(dot(-incident, normal), 0.0);
            float f = 0.0204 + 0.9796 * pow5(1.0 - noV);
            vec3 environment = astra_reflection_sky(ray, 0.08)
                             * astra_environment_reflection_gain(0.08, noV, 0.0204);
            color = mix(color, environment, f);
        }
        #if defined ASTRA_TRANSLUCENT || !defined ASTRA_SCENE_COPY
            color = astra_apply_medium(color, playerPos, lightLevel.y);
        #endif
    #endif
    #if defined ASTRA_TRANSLUCENT && defined FANCY_TRANSLUCENTS
        color *= albedo.a;
    #endif
    #if DEBUG_VERTEX_AO == 1 && defined ASTRA_TERRAIN
        color = vec3(vertexAO);
    #endif
    ASTRA_LIT_COLOR = vec4(max(color, vec3(0.0)), albedo.a);
    #ifdef ASTRA_TAA
        // Without object velocities, animated/non-terrain surfaces use only this
        // frame. Full mask writes also cover translucent layers without depth writes.
        float reactive = 1.0;
        #if defined ASTRA_TERRAIN && !defined ASTRA_TRANSLUCENT && !defined ASTRA_HAND
        reactive = ((material >= 1u && material <= 10u) || puddle > 0.001) ? 1.0 : 0.0;
        bool motionValid=taaFoliageValid>0.5 && taaPreviousClip.w>0.00001
                       && taaPreviousViewDepth>0.0
                       && all(lessThanEqual(abs(taaPreviousClip.xy),vec2(taaPreviousClip.w)));
        if(motionValid) reactive=0.0;
        #endif
        #ifdef ASTRA_WEATHER
        weatherReactive = vec4(reactive, 0.0, 0.0, 1.0);
        #elif defined ASTRA_TRANSLUCENT && !defined ASTRA_WATER_PASS
        gl_FragData[1] = vec4(reactive, 0.0, 0.0, 1.0);
        #else
        gl_FragData[2] = vec4(reactive, 0.0, 0.0, 1.0);
        #endif
        #ifndef ASTRA_TRANSLUCENT
        gl_FragData[3] = vec4(0.0);
        #if defined ASTRA_TERRAIN && !defined ASTRA_HAND
        if(motionValid) {
            vec2 previousUV=taaPreviousClip.xy/taaPreviousClip.w*0.5+0.5;
            vec2 currentUnjittered=gl_FragCoord.xy/vec2(viewWidth,viewHeight)-astra_jitter_uv();
            // Store UV displacement, not absolute UV: the resolve reconstructs
            // onto an unjittered grid, offset from this raster sample's location.
            gl_FragData[3]=vec4(previousUV-currentUnjittered,
                               log2(1.0+taaPreviousViewDepth),1.0);
        }
        #endif
        #endif
    #endif
    // SC-39 (2026-09-17, corrected by the 2026-09-20 consolidated review F-01): the
    // sparse standing-water mask rides in the GEOMETRY buffer's alpha channel
    // (colortex3) from here to program/deferred.fsh.
    //
    // Which channel, and why. The first attempt used the scene colour's alpha
    // (colortex0.a) on the stated reasoning that R11F_G11F_B10F leaves its A channel as
    // unused padding. That is false - R11F_G11F_B10F is an RGB format with NO alpha
    // channel at all, so the write is dropped and every read returns 1.0. Verified
    // against the authoritative declaration: lib/water_buffer_formats.glsl sets
    // colortex0Format = R11F_G11F_B10F.
    //
    // colortex3 is the carrier. It is not format-declared by this pack, so it keeps
    // Iris's RGBA8 default - a real alpha channel - and its clear colour writes an
    // alpha of 0.0, the mask's own zero (settings.glsl colortex3ClearColor).
    //
    // The ONLY writer is the opaque terrain branch below. An intermediate revision also
    // overwrote gl_FragData[1].a inside the water pass; that slot is colortex5
    // (RENDERTARGETS 0,5), whose alpha is the water-surface VALIDITY flag read by
    // program/water_state.fsh - the overwrite zeroed the flag and, through the
    // SRC_ALPHA blend on colortex5, dropped the packed surface height in .rgb as well.
    // The water pass never computes a puddle (its terrain branch is ASTRA_TRANSLUCENT),
    // so it has nothing to say in colortex3 and does not touch it. Translucents and
    // weather likewise only write colortex0; a puddle stays an opaque-ground feature,
    // which is correct since standing water needs opaque ground.
    //
    // The HAND pass is excluded: its fragments carry the high bit in gl_FragData[1].r
    // and are re-projected in deferred, so it must not also claim a puddle.
    #ifdef ASTRA_WATER_PASS
        gl_FragData[1] = vec4(0.0);
        if (water) {
            gl_FragData[1] = abs(geometricNormal.y) > 0.9
                ? vec4(water_pack_surface_height(playerPos.y + cameraPosition.y), lightLevel.y, 1.0)
                : vec4(1.0, 1.0, lightLevel.y, 1.0);
        }
    #endif
    #ifndef ASTRA_TRANSLUCENT
        // Seven light bits retain more precision than the 16 Minecraft light levels.
        // The high bit carries the projection override across the deferred boundary.
        uint lightData = uint(round(lightLevel.y * 127.0));
        #ifdef ASTRA_HAND
            lightData |= 128u;
        #endif
        gl_FragData[1] = vec4(float(lightData) / 255.0, encode_unit_vector(puddleNormal) * 0.5 + 0.5, 0.0);
        // Opaque ground only. The default class (`material == 0u`) plus the four
        // reclassified rock groups (12..15) excludes water, glass, ice, leaves and the
        // emissive groups, so the mask cannot appear on a surface that cannot hold water.
        // The widened set mirrors the rain-wet gate above - same predicate, same reason
        // (E3 2026-09-22), so the mask the deferred pass reads agrees with whether the
        // fragment got any puddle at all.
        gl_FragData[1].a = (material == 0u || (material >= 12u && material <= 15u))
            ? clamp(puddle, 0.0, 1.0) : 0.0;
        #if defined DIMENSION_NETHER && defined ASTRA_TERRAIN && !defined ASTRA_HAND
        // This dimension has no rain puddles. Use alpha for rock smoothness,
        // and gb for the geometric reflection normal consumed by the Nether composite.
        gl_FragData[1].a = rockSmoothness
            * (material == 12u ? NETHERRACK_GLOW * 0.01 : 1.0);
        #endif
        #if defined DIMENSION_END && defined ASTRA_TERRAIN
        gl_FragData[1].a = astra_end_stone_emission(material,albedo.rgb).g;
        #endif
    #endif
}
