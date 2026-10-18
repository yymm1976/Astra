#ifndef ASTRA_LIB_SETTINGS_GLSL
#define ASTRA_LIB_SETTINGS_GLSL

// ============================================================
//  Astra v1 - lib/settings.glsl
//  Single source of truth for ALL user options (design.md 3.3).
//  Nested colour controls and inherited quality profiles (shaders.properties).
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
//#define DIRECTIONAL_SKYLIGHT // [false true]
// Optional overworld directional sky irradiance, independent of TAA and clouds.
//#define SCREENSPACE_AO // [false true]
// Optional ambient-only AO for opaque overworld terrain.
#define AO_STRENGTH 75 // [0 25 50 75 100]
#define AO_RADIUS 100 // [50 100 150 200]
// Radius in hundredths of a block; AO is a local contact term.
#define SUNLIGHT_STRENGTH 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Direct sunlight strength, % (100 = default)
#define MOONLIGHT_STRENGTH 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Moonlight strength, %
#define SKYLIGHT_STRENGTH 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Directional ambient (skylight) strength, %
#define MIN_AMBIENT 8 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20]
// Cave floor minimum ambient, per mille (8 = 0.008; 2026-09-07 visual round: 5 -> 8 so shadow
// areas keep a soft blue floor instead of cutting to the material albedo)
#define BLOCKLIGHT_STRENGTH 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Blocklight strength, %
#define BLOCKLIGHT_SUPPRESSION // [false true]
// Suppress blocklight by daylight. It was documented as a replacement for auto-exposure
// until SC-41 overturned that: this is a lighting term, auto-exposure is a display gain.
#define HANDHELD_LIGHTING // [false true]
// Dynamic handheld light source
#define DIRECTIONAL_LOCAL_LIGHTING // [false true]
// Known hand-light direction and the Nether volume gradient; no guessed lightmap direction.
#define HANDHELD_LIGHT_STRENGTH 100 // [0 25 50 75 100 125 150 175 200 225 250 275 300 325 350 375 400]
// Handheld light strength, %
#define LIGHTNING_FLASH // [false true]
// Lightning bolt point light + sky flash
#define EMISSIVE_STRENGTH 100 // [50 60 70 80 90 100 110 120 130 140 150 160 170 180 190 200]
// Emissive surface boost, %
#define ORE_GLOW // [false true]
// Mineral flecks only; coal and copper ores are deliberately unclassified.

// --- SHADOWS ---
#define SHADOW_FILTER_MODE 0 // [0 1]
#define SHADOW_FILTER_QUALITY 1 // [0 1 2]
// Native overworld receivers: 0 = one footprint; 1/2 = four fixed footprints.
// Each footprint keeps four discrete comparisons. Other receivers use their own tiers.
// 0 = software depth comparisons; 1 = hardware comparison gathers.
// Both comparison modes pair each corner with its individual caster tint.
#define SHADOWS // [false true]
// Master switch for shadow map
#define SHADOW_RESOLUTION 1536 // [1024 1536 2048]
// Shadow map resolution (square)
#define SHADOW_DISTANCE 96 // [64 80 96 112 128]
// Shadow render distance, blocks
#define ENTITY_SHADOW_DISTANCE 32 // [32 64]
// Entity shadow distance, blocks
#define ENTITY_SHADOWS // [false true]
// Renderer-level switch for entity, player and block-entity shadow casters.
#define SHADOW_SOFTNESS 2 // [1 2 4]
// Shadow footprint radius, texels; medium/high filter quality only.
#define CLOUD_SHADOW_SOFTENING 100 // [0 25 50 75 100]
// Native surface footprints widen by at most 25% under the existing cloud shadow.
#define COLORED_SHADOWS // [false true]
// Tinted shadows via shadowcolor0 (stained glass / water)
#define STATIC_SHADOW_FALLBACK // [false true]
// Skylight-based static shadow approximation outside shadow distance
#define SSS_FOLIAGE // [false true]
// Foliage translucency approximation
#define SSS_STRENGTH 60 // [0 10 20 30 40 50 60 70 80 90 100 110 120 130 140 150 160 170 180 190 200]
// Foliage SSS strength, % (60 = the BALANCED profile value).

