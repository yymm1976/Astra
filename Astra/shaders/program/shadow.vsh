// Astra v1 - program/shadow.vsh (shadow pass: producer of shadowtex0/1 + shadowcolor0)
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot
//   source: _analysis/Steadfast-0.8.0/shaders/program/shadow/shadow.vsh
// This file is a derivative of Steadfast and is licensed under the GNU General Public
// License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
// _analysis/Steadfast-0.8.0/LICENSE.md, including Steadfast's Section 7 additional terms.
// Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Astra changes: block IDs come straight from block.properties (10001 water, 10010
// shadow-transparent glass) instead of a decoded material enum, because E1's 4-bit
// material table is not frozen yet and the shadow pass needs only these two classes.
// Water height encoding moved to global/lighting/shadowmap.glsl (shared with C2).
//
// Uniforms: shadowModelViewInverse, shadowModelView, cameraPosition,
//           windStrength, windTheta (lib/uniforms.glsl)
// design.md 3.2 layer 2: program/* is the only lib entry
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/global/lighting/shadowmap.glsl"
#include "/global/lighting/wind.glsl"

in vec4 mc_Entity;
in vec3 at_midBlock;

out vec2 texcoord;
out vec4 tint;                  // vertex colour, feeds the coloured-shadow tint
out float waterHeight;

void main() {
	vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
	// Undoing the shadow view yields player space, which still contains the same
	// render-origin translation held in gbufferModelViewInverse[3]. The lit vertex
	// path uses mat3(gbufferModelViewInverse), so remove that translation before
	// sharing its eye-relative foliage displacement and absolute-water-Y formulas.
	vec3 playerSpacePos = (shadowModelViewInverse * viewPos).xyz;
	vec3 playerOriginOffset = gbufferModelViewInverse[3].xyz;
	vec3 eyeRelativePos = playerSpacePos - playerOriginOffset;

	// Raw block.properties IDs - see block.properties for the allocation table.
	bool isWater = abs(mc_Entity.x - 10001.0) < 0.5;
	bool isLeaves = abs(mc_Entity.x - 10002.0) < 0.5;
	bool isGroundFoliage = abs(mc_Entity.x - 10004.0) < 0.5
		|| abs(mc_Entity.x - 10005.0) < 0.5
		|| abs(mc_Entity.x - 10006.0) < 0.5;
	bool topOfFoliage = abs(mc_Entity.x - 10006.0) < 0.5
		|| ((abs(mc_Entity.x - 10004.0) < 0.5
			|| abs(mc_Entity.x - 10005.0) < 0.5) && at_midBlock.y < 0.0);
	bool noShadow = abs(mc_Entity.x - 10010.0) < 0.5;

	if (isWater
		// Only the upward face is a water/air boundary. Flowing water can have a valid
		// non-full-block top, so its at_midBlock height must not filter it out.
		&& gl_Normal.y > 0.999
	) {
		waterHeight = encode_water_height(eyeRelativePos.y + cameraPosition.y);
	} else {
		waterHeight = WATER_HEIGHT_NONE;
	}

#ifdef WAVING_FOLIAGE
	wave_foliage(isLeaves, isGroundFoliage, topOfFoliage, eyeRelativePos);
	vec3 displacedPlayerSpacePos = eyeRelativePos + playerOriginOffset;
	viewPos = shadowModelView * vec4(displacedPlayerSpacePos, 1.0);
#endif

	texcoord = gl_MultiTexCoord0.xy;
	tint = gl_Color;

	gl_Position = gl_ProjectionMatrix * viewPos;
	gl_Position.xyz = distort(gl_Position.xyz);

	// Shadow-transparent glass casts nothing (design.md 4.1). Steadfast writes
	// vec4(-1.0), which lands on the far-plane corner with w = -1 and is not reliably
	// clipped; collapsing the triangle to z > w clips it on the far plane for sure.
	if (noShadow) {
		gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
	}
}
