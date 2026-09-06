// Astra E1/E2. Single lit fragment entry for native geometry.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/program/scene.glsl"
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
    #include "/global/water/caustics.glsl"
#endif
#ifdef ASTRA_WATER_PASS
    #include "/program/water.glsl"
#endif
in vec2 texcoord;
in vec2 lightcoord;
in vec4 tint;
flat in uint faceData;
#ifdef ASTRA_TRANSLUCENT
    /* RENDERTARGETS: 0 */
#else
    /* RENDERTARGETS: 0,3 */
#endif

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    float depth = gl_FragCoord.z;
    #ifdef ASTRA_HAND
        depth = ((depth * 2.0 - 1.0) / MC_HAND_DEPTH) * 0.5 + 0.5;
    #endif
    vec3 viewPos = screen_view(vec3(uv, depth));
    vec3 playerPos = view_player(viewPos);
    float pixelFootprint = max(length(dFdx(playerPos)), length(dFdy(playerPos)));
    vec3 normal = unpack_octahedral(faceData, 9);
    uint material = (faceData >> 18) & 15u;
    bool water = material == 1u;
    bool iceTop = material == 9u && normal.y > 0.99;
    #ifdef ASTRA_WATER_PASS
        // Evaluate derivatives before alpha rejection or divergent material flow.
        WaterSurface waves = water_surface(playerPos + cameraPosition, normal, frameTimeCounter);
        if (water) normal = waves.normal;
    #endif
    if (!gl_FrontFacing) normal = -normal;
    vec4 albedo = texture(gtexture, texcoord) * tint;
    if (albedo.a < alphaTestRef) discard;
    albedo.rgb = srgb_decode(max(albedo.rgb, vec3(0.0)));
    #ifdef ASTRA_ENTITY
        albedo.rgb = mix(albedo.rgb, srgb_decode(max(entityColor.rgb, vec3(0.0))), entityColor.a);
    #endif
    // Texture coordinates are [8,248]/256 for Minecraft light levels 0..15.
    vec2 lightLevel = clamp((lightcoord * 256.0 - 8.0) / 240.0, 0.0, 1.0);
    #if defined ASTRA_WEATHER && (defined DIMENSION_NETHER || defined DIMENSION_END)
        discard;
    #endif
    vec3 color = astra_light(albedo.rgb, normal, playerPos, lightLevel.y, lightLevel.x, material);
    #if defined WATER_CAUSTICS && defined SHADOWS && !defined DIMENSION_NETHER && !defined DIMENSION_END
        if (!water && lightLevel.y > 0.0) {
            vec3 shadowPos = shadow_map_position(playerPos, normal, dot(normal, view_player(lightVector)));
            float caustics = water_caustics(playerPos, shadowPos, frameTimeCounter, pixelFootprint);
            color *= 1.0 + caustics * lightLevel.y * max(dot(normal, view_player(lightVector)), 0.0);
        }
    #endif
    #ifdef ASTRA_WATER_PASS
        if (water || iceTop) {
            float roughness = water ? waves.roughness : 0.08;
            vec4 surface = astra_water(color, albedo.a, playerPos, viewPos, normal,
                                       roughness, lightLevel.y, water);
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
    gl_FragData[0] = vec4(max(color, vec3(0.0)), albedo.a);
    #ifndef ASTRA_TRANSLUCENT
        // Seven light bits retain more precision than the 16 Minecraft light levels.
        // The high bit carries the projection override across the deferred boundary.
        uint lightData = uint(round(lightLevel.y * 127.0));
        #ifdef ASTRA_HAND
            lightData |= 128u;
        #endif
        gl_FragData[1] = vec4(float(lightData) / 255.0, 0.0, 0.0, 1.0);
    #endif
}
