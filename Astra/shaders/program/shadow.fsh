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
    #ifdef WATER_CAUSTICS
    if (waterHeight < WATER_HEIGHT_NONE) {
        float focus = solas_water_caustics(waterCasterWorld);
        vec3 waterTint = vec3(115.0, 200.0, 250.0) / 255.0 * 0.80;
        // Reference mapping: the water's own tint is only reached at the caustic peaks,
        // the rest of the surface stays close to neutral. The floor term is the dark
        // water base the reference keeps at 0.3; without it the whole seabed went dim.
        shadowTint = mix(vec3(1.0), pow(waterTint, vec3(0.75)), 0.20 + 0.80 * min(focus, 1.0));
        shadowTint *= (0.30 + focus * 1.5) * (1.0 - pow(albedo.a, 32.0));
    }
    #endif
    shadowData = vec4(waterHeight, shadowTint);
}
