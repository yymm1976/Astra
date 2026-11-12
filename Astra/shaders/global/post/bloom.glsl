#ifndef ASTRA_GLOBAL_POST_BLOOM_GLSL
#define ASTRA_GLOBAL_POST_BLOOM_GLSL

// Original Astra HDR bloom. General threshold/mip-pyramid ideas from Refrax,
// MakeUp and Mellow: IDEA ONLY; no upstream filtering expression retained.
// The former Refrax-derived quadratic knee and dual-filter stencil were replaced
// on 2026-10-05 with the integrated activation and moment-matched disk below.
// Thresholds, capture scale, mip weights and water gain stay local.
// No upstream code was imported for this replacement; see THIRD-PARTY.md.

// --- prefilter tuning (HDR, pre-tonemap; colortex0 is R11F_G11F_B10F) ---
// Anything at or below white contributes nothing, which is what keeps bloom off the
// midtones and stops it from turning into a grey haze over the whole frame.
#if defined DIMENSION_END && defined ASTRA_BLOOM_CAPTURE && END_STONE_GLOW > 0
uniform sampler2D colortex3;
#endif
const float BLOOM_THRESHOLD = 1.0;
// Soft knee width, in the same units. Without it, pixels crossing the threshold pop
// in and out as the sun or a light source moves, which is very visible without TAA.
const float BLOOM_KNEE = 0.5;
// Ceiling on the emitted scalar excess, before preserving the source hue.
const float BLOOM_SOURCE_CLAMP = 16.0;

// Must match size.buffer.colortex2 in shaders.properties. Source-space offsets
// widen with the reduction ratio, preserving the existing screen-space radius.
const float BLOOM_CAPTURE_SCALE = 0.25;

// Twelve equally weighted points at radius 2, starting at 15 degrees, plus a
// centre of weight 1/4. Sum=1; per-axis second moment=(12/16)*4/2=1.5,
// matching the existing glow radius without retaining the copied square stencil.
const vec2 BLOOM_DISK[12] = vec2[12](
    vec2( 1.93185165, 0.51763809), vec2( 1.41421356, 1.41421356),
    vec2( 0.51763809, 1.93185165), vec2(-0.51763809, 1.93185165),
    vec2(-1.41421356, 1.41421356), vec2(-1.93185165, 0.51763809),
    vec2(-1.93185165,-0.51763809), vec2(-1.41421356,-1.41421356),
    vec2(-0.51763809,-1.93185165), vec2( 0.51763809,-1.93185165),
    vec2( 1.41421356,-1.41421356), vec2( 1.93185165,-0.51763809));

// Integrate a monotone activation 0.75*s + 0.25*smoothstep(0,1,s).
// Its primitive is .375*s^2+.25*s^3-.125*s^4. At s=0 value/slope=0;
// at s=1 value=.5 and slope=1, joining the full linear excess without a kink.
// This independent curve differs slightly inside the transition, never below
// the threshold or above its endpoint. All brightness controls are unchanged.
vec3 bloom_prefilter(vec3 color) {
    float peak=max(color.r,max(color.g,color.b));
    float above=peak-BLOOM_THRESHOLD;
    if (!(above>0.0)) return vec3(0.0);
    float width=2.0*BLOOM_KNEE;
    float excess;
    if (above<width) {
        float s=above/width;
        excess=width*s*s*(0.375+s*(0.25-0.125*s));
    } else {
        excess=above-BLOOM_KNEE;
    }
    return color*(min(excess,BLOOM_SOURCE_CLAMP)/peak);
}

