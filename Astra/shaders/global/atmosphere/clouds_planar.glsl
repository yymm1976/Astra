#ifndef ASTRA_GLOBAL_ATMOSPHERE_CLOUDS_PLANAR_GLSL
#define ASTRA_GLOBAL_ATMOSPHERE_CLOUDS_PLANAR_GLSL
#include "/lib/twilight.glsl"

// ============================================================
//  Astra v1 - planar cloud sheet, shaped and shaded with the
//  Complementary r5.9 (Reimagined) cloud model.
//  Reference root: _analysis/Complementary r5.9/Reimagined/shaders/
//    lib/atmospherics/clouds/cloudCoord.glsl:4-28
//        cloudNarrowness, GetRoundedCloudCoord, ModifyTracePos
//    lib/atmospherics/clouds/reimaginedClouds.glsl:3-5, 17-19, 30-146
//        cloudStretch / cloudTallness / cloudRoundness, the vertical noise
//        threshold, the altitude shading and the two-tap light march
//    lib/atmospherics/clouds/mainClouds.glsl:9-16, 82, 91
//        InterleavedGradientNoiseForClouds, thresholdF, Reimagined ambient trim
//    lib/colors/cloudColors.glsl:1-14
//        cloudRainColor / cloudAmbientColor / cloudLightColor
//    lib/colors/lightAndAmbientColors.glsl:6-79
//        lightColor / ambientColor (the inputs cloudColors.glsl needs)
//
//  WHAT CHANGED SHAPE-WISE: the old Astra sheet sampled one flat plane and
//  thresholded a 3-octave noise sum, so every cloud had the same thickness and
//  no lit tops / dark bottoms. The reference marches the ray between
//  cloudAltitude +/- cloudStretch, tests `noise > threshold * 0.5 + 0.25`
//  with a vertical falloff, and shades by the height of the first hit
//  (cloudShading), which is what produces rounded tops and dark undersides.
//
//  ASTRA ADAPTATIONS (the reference parts that cannot be copied as-is):
//   - Noise source: dedicated complementaryCloudNoise binds the original
//     cloud-water.png; geometry and deferred stages share the same source.
//   - Sample count: taken from the CLOUD_QUALITY == 1 branch
//     (reimaginedClouds.glsl:48), which is the branch the reference selects
//     whenever DEFERRED1 is undefined - as it is in Astra.
//   - CLOUD_COVERAGE: Astra's own option; the reference has no equivalent. It
//     is applied as an additive bias on the reference's `threshold * 0.5 +
//     0.25` test, zero at the default 50 so the default look is the reference's.
//   - Light march shadowing (`GetShadowOnCloud`) needs the shadow map, which is
//     the integration task's boundary; lightMult stays 1.0.
//   - `skyFade` (above-void / above-cloud fade) has no Astra equivalent, so it
//     is 1.0; every term it feeds collapses to the reference's skyFadeM = 1.0.
//
//  NOT PORTED (needs a public boundary change - see docs/handoffs/sky-clouds.md):
//   - lib/lighting/cloudShadows.glsl (cloud shadows cast onto the ground)
//   - the mainClouds.glsl:56-78 camera-position precision wrap
//   - AURORA_STYLE / NIGHT_NEBULAE additive terms
// ============================================================

#include "/global/atmosphere/sky_gradient.glsl"
uniform sampler2D complementaryCloudNoise;

// lib/atmospherics/clouds/cloudCoord.glsl:4
const float ASTRA_CLOUD_NARROWNESS = 0.07;
// lib/atmospherics/clouds/reimaginedClouds.glsl:3-5
const float ASTRA_CLOUD_STRETCH   = 4.2;
const float ASTRA_CLOUD_TALLNESS  = ASTRA_CLOUD_STRETCH * 2.0;
const float ASTRA_CLOUD_ROUNDNESS = 0.125;
// lib/atmospherics/clouds/mainClouds.glsl:82 (CLOUDS_REIMAGINED branch)
const float ASTRA_CLOUD_THRESHOLD_F = 4000.0;
// lib/common.glsl:838 - CLOUD_ALT1 default 192
const float ASTRA_CLOUD_ALTITUDE = 192.0;
// reimaginedClouds.glsl:47-48 - CLOUD_QUALITY == 1 branch. Astra defines no
// DEFERRED1, so this is the branch the reference itself would select here.

