#ifndef ASTRA_GLOBAL_DIMENSION_OVERWORLD_GLSL
#define ASTRA_GLOBAL_DIMENSION_OVERWORLD_GLSL

// Astra v1 - overworld sky/light facade.
// Uniforms: worldSunVector, sunProgress, moonProgress, skyVisibilityDay, sunrise,
//           rainStrength, frameTimeCounter.
// Requires the atmosphere modules to be defined before this file is included.

vec3 astra_sky_radiance(vec3 worldDir) {
#if SKY_MODE == SKY_GRADIENT
	vec3 sky = astra_gradient_sky(worldDir);
#else
	vec3 sky = astra_minishita_sky(worldDir);
#endif
#ifdef LIGHTNING_FLASH
	// Sky-wide part of a thunderstorm flash. Before this the bolt only existed as a point
	// light, so the terrain lit up while the sky behind it stayed black.
	// eyeBrightnessSmooth.y is the same sky exposure the point light gates on.
	sky += astra_lightning_sky_flash(worldDir, eyeBrightnessSmooth.y / 240.0);
#endif
	return sky;
}

vec3 astra_sky_ambient() {
	vec3 dayAmbient = mix(vec3(0.12, 0.20, 0.34), vec3(0.23, 0.38, 0.68), sunProgress);
	vec3 nightAmbient = mix(vec3(0.012, 0.020, 0.045), vec3(0.025, 0.045, 0.090), moonProgress);
	// C1 owns the user strength multiplier. This interface returns the untuned HDR colour so
	// every lighting consumer applies SKYLIGHT_STRENGTH exactly once.
	vec3 ambient = mix(nightAmbient, dayAmbient, skyVisibilityDay);
	return mix(ambient, vec3(dot(ambient, vec3(0.25, 0.65, 0.10))) * 0.78, rainStrength * 0.55);
}

// Reflection deliberately omits sun/moon discs and the star field. Roughness raises the
// effective horizon and blends toward ambient, suppressing distant high-frequency contrast.
// 2026-09-07 visual round: ambient mix 0.58 -> 0.22 so the reflected sky reads as the
//   sky itself (matching Steadfast/Solas), only the roughest ripples drift toward ambient.
//   The earlier 0.58 turned the water surface into flat grey at distance ("水面偏灰").
// SC-35: distant water kept dense parallel stripes because the wave-perturbed sky
//   direction stayed contrasty at any range. Roughness grows with distance
//   (screen-space slope variance), so convergence now scales with it: near-mirror
//   keeps the sky, distant/rough water converges to the smooth ambient dome.
vec3 astra_sky_reflection(vec3 worldDir, float roughness) {
	float r = clamp(roughness, 0.0, 1.0);
	vec3 safeDir = normalize(vec3(worldDir.x, max(worldDir.y, mix(-0.03, 0.10, r)), worldDir.z));
	float convergence = r * r * mix(0.22, 1.0, smoothstep(0.10, 0.40, r));
	return mix(astra_sky_radiance(safeDir), astra_sky_ambient(), convergence);
}

vec3 astra_direct_light() {
	vec3 sun = mix(vec3(1.30, 0.48, 0.17), vec3(1.05, 0.93, 0.78), sunProgress)
	         * (SUNLIGHT_STRENGTH * 0.01);
	vec3 moon = mix(vec3(0.22, 0.30, 0.52), vec3(0.34, 0.43, 0.68), moonProgress)
	          * (MOONLIGHT_STRENGTH * 0.01);
	vec3 direct = mix(moon, sun, skyVisibilityDay);
	return direct * mix(1.0, 0.22, astraRainFactor);
}

vec3 astra_overworld_sky(vec3 worldDir) {
	vec3 sky = astra_sky_radiance(worldDir);
#ifdef STARS
	sky += astra_star_field(worldDir);
#endif
	return sky;
}

#endif
