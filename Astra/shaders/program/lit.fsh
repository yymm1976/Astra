// Astra E1/E2. Single lit fragment entry for native geometry.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/program/scene.glsl"
#include "/lib/surface_emission.glsl"
#if defined ASTRA_TERRAIN && !defined ASTRA_WATER_PASS     && !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Terrain only: the direct caustic term below needs the Solas height field. It is a
    // program-level include, so no global/* -> global/* layering rule is broken.
    #include "/global/water/caustics.glsl"
#endif
#ifdef ASTRA_WATER_PASS
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
#ifdef ASTRA_WATER_PASS
    /* RENDERTARGETS: 0,5 */
#elif defined ASTRA_TRANSLUCENT
    /* RENDERTARGETS: 0 */
#else
    /* RENDERTARGETS: 0,3 */
#endif

in vec3 cameraRelativePosition;
in vec3 surfaceShadowPosition;

#ifdef ASTRA_WEATHER
// Keep translucent rain alpha; clipping is explicitly handled before lighting.
layout(location = 0) out vec4 weatherColor;
#define ASTRA_LIT_COLOR weatherColor
#else
#define ASTRA_LIT_COLOR gl_FragData[0]
#endif
void main() {
    // Use the rasterized surface itself for lighting and waves. A depth-buffer
    // reconstruction is unnecessary here and can disagree with per-pass projection.
    vec3 playerPos = cameraRelativePosition;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Before alpha rejection and material branches, for the entire quad.
    vec2 rippleCoord=playerPos.xz/ASTRA_RIPPLE_TILE;
    float rippleFootprint=max(length(dFdx(rippleCoord)),length(dFdy(rippleCoord)));
    #endif
    #ifdef DIMENSION_END
    // End-stone texture footprint, in atlas texels per pixel. Computed before any
    // material branch: derivatives inside `if (material == 11u)` would be non-uniform
    // across quads that straddle materials (consolidated review A4).
    float endStoneFootprint = max(length(dFdx(texcoord)), length(dFdy(texcoord))) * 256.0;
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
        // Evaluate derivatives before alpha rejection or divergent material flow.
        bool activeWaves=water;
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        // The submerged interface supplies its own Solas normal below.
        activeWaves=activeWaves && isEyeInWater != 1;
        #endif
        WaterSurface waves = water_surface(playerPos + cameraPosition, normal, frameTimeCounter,activeWaves);
        if (water) {
            normal = waves.normal;
            #ifdef WATER_WAVES
            #if !defined DIMENSION_NETHER && !defined DIMENSION_END
            if (isEyeInWater == 1) {
                vec3 face = faceNormal;
                float fresnel = clamp(1.0 + dot(face, normalize(playerPos)), 0.0, 1.0);
                normal = solas_water_normal(playerPos + cameraPosition, face, waterTangent,
                                            waterBinormal, waterViewVector, waterViewDistance, fresnel);
            }
            #endif
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
    #endif
    vec4 albedo = texture(gtexture, texcoord) * tint;
    // Vanilla rain splash particles - NOT implementable here ------------------------
    // Two attempts have now failed, and the second failure is provable rather than a
    // tuning problem:
    //
    //   attempt 1 guessed the splash sprite's atlas cell. The stitcher rounds
    //   (sprite + 2*padding) up to a power of two and doubles padding per mip level, so
    //   the cell is nowhere near the corner that was assumed.
    //
    //   attempt 2 used d(texcoord)/d(pixel) > 0.09 as a "tiny quad" test. That arithmetic
    //   is wrong: texcoord is normalised over the WHOLE atlas, so an 8px sprite in a
    //   256px atlas drawn across N screen pixels gives (8/256)/N = 0.031/N per pixel -
    //   about 0.008 at four pixels, four times under the threshold. It would never fire
    //   on a normally sized splash, while a sufficiently zoomed blue particle could still
    //   trip it.
    //
    // Iris exposes no particle type id (no particle.properties, and gbuffers_particles*
    // only covers the translucent layer), so from inside a shader the splash cannot be
    // told apart from any other particle sharing the atlas. The honest options are a
    // resource pack that blanks minecraft:splash_0..3, or engine support for particle
    // identity. Colour or derivative thresholds are guesses, and a guess that silently
    // deletes potion or sculk particles is worse than leaving the splash in place.
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
    #ifdef ASTRA_ENTITY
        albedo.rgb = mix(albedo.rgb, srgb_decode(max(entityColor.rgb, vec3(0.0))), entityColor.a);
    #endif
    // Texture coordinates are [8,248]/256 for Minecraft light levels 0..15.
    vec2 lightLevel = clamp((lightcoord * 256.0 - 8.0) / 240.0, 0.0, 1.0);
    #if defined ASTRA_WEATHER && (defined DIMENSION_NETHER || defined DIMENSION_END)
        discard;
    #endif
    // Damp ground and standing water are separate signals (global/atmosphere/weather.glsl):
    //   surfaceWet  - how damp, drives darkening and gloss only.
    //   puddle      - sparse standing water, the only thing that drives a REFLECTION.
    // Both are gated on the same rain envelope, so both clear when the rain stops.
    //
    // SC-39 (2026-09-17 correction). The first version of this wrote `surfaceWet` into
    // colortex3.a and then let program/deferred.fsh derive the reflection weight from
    // it (`smoothstep(0.30, 0.85, wetSurface)`). That is the wrong signal: `surfaceWet`
    // is the BROAD damp mask, which saturates to ~1 across all rain-wet terrain, so the
    // derived weight was 1 nearly everywhere and the expensive 96-tap puddle reflection
    // ran as widely as before the change - the opposite of the stated intent, and the
    // direct cause of the "泛白的反射块" the same round was supposed to remove. `puddle`
    // was computed and then never used by anything.
    //
    // The sparse mask now travels to deferred through colortex0.a instead, which no
    // other consumer of this pass reads (see the note at the write site below). The
    // ripple normal keeps BOTH signals: its amplitude is the puddle width, so standing
    // water carries the full ripple, damp ground carries a faint one, and dry ground is
    // flat - which is also what lets deferred treat "this fragment has a ripple" as the
    // "there is water here" test without a third channel.
    float puddle = 0.0;
    float surfaceWet = 0.0;
    vec3 puddleNormal = geometricNormal;
    #if defined ASTRA_TERRAIN && !defined ASTRA_TRANSLUCENT && !defined DIMENSION_NETHER && !defined DIMENSION_END
    // E3 2026-09-22 regression fix. The rock groups the emitter-gloss branch below pulls
    // out of the default class (materials 12..15) used to arrive here as material 0, so
    // reclassifying them had silently switched their rain-wet path OFF: no damp darkening,
    // no rain gloss, no ripple normal and - through the colortex3.a standing-water mask
    // written at the tail of this file - no puddle reflection either. The predicate below
    // keeps the original set (the default class) and adds back exactly those four groups,
    // so their wet behaviour is again what it was before the reclassification. It cannot
    // reach any other surface: 12..15 is disjoint from every other live value (1..11), and
    // no block.properties id outside 10013..10016 maps into it (program/lit.vsh
    // astra_material), so the new rock classes are not "extra" wet surfaces - they are the
    // ones the branch already served. The emitter-gloss term stays independent (it is an
    // additive return on the fragment's own block light, above), so a dry rock far from
    // any emitter is still bit-for-bit the baseline colour.
    if ((material == 0u || (material >= 12u && material <= 15u))
            && isEyeInWater == 0 && astraRainFactor > 0.001) {
        surfaceWet = astra_wet_ground(geometricNormal, lightLevel.y);
        vec3 wetWorldPos = playerPos + cameraPosition;
        // Standing water: unchanged coverage. The sky-exposure gate is applied inside
        // astra_puddle on the fragment's own lightmap, so an overhanging leaf does not
        // grow a puddle.
        puddle = astra_puddle(wetWorldPos, geometricNormal, lightLevel.y);
        // Ripples belong to BOTH: rain is striking the damp ground all around the
        // patch, not only the puddle. `graze` damps the perturbation at shallow view
        // angles (see astra_rain_ripple) - computed from the rasterized geometric
        // normal, so it is derivative-free and safe on shoreline quads.
        float graze = abs(dot(geometricNormal, normalize(playerPos)));
        vec2 ripple = astra_rain_ripple(wetWorldPos, astra_rain_exposure(lightLevel.y),
                                        rippleFootprint, graze, puddle);
        puddleNormal = normalize(vec3(ripple.x, 1.0, ripple.y));
        // Damp darkening. BSL darkens by 0.15 + 0.5 * porosity of the PUDDLE factor
        // (rainPuddles.glsl:80-85); Astra has no porosity map, so a flat 0.18 replaces
        // it, scaled by how damp the fragment is. Uses the original 0.16 constant on
        // the puddle term so standing water is the darker of the two.
        albedo.rgb *= 1.0 - 0.18 * surfaceWet - 0.16 * puddle;
    }
    #endif
    vec3 directRadiance;
    vec3 color = astra_light(albedo.rgb, normal, playerPos, surfaceShadowPosition,
                             lightLevel.y, lightLevel.x, material, directRadiance,
                             vertexAO);
    #ifdef DIMENSION_END
    bool endObsidian=(faceData&(1u<<22))!=0u;
    if((material==11u || endObsidian) && dot(normal,end_light_direction())>0.0) {
        float tone=clamp(dot(albedo.rgb,vec3(0.2126,0.7152,0.0722)),0.0,1.0);
        float roughness=endObsidian ? mix(0.39,0.23,clamp(tone*22.0,0.0,1.0))
                                    : mix(0.86,0.62,tone);
        roughness=mix(roughness,endObsidian ? 0.34 : 0.75,
                      smoothstep(0.6,2.4,endStoneFootprint));
        float surfaceVisibility=end_surface_visibility;
        color+=end_surface_specular(normal,-normalize(playerPos),roughness,
                                   surfaceVisibility,end_surface_eclipse);
    }
    #endif
    #if defined ASTRA_TERRAIN && !defined ASTRA_TRANSLUCENT
    color += astra_rock_emission(material,albedo.rgb,playerPos+cameraPosition,
                                 normal,playerPos,lightLevel.x);
    #ifdef DIMENSION_END
    color += astra_end_stone_emission(material,albedo.rgb);
    #endif
    #endif
    #if defined ASTRA_WEATHER && !defined DIMENSION_NETHER && !defined DIMENSION_END
        // Camera-facing precipitation has no stable surface normal. Use diffuse
        // sky and local block light, without surface shadows or sun-facing bands.
        color = albedo.rgb * (astra_sky_ambient() * lightLevel.y
              + block_lighting(lightLevel.y, lightLevel.x, 0.0,
                               astraBlocklightSuppression, astraHeldLightSuppression));
    #endif
    #ifdef ASTRA_WATER_PASS
        if (water || iceTop) {
            #if !defined DIMENSION_NETHER && !defined DIMENSION_END
            if(water && isEyeInWater == 0 && geometricNormal.y > 0.9 && astraRainFactor > 0.01) {
                // The shared ripple field already has a bounded slope amplitude.
                // Same grazing damping as the wet-ground field above: on water the
                // surface normal being perturbed is the wave normal, and at a shallow
                // view angle that is what made distant rain streaks look torn.
                float exposure = astra_rain_exposure(lightLevel.y);
                float waterGraze = abs(dot(geometricNormal, normalize(playerPos)));
                // Standing water by definition: full ripple amplitude.
                vec2 ripple = astra_rain_ripple(playerPos + cameraPosition, exposure,
                                                rippleFootprint, waterGraze, 1.0);
                normal = normalize(normal + vec3(ripple.x, 0.0, ripple.y));
            }
            #endif
            // Ice is NOT water with a different colour, and it must not share water's
            // surface response: 0.08 was a near-mirror, which is exactly the "透明洞"
            // read (the sky reflection swamped the texture). 0.24 sits inside the range
            // astra_sky_reflection() already handles - it is bluer and softer than
            // water's 0.035..0.135 and keeps the cel surface texture as the dominant
            // signal. Below this, astra_water()'s !water branch uses `roughness` for the
            // single reflection blend, so the whole ice response follows from here.
            float roughness = water ? waves.roughness : 0.24;
            vec4 surface = astra_water(color, albedo.a, playerPos, viewPos, normal,
                                       roughness, lightLevel.y, water, ice, geometricNormal);
            color = surface.rgb;
            albedo.a = surface.a;
        } else {
            color = astra_apply_medium(color, playerPos, lightLevel.y);
        }
    #else
        // Opaque ice precedes the copy; its top uses analytic reflection (design 4.3).
        if (iceTop) {
            vec3 ray = reflect(normalize(playerPos), normal);
            float f = 0.0204 + 0.9796 * pow5(1.0 - max(dot(-normalize(playerPos), normal), 0.0));
            color = mix(color, astra_reflection_sky(ray, 0.08), f);
        }
        #if defined ASTRA_TRANSLUCENT || !defined ASTRA_SCENE_COPY
            color = astra_apply_medium(color, playerPos, lightLevel.y);
        #endif
    #endif
    #if defined ASTRA_TRANSLUCENT && defined FANCY_TRANSLUCENTS
        color *= albedo.a;
    #endif
    // Direct caustics on submerged terrain. One field drives it: solas_water_caustics()
    // is the same Solas height field program/shadow.fsh:59 bakes into the water caster's
    // coloured shadow and global/water/light_shafts.glsl integrates per march sample.
    //
    // The pixel-side delta below serves AIR-SIDE receivers only, and the reason is
    // measurable. Underwater the water caster's own coloured shadow already carries the
    // network - global/lighting resolves caster.gba through diffuse.glsl:282 /
    // shadowmap.glsl:153 when isEyeInWater == 1 - and it bakes the field at the WATER
    // SURFACE (shadow.fsh's waterCasterWorld). The pixel-side gain would instead sample
    // it at the RECEIVER (this fragment, on the seabed), and caustics.glsl:13 shifts the
    // phase by p.y * 0.2, so a 5-block column moves the two sample points 1.0 block apart
    // in xz. Measured against the shipped texture over a 16-block patch they are
    // essentially uncorrelated: Pearson +0.07 at a 5-block column (and still only +0.26
    // even at a 1-block column). Applying both multiply two different lattices, yielding
    // a pattern that is neither; only then does the pair "disagree about where the light
    // lands". So underwater is left to the caster path alone, and this delta exists to put
    // the network on the bed from ABOVE the surface, where the caster tint resolves to
    // white (diffuse.glsl:282, shadowmap.glsl:153).
    //
    // Mapping the field as a gain around ITS OWN median (measured on the shipped texture
    // by qa/tools/underwater_light_probe.py section [2]: p50 0.094, p95 0.662, mean 0.181
    // over a 16-block patch) is what makes it read as LIGHT: 1.35 * 0.094 - 0.135 ~= 0 at
    // the median, so the typical receiver pixel is unchanged, peaks brighten toward the
    // 1.80 cap and troughs darken to 0.70. The consumer this replaces,
    // astra_water_caustics_focus(), collapsed onto its own 0.2 clamp floor over 92.3% of
    // the seabed and was then applied as mix(1, field, 0.70) - a flat 0.44 multiplier that
    // only dimmed the sun by 56% and could never produce a bright spot (measured, same
    // probe).
    // R6 note kept: IterationT multiplies its caustic into the SUNLIGHT term
    // (composite.fsh: shadow *= CalculateWaterCaustics(...)), never into the finished
    // pixel, so the delta below goes into the direct radiance only (reported through
    // astra_light's out parameter) and ambient, block light and emissive surfaces are
    // untouched.
    #if defined ASTRA_TERRAIN && !defined ASTRA_WATER_PASS && defined WATER_CAUSTICS
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        if (!iceTop) {
            // Air-side receivers: this fragment carries caustics when the nearest
            // translucent caster on the light path is a water surface and the fragment
            // sits below it. That is the same question Steadfast 0.8.0
            // environment/lighting/shadowmap.glsl:135-154 answers from its own water
            // height (idea only). global/lighting/ still resolves a water caster's tint
            // to white for air-side receivers (diffuse.glsl:282, shadowmap.glsl:153), so
            // from above water this term is the only place the pattern can appear; the
            // distance and thin-column fades are the reference's own limits.
            float causticFade = 1.0;
            // false underwater, so the delta cannot stack on the caster path's own
            // network there (see the header comment above).
            bool receivesCaustics = false;
            #ifdef SHADOWS
            if (isEyeInWater == 0) {
                vec4 caster = shadow_caster_data(surfaceShadowPosition.xy);
                if (caster.r < 0.999) {
                    float waterY = decode_water_height(caster.r);
                    float column = waterY - (playerPos.y + cameraPosition.y);
                    // 1/16 block under the surface is too thin a column to focus
                    // anything (Steadfast's own lower clamp), and the map's 48-block
                    // reach is where its caustics stop being worth rendering.
                    causticFade = (1.0 - smoothstep(48.0, 52.0, length(playerPos)))
                                * smoothstep(0.0, 0.0625, column);
                    receivesCaustics = column > 0.0;
                }
            }
            #endif
            if (receivesCaustics) {
                float field = clamp(solas_water_caustics(playerPos + cameraPosition), 0.0, 1.5);
                float causticGain = clamp(1.0 + ASTRA_CAUSTIC_STRENGTH * (1.35 * field - 0.135),
                                          0.70, 1.80);
                color += directRadiance * ((causticGain - 1.0) * causticFade);
            }
        }
        #endif
    #endif
    #if DEBUG_VERTEX_AO == 1 && defined ASTRA_TERRAIN
        color = vec3(vertexAO);
    #endif
    ASTRA_LIT_COLOR = vec4(max(color, vec3(0.0)), albedo.a);
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
        gl_FragData[1] = water && abs(geometricNormal.y) > 0.9
            ? vec4(water_pack_surface_height(playerPos.y + cameraPosition.y), lightLevel.y, 1.0)
            : vec4(0.0);
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
        #if defined DIMENSION_END && defined ASTRA_TERRAIN
        gl_FragData[1].a = astra_end_stone_emission(material,albedo.rgb).g;
        #endif
    #endif
}
