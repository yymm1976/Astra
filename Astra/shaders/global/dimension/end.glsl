#ifndef ASTRA_GLOBAL_DIMENSION_END_GLSL
#define ASTRA_GLOBAL_DIMENSION_END_GLSL
#include "/global/dimension/end_blackhole.glsl"
// Solas V2.2b: common.glsl End palette, skyEffects.glsl stars/nebula,
// fog.glsl distance curve and gbuffersLighting.glsl shadow mix.
// Astra: linear HDR boundary, full-screen sky, emissive stellar disc instead
// of vortex, and no atmospheric cloud layers. See THIRD-PARTY.md.
#include "/lib/colors.glsl"
#include "/lib/encoding.glsl"
#include "/lib/solas_water.glsl"
struct EndParams { float nightVision; float heldLightBase; };
const vec3 END_SKY_LIGHT_COLOR = vec3(165.0,125.0,255.0) / 255.0 * 0.90 * vec3(165.0,125.0,255.0) / 255.0 * 0.90;
const vec3 END_AMBIENT_COLOR = vec3(205.0,145.0,255.0) / 255.0 * 0.30 * vec3(205.0,145.0,255.0) / 255.0 * 0.30;
const vec3 END_VOID_COLOR = END_AMBIENT_COLOR * 0.15;
vec3 end_void_tint(float y) { return END_VOID_COLOR; }
float end_noise(vec2 p) { return fract(sin(dot(p, vec2(12.9898,4.1414))) * 43758.5453); }
float end_spiral(vec2 coord){
	float whirl = 20.0;
	float arms = 5.0;

    coord = vec2(atan(coord.y, coord.x) - frameTimeCounter * 0.125, sqrt(coord.x * coord.x + coord.y * coord.y));
    float center = pow(clamp(1.0 - coord.y, 0.0, 1.0), 8.0) * 24.0;
    float spiral = sin((coord.x + sqrt(coord.y) * whirl) * arms) + center - coord.y;

    return clamp(spiral * 0.1, 0.0, 1.0);
}

void end_reference_nebula(inout vec3 color, in vec3 worldPos, in float VoU, inout float nebulaFactor, in float caveFactor) {
	float visibility = ((1.0 - abs(VoU)) * (1.0 - abs(VoU))) * 1.25;

	if (visibility > 0.0) {
		vec3 sunVec = normalize(view_player(lightVector));
		vec2 sunCoord = sunVec.xz / max(sunVec.y + length(sunVec), 0.01);
		vec2 planeCoord1 = worldPos.xz / max(length(worldPos) + worldPos.y, 0.01) - sunCoord;
		vec2 planeCoord2 = worldPos.xz / length(worldPos) - sunCoord;
		float spiral1 = end_spiral(planeCoord1) * clamp(VoU, 0.0, 1.0);
		float spiral2 = end_spiral(planeCoord2) * clamp(VoU, 0.0, 1.0);
			 planeCoord1 += cameraPosition.xz * 0.0001;
			 planeCoord2 += cameraPosition.xz * 0.0001;
			 planeCoord1 += spiral1;
			 planeCoord2 += spiral2 * 2.0;

		float nebulaNoise1  = texture(solasWaterNoise, planeCoord1 * 0.01 + frameTimeCounter * 0.0001).r;
			  nebulaNoise1 += texture(solasWaterNoise, planeCoord1 * 0.02 - frameTimeCounter * 0.0002).r * 0.500;
			  nebulaNoise1 += texture(solasWaterNoise, planeCoord1 * 0.04 + frameTimeCounter * 0.0003).r * 0.250;
			  nebulaNoise1 += texture(solasWaterNoise, planeCoord1 * 0.08 - frameTimeCounter * 0.0004).r * 0.250;
			  nebulaNoise1 += texture(solasWaterNoise, planeCoord1 * 0.16 + frameTimeCounter * 0.0005).r * 0.125;
			  nebulaNoise1 = clamp(nebulaNoise1 - 0.7, 0.0, 1.0);
		float nebulaNoise2  = texture(solasWaterNoise, planeCoord2 * 0.02 - frameTimeCounter * 0.00015).r;
			  nebulaNoise2 += texture(solasWaterNoise, planeCoord2 * 0.04 + frameTimeCounter * 0.00030).r * 0.75;
			  nebulaNoise2 += texture(solasWaterNoise, planeCoord2 * 0.08 - frameTimeCounter * 0.00060).r * 0.50;
			  nebulaNoise2 = clamp(nebulaNoise2 - 0.8, 0.0, 1.0);

		color += mix(mix(END_AMBIENT_COLOR, END_SKY_LIGHT_COLOR, nebulaNoise1), mix(vec3(2.0, 0.8, 0.2), vec3(0.1, 2.1, 0.8), nebulaNoise1), texture(solasWaterNoise, planeCoord1 * 0.025).r * 0.4) * visibility * nebulaNoise1;
		color += mix(vec3(2.3, 0.8, 0.5), vec3(1.2, 2.2, 0.9), nebulaNoise2 - 0.25) * visibility * (nebulaNoise2 * nebulaNoise2) * 0.125;
		nebulaFactor = (nebulaNoise1 + nebulaNoise2) * visibility;
	}
}

