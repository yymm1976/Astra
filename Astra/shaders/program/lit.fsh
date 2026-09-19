// Astra E1/E2. Single lit fragment entry for native geometry.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/program/scene.glsl"
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
    vec3 normal = unpack_octahedral(faceData, 9);
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
                vec3 face = unpack_octahedral(faceData, 9);
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
    vec3 geometricNormal = unpack_octahedral(faceData, 9);
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
    if (material == 0u && isEyeInWater == 0 && astraRainFactor > 0.001) {
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
                             lightLevel.y, lightLevel.x, material, directRadiance);
    #ifdef DIMENSION_END
    if (material == 11u) {
        vec3 L = end_light_direction();
        vec3 V = -normalize(playerPos);
        vec3 H = normalize(L + V + vec3(1e-6));
        // ------------------------------------------------------------------
        // End stone: the narrow and broad lobes already existed and are kept.
        // What they lacked is texture - every texel of a wall returned the same
        // plastic gloss, because the term was a pure function of (normal, light,
        // view). Complementary gives its end stone a per-texel roughness from the
        // texture's red channel high powers (lib/materials/specificMaterials/
        // terrain/endStone.glsl). The first attempt here derived that from the
        // albedo alone and that is not enough: the end stone atlas cells are close
        // to uniform, so pow(luma, 6) came out nearly constant across the block and
        // the surface stayed plastic. What the block actually looks like is a few
        // brighter mineral grains among matte rock, so the grain is reconstructed
        // from two inputs:
        //   - the albedo (already sampled for the diffuse pass - no extra texture
        //     read), which biases the whole cell by how bright it is,
        //   - a world-space hash on a four-per-block grid, which is the grain
        //     itself. Fixed world coordinates, not a screen or frame hash, so the
        //     pattern is static on the block, identical every frame and stable
        //     under camera motion - it cannot read as noise or as flicker.
        // ------------------------------------------------------------------
        vec3 worldPos = playerPos + cameraPosition;
        // Two per block: the end-stone atlas cell is 16 texels across, so its own
        // grain is ~1/16 block, and a grid finer than the texture would only add
        // shimmer. Two per block is also right at the resolvable edge at the shadow
        // range, which is where the footprint fade below takes over.
        float grainCell = fract(sin(dot(floor(worldPos * 2.0),
                                         vec3(12.9898, 78.233, 37.719))) * 43758.5453);
        float grainMask = smoothstep(0.52, 0.90, grainCell);
        float grainTone = clamp(dot(albedo.rgb, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
        // Wide dynamic range on purpose: most of the block stays matte at 0.20 and
        // the grains reach full gloss. That is what keeps this stone rather than
        // plastic - the complaint was uniform sheen, and a narrow range would
        // reproduce it.
        float gloss = 0.20 + 0.80 * grainMask * mix(0.55, 1.0, grainTone);
        // Micro-detail has to converge with the screen footprint or a distant wall
        // turns into a field of flickering pixels. The texture footprint in atlas
        // space, in texels per pixel, is the honest measure of what is resolvable;
        // the same derivative-based idea Complementary uses for its generated
        // normals. No noise, no per-frame randomisation.
        // The texture footprint in atlas space, in texels per pixel, is the honest measure
        // of what is resolvable; hoisted above because derivatives inside a flat-varying
        // branch are non-uniform (consolidated review A4).
        float footprint = endStoneFootprint;
        gloss = mix(gloss, 0.48, smoothstep(0.6, 2.4, footprint));
        float visibility = 1.0;
        #ifdef SHADOWS
        // Unchanged: the shadow the diffuse pass already respects. No second
        // lighting evaluation, no black-hole reflection trace.
        visibility = mix(1.0, shadow_opaque_visibility(surfaceShadowPosition),
                         shadow_coverage(playerPos, surfaceShadowPosition));
        #endif
        float h = max(dot(normal, H), 0.0);
        float h2 = h * h;
        float h4 = h2 * h2;
        float h8 = h4 * h4;
        float sheen = h8 * h8 * h8
                    * max(dot(normal, L), 0.0) * visibility;
        float broad = pow5(h)
                    * max(dot(normal, L), 0.0) * visibility;
        color += vec3(0.055, 0.057, 0.049) * (sheen * mix(0.30, 1.70, gloss))
               + vec3(0.010, 0.011, 0.009) * (broad * mix(0.75, 1.20, gloss));
    }
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
    // Direct caustics on submerged terrain.
    // The reference projects its water-surface focus pattern down through the shadow map,
    // and Astra still writes that pattern into the coloured shadow. The user reported the
    // seabed as having no caustics at all, and that path depends on the water caster being
    // present and correctly tinted in shadowcolor0, which cannot be verified offline. This
    // evaluates the SAME Solas height field directly at the submerged fragment, so the
    // network is guaranteed to appear and still animates and respects the sun through the
    // surface wave phase. It is a multiplier centred near 1, so it modulates rather than
    // dims: caustic peaks lift a little, the dark lattice crushes.
    // R6 FIX. IterationT multiplies its caustic into the SUNLIGHT term
    // (composite.fsh: shadow *= CalculateWaterCaustics(...)), not into the finished pixel.
    // The previous version scaled the whole colour, which also dimmed ambient light, block
    // light and emissive surfaces, and it ran regardless of the WATER_CAUSTICS option.
    // Here the delta is applied to the direct radiance only, so a caustic peak brightens
    // sunlight and a dark lattice removes sunlight while every other light path is left
    // alone. astra_light reports the direct part through its out parameter.
    #if defined ASTRA_TERRAIN && !defined ASTRA_WATER_PASS && defined WATER_CAUSTICS
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        if (isEyeInWater == 1 && !iceTop) {
            float causticGain = mix(1.0, astra_water_caustics_focus(playerPos + cameraPosition),
                                    ASTRA_CAUSTIC_STRENGTH);
            color += directRadiance * (causticGain - 1.0);
        }
        #endif
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
        // Opaque ground only. `material == 0u` excludes water, glass, ice, leaves and the
        // emissive groups, so the mask cannot appear on a surface that cannot hold water.
        gl_FragData[1].a = material == 0u ? clamp(puddle, 0.0, 1.0) : 0.0;
    #endif
}
