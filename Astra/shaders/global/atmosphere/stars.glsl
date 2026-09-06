#ifndef ASTRA_GLOBAL_ATMOSPHERE_STARS_GLSL
#define ASTRA_GLOBAL_ATMOSPHERE_STARS_GLSL

// Astra v1 - face-local cubemap star cells with footprint filtering.
// Uniforms: frameTimeCounter, skyVisibilityDay, rainStrength.
// Original implementation; high-frequency stars are consumed only by the visible sky path.

float astra_star_hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

vec3 astra_star_field(vec3 worldDir) {
	vec3 direction = normalize(worldDir);
	vec3 ad = abs(direction);
	vec2 faceUv;
	float face;
	if (ad.x >= ad.y && ad.x >= ad.z) {
		faceUv = direction.yz / ad.x;
		face = direction.x > 0.0 ? 0.0 : 1.0;
	} else if (ad.y >= ad.z) {
		faceUv = direction.xz / ad.y;
		face = direction.y > 0.0 ? 2.0 : 3.0;
	} else {
		faceUv = direction.xy / ad.z;
		face = direction.z > 0.0 ? 4.0 : 5.0;
	}

	vec2 grid = (faceUv * 0.5 + 0.5) * 150.0;
	vec2 cell = floor(grid);
	vec2 local = fract(grid) - 0.5;
	vec3 key = vec3(cell, face * 173.0);
	float presence = astra_star_hash(key);

	// Evaluate derivatives before the cell branch; derivatives in divergent flow are undefined.
	float pixel = max(fwidth(grid.x), fwidth(grid.y));
	if (presence < 0.985) return vec3(0.0);

	vec2 jitter = vec2(astra_star_hash(key + 19.1), astra_star_hash(key + 71.7)) - 0.5;
	float baseRadius = mix(0.055, 0.13, pow((presence - 0.985) / 0.015, 2.0));
	float radius = max(baseRadius, 0.52 * pixel);
	float flux = min(1.0, baseRadius * baseRadius / max(radius * radius, 1e-5));
	float star = 1.0 - smoothstep(0.18 * radius, radius, length(local - jitter * 0.58));
	float phase = astra_star_hash(key + 131.0) * 6.2831853;
	float twinkle = 0.94 + 0.06 * sin(frameTimeCounter * 1.7 + phase);
	float faceEdge = smoothstep(0.0, 0.035, 1.0 - max(abs(faceUv.x), abs(faceUv.y)));
	float visibility = (1.0 - skyVisibilityDay) * (1.0 - rainStrength)
	                 * smoothstep(-0.02, 0.12, direction.y) * faceEdge;
	vec3 tint = mix(vec3(0.68, 0.79, 1.0), vec3(1.0, 0.78, 0.58), astra_star_hash(key + 241.0));
	return tint * (star * flux * twinkle * visibility * 1.8);
}

#endif
