# 2026-09-29 实机反馈调研：水下过暗 / 光束不可见 / 下界反射与过红

针对第三轮修复后的实机反馈（水下黑过头、正午看不到光束、下界岩无火焰反射、火焰/岩浆被错误加强且过红刺眼）做的根因调研。**本文不含代码改动**；全部结论来自当前工作区源码与参考包对照，读取时点 2026-09-29 13:13（工作区未提交状态，行号会漂移，以符号名为准）。

- 参考源码：`SOLAS` = `_analysis/Solas Shader V2.2b/shaders`；`COMPL` = `_analysis/Complementary r5.9/Reimagined/shaders`；`ASTRA` = `Astra/shaders`。
- **硬约束（用户原话，记录在案）**：火焰/岩浆等发光体亮度被错误加强"是严令禁止的"——任何后续改动不得再提高发光体亮度；当前过红过亮需要回退而非补偿。
- 截图观察（用户提供的 4 张下界图）：火焰白芯过曝 + 巨大橙色 bloom 光晕；地面/岩壁无任何火焰镜像形状；地面矿斑亮白；整体强红饱和 + 橙红雾。

## 1. 水下黑过头

变暗项全清单（正午、主世界、眼在水中；**无双重变暗**——`scene.glsl:199-207` 相机支路原样返回，`fog.glsl:160-171` 水下分支是不可达死支路，吸收消光每条光学路径恰好一次）：

| 项 | 位置 | 正午量级 |
|---|---|---|
| 相机侧雾 | `water_composite.fsh:24` → `solas_water.glsl:83-99` | 32 格 fogAmount=0.85；雾色 ×(0.1+0.4·sun)=0.5 ×(0.5+0.5·eBS+glare 项)≈0.8 |
| 直射 ×焦散可见度 | `diffuse.glsl:353-387` | `sunWeight = visibility × (1-wetness·0.75) × ShadowFade`，direct 乘**未封顶**的焦散调制值——平水 shadowCol≈0.22 → sunWeight≈0.05，**地形直射近全灭** |
| shadow fallback 掐直射 | `diffuse.glsl:262` | 水下 fallback=0（Solas 同款） |
| 水面界面 | `water.glsl:135-165` | 从下看 opacity≥0.70 |
| 采样腿消光 | `water.glsl:96-117` | Beer-Lambert 各腿一次 |

与 Solas 的逐项对照结论：**公式、常数、存储/应用顺序已全部对齐 Solas 默认**（雾指数 -6、密度乘子 1.0、雾色 0.1+0.4sun、增益 4+8sun、VL_STRENGTH 1.75、SAMPLES 7；Solas 的 `lightColor.glsl` 全文无水下缩减，变暗由雾独扛）。"参考改错了"与"额外叠加"两个假设都不成立。剩下两个候选根因：

- **根因甲（可同时解释症状 2，优先检验）——运行时水面数据缺失**：`light_shafts.glsl:62` 的跳过门是 `shadow0 >= 0.999 → continue`（shadow0 采 shadowtex0）。若水面实际没有进入 shadow pass（block.10001 映射失效 / shadow.vsh 的 isWater 链断），则开阔水体样本 shadow0=1 全部跳过 → integral≡0 → 光束全灭；同一缺失使 `diffuse.glsl:364` 的 sunWeight 读到 shadowcolor0 空数据 → 地形直射近全灭 → **黑过头与光束全灭同根**。决定性检验：正午开 Iris 的 shadowtex0 调试视图看水面在不在；或对比"焦散亮纹是否存在于水底"（焦散也依赖同一数据）。
- **根因乙（数据正常时的量级本质）**：平水焦散 floor 使 shadowCol²≈0.05，正午 visibility 链 ≈0.03–0.2，光束仅占 sqrt 域 0.02–0.05，被 32 格 85% 的雾淹没——只有焦散波峰可见。Solas 在平静水面同样如此（其演示光束多在波浪海面）；这是参考行为的物理保守性，不是移植错误。

若实机检验排除甲，则"黑过头"的调参方向不是再加回自写项，而是：直射项采用 Solas `shadows.glsl:65-80` 的 `clamp(shadowCol·(1-shadow0)+shadow0, 0, 1)` 语义核对 Astra 是否少了这个 clamp；以及雾指数 -6 是否适合 Astra 的 UNDERWATER_FOG_DENSITY 档位映射（Solas 无独立密度选项，Astra 有，映射 40→1.0 需实机标定）。

