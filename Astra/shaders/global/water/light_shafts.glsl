// Adapted from Solas V2.2b volumetricLight.glsl and composite3/5 by Septonious.
// See THIRD-PARTY.md. Retains Solas compressed storage and coloured shadows.
// Current march follows ITT 3.2's short water volume, refracted-light phase,
// caustic contrast and distance attenuation, adapted to Astra's shadow carrier.
// Independent volume history never accumulates scene colour.
#ifndef ASTRA_GLOBAL_WATER_LIGHT_SHAFTS_GLSL
#define ASTRA_GLOBAL_WATER_LIGHT_SHAFTS_GLSL
#include "/lib/transforms.glsl"
uniform sampler2D colortex3;
const float WATER_SHAFT_MAX_DISTANCE = 128.0;

vec3 water_shafts_view(vec2 uv, out float rayLength) {
    ivec2 size = textureSize(depthtex0, 0);
    ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    float depth = texelFetch(depthtex0, pixel, 0).r;
    if (depth < 0.999999) {
        uint flags = uint(round(texelFetch(colortex3, pixel, 0).r * 255.0));
        if ((flags & 128u) != 0u && depth == texelFetch(depthtex1, pixel, 0).r)
            depth = ((depth * 2.0 - 1.0) / MC_HAND_DEPTH) * 0.5 + 0.5;
    }
    vec2 pixelUV = (vec2(pixel) + 0.5) / vec2(size);
    vec3 viewPos = screen_view(vec3(pixelUV, min(depth, 0.999999)));
    rayLength = min(length(viewPos), WATER_SHAFT_MAX_DISTANCE);
    return viewPos;
}

