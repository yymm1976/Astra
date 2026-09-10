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
    vec3 viewPos = camera_relative_view(playerPos);
    vec3 normal = unpack_octahedral(faceData, 9);
    uint material = (faceData >> 18) & 15u;
    bool water = material == 1u;
    bool iceTop = material == 9u && normal.y > 0.99;
    #ifdef ASTRA_WATER_PASS
        // Evaluate derivatives before alpha rejection or divergent material flow.
        WaterSurface waves = water_surface(playerPos + cameraPosition, normal, frameTimeCounter);
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
    #ifdef ASTRA_PARTICLE
    // Vanilla rain splash particles -> deleted -------------------------------------
    // Confirmed path: WaterDropParticle.getLayer() returns SingleQuadParticle$Layer.OPAQUE
    // in the 26.2 client, so the splash is drawn by the opaque particle program, which
    // Iris feeds from gbuffers_particles (falling back to gbuffers_textured_lit). Both
    // entries define ASTRA_PARTICLE, so this block covers either mapping.
    //
    // Iris exposes no particle type id, and the previous "guess the atlas cell" box
    // missed: the stitcher rounds (sprite + 2*padding) up to a power of two and doubles
    // the padding per mip level, so the splash cell is nowhere near the sheet corner.
    // This test instead uses a property independent of atlas geometry and resource pack:
    //
    //   a single-quad particle spans one 8x8 sprite over a handful of screen pixels, so
    //   its texture-coordinate derivative is large (~0.1-0.4 per pixel), while real block
    //   and item surfaces stay far below that. Combined with the blue bias this removes
    //   the splash without touching larger blue sprites (potion swirl, sculk soul,
    //   dripping water), which the user asked to keep.
    vec2 astraFootprint = vec2(length(vec2(dFdx(texcoord.x), dFdy(texcoord.x))),
                               length(vec2(dFdx(texcoord.y), dFdy(texcoord.y))));
    if (max(astraFootprint.x, astraFootprint.y) > 0.09) {
        float splashBlue = albedo.b - max(albedo.r, albedo.g);
        if (splashBlue > 0.15 && albedo.a > 0.02) discard;
    }
    #endif