## 2. 正午看不到光束

可见性链逐项与 Solas 一致（`light_shafts.glsl:51-75` vs SOLAS volumetricLight.glsl）：

- shadow0 采 **shadowtex0**（含水面）只作"完全照亮则跳过"的门，不乘入结果；shadow1 采 **shadowtex1**（不含水面）作可见度；图案 = `shadow1·pow2(shadowcolor0.GBA)`，clamp 8——与 Solas :113 水下分支逐字同构。
- 生产端确认水面进 shadow.vsh/fsh（isWater=mc_Entity.x==10001，GBA=solas_water_shadow）；BALANCED 档 WATER_CAUSTICS/UNDERWATER_LIGHT_SHAFTS 均开，STRENGTH=100。
- 正午标量门全部非零（sun=1.0、visibility≈0.03–0.2、增益 ×12）。

因此"正午完全看不到"的两个候选与症状 1 共享：**甲 = 水面数据缺失导致恒零（同上检验）**；**乙 = 平水 floor×visibility 的量级本质**。另有一个结构性差异值得注意：Astra 的 `visibility` 正午≈0.03–0.2 里，`(2-sun)·0.5=0.5` 与 Solas 一致，但 `VoU^1.5` 仰角项在平视时极小——Solas 同款，属参考行为。

## 3. 下界岩无火焰/岩浆反射

**核心事实：反射链本身是对的，是几何 + 门限使它在用户的测试视角下本来就近乎不可见——参考包在相同条件下同样接近零。**

数值推演（`nether_reflection.glsl` 当前权重 = `(fresnel·0.7+0.3)²·sqrt(smoothness)`，netherrack 纹理红通道 0.30–0.65 → colortex3.a≈0.14–0.63）：

| 视角 | fresnel | 混合比 | ×0.7 纹理保持后可见差 |
|---|---|---|---|
| 俯视地面 45° | 0.29 | 0.14 | **≈4%** |
| 俯视 60° | 0.50 | 0.23 | ≈7% |
| 正对岩壁 | ≈0 | 0.05 | ≈1.5%，不可见 |
| 掠射岩壁 | 0.80 | 0.41 | ≈12% |

- Complementary 参考在同样条件下代入其公式（deferred1.glsl:306-313）：45° 且 smoothness 0.3–0.5 时 **fresnelM=0，直接跳过 march**（composite.glsl:116 的 `if (abs(fresnelM-0.5)<0.5)` 门）——参考在俯视地面时反射就是 0~9%。
- 几何约束：水平地面物理上无法镜像水平的岩浆湖/地面火（镜像射线朝上，只能命中高于地面的火苗与岩浆壁）；岩浆湖面本身 material 10u → colortex3.a=0 → 被接收面门排除。
- 用户截图全部是俯视地面/近正对岩壁视角——恰好落在响应最低区。

结论与可选方向（供决策，非擅自偏离参考）：
1. **改测试姿势验证**：对岩壁侧面/掠射角看（这是参考反射真正出现的位置）；若侧面也没有，再查链路。
2. **补齐第二轮审查就指出的 bokeh**（§4 移植清单第 3 项，至今未做）：Complementary 的"火焰反光感"很大程度来自远处发光体 bokeh（岩浆湖在屏幕上糊成大亮斑 → march 命中大目标）+ bloom 响应——这是参考观感的组成部分，不是可选项。
3. 若上述之后仍要俯视地面可见反射，那是**有意超出参考**的画质决策：提高基础 fresnel 或改用 deferred1.glsl:309 的宽松分支 `(fresnel·0.7+0.3)`（无收紧）——需明示取舍并实机 A/B，不建议静默做。

## 4. 火焰/岩浆被错误加强 + 过红（硬约束项）

贡献分解（工作区当前值 vs HEAD，近岩浆暗岩红通道合计可达 HEAD 的 ~8–10 倍）：

