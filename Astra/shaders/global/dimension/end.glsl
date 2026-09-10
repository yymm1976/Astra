#ifndef ASTRA_GLOBAL_DIMENSION_END_GLSL
#define ASTRA_GLOBAL_DIMENSION_END_GLSL
// Solas V2.2b: common.glsl End palette, skyEffects.glsl stars/nebula,
// fog.glsl distance curve and gbuffersLighting.glsl shadow mix.
// Astra: linear HDR boundary, full-screen sky, emissive stellar disc instead
// of vortex, and no atmospheric cloud layers. See THIRD-PARTY.md.
#include "/lib/colors.glsl"
#include "/lib/encoding.glsl"
#include "/lib/solas_water.glsl"
struct EndParams { float nightVision; float heldLightBase; };
const vec3 END_SKY_LIGHT_COLOR = vec3(165.0,125.0,255.0) / 255.0 * 0.90 * vec3(165.0,125.0,255.0) / 255.0 * 0.90;
const vec3 END_AMBIENT_COLOR = vec3(205.0,145.0,255.0) / 255.0 * 0.30 * vec3(205.0,145.0,255.0) / 255.0 * 0.30;
const vec3 END_VOID_COLOR = END_AMBIENT_COLOR * 0.15;
vec3 end_void_tint(float y) { return END_VOID_COLOR; }
float end_noise(vec2 p) { return fract(sin(dot(p, vec2(12.9898,4.1414))) * 43758.5453); }
float end_spiral(vec2 coord){
	float whirl = 20.0;
	float arms = 5.0;

    coord = vec2(atan(coord.y, coord.x) - frameTimeCounter * 0.125, sqrt(coord.x * coord.x + coord.y * coord.y));
    float center = pow(clamp(1.0 - coord.y, 0.0, 1.0), 8.0) * 24.0;
    float spiral = sin((coord.x + sqrt(coord.y) * whirl) * arms) + center - coord.y;

    return clamp(spiral * 0.1, 0.0, 1.0);
}

void end_reference_nebula(inout vec3 color, in vec3 worldPos, in float VoU, inout float nebulaFactor, in float caveFactor) {
	float visibility = ((1.0 - abs(VoU)) * (1.0 - abs(VoU))) * 1.25;

	if (visibility > 0.0) {
		vec3 sunVec = normalize(view_player(lightVector));
		vec2 sunCoord = sunVec.xz / max(sunVec.y + length(sunVec), 0.01);
		vec2 planeCoord1 = worldPos.xz / max(length(worldPos) + worldPos.y, 0.01) - sunCoord;
		vec2 planeCoord2 = worldPos.xz / length(worldPos) - sunCoord;
		float spiral1 = end_spiral(planeCoord1) * clamp(VoU, 0.0, 1.0);
		float spiral2 = end_spiral(planeCoord2) * clamp(VoU, 0.0, 1.0);
			 planeCoord1 += cameraPosition.xz * 0.0001;
			 planeCoord2 += cameraPosition.xz * 0.0001;
			 planeCoord1 += spiral1;
			 planeCoord2 += spiral2 * 2.0;

		float nebulaNoise1  = texture(solasWaterNoise, planeCoord1 * 0.01 + frameTimeCounter * 0.0001).r;
			  nebulaNoise1 += texture(solasWaterNoise, planeCoord1 * 0.02 - frameTimeCounter * 0.0002).r * 0.500;
			  nebulaNoise1 += texture(solasWaterNoise, planeCoord1 * 0.04 + frameTimeCounter * 0.0003).r * 0.250;
			  nebulaNoise1 += texture(solasWaterNoise, planeCoord1 * 0.08 - frameTimeCounter * 0.0004).r * 0.250;
			  nebulaNoise1 += texture(solasWaterNoise, planeCoord1 * 0.16 + frameTimeCounter * 0.0005).r * 0.125;
			  nebulaNoise1 = clamp(nebulaNoise1 - 0.7, 0.0, 1.0);
		float nebulaNoise2  = texture(solasWaterNoise, planeCoord2 * 0.02 - frameTimeCounter * 0.00015).r;
			  nebulaNoise2 += texture(solasWaterNoise, planeCoord2 * 0.04 + frameTimeCounter * 0.00030).r * 0.75;
			  nebulaNoise2 += texture(solasWaterNoise, planeCoord2 * 0.08 - frameTimeCounter * 0.00060).r * 0.50;
			  nebulaNoise2 = clamp(nebulaNoise2 - 0.8, 0.0, 1.0);

		color += mix(mix(END_AMBIENT_COLOR, END_SKY_LIGHT_COLOR, nebulaNoise1), mix(vec3(2.0, 0.8, 0.2), vec3(0.1, 2.1, 0.8), nebulaNoise1), texture(solasWaterNoise, planeCoord1 * 0.025).r * 0.4) * visibility * nebulaNoise1;
		color += mix(vec3(2.3, 0.8, 0.5), vec3(1.2, 2.2, 0.9), nebulaNoise2 - 0.25) * visibility * (nebulaNoise2 * nebulaNoise2) * 0.125;
		nebulaFactor = (nebulaNoise1 + nebulaNoise2) * visibility;
	}
}

