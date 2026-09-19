// Astra v1 - vanilla cloud passthrough or planar wispy shading on the original cloud geometry.
// Uniforms: gtexture, viewWidth, viewHeight and scene/cloud module dependencies.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/transforms.glsl"
#include "/program/scene.glsl"
#include "/global/atmosphere/clouds_planar.glsl"

in vec2 texcoord;
in vec4 tint;

/* RENDERTARGETS: 0 */

vec3 astra_cloud_world_direction() {
	vec2 screenUv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
	vec3 viewDir = screen_view(vec3(screenUv, 1.0));
	return normalize(mat3(gbufferModelViewInverse) * viewDir);
}

void main() {
#if defined(DIMENSION_NETHER) || defined(DIMENSION_END) || CLOUD_MODE == CLOUD_OFF
	discard;
#elif CLOUD_MODE == CLOUD_PLANAR
	// The full-screen sky path owns planar clouds, including cells where vanilla emitted no
	// cloud geometry. Suppress this geometry pass to avoid drawing the sheet twice.
	discard;
#else
	vec4 cloud = texture(gtexture, texcoord) * tint;
	cloud.rgb = srgb_decode(max(cloud.rgb, vec3(0.0)));
	cloud.rgb *= mix(vec3(0.72), vec3(1.0), skyVisibilityDay);
    vec3 direction=astra_cloud_world_direction();
    vec3 morningCloud=astra_twilight_atmosphere(cloud.rgb,direction);
    cloud.rgb=mix(cloud.rgb,morningCloud*mix(0.60,0.92,tint.r),astra_twilight_strength());
	cloud.rgb = mix(cloud.rgb, vec3(dot(cloud.rgb, vec3(0.25, 0.65, 0.10))) * 0.72,
	                rainStrength * 0.65);
	#ifdef FANCY_TRANSLUCENTS
		cloud.rgb *= cloud.a;
	#endif
	gl_FragData[0] = cloud;
#endif
}
