#ifndef ASTRA_LIB_SETTINGS_GLSL
#define ASTRA_LIB_SETTINGS_GLSL

// ============================================================
//  Astra v1 - lib/settings.glsl
//  Single source of truth for ALL user options (design.md 3.3).
//  7 GUI categories / 3 profiles (profile values live in shaders.properties).
//  Conventions (design.md 3.2):
//    - macros UPPER_SNAKE_CASE
//    - booleans use #ifdef (bare define = on, commented-out define = off)
//    - enums are numeric; named token constants below keep call sites readable
//    - strength sliders are percentages (100 = default); scale at the use site
// ============================================================

// --- enum token constants (do not reference from GUI) ---
//     A token may name the arm no branch tests (the code checks one value and lets the
//     rest fall through); check_pack.py check 13 requires each such token to stay a real
//     value of its option, and rejects a token that is neither tested nor exempted.
#define TONEMAP_UCHIMURA         0
#define TONEMAP_AGX              1
#define TONEMAP_ACES             2
#define TONEMAP_REINHARD_JODIE   3
#define SKY_MINISHITA            0
#define SKY_GRADIENT             1
#define SUN_MOON_VANILLA         0
#define SUN_MOON_DISCS           1
#define CLOUD_VANILLA            0
#define CLOUD_PLANAR             1
#define CLOUD_OFF                2
#define WATER_COLD               0
#define WATER_BALANCED           1
#define WATER_TROPICAL           2
#define SHADOW_FILTER_SOFTWARE   0
#define SHADOW_FILTER_HARDWARE   1

// --- LIGHTING ---
#define SUNLIGHT_STRENGTH 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Direct sunlight strength, % (100 = default)
#define MOONLIGHT_STRENGTH 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Moonlight strength, %
#define SKYLIGHT_STRENGTH 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Directional ambient (skylight) strength, %
#define MIN_AMBIENT 8 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20]
// Cave floor minimum ambient, % (8 = 0.08; 2026-09-07 visual round: 5 -> 8 so shadow
// areas keep a soft blue floor instead of cutting to the material albedo)
#define BLOCKLIGHT_STRENGTH 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Blocklight strength, %
#define BLOCKLIGHT_SUPPRESSION // [false true]
// Suppress blocklight by daylight. It was documented as a replacement for auto-exposure
// until SC-41 overturned that: this is a lighting term, auto-exposure is a display gain.
#define HANDHELD_LIGHTING // [false true]
// Dynamic handheld light source
#define HANDHELD_LIGHT_STRENGTH 100 // [0 25 50 75 100 125 150 175 200 225 250 275 300 325 350 375 400]
// Handheld light strength, %
#define LIGHTNING_FLASH // [false true]
// Lightning bolt point light + sky flash
#define EMISSIVE_STRENGTH 100 // [50 60 70 80 90 100 110 120 130 140 150 160 170 180 190 200]
// Emissive surface boost, %

// --- SHADOWS ---
#define SHADOW_FILTER_MODE 0 // [0 1]
// 0 = sixteen software depth comparisons in four gathers, with per-corner tint;
// 1 = four hardware comparison taps with a centre-material approximation.
#define SHADOWS // [false true]
// Master switch for shadow map
#define SHADOW_RESOLUTION 2048 // [512 1024 1536 2048 3072 4096]
// Shadow map resolution (square)
#define SHADOW_DISTANCE 256 // [64 80 96 112 128 160 192 256]
// Shadow render distance, blocks
#define ENTITY_SHADOW_DISTANCE 64 // [32 48 64 96 128]
// Entity shadow distance, blocks
#define SHADOW_SOFTNESS 2 // [1 2 4 8 16]
// Shadow edge softness, texels (4-tap PCF, max 16)
#define COLORED_SHADOWS // [false true]
// Tinted shadows via shadowcolor0 (stained glass / water)
#define STATIC_SHADOW_FALLBACK // [false true]
// Skylight-based static shadow approximation outside shadow distance
#define SSS_FOLIAGE // [false true]
// Foliage translucency approximation
#define SSS_STRENGTH 60 // [0 10 20 30 40 50 60 70 80 90 100 110 120 130 140 150 160 170 180 190 200]
// Foliage SSS strength, % (60 = the BALANCED profile value; the raw defaults must stay
// identical to that profile so "raw defaults = BALANCED" holds as a benchmark anchor)

