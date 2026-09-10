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

vec4 water_raytrace(sampler2D sceneDepth, vec3 viewPos, vec3 rayDirection,
                    vec3 interfaceNormal) {
    rayDirection = normalize(rayDirection);
    float rangeVisibility = 1.0 - smoothstep(64.0, 128.0, length(viewPos));
    if (rangeVisibility <= 0.0) return vec4(0.0);

    vec3 origin = viewPos + rayDirection * 0.02;
    float low = 0.0;
    float high = 0.0;
    float previous = 0.0;
    float stride = clamp(-viewPos.z * 0.0025, 0.08, 0.25);
    vec2 hitUV = vec2(0.0);
    float hitDepth = 1.0;
    bool found = false;
    // Keep the first depth crossing on the REFLECTED side. A submerged floor
    // must not end an above-water reflection before the ray reaches the shore.
    for (int i = 0; i < 24; ++i) {
        float travel = previous + stride;
        vec3 candidate = origin + rayDirection * travel;
        vec2 uv;
        if (!water_ssr_project(candidate, uv) || !water_ssr_gather_uv_valid(sceneDepth, uv)) break;
        float depth = water_ssr_depth_range(sceneDepth, uv).x;
        if (depth < 0.999999) {
            vec3 scene = screen_view(vec3(uv, depth));
            if (dot(scene - viewPos, interfaceNormal) > 0.0 && candidate.z <= scene.z) {
                low = previous;
                high = travel;
                hitUV = uv;
                hitDepth = depth;
                found = true;
                break;
            }
        }
        previous = travel;
        stride = min(stride * 1.6, 8.0);
    }
    if (!found) return vec4(0.0);

    // Refine a depth interval, without fitting a plane through unrelated leaves.
    // Six subdivisions leave at most 1/8 block for the largest coarse stride.
    for (int i = 0; i < 6; ++i) {
        float middle = 0.5 * (low + high);
        vec3 candidate = origin + rayDirection * middle;
        vec2 uv;
        if (!water_ssr_project(candidate, uv) || !water_ssr_gather_uv_valid(sceneDepth, uv)) break;
        float depth = water_ssr_depth_range(sceneDepth, uv).x;
        vec3 scene = screen_view(vec3(uv, depth));
        bool behind = depth < 0.999999 && dot(scene - viewPos, interfaceNormal) > 0.0
                   && candidate.z <= scene.z;
        if (behind) {
            high = middle;
            hitUV = uv;
            hitDepth = depth;
        } else {
            low = middle;
        }
    }
    vec3 endpoint = origin + rayDirection * high;
    float sceneZ = water_ssr_view_z(hitDepth, hitUV);
    float footprint = 2.0 * abs(sceneZ) / max(abs(gbufferProjection[1][1]) * viewHeight, 1.0);
    float thickness = max(0.25, footprint * 2.0);
    float residual = abs(sceneZ - endpoint.z);
    float confidence = 1.0 - smoothstep(thickness, thickness * 2.0, residual);
    float edge = min(min(hitUV.x, 1.0-hitUV.x), min(hitUV.y, 1.0-hitUV.y));
    confidence *= smoothstep(0.0, 0.03, edge) * rangeVisibility;
    return vec4(hitUV, hitDepth, confidence);
}

#endif
