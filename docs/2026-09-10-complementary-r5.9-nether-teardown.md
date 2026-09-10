# Complementary r5.9 下界部分完整拆解

参考来源：Modrinth `complementary-reimagined` / `complementary-unbound`，版本 **r5.9（2026-09-02）**。
本地位置：`Astra并行开发/nether/_analysis/complementary/{Reimagined,Unbound}/`（`/_analysis/` 已 gitignore）。
两个风格源码相同，只有默认设置不同；下文行号以 `Reimagined` 为准。

结论先放一句：**Complementary 的下界不是「雾 + 熔岩辉光」，而是「一个体积光系统 + 一个体积噪声风暴 + 一个平铺底色」。**
熔岩的亮度几乎全部来自**体积光（colored light volume）的距离衰减采样**，而不是任何写在光照公式里的熔岩常量。

---

## 0. 渲染链总览

| 阶段 | 下界行为 | 文件 |
|---|---|---|
| 维度接线 | `world-1/*` 每文件 `#define NETHER` | `dimension.properties:6` |
| 编译期开关 | 下界 `#undef ATMOSPHERIC_FOG`、`#undef NO_WAVING_INDOORS`；非下界 `#undef NETHER_STORM` | `lib/common.glsl:595-600` |
| 天空贴图 | `gbuffers_skytextured` 下界 → `vec4 color = vec4(0.0)`（清零） | `program/gbuffers_skytextured.glsl:107-109` |
| 天空颜色 | 天空分支直接写 `netherColor * (1 - maxBlindnessDarkness)` | `program/deferred1.glsl:375-381` |
| 方块光照 | `lightColor = vec3(0)`；`ambientColor = (netherColor + 0.5*lavaLightColor) * (0.9 + 0.45*vsBrightness)` | `lib/colors/lightAndAmbientColors.glsl:79-81` |
| 光照装配 | `sceneLighting = lightColorM*shadowLightMult + ambientColorM*ambientMult`；下界方向项再平方 + 熔岩方向项 | `lib/lighting/mainLighting.glsl:500-540` |
| 阴影 | **完全不做**（`#ifndef NETHER` 跳掉 shadow map） | `lib/materials/materialMethods/worldSpaceRef.glsl:143` |
| 边界雾 | `fog = mix(lPos/farM, min1(lPos/min(farM,256)), 0.5)`，颜色 = `netherColor` | `lib/atmospherics/fog/mainFog.glsl:24-27, 47-48` |
| 体积光雾 | `coloredLightFog` raymarch 光体积 → `* netherColor * 5.0` | `lib/atmospherics/fog/coloredLightFog.glsl` |
| 体积风暴雾 | `GetNetherStorm` raymarch 3D 噪声，锚在 Y=28 | `lib/atmospherics/netherStorm.glsl` |
| 泛光 | 近处 ×0.7、远处 ×1.8 | `program/composite5.glsl:132-139` |
| 泛光雾 | `netherBloomAdd`（BORDER_FOG 开时 14，关时 3） | `lib/atmospherics/fog/bloomFog.glsl:11-14, 29-36` |
| 熔岩方块 | `color.rgb *= 0.84`、`lmCoordM = 0`、`emission` 由自身亮度驱动 | `lib/materials/specificMaterials/terrain/lava.glsl` |

---

## 1. 颜色系统（一切的基础）

### 1.1 `netherColor` —— 三种模式，默认模式 3

`lib/common.glsl:799-814`，`NETHER_COLOR_MODE` 默认 `3`（`common.glsl:119`）：