// lib/atmospherics/clouds/cloudCoord.glsl:7-15 - "Thanks to SixthSurge"
vec2 astra_rounded_cloud_coord(vec2 pos, float cloudRoundness) {
	vec2 coord = pos.yx + 0.5;
	vec2 signCoord = sign(coord);
	coord = abs(coord) + 1.0;
	vec2 i, f = modf(coord, i);
	f = smoothstep(0.5 - cloudRoundness, 0.5 + cloudRoundness, f);
	coord = i + f;
	return (coord - 0.5) * signCoord / 256.0;
}

// lib/atmospherics/clouds/cloudCoord.glsl:17-28
// CLOUD_SPEED_MULT == 100 in the reference, so `wind = syncedTime` (seconds).
vec3 astra_modify_trace_pos(vec3 tracePos, float cloudAltitude) {
	float wind = frameTimeCounter;   // ASTRA MAP: syncedTime
	tracePos.z -= wind;
	tracePos.x += cloudAltitude * 64.0;
	tracePos.xz *= ASTRA_CLOUD_NARROWNESS;
	return tracePos.xyz;
}

// lib/atmospherics/clouds/reimaginedClouds.glsl:22-28 (Astra noise source, see header)
float astra_2d_cloud_sample(vec2 pos) {
	return texture(complementaryCloudNoise, astra_rounded_cloud_coord(pos, ASTRA_CLOUD_ROUNDNESS)).b;
}

// lib/atmospherics/clouds/reimaginedClouds.glsl:7-20, without the colortex3 branch
float astra_cloud_noise(vec3 tracePos, float cloudAltitude) {
	vec3 tracePosM = astra_modify_trace_pos(tracePos, cloudAltitude);
	return astra_2d_cloud_sample(tracePosM.xz);
}

// lib/atmospherics/clouds/mainClouds.glsl:9-16, non-TAA branch
float astra_cloud_ign() {
	return fract(52.9829189 * fract(0.06711056 * gl_FragCoord.x + 0.00583715 * gl_FragCoord.y));
}

// lib/colors/lightAndAmbientColors.glsl:6-79 + lib/colors/cloudColors.glsl:1-14
// Resolved at the reference defaults: SPECIAL_BIOME_WEATHER off, RAIN_STYLE = 1,
// SUN_MOON_DURING_RAIN on (so rainShadowVisReduce = 0.0, lines 56-66), and the
// DEFERRED1 branch of nightClearLightColor (line 76), which is the cloud pass.
void astra_cloud_colors(AstraSkyFactors f, AstraSkyPalette p,
                        out vec3 cloudAmbientColor, out vec3 cloudLightColor) {
	vec3 skyColorNN = max(skyColor, vec3(0.0));

	// :9-27
	vec3 noonClearLightColor   = vec3(0.65, 0.55, 0.375) * 2.05;
	vec3 noonClearAmbientColor = pow(skyColorNN, vec3(0.75)) * 0.85;

	vec3 sunsetClearLightColor   = pow(vec3(0.64, 0.45, 0.3), vec3(1.5 + f.invNoonFactor)) * 5.0;
	vec3 sunsetClearAmbientColor = noonClearAmbientColor * vec3(1.21, 0.92, 0.76) * 0.95;

	vec3 nightClearLightColor   = 0.9 * vec3(0.11, 0.14, 0.20);
	vec3 nightClearAmbientColor = 0.9 * vec3(0.09, 0.12, 0.17) * (1.55 + ASTRA_VS_BRIGHTNESS * 0.77);

	// :44-45
	vec3 dayRainLightColor   = vec3(0.21, 0.16, 0.13) * 0.85 + f.noonFactor * vec3(0.0, 0.02, 0.06);
	vec3 dayRainAmbientColor = vec3(0.2, 0.2, 0.25) * (1.8 + 0.5 * ASTRA_VS_BRIGHTNESS);

	// :47-48
	vec3 nightRainLightColor   = vec3(0.03, 0.035, 0.05) * (0.5 + 0.5 * ASTRA_VS_BRIGHTNESS);
	vec3 nightRainAmbientColor = vec3(0.16, 0.20, 0.3) * (0.75 + 0.6 * ASTRA_VS_BRIGHTNESS);

	// :50-54 - noonFactorDM = noonFactor (non-COMPOSITE1 branch)
	vec3 dayLightColor   = mix(sunsetClearLightColor, noonClearLightColor, f.noonFactor);
	vec3 dayAmbientColor = mix(sunsetClearAmbientColor, noonClearAmbientColor, f.noonFactor);

	// :56-60
	vec3 clearLightColor   = mix(nightClearLightColor, dayLightColor, f.sunVisibility2);
	vec3 clearAmbientColor = mix(nightClearAmbientColor, dayAmbientColor, f.sunVisibility2);

	// :68-72 - rainShadowVisReduce is 0.0 at the defaults above
	vec3 rainLightColor   = mix(nightRainLightColor, dayRainLightColor, f.sunVisibility2) * 2.5;
	vec3 rainAmbientColor = mix(nightRainAmbientColor, dayRainAmbientColor, f.sunVisibility2);

	// :74-75
	vec3 lightColor   = mix(clearLightColor, rainLightColor, f.rainFactor);
	vec3 ambientColor = mix(clearAmbientColor, rainAmbientColor, f.rainFactor);

	// lib/colors/cloudColors.glsl:1
	vec3 cloudRainColor = mix(p.nightMiddle, p.middle, f.sunFactor);

	// lib/colors/cloudColors.glsl:3-14 (CLOUDS_UNBOUND not defined in Astra)
	cloudAmbientColor = mix(ambientColor * (f.sunVisibility2 * (0.55 + vec3(0.2, 0.1, 0.0) * f.noonFactor) + 0.35),
	                        cloudRainColor * 0.5, f.rainFactor);
	cloudLightColor   = mix(lightColor * 1.3, cloudRainColor * 0.45, f.noonFactor * f.rainFactor);

	// lib/atmospherics/clouds/mainClouds.glsl:91 (CLOUDS_REIMAGINED)
	cloudAmbientColor *= 1.0 - 0.25 * f.rainFactor;
    // Warm illuminated edges over a cooler cloud body during the same twilight
    // envelope used by the sky and terrain (Solas separates these two colours).
    float twilight=astra_twilight_strength();
    cloudLightColor=mix(cloudLightColor,cloudLightColor*vec3(1.12,0.88,0.72)
                        +astra_twilight_tint()*0.18,twilight*0.65);
    cloudAmbientColor=mix(cloudAmbientColor,cloudAmbientColor*vec3(0.92,0.94,1.04),twilight);
}

