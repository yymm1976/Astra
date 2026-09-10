# Complementary r5.9 下界专题分析报告

- **参考版本**：Complementary Shaders **r5.9**，发布于 2026-09-02（Modrinth）
- **下载内容**：`ComplementaryReimagined_r5.9.zip`、`ComplementaryUnbound_r5.9.zip`，各 468 条目
- **本地位置**：`Astra并行开发/nether/_analysis/complementary/{Reimagined,Unbound}/shaders/`
  （`/_analysis/` 已在 `.gitignore` 中，不进版本控制）
- **两风格关系**：源码**完全一致**，只有默认设置不同。本报告行号以 `Reimagined` 为准。
- **Astra 侧对照**：`Astra并行开发/nether/Astra/shaders/global/dimension/nether.glsl`（C3 的自有下界路径）

---

## 0. 摘要：三条最重要的结论

**① 参考的下界不是一个「雾 + 熔岩辉光」模块，而是三套独立机制**

| 机制 | 作用 | 默认状态 |
|---|---|---|
| `netherColor` 平铺 | 天空、边界雾、体积雾的颜色源 | ✅ 开 |
| `netherStorm` 体积噪声风暴 | 下界的「空气感」 | ✅ 开 |
| `coloredLightFog` 体积光雾 | 唯一的「熔岩附近的雾」 | ❌ **默认关闭** |

**② `COLORED_LIGHTING` 在两个风格里默认都是 `0`（关）**

`Reimagined/shaders/lib/common.glsl:31`、`Unbound/shaders/lib/common.glsl:31`：

```glsl
#define COLORED_LIGHTING 0 //[128 192 256 384 512 768 1024]
```

因此 `COLORED_LIGHT_FOG` **不编译**（`common.glsl:34-37` 的 `#if COLORED_LIGHTING_INTERNAL > 0` 不成立）。

> ⚠ **这条更正我上一版拆解里的说法**：我把 `coloredLightFog` 描述成了「熔岩附近的雾」的实现，
> 这是**能力**层面的正确描述，但**不是默认配置下的实际观感**。默认下界里没有它。

**③ 于是默认配置下，参考抑制熔岩刺眼的全部手段只有三条**

| 手段 | 位置 | 类型 |
|---|---|---|
| 熔岩反照率 ×0.84 | `materials/specificMaterials/terrain/lava.glsl:1` | 变暗 |
| 熔岩不吃 lightmap（不被自己的光照亮） | 同文件 `:15` `lmCoordM = vec2(0.0)` | 变暗 |
| 近处泛光 ×0.7 | `program/composite5.glsl:139` | 压低 |

外加熔岩色常量本身极小：`lavaLightColor = vec3(0.15, 0.06, 0.01)`（`common.glsl:815`）。

**这三条里，Astra 一条都没有。** 第 2 条（`lmCoordM = 0`）卡在公共边界（见 §13 P-001）。

---

## 1. 维度接线与编译期开关

### 1.1 维度目录

`shaders/dimension.properties`（全 9 行）：

```properties
dimension.world0=*
dimension.world-1=minecraft:the_nether minecraft:nether
dimension.world1=minecraft:the_end minecraft:end
```

`world-1/` 下**每一个** pass 文件都只有 5-7 行，形如（`world-1/deferred1.fsh`）：

```glsl
#version 130
#define FRAGMENT_SHADER
#define NETHER
#define DEFERRED1
#include "/program/deferred1.glsl"
```

覆盖的 pass 共 41 个（`cls*` 除外）：`composite`/`1`~`7`、`deferred1`、`shadow`、`final`、
`dh_terrain`、`dh_water`、`gbuffers_*`（armor_glint / basic / beaconbeam / block /
block_translucent / clouds / damagedblock / entities / entities_glowing / entities_translucent /
hand / hand_water / lightning / line / particles_translucent / skybasic / skytextured /
spidereyes / terrain / textured / textured_lit / water / weather）、`voxy_opaque`、`voxy_translucent`。
**与 Astra 的 `world-1/*` 结构相同。**

### 1.2 编译期开关（`lib/common.glsl:595-600`）

```glsl
#ifdef NETHER
    #undef ATMOSPHERIC_FOG          // 整套大气雾（太阳方向、空气透视、群系着色）不编译
    #undef NO_WAVING_INDOORS        // 下界不做「室内不摆动」判定
#else
    #undef NETHER_STORM             // 非下界不编译风暴
#endif
```

### 1.3 其他编译期分支

| 位置 | 内容 |
|---|---|
| `common.glsl:542` | `LOW_QUALITY_NETHER_STORM`（低质量档位下启用，风暴采样数减半、alpha ×1.8 补偿） |
| `common.glsl:559` | `DO_NETHER_VINE_WAVING_OUTSIDE_NETHER`（高细节档位下，藤蔓在非下界也摆动） |
| `common.glsl:602-603` | `#ifdef END → #undef BLOOM_FOG`（末地关，下界**保留**） |
| `common.glsl:609-611` | `BLOOM_ENABLED == -1` 时 `#undef BLOOM_FOG` |
| `common.glsl:623-629` | `BLOOM_FOG` 时按 `WORLD_BLUR > 0` 选 `COMPOSITE3` 或 `COMPOSITE1` 落地 |

---

## 2. 颜色系统：`netherColor`

### 2.1 三种模式（`NETHER_COLOR_MODE`，默认 `3`）

`lib/common.glsl:799-814`：

```glsl
#if NETHER_COLOR_MODE == 3            // 默认：「Biome Based (Modified)」
    float netherColorMixer = inNetherWastes + inCrimsonForest + inWarpedForest
                           + inBasaltDeltas + inSoulValley;
    vec3 netherColor = mix(
        fogColor * 0.6 + 0.2 * normalize(fogColor + 0.0001),          // 未识别区域
        (  inNetherWastes  * vec3(0.4,   0.14,  0.06)
         + inCrimsonForest * vec3(0.36,  0.07,  0.05)
         + inWarpedForest  * vec3(0.18,  0.10,  0.25)
         + inBasaltDeltas  * vec3(0.25,  0.235, 0.23)
         + inSoulValley    * vec3(0.10,  0.24,  0.24) ),              // 硬编码调色板
        netherColorMixer
    );
#elif NETHER_COLOR_MODE == 2          // 「Biome Based」
    vec3 netherColor = fogColor * 0.6 + 0.2 * normalize(fogColor + 0.0001);
#elif NETHER_COLOR_MODE == 0          // 「Constant」
    vec3 netherColor = vec3(0.7, 0.26, 0.08) * 0.6;
#endif
vec3 lavaLightColor = vec3(0.15, 0.06, 0.01);
```

菜单文案（`lang/en_US.lang:426-430`）：