```glsl
// 模式 3（默认）
float netherColorMixer = inNetherWastes + inCrimsonForest + inWarpedForest + inBasaltDeltas + inSoulValley;
vec3 netherColor = mix(
    fogColor * 0.6 + 0.2 * normalize(fogColor + 0.0001),      // 未识别区域：由原版雾色派生
    (  inNetherWastes  * vec3(0.4,   0.14,  0.06)
     + inCrimsonForest * vec3(0.36,  0.07,  0.05)
     + inWarpedForest  * vec3(0.18,  0.10,  0.25)
     + inBasaltDeltas  * vec3(0.25,  0.235, 0.23)
     + inSoulValley    * vec3(0.10,  0.24,  0.24) ),          // 五个生物群系的硬编码调色板
    netherColorMixer
);
// 模式 2：只用第一支（纯 fogColor 派生）
// 模式 0：vec3(0.7, 0.26, 0.08) * 0.6          —— 固定色
```

三个要点，Astra 都没有：

1. **每生物群系一张硬编码调色板**，通过 5 个布尔 uniform 选择。生物群系身份不靠 `fogColor` 反推。
2. **调色板保留绝对亮度差**：净魂沙谷 `(0.10, 0.24, 0.24)` 明显比下界荒地 `(0.40, 0.14, 0.06)` 暗；
   玄武岩三角洲 `(0.25, 0.235, 0.23)` 是接近中性的灰。
3. **混合系数 `netherColorMixer` 兼作「是否在已知下界群系」的开关**：在未知区域（模组群系、结构内部）
   自动回退到由 `fogColor` 派生的颜色，不会变成黑或洋红。

> `fogColor * 0.6 + 0.2 * normalize(fogColor + 0.0001)` 这一支与 Astra 的
> `nether_atmosphere_tint()` 有共同祖先（都是「原版雾色 + 提亮」），但**参考几乎不用它**——
> 只在模式 2 和模式 3 的回退分支里出现。Astra 把它当成了唯一来源。

### 1.2 `lavaLightColor` —— 全部熔岩光的唯一常量

`lib/common.glsl:815`：

```glsl
vec3 lavaLightColor = vec3(0.15, 0.06, 0.01);
```

**就这么小。** 色相比 `1 : 0.4 : 0.0667`。它只在两个地方出现（见 §2.2），加起来峰值 R 0.259。

### 1.3 用户倍率

`lib/colors/colorMultipliers.glsl:16-19, 41-44`：

```glsl
vec3 netherLightMult = vec3(LIGHT_NETHER_R, LIGHT_NETHER_G, LIGHT_NETHER_B) * LIGHT_NETHER_I;
lightColorMult = netherLightMult;
vec3 netherAtmMult = vec3(ATM_NETHER_R, ATM_NETHER_G, ATM_NETHER_B) * ATM_NETHER_I;
atmColorMult = netherAtmMult;
```

默认全部 `1.00`（`common.glsl:333-340`），即开箱中性。给用户的是**光照**和**大气**两条独立 RGB×强度 通道。

---

## 2. 光照

### 2.1 直射光恒为零

`lib/colors/lightAndAmbientColors.glsl:80`：`vec3 lightColor = vec3(0.0);`

于是 `mainLighting.glsl:540` 的 `sceneLighting = lightColorM * shadowLightMult + ambientColorM * ambientMult`
第一项归零，**下界完全没有直射/阴影项**。Astra 的思路一致（无日光路径）。

### 2.2 环境光与熔岩项

`lib/colors/lightAndAmbientColors.glsl:81`：

```glsl
vec3 ambientColor = (netherColor + 0.5 * lavaLightColor) * (0.9 + 0.45 * vsBrightness);
```

熔岩在基础环境里只贡献 `0.5 * vec3(0.15,0.06,0.01)` = `vec3(0.075, 0.03, 0.005)`，
再乘 `(0.9 + 0.45*vsBrightness)`，`vsBrightness = 1` 时 ×1.35 → `vec3(0.101, 0.0405, 0.00675)`。

`lib/lighting/mainLighting.glsl:506-520`，方向性部分：

```glsl
#if !defined NETHER
    float NdotUM = 0.75 + NdotU * 0.25;
#else
    float NdotUM = 0.75 + abs(NdotU + 0.5) * 0.16666;
#endif
float NdotNM = 1.0 + 0.075 * absNdotN;
float NdotEM = 1.0 - 0.1 * absNdotE2;
directionShade = NdotUM * NdotEM * NdotNM;
...
#elif defined NETHER
    directionShade *= directionShade;                    // ★ 下界把方向项再平方一次
    ambientColorM += lavaLightColor * pow2(absNdotN * 0.5 + max0(-NdotU)) * (0.7 + 0.35 * vsBrightness);
#endif
```

