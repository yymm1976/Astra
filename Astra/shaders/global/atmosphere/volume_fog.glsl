#ifndef ASTRA_GLOBAL_ATMOSPHERE_VOLUME_FOG_GLSL
#define ASTRA_GLOBAL_ATMOSPHERE_VOLUME_FOG_GLSL

// Bare option site (check_pack #11 / SC-28): Iris discovers VOLUMETRIC_FOG from this
// #ifdef in a compiled source; lib/settings.glsl alone is not scanned for options.
// Everything below is compiled only while the option is on.
#ifdef VOLUMETRIC_FOG

// Astra v1 — global/atmosphere/volume_fog.glsl (R2 / H3 optional overworld volume).
//
// The ray-marched owner of the ordinary overworld AIR segment when VOLUMETRIC_FOG is
// on. Density is a function of ABSOLUTE world height (the same convention as
// fog_valley_mist: the layer lives in the world, not in camera space), thickened by a
// bounded weather gain. Per-step the source term is one sun-or-moon lobe (the pack's
// astra_direct_light palette, a Henyey-Greenstein phase, the shadow map and the B2
// cloud-shadow cache) plus a sky-ambient incident with the cave floor as its lower
// bound. Integration and composition are lib/volume_integral.glsl's: this file only
// prepares per-segment source and extinction.
//
// Ownership table and the deferred/deferred1/deferred2 scheduling live in
// docs/archive/实现与取证.md#record-077. Blindness, lava, powder snow, the
// underwater camera leg and the water volume itself are NOT owned here.
//
// Requires (included by program/scene.glsl before this file): transforms, pow,
// shadowmap, lighting facades (astra_direct_light / astra_sky_ambient), weather
// (astra_cloud_transmission), lib/colors.glsl (MIN_AMBIENT_COLOR).
#include "/lib/bayer.glsl"
#include "/lib/volume_integral.glsl"

// SUMMARY idea: Nostalgia/Kappa/Hysteria distance-adaptive volume sampling.
// Original Astra scheduling; quality sets the maximum, short rays use fewer steps.
#if VOLUME_FOG_QUALITY == 0
#define ASTRA_VOLUME_STEPS 12
#define ASTRA_VOLUME_PREFIX_STEPS 4
#elif VOLUME_FOG_QUALITY == 2
#define ASTRA_VOLUME_STEPS 48
#define ASTRA_VOLUME_PREFIX_STEPS 12
#else
#define ASTRA_VOLUME_STEPS 24
#define ASTRA_VOLUME_PREFIX_STEPS 8
#endif
#define ASTRA_VOLUME_MAX_DISTANCE 192.0
#define ASTRA_VOLUME_SEA_LEVEL 62.0
#define ASTRA_VOLUME_HEIGHT_SCALE 28.0
#define ASTRA_VOLUME_HEIGHT_FLOOR 0.15
// Base extinction (0.004) and rain gain (2.2) are owned by the CPU-side
// astraVolumeDensity expression in shaders.properties.
// Forward-scattering anisotropy g of the sun/moon lobe, bounded to [-0.8, 0.8]. A
// source constant rather than a menu option. 0.60 reads as
// a visible forward lobe without a blinding core.
#define ASTRA_VOLUME_PHASE_G 0.60

// Extinction per block at an absolute world height. Valleys hold the full density,
// high ground keeps a bounded floor so mountains and the build limit stay hazy
// rather than perfectly clear.
float astra_volume_extinction(float worldY, float density) {
    // Below sea level the clamped exponent is exactly zero and height is one.
    if (worldY <= ASTRA_VOLUME_SEA_LEVEL) return density;
	float height = ASTRA_VOLUME_HEIGHT_FLOOR
	             + (1.0 - ASTRA_VOLUME_HEIGHT_FLOOR)
	             * exp(-max(worldY - ASTRA_VOLUME_SEA_LEVEL, 0.0) / ASTRA_VOLUME_HEIGHT_SCALE);
	return density * height;
}

