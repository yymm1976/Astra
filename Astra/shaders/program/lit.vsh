// Original Astra integration for native geometry and water interfaces.
#include "/lib/settings.glsl"
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
#define ASTRA_WATER_STATE_FRAME_WRITE
#endif
#if !defined DIMENSION_NETHER && !defined DIMENSION_END && !defined ASTRA_WATER_PASS && !defined ASTRA_WEATHER
#define ASTRA_SURFACE_SHADOW_PLANE
#endif
#include "/lib/uniforms.glsl"
#define ASTRA_HELD_LIGHT_VERTEX
#include "/lib/handheld_light.glsl"
#include "/lib/encoding.glsl"
#include "/lib/transforms.glsl"
#include "/lib/wet_material.glsl"
#include "/lib/ao_material.glsl"
#include "/global/lighting/shadowmap.glsl"
#include "/global/lighting/wind.glsl"
#ifdef ASTRA_TAA
#include "/lib/taa_state.glsl"
uniform sampler2D colortex17;
out vec4 taaPreviousClip;
out float taaPreviousViewDepth;
flat out float taaFoliageValid;
#endif
#ifdef ASTRA_TERRAIN
in vec4 mc_Entity;
in vec3 at_midBlock;
#endif
#ifdef ASTRA_WATER_PASS
flat out int waterRasterProjectionMatches;
#if defined DIMENSION_NETHER || defined DIMENSION_END
in vec4 at_tangent;
out vec3 waterTangent;
out vec3 waterBinormal;
out vec3 waterViewVector;
out float waterViewDistance;
#else
flat out vec3 waterSunCentre;
#if SUN_MOON_MODE == SUN_MOON_VANILLA
flat out vec3 waterSunRight;
flat out vec3 waterSunVertical;
#endif
#endif
#endif
out vec2 texcoord;
out vec2 lightcoord;
out vec4 tint;
out float vertexAO;
out vec3 cameraRelativePosition;
out vec3 surfaceShadowCoordinate;
#ifdef ASTRA_SURFACE_SHADOW_PLANE
flat out vec3 surfaceShadowPlaneNormal;
#endif
flat out uint faceData;
uint astra_material(int id) {
    if (id < 10001 || id > 10040) return 0u;
    if (id == 10033) return 0u; // non-emitting partial shapes; voxel identity is separate
    if (id >= 10001 && id <= 10007) return uint(id - 10000);
    if (id == 10010) return 8u;
    if (id == 10011) return 9u;
    if (id == 10012) return 11u;
    // E3 2026-09-22. Rock classes for current AO eligibility, wetness and reflection response. The 4-bit material field has
    // values 0..11 in use (0 default, 1..7 block.properties classes, 8 glass, 9 ice,
    // 10 emissive, 11 end stone), so 12..15 are free and no bit extension is needed:
    // The octahedral normal keeps its 18-bit layout and no existing class changes
    // value. Bit 22 tags End obsidian; bits 23..24 carry the independent wet class.
    if (id == 10013) return 12u;   // netherrack
    if (id == 10014) return 13u;   // blackstone / basalt family
    if (id == 10015) return 14u;   // deepslate family
    if (id == 10016) return 15u;   // stone / cobblestone family
    if (id >= 10021 && id <= 10030) return 10u;
    if (id >= 10034 && id <= 10040) return 10u;
    return 0u;
}
void main() {
    #if defined ASTRA_WEATHER && !defined DIMENSION_NETHER && !defined DIMENSION_END
    // The fragment's rain opacity is uniformly zero at this factor. Clip the
    // whole curtain before vertex work and rasterization; snow keeps its path.
    if (temperature > 0.15 && astraRainFactor <= 0.0) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        return;
    }
    #endif
    #ifdef ASTRA_WATER_STATE_FRAME_WRITE
    // The medium record cannot change during this geometry draw. Supply the
    // same identity to lighting, AO and fog without fragment-side state reads.
    waterMaterialThinSheet = water_is_thin_sheet() ? 1 : 0;
    #endif
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lightcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    tint = gl_Color;
    vertexAO = 1.0;
    #if defined ASTRA_TERRAIN && defined SHADOWS
        vertexAO = clamp(gl_Color.a,0.0,1.0);
        // AO is not opacity. Only terrain receives the separateAo contract.
        tint.a = 1.0;
        #ifndef DIMENSION_NETHER
        #if defined ASTRA_SSAO && !defined ASTRA_TRANSLUCENT && !defined ASTRA_UNLIT_TERRAIN
            // Classified below: AO receivers preserve albedo for ambient-only AO.
        #else
            tint.rgb *= vertexAO;
        #endif
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
    #if defined ASTRA_SSAO && defined ASTRA_TERRAIN && !defined ASTRA_TRANSLUCENT && defined SHADOWS && !defined ASTRA_UNLIT_TERRAIN
    // Mutually exclusive with the early pre-multiply above; ASTRA_SSAO requires
    // SHADOWS and an overworld receiver (settings.glsl).
    if (!astra_ao_receiver(material)) tint.rgb *= vertexAO;
    #endif
    vec3 normal = mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal);
    normal = dot(normal, normal) > 1e-8 ? normalize(normal) : vec3(0.0, 1.0, 0.0);
    #ifdef ASTRA_SURFACE_SHADOW_PLANE
    surfaceShadowPlaneNormal = vec3(0.0);
    #if defined ASTRA_TERRAIN && defined SHADOWS
    // Static block faces have an exact plane independent of screen orientation.
    // Displaced plants retain the actual triangle's derivative reconstruction.
    if (material != 2u && material != 4u && material != 5u && material != 6u)
        surfaceShadowPlaneNormal = (mat3(shadowModelView) * normal)
            / vec3(shadowProjection[0][0],shadowProjection[1][1],shadowProjection[2][2]);
    #endif
    #endif
    faceData = pack_octahedral(normal, 9) | (material << 18);
    #if defined ORE_GLOW && defined ASTRA_TERRAIN && !defined ASTRA_TRANSLUCENT
    // Keep the normal, four-bit material, wet class and dimension flags intact.
    int oreBlock = int(mc_Entity.x + 0.5);
    uint oreType = oreBlock >= 10041 && oreBlock <= 10048 ? uint(oreBlock - 10040) : 0u;
    if (oreBlock == 10034) oreType = 3u; // triggered redstone keeps its old emitter ID
    faceData |= oreType << 27;
    #endif
    #if defined DIMENSION_NETHER && defined ASTRA_TERRAIN
    // Preserve lava identity separately from the shared emissive category.
    if (int(mc_Entity.x + 0.5) == 10030) faceData |= 1u << 25;
    // Bit 26 is Nether masonry only; the shared four-bit material stays intact.
    if (int(mc_Entity.x + 0.5) == 10018) faceData |= 1u << 26;
    #endif
    #if defined ASTRA_TERRAIN && !defined DIMENSION_NETHER && !defined DIMENSION_END
        faceData |= astra_wet_class(int(mc_Entity.x + 0.5)) << 23;
    #endif
    #ifdef DIMENSION_END
    #if defined ASTRA_TERRAIN
        if(int(mc_Entity.x+0.5)==10017) faceData|=1u<<22;
    #elif defined ASTRA_BLOCK
        if(blockEntityId==10017) faceData|=1u<<22;
    #elif defined ASTRA_HAND
        if(currentRenderedItemId==10017) faceData|=1u<<22;
    #endif
    #endif
    #ifdef HANDHELD_LIGHTING
    astraHeldLightTint = astra_compute_held_light_tint();
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
    // Decide once per vertex, including hand-water's distinct projection.
    // Only matching native projection can reuse the raster clip coordinate.
    waterRasterProjectionMatches = int(all(equal(gl_ProjectionMatrix[0],gbufferProjection[0]))
        && all(equal(gl_ProjectionMatrix[1],gbufferProjection[1]))
        && all(equal(gl_ProjectionMatrix[2],gbufferProjection[2]))
        && all(equal(gl_ProjectionMatrix[3],gbufferProjection[3])));
    #endif
    #if defined ASTRA_WATER_PASS && (defined DIMENSION_NETHER || defined DIMENSION_END)
        waterTangent = normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * at_tangent.xyz));
        waterBinormal = normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * cross(at_tangent.xyz, gl_Normal.xyz) * at_tangent.w));
        vec3 worldView = view_player(viewPos.xyz);
        waterViewVector = vec3(dot(waterTangent, worldView), dot(waterBinormal, worldView), dot(normal, worldView));
        waterViewDistance = length(viewPos.xyz);
    #endif
    #if defined ASTRA_WATER_PASS && !defined DIMENSION_NETHER && !defined DIMENSION_END
    waterSunCentre = normalize(worldSunVector);
    #if SUN_MOON_MODE == SUN_MOON_VANILLA
    vec3 orbitRight = vec3(0.0,sin(radians(sunPathRotation)),cos(radians(sunPathRotation)));
    waterSunRight = normalize(orbitRight-waterSunCentre*dot(orbitRight,waterSunCentre));
    waterSunVertical = cross(waterSunRight,waterSunCentre);
    #endif
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
    float weatherSkyAccess = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
    // Fully sheltered weather has no shear; retain the original view position.
    if (weatherSkyAccess > 0.0) {
        vec3 weatherWorld = playerPos + cameraPosition;
        float shearAngle = dot(weatherWorld, vec3(3.0, 0.5, 3.0)) + frameTimeCounter * 0.2;
        vec2 shearRot = vec2(sin(shearAngle), cos(shearAngle));
        vec2 shear = (vec2(ASTRA_RAIN_WIND_X, ASTRA_RAIN_WIND_Z)
                      + shearRot * ASTRA_RAIN_DISTURBANCE) * playerPos.y;
        playerPos.xz += weatherSkyAccess * shear;
        viewPos.xyz = camera_relative_view(playerPos);
    }
    #endif
    #ifdef ASTRA_TAA
    taaPreviousClip=vec4(0.0);
    taaPreviousViewDepth=0.0;
    taaFoliageValid=0.0;
    #if defined ASTRA_TERRAIN && !defined ASTRA_TRANSLUCENT
    bool foliage=material==2u || material==4u || material==5u || material==6u;
    vec4 effects, windState;
    if(foliage && isEyeInWater==0 && astra_taa_state_valid(colortex17,effects,windState)) {
        vec3 previousRelative=playerPos+(cameraPosition-previousCameraPosition);
        bool previousWindValid=true;
        #ifdef WAVING_FOLIAGE
        bool previousGround=material==4u || material==5u || material==6u;
        bool previousTop=material==6u || ((material==4u || material==5u) && at_midBlock.y<0.0);
        float previousStrength=0.0;
        if (windState.z != 0.0 && (material==2u || (previousGround && previousTop)))
            previousStrength=windState.z*astra_foliage_wind_lod(previousRelative,material==2u);
        // Anchored bases and fully faded wind keep the same previous position.
        // They still retain valid camera motion, without reading unused phases.
        if (previousStrength != 0.0) {
            vec4 windPhases=texelFetch(colortex17,ivec2(3,0),0);
            // The fourth state texel has its own validity flag. Missing phases
            // must keep moving foliage reactive, rather than invent old motion.
            previousWindValid=windPhases.w==1.0
                && !any(isnan(windPhases)) && !any(isinf(windPhases));
            if (previousWindValid)
                previousRelative+=astra_foliage_displacement(playerPos+cameraPosition,
                    effects.z,windState.y,previousStrength,material==2u,previousGround,previousTop,windPhases.xyz);
        }
        #endif
        if (previousWindValid) {
            vec4 previousView=gbufferPreviousModelView*vec4(previousRelative,1.0);
            taaPreviousClip=gbufferPreviousProjection*previousView;
            taaPreviousViewDepth=-previousView.z;
            taaFoliageValid=1.0;
        }
    }
    #endif
    #endif
    #if defined ASTRA_TERRAIN && defined WAVING_FOLIAGE
        bool ground = material == 4u || material == 5u || material == 6u;
        bool top = material == 6u || ((material == 4u || material == 5u) && at_midBlock.y < 0.0);
        // Only displaced vertices need to rebuild the view-space position.
        if (material == 2u || (ground && top)) {
            if (wave_foliage(material == 2u, ground, top, playerPos))
                viewPos.xyz = camera_relative_view(playerPos);
        }
    #endif
    cameraRelativePosition = playerPos;
    // Native receivers carry the undistorted coordinate. A warped quad is not
    // planar, and its two possible diagonals must not change surface depth.
    #if defined SHADOWS && !defined DIMENSION_NETHER && !defined ASTRA_WEATHER
    float shadowNdotL = dot(normal, astra_shadow_light_direction());
    #if defined ASTRA_TERRAIN && !defined DIMENSION_END && !defined ASTRA_WATER_PASS
    bool shadowReceiver = shadowNdotL > -0.10 || material == 8u;
    #ifdef SSS_FOLIAGE
    if (material >= 2u && material <= 6u)
        shadowReceiver = material != 2u || shadowNdotL > -0.60;
    #endif
    // Flat native face normals cannot become lit after interpolation. The
    // margin also covers their fragment-side octahedral quantization.
    surfaceShadowCoordinate = vec3(0.0);
    if (shadowReceiver)
    #endif
        surfaceShadowCoordinate = shadow_map_position(playerPos, normal, shadowNdotL);
    #else
    // These lighting paths never consume a projected surface shadow coordinate.
    surfaceShadowCoordinate = vec3(0.0);
    #endif
    gl_Position = astra_jitter_clip(gl_ProjectionMatrix * viewPos);
}
