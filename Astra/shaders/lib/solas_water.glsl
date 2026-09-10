#ifndef ASTRA_SOLAS_WATER_GLSL
#define ASTRA_SOLAS_WATER_GLSL
#include "/lib/transforms.glsl"
// Adapted from Solas V2.2b by Septonious: common.glsl, waterFog.glsl,
// color/lightColor.glsl. Source supplied locally; see THIRD-PARTY.md.
// Astra adapters: prefixed names, existing world sun, linear scene boundary.
const vec3 solasWaterSqrt = vec3(115.0, 200.0, 250.0) / 255.0 * 0.80;
const vec3 solasWeather = vec3(175.0, 185.0, 255.0) / 255.0 * 0.60;
const vec3 solasMinLightSqrt = vec3(125.0, 130.0, 135.0) * (0.40 / 255.0);
const vec3 solasMinLight = solasMinLightSqrt * solasMinLightSqrt * 0.1;
uniform float wetness;
uniform float astraSolasTimeBrightness;
uniform float astraSolasShadowFade;
uniform float astraSolasTimeAngle;

float solas_sun_visibility() {
    return clamp(worldSunVector.y + 0.1, 0.0, 0.25) * 4.0;
}
void solas_water_lighting(out vec3 ambient, out vec3 direct, bool terrain) {
    float time = astraSolasTimeBrightness;
    float t = mix(mix(25.0, 47.5, sqrt(time)), 57.5, time * time);
    vec3 sun = vec3(1.0, clamp(0.390081578 * log(t) - 0.631841443, 0.0, 1.0),
                        clamp(0.543206789 * log(t - 10.0) - 1.196254089, 0.0, 1.0));
    vec3 night = vec3(clamp(1.292936186 * pow(57.5, -0.133204759), 0.0, 1.0),
                     clamp(1.129890860 * pow(57.5, -0.075514849), 0.0, 1.0), 1.0);
    float intensity = terrain ? mix(mix(1.69, 2.25, sqrt(time)), 2.25, time)
                              : mix(mix(1.3, 1.5, sqrt(time)), 1.5, time);
    sun = normalize(mix(pow((sun + 0.055) / 1.055, vec3(2.2)), sun / 12.92,
                         step(sun, vec3(0.04045)))) * intensity;
    night = mix(pow((night + 0.055) / 1.055, vec3(2.2)), night / 12.92,
                step(night, vec3(0.04045))) * 0.3;
    float day = solas_sun_visibility();
    vec3 raw = mix(night, mix(sun, normalize(skyColor + 0.0001), 0.1), day * day);
    vec3 lightSqrt = mix(raw, dot(raw, vec3(0.299, 0.587, 0.114)) * solasWeather, wetness * 0.5);
    direct = lightSqrt * lightSqrt;
    float ambientIntensity = mix(0.6, mix(0.9, 1.2, time), day * day);
    vec3 ambientColor = mix(night,
        mix(raw, normalize(skyColor + 0.0001), 0.6)
        * normalize(mix(vec3(1.0), skyColor, 0.6) + 0.0001), day * day);
    vec3 ambientRaw = pow(max(ambientColor, vec3(0.0)), vec3(0.75)) * 0.5 * ambientIntensity;
    ambientRaw = mix(ambientRaw, dot(ambientRaw, vec3(0.299, 0.587, 0.114)) * solasWeather, wetness * 0.5);
    ambient = ambientRaw * ambientRaw;
}
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

vec4 solas_water_fog(vec3 viewPos) {
    float density = UNDERWATER_FOG_DENSITY / 40.0;
    float fogAmount = 1.0 - exp(-6.0 * length(viewPos) * 0.01 * density);
    vec3 fog = mix(mix(solasWaterSqrt * solasWaterSqrt,
                       normalize(fogColor + 0.00001) * 0.5, 0.25),
                   solasWeather * 0.25, wetness * 0.25);
    float eyeSky = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
    vec3 lightDir = normalize(view_player(lightVector));
    vec3 ray = normalize(view_player(viewPos));
    float glare = clamp(dot(ray, lightDir) * astraSolasShadowFade * 0.5 + 0.5, 0.0, 1.0);
    glare = 0.01 / (1.0 - 0.99 * glare) - 0.01;
    fog *= (0.1 + solas_sun_visibility() * 0.4)
         * ((0.5 + 0.5 * eyeSky) + glare * 16.0 * astraSolasTimeBrightness * eyeSky);
    fog *= 1.0 - clamp(blindness, 0.0, 1.0);
    return vec4(fog, fogAmount);
}
// Solas stores the pre-composite scene in gamma 2.2, blends fog in sqrt space,
// then adds VL before decoding to linear. Keep those operations in that domain.
vec3 solas_water_composite(vec3 linearColor, vec3 viewPos, vec3 shafts) {
    vec3 color = pow(max(linearColor, vec3(0.0)), vec3(1.0 / 2.2));
    vec4 fog = solas_water_fog(viewPos);
    color = mix(sqrt(color), sqrt(max(fog.rgb, vec3(0.0))), fog.a);
    color = color * color + shafts;
    return pow(max(color, vec3(0.0)), vec3(2.2));
}
// Solas composite14 and lib/post/tonemap defaults.
vec3 solas_water_tonemap_curve(vec3 color) {
    return ((color * (0.28 * color + 0.10 * 0.290) + 0.150 * 0.016)
        / (color * (0.28 * color + 0.290) + 0.150 * 0.350)) - 0.016 / 0.350;
}
vec3 solas_water_display(vec3 color) {
    return pow(max(solas_water_tonemap_curve(color * 4.7) / solas_water_tonemap_curve(vec3(15.2)),
                   vec3(0.0)), vec3(1.0 / 2.2));
}
#endif
