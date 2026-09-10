# IterationT 3.2.0 源码阅读笔记：可借鉴的设计

来源：`_analysis/latest-2026-09-10/iterationT-3.2.0`（下载与登记见 `sources.json`）。
规模：75 个 `.glsl` + 123 个 `.fsh`，根层 45 个 pass、17 个 composite。
授权：归档内无许可文件，按专有处理；以下均为"读设计与算法"，不是"照抄代码"。

---

## 1. 架构层：薄壳 pass + 用 define 选择程序的共享模块

这是整包最值得学的一处。

`composite10.fsh` 全文只有 8 行：

```glsl
#version 330
#define DIMENSION_MAIN
#define PROGRAM_BLOOM_1
#include "/Lib/IndividualFounctions/Bloom.glsl"
```

真正的实现全在 `Lib/IndividualFounctions/Bloom.glsl` 里，用 `#ifdef PROGRAM_BLOOM_*` 分出
降采样 / 升采样 / 合成等多个子程序；每个 pass 文件只负责"选哪个程序"。

- **优点**：一个效果的全部阶段放在同一文件，改算法时不会漏掉配对的半段；pass 顺序与依赖一目了然。
- 对比 Astra：我们的 `program/*.fsh` 是"一个 pass 一个文件 + 共享 module"，没有 define 选择层。
  当像 godrays/bloom 这种"多阶段同族"效果变多时，ITT 的组织方式更不容易散架。
- 配套：`Lib/Programs/CompositeVS.glsl`（5.4KB）给所有 composite 共用顶点着色器；
  `Lib/Programs/Final.glsl`（583 行）承载整条 final 链。

**另一处**：`/* DRAWBUFFERS:13 */` —— 一次 pass 同时写 colortex1 与 colortex3（MRT）。
省 pass 的常规手段，但 ITT 用得比较彻底（阴影、VFOG、GI 都靠 MRT 并行输出）。

## 2. 数学工具箱 `Lib/Utilities.glsl`（302 行）

一位作者把"能省的都省了"的典型：

| 手法 | 内容 | 价值 |
|---|---|---|
| `fsqrt(x)` | `intBitsToFloat(0x1fbd1df5 + (floatBitsToInt(x) >> 1))` | 位运算近似开方，一次整数移位 |
| `fsign(x)` | `uintBitsToFloat((floatBitsToUint(x) & 0x80000000u) \| 0x3f800000u)` | 无分支取符号，被 `OctWrap` 复用 |
| `facos(x)` | `(-0.156583*|x| + hPI) * fsqrt(1-|x|)` | 一次多项式 + 近似开方替代 `acos` |
| `Bayer2..Bayer128` | `bayer4 = bayer2(0.5*a)*0.25 + bayer2(a)` 递归组合 | 由 2x2 递推构造到 128x128，代码极短 |
| `Sequences_R1/R2` | `fract(0.5 + n/φ)`、`fract(0.5 + n*(1/plastic, 1/plastic²))` | 黄金比/塑胶比低差异序列，固定采样数下分布最均匀 |
| `Pack2x8/2x16` | 两值打包进一个通道 | 省带宽 |
| `EncodeNormal/OctWrap` | 八面体法线编码 | 两张 8-bit 存一个法线 |

`TemporalNoise.glsl` 只有 11 行，但思路很巧：

```glsl
vec2 BlueNoiseTemproal(){
    return fract(texelFetch(noisetex, ivec2(gl_FragCoord.xy) % 64, 0).xy
                 + vec2(goldenRatio, plasticRatio) * vec2(frameCounter % 64));
}
```

**空间用蓝噪声纹理 + 时间用黄金比偏移**：每帧的采样点仍然在空间上分布良好，跨帧又不会聚成一堆。
这是它敢在 VPS / VFOG / GI 里只用 8~16 个采样的底气。Astra 没有 TAA，不能直接照搬时间项
（会闪），但**空间那一半（蓝噪声 dither）完全可用**，而且正是我们光束"像实体锥"的解法。

## 3. 阴影：变半影（VPS）+ 无分支彩色阴影合成

`Lib/BasicFounctions/Sunlight_Shadow.glsl::VariablePenumbraShadow`

- 先用 3×3 邻域统计 `shadowtex0` 的深度差方差 `avgDiff`；
- 半影宽度 `sampleSpread = avgDiff * 0.2 * spread + SHADOW_BASIC_BLUR / res`；
  即**几何起伏越大、半影越宽**（接触硬化软阴影的近似），而不是全场景固定 PCF 宽度；
