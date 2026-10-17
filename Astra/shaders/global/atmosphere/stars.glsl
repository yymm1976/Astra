#ifndef ASTRA_GLOBAL_ATMOSPHERE_STARS_GLSL
#define ASTRA_GLOBAL_ATMOSPHERE_STARS_GLSL

// Complementary r5.9 (Reimagined) provenance retained: spherical projection,
// horizon / sun-moon exclusion and weather / dusk visibility envelopes.
// Astra's integer catalogue, overlapping charts and colour / twinkle below
// replace the former three sine hashes and frameTimeCounter position drift.
// Photon / Bliss informed the stable four-corner reconstruction; their shader
// functions and blackbody implementation are not copied here. See THIRD-PARTY.md.

#include "/global/atmosphere/sky_gradient.glsl"

uint astra_star_hash(ivec2 cell, uint salt) {
    uint h = uint(cell.x) * 1597334677u ^ uint(cell.y) * 3812015801u ^ salt;
    h = (h ^ (h >> 15u)) * 2246822519u;
    h = (h ^ (h >> 13u)) * 3266489917u;
    return h ^ (h >> 16u);
}

vec3 astra_star_cell(ivec2 cell, uint salt) {
    uint seed = astra_star_hash(cell, salt);
    float draw = float(seed >> 8u) * (1.0 / 16777216.0);
    // Default occupancy approximates the former product-of-three > 0.7 field.
    #if STAR_AMOUNT == 1
        const float coverage = 0.004;
    #elif STAR_AMOUNT == 3
        const float coverage = 0.009;
    #elif STAR_AMOUNT == 4
        const float coverage = 0.014;
    #else
        const float coverage = 0.0058;
    #endif
    if (draw <= 1.0 - coverage) return vec3(0.0);

    float rank = (draw - (1.0 - coverage)) / coverage;
    // A sparse bright tail shares the catalogue lookup with the small stars.
    float flux = 0.95 * pow4(rank) * (1.0 + 0.35 * smoothstep(0.985, 1.0, rank));
    uint detail = astra_star_hash(cell, seed ^ 277803737u);
    float temperature = float(detail & 255u) * (1.0 / 255.0);
    // Restrained colour-temperature palette, avoiding a per-star blackbody fit.
    vec3 warm = vec3(1.0, 0.86, 0.72);
    vec3 neutral = vec3(0.90, 0.95, 1.0);
    vec3 cool = vec3(0.75, 0.86, 1.0);
    vec3 colour = temperature < 0.5
        ? mix(warm, neutral, temperature * 2.0)
        : mix(neutral, cool, temperature * 2.0 - 1.0);
    colour *= 0.90 / dot(colour, vec3(0.2126, 0.7152, 0.0722));
    // Random phase and amplitude per star, with the time-only sin/cos on CPU.
    vec2 phase = vec2(float((detail >> 8u) & 255u), float((detail >> 16u) & 255u))
               * (2.0 / 255.0) - 1.0;
    float twinkle = 1.0 + 0.035 * dot(astraStarTwinkle, phase);
    return colour * (flux * twinkle);
}

vec3 astra_star_chart(vec2 coord, uint salt) {
    vec2 grid = coord * 204.8;
    ivec2 cell = ivec2(floor(grid));
    vec2 f = fract(grid);
    vec4 dx = vec4(f.x,f.x-1.0,f.x,f.x-1.0);
    vec4 dy = vec4(f.y,f.y,f.y-1.0,f.y-1.0);
    vec4 support = max(vec4(1.0)-dx*dx-dy*dy,vec4(0.0));
    vec4 broad = support*support;
    vec4 core = broad*broad*broad;
    // Compact round points with a tight core and faint halo. Each radial
    // profile has unit integral, preserving catalogue flux and star count.
    // Value and slope reach zero before a star leaves this four-corner cell.
    vec4 weights = (0.85*7.0/3.14159265)*core
                 +(0.15*3.0/3.14159265)*broad;
    return astra_star_cell(cell,salt)*weights.x
         + astra_star_cell(cell+ivec2(1,0),salt)*weights.y
         + astra_star_cell(cell+ivec2(0,1),salt)*weights.z
         + astra_star_cell(cell+ivec2(1,1),salt)*weights.w;
}