| 值 | 名称 | 文案 |
|---|---|---|
| `3` | **Biome Based (Modified)** | 「Biome based, but **the colors have been rebalanced to better suit the default visual direction of Complementary**」 |
| `2` | Biome Based | 「Colors will change depending on the biome」 |
| `0` | Constant | 「Colors won't change between biomes」 |

**模式 3 的调色板是「重新平衡过」的，不是原版雾色的直读。** 原版口径的模式是 2。
这一条很重要：抄模式 3 的数值等于抄 Complementary 的美术取向，不是抄原版。

### 2.2 五张调色板的设计意图

| 群系 | 调色板 | 特征 |
|---|---|---|
| 下界荒地 | `(0.40, 0.14, 0.06)` | 最亮，饱和红橙 |
| 绯红森林 | `(0.36, 0.07, 0.05)` | 比荒地更暗更红，接近纯红 |
| 诡异森林 | `(0.18, 0.10, 0.25)` | **唯一的蓝紫**，且明显偏暗 |
| 玄武岩三角洲 | `(0.25, 0.235, 0.23)` | **近中性灰**，三通道几乎相等 |
| 灵魂沙谷 | `(0.10, 0.24, 0.24)` | **最暗**，青绿 |

三个可复用的观察：

1. **亮度序是设计的一部分**：荒地 0.40 > 绯红 0.36 > 玄武岩 0.25 > 诡异 0.18 > 灵魂沙谷 0.10（按 R）；
   按感知亮度灵魂沙谷的 G/B 0.24 让它不至于全黑，但整体仍是最暗的群系。
2. **两张「近中性」调色板**（玄武岩、灵魂沙谷）是刻意保留的——它们在下界里承担「冷/灰」对比。
3. **`normalize()` 在参考里只用于回退分支**，不用于主色。

### 2.3 群系切换是**时间平滑**的（15 帧）

`shaders.properties:266-270`：

```properties
uniform.float.inNetherWastes=smooth(50, if(in(biome, BIOME_NETHER_WASTES), 1, 0), 15, 15)
uniform.float.inCrimsonForest=smooth(51, if(in(biome, BIOME_CRIMSON_FOREST), 1, 0), 15, 15)
uniform.float.inWarpedForest=smooth(52, if(in(biome, BIOME_WARPED_FOREST), 1, 0), 15, 15)
uniform.float.inBasaltDeltas=smooth(53, if(in(biome, BIOME_BASALT_DELTAS), 1, 0), 15, 15)
uniform.float.inSoulValley=smooth(54, if(in(biome, BIOME_SOUL_SAND_VALLEY), 1, 0), 15, 15)
```

`smooth(id, expr, upFrames, downFrames)` = 帧间平滑滤波器，`15, 15` 表示**升/降各用 15 帧**过渡。
配合 `mix(..., netherColorMixer)` 的归一化混合，**跨越群系边界时颜色是渐变而非突变**。
（同一机制也用在 `rainFactor(3,3)`、`eyeBrightnessM(5,5)` 等处，是 Complementary 的通用手法。）

### 2.4 用户倍率

`lib/colors/colorMultipliers.glsl:16-19, 41-44`：

```glsl
#elif defined NETHER
    vec3 netherLightMult = vec3(LIGHT_NETHER_R, LIGHT_NETHER_G, LIGHT_NETHER_B) * LIGHT_NETHER_I;
    lightColorMult = netherLightMult;
...
#elif defined NETHER
    vec3 netherAtmMult = vec3(ATM_NETHER_R, ATM_NETHER_G, ATM_NETHER_B) * ATM_NETHER_I;
    atmColorMult = netherAtmMult;
```

默认全 `1.00`（`common.glsl:333-340`）。给用户**光照**与**大气**两条独立 RGB×强度 通道，
菜单分组 `screen.NETHER_LIGHT_MULTS`（`shaders.properties:57`）与 `screen.NETHER_ATM_MULTS`（`:49`）。

---

## 3. 天空

`program/deferred1.glsl:362-381`，天空分支：

```glsl
{ // Sky
    skyFade = 1.0;
    #ifdef OVERWORLD
        ...极光、霓虹云...
    #endif
    #ifdef NETHER
        color.rgb = netherColor * (1.0 - maxBlindnessDarkness);    // ← 下界天空的全部内容
        #ifdef ATM_COLOR_MULTS
            color.rgb *= atmColorMult;
        #endif
    #endif
```

- **下界天空 = `netherColor` 平铺**。没有天顶/地平线渐变，没有太阳、月亮、星、云、极光、霓虹云。
- 原版天空贴图被清零：`program/gbuffers_skytextured.glsl:107-109`
  ```glsl
  #ifdef NETHER
      vec4 color = vec4(0.0);
  #endif
  ```
- `maxBlindnessDarkness = max(blindness, darknessFactor)`（`shaders.properties:275`）
  统一压制失明与黑暗效果（天空、风暴、光雾、泛光四处都用它）。

`lib/colors/skyColors.glsl` 虽然被下界的边界雾 include（`mainFog.glsl:11-12`），
但整个文件内容都在 `#ifdef OVERWORLD` 内，**对下界零贡献**（是一个惰性 include）。

> **对照 Astra**：`nether_sky()` 做了天顶 0.55 / 地平线 1.30 渐变 + 地平线下熔岩池，
> 这是 Astra 自己的设计（design.md 4.5「红/橙渐变天空」），参考没有对应实现。

---

## 4. 光照

### 4.1 直射光恒为零

`lib/colors/lightAndAmbientColors.glsl:79-81`：

```glsl
#elif defined NETHER
    vec3 lightColor   = vec3(0.0);
    vec3 ambientColor = (netherColor + 0.5 * lavaLightColor) * (0.9 + 0.45 * vsBrightness);
```

于是 `mainLighting.glsl:540` 的
`sceneLighting = lightColorM * shadowLightMult + ambientColorM * ambientMult`
第一项归零 → **下界完全没有直射项、没有阴影项**。

### 4.2 方向性（下界单独的形态 + 平方）

`lib/lighting/mainLighting.glsl:500-520`：

```glsl
#if !defined NETHER
    float NdotUM = 0.75 + NdotU * 0.25;                      // 主世界
#else
    float NdotUM = 0.75 + abs(NdotU + 0.5) * 0.16666;        // 下界
#endif
float NdotNM = 1.0 + 0.075 * absNdotN;                        // NdotN = n·north
float NdotEM = 1.0 - 0.1 * absNdotE2;                         // NdotE = n·east
directionShade = NdotUM * NdotEM * NdotNM;

#if defined OVERWORLD
    lightColorM *= 1.0 + absNdotE2 * 0.75;
#elif defined NETHER
    directionShade *= directionShade;                        // ★ 下界把方向项再平方
    ambientColorM += lavaLightColor * pow2(absNdotN * 0.5 + max0(-NdotU))
                                      * (0.7 + 0.35 * vsBrightness);
#endif
```