两处值得抄：

- **`directionShade *= directionShade`**：下界的方向性对比被平方放大。`NdotUM` 的取值范围很窄
  （`NdotU` 从 -1 到 1 → 0.8333 到 1.0，最低点在 `NdotU = -0.5` 处 0.75），平方后差异拉开，
  朝上/朝下的明暗关系更硬。
- **熔岩只在「不朝上」的表面发力**：`pow2(absNdotN*0.5 + max0(-NdotU))`
  - 朝下（`NdotU=-1, NdotN=0`）→ `(0 + 1)² = 1.0`，最强
  - 水平朝南北（`NdotN=±1, NdotU=0`）→ `0.25`
  - 朝上（`NdotU=1`）→ `(0 + 0)² = 0`，**完全没有**
  峰值 `vec3(0.1575, 0.063, 0.0105)`。

### 2.3 熔岩总预算

| 来源 | 峰值 |
|---|---|
| 基础环境里的 `0.5*lavaLightColor` ×1.35 | `(0.101, 0.0405, 0.00675)` |
| 方向性熔岩项 | `(0.1575, 0.063, 0.0105)` |
| **合计** | **`(0.259, 0.1035, 0.0173)`** |

对比之下，`netherColor` 本身（下界荒地）是 `(0.40, 0.14, 0.06)` × 1.35 = `(0.54, 0.189, 0.081)`。
**熔岩在整个环境光里占不到一半**——它是「底色上的一层暖调」，不是主光源。

### 2.4 环境光遮蔽

`mainLighting.glsl:574-578`：

```glsl
#elif defined NETHER
    vanillaAO = pow(pow1_5(vanillaAO), 1.0 + NdotUmax0 * 0.5);
```

下界 AO 的指数单独写，比其他维度更重（`1.0 + NdotUmax0*0.5` 最大 1.5）。

---

## 3. 熔岩方块本身（`lava.glsl` 全文 23 行，三板斧）

```glsl
color.rgb *= 0.84;                       // ① 无条件降低反照率 16%

#ifdef NETHER                            // ② 下界：用噪声轻微扰动 gamma，做出流动感
    vec3 worldPos = playerPos + cameraPosition;
    vec2 lavaPos = (floor(worldPos.xz * 16.0) + worldPos.y * 32.0) * 0.000666;
    vec2 wind = vec2(frameTimeCounter * 0.012, 0.0);
    float noiseSample = texture2DLod(noisetex, lavaPos + wind, 0.0).g;
    noiseSample = (noiseSample - 0.5) * 0.1;          // ∈ [-0.05, +0.05]
    color.rgb = pow(color.rgb, vec3(1.0 + noiseSample));
#endif

noDirectionalShading = true;             // ③ 不吃方向性明暗
lmCoordM = vec2(0.0);                    // ③ 不吃 lightmap —— 即「不被自己的光照亮」
emission = GetLuminance(color.rgb) * 7.48 + 0.5;                 // 自发光强度由自身亮度驱动
maRecolor = vec3(clamp(pow2(pow2(pow2(smoothstep1(emission * 0.28)))), 0.12, 0.4) * 1.3)
          * vec3(0.25, vec2(0.175));                              // 方块光重染色，R 上限 0.13
```

关键三条：

- **`color.rgb *= 0.84`**：熔岩不是被提亮，是被**压暗**。
- **`lmCoordM = vec2(0.0)`**：熔岩是 15 级光源，自己脚下的 lightmap 接近 1.0。参考把这一个坐标清零，
  于是熔岩表面**不会叠加一份自己发出的光**。这是「不被自身照亮」的实现方式，**也是 Astra 目前缺的一条**。
