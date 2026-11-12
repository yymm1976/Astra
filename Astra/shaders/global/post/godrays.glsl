#ifndef ASTRA_GLOBAL_POST_GODRAYS_GLSL
#define ASTRA_GLOBAL_POST_GODRAYS_GLSL

// Astra v1 — global/post/godrays.glsl
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot
//   source: _analysis/Steadfast-0.8.0/shaders/program/post/noisy_godrays.fsh
// This file is a derivative of Steadfast and is licensed under the GNU General Public
// License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
// _analysis/Steadfast-0.8.0/LICENSE.md, including Steadfast's Section 7 additional terms.
// Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Astra changes:
//   - the pass body stays in program/composite.fsh; this module holds only the
//     algorithm, so the second stage (final-pass smoothing + upsample, E1/C6's side)
//     and this one can be reviewed and tuned independently.
//   - the Bayer8 start jitter comes from Astra's own lib/bayer.glsl (public-domain
//     recursive matrix, escalations.md SC-7) instead of Steadfast's bayer8.glsl.
//   - depthtex0 is declared in lib/uniforms.glsl, not here.
//
// Uniforms: depthtex0, godraysExposure (lib/uniforms.glsl)
// Consts:   none
// Owner: B4. Consumer: program/composite.fsh.

#include "/lib/bayer.glsl"

// The sky has no geometry, so it keeps the far-plane depth. This is one of the few
// places where an == comparison on a depth buffer is reliable.
const float SKY_DEPTH = 1.0;

#ifdef ASTRA_TREE_SHAFTS
#ifdef ASTRA_TREE_SHAFT_MARCH_PASS
// Original Astra bounded single-scattering path. Unlike the screen-radial
// fallback below, its occluders come from the world shadow map, so foliage can
// split a shaft while the solar disc is outside the viewport. Ordinary fog
// continues to own ambient haze; this path adds only the direct sunlight term.
vec2 astra_tree_shafts(vec2 uv) {
    ivec2 size = textureSize(depthtex0,0);
    ivec2 pixel = clamp(ivec2(uv*vec2(size)),ivec2(0),size-1);
    float depth = texelFetch(depthtex0,pixel,0).r;
    vec2 pointUV = (vec2(pixel)+0.5)/vec2(size);
    vec3 viewPoint = screen_view(vec3(pointUV,depth));
    float receiverZ = depth >= 0.999999 ? 65504.0 : max(-viewPoint.z,0.0);
    vec3 viewOrigin = projection_view_origin();
    vec3 delta = viewPoint-viewOrigin;
    float distanceBlocks = length(delta);
    float reach = min(distanceBlocks,48.0);
    if (reach <= 0.5) return vec2(0.0,receiverZ);
    vec3 ray = view_player(delta)/max(distanceBlocks,0.00001);
    vec3 origin = view_camera_relative(viewOrigin);
    vec3 light = astra_world_light_direction();
    float mu = clamp(dot(ray,light),-1.0,1.0);
    // HG forward scattering, g=0.55. The phase is evaluated once per ray.
    float phaseBase = 1.3025-1.10*mu;
    float phase = 0.6975/(12.5663706*phaseBase*sqrt(phaseBase));
    vec4 shadowOrigin = shadowProjection*(shadowModelView*vec4(origin,1.0));
    vec4 shadowRay = shadowProjection*vec4(mat3(shadowModelView)*ray,0.0);
    #ifdef ASTRA_OVERWORLD_OPTIMIZED
    const int samples = 8;
    #else
    const int samples = 12;
    #endif
    float jitter = bayer8(gl_FragCoord.xy);
    float transmission = 1.0;
    float integral = 0.0;
    for (int i=0;i<samples;++i) {
        float left = float(i)/float(samples);
        float right = float(i+1)/float(samples);
        left *= left;
        right *= right;
        float t = mix(left,right,jitter)*reach;
        vec3 point = origin+ray*t;
        vec4 clip = shadowOrigin+shadowRay*t;
        vec3 sp = distort(clip.xyz/clip.w)*0.5+0.5;
        sp.z -= 0.00002;
        float coverage = shadow_map_fade(point)*shadow_uv_coverage(sp);
        float visible = coverage > 0.0 ? shadow_opaque_visibility(sp)*coverage : 0.0;
        float nextTransmission = exp(-0.006*right*reach);
        integral += visible*(transmission-nextTransmission);
        transmission = nextTransmission;
    }
    // One cloud query per ray. The short near-field shaft shares cloud cover,
    // while foliage/terrain visibility is still evaluated at every sample.
    integral *= astra_cloud_transmission(cameraPosition+origin+ray*(0.5*reach),light);
    return vec2(integral*phase,receiverZ);
}
#else
float astra_tree_shafts_resolve(sampler2D source,vec2 uv) {
    float depth = textureLod(depthtex0,uv,0.0).r;
    float receiverZ = 65504.0;
    if (depth < 0.999999) {
        vec3 ndc = vec3((uv-astra_jitter_uv())*2.0-1.0,depth*2.0-1.0);
        float z = gbufferProjectionInverse[0].z*ndc.x+gbufferProjectionInverse[1].z*ndc.y
                + gbufferProjectionInverse[2].z*ndc.z+gbufferProjectionInverse[3].z;
        float w = gbufferProjectionInverse[0].w*ndc.x+gbufferProjectionInverse[1].w*ndc.y
                + gbufferProjectionInverse[2].w*ndc.z+gbufferProjectionInverse[3].w;
        receiverZ = max(-z/w,0.0);
    }
    ivec2 size = textureSize(source,0);
    vec2 location = uv*vec2(size)-0.5;
    ivec2 base = ivec2(floor(location));
    vec2 f = fract(location);
    float total = 0.0, weights = 0.0;
    for (int i=0;i<4;++i) {
        ivec2 offset = ivec2(i&1,i>>1);
        vec2 bilinear = mix(1.0-f,f,vec2(offset));
        vec2 tap = texelFetch(source,clamp(base+offset,ivec2(0),size-1),0).rg;
        float tolerance = max(0.25,receiverZ*0.02);
        bool sameSky = (receiverZ >= 65504.0) == (tap.g >= 65504.0);
        float weight = bilinear.x*bilinear.y
            *float(sameSky)*clamp(1.0-abs(tap.g-receiverZ)/tolerance,0.0,1.0);
        total += tap.r*weight;
        weights += weight;
    }
    // No cross-silhouette borrowing and no full-resolution fallback march.
    return weights > 0.00001 ? total/weights : 0.0;
}
#endif
#endif

