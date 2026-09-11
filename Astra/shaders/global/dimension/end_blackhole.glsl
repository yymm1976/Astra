#ifndef ASTRA_END_BLACKHOLE_GLSL
#define ASTRA_END_BLACKHOLE_GLSL
// End black hole and star field.
//
// Ported from IterationT 3.2.0 by the IterationT authors:
//   shaders/Lib/IndividualFounctions/EndSky.glsl  (CalculateStars, WarpSpace,
//       RotateMatrix, Calculate3DNoise, CalculateCloudFBM, pcurve,
//       BlackHole_AccretionDisc_Stars)
//   shaders/Lib/Utilities.glsl                    (Blackbody, MiePhaseFunction,
//       InterleavedGradientNoise, curve/saturate/remapSaturate macros)
// Retrieved 2026-09-11 from the author's distribution
// (https://edge.forgecdn.net/files/6825/165/iterationT%203.2.0.zip).
//
// This replaced an earlier hand-written analytic model in end.glsl. The analytic version
// could not reproduce the reference's look because IterationT does not evaluate a lensing
// formula at all: it RAY-MARCHES (50 steps) and bends the ray toward the singularity at
// every step (WarpSpace), so the accretion disc is sampled properly on both passes and the
// background is warped continuously. That is where the arcs and the depth come from.
//
// Astra adapters (marked inline):
//   - noisetex is Astra's 256x256 texture; the reference samples its own 64x64 sheet.
//   - BlueNoiseTemproal() is a TAA lookup; Astra has no TAA, so the interleaved gradient
//     noise the reference also ships is used instead.
//   - worldShadowVector -> the End's stellar direction passed in by end.glsl.
//   - ASTRA_END_STAR_GAIN compensates for Astra's different exposure/tonemap chain; the
//     reference value is 1.0 (its maxLuminance is 0.04).
//
// License: IterationT ships no license file; treated as proprietary, same as the existing
// Refrax entries in THIRD-PARTY.md. Personal-use only, rewrite required before distribution.

#define bh_saturate(x) clamp(x, 0.0, 1.0)
#define bh_curve(x)    ((x) * (x) * (3.0 - 2.0 * (x)))

// Resolves to an effective peak star luminance of about 0.12 against Astra's End exposure.
const float ASTRA_END_STAR_GAIN = 3.0;

float bh_remapSaturate(float x, float e0, float e1) {
    return bh_saturate((x - e0) / (e1 - e0));
}

vec3 bh_Blackbody(float temperature) {
    // https://en.wikipedia.org/wiki/Planckian_locus
    const mat2x4 splineX = mat2x4(-0.2661293e9, -0.2343589e6, 0.8776956e3, 0.179910,
                                  -3.0258469e9,  2.1070479e6, 0.2226347e3, 0.240390);
    const mat3x4 splineY = mat3x4(-1.1063814, -1.34811020, 2.18555832, -0.20219683,
                                  -0.9549476, -1.37418593, 2.09137015, -0.16748867,
                                   3.0817580, -5.87338670, 3.75112997, -0.37001483);
    float rt = 1.0 / temperature;
    float rt2 = rt * rt;
    vec4 coeffX = vec4(rt2 * rt, rt2, rt, 1.0);
    float x = dot(coeffX, temperature < 4000.0 ? splineX[0] : splineX[1]);
    float x2 = x * x;
    vec4 coeffY = vec4(x2 * x, x2, x, 1.0);
    float z = 1.0 / dot(coeffY, temperature < 2222.0 ? splineY[0]
                             : temperature < 4000.0 ? splineY[1] : splineY[2]);
    vec3 xyz = vec3(x * z, 1.0, z);
    xyz.z -= xyz.x + 1.0;
    const mat3 xyzToSrgb = mat3( 3.24097, -0.96924,  0.05563,
                                -1.53738,  1.87597, -0.20398,
                                -0.49861,  0.04156,  1.05697);
    return max(xyzToSrgb * xyz, vec3(0.0));
}

float bh_InterleavedGradientNoise(vec2 c) {
    return fract(52.9829189 * fract(0.06711056 * c.x + 0.00583715 * c.y));
}