`NdotUM` 的下界形态：`NdotU` 从 -1 到 1 时取值为 **0.8333 → 0.75（最低点在 -0.5）→ 0.9167 → 1.0**。
再经 `directionShade *= directionShade` 平方，明暗对比被放大。

> **对照 Astra**：`ambient_strength(worldNormalY) = 0.67 + y*0.33`（`diffuse.glsl:85-87`），
> 范围 0.34 ~ 1.0，且**没有下界专属的平方**。

### 4.3 熔岩的方向形态（`absNdotN * 0.5 + max0(-NdotU)` 的平方）

| 表面朝向 | `NdotN` | `NdotU` | 系数 | 峰值贡献 |
|---|---|---|---|---|
| 朝下（天花板下面是熔岩） | 0 | -1 | `(0 + 1)² = 1.0` | **最大** |
| 水平朝北/南 | ±1 | 0 | `(0.5)² = 0.25` | 1/4 |
| 朝上（地面） | 0 | +1 | `(0 + 0)² = 0` | **0** |

**熔岩对朝上的表面完全不发力。** 这符合物理直觉（光从下面来），也避免了地板整体泛红。

> **对照 Astra**：`nether_lava_glow()` 用 `directional = 0.75 - 0.25 * worldNormalY`
> —— 朝下 1.0、朝上 0.5。**Astra 的朝上表面仍拿到一半的熔岩辉光**，这是「地面泛红」的来源之一。

### 4.4 熔岩在光照里的总预算

| 来源 | 公式 | vsBrightness=1 时峰值 |
|---|---|---|
| 基础环境 | `0.5 * lavaLightColor * (0.9 + 0.45*vsBrightness)` | `(0.101, 0.0405, 0.00675)` |
| 方向项 | `lavaLightColor * pow2(...) * (0.7 + 0.35*vsBrightness)` | `(0.1575, 0.063, 0.0105)` |
| **合计** | | **`(0.259, 0.1035, 0.0173)`** |

同一环境下 `netherColor`（荒地）是 `(0.40, 0.14, 0.06) × 1.35 = (0.54, 0.189, 0.081)`。
**熔岩在整个环境光里的占比不到一半**，它是底色上的一层暖调。

### 4.5 最低照明 `GetMinimumLighting`

`lib/lighting/minimumLighting.glsl` 全文 17 行：

```glsl
vec3 GetMinimumLighting(float lightmapYM) {
    #if !defined END && CAVE_LIGHTING > 0                 // ← 下界生效，只排除末地
        vec3 minLighting = vec3(0.005625 + vsBrightness * 0.043);
        #if CAVE_LIGHTING != 100
            #define CAVE_LIGHTING_M CAVE_LIGHTING * 0.01
            minLighting *= CAVE_LIGHTING_M;
        #endif
        minLighting *= vec3(0.45, 0.475, 0.6);            // ← 轻微偏冷
        minLighting *= 1.0 - lightmapYM;                  // ← 有方块光时淡出
    #else
        vec3 minLighting = vec3(0.0);
    #endif

    minLighting += nightVision * vec3(0.5, 0.5, 0.75);    // ← 夜视，偏蓝白
    return max(minLighting, vec3(0.0));
}
```

`vsBrightness = 1`、`CAVE_LIGHTING = 100`（默认）时：

- 幅度 `(0.048625) * (0.45, 0.475, 0.6)` = **`(0.0219, 0.0231, 0.0292)`**
- 色相比 `1 : 1.056 : 1.333` —— **轻微偏冷，远不是强蓝**

三条与 Astra 的差异：

| 项 | Complementary | Astra |
|---|---|---|
| `MIN_AMBIENT` 等效值 | `(0.0219, 0.0231, 0.0292)` | `(0.00264, 0.00640, 0.00800)`（`MIN_AMBIENT = 8`） |
| 色相比 | `1 : 1.056 : 1.333` | `1 : 2.42 : 3.03`（`MIN_AMBIENT_TINT = (0.33,0.8,1.0)`） |
| 是否随方块光淡出 | ✅ `*= 1.0 - lightmapYM` | ❌ 无淡出项 |
| 夜视色调 | `(0.5, 0.5, 0.75)` 蓝白 | `(0.2, 0.3, 0.2)` **偏绿** |

**幅度上参考的下限比 Astra 大 3.6~8.3 倍**（R 差 8.3 倍），但**色相远没那么蓝**。

### 4.6 环境光遮蔽

`mainLighting.glsl:574-578`：

```glsl
#elif defined NETHER
    vanillaAO = pow(pow1_5(vanillaAO), 1.0 + NdotUmax0 * 0.5);
```

下界的 AO 指数单独写（最大 1.5），比主世界更重。

### 4.7 方块光与手持光

`mainLighting.glsl:543-547`：

```glsl
#if HELD_LIGHTING_MODE >= 1
    blockLighting = sqrt(pow2(blockLighting) + heldLighting);    // 平方和开方，而非直接相加
#endif
blockLighting *= XLIGHT_I;
```

`HELD_LIGHTING_MODE = 2`、`XLIGHT_I = 1.00`（默认）。**方块光与手持光是平方和而不是相加**——
这样两者同时存在时不会简单叠加到过亮。

---

## 5. 熔岩专项

### 5.1 方块本体（`materials/specificMaterials/terrain/lava.glsl`，全文 23 行）

```glsl
color.rgb *= 0.84;                        // ① 无条件压暗 16%

#ifdef NETHER                            // ② 噪声扰动 gamma，做出流动感
    vec3 worldPos = playerPos + cameraPosition;
    vec2 lavaPos = (floor(worldPos.xz * 16.0) + worldPos.y * 32.0) * 0.000666;
    vec2 wind = vec2(frameTimeCounter * 0.012, 0.0);
    float noiseSample = texture2DLod(noisetex, lavaPos + wind, 0.0).g;
    noiseSample = (noiseSample - 0.5) * 0.1;              // ∈ [-0.05, +0.05]
    color.rgb = pow(color.rgb, vec3(1.0 + noiseSample));  // gamma 在 0.95 ~ 1.05 间游走
#endif

noDirectionalShading = true;              // ③ 不吃方向性明暗
lmCoordM = vec2(0.0);                     // ④ 不吃 lightmap —— 不被自己的光照亮
emission = GetLuminance(color.rgb) * 7.48 + 0.5;             // ⑤ 发光由自身亮度驱动
maRecolor = vec3(clamp(pow2(pow2(pow2(smoothstep1(emission * 0.28)))), 0.12, 0.4) * 1.3)
          * vec3(0.25, vec2(0.175));                          // ⑥ 方块光重染色
```

逐条：