// --- SKY ---
#define SKY_MODE 1 // [0 1]
// 0 = Minishita mini physical atmosphere, 1 = simple gradient
#define SUN_MOON_MODE 0 // [0 1]
// 0 = vanilla sun/moon texture, 1 = procedural discs
#define STARS // [false true]
// Cell-hash star field with subtle twinkle
#define CLOUD_MODE 1 // [0 1 2]
// 0 = vanilla clouds, 1 = planar wispy clouds, 2 = off
#define CLOUD_COVERAGE 50 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
// Planar cloud coverage, % (CLOUD_MODE=1 only)
//#define CLOUD_SHADOWS // [false true]
// Project the planar cloud field onto the ground in clear weather as well as rain.
// Off by default in every tier; the strength and the horizon fade need in-game A/B.
#define AIR_PERSPECTIVE // [false true]
// View-angle-dependent horizon tinting at sunrise/sunset (Refrax style)
#define BIOME_TINT // [false true]
// Subtle fog/ambient tint by biome temperature/humidity
#define BIOME_TINT_STRENGTH 50 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
// Biome tint strength, %
#define END_NEBULA // [false true]
// End dimension: faint nebula layer (low intensity)
#define END_PRECESSION_MINUTES 36 // [20 24 28 32 36 40 44 48 52 56 60]
// End ring axis precession; body orbital periods remain independent.

// --- WATER ---
#define WATER_WAVES // [false true]
// Animated water surface normals
#define WATER_WAVE_HEIGHT 100 // [25 50 75 100 125 150 175 200]
// 2026-09-11: briefly lowered to 62 for a "silkier" surface, then reverted - the user
// confirmed the original waves were fine and that the below-water breakup is unrelated
// to wave amplitude. Do not reduce this to chase that report.
// Wave amplitude, %
#define WATER_WAVE_SPEED 100 // [25 50 75 100 125 150 175 200]
// Wave flow speed, %
#define SCREENSPACE_REFLECTIONS // [false true]
// SSR on water/ice top faces (24 steps, sky fallback)
#define SCREENSPACE_REFRACTION // [false true]
// Finite interface perturbation with per-tap depth/side rejection
#define REFRACTION_STRENGTH 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
// Refraction offset strength, %
// Controls the finite wave layer; background depth cannot amplify this strength.
#define WATER_ABSORPTION 100 // [0 10 20 30 40 50 60 70 80 90 100]
// Underwater absorption amount, % (0 = OFF, enables deferred pass)
#define WATER_CHARACTER 1 // [0 1 2]
// Water palette: 0 = COLD, 1 = BALANCED, 2 = TROPICAL
#define WATER_CAUSTICS // [false true]
// 6-layer crest caustics from shadow-encoded water height
//#define UNDERWATER_PARTICLES // [false true]
// 2026-09-11 user round: default off. Both the reference look (Solas' still, clear
// underwater) and the user's request ("大幅调低") are served better by the volume
// light and caustics carrying the underwater read; the motes remain available for
// anyone who wants the suspended-matter layer.
// Underwater suspended particles
#define UNDERWATER_LIGHT_SHAFTS // [false true]
// Shadowed underwater sunlight, independent of the air GODRAYS option
#define UNDERWATER_SHAFT_STRENGTH 100 // [0 25 50 75 100 125 150 175 200]
// Underwater light shaft brightness, %
// The user control scales the integrated solar source once.
#define UNDERWATER_SHAFT_SAMPLES 7 // [4 5 6 7 8 9 10]
// Shadow samples along each full-resolution water view ray
//#define UNDERWATER_SHAFT_CALIBRATION // [false true]
// Swap the three underwater-shaft calibration curves (intensity lobe, sample
// distribution, beam tint) to their Solas V3.7b shapes. Off by default in every tier;
// absolute weights need in-game A/B before any tier would enable it.
#define FANCY_TRANSLUCENTS // [false true]
// Premultiplied alpha blending for translucents (blend ONE, ONE_MINUS_SRC_ALPHA)