// --- SKY ---
#define SKY_MODE 1 // [0 1]
// 0 = Minishita mini physical atmosphere, 1 = simple gradient
#define SUN_MOON_MODE 0 // [0 1]
// 0 = vanilla sun/moon texture, 1 = procedural discs
#define STARS // [false true]
#define STAR_AMOUNT 2 // [0 1 2 3 4]
#define MILKY_WAY_BRIGHTNESS 100 // [0 25 50 75 100 125 150 175 200]
// Procedural galactic band and its faint extra stars; existing points stay unchanged.
// Celestial star catalogue: off / sparse / normal / dense / very dense.
#define CLOUD_MODE 1 // [0 1 2]
#define CLOUD_QUALITY 2 // [0 1 2]
// Planar clouds: quarter/half/native grid. Low/medium retain 12/16 coarse
// searches and boundary refinement; high integrates 4-block intervals (up to
// 512) and averages four native subpixel rays. High reflections share density
// integration. Sky-base tables use 65/129/257 square nodes. Cloud quality is
// independent of the overworld surface/water budget; high is the default.
// 0 = vanilla clouds, 1 = planar wispy clouds, 2 = off
#define CLOUD_COVERAGE 50 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
// Planar cloud coverage, % (CLOUD_MODE=1 only)
//#define CLOUD_SHADOWS // [false true]
// Project the planar cloud field onto the ground in clear weather as well as rain.
// Off by default in every tier; the strength and the horizon fade need in-game A/B.
// Independent cloud history, shared with the properties resource schedule.
// Disabling it selects the current-frame sheet and releases its history targets.
#define CLOUD_TEMPORAL // [false true]
#define AIR_PERSPECTIVE // [false true]
// View-angle-dependent horizon tinting at sunrise/sunset (Refrax style)
#define BIOME_TINT // [false true]
// Subtle biome-colour tint in thin atmospheric haze, fading with distance
#define BIOME_TINT_STRENGTH 50 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
// Biome tint strength, %
#define END_STONE_GLOW 0 // [0 25 50 75 100 125 150]
// Optional end-stone pore emission; zero preserves the unlit pore texture.
#define NETHERRACK_GLOW 100 // [0 25 50 75 100]
#define NETHER_ROCK_REFLECTIONS // [false true]
// Rock reflections are independent of the water/puddle SSR option.
#define NETHER_REFLECTION_QUALITY 1 // [0 1 2]
// Low/balanced trace a 2x2 lattice and reconstruct 5/9 footprints; high uses
// native receiver tracing and the 5x5 kernel. Independent of water quality.
#define DEBUG_VERTEX_AO 0 // [0 1]
#define DEBUG_NETHER_LIGHT 0 // [0 1 2 3]
// 1: receiver field, 2: camera-height light slice, 3: occupancy/source slice.
// Diagnostic bypass switches. Each removes exactly one stage from the composed
// image, so an A/B pair can attribute a visual result to that stage instead of
// guessing which layer produced it. All three default OFF and are inert in the
// shipping path; they are not quality options. Per-stage A/B table:
// docs/审查/2026-10-14下一步规划意见处置.md
//#define DEBUG_DISABLE_WATER_ABSORPTION // [false true]
// Removes the per-channel extinction of the scene seen through water (camera
// leg and interface bed paths). The in-scatter medium is untouched, so a
// remaining tint belongs to the medium, not to absorption.
//#define DEBUG_DISABLE_UNDERWATER_FOG // [false true]
// Removes the water in-scatter/medium term. Absorption stays, so the bed and
// distant scene keep their depth-dependent attenuation.
//#define DEBUG_DISABLE_COLOR_GRADE // [false true]
// Bypasses the display-space grade (temperature, vibrance, saturation,
// contrast, tonal balance). Exposure and the tone map are separate slots.
#define END_PRECESSION_MINUTES 36 // [20 24 28 32 36 40 44 48 52 56 60]
// End ring axis precession; body orbital periods remain independent.