- **① `×0.84`**：熔岩是**被压暗**的，不是被提亮。全维度生效（不在 `#ifdef NETHER` 内）。
- **② 噪声扰动 gamma**：`±0.05` 的 gamma 摆动，配合 `floor(xz*16)` 的方块量化 + `y*32` 的层间错位，
  做出「熔岩表面在缓慢流动」的观感。`wind = frameTimeCounter * 0.012`，即 **1 单位/83 秒**的极慢漂移。
- **④ `lmCoordM = vec2(0.0)`**：熔岩是 15 级光源，自身位置的 lightmap ≈ 1.0。
  把这个坐标清零，**熔岩表面就不会再叠加一份自己发出的光**。
- **⑤ `emission` 由亮度驱动**：`GetLuminance(color.rgb) * 7.48 + 0.5`。
  纹理亮的地方发光强、暗纹处发光弱，**熔岩自身有明暗层次**，不是一片均匀的亮红。
- **⑥ `maRecolor`**：`smoothstep1(emission*0.28)` 的 8 次方，再 `clamp(·, 0.12, 0.4) * 1.3`，
  最后乘 `(0.25, 0.175, 0.175)` → **R 上限 0.13、G/B 上限 0.091**。给彩色方块光系统的重染色，很小。

### 5.2 熔岩作为光源的注册

`lib/colors/blocklightColors.glsl`：

```glsl
vec3 lavaSpecialLightColor = vec3(3.25, 0.9, 0.2) * 3.9;      // :20  = (12.675, 3.51, 0.78)
...
if (mat == 13) return vec4(lavaSpecialLightColor,      0.8);   // :60  Lava
if (mat == 14) return vec4(lavaSpecialLightColor,      0.0);   // :66  Lava Cauldron
if (mat == 37) return vec4(lavaSpecialLightColor * 0.1, 0.1);  // :110 Magma Block
```

色相比 `1 : 0.277 : 0.0615`，是 **HDR 的光源强度**（走方块光/光体积系统），
**不是直接加进画面的颜色**。这是关键区别。

### 5.3 方块 id（`block.properties`）

| id | 内容 |
|---|---|
| `10056` | `lava_cauldron` |
| `10068` | `lava` `flowing_lava` |
| `10076` | `soul_fire` |
| `10140` | `netherrack` |
| `10144` | `warped_nylium` `warped_wart_block` |
| `10148` | `crimson_nylium` `nether_wart_block` |
| `10212`~`10224` | 绯红/诡异木料全套（板、栅栏、台阶、楼梯、茎、菌核、门） |
| `10248` | `netherite_block` |
| `10308` | `nether_gold_ore` |
| `10364`~`10368` | 石英方块族、`nether_quartz_ore` |
| `10408` | 玄武岩族 |
| `10412` | `glowstone` `light` |
| `10416`~`10423` | 下界砖族（含红下界砖） |
| `10452` | `magma` `magma_block` |
| `10480`~`10484` | 黑石族、`gilded_blackstone` |
| `10528` `10564` | `soul_torch` `soul_wall_torch`、`soul_lantern` |
| `10648` | `shroomlight` |
| `10656` `10661` | `soul_campfire:lit=true`、未点燃的营火 |
| `10744` | `soul_sand` `soul_soil` |
| `10776` `10780` | `warped_fungus` `crimson_fungus` |
| `10884` `10885` | `weeping_vines_plant`、`weeping_vines` `twisting_vines*` |
| `30020` | `portal` `nether_portal` |

**每个下界方块都有自己的材质 id。** 这是 Complementary 能做「熔岩专属处理」的根本原因，
也正是 Astra 缺的（Astra 用 `block.10022` 把橙光组 8 个方块压成材质 `10u`）。

---

## 6. 雾（四套并行）

### 6.1 边界雾：`netherColor` 平铺

`lib/atmospherics/fog/mainFog.glsl:15-48`：

```glsl
void DoBorderFog(inout vec4 color, inout float skyFade, float lPos, float VdotU, float VdotS, float dither) {
    ...
    #ifdef NETHER
        float farM = min(renderDistance, NETHER_VIEW_LIMIT);
        float fog = lPos / farM;
        fog = mix(fog, min1(lPos / min(farM, 256.0)), 0.5);      // 两条线性斜坡取混合
    #endif
    ...
    #ifdef OVERWORLD
        vec3 fogColorM = GetSky(VdotU, VdotS, dither, true, false);
    #elif defined NETHER
        vec3 fogColorM = netherColor;                            // ← 平铺，无熔岩项
    #else
        vec3 fogColorM = endSkyColor;
    #endif
    color = mix(color, vec4(fogColorM, 0.0), fog);
```

**参考的下界边界雾颜色就是 `netherColor`，没有任何熔岩加法。**
`ATMOSPHERIC_FOG` 在下界被 `#undef`，那套带太阳方向/空气透视/群系着色的大气雾不参与。

> **对照 Astra**：`nether_fog()` 在 `netherColor`（= `tint * 0.25`）之上还加一层
> 「熔岩辉光 + 云层」的加法项，并按世界 Y 决定浓度。**参考这里什么都没有。**

### 6.2 体积光雾 `coloredLightFog` —— 默认关闭，但是正确做法

`lib/atmospherics/fog/coloredLightFog.glsl` 全文 52 行，前提是 `COLORED_LIGHT_FOG` 被定义
（`common.glsl:34-37`，需要 `IRIS_FEATURE_CUSTOM_IMAGES && SHADOW_QUALITY > -1 && COLORED_LIGHTING > 0`）。

```glsl
vec3 GetColoredLightFog(vec3 nPlayerPos, vec3 translucentMult, float lViewPos, float lViewPos1, float dither) {
    vec3 lightFog = vec3(0.0);
    float stepMult = 8.0;
    float maxDist = min(effectiveACTdistance * 0.5, far);
    int sampleCount = int(maxDist / stepMult + 0.001);
    vec3 traceAdd = nPlayerPos * stepMult;
    vec3 tracePos = traceAdd * dither;

    for (int i = 0; i < sampleCount; i++) {
        float lTracePos = length(tracePos);
        if (lTracePos > lViewPos1) break;
        if (any(greaterThan(abs(tracePos * 2.0), vec3(voxelVolumeSize)))) break;

        vec3 voxelPos = SceneToVoxel(tracePos);
        voxelPos = clamp01(voxelPos / vec3(voxelVolumeSize));
        vec3 lightSample = GetLightVolume(voxelPos).rgb;
        float lTracePosM = length(vec3(tracePos.x, tracePos.y * 2.0, tracePos.z));  // y 加权 2×
        lightSample *= max0(1.0 - lTracePosM / maxDist);          // ★ 线性距离衰减
        lightSample *= pow2(min1(lTracePos * 0.03125));           // ★ 32 格内平方抑制
        if (lTracePos > lViewPos) lightSample *= translucentMult;  // 被几何体遮挡
        lightFog += lightSample;
        tracePos += traceAdd;
    }

    #ifdef NETHER
        lightFog *= netherColor * 5.0;
    #endif
    lightFog *= 1.0 - maxBlindnessDarkness;
    lightFog = pow(lightFog / sampleCount, vec3(0.25));           // ★ 四次方根压缩
    return lightFog;
}
```