// Stage 1 (program/composite1.fsh): prefiltered downsample of the HDR scene into the
// bloom capture buffer. One pass, 4/5/13 source texture fetches, no colour output
// dependency - the buffer Iris produces here is what gets mipmapped.
//
// src is colortex0 at render resolution; texCoord is the capture pass's own normalised
// coordinate, which is also valid for sampling the full-res source.
vec3 bloom_capture(sampler2D src, vec2 texCoord, bool sceneCapture) {
	// Derived from the source rather than from viewWidth/viewHeight: the capture rate
	// has to track whatever size colortex0 actually is, and Iris resizes it with the
	// render scale.
	vec2 srcTexel = 1.0 / vec2(textureSize(src, 0));

	// Keep the established footprint in source-texel coordinates at every view size.
	float footprint = float(textureSize(src, 0).x)
	                / max(float(viewWidth) * BLOOM_CAPTURE_SCALE, 1.0);
	float tapScale = max(footprint * 0.5, 1.0);

	vec2 pad = 0.5 * srcTexel * tapScale;

	vec3 acc = vec3(0.0);
    // Both overworld budget tiers use the four-tap capture below; every other
    // case keeps its BLOOM_QUALITY stencil. Raw BLOOM_QUALITY 0 keeps its own
    // tighter four-corner stencil; the budget never widens that choice.
    #if defined ASTRA_OVERWORLD_OPTIMIZED || BLOOM_QUALITY == 0
    const int taps = 4;
    #elif BLOOM_QUALITY == 2
    const int taps = 13;
    #else
    const int taps = 5;
    #endif
	for (int i = 0; i < taps; i++) {
        vec2 offset;
        float weight;
        #if defined ASTRA_OVERWORLD_OPTIMIZED && BLOOM_QUALITY > 0
        // Budget-tier four-corner stencil: the same four reads and 0.25 weights as
        // the raw BLOOM_QUALITY 0 stencil, but each axis offset is sqrt(1.5) so the
        // per-axis second moment is 1.5 - the same 1.5 the balanced (5-tap, sqrt(6)
        // arms) and high (13-tap disk) tiers carry - so the budget does not change
        // the capture's per-axis footprint. Center of mass and weights are unchanged,
        // and the caller's tapScale and prefilter are untouched. Not a claim about
        // the on-screen radius: this only keeps the stencil's second moment in line
        // with the other tiers.
        offset = vec2((i & 1) == 0 ? -1.0 : 1.0,
                      (i & 2) == 0 ? -1.0 : 1.0) * 1.224744871;
        weight = 0.25;
        #elif defined ASTRA_OVERWORLD_OPTIMIZED || BLOOM_QUALITY == 0
        // Raw BLOOM_QUALITY 0 keeps its original tighter four-corner stencil at
        // offset 0.5; the optimized tier also lands here when the raw option is 0
        // (BLOOM_QUALITY > 0 is false), so the user's lighter/narrower choice is
        // never widened.
        offset = vec2((i & 1) == 0 ? -1.0 : 1.0,
                      (i & 2) == 0 ? -1.0 : 1.0) * 0.5;
        weight = 0.25;
        #elif BLOOM_QUALITY == 2
        offset = i == 0 ? vec2(0.0) : BLOOM_DISK[i-1];
        weight = i == 0 ? 0.25 : 0.0625;
        #else
        // Centre plus an axial cross. Sum=1 and per-axis second moment is
        // 2*(1/8)*sqrt(6)^2=1.5, matching the old nine-tap radius with fewer
        // reads. Diagonal isolated sparks may contribute less before mip blur.
        offset = i == 0 ? vec2(0.0) : (i == 1 ? vec2(-1.0,0.0)
               : (i == 2 ? vec2(1.0,0.0) : (i == 3 ? vec2(0.0,-1.0) : vec2(0.0,1.0)))) * 2.44948974;
        weight = i == 0 ? 0.5 : 0.125;
        #endif
		vec2 coord = clamp(texCoord + offset * srcTexel * tapScale,
		                   pad, 1.0 - pad);
        #ifdef ASTRA_CELESTIAL_BLOOM
        // Filter the VISIBLE sky after opaque/translucent occlusion. An unseen
        // disc emits nothing; its surviving half can spill across a foreground
        // silhouette later. Pair the point colour with this very depth texel.
        ivec2 sourceSize = textureSize(src,0);
        ivec2 pixel = clamp(ivec2(coord*vec2(sourceSize)),ivec2(0),sourceSize-1);
        if (texelFetch(depthtex0,pixel,0).r < 0.999999) continue;
        vec3 source = max(texelFetch(src,pixel,0).rgb,vec3(0.0));
        #else
        vec3 source = max(textureLod(src,coord,0.0).rgb,vec3(0.0));
        #endif
        if (!sceneCapture) source = bloom_prefilter(source);
        #ifdef ASTRA_CELESTIAL_BLOOM
        float sourcePeak = max(source.r,max(source.g,source.b));
        source *= min(1.0,3.0/max(sourcePeak,0.000001));
        #endif
        #if defined DIMENSION_END && defined ASTRA_BLOOM_CAPTURE && END_STONE_GLOW > 0
        // With pore emission disabled, colortex3.a is identically zero.
        // Ordinary scene/sky bloom above remains independent of this option.
        // Reject sky and opaque surfaces covered by translucent geometry. The mask
        // is written only by identity-gated End-stone terrain, never pale sand.
        float depth = textureLod(depthtex0,coord,0.0).r;
        if (depth < 0.999999) {
            float emission = textureLod(colortex3,coord,0.0).a;
            if (emission > 0.0) {
                float opaqueDepth = textureLod(depthtex1,coord,0.0).r;
                if (abs(depth-opaqueDepth) < 1e-7)
                    source += vec3(0.16/0.19,1.0,0.08/0.19)*emission;
            }
        }
        #endif
        acc += source * weight;
	}

	return acc;
}

