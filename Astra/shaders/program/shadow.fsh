// Astra v1 - program/shadow.fsh (shadow pass: caster tint / cached water lens)
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot
//   source: _analysis/Steadfast-0.8.0/shaders/program/shadow/shadow.fsh
// This file is a derivative of Steadfast and is licensed under the GNU General Public
// License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
// _analysis/Steadfast-0.8.0/LICENSE.md, including Steadfast's Section 7 additional terms.
// Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Astra changes: Steadfast writes a constant vec4(waterHeight, 1, 1, 1) because it has
// no coloured shadows. Astra puts non-water translucent tint in GBA, so an
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

// Optical slope is signed and caustic focus can exceed one; retain both in FP16.
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
#ifndef RGBA16F
const int RGBA16F = 0;
#endif
const int shadowcolor0Format = RGBA16F;
#endif

/* RENDERTARGETS: 0 */
// GBA stores caster transmission or water slope/focus; A is data, not coverage.
// Iris adds an output-alpha discard to legacy gl_FragData[0] writes. Use an
// explicit data output so only the source-albedo cutout below clips geometry;
// keep alphaTestRef supplied by Iris (including the terrain cutout threshold).
layout(location = 0) out vec4 shadowData;

void main() {
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Derivatives must be evaluated before the per-caster water branch.
    float waterFootprint = max(length(dFdx(waterCasterWorld.xz)),
                               length(dFdy(waterCasterWorld.xz)));
    // Horizontal water stores its optical record, independent of texture alpha
    // and tint. It needs no material texture sample or caster-tint preparation.
    if (waterHeight < WATER_HEIGHT_NONE) {
        vec3 lens = vec3(0.0, 0.0, 1.0);
        #if defined WATER_CAUSTICS || (defined WATER_WAVES && defined ASTRA_UNDERWATER_SHAFTS)
        lens = astra_water_caustic_lens(waterCasterWorld, waterFootprint);
        #endif
        shadowData = vec4(waterHeight, lens);
        return;
    }
    #endif
	vec4 albedo = texture(gtexture, texcoord) * tint;

	if (waterHeight >= WATER_HEIGHT_NONE && albedo.a < alphaTestRef) {
		discard;
	}

#ifdef COLORED_SHADOWS
	// Near-opaque surfaces keep the neutral tint: their job is to block light, not to
	// colour it. Only genuinely translucent casters (stained glass, stained panes,
	// tinted water) contribute colour.
	vec3 shadowTint = vec3(1.0);
	if (waterHeight >= WATER_HEIGHT_NONE) {
		float translucency = 1.0 - smoothstep(0.9, 1.0, albedo.a);
		if (translucency > 0.0)
			shadowTint = mix(vec3(1.0), srgb_decode(albedo.rgb), translucency);
	}
	// Water albedo is a surface texture, not a light-transmission coefficient.
	// Its absorption is evaluated over the water column by the lighting consumer.
#else
	vec3 shadowTint = vec3(1.0);
#endif

    shadowData = vec4(waterHeight, shadowTint);
}