// --- WATER ---
#define WATER_WAVES // [false true]
// Animated water surface normals
#define WATER_WAVE_QUALITY 0 // [0 1 2]
// Analytic surface normal: 4/5/6 layers. Lower tiers omit fine ripples and
// carry their mean slope into roughness; crest amplitude and motion stay unchanged.
#define WATER_WAVE_HEIGHT 100 // [25 50 75 100 125 150 175 200]
// 2026-09-11: briefly lowered to 62 for a "silkier" surface, then reverted - the user
// confirmed the original waves were fine and that the below-water breakup is unrelated
// to wave amplitude. Do not reduce this to chase that report.
// Wave amplitude, %
#define WATER_WAVE_SPEED 100 // [25 50 75 100 125 150 175 200]
// Wave flow speed, %
//#define SCREENSPACE_REFLECTIONS // [false true]
#define UNDERWATER_SURFACE_REFLECTIONS // [false true]
// Independent underside scene reflection; no extra air-side water ray.
//#define ROUGH_SKY_REFLECTIONS // [false true]
// Optional mip-filtered overworld environment + normalized environment BRDF.
// Off by default to retain the existing water/ice/puddle appearance.
#define WATER_EFFECT_QUALITY 0 // [0 1 2]
// Water SSR total depth-query budget: 12/20/40 (including 4/4/8 refinements).
// Nether rock tracing/reconstruction has its own NETHER_REFLECTION_QUALITY.
// Reflection reconstruction uses 1/5/9 bilinear footprints. Refraction keeps
// the same interface-side rejection and true optical path at every quality.
// SSR on water top faces; ice uses the environment without a fluid march.
// Water reflections use current-frame radiance. Geometry passes do not provide
// the composite-stage ping-pong contract needed for a self-written history.
#define SCREENSPACE_REFRACTION // [false true]
// Finite interface perturbation with per-tap depth/side rejection
#define REFRACTION_STRENGTH 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
// Refraction offset strength, %
// Controls the finite wave layer; background depth cannot amplify this strength.
#define WATER_ABSORPTION 100 // [0 10 20 30 40 50 60 70 80 90 100]
// Underwater absorption amount, % (0 = OFF); deferred still supplies scene colour.
#define WATER_CHARACTER 1 // [0 1 2]
// Water palette: 0 = COLD, 1 = BALANCED, 2 = TROPICAL
#define WATER_CAUSTICS // [false true]
// Shared optical-wave focus cached in the water shadow records.
//#define UNDERWATER_PARTICLES // [false true]
// Optional underwater suspended particles.
//#define UNDERWATER_LIGHT_SHAFTS // [false true]
// Shadowed underwater sunlight, independent of the air GODRAYS option.
#define UNDERWATER_SHAFT_STRENGTH 100 // [0 25 50 75 100 125 150 175 200]
// Underwater light shaft brightness, %.
#define UNDERWATER_SHAFT_DISTANCE 1 // [0 1 2 3 4 6 8 10 12 16]
// Nearby scattering reaches full strength at this distance; no emitter layout.
#define UNDERWATER_SHAFT_SAMPLES 7 // [4 7 10]
// Maximum receiver-shadow intervals along the water ray in the scattering target.
#define FANCY_TRANSLUCENTS // [false true]
// Premultiplied alpha blending for translucents.

// --- FOG ---
#define FOG_DENSITY 50 // [25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Atmospheric fog density, %.
#define SKY_FOG_STRENGTH 15 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]
// Fog blending into sky, %.
#define BORDER_FOG // [false true]
// Render-distance border fog.
#define CAVE_FOG // [false true]
// Cave fog.
#define UNDERWATER_FOG_DENSITY 35 // [0 15 25 35 50 75 100]
// Astra cyan water haze: 40 gives visible distance fog with a short near-eye fade.
// Other values scale density; reference-style atmosphere, locally tuned strength.
#define NETHER_FOG_DENSITY 70 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Scales Complementary's distance fog; there is no additional plume layer.
#define END_FOG_DENSITY 100 // [25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define END_HEIGHT_FOG // [false true]
// Broad island-height atmosphere; retains the original far-distance fade.
// End void fog density, %
#define NETHER_VOXEL_LIGHT // [false true]
// Nether volumetric light: fire, soul fire and lava cast spatial coloured light through a
// 64x64x64 voxel volume around the player (8 propagation steps, same frame, no history).
// Bounded subset of the Solas voxel-light architecture, not a full 128+ volume. Needs
// OpenGL 4.3 compute and custom images. No complete fallback is implemented
// for hosts without those capabilities.
//#define VOLUMETRIC_FOG // [false true]
// Optional ray-marched overworld volumetric fog: height-based density, sun/moon phase
// lobes, sky incident, shadow-map and cloud-shadow attenuation, composed as scene*T+S.
// While enabled it REPLACES the atmospheric distance fog, the rain haze (rainy_air) and
// the air GODRAYS over the same air segment; caves, blindness, lava, powder snow and
// underwater keep their own media. Default off in every profile, independent of TAA.
// Design and ownership: docs/archive/实现与取证.md#record-077.
#define VOLUME_FOG_DENSITY 50 // [0 25 50 75 100 125 150 175 200]
#define VOLUME_FOG_QUALITY 0 // [0 1 2]
// Low: quarter grid / up to 12 steps; balanced: half / 24; high: half / 48.
#define VOLUME_FOG_ADAPTIVE // [false true]
// Fewer samples on short rays, quadratic near-camera distribution; fixed mode
// keeps the selected count and uniform segment lengths.
// Volumetric fog density, % (sea-level extinction; this integrated curve is not
// calibrated as equivalent to the ordinary distance-fog curve). High air keeps a bounded thin floor. The
// phase lobe's anisotropy is a bounded source constant (ASTRA_VOLUME_PHASE_G in
// global/atmosphere/volume_fog.glsl).