#ifdef ASTRA_SHAFT_MARCH_PASS
#include "/lib/dither.glsl"
// Cornette-Shanks phase, following ITT 3.2 Utilities::MiePhaseFunction.
// Expressed relative to isotropic scattering; the forward peak stays bounded.
float water_shaft_phase(vec3 ray, vec3 source) {
    float cosine = clamp(dot(ray, source), -1.0, 1.0);
    float base = max(1.49-1.4*cosine, 0.09);
    float phase = (1.5*0.51/2.49)*(1.0+cosine*cosine)/(base*sqrt(base));
    return 0.20+0.80*min(phase, 2.5);
}
vec4 water_shafts_march(vec2 uv, out vec3 viewPos, out float marchLength) {
    float rayLength;
    viewPos = water_shafts_view(uv, rayLength);
    marchLength = min(rayLength, astraWaterShaftRange);
    if (rayLength <= 0.001) return vec4(vec3(0.0), rayLength / 128.0);
    float sourceStrength = mix(float(MOONLIGHT_STRENGTH), float(SUNLIGHT_STRENGTH), astraSunSource) * 0.01;
    float visibility = astraSolasShadowFade * (1.0 - wetness*0.75) * sourceStrength;
    // The display stage attenuates the complete scene for Darkness once.
    visibility *= (1.0 - clamp(blindness, 0.0, 1.0));
    if (visibility <= 0.0)
        return vec4(vec3(0.0), rayLength / 128.0);
    float viewDistance = length(viewPos);
    float inverseViewDistance = 1.0/max(viewDistance,0.0001);
    vec3 worldDelta = view_player(viewPos);
    vec3 ray = normalize(worldDelta);
    vec3 lightDir = astra_world_light_direction();
    vec3 waterLightDir = -refract(-lightDir, vec3(0.0, 1.0, 0.0), 1.0/WATER_IOR);
    vec2 flatSlope = waterLightDir.xz/max(waterLightDir.y, 0.35);
    vec3 worldOrigin = gbufferModelViewInverse[3].xyz;
    vec4 waterState = water_volume_state();
    bool knownSurface = waterState.a > 0.5;
    float surfaceY = cameraPosition.y+worldOrigin.y;
    float originDepth = 0.0;
    if (knownSurface) {
        surfaceY = water_unpack_surface_height(waterState.rg);
        originDepth = max(surfaceY-cameraPosition.y-worldOrigin.y, 0.0);
        // An upward view can end in air. Stop at the known local interface,
        // so refracted-light evaluation stays inside the water volume.
        if (worldDelta.y > 0.0001)
            marchLength = min(marchLength, originDepth*viewDistance/worldDelta.y);
        if (marchLength <= 0.001) return vec4(vec3(0.0), rayLength/128.0);
    }
    vec4 shadowOrigin = shadowProjection*(shadowModelView*vec4(worldOrigin,1.0));
    vec4 shadowDelta = shadowProjection*vec4(mat3(shadowModelView)*worldDelta,0.0);
    vec4 shadowBendX = shadowProjection*shadowModelView[0];
    vec4 shadowBendZ = shadowProjection*shadowModelView[2];
    vec4 entryOrigin = shadowOrigin, entryDelta = shadowDelta;
    if (knownSurface) {
        vec3 flatUp = vec3(flatSlope.x,1.0,flatSlope.y);
        entryOrigin = shadowProjection*(shadowModelView*vec4(worldOrigin+flatUp*originDepth,1.0));
        entryDelta = shadowProjection*vec4(mat3(shadowModelView)*(worldDelta-flatUp*worldDelta.y),0.0);
    }

    float count = float(UNDERWATER_SHAFT_SAMPLES);
    // IGN distributes ray offsets across nearby pixels for spatial reconstruction.
    // Independent history still advances the pattern when scene TAA is disabled.
    float rayOffset = ign(gl_FragCoord.xy, true);
    vec3 integral = vec3(0.0);
    // Evenly cover a short visible segment, like ITT's 40-block volume. The
    // existing 4/7/10 sample budgets and independent history stay in use.
    float stepLength = marchLength / count;
    // Attenuate the additive shaft path, not the scene a second time. Red
    // fades faster than green/blue; recurrent transport avoids per-step exp.
    vec3 extinction = vec3(0.035, 0.012, 0.010) * (UNDERWATER_FOG_DENSITY / 40.0)
                    + vec3(astra_water_haze_density()*0.5);
    vec3 transmission = exp(-extinction * (rayOffset*stepLength));
    vec3 stepTransmission = exp(-extinction * stepLength);
    vec2 shadowSize = vec2(textureSize(shadowtex0, 0));
    ivec2 lensSize = textureSize(shadowcolor0,0);
    for (int i = 0; i < UNDERWATER_SHAFT_SAMPLES; ++i) {
        float currentDist = (float(i) + rayOffset) * stepLength;
        vec3 sampleTransmission = transmission;
        transmission *= stepTransmission;
        float fraction = currentDist * inverseViewDistance;
        vec3 point = worldOrigin + worldDelta * fraction;
        vec4 shadowClip = shadowOrigin + shadowDelta * fraction;
        // ITT projects every volume sample along the refracted source to its
        // animated wave-normal field. Reuse our water caster cache for that
        // field, instead of rebuilding noise or sharing one normal for the ray.
        vec4 entryClip = entryOrigin+entryDelta*fraction;
        vec3 entryPos = distort(entryClip.xyz/entryClip.w)*0.5+0.5;
        if (shadow_uv_coverage(entryPos) <= 0.0) continue;
        vec2 lensLocation = entryPos.xy*vec2(lensSize)-0.5;
        ivec2 lensBase = ivec2(floor(lensLocation));
        vec4 lensWeights = shadow_corner_weights(fract(lensLocation));
        vec2 waveSlope = vec2(0.0);
        float focusedLight = 0.0, waterCoverage = 0.0, entryHeight = 0.0;
        for (int corner = 0; corner < 4; ++corner) {
            float weight = lensWeights[corner];
            if (weight <= 0.0) continue;
            ivec2 pixel = clamp(lensBase+ivec2(corner & 1,corner >> 1),ivec2(0),lensSize-1);
            vec4 lens = texelFetch(shadowcolor0,pixel,0);
            if (lens.r >= WATER_HEIGHT_NONE) continue;
            waterCoverage += weight;
            waveSlope += lens.gb*weight;
            // The valid local interface already supplies the surface height.
            // Caster height is needed only by the missing-interface fallback.
            if (!knownSurface) entryHeight += decode_water_height(lens.r)*weight;
            float focus = max(lens.a,0.0);
            focusedLight += min(focus*focus*focus,4.0)*weight;
        }
        if (waterCoverage <= 0.0) continue;
        waveSlope /= waterCoverage;
        float localSurfaceY = knownSurface ? surfaceY : entryHeight/waterCoverage;
        float waterDepth = max(localSurfaceY-cameraPosition.y-point.y,0.0);
        vec3 waveNormal = normalize(vec3(-waveSlope.x,1.0,-waveSlope.y));
        vec3 bentLightDir = -refract(-lightDir,waveNormal,1.0/WATER_IOR);
        vec2 bend = bentLightDir.xz/max(bentLightDir.y,0.35)-flatSlope;
        shadowClip += (shadowBendX*bend.x+shadowBendZ*bend.y)*waterDepth;
        vec3 pos = distort(shadowClip.xyz / shadowClip.w) * 0.5 + 0.5;
        float coverage = shadow_coverage(point, pos);
        if (coverage <= 0.0) continue;
        vec4 weights = shadow_corner_weights(fract(pos.xy * shadowSize - 0.5));
        vec4 allVisibility = shadow_gather_visibility(shadowtex0, pos.xy, pos.z);
        if (all(equal(allVisibility, vec4(1.0)))) continue;
        vec4 opaqueVisibility = shadow_gather_visibility(shadowtex1, pos.xy, pos.z);
        float shadowVisibility = dot(max(opaqueVisibility-allVisibility,vec4(0.0)),weights);
        if (shadowVisibility <= 0.0) continue;
        vec3 shadow = astraWaterTransmissionTint*focusedLight*shadowVisibility;
        integral += shadow * sampleTransmission * coverage
                  * (water_shaft_phase(ray,bentLightDir)*stepLength/max(3.0,currentDist*0.1));
    }
    if (all(lessThanEqual(integral, vec3(0.0))))
        return vec4(vec3(0.0), rayLength / 128.0);
    vec3 ambientLight, directLight;
    solas_water_lighting(ambientLight, directLight, false);
    integral *= sqrt(max(directLight, vec3(0.0)))
              * mix(astraWaterShaftTintSqrt, astraWaterShaftTintSqrt*solasWeather, wetness)
              * (visibility * 0.04);
    return vec4(pow(clamp(integral / 128.0, 0.0, 1.0), vec3(0.25)), rayLength / 128.0);
}

