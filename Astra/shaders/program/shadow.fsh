// Astra v1 - program/shadow.fsh (shadow pass: caster tint / cached caustic focus)
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
#if !defined ASTRA_SOLID_SHADOW || defined DIMENSION_NETHER || defined DIMENSION_END
#include "/lib/encoding.glsl"
#endif
#include "/global/lighting/shadowmap.glsl"
in vec2 texcoord;
in vec4 tint;
in float waterHeight;
flat in int waterCasterKind;
in vec3 waterCasterWorld;
#if defined SHADOWS && !defined DIMENSION_NETHER && !defined DIMENSION_END
in vec3 shadowUndistortedPosition;
flat in vec3 shadowCasterPlaneNormal;
#ifndef ASTRA_SOLID_SHADOW
flat in vec4 shadowFoliageTexBounds;
#endif
#endif
#include "/global/water/caustics.glsl"

// Caustic focus can exceed one; retain it in FP16.
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
#ifndef RGBA16F
const int RGBA16F = 0;
#endif
const int shadowcolor0Format = RGBA16F;
#endif

/* RENDERTARGETS: 0 */
// GBA stores a non-water caster's transmission. A water caster's GB has no
// reader; its A holds the caustic focus. A is data, not coverage.
// Iris adds an output-alpha discard to legacy gl_FragData[0] writes. Use an
// explicit data output so only the source-albedo cutout below clips geometry;
// keep alphaTestRef supplied by Iris (including the terrain cutout threshold).
layout(location = 0) out vec4 shadowData;

