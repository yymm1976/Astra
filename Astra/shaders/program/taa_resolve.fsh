// Original Astra TAA: unjittered HDR output, validated bilinear history and a
// conservative reactive path. No object velocity is inferred from camera motion.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
uniform sampler2D colortex0;
#if defined ASTRA_BLOOM && !defined DIMENSION_NETHER && !defined DIMENSION_END
uniform sampler2D colortex4;
#endif
in vec2 texcoord;
#ifdef ASTRA_TAA
#include "/lib/transforms.glsl"
#include "/lib/taa_state.glsl"
uniform sampler2D colortex15;
uniform sampler2D colortex16;
uniform sampler2D colortex17;
uniform sampler2D colortex22;
#ifndef RGBA16F
const int RGBA16F = 0;
#endif
const int colortex15Format = RGBA16F;
const bool colortex15Clear = false;
const vec4 colortex15ClearColor = vec4(0.0, 0.0, 0.0, -1.0);
/* RENDERTARGETS: 0,15 */

vec3 taa_ycocg(vec3 rgb) {
    return vec3(dot(rgb, vec3(0.25, 0.5, 0.25)),
                0.5 * (rgb.r - rgb.b), 0.5 * rgb.g - 0.25 * (rgb.r + rgb.b));
}
vec3 taa_rgb(vec3 c) { return vec3(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z); }

// Same complete 3x3 max as the scalar dilation. Two overlapping 2x2 gathers
// cover seven unique texels; the opposite corners below supply the other two.
// Anchor inside each gather footprint, away from texel-centre rounding ties.
// Borders retain explicit clamping, independently of sampler wrap state.
float taa_reactive_neighbourhood(ivec2 pixel, ivec2 size) {
    float reactive = texelFetch(colortex16, pixel, 0).r;
    if (reactive >= 0.95) return reactive;
    if (all(greaterThan(pixel, ivec2(0))) && all(lessThan(pixel, size - 1))) {
        vec2 gatherUV = (vec2(pixel) + 0.25) / vec2(size);
        vec4 lower = textureGather(colortex16, gatherUV, 0);
        reactive = max(reactive, max(max(lower.x, lower.y), max(lower.z, lower.w)));
        if (reactive >= 0.95) return reactive;
        vec4 upper = textureGather(colortex16, (vec2(pixel) + 1.25) / vec2(size), 0);
        reactive = max(reactive, max(max(upper.x, upper.y), max(upper.z, upper.w)));
        if (reactive >= 0.95) return reactive;
        reactive = max(reactive, texelFetch(colortex16, pixel + ivec2(-1, 1), 0).r);
        if (reactive >= 0.95) return reactive;
        return max(reactive, texelFetch(colortex16, pixel + ivec2(1, -1), 0).r);
    }
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            if (x == 0 && y == 0) continue;
            ivec2 p = clamp(pixel + ivec2(x, y), ivec2(0), size - 1);
            reactive = max(reactive, texelFetch(colortex16, p, 0).r);
            if (reactive >= 0.95) return reactive;
        }
    }
    return reactive;
}

// Validate EACH bilinear contributor before mixing; an interpolated depth can
// invent a surface between a moving foreground object and the exposed background.
vec4 taa_history(vec2 uv, float expectedDepth, float tolerance, ivec2 size) {
    vec2 location = uv * vec2(size) - 0.5;
    ivec2 base = ivec2(floor(location));
    vec2 fraction = fract(location);
    vec3 sum = vec3(0.0);
    float coverage = 0.0;
    for (int y = 0; y < 2; ++y) for (int x = 0; x < 2; ++x) {
        ivec2 p = base + ivec2(x, y);
        if (any(lessThan(p, ivec2(0))) || any(greaterThanEqual(p, size))) continue;
        vec2 axisWeight = mix(vec2(1.0) - fraction, fraction, bvec2(x == 1, y == 1));
        float weight = axisWeight.x * axisWeight.y;
        if (weight <= 0.0) continue;
        vec4 h = texelFetch(colortex15, p, 0);
        if (h.a < 0.0 || any(isnan(h)) || any(isinf(h))) continue;
        bool sameSurface = expectedDepth == 0.0 ? h.a == 0.0
            : h.a > 0.0 && abs(h.a - expectedDepth) < tolerance;
        if (!sameSurface) continue;
        sum += max(h.rgb, vec3(0.0)) * weight;
        coverage += weight;
    }
    return vec4(sum / max(coverage, 0.00001), coverage);
}

