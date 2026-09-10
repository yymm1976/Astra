#ifndef ASTRA_GLOBAL_DIMENSION_NETHER_GLSL
#define ASTRA_GLOBAL_DIMENSION_NETHER_GLSL

// Astra v1 — global/dimension/nether.glsl
// The Nether's independent atmosphere, fog and lighting path (design.md 4.5).
//
// Why this file exists as a SEPARATE path rather than as branches inside the overworld
// modules: the Nether has no sun and no sky light, so the overworld lighting composer
// (global/lighting/diffuse.glsl, C1) has nothing to compute — its sky-ambient term and its
// shadow-mapped direct term are both meaningless here. design.md 4.5 asks for 光照路径重构,
// not for a tinted copy of the overworld path. Mellow v3.4 makes the same call in
// global/lighting/light_colors.vsh: under DIMENSION_NETHER it sets `SUN_DIRECT = vec3(0)` and
// returns a flat ambient, i.e. the direct-light path is switched off at the source. Astra does
// that by giving E1 a whole nether composer to call INSTEAD of diffuse_lighting().
//
// Provenance (see THIRD-PARTY.md; Solas licence is undeclared = default copyright, Mellow is MIT):
//   - Structure-level borrowing from Solas V2.2b:
//       lib/color/netherColor.glsl       -> nether_atmosphere_tint() (normalize + quarter-power lift)
//       lib/atmosphere/fog.glsl:52-62    -> nether_fog() base curve (linear-near + pow4-far, tint * 0.25)
//       lib/atmosphere/lpvFog.glsl:84-93 -> nether_cloud_glow() (y-banded slice blend of a 2D value
//                                           noise, threshold-and-sharpen, crest term `c * (1 + c^2)`)
//       lib/lighting/gbuffersLighting.glsl:150 -> the base ambient floor `pow(tint, 0.75) * 0.03`
//       lib/lighting/gbuffersLighting.glsl:177 -> the night-vision green lift
//     PROVENANCE: adapted from Solas V2.2b (licence undeclared) - REWRITE REQUIRED before distribution
//     Solas evaluates its cloudy fog inside a voxel/LPV raymarch; Astra has no voxel volume
//     (design.md 2.1: forward, zero compute), so the cloud term is re-derived here as a single
//     per-fragment evaluation on the fog itself. Only the noise-shaping structure is borrowed.
//   - Idea-level borrowing from Mellow v3.4 (MIT) by TheCMK:
//       global/atmosphere/sky.glsl:138-141 -> the nether sky is derived from the vanilla biome
//                                             fog colour rather than hardcoded (see below)
//       global/atmosphere/fog.glsl:16-30   -> the nether's border fog closes in EARLIER than the
//                                             overworld's (Mellow does it by squaring the falloff
//                                             exponent twice fewer; Astra does it with the pow4
//                                             far term above, which is the same shape)
//     License: MIT - see THIRD-PARTY.md
//   - The height-anchored lava-sea glow, the red/orange sky gradient, the separately tuned
//     blocklight curve and the dark-area breathing are Astra's own (design.md 4.5 items that
//     neither reference implements).
//   Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Design note — why the atmosphere colour is DERIVED, not a constant:
//   Both references converge on reading vanilla's per-biome `fogColor` for the nether tint. That
//   single choice makes all five nether biomes distinct for free (nether wastes dull red, crimson
//   forest deep red, warped forest teal, soul sand valley pale grey-cyan, basalt deltas grey-brown)
//   with zero palette data and zero CPU cost, and it stays correct if Mojang retunes a biome.
//   Solas then lifts it with a quarter power, because vanilla's nether fog colours are very dark
//   and a raw linear read would leave the atmosphere nearly black. Astra keeps both steps.
//
// Uniforms: cameraPosition, frameTimeCounter, noisetex (via lib/noise.glsl), borderFogDistance,
//           blindness, isEyeInWater (all frozen in lib/uniforms.glsl).
// Consts:   NETHER_FOG_DENSITY, UNDERWATER_FOG_DENSITY, SKY_FOG_STRENGTH, BORDER_FOG,
//           BLOCKLIGHT_STRENGTH, HANDHELD_LIGHTING, EMISSIVE_STRENGTH (lib/settings.glsl);
//           BLOCKLIGHT_COLOR, MIN_AMBIENT_COLOR (lib/colors.glsl); the NETHER_* tuning constants
//           below are local to this module.
// Owner: C3. Consumers: program/lit.fsh (E1, lighting), program/deferred.fsh or lit.fsh (E1, fog),
//                       program/sky.fsh (D2, sky).
// Requires (NOT included here — program/* guarantees the order, design.md 3.2 layer 2/3, matching
//   lib/colors.glsl and global/lighting/diffuse.glsl which likewise include no settings/uniforms):
//     lib/settings.glsl              -> the option macros listed above
//     lib/uniforms.glsl              -> the uniforms listed above
//     global/lighting/blocklight.glsl (C1, SIBLING) -> held_light_strength()
//     global/lighting/diffuse.glsl    (C1, SIBLING) -> ambient_strength()
//   globals may not include globals (SC-10), so C1's two helpers arrive by program-ordered
//   inclusion: lit.fsh must include /global/lighting/blocklight.glsl and
//   /global/lighting/diffuse.glsl BEFORE this file — the order C1's own headers already specify
//   (colors -> blocklight -> diffuse). C3 re-derives neither the handheld ramp nor the directional
//   ambient curve: one owner, one definition.
//
// Interface contract (E1 unfrozen — every non-frozen input is a documented parameter):
//   ⚠ REQUIRED FROM E1: `uniform vec3 fogColor;` (an Iris built-in: vanilla's current fog colour)
//   is NOT in lib/uniforms.glsl, and C3 may not add it — that file is E1's to extend ("Owner: E1
//   extends with any additional built-in the modules it wires in need"). Until E1 declares it, the
//   biome fog colour is handed over as NetherParams.biomeFogColor. Mellow and Solas both read this
//   built-in directly; Astra routes it as a parameter so no C-series module opens a uniform.
//   worldNormal  — player-relative world space, normalized (same convention as C1/B1).
//   playerPos    — camera-relative world space; absolute Y is playerPos.y + cameraPosition.y.
//   blockLight   — 0..1 lightmap (1 = light level 15). skyLight is deliberately NOT a parameter:
//                  there is no sky light in the nether, and accepting one would invite a caller to
//                  feed the overworld lightmap back in.
//   subsurfaceScatter is likewise absent, not forgotten. C1's diffuse_lighting uses it to swap the
//                  directional ambient for a flat 0.7071 (45°) so backlit foliage does not go black
//                  — it is a wrap term on the DIRECT light. The nether has no direct light, so there
//                  is nothing to wrap: nether foliage takes the same ambient as netherrack and the
//                  parameter would be dead. If E1 wants leaves/flowers to read differently here, the
//                  place to do it is a term in this composer, not a carried-over flag.
//   emissiveMask / portalMask — E1-resolved material categories, 0.0 or 1.0, exactly like the
//                  subsurfaceScatter/isLeaves/isGlass booleans in C1's diffuse_lighting contract.
//   time         — frameTimeCounter (frozen); the caller may scale it.
//
// Perf (task acceptance: 帧率同主世界标准): the nether path is strictly CHEAPER than the overworld
// one — no shadow-map sample at all (there is no directional light to shadow), no sky evaluation
// unless skyFogStrength > 0, and the cloud term is two noisetex lookups (design.md 5: 噪声优先查表).

