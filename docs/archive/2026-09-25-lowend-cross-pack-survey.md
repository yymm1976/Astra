# 低配参考包横向普查与 Astra 落地评估（2026-09-25）

本文件是 [2026-09-25-low-end-optimization.md](2026-09-25-low-end-optimization.md) 的扩展轮。
前一轮读 5 个包（Steadfast / Mellow / Miniature / MakeUp / Sildur-Fast）并落地 4 项；本轮把样本扩到 **17 个包**，
做机器普查与共性提炼，并对每项手法给出 Astra 侧的落地评估。

仓库里已有的低配参考：

| 位置 | 包 |
|---|---|
| `_analysis/Steadfast-0.8.0/` | Steadfast 0.8.0 |
| `_analysis/Mellow Shader v3.4/` | Mellow 3.4 |
| `_analysis/refs-2026-09-24/` | Miniature 2.19、FastPBR 2.0、Shrimple v0.12（另有 7 个非低配包） |
| `_analysis/low-end-2026-09-25/sildur-fast/` | Sildur's Enhanced Default 1.20 Fast |
| `_analysis/lowend-refs-2026-09-25/` | **本轮新增 12 个**：MakeUp Ultra Fast 9.5e、Lite、Potato、Sildur's Vibrant、Bloop、Pegasus、SoftVoxelsLite、RenderPearl、BuildersQoL、SimplyUpscaled、ReShaded、JustColoredLighting |

普查脚本：`qa/tools/lowend_census.py`（只统计源码文本可直接比较的量，不展开宏、不计时）。

---

## 1. 机器普查

| 包 | 源文件 | 入口 | 行数 | colortex 格式声明 | 降采样缓冲 | enable 规则 | 档位 | custom uniform | 最大 MRT 扇出 |
|---|---|---|---|---|---|---|---|---|---|
| **Astra** | 254 | 41 | 10278 | 6 | **5** | 36 | 4 | 49 | 2 |
| Steadfast | 101 | 23 | 8570 | 5 | 1 | 2 | 19 | 146 | 1 |
| Mellow | 381 | 34 | 6754 | 4 | 1 | 52 | 3 | 32 | 1 |
| Miniature | 99 | 13 | 1482 | 0 | 0 | 5 | 4 | 0 | 1 |
| **MakeUp-UF** | 317 | 44 | 10357 | 6 | **0** | 1 | 8 | 30 | 3 |
| Sildur-Fast | 60 | 9 | 2577 | 0 | 0 | 1 | 2 | 1 | 1 |
| **Sildur-Vibrant** | 129 | 19 | 18401 | 7 | **0** | 9 | 0 | 2 | 3 |
| **Potato** | 168 | 23 | 8332 | 5 | **0** | 0 | 0 | 45 | 1 |
| Bloop | 393 | 62 | 23285 | 16 | 4 | 26 | 8 | 167 | 4 |
| **Lite** | 342 | 44 | 15056 | 11 | **0** | 8 | 6 | 42 | 4 |
| Pegasus | 339 | 33 | 28400 | 4 | 2 | 3 | 0 | 2 | 8 |
| RenderPearl | 258 | 39 | 4912 | 3 | 0 | 0 | 8 | 16 | 2 |
| BuildersQoL | 132 | 19 | 12949 | 0 | 0 | 0 | 0 | 15 | 3 |
| SimplyUpscaled | 165 | 18 | 11472 | 1 | 1 | 0 | 0 | 0 | 2 |
| SoftVoxelsLite | 295 | 52 | 19881 | 16 | 1 | 10 | 3 | 84 | 4 |
| ReShaded | 11 | 0 | 1143 | 0 | 0 | 0 | 0 | 0 | 0 |
| JustColoredLighting | 292 | 28 | 23391 | 1 | 1 | 0 | 0 | 0 | 2 |
| FastPBR | 321 | 45 | 16661 | 14 | 1 | 0 | 0 | 85 | 4 |
| Shrimple | 689 | 120 | 41021 | 13 | 4 | 4 | 2 | 34 | 4 |

**三条反直觉的读数：**

1. **降采样不是低配包的杠杆**。MakeUp-UF、Potato、Lite、Sildur-Vibrant、Sildur-Fast 的降采样缓冲**全部是 0**。
   它们要么给已有缓冲开 `MipmapEnabled` 用 mip 链（MakeUp 预计算 `softLod=log2(viewHeight/128)`，
   `shaders.properties:225-228` + `lib/bloom.glsl:25` 的 `texture2DLod`），要么直接缩放 UV 假装低分辨率
   （Sildur `composite.fsh:125` 的 `texcoord*4.0`）。省的是**渲染目标数量**，不只是带宽。