// --- POST ---
#define TONEMAP_OPERATOR 0 // [0 1 2 3]
// 0 = Uchimura (default), 1 = AgX, 2 = ACES, 3 = Reinhard-Jodie
#define EXPOSURE 100 // [25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
// Color grading: exposure, %
//#define AUTO_EXPOSURE // [false true]
// Scene-measured exposure gain on top of the slider above (bounded to about one stop
// either way, overworld air only; needs in-game A/B, design.md SC-41)
#define SATURATION 100 // [50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150]
// Color grading: saturation, %; 100 is neutral in every look.
#define VIBRANCE 100 // [50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150]
// Color grading: vibrance, %; 100 is neutral.
#define CONTRAST 100 // [50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150]
// Color grading: contrast, %; 100 is neutral in every look.
#define COLOR_TEMPERATURE 0 // [-50 -45 -40 -35 -30 -25 -20 -15 -10 -5 0 5 10 15 20 25 30 35 40 45 50]
// Color grading: temperature shift (-cool / +warm)
#define LOOK_WARM_SATURATION 104 // [80 85 90 95 100 102 104 106 108 110 115 120]
#define LOOK_CYAN_SATURATION 106 // [80 85 90 95 100 102 104 106 108 110 115 120]
#define LOOK_GREEN_SATURATION 100 // [80 85 90 95 100 102 104 106 108 110 115 120]
// Natural overworld daylight only; chromatic masks preserve greys and night colours.
#define AIR_SHAFT_COLOR 1 // [0 1]
// 0 follows terrain light; 1 uses a mildly warm, luminance-matched air-scattering tint.
//#define BLOOM // [false true]
// A narrow visible-sky halo, independent of general scene/underwater Bloom.
#define CELESTIAL_BLOOM // [false true]
// Optional Bloom: underwater composition/capture + display mip consumption.
#define BLOOM_QUALITY 0 // [0 1 2]
// Capture source reads: low 4, balanced 5, high 13; all keep threshold and knee.
#define BLOOM_STRENGTH 100 // [0 10 20 30 40 50 60 70 80 90 100 110 120 130 140 150 160 170 180 190 200]
// Bloom strength, %
#define PURKINJE_STRENGTH 0 // [0 10 20 30 40 50 60 70 80 90 100]
// Optional night blue shift; zero removes the colour operation. Independent of quality.
#define GODRAYS // [false true]
// With shadows: bounded quarter-size sunlight shafts, on in balanced/quality.
// Without shadows: the original half-size screen-space fallback.
#define GODRAYS_STRENGTH 100 // [0 10 20 30 40 50 60 70 80 90 100 110 120 130 140 150 160 170 180 190 200]
// Godrays strength, %
//#define GODRAYS_SUN_OCCLUSION // [false true]
// Godrays sun occlusion (one probed pixel fades the whole beam field when the
// solar disc is behind geometry; needs in-game A/B, see qa/session-log.md)
#define DITHERING // [false true]
// IGN output dithering (banding suppression, after any spatial AA)
#define ANTIALIASING 1 // [0 1 2 3]
// 0 off, 1 display-space FXAA, 2 HDR temporal AA with projection jitter, 3 SMAA 1x.
//#define VIGNETTE // [false true]
// Vignette (explicitly OFF by default, design 4.4)

