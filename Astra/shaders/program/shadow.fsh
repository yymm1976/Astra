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
in vec3 shadowPlanePosition;

/* RENDERTARGETS: 0 */

void main() {
	// A nonlinear XY warp invalidates interpolated Z, even on a flat block.
	// Reconstruct the original light-space plane at the inverse-warped pixel.
	// Derivatives are evaluated before alpha rejection.
	vec3 planeNormal = cross(dFdx(shadowPlanePosition), dFdy(shadowPlanePosition));
	vec2 rawXY = undistort(vec3(gl_FragCoord.xy / float(shadowMapResolution) * 2.0 - 1.0, 0.0)).xy;
	float rawZ = shadowPlanePosition.z;
	if (abs(planeNormal.z) > 1e-12)
		rawZ -= dot(planeNormal.xy, rawXY - shadowPlanePosition.xy) / planeNormal.z;
	gl_FragDepth = clamp(rawZ * 0.1 + 0.5, 0.0, 1.0);
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

	gl_FragData[0] = vec4(waterHeight, shadowTint);
}