// --- FOG ---
#define FOG_DENSITY 50 // [25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Atmospheric fog density, % (pow3 coefficient precomputed on CPU)
// 2026-09-06 second visual round: factory default 100 → 65（清爽风格收尾）
// 2026-09-07 third visual round: 65 → 50（大幅减雾）
#define SKY_FOG_STRENGTH 15 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
// Fog blending into sky, % (low values skip sky color computation)
// 2026-09-06 second visual round: factory default 50 → 25；远端仍强制收敛天空色。
// 2026-09-07 third visual round: 25 → 15（雾是点缀不是滤镜）
#define BORDER_FOG // [false true]
// Render-distance border fog
#define CAVE_FOG // [false true]
// Cave fog
#define UNDERWATER_FOG_DENSITY 40 // [25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Underwater fog density, %
// 2026-09-06 second visual round: factory 100 -> 55 (25-40 block visibility target)
// 2026-09-07 visual round: 55 -> 42 (toward Steadfast/Solas clean-through look; visibility >32 blocks)
#define NETHER_FOG_DENSITY 70 // [25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Nether fog density, % (independent curve, design 4.5)
// 2026-09-11 user round: "下界的雾气稍多" -> 100 to 70. The volumetric plume/haze
// layer in nether_volume.glsl is composited on top of this, so the total density is
// the two together; cut the homogeneous layer rather than the plumes that carry the
// depth the user asked for.
#define END_FOG_DENSITY 100 // [25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// End void fog density, %
#define NETHER_VOXEL_LIGHT // [false true]
// Nether volumetric light: fire, soul fire and lava cast spatial coloured light through a
// 64x64x64 voxel volume around the player (8 propagation steps, same frame, no history).
// Bounded subset of the Solas voxel-light architecture, not a full 128+ volume. Needs
// OpenGL 4.3 compute and custom images; on hardware without them Iris drops the option
// and the rest of the pack keeps working.

// --- POST ---
#define TONEMAP_OPERATOR 0 // [0 1 2 3]
// 0 = Uchimura (default), 1 = AgX, 2 = ACES, 3 = Reinhard-Jodie
#define EXPOSURE 100 // [25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Color grading: exposure, %
//#define AUTO_EXPOSURE // [false true]
// Scene-measured exposure gain on top of the slider above (bounded to about one stop
// either way, overworld air only; needs in-game A/B, design.md SC-41)
#define SATURATION 100 // [50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150]
// Color grading: saturation (factory 105 after second visual round; 2026-09-07 -> 100)
#define VIBRANCE 100 // [50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150]
// Color grading: vibrance (factory 108 after second visual round; 2026-09-07 -> 100)
#define CONTRAST 102 // [50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150]
// Color grading: contrast (factory 104 per Refrax target; 2026-09-07 -> 102 弱化阴影对比)
#define COLOR_TEMPERATURE 0 // [-50 -45 -40 -35 -30 -25 -20 -15 -10 -5 0 5 10 15 20 25 30 35 40 45 50]
// Color grading: temperature shift (-cool / +warm)
#define BLOOM // [false true]
// Bloom (2-pass: composite1 capture + final composite)
#define BLOOM_STRENGTH 100 // [0 10 20 30 40 50 60 70 80 90 100 110 120 130 140 150 160 170 180 190 200]
// Bloom strength, %
//#define GODRAYS // [false true]
// Godrays (half-res, default OFF for the BALANCED profile, design 1.2)
#define GODRAYS_STRENGTH 100 // [0 10 20 30 40 50 60 70 80 90 100 110 120 130 140 150 160 170 180 190 200]
// Godrays strength, %
//#define GODRAYS_SUN_OCCLUSION // [false true]
// Godrays sun occlusion (one probed pixel fades the whole beam field when the
// solar disc is behind geometry; needs in-game A/B, see qa/session-log.md)
#define DITHERING // [false true]
// IGN output dithering (banding suppression, required without AA)
//#define VIGNETTE // [false true]
// Vignette (explicitly OFF by default, design 4.4)

// --- PERFORMANCE + ADVANCED ---
#define WAVING_FOLIAGE // [false true]
// Vertex-animated foliage sway (wind params via custom uniforms)
#define WAVING_FOLIAGE_STRENGTH 100 // [25 50 75 100 125 150 175 200]
// Foliage sway strength, %
//#define VOXY_SUPPORT // [false true]
// Voxy distant-terrain support (EXPERIMENTAL on 26.x, design 4.6)
// Iris keeps this option only because lib/uniforms.glsl references it; the real
// Voxy integration (voxy.json patch + Voxy programs) is still pending (owner C5).