#include "/lib/colors.glsl"
#include "/lib/encoding.glsl"
#include "/lib/noise.glsl"

// Everything this module needs that is not a frozen uniform. Same idiom as B2's FogParams and
// C1's LightParams: palette/CPU data travels as a struct, never as a privately opened uniform.
struct NetherParams {
	vec3  biomeFogColor;   // vanilla fogColor (sRGB-ish 0..1), per nether biome — E1 supplies
	float nightVision;     // built-in (not frozen): 0..1, lifts the ambient floor only
	float heldLightBase;   // CPU pow(heldBlockLightValue / 15, 4), 0..1 — see C1 blocklight.glsl
};

// ---------------------------------------------------------------------------
// Tuning constants. All nether-local: none of them belongs in grading.glsl (C6 owns the
// image-wide style layer) or in lib/colors.glsl (C1 owns the SHARED light palette; these
// colours are used by this dimension only and would be dead weight everywhere else).
// ---------------------------------------------------------------------------

// Vanilla's nether lava sea surface plane. Lava source blocks fill up to Y=31, so the exposed
// surface sits at Y=32. UNVERIFIED against a live world (SC-6: no Iris instance on this machine).
const float NETHER_LAVA_SEA_Y = 32.0;

// Base ambient floor. Solas uses exactly `pow(netherColSqrt, vec3(0.75)) * 0.03` as the nether's
// entire scene lighting; Astra keeps that scale but adds the lava glow and the blocklight curve
// on top, so it reads as the floor of a lit space rather than the whole lighting model.
//
// ⚠ DEAD (rollback only, 2026-09-10). nether_lighting() now uses the reference's ambient term
// (`(netherColor + 0.5 * lavaLightColor) * (0.9 + 0.45 * vsBrightness)`), so nothing reads this
// constant. Kept so the pre-port ambient is one edit away; see docs/handoffs/nether.md.
const float NETHER_AMBIENT_INTENSITY = 0.030;

// Solas's night-vision lift (gbuffersLighting.glsl:177), applied to the ambient only.
//
// ⚠ DEAD (rollback only, 2026-09-10): the port uses the reference's own night-vision tint,
// NETHER_NIGHT_VISION_TINT_REF = vec3(0.5, 0.5, 0.75) (minimumLighting.glsl:14), which is blue
// rather than this green. That hue change is a recorded deviation, not an oversight.
const vec3  NETHER_NIGHT_VISION_TINT = vec3(0.2, 0.3, 0.2);