- **`emission` 由 `GetLuminance(color.rgb)` 驱动**（而不是一个常量）：纹理亮的地方发光强，
  暗纹处发光弱，所以熔岩表面自身有明暗层次，不是一片均匀的亮红。
- `maRecolor` 是给彩色方块光系统用的重染色，被 `clamp(..., 0.12, 0.4)` 卡住，R 最高只到 0.13。

另外 `lib/colors/blocklightColors.glsl:20, 60, 66, 110`：
`lavaSpecialLightColor = vec3(3.25, 0.9, 0.2) * 3.9` = `vec3(12.675, 3.51, 0.78)`（色相比 1 : 0.277 : 0.0615），
熔岩方块以强度 `0.8` 注册，熔岩锅 `0.0`，岩浆块 `×0.1`。这是 HDR 的**光源强度**，走方块光系统，
不是直接加进画面的颜色。

---

## 4. 天空

`program/deferred1.glsl:362-381` 的天空分支：

```glsl
{ // Sky
    skyFade = 1.0;
    #ifdef NETHER
        color.rgb = netherColor * (1.0 - maxBlindnessDarkness);   // 就这一行
        #ifdef ATM_COLOR_MULTS
            color.rgb *= atmColorMult;
        #endif
    #endif
```

- 下界天空 = **`netherColor` 平铺**。没有天顶/地平线渐变，没有太阳、月亮、星、云、极光、霓虹。
- 原版天空贴图被清零（`gbuffers_skytextured.glsl:107-109`）。
- `maxBlindnessDarkness = max(blindness, darknessFactor)`（`shaders.properties:275`）统一处理失明/黑暗效果。

> Astra 的 `nether_sky()` 做了天顶 0.55 / 地平线 1.30 的渐变 + 地平线下的熔岩池，
> 这是 Astra 自己的设计（design.md 4.5 红/橙渐变天空），**参考没有对应实现**。

---

## 5. 雾（本任务「空间雾」的对照重点）

参考的下界有**四套并行的雾**，各自独立。

### 5.1 边界雾：`netherColor` 平铺

`lib/atmospherics/fog/mainFog.glsl:24-27`：

```glsl
#ifdef NETHER
    float farM = min(renderDistance, NETHER_VIEW_LIMIT);
    float fog = lPos / farM;
    fog = mix(fog, min1(lPos / min(farM, 256.0)), 0.5);       // 两条线性斜坡取混合
#endif
```

`:47-48`：`vec3 fogColorM = netherColor;`

**没有熔岩加法项。** `ATMOSPHERIC_FOG` 在下界被 `#undef`（`common.glsl:596`），
所以那套带太阳方向、空气透视、生物群系着色的大气雾在下界根本不编译。

### 5.2 体积光雾 `coloredLightFog` —— **这才是「熔岩附近的雾」**

`lib/atmospherics/fog/coloredLightFog.glsl` 全文（52 行），raymarch 彩色光体素体积：

```glsl
float maxDist = min(effectiveACTdistance * 0.5, far);
int sampleCount = int(maxDist / 8.0 + 0.001);
for (int i = 0; i < sampleCount; i++) {
    if (lTracePos > lViewPos1) break;
    if (any(greaterThan(abs(tracePos * 2.0), vec3(voxelVolumeSize)))) break;
    vec4 lightVolume = GetLightVolume(SceneToVoxel(tracePos) / vec3(voxelVolumeSize));
    vec3 lightSample = lightVolume.rgb;
    float lTracePosM = length(vec3(tracePos.x, tracePos.y * 2.0, tracePos.z));   // y 加权 2×
    lightSample *= max0(1.0 - lTracePosM / maxDist);      // ★ 线性距离衰减
    lightSample *= pow2(min1(lTracePos * 0.03125));       // ★ 近处 32 格内平方抑制（1/32）
    if (lTracePos > lViewPos) lightSample *= translucentMult;   // 被几何体遮挡
    lightFog += lightSample;
}
#ifdef NETHER
    lightFog *= netherColor * 5.0;
#endif
lightFog *= 1.0 - maxBlindnessDarkness;
lightFog = pow(lightFog / sampleCount, vec3(0.25));       // ★ 四次方根压缩
```