// Henyey-Greenstein phase for one lobe. g is the bounded source constant above.
float astra_volume_phase(float mu) {
	float g = clamp(ASTRA_VOLUME_PHASE_G, -0.8, 0.8);
	float g2 = g * g;
    float base = 1.0 + g2 - 2.0 * g * mu;
	return (1.0 - g2) / (12.5663706 * base * sqrt(base));
}

// Sky-ambient incident radiance for the in-scatter floor. The cave floor colour is
// the lower bound: in caves and at night the air keeps a faint readable haze instead
// of the old cave-fog palette (which this option replaces in the overworld air).
vec3 astra_volume_incident() {
	float eyeSky = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
	vec3 outdoor = astra_sky_ambient() * (SKYLIGHT_STRENGTH * 0.01);
	return mix(MIN_AMBIENT_COLOR, outdoor, smoothstep(0.0, 0.40, eyeSky));
}

// Per-sample source radiance (NOT yet multiplied by extinction). lightDirWorld is the
// shadow light (sun by day, moon by night) in player-relative world axes - the same
// direction astra_direct_light's palette is built for. cloud transmission comes from
// the B2 cache; the shadow map is queried only on the production march, where its
// cost is amortised over half-resolution pixels. shadow coverage fades with the
// map's own range and leaves open sky lit, exactly like deferred's rainy_air.
vec3 astra_volume_light(vec3 playerPos, vec3 lightDirWorld, vec3 direct,
                        vec3 incident, vec4 shadowClip, bool shadowMap) {
	// Extinction and ambient scattering still apply when the direct source is off.
	// Its visibility queries cannot contribute in that case.
	if (all(lessThanEqual(direct, vec3(0.0)))) return incident;
	vec3 light = direct * astra_cloud_transmission(playerPos + cameraPosition, lightDirWorld);
#ifdef SHADOWS
	float mapFade = shadowMap ? shadow_map_fade(playerPos) : 0.0;
	if (mapFade > 0.0) {
		vec3 sp = distort(shadowClip.xyz / shadowClip.w) * 0.5 + 0.5;
		sp.z -= 0.00002;
		float coverage = mapFade * shadow_uv_coverage(sp);
		if (coverage > 0.0)
			light *= mix(1.0, shadow_opaque_visibility(sp), coverage);
	}
#endif
	return light + incident;
}

// This march's source is incident radiance multiplied by the SAME extinction
// sigma used by the segment. Cancel sigma analytically for the ordinary branch;
// preserve volume_integral.glsl's cancellation-free small-optical-depth series.
vec4 astra_volume_incident_segment(vec3 incident, float extinction, float distanceBlocks) {
    float tau = max(extinction, 0.0) * max(distanceBlocks, 0.0);
    float transmission = exp(-tau);
    float scatter = tau < 1e-3
        ? tau * (1.0 - tau * (0.5 - tau * (1.0 / 6.0)))
        : 1.0 - transmission;
    return vec4(incident * scatter, transmission);
}