// Lava-sea glow. HDR on purpose — folded back by the tonemap (C6), same reasoning as C1's
// BLOCKLIGHT_COLOR in lib/colors.glsl.
//
// Magnitude and hue are aligned to Complementary r5.9 (2026-09-02), which adds its lava term in the
// same place Astra does — to the ambient, before the albedo multiply — with
//   lib/common.glsl:815                `lavaLightColor = vec3(0.15, 0.06, 0.01)`
//   lib/lighting/mainLighting.glsl:519 `ambientColorM += lavaLightColor
//                                         * pow2(absNdotN * 0.5 + max0(-NdotU))
//                                         * (0.7 + 0.35 * vsBrightness)`
//   lib/colors/lightAndAmbientColors.glsl:81  `ambientColor = (netherColor + 0.5 * lavaLightColor)
//                                               * (0.9 + 0.45 * vsBrightness)`
// At vsBrightness = 1 that is a peak of (0.259, 0.1035, 0.0173): R 0.259 is the reference's ENTIRE
// lava budget, and its hue is 1 : 0.4 : 0.0667.
//
// Astra shipped vec3(1.60, 0.42, 0.08) at intensity 0.30, i.e. a peak of (0.96, 0.252, 0.048) after
// concentration 2.0 and directional 1.0 — 3.7x the reference's total, 6.1x its directional term,
// and redder (1 : 0.2625 : 0.05). That is the 又红又亮. This is a magnitude error, not a placement
// error: the reference's lava term is not distance- or height-attenuated either.
//
// The engine already carries lava's LOCAL light — Astra/shaders/block.properties:52 registers
// minecraft:lava and minecraft:magma_block as emitters, so the lightmap supplies attenuated,
// occluded lava light. This constant is only the dimension-wide atmospheric wash on top of it.
const vec3  NETHER_LAVA_GLOW_COLOR   = vec3(1.60, 0.64, 0.107);  // = reference hue 1 : 0.4 : 0.0667
const float NETHER_LAVA_GLOW_HEIGHT  = 28.0;   // vertical reach ABOVE the sea, blocks
const float NETHER_LAVA_GLOW_DEPTH   = 12.0;   // extra concentration BELOW the surface, blocks
// Peak = 1.60 * 0.08 * 2.0 (submersion) * 1.0 (direction) = (0.256, 0.102, 0.017),
// landing on the reference's (0.259, 0.1035, 0.0173). Was 0.30, i.e. 3.75x this.
const float NETHER_LAVA_GLOW_INTENSITY = 0.08;

// The same hue folded into 0..1, for the ADDITIVE terms (the fog colour and the sky pool).
// NETHER_LAVA_GLOW_COLOR above is an HDR lighting constant and is safe on the lighting path because
// there it is multiplied by an albedo <= 1, which absorbs the headroom. An additive fog or sky term
// has no albedo, so the raw peak lands in the frame unabsorbed. Dividing by the peak channel keeps
// the hue and the height/depth response exactly.
const vec3  NETHER_LAVA_ADD_COLOR = NETHER_LAVA_GLOW_COLOR * (1.0 / 1.60);

// ===========================================================================
// Complementary r5.9 逐字移植的下界光照常量
//   来源：_analysis/complementary/Reimagined/shaders/（版本 r5.9，2026-09-02）
//   原则：能用参考表达式的地方一律照抄，不自行推导形态或量级。
// ===========================================================================

// common.glsl:815 —— 参考全部熔岩氛围光的唯一常量，就这么大。
const vec3  NETHER_LAVA_LIGHT_COLOR = vec3(0.15, 0.06, 0.01);

// common.glsl:748 `float vsBrightness = clamp(screenBrightness, 0.0, 1.0);`
// screenBrightness 是原版亮度滑条（0..1）。**Astra 没有这个 uniform**，
// 而本模块的契约是不自行打开 uniform（见文件头「Uniforms」段），
// 因此这里取原版滑条的默认值 0.5。
// ⚠ 要让它动态化需要 E1 在 lib/uniforms.glsl 声明 screenBrightness —— 已记为 P-002。
// 参考里它的作用范围：
//   环境 `(0.9 + 0.45 * vsBrightness)`    → 0.90 ~ 1.35
//   熔岩 `(0.7 + 0.35 * vsBrightness)`    → 0.70 ~ 1.05
//   下限 `vec3(0.005625 + vsBrightness * 0.043)` → 0.0056 ~ 0.0486
const float NETHER_VS_BRIGHTNESS = 0.5;

// minimumLighting.glsl:8 —— 下界暗部下限的色相（轻微偏冷，不是强蓝）
const vec3  NETHER_FLOOR_TINT = vec3(0.45, 0.475, 0.6);
// minimumLighting.glsl:14 —— 夜视
const vec3  NETHER_NIGHT_VISION_TINT_REF = vec3(0.5, 0.5, 0.75);

// Fog curve. Solas: `fog = lViewPos * 0.004; fog += 6.0 * pow4(lWorldPos / far); fog = 1 - exp(-fog)`.
// The near term is LINEAR in distance (the overworld's is pow3), which is what makes the nether
// feel closed in from the first few blocks; the pow4 far term is the tighter border ramp that
// Mellow gets by reducing its falloff exponent. NETHER_FOG_DENSITY (the user's %) scales both.
const float NETHER_FOG_NEAR_COEFF = 0.0040;
const float NETHER_FOG_FAR_COEFF  = 6.0;
const float NETHER_FOG_FAR_EXP    = 4.0;
const float NETHER_FOG_TINT       = 0.25;      // Solas: fogCol = netherColSqrt * 0.25

