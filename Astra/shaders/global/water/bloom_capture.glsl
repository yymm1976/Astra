// Adapted from Solas V2.2b computeBloom.glsl by Septonious; see THIRD-PARTY.md.

const float weight[6] = float[6](0.0556, 0.1667, 0.2777, 0.2777, 0.1667, 0.0556);

vec3 getBloomTile(float lod, vec2 bloomCoord, vec2 offset) {
    float pixelHeight=0.8/min(360.0,viewHeight);
    float pixelWidth=pixelHeight/(viewWidth/viewHeight);
    vec2 viewSize=1.0/vec2(viewWidth,viewHeight);
	vec3 bloom = vec3(0.0);

	float scale = exp2(lod);
	// The taps used to derive their mip level from screen-space derivatives, which is
	// undefined inside the per-tile test below. bloomCoord spans pixelHeight *
	// viewHeight texels per screen pixel, so this is the level those derivatives
	// resolved to; dropping the log2 term would change the blur at every resolution.
	float level = lod + log2(pixelHeight * viewHeight);
	bloomCoord = (bloomCoord - offset) * scale;
	vec2 padding = vec2(0.5) + 2.0 * viewSize * scale;

	if (abs(bloomCoord.x - 0.5) < padding.x && abs(bloomCoord.y - 0.5) < padding.y) {
		for(int i = 0; i < 6; i++) {
			for(int j = 0; j < 6; j++) {
				vec2 pixelOffset = vec2((i - 2.25) * pixelWidth, (j - 2.25) * pixelHeight);
				vec2 sampleCoord = bloomCoord + pixelOffset * scale;

				bloom += clamp(textureLod(colortex0, sampleCoord, level).rgb, 0.0, 1.0) * weight[i] * weight[j];
			}
		}
	}

	return pow(bloom / 256.0, vec3(0.125));
}

vec3 computeBloom(vec2 texCoord) {
    vec2 viewSize=1.0/vec2(viewWidth,viewHeight);
	vec2 bloomCoord = texCoord * viewHeight * 0.8 / min(360.0, viewHeight);
	vec3 blur =  getBloomTile(1.0 + 1.0, bloomCoord, vec2(0.0   , 0.0 ) + vec2( 0.5, 0.0) * viewSize);
	     blur += getBloomTile(2.0 + 1.0, bloomCoord, vec2(0.50  , 0.0 ) + vec2( 4.0, 0.0) * viewSize);
	     blur += getBloomTile(3.0 + 1.0, bloomCoord, vec2(0.50  , 0.25) + vec2( 4.0, 4.0) * viewSize);
	     blur += getBloomTile(4.0 + 1.0, bloomCoord, vec2(0.625 , 0.25) + vec2( 8.0, 4.0) * viewSize);

    return clamp(blur, 0.0, 1.0);
}
