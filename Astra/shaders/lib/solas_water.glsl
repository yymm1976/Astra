#ifndef ASTRA_SOLAS_WATER_GLSL
#define ASTRA_SOLAS_WATER_GLSL
#include "/lib/transforms.glsl"
#include "/lib/water_palette.glsl"
#include "/lib/colors.glsl"
#include "/lib/water_interface_record.glsl"
#include "/global/water/medium_state.glsl"
#include "/global/water/absorption.glsl"
#include "/lib/solas_water_frame.glsl"
// Adapted from Solas V2.2b by Septonious: common.glsl, waterFog.glsl,
// color/lightColor.glsl. Source supplied locally; see THIRD-PARTY.md.
// Astra adapters: prefixed names, existing world sun, linear scene boundary.
// Both palettes retain the original terrain/surface intensities and colour domain.
uniform vec3 astraSolasTerrainAmbient;
uniform vec3 astraSolasTerrainDirect;
uniform vec3 astraSolasSurfaceAmbient;
uniform vec3 astraSolasSurfaceDirect;
void solas_water_lighting(out vec3 ambient, out vec3 direct, bool terrain) {
    ambient = terrain ? astraSolasTerrainAmbient : astraSolasSurfaceAmbient;
    direct = terrain ? astraSolasTerrainDirect : astraSolasSurfaceDirect;
}
// Retained reference helper with no active caller; Astra uses its shared sky.
// Solas sky.glsl default daytime/nighttime scattering, evaluated in world axes.
// Its return value is the reference interface's color domain (before composite5).
vec3 solas_water_sky(vec3 direction) {
    vec3 ray = normalize(direction);
    float time = astraSolasTimeBrightness;
    float sunVisibility = solas_sun_visibility();
    float VoURaw = ray.y;
    float VoU = clamp(VoURaw, 0.0, 1.0);
    float VoS = pow(clamp(dot(ray, normalize(worldSunVector)), 0.0, 1.0), 1.25);
    float skyDensity = exp(-0.75 * pow(VoU, 2.0 - time));
    float width = pow(1.0 - VoU, 2.0 - VoS) * pow(min(1.0 + VoURaw, 1.0), 3.0);
    float sunMix = (1.0 - time * 0.5) * (1.0 - wetness * 0.5) * VoS * width * 0.25;
    float rayleighMix = (0.25 + sunVisibility * 0.25) * (1.0 - wetness * 0.75) * (1.0 - time*time * 0.5);
    float density = 1.25 - time * 0.5;
    float zenith = density / pow(max(ray.y * 3.14159265359, 0.0035), 0.75);
    float sunZenith = density / pow(max(worldSunVector.y + 0.5, 0.0035), 0.75);
    vec3 newSky = vec3(0.39, 0.57, 1.0) * 2.5;
    vec3 absorption = exp2(-newSky * zenith) * 2.0;
    vec3 sunAbsorption = exp2(-newSky * sunZenith) * 2.0;
    vec3 sky = newSky * zenith;
    vec3 totalSky = mix(sky * absorption, sky / sqrt(sky*sky + 2.0), clamp(worldSunVector.y + 0.5, 0.0, 1.0));
    totalSky *= sunAbsorption * 0.5 + 0.5 * length(sunAbsorption);
    vec3 ambient, direct;
    solas_water_lighting(ambient, direct, false);
    vec3 lightSqrt = sqrt(max(direct, vec3(0.0)));
    vec3 day = mix(normalize(skyColor + 0.00001) * 1.5, vec3(0.62, 0.69, 1.0), 0.5 - time * 0.25);
    day = mix(day, lightSqrt, pow(1.0 - VoU, 2.0) * (1.0 - wetness) * (1.0 - time) * 0.2);
    day = mix(day * skyDensity, totalSky, rayleighMix) * 3.14159265359;
    vec3 tc = day / (day + 1.0);
    day = mix(day / (dot(day, vec3(0.2126,0.7152,0.0722)) + 1.0), tc, tc);
    day = mix(pow(max(day, vec3(0.0)), vec3(2.2)), lightSqrt, sunMix);
    vec3 night = vec3(clamp(1.292936186 * pow(57.5,-0.133204759),0.0,1.0),
                      clamp(1.129890860 * pow(57.5,-0.075514849),0.0,1.0),1.0);
    night = mix(pow((night+0.055)/1.055,vec3(2.2)), night/12.92, step(night,vec3(0.04045))) * 0.3;
    vec3 atmosphere = mix(night * 0.65 * skyDensity, day, sunVisibility);
    atmosphere = mix(atmosphere, solasWeather * clamp(sunVisibility,0.35,1.0), wetness * 0.5);
    return atmosphere * (1.0 - clamp(blindness,0.0,1.0));
}