2. **MRT 扇出大 ≠ 贵**。Pegasus 扇出 8、Bloop/FastPBR/SoftVoxelsLite 扇出 4，都比 Astra 的 2 大，
   却都被列为低配/快速。原因是多出的附件写在**本来就要跑的几何 pass** 里，且位数极矮
   （Bloop 用 R16 / RGBA8 / R11F_G11F_B10F；FastPBR 在 RGBA16 里 `pack2x8` 塞四个字段，
   `pipeline.glsl:187-195`），并且写入被严格条件化（Pegasus 只写 3-4 张 vs 扇出 8 的分支）。
   成本模型是 **pass 数 × 分辨率 × 带宽**，不是附件数。
3. **Astra 是唯一"降采样但不做时间累积"的包**。上表里凡是用降采样的包
   （MakeUp、Potato、Lite、Bloop、FastPBR、SoftVoxelsLite、Shrimple）**都默认开 TAA 或跨帧累积**，
   靠时间维度把降采样损失的画质补回来。Astra 有 5 张降采样缓冲却无 TAA，
   于是只能**用每帧更多 tap 去补**——这是结构性差异，不是调参问题。

---

## 2. 跨包共性手法（17 包里 ≥4 家在做的）

### 手法 1：把昂贵效果变成「按需付费」
- Sildur-Vibrant 用 `block.properties` 打 matID 存进 colortex1，反射**只在金属/抛光/雨天表面**执行
  （`deferred1.fsh:83`、`gbuffers_water.fsh:207`）；并且 `program.deferred1.enabled=metallicRefl||polishedRefl||RainReflections`
  （`shaders.properties:8-13`）——**整个反射 pass 可以被选项关掉**。
- Bloop：VL 在 `fogAmount<=0.35` 早退（`fogloop.glsl:53-64`）；SSR 按粗糙度 2→6 采样（`reflection_lib.glsl:449`）。
- FastPBR：粗糙度 >0.6 **直接跳过 SSR**（`settings:81/85`）。
- MakeUp：云只在 `linearDepth>0.9999` 计算，地面像素零成本（`deferred_fragment.glsl:126`）。
- Sildur：阴影越出贴图边界直接 `return 1.0`（`deferred.fsh:553`）。

### 手法 2：整段停 pass，而不只是在 fragment 里返回零
- Sildur-Vibrant 5 条、Lite 4 条、Bloop 十余条 `program.*.enabled`。
- Potato 与 BuildersQoL 更彻底：**全包没有 shadow 程序**，直接删掉一整个 pass 类型。
- Steadfast：`program.deferred.enabled=SSR||REFRACTION||REFRACTION_ASSISTED`（`shaders.properties:27-30`）。
- 注：Potato 一条 enable 规则都没有，靠 `#ifdef` 清空 pass 体——那是**省算力不省 pass**，
  比 Potato 更省的是加了 enable 规则的那些。

### 手法 3：预计算常量搬到 CPU（custom uniform）
- Bloop 把 sunLight / atmosphereUp / 散射系数**全部**预计算成 uniform（`shaders.properties:286-573`）。
- MakeUp 13 条 custom uniform 全是 CPU 侧：`dayMixer/nightMixer` 抛物线取代时间判断、
  16 帧 TAA 偏移表、`pixelSizeX/aspectRatioInverse/fovYInverse`（`shaders.properties:94-228`）。
- Steadfast 有 146 条、Bloop 167 条。Astra 49 条，且照旧在逐像素重算。
- 所有包都没有禁用该机制。

### 手法 4：便宜的阴影
- **没有一家手写 PCF**。全部走硬件比较：`shadow2D` / `textureGather(sampler2DShadow)`。
- 核大小 4~12 tap + 抖动（MakeUp 4 次硬件比较 + 径向蝶形抖动，`lib/shadow_frag.glsl:24-27`；Sildur 12）。
- 核宽按 `shadowMapResolution/1024` 或按 shadowDistance 归一（Pegasus `shadows.glsl:77/133`；Bloop `shadowfunc_advanced.glsl:29-36`）。
- **非线性坐标扭曲**：Sildur `utilDistortion()` 用 `a=exp(0.05)`、`b=(exp(0.8)-a)*dist/128`
  的对数扭曲（`shaders.settings:42-48`）以低分辨率换远处精度；MakeUp `SHADOW_DIST` 随档 0.75→0.81。

### 手法 5：小而固定的辅助缓冲
- 天空：FastPBR 256×128、SoftVoxelsLite 256×384。
- 云阴影：FastPBR 512、SoftVoxelsLite 512。
- 水法线：Bloop 256²。3D 噪声：64³。体素：128–256³。
- 这些量级远小于全屏，且与视距无关。