vec3 end_sky(vec3 dir, vec3 voidTint, float time) {
    dir = normalize(dir);
    vec3 sky = END_VOID_COLOR;
    float nebula = 0.0;
    #ifdef END_NEBULA
    end_reference_nebula(sky, dir, dir.y, nebula, 1.0);
    #endif
    // Emission and terrain shadows use exactly the same shadow-light direction.
    vec3 stellarDirection = normalize(view_player(lightVector));
    // IterationT 3.2 port. Everything the brief asks for - the deep space background with
    // a warped star field, the black event horizon, the thin blue-white photon ring, the
    // tilted accretion disc grading from white-blue through gold to dark red with Doppler
    // beaming, and the lensed arcs - comes out of one 50-step march whose ray is bent
    // toward the singularity at every step. The hand-written analytic version this
    // replaces could not reproduce that because it evaluated one static angle instead of
    // integrating the bend. Provenance and the Astra adapters are documented in
    // global/dimension/end_blackhole.glsl.
    astra_end_blackhole(sky, dir, stellarDirection);
    return sky * (1.0 - max(blindness, darknessFactor));
}
vec4 end_fog(out float skyFogStrength, float distanceToEye, float borderDistance, vec3 playerPos) {
    skyFogStrength = 0.0;
    float f = 1.0 - exp(-2.0 * pow(borderDistance / max(borderFogDistance, 1.0), 4.0) * (END_FOG_DENSITY * 0.01));
    vec3 c = END_VOID_COLOR;
    float dark = max(blindness, darknessFactor);
    if (dark > 0.0) { f = max(f, 1.0-exp(-distanceToEye * dark * 0.1)); c *= 1.0-dark; }
    if (isEyeInWater == 2) { f = 1.0-exp(-distanceToEye*2.0); c=vec3(1.0,0.05,0.0); }
    return vec4(c, f);
}
vec3 end_lighting(vec3 albedo, vec3 normal, vec3 playerPos, vec3 shadowPos,
                  float blockLight, float emissive, float portal, float time, EndParams params) {
    float ndotl = max(dot(normal, normalize(view_player(lightVector))), 0.0);
    float visibility = 1.0;
    #ifdef SHADOWS
    visibility = mix(1.0, shadow_opaque_visibility(shadowPos), shadow_coverage(playerPos, shadowPos));
    #endif
    // Solas shadow mixing and palette. Astra uses a brighter diffuse response
    // below to keep the island readable with its separate exposure/tonemap.
    // This response is an artistic adaptation, not a color-space conversion.
    vec3 scene = mix(END_AMBIENT_COLOR, END_SKY_LIGHT_COLOR, visibility * ndotl) * 0.25;
    scene += solasMinLight + params.nightVision * vec3(0.2,0.3,0.2);
    vec3 factor = sqrt(max(scene, vec3(0.0))) * 1.22;
    vec3 local = block_lighting(0.0, blockLight, held_light_strength(params.heldLightBase, playerPos), 0.0, 0.0);
    return albedo * (factor + local + (emissive + portal * 2.0) * (EMISSIVE_STRENGTH * 0.01));
}
#endif