// Drifting glow clouds (Solas NETHER_CLOUDY_FOG). Solas scales world position by
// VF_NETHER_FREQUENCY = 3.0, samples the noise plane at npos.xz * 0.001 in texture space, steps
// the y-band by floor(npos.y * 0.1) * 0.2, and scrolls +X at VF_NETHER_SPEED = 6.0.
// Astra's lib/noise.glsl takes coordinates in TEXEL space (it divides by noiseTextureResolution
// internally), so the two texture-space constants are converted rather than copied:
//   plane scale  = 0.001 * noiseTextureResolution * 0.75 = 0.001 * 256 * 0.75 = 0.192
//   band offset  = 0.20  * noiseTextureResolution * 0.75 = 0.20  * 256 * 0.75 = 38.4
// which reproduces Solas's ~333-block horizontal period and its 10-block vertical banding exactly
// at the shipped ENGINE KNOB values. noiseTextureResolution is written as a literal here on
// purpose: a const initializer must be constant, and the conversion above is the documented
// derivation. UNVERIFIED tuning defaults (SC-6) — E2/visual pass to retune.
const float NETHER_CLOUD_FREQUENCY   = 3.0;
const float NETHER_CLOUD_SPEED       = 6.0;
const float NETHER_CLOUD_STRENGTH    = 1.5;
const float NETHER_CLOUD_SCALE       = 0.192;
const float NETHER_CLOUD_BAND_OFFSET = 38.4;
const float NETHER_CLOUD_BAND_HEIGHT = 10.0;   // Solas: npos.y * 0.1
const float NETHER_CLOUD_THRESHOLD   = 0.45;
const float NETHER_CLOUD_GAIN        = 8.0;
// Scale on the cloud term's contribution to the FOG COLOUR. Solas needs no such constant because it
// accumulates the term across a raymarch (per-sample `(currentDist / maxDist) / sampleCount` and a
// 0.5 nether visibility multiplier); Astra evaluates it once per fragment, so the raw product —
// crest up to 2.0 * NETHER_CLOUD_STRENGTH, times a proximity concentration up to 2.0 — would reach
// ~6x the tint. 0.10 brings that to 0.6x the tint, and nether_fog() additionally folds the whole
// additive term through 1 - exp(-x), so this scale now only sets the level rather than having to
// guarantee the bound on its own. UNVERIFIED (SC-6).
const float NETHER_CLOUD_FOG_SCALE   = 0.10;

// Blocklight curve, separately tuned (design.md 4.5: blocklight 曲线单独调). C1 uses pow(_, 4.0),
// which gives tight torch pools; the nether has almost no other light, so a lower exponent widens
// the pools and softens their edge — that gradual falloff is what keeps unlit nether rock reading
// as "dim" instead of "dead". UNVERIFIED (SC-6).
const float NETHER_BLOCKLIGHT_EXPONENT = 2.75;

// Dark-area breathing: a slow, few-percent undulation on the ambient floor ONLY (never on
// blocklight), so the nether's unlit pockets feel like they have air in them instead of sitting
// at a fixed black level. Amplitude is deliberately small; set to 0.0 to disable in one edit.
// UNVERIFIED (SC-6) and the one constant here most likely to want retuning by eye.
//
// ⚠ DEAD (rollback only, 2026-09-10). Complementary r5.9 has no equivalent mechanism, so the
// reference port in nether_lighting() no longer reads these three; the whole breathing term was
// deleted with the old additive composer. Kept deliberately so one edit restores the Astra
// behaviour if the port is rolled back — recorded as a design.md 4.5 conflict in
// docs/handoffs/nether.md. Delete together with NETHER_AMBIENT_INTENSITY above if the port stays.
const float NETHER_DARK_BREATHING   = 0.06;
const float NETHER_BREATHING_PERIOD = 11.0;    // seconds
const float NETHER_TAU              = 6.28318530718;

// Emissive / portal brightening (design.md 4.5: 发光体与传送门增亮). Both multiply on top of the
// user's EMISSIVE_STRENGTH, so the nether boost is a relative lift, not an override.
// nether_lighting() additionally scales the whole lift by the surface's luminance headroom
// (1 minus the Rec.709 luminance of the albedo), so an already-bright emitter cannot be pushed
// past 1 by the boost alone. Lava is the case that matters — see the note at the call site.
const float NETHER_EMISSIVE_BOOST    = 1.35;
const float NETHER_PORTAL_BOOST      = 2.20;
const float NETHER_PORTAL_SHIMMER    = 0.12;   // ±12% on the portal boost
const float NETHER_PORTAL_SHIMMER_RATE = 1.7;  // rad/s

// Sky gradient (design.md 4.5: 红/橙渐变天空). Multipliers on the derived biome tint: the zenith
// closes in darker, the horizon opens up brighter, and the lava sea lights the underside of the
// fog from below the horizon line.
const float NETHER_SKY_ZENITH     = 0.55;
const float NETHER_SKY_HORIZON    = 1.30;
const float NETHER_SKY_FALLOFF    = 1.6;
const float NETHER_SKY_LAVA_POOL  = 0.22;

// ---------------------------------------------------------------------------
// Atmosphere colour
// ---------------------------------------------------------------------------

// Per-biome nether tint. Solas: `netherCol = sqrt(normalize(fogColor + eps)); netherColSqrt =
// sqrt(netherCol)`, i.e. a quarter power of the hue-normalized vanilla fog colour. Astra runs the
// sRGB -> linear conversion FIRST (Mellow's sky path does `to_linear(fogColor.rgb)`; Solas reads it
// raw) because Astra's lighting is linear HDR end to end, so feeding a display-referred colour into
// it would darken the whole dimension. The epsilon inside normalize() is Mellow's NaN guard for a
// black fog colour.
//
// normalize() gives unit LENGTH, not unit luminance — that is the point: it keeps vanilla's hue and
// discards its very low brightness, then the quarter power lifts what is left into a usable range.
//
// ⚠ OPEN DECISION — this function and nether_color() below are the nether's TWO COLOUR SYSTEMS
// (2026-09-10 audit). Consumers today:
//   nether_lighting()  -> nether_color()             (the reference port; keeps vanilla's
//                                                     absolute brightness ordering between biomes)
//   nether_fog() / nether_sky() -> nether_atmosphere_tint()   (this function; normalizes
//                                                     brightness away, keeps only hue)
// They disagree on the same biomeFogColor by roughly 2.5x in magnitude AND in hue, so terrain
// lighting and the horizon (fog + sky) can read as different colour temperatures. Measured for a
// nether-wastes fog colour: this function gives (3.325, 1.995, 1.165), nether_color() gives
// (1.339, 0.803, 0.466).
//
// Why it was left split: unifying them either way is a visible design change that needs eyes on
// screen (SC-6), and the task table's 4.5 bullets for nether_sky()/nether_fog() are still pending
// a decision — see docs/handoffs/nether.md "尚未动、待你定的两处". Do NOT unify silently.
// Recommended resolution (unverified): move fog and sky onto nether_color() so all three share the
// reference's brightness ordering, then retire this function.
vec3 nether_atmosphere_tint(vec3 biomeFogColor) {
	vec3 linear = to_linear(biomeFogColor) + vec3(1e-6);
	return sqrt(sqrt(normalize(linear)));
}

