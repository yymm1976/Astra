#ifndef ASTRA_GLOBAL_WATER_REFRACTION_GLSL
#define ASTRA_GLOBAL_WATER_REFRACTION_GLSL

// Astra v1 — global/water/refraction.glsl
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot
//   source: _analysis/Steadfast-0.8.0/shaders/environment/water/refraction.glsl
// This file is a derivative of Steadfast and is licensed under the GNU General
// Public License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
// _analysis/Steadfast-0.8.0/LICENSE.md. Redistribution is permitted only under that
// license including Steadfast's Section 7 additional terms.
// Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Non-physical single-hop screen-space refraction (design.md 4.3: 背景深度直接跳一步 +
// textureGather min/max 深度拒绝 + 屏幕边缘 10% 混回). Marching a ray is too expensive
// and looks worse for refraction, where we do not want to reject hits: because E2 keeps
// the refract direction close to the incident vector, the refracted point lands near the
// background point, so we read the background depth, jump that far, and accept it.
//
// Adaptations for Astra (design.md 1.2 / 2.4 / 3.2):
//   - Astra is Iris-only on `#version 400 compatibility`, where textureGather is CORE
//     (design.md 3.2: 免扩展检测舞蹈). Steadfast's `#ifdef MC_GL_ARB_texture_gather`
//     guard and its texelFetch fallback are dead here and are removed. That fallback was
//     the ONLY consumer of `uniform float viewWidth/viewHeight`, which are NOT in Astra's
//     frozen uniform set (lib/uniforms.glsl, SC-14) — so dropping it drops the only
//     non-frozen dependency and leaves the module with zero uniform declarations of its own.
//   - depthBuffer / colorBuffer stay FUNCTION PARAMETERS (Steadfast's own signature): C2
//     must not privately open buffers (task directive). The caller passes depthtex0 and
//     colortex4 plus depthtex1 (design.md 2.3: the opaque scene copy and opaque depth).
//   - gbufferProjection / gbufferProjectionInverse are frozen uniforms, used directly
//     instead of passed (Steadfast passed them; Astra freezes them in uniforms.glsl).
//   - Steadfast's MIN_DEPTH/MAX_DEPTH accessor macros are dropped in favour of explicit
//     .x/.y so the generic macro names cannot collide with the SSR/surface modules that
//     share lit.fsh's compilation unit. Renamed to snake_case (design.md 3.2).
//
// Interface contract (E2 owns the water surface; C2 delivers the trace body only):
//   - viewPos:          view-space position of the refracting surface fragment.
//   - refractDirection: view-space refracted ray direction, built by E2 from the animated
//                       water-surface normal (global/water/surface.glsl, SC-15) and scaled
//                       by REFRACTION_STRENGTH. C2 does NOT compute the water normal — that
//                       surface integration is explicitly reserved to E2 (不越界).
//   - maxRefractDistance: clamp on the single hop, in blocks.
//   - refract_trace returns vec3(screenUV.x, screenUV.y, hitDepth); feed screenUV to
//     refraction_safe_sample(colortex4, uv) to read the refracted background color.
//
// Uniforms: gbufferProjection, gbufferProjectionInverse (lib/uniforms.glsl).
// Owner: C2. Consumer: E2.

// Min (x) and max (y) of the 4 depth texels around `at`, via textureGather. Gathering
// instead of texture() avoids bilinear-filtering the depth buffer, which would interpolate
// across depth discontinuities and fringe the pass/fail boundary — the exact edge noise
// design.md 2.4 names textureGather rejection as the cure for (Astra has no TAA).
vec2 depth_range(sampler2D depthBuffer, vec2 at) {
	vec4 depthX4 = textureGather(depthBuffer, at);
	float minDepth = min(min(depthX4.x, depthX4.y), min(depthX4.z, depthX4.w));
	float maxDepth = max(max(depthX4.x, depthX4.y), max(depthX4.z, depthX4.w));
	return vec2(minDepth, maxDepth);
}

bool refraction_gather_uv_valid(sampler2D depthBuffer, vec2 at) {
	vec2 halfTexel = 0.5 / vec2(textureSize(depthBuffer, 0));
	return all(greaterThanEqual(at, halfTexel))
		&& all(lessThanEqual(at, vec2(1.0) - halfTexel));
}

