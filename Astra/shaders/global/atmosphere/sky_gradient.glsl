#ifndef ASTRA_GLOBAL_ATMOSPHERE_SKY_GRADIENT_GLSL
#define ASTRA_GLOBAL_ATMOSPHERE_SKY_GRADIENT_GLSL

// ============================================================
//  Astra v1 - overworld sky, ported from Complementary r5.9 (Reimagined).
//  This is the "up / middle / down" three-direction spherical model
//  (VdotU = view.up, VdotS = view.sun), NOT a single vertical gradient.
//
//  PROVENANCE - every expression below is copied from the reference pack.
//  Reference root: _analysis/Complementary r5.9/Reimagined/shaders/
//    lib/atmospherics/sky.glsl:11-99           GetSky()                -> astra_get_sky()
//    lib/colors/skyColors.glsl:5-54            noon/sunset/night palettes
//                                                                      -> astra_sky_palette()
//    lib/util/commonFunctions.glsl:21-23       GetLuminance
//    lib/util/commonFunctions.glsl:126-140     min1 / max0 / clamp01
//    lib/util/commonFunctions.glsl:151-153     pow2
//    lib/util/commonFunctions.glsl:193-210     sqrt1 / sqrt2
//    lib/util/commonFunctions.glsl:229-235     sqrt3
//    lib/util/commonFunctions.glsl:290-292     smoothstep1
//    lib/atmospherics/clouds/mainClouds.glsl:9-16
//                                              InterleavedGradientNoiseForClouds
//                                                                      -> astra_sky_dither()
//    program/composite.glsl:30-36              SdotU / sunFactor / sunVisibility / shadowTime
//    lib/common.glsl:740-746                   noonFactor / nightFactor / rainFactor2 /
//                                              invNoonFactor / invNoonFactor2 / invRainFactor
//    program/gbuffers_skybasic.glsl:83         sky call uses (doGlare = true, doGround = false)
//
//  ASTRA MAPPING - the reference factors that Astra has no uniform for. Each is
//  listed with the Astra input it is derived from; everything else is verbatim.
//    sunFactor / sunVisibility / shadowTime
//        verbatim from SdotU = worldSunVector.y (reference: dot(sunVec, upVec)).
//    noonFactor      <- sqrt of normalized solar elevation; geometric analogue
//                       of the reference sqrt(max(sin(timeAngle*2pi),0)), with
//                       Astra's tilted solar path divided out.
//    nightFactor     <- 1.0 - skyVisibilityDay (reference: max(sin(-timeAngle*2pi),0);
//                                               same 1-at-midnight / 0-at-noon endpoints)
//    rainFactor      <- rainStrength           (reference smooths it: `smooth(1, rainStrength, 3, 3)`)
//    dither          <- astra_sky_dither()     (reference pulls a per-pixel IGN value; the
//                                               formula is the reference's own cloud IGN)
//    vsBrightness    <- ASTRA_VS_BRIGHTNESS    (reference `clamp(screenBrightness,0,1)`; same
//                                               expression here - `screenBrightness` is declared
//                                               in lib/uniforms.glsl:67, handoff P-002 / H2)
//  Reference options with no Astra counterpart are resolved at the reference default:
//    SPECIAL_BIOME_WEATHER off, RAIN_STYLE = 1, SUN_MOON_DURING_RAIN on,
//    ATM_COLOR_MULTS / MOON_PHASE_INF_ATMOSPHERE off.
//  Branches dropped on purpose (they would fight Astra's own systems):
//    - "Apply Underwater Fog" (sky.glsl:54-55): Astra's water medium owns underwater colour.
//    - CAVE_FOG (sky.glsl:90-93): Astra applies cave fog in global/atmosphere/fog.glsl;
//      duplicating it here would double-apply it.
// ============================================================

// ------------------------------------------------------------
// Reference helpers - lib/util/commonFunctions.glsl (verbatim)
// ------------------------------------------------------------
float pow2(float x) { return x * x; }                       // :151-153
float max0(float x) { return max(x, 0.0); }                 // :132-134
float min1(float x) { return min(x, 1.0); }                 // :126-128
float clamp01(float x) { return clamp(x, 0.0, 1.0); }       // :138-140
float sqrt1(float x) { return x * (2.0 - x); }              // :193-195
float sqrt2(float x) {                                      // :205-210
	x = 1.0 - x;
	x *= x;
	x *= x;
	return 1.0 - x;
}
float sqrt3(float x) {                                      // :229-235
	x = 1.0 - x;
	x *= x;
	x *= x;
	x *= x;
	return 1.0 - x;
}
float smoothstep1(float x) { return x * x * (3.0 - 2.0 * x); }        // :290-292
float GetLuminance(vec3 color) { return dot(color, vec3(0.299, 0.587, 0.114)); }  // :21-23

