// Astra E1/E2. Single lit fragment entry for native geometry.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/program/scene.glsl"
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
    #if defined ASTRA_WEATHER && !defined DIMENSION_NETHER && !defined DIMENSION_END
    if (temperature > 0.15) {
        // Procedural clear droplets within each weather sheet, no blue atlas RGB.
        vec2 cell = vec2(texcoord.x * 9.0, texcoord.y * 3.0);
        vec2 id = floor(cell);
        float seed = fract(sin(dot(id,vec2(12.9898,78.233))) * 43758.5453);
        vec2 q = fract(cell) - vec2(0.25+0.5*seed,0.5);
        float width = 0.045 * (1.0 - q.y * 0.65);
        float d = length(vec2(q.x / width, q.y / 0.28));
        float aa = max(fwidth(d),0.08);
        float drop = 1.0-smoothstep(0.75-aa,1.0+aa,d);
        albedo = vec4(vec3(0.82),drop * tint.a * 0.26);
    }
    if (albedo.a < 0.003) discard;
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