调用处 `program/composite1.glsl:256-258`，强度 `COLORED_LIGHT_FOG_I = 0.65`（`common.glsl:37`）。

**四道防线：光体积驱动 → 线性距离衰减 → 32 格内平方抑制 → 四次方根压缩。**
其中 `pow2(min1(lTracePos * 0.03125))`（`1/32`）是最关键的一条：**近距离根本不泛光**。

体积参数（`lib/voxelization/lightVoxelization.glsl:4-10`）：

```glsl
#if COLORED_LIGHTING_INTERNAL <= 512
    const ivec3 voxelVolumeSize = ivec3(COLORED_LIGHTING_INTERNAL, COLORED_LIGHTING_INTERNAL * 0.5, COLORED_LIGHTING_INTERNAL);
#else
    const ivec3 voxelVolumeSize = ivec3(COLORED_LIGHTING_INTERNAL, 512 * 0.5, COLORED_LIGHTING_INTERNAL);
#endif
float effectiveACTdistance = min(float(COLORED_LIGHTING_INTERNAL), shadowDistance * 2.0);
```

体积**高度只有水平分辨率的 0.5 倍**——这就是 `coloredLightFog` 里 `tracePos.y * 2.0` 的原因。

### 6.3 体积风暴 `netherStorm` —— 默认开启

`lib/atmospherics/netherStorm.glsl` 全文 78 行：

```glsl
vec4 GetNetherStorm(vec3 color, vec3 translucentMult, vec3 nPlayerPos, vec3 playerPos,
                    float lViewPos, float lViewPos1, float dither) {
    if (isEyeInWater != 0) return vec4(0.0);
    vec4 netherStorm = vec4(1.0, 1.0, 1.0, 0.0);

    #ifdef BORDER_FOG
        float maxDist = min(renderDistance, NETHER_VIEW_LIMIT);
    #else
        float maxDist = renderDistance;
    #endif
    maxDist = min(maxDist, 512.0);

    #ifndef LOW_QUALITY_NETHER_STORM
        int sampleCount = int(maxDist / 8.0 + 0.001);
        vec3 traceAdd = nPlayerPos * maxDist / sampleCount;
        vec3 tracePos = cameraPosition + traceAdd * dither;
    #else
        int sampleCount = int(maxDist / 16.0 + 0.001);
        ...（起点偏移到中点）
    #endif

    vec3 translucentMultM = pow(translucentMult, vec3(1.0 / sampleCount));
    float translucentMultM2 = GetLuminance(translucentMultM);

    for (int i = 0; i < sampleCount; i++) {
        tracePos += traceAdd;
        vec3 tracedPlayerPos = tracePos - cameraPosition;
        float lTracePos = length(tracedPlayerPos);
        if (lTracePos > lViewPos1) break;

        vec3 wind = vec3(frameTimeCounter * 0.002);
        vec3 tracePosM = tracePos * 0.001;
        tracePosM.y += tracePosM.x;                        // 剪切 → 斜向层理
        tracePosM += Noise3D(tracePosM - wind) * 0.01;      // 域扭曲
        tracePosM = tracePosM * vec3(2.0, 0.5, 2.0);        // 垂直压扁、水平拉伸

        float traceAltitudeM = abs(tracePos.y - NETHER_STORM_LOWER_ALT);       // 锚点 28
        if (tracePos.y < NETHER_STORM_LOWER_ALT) traceAltitudeM *= 10.0;       // 下方衰减快 10×
        traceAltitudeM = 1.0 - min1(abs(traceAltitudeM) / NETHER_STORM_HEIGHT); // 高度 200

        for (int h = 0; h < 4; h++) {                      // 4 个倍频，逐级 ×2
            float stormSample = pow2(Noise3D(tracePosM + wind));
            stormSample *= traceAltitudeM;
            stormSample = pow2(pow2(stormSample));         // 累计噪声 ^8 → 只留细丝
            stormSample *= sqrt1(max0(1.0 - lTracePos / maxDist));   // 距离衰减（开方）
            netherStorm.a += stormSample;
            tracePosM *= 2.0;
            wind *= -2.0;
        }

        if (lTracePos > lViewPos) {
            netherStorm.rgb *= translucentMultM;           // 被几何体遮挡
            netherStorm.a *= translucentMultM2;
        }
    }

    #ifdef LOW_QUALITY_NETHER_STORM
        netherStorm.a *= 1.8;
    #endif

    netherStorm.a = min1(netherStorm.a * NETHER_STORM_I);   // 0.40，硬上限
    netherStorm.rgb *= netherColor * 3.0 * (1.0 - maxBlindnessDarkness);

    return netherStorm;
}
```

调用处 `program/composite1.glsl:241-253`：

```glsl
#ifdef NETHER_STORM
    volumetricEffect = GetNetherStorm(color, translucentMult, nPlayerPos, playerPos, lViewPos, lViewPos1, dither);
#endif
...
#ifdef NETHER_STORM
    color = mix(color, volumetricEffect.rgb, volumetricEffect.a);
#endif
```

**颜色与强度分离是核心设计**：返回值是 `vec4(netherColor * 3.0, 强度)`，用 **alpha 混合**。
强度被 `min1(... * 0.40)` 卡死，**结构上不可能「叠加到过曝」**。

**高度锚点方向与 Astra 相反**（`lang/en_US.lang:405` 原文）：

> "Determines the lower starting point of the Nether Storm.
> The Nether Storm **won't appear below this altitude**, and it will look **the most bright right above** this altitude."

即：**风暴在熔岩面上方最浓，往下急剧消失。**

### 6.4 泛光雾 `bloomFog`

`lib/atmospherics/fog/bloomFog.glsl:11-14, 29-36`：

```glsl
#ifdef BORDER_FOG
    const float netherBloomAdd = 14.0;
#else
    const float netherBloomAdd = 3.0;
#endif
...
#elif defined NETHER
    float farM = min(renderDistance, NETHER_VIEW_LIMIT);
    float bloomFog = lViewPos / clamp(farM, 96.0, 512.0);
    bloomFog *= bloomFog * bloomFog;                  // ^3
    bloomFog = 1.0 - exp(-8.0 * bloomFog);
    bloomFog *= float(isEyeInWater == 0);
    float bloomFogMult = netherBloomAdd;
```

### 6.5 雾的其他分支

