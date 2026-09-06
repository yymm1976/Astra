#ifndef ASTRA_LIB_SETTINGS_GLSL
#define ASTRA_LIB_SETTINGS_GLSL

// ============================================================
//  Astra v1 - lib/settings.glsl
//  Single source of truth for ALL user options (design.md 3.3).
//  61 options / 7 GUI categories / 3 profiles (profile values live in shaders.properties).
//  Conventions (design.md 3.2):
//    - macros UPPER_SNAKE_CASE
//    - booleans use #ifdef (bare define = on, commented-out define = off)
//    - enums are numeric; named token constants below keep call sites readable
//    - strength sliders are percentages (100 = default); scale at the use site
// ============================================================

// --- enum token constants (do not reference from GUI) ---
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

// --- LIGHTING ---
#define SUNLIGHT_STRENGTH 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Direct sunlight strength, % (100 = default)
#define MOONLIGHT_STRENGTH 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Moonlight strength, %
#define SKYLIGHT_STRENGTH 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Directional ambient (skylight) strength, %
#define MIN_AMBIENT 5 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20]
// Cave floor minimum ambient, % (5 = 0.05)
#define BLOCKLIGHT_STRENGTH 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Blocklight strength, %
#define BLOCKLIGHT_SUPPRESSION // [false true]
// Suppress blocklight by daylight (replaces auto-exposure, design 4.1)
#define HANDHELD_LIGHTING // [false true]
// Dynamic handheld light source
#define HANDHELD_LIGHT_STRENGTH 100 // [0 25 50 75 100 125 150 175 200 225 250 275 300 325 350 375 400]
// Handheld light strength, %
#define LIGHTNING_FLASH // [false true]
// Lightning bolt point light + sky flash
#define EMISSIVE_STRENGTH 100 // [50 60 70 80 90 100 110 120 130 140 150 160 170 180 190 200]
// Emissive surface boost, %

// --- SHADOWS ---
#define SHADOWS // [false true]
// Master switch for shadow map
#define SHADOW_RESOLUTION 2048 // [512 1024 1536 2048 3072 4096]
// Shadow map resolution (square)
#define SHADOW_DISTANCE 128 // [64 80 96 112 128 160 192 256]
// Shadow render distance, blocks
#define ENTITY_SHADOW_DISTANCE 64 // [32 48 64 96 128]
// Entity shadow distance, blocks
#define SHADOW_SOFTNESS 4 // [1 2 4 8 16]
// Shadow edge softness, texels (4-tap PCF, max 16)
#define COLORED_SHADOWS // [false true]
// Tinted shadows via shadowcolor0 (stained glass / water)
#define STATIC_SHADOW_FALLBACK // [false true]
// Skylight-based static shadow approximation outside shadow distance
#define SSS_FOLIAGE // [false true]
// Foliage translucency approximation
#define SSS_STRENGTH 100 // [0 10 20 30 40 50 60 70 80 90 100 110 120 130 140 150 160 170 180 190 200]
// Foliage SSS strength, %

// --- SKY ---
#define SKY_MODE 0 // [0 1]
// 0 = Minishita mini physical atmosphere, 1 = simple gradient
#define SUN_MOON_MODE 0 // [0 1]
// 0 = vanilla sun/moon texture, 1 = procedural discs
#define STARS // [false true]
// Cell-hash star field with subtle twinkle
#define CLOUD_MODE 0 // [0 1 2]
// 0 = vanilla clouds, 1 = planar wispy clouds, 2 = off
#define CLOUD_COVERAGE 50 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
// Planar cloud coverage, % (CLOUD_MODE=1 only)
#define AIR_PERSPECTIVE // [false true]
// View-angle-dependent horizon tinting at sunrise/sunset (Refrax style)
#define BIOME_TINT // [false true]
// Subtle fog/ambient tint by biome temperature/humidity
#define BIOME_TINT_STRENGTH 50 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
// Biome tint strength, %
#define END_NEBULA // [false true]
// End dimension: faint nebula layer (low intensity)

// --- WATER ---
#define WATER_WAVES // [false true]
// Animated water surface normals
#define WATER_WAVE_HEIGHT 100 // [25 50 75 100 125 150 175 200]
// Wave amplitude, %
#define WATER_WAVE_SPEED 100 // [25 50 75 100 125 150 175 200]
// Wave flow speed, %
#define SCREENSPACE_REFLECTIONS // [false true]
// SSR on water/ice top faces (24 steps, sky fallback)
#define SCREENSPACE_REFRACTION // [false true]
// Single-jump screen-space refraction with depth rejection
#define REFRACTION_STRENGTH 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
// Refraction offset strength, %
#define WATER_ABSORPTION 100 // [0 10 20 30 40 50 60 70 80 90 100]
// Underwater absorption amount, % (0 = OFF, enables deferred pass)
#define WATER_CHARACTER 1 // [0 1 2]
// Water palette: 0 = COLD, 1 = BALANCED, 2 = TROPICAL
#define WATER_CAUSTICS // [false true]
// 6-layer crest caustics from shadow-encoded water height
#define UNDERWATER_PARTICLES // [false true]
// Underwater suspended particles
#define FANCY_TRANSLUCENTS // [false true]
// Premultiplied alpha blending for translucents (blend ONE, ONE_MINUS_SRC_ALPHA)

