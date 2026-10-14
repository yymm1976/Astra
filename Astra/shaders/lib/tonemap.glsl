#ifndef ASTRA_LIB_TONEMAP_GLSL
#define ASTRA_LIB_TONEMAP_GLSL

// Immediate source: Mellow v3.4 by TheCMK (MIT) - lib/tonemap_operators.glsl + lib/tonemap.glsl.
// Ported for Astra v1: only the 4 design operators (design.md 4.4) plus the grading
// primitives; renamed to snake_case per design.md 3.2. Ledger: THIRD-PARTY.md.
//
// Mellow's tonemap_operators.glsl is not all TheCMK's, and most of what it holds is a relay of
// two further upstreams: uchimura_tonemap*() and agx_cdl() are verbatim upstream
// glsl-tone-map (https://github.com/dmnsgn/shaders-tone-map),
// Copyright (C) 2019 Damien Seguin, MIT - the licence text ships in
// lib/vendor/glsl-tone-map/LICENSE.md. aces_tonemap() and its two matrices plus
// rrt_and_odt_fit() are BakingLab (https://github.com/TheRealMJP/BakingLab, ACES.hlsl),
// Copyright (c) 2016 MJP, MIT, the fit credited there to Stephen Hill (@self_shadow) - the
// licence text ships in lib/vendor/bakinglab/LICENSE.txt. Only reinhard_jodie() and the three
// grading primitives are TheCMK's own. Mellow's fifth operator, PBRNeutralToneMapping, is
// Apache-2.0 (The Khronos Group) and is not ported here.
//
// Uniforms: none
// Requires: lib/settings.glsl (TONEMAP_OPERATOR), lib/encoding.glsl (get_luminance, to_linear)

// https://64.github.io/tonemapping/
vec3 reinhard_jodie(vec3 v) {
    float l = get_luminance(v);
    vec3 tv = v / (1.0 + v);
    return mix(v / (1.0 + l), tv, tv);
}

// Uchimura 2017, "HDR theory and practice"
// Math: https://www.desmos.com/calculator/gslcdxvipg
// Source: https://www.slideshare.net/nikuque/hdr-theory-and-practicce-jp
vec3 uchimura_tonemap_full(vec3 x, float P, float a, float m, float l, float c, float b) {
    float l0 = ((P - m) * l) / a;
    float L0 = m - m / a;
    float L1 = m + (1.0 - m) / a;
    float S0 = m + l0;
    float S1 = m + a * l0;
    float C2 = (a * P) / (P - S1);
    float CP = -C2 / P;

    vec3 w0 = vec3(1.0 - smoothstep(0.0, m, x));
    vec3 w2 = vec3(step(m + l0, x));
    vec3 w1 = vec3(1.0 - w0 - w2);

    // The toe and shoulder are disjoint ranges. When every channel's weight
    // is zero, omit that curve while retaining the original transition masks.
    vec3 T = vec3(0.0);
    if (any(greaterThan(w0, vec3(0.0))))
        T = vec3(m * pow(x / m, vec3(c)) + b);
    vec3 S = vec3(0.0);
    if (any(greaterThan(w2, vec3(0.0))))
        S = vec3(P - (P - S1) * exp(CP * (x - S0)));
    vec3 L = vec3(m + a * (x - m));

    return T * w0 + L * w1 + S * w2;
}

vec3 uchimura_tonemap(vec3 x) {
    const float P = 1.0;  // max display brightness
    const float a = 1.0;  // contrast
    const float m = 0.22; // linear section start
    const float l = 0.4;  // linear section length
    const float c = 1.33; // black
    const float b = 0.0;  // pedestal

    return uchimura_tonemap_full(x, P, a, m, l, c, b);
}

// Scalar specialization of the existing Uchimura defaults. Its linear section
// is exactly x; toe and shoulder never overlap, so only one curve is needed.
float astra_uchimura_peak(float x) {
    const float m = 0.22;
    const float shoulderStart = 0.532;
    const float shoulderRange = 0.468;
    if (x >= shoulderStart)
        return 1.0 - shoulderRange * exp(-(x - shoulderStart) / shoulderRange);
    if (x >= m) return x;
    return mix(m * pow(x / m, 1.33), x, smoothstep(0.0, m, x));
}