- 再用黄金角旋转 + `sqrt` 分布的圆盘抖动，配 `BlueNoiseTemproal()` 做时域抖动；
- 叶片/草另给最小 spread（`0.015*mask.leaves + 0.01*mask.grass`）。

**彩色阴影合成是无分支的一行**：

```glsl
float translucentShadow = step(sampleCoord.z, textureLod(shadowtex0, ...).x); // 有任何遮挡体
float soildShadow       = textureLod(shadowtex1, ...);                        // 仅不透明遮挡
result += vec3(translucentShadow);
result += shadowColorSample * (soildShadow - translucentShadow);              // 差值为 1 = 只有半透明挡着
```

Astra 的 `surface_shadow_light` 做的是同一件事，但用了 `#ifdef` + 混合表达式；ITT 这版更短且无分支。
**可变半影是 Astra 目前没有的质量项**——我们的 `SHADOW_SOFTNESS` 是固定宽度。

## 4. 水下：焦散与体积雾（对我们当前问题最直接）

### 4.1 焦散：几何聚焦量，而不是阴影贴图染色

`Sunlight_Shadow.glsl::CalculateWaterCaustics` 与 `UnderwaterVolumetricFog.glsl::CalculateWaterCaustics`

核心思路：**水面波法线让垂直光线折射，折射后光线落在哪、离接收点多远，就是焦散的强弱。**

```glsl
vec3 lookupCenter = worldPos + vec3(0.0, 1.0, 0.0);        // 抬到水面
vec3 wavesNormal  = GetWavesNormalFromTex(lookupCenter);   // 从纹理取波法线
vec3 refractVector = refract(vec3(0,1,0), wavesNormal, 1.0);
vec3 collisionPoint = lookupCenter - refractVector / refractVector.y;  // 折射光线落点
float dist = dot(collisionPoint - worldPos, collisionPoint - worldPos) * 7.1;
caustics += 1.0 - saturate(dist * 7.0);                    // 聚焦在接收点附近 => 亮
```

- 取 3×3 共 9 个样本 + 时间蓝噪声抖动后求和；
- 最后 `shadow *= CalculateWaterCaustics(worldPos);` —— **直接乘进阳光项**（`composite.fsh:327`）。

**这是 Astra 该走的路**：不依赖"水方块被写进 shadowcolor0 且染色正确"这条我离线验证不了的链，
而是在接收点直接求值，物理上还是"光被水面波聚焦"的近似，且天然跟随太阳方向（折射用的是
`worldShadowVector`）。

### 4.2 波法线从哪来：把水面法线写进一张颜色缓冲当纹理用

`GetWavesNormalFromTex` 从 `colortex7` 读法线，坐标是**世界 XZ 平铺**：

```glsl
vec2 coord = position.xz;
vec3 lightVector = refract(worldShadowVector, vec3(0,1,0), 1.0 / WATER_REFRACT_IOR);
coord.x += position.y * lightVector.x / lightVector.y;   // 沿折射光方向做视差
coord.y += position.y * lightVector.z / lightVector.y;
coord *= 0.02;  coord = fract(coord);                     // 平铺
coord *= pixelSize * min(screenSize.y, CAUSTICS_TEX_RESOLUTION);
vec3 normal = DecodeNormal(textureLod(colortex7, coord, 0).xy);
```

**设计要点**：水面 pass 把波法线写进一张分屏缓冲的固定区域，其他 pass 当成"可平铺的世界空间法线图"
来查。好处是焦散的世界相位与真实波浪**天然一致**（同一份法线），不需要两套噪声参数对齐。
我们用 `solas_water_caustics` 自己算高度场，与水面法线是两套场，永远对不齐——这是我们的结构性问题。

### 4.3 水下体积雾（光束）

`UnderwaterVolumetricFog.glsl::UnderwaterVolumetricFog`，96 行，几个关键设计：

```glsl
const float range = 40.0;
float noise = BlueNoiseTemproal().y;
for (i...) {
    float rayLength = (i + noise) * stepLength;       // 抖动起点
    ...
    float caustics = CalculateWaterCaustics(rayPos);
    shadow *= caustics * caustics * caustics;          // 焦散调制光束 -> 柔和条纹
    shadow /= max(3.0, rayLength * 0.1);               // 距离衰减 -> 近处消失
    shadow *= pow(vec3(0.1,0.6,1.0)*0.99, vec3(rayLength*0.04*WATERFOG_DENSITY));  // 水体吸收
}
result *= colorShadowlight * (0.04 * phace * SUNLIGHT_INTENSITY * UNDERWATER_VFOG_DENSITY);
```