四个「防瞎眼」设计，每一个 Astra 都没有：

1. **光体积驱动**：亮度来自游戏里**实际累积的光**（熔岩作为光源进了体素体积），不是写死的颜色。
2. **线性距离衰减** `max0(1 - d/maxDist)`：光雾随距离消失。
3. **近处平方抑制** `pow2(min1(lTracePos * 0.03125))`：`1/32` 使得 **32 格以内按平方从 0 长到 1**。
   站在熔岩边上时这项接近 0 —— **近距离根本不泛光**。这是「岩浆不能瞎眼」最直接的一招。
4. **四次方根压缩** `pow(x, 0.25)`：把累加值压回可视范围。

调用处 `program/composite1.glsl:256-258`，强度 `COLORED_LIGHT_FOG_I = 0.65`（默认，`common.glsl:37`）。

> 还有 y 轴加权：`length(vec3(x, y*2, z))` —— 让光雾在垂直方向上衰减更快，
> 于是熔岩的热气不会无限往上飘。

### 5.3 体积风暴 `netherStorm` —— 下界的「空气感」

`lib/atmospherics/netherStorm.glsl` 全文 78 行：

```glsl
maxDist = min(min(renderDistance, NETHER_VIEW_LIMIT), 512.0);
int sampleCount = int(maxDist / 8.0 + 0.001);          // LOW_QUALITY 时 /16
vec3 traceAdd = nPlayerPos * maxDist / sampleCount;
vec3 tracePos = cameraPosition + traceAdd * dither;

for (int i = 0; i < sampleCount; i++) {
    tracePos += traceAdd;
    float lTracePos = length(tracePos - cameraPosition);
    if (lTracePos > lViewPos1) break;

    vec3 wind = vec3(frameTimeCounter * 0.002);
    vec3 tracePosM = tracePos * 0.001;
    tracePosM.y += tracePosM.x;                        // 剪切，做出斜向层理
    tracePosM += Noise3D(tracePosM - wind) * 0.01;
    tracePosM = tracePosM * vec3(2.0, 0.5, 2.0);       // 垂直压扁 2×，水平拉伸

    float traceAltitudeM = abs(tracePos.y - NETHER_STORM_LOWER_ALT);   // 28
    if (tracePos.y < NETHER_STORM_LOWER_ALT) traceAltitudeM *= 10.0;   // 低于锚点衰减快 10×
    traceAltitudeM = 1.0 - min1(abs(traceAltitudeM) / NETHER_STORM_HEIGHT);   // 200

    for (int h = 0; h < 4; h++) {                      // 4 个倍频
        float stormSample = pow2(Noise3D(tracePosM + wind)) * traceAltitudeM;
        stormSample = pow2(pow2(stormSample));         // 累计噪声^8，只留细丝
        stormSample *= sqrt1(max0(1.0 - lTracePos / maxDist));   // 距离衰减（开方）
        netherStorm.a += stormSample;
        tracePosM *= 2.0;
        wind *= -2.0;
    }
    if (lTracePos > lViewPos) { netherStorm.rgb *= translucentMultM; netherStorm.a *= lum(translucentMultM); }
}

netherStorm.a = min1(netherStorm.a * NETHER_STORM_I);        // 0.40，硬上限
netherStorm.rgb *= netherColor * 3.0 * (1.0 - maxBlindnessDarkness);
```

调用处 `program/composite1.glsl:241-253`：`volumetricEffect = GetNetherStorm(...)`，然后
`color = mix(color, volumetricEffect.rgb, volumetricEffect.a)`。

三处关键设计：

- **颜色与强度分离**：返回值是 `vec4(netherColor*3.0, 强度)`，用 **alpha 混合**而不是加法。
  强度被 `min1(... * 0.40)` 卡死，**永远不可能「叠加到过曝」**。Astra 的云层项是加法进雾色。