// Original Astra natural-look adaptation: preserve channel ratios through the
// shoulder, then lose chroma only for genuinely bright scene luminance. This
// does not tint midtones or add a grey shadow floor. No reference look is copied.
vec3 astra_natural_uchimura(vec3 x) {
    float peak = max(x.r, max(x.g, x.b));
    if (peak <= 0.0) return vec3(0.0);
    float mappedPeak = astra_uchimura_peak(peak);
    vec3 mapped = x * (mappedPeak / peak);
    float whitePath = smoothstep(1.0, 8.0, get_luminance(x));
    return mix(mapped, vec3(mappedPeak), whitePath);
}

// Missing Deadlines (Benjamin Wrensch): https://iolite-engine.com/blog_posts/minimal_agx_implementation
// Filament: https://github.com/google/filament/blob/main/filament/src/ToneMapper.cpp#L263
// https://github.com/EaryChow/AgX_LUT_Gen/blob/main/AgXBaseRec2020.py
// Three.js: https://github.com/mrdoob/three.js/blob/4993e3af579a27cec950401b523b6e796eab93ec/src/renderers/shaders/ShaderChunk/tonemapping_pars_fragment.glsl.js#L79-L89
// Matrices for rec 2020 <> rec 709 color space conversion, row-major, transposed
// https://www.itu.int/pub/R-REP-BT.2407-2017
const mat3 linear_rec2020_to_linear_srgb = mat3(
    1.6605, -0.1246, -0.0182,
   -0.5876,  1.1329, -0.1006,
   -0.0728, -0.0083,  1.1187
);

const mat3 linear_srgb_to_linear_rec2020 = mat3(
    0.6274, 0.0691, 0.0164,
    0.3293, 0.9195, 0.0880,
    0.0433, 0.0113, 0.8956
);

// Converted to column major from blender:
// https://github.com/blender/blender/blob/fc08f7491e7eba994d86b610e5ec757f9c62ac81/release/datafiles/colormanagement/config.ocio#L358
const mat3 agx_inset_matrix = mat3(
    0.856627153315983, 0.137318972929847, 0.11189821299995,
    0.0951212405381588, 0.761241990602591, 0.0767994186031903,
    0.0482516061458583, 0.101439036467562, 0.811302368396859
);

// Converted to column major and inverted from
// https://github.com/EaryChow/AgX_LUT_Gen/blob/ab7415eca3cbeb14fd55deb1de6d7b2d699a1bb9/AgXBaseRec2020.py#L25
// https://github.com/google/filament/blob/bac8e58ee7009db4d348875d274daf4dd78a3bd1/filament/src/ToneMapper.cpp#L273-L278
const mat3 agx_outset_matrix = mat3(
    1.1271005818144368, -0.1413297634984383, -0.14132976349843826,
   -0.11060664309660323, 1.157823702216272, -0.11060664309660294,
   -0.016493938717834573, -0.016493938717834257, 1.2519364065950405
);

const float agx_min_ev = -12.47393;
const float agx_max_ev = 4.026069;

// Full AgX with CDL look controls; neutral look = slope 1, offset 0, power 1, saturation 1
vec3 agx_cdl(vec3 color, vec3 slope, vec3 offset, vec3 power, float saturation) {
    color = linear_srgb_to_linear_rec2020 * color; // From three.js

    // 1. agx() - input transform (inset)
    color = agx_inset_matrix * color;

    color = max(color, 1e-10); // From Filament: avoid 0 or negative numbers for log2

    // Log2 space encoding
    color = clamp(log2(color), agx_min_ev, agx_max_ev);
    color = (color - agx_min_ev) / (agx_max_ev - agx_min_ev);

    color = clamp(color, 0.0, 1.0); // From Filament

    // Apply sigmoid function approximation
    // Mean error^2: 3.6705141e-06
    vec3 x2 = color * color;
    vec3 x4 = x2 * x2;
    color = + 15.5     * x4 * x2
            - 40.14    * x4 * color
            + 31.96    * x4
            - 6.868    * x2 * color
            + 0.4298   * x2
            + 0.1191   * color
            - 0.00232;

    // 2. agxLook()
    color = pow(max(color * slope + offset, vec3(0.0)), power);
    const vec3 lw = vec3(0.2126, 0.7152, 0.0722);
    float luma = dot(color, lw);
    color = luma + saturation * (color - luma);

    // 3. agxEotf() - inverse input transform (outset)
    color = agx_outset_matrix * color;

    // sRGB IEC 61966-2-1 2.2 Exponent Reference EOTF Display
    color = pow(max(vec3(0.0), color), vec3(2.2)); // From filament: max()

    color = linear_rec2020_to_linear_srgb * color; // From three.js
    // Gamut mapping. Simple clamp for now.
    color = clamp(color, 0.0, 1.0);

    return color;
}