// Depth comparison done by hand: Iris gives us depthtex0 as a plain sampler, so we
// reproduce GL_LEQUAL against the stored depth instead of using a shadow sampler.
// Bounds and ray exits diverge across pixels; explicit level zero avoids implicit
// texture derivatives in those branches and keeps the native depth footprint.
float depth_compare_sample(vec3 texCoord) {
	if (any(lessThan(texCoord.xy, vec2(0.0))) || any(greaterThan(texCoord.xy, vec2(1.0)))) {
		return 0.0;
	}
	return float(texCoord.z <= textureLod(depthtex0, texCoord.xy, 0.0).r);
}

// Screen-space light shafts after GPU Gems 3, "Volumetric Light Scattering as a
// Post-Process":
//   https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows
//
// Two departures from the chapter, both Steadfast's:
//   1. march the DEPTH buffer instead of the colour buffer, so occlusion is decided
//      by geometry rather than by how bright the occluder happens to be;
//   2. jitter the start position with ordered dithering, which turns the banding of a
//      low sample count into noise - 8 samples with a Bayer8 offset looks like far
//      more, and the noise is removed by the second (final-pass) smoothing stage.
//
// screenCoord is normalised coordinates of the HALF-RESOLUTION godrays buffer;
// lightScreenPos is the shadow light's position in the same space (0..1, may be
// off-screen - the CPU-side offscreen fade in godraysExposure handles that).
// scattering.fsh owns the air-volume exclusion. Retain the guard below for
// independent callers: it must never duplicate volume-owned air scattering.
float godrays_density(vec2 screenCoord, vec2 lightScreenPos) {
	#ifdef ASTRA_VOLUME_FOG
	// R2/H3: with the optional overworld volume on, the ray march owns this air
	// segment's solar in-scatter (per-step shadow map, cloud shadow and phase lobe).
	// Keeping the screen-space beam would scatter the same air twice (handoff R2
	// section 4.3), so the legacy path yields nothing while the volume option is on.
	// godraysExposure / GODRAYS_STRENGTH stay display-side and need no change; the
	// underwater arm of composite2 is a different medium and keeps working.
	return 0.0;
	#else
	const float NUM_SAMPLES = 8.0;
	const float DENSITY = 0.83;
	const float DECAY = pow(0.5, 1.0 / NUM_SAMPLES);

	vec2 texCoord = screenCoord;

	// Step from this pixel towards the light, scaled by the density control factor.
	vec2 deltaTexCoord = texCoord - lightScreenPos;
	deltaTexCoord *= 1.0 / NUM_SAMPLES * DENSITY;

	texCoord += deltaTexCoord * 1.5 * bayer8(gl_FragCoord.xy);

	float accumulated = 0.0;
	float illuminationDecay = 1.0;

	for (uint i = uint(0); i < uint(NUM_SAMPLES); i++) {
		texCoord -= deltaTexCoord;
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        // After the first jittered sample the ray moves monotonically from its
        // on-screen origin towards the light. Once it leaves the convex screen
        // rectangle it cannot re-enter; every remaining depth comparison is zero.
        // Sample zero may start just outside and then enter, so retain that case.
        bool outside = any(lessThan(texCoord, vec2(0.0)))
                    || any(greaterThan(texCoord, vec2(1.0)));
        if (outside && i > uint(0)) break;
        float depthSample = outside ? 0.0
            : float(SKY_DEPTH <= textureLod(depthtex0, texCoord, 0.0).r);
        #else
		float depthSample = depth_compare_sample(vec3(texCoord, SKY_DEPTH));
        #endif
		depthSample *= illuminationDecay;
		accumulated += depthSample;
		illuminationDecay *= DECAY;
	}

	return accumulated / NUM_SAMPLES;
	#endif
}

#endif