vec3 refract_trace(
	sampler2D depthBuffer,
	vec3 viewPos,
	vec3 refractDirection,
	float maxRefractDistance
) {
	// A zero vector is the specified result of refract() under total internal
	// reflection. Treat it as a rejected offset and keep the unrefracted sample.
	bool totalInternalReflection = dot(refractDirection, refractDirection) < 1e-8;

	// 1. Background depth at the un-refracted screen position (max of the gather: the
	//    jump target is the far side of whatever sits behind the water here).
	vec4 clipPos = gbufferProjection * vec4(viewPos, 1.0);
	if (clipPos.w <= 0.00001) {
		return vec3(0.5, 0.5, 1.0);
	}
	vec3 ndcPos = clipPos.xyz / clipPos.w;
	vec2 backgroundPos2D = ndcPos.xy * 0.5 + 0.5;
	if (any(greaterThan(abs(ndcPos), vec3(1.0)))
		|| !refraction_gather_uv_valid(depthBuffer, backgroundPos2D)) {
		return vec3(clamp(backgroundPos2D, vec2(0.0), vec2(1.0)), 1.0);
	}
	float backgroundDepth = depth_range(depthBuffer, backgroundPos2D).y;
	if (totalInternalReflection) {
		return vec3(backgroundPos2D, backgroundDepth);
	}

	// Linearize that depth to a view-space Z so we know how far to jump. In view space the
	// camera rotation is already applied and Z is depth, so only Z matters below.
	ndcPos.z = backgroundDepth * 2.0 - 1.0;
	vec4 homogenousPos = gbufferProjectionInverse * vec4(ndcPos, 1.0);
	float backgroundViewPosZ = homogenousPos.z / homogenousPos.w;

	// 2. Advance along the refracted ray by that Z distance, clamped to maxRefractDistance.
	float refractDistance = min(abs(viewPos.z - backgroundViewPosZ), maxRefractDistance);
	vec3 viewPosRefracted = viewPos + refractDirection * refractDistance;

	// 3. Project the refracted point. A screen-space method has no data off-screen, so in
	//    the outer 10% blend the sample back to the background position (design.md 4.3
	//    边缘混回); with E2's tightly-bounded refract direction this hides the seam.
	vec4 refractedClipPos = gbufferProjection * vec4(viewPosRefracted, 1.0);
	if (refractedClipPos.w <= 0.00001) {
		return vec3(backgroundPos2D, backgroundDepth);
	}
	vec2 refractedPosNdc = refractedClipPos.xy / refractedClipPos.w;
	float hitPosMax = max(abs(refractedPosNdc.x), abs(refractedPosNdc.y));
	float visibility = clamp((1.0 - hitPosMax) / 0.10, 0.0, 1.0);
	vec2 refractedPos2D = refractedPosNdc * 0.5 + 0.5;
	refractedPos2D = mix(backgroundPos2D, refractedPos2D, visibility);
	if (abs(refractedClipPos.z / refractedClipPos.w) > 1.0
		|| !refraction_gather_uv_valid(depthBuffer, refractedPos2D)) {
		return vec3(backgroundPos2D, backgroundDepth);
	}

	// 4. Reject a hit that ended up in front of the refracting surface (gl_FragCoord.z
	//    deeper than the gathered min): that is not a valid hit, it happens at water edges.
	//    Fall back to the background, i.e. no refraction at all on those pixels.
	vec2 refractDepthRange = depth_range(depthBuffer, refractedPos2D);
	float refractDepth = refractDepthRange.y;
	if (gl_FragCoord.z > refractDepthRange.x
		|| refractDepthRange.y >= 0.999999) {
		refractedPos2D = backgroundPos2D;
		refractDepth = backgroundDepth;
	}

	return vec3(refractedPos2D, refractDepth);
}

// Read the background color at the refracted position. Bilinear is safe here (and keeps the
// color texture filtered) precisely because depth_range already confirmed all four gathered
// texels pass the depth rejection — there is no closer geometry bleeding in.
vec4 refraction_safe_sample(sampler2D colorBuffer, vec2 at) {
	return texture(colorBuffer, at);
}

#endif