// Integrate the camera ray out to distanceBlocks. Segments are composed near-first
// (astra_volume_compose contract); each segment is treated as homogeneous at its
// sample point. Beyond the bounded march the residual is one analytic segment at its
// midpoint's density, so far geometry converges into the haze instead of cutting off.
// shadowMap=false is the cheap mode (cloud shadow only) used by the prefix query.
vec4 astra_volume_march_from(vec3 origin, vec3 rayWorld, float distanceBlocks,
                            bool shadowMap, int steps) {
	vec4 volume = astra_volume_identity();
	if (distanceBlocks <= 0.0 || VOLUME_FOG_DENSITY == 0) return volume;
	float marchLength = min(distanceBlocks, ASTRA_VOLUME_MAX_DISTANCE);
	vec3 lightDirWorld = astra_world_light_direction();
	// Ray direction and frame lighting are identical for every segment. Keep
	// palette and phase work outside the integration loop; weather density is CPU-side.
	vec3 direct = astra_direct_light() * astra_volume_phase(dot(rayWorld,lightDirWorld));
	vec3 incident = astra_volume_incident();
	float density = astraVolumeDensity;
    // Parallel shadow-space ray: transform the affine origin/direction once.
    // Preserve project_and_divide's homogeneous point contract; divide and
    // nonlinear distortion remain per sample, including adaptive sample positions.
    vec4 shadowOrigin = vec4(0.0);
    vec4 shadowRay = vec4(0.0);
    bool traceShadows = false;
    #ifdef SHADOWS
    traceShadows = shadowMap && any(greaterThan(direct, vec3(0.0)));
    if (traceShadows) {
        vec3 lightOrigin = (shadowModelView * vec4(origin, 1.0)).xyz;
        vec3 lightRay = mat3(shadowModelView) * rayWorld;
        shadowOrigin = shadowProjection * vec4(lightOrigin, 1.0);
        shadowRay = shadowProjection * vec4(lightRay, 0.0);
    }
    #endif
    int sampleCount = steps;
    #ifdef VOLUME_FOG_ADAPTIVE
    sampleCount = min(steps, max(4, int(ceil(float(steps) * marchLength / ASTRA_VOLUME_MAX_DISTANCE))));
    #endif
	float jitter = bayer8(gl_FragCoord.xy);
    float inverseSampleCount = 1.0 / float(sampleCount);
	for (int i = 0; i < sampleCount; ++i) {
        if (volume.a < 0.002) break;
        float left = float(i) * inverseSampleCount;
        float right = i + 1 == sampleCount ? 1.0 : float(i + 1) * inverseSampleCount;
        #ifdef VOLUME_FOG_ADAPTIVE
        // Quadratic boundaries favour near-camera detail. Each actual segment
        // length enters extinction and scattering, retaining the full ray length.
        left *= left;
        right *= right;
        #endif
        float stepLength = (right - left) * marchLength;
		float t = mix(left, right, jitter) * marchLength;
		vec3 p = origin + rayWorld * t;
		float sigma = astra_volume_extinction(cameraPosition.y + p.y,density);
		vec4 shadowClip = vec4(0.0);
        #ifdef SHADOWS
        if (traceShadows) shadowClip = shadowOrigin + shadowRay * t;
        #endif
		vec3 source = astra_volume_light(p, lightDirWorld, direct, incident,
                                       shadowClip, traceShadows);
		volume = astra_volume_compose(volume, astra_volume_incident_segment(source, sigma, stepLength));
	}
    if (distanceBlocks > marchLength) {
        float residualLength = distanceBlocks - marchLength;
        // Represent the whole residual instead of extending its starting
        // height indefinitely along upward or downward rays.
        vec3 p = origin + rayWorld * (marchLength + 0.5 * residualLength);
        float sigma = astra_volume_extinction(cameraPosition.y + p.y,density);
        vec3 source = astra_volume_light(p, lightDirWorld, direct, incident,
                                       vec4(0.0), false);
        volume = astra_volume_compose(volume,
            astra_volume_incident_segment(source, sigma, residualLength));
    }
	return volume;
}

vec4 astra_volume_march(vec3 rayWorld, float distanceBlocks, bool shadowMap, int steps) {
    return astra_volume_march_from(vec3(0.0), rayWorld, distanceBlocks, shadowMap, steps);
}

// A reflected air leg starts at the interface, rather than at the camera.
// Density and cloud-shadow queries must retain that world-space origin.
vec4 astra_volume_path_medium(vec3 start, vec3 finish) {
    vec3 delta = finish - start;
    float distanceBlocks = length(delta);
    return astra_volume_march_from(start, delta / max(distanceBlocks, 1e-5),
                                  distanceBlocks, false, ASTRA_VOLUME_PREFIX_STEPS);
}

// Explicit interface for paths that need the prefix medium up to a point that is NOT
// the buffered endpoint (water interfaces, translucent interiors, transported
// samples). It re-integrates the shared density model instead of guessing from the
// background's total transmittance; the cheap mode trades the shadow map for cloud
// shadow only, which the handoff documents as the first-version approximation.
vec4 astra_volume_prefix_medium(vec3 playerPos, float distanceBlocks) {
	return astra_volume_march(playerPos / max(distanceBlocks, 1e-5), distanceBlocks,
	                          false, ASTRA_VOLUME_PREFIX_STEPS);
}
vec4 astra_volume_prefix_medium(vec3 playerPos) {
    return astra_volume_prefix_medium(playerPos, length(playerPos));
}

