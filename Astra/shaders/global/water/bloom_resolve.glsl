// Read the linear HDR scene pyramid captured after water composition.
// Shared bloom implementation/provenance: global/post/bloom.glsl.
#include "/lib/water_palette.glsl"
void getBloom(inout vec3 color, vec2 coord) {
    // ITT 3.2 Final.glsl mixes scene and low-frequency colour in linear space.
    // Preserve constant colour/energy instead of adding a second fog layer.
    float amount = 0.0;
    float depth = textureLod(depthtex0, coord, 0.0).r;
    if (depth < 0.999999) {
        // Single linear view-Z reconstruction on the same rasterized grid the
        // pyramid was captured on; no extra scene-colour read.
        float ndc = depth * 2.0 - 1.0;
        float linearDepth = abs((gbufferProjectionInverse[2].z * ndc + gbufferProjectionInverse[3].z)
                              / (gbufferProjectionInverse[2].w * ndc + gbufferProjectionInverse[3].w));
        float fogFactor = 1.1
            - exp(-linearDepth * 0.07 * 0.6931472 * astra_water_fog_density());
        // The reference's extinction and light response provide the atmosphere;
        // replacing up to 85% of this scene with broad bloom erased bed detail.
        amount = clamp(max(0.06, fogFactor*0.35) * (BLOOM_STRENGTH * 0.01), 0.0, 0.38);
        // The compressed hand depth and close interfaces retain their detail.
        amount *= smoothstep(2.0, 8.0, linearDepth);
    }
    if (amount <= 0.0) return;
    // Water uses only the two tightest levels (4/8-pixel footprints), rather
    // than the air glow's 16/32-pixel tail. Both weights sum to one.
    vec3 softScene = textureLod(colortex2,coord,0.0).rgb*0.8
                   +textureLod(colortex2,coord,1.0).rgb*0.2;
    color = mix(color, max(softScene,vec3(0.0)), amount);
}