#else
vec3 water_shafts_resolve(sampler2D shaftMap, vec2 uv, float rayLength) {
    ivec2 size = textureSize(shaftMap, 0);
    vec2 position = clamp(uv, 0.0, 1.0) * vec2(size) - 0.5;
    // Continuous quadratic B-spline reconstruction: nine nearby volume texels
    // suppress per-ray grain even at exact texel centres, where bilinear alone
    // did no smoothing. Its compact footprint retains broad shaft contrast.
    ivec2 centre = ivec2(floor(position+0.5));
    vec2 fraction = position-vec2(centre);
    vec2 left = 0.5*(0.5-fraction)*(0.5-fraction);
    vec2 middle = vec2(0.75)-fraction*fraction;
    vec2 right = 0.5*(0.5+fraction)*(0.5+fraction);
    vec3 compressed = vec3(0.0);
    float weights = 0.0;
    float referenceLength = min(clamp(rayLength, 0.0, WATER_SHAFT_MAX_DISTANCE), astraWaterShaftRange);
    // Reject distance mismatches per tap; scene colour is never filtered here.
    for (int y = -1; y <= 1; ++y) for (int x = -1; x <= 1; ++x) {
        float axisX = x < 0 ? left.x : (x == 0 ? middle.x : right.x);
        float axisY = y < 0 ? left.y : (y == 0 ? middle.y : right.y);
        float spatialWeight = axisX*axisY;
        if (spatialWeight <= 0.0) continue;
        vec4 tap = texelFetch(shaftMap, clamp(centre+ivec2(x,y), ivec2(0), size-1), 0);
        // Geometry beyond the integration window cannot occlude this volume.
        // Comparing its full endpoint distance isolated noisy far-field rays.
        float delta = abs(min(clamp(tap.a, 0.0, 1.0) * WATER_SHAFT_MAX_DISTANCE, astraWaterShaftRange)
                          - referenceLength);
        float weight = spatialWeight * exp(-delta * 0.25);
        compressed += tap.rgb * weight;
        weights += weight;
    }
    // Solas filters fourth-root storage BEFORE expanding it. Decoding isolated
    // caustic peaks first turned sparse march samples into conspicuous speckles.
    // Only the additive volume is filtered; scene colour stays full resolution.
    compressed /= max(weights, 1e-30);
    vec3 squared = compressed * compressed;
    return squared * squared * 128.0;
}
#endif
#endif