// ---------------------------------------------------------------------------
// netherColor —— 参考的下界底色（逐字移植）
// ---------------------------------------------------------------------------

// Complementary r5.9 common.glsl:811，`NETHER_COLOR_MODE == 2`（「Biome Based」）的表达式：
//
//     vec3 netherColor = fogColor * 0.6 + 0.2 * normalize(fogColor + 0.0001);
//
// 与上面 nether_atmosphere_tint() 的**关键差别**：主项 `fogColor * 0.6` 不做归一化，
// 于是原版雾色的绝对亮度差被完整保留 —— 灵魂沙谷 `~0.1`、下界荒地 `~0.4`。
// nether_atmosphere_tint() 的 `normalize()` 会把亮度序抹掉，所有群系都落到 0.5~1.0，
// 这是「生物群系辨识度」的一个结构性缺陷（见参考报告 §12）。
//
// 模式 2 而不是模式 3（默认）：模式 3 用五张硬编码调色板，需要 5 个生物群系布尔 uniform，
// 属于 shaders.properties 的改动（公共边界）；模式 2 只需要 fogColor，本 worktree 内可实现。
//
// to_linear 是 Astra 独有的步骤（参考在显示域直接算）：Astra 的光照到合成是线性 HDR，
// 把显示域颜色直接喂进去会整体偏暗。已记录为对参考的一处偏离。
vec3 nether_color(vec3 biomeFogColor) {
	return to_linear(biomeFogColor * 0.6 + 0.2 * normalize(biomeFogColor + 0.0001));
}

// ---------------------------------------------------------------------------
// Lava-sea glow: the height/depth term the task table asks for
// (随高度/深度变化，贴近熔岩面更浓更亮)
// ---------------------------------------------------------------------------

// 1.0 at or below the lava surface, falling to 0.0 NETHER_LAVA_GLOW_HEIGHT blocks above it (by the
// shipped constants: worldY >= 32 + 28 = 60). smoothstep already clamps outside its edges, so the
// whole nether column is covered without an explicit clamp — including the ceiling bedrock shelf,
// which is above 60 and therefore gets no glow at all.
float nether_lava_proximity(float worldY) {
	return 1.0 - smoothstep(0.0, NETHER_LAVA_GLOW_HEIGHT, worldY - NETHER_LAVA_SEA_Y);
}

// Extra concentration for fragments BELOW the surface plane — inside the lava ocean itself, or in
// rock underneath it. Capped so digging down does not blow out to infinity.
float nether_lava_submersion(float worldY) {
	return smoothstep(0.0, NETHER_LAVA_GLOW_DEPTH, NETHER_LAVA_SEA_Y - worldY);
}

// The lighting-side lava term is now the reference's own expression and lives inline in
// nether_lighting() (mainLighting.glsl:519):
//
//     lavaLightColor * pow2(absNdotN * 0.5 + max0(-NdotU)) * (0.7 + 0.35 * vsBrightness)
//
// The old height/depth-anchored form — `0.75 - 0.25 * worldNormalY` scaled by a proximity term that
// rose below NETHER_LAVA_SEA_Y — has been REMOVED. Complementary r5.9 has no height term in its lava
// lighting at all: its vertical variation lives in the nether storm, which is anchored at Y = 28 and
// decays 10x faster BELOW the anchor (netherStorm.glsl:45-47).
//
// nether_lava_proximity() / nether_lava_submersion() are kept because nether_fog() still uses them
// for the fog's own height response.

// ---------------------------------------------------------------------------
// Drifting glow clouds (Solas NETHER_CLOUDY_FOG structure, Astra scales)
// ---------------------------------------------------------------------------

// A 3D-feeling cloud field out of a 2D value-noise texture: slice the noise plane by height band
// and interpolate between the current band's slice and the next one's. Two lookups, no 3D texture.
// Returns 0..1; the `c * (1 + c^2)` crest term keeps most of the volume flat and raises filaments,
// the same shaping C2's caustics uses.
float nether_cloud_glow(vec3 worldPos, float time) {
	vec3 at = worldPos * NETHER_CLOUD_FREQUENCY
	        + vec3(time * NETHER_CLOUD_SPEED, 0.0, 0.0);

	float band  = at.y * (1.0 / NETHER_CLOUD_BAND_HEIGHT);
	vec2  plane = at.xz * NETHER_CLOUD_SCALE + NETHER_CLOUD_BAND_OFFSET * floor(band);

	float cloudy = mix(noise(plane), noise(plane + NETHER_CLOUD_BAND_OFFSET), fract(band));
	cloudy = max(cloudy - NETHER_CLOUD_THRESHOLD, 0.0);
	cloudy = min(cloudy * NETHER_CLOUD_GAIN, 1.0);

	return cloudy * (1.0 + cloudy * cloudy) * NETHER_CLOUD_STRENGTH;
}

