#ifndef ASTRA_GLOBAL_ATMOSPHERE_STARS_GLSL
#define ASTRA_GLOBAL_ATMOSPHERE_STARS_GLSL

// Complementary r5.9 (Reimagined) provenance retained: spherical projection,
// horizon / sun-moon exclusion and weather / dusk visibility envelopes.
// Astra's integer catalogue, overlapping charts and colour / twinkle below
// replace the former three sine hashes and frameTimeCounter position drift.
// Photon / Bliss informed the stable four-corner reconstruction; their shader
// functions and blackbody implementation are not copied here. See THIRD-PARTY.md.

#include "/global/atmosphere/sky_gradient.glsl"

#if STAR_AMOUNT == 1
const float ASTRA_MILKY_GAIN = (MILKY_WAY_BRIGHTNESS * 0.01) * 0.65;
#else
const float ASTRA_MILKY_GAIN = MILKY_WAY_BRIGHTNESS * 0.01;
#endif

uint astra_star_hash(ivec2 cell, uint salt) {
    uint h = uint(cell.x) * 1597334677u ^ uint(cell.y) * 3812015801u ^ salt;
    h = (h ^ (h >> 15u)) * 2246822519u;
    h = (h ^ (h >> 13u)) * 3266489917u;
    return h ^ (h >> 16u);
}

