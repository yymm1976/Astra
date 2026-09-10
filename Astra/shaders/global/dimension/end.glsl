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
    #ifdef STARS
    // Solas star distribution; both hemispheres, independent of camera motion.
    vec2 coord = dir.xz / max(abs(dir.y) + length(dir.xz), 0.001);
    coord = floor(coord * 850.0) / 850.0;
    float stars = end_noise(coord) * end_noise(coord + 0.10) * end_noise(coord + 0.23);
    sky += vec3(max(stars - 0.82, 0.0) * max(0.4 - nebula * 0.2, 0.0) * 8.0 * (0.94 + 0.06*sin(time*0.24 + end_noise(coord+0.37)*6.283185)));
    #endif
    // Emission and terrain shadows use exactly the same shadow-light direction.
    vec3 stellarDirection = normalize(view_player(lightVector));
    float angle = acos(clamp(dot(dir, stellarDirection), -1.0, 1.0));
    float aa = max(fwidth(angle), 0.0001);
    // 2026-09-11 user round: "恒星太简陋" plus a pointer to IterationT 3.2, whose End
    // is built around a super-massive black hole. First attempt was still a flat ring;
    // this version models the four features that actually make such an object read as a
    // black hole instead of as a bright donut:
    //
    //   1. a pure-black shadow disk that occludes the background (mass, not brightness),
    //   2. the photon ring hugging the shadow edge,
    //   3. an inclined accretion disk with a hot inner edge, Doppler beaming (the side
    //      sweeping toward the camera is brighter) and a colour shift from blue-shifted
    //      to red-shifted across the disk,
    //   4. a lensed halo plus an ionised jet perpendicular to the disk.
    const float ASTRA_BH_SHADOW = 0.055;   // angular radius of the event horizon shadow
    const float ASTRA_BH_RING   = 0.028;   // photon-ring thickness
    const float ASTRA_BH_DISK   = 0.090;   // outer accretion disk radius
    float bhShadow = 1.0 - smoothstep(ASTRA_BH_SHADOW-aa, ASTRA_BH_SHADOW+aa, angle);
    vec3 axis = abs(stellarDirection.y)<0.95 ? vec3(0.0,1.0,0.0) : vec3(1.0,0.0,0.0);
    vec3 tangent = normalize(cross(axis,stellarDirection));
    float sinShadow = sin(ASTRA_BH_SHADOW);
    // (3) Accretion disk modelled as a projected band, which is what makes it read as
    // an inclined disk instead of a rectangle: the apparent width across the screen is
    // set by the disk plane normal (0.72,1,0.20 normalised), so viewing it near edge-on
    // narrows the band and viewing it face-on widens it, with no extra orientation term.
    vec3 diskNormal = normalize(vec3(0.72, 1.0, 0.20));
    vec3 diskAxis = normalize(cross(diskNormal, stellarDirection));
    if (dot(diskAxis,diskAxis) < 1e-6) diskAxis = tangent;
    vec3 diskAxis2 = cross(stellarDirection, diskAxis);
    // Direction within the disk plane, scaled so 1.0 is the shadow edge.
    vec2 diskPos = vec2(dot(dir,diskAxis), dot(dir,diskAxis2))/sinShadow;
    float diskRadius = length(diskPos);
    // How edge-on this disk is seen from stellarDirection: 0 = edge-on, 1 = face-on.
    float faceOn = clamp(abs(dot(normalize(dir), diskNormal)), 0.0, 1.0);
    float diskSpan = max(ASTRA_BH_DISK/sinShadow - 1.0, 0.001);
    float diskT = clamp((diskRadius-1.0)/diskSpan, 0.0, 1.0);
    // Band width grows with the projected opening angle; 0.30 keeps the near edge-on
    // case (what the vanilla End look gives from ground level) a thin bright streak.
    float diskBand = 1.0 - smoothstep(0.0, mix(0.30, 1.0, faceOn), abs(diskPos.y));
    float disk = diskBand * (1.0 - smoothstep(0.10, 1.0, diskT));
    float diskHot = 1.0 - diskT;                       // hotter toward the inner edge
    float doppler = diskPos.x / max(diskRadius, 1e-4);
    float beam = 0.22 + 0.78*pow(0.5+0.5*doppler, 1.55);
    vec3 blueShift = vec3(0.72,0.83,1.00);
    vec3 redShift  = vec3(1.00,0.52,0.26);
    vec3 diskColor = mix(blueShift, redShift, 0.5+0.5*doppler);
    diskColor = mix(diskColor, vec3(1.00,0.94,0.82), diskHot*0.65);
    float cells = texture(solasWaterNoise, diskPos*3.2 + vec2(time*0.004,0.0)).r;
    float diskDetail = 0.78 + 0.22*cells;
    // (2) Photon ring: thin, bright, hugging the shadow.
    float photonRing = exp(-max(angle-ASTRA_BH_SHADOW,0.0)*140.0);
    // (4) Lensed halo: background light wrapped around the mass.
    float halo = exp(-max(angle-ASTRA_BH_SHADOW-ASTRA_BH_RING,0.0)*4.6);
    float outer = exp(-angle*3.4)*0.085;
    // Jet: ionised outflow along the disk's rotation axis, so it is perpendicular to the
    // band above rather than to the old fixed tower axis.
    float jetAlong = dot(dir,diskNormal);
    float jetAcross = length(cross(dir,diskNormal));
    float jet = exp(-pow(jetAcross/max(sinShadow*0.14,1e-4),2.0))
              * exp(-max(angle-ASTRA_BH_SHADOW,0.0)*5.5);
    // The shadow eats the sky it covers; every emission term is ~0 inside it already.
    sky *= bhShadow;
    sky += diskColor * disk * diskDetail * beam * 3.4;
    sky += vec3(1.00,0.86,0.62) * photonRing * 1.5;
    sky += vec3(0.62,0.46,1.00) * (halo*0.34 + outer);
    sky += vec3(0.55,0.72,1.00) * jet * 0.22;
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
