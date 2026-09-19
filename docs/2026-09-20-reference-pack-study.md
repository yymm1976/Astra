# 参考光影源码研究：Unbound r5.9.3 / Reimagined r5.9.3 / Steadfast 0.8.0（2026-09-20）

**性质**：只读研究。素材取自 `C:\Users\杨铭\Desktop\光影包`——**该目录为空**（`光影`、`MC模组开发/光影` 亦无相关内容；实例与 Downloads 均无更新版本）。因此沿用 09-16 性能研究的既定方法从 Modrinth 官方 API 取最新版：

| 包 | 最新版（Modrinth 实查） | 本地素材 |
|---|---|---|
| Complementary Reimagined | **r5.9.3（2026-09-15，即最新）** | 已有：`_analysis/performance-study-2026-09-16/complementary-reimagined` |
| Complementary Unbound | **r5.9.3（2026-09-15，即最新）** | **本轮下载**：`_analysis/study-2026-09-20/ComplementaryUnbound_r5.9.3/`（468 文件） |
| Steadfast | **0.8.0（即最新）** | 已有：`_analysis/Steadfast-0.8.0` |

**与既有研究的关系**：09-16 两份研究已覆盖性能成本链与视觉体验（Astra 也已吸收其大部分建议）。本报告聚焦**新角度**：以 09-20 修复后的 Astra 现状（光束重标定、水色行程、colortex 状态链、死链清理）为基线，只列**尚未吸收且可执行**的学习点。许可提示：Complementary 系为 License 1.7（专有）——以下全部按"思路级"处理，落地时重写，发布前过 design.md §9.3 闸门；Steadfast 部分沿用既有 GPLv3 台账规则。

---

## 1. Unbound r5.9.3：六个可直接借鉴的机制

### 1.1 【价值最高】无 TAA 的时域自适应体光采样（vlFactor）

`lib/atmospherics/volumetricLight/volumetricLight.glsl:9,183,321-346` + `program/composite1.glsl:16,339,343,379`：

- **机制**：一个标量 `vlFactor`（0..1）随帧演化——相机静止时每帧 `vlFactor = min(vlFactor + OSIEBCA, 1.0)` 爬升，运动时按 `reduceAmount` 更快回落（`:341-343`）；VL 的实际采样数由它驱动（`nearSamples`/`farSamples` 随之增减）。
- **持久化**：`composite1.vsh:379` 从 `colortex5` 的**最后一个像素** `.a` 读上一帧值（`texelFetch(colortex5, ivec2(viewWidth-1, viewHeight-1), 0).a`），fragment 再写回——正是 Astra colortex6（1×1 水体状态、`colortex6Clear=false`）同款"状态像素"技巧，机制已被 Astra 验证可用。
- **运行时循环上界**：`int totalSamples = (rayEnd <= qualityThreshold) ? nearSamples : (nearSamples + farSamples)`（`:176`）——**循环上界是运行时值**。可行前提是循环体内全部用 `texelFetch`/显式 LOD（`:201` 注释原话："We need to use texelFetch here or a lot of Nvidia GPUs can't get a valid value"）。
- **对 Astra 的意义**：水下光束 09-20 修复后量级已恢复，但采样数（7/10）是编译期常量——静止观赏时不足、移动时又白付。可引入 `astraVlFactor`（挂在现有 1×1 colortex6 的空闲通道或新增 1×1 缓冲）：静止爬升、运动回落，`UNDERWATER_SHAFT_SAMPLES` 变为该标量驱动的运行时上界（循环体已全部 `texture`/`textureLod` 显式采样，满足前提）。预期：静止时光束质量显著上升，平均成本不升。
- **成本**：一个 1×1 状态通道 + 循环上界改运行时；风险为 F-14 同类（非一致循环内采样），全显式 LOD 后即消除。

### 1.2 近/远双段采样：远场免阴影

`volumetricLight.glsl:183-250`：近段（`i <= nearSamples`）逐样本查阴影；远段（`else`）**完全不查阴影**，密度直接用 `eyeBrightnessM`（`:250` 附近）。远场本来就低频，阴影贡献趋于常数。Astra 的光束 7-10 样本全程查阴影 + 焦散——可把后半段样本改为免阴影（只保留均值照明），在相同样本数下把阴影预算集中在近段。

### 1.3 dimension.properties + `world0=*` 通配：按维度裁剪管线的正解

`dimension.properties`（`dimension.world0=*`）+ `shaders.properties:95-112`：

- world0 通配**所有模组维度**；`#if SHADOW_QUALITY == -1 → program.world0/shadow.enabled=false` 等写法按选项**整条禁用 pass**（分维度三行各写一遍）。
- 对 Astra 的两个直接价值：① 模组维度（SC-3 决定 v1 继承根层=主世界语义）至少可以关掉下界/末地专属 pass；② 09-13 §13.3 认为"properties 尺寸指令不能按维度收窄"（T7），而 Complementary 证明**按维度禁用/启用 pass** 是一等公民机制——colortex1 在下界/末地的闲置分配、deferred 条件化（汇总工单的"下一批"项）都有正解路径了。v1.1 候选。

### 1.4 昂贵 pass 的分辨率做成用户选项

`lib/common.glsl:240`：`#define REFLECTION_RES 0.5 //[1.0 0.5]`，`:120-121` 两张反射缓冲的尺寸都挂在这个用户选项上（且用 `#if defined IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE` 探测 Iris 版本后才声明）。Astra 的对应场景：光束 march（现 0.5）、colortex7（现 0.25）——把"反射/光束分辨率"暴露成 LOW/HIGH 选项，低配用户再多一档退路。

### 1.5 Unbound 自带完整 TAA（v2 候选，不影响 design 2.4）

