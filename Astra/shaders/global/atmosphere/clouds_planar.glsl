#ifndef ASTRA_GLOBAL_ATMOSPHERE_CLOUDS_PLANAR_GLSL
#define ASTRA_GLOBAL_ATMOSPHERE_CLOUDS_PLANAR_GLSL

// Astra v1 - three-lookup, world-anchored wispy cloud sheet.
// Uniforms: cameraPosition, frameTimeCounter, rainStrength, noisetex.
// Requires settings.glsl before this module. Original Astra implementation.

vec4 astra_planar_cloud(vec3 worldDir, vec3 directLight, vec3 ambientLight) {
	const float cloudAltitude = 128.0;
	float dy = worldDir.y;
	float safeDy = dy >= 0.0 ? max(dy, 0.002) : min(dy, -0.002);
	float rayDistance = (cloudAltitude - cameraPosition.y) / safeDy;
	if (rayDistance <= 0.0 || rayDistance > 7000.0) return vec4(0.0);

	vec2 worldXZ = cameraPosition.xz + worldDir.xz * rayDistance;
	vec2 wind = vec2(frameTimeCounter * 0.0009, frameTimeCounter * 0.00035);
	vec2 uv = worldXZ * 0.00155 + wind;
	float broad = texture(noisetex, uv).r;
	float wisps = texture(noisetex, uv * 2.07 + vec2(-0.17, 0.31)).r;
	float detail = texture(noisetex, uv * 4.13 + vec2(0.43, -0.09)).r;
	float shape = broad * 0.62 + wisps * 0.28 + detail * 0.10;
	float threshold = mix(0.74, 0.43, CLOUD_COVERAGE * 0.01);
	float alpha = smoothstep(threshold, threshold + 0.16, shape);
	alpha *= smoothstep(0.015, 0.11, abs(dy));
	alpha *= mix(0.70, 1.0, rainStrength);

	float sunFacing = pow(max(0.0, dot(worldDir, normalize(worldSunVector))), 8.0);
	vec3 light = ambientLight * 0.72 + directLight * (0.18 + 0.20 * sunFacing);
	vec3 cloudColor = mix(light, vec3(dot(light, vec3(0.25, 0.65, 0.10))) * 0.68,
	                      rainStrength * 0.72);
	return vec4(max(cloudColor, vec3(0.025)), alpha * 0.72);
}

#endif