// --- COLOURS: independent of quality profiles ---
#define OVERWORLD_LOOK 1 // [0 1]
// 0 follows the existing palette; 1 adds the fresh natural overworld look.
// Manual colour controls remain relative adjustments; quality profiles keep this choice.
#define COLOR_STYLE 0 // [0 1 2 3]
// 0 native; 1 warm natural; 2 cool clear; 3 soft. RGB gains stack on the style.
#define TINT_SKY_DAY_TOP_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DAY_TOP_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DAY_TOP_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DAY_HORIZON_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DAY_HORIZON_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DAY_HORIZON_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DAWN_TOP_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DAWN_TOP_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DAWN_TOP_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DAWN_HORIZON_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DAWN_HORIZON_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DAWN_HORIZON_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DUSK_TOP_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DUSK_TOP_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DUSK_TOP_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DUSK_HORIZON_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DUSK_HORIZON_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_DUSK_HORIZON_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_NIGHT_TOP_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_NIGHT_TOP_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_NIGHT_TOP_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_NIGHT_HORIZON_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_NIGHT_HORIZON_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SKY_NIGHT_HORIZON_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SUN_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SUN_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_SUN_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_DAWN_SUN_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_DAWN_SUN_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_DAWN_SUN_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_DUSK_SUN_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_DUSK_SUN_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_DUSK_SUN_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_MOON_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_MOON_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_MOON_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_AMBIENT_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_AMBIENT_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_AMBIENT_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_BLOCK_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_BLOCK_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_BLOCK_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_CAVE_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_CAVE_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_CAVE_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_END_LIGHT_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_END_LIGHT_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_END_LIGHT_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_END_AMBIENT_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_END_AMBIENT_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_END_AMBIENT_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_END_SKY_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_END_SKY_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_END_SKY_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_NETHER_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_NETHER_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define TINT_NETHER_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define LOOK_SHADOWS_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define LOOK_SHADOWS_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define LOOK_SHADOWS_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define LOOK_MIDS_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define LOOK_MIDS_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define LOOK_MIDS_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define LOOK_HIGHS_R 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define LOOK_HIGHS_G 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]
#define LOOK_HIGHS_B 100 // [0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200]

// --- PERFORMANCE + ADVANCED ---
#define OVERWORLD_BUDGET 1 // [0 1 2]
// Main-world budget: 0 uses raw options; 1 caps shadows at 1536/112;
// 2 is the tighter frame-rate budget (1024 ceiling, earlier water fading). Active budgets also use
// per-corner software shadow comparison. Ceilings never raise lighter raw options or enable
// effects. Colour is independent; Nether and End retain their own settings.
#define WAVING_FOLIAGE // [false true]
// Vertex-animated foliage sway (wind params via custom uniforms)
#define WAVING_FOLIAGE_STRENGTH 50 // [0 25 50 75 100]
// Foliage sway strength, %
//#define VOXY_SUPPORT // [false true]
// Reserved Voxy integration switch; distant-terrain rendering is not implemented.
// Iris keeps this option only because lib/uniforms.glsl references it; the real
// Voxy integration (voxy.json patch + Voxy programs) is still pending (owner C5).

// Internal budget predicates. Defined before the engine knobs below because the
// preprocessor is single-pass: ASTRA_OVERWORLD_OPTIMIZED only in the overworld with
// OVERWORLD_BUDGET > 0, ASTRA_OVERWORLD_AGGRESSIVE only in the overworld at budget 2.
// Other dimensions never define either macro.
#if !defined DIMENSION_NETHER && !defined DIMENSION_END && OVERWORLD_BUDGET > 0
#define ASTRA_OVERWORLD_OPTIMIZED
#endif
#if !defined DIMENSION_NETHER && !defined DIMENSION_END && OVERWORLD_BUDGET == 2
#define ASTRA_OVERWORLD_AGGRESSIVE
#endif
#if !defined DIMENSION_NETHER && !defined DIMENSION_END && OVERWORLD_LOOK == 1
#define ASTRA_OVERWORLD_NATURAL
#endif
// Plane-corrected surface corners have four different references. A raw gather
// compares all four in one vector operation; hardware needs four separate
// gathers. Volume/water retain the same compare-before-weight semantics.
// Raw settings select the mode outside the active main-world budget.
#ifdef ASTRA_OVERWORLD_OPTIMIZED
#define ASTRA_SHADOW_FILTER_MODE SHADOW_FILTER_SOFTWARE
#else
#define ASTRA_SHADOW_FILTER_MODE SHADOW_FILTER_MODE
#endif