// ------------------------------------------------------------
// Cloud colors come from the reference sky palette.
vec4 astra_planar_cloud(vec3 worldDir) {
	AstraSkyFactors f = astra_sky_factors();
	AstraSkyPalette p = astra_sky_palette(f);
	vec3 cloudAmbientColor, cloudLightColor;
	astra_cloud_colors(f, p, cloudAmbientColor, cloudLightColor);

	vec3 nPlayerPos = normalize(worldDir);
	float VdotU = nPlayerPos.y;
	float VdotS = dot(nPlayerPos, normalize(worldSunVector));
	float dither = astra_cloud_ign();

	// ASTRA OWN: CLOUD_COVERAGE bias, zero at the default 50 so the default
	// test is exactly the reference's `noise > threshold * 0.5 + 0.25`.
	float coverageBias = mix(0.20, -0.20, CLOUD_COVERAGE * 0.01) - 0.04 - 0.28 * f.rainFactor;

	// lib/atmospherics/clouds/reimaginedClouds.glsl:33-41
	float higherPlaneAltitude = ASTRA_CLOUD_ALTITUDE + ASTRA_CLOUD_STRETCH;
	float lowerPlaneAltitude  = ASTRA_CLOUD_ALTITUDE - ASTRA_CLOUD_STRETCH;

	// ASTRA: guard the plane solve first; a horizontal ray makes both distances blow up.
	if (abs(nPlayerPos.y) < 1e-5) return vec4(0.0);
	float lowerPlaneDistance  = (lowerPlaneAltitude  - cameraPosition.y) / nPlayerPos.y;
	float higherPlaneDistance = (higherPlaneAltitude - cameraPosition.y) / nPlayerPos.y;
	float minPlaneDistance = min(lowerPlaneDistance, higherPlaneDistance);
	      minPlaneDistance = max(minPlaneDistance, 0.0);
	float maxPlaneDistance = max(lowerPlaneDistance, higherPlaneDistance);
	if (maxPlaneDistance < 0.0) return vec4(0.0);
	float planeDistanceDif = maxPlaneDistance - minPlaneDistance;

	// skyFade has no Astra equivalent -> skyFadeM is the reference's 1.0 (see header)
	const float skyFadeM = 1.0;

	// lib/atmospherics/clouds/reimaginedClouds.glsl:47-48
	int sampleCount = clamp(int(min(planeDistanceDif, ASTRA_CLOUD_THRESHOLD_F)) / 16, 6, 64);

	// lib/atmospherics/clouds/reimaginedClouds.glsl:55-59
	float stepMult = planeDistanceDif / float(sampleCount);
	vec3 traceAdd = nPlayerPos * stepMult;
	vec3 tracePos = cameraPosition + minPlaneDistance * nPlayerPos;
	tracePos += traceAdd * dither;
	tracePos.y -= traceAdd.y;

	vec4 volumetricClouds = vec4(0.0);

	for (int i = 0; i < sampleCount; i++) {
		tracePos += traceAdd;

		float lTracePosXZ = length(tracePos.xz - cameraPosition.xz);
		if (lTracePosXZ > ASTRA_CLOUD_THRESHOLD_F) break;   // :72

		// lib/atmospherics/clouds/reimaginedClouds.glsl:17-19
		float threshold = clamp(abs(ASTRA_CLOUD_ALTITUDE - tracePos.y) / ASTRA_CLOUD_STRETCH, 0.001, 0.999);
		      threshold = pow2(pow2(pow2(threshold)));
		float noise = astra_cloud_noise(tracePos, ASTRA_CLOUD_ALTITUDE);
		if (noise <= threshold * 0.5 + 0.25 + coverageBias) continue;

		// :94-95 - height within the sheet drives the lit-top / dark-bottom look
		float cloudShading = 1.0 - (higherPlaneAltitude - tracePos.y) / ASTRA_CLOUD_TALLNESS;
		      cloudShading = pow(max0(cloudShading), 0.8);
		// :96
		float VdotSM1 = max0(f.sunVisibility > 0.5 ? VdotS : -VdotS);

		// :99-120, CLOUD_QUALITY >= 2 branch.
		// cloudShadingM uses the non-DEFERRED1 form (Astra has no such pass define)
		// and lightMult stays 1.0 because GetShadowOnCloud needs the shadow map.
		float cloudShadingM = 1.0 - cloudShading;
		float gradientNoise = astra_cloud_ign();

		vec3 cLightPos = astra_modify_trace_pos(tracePos, ASTRA_CLOUD_ALTITUDE);
		// lightVec (composite.glsl:26) == Astra's lightVector (sun by day, moon by night)
		vec3 cLightPosAdd = normalize(mat3(gbufferModelViewInverse) * lightVector) * 0.08 * f.shadowTime;

		float light = 2.0;
		cLightPos += (1.0 + gradientNoise) * cLightPosAdd;
		    light -= astra_2d_cloud_sample(cLightPos.xz) * cloudShadingM;
		cLightPos += gradientNoise * cLightPosAdd;
		    light -= astra_2d_cloud_sample(cLightPos.xz) * cloudShadingM;

		float VdotSM2 = VdotSM1 * f.shadowTime * 0.25;
		      VdotSM2 += 0.5 * cloudShading + 0.08;
		cloudShading = VdotSM2 * light;

		// :122
		vec3 colorSample = cloudAmbientColor * 0.95 * (1.0 - 0.35 * cloudShading)
		                 + cloudLightColor  * 0.9  * (0.1 + cloudShading);
		// :123 - doGlare = isEyeInWater == 0, doGround = false (same as the sky)
		vec3 cloudSkyColor = astra_get_sky(VdotU, VdotS, dither, isEyeInWater == 0, false, f, p);

		// :127-132
		float distanceRatio = (ASTRA_CLOUD_THRESHOLD_F - lTracePosXZ) / ASTRA_CLOUD_THRESHOLD_F;
		float cloudFogFactor = pow2(clamp(distanceRatio, 0.0, 1.0)) * 0.707;
		      cloudFogFactor = mix(1.0, cloudFogFactor, skyFadeM);
		colorSample *= 1.0 - 0.2 * (1.0 - skyFadeM) * max(f.sunVisibility2, f.nightFactor);
		colorSample = mix(cloudSkyColor, colorSample, cloudFogFactor * 0.707);
		// :132 - Astra's blindness is the vanilla darkness effect in [0,1]
		colorSample *= pow2(1.0 - blindness);

		// :134-137 - cloudMult is 1.0 (the lViewPosM branch has no Astra equivalent)
		float cloudDistanceFactor = clamp(distanceRatio, 0.0, 0.75);
		volumetricClouds.a = sqrt(cloudDistanceFactor * 1.33333);
		volumetricClouds.rgb = colorSample;
		break;
	}

	// :144 - skyFadeM is 1.0
	volumetricClouds.a *= 0.5 + 0.5 * skyFadeM;

	return volumetricClouds;
}

#endif
