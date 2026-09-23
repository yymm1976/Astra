// Astra E1. Original integration; varying contract is frozen in design 3.2.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/encoding.glsl"
#include "/lib/transforms.glsl"
#include "/global/lighting/shadowmap.glsl"
#include "/global/lighting/wind.glsl"
#ifdef ASTRA_TERRAIN
in vec4 mc_Entity;
in vec3 at_midBlock;
#endif
#ifdef ASTRA_WATER_PASS
in vec4 at_tangent;
out vec3 waterTangent;
out vec3 waterBinormal;
out vec3 waterViewVector;
out float waterViewDistance;
#endif
out vec2 texcoord;
out vec2 lightcoord;
out vec4 tint;
out float vertexAO;
out vec3 cameraRelativePosition;
out vec3 surfaceShadowPosition;
flat out uint faceData;
uint astra_material(int id) {
    if (id >= 10001 && id <= 10007) return uint(id - 10000);
    if (id == 10010) return 8u;
    if (id == 10011) return 9u;
    if (id == 10012) return 11u;
    // E3 2026-09-22. Emitter-driven gloss rock classes. The 4-bit material field has
    // values 0..11 in use (0 default, 1..7 block.properties classes, 8 glass, 9 ice,
    // 10 emissive, 11 end stone), so 12..15 are free and no bit extension is needed:
    // The octahedral normal keeps its 18-bit layout and no existing class changes
    // value. Bit 22 separately tags End obsidian; bits 23..31 remain unused.
    if (id == 10013) return 12u;   // netherrack
    if (id == 10014) return 13u;   // blackstone / basalt family
    if (id == 10015) return 14u;   // deepslate family
    if (id == 10016) return 15u;   // stone / cobblestone family
    if (id >= 10021 && id <= 10030) return 10u;
    return 0u;
}
void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lightcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    tint = gl_Color;
    vertexAO = 1.0;
    #if defined ASTRA_TERRAIN && defined SHADOWS
        vertexAO = clamp(gl_Color.a,0.0,1.0);
        // AO is not opacity. Only terrain receives the separateAo contract.
        tint.a = 1.0;
        #ifndef DIMENSION_NETHER
            tint.rgb *= vertexAO;
        #endif
    #endif
    uint material = 0u;
    #if defined ASTRA_TERRAIN
        material = astra_material(int(mc_Entity.x + 0.5));
    #elif defined ASTRA_BLOCK
        material = astra_material(blockEntityId);
    #elif defined ASTRA_HAND
        material = astra_material(currentRenderedItemId);
    #elif defined ASTRA_ENTITY
        if (entityId >= 100 && entityId <= 103) material = 10u;
        if (entityId == 1) material = 10u;
    #endif
    vec3 normal = mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal);
    normal = dot(normal, normal) > 1e-8 ? normalize(normal) : vec3(0.0, 1.0, 0.0);
    faceData = pack_octahedral(normal, 9) | (material << 18);
    #ifdef DIMENSION_END
    #if defined ASTRA_TERRAIN
        if(int(mc_Entity.x+0.5)==10017) faceData|=1u<<22;
    #elif defined ASTRA_BLOCK
        if(blockEntityId==10017) faceData|=1u<<22;
    #elif defined ASTRA_HAND
        if(currentRenderedItemId==10017) faceData|=1u<<22;
    #endif
    #endif
    vec4 vertex=gl_Vertex;
    #ifdef ASTRA_SKY_TEXTURED
    #if SUN_MOON_MODE == SUN_MOON_VANILLA
    // Vanilla celestial quads lie in XZ at +/-100 Y. Scale around their centre,
    // keeping the supplied moon atlas UVs and all eight phases intact.
    if (renderStage == MC_RENDER_STAGE_SUN || renderStage == MC_RENDER_STAGE_MOON)
        vertex.xz *= 1.12;
    #endif
    #endif
    vec4 viewPos = gl_ModelViewMatrix * vertex;
    #ifdef ASTRA_WATER_PASS
        waterTangent = normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * at_tangent.xyz));
        waterBinormal = normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * cross(at_tangent.xyz, gl_Normal.xyz) * at_tangent.w));
        vec3 worldView = view_player(viewPos.xyz);
        waterViewVector = vec3(dot(waterTangent, worldView), dot(waterBinormal, worldView), dot(normal, worldView));
        waterViewDistance = length(viewPos);
    #endif
    vec3 playerPos = view_camera_relative(viewPos.xyz);
    #if defined ASTRA_WEATHER && !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Rain curtain shear. Ported from IterationT 3.2 Lib/Programs/Gbuffers/Weather_VS.glsl.
    //
    // The whole rain sheet is displaced in world space by an offset PROPORTIONAL TO HEIGHT,
    // so the curtain is slanted rather than vertical, and the disturbance vector rotates
    // per world position and over time, which gives the curtain internal turbulence instead
    // of translating it as a rigid body. This is the layer that actually removes the
    // "picket fence" reading - no amount of colour or alpha work can, because the geometry
    // was the problem.
    //
    // The reference exposes these three as sliders; Astra increases the wind tilt.
    // They are local constants rather than options so this change does not churn the option
    // registry; promote them to sliders if tuning is wanted.
    const float ASTRA_RAIN_WIND_X = 0.24;
    const float ASTRA_RAIN_WIND_Z = 0.12;
    const float ASTRA_RAIN_DISTURBANCE = 0.05;
    {
        vec3 weatherWorld = playerPos + cameraPosition;
        float shearAngle = dot(weatherWorld, vec3(3.0, 0.5, 3.0)) + frameTimeCounter * 0.2;
        vec2 shearRot = vec2(sin(shearAngle), cos(shearAngle));
        vec2 shear = (vec2(ASTRA_RAIN_WIND_X, ASTRA_RAIN_WIND_Z)
                      + shearRot * ASTRA_RAIN_DISTURBANCE) * playerPos.y;
        playerPos.xz += clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0) * shear;
        viewPos.xyz = camera_relative_view(playerPos);
    }
    #endif
    #if defined ASTRA_TERRAIN && defined WAVING_FOLIAGE
        bool ground = material == 4u || material == 5u || material == 6u;
        bool top = material == 6u || ((material == 4u || material == 5u) && at_midBlock.y < 0.0);
        wave_foliage(material == 2u, ground, top, playerPos);
        viewPos.xyz = camera_relative_view(playerPos);
    #endif
    cameraRelativePosition = playerPos;
    // Match the shadow pass's interpolated triangle, including foliage motion.
    // Reprojecting the interior after a nonlinear warp uses a different surface.
    surfaceShadowPosition = shadow_map_position(playerPos, normal,
                                dot(normal, astra_shadow_light_direction()));
    gl_Position = gl_ProjectionMatrix * viewPos;
}
