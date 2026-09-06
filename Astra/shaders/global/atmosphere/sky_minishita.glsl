#ifndef ASTRA_GLOBAL_ATMOSPHERE_SKY_MINISHITA_GLSL
#define ASTRA_GLOBAL_ATMOSPHERE_SKY_MINISHITA_GLSL

// Astra v1 - two-view-sample mini atmosphere.
// Uniforms: worldSunVector, sunProgress, moonProgress, skyVisibilityDay, rainStrength.
// Original Astra implementation. The integration layout follows the public Minishita idea
// (tiny spherical atmosphere, very few samples); no reference-pack expression is copied.

const float ASTRA_PI = 3.14159265359;
const float ASTRA_PLANET_RADIUS = 1.0;
const float ASTRA_ATMOS_RADIUS = 1.035;
const float ASTRA_RAYLEIGH_HEIGHT = 0.010;
const float ASTRA_MIE_HEIGHT = 0.0040;
const vec3 ASTRA_BETA_R = vec3(5.6, 12.8, 30.0);
const float ASTRA_BETA_M = 3.4;
const float ASTRA_MIE_G = 0.76;

float astra_atmos_exit(vec3 origin, vec3 direction, float radius) {
	float b = dot(origin, direction);
	float c = dot(origin, origin) - radius * radius;
	return max(0.0, -b + sqrt(max(0.0, b * b - c)));
}

vec2 astra_atmos_density(vec3 position) {
	float height = max(0.0, length(position) - ASTRA_PLANET_RADIUS);
	return exp(-height / vec2(ASTRA_RAYLEIGH_HEIGHT, ASTRA_MIE_HEIGHT));
}

float astra_phase_rayleigh(float cosineTheta) {
	return 3.0 * (1.0 + cosineTheta * cosineTheta) / (16.0 * ASTRA_PI);
}

// Cornette-Shanks phase; the denominator clamp also makes the sun-centre pixel finite.
float astra_phase_mie(float cosineTheta) {
	float g2 = ASTRA_MIE_G * ASTRA_MIE_G;
	float base = max(1.0 + g2 - 2.0 * ASTRA_MIE_G * cosineTheta, 0.006);
	return 3.0 * (1.0 - g2) * (1.0 + cosineTheta * cosineTheta)
	     / (8.0 * ASTRA_PI * (2.0 + g2) * base * sqrt(base));
}

vec3 astra_minishita_sky(vec3 worldDir) {
	vec3 viewDir = normalize(vec3(worldDir.x, max(worldDir.y, -0.045), worldDir.z));
	vec3 observer = vec3(0.0, ASTRA_PLANET_RADIUS + 0.0008, 0.0);
	float distanceToTop = astra_atmos_exit(observer, viewDir, ASTRA_ATMOS_RADIUS);

	// Use whichever celestial body is above the horizon. The moon reuses the optical path at
	// a much lower irradiance, avoiding a second integration and keeping this below the D2 budget.
	float daylight = step(0.0, worldSunVector.y);
	vec3 sourceDir = normalize(mix(-worldSunVector, worldSunVector, daylight));
	float sourceStrength = mix(0.055 + 0.025 * moonProgress, 1.0, daylight);
	float mu = dot(viewDir, sourceDir);
	float phaseR = astra_phase_rayleigh(mu);
	float phaseM = astra_phase_mie(mu);

	vec2 opticalView = vec2(0.0);
	vec3 scatteredR = vec3(0.0);
	vec3 scatteredM = vec3(0.0);
	float segment = distanceToTop * 0.5;

	// Two midpoint view samples and one midpoint light sample at each view point.
	for (int i = 0; i < 2; ++i) {
		vec3 samplePos = observer + viewDir * (segment * (float(i) + 0.5));
		vec2 density = astra_atmos_density(samplePos);
		opticalView += density * segment;

		float lightDistance = astra_atmos_exit(samplePos, sourceDir, ASTRA_ATMOS_RADIUS);
		vec2 opticalLight = astra_atmos_density(samplePos + sourceDir * (0.5 * lightDistance))
		                  * lightDistance;
		vec2 optical = opticalView + opticalLight;
		vec3 extinction = exp(-(ASTRA_BETA_R * optical.x + vec3(ASTRA_BETA_M * optical.y)));
		scatteredR += density.x * extinction * segment;
		scatteredM += density.y * extinction * segment;
	}

	vec3 radiance = (scatteredR * ASTRA_BETA_R * phaseR
	               + scatteredM * ASTRA_BETA_M * phaseM) * sourceStrength;
	float night = 1.0 - skyVisibilityDay;
	radiance += vec3(0.0035, 0.0065, 0.014) * night * (0.35 + 0.65 * max(viewDir.y, 0.0));
	radiance *= mix(1.0, 0.58, rainStrength);

	// The spherical approximation has no terrain occluder. Fade its small negative-y safety band
	// to a ground haze so rays below the horizon never expose the far side of the atmosphere.
	vec3 groundHaze = mix(vec3(0.008, 0.011, 0.016), radiance, 0.32);
	return max(vec3(0.0), mix(groundHaze, radiance, smoothstep(-0.045, 0.018, worldDir.y)));
}

#endif
