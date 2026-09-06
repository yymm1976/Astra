#ifndef ASTRA_GLOBAL_ATMOSPHERE_SKY_GRADIENT_GLSL
#define ASTRA_GLOBAL_ATMOSPHERE_SKY_GRADIENT_GLSL

// Astra v1 - inexpensive fallback sky.
// Uniforms: worldSunVector, sunProgress, skyVisibilityDay, sunrise, rainStrength.
// Original Astra palette and interpolation.

vec3 astra_gradient_sky(vec3 worldDir) {
	float up = clamp(worldDir.y, 0.0, 1.0);
	float horizon = exp2(-7.0 * up);
	float day = skyVisibilityDay;
	vec3 nightZenith = vec3(0.004, 0.009, 0.024);
	vec3 nightHorizon = vec3(0.018, 0.024, 0.045);
	vec3 dayZenith = vec3(0.075, 0.20, 0.52);
	vec3 dayHorizon = vec3(0.40, 0.58, 0.78);
	vec3 sky = mix(mix(nightZenith, dayZenith, day),
	               mix(nightHorizon, dayHorizon, day), horizon);

	float towardSun = max(0.0, dot(normalize(worldDir), normalize(worldSunVector)));
	float sunsetBand = sunrise * horizon * pow(towardSun, 5.0);
	sky += vec3(0.85, 0.20, 0.045) * (0.42 * sunsetBand);
	sky = mix(sky, vec3(dot(sky, vec3(0.25, 0.65, 0.10))) * 0.72, rainStrength * 0.58);

	vec3 below = mix(vec3(0.006, 0.009, 0.014), sky, 0.28);
	return max(vec3(0.0), mix(below, sky, smoothstep(-0.04, 0.025, worldDir.y)));
}

#endif