// Distance medium in the frame's linear HDR domain. rgb is the medium radiance
// and a is scalar distance visibility; at the eye and at density zero the
// fog blend is identity. ITT 3.2 composite1.fsh::WaterFog is the reference; ordinary
// Astra water has no ice mask, so its ice terms are not faked. waterDistance is
// the caller's real camera leg (hand-remapped, without the shaft distance cap), so
// visibility and the caller's spectral absorption share one length.
vec4 solas_water_fog(vec3 viewPos, float waterDistance) {
    float visibility = astra_water_visibility(waterDistance);
    vec3 medium;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END && defined ASTRA_WATER_FOG_FRAME_READ
    // Ordinary fog has no directional peak. Both shafts-on and shafts-off
    // draws reuse the complete linear medium prepared by the vertex stage.
    medium = waterFogFrameMedium;
    #else
    vec3 fogBase;
    vec2 response;
    solas_water_fog_frame_parameters(fogBase, response);
    medium = solas_water_medium_linear(fogBase, response.x, wetness);
    #endif
    // ITT WaterFog's up/down response belongs to the medium, not to screen
    // blur. The shadowed shaft pass continues to own directional sunlight.
    vec3 worldRay = normalize(view_player(viewPos));
    medium *= clamp(worldRay.y*0.4+0.6,0.2,1.0);
    return vec4(medium, visibility);
}
// ITT 3.2 composite1.fsh::WaterFog order in linear HDR: the scene behind the
// camera leg is attenuated by the per-channel absorption curve, then mixed
// toward the medium with the scalar distance visibility. This replaces the old
// pow(C, 1.0/4.4) -> mix -> pow(4.4) gamma round trip. Shafts stay a linear add.
vec3 solas_water_composite(vec3 linearColor, vec3 viewPos, float waterDistance, vec3 shafts,
                           vec2 interfaceUV, bool thinSheet) {
    if (thinSheet) {
        // Side interfaces have already transported the camera's short water
        // leg. Other rays (e.g. the floor below a waterfall) still need it once.
        if (water_interface_is_side(water_interface_at(interfaceUV))) return linearColor;
        // Same incident-light colour as astra_sky_ambient(): the shared natural-look
        // gain (lib/color_controls.glsl) keeps the interface light on one hue. The
        // water material tint, absorption, fog and curve stay untouched.
        // Every input is a uniform, so the full-screen passes read the
        // value their vertex stage already prepared instead of rebuilding it here.
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END && defined ASTRA_WATER_FOG_FRAME_READ
        vec3 incident = waterInterfaceIncident;
        #else
        vec3 incident = solas_water_interface_incident();
        #endif
        return water_surface_medium(linearColor, min(length(viewPos), 1.0), incident);
    }
    vec4 fog = solas_water_fog(viewPos, waterDistance);
    vec3 absorbed = max(linearColor, vec3(0.0))
                  * astra_water_absorption_transmission(waterDistance);
    return mix(fog.rgb, absorbed, fog.a) + shafts;
}
// Solas composite14 and lib/post/tonemap defaults.
vec3 solas_water_tonemap_curve(vec3 color) {
    return ((color * (0.28 * color + 0.10 * 0.290) + 0.150 * 0.016)
        / (color * (0.28 * color + 0.290) + 0.150 * 0.350)) - 0.016 / 0.350;
}
vec3 solas_water_display(vec3 color) {
    // Slightly lower underwater exposure; retain the curve and its highlight shoulder.
    return pow(max(solas_water_tonemap_curve(color * 4.95) / solas_water_tonemap_curve(vec3(15.2)),
                   vec3(0.0)), vec3(1.0 / 2.2));
}
#endif