// Compose the render-distance fade as an additional far medium, preserving
// scattering as well as extinction. Scaling T alone fades terrain to black.
vec4 astra_volume_border(vec4 volume, float distanceBlocks) {
    #ifdef BORDER_FOG
    float opacity = smoothstep(borderFogDistance - 8.0, borderFogDistance, distanceBlocks);
    if (opacity <= 0.0) return volume;
    float scatteredFraction = 1.0 - volume.a;
    vec3 target = scatteredFraction > 0.00001
        ? volume.rgb / scatteredFraction : astra_volume_incident();
    volume.rgb += volume.a * opacity * target;
    volume.a *= 1.0 - opacity;
    #endif
    return volume;
}

// Edge-aware upsample of the reduced-resolution S/T buffer to a full-resolution pixel.
// A tap is dropped when its own geometry (depthtex0 at the tap centre) does not
// belong to this pixel's surface, so silhouettes do not inherit a march that ended
// on background terrain; sky taps carry no medium and never dilute geometry. If no
// tap survives, the pixel falls back to the analytic prefix march. The caller owns
// the border-fog fold and the final astra_volume_apply.
vec4 astra_volume_resolve(sampler2D volumeBuffer, sampler2D surfaceData,
                         vec2 uv, float referenceZ, vec3 playerPos) {
	// At zero density the producer's whole field is the identity. Border fog
	// is still composed by the caller, without reading four unused footprints.
	if (VOLUME_FOG_DENSITY == 0) return astra_volume_identity();
	vec2 bufferSize = vec2(textureSize(volumeBuffer, 0));
	vec2 center = uv * bufferSize - 0.5;
	vec2 base = floor(center);
	vec2 f = center - base;
	vec4 sum = vec4(0.0);
	float weights = 0.0;
	ivec2 surfaceSize = textureSize(surfaceData, 0);
	ivec2 depthSize = textureSize(depthtex0, 0);
	for (int y = 0; y < 2; ++y) {
		for (int x = 0; x < 2; ++x) {
			vec2 offset = vec2(float(x), float(y));
			vec2 tap = clamp(base + offset, vec2(0.0), bufferSize - 1.0);
			vec2 tapUV = (tap + 0.5) / bufferSize;
			vec2 bilinear = mix(vec2(1.0) - f, f, offset);
			float weight = bilinear.x * bilinear.y;
			if (weight <= 0.0) continue;
			ivec2 depthPixel = clamp(ivec2(tapUV * vec2(depthSize)), ivec2(0), depthSize - 1);
			float tapDepth = texelFetch(depthtex0, depthPixel, 0).r;
			if (tapDepth >= 0.999999 || referenceZ <= 0.0) continue;
			// A depth mismatch cannot contribute even if its material is eligible.
			// Reject it before fetching the separate hand/material record.
			// Match volume_main's point-fetched depth and its exact receiver ray.
			vec2 receiverUV = (vec2(depthPixel) + 0.5) / vec2(depthSize);
			float tapZ = -screen_view(vec3(receiverUV, tapDepth)).z;
			float band = 1.0 - smoothstep(0.02, 0.06,
				abs(tapZ - referenceZ) / max(referenceZ, 1e-3));
			weight *= band;
			if (weight <= 0.0) continue;
			ivec2 surfacePixel = clamp(ivec2(receiverUV * vec2(surfaceSize)),
			                           ivec2(0), surfaceSize - 1);
			uint flags = uint(round(texelFetch(surfaceData, surfacePixel, 0).r * 255.0));
			if ((flags & 128u) != 0u) continue;
			sum += texelFetch(volumeBuffer, ivec2(tap), 0) * weight;
			weights += weight;
		}
	}
	if (weights < 1e-4) return astra_volume_prefix_medium(playerPos);
	return sum / weights;
}

#endif // VOLUMETRIC_FOG

#endif