mat3 bh_RotateMatrix(float x, float y, float z) {
    mat3 matx = mat3(1.0, 0.0, 0.0,
                     0.0, cos(x), sin(x),
                     0.0, -sin(x), cos(x));
    mat3 maty = mat3(cos(y), 0.0, -sin(y),
                     0.0, 1.0, 0.0,
                     sin(y), 0.0, cos(y));
    mat3 matz = mat3(cos(z), sin(z), 0.0,
                     -sin(z), cos(z), 0.0,
                     0.0, 0.0, 1.0);
    return maty * matx * matz;
}

// Gravitational bending. This is the heart of the reference look: the direction is not
// computed once, it is pulled toward the singularity a little on every march step, so the
// disc's far side curves over the shadow and the background smears.
void bh_WarpSpace(inout vec3 eyevec, inout vec3 raypos) {
    vec3 origin = vec3(0.0, 0.0, 0.0);
    float singularityDist = distance(raypos, origin);
    float warpFactor = 1.0 / (singularityDist * singularityDist + 0.000001);
    vec3 singularityVector = normalize(origin - raypos);
    float warpAmount = 0.06;
    eyevec = normalize(eyevec + singularityVector * warpFactor * warpAmount);
}

// Astra adapter: the reference reads its 64x64 noisetex; Astra's is 256x256.
float bh_3DNoise(vec3 position) {
    vec3 p = floor(position);
    vec3 b = bh_curve(fract(position));
    vec2 uv = 17.0 * p.z + p.xy + b.xy;
    vec2 rg = textureLod(noisetex, (uv + 0.5) / float(noiseTextureResolution), 0.0).zx;
    return mix(rg.x, rg.y, b.z);
}

float bh_CloudFBM(vec3 position, vec3 shift) {
    const int octaves = 4;
    const float octAlpha = 0.87;
    const float octScale = 2.5;
    const float octShift = (octAlpha / octScale) / float(octaves);
    float accum = 0.0;
    float alpha = 0.5;
    for (int i = 0; i < octaves; i++) {
        accum += alpha * bh_3DNoise(position);
        position = (position + shift) * octScale;
        alpha *= octAlpha;
    }
    return accum + octShift;
}

float bh_pcurve(float x) {
    float x2 = x * x;
    return 12.207 * x2 * x2 * (1.0 - x);
}

// Star field, ported from the reference. Colours come from blackbody temperature, which is
// what gives the cool-blue / warm-amber spread rather than a single white tint.
vec3 astra_end_stars(vec3 worldDir) {
    float angleY = frameTimeCounter * 0.001;
    mat3 eyeRotationMatrixY = mat3(cos(angleY), 0, sin(angleY), 0, 1, 0,
                                   -sin(angleY), 0, cos(angleY));
    worldDir = eyeRotationMatrixY * worldDir;

    const float scale = 384.0;
    const float coverage = 0.007;
    const float maxLuminance = 0.04 * ASTRA_END_STAR_GAIN;
    const float minTemperature = 4000.0;
    const float maxTemperature = 8000.0;

    // Aligns the field to the sun axis, as the reference does.
    float cosine = dot(worldSunVector, vec3(0.0, 0.0, 1.0));
    vec3 axis = cross(worldSunVector, vec3(0.0, 0.0, 1.0));
    float cosecantSquared = 1.0 / max(dot(axis, axis), 1e-6);
    worldDir = cosine * worldDir + cross(axis, worldDir)
             + (cosecantSquared - cosecantSquared * cosine) * dot(axis, worldDir) * axis;

    vec3 p = worldDir * scale;
    ivec3 i = ivec3(floor(p));
    vec3 f = p - vec3(i);
    float r = dot(f - 0.5, f - 0.5);

    vec3 i3 = fract(vec3(i) * vec3(443.897, 441.423, 437.195));
    i3 += dot(i3, i3.yzx + 19.19);
    vec2 hash = fract((i3.xx + i3.yz) * i3.zy);
    hash.y = 2.0 * hash.y - 4.0 * hash.y * hash.y + 3.0 * hash.y * hash.y * hash.y;

    float c = bh_remapSaturate(hash.x, 1.0 - coverage, 1.0);
    return (maxLuminance * bh_remapSaturate(r, 0.25, 0.0) * c * c)
         * bh_Blackbody(mix(minTemperature, maxTemperature, hash.y));
}

