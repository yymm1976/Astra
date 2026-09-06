// Astra E1. Original integration; varying contract is frozen in design 3.2.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/encoding.glsl"
#include "/global/lighting/wind.glsl"
#ifdef ASTRA_TERRAIN
in vec4 mc_Entity;
in vec3 at_midBlock;
#endif
out vec2 texcoord;
out vec2 lightcoord;
out vec4 tint;
flat out uint faceData;
uint astra_material(int id) {
    if (id >= 10001 && id <= 10007) return uint(id - 10000);
    if (id == 10010) return 8u;
    if (id == 10011) return 9u;
    if (id >= 10021 && id <= 10027) return 10u;
    return 0u;
}
void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lightcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    tint = gl_Color;
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
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    #if defined ASTRA_TERRAIN && defined WAVING_FOLIAGE
        vec3 playerPos = mat3(gbufferModelViewInverse) * viewPos.xyz;
        bool ground = material == 4u || material == 5u || material == 6u;
        bool top = material == 6u || ((material == 4u || material == 5u) && at_midBlock.y < 0.0);
        wave_foliage(material == 2u, ground, top, playerPos);
        viewPos.xyz = mat3(gbufferModelView) * playerPos;
    #endif
    gl_Position = gl_ProjectionMatrix * viewPos;
}