vec3 end_sky(vec3 dir, vec3 voidTint, float time) {
    dir = normalize(dir);
    vec3 sky = END_VOID_COLOR;
    float nebula = 0.0;
    #ifdef END_NEBULA
    end_reference_nebula(sky, dir, dir.y, nebula, 1.0);
    #endif
    // Emission and terrain shadows use exactly the same shadow-light direction.
    vec3 stellarDirection = normalize(view_player(lightVector));
    float angle = acos(clamp(dot(dir, stellarDirection), -1.0, 1.0));
    float aa = max(fwidth(angle), 0.0001);
    // 2026-09-11 user round (second pass) - the brief: a deep-space background with a
    // razor-sharp pure-black event horizon, an extremely thin blue-white photon ring, an
    // accretion disk flattened into an ellipse and bent by lensing into arcs above and
    // below, hot blue-white inside grading through gold-orange to dark red outside,
    // turbulent grain, background stars smeared into long arcs, high contrast.
    //
    // Lensing. A point mass deflects a ray by theta_E^2 / theta; solving the resulting
    // quadratic in cos(angle) gives the background direction directly, with the right
    // limits (inverse deflection far away, strong bending near the disk). The map is
    // applied to BOTH the nebula and the star field, which is what warps the sky and
    // smears the stars into arcs instead of leaving a decorative ring behind.
    //
    // Accretion disk, in world space with the black hole at the origin and the view ray
    // parameterised as d*t (t > 0 ahead of the camera, which sits at the hole). The disk
    // is a plane through the origin with normal n, so d*t . n = 0 gives the intersection
    // at t = -p0.n / d.n with p0 = 0 -> t = 0. That degeneracy is the wrong parameterisation
    // for a distant camera, so the camera is instead treated as far away: the ray is
    // roughly the same everywhere and what matters is the angle to the disk axis.
    //
    // In that far-field view the disk projects to an ellipse: the axis-aligned component
    // expands by 1/|axis.n|. The primary image is therefore the half of that ellipse on
    // the camera side, and the far half is supplied separately by the lensed arc below -
    // which is exactly the top-arc / bottom-band split the brief describes.
    const float ASTRA_BH_SHADOW = 0.052;
    const float ASTRA_BH_EINSTEIN = 0.115;   // Einstein radius (the arcs live here)
    const float ASTRA_BH_DISK_IN = 0.085;    // inner accretion radius
    const float ASTRA_BH_DISK_OUT = 0.205;   // outer accretion radius
    float cosA = clamp(dot(dir, stellarDirection), -1.0, 1.0);
    float R = max(angle, 1e-4);
    float E = ASTRA_BH_EINSTEIN;
    float q = sqrt(max(R * R + 4.0 * E * E, 0.0));
    float cosDest = clamp((R * cosA + 2.0 * E * E) / max(q, 1e-6), -1.0, 1.0);
    float destAngle = acos(cosDest);
    float magnification = clamp((destAngle - E) / R, 0.0, 1.0);   // 1 = undistorted sky
    vec3 radialAxis = dir - cosA * stellarDirection;
    float sinAngle = length(radialAxis);
    radialAxis = sinAngle > 1e-5
        ? radialAxis / sinAngle
        : normalize(cross(stellarDirection, vec3(0.0, 1.0, 0.0)) + vec3(1e-5, 0.0, 1e-5));
    vec3 lensedDir = cosDest * stellarDirection + radialAxis * sin(destAngle);

    // Background samples the lensed direction, which is what warps the nebula and smears
    // the star field into arcs around the mass.
    float lensNebula = 0.0;
    #ifdef END_NEBULA
    {
        vec3 nebulaSky = END_VOID_COLOR;
        end_reference_nebula(nebulaSky, lensedDir, lensedDir.y, lensNebula, 1.0);
        sky = nebulaSky;
    }
    #endif
    #ifdef STARS
    // Cool blue star field; near the Einstein radius the mapping compresses the sky, so
    // the same points land closer together and each one stretches into a short arc.
    vec2 starCoord = lensedDir.xz / max(abs(lensedDir.y) + length(lensedDir.xz), 0.001);
    starCoord = floor(starCoord * 850.0) / 850.0;
    float stars = end_noise(starCoord) * end_noise(starCoord + 0.10) * end_noise(starCoord + 0.23);
    float starArc = smoothstep(0.55, 1.0, 1.0 - magnification);
    float starLum = max(stars - 0.80, 0.0) * max(0.4 - lensNebula * 0.2, 0.0) * 9.0
                  * (0.94 + 0.06 * sin(time * 0.24 + end_noise(starCoord + 0.37) * 6.283185));
    starLum *= (1.0 + starArc * 5.5);
    sky += vec3(0.62, 0.78, 1.20) * starLum;
    #endif

    // ---- accretion disk -------------------------------------------------------
    vec3 diskNormal = normalize(vec3(0.35, 1.0, 0.18));
    float axisDotN = abs(dot(stellarDirection, diskNormal));
    // Projected ellipse: the component along the disk axis is stretched by 1/axisDotN.
    float radialComp = dot(dir, normalize(cross(diskNormal, stellarDirection) + vec3(1e-5)));
    float axisComp  = dot(dir, normalize(cross(stellarDirection, cross(diskNormal, stellarDirection)) + vec3(1e-5)));
    float projected = length(vec2(radialComp, axisComp / max(axisDotN, 1e-3)));
    float diskRadius = asin(clamp(projected, 0.0, 1.0));
    float u = clamp((diskRadius - ASTRA_BH_DISK_IN)
                    / max(ASTRA_BH_DISK_OUT - ASTRA_BH_DISK_IN, 1e-4), 0.0, 1.0);
    vec3 hotCore = vec3(1.30, 1.32, 1.45);
    vec3 goldMid = vec3(1.40, 0.85, 0.34);
    vec3 redEdge = vec3(0.52, 0.14, 0.08);
    vec3 diskGrad = mix(hotCore, goldMid, smoothstep(0.0, 0.55, u));
    diskGrad = mix(diskGrad, redEdge, smoothstep(0.55, 1.0, u));
    float turb = texture(solasWaterNoise, vec2(radialComp, axisComp) * 6.0
                         + vec2(time * 0.010, 0.0)).r;
    float diskGrain = 0.68 + 0.32 * turb;
    // Doppler beaming: the half sweeping toward the camera is far brighter.
    float beam = 0.22 + 1.05 * pow(clamp(0.5 + 0.5 * radialComp, 0.0, 1.0), 1.6);
    // Only the camera-side half is drawn here; the far half is the lensed arc below.
    float nearHalf = smoothstep(-0.02, 0.06, radialComp);
    float diskMask = (1.0 - smoothstep(0.72, 1.0, u)) * nearHalf;
    vec3 diskRGB = diskGrad * diskMask * diskGrain * beam * 3.4;

    // ---- lensed far side: the arc swept over the shadow ----------------------
    {
        float arcBand = exp(-pow((angle - E) / max(E * 0.62, 1e-4), 2.0));
        float arcTurb = texture(solasWaterNoise, vec2(angle * 26.0, angle * 9.0)
                                + vec2(time * 0.007, 0.0)).r;
        vec3 arcColor = mix(vec3(1.30, 1.28, 1.44), vec3(1.32, 0.78, 0.30), 0.40);
        diskRGB += arcColor * arcBand * smoothstep(0.15, 0.9, 1.0 - magnification)
                 * (0.50 + 0.50 * arcTurb) * 3.0;
    }

    // ---- horizon, photon ring, halo ------------------------------------------
    // Hard-edged pure-black shadow; it occludes everything already computed behind it.
    float horizon = 1.0 - smoothstep(ASTRA_BH_SHADOW - aa, ASTRA_BH_SHADOW + aa, angle);
    float photonRing = exp(-max(angle - ASTRA_BH_SHADOW, 0.0) * 220.0);
    sky *= horizon;
    sky += diskRGB;
    sky += vec3(0.80, 0.90, 1.30) * photonRing * 2.2;
    // Cool halo where the lensed background piles up at the ring: the deep-blue contrast
    // against the warm disk is what the brief asks for.
    sky += vec3(0.30, 0.38, 0.68) * exp(-max(angle - E, 0.0) * 3.0) * 0.17;

    // Cinematic grade: higher contrast, and a slight bloom bleed from the disk.
    sky = sky * sky * 0.60 + sky * 0.50;
    return sky * (1.0 - max(blindness, darknessFactor));
}
vec4 end_fog(out float skyFogStrength, float distanceToEye, float borderDistance, vec3 playerPos) {
    skyFogStrength = 0.0;
    float f = 1.0 - exp(-2.0 * pow(borderDistance / max(borderFogDistance, 1.0), 4.0) * (END_FOG_DENSITY * 0.01));
    vec3 c = END_VOID_COLOR;
    float dark = max(blindness, darknessFactor);
    if (dark > 0.0) { f = max(f, 1.0-exp(-distanceToEye * dark * 0.1)); c *= 1.0-dark; }
    if (isEyeInWater == 2) { f = 1.0-exp(-distanceToEye*2.0); c=vec3(1.0,0.05,0.0); }
    return vec4(c, f);
}
vec3 end_lighting(vec3 albedo, vec3 normal, vec3 playerPos, vec3 shadowPos,
                  float blockLight, float emissive, float portal, float time, EndParams params) {
    float ndotl = max(dot(normal, normalize(view_player(lightVector))), 0.0);
    float visibility = 1.0;
    #ifdef SHADOWS
    visibility = mix(1.0, shadow_opaque_visibility(shadowPos), shadow_coverage(playerPos, shadowPos));
    #endif
    // Solas shadow mixing and palette. Astra uses a brighter diffuse response
    // below to keep the island readable with its separate exposure/tonemap.
    // This response is an artistic adaptation, not a color-space conversion.
    vec3 scene = mix(END_AMBIENT_COLOR, END_SKY_LIGHT_COLOR, visibility * ndotl) * 0.25;
    scene += solasMinLight + params.nightVision * vec3(0.2,0.3,0.2);
    vec3 factor = sqrt(max(scene, vec3(0.0))) * 1.22;
    vec3 local = block_lighting(0.0, blockLight, held_light_strength(params.heldLightBase, playerPos), 0.0, 0.0);
    return albedo * (factor + local + (emissive + portal * 2.0) * (EMISSIVE_STRENGTH * 0.01));
}
#endif