// Marching black hole: stars + accretion disc + photon ring, occlusion handled by
// transmittance. `lightDir` is the End's stellar direction.
void astra_end_blackhole(inout vec3 color, vec3 rayDir, vec3 lightDir) {
    const float steps = 50.0;
    const float rSteps = 1.0 / steps;
    const float stepLength = 0.2;

    const float discRadius = 2.25;
    const float discWidth = 3.5;
    const float discInner = discRadius - discWidth * 0.5;

    // Astra adapter: no TAA, so use the interleaved gradient noise the reference also ships.
    float noise = bh_InterleavedGradientNoise(gl_FragCoord.xy);

    vec3 eye = -lightDir * 8.0;
    vec3 rayPos = eye + rayDir * 3.0;
    mat3 rotation = bh_RotateMatrix(0.1, 0.0, -0.35);

    vec3 result = vec3(0.0);
    float transmittance = 1.0;

    rayPos += rayDir * stepLength * noise;

    for (int i = 0; i < int(steps); i++) {
        if (transmittance < 0.0001) break;

        bh_WarpSpace(rayDir, rayPos);
        rayPos += rayDir * stepLength;

        {
            vec3 discPos = rotation * rayPos;
            float r = length(discPos);
            float pAngle = atan(-discPos.z, discPos.x);
            float h = discPos.y;

            float radialGradient = 1.0 - bh_saturate((r - discInner) / discWidth * 0.5);
            float dist = abs(h);
            float discThickness = 0.1 * radialGradient;

            float fr = abs(r - discInner) + 0.4;
            fr = fr * fr;
            float fade = fr * fr * 0.04;
            float bloomFactor = 1.0 / (h * h * 40.0 + fade + 0.00002);
            bloomFactor *= bh_saturate(2.0 - abs(dist) / discThickness);
            bloomFactor = bloomFactor * bloomFactor;

            float dr = bh_pcurve(radialGradient);
            float density = dr;
            density *= bh_saturate(1.0 - abs(dist) / discThickness);
            density = bh_saturate(density * 0.7);
            density = bh_saturate(density + bloomFactor * 0.1);

            if (density > 0.0001) {
                // Astra adaptation for "动态立体": the reference offers
                // ACCRETIONDISC_DETAIL_ALONG_LONGTITUDE, which folds the azimuth into the
                // noise coordinate (it ships that branch OFF). This switches it on AND
                // advances the azimuth at a Keplerian rate, omega ~ r^-1.5, so the inner
                // disc visibly outruns the outer one. Differential rotation is what makes
                // the disc read as a rotating three-dimensional body instead of a texture
                // sliding past; a uniform scroll would look like a conveyor belt.
                float kepler = frameTimeCounter * 0.55 * pow(max(r, 0.45), -1.5);
                vec3 discCoord = vec3(r, pAngle + kepler, h * 0.1) * 3.5;
                float fbm = bh_CloudFBM(discCoord, frameTimeCounter * vec3(0.0, 0.0, 0.05));
                fbm = fbm * fbm;
                fbm = fbm * fbm;

                density *= fbm * dr;

                float gr = 1.0 - radialGradient;
                gr = gr * gr;
                float glowStrength = 1.0 / (gr * gr * 400.0 + 0.002);
                vec3 glow = bh_Blackbody(2700.0 + glowStrength * 50.0) * glowStrength;

                glow *= sin(pAngle - 1.07) * 0.75 + 1.0;

                float stepTransmittance = exp2(-density * 7.0);
                float integral = 1.0 - stepTransmittance;
                transmittance *= stepTransmittance;

                result += integral * transmittance * glow;
            }

            // Thin blue-white photon ring: a torus of very small tube radius rendered as a
            // bloom disc. This is the reference's ring, not an analytic glow.
            vec2 t = vec2(1.0, 0.01);
            float torusDist = length(length(discPos + vec3(0.0, -0.05, 0.0)) - t);
            float bloomDisc = 1.0 / (pow(torusDist, 3.5) + 0.001);
            vec3 col = bh_Blackbody(12000.0);
            bloomDisc *= step(0.5, r);
            result += col * bloomDisc * 0.1 * transmittance;
        }
    }
    result *= rSteps;

    color += astra_end_stars(rayDir);

    // The hole occludes the background (nebula included), then its own light is added.
    color *= transmittance;
    color += result;
}

#endif
