#ifndef ASTRA_WATER_REFERENCE_LIGHT_GLSL
#define ASTRA_WATER_REFERENCE_LIGHT_GLSL
// Steadfast is a fast and high-quality graphical overhaul for Minecraft (JE)
// Copyright (C) 2026 coderbot
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// Adapted for the water path only from Steadfast 0.8.0 minishita.glsl
// and shaders.properties. Functions/constants are prefixed; public sky is independent.
float waterRef_CornetteShanks(float mu) {
	const float PI = 3.14159274;
	const float g = 0.76;
	return 3.0 / (8.0 * PI)
		* ((1.0 - g * g) * (1.0 + mu * mu))
		/ ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 3.0 / 2.0));
}
float waterRef_RayleighPhase(float mu) {
	const float PI = 3.14159274;
	return 3.0 / (16.0 * PI) * (1.0 + mu * mu);
}
float waterRef_RayIntersectUnitSphereBi(vec3 origin, vec3 direction, out float reverse) {
	float od = dot(origin, direction);
	float oo = dot(origin, origin);
	float sq = sqrt(od * od + (1.0 - oo));
	reverse = sq + od;
	return sq - od;
}
const vec3 waterRef_RAYLEIGH_SCATTER_COEFFICIENTS = vec3(5.8, 13.5, 33.1);
const float waterRef_MIE_SCATTER_COEFFICIENT = 5.0;
const float waterRef_PLANET_RADIUS_KM = 6360.0;
const float waterRef_ATMOSPHERE_THICKNESS_KM = 100.0;
const float waterRef_SCALE_HEIGHT_KM = 25.0;
const float waterRef_ATMOSPHERE_RADIUS_KM = waterRef_PLANET_RADIUS_KM + waterRef_ATMOSPHERE_THICKNESS_KM;
const float waterRef_KM_TO_UNIT = 1.0 / waterRef_ATMOSPHERE_RADIUS_KM;
const float waterRef_PLANET_RADIUS_UNIT = waterRef_KM_TO_UNIT * (waterRef_PLANET_RADIUS_KM);
const float waterRef_SCALE_HEIGHT_UNIT = waterRef_KM_TO_UNIT * (waterRef_SCALE_HEIGHT_KM);
const float waterRef_COEFFICIENT_TO_UNIT = waterRef_ATMOSPHERE_RADIUS_KM * (1.0 / 1000.0);
const vec3 waterRef_RAYLEIGH_UNIT = waterRef_COEFFICIENT_TO_UNIT * waterRef_RAYLEIGH_SCATTER_COEFFICIENTS;
const float waterRef_MIE_UNIT = waterRef_COEFFICIENT_TO_UNIT * waterRef_MIE_SCATTER_COEFFICIENT;
const float waterRef_EYE_HEIGHT_KM = 5.0;
const float waterRef_EYE_HEIGHT_UNIT = waterRef_KM_TO_UNIT * (waterRef_PLANET_RADIUS_KM + waterRef_EYE_HEIGHT_KM);
float waterRef_OpticalDepthLight(vec3 samplePos, vec3 worldLightDir, float distance) {
	vec3 lightSamplePos = worldLightDir * (0.15 * distance) + samplePos;
	float lightHeight = length(lightSamplePos) - waterRef_PLANET_RADIUS_UNIT;
	return distance * exp((-1.0 / waterRef_SCALE_HEIGHT_UNIT) * lightHeight);
}
vec3 waterRef_SkyColor(vec3 worldDir) {
    float exposureDay = 25.0 + 35.0 * exp(-15.0 * max(0.0, worldSunVector.y));
    float exposureNight = mix(0.33, 2.4, nightVision);
    vec3 rayleighStrengthSun = exposureDay * waterRef_RAYLEIGH_SCATTER_COEFFICIENTS;
    vec3 rayleighStrengthMoon = exposureNight * waterRef_RAYLEIGH_SCATTER_COEFFICIENTS;
    float mieStrengthSun = exposureDay * 5.0 * (1.0 - rainStrength) * 0.66;
    float mieStrengthMoon = exposureNight * 5.0 * (1.0 - rainStrength);
    vec3 atmosphericAmbient = vec3(0.13, 0.33, 1.0)
        * (0.2 / (1.0 + exp(-30.0 * (worldSunVector.y + 0.05)))
         + 0.2 / (1.0 + exp(-15.0 * (worldSunVector.y - 0.45))));
    vec3 luma = vec3(0.2126, 0.7152, 0.0722);
    vec3 ambientSkyColor = mix(atmosphericAmbient, vec3(dot(atmosphericAmbient, luma)), rainStrength * 0.8);
    vec3 gray = vec3(0.25, 0.575, 1.0);
    vec3 blue = vec3(0.07, 0.45, 1.0);
    vec3 nightOverride = mix(gray / dot(gray,luma), blue / dot(blue,luma), 0.66);
    vec4 daySkyOverridePremultiplied = vec4(vec3(rainStrength), 1.0 - rainStrength);
    vec4 nightSkyOverridePremultiplied = vec4(mix(nightOverride, vec3(1.0), rainStrength), 0.0);

	float muSun = dot(worldDir, worldSunVector);
	float muMoon = -muSun;
	float rayleighPhase = waterRef_RayleighPhase(muSun);
	float scatterMieSun = waterRef_CornetteShanks(muSun) * mieStrengthSun;
	float scatterMieMoon = waterRef_CornetteShanks(muMoon) * mieStrengthMoon;
	vec3 scatterSun = rayleighPhase * rayleighStrengthSun + scatterMieSun;
	vec3 scatterMoon = rayleighPhase * rayleighStrengthMoon + scatterMieMoon;
	worldDir.y = max(0.0, worldDir.y);
	worldDir = normalize(worldDir);
	float od = waterRef_EYE_HEIGHT_UNIT * worldDir.y;
	const float oo = waterRef_EYE_HEIGHT_UNIT * waterRef_EYE_HEIGHT_UNIT;
	float atmosphereDistance = sqrt(od * od + (1.0 - oo)) - od;
	const vec3 eyePos = vec3(0.0, waterRef_EYE_HEIGHT_UNIT, 0.0);
	vec3 samplePos1 = worldDir * (0.15 * atmosphereDistance) + eyePos;
	vec3 samplePos2 = worldDir * (0.65 * atmosphereDistance) + eyePos;
	float vHeight1 = length(samplePos1) - waterRef_PLANET_RADIUS_UNIT;
	float vHeight2 = length(samplePos2) - waterRef_PLANET_RADIUS_UNIT;
	const float unitScale = (-1.0 / waterRef_SCALE_HEIGHT_UNIT);
	float depthV1 = 0.5 * (atmosphereDistance * exp(unitScale * vHeight1));
	float depthV2 = 0.5 * (atmosphereDistance * exp(unitScale * vHeight2));
	float dM1, dM2;
	float dS1 = waterRef_RayIntersectUnitSphereBi(samplePos1, worldSunVector, dM1);
	float dS2 = waterRef_RayIntersectUnitSphereBi(samplePos2, worldSunVector, dM2);
	float depthLightSun1  = waterRef_OpticalDepthLight(samplePos1,  worldSunVector, dS1);
	float depthLightSun2  = waterRef_OpticalDepthLight(samplePos2,  worldSunVector, dS2);
	float depthLightMoon1 = waterRef_OpticalDepthLight(samplePos1, -worldSunVector, dM1);
	float depthLightMoon2 = waterRef_OpticalDepthLight(samplePos2, -worldSunVector, dM2);
	float opticalDepthS1 = dot(vec2(depthLightSun1, depthV1), vec2(0.5, 0.05));
	float opticalDepthS2 = dot(vec2(depthLightSun2, depthV2), vec2(0.5, 3.0));
	float opticalDepthM1 = dot(vec2(depthLightMoon1, depthV1), vec2(0.5, 0.05));
	float opticalDepthM2 = dot(vec2(depthLightMoon2, depthV2), vec2(0.5, 3.0));
	vec3 tmSun  = depthV1 * exp(opticalDepthS1 * (-(waterRef_RAYLEIGH_UNIT + waterRef_MIE_UNIT)))
	            + depthV2 * exp(opticalDepthS2 * (-(waterRef_RAYLEIGH_UNIT + waterRef_MIE_UNIT)));
	vec3 tmMoon = depthV1 * exp(opticalDepthM1 * (-(waterRef_RAYLEIGH_UNIT + waterRef_MIE_UNIT)))
	            + depthV2 * exp(opticalDepthM2 * (-(waterRef_RAYLEIGH_UNIT + waterRef_MIE_UNIT)));
	vec3 day = tmSun * scatterSun;
	vec3 night = tmMoon * scatterMoon;
	float luminanceDay = dot(day, vec3(0.2126, 0.7152, 0.0722));
	float luminanceNight = dot(night, vec3(0.2126, 0.7152, 0.0722));
	vec3 sky = day * daySkyOverridePremultiplied.a + ambientSkyColor;
	sky += night * nightSkyOverridePremultiplied.a;
	sky += luminanceDay * daySkyOverridePremultiplied.rgb;
	sky += luminanceNight * nightSkyOverridePremultiplied.rgb;
	return sky;
}

