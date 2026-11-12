#ifndef LIB_CLOUDS
#define LIB_CLOUDS

#include "/lib/common.glsl"
#include "/lib/sky.glsl"

// Procedural clouds: one slab at a fixed world height, from CLOUD_HEIGHT to
// CLOUD_HEIGHT + CLOUD_THICKNESS, marched along the view ray. The shapes
// come from value noise read out of the noise texture Iris provides.
//
// The slab stays where it is, so it can be flown into and over. The march
// starts where the ray enters the slab, or at the eye when the player is
// inside it, and ends where the ray leaves it or meets the scene.
//
// No uniforms are declared here; the callers pass what is needed, since most
// of them declare the same uniforms already and GLSL rejects a second
// declaration. The noise texture lives in common.glsl.

float nlCloudNoise(vec2 p) {
    return nlTexNoise(p);
}

// Each octave is turned against the last one, otherwise the lattice of the
// value noise shows through as rows of square puffs.
float nlCloudFbm(vec2 p, int octaves) {
    float sum = 0.0;
    float amp = 0.5;
    float norm = 0.0;
    mat2 rot = mat2(0.80, -0.60, 0.60, 0.80);
    for (int i = 0; i < 5; i++) {
        if (i >= octaves) break;
        sum  += nlCloudNoise(p) * amp;
        norm += amp;
        p = rot * p * 2.07 + vec2(13.7, 7.3);
        amp *= 0.5;
    }
    return sum / norm;
}

// Density at a point of the slab. h runs from 0 at the base to 1 at the top.
// Cumulus are flat underneath and round on top, so the coverage threshold
// climbs quickly below the lower quarter and slowly above it.
float nlCloudDensity(vec2 p, float h, int octaves) {
    // Large shapes first: they decide where a cloud is at all
    float shape = nlCloudFbm(p * (1.0 / 300.0), 3);
    // Summed octaves huddle around one half; spread them back out so the
    // coverage setting has the whole range to work with.
    shape = (shape - 0.5) * 2.6 + 0.5;

    float profile = h < 0.18 ? (0.18 - h) * 3.0 : (h - 0.18) * 0.70;
    float d = shape - (1.0 - CLOUD_AMOUNT) - profile;
    if (d < -0.30) return 0.0;

    // The finer octaves eat into the cloud, most of all where it is thin,
    // which turns a smooth blob into a heap of rounded puffs. Shifted with
    // height so the outline changes from the base to the top.
    float detail = nlCloudFbm(p * (1.0 / 70.0) + vec2(h * 1.7, -h * 1.1), octaves);
    detail = (detail - 0.5) * 2.4 + 0.5;
    d -= detail * mix(0.40, 0.18, nlSat(d * 3.0)) - 0.10;

    // Soft saturation: a hard clamp turns the inside of every cloud into one
    // flat value and the shading has nothing left to work with.
    float raw = max(d, 0.0) * 3.0;
    return raw * inversesqrt(raw * raw + 0.40);
}