// ------------------------------------------------------------
// ENGINE KNOBS (design.md 4.1 / 5) - the engine reads these const names, not macros.
// "const = MACRO" is resolved by Iris at load time; OptiFine would need literals here,
// which Astra does not support (design.md 1.2: Iris-only).
// ------------------------------------------------------------
#ifdef DIMENSION_NETHER
// This pass captures the fixed 64^3 voxel volume and clips every raster
// primitive. Its unused depth/color targets do not need the surface-shadow
// resolution or hundreds of blocks of submitted terrain. A 48-block box
// covers the +/-32 capture range, camera fraction and section-aligned margin.
// Keep this bound paired with ASTRA_NETHER_VOXEL_SIZE if that volume changes.
const int   shadowMapResolution = 64;
const float shadowDistance = 48.0;
const float shadowDistanceRenderMul = 1.0;
#elif defined DIMENSION_END
const int   shadowMapResolution  = SHADOW_RESOLUTION;  // shadow map is square
const float shadowDistance       = SHADOW_DISTANCE;    // blocks
const float shadowDistanceRenderMul = 1.5;             // shadow frustum extent, x shadowDistance
#else
// Overworld ceilings: priority at most 1536/112, tightened at most 1024/112.
// Keep lighter raw selections. Preprocessor branches expose simple values to Iris's
// directive reader, which cannot evaluate min() or arithmetic in these engine knobs.
#ifdef ASTRA_OVERWORLD_OPTIMIZED
#ifdef ASTRA_OVERWORLD_AGGRESSIVE
    #if SHADOW_RESOLUTION < 1024
const int   shadowMapResolution = SHADOW_RESOLUTION;
    #else
const int   shadowMapResolution = 1024;
    #endif
#else
    #if SHADOW_RESOLUTION < 1536
const int   shadowMapResolution = SHADOW_RESOLUTION;
    #else
const int   shadowMapResolution = 1536;
    #endif
#endif
#if SHADOW_DISTANCE < 112
const float shadowDistance = SHADOW_DISTANCE;
#else
const float shadowDistance = 112.0;
#endif
const float shadowDistanceRenderMul = 1.125;
#else
const int   shadowMapResolution  = SHADOW_RESOLUTION;  // shadow map is square
const float shadowDistance       = SHADOW_DISTANCE;    // blocks
    #if SHADOW_FILTER_QUALITY < 2
// Low/balanced trim the outer caster margin. Near geometry remains captured;
// distant, low-angle shadows from beyond this margin may be approximated away.
const float shadowDistanceRenderMul = 1.125;
    #else
const float shadowDistanceRenderMul = 1.5;             // shadow frustum extent, x shadowDistance
    #endif
#endif
#endif
// Iris's world-grid snap cannot align texels after radial distortion: crossing
// a half-block cell moves the whole nonlinear map abruptly. Zero disables this
// snap (ShadowMatrices explicitly returns), allowing continuous main-world motion.
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
const float shadowIntervalSize   = 0.0;
#else
const float shadowIntervalSize   = 0.5;
#endif
// Both Steadfast and Solas use this orbit; Iris applies it to sky and shadow matrices.
const float sunPathRotation = -40.0; // [-60.0 -50.0 -40.0 -30.0 -20.0 -10.0 0.0 10.0 20.0 30.0 40.0 50.0 60.0]
// noisetex/noise.png were removed: nothing sampled them (consolidated review E4).
const int   noiseTextureResolution = 256;              // engine default kept explicit