| 位置 | 内容 |
|---|---|
| `mainFog.glsl:98-121` | 主世界专用的 `GetAtmFogColor` / `GetAtmFogAltitudeFactor` / `DoAtmosphericFog`（`ATMOSPHERIC_FOG` 在下界被 undef） |
| `lib/atmospherics/fog/waterFog.glsl` | 水下雾（下界无水，实际不触发） |
| `lib/atmospherics/fog/caveFactor.glsl` | 洞穴系数（依赖天空光，下界无意义） |

---

## 7. 泛光与景深

### 7.1 泛光的近远分离调制

`program/composite5.glsl:130-139`：

```glsl
float bloomStrength = BLOOM_STRENGTH + 0.2 * darknessFactor;

#if defined BLOOM_FOG && defined NETHER && defined BORDER_FOG
    float farM = min(renderDistance, NETHER_VIEW_LIMIT);
    float netherBloom = lViewPos / clamp(farM, 96.0, 256.0);
    netherBloom *= netherBloom;                       // ^2
    netherBloom *= netherBloom;                       // ^4
    netherBloom = 1.0 - exp(-8.0 * netherBloom);
    netherBloom *= 1.0 - maxBlindnessDarkness;
    bloomStrength = mix(bloomStrength * 0.7, bloomStrength * 1.8, netherBloom);
#endif
```

**近处 `× 0.7`、远处 `× 1.8`。** `BLOOM_STRENGTH` 默认 `0.12`（`common.glsl:146`）。

### 7.2 景深

`program/composite3.glsl:73-74`：

```glsl
#elif defined NETHER
    float dbMult = WB_DB_NETHER_I;
...
float coc = clamp(lViewPos0 * 0.001, 0.0, 0.1) * dbMult * 0.03;
```

`WB_DB_NETHER_I = 64.0`，`WORLD_BLUR = 0`（默认）→ **景深默认关闭，此项默认不生效**。

---

## 8. 阴影：下界完全不做

`lib/materials/materialMethods/worldSpaceRef.glsl:143`：

```glsl
#ifndef NETHER
    vec3 shadow = shadowMult;
    if (lightingNdotL > 0.0001) {
        float shadowLength = shadowDistance * 0.9166667 - length(playerPos);
        ...
        shadow = GetShadow(GetShadowPos(playerPos + bias), faceData.lightmap.y, offset, shadowSamples, false, playerPos);
    }
#endif
```

下界无直射光 → 无阴影采样 → 与 Astra 的设计一致。

**但有一个 hack 值得知道**（`program/gbuffers_basic.glsl:101-103`）：

```glsl
#if COLORED_LIGHTING_INTERNAL > 0 && defined NETHER
    if (gl_FragCoord.x < 0.0)
    color = shadow2D(shadowtex0, vec3(0.5)); // To Activate Shadowmap in Nether
#endif
```

`gl_FragCoord.x < 0.0` **永远不成立**，这是刻意的死代码——唯一目的是让 Iris 认为
shadow map 被引用，从而不去裁剪它（彩色光体积需要它的深度）。注释里也写明了。

---

## 9. 其他下界专属处理

| 位置 | 处理 | 备注 |
|---|---|---|
| `materials/materialHandling/terrainIPBR.glsl:796-799` | 下界金矿发光：`emission = color.g * 1.5; emission *= GLOWING_ORE_MULT;` | 由 `GLOWING_ORE_NETHERGOLD` 控制 |
| `materials/materialHandling/terrainIPBR.glsl:974-977` | 下界石英矿发光：`emission = pow2(color.b * 1.6); emission *= GLOWING_ORE_MULT;` | 由 `GLOWING_ORE_NETHERQUARTZ` 控制 |
| `lib/voxelization/lightVoxelization.glsl:162-163` | 下界金矿进光体积（`return 50`） | 需 `GLOWING_ORE_NETHERGOLD && DO_IPBR_LIGHTS` |
| `lib/voxelization/lightVoxelization.glsl:186-187` | 下界石英矿进光体积（`return 49`） | 需 `GLOWING_ORE_NETHERQUARTZ` |
| `materials/materialMethods/wavingBlocks.glsl:154-157` | 垂泪藤 / 缠怨藤摆动 | `#if defined NETHER \|\| defined DO_NETHER_VINE_WAVING_OUTSIDE_NETHER` |
| `materials/specificMaterials/translucents/netherPortal.glsl` | 8 次采样拖影；`lmCoordM = vec2(0.0)`；`emission = clamp(emission * 120.0, 0.03, 1.2) * 8.0`（上限 9.6）；近处 `color.a *= min1(lViewPos - 0.2)` | 同样「光源不吃 lightmap」 |
| `materials/specificMaterials/terrain/netherrack.glsl`（全文 7 行） | `smoothnessG = min1(pow2(color.r) * 1.5); smoothnessD = smoothnessG;` | 只改平滑度，不改颜色 |
| `materials/specificMaterials/terrain/netheriteBlock.glsl` | 金属质感 | — |
| `program/gbuffers_beaconbeam.glsl:92-96` | 跳过信标光柱的高度重映射 | — |
| `lib/common.glsl:597` | `#undef NO_WAVING_INDOORS` | 下界不做室内判定 |
| `lib/misc/showLightLevels.glsl` | 下界调试显示 | — |

---

## 10. 用户可调项全表

| 选项 | 默认 | 范围 | 说明（`lang/en_US.lang` 原文摘要） |
|---|---|---|---|
| `NETHER_VIEW_LIMIT` | `256.0` | 96.0 → 99999.0（6 → Limitless 区块） | 雾允许的最大可视距离；调高在风暴开启时影响性能 |
| `NETHER_COLOR_MODE` | `3` | 3 / 2 / 0 | 3 = Biome Based (Modified)，2 = Biome Based，0 = Constant |
| `NETHER_STORM` | 开 | — | 体积烟雾效果；⚠ 影响性能 |
| `NETHER_STORM_I` | `0.40` | 0.05 → 1.50 | 风暴不透明度 |
| `NETHER_STORM_LOWER_ALT` | `28` | -296 → 300 | 风暴下锚点；此高度以下不出现，紧邻其上方最亮 |
| `NETHER_STORM_HEIGHT` | `200` | 25 → 900 | 风暴高度；调小会让风暴向锚点聚拢 |
| `LIGHT_NETHER_R/G/B/I` | `1.00` 各 | 0.01 → 2.00 | 下界光照颜色倍率 |
| `ATM_NETHER_R/G/B/I` | `1.00` 各 | 0.01 → 2.00 | 下界大气颜色倍率 |
| `WB_DB_NETHER_I` | `64.0` | 1.0 → 4096.0 | 世界虚化景深的「距离模糊 - 下界」 |
| `GLOWING_ORE_NETHERQUARTZ` | — | — | 下界石英矿发光 |
| `GLOWING_ORE_NETHERGOLD` | — | — | 下界金矿发光 |

菜单结构（`shaders.properties`）：
`screen.NETHER_SETTINGS`（`:41`）、`screen.NETHER_ATM_MULTS`（`:49`）、`screen.NETHER_LIGHT_MULTS`（`:57`）。

