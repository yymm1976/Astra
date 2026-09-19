// Astra v1 - visible sky and celestial texture pass.
// Uniforms: gtexture, renderStage, viewWidth, viewHeight and scene.glsl dependencies.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/transforms.glsl"
#include "/program/scene.glsl"

#ifdef ASTRA_SKY_TEXTURED
in vec2 texcoord;
in vec4 tint;
#endif

/* RENDERTARGETS: 0 */

vec3 astra_sky_world_direction() {
	vec2 screenUv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
	vec3 viewDir = screen_view(vec3(screenUv, 1.0));
	return normalize(mat3(gbufferModelViewInverse) * viewDir);
}

// Moon with its phase applied. Vanilla's moon_phases texture carries the phase for the
// textured path, but the procedural disc drew a full moon every night, so the phase never
// showed. Iris reports moonPhase as 0..7 with 0 full and 4 new, the same order as the
// vanilla texture strip.
vec4 astra_procedural_moon(vec3 worldDir, vec3 centre, float angularRadius, vec3 color) {
	vec3 c = normalize(centre);
	float cosineRadius = cos(angularRadius);
	float cosineAngle = dot(worldDir, c);
	float edge = max(fwidth(cosineAngle), 2.0e-6);
	float disc = smoothstep(cosineRadius - edge, cosineRadius + edge, cosineAngle);
	if (disc <= 0.0) return vec4(0.0);

	// Horizontal offset inside the disc, in disc radii (-1..1). Across half a degree the
	// terminator's curvature is not resolvable, so a straight edge is used rather than
	// projecting an ellipse.
	vec3 up = normalize(cross(c, vec3(0.0, 0.0, 1.0)));
	vec3 right = cross(c, up);
	float x = dot(worldDir, right) / max(sin(angularRadius), 1e-6);

	float lit = 0.5 + 0.5 * cos(6.2831853 * moonPhase / 8.0);   // 1 full, 0 new
	float side = moonPhase < 4.0 ? 1.0 : -1.0;                    // waxing vs waning limb
	float phaseMask = step(1.0 - 2.0 * lit, x * side);
	// A new moon keeps a faint earthshine disc so the sky is never missing its object.
	float shown = mix(0.045, 1.0, phaseMask);

	float alpha = disc * shown;
	return vec4(color * alpha, alpha);
}

vec4 astra_procedural_disc(vec3 worldDir, vec3 centre, float angularRadius, vec3 color) {
	float cosineRadius = cos(angularRadius);
	float cosineAngle = dot(worldDir, normalize(centre));
	float edge = max(fwidth(cosineAngle), 2.0e-6);
	float alpha = smoothstep(cosineRadius - edge, cosineRadius + edge, cosineAngle);
	return vec4(color * alpha, alpha);
}