- **高度锚点在 Y=28**，不是熔岩海的 Y=32。语言文件写得很直白：
  > "Determines the lower starting point of the Nether Storm. The Nether Storm **won't appear below this altitude**,
  > and it will look **the most bright right above** this altitude."
  > —— `lang/en_US.lang:405`

  即：**风暴在熔岩面上方最浓，越往下越没有。** Astra 的熔岩辉光恰好相反，是在熔岩面**以下**浓度翻倍。
- **垂直范围 200 格**，覆盖整个下界柱，不是贴着熔岩的一层。

### 5.4 泛光雾 `bloomFog`

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
    bloomFog *= bloomFog * bloomFog;                   // ^3
    bloomFog = 1.0 - exp(-8.0 * bloomFog);
    bloomFog *= float(isEyeInWater == 0);
    float bloomFogMult = netherBloomAdd;
```

用来在远处压制泛光、避免远处的亮块糊成一片。

---

## 6. 泛光的下界调制 —— 就近削弱

`program/composite5.glsl:132-139`：

```glsl
#if defined BLOOM_FOG && defined NETHER && defined BORDER_FOG
    float farM = min(renderDistance, NETHER_VIEW_LIMIT);
    float netherBloom = lViewPos / clamp(farM, 96.0, 256.0);
    netherBloom *= netherBloom;                        // ^2
    netherBloom *= netherBloom;                        // ^4
    netherBloom = 1.0 - exp(-8.0 * netherBloom);
    netherBloom *= 1.0 - maxBlindnessDarkness;
    bloomStrength = mix(bloomStrength * 0.7, bloomStrength * 1.8, netherBloom);
#endif
```

**近处 `bloomStrength × 0.7`，远处 `× 1.8`。**

也就是说：**站在熔岩旁边，泛光被砍到 70%；看远处的熔岩海，泛光才放大到 180%。**
这是「岩浆不瞎眼」的第三招（前两招是 `lmCoordM = 0` 和光雾的 32 格抑制）。

---

## 7. 阴影：下界完全不做

`lib/materials/materialMethods/worldSpaceRef.glsl:143`：

```glsl
#ifndef NETHER
    vec3 shadow = shadowMult;
    ...
    shadow = GetShadow(...);
#endif
```

下界没有直射光，也就没有阴影采样。与 Astra 的设计一致。

顺带一个 hack 值得知道：`program/gbuffers_basic.glsl:101-103`

```glsl
#if COLORED_LIGHTING_INTERNAL > 0 && defined NETHER
    if (gl_FragCoord.x < 0.0)
    color = shadow2D(shadowtex0, vec3(0.5)); // To Activate Shadowmap in Nether
#endif
```

`gl_FragCoord.x < 0.0` 永远不成立，这个分支是**故意写死的死代码**——
唯一目的是让 Iris 认为 shadow map 被用到，从而不去裁掉它（彩色光体积依赖它的深度）。

---

## 8. 其他下界专属处理

| 位置 | 处理 |
|---|---|
| `lib/materials/materialHandling/terrainIPBR.glsl:796-799, 974-977` | 下界金矿 / 下界石英矿的发光选项，`emission` 由 `color.g` / `color.b` 驱动 |
| `lib/materials/materialMethods/wavingBlocks.glsl:154-157` | 垂泪藤 / 缠怨藤在下界摆动（`#if defined NETHER \|\| defined DO_NETHER_VINE_WAVING_OUTSIDE_NETHER`） |
| `lib/materials/specificMaterials/translucents/netherPortal.glsl` | 8 次采样拖影 + `lmCoordM = vec2(0.0)` + `emission = clamp(emission*120, 0.03, 1.2) * 8.0`（上限 9.6）+ 近处 `color.a *= min1(lViewPos - 0.2)` |
| `lib/materials/specificMaterials/terrain/netherrack.glsl` | 仅 7 行：`smoothnessG = min1(pow2(color.r) * 1.5)`，`smoothnessD = smoothnessG` |
| `program/gbuffers_beaconbeam.glsl:92-96` | 下界跳过信标光柱的高度重映射 |
| `program/composite3.glsl:73-74` | 世界虚化景深倍率 `WB_DB_NETHER_I = 64.0` |
| `lib/voxelization/lightVoxelization.glsl:162-163, 186-187` | 下界金矿 / 石英矿进光体积（发光矿选项开启时） |

