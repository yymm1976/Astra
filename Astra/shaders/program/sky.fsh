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
		// Astra owns the star field in skybasic, so the vanilla star draw is always suppressed.
		if (renderStage == MC_RENDER_STAGE_STARS) discard;

		#if SUN_MOON_MODE == SUN_MOON_VANILLA
			vec4 celestial = texture(gtexture, texcoord) * tint;
			celestial.rgb = srgb_decode(max(celestial.rgb, vec3(0.0)));
            float throughCloud = astra_cloud_transmission(cameraPosition, normalize(worldSunVector));
            celestial.a *= mix(1.0, throughCloud * 0.25, astraRainFactor);
            gl_FragData[0] = celestial;
		#else
			vec3 worldDir = astra_sky_world_direction();
			if (renderStage == MC_RENDER_STAGE_SUN) {
				gl_FragData[0] = astra_procedural_disc(
					worldDir, worldSunVector, 0.00873,
					vec3(7.5, 4.8, 2.3) * mix(0.55, 1.0, sunProgress));
			} else if (renderStage == MC_RENDER_STAGE_MOON) {
				gl_FragData[0] = astra_procedural_moon(
					worldDir, -worldSunVector, 0.0096,
					vec3(0.72, 0.88, 1.25) * (0.55 + 0.45 * moonProgress));
			} else {
				discard;
			}
        #endif
        #if SUN_MOON_MODE != SUN_MOON_VANILLA
        gl_FragData[0].a *= mix(1.0, astra_cloud_transmission(cameraPosition, normalize(worldSunVector)) * 0.25, astraRainFactor);
        #endif
    #endif
#else
	#ifdef DIMENSION_END
		// End's full-screen sky is drawn once, in deferred after terrain depth exists.
		gl_FragData[0]=vec4(0.0,0.0,0.0,1.0);
		return;
	#endif
	// gbuffers_skybasic also receives vanilla star geometry. Drawing an opaque atmosphere on
	// those triangles would cover the sky; our cell field is already part of the SKY draw.
	if (renderStage == MC_RENDER_STAGE_STARS) discard;
	vec3 worldDir = astra_sky_world_direction();
	gl_FragData[0] = vec4(astra_sky(worldDir), 1.0);
#endif
}