// ------------------------------------------------------------
// ENGINE KNOBS (design.md 4.1 / 5) - the engine reads these const names, not macros.
// "const = MACRO" is resolved by Iris at load time; OptiFine would need literals here,
// which Astra does not support (design.md 1.2: Iris-only).
// ------------------------------------------------------------
const int   shadowMapResolution  = SHADOW_RESOLUTION;  // shadow map is square
const float shadowDistance       = SHADOW_DISTANCE;    // blocks
const float shadowDistanceRenderMul = 1.5;             // retain upstream casters beyond the receiver range
// Smaller world-grid intervals reduce changes of the distortion origin at
// cell boundaries; this does not change the shadow map's texel resolution.
const float shadowIntervalSize   = 0.5;
// Both Steadfast and Solas use this orbit; Iris applies it to sky and shadow matrices.
const float sunPathRotation = -40.0;
// noisetex/noise.png were removed: nothing sampled them (consolidated review E4).
const int   noiseTextureResolution = 256;              // engine default kept explicit

// --- SC-13 (design.md 4.1): the three shadow engine knobs, semantics frozen there ---
// Iris multiplies shadowDistance * shadowDistanceRenderMul * this ratio.
// Literal table for all advertised options: Iris's directive reader cannot
// evaluate arithmetic. Render multiplier is 1.5 above; keep it paired here.
#if SHADOW_DISTANCE == 64
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.3333333333;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.5000000000;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.6666666667;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 1.0000000000;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 1.3333333333;
#endif
#elif SHADOW_DISTANCE == 80
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.2666666667;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.4000000000;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.5333333333;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.8000000000;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 1.0666666667;
#endif
#elif SHADOW_DISTANCE == 96
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.2222222222;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.3333333333;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.4444444444;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.6666666667;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.8888888889;
#endif
#elif SHADOW_DISTANCE == 112
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.1904761905;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.2857142857;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.3809523810;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.5714285714;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.7619047619;
#endif
#elif SHADOW_DISTANCE == 128
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.1666666667;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.2500000000;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.3333333333;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.5000000000;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.6666666667;
#endif
#elif SHADOW_DISTANCE == 160
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.1333333333;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.2000000000;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.2666666667;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.4000000000;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.5333333333;
#endif
#elif SHADOW_DISTANCE == 192
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.1111111111;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.1666666667;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.2222222222;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.3333333333;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.4444444444;
#endif
#else // SHADOW_DISTANCE == 256
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.0833333333;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.1250000000;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.1666666667;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.2500000000;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.3333333333;
#endif
#endif

// Software retains exact depth/material pairing. Optional hardware comparison
// filtering uses the surface consumer's explicitly approximate centre material.
#if SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
const bool shadowHardwareFiltering = true;
const bool shadowHardwareFiltering0 = true;
const bool shadowHardwareFiltering1 = true;
#else
const bool shadowHardwareFiltering = false;
const bool shadowHardwareFiltering0 = false;
const bool shadowHardwareFiltering1 = false;
#endif

// --- buffer formats (design.md 2.3) ---
// Iris accepts named format directives in entries or expanded includes.
// Declare each buffer once per compilation unit; the symbolic format token
// also needs a GLSL declaration. Scene/bloom formats: water_buffer_formats.glsl;
// End data/sky formats: end_illumination.fsh and end_sky_buffer.fsh.

// E1/E2 internal scheduling predicate; not a user option.
#ifdef UNDERWATER_LIGHT_SHAFTS
#ifdef SHADOWS
#if !defined DIMENSION_NETHER && !defined DIMENSION_END && UNDERWATER_SHAFT_STRENGTH > 0
    #define ASTRA_UNDERWATER_SHAFTS
#endif
#endif
#endif
// Water still scatters when absorption/reflection options are off. Its background
// copy is part of the optical composition, independent of those optional effects.
#define ASTRA_SCENE_COPY
// SC-23: clear colors must be 4-arg constructors with plain literal components
// (Iris parses each argument with Float.parseFloat - no expressions, no 1-arg splat).
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
// Alpha of this clear colour is the standing-water mask's own ZERO: sky, water-surface
// and translucent pixels keep it, so a 1.0 here would open deferred's puddle gate on
// every one of them (consolidated review A2 / F-42). The .r marker is unchanged.
const vec4 colortex3ClearColor = vec4(0.498, 0.0, 0.0, 0.0);  // 127/255 skylight marker
const vec4 shadowcolor0ClearColor = vec4(1.0, 1.0, 1.0, 1.0);
const vec4 colortex5ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex6ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const bool colortex6Clear = false;

#endif