// Returns premultiplied color in rgb and coverage in a.
// dir and the light directions are world space, camPos is cameraPosition.
// maxDist is how far the ray gets before it meets the scene; pass a large
// value for the open sky.
vec4 nlClouds(vec3 dir, vec3 sunDir, vec3 lightDir, vec3 camPos, float maxDist,
              float time, float rain, float dither, int steps) {
    float base = CLOUD_HEIGHT;
    float top  = CLOUD_HEIGHT + CLOUD_THICKNESS;
    float y = camPos.y;

    // Where the ray runs through the slab. horizon fades the layer out where
    // it turns into a thin band along the horizon, seen from below or above.
    float t0, t1, horizon;
    bool inside = false;
    if (y < base) {
        if (dir.y <= 0.0) return vec4(0.0);
        t0 = (base - y) / dir.y;
        t1 = (top - y) / dir.y;
        horizon = nlSat((dir.y - 0.015) * 14.0);
    } else if (y > top) {
        if (dir.y >= 0.0) return vec4(0.0);
        t0 = (top - y) / dir.y;
        t1 = (base - y) / dir.y;
        horizon = nlSat((-dir.y - 0.015) * 14.0);
    } else {
        inside = true;
        t0 = 0.0;
        t1 = dir.y >  0.001 ? (top - y) / dir.y
           : dir.y < -0.001 ? (base - y) / dir.y : 1e6;
        horizon = 1.0;
    }

    // Beyond this the layer is only a thin band on the horizon and the march
    // would stretch a handful of samples over many kilometres.
    if (t0 > min(9000.0, maxDist)) return vec4(0.0);
    t1 = min(min(t1, t0 + CLOUD_THICKNESS * 6.0), maxDist);

    float dt = (t1 - t0) / float(steps);
    vec2 wind = vec2(time * 2.2, time * 0.6) * CLOUD_SPEED;

    // Rain packs the sky full
    float amountBoost = rain * 0.30;

    float VoL = dot(dir, lightDir);
    // Silver lining towards the light, a softer lift away from it
    float phase = 0.80 + 2.4 * pow(max(VoL, 0.0), 6.0) + 0.35 * pow(max(VoL, 0.0), 1.5);

    vec3 lightCol = nlSunlightColor(sunDir, rain) * 0.30;

    // The shaded side takes its light from the sky: the dome overhead and the
    // bright band along the horizon, both seen from inside the cloud.
    vec3 skyUp  = nlGetSkyColor(vec3(0.0, 1.0, 0.0), sunDir, vec3(0.0), vec3(0.0), rain);
    vec3 skyHor = nlGetSkyColor(normalize(vec3(-sunDir.x, 0.05, -sunDir.z)), sunDir,
                                vec3(0.0), vec3(0.0), rain);
    vec3 ambCol = skyUp * 0.80 + skyHor * 0.30;
    // Seen from inside a cloud the sky is scattered many times over and
    // loses most of its color; a saturated noon horizon otherwise turns
    // every cloud base baby blue.
    ambCol = mix(vec3(nlLuma(ambCol)), ambCol, 0.45);

    // Two samples towards the light, near and far, measured from the sample
    vec2 lightStep = lightDir.xz / max(lightDir.y, 0.25) * CLOUD_THICKNESS;

    vec3 color = vec3(0.0);
    float trans = 1.0;

    for (int i = 0; i < 32; i++) {
        if (i >= steps || trans < 0.02) break;

        float x = (float(i) + dither) / float(steps);
        float t = t0 + dt * float(steps) * x;
        float ds = dt;
        // From inside, what is close decides what is seen: the samples are
        // packed near the eye and spread out with distance.
        if (inside) {
            t  = t0 + dt * float(steps) * x * x;
            ds = dt * 2.0 * x;
        }
        vec3 p = camPos + dir * t;
        float h = nlSat((p.y - base) / CLOUD_THICKNESS);
        vec2 xz = p.xz + wind;

        float d = nlCloudDensity(xz, h, 4);
        d = nlSat(d + amountBoost * (1.0 - h));
        if (d < 0.005) continue;

        // Light the cloud swallows before it arrives here. Thin edges let it
        // through, a thick core does not, and that contrast between a bright
        // rim and a darker middle is what gives the puffs their volume.
        float od = nlCloudDensity(xz + lightStep * 0.20, min(h + 0.20, 1.0), 2)
                 + nlCloudDensity(xz + lightStep * 0.55, min(h + 0.55, 1.0), 2);
        float lit = exp(-od * 1.3) * mix(0.45, 1.0, h);

        // Sunlit where the light gets in, sky lit where it does not. Mixed
        // rather than summed, so the sky does not wash a lit flank blue.
        // The upper part of a cloud scatters the light it gets many times
        // over and sends it out in every direction, which is why a cloud
        // deck seen from above glares white with the sun behind the viewer.
        // From below those tops are hidden behind the base anyway.
        float scatter = phase + 0.9 * h * h;
        vec3 sampleCol = mix(ambCol * mix(0.55, 1.0, h), lightCol * scatter, lit);

        float a = 1.0 - exp(-d * ds * 0.09);
        color += trans * a * sampleCol;
        trans *= 1.0 - a;
    }

    float alpha = 1.0 - trans;

    // Aerial perspective: distant clouds sink into the horizon haze
    vec3 skyHere = nlGetSkyColor(dir, sunDir, vec3(0.0), vec3(0.0), rain);
    float haze = 1.0 - exp(-t0 * 0.00022);
    color = mix(color, skyHere * alpha, haze);
    color *= CLOUD_BRIGHTNESS * (1.0 - rain * 0.35);

    return vec4(color, alpha) * horizon;
}

#endif