// ---------------------------------------------------------------------------
// Fog (design.md 4.5: 独立大气与雾曲线 — independent of the overworld's parameters)
// ---------------------------------------------------------------------------

// Drop-in replacement for B2's global/atmosphere/fog.glsl:fog_v2() in the nether: same return
// shape, vec4(fogColor, fogFactor) with the sky blend strength as an out parameter, so E1's call
// site stays `mix(sceneColor, fogColor + skyColor * skyFogStrength, fogFactor)` with skyColor
// coming from nether_sky() instead of the overworld sky.
//
// What is NOT reused from fog_v2, and why:
//   - atmosphereFogCoefficient / FOG_DENSITY: the overworld's pow(d,3) curve is CPU-precomputed for
//     a sun-lit atmosphere. The nether uses its own linear-near + pow4-far curve with
//     NETHER_FOG_DENSITY, so neither the uniform nor the overworld slider affects it.
//   - CAVE_FOG / skyLightStrength: the nether has no sky light gradient to switch on, so there is no
//     cave transition. The parameter is absent from the signature rather than ignored inside it.
//   - AIR_PERSPECTIVE / BIOME_TINT: both are sun-direction effects (fog_air_perspective dots against
//     worldSunVector). There is no sun. The biome influence arrives through the tint instead.
// The blindness / water / lava overrides ARE kept, with B2's shapes: they are dimension-independent
// player states, and dropping them here would silently remove them from the nether.
//
//   fragDistance        distance for the near term
//   borderFragDistance  distance for the pow4 far term; differs from fragDistance only for Voxy (C5)
//   playerPos           camera-relative fragment position; absolute Y drives the lava glow
vec4 nether_fog(
	out float skyFogStrength,
	NetherParams params,
	float fragDistance,
	float borderFragDistance,
	vec3 playerPos
) {
	vec3 tint = nether_atmosphere_tint(params.biomeFogColor);
	float densityScale = NETHER_FOG_DENSITY * 0.01;

	// Near: linear in distance. Far: pow4 border ramp that closes in earlier than the overworld's.
	float fogDensity = fragDistance * NETHER_FOG_NEAR_COEFF;
	#ifdef BORDER_FOG
		float farRatio = borderFragDistance > 0.0 ? borderFragDistance / borderFogDistance : 0.0;
		fogDensity += NETHER_FOG_FAR_COEFF * pow(farRatio, NETHER_FOG_FAR_EXP);
	#endif
	float fogFactor = 1.0 - exp(-fogDensity * densityScale);

	vec3 fogColor = tint * NETHER_FOG_TINT;

	// Lava glow fog: brighter close to the sea. The cloud field is modulated by the same proximity
	// term, so the drifting filaments concentrate over the lava and thin out up by the ceiling —
	// that coupling is the 随高度/深度变化 the task asks for.
	// NOTE — the fog's DENSITY deliberately does not react to proximity. This comment used to claim
	// it did ("denser AND brighter"); fogFactor is computed above and proximity never touches it.
	// Adding a density term would shorten the sight line over the lava sea, which is a 空间雾
	// decision that needs eyes on screen, so it is recorded in docs/handoffs/nether.md rather than
	// guessed at here.
	float worldY = playerPos.y + cameraPosition.y;
	float proximity = nether_lava_proximity(worldY);
	if (proximity > 0.0001) {
		float concentration = proximity * (1.0 + nether_lava_submersion(worldY));
		float cloud = nether_cloud_glow(playerPos + cameraPosition, frameTimeCounter);
		vec3 glow = NETHER_LAVA_ADD_COLOR * NETHER_LAVA_GLOW_INTENSITY
		          + tint * (cloud * NETHER_CLOUD_FOG_SCALE);
		// Folded through the same 1 - exp(-x) response the fog factor already uses, so the glow stays
		// monotonic in height and depth and is bounded below 1 per channel ON ITS OWN. A straight
		// `+=` had no bound at all: the cloud crest reaches NETHER_CLOUD_STRENGTH * 2.0 and the
		// concentration doubles below the sea. With the current constants that additive term peaks at
		// 0.68 / 0.59 / 0.53 on a neutral tint and folds to 0.49 / 0.44 / 0.41. Before this round's
		// lava cut it peaked at 1.48 / 0.77 / 0.57, which put the fog colour at R 1.70 / G 0.99 /
		// B 0.79 and washed out through the tonemap's highlight desaturation.
		fogColor += vec3(1.0) - exp(-glow * concentration);
	}

	skyFogStrength = SKY_FOG_STRENGTH * 0.01;

	if (blindness > 0.0001) {
		fogFactor = max(0.85, 1.0 - exp(-pow(fragDistance * blindness * 0.5, 2.0)));
		fogColor = vec3(0.0);
		skyFogStrength = 0.0;
	} else if (isEyeInWater == 1) {
		// Water cannot be placed in the nether, but a waterlogged block or a carried bucket can
		// still put the eye in it; keep B2's override so the case is not unhandled.
		fogFactor = 1.0 - exp(-pow(fragDistance * 0.02 * (UNDERWATER_FOG_DENSITY * 0.01), 2.0));
		fogColor = tint * NETHER_FOG_TINT;
		skyFogStrength = 0.0;
	} else if (isEyeInWater == 2) {
		// Submerged in lava: near-zero visibility with a high floor and the lava's own colour.
		fogFactor = max(0.85, 1.0 - exp(-pow(fragDistance * 0.5, 2.0)));
		fogColor = vec3(1.0, 0.05, 0.0);
		skyFogStrength = 0.0;
	}

	if (skyFogStrength > 0.0) {
		// B2's weak-fog zeroing, kept so the caller's sky path is skipped for nearby terrain.
		fogFactor *= smoothstep(0.01, 0.015, fogFactor);
	}

	return vec4(fogColor, fogFactor);
}

