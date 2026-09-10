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
    // 2026-09-11 user round. Previous attempt was a disaster: the quadratic root it
    // picked mapped any ray inside the Einstein radius to the OPPOSITE side of the sky
    // (measured: a ray at the hole centre landed 81 degrees away), which produced the
    // mirrored "second half moon" and wiped out the star field. It also drew a half-disk
    // so the object looked like a crescent. Rebuilt on three rules:
    //
    //   1. the background keeps its original nebula + star field, expressed on the
    //      UNLENSED direction. Nothing is remapped wholesale.
    //   2. lensing is a local, single-valued warp near the hole (stars only), tapering to
    //      zero before the Einstein radius, so no second image and no opposite-side copy.
    //   3. the object is a centred black disk + thin blue-white photon ring + one tilted
    //      accretion ellipse with a Doppler-bright side. No half selections.
    const float ASTRA_BH_SHADOW = 0.042;     // event horizon shadow radius
    const float ASTRA_BH_RING = 0.055;       // photon ring radius (just outside)
    const float ASTRA_BH_DISK_OUT = 0.150;   // accretion ellipse outer radius
    float cosA = clamp(dot(dir, stellarDirection), -1.0, 1.0);
    float horizon = 1.0 - smoothstep(ASTRA_BH_SHADOW - aa, ASTRA_BH_SHADOW + aa, angle);
    // Local frame around the hole: `along` is horizontal on screen, `across` vertical.
    vec3 radialAxis = dir - cosA * stellarDirection;
    float sinAngle = length(radialAxis);
    radialAxis = sinAngle > 1e-5
        ? radialAxis / sinAngle
        : normalize(cross(stellarDirection, vec3(0.0, 1.0, 0.0)) + vec3(1e-5, 0.0, 1e-5));
    vec3 diskAxis = normalize(cross(stellarDirection, radialAxis));

    // ---- 2. star-field lensing: local warp only, no second image -----------------
    // The displacement fades out by ASTRA_BH_LENS_END, so outside that radius the stars
    // are exactly the field the user asked to keep. Inside it the field is pulled toward
    // the ring, which is what stretches point stars into short tangential arcs.
    const float ASTRA_BH_LENS_END = 0.34;
    float lensT = 1.0 - smoothstep(ASTRA_BH_RING, ASTRA_BH_LENS_END, angle);
    float lensPull = ASTRA_BH_RING * lensT * 0.70;   // angular pull toward the ring
    float warpedAngle = max(angle - lensPull, 1e-4);
    vec3 warpedDir = cos(min(warpedAngle, 3.14159)) * stellarDirection
                   + radialAxis * sin(min(warpedAngle, 3.14159));

    // ---- 1. background: nebula and stars on the original field -------------------
    // The nebula was already evaluated on the unlensed `dir` above; reuse its factor
    // instead of running the same noise a second time.
    float lensNebula = nebula;
    #ifdef STARS
    {
        vec2 starCoord = warpedDir.xz / max(abs(warpedDir.y) + length(warpedDir.xz), 0.001);
        starCoord = floor(starCoord * 850.0) / 850.0;
        float stars = end_noise(starCoord) * end_noise(starCoord + 0.10)
                    * end_noise(starCoord + 0.23);
        float starLum = max(stars - 0.80, 0.0) * max(0.4 - lensNebula * 0.2, 0.0) * 8.0
                      * (0.94 + 0.06 * sin(time * 0.24 + end_noise(starCoord + 0.37) * 6.283185));
        // Arc stretch: the warp compresses neighbouring star cells together near the
        // ring, so the same points land closer and each one reads as a short arc.
        starLum *= 1.0 + 2.5 * lensT * lensT;
        sky += vec3(0.66, 0.80, 1.18) * starLum;
    }
    #endif

    // ---- 3. accretion disk -------------------------------------------------------
    // The previous build put a symmetric bright ring around a dark disk, which is exactly
    // what a moon (or an eclipse) looks like - the user's "看起来也只像个大月亮". A black
    // hole reads as one because of two things a ring cannot give: the disk is TILTED and
    // passes IN FRONT of the shadow, and its lensed image arcs over the top. So the halo
    // ring is gone; the disk does all the work.
    float along = dot(dir, radialAxis);
    float across = dot(dir, diskAxis);
    const float ASTRA_BH_A = 0.150;      // disk half-width
    const float ASTRA_BH_T = 0.0160;     // band half-thickness
    const float ASTRA_BH_Y0 = -0.009;    // near side sits just below centre
    const float ASTRA_BH_TILT = 0.17;
    float ct = cos(ASTRA_BH_TILT), st = sin(ASTRA_BH_TILT);
    float su = along * ct - across * st;      // along the disk
    float sv = along * st + across * ct;      // across the disk
    float radial = clamp(abs(su) / ASTRA_BH_A, 0.0, 1.0);
    // Inner edge hot blue-white, outer edge dim deep red.
    vec3 hotInner = vec3(1.05, 1.12, 1.45);
    vec3 goldMid  = vec3(1.30, 0.82, 0.34);
    vec3 deepRed  = vec3(0.46, 0.13, 0.07);
    vec3 diskCol = mix(hotInner, goldMid, smoothstep(0.0, 0.55, radial));
    diskCol = mix(diskCol, deepRed, smoothstep(0.60, 1.0, radial));
    // Doppler beaming: the approaching side is far brighter than the receding one. This
    // asymmetry is the strongest single "not a moon" cue in the whole image.
    float beam = mix(0.14, 1.0, smoothstep(-ASTRA_BH_A * 0.85, ASTRA_BH_A * 0.85, -su));
    float turb = texture(solasWaterNoise, vec2(su, sv) * 46.0 + vec2(time * 0.010, 0.0)).r;
    float grain = 0.62 + 0.38 * turb;
    float radialFall = exp(-pow(radial * 1.10, 2.6));
    // Near side: the band just below the centre line, drawn IN FRONT of the shadow.
    float bandV = sv - ASTRA_BH_Y0;
    float nearBand = exp(-pow(bandV / ASTRA_BH_T, 2.0))
                   * smoothstep(0.0, -ASTRA_BH_T * 0.4, bandV)
                   * (1.0 - smoothstep(0.84, 1.0, radial));
    // Lensed far side: the same band lifted clear over the top of the shadow.
    // The lensed image hugs the top of the shadow rather than floating above it.
    float farV = sv - (ASTRA_BH_Y0 + 1.55 * ASTRA_BH_SHADOW);
    float farBand = exp(-pow(farV / (ASTRA_BH_T * 1.15), 2.0))
                  * (1.0 - smoothstep(0.76, 1.0, radial));
    vec3 diskEmission = diskCol * (nearBand + farBand * 0.80) * beam * grain
                      * radialFall * 1.55;

    // Photon ring: a hairline just outside the shadow. Deliberately weak - a bright ring
    // all the way around is the moon look this pass is removing.
    float photonRing = exp(-max(angle - ASTRA_BH_SHADOW, 0.0) * 420.0);

    // Background is occluded by the shadow; the disk is added after, so its near side
    // correctly crosses in front of the black disk.
    sky *= horizon;
    sky += diskEmission;
    sky += vec3(0.85, 0.95, 1.35) * photonRing * 0.40;

    // Mild contrast lift only; the previous sky*sky term blew the disk out to white.
    sky *= 1.06;
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