vec3 astra_milky_way(vec3 celestial) {
    // A low-frequency celestial band shares the existing noise texture. Only
    // visible night-sky rays inside the band pay these two lookups; no new march.
    const vec3 pole = normalize(vec3(0.42, 0.34, 0.84));
    float latitude = abs(dot(celestial, pole));
    float band = 1.0 - smoothstep(0.035, 0.22, latitude);
    if (band <= 0.0) return vec3(0.0);
    vec2 coordinate = celestial.xy * vec2(0.63, 0.84) + celestial.z * vec2(0.27, -0.19);
    float broad = textureLod(solasWaterNoise, coordinate + vec2(0.17, 0.41), 0.0).b;
    float structure = 0.35 + 0.65 * smoothstep(0.20, 0.80, broad);
    float core = 1.0 - smoothstep(0.012, 0.065, latitude);
    float dust = 0.0;
    // The detail octave affects dust only inside the narrow galactic core.
    // The wider band keeps its original broad structure with one lookup.
    if (core > 0.0) {
        float detail = textureLod(solasWaterNoise, coordinate * 3.0 + vec2(0.53, 0.11), 0.0).b;
        dust = core * (1.0 - smoothstep(0.28, 0.68, detail)) * 0.50;
    }
    return (vec3(0.009, 0.012, 0.020) * band * structure
          + vec3(0.004, 0.0038, 0.0032) * core * broad) * (1.0 - dust);
}

vec3 astra_star_field(vec3 worldDir, out float pointStars) {
    pointStars = 0.0;
    #if STAR_AMOUNT == 0
        return vec3(0.0);
    #else
        if (astraStarVisibility <= 0.0) return vec3(0.0);
        vec3 nDir = normalize(worldDir);
        if (nDir.y <= 0.0) return vec3(0.0);
        // Actual sun direction avoids the shadow-light sun/moon handoff. All
        // three basis vectors are CPU values; no pixel-local rotation trig.
        vec3 celestial = vec3(dot(nDir, astraStarTangent),
                              dot(nDir, astraSunDirection),
                              dot(nDir, astraStarAxis));
        // The disc exclusion multiplies both the catalogue and the galactic band.
        // Rays with exactly zero visibility need neither hashes nor noise fetches.
        float discExclusion = max0(1.0 - pow100(abs(celestial.y) * 1.002));
        float visibility = min1(nDir.y * 3.0) * discExclusion * astraStarVisibility;
        if (visibility <= 0.0) return vec3(0.0);
        float radial = length(celestial.xy);
        // The old upper-only projection is singular when rotated below its
        // equator. Two spherical charts overlap smoothly across a fixed band.
        // Only the band evaluates both; each pole uses its well-defined chart.
        float northWeight = smoothstep(-0.12, 0.12, celestial.z);
        vec3 stars = vec3(0.0);
        if (celestial.z > -0.12)
            stars += astra_star_chart(celestial.xy / (celestial.z + 0.5 * radial),
                                      19349663u) * northWeight;
        if (celestial.z < 0.12)
            stars += astra_star_chart(celestial.xy / (-celestial.z + 0.5 * radial),
                                      83492791u) * (1.0 - northWeight);
        pointStars = max(stars.r, max(stars.g, stars.b));
        vec3 galaxy = astra_milky_way(celestial);
        if (pointStars <= 0.0 && max(galaxy.r, max(galaxy.g, galaxy.b)) <= 0.0)
            return vec3(0.0);
        pointStars *= visibility;
        return (stars + galaxy) * visibility;
    #endif
}

vec3 astra_star_field(vec3 worldDir) {
    float pointStars;
    return astra_star_field(worldDir, pointStars);
}

#endif