// lib/atmospherics/clouds/mainClouds.glsl:9-16, non-TAA branch.
// Used as the `dither` argument of GetSky (sky.glsl:96).
float astra_sky_dither() {
	return fract(52.9829189 * fract(0.06711056 * gl_FragCoord.x + 0.00583715 * gl_FragCoord.y));
}

// Same clamp as the reference (lib/common.glsl:748). `screenBrightness` is declared in
// lib/uniforms.glsl:67 as the engine's built-in brightness value; if a loader never binds it the
// uniform reads 0, which darkens these colours instead of resolving to the reference's default.
#define ASTRA_VS_BRIGHTNESS clamp(screenBrightness, 0.0, 1.0)

// ------------------------------------------------------------
// Time-of-day factors
// ------------------------------------------------------------
struct AstraSkyFactors {
	float sunFactor;       // 0 at night, 1 during the day
	float sunVisibility;   // 0 at night, 1 during the day (sharper than sunFactor)
	float sunVisibility2;
	float noonFactor;      // 0 at the horizon, 1 at noon
	float invNoonFactor;
	float invNoonFactor2;
	float nightFactor;     // 0 during the day, 1 at midnight
	float rainFactor;
	float rainFactor2;
	float invRainFactor;
	float shadowTime;      // 1 while the sun is the shadow light, 0 at night
};

AstraSkyFactors astra_sky_factors() {
	// program/composite.glsl:30 - SdotU = dot(sunVec, upVec). Astra's worldSunVector is
	// already a world-space unit vector, so SdotU is its Y component.
	float SdotU = worldSunVector.y;

	AstraSkyFactors f;
	// program/composite.glsl:31-32
	f.sunFactor     = SdotU < 0.0 ? clamp(SdotU + 0.375, 0.0, 0.75) / 0.75
	                              : clamp(SdotU + 0.03125, 0.0, 0.0625) / 0.0625;
	f.sunVisibility = clamp(SdotU + 0.0625, 0.0, 0.125) / 0.125;
	f.sunVisibility2 = f.sunVisibility * f.sunVisibility;   // composite.glsl:33

	// lib/common.glsl:740-746
    // Use the geometric analogue of sqrt(sin(timeAngle*2pi)); sunProgress is a
    // different easing curve and was prematurely neutralising the palette.
    // square()/pow4() replace pow() with constant integer exponents: this function runs
    // per sky pixel, and pow is a transcendental expansion on every vendor (lib/pow.glsl).
	f.noonFactor      = sqrt(clamp(worldSunVector.y / cos(radians(sunPathRotation)),0.0,1.0));
	f.invNoonFactor   = min(1.0-f.noonFactor,1.0-smoothstep(0.070,0.242,SdotU));
	f.invNoonFactor2  = square(f.invNoonFactor);
	f.nightFactor     = 1.0 - skyVisibilityDay;             // ASTRA MAP: see header
	f.rainFactor      = astraRainFactor;                       // ASTRA MAP: see header
	f.rainFactor2     = square(f.rainFactor);
	f.invRainFactor   = 1.0 - f.rainFactor;

	// program/composite.glsl:34-36
	float shadowTimeVar1 = abs(f.sunVisibility - 0.5) * 2.0;
	f.shadowTime = pow4(shadowTimeVar1);
	return f;
}

// ------------------------------------------------------------
// Sky palette - lib/colors/skyColors.glsl:5-54 (verbatim)
// ------------------------------------------------------------
struct AstraSkyPalette {
	vec3 up;             // dayUpSkyColor      (:47)
	vec3 middle;         // dayMiddleSkyColor  (:48)
	vec3 down;           // dayDownSkyColor    (:49)
	vec3 sunsetDownP;    // sunsetDownSkyColorP(:44)
	vec3 nightUp;        // nightUpSkyColor    (:52)
	vec3 nightMiddle;    // nightMiddleSkyColor(:53)
	vec3 nightDown;      // nightDownSkyColor  (:54)
};