// Same light-direction quadrature as Steadfast shaders.properties st_*.
void water_reference_lighting(out vec3 ambient, out vec3 direct) {
    vec3 eye = vec3(0.0, waterRef_EYE_HEIGHT_UNIT, 0.0);
    float reverse;
    float distance = waterRef_RayIntersectUnitSphereBi(eye, worldSunVector, reverse);
    vec3 transmittance = vec3(0.0);
    for (int i = 0; i < 2; ++i) {
        float t = i == 0 ? 0.15 : 0.65;
        vec3 p = eye + worldSunVector * (t * distance);
        float depthV = 0.5 * distance * exp(-(length(p) - waterRef_PLANET_RADIUS_UNIT) / waterRef_SCALE_HEIGHT_UNIT);
        float depthLight = waterRef_OpticalDepthLight(p, worldSunVector, (1.0 - t) * distance);
        float depth = depthLight * 0.5 + depthV * (i == 0 ? 0.05 : 3.0);
        transmittance += depthV * exp(-depth * (waterRef_RAYLEIGH_UNIT + waterRef_MIE_UNIT));
    }
    vec3 scatter = waterRef_RayleighPhase(1.0) * waterRef_RAYLEIGH_SCATTER_COEFFICIENTS
                 + 5.0 * waterRef_CornetteShanks(1.0);
    vec3 sun = transmittance * scatter * (27.5 * clamp(worldSunVector.y / 0.6, 0.0, 1.0))
             * (SUNLIGHT_STRENGTH * 0.01);
    vec3 moon = vec3(0.5, 0.65, 1.0) * (10.75 * mix(0.008, 0.024, nightVision)
              * pow(max(0.0, -worldSunVector.y), 0.4)) * (MOONLIGHT_STRENGTH * 0.01);
    vec3 sky = vec3(0.13, 0.33, 1.0)
        * (0.2 / (1.0 + exp(-30.0 * (worldSunVector.y + 0.05)))
         + 0.2 / (1.0 + exp(-15.0 * (worldSunVector.y - 0.45))));
    vec3 skyBase = sky + 0.25 * moon;
    ambient = mix(skyBase + 0.125 * (sun + moon),
                  vec3(dot(skyBase, vec3(0.2126,0.7152,0.0722)) * 0.6), rainStrength);
    direct = (1.0 - rainStrength) * 0.875 * (sun + moon);
}

#endif