---

## 11. 默认配置下，下界观感到底由什么构成

这一节是判断「该抄什么」的依据。逐项列出**默认是否生效**：

| 机制 | 默认 | 贡献 |
|---|---|---|
| `netherColor` 平铺（天空 + 边界雾） | ✅ | 全部底色 |
| `lavaLightColor` 环境 + 方向项 | ✅ | 熔岩氛围光，峰值 R `0.259` |
| `lava.glsl` `×0.84` | ✅ | 熔岩方块压暗 16% |
| `lava.glsl` `lmCoordM = 0` | ✅ | **熔岩不被自己的光照亮** |
| `lava.glsl` `emission` 亮度驱动 | ✅ | 熔岩自身明暗纹理 |
| 噪声流动（下界专属） | ✅ | 熔岩表面缓慢流动 |
| `netherStorm` | ✅ | 体积风暴雾，强度上限 0.40 |
| 泛光近 `×0.7` / 远 `×1.8` | ✅ | **近处泛光被压低** |
| `bloomFog` | ✅ | 远处泛光压制 |
| `NETHER_VIEW_LIMIT 256` | ✅ | 可视距离上限 |
| 群系颜色 15 帧平滑 | ✅ | 跨群系不突变 |
| `GetMinimumLighting` | ✅ | 暗部下限 `(0.0219, 0.0231, 0.0292)`，随方块光淡出 |
| 夜视 `(0.5, 0.5, 0.75)` | ✅ | 偏蓝白 |
| `coloredLightFog` | ❌ | 需 `COLORED_LIGHTING > 0` |
| `WORLD_BLUR` 景深 | ❌ | 默认 `0` |
| 彩色方块光体积 | ❌ | 同 `COLORED_LIGHTING` |
| 阴影 | ❌ | 下界本就不做 |

**结论：默认下界里，熔岩的「不刺眼」只由 `×0.84` + `lmCoordM = 0` + 近处泛光 ×0.7 三条保证，
加上熔岩色常量本身极小（`vec3(0.15, 0.06, 0.01)`）。**

`coloredLightFog` 和彩色光体积是**能力**，不是默认观感。抄它需要新增 Iris 自定义图像基础设施，
远超本 worktree 范围；但它「距离衰减 + 近处平方抑制」的**思想**可以用一次乘加近似。

---

## 12. 与 Astra 的逐项对照

| 维度 | Complementary r5.9 | Astra（`global/dimension/nether.glsl`） | 性质 |
|---|---|---|---|
| 维度接线 | `world-1/*` + `#define NETHER` | `program/scene.glsl` 里 `#if defined DIMENSION_NETHER` | ✅ 一致 |
| 直射光 | `lightColor = vec3(0)` | 无直射项 | ✅ 一致 |
| 阴影 | 不做（且明确 `#ifndef NETHER`） | 不做 | ✅ 一致 |
| 天空 | `netherColor` 平铺（`deferred1:376`） | 天顶/地平线渐变 + 熔岩池 | Astra 自有 |
| 天空贴图 | `gbuffers_skytextured` 清零 | — | — |
| 群系颜色来源 | 5 布尔 + 硬编码调色板 + 未知回退 | `normalize(fogColor)` → 四次方根 | ⚠ 机制不同 |
| 群系亮度序 | 保留（0.10 ~ 0.40） | `normalize()` 归一 → 只留色相 | ❌ **亮度序丢失** |
| 群系过渡 | 15 帧平滑 | 无（每帧直读 `fogColor`） | ⚠ 无突变缓冲 |
| 熔岩环境光峰值 | R `0.259` | R `0.256`（本轮已对齐） | ✅ |
| 熔岩色相 | `1 : 0.4 : 0.0667` | `1 : 0.4 : 0.0669`（本轮已对齐） | ✅ |
| 熔岩方向形态 | `pow2(\|NdotN\|*0.5 + max0(-NdotU))`，朝上为 0 | `0.75 - 0.25*NdotU`，朝上 0.5 | ❌ 朝上仍受力 |
| 熔岩方块反照率 | `× 0.84` | `× 1.35` 自发光提亮（本轮加了亮度余量） | ❌ 方向相反 |
| 熔岩不被自身照亮 | `lmCoordM = vec2(0.0)` | 无 | ❌ **P-001** |
| 熔岩明暗纹理 | `emission` 由自身亮度驱动 | 无 | ⚠ 可借鉴 |
| 方向性对比 | `0.75 + \|NdotU+0.5\|/6` 再平方 | `0.67 + y*0.33`，不平方 | ⚠ 参考更硬 |
| 暗部下限 | `(0.0219, 0.0231, 0.0292)`，比 `1 : 1.056 : 1.333`，随方块光淡出 | `(0.00264, 0.00640, 0.00800)`，比 `1 : 2.42 : 3.03`，无淡出 | ⚠ 幅度小 3.6~8.3×、更蓝、无淡出 |
| 夜视色调 | `(0.5, 0.5, 0.75)` 蓝白 | `(0.2, 0.3, 0.2)` 偏绿 | ⚠ 取向不同 |
| 方块光 + 手持光 | `sqrt(block² + held²)` 平方和 | 直接相加 | ⚠ 可借鉴 |
| 边界雾颜色 | `netherColor` 平铺，无熔岩项 | `tint*0.25` + 熔岩辉光 + 云层（按 Y） | ❌ 加法项是 Astra 独有 |
| 体积雾 | `netherStorm` raymarch，alpha 混合、上限 0.40、锚点上方最浓 | 单点云项加进雾色，无上限，锚点下方 2× | ❌ 结构性差距 |
| 熔岩附近的雾 | 体积光雾（默认关） | 无 | 能力缺口 |
| 泛光 | 近 ×0.7 / 远 ×1.8 | 无下界调制 | ❌ Astra 的 bloom 仅主世界 |
| AO | `pow(pow1_5(ao), 1.0 + NdotUmax0*0.5)` | 无下界专属 AO | ⚠ |
| 藤蔓摆动 | 垂泪/缠怨藤 | `wind.glsl` 属 terrain-foliage 范围 | — |
| 熔岩表面流动 | 噪声 gamma 扰动 | 无 | ⚠ 可借鉴 |
| 矿脉发光 | 下界金矿/石英矿可选发光 | 无 | ⚠ |

---

## 13. 三条处理建议

### A. 可直接在 `global/dimension/nether.glsl` 内实现（按性价比排序）

1. **熔岩辉光加近处抑制**（最高优先）
   ```glsl
   glow *= pow2(min1(fragDistance * 0.03125));    // 参考的 1/32，32 格内平方抑制
   ```
   一次乘加。参考在默认关闭光雾的情况下仍有近处泛光 ×0.7 兜底；Astra 连这一层都没有。