void main() {
    ivec2 size = textureSize(colortex0, 0);
    vec2 edge = 0.5 / vec2(size);
    // Only scene inputs are jittered; history/output use an unjittered pixel grid.
    // Consequently previousProjection below does NOT add the previous jitter.
    vec2 sceneUV = clamp(texcoord + astra_jitter_uv(), edge, 1.0 - edge);
    ivec2 pixel = clamp(ivec2(sceneUV * vec2(size)), ivec2(0), size - 1);
    #if defined ASTRA_BLOOM && !defined DIMENSION_NETHER && !defined DIMENSION_END
    vec3 current = isEyeInWater == 1
        ? max(textureLod(colortex4, sceneUV, 0.0).rgb, vec3(0.0))
        : max(textureLod(colortex0, sceneUV, 0.0).rgb, vec3(0.0));
    #else
    vec3 current = max(textureLod(colortex0, sceneUV, 0.0).rgb, vec3(0.0));
    #endif
    // All camera media reject scene history. This uniform branch runs before
    // derivatives and also persists the same invalid history marker as below.
    if (isEyeInWater != 0) {
        gl_FragData[0] = vec4(current,1.0);
        gl_FragData[1] = vec4(min(current,vec3(65000.0)),-1.0);
        return;
    }
    float depth = texelFetch(depthtex0, pixel, 0).r;
    bool sky = depth >= 0.999999;
    vec3 view = screen_view(vec3(sceneUV, depth));
    float storedDepth = sky ? 0.0 : log2(1.0 + max(-view.z, 0.0));
    vec3 world = sky ? view_player(view) : view_camera_relative(view);
    vec4 previousView = sky
        ? vec4(mat3(gbufferPreviousModelView) * world, 0.0)
        : gbufferPreviousModelView * vec4(world + (cameraPosition - previousCameraPosition), 1.0);
    vec4 clip = gbufferPreviousProjection * previousView;
    vec2 historyUV = clip.xy / max(clip.w, 0.00001) * 0.5 + 0.5;
    float expectedDepth = sky ? 0.0 : log2(1.0 + max(-previousView.z, 0.0));
    vec4 foliageMotion=sky ? vec4(0.0) : texelFetch(colortex22,pixel,0);
    if(!sky && foliageMotion.a>0.5) {
        historyUV=texcoord+foliageMotion.xy;
        expectedDepth=foliageMotion.z;
    }
    // Derivatives are evaluated before divergent rejection; the capped allowance
    // covers slopes and half-float depth precision without accepting distant layers.
    float tolerance = 0.012 + min(0.04, 2.0 * fwidth(expectedDepth));
    // One-pixel dilation covers bilinear footprints and moving silhouettes.
    // A reactive centre still rejects history before reading any neighbours.
    float reactive = taa_reactive_neighbourhood(pixel, size);
    vec3 resolved = current;
    bool valid = reactive < 0.95 && clip.w > 0.00001
        && all(greaterThanEqual(historyUV, edge)) && all(lessThanEqual(historyUV, 1.0 - edge))
        && astra_taa_state_valid(colortex17);
    if (valid) {
        vec4 h = taa_history(historyUV, expectedDepth, tolerance, size);
        if (h.a > 0.5) {
            vec3 historyColor = taa_ycocg(h.rgb);
            float currentY = taa_ycocg(current).x;
            float change = abs(historyColor.x - currentY) / max(max(historyColor.x, currentY), 0.05);
            float colorTrust = 1.0 - smoothstep(0.20, 0.80, change);
            // Zero colour trust uses the current frame, without a neighbourhood.
            if (colorTrust > 0.0) {
                // Colour statistics only constrain accepted history. Reactive
                // pixels and disocclusions need none of these nine scene fetches.
                vec3 lo = vec3(1e20), hi = vec3(-1e20), mean = vec3(0.0), second = vec3(0.0);
                for (int y = -1; y <= 1; ++y) for (int x = -1; x <= 1; ++x) {
                    ivec2 p = clamp(pixel + ivec2(x,y),ivec2(0),size-1);
                    vec3 sampleColor = taa_ycocg(max(texelFetch(colortex0,p,0).rgb,vec3(0.0)));
                    lo = min(lo,sampleColor);
                    hi = max(hi,sampleColor);
                    mean += sampleColor;
                    second += sampleColor*sampleColor;
                }
                mean /= 9.0;
                vec3 sigma = sqrt(max(second/9.0-mean*mean,vec3(0.0)));
                lo = max(lo,mean-1.25*sigma);
                hi = min(hi,mean+1.25*sigma);
                vec3 bounded = clamp(historyColor, lo, hi);
                float motion = clamp(length((historyUV - texcoord) * vec2(size)) / 16.0, 0.0, 1.0);
                // SUMMARY idea (Photon/Kappa/Mellow): trust a bilinear history near
                // texel centres more than a footprint spanning four contributors.
                // Original Astra bounded attenuation; retain per-corner depth rejection.
                vec2 phase = abs(fract(historyUV * vec2(size)) - 0.5) * 2.0;
                float centreTrust = 1.0 - 0.35 * max(phase.x, phase.y);
                float weight = mix(0.92, 0.70, motion) * (1.0 - reactive) * h.a
                             * colorTrust * centreTrust;
                resolved = mix(current, max(taa_rgb(bounded), vec3(0.0)), weight);
            }
        }
    }
    // A negative depth persists the CURRENT reactive footprint into next frame.
    // A newly exposed background must reject the previous moving surface too.
    gl_FragData[0] = vec4(resolved, 1.0);
    gl_FragData[1] = vec4(min(resolved, vec3(65000.0)), reactive >= 0.95 ? -1.0 : storedDepth);
}
#else
/* RENDERTARGETS: 0 */
void main() { gl_FragData[0] = texture(colortex0, texcoord); }
#endif