三个设计点，正好逐条对上用户对我们光束的三条批评：
1. **`shadow *= caustics³`** —— 光束亮度被水面焦散调制，所以是"一条条柔和的亮柱"而不是均匀锥；
2. **`/= max(3, rayLength*0.1)`** —— 近处被压掉，这就是"走近一点光束就消失"；
3. **相函数用折射后的光方向**：`lightVector = refract(worldShadowVector, vec3(0,-1,0), 1/1.2)`，
   再用 `MiePhaseFunction(0.7, LdotV)` —— 水体内部的散射相位用**折射后的太阳方向**算，
   不是空气太阳方向。我们之前在这个点上反复错过。

## 5. 水：波高场与法线场分离，视差采样在切线空间

`WaterWaves.glsl`：`GetWaves()`（高度）与 `GetWavesNormal()`（法线）分开，另有
`GetWaterParallaxCoord()` 做视差；`vec4 textureSmooth()` 提供平滑查表。
`PhysicsOceans.glsl`：`physics_waveHeight / physics_waveDirection / physics_waveNormal /
physics_wavePixel` —— 把"方向谱波浪"拆成可单点求值的四个函数，便于在任意 pass 复用。
`Ripple.glsl`：`GetRainNormal(pos, strength, inout float wet)` —— **雨滴法线同时更新湿度**，
把"下雨变湿"和"涟漪法线"合成一次调用。

## 6. 后处理与管线

- `GlobalIllumination.glsl`（375 行）：**RSM（反射阴影贴图）** 取间接光 → `GI_TemporalFilter`（时域累积，
  带深度/法线校验与 `GI_RENDER_RESOLUTION` 半分辨率）→ `GI_SpatialFilter`（空间去噪）→ 再 `GTAOMultiBounce`
  合成。是"低分辨率 + 时域 + 空间滤波"三段式，而不是一次算对。
- `GTAO.glsl` 只有 145 行，但 `GTAOMultiBounce(ao, albedo)` 用一条三次多项式把单次 AO 提升为多次反弹：

  ```glsl
  vec3 a = 2.0404*albedo - 0.3324, b = -4.7951*albedo + 0.6417, c = 2.7552*albedo + 0.6903;
  return max(vec3(ao), ((ao*a + b)*ao + c)*ao);
  ```

  **一行拿到"多次反弹"观感**，Astra 目前没有这一项，性价比极高。
- `TAA.glsl`（381 行）：YCoCg 空间做邻域裁剪（减少色度拖影）+ `BicubicTexture` 做历史重投影。
- 运动向量：`CalculateCameraVelocity()` 从当前/上一帧矩阵推屏幕速度，供 TAA/运动模糊共用。
- 其他：`Bloom`、`DOF`、`MotionBlur`、`LensGlareFlare`、`FsrEASU`（FSR1 超分）、`AgX`、`CloudShadow`、
  `PlanarClouds`、`NUBIS`（体积云）、`Parallax`（POM）、`VanillaComposite`、`NetherColor`、`Blocklight`。

## 7. 对 Astra 的落地清单（按性价比排序）

| 优先级 | 项 | 依据 | 风险 |
|---|---|---|---|
| ★★★ | 焦散改为"几何聚焦量"直算，并乘进阳光项 | §4.1 | 低：无需阴影贴图配合，可离线数值验证 |
| ★★★ | 光束 = 体积雾 + **焦散调制** + **距离衰减** + 折射方向相函数 | §4.3 | 低：三点都是明确的公式改动 |
| ★★☆ | 波法线写入缓冲供焦散复用（对齐世界相位） | §4.2 | 中：要动水面 pass 的 MRT 布局 |
| ★★☆ | `GTAOMultiBounce` 一行提升 AO 质量 | §6 | 低 |
| ★★☆ | 采样抖动用蓝噪声（空间）替代当前的手写 hash | §2 | 低：无 TAA 时只取空间项 |
| ★☆☆ | 变半影阴影（VPS） | §3 | 中：要改阴影采样与邻域统计 |
| ★☆☆ | 薄壳 pass + define 选择程序的架构 | §1 | 低收益高工作量，重构级 |
| ★☆☆ | `fsqrt`/`fsign`/`facos`/Bayer 递归/低差异序列工具箱 | §2 | 低，属长期积累 |

**不建议**：TAA / GI / 体积云这类需要时域累积或整条新管线的项——Astra 的设计前提是"无 TAA、
前向一次算完"，引入会推翻既有取舍。

## 8. 授权

IterationT 归档不含许可文件，按专有处理（与本文件既有的 Refrax 条目同级）。
本笔记只记录**设计与算法思路**；任何代码级移植必须逐条登记到 `THIRD-PARTY.md`，
并受 `design.md` 9.3 发布闸门约束（发布前重写或取得授权）。
