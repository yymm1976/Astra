#ifndef ASTRA_WET_MATERIAL_GLSL
#define ASTRA_WET_MATERIAL_GLSL

// ITT 3.2 material-dependent wetness: idea only, original Astra implementation.
// faceData: normal 0..17, material 18..21, End obsidian 22, wet class 23..24.
// Wet classes are independent of the four-bit lighting/emission material field.
uint astra_wet_class(int blockId) {
    if (blockId == 10031) return 1u; // wood
    if (blockId == 10032) return 2u; // soil / loose mineral surfaces
    if (blockId == 10014 || blockId == 10015 || blockId == 10017) return 3u;
    return 0u;
}

// x: damp darkening; y: maximum direct-light gloss gain; z: highlight exponent.
// These are art controls, not measured porosity or a physical water-film BRDF.
vec3 astra_wet_material(uint wetClass) {
    if (wetClass == 1u) return vec3(0.24, 0.10, 16.0);
    if (wetClass == 2u) return vec3(0.30, 0.04, 10.0);
    if (wetClass == 3u) return vec3(0.12, 0.28, 32.0);
    return vec3(0.18, 0.18, 24.0);
}

float astra_wet_gloss(vec3 normal, vec3 viewDir, vec3 lightDir, vec3 response) {
    vec3 halfVector = viewDir + lightDir;
    halfVector *= inversesqrt(max(dot(halfVector, halfVector), 1e-6));
    float facing = clamp(dot(normal, halfVector), 0.0, 1.0);
    return response.y * pow(facing, response.z);
}
#endif