2. **熔岩方向形态改成参考形状**
   ```glsl
   float lavaDirection = abs(worldNormal.z) * 0.5 + max(0.0, -worldNormal.y);  // NdotN≈z, NdotU=y
   glow *= lavaDirection * lavaDirection;         // 朝上的面系数为 0
   ```
   一次性解决「地板泛红」。
3. **熔岩方块按自身亮度提亮/压暗**：`nether_lighting()` 里有 `surfaceColor`，
   可做 `emission = luminance(albedo) * k` 的驱动形式，让熔岩有明暗层次而不是均匀亮。
4. **云层项改成 alpha 混合 + 硬上限**：把「加进雾色」改成「按强度混合到 `tint * 3`」，
   强度 `min1(...)`。结构上消除过曝可能。
5. **边界雾去掉熔岩加法或大幅压低**：参考这里是纯 `netherColor` 平铺。
6. **补充垂直锚点方向的判断**：参考是锚点上方最浓，Astra 是下方浓度翻倍（取反）。
7. **方块光 + 手持光改成平方和**：`sqrt(b² + h²)`。
8. **下限加方块光淡出**：`*= 1.0 - blockLight`，只在暗处生效。

### B. 需要公共边界（`docs/handoffs/nether.md` 已有 P-001）

1. **P-001 熔岩专属材质 id**（`program/lit.vsh:25-29`）：参考的 `lmCoordM = vec2(0.0)`
   在当前 `10u` 掩码下无法实现。**这是默认配置下参考最有效的一条防刺眼手段。**
2. **彩色光体积基础设施**：整个 `coloredLightFog` + `lightVoxelization` 体系。
   属于新增 Iris 自定义图像通道，超出本 worktree 范围。

### C. 结构上不能照搬

| 项目 | 原因 |
|---|---|
| `netherStorm` raymarch | `sampleCount = maxDist/8`，256 格 32 次采样 × 4 倍频噪声 |
| `coloredLightFog` raymarch | 同上，且依赖光体积 |
| `NETHER_COLOR_MODE 3` 硬编码调色板 | Astra 的设计线是「从原版雾色派生」（design.md 4.5），引入调色板表属设计变更 |
| 每方块独立材质 id 体系 | 参考的 `block.properties` 有 300+ 条细粒度注册；Astra 是分类式 |

---

## 14. 对我上一轮改动的修正（必须说明）

上一轮（本 worktree 第二次提交前）我把环境光下限从 `MIN_AMBIENT_COLOR`（强蓝，比 `1 : 2.42 : 3.03`）
改成了**沿生物群系 tint 重定向的暖色**。查到参考的实现后，这个改动**方向过头了**：

- 参考的 `GetMinimumLighting` **确实**给下界保留了一层**轻微偏冷**的下限：`vec3(0.45, 0.475, 0.6)`，
  比 `1 : 1.056 : 1.333`。它不是「冷蓝也不该有」，而是「不该那么蓝」。
- Astra 原值的问题在**色相过蓝**（B/R = 3.03 对参考的 1.333），而不是「不该冷」。
- 我的改动把色相从强蓝变成了生物群系暖色，等于从一端走到了另一端。

**建议的对齐值**（保留用户选项的亮度语义，色相取参考比例）：

```glsl
// 参考 lib/lighting/minimumLighting.glsl:8 的比例
const vec3 NETHER_FLOOR_TINT = vec3(0.45, 0.475, 0.6);
float floorLuma = dot(MIN_AMBIENT_COLOR, vec3(0.2126, 0.7152, 0.0722));
lighting += NETHER_FLOOR_TINT
          * (floorLuma * (MIN_AMBIENT_COLOR / max(MIN_AMBIENT_COLOR.b, 1e-5)).b / ...)
```

或更简单：直接按参考的绝对幅度给一个下界下限，不再逐帧从 `MIN_AMBIENT_COLOR` 推导。

同轮另外两条改动仍然成立、与参考不冲突：

- 加法项改用折算过的熔岩色（`NETHER_LAVA_ADD_COLOR`）——参考没有对应问题，因为它不做加法。
- 加法辉光的 `1 - exp(-x)` 饱和收敛——参考用 alpha 混合 + `min1` 达到同一目的，思路一致。
- 环境光下限的**幅度**：参考比 Astra 大 3.6~8.3 倍，说明 Astra 的下界暗部其实偏暗，
  这也符合「下界应该更暗」的直觉，但值得实测确认。

---

## 附：本报告的证据清单

所有结论均来自以下已读文件（行号已核对）：

```
lib/common.glsl                 :31, 86-87, 108-123, 174, 222-226, 333-340, 352-354, 356-357,
                                  542, 559, 595-600, 623-629, 799-815
lib/colors/lightAndAmbientColors.glsl  :79-81
lib/colors/colorMultipliers.glsl       :16-19, 41-44
lib/colors/blocklightColors.glsl       :20, 60, 66, 110
lib/colors/skyColors.glsl              :4-55（全部在 #ifdef OVERWORLD 内）
lib/lighting/mainLighting.glsl         :500-547, 574-578
lib/lighting/minimumLighting.glsl      :1-17
lib/atmospherics/netherStorm.glsl      :1-78（全文）
lib/atmospherics/fog/mainFog.glsl      :8-60
lib/atmospherics/fog/coloredLightFog.glsl :1-52（全文）
lib/atmospherics/fog/bloomFog.glsl     :9-37
lib/materials/specificMaterials/terrain/lava.glsl           :1-23（全文）
lib/materials/specificMaterials/terrain/netherrack.glsl     :1-7（全文）
lib/materials/specificMaterials/translucents/netherPortal.glsl :1-77（全文）
lib/materials/materialMethods/wavingBlocks.glsl  :150-165
lib/materials/materialMethods/worldSpaceRef.glsl :139-153
lib/materials/materialHandling/terrainIPBR.glsl  :792-806, 970-984
lib/voxelization/lightVoxelization.glsl          :4-13, 98-101, 158-190
program/deferred1.glsl                 :352-388
program/composite1.glsl                :79-87, 224-258
program/composite3.glsl                :71-78
program/composite5.glsl                :130-139
program/gbuffers_basic.glsl            :99-107
program/gbuffers_beaconbeam.glsl       :90-96
program/gbuffers_skytextured.glsl      :105-113
shaders.properties                     :19-21, 31-57, 67-68, 258-279
lang/en_US.lang                        :82, 100-101, 152, 398-430, 774, 910-911, 1165-1172
block.properties                       :27-39, 67, 70, 72, 126-128, 165-172, 189, 207, 222-228,
                                         240-251, 264, 271-274, 285-300, 334-337, 358-362, 374-385,
                                         404-406, 467
dimension.properties                   :1-9
world-1/deferred1.fsh                  :1-7（维度覆盖样板）
```