### 手法 6：顶点级与低频计算
- ReShaded 把**全部光照放在顶点着色器**（`terrain.vsh:32` 采 lightmap + `:36-56` 按面法线三常数调制），
  片元零光照；全局曝光用一个 0.62 常数代替 tonemap（`terrain.fsh:156`）。
- Miniature 把雾与部分光色放到顶点（`program/textured_lit.vsh:115`）。
- MakeUp 的 `sqrt(sqrt(x))` 替代 `pow`（`lib/volumetric_clouds.glsl:88-91`）。
- Potato 把 `gauss9w/gauss9o` 写成 `const` 数组让驱动常量折叠（`world0/composite1.fsh:63-77`）。

### 手法 7：时间分摊（Astra 用不了的）
- SoftVoxelsLite：**1 spp** 全分辨率路径追踪 + 256 帧累积 + SVGF 去噪（`settings:80/88/94`）。
- FastPBR：TAAU + FXAA（`settings:128-130`）。
- MakeUp/Bloop/Sildur/Potato/Lite：全部默认开 TAA 或 FXAA。
- JustColoredLighting 的替代方案：**用更新间隔换轮数**。彩光传播压在 1 个 compute 里，
  `LIGHT_UPDATE_SPEED` 默认 1 时 `prepare_a/b/c/d` 四段全部关闭（`shaders.properties:328-356`）。

---

## 3. Astra 的实测开销分布

用 `qa/tools/lowend_census.py` 与逐文件扫描得到（默认档 BALANCED）。

### 3.1 每帧阶段数

| 维度 | 阶段 | 数量 |
|---|---|---|
| 主世界 | shadow, deferred, composite, composite1, composite2, composite3, composite4, final | **8 个全屏** |
| 下界 | shadow + **9 个 compute**（shadowcomp + A…H）+ deferred + composite1 + final | 13（其中 9 个是 compute） |
| 末地 | prepare, shadow, deferred, deferred1, composite1, final | 6 |

主世界 `composite5` 关闭（`AUTO_EXPOSURE` 在 BALANCED 为 `!AUTO_EXPOSURE`）；
`composite.enabled=true`、`composite3.enabled=true` 是**无条件**的（`shaders.properties:66, 80`）。

### 3.2 高开销循环（源码计数）

| 位置 | 次数 | 说明 |
|---|---|---|
| `program/deferred.fsh:32` | **96** | 雨天积水 SSR（每步含深度读） |
| `program/scattering.fsh:62-63` | **7×7 = 49** | 光束探针嵌套循环 |
| `global/atmosphere/clouds_planar.glsl:232` | `clamp(ceil(dist/16), 6, 64)` → **最多 64** | 平面云步数 |
| `global/water/raytrace.glsl:63` | 24 | SSR |
| `program/water_state.fsh:14,15` | 12, 20 | 水状态 |
| `global/dimension/nether_volume.glsl:68` | 16 | 下界体雾 |
| `global/post/bloom.glsl:107` | 13 | bloom tap |
| `program/deferred.fsh:81` | 10 | 雨天空气散射 |
| `global/water/light_shafts.glsl:53` | 7（`UNDERWATER_SHAFT_SAMPLES`） | 水下光束 |

### 3.3 缓冲与格式

6 个 `colortex*Format` 声明；5 张降采样：`colortex1`(0.5/0.25)、`colortex2`(0.25)、`colortex7`(0.25)、
`colortex8`(294×1)、`colortex9`(0.75)；MRT 扇出 2。无 TAA、无历史缓冲。

---

## 4. 逐手法的落地评估

评级依据：**收益**（能省多少，尽量量化）、**风险**（会不会改观感）、**是否需改架构**。

### A 级：可直接落地，无需架构变更

| # | 手法 | Astra 现状 | 预期收益 | 风险 |
|---|---|---|---|---|
| A1 | **下界 8 轮扩散改为分帧更新**（JustColoredLighting 手法 7 的变体） | `shadowcomp` + `A`–`H` **每帧 9 个 compute 全跑**（`shaders.properties:369-377`） | 下界每帧 compute **9 → 1~2**，其余按更新间隔摊销。这是全包最大的单点固定支出 | 中。轮数减少会让远处彩光扩散变慢；需要"静态区域不再重算"的判定，否则移动光源下会滞后 |
| A2 | **预计算常量搬到 custom uniform** | 49 条，但逐像素仍重算大气/光色 | 不减少采样，减少每像素 ALU。Steadfast 146 / Bloop 167 条说明还有空间 | 低。需逐个确认搬到 CPU 后与时间/天气的耦合 |
| A3 | **`composite` / `composite3` 的 enable 条件** | 无条件 `true` | 若某档不需要水状态则可整 pass 跳过 | 中。`composite` 供地形光照与焦散；`composite3` 是水合成。上一轮的 air-side `discard` 因依赖 Iris 未验证行为被回退——**改 enable 条件同样依赖引擎行为，需先验证** |
| A4 | **辅助缓冲降到固定小尺寸** | `colortex8` 已 294×1 | 其余（如 bloom 源、光束）已降采样，空间有限 | 低 |
| A5 | **便宜的阴影核** | 软件模式：每 lobe 1 次 `textureGather` + 最多 4 次 `texelFetch`，4 lobes | 已接近参考做法 | — |

