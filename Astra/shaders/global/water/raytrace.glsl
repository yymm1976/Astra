#ifndef ASTRA_GLOBAL_WATER_RAYTRACE_GLSL
#define ASTRA_GLOBAL_WATER_RAYTRACE_GLSL

// Astra v1 - water/ice screen-space reflections.
// New Astra implementation based on the project specification and Khronos GLSL
// texture-gather/projection semantics; no source shader code was incorporated.
// Primary language reference (texture gather functions, section 8.7):
// https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.4.00.pdf
//
// Uniforms: gbufferProjection, gbufferProjectionInverse (lib/uniforms.glsl).
// The caller supplies depthtex1 and consumes the matching raw colour separately.
// Returns UV/depth and confidence; colour and optical length stay paired in the caller.

vec2 water_ssr_depth_range(sampler2D sceneDepth, vec2 uv) {
    ivec2 size = textureSize(sceneDepth, 0);
    float depth = texelFetch(sceneDepth, clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1), 0).r;
    // Trace actual geometry. A four-pixel minimum dilates a foreground silhouette.
    return vec2(depth);
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

// Neighbours are selected within the same depth surface, never across a silhouette.
bool water_scene_plane(sampler2D sceneDepth, vec2 uv, out vec3 center,
                       out vec3 planeNormal, out float footprint) {
    ivec2 size = textureSize(sceneDepth, 0);
    ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(1), size - 2);
    vec2 centerUV = (vec2(pixel) + 0.5) / vec2(size);
    float centerDepth = texelFetch(sceneDepth, pixel, 0).r;
    center = screen_view(vec3(centerUV, centerDepth));
    float leftD = texelFetch(sceneDepth, pixel + ivec2(-1,0), 0).r;
    float rightD = texelFetch(sceneDepth, pixel + ivec2(1,0), 0).r;
    float downD = texelFetch(sceneDepth, pixel + ivec2(0,-1), 0).r;
    float upD = texelFetch(sceneDepth, pixel + ivec2(0,1), 0).r;
    int dx = abs(leftD-centerDepth) < abs(rightD-centerDepth) ? -1 : 1;
    int dy = abs(downD-centerDepth) < abs(upD-centerDepth) ? -1 : 1;
    float xDepth = dx < 0 ? leftD : rightD;
    float yDepth = dy < 0 ? downD : upD;
    if (centerDepth >= 0.999999 || xDepth >= 0.999999 || yDepth >= 0.999999) return false;
    vec3 pointX = screen_view(vec3(centerUV + vec2(dx,0)/vec2(size), xDepth));
    vec3 pointY = screen_view(vec3(centerUV + vec2(0,dy)/vec2(size), yDepth));
    vec3 crossNormal = cross(pointX-center, pointY-center);
    if (dot(crossNormal,crossNormal) < 1e-12) return false;
    planeNormal = normalize(crossNormal);
    footprint = length(pointX-center) + length(pointY-center);
    return true;
}

vec4 water_raytrace(
	sampler2D sceneDepth,
	vec3 viewPos,
	vec3 rayDirection,
	float roughness
) {
	rayDirection = normalize(rayDirection);
	float roughnessVisibility = 1.0 - smoothstep(0.18, 0.48, clamp(roughness, 0.0, 1.0));
	float surfaceRangeVisibility = 1.0 - smoothstep(64.0, 128.0, length(viewPos));

	// Rays may travel towards the eye and still hit visible geometry below water.
	if (roughnessVisibility * surfaceRangeVisibility <= 0.0) {
		return vec4(0.0);
	}

	vec3 rayOrigin = viewPos + rayDirection * 0.02;
	float lowDistance = 0.0;
	float highDistance = 0.0;
	float previousDistance = 0.0;
	float stepLength = max(0.06, min(0.24, -viewPos.z * 0.0025));
	vec2 hitUv = vec2(0.0);
	bool bracketed = false;

	// Twenty coarse samples are followed by four binary steps and local-plane
	// reconstruction. Doubling the step covers open water quickly while preserving nearby
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
		}
	}

    // Four bisections leave up to 0.75 blocks of uncertainty after a 12-block
    // stride. Comparing that arbitrary residual to a 0.1-block thickness made
    // a continuous floor alternate between valid reflection and dark fallback.
    // Reconstruct a local opaque plane, choosing neighbours on its own side of
    // a silhouette, then intersect the ray with that plane analytically.
    vec3 center, planeNormal;
    float footprint;
    if (!water_scene_plane(sceneDepth, hitUv, center, planeNormal, footprint)) return vec4(0.0);
    ivec2 size = textureSize(sceneDepth, 0);
    float denominator = dot(planeNormal, rayDirection);
    if (abs(denominator) < 1e-5) return vec4(0.0);
    float travel = dot(planeNormal, center-rayOrigin) / denominator;
    if (travel < max(lowDistance - 0.25, 0.0) || travel > highDistance + 0.25) return vec4(0.0);
    vec3 point = rayOrigin + rayDirection * travel;
    if (!water_ssr_project(point, hitUv) || !water_ssr_gather_uv_valid(sceneDepth, hitUv)) return vec4(0.0);
    float actualDepth = texelFetch(sceneDepth, ivec2(hitUv * vec2(size)), 0).r;
    if (actualDepth >= 0.999999) return vec4(0.0);
    vec3 actual = screen_view(vec3(hitUv, actualDepth));
    float tolerance = max(0.08, footprint);
    float error = abs(actual.z - point.z);
    float geometryConfidence = 1.0 - smoothstep(tolerance, tolerance * 2.0, error);
    float edgeDistance = min(min(hitUv.x,1.0-hitUv.x), min(hitUv.y,1.0-hitUv.y));
    float confidence = smoothstep(0.0,0.10,edgeDistance) * roughnessVisibility
                     * surfaceRangeVisibility * geometryConfidence;
    return vec4(hitUv, actualDepth, confidence);
}

#endif