---

## 9. 下界相关选项与默认值

`lib/common.glsl:118-123, 174, 333-340`：

| 选项 | 默认 | 含义 |
|---|---|---|
| `NETHER_VIEW_LIMIT` | `256.0` | 下界可视距离上限，同时是边界雾与风暴雾的 `farM` |
| `NETHER_COLOR_MODE` | `3` | 3 = 每群系调色板；2 = 纯雾色派生；0 = 固定色 |
| `NETHER_STORM` | 开 | 体积风暴雾总开关 |
| `NETHER_STORM_LOWER_ALT` | `28` | 风暴下锚点高度 |
| `NETHER_STORM_HEIGHT` | `200` | 风暴垂直范围 |
| `NETHER_STORM_I` | `0.40` | 风暴不透明度上限 |
| `COLORED_LIGHT_FOG_I` | `0.65` | 体积光雾强度 |
| `WB_DB_NETHER_I` | `64.0` | 世界虚化景深倍率 |
| `LIGHT_NETHER_R/G/B/I` | `1.00` | 光照颜色倍率 |
| `ATM_NETHER_R/G/B/I` | `1.00` | 大气颜色倍率 |
| `NETHER_ATM_MULTS` 屏 | — | `screen.NETHER_SETTINGS` / `NETHER_ATM_MULTS` 两组菜单 |

---

## 10. 与 Astra 的逐项对照

| 维度 | Complementary r5.9 | Astra 现状 | 差距性质 |
|---|---|---|---|
| 直射光 | `lightColor = vec3(0)` | 无直射项 | ✅ 一致 |
| 阴影 | 下界不做 | 下界不做 | ✅ 一致 |
| 天空 | `netherColor` 平铺 | 天顶/地平线渐变 + 熔岩池 | Astra 自有设计，参考无 |
| 生物群系来源 | 5 布尔 → 硬编码调色板 + 未知区域回退 | `normalize(fogColor)` 四次方根 | ⚠ 机制不同 |
| 生物群系亮度 | 保留绝对亮度差（0.1 ~ 0.4） | `normalize()` 归一 → 只留色相 | ⚠ **亮度序丢失** |
| 熔岩环境光 | 峰值 R `0.259` | 已改到 R `0.256` | ✅ 已对齐 |
| 熔岩方块 | `×0.84` + `lmCoordM=0` + `emission` 由亮度驱动 | `×1.35` 自发光提亮 + 亮度余量 | ❌ 缺 `lmCoordM` |
| 熔岩附近的雾 | 体积光 raymarch，线性衰减 + 32 格平方抑制 + 四次方根 | 单点云层项，无距离衰减 | ❌ 结构性差距 |
| 体积雾 | `netherStorm` raymarch，alpha 混合、上限 0.40、锚在 Y=28 上方最浓 | 单点云项加进雾色，无上限 | ❌ 结构性差距 |
| 泛光 | 近 ×0.7 / 远 ×1.8 | 无下界调制 | ⚠ Astra 的 bloom 仅主世界 |
| 方向性 | `0.75 + |NdotU+0.5|/6`，再平方 | `0.67 + y*0.33` | ⚠ 参考下界对比更强 |
| 环境光下限 | 无独立下限项 | `MIN_AMBIENT_COLOR`（已改沿 tint 重定向） | Astra 自有，参考无 |
| 熔岩有明暗纹理 | `emission` 由自身亮度驱动 | 无 | 可借鉴 |

### 结构性差距的根源

参考的熔岩亮度分配是：

