#ifndef ASTRA_SOLAS_WATER_GLSL
#define ASTRA_SOLAS_WATER_GLSL
// Adapted from Solas V2.2b by Septonious: common.glsl, waterFog.glsl,
// color/lightColor.glsl. Source supplied locally; see THIRD-PARTY.md.
// Astra adapters: prefixed names, existing world sun, linear scene boundary.
const vec3 solasWaterSqrt = vec3(115.0, 200.0, 250.0) / 255.0 * 0.80;
const vec3 solasWeather = vec3(175.0, 185.0, 255.0) / 255.0 * 0.60;
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
    vec3 lightSqrt = mix(raw, dot(raw, vec3(0.299, 0.587, 0.114)) * solasWeather, rainStrength * 0.5);
    direct = lightSqrt * lightSqrt;
    float ambientIntensity = mix(0.6, mix(0.9, 1.2, time), day * day);
    vec3 ambientColor = mix(night,
        mix(raw, normalize(skyColor + 0.0001), 0.6)
        * normalize(mix(vec3(1.0), skyColor, 0.6) + 0.0001), day * day);
    vec3 ambientRaw = pow(max(ambientColor, vec3(0.0)), vec3(0.75)) * 0.5 * ambientIntensity;
    ambientRaw = mix(ambientRaw, dot(ambientRaw, vec3(0.299, 0.587, 0.114)) * solasWeather, rainStrength * 0.5);
    ambient = ambientRaw * ambientRaw;
}
vec4 solas_water_fog(vec3 viewPos) {
    float density = UNDERWATER_FOG_DENSITY / 40.0;
    float fogAmount = 1.0 - exp(-6.0 * length(viewPos) * 0.01 * density);
    vec3 fog = mix(mix(solasWaterSqrt * solasWaterSqrt,
                       normalize(fogColor + 0.00001) * 0.5, 0.25),
                   solasWeather * 0.25, rainStrength * 0.25);
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