`lib/antialiasing/taa.glsl`（251 行）+ `jitter.glsl`（8 点 Chocapic 抖动序列）+ `screen.TAA_SETTINGS`（含 TAA_SMOOTHING 2/3/4 三档混合参数预设、Catmull-Rom 历史采样、运动改善滤波）。定位：**可选开关**，默认档未见强制。Astra design 2.4"无 AA"是刻意决策——不建议现在翻案，但这是 2026 年一线包在无 TAA 观感瓶颈上的成熟答案，若 v2 引入体积云/彩光（时间累积类效果）时是现成参考。注意：其 VL 时域机制**不依赖 TAA**，可先行。

### 1.6 杂项

- **shadowcolor1 × 4.0**（`:221`）：染色阴影透射色在 VL 里乘 4 补偿能量——Astra 的 `caster.gba` 直接使用，水下光束若偏暗可试同款缩放（与 09-20 B4 重标定互补）。
- **每时段调色板滑块**（`shaders.properties:68`：LIGHT_NOON/MORNING/NIGHT/RAIN × RGB 等 100+ 滑块）：与 Astra"风格集中在 grading.glsl 单文件"的哲学相反。**不建议照搬**（违背 design 3.3 的少而精），仅记录为艺术管线对照。
- **GetSky 同样逐像素调用**（`mainFog.glsl`/`reflectionBackground.glsl` 都调）：说明 Astra 的雾/反射逐像素天空成本与一线包同级——汇总报告"天空 LUT"仍是对 Photon 的**超车项**而非补课项，优先级可保持中位。
- **`world0` + `dimension.properties` 还承载 buffer 尺寸差异化的可能**（尺寸指令放 world 壳内），T7 的彻底解法。

## 2. Reimagined vs Unbound（同为 r5.9.3）

同一骨架（`lib/` 共享 95%+）；Unbound 多出：TAA、`lib/voxelization`（屏幕空间方块光）、`unboundClouds`（204 行 3D 云）、SSR/反射缓冲链（colortex7/8 @ REFLECTION_RES）、`lib/textRendering`。Reimagined 即"关掉这些的清爽版"。对 Astra 的启示：**一个代码库承载两档产品形态**的能力来自它把"重特性"全部隔离成可关断的 pass + 缓冲，Astra 的 program.enabled 体系已具雏形，差距在缓冲尺寸/维度还没有跟随选项收放。

## 3. Steadfast 0.8.0：水体吸收的第三个分支（新角度）

`environment/water/absorption_refraction.glsl:22-120`：折射背景的水吸收按三分支取深度——

1. **顶面**：几何深度 `dot(viewPos−viewPosRefracted, upVector)`，`waterDepth = clamp(d/16 + 1/16, 0, 1)`——Astra 的 `clamp(depth+1, 0, 16)` 正是同一血统（09-20 已把上限放宽到 24 并加 in-scatter，已超越）。
2. **侧面/非竖直面**：几何深度不可靠，改用**背景天光作为深度代理**：`waterDepth = (−15/16)·skylight + 1`（单条 FMA）。**Astra 缺这个**：`water_sample_path` 用 `dot(origin−point, faceNormal)`，竖直水壁（瀑布/流水侧面）上该值≈0，几乎不吃吸收。借鉴点明确：非上向水面用背景 skylight 代理深度（colortex3 的 skylight 现成）。
3. **未命中几何（射线出水面/深水）**：不回退黑值——**假设满水深**（`waterDepth = 0.25 + 0.75·min(−z/24, 1)`）并按距离衰减背景。Astra 09-20 修复后该路径返回固定的水体色（24 格满深），但没有 Steadfast 的近场缓释：瀑布背后、浅水贴地平线处会偏浓。借鉴点：在未命中分支加同一近场缓释（24 格内按距离线性减浅）。

## 4. 对 Astra 的行动建议（按价值排序）

| # | 借鉴项 | 来源 | 落点 | 建议批次 |
|---|---|---|---|---|
| 1 | 光束时域自适应采样（vlFactor + 状态像素 + 运行时循环上界 + 全显式 LOD） | Unbound VL | light_shafts + colortex6 空闲通道/新 1×1 | v1.1，实机对拍 |
| 2 | 光束近/远双段：远段免阴影 | Unbound VL | light_shafts | v1.1，随 #1 |
| 3 | 水吸收侧面 skylight 代理 + 未命中近场缓释 | Steadfast | water_sample_path / astra_water_segment | v1.1，小改 |
| 4 | dimension.properties + world0 按维度禁 pass / 尺寸收放 | Unbound | 新增 world0 + dimension.properties | v1.1 决议（推翻/扩展 SC-3） |
| 5 | 反射/光束分辨率用户选项 | Unbound REFLECTION_RES | properties + 尺寸指令 | v1.1 |
| 6 | shadowcolor 染色 ×4 缩放试验 | Unbound | 光束颜色路径 | 随 #1 对拍 |
| 7 | TAA 完整参考实现 | Unbound taa.glsl | — | v2（design 2.4 闸门重议时） |

**不建议**：照搬 100+ 调色板滑块（违背 design 3.3）；现在引入 TAA（design 2.4 未重议）。

## 附：素材与许可

- 新增素材：`_analysis/study-2026-09-20/ComplementaryUnbound_r5.9.3/`（Modrinth CDN 直下，553KB，468 文件；`_analysis/` 不入库）。
- 许可口径不变：Complementary 系（Reimagined/Unbound）= License 1.7 专有，全部按**思路级**吸收，落地代码须自写并过 design §9.3 发布闸门；Steadfast 派生按 GPLv3 + §7 台账规则。
- `Desktop/光影包` 与 `Desktop/光影` 均为空目录；若用户后续放入新的包（如 EuphoriaPatches 或其他新包），可在此基础上续作。