| 项 | 位置 | 量级 |
|---|---|---|
| **sqrt 混光挪到 gamma 域**：`srgb_decode(srgb_encode(albedo)·sqrt(finalDiffuse))` | `nether.glsl:189`（本轮新改） | 近岩浆暗岩红通道 ×3.6（0.36→1.29 热边）——**最大单项** |
| **blocklight 曲线换 Complementary 版且无上限** | `nether.glsl:96-110` | level=1 红 4.4→**8.56**（×1.95），中间调反而变暗、峰值陡增 |
| **NETHER_EMISSIVE_BOOST 2.00 未回退** | `nether.glsl:34`（第二轮为救黑调从 1.35 提到 2.00，第三轮修好了黑调但没降回） | 发光面自亮 ×1.48，并把更多纹素推过 bloom 阈值 1.0 → 火焰大光晕 |
| 环境光平方放大红占比 | `nether.glsl:150-151,185` | wastes 红:绿从 2.9:1 → **7.8:1**——全维红罩感主源 |
| 朝下岩浆假反弹 | `nether.glsl:153-155` | 朝下面 +~0.2 红（中等） |
| minLighting 抑制删除 + AO +0.08 | `:157-158,180` | 各 <10% |
| 曝光 ×1.05 | `grading.glsl:77,124` | +5% |

关键判断：**第三轮把黑调修对的同时，第二轮为救黑调所做的临时补偿（boost 2.00）没有回退，两项叠加使发光体净亮度超过参考**；gamma 域乘法在 S>1 时对暗色 albedo 产生 Complementary 原版也有的热边，但 Complementary 另有 `maRecolor` 边缘暗化与 `albedo·0.84` 压制（lava.glsl:1,18），Astra 未移植这两项压制。

回退顺序建议（三项互相独立、均可单独回退，HEAD 可查）：
1. `NETHER_EMISSIVE_BOOST 2.00 → 1.35`（第二轮的临时补偿，黑调已修，补偿应撤）；
2. blocklight 曲线恢复 HEAD 的 `min(1.0)` 封顶形式，或至少恢复上限；
3. gamma 域乘法的热边：移植 Complementary 的 `maRecolor`/`albedo·0.84` 边缘压制，或把 sqrt 混光挪回线性域乘法后整体编码（报告 `2026-09-28-nether-underwater-borrow-study.md` §5 的原推导）。
以上均不新增亮度；"不得加强发光体"作为硬约束记录于总表。

## 5. 修复优先级建议（供修复负责人，本文不改代码）

1. **先做甲检验**（shadowtex0 调试视图 / 水底焦散有无）：若水面数据缺失，这是水下黑 + 光束灭的共同根因，修数据链优先于一切调参。
2. **下界回退三项**（第 4 节顺序，全部是减量，符合硬约束）。
3. **反射侧**：先改测试姿势对岩壁/掠射验证；然后补 bokeh（参考观感组成部分）；俯视地面可见反射属超出参考的画质决策，需明示取舍。
4. **水下**：若甲排除，按第 1 节末段的 clamp 语义与密度映射标定，不 reintroduce 自写衰减。
5. 全程遵守 `2026-09-28-nether-underwater-borrow-study.md` §6 红线与硬约束；每处回摆写明理由与 A/B 证据。

## 勘误（2026-09-29 晚，修复负责人复核时发现）

1. §1 表格"直射 ×焦散可见度"一行称"没有 clamp 到 1 的 LDR clamp"——不准确：透光在 `shadowmap.glsl:126` 已有 `clamp(caster.gba, 0, 1)`（每样本、可见度域）。水下地形直射并未承受 >1 的未封顶调制。
2. §4 回退建议中"移植 Complementary 的 maRecolor 边缘暗化"不成立：maRecolor 是**加色**补色项（gbuffers_terrain 加法用法），照搬会增亮而非压制。可用的压制是 lava.glsl:1 的 `color.rgb *= 0.84`（及火的 `sqrt1(luminance)` 纹理调制）。
3. §1/§2 的"根因甲（水面数据缺失）"已被运行时探针证实并修复（shadow.vsh 的法线门槛、block.properties 的 ISO-8859-1 截断——后者同时解释了下界岩材质表 09-22 起从未加载）。修复记录见 `2026-09-28-water-material-lighting.md` 的 2026-09-29 晚声明。
