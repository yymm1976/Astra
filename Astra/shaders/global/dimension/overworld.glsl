#ifndef ASTRA_GLOBAL_DIMENSION_OVERWORLD_GLSL
#define ASTRA_GLOBAL_DIMENSION_OVERWORLD_GLSL
#include "/lib/twilight.glsl"
#if CLOUD_MODE == CLOUD_PLANAR && !defined ASTRA_SKY_CACHE_WRITE
    #include "/lib/sky_reflection_cache.glsl"
#endif

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
    sky *= astra_sky_color_gain(direction.y, skyVisibilityDay, astraTwilightFactor, astraDawnBlend);
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
    // CPU evaluates the same day/night, twilight and rain palette once per frame.
    // C1 still applies SKYLIGHT_STRENGTH exactly once at the consuming surface.
    // The natural-look hue shift is one shared constant (lib/color_controls.glsl),
    // also used by the water interface incident colour. Ambient strength, the dark
    // floor, clouds and the reflection path all keep consuming this single value.
    return astraAmbientPalette * ASTRA_TINT_AMBIENT * ASTRA_STYLE_AMBIENT
         * ASTRA_OVERWORLD_AMBIENT_GAIN;
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
    #if CLOUD_MODE == CLOUD_PLANAR && !defined ASTRA_SKY_CACHE_WRITE
        // Current-frame sky and the visible cloud model, shared by every reflector.
        // The producer never enters this branch or binds its own target as a sampler.
        vec3 reflectedSky = astra_cached_reflection_sky(safeDir, r);
    #else
        vec3 reflectedSky = astra_sky_radiance(safeDir);
    #endif
    // The rough lobe retains its separately calibrated ambient twilight;
    // it does not apply the reflected-sky tint a second time.
	return mix(reflectedSky,
               astra_sky_ambient()+astra_twilight_sky(safeDir)*0.35, convergence);
}

vec3 astra_direct_light() {
    vec3 sun = astraSunPalette * (SUNLIGHT_STRENGTH * 0.01)
             * astra_sun_color_gain(astraTwilightFactor, astraDawnBlend);
	// 2026-09-23 night-visual round ("夜晚阴影太多显得奇怪"): the old palette was a
	// saturated blue (R<G<B, 0.30/0.40/0.62 -> 0.48/0.61/0.88) at 0.68 absolute, i.e.
	// about 4x astra_sky_ambient(), so direct light dominated the night and every cast
	// shadow read as a black patch. The reference packs (Mellow f_MOON 0.133/0.133/0.214)
	// carry the night as a near-neutral, faintly blue wash instead: R=G with B only
	// ~1.6x R, and much dimmer. Same hue ratio here, factor 0.0068 -> 0.0046 so the
	// direct term lands at 1.5..2.3x the sky ambient over the whole moonProgress and
	// moon-phase range (mid-phase/mid-phase 3.8:1 -> 1.9:1). See diffuse.glsl night note.
	// Phase (astraMoonLightScale, 0.82..1.06) and the horizon/rain gates below are unchanged.
    vec3 moon = astraMoonPalette * (MOONLIGHT_STRENGTH * 0.0046) * ASTRA_TINT_MOON;
	// Moon phase (design: the phase stays visible and is allowed a SMALL effect on
	// direct moonlight - MakeUp does the same in its night palette). This multiplies
	// the direct term only: the ambient term is astra_sky_ambient(), which has no phase
	// factor in it, so a new moon dims the moon's own light and shadow without taking
	// the night's readability with it. The floor is deliberately high; the value is a
	// hint that the moon is thin, not a second night cycle.
	moon *= astraMoonLightScale;
	// Match the actual shadow source, including Iris's dusk/dawn handoff.
    // The source transform, normalization, handoff and horizon polynomials are
    // uniform across the frame; shaders.properties evaluates them on the CPU.
    return mix(moon, sun, astraSunSource) * astraDirectLightGate;
}

vec3 astra_overworld_sky(vec3 worldDir) {
	vec3 sky = astra_sky_radiance(worldDir);
#ifdef STARS
	sky += astra_star_field(worldDir);
#endif
	return sky;
}

#endif