void main() {
#ifdef ASTRA_SKY_TEXTURED
	#if defined(DIMENSION_NETHER) || defined(DIMENSION_END)
		discard;
	#else
		// Astra owns the star field, so the vanilla star draw is always suppressed.
		if (renderStage == MC_RENDER_STAGE_STARS) discard;

		#if SUN_MOON_MODE == SUN_MOON_VANILLA
			vec4 celestial = texture(gtexture, texcoord) * tint;
            if (celestial.a <= 0.001 || max(max(celestial.r,celestial.g),celestial.b) <= 0.001) discard;
			celestial.rgb = srgb_decode(max(celestial.rgb, vec3(0.0)));
            if (renderStage == MC_RENDER_STAGE_SUN)
                celestial.rgb *= mix(vec3(2.0,1.90,1.65),vec3(2.0,1.28,0.56),astra_twilight_strength());
            // The sun/moon sprite owns its own ceiling. The vanilla atlas sun is a
            // hard-edged square, and 2.0x on the linear white sprite put every channel
            // far past the tonemapper's knee, where the disc flattened to a white
            // rectangle with no readable limb. This is the SAME luminance shoulder the
            // sky uses (twilight.glsl): the square body stays square and stays at the
            // brightness the multiplier above asked for, while the sprite's edge
            // texels - which are dimmer - keep their relative values, so the outline
            // reads. No new pass and no new render target: one function call on four
            // pixels of sky per frame.
            celestial.rgb = astra_scene_highlights(celestial.rgb);
            vec3 celestialDirection=astra_sky_world_direction();
            float throughCloud = astra_cloud_transmission(cameraPosition,celestialDirection);
            celestial.a *= throughCloud * mix(1.0,0.25,astraRainFactor);
            gl_FragData[0] = celestial;
		#else
			vec3 worldDir = astra_sky_world_direction();
			if (renderStage == MC_RENDER_STAGE_SUN) {
                // Separate controls, which is what the task asks for: the DISC profile
                // lives here (peak, limb and colour), the near glow lives in the sky
                // gradient's glare lobe, and the wide diffusion lives in
                // global/post/bloom.glsl. Before this the disc was a flat multiply,
                // so "make the sun brighter" and "make the glow wider" were the same
                // edit and the only way to see the shape was to blow the frame out.
                //
                // (8.0, 7.0, 5.2) day / (6.2, 4.2, 1.8) twilight. The compression is
                // the shared single-factor shoulder (twilight.glsl), so the disc's
                // channel ratios survive and its brightness falls monotonically to the
                // ceiling as the multiplier rises. Peak after compression: 3.14 day,
                // 2.61 twilight - above the tonemapper's knee, which is what keeps a
                // sun-staring frame bright, but no longer 6.7x above it.
                vec3 disc = mix(vec3(8.0,7.0,5.2),vec3(6.2,4.2,1.8),astra_twilight_strength());
                gl_FragData[0] = astra_procedural_disc(
					worldDir, worldSunVector, 0.028,
                    astra_scene_highlights(disc));
			} else if (renderStage == MC_RENDER_STAGE_MOON) {
                // The moon keeps its phase mask (astra_procedural_moon) and its cooler
                // colour; only its ceiling moves with the disc's, for the same reason.
                vec3 disc = vec3(0.72, 0.88, 1.25) * (0.55 + 0.45 * moonProgress);
				gl_FragData[0] = astra_procedural_moon(
					worldDir, -worldSunVector, 0.0096,
                    astra_scene_highlights(disc));
			} else {
				discard;
			}
        #endif
        #if SUN_MOON_MODE != SUN_MOON_VANILLA
        if (gl_FragData[0].a<=0.0) discard;
        #if CLOUD_MODE == CLOUD_PLANAR
        // The celestial pass is after skybasic: attenuate the disc by the
        // same visible cloud sheet, also in clear weather.
        gl_FragData[0].a *= 1.0-astra_planar_cloud(astra_sky_world_direction()).a;
        #endif
        gl_FragData[0].a *= mix(1.0,0.22,astraRainFactor);
        #endif
    #endif
#else
	#ifdef DIMENSION_END
		// End's full-screen sky is drawn once, in deferred after terrain depth exists.
		gl_FragData[0]=vec4(0.0,0.0,0.0,1.0);
		return;
	#endif
	// gbuffers_skybasic also receives vanilla star geometry. It must not cover
	// celestial sprites; Astra supplies its own stars with the atmosphere.
	if (renderStage == MC_RENDER_STAGE_STARS) discard;
	// The nether joins the "black here, composed in deferred" path: its deferred pass
	// recomputes astra_sky for every sky pixel and overwrote this one, so this was a
	// full-screen double evaluation (consolidated review D6 / Qoder F-22). The End
	// returned black above for the same reason.
	#if defined DIMENSION_NETHER || (!defined DIMENSION_END && CLOUD_MODE != CLOUD_VANILLA)
		gl_FragData[0] = vec4(0.0,0.0,0.0,1.0);
	#else
	vec3 worldDir = astra_sky_world_direction();
	gl_FragData[0] = vec4(astra_sky(worldDir), 1.0);
	#endif
#endif
}