AstraSkyPalette astra_sky_palette(AstraSkyFactors f) {
	// :5-9
	// ASTRA: max(skyColor, 0.0) guards sqrt()/pow() against a negative Iris value; the
	// reference relies on skyColor being non-negative.
	vec3 skyColorNN = max(skyColor, vec3(0.0));
	vec3 skyColorSqrt = sqrt(skyColorNN);
	float invRainStrength2 = (1.0 - rainStrength) * (1.0 - rainStrength);
	vec3 skyColorM  = mix(max(skyColorSqrt, vec3(0.63, 0.67, 0.73)), skyColorSqrt, invRainStrength2);
	vec3 skyColorM2 = mix(max(skyColorNN, f.sunFactor * vec3(0.265, 0.295, 0.35)), skyColorNN, invRainStrength2);

	// :29-34 - SPECIAL_BIOME_WEATHER off and RAIN_STYLE = 1 resolve every *SnowM / *DryM /
	// *RainM modifier to vec3(0.0), leaving only the plain weather modifiers.
	vec3 nuscWeatherM = vec3(0.1, 0.0, 0.1);
	vec3 nmscWeatherM = vec3(-0.1, -0.4, -0.6) + vec3(0.0, 0.06, 0.12) * f.noonFactor;
	vec3 ndscWeatherM = vec3(-0.15, -0.3, -0.42) + vec3(0.0, 0.02, 0.08) * f.noonFactor;

	// :36-40
	// pow() is kept here: 2.9 is not an exact integer, so there is no multiply chain to
	// fold it to and lib/pow.glsl's generic loop would be slower than the intrinsic.
	vec3 noonUpSkyColor     = pow(skyColorM, vec3(2.9)) * (vec3(0.85, 0.92, 0.81) + f.rainFactor * nuscWeatherM);
	vec3 noonMiddleSkyColor = skyColorM * (vec3(1.4, 1.3, 1.3) + f.rainFactor * nmscWeatherM)
	                        + noonUpSkyColor * 0.25;
	vec3 noonDownSkyColor   = skyColorM * (vec3(0.9) + f.rainFactor * ndscWeatherM)
	                        + noonUpSkyColor * 0.25;

	// :42-45
	vec3 sunsetUpSkyColor     = skyColorM2 * (vec3(0.72, 0.522, 0.47) + vec3(0.1, 0.2, 0.35) * f.rainFactor2);
	vec3 sunsetMiddleSkyColor = skyColorM2 * (vec3(1.8, 1.3, 1.2) + vec3(0.15, 0.25, -0.05) * f.rainFactor2);
	vec3 sunsetDownSkyColorP  = vec3(1.45, 0.86, 0.5) - vec3(0.8, 0.3, 0.0) * f.rainFactor;
	vec3 sunsetDownSkyColor   = sunsetDownSkyColorP * 0.5 + 0.25 * sunsetMiddleSkyColor;

	// :47-49
	AstraSkyPalette p;
	p.up     = mix(noonUpSkyColor, sunsetUpSkyColor, f.invNoonFactor2);
	p.middle = mix(noonMiddleSkyColor, sunsetMiddleSkyColor, f.invNoonFactor2);
	p.down   = mix(noonDownSkyColor, sunsetDownSkyColor, f.invNoonFactor2);
	p.sunsetDownP = sunsetDownSkyColorP;

	// :51-54
	// Same reasoning as noonUpSkyColor: 0.90 is not an exact integer exponent.
	vec3 nightColFactor = 0.9 * vec3(0.07, 0.14, 0.24) * (1.0 - 0.5 * f.rainFactor) + skyColorNN;
	p.nightUp     = pow(nightColFactor, vec3(0.90)) * 0.45;
	p.nightMiddle = sqrt(p.nightUp) * 0.65;
	p.nightDown   = p.nightMiddle * vec3(0.82, 0.82, 0.88);
	return p;
}