void main() {
#if defined SHADOWS && !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Derivatives must precede the material/alpha branches. All three original
    // coordinates lie on the actual caster plane, independent of the diagonal.
    vec3 shadowDx=dFdx(shadowUndistortedPosition);
    vec3 shadowDy=dFdy(shadowUndistortedPosition);
    float shadowDet=shadowDx.x*shadowDy.y-shadowDx.y*shadowDy.x;
    vec2 ray=undistort(vec3(gl_FragCoord.xy*(2.0/float(shadowMapResolution))-1.0,0.0)).xy;
    #ifndef ASTRA_SOLID_SHADOW
    // Derive texture gradients before any alpha/material branch. Depth and the
    // foliage cutout must describe the SAME inverse-warped light ray. Ordinary
    // interpolation on a radially warped triangle makes the holes slide over
    // its depth plane as the camera moves, independently of wind strength.
    vec2 shadowTexcoord=texcoord;
    vec2 shadowTexcoordDx=dFdx(texcoord), shadowTexcoordDy=dFdy(texcoord);
    vec2 rayDx=dFdx(ray), rayDy=dFdy(ray);
    bool foliageCaster=shadowFoliageTexBounds.z>shadowFoliageTexBounds.x
        && shadowFoliageTexBounds.w>shadowFoliageTexBounds.y;
    if (foliageCaster && abs(shadowDet)>1e-20) {
        vec2 uvRawX=(shadowTexcoordDx*shadowDy.y-shadowTexcoordDy*shadowDx.y)/shadowDet;
        vec2 uvRawY=(shadowTexcoordDy*shadowDx.x-shadowTexcoordDx*shadowDy.x)/shadowDet;
        vec2 rawDelta=ray-shadowUndistortedPosition.xy;
        shadowTexcoord+=uvRawX*rawDelta.x+uvRawY*rawDelta.y;
        shadowTexcoordDx=uvRawX*rayDx.x+uvRawY*rayDx.y;
        shadowTexcoordDy=uvRawX*rayDy.x+uvRawY*rayDy.y;
        // The straight raster edge can extend beyond the inverse-warped face.
        // Keep its corrected lookup inside this quad's atlas rectangle.
        vec2 inset=min(0.5/vec2(textureSize(gtexture,0)),
                       (shadowFoliageTexBounds.zw-shadowFoliageTexBounds.xy)*0.25);
        shadowTexcoord=clamp(shadowTexcoord,shadowFoliageTexBounds.xy+inset,
                                          shadowFoliageTexBounds.zw-inset);
    }
    #endif
    gl_FragDepth=gl_FragCoord.z;
    bool analyticPlane = abs(shadowCasterPlaneNormal.z)>1e-6;
    if (waterCasterKind==0 && (analyticPlane || abs(shadowDet)>1e-20)) {
        vec2 plane=analyticPlane ? -shadowCasterPlaneNormal.xy/shadowCasterPlaneNormal.z
            : vec2(shadowDy.y*shadowDx.z-shadowDx.y*shadowDy.z,
                   shadowDx.x*shadowDy.z-shadowDy.x*shadowDx.z)/shadowDet;
        float planeDepth=(shadowUndistortedPosition.z
            +dot(ray-shadowUndistortedPosition.xy,plane))*0.25+0.5;
        // Receiver and caster must describe the same inverse-warped plane.
        // Clamping this to raster depth preserves the triangle's diagonal error
        // on one side, including static trunks. Correction can go either way;
        // declaring depth_greater would therefore be invalid for solid casters.
        gl_FragDepth=planeDepth;
    }
#endif
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    #ifdef ASTRA_SOLID_SHADOW
    // The dedicated solid program has OFF alpha in Iris and no pack override.
    // Non-water stores only its category marker; there is no material sample or
    // potential discard anywhere in this compiled fragment program. A mod or
    // resource can still place an actual water model in SOLID, so keep its record.
    if (waterCasterKind == 0) {
        shadowData = vec4(WATER_HEIGHT_NONE, 1.0, 1.0, 1.0);
        return;
    }
    #else
    // Iris 1.11.2 uses AlphaTests.OFF (reference 0) for Sodium's solid
    // shadow terrain. These casters are copied into BOTH shadow depths before
    // translucent terrain: their per-corner transparent weight is always zero.
    // Only the neutral non-water marker can be consumed from their colour record.
    // Keep the reference guard for engines/overrides that still clip this stage;
    // cutout foliage, entities and horizontal water retain their complete path.
    if (renderStage == MC_RENDER_STAGE_TERRAIN_SOLID && alphaTestRef <= 0.0
        && waterCasterKind == 0) {
        shadowData = vec4(WATER_HEIGHT_NONE, 1.0, 1.0, 1.0);
        return;
    }
    #endif
    // Derivatives must be evaluated before the per-caster water branch. They feed
    // only the caustic focus now, so a caustics-off build never pays for them.
    #ifdef WATER_CAUSTICS
    float waterFootprint = max(length(dFdx(waterCasterWorld.xz)),
                               length(dFdy(waterCasterWorld.xz)));
    #endif
    // Horizontal water stores its optical record, independent of texture alpha
    // and tint. It needs no material texture sample or caster-tint preparation.
    if (waterCasterKind == 1) {
        // An unrepresentable custom-world height stays neutral water, never tint.
        if (waterHeight >= WATER_HEIGHT_NONE) {
            shadowData = vec4(WATER_HEIGHT_NONE, 1.0, 1.0, 1.0);
            return;
        }
        // Volume beams evaluate their own optical wave entries, so a caster's
        // GB has no reader. Build the focus in A only for surface caustics.
        float focus = 1.0;
        #ifdef WATER_CAUSTICS
        focus = astra_water_caustic_focus(waterCasterWorld, waterFootprint);
        #endif
        shadowData = vec4(waterHeight, 1.0, 1.0, focus);
        return;
    }
    #endif
    #if defined ASTRA_SOLID_SHADOW && !defined DIMENSION_NETHER && !defined DIMENSION_END
    shadowData = vec4(WATER_HEIGHT_NONE, 1.0, 1.0, 1.0);
    #else
    #if defined SHADOWS && !defined DIMENSION_NETHER && !defined DIMENSION_END
        vec4 albedo = textureGrad(gtexture,shadowTexcoord,shadowTexcoordDx,shadowTexcoordDy) * tint;
    #else
		vec4 albedo = texture(gtexture, texcoord) * tint;
    #endif

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
    #endif
}
