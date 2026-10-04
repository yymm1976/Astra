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
//           astraFoliageWindPhases (lib/uniforms.glsl)
// design.md 3.2 layer 2: program/* is the only lib entry
#include "/lib/settings.glsl"
// Option reference for Iris: shaders.properties owns caster-list filtering,
// which must happen before drawing rather than after entering this shader.
#ifdef ENTITY_SHADOWS
#endif
#include "/lib/uniforms.glsl"
#include "/global/lighting/shadowmap.glsl"
#include "/global/lighting/wind.glsl"

in vec4 mc_Entity;
in vec3 at_midBlock;

out vec2 texcoord;
out vec4 tint;                  // vertex colour, feeds the coloured-shadow tint
out float waterHeight;
out vec3 waterCasterWorld;

// Nether voxel capture. Both guards are required: the option is global while the
// uimage3D declaration and imageAtomicMax need GLSL 420+, so the overworld and
// End shadow shells must not see them at all.
#if defined DIMENSION_NETHER && defined NETHER_VOXEL_LIGHT && defined SHADOWS && BLOCKLIGHT_STRENGTH > 0
#include "/lib/nether_voxel_grid.glsl"
layout(r32ui) uniform uimage3D astraVoxelImage;
// Occupancy encoding consumed by program/nether_light.csh and
// global/dimension/nether_colored_light.glsl:
//   bit 8  : solid geometry -> blocks diffusion
//   bits 0-7: 0 = air, 1 = solid/unlit, 2..8 = coloured light groups,
//            9..11 = fire, soul fire, lava
// There is deliberately NO frame stamp. The image directive declares clear=true
// (shaders.properties), so Iris zeroes the whole volume every frame: an unwritten cell
// reads as 0 and 0 already means "air". An earlier version added a 2-bit stamp to retire
// unloaded regions; it was both unnecessary and wrong - ordinary air has no vertices, so
// it is never written, and the stamp made the march treat unwritten air as stale on one
// frame parity and valid on the other, flipping the light field every other frame.
uint astra_voxel_encode(uint kind, bool solid) {
    return (kind & 255u) | (solid ? 256u : 0u);
}
void astra_voxel_write() {
    // MC_RENDER_STAGE_* values must match Iris WorldRenderingPhase ordinals; see the
    // table note in qa/tools/compile_glsl.py before changing this list.
    if (!(renderStage == MC_RENDER_STAGE_TERRAIN_SOLID || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT
       || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED || renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT)) return;
    vec3 center = (shadowModelViewInverse * gl_ModelViewMatrix * vec4(gl_Vertex.xyz + at_midBlock/64.0,1.0)).xyz;
    ivec3 cell = astra_nether_voxel_cell(center, fract(cameraPosition));
    if(!astra_nether_voxel_in_bounds(cell)) return;
    int raw = int(mc_Entity.x+0.5);
    // Any rendered vertex marks its cell as captured. kind 0 = captured air, kind 1 =
    // captured solid, 2..8 = coloured light groups, 9..11 = fire/soul fire/lava. The
    // diffusion pass only spreads through kind 0, so an unlit-but-rendered cell must be
    // 0 here; writing 1 for it (the pre-handoff behaviour) made every air cell look
    // solid and the propagation loop never ran at all.
    uint kind = 0u;
    bool solid = true;
    // Water, plants and torches are not full cubes: they must not block the volume.
    if(raw == 10001 || raw == 10010 || (raw >= 10003 && raw <=10006)) { kind = 0u; solid = false; }
    if(raw == 10033) { kind = 0u; solid = false; }
    if(raw >=10021 && raw <=10027) { kind=uint(raw-10019); solid = false; }
    // Opaque emitting cubes radiate their own species but block light arriving
    // from other sources, just as the lava cell does below.
    if(raw >=10034 && raw <=10040) { kind=uint(raw-10032); solid = true; }
    if(raw ==10028) { kind=9u; solid = false; }
    if(raw ==10029) { kind=10u; solid = false; }
    // lava is opaque, so it keeps the solid bit; the march is written to still read the
    // light OUT of an emitter cell (see nether_light.csh), so lava can light its
    // neighbours while remaining a blocker for light coming from elsewhere.
    if(raw ==10030) kind=11u;
    imageAtomicMax(astraVoxelImage,cell,astra_voxel_encode(kind,solid));
}
#endif
void main() {
#if defined DIMENSION_NETHER && defined NETHER_VOXEL_LIGHT && defined SHADOWS && BLOCKLIGHT_STRENGTH > 0
    astra_voxel_write();
#endif
    bool isGroundFoliage = abs(mc_Entity.x - 10004.0) < 0.5
        || abs(mc_Entity.x - 10005.0) < 0.5
        || abs(mc_Entity.x - 10006.0) < 0.5;
    bool noShadow = abs(mc_Entity.x - 10010.0) < 0.5;
    // Glass remains shadow-transparent. Plants follow the same animated
    // alpha-cutout projection as their visible geometry, including both halves.
    if (noShadow) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        texcoord = gl_MultiTexCoord0.xy;
        tint = gl_Color;
        waterHeight = WATER_HEIGHT_NONE;
        waterCasterWorld = vec3(0.0);
        return;
    }
	vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
	// Sodium's region offset already subtracts cameraPosition. Undo only this
	// pass's shadow view: the result is camera-relative, exactly as in lit.vsh.
	// The main camera's inverse-view translation is unrelated to this transform.

	// Raw block.properties IDs - see block.properties for the allocation table.
	bool isWater = abs(mc_Entity.x - 10001.0) < 0.5;
	bool isLeaves = abs(mc_Entity.x - 10002.0) < 0.5;
	bool topOfFoliage = abs(mc_Entity.x - 10006.0) < 0.5
		|| ((abs(mc_Entity.x - 10004.0) < 0.5
			|| abs(mc_Entity.x - 10005.0) < 0.5) && at_midBlock.y < 0.0);

    // Static opaque casters already have their final shadow-view position.
    // Only water records, displaced foliage and the End projection need world space.
    vec3 eyeRelativePos = vec3(0.0);
    #ifdef DIMENSION_END
        eyeRelativePos = (shadowModelViewInverse * viewPos).xyz;
    #else
        bool needsWorldPosition = isWater;
        #ifdef WAVING_FOLIAGE
        needsWorldPosition = needsWorldPosition || isLeaves || (isGroundFoliage && topOfFoliage);
        #endif
        if (needsWorldPosition) eyeRelativePos = (shadowModelViewInverse * viewPos).xyz;
    #endif

	if (isWater
		// Fluid surfaces have opposing faces. The downward copy can win the
		// shadow depth tie (observed ID 10001, normal.y=-1 at noon underwater).
		// Solas classifies water independently of orientation; accept both copies
		// here, retaining a horizontal-face gate for Astra's height anchor.
		&& abs(gl_Normal.y) > 0.9
	) {
		waterHeight = encode_water_height(eyeRelativePos.y + cameraPosition.y);
	} else {
		waterHeight = WATER_HEIGHT_NONE;
	}

#ifdef WAVING_FOLIAGE
    // Other casters already have their original shadow-view position.
    if (isLeaves || (isGroundFoliage && topOfFoliage)) {
        wave_foliage(isLeaves, isGroundFoliage, topOfFoliage, eyeRelativePos);
        viewPos = shadowModelView * vec4(eyeRelativePos, 1.0);
    }
#endif

	waterCasterWorld = eyeRelativePos + cameraPosition;
	texcoord = gl_MultiTexCoord0.xy;
	tint = gl_Color;

    #ifdef DIMENSION_END
    gl_Position = vec4(end_shadow_ndc(eyeRelativePos),1.0);
    #else
	gl_Position = gl_ProjectionMatrix * viewPos;
    #endif
	// Use the rasterizer's triangle depth. Surface receivers interpolate this
	// same vertex projection in lit.vsh; neither pass extrapolates a plane.
	gl_Position.xyz = distort(gl_Position.xyz / gl_Position.w) * gl_Position.w;

}