vec3 astra_star_cell(ivec2 cell, uint salt, float galaxyDensity) {
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
    float flux;
    if (draw > 1.0 - coverage) {
        float rank = (draw - (1.0 - coverage)) / coverage;
        // Keep the original catalogue's rank, colour and bright tail unchanged.
        flux = 0.95 * pow4(rank) * (1.0 + 0.35 * smoothstep(0.985, 1.0, rank));
    } else {
        #if MILKY_WAY_BRIGHTNESS > 0
        // Additional fixed candidates come from the SAME draw, with no second
        // chart or position lookup. Density only fades their flux, never their rank.
        #if STAR_AMOUNT == 1
        const float extraCoverage = coverage;
        #else
        const float extraCoverage = coverage * 3.0;
        #endif
        if (galaxyDensity <= 0.0 || draw <= 1.0 - coverage - extraCoverage)
            return vec3(0.0);
        float rank = (draw - (1.0 - coverage - extraCoverage)) / extraCoverage;
        flux = 0.10 * pow4(rank) * galaxyDensity * ASTRA_MILKY_GAIN;
        // The unused low eight seed bits give each faint star its own colour,
        // without another catalogue draw. Constant palettes share luminance, so
        // interpolation needs no pixel-local division or temperature fit.
        const vec3 luma = vec3(0.2126,0.7152,0.0722);
        const vec3 warm = vec3(1.0,0.68,0.40) * (0.90/dot(vec3(1.0,0.68,0.40),luma));
        const vec3 white = vec3(0.95,0.94,1.0) * (0.90/dot(vec3(0.95,0.94,1.0),luma));
        const vec3 blue = vec3(0.50,0.73,1.0) * (0.90/dot(vec3(0.50,0.73,1.0),luma));
        float tint = float(seed & 255u) * (1.0/255.0);
        vec3 faintColour = tint < 0.5
            ? mix(warm,white,tint*2.0)
            : mix(white,blue,tint*2.0-1.0);
        return faintColour * flux;
        #else
        return vec3(0.0);
        #endif
    }
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

vec3 astra_star_chart(vec2 coord, uint salt, float galaxyDensity) {
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
    // The circular support excludes some corners of the square footprint.
    // Zero-weight corners contribute exactly nothing and need no catalogue work.
    vec3 stars = vec3(0.0);
    if (weights.x > 0.0) stars += astra_star_cell(cell,salt,galaxyDensity)*weights.x;
    if (weights.y > 0.0) stars += astra_star_cell(cell+ivec2(1,0),salt,galaxyDensity)*weights.y;
    if (weights.z > 0.0) stars += astra_star_cell(cell+ivec2(0,1),salt,galaxyDensity)*weights.z;
    if (weights.w > 0.0) stars += astra_star_cell(cell+ivec2(1,1),salt,galaxyDensity)*weights.w;
    return stars;
}

vec3 astra_milky_way(vec3 celestial, out float stellarDensity) {
    stellarDensity = 0.0;
    #if MILKY_WAY_BRIGHTNESS == 0
    return vec3(0.0);
    #else
    // A low-frequency celestial band shares the existing noise texture. Only
    // visible night-sky rays inside the band pay these two lookups; no new march.
    const vec3 pole = normalize(vec3(0.42, 0.34, 0.84));
    float signedLatitude = dot(celestial, pole);
    float latitude = abs(signedLatitude);
    float band = 1.0 - smoothstep(0.035, 0.22, latitude);
    if (band <= 0.0) return vec3(0.0);
    const vec3 centreHint = vec3(-0.72, 0.18, 0.57);
    const vec3 centre = normalize(centreHint - pole * dot(centreHint,pole));
    const vec3 alongBand = cross(pole,centre);
    // Longitude remains well-conditioned inside this equatorial band. A linear
    // projection of the sphere folds and collapses one tangent into streaks.
    // One longitude period spans exactly one REPEAT texture period, including
    // the integer-scaled detail octave, so its seam has matching samples.
    float longitude = atan(dot(celestial,alongBand),dot(celestial,centre))
                    * (0.5/3.14159265);
    vec2 coordinate = vec2(longitude,signedLatitude*1.5);
    // R/G contain spatially coherent fields; B is near-uncorrelated texel noise
    // and cannot describe broad nebula structure. Keep the same lookup budget.
    float broad = clamp(textureLod(solasWaterNoise,coordinate+vec2(0.17,0.41),0.0).r
                        *1.5-0.2,0.0,1.0);
    float structure = 0.35 + 0.65 * smoothstep(0.20, 0.80, broad);
    float centreWeight = pow4(max(dot(celestial,centre),0.0));
    float core = 1.0 - smoothstep(0.012, 0.065, latitude);
    float dust = 0.0;
    float roseCloud = 0.0;
    // Reuse the core's existing detail for rose-coloured knots beside the dust.
    // The wider band keeps its original broad structure with one lookup.
    if (core > 0.0) {
        float detail = clamp(textureLod(solasWaterNoise,coordinate*3.0+vec2(0.53,0.11),0.0).g
                             *1.8,0.0,1.0);
        dust = core * (1.0 - smoothstep(0.28, 0.68, detail)) * 0.70;
        roseCloud = core * smoothstep(0.58,0.85,detail);
    }
    stellarDensity = band * structure * (1.0 - dust);
    // Broad blue/violet structure, local rose knots and a golden central bulge.
    // Each constant palette is normalised at compile time to the old layer's
    // luminance. Convex colour blends preserve its light budget, not its hue.
    const vec3 luma = vec3(0.2126,0.7152,0.0722);
    const vec3 blue = vec3(0.24,0.30,0.58) * (0.277272/dot(vec3(0.24,0.30,0.58),luma));
    const vec3 violet = vec3(0.48,0.19,0.55) * (0.277272/dot(vec3(0.48,0.19,0.55),luma));
    const vec3 rose = vec3(0.60,0.19,0.31) * (0.277272/dot(vec3(0.60,0.19,0.31),luma));
    const vec3 gold = vec3(0.12,0.075,0.025) * (0.072447/dot(vec3(0.12,0.075,0.025),luma));
    vec3 bandColour = mix(blue,violet,broad);
    bandColour = mix(bandColour,rose,roseCloud*(0.35+0.65*centreWeight));
    // At 100%, the unoccluded coefficient ceiling is about 0.35 Rec.709 luminance,
    // not an assertion about the composited sky or its displayed brightness.
    return (bandColour * stellarDensity * (0.65 + 0.35*centreWeight)
          + gold * core * broad * (0.30 + 0.70*centreWeight)
            * (1.0 - dust)) * ASTRA_MILKY_GAIN;
    #endif
}

vec3 astra_star_field(vec3 worldDir, out float pointStars, out float galaxyReactive) {
    pointStars = 0.0;
    galaxyReactive = 0.0;
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
        float galaxyDensity;
        vec3 galaxy = astra_milky_way(celestial,galaxyDensity);
        float radial = length(celestial.xy);
        // The old upper-only projection is singular when rotated below its
        // equator. Two spherical charts overlap smoothly across a fixed band.
        // Only the band evaluates both; each pole uses its well-defined chart.
        float northWeight = smoothstep(-0.12, 0.12, celestial.z);
        vec3 stars = vec3(0.0);
        if (celestial.z > -0.12)
            stars += astra_star_chart(celestial.xy / (celestial.z + 0.5 * radial),
                                      19349663u,galaxyDensity) * northWeight;
        if (celestial.z < 0.12)
            stars += astra_star_chart(celestial.xy / (-celestial.z + 0.5 * radial),
                                      83492791u,galaxyDensity) * (1.0 - northWeight);
        pointStars = max(stars.r, max(stars.g, stars.b));
        if (pointStars <= 0.0 && max(galaxy.r, max(galaxy.g, galaxy.b)) <= 0.0)
            return vec3(0.0);
        pointStars *= visibility;
        // Keep some history for this smooth layer, but shorten it locally as the
        // celestial frame moves. Point stars retain their existing full reaction.
        galaxyReactive = 0.30 * galaxyDensity * min(ASTRA_MILKY_GAIN,1.0) * visibility;
        return (stars + galaxy) * visibility;
    #endif
}

vec3 astra_star_field(vec3 worldDir) {
    float pointStars;
    float galaxyReactive;
    return astra_star_field(worldDir, pointStars, galaxyReactive);
}

#endif