// ---------------------------------------------------------------------------
// Sky (design.md 4.5: 红/橙渐变天空)
// ---------------------------------------------------------------------------

// The nether sky is not a sky: it is the underside of a fog ceiling, so it is a gradient of the
// biome tint rather than a scattering model. Darker overhead (the ceiling closes in), brighter at
// the horizon (the fog is thickest along the longest sight line), with a warm pool below the
// horizon where the lava sea lights it from underneath.
//
// Deliberately absent: sun, moon, stars, clouds, weather, air perspective. design.md 4.5 asks for
// the overworld's sky features to be cut wholesale in the non-overworld dimensions; Mellow does the
// same by not calling any of its sun/sky helpers under DIMENSION_NETHER.
//
//   worldViewDir — NORMALIZED player-relative world-space view direction (y is up).
//   tint         — from nether_atmosphere_tint(); computed once by the caller and shared with the
//                  fog so the horizon seam between sky and distant fog is exact.
vec3 nether_sky(vec3 worldViewDir, vec3 tint) {
	float up = clamp(worldViewDir.y, -1.0, 1.0);
	float horizon = 1.0 - abs(up);

	vec3 sky = tint * mix(NETHER_SKY_ZENITH, NETHER_SKY_HORIZON, pow(horizon, NETHER_SKY_FALLOFF));

	// Below the horizon the lava sea takes over as the light source: 0.0 looking up, 1.0 looking
	// well below the horizon. Written as 1 - smoothstep(low, high, up) rather than a reversed-edge
	// smoothstep, which the GLSL spec leaves undefined when edge0 >= edge1.
	// Additive, so it uses the folded lava colour. The HDR peak put the bright horizon at
	// R 1.13 + 0.35 = 1.48 before the fog blend even started; folded it is 1.13 + 0.22 = 1.35.
	sky += NETHER_LAVA_ADD_COLOR * (NETHER_SKY_LAVA_POOL * (1.0 - smoothstep(-0.60, 0.15, up)));

	return sky;
}

// ---------------------------------------------------------------------------
// Lighting (design.md 4.5: 无日光光照路径 — 环境光 = 方块光 + 熔岩海辉光 + 基础红色环境底)
// ---------------------------------------------------------------------------

// Blocklight + handheld, on the nether's own curve. Structurally C1's block_lighting() minus the
// daylight suppression: BLOCKLIGHT_SUPPRESSION exists to stop torches glowing in daylight, and
// there is no daylight here. C1's form would already reduce to a no-op because nether skyLight is
// 0, but it multiplies by the CPU `blocklightSuppression`, whose value Iris derives from the
// overworld night/rain cycle — skipping the term removes that dependency entirely rather than
// trusting it to be 0 in a dimension it was never written for.
//
// heldLight arrives from C1's held_light_strength() (see nether_lighting below), which already
// applies HANDHELD_LIGHT_STRENGTH and returns 0.0 when HANDHELD_LIGHTING is off. The #ifdef here is
// therefore a SECOND gate, and deliberate: it compiles the pow out entirely rather than evaluating
// pow(0.0, e), and it means no caller can bypass the option by feeding this function a raw value.
// That is the one place this intentionally diverges from C1's block_lighting(), which takes an
// already-gated float and so has no #ifdef of its own.
vec3 nether_block_lighting(float blockLight, float heldLight) {
	float intensity = pow(blockLight, NETHER_BLOCKLIGHT_EXPONENT) * (BLOCKLIGHT_STRENGTH * 0.01);

	#ifdef HANDHELD_LIGHTING
		intensity += pow(heldLight, NETHER_BLOCKLIGHT_EXPONENT);
	#endif

	return BLOCKLIGHT_COLOR * min(1.0, intensity);
}

// Emissive and portal brightening, as a scalar multiplier on the surface's own albedo. Returning a
// factor rather than a colour matters: nether_lighting ends with a single `surfaceColor * lighting`
// multiply, so an emissive surface is `albedo * boost` — taking the albedo as an input here would
// square it. Both masks are E1-resolved material categories, so this costs two multiplies and no
// branching; a fragment that is neither returns 0.0 and drops out of the sum.
float nether_emissive_boost(float emissiveMask, float portalMask, float time) {
	if (emissiveMask < 0.0001 && portalMask < 0.0001) { return 0.0; }

	float boost = (EMISSIVE_STRENGTH * 0.01)
	            * mix(NETHER_EMISSIVE_BOOST, NETHER_PORTAL_BOOST, portalMask);

	// A portal that sits perfectly still reads as a painted decal; a slow shimmer reads as an open
	// surface. Only the portal term shimmers, so glowstone and shroomlights stay steady.
	boost *= 1.0 + NETHER_PORTAL_SHIMMER * portalMask * sin(time * NETHER_PORTAL_SHIMMER_RATE);

	return boost * max(emissiveMask, portalMask);
}

