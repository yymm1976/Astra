#ifndef ASTRA_GLOBAL_WATER_SURFACE_GLSL
#define ASTRA_GLOBAL_WATER_SURFACE_GLSL

// Astra v1 - analytic, footprint-limited water surface.
// New Astra implementation. The wave field is evaluated from absolute world
// coordinates so adjacent chunks share the same phase.
// GLSL derivative semantics: Khronos GLSL 4.00 specification, section 8.8:
// https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.4.00.pdf
//
// Uniforms: none. WATER_WAVE_HEIGHT / WATER_WAVE_SPEED come from settings.glsl.
// Consumer: E2's water branch in program/lit.fsh.

struct WaterSurface {
	vec3 normal;
	float roughness;
};

const float ASTRA_WATER_TAU = 6.28318530718;

// Add one height-field wave and its analytic gradient. Detail is attenuated before
// its phase change across one pixel reaches pi radians (the spatial Nyquist limit).
// The same continuous weight feeds roughness, so filtered detail becomes a broader
// highlight instead of disappearing abruptly.
void water_wave_layer(
	vec2 position,
	vec2 pixelDx,
	vec2 pixelDy,
	vec2 direction,
	float wavelength,
	float amplitude,
	float speed,
	float time,
	inout vec2 slope,
	inout float unresolvedLayers,
	inout float unresolvedSlope
) {
	float waveNumber = ASTRA_WATER_TAU / wavelength;
	float phaseFootprint = max(
		abs(waveNumber * dot(direction, pixelDx)),
		abs(waveNumber * dot(direction, pixelDy)));
	float resolved = 1.0 - smoothstep(0.35 * 3.14159265359, 3.14159265359, phaseFootprint);

	// Deep-water dispersion gives long waves a slower-looking, weightier motion.
	float angularSpeed = sqrt(9.81 * waveNumber) * speed;
	float phase = waveNumber * dot(direction, position) + angularSpeed * time;
	float slopeAmplitude = amplitude * waveNumber;
	slope += direction * (slopeAmplitude * cos(phase) * resolved);

	float unresolved = 1.0 - resolved;
	unresolvedLayers += unresolved;
	unresolvedSlope += slopeAmplitude * unresolved;
}

WaterSurface water_surface(vec3 worldPos, vec3 baseNormal, float time) {
	WaterSurface surface;
	vec3 faceNormal = normalize(baseNormal);
	surface.normal = faceNormal;
	surface.roughness = 0.035;

	// Flowing side faces retain their geometric normal and vanilla texture. Both the
	// upward water surface and its underside are eligible, with matching orientation.
	if (abs(faceNormal.y) <= 0.999) {
		return surface;
	}

#ifdef WATER_WAVES
	vec2 pixelDx = dFdx(worldPos.xz);
	vec2 pixelDy = dFdy(worldPos.xz);
	vec2 slope = vec2(0.0);
	float unresolvedLayers = 0.0;
	float unresolvedSlope = 0.0;
	float heightScale = WATER_WAVE_HEIGHT * 0.01;
	float speedScale = WATER_WAVE_SPEED * 0.01;

	water_wave_layer(worldPos.xz, pixelDx, pixelDy, vec2( 0.970143,  0.242536), 18.0, 0.100 * heightScale, 0.36 * speedScale, time, slope, unresolvedLayers, unresolvedSlope);
	water_wave_layer(worldPos.xz, pixelDx, pixelDy, vec2(-0.554700,  0.832050),  9.0, 0.052 * heightScale, 0.48 * speedScale, time, slope, unresolvedLayers, unresolvedSlope);
	water_wave_layer(worldPos.xz, pixelDx, pixelDy, vec2( 0.196116, -0.980581),  4.5, 0.025 * heightScale, 0.64 * speedScale, time, slope, unresolvedLayers, unresolvedSlope);
	water_wave_layer(worldPos.xz, pixelDx, pixelDy, vec2( 0.780869,  0.624695),  2.2, 0.011 * heightScale, 0.86 * speedScale, time, slope, unresolvedLayers, unresolvedSlope);
	water_wave_layer(worldPos.xz, pixelDx, pixelDy, vec2(-0.894427, -0.447214),  1.1, 0.004 * heightScale, 1.12 * speedScale, time, slope, unresolvedLayers, unresolvedSlope);

	vec3 upwardNormal = normalize(vec3(-slope.x, 1.0, -slope.y));
	surface.normal = upwardNormal * sign(faceNormal.y);
	surface.roughness = clamp(
		0.035 + 0.030 * unresolvedLayers + 0.55 * unresolvedSlope,
		0.035,
		0.30);
#endif

	return surface;
}

#endif
