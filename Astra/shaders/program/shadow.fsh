// Astra v1 - program/shadow.fsh (shadow pass: shadowcolor0 = water height + tint)
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot
//   source: _analysis/Steadfast-0.8.0/shaders/program/shadow/shadow.fsh
// This file is a derivative of Steadfast and is licensed under the GNU General Public
// License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
// _analysis/Steadfast-0.8.0/LICENSE.md, including Steadfast's Section 7 additional terms.
// Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Astra changes: Steadfast writes a constant vec4(waterHeight, 1, 1, 1) because it has
// no coloured shadows. Astra puts the translucent tint in GBA (design.md 2.3), so an
// opaque caster has to store white - otherwise every shadow would come out black.
// The tint blend follows Solas V2.2b (program/shadow.glsl): fade to the surface colour
// by translucency, then zero it out for near-opaque surfaces.
//
// Uniforms: none beyond built-ins (alphaTestRef, gtexture)
// design.md 3.2 layer 2: program/* is the only lib entry
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
// srgb_decode: texture colour is sRGB, the tint must be linear
#include "/lib/encoding.glsl"
#include "/global/lighting/shadowmap.glsl"
in vec2 texcoord;
in vec4 tint;
in float waterHeight;
in vec3 waterCasterWorld;
#include "/global/water/caustics.glsl"

/* RENDERTARGETS: 0 */
// GBA stores light-transmission RGB, so A is data, not surface coverage.
// Iris adds an output-alpha discard to legacy gl_FragData[0] writes. Use an
// explicit data output so only the source-albedo cutout below clips geometry;
// keep alphaTestRef supplied by Iris (including the terrain cutout threshold).
layout(location = 0) out vec4 shadowData;

void main() {
	vec4 albedo = texture(gtexture, texcoord) * tint;

	if (waterHeight >= WATER_HEIGHT_NONE && albedo.a < alphaTestRef) {
		discard;
	}

#ifdef COLORED_SHADOWS
	// Near-opaque surfaces keep the neutral tint: their job is to block light, not to
	// colour it. Only genuinely translucent casters (stained glass, stained panes,
	// tinted water) contribute colour.
	float translucency = 1.0 - smoothstep(0.9, 1.0, albedo.a);
	vec3 shadowTint = mix(vec3(1.0), srgb_decode(albedo.rgb), translucency);
	// Water albedo is a surface texture, not a light-transmission coefficient.
	// Its absorption is evaluated over the water column by the lighting consumer.
	if (waterHeight < WATER_HEIGHT_NONE) shadowTint = vec3(1.0);
#else
	vec3 shadowTint = vec3(1.0);
#endif

    // Solas writes the water focusing pattern into the light map itself.
    // Both the floor and volume samples consume this same projected pattern.
    //
    // 2026-09-23 (underwater rewrite). The reference mapping reached the water's tint
    // only at the peaks but multiplied the WHOLE surface by (0.30 + focus * 1.5): at the
    // shipped field's median (0.094) that is a flat 0.441x on every submerged receiver,
    // i.e. the bed was dimmed 2.4x with a faint texture on top - measured in
    // qa/underwater-caustics-2026-09-22.log [3] (tint G p50 0.413) and reported by the
    // user as "a blue mist, no light spots". The gain below is neutral at the field's own
    // median instead - the same `1.35 * field - 0.135` idiom program/lit.fsh uses above
    // water, so both sides of the surface read one calibration - and the tint colour only
    // appears as the spots brighten. This is also the ONLY caustic path underwater:
    // lit.fsh's pixel-side delta is air-side only (lit.fsh:442-478, isEyeInWater == 0).
    #ifdef WATER_CAUSTICS
    if (waterHeight < WATER_HEIGHT_NONE) {
        float field = solas_water_caustics(waterCasterWorld);
        float gain = clamp(1.0 + ASTRA_CAUSTIC_CASTER_STRENGTH * (1.35 * field - 0.135),
                           0.80, 2.60);
        vec3 waterTint = vec3(115.0, 200.0, 250.0) / 255.0 * 0.80;
        // x^0.75 as a squaring chain: pow() with a literal exponent expands to
        // transcendentals and this runs on every shadow-caster pixel (consolidated
        // review E7 / Qoder F-36). No pow.glsl here - this TU does not include
        // scene.glsl, so the helpers are not in scope.
        vec3 waterTintPow = sqrt(sqrt(waterTint * waterTint * waterTint));
        shadowTint = mix(vec3(1.0), waterTintPow, clamp(gain - 1.0, 0.0, 1.0)) * gain;
        // x^32 as an explicit squaring chain, as before. The old `1.0 - a32` deleted the
        // whole transmission for a near-opaque water sprite (albedo.a >= 0.99, e.g. a
        // resource pack's water_still.png): the water caster then blocked all direct light
        // and the seabed went black. Vanilla's 180/255 is safe, so this is a floor rather
        // than a redesign - an opaque water surface still transmits the network.
        float a2 = albedo.a * albedo.a;
        float a32 = a2 * a2; a32 = a32 * a32; a32 = a32 * a32; a32 = a32 * a32;
        shadowTint *= 1.0 - 0.45 * a32;
    }
    #endif
    shadowData = vec4(waterHeight, shadowTint);
}