// The nether lighting composer — the counterpart of C1's diffuse_lighting(), and what E1 calls
// INSTEAD of it under DIMENSION_NETHER.
//
// Terms, in design.md 4.5's order: 基础红色环境底 (ambient floor) + 熔岩海辉光 (lava glow) +
// 方块光 (blocklight, own curve) + 发光体/传送门增亮 (emissive). There is no sky-ambient term and
// no direct sun/moon term, and therefore no shadow-map sample — that absence is the whole point of
// 光照路径重构, and it is also why the nether is cheaper per fragment than the overworld.
//
// Returns surfaceColor * lighting, linear HDR, ready for the tonemap in global/post/grading.glsl.
vec3 nether_lighting(
	vec3  surfaceColor,
	vec3  worldNormal,
	vec3  playerPos,
	float blockLight,
	float emissiveMask,
	float portalMask,
	float time,
	NetherParams params
) {
	// ===========================================================================
	// Complementary r5.9 逐字移植。每一步上方标注参考位置。
	// 与 Astra 旧实现的根本差别：合成是「平方和再开方」，不是加法累加
	// （mainLighting.glsl:613-616）。加法在结构上可以过曝；平方和开方有上界。
	// ===========================================================================

	vec3 netherCol = nether_color(params.biomeFogColor);

	// --- mainLighting.glsl:66-69 —— 世界轴基向量 --------------------------------
	// 参考用 northVec / eastVec / upVec 内建。Astra 没有这三个，但 worldNormal 已经是
	// 归一化的玩家系世界空间，轴基向量可直接写出，与 dot(normalM, *Vec) 等价：
	//   upVec    = (0, 1, 0)   → NdotU = worldNormal.y
	//   eastVec  = (1, 0, 0)   → NdotE = worldNormal.x
	//   northVec = (0, 0, -1)  → NdotN = -worldNormal.z   （Minecraft 北为 -Z）
	float NdotU = worldNormal.y;
	float NdotE = worldNormal.x;
	float NdotN = -worldNormal.z;
	float absNdotN = abs(NdotN);

	// --- mainLighting.glsl:506-519 —— 下界专属方向项，并且再平方一次 ------------
	float NdotUM = 0.75 + abs(NdotU + 0.5) * 0.16666;
	float NdotNM = 1.0 + 0.075 * absNdotN;
	float NdotEM = 1.0 - 0.1 * NdotE * NdotE;
	float directionShade = NdotUM * NdotEM * NdotNM;
	// ⚠ DO NOT "FIX" THIS INTO A SINGLE SQUARE. The reference squares directionShade HERE and
	// again at the composition step below, so the final gate is directionShade^4. Verified
	// 2026-09-10 against both cited lines, verbatim:
	//   :518 (inside the DIRECTIONAL_SHADING block, NETHER branch only)
	//        directionShade *= directionShade;
	//   :613 vec3 finalDiffuse = pow2(directionShade * vanillaAO) * (...) + pow2(emission);
	// The End takes the `!defined NETHER` branch of the same block, which has NO squaring at
	// :518 — hence end.glsl squares exactly once. The asymmetry is the reference's, not a
	// transcription slip; removing either square flattens nether relief quadratically (4x).
	directionShade *= directionShade;                    // mainLighting.glsl:518 (square #1)

	// --- lightAndAmbientColors.glsl:80-81 —— 下界无直射光，lightColor = vec3(0) --
	vec3 sceneLighting = (netherCol + 0.5 * NETHER_LAVA_LIGHT_COLOR)
	                   * (0.9 + 0.45 * NETHER_VS_BRIGHTNESS);

	// --- mainLighting.glsl:519 —— 熔岩的朝向形态：朝上的面系数为 0 ---------------
	float lavaDir = absNdotN * 0.5 + max(0.0, -NdotU);
	sceneLighting += NETHER_LAVA_LIGHT_COLOR * (lavaDir * lavaDir)
	               * (0.7 + 0.35 * NETHER_VS_BRIGHTNESS);

	// --- minimumLighting.glsl:1-17 —— 暗部下限，随方块光淡出；夜视偏蓝白 -------
	//     参考的 lightmapYM 取 lightmap 的方块光分量，Astra 的 blockLight 同义。
	vec3 minLighting = vec3(0.005625 + NETHER_VS_BRIGHTNESS * 0.043)
	                 * NETHER_FLOOR_TINT
	                 * (1.0 - blockLight);
	minLighting += params.nightVision * NETHER_NIGHT_VISION_TINT_REF;

	// --- Astra 自有（保留）：方块光曲线，pow 指数 2.75 --------------------------
	vec3 blockLighting = nether_block_lighting(
		blockLight,
		held_light_strength(params.heldLightBase, playerPos));

	// --- Astra 自有（保留）：发光体 / 传送门 -----------------------------------
	float emission = nether_emissive_boost(emissiveMask, portalMask, time);

	// --- mainLighting.glsl:613-616 —— 合成：平方和再开方 -----------------------
	//     参考的 vanillaAO = glColor.a（min版还有一段下界专属的 pow 重加权）。本模块拿不到
	//     它：nether_lighting 的调用点在 program/scene.glsl:178，参数表由 E1 固定，
	//     故取 1.0。这是一处已记录的偏离。
	float vanillaAO = 1.0;
	// directionShade is squared a SECOND time here (reference :613 `pow2(directionShade *
	// vanillaAO)`), on top of the `*= directionShade` above — see the warning there.
	vec3 finalDiffuse = directionShade * directionShade * vanillaAO * vanillaAO
	                  * (blockLighting + sceneLighting * sceneLighting + minLighting)
	                  + emission * emission;
	finalDiffuse = sqrt(max(finalDiffuse, vec3(0.0)));

	return surfaceColor * finalDiffuse;
}

#endif
