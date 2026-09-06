#ifndef ASTRA_GLOBAL_WATER_RAYTRACE_GLSL
#define ASTRA_GLOBAL_WATER_RAYTRACE_GLSL

// Astra v1 - water/ice screen-space reflections.
// New Astra implementation based on the project specification and Khronos GLSL
// texture-gather/projection semantics; no source shader code was incorporated.
// Primary language reference (texture gather functions, section 8.7):
// https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.4.00.pdf
//
// Uniforms: gbufferProjection, gbufferProjectionInverse (lib/uniforms.glsl).
// The caller supplies colortex4 and depthtex1. Returned RGB remains linear HDR;
// alpha is hit confidence, and a miss is vec4(0.0).

vec2 water_ssr_depth_range(sampler2D sceneDepth, vec2 uv) {
	vec4 gathered = textureGather(sceneDepth, uv);
	return vec2(
		min(min(gathered.x, gathered.y), min(gathered.z, gathered.w)),
		max(max(gathered.x, gathered.y), max(gathered.z, gathered.w)));
}

float water_ssr_view_z(float depth, vec2 uv) {
	vec4 view = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	return view.z / view.w;
}

bool water_ssr_project(vec3 viewPosition, out vec2 uv) {
	vec4 clip = gbufferProjection * vec4(viewPosition, 1.0);
	if (clip.w <= 0.00001) {
		return false;
	}

	vec3 ndc = clip.xyz / clip.w;
	if (any(greaterThan(abs(ndc), vec3(1.0)))) {
		return false;
	}

	uv = ndc.xy * 0.5 + 0.5;
	return true;
}

bool water_ssr_gather_uv_valid(sampler2D sceneDepth, vec2 uv) {
	vec2 halfTexel = 0.5 / vec2(textureSize(sceneDepth, 0));
	return all(greaterThanEqual(uv, halfTexel))
		&& all(lessThanEqual(uv, vec2(1.0) - halfTexel));
}

vec4 water_raytrace(
	sampler2D sceneColor,
	sampler2D sceneDepth,
	vec3 viewPos,
	vec3 viewNormal,
	float roughness
) {
	vec3 normal = normalize(viewNormal);
	vec3 incident = normalize(viewPos);
	vec3 rayDirection = reflect(incident, normal);
	float roughnessVisibility = 1.0 - smoothstep(0.18, 0.48, clamp(roughness, 0.0, 1.0));

	// Rays returning toward the near plane cannot find reliable opaque screen data.
	if (roughnessVisibility <= 0.0 || dot(viewPos, rayDirection) <= 0.0) {
		return vec4(0.0);
	}

	vec3 rayOrigin = viewPos + normal * 0.04;
	float lowDistance = 0.0;
	float highDistance = 0.0;
	float previousDistance = 0.0;
	float stepLength = max(0.06, min(0.24, -viewPos.z * 0.0025));
	vec2 hitUv = vec2(0.0);
	vec2 hitDepthRange = vec2(1.0);
	vec3 hitRayPosition = rayOrigin;
	bool bracketed = false;

	// Twenty coarse samples leave four of the strict 24-sample budget for binary
	// refinement. Doubling the step covers open water quickly while preserving nearby
	// contacts through the small initial stride.
	for (int stepIndex = 0; stepIndex < 20; ++stepIndex) {
		float travel = previousDistance + stepLength;
		vec3 candidate = rayOrigin + rayDirection * travel;
		vec2 uv;
		if (!water_ssr_project(candidate, uv)
			|| !water_ssr_gather_uv_valid(sceneDepth, uv)) {
			return vec4(0.0);
		}

		vec2 depthRange = water_ssr_depth_range(sceneDepth, uv);
		if (depthRange.x < 0.999999) {
			float sceneNearZ = water_ssr_view_z(depthRange.x, uv);
			if (candidate.z <= sceneNearZ) {
				lowDistance = previousDistance;
				highDistance = travel;
				hitUv = uv;
				hitDepthRange = depthRange;
				hitRayPosition = candidate;
				bracketed = true;
				break;
			}
		}

		previousDistance = travel;
		stepLength = min(stepLength * 2.0, 12.0);
	}

	if (!bracketed) {
		return vec4(0.0);
	}

	// The last in-front point and first behind point form a valid interval. Four
	// bisections refine it without stochastic offsets or frame-dependent state.
	for (int refinement = 0; refinement < 4; ++refinement) {
		float middleDistance = 0.5 * (lowDistance + highDistance);
		vec3 candidate = rayOrigin + rayDirection * middleDistance;
		vec2 uv;
		if (!water_ssr_project(candidate, uv)
			|| !water_ssr_gather_uv_valid(sceneDepth, uv)) {
			return vec4(0.0);
		}

		vec2 depthRange = water_ssr_depth_range(sceneDepth, uv);
		if (depthRange.x >= 0.999999) {
			lowDistance = middleDistance;
			continue;
		}

		float sceneNearZ = water_ssr_view_z(depthRange.x, uv);
		if (candidate.z > sceneNearZ) {
			lowDistance = middleDistance;
		} else {
			highDistance = middleDistance;
			hitUv = uv;
			hitDepthRange = depthRange;
			hitRayPosition = candidate;
		}
	}

	float sceneNearZ = water_ssr_view_z(hitDepthRange.x, hitUv);
	float sceneFarZ = water_ssr_view_z(hitDepthRange.y, hitUv);
	float thickness = 0.10 + min(1.50, highDistance * 0.012);
	float hitError = sceneNearZ - hitRayPosition.z;
	float gatheredSpan = sceneNearZ - sceneFarZ;

	// Requiring the four gathered depths to agree within a view-space thickness
	// rejects silhouettes where bilinear depth would manufacture a false surface.
	float allowedSpan = max(0.35, thickness * 2.0);
	if (hitError < 0.0 || hitError > thickness || gatheredSpan > allowedSpan) {
		return vec4(0.0);
	}

	float edgeDistance = min(min(hitUv.x, 1.0 - hitUv.x), min(hitUv.y, 1.0 - hitUv.y));
	float edgeVisibility = smoothstep(0.0, 0.10, edgeDistance);
	float depthConfidence = 1.0 - smoothstep(0.35 * thickness, thickness, hitError);
	float rangeConfidence = 1.0 - smoothstep(0.45 * allowedSpan, allowedSpan, gatheredSpan);
	float confidence = edgeVisibility * roughnessVisibility * depthConfidence * rangeConfidence;

	if (confidence <= 0.0) {
		return vec4(0.0);
	}

	return vec4(textureLod(sceneColor, hitUv, 0.0).rgb, confidence);
}

#endif