// --- SC-13 (design.md 4.1): the three shadow engine knobs, semantics frozen there ---
// Iris multiplies shadowDistance * shadowDistanceRenderMul * this ratio.
// Confirmed in Iris 1.11.2 ShadowRenderer: renderShadows multiplies the two
// multipliers before createShadowFrustum applies the pack distance (qa/open-premises.md P-2).
// Literal table for all advertised options: Iris's directive reader cannot
// evaluate arithmetic. Pair the table with the selected 1.125 or 1.5 caster
// multiplier, preserving each advertised entity distance. Nether uses a separate 48-block capture box; its entity
// primitives are raster-clipped and do not populate the terrain voxel field.
// The overworld budget caps entity casters at 32 blocks. Its literal ratios must
// follow the capped shadow distance, including lighter raw distances below 112.
#if defined ASTRA_OVERWORLD_OPTIMIZED
#if SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.444444444;
#elif SHADOW_DISTANCE == 80
const float entityShadowDistanceMul = 0.355555556;
#elif SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.296296296;
#else
const float entityShadowDistanceMul = 0.253968254;
#endif
#elif !defined DIMENSION_NETHER && !defined DIMENSION_END && SHADOW_FILTER_QUALITY < 2
#if SHADOW_DISTANCE == 64
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.444444444;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.666666667;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.888888889;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 1.333333333;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 1.777777778;
#endif
#elif SHADOW_DISTANCE == 80
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.355555556;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.533333333;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.711111111;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 1.066666667;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 1.422222222;
#endif
#elif SHADOW_DISTANCE == 96
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.296296296;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.444444444;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.592592593;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.888888889;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 1.185185185;
#endif
#elif SHADOW_DISTANCE == 112
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.253968254;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.380952381;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.507936508;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.761904762;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 1.015873016;
#endif
#elif SHADOW_DISTANCE == 128
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.222222222;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.333333333;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.444444444;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.666666667;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.888888889;
#endif
#elif SHADOW_DISTANCE == 160
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.177777778;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.266666667;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.355555556;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.533333333;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.711111111;
#endif
#elif SHADOW_DISTANCE == 192
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.148148148;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.222222222;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.296296296;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.444444444;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.592592593;
#endif
#else // SHADOW_DISTANCE == 256
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.111111111;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.166666667;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.222222222;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.333333333;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.444444444;
#endif
#endif
#else
#if SHADOW_DISTANCE == 64
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.333333333;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.500000000;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.666666667;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 1.000000000;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 1.333333333;
#endif
#elif SHADOW_DISTANCE == 80
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.266666667;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.400000000;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.533333333;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.800000000;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 1.066666667;
#endif
#elif SHADOW_DISTANCE == 96
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.222222222;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.333333333;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.444444444;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.666666667;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.888888889;
#endif
#elif SHADOW_DISTANCE == 112
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.190476190;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.285714286;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.380952381;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.571428571;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.761904762;
#endif
#elif SHADOW_DISTANCE == 128
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.166666667;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.250000000;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.333333333;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.500000000;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.666666667;
#endif
#elif SHADOW_DISTANCE == 160
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.133333333;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.200000000;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.266666667;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.400000000;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.533333333;
#endif
#elif SHADOW_DISTANCE == 192
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.111111111;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.166666667;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.222222222;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.333333333;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.444444444;
#endif
#else // SHADOW_DISTANCE == 256
#if ENTITY_SHADOW_DISTANCE == 32
const float entityShadowDistanceMul = 0.083333333;
#elif ENTITY_SHADOW_DISTANCE == 48
const float entityShadowDistanceMul = 0.125000000;
#elif ENTITY_SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.166666667;
#elif ENTITY_SHADOW_DISTANCE == 96
const float entityShadowDistanceMul = 0.250000000;
#else // ENTITY_SHADOW_DISTANCE == 128
const float entityShadowDistanceMul = 0.333333333;
#endif
#endif

#endif

// Both modes pair surface depth comparisons with each texel's caster colour.
// Hardware mode retains bilinear comparison filtering for opaque volume queries.
#if ASTRA_SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
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

// AA modes: 0 off, 1 display-space FXAA, 2 HDR temporal AA.
// Keep the public Bloom switch discoverable while zero strength removes its
// producers, pyramids and display reads. Properties use the same two conditions.
#ifdef BLOOM
#if BLOOM_STRENGTH > 0
    #define ASTRA_BLOOM
#endif
#endif
#if defined CELESTIAL_BLOOM && !defined ASTRA_BLOOM && !defined DIMENSION_NETHER && DEBUG_VERTEX_AO == 0
    #define ASTRA_CELESTIAL_BLOOM