```
熔岩方块（块状光源，被 ×0.84 压暗、不让自照）
   ↓ 进入彩色光体积
体积光雾 raymarch（距离衰减 + 32 格内平方抑制 + 四次方根）
   ↓
画面
```

Astra 的是：

```
熔岩方块（被 ×1.35 提亮、叠加自己的光）
   ↓ 另有一条与方块无关的路径
按世界 Y 计算的距离无关辉光（直接加进光照，再直接加进雾色）
   ↓
画面
```

**参考用「空间上衰减的采样」解决亮度分配；Astra 用「一个写在常量里的量级」解决。**
参考那套需要 raymarch（design.md 5 明确拒绝：前向、零 compute），Astra 的单点近似是刻意的取舍。

因此可以抄的是**近处抑制**这一招——它不需要 raymarch，只需要知道「目标是离相机多远」：
`nether_glow *= pow2(min1(distanceToCamera * k))`，代价一次乘加。
**这是完全不搬 raymarch 也能拿到的最大一块收益。**

---

## 11. 可直接借鉴 / 需要公共边界 / 不能照搬

### 可直接在 `global/dimension/nether.glsl` 内实现

1. **熔岩辉光加近处抑制**：`pow2(min1(fragDistance * k))`，`k` 取参考的 `1/32`。
   站在熔岩旁不再被自己的辉光顶着。参考同时保留了 `max0(1 - d/maxDist)` 的远端衰减。
2. **熔岩辉光的方向形态改成参考的形状**：`pow2(absNdotN*0.5 + max0(-NdotU))`
   —— 朝上的面完全不受熔岩影响（现在 Astra 的朝上面仍拿 0.5）。
3. **熔岩色温：让熔岩有明暗纹理而不是均匀亮**。参考用 `GetLuminance(color.rgb)` 驱动发光强度。
   Astra 在 `nether_lighting()` 里拿得到 `surfaceColor`，可以做同样的「亮度驱动」。
4. **风暴的 alpha 混合式组织**：把云层项从「加进雾色」改成「按强度混合到 `tint*3`」，
   并给强度一个 `min1` 上限。这样永远不可能过曝。
5. **补充垂直锚点方向**：参考的风暴在锚点**上方**最浓、下方衰减快 10×；
   Astra 的辉光在熔岩面**下方**浓度翻倍。这两种取向相反，值得单独判定哪个更符合用户预期。

### 需要主任务改公共文件

1. **熔岩专属材质 id**（已在 `docs/handoffs/nether.md` 记为 P-001）：
   参考的 `lmCoordM = vec2(0.0)`（不被自己的光照亮）在当前 `10u` 掩码下无法实现。
2. **下界彩色光体积**：参考的整套「熔岩附近的雾」建立在 Iris 自定义图像 + 光体素化之上。
   Astra 若要走这条路，属于新增基础设施，远超本 worktree 范围。

### 结构上不能照搬

- **`netherStorm` 的 raymarch**：`sampleCount = maxDist/8`，256 格时 32 次采样 ×4 倍频噪声。
  与 design.md 5「前向、零 compute」直接冲突。
- **`coloredLightFog` 的 raymarch**：同类问题，且依赖光体积。
- **`NETHER_COLOR_MODE 3` 的硬编码群系调色板**：抄数值容易，但 Astra 的
  `nether_atmosphere_tint()` 是「从原版雾色派生」这条设计线（design.md 4.5 明确要求
  「保留各生物群系辨识度」且不引入调色板数据）。引入硬编码表是设计变更，不是修 bug。

---

## 12. 一句话总结

> 参考的下界靠**三件事**避免熔岩瞎眼：**熔岩方块不被自己的光照亮（`lmCoordM=0`）**、
> **熔岩附近的雾是距离衰减且 32 格内被平方抑制的体积光**、**近处泛光砍到 0.7×**。
> 熔岩色本身只有 `vec3(0.15, 0.06, 0.01)`，在环境光里占不到一半。
>
> Astra 缺的不是颜色，是**空间衰减**。raymarch 搬不动，但「近处抑制」这一招一次乘加就能拿到。
