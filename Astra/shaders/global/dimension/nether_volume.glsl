#ifndef ASTRA_NETHER_VOLUME_GLSL
#define ASTRA_NETHER_VOLUME_GLSL
// Adapted from X0nk Bliss Stable lib/nether_fog.glsl, retrieved 2026-09-10.
// Original noise layout; Astra exposure uses lower plume/ceiling density.
//
// This volume is composited over the plain nether fog in program/scene.glsl as
//   result = result * volume.a + volume.rgb
// which is the single-scattering form: the volume attenuates what is behind it and
// adds its own in-scattered light exactly once. Do not fold the plain-fog term in
// here as well, or the medium absorbs twice.
//
// Astra density scale. The reference runs this march over a longer distance with more
// samples; Astra keeps 16 samples and shortens the march, so the per-step densities
// are dialled down to keep the plumes readable instead of blanketing the view.
const float ASTRA_NETHER_PLUME_SCALE = 0.55;
const float ASTRA_NETHER_HAZE_SCALE = 0.30;
const float ASTRA_NETHER_CEILING_SCALE = 0.35;
uniform sampler2D blissNetherNoise;
float astra_bliss_density(in vec3 pos){
	pos /= 18.;
	pos.xz *= 0.5;

	vec3 p = floor(pos);
	vec3 f = fract(pos);

	f = (f*f) * (3.-2.*f);
	vec2 uv =  p.xz + f.xz + p.y * vec2(0.0,193.0);
	vec2 coord =  uv / 512.0;
	vec2 xy = texture(blissNetherNoise, coord).yx;
	return mix(xy.r,xy.g, f.y);
}

float astra_bliss_cloud(in vec3 pos){
	vec3 samplePos = pos*vec3(1.0,1./48.,1.0);

    float Wind = pow(max(pos.y-30,0.0) / 15.0,2.1);

	float Plumes = texture(blissNetherNoise, (samplePos.xz + Wind)/256.0).b;
	float floorPlumes = clamp(0.3 - exp(Plumes * -6),0,1);
	Plumes *= Plumes;

	float Erosion = astra_bliss_density(samplePos * 400	- frameTimeCounter*10 - Wind*10) *0.7+0.3 ;

    float RoofToFloorDensityFalloff = exp(max(100-pos.y,0.0) / -15);
	float FloorDensityFalloff = pow(exp(max(pos.y-31,0.0) / -3.0),2);

	float Output = max((RoofToFloorDensityFalloff - Plumes * (1.0-Erosion)) * 2.0,	clamp((FloorDensityFalloff - floorPlumes*0.5) * Erosion ,0.0,1.0) );
    
	return Output;
}

vec4 astra_bliss_fog(
	vec3 viewPosition,
	float dither,
	float dither2
){


	/// -------------  RAYMARCHING STUFF ------------- \\\

	const int SAMPLECOUNT = 16;

	vec3 wpos = mat3(gbufferModelViewInverse) * viewPosition + gbufferModelViewInverse[3].xyz;
	vec3 dVWorld = (wpos-gbufferModelViewInverse[3].xyz);
	vec3 progressW = vec3(0.0);

	float rayLength = length(dVWorld);
    if (rayLength < 0.001) return vec4(0.0, 0.0, 0.0, 1.0);
	float maxLength = min(rayLength, min(borderFogDistance, 12*16))/rayLength;

	dVWorld *= maxLength;

	float dL = length(dVWorld);

	const float expFactor = 11.0;
    // Algebraic recurrence of Bliss's exponential sample distribution. It keeps
    // the same points/weights, without two pow evaluations per loop iteration.
    const float sampleRatio = pow(expFactor, 1.0 / float(SAMPLECOUNT));
    const float weightScale = log(expFactor) / float(SAMPLECOUNT) / (expFactor - 1.0);
    float sampleExp = pow(expFactor, dither / float(SAMPLECOUNT));
	
	/// -------------  COLOR/LIGHTING STUFF ------------- \\\

	vec3 color = vec3(0.0);
	float absorbance = 1.0;

	vec3 hazeColor = nether_palette(fogColor);

	#if defined LPV_VL_FOG_ILLUMINATION && defined EXCLUDE_WRITE_TO_LUT
    	float TorchBrightness_autoAdjust = mix(1.0, 30.0,  clamp(exp(-10.0*exposure),0.0,1.0)) / 5.0;
	#endif

	for (int i = 0; i < SAMPLECOUNT; i++) {
		float d = (sampleExp - 1.0) / (expFactor - 1.0);
		float dd = sampleExp * weightScale;
        sampleExp *= sampleRatio;
		
		progressW = gbufferModelViewInverse[3].xyz + cameraPosition + d*dVWorld;

		float densityVol = astra_bliss_cloud(progressW);
		float clearArea = 1.0 - min(max(1.0 - length(progressW - cameraPosition) / 24.0,0.0),1.0);

		//------ PLUME EFFECT
			float plumeDensity = min(densityVol * pow(min(max(100.0-progressW.y,0.0)/30.0,1.0),4.0), pow(clamp(1.0 - length(progressW-cameraPosition)/borderFogDistance,0.0,1.0),5.0));
			plumeDensity *= 0.22 * ASTRA_NETHER_PLUME_SCALE;
			float plumeVolumeCoeff = exp(-plumeDensity*dd*dL);

			vec3 lighting = vec3(1.0,0.4,0.2) * exp(-15.0*densityVol) * (clearArea*clearArea*0.9+0.1);

			color += (lighting - lighting * plumeVolumeCoeff) * absorbance;
			absorbance *= plumeVolumeCoeff;

		//------ HAZE EFFECT
			// dont make haze contrube to absorbance.
			float hazeDensity = 0.001 * ASTRA_NETHER_HAZE_SCALE;
			#ifndef ReflectedFog
				hazeDensity *= 0.65;
			#endif
			float hazeVolumeCoeff = exp(-hazeDensity*dd*dL);
			
			vec3 hazeLighting = hazeColor;
			
			color += (hazeLighting - hazeLighting*hazeVolumeCoeff) * absorbance;

		//------ CEILING SMOKE EFFECT
			float ceilingSmokeDensity = 0.001 * pow(min(max(progressW.y-40.0,0.0)/50.0,1.0),3.0);
			ceilingSmokeDensity *= 0.60 * ASTRA_NETHER_CEILING_SCALE;
			float ceilingSmokeVolumeCoeff = exp(-ceilingSmokeDensity*dd*dL);
			
			// Bliss's white ceiling term assumed its own exposure/palette. Use the
            // same Complementary biome illumination as the haze, so the ceiling
            // does not wash crimson/soul/warped biomes into the same white veil.
            vec3 ceilingSmoke = hazeColor;

			color += (ceilingSmoke - ceilingSmoke*ceilingSmokeVolumeCoeff) * (absorbance*0.5+0.5);
			absorbance *= ceilingSmokeVolumeCoeff;

		//------ LPV FOG EFFECT
			#if defined LPV_VL_FOG_ILLUMINATION && defined EXCLUDE_WRITE_TO_LUT
				color += LPV_FOG_ILLUMINATION(progressW-cameraPosition, dd, dL) * TorchBrightness_autoAdjust * absorbance;
			#endif

	}
	return vec4(color, absorbance);
}
#endif