#if defined ASTRA_WEATHER && !defined DIMENSION_NETHER && !defined DIMENSION_END
    if (temperature > 0.15) {
        // Rain streaks. Three constraints shape this grid:
        //   1. texcoord is per-quad and UV.y is stretched by the vanilla rain sheet, so
        //      a plain UV grid produced the long regular stripes the user reported.
        //   2. The vertical scroll is world-Y driven so the phase is continuous across
        //      particles and the sheet appears to fall at a constant world speed.
        //   3. Cells must be anchored to the world, not to the screen. The world column
        //      is part of the hash, and the drop's in-cell offset only depends on the
        //      cell's own hash, so a given piece of sky always rains the same way as the
        //      camera moves instead of boiling (the earlier version hashed the moving
        //      time index, which made every drop flicker on its own).
        const float ASTRA_RAIN_FREQ_X = 6.0;
        const float ASTRA_RAIN_FREQ_Y = 2.2;
        const float ASTRA_RAIN_DENSITY = 0.78;   // cells kept (lower = denser rain)
        vec2 grid = vec2(texcoord.x * ASTRA_RAIN_FREQ_X,
                         (playerPos.y + cameraPosition.y) * 0.06
                         + frameTimeCounter * ASTRA_RAIN_FREQ_Y);
        vec2 cell = floor(grid);
        // Stable repeat: the hash must not contain the moving time index, otherwise
        // every cell re-rolls each frame and the whole field boils. Both hashed
        // indices are world-anchored quantities, only the scroll above is temporal.
        vec2 modIndex = floor(vec2(texcoord.x * ASTRA_RAIN_FREQ_X,
                                   playerPos.y + cameraPosition.y) * 0.5);
        vec2 column = floor((playerPos.xz + cameraPosition.xz) * 0.5);
        float seed = fract(sin(dot(modIndex + column * 17.0, vec2(12.9898, 78.233))) * 43758.5453);
        float alive = fract(seed * 7.31);
        if (alive < ASTRA_RAIN_DENSITY) discard;
        vec2 center = vec2(0.5) + (vec2(fract(seed * 31.7), fract(seed * 71.3)) - 0.5) * 0.7;
        vec2 q = fract(grid) - center;
        float width = mix(0.022, 0.042, fract(seed * 13.1));
        float height = mix(0.15, 0.30, fract(seed * 17.3));
        float d = length(q / vec2(width, height));
        float aa = max(fwidth(d), 0.07);
        float drop = 1.0 - smoothstep(0.75 - aa, 1.0 + aa, d);
        // Held back only in the first ~1.7 blocks, where a full-screen quad is not a
        // credible volume; the previous 1.8-5.5 block ramp hid almost all near rain.
        float nearFade = smoothstep(0.6, 1.7, length(playerPos));
        // Brightness follows rain strength so a light drizzle does not read as a
        // downpour, and the streak itself is much brighter than the old 0.86.
        albedo = vec4(vec3(1.25), drop * clamp(tint.a, 0.0, 1.0) * (0.55 + 0.45 * astraRainFactor) * nearFade);
    }
    if (albedo.a < 0.004) discard;
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
    float puddle = 0.0;
    vec3 puddleNormal = geometricNormal;
    #if defined ASTRA_TERRAIN && !defined ASTRA_TRANSLUCENT && !defined DIMENSION_NETHER && !defined DIMENSION_END
    if (material == 0u && isEyeInWater == 0 && wetness > 0.001) {
        puddle = astra_puddle(playerPos + cameraPosition, geometricNormal, lightLevel.y);
        puddleNormal = astra_puddle_normal(playerPos + cameraPosition);
        albedo.rgb *= 1.0 - 0.22 * wetness * astra_rain_exposure(lightLevel.y);
    }
    #endif
    vec3 directRadiance;
    vec3 color = astra_light(albedo.rgb, normal, playerPos, surfaceShadowPosition,
                             lightLevel.y, lightLevel.x, material, directRadiance);
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
                // Impact rings: the helper already scales by astraRainFactor; this
                // multiplier is the visible strength on a water face. The previous
                // 1.0 was under the threshold of notice in the user's rain round.
                vec3 rings = astra_puddle_normal(playerPos+cameraPosition);
                float exposure = astra_rain_exposure(lightLevel.y);
                normal = normalize(normal + vec3(rings.x,0.0,rings.z)*exposure*4.0);
            }
            #endif
            float roughness = water ? waves.roughness : 0.08;
            vec4 surface = astra_water(color, albedo.a, playerPos, viewPos, normal,
                                       roughness, lightLevel.y, water, geometricNormal);
            color = surface.rgb;
            albedo.a = surface.a;
        } else {
            color = astra_apply_medium(color, playerPos, lightLevel.y);
        }
    #else
        // Opaque ice precedes the copy; its top uses analytic reflection (design 4.3).
        if (iceTop) {
            vec3 ray = reflect(normalize(playerPos), normal);
            float f = 0.0204 + 0.9796 * pow(1.0 - max(dot(-normalize(playerPos), normal), 0.0), 5.0);
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
    #if defined ASTRA_TERRAIN && !defined ASTRA_WATER_PASS
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        if (isEyeInWater == 1 && !iceTop) {
            // IterationT's geometric caustic, multiplied straight into the lit colour the
            // same way the reference multiplies it into its shadow term.
            color *= mix(1.0, astra_water_caustics_focus(playerPos + cameraPosition), 0.70);
        }
        #endif
    #endif
    ASTRA_LIT_COLOR = vec4(max(color, vec3(0.0)), albedo.a);
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
        gl_FragData[1] = vec4(float(lightData) / 255.0, encode_unit_vector(puddleNormal) * 0.5 + 0.5, puddle);
    #endif
}