#endif
#if !defined DIMENSION_NETHER && !defined DIMENSION_END && DEBUG_VERTEX_AO == 0
    // Zero sky intensity has no directional term or bent-normal sky swap.
    #ifdef DIRECTIONAL_SKYLIGHT
    #if SKYLIGHT_STRENGTH > 0
        #define ASTRA_DIRECTIONAL_SKYLIGHT
    #endif
    #endif
    #if defined SCREENSPACE_AO && defined SHADOWS && AO_STRENGTH > 0
        #define ASTRA_SSAO
    #endif
#endif
// R2/H3: the volume march is overworld-only and does not depend on the AO debug
// mode, TAA or shadows (without SHADOWS the sun term keeps cloud shadow only).
#if !defined DIMENSION_NETHER && !defined DIMENSION_END && defined VOLUMETRIC_FOG && VOLUME_FOG_DENSITY > 0
    #define ASTRA_VOLUME_FOG
#endif
#if defined GODRAYS && GODRAYS_STRENGTH > 0 && defined SHADOWS && !defined ASTRA_VOLUME_FOG && !defined DIMENSION_NETHER && !defined DIMENSION_END && DEBUG_VERTEX_AO == 0
    #define ASTRA_TREE_SHAFTS
#endif
// R6/T3: the screen-cloud history is overworld-only (planar clouds are) and
// deliberately independent of ASTRA_TAA: it keeps its own previous-frame state
// so cloud stability survives ANTIALIASING != 2. CLOUD_TEMPORAL (above)
// selects the independent resolve instead of the current-frame sheet.
#if !defined DIMENSION_NETHER && !defined DIMENSION_END && CLOUD_MODE == CLOUD_PLANAR
    #ifdef CLOUD_TEMPORAL
    #define ASTRA_CLOUD_TEMPORAL
    #endif
#endif
// A same-frame low-frequency gradient-sky table reuses the raw cloud target only
// when screen clouds do not own it. Minishita and its clouds do not read this table.
// Celestial glare, stars and discs stay analytic.
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
#if SKY_MODE == SKY_GRADIENT && (CLOUD_MODE != CLOUD_PLANAR || defined CLOUD_TEMPORAL)
    #define ASTRA_GRADIENT_SKY_CACHE
#endif
#endif
// The AO diagnostic stays unjittered even when temporal AA is selected.
#if ANTIALIASING == 2 && DEBUG_VERTEX_AO == 0
    #define ASTRA_TAA
#endif

#if (ANTIALIASING == 1 || ANTIALIASING == 3) && DEBUG_VERTEX_AO == 0
#define ASTRA_SPATIAL_AA
#endif
#if ANTIALIASING == 3 && DEBUG_VERTEX_AO == 0
#define ASTRA_SMAA
#endif

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
#if !defined DIMENSION_NETHER && !defined DIMENSION_END && CLOUD_MODE == CLOUD_PLANAR
#if defined GODRAYS && GODRAYS_STRENGTH > 0 && !defined ASTRA_VOLUME_FOG && !defined ASTRA_TREE_SHAFTS
    #define ASTRA_GODRAYS_CLOUD_OCCLUSION
#endif
#endif
// SC-23: clear colors must be 4-arg constructors with plain literal components
// (Iris parses each argument with Float.parseFloat - no expressions, no 1-arg splat).
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
// Alpha of this clear colour is the standing-water mask's own ZERO: sky, water-surface
// and translucent pixels keep it, so a 1.0 here would open deferred's puddle gate on
// every one of them (consolidated review A2 / F-42). The .r marker is unchanged.
const vec4 colortex3ClearColor = vec4(0.498, 0.0, 0.0, 0.0);  // 127/255 skylight marker
// R2/H3 volume S/T: the identity segment (no scattering, full transmittance). The
// production pass overwrites every texel it owns each frame; the clear only covers
// frames where the pass is enabled but a dimension slot does not run it.
const vec4 colortex23ClearColor = vec4(0.0, 0.0, 0.0, 1.0);
const vec4 shadowcolor0ClearColor = vec4(1.0, 1.0, 1.0, 1.0);
const vec4 colortex5ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex6ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const bool colortex6Clear = false;

#endif