// ------------------------------------------------------------
// GetSky - lib/atmospherics/sky.glsl:11-99 (verbatim, minus the two
// branches documented in the file header)
// ------------------------------------------------------------
vec3 astra_get_sky(float VdotU, float VdotS, float dither, bool doGlare, bool doGround,
                   AstraSkyFactors f, AstraSkyPalette p) {
	// :13-21
	float nightFactorSqrt2 = sqrt2(f.nightFactor);
	float nightFactorM = sqrt2(nightFactorSqrt2) * 0.4;
	float VdotSM1 = pow2(max(VdotS, 0.0));
	float VdotSM2 = pow2(VdotSM1);
	float VdotSM3 = pow2(pow2(max(-VdotS, 0.0)));
	float VdotSML = f.sunVisibility > 0.5 ? VdotS : -VdotS;

	float VdotUmax0 = max(VdotU, 0.0);
	float VdotUmax0M = 1.0 - pow2(VdotUmax0);

	// :24-26
	vec3 upColor     = mix(p.nightUp     * (1.5 - 0.5 * nightFactorSqrt2 + nightFactorM * VdotSM3 * 1.5),
	                       p.up,     f.sunFactor);
	vec3 middleColor = mix(p.nightMiddle * (3.0 - 2.0 * nightFactorSqrt2),
	                       p.middle * (1.0 + VdotSM2 * 0.3), f.sunFactor);
	vec3 downColor   = mix(p.nightDown, p.down, (f.sunFactor + f.sunVisibility) * 0.5);

	// :30-33 - sky gradient: up -> middle
	float VdotUM1 = pow2(1.0 - VdotUmax0);
	      VdotUM1 = pow(VdotUM1, (1.0 - VdotSM2 * 0.4) * (1.15 - 0.15 * f.rainFactor2));
	      VdotUM1 = mix(VdotUM1, 1.0, f.rainFactor2 * 0.15);
	vec3 finalSky = mix(upColor, middleColor, VdotUM1);

	// :36-39 - sunset band, widest at the horizon and facing the sun
	float VdotUM2 = pow2(1.0 - abs(VdotU));
	      VdotUM2 = VdotUM2 * VdotUM2 * (3.0 - 2.0 * VdotUM2);
	      VdotUM2 *= (0.7 - nightFactorM + VdotSM1 * (0.3 + nightFactorM)) * f.invNoonFactor * f.sunFactor;
	finalSky = mix(finalSky, p.sunsetDownP * (1.0 + VdotSM1 * 0.3), VdotUM2 * f.invRainFactor);

	// :42-46 - sky ground with fake light scattering (per-channel falloff)
	float VdotUM3 = min(max0(-VdotU + 0.08) / 0.35, 1.0);
	      VdotUM3 = smoothstep1(VdotUM3);
	vec3 scatteredGroundMixer = vec3(VdotUM3 * VdotUM3, sqrt1(VdotUM3), sqrt3(VdotUM3));
	     scatteredGroundMixer = mix(vec3(VdotUM3), scatteredGroundMixer, 0.75 - 0.5 * f.rainFactor);
	finalSky = mix(finalSky, downColor, scatteredGroundMixer);

	// :50-51
	if (doGround)
		finalSky *= smoothstep1(pow2(1.0 + min(VdotU, 0.0)));

	// :58-88 - sun / moon glare
	if (doGlare) {
		if (0.0 < VdotSML) {
			float glareScatter = 3.0 * (2.0 - clamp01(VdotS * 1000.0));
			// SUN_MOON_DURING_RAIN is on at the reference default, so the
			// `#ifndef SUN_MOON_DURING_RAIN` line at :61-63 does not apply.
			float VdotSM4 = pow(abs(VdotS), glareScatter);

			float visfactor = 0.075;
			float glare = visfactor / (1.0 - (1.0 - visfactor) * VdotSM4) - visfactor;
			glare *= 0.24;

			// Astra declares isEyeInWater as int; the reference multiplies it directly.
			float glareWaterFactor = float(isEyeInWater) * f.sunVisibility;
			vec3 glareColor = mix(vec3(0.38, 0.4, 0.5) * 0.3,
			                      vec3(1.5, 0.7, 0.3) + vec3(0.0, 0.5, 0.5) * f.noonFactor,
			                      f.sunVisibility);
			     glareColor = glareColor + glareWaterFactor * vec3(7.0);

			// :74-78, SUN_MOON_DURING_RAIN branch
			glare *= 1.0 - 0.6 * f.rainFactor;
			// :79-84, RAIN_STYLE == 1
			glareColor = mix(glareColor, vec3(GetLuminance(glareColor)), 0.5 * f.rainFactor);

			finalSky += glareColor * glare * f.shadowTime;
		}
	}

	// :96 - dither to fix banding
	finalSky = max(finalSky + (dither - 0.5) / 128.0, vec3(0.0));

	return finalSky;
}

// ------------------------------------------------------------
// Astra interface - unchanged signature, consumed by
// global/dimension/overworld.glsl:9-15 (astra_sky_radiance).
// doGlare / doGround follow program/gbuffers_skybasic.glsl:83 (true, false).
// ------------------------------------------------------------
vec3 astra_gradient_sky(vec3 worldDir) {
	vec3 nDir = normalize(worldDir);
	AstraSkyFactors f = astra_sky_factors();
	AstraSkyPalette p = astra_sky_palette(f);
	return astra_get_sky(nDir.y, dot(nDir, normalize(worldSunVector)),
	                     astra_sky_dither(), true, false, f, p);
}

#endif
