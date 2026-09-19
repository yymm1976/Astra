#ifndef ASTRA_GLOBAL_ATMOSPHERE_STARS_GLSL
#define ASTRA_GLOBAL_ATMOSPHERE_STARS_GLSL

// ============================================================
//  Astra v1 - star field, ported from Complementary r5.9 (Reimagined).
//  Reference root: _analysis/Complementary r5.9/Reimagined/shaders/
//    lib/atmospherics/stars.glsl:3-5    GetStarNoise   -> astra_star_noise()
//    lib/atmospherics/stars.glsl:7-12   GetStarCoord   -> astra_star_coord()
//    lib/atmospherics/stars.glsl:14-48  GetStars       -> astra_stars()
//    program/gbuffers_skybasic.glsl:92  sphereness = 0.5 for the overworld
//    program/gbuffers_skybasic.glsl:24  reflection uses sphereness = 0.5 too
//
//  The previous Astra implementation (cubemap-face cell hashing) is REPLACED.
//  The reference projects the direction onto a sphere instead of a cube:
//      starCoord = wpos / (wpos.y + length(wpos.xz) * sphereness)
//  which removes the face-seam stretching the cube projection produced at the
//  zenith and along the four vertical seams.
//
//  ASTRA MAPPING (reference input -> Astra input):
//    syncedTime       <- frameTimeCounter   (reference: (worldTime + day*24000) * 0.05,
//                                            i.e. seconds; Astra has no worldTime uniform)
//    invRainFactor    <- 1.0 - rainStrength (reference: lib/common.glsl:744)
//    invNoonFactor2   <- (1 - sunProgress)^2 (reference: lib/common.glsl:745-746;
//                                            noonFactor <- sunProgress, see sky_gradient.glsl)
//    sunVisibility    <- astra_sky_factors().sunVisibility (verbatim from worldSunVector.y)
//    NIGHT_STAR_AMOUNT = 2 (reference default, lib/common.glsl:99) -> `star -= 0.7;`
// ============================================================

#include "/global/atmosphere/sky_gradient.glsl"

// lib/atmospherics/stars.glsl:3-5
float astra_star_noise(vec2 pos) {
	return fract(sin(dot(pos, vec2(12.9898, 4.1414))) * 43758.54953);
}

// lib/atmospherics/stars.glsl:7-12
// The reference takes a view-space position and converts it with gbufferModelViewInverse.
// Astra's callers already hand us a world-space direction, so only the spherical
// projection itself is kept (`viewPos * 1000.0` and the matrix multiply drop out).
vec2 astra_star_coord(vec3 worldDir, float sphereness) {
	vec3 wpos = normalize(worldDir);
	vec3 starCoord = wpos / (wpos.y + length(wpos.xz) * sphereness);
	starCoord.x += 0.006 * frameTimeCounter;   // ASTRA MAP: 0.006 * syncedTime
	return starCoord.xz;
}

// lib/atmospherics/stars.glsl:14-48
vec3 astra_stars(vec2 starCoord, float VdotU, float VdotS,
                 float invRainFactor, float invNoonFactor2, float sunVisibility) {
	if (VdotU < 0.0) return vec3(0.0);   // :18

	starCoord *= 0.2;                    // :20
	float starFactor = 1024.0;           // :21
	starCoord = floor(starCoord * starFactor) / starFactor;   // :22

	float star = 1.0;                    // :24
	star *= astra_star_noise(starCoord.xy);        // :25
	star *= astra_star_noise(starCoord.xy + 0.1);  // :26
	star *= astra_star_noise(starCoord.xy + 0.23); // :27

	star -= 0.7;                         // :33 - NIGHT_STAR_AMOUNT == 2
	star = max0(star);                   // :41
	star *= star;                        // :42

	star *= min1(VdotU * 3.0) * max0(1.0 - pow100(abs(VdotS) * 1.002));   // :44
	star *= invRainFactor * pow4(invNoonFactor2) * (1.0 - 0.5 * sunVisibility);  // :45

	return 40.0 * star * vec3(0.38, 0.4, 0.5);   // :47
}

// ------------------------------------------------------------
// Astra interface - unchanged signature, consumed by
// global/dimension/overworld.glsl:51-57 (astra_overworld_sky).
// ------------------------------------------------------------
vec3 astra_star_field(vec3 worldDir) {
	vec3 nDir = normalize(worldDir);
	AstraSkyFactors f = astra_sky_factors();
	// program/gbuffers_skybasic.glsl:92 - sphereness 0.5 for the overworld sky.
	vec2 starCoord = astra_star_coord(nDir, 0.5);
	float VdotS = dot(nDir, normalize(worldSunVector));
	return astra_stars(starCoord, nDir.y, VdotS,
	                   f.invRainFactor, f.invNoonFactor2, f.sunVisibility);
}

#endif