// --- FOG ---
#define FOG_DENSITY 100 // [25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Atmospheric fog density, % (pow3 coefficient precomputed on CPU)
#define SKY_FOG_STRENGTH 50 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
// Fog blending into sky, % (low values skip sky color computation)
#define BORDER_FOG // [false true]
// Render-distance border fog
#define CAVE_FOG // [false true]
// Cave fog
#define UNDERWATER_FOG_DENSITY 100 // [25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Underwater fog density, %
#define NETHER_FOG_DENSITY 100 // [25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Nether fog density, % (independent curve, design 4.5)
#define END_FOG_DENSITY 100 // [25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// End void fog density, %

// --- POST ---
#define TONEMAP_OPERATOR 0 // [0 1 2 3]
// 0 = Uchimura (default), 1 = AgX, 2 = ACES, 3 = Reinhard-Jodie
#define EXPOSURE 100 // [25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Color grading: exposure, %
#define SATURATION 112 // [50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150]
// Color grading: saturation (factory 112 per Refrax target)
#define VIBRANCE 115 // [50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150]
// Color grading: vibrance (factory 115 per Refrax target)
#define CONTRAST 104 // [50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150]
// Color grading: contrast (factory 104 per Refrax target)
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

// ------------------------------------------------------------
// ENGINE KNOBS (design.md 4.1 / 5) - the engine reads these const names, not macros.
// "const = MACRO" is resolved by Iris at load time; OptiFine would need literals here,
// which Astra does not support (design.md 1.2: Iris-only).
// ------------------------------------------------------------
const int   shadowMapResolution  = SHADOW_RESOLUTION;  // shadow map is square
const float shadowDistance       = SHADOW_DISTANCE;    // blocks
const float shadowDistanceRenderMul = 1.0;             // box culling, no overscan (design 5)
const int   noiseTextureResolution = 256;              // matches texture.noisetex

// --- SC-13 (design.md 4.1): the three shadow engine knobs, semantics frozen there ---
// Entity shadow distance is a RATIO of the terrain shadow distance, not a block count.
// All three profiles resolve to 0.5 (48/96, 64/128, 96/192), so the option keeps the
// stable meaning "entities cast shadows out to half the shadow distance".
// SC-23 round-trip on real hardware: Iris' const parser accepts plain literals only
// (NumberFormatException on `64 * (1.0 / 128)`), so the ratio ships pre-computed.
// All three profiles resolve to 0.5 (48/96, 64/128, 96/192); if the profiles ever
// diverge, this must become a per-profile literal again.
const float entityShadowDistanceMul = 0.5;

// Hardware PCF is the precondition of the 4-tap kernel in
// global/lighting/shadowmap.glsl (design.md 4.1), not a user choice. Unsuffixed form
// is what Mellow ships on Iris (global/configurations.glsl:17).
const bool shadowHardwareFiltering = true;

// --- buffer formats (design.md 2.3) ---
// SC-25 (4th real-hardware round): Iris does NOT rewrite format tokens inside lib
// includes - `R11F_G11F_B10F` reached the GLSL driver as an undefined identifier
// (C1503 in deferred.vsh). Every reference pack declares format consts in program
// files (Refrax program/composite0, Solas program/final, Steadfast program/shadow
// + program/post; Mellow's release ships its lib declarations commented out and
// runs on Iris defaults). Formats therefore live with their writer programs:
//   all six -> ENTRY final.fsh shells (root / world-1 / world1), one set per dimension
// SC-26 refinement: Iris rewrites format tokens solely in the file it compiles
// directly (the entry shell) - program/lib includes are never rewritten even when
// their consts are READ for directive collection. Entry files only; do NOT move
// back into this single-point file.

// E1/E2 internal scheduling predicate; not a user option.
#if defined SCREENSPACE_REFLECTIONS || defined SCREENSPACE_REFRACTION || WATER_ABSORPTION > 0
    #define ASTRA_SCENE_COPY
#endif
// SC-23: clear colors must be 4-arg constructors with plain literal components
// (Iris parses each argument with Float.parseFloat - no expressions, no 1-arg splat).
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex3ClearColor = vec4(0.498, 0.0, 0.0, 1.0);  // 127/255 skylight marker
const vec4 shadowcolor0ClearColor = vec4(1.0, 1.0, 1.0, 1.0);

#endif