vec3 agx_punchy(vec3 color) {
    return agx_cdl(color, vec3(1.0), vec3(0.0), vec3(1.35), 1.4);
}

vec3 agx_tonemap(vec3 color) {
    return agx_cdl(color, vec3(1.0), vec3(0.0), vec3(1.0), 1.0);
}

// https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl
// sRGB => XYZ => D65_2_D60 => AP1 => RRT_SAT
const mat3 aces_input_mat = mat3(
    0.59719, 0.07600, 0.02840,
    0.35458, 0.90834, 0.13383,
    0.04823, 0.01566, 0.83777
);

// ODT_SAT => XYZ => D60_2_D65 => sRGB
const mat3 aces_output_mat = mat3(
    1.60475, -0.10208, -0.00327,
   -0.53108,  1.10813, -0.07276,
   -0.07367, -0.00605,  1.07602
);

vec3 rrt_and_odt_fit(vec3 v) {
    vec3 a = v * (v + 0.0245786) - 0.000090537;
    vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return a / b;
}

vec3 aces_tonemap(vec3 color) {
    color = aces_input_mat * color;

    // Apply RRT and ODT
    color = rrt_and_odt_fit(color);

    color = aces_output_mat * color;

    // Clamp to [0, 1]
    color = clamp(color, 0, 1);

    return color;
}

// --- dispatch (Astra enum tokens from lib/settings.glsl) ---
vec3 apply_tonemap(vec3 x) {
    x = max(x, vec3(0.0));
    #if TONEMAP_OPERATOR == TONEMAP_UCHIMURA
    #if defined ASTRA_OVERWORLD_NATURAL && !defined DEBUG_DISABLE_COLOR_GRADE
    return astra_natural_uchimura(x);
    #else
    return uchimura_tonemap(x);
    #endif
    #elif TONEMAP_OPERATOR == TONEMAP_AGX
    return agx_tonemap(x);
    #elif TONEMAP_OPERATOR == TONEMAP_ACES
    return aces_tonemap(x);
    #elif TONEMAP_OPERATOR == TONEMAP_REINHARD_JODIE
    return reinhard_jodie(x);
    #endif
    return uchimura_tonemap(x);
}

// --- grading primitives (design.md 4.4 color grading sliders) ---
vec3 apply_saturation(vec3 color, float sat) {
    float luminance = get_luminance(color);
    return mix(vec3(luminance), color, sat);
}

vec3 apply_vibrance(vec3 color, float intensity) {
    float mn = min(color.r, min(color.g, color.b));
    float mx = max(color.r, max(color.g, color.b));
    float sat = (1.0 - clamp(mx - mn, 0, 1)) * clamp(1.0 - mx, 0, 1) * get_luminance(color) * 5.0;
    vec3 lightness = vec3((mn + mx) * 0.5);

    return mix(color, mix(lightness, color, intensity), sat);
}

vec3 apply_contrast(vec3 color, float contrast) {
    // Endpoint-preserving curve: a nonzero shadow must not become negative
    // and get clipped to black by the final grade.
    vec3 c = clamp(color, 0.0, 1.0);
    // Both halves are mirror images. Evaluate one power per channel instead
    // of evaluating both curves and discarding one of them.
    vec3 curved = 0.5 * pow(2.0 * min(c,1.0-c), vec3(contrast));
    return mix(curved,1.0-curved,step(vec3(0.5),c));
}

#endif
