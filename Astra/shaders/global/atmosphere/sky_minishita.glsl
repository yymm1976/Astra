#ifndef ASTRA_GLOBAL_ATMOSPHERE_SKY_MINISHITA_GLSL
#define ASTRA_GLOBAL_ATMOSPHERE_SKY_MINISHITA_GLSL

// Astra v1 - two-view-sample mini atmosphere.
// Uniforms: worldSunVector, sunProgress, moonProgress, skyVisibilityDay, rainStrength.
// Original Astra implementation. The integration layout follows the public Minishita idea
// (tiny spherical atmosphere, very few samples); no reference-pack expression is copied.
//
// ★ ASTRA-OWNED DESIGN - KEPT AS IS (2026-09-10 sky/cloud worktree).
//   The reference pack for this task (Complementary r5.9) has NO physically-based
//   atmosphere: its sky is the artist "up / middle / down" spherical model, which was
//   ported into global/atmosphere/sky_gradient.glsl instead. This file therefore has no
//   counterpart to copy from, and per the task constraint ("参考没有的（Astra 自有设计）
//   保留并标注") its scattering structure is left untouched - only this header changed.
//
//   Known open issues, all inherent to this model and NOT addressed here:
//     - The 2x1 sample budget over-extincts blue on long grazing paths, so the horizon
//       drifts olive; ASTRA_SKY_HORIZON_ELEVATION clamps at 0.10 instead of resolving it.
//     - No ambient floor term, which is why the day gain needs ASTRA_SKY_DAY_GAIN = 22.
//   A different reference (Steadfast-0.8.0/shaders/environment/sky/minishita.glsl) has a
//   structurally better version of the same idea (0.15/0.65 non-uniform view samples,
//   t = 0.15 light samples, a hardcoded ambient blue and luminance-preserving day/night
//   overrides). Porting it needs four extra CPU-side uniforms
//   (rayleighStrengthSun/Moon, mieStrengthSun/Moon, day/nightSkyOverridePremultiplied,
//   ambientSkyColor), which live in shaders.properties - the integration task's boundary.
//   Raised in docs/handoffs/sky-clouds.md.

const float ASTRA_PI = 3.14159265359;
const float ASTRA_PLANET_RADIUS = 1.0;
const float ASTRA_ATMOS_RADIUS = 1.035;
const float ASTRA_RAYLEIGH_HEIGHT = 0.010;
const float ASTRA_MIE_HEIGHT = 0.0040;
// 2026-09-06 P0-1 calibration (first visual round, docs/2026-09-06-first-visual-round-fix-order.md):
// the raw model output was ~11-23x below the pack's own gradient palette at noon
// (zenith display (0.007,0.047,0.102) vs Steadfast reference ~(0.36,0.51,0.77), and the
// 2-sample light-path estimate over-extincts blue on long horizon paths -> green horizon.
// BETA_R x0.7 and DAY_GAIN 22 were the first-round adjustment. The second-round
// horizon still needed the angular continuation below (SC-32); the historical
// diagnosis script does not model all subsequent changes.
const vec3 ASTRA_BETA_R = vec3(3.92, 8.96, 21.0);
const float ASTRA_BETA_M = 3.4;
const float ASTRA_MIE_G = 0.76;
const float ASTRA_SKY_DAY_GAIN = 22.0;
const float ASTRA_SKY_HORIZON_ELEVATION = 0.10;

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

vec3 astra_minishita_source(vec3 worldDir,vec3 sourceDir,float sourceStrength) {
	// Two view samples cannot resolve the long grazing optical path, and negative
	// rays can enter the solid planet. Continue the stable lower sky into the
	// horizon instead of amplifying its erroneous olive extinction.
	vec3 viewDir = normalize(worldDir);
	if (viewDir.y < ASTRA_SKY_HORIZON_ELEVATION) {
		float horizontalLength = length(viewDir.xz);
		vec2 azimuth = horizontalLength > 1e-5 ? viewDir.xz / horizontalLength : vec2(0.0, 1.0);
		// sqrt(1 - 0.10^2): preserve a fixed elevation, including downward reflections.
		viewDir = vec3(azimuth.x * 0.9949874371, ASTRA_SKY_HORIZON_ELEVATION,
		               azimuth.y * 0.9949874371);
	}
	vec3 observer = vec3(0.0, ASTRA_PLANET_RADIUS + 0.0008, 0.0);
	float distanceToTop = astra_atmos_exit(observer, viewDir, ASTRA_ATMOS_RADIUS);

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
	return max(vec3(0.0),radiance);
}
vec3 astra_minishita_sky(vec3 worldDir) {
    // Only twilight needs both sources. Fade residual sunlight below the horizon
    // instead of switching the entire scattering direction at elevation zero.
    float day=smoothstep(-0.16,0.08,worldSunVector.y);
    vec3 radiance=vec3(0.0);
    if(day>0.0) {
        vec3 sun=normalize(vec3(worldSunVector.x,max(worldSunVector.y,0.01),worldSunVector.z));
        radiance+=astra_minishita_source(worldDir,sun,
                    ASTRA_SKY_DAY_GAIN*mix(0.40,1.0,sunProgress))*day;
    }
    if(day<1.0) {
        vec3 moon=normalize(vec3(-worldSunVector.x,max(-worldSunVector.y,0.01),-worldSunVector.z));
        radiance+=astra_minishita_source(worldDir,moon,0.055+0.025*moonProgress)*(1.0-day);
    }
	float night = 1.0 - skyVisibilityDay;
	radiance += vec3(0.0035, 0.0065, 0.014) * night * (0.35 + 0.65 * max(normalize(worldDir).y, 0.0));
	radiance *= mix(1.0, 0.58, rainStrength);

	// Sky, reflections and fully fogged terrain share this continuation.
	return max(vec3(0.0), radiance);
}

#endif
