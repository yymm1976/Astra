// Adapted from Solas V2.2b getBloom.glsl by Septonious; see THIRD-PARTY.md.
float pixelWidth = 1.0 / viewWidth;
float pixelHeight = 1.0 / viewHeight;

vec3 getBloomTile(float lod, vec2 bloomCoord, vec2 offset) {
	float scale = exp2(lod);

	float resScale = 1.25 * min(360.0, viewHeight) / viewHeight;
	vec3 bloom = texture2DLod(colortex7, (bloomCoord / scale + offset) * resScale, 0.0).rgb;

	return pow(bloom, vec3(8.0)) * 256.0;
}

void getBloom(inout vec3 color, vec2 coord, float z1) {
	float eBS = eyeBrightnessSmooth.y / 240.0;
	vec2 viewSize = vec2(1.0 / viewWidth, 1.0 / viewHeight);
	vec3 blur1 = getBloomTile(1.0 + 1.0, coord, vec2(0.0   , 0.0 ) + vec2( 0.5, 0.0) * viewSize);
	vec3 blur2 = getBloomTile(2.0 + 1.0, coord, vec2(0.50  , 0.0 ) + vec2( 4.5, 0.0) * viewSize);
	vec3 blur3 = getBloomTile(3.0 + 1.0, coord, vec2(0.50  , 0.25) + vec2( 4.5, 4.0) * viewSize);
	vec3 blur4 = getBloomTile(4.0 + 1.0, coord, vec2(0.625 , 0.25) + vec2( 8.5, 4.0) * viewSize);

	vec3 blur = (blur1 * 2.46 + blur2 * 2.25 + blur3 * 1.71 + blur4) / 7.42;
	
	float bloomStrength = (BLOOM_STRENGTH * 0.01);

	#if !defined DIMENSION_NETHER && !defined DIMENSION_END
	bloomStrength *= 1.0 - astraSolasTimeBrightness * 0.33 * eBS;
	#endif

	#if 2 == 0
	color = mix(color, blur, 0.25 * bloomStrength);
	#else
	vec3 bloomContrast = vec3(exp2(2 * 0.25));
	color = pow(color, bloomContrast);
	blur = pow(blur, bloomContrast);
	vec3 strengthFactor = pow(vec3(0.2 * bloomStrength), bloomContrast) * (2.0 - eBS);
	color = mix(color, blur, strengthFactor);
	color = pow(color, 1.0 / bloomContrast);
	#endif
}
