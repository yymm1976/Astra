#ifndef ASTRA_GLOBAL_DIMENSION_OVERWORLD_GLSL
#define ASTRA_GLOBAL_DIMENSION_OVERWORLD_GLSL
#include "/lib/twilight.glsl"

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
    vec3 direction=normalize(worldDir);
    sky=astra_twilight_atmosphere(sky,direction);
	sky = astra_twilight_highlights(sky);
#ifdef LIGHTNING_FLASH
	// Sky-wide part of a thunderstorm flash. Before this the bolt only existed as a point
	// light, so the terrain lit up while the sky behind it stayed black.
	// eyeBrightnessSmooth.y is the same sky exposure the point light gates on.
	sky += astra_lightning_sky_flash(worldDir, eyeBrightnessSmooth.y / 240.0);
#endif
	return sky;
}

vec3 astra_sky_ambient() {
	vec3 dayAmbient = mix(vec3(0.28, 0.30, 0.35), vec3(0.36, 0.43, 0.57), sunProgress);
	vec3 nightAmbient = mix(vec3(0.050, 0.063, 0.086), vec3(0.083, 0.106, 0.148), moonProgress);
	// C1 owns the user strength multiplier. This interface returns the untuned HDR colour so
	// every lighting consumer applies SKYLIGHT_STRENGTH exactly once.
	// Twilight is diffuse illumination and persists across the sun/moon handoff.
	float twilight = smoothstep(-0.20, 0.08, worldSunVector.y);
	vec3 ambient = mix(nightAmbient, dayAmbient, twilight);
    vec3 morningAmbient=mix(vec3(0.13,0.14,0.18),vec3(0.29,0.25,0.255),
                             smoothstep(-0.14,0.06,worldSunVector.y));
    ambient=mix(ambient,morningAmbient,astra_twilight_strength());
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
    vec3 reflectedSky=astra_sky_radiance(safeDir);
    #if CLOUD_MODE == CLOUD_PLANAR
    // Complementary reflectionBackground reflects the same atmosphere and
    // clouds. Here a two-fetch density plane replaces a second cloud march.
    float morning=astra_twilight_strength();
    if (morning>0.0 && safeDir.y>0.025 && cameraPosition.y<ASTRA_CLOUD_ALTITUDE) {
        float travel=(ASTRA_CLOUD_ALTITUDE-cameraPosition.y)/safeDir.y;
        vec3 hit=cameraPosition+safeDir*travel;
        float density=astra_cloud_noise(hit,ASTRA_CLOUD_ALTITUDE);
        float bias=mix(0.20,-0.20,CLOUD_COVERAGE*0.01)-0.04-0.28*astraRainFactor;
        float coverage=smoothstep(0.21+bias,0.43+bias,density)
                       *(1.0-smoothstep(2400.0,4000.0,travel));
        float toward=cube(max(dot(safeDir,worldSunVector),0.0));
        vec3 body=vec3(0.18,0.15,0.17)+astra_twilight_sunlight()*(0.08+0.13*toward);
        reflectedSky=mix(reflectedSky,body,coverage*morning*0.70);
    }
    #endif
	return mix(reflectedSky,
               astra_sky_ambient()+astra_twilight_sky(safeDir)*0.35, convergence);
}

vec3 astra_direct_light() {
	vec3 sun = mix(vec3(0.92, 0.81, 0.65), vec3(1.10, 0.99, 0.83), sunProgress)
	         * (SUNLIGHT_STRENGTH * 0.01);
    sun = mix(sun,astra_twilight_sunlight()*(SUNLIGHT_STRENGTH*0.01),astra_twilight_strength());
	vec3 moon = mix(vec3(0.30, 0.40, 0.62), vec3(0.48, 0.61, 0.88), moonProgress)
	          * (MOONLIGHT_STRENGTH * 0.0068);
	// Moon phase (design: the phase stays visible and is allowed a SMALL effect on
	// direct moonlight - MakeUp does the same in its night palette). This multiplies
	// the direct term only: the ambient term is astra_sky_ambient(), which has no
	// moonPhase in it, so a new moon dims the moon's own light and shadow without
	// taking the night's readability with it. The floor is deliberately high; the
	// value is a hint that the moon is thin, not a second night cycle.
	moon *= mix(0.82, 1.06, 1.0 - clamp(moonPhase, 0.0, 4.0) * 0.25);
	// Match the actual shadow source, including Iris's dusk/dawn handoff.
	vec3 source = normalize(view_player(lightVector));
	float sunSource = step(0.0, dot(source, worldSunVector));
	vec3 direct = mix(moon, sun, sunSource);
	float horizon = mix(smoothstep(0.08,0.40,source.y),
        smoothstep(0.0,0.085,source.y)*mix(0.82,1.0,smoothstep(0.12,0.40,source.y)),sunSource);
	return direct * horizon * mix(1.0, 0.22, astraRainFactor);
}

vec3 astra_overworld_sky(vec3 worldDir) {
	vec3 sky = astra_sky_radiance(worldDir);
#ifdef STARS
	sky += astra_star_field(worldDir);
#endif
	return sky;
}

#endif