### B 级：可落地但需实测与取舍

| # | 手法 | Astra 现状 | 预期收益 | 风险 |
|---|---|---|---|---|
| B1 | **积水 SSR 96 步分级** | `deferred.fsh:32` 固定 96 步 | 仅雨天有效水洼像素受益。参考 Miniature 10 步 + 4 次二分、FastPBR 4 采样 | 中。Astra 的 96 步是针对薄植被设计的；降步数会漏细物体反射。需按距离分级而非一刀切 |
| B2 | **平面云步数上限** | `clamp(...,6,64)` | 上一轮已做地形截断。上限本身可降 | 中。Astra 的"平面云"含命中点光照，与 Mellow 的 Flat 不同名不同物。降上限会改变薄边与低仰角表现 |
| B3 | **非同步阴影核宽归一** | 已有 `SHADOW_SOFTNESS` | 参考做法是按 `shadowMapResolution/1024` 归一，使分辨率档位改变时核的**世界宽度**不变 | 低 |
| B4 | **`pow` → 平方根链** | 部分已做 | 纯 ALU | 低 |

### C 级：需要架构决策（本轮不建议动）

| # | 手法 | 为什么是架构问题 |
|---|---|---|
| C1 | **TAA / 历史缓冲** | 这是所有降采样包的质量后盾，**也是解决 3.2 节所有高 tap 数的根本手段**。但用户明确禁止引入 TAA。若未来放开，Astra 的 5 张降采样缓冲才能真正发挥作用；不放开则只能用 tap 换质量 |
| C2 | **compute 合并**（FastPBR 手法：算+滤波同一 dispatch） | 需重排 pass 与 image 绑定 |
| C3 | **入口塌缩**（RenderPearl：40+ gbuffers → 3 个共享程序） | 省编译时间与维护面，**不省帧时间**。属于可读性投资 |
| C4 | **删 deferred 的第二附件** | 上一轮已核实：`colortex4` 存未施介质的原色，透明水要用，关闭 SSR 不代表消费者消失 |

### D 级：与 Astra 现状冲突，不采用

| 手法 | 冲突点 |
|---|---|
| 整条删掉阴影 pass（Potato / BuildersQoL） | Astra 主世界依赖方向性阴影；已有 `NO_SHADOWS` 档可覆盖弱机场景 |
| UV 缩放假装低分辨率（Sildur `texcoord*4.0`） | 会破坏 Astra 的 HDR 合成链与末端 bloom 半径 |
| 跨帧累积彩光（Mellow / SoftVoxelsLite / Bloop） | 与"不引入历史"约束冲突 |
| 顶点级全光照（ReShaded） | 与 Astra 的 PBR 材质、SSS、体素彩光不兼容 |

---

## 5. 建议的执行顺序

1. **A1 下界 9 compute → 分帧更新**。这是全包最大且最孤立的固定支出，且只影响下界，改坏了不影响主世界。
2. **A2 预计算常量盘点**。零风险，纯 ALU 收益，可分批。
3. **B1/B3 阴影与 SSR 分级**。需要先确认当前默认档的实际像素覆盖（雨天 vs 晴天差很多）。
4. **C1 TAA** 作为唯一能解锁剩余空间的架构决策，交由用户拍板；在它之前，C 级其他项收益有限。

**不建议**先做 C3（入口塌缩）——它省的是编译时间，不是帧时间，容易在"优化了"的错觉下消耗预算。

---

## 6. 本轮未做的事与限制

- **没有实机帧率数据**。本文所有收益都是源码级或解析式计数，不是 FPS 提升。
- **没有修改任何 shader**。本轮只做普查与评估，未落地改动；前一轮已落地的 4 项见
  [2026-09-25-low-end-optimization.md](2026-09-25-low-end-optimization.md)。
- 普查脚本不展开宏、不做数据流分析，**循环次数是源码字面量**，不是展开后的指令数。
- 各包默认档由源码 `#define` 与 `shaders.properties` profile 推断；若用户在实际游戏中改过选项，成本会不同。
- 参考包多为"保留所有权利"许可，本文只做数值与思路参考，不含任何代码移植。