vec3 bloom_capture(sampler2D src, vec2 texCoord) {
    #ifdef ASTRA_WATER_SCENE_BLOOM
    return bloom_capture(src, texCoord, true);
    #else
    return bloom_capture(src, texCoord, false);
    #endif
}

#ifdef CELESTIAL_BLOOM
// Two existing pyramid levels form a narrow optical halo. Added in display
// linear light so sky and foreground share the SAME glow at an occlusion edge,
// even though the End photosphere has its own surface/sky tone curves.
vec3 celestial_bloom(sampler2D bloomTex,vec2 uv) {
    vec3 light = textureLod(bloomTex,uv,0.0).rgb*0.75
               + textureLod(bloomTex,uv,1.0).rgb*0.25;
    return max(light,vec3(0.0))*0.16;
}
#endif

// Stage 2 (program/display.fsh, E1/C6): combine the mip levels of the capture into the
// bloom that gets added to the scene.
//
// Weights fall off with level on purpose - most of the energy stays in the tighter
// levels, so the result reads as light spilling out of bright pixels rather than a
// uniform veil. Only emitted excess is added; non-emitting midtones stay untouched.
//
//   color += bloom_composite(colortex2, texcoord, BLOOM_STRENGTH * 0.01);
vec3 bloom_composite(sampler2D bloomTex, vec2 texCoord, float strength) {
	#ifdef DIMENSION_END
		// A hot photosphere needs a small optical shoulder beyond its white core.
		// Keep most energy local so the native-resolution photon ring stays legible.
		vec3 bloom=textureLod(bloomTex,texCoord,0.0).rgb*0.50
		          +textureLod(bloomTex,texCoord,1.0).rgb*0.25
		          +textureLod(bloomTex,texCoord,2.0).rgb*0.15
		          +textureLod(bloomTex,texCoord,3.0).rgb*0.10;
		return max(bloom,vec3(0))*strength*0.35;
	#else
	// Mip levels compensate for the capture resolution, so these are not arbitrary.
	// A level's texel covers (screen/bloomWidth) * 2^level pixels, so at the 0.5x capture
	// levels 1..4 spanned 4, 8, 16 and 32 pixels. The capture is now 0.25x, which doubles
	// every level's footprint, so the reads shift down one level and land on exactly the
	// same 4, 8, 16, 32 pixel footprints - the weighted mean stays 10.4 px and the bloom
	// radius is unchanged. Reading 1..4 here would silently widen the whole glow to a veil.
	// The one residual difference is that level 0 is the capture itself rather than a mip
	// of it, so the tightest term is marginally crisper; confirm in game.
	vec3 bloom = textureLod(bloomTex, texCoord, 0.0).rgb * 0.40
	           + textureLod(bloomTex, texCoord, 1.0).rgb * 0.30
	           + textureLod(bloomTex, texCoord, 2.0).rgb * 0.20
	           + textureLod(bloomTex, texCoord, 3.0).rgb * 0.10;

	return max(bloom, vec3(0.0)) * strength;
	#endif
}

#endif
