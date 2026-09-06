# Astra 任务计划 — 高级Ⅱ（C 系）

> 梯度定位：**跨 pass 交互或需要设计判断的模块**。参考实现不完整、需与多模块耦合、或含观感调校——需要真正理解管线，产出会被顶级Ⅱ集成。
> 上位规格：[design.md](design.md)。升档路径：架构/管线问题直接报顶级Ⅱ（E 系）；模块级困难可请顶级Ⅰ（D 系）协助。

## 任务清单

| # | 里程碑 | 任务 | 内容 | 验收标准 | 依赖 | 状态 |
|---|---|---|---|---|---|---|
| C1 | M2 | 光照模块 | `diffuse.glsl`、`blocklight.glsl`（含日光压制）、`sss.glsl`（植被经验近似）、手持光、闪电点光 | 仿原版方向性环境光 + skylight 立方衰减；日光压制生效无跳变；洞底 minAmbient 正确；"清爽"观感基线成立 | E1、B1 | ✅（模块本体；lit 接线归 E1，实机验收待 SC-6） |
| C2 | M2 | 水下子模块 | **SC-24 重定向（2026-09-06，用户更正：水下对标 Solas）**：`absorption.glsl`/`refraction.glsl`/`caustics.glsl` 参考源由 Steadfast 换为 **Solas**（`_analysis/Solas Shader V2.2b/shaders/lib/water/` 的 waterFog / waterCaustics 等），观感重写为 Solas 水下；接口与签名冻结不变，E2 总成接线不动 | 水下 ≈ **Solas** 单项对标通过；焦散随阴影投射且随深度衰减 | E1、B1 | 🔶 SC-24 换源重写待执行（原 Steadfast 版本体 ✅，见完成记录） |
| C3 | M3 | 下界特调 | `dimension/nether.glsl`：无日光光照路径（环境光=方块光+熔岩辉光+红底）、熔岩辉光雾（随高度/深度）、独立大气与雾曲线、发光体/传送门增亮 | design.md §4.5 下界条目逐项达成；帧率同主世界标准 | E1、C1 | ✅（模块本体；`fogColor` 与维度覆盖壳归 E1（SC-18），实机验收待 SC-6） |
| C4 | M3 | 末地特调 | `dimension/end.glsl`：真空暗天空 + 稠密星野（缓慢旋转）、褪色环境光、void 雾渐变、微星云（默认开低强度） | §4.5 末地条目逐项达成；截图可独立辨识为"设计过" | E1、D2 | ✅（模块本体；维度覆盖壳归 E1（SC-18）、天空消费归 D2，实机验收待 SC-6） |
| C5 | M3 | Voxy 接入 | `voxy.json`、`voxy_opaque/translucent.glsl`、`lit_voxy.fsh`（`EXTERNALLY_DEFINED_UNIFORMS` 模式，参照 Mellow/Steadfast 现成实现） | Voxy LOD 地形光照/水面与主世界一致；不兼容则出实验特性说明 | E1、D1 | 🔶 SC-17已下放：E1接口已冻结；26.2/Voxy0.2.18-beta实例已找到，C5调用映射与D1实际加载待续 |
| C6 | M4 | 色彩与风格层 | `grading.glsl` 预设定稿（原 T5 下放）：tonemap 选型执行、出厂参数校准（对 Refrax 参考图迭代，起始 饱和 1.12/自然饱和 1.15/对比 1.04）、IGN 抖动配合 | 色调对标 Refrax（用户目视确认）；风格参数 100% 集中在 grading.glsl | M2 完成 | 🔶 SC-16已解决并接入final（单次sRGB后分级）；预设不重写，色调对标待运行素材与用户目视 |

| C7 | M2 | 水面与SSR（SC-15指令下放） | **SC-24 重定向（2026-09-06，用户更正：水面对标 Steadfast）**：surface.glsl 参考源由 Solas 换为 **Steadfast**（`_analysis/Steadfast-0.8.0/shaders/environment/water/`——解析导数程序波浪、Nyquist 比率受限、4 步自适应视差），观感重写为 Steadfast 水面；raytrace.glsl（SSR 基础设施）不动；接口与签名冻结不变 | 水面 ≈ **Steadfast** 单项对标通过；接口符合 design §4.3；E2 集成后另作实机视觉裁决 | E1 | 🔶 SC-24 换源重写待执行（surface 原版 ✅；raytrace 不动） |

## 协作规则

- 接口纪律与 B 系相同：只走 E1 冻结的 varyings/uniforms/缓冲，禁止私开。
- C2 按设计文档 §4.3 规格独立成模块，与水面的总成集成由 E2 负责——不越界做集成。
- C6 只调参数与预设；需要动管线/插入点（如换 tonemap 位置）属架构问题，报 E 系裁决。
- 验收双闸门：任务表标准 + Z7 回归清单；视觉类以参考截图对比为准。
- 卡住两轮无进展：带证据上报；架构变更请求写清"现状/问题/建议决议"三段，报 E 系。
- 上报与接手：按 [escalations.md](escalations.md) 流程执行（登记→认领→结论下放→闭环）；上报中的任务状态标 🔶。

## 完成记录（每任务一行）

> 共同边界（与 tasks-advanced-1.md B 系同）：E1 未冻结（tasks-top-2.md 仍 ⬜），本批**只写模块主体**，
> `program/lit.*`、`program/final.*`、`gbuffers_*` 包装、维度壳一律未动；接口契约（参数、调用时机、
> 消费者、未冻结项）写在各模块文件头。判 ✅ 的依据是"照 design.md §4 规格实现 + 静态校验不劣化
> （`check_pack.py` 现为 1 FAIL / 1 WARN / 9 PASS，唯一 FAIL 是 E1 的 #10 最小 final 链）+ 出处台账落档"；
> 实机与视觉判据零证据，全部留给 SC-6 解除后的 Z7/D1 环节。

- **C1 ✅**：`global/lighting/diffuse.glsl`（197 行：`ambient_strength()` 方向性环境光、
  `ambient_sky_lighting()` skylight 立方衰减、`direct_lighting()`、`diffuse_lighting()` 总成）
  + `blocklight.glsl`（133 行：`block_lighting()` 含日光压制、`held_light_strength()` 手持光衰减、
  `lightning_point_light()` 闪电点光）+ `sss.glsl`（60 行：`sss_wrap()` 植被经验近似 + `SSS_STRENGTH`
  滑条化）。日光压制"生效无跳变"与洞底 minAmbient 为静态推演结论，实机未证。
- **C2 ✅**：`global/water/absorption.glsl`（56 行，exp 深度模型 + 三档 `WATER_CHARACTER`）、
  `refraction.glsl`（112 行，单跳 + `textureGather` 边界拒绝 + 外 10% 混回背景）、
  `caustics.glsl`（328 行，`CAUSTICS[6]` crest 表 + `water_caustics()` 经 B1 的 shadowcolor0 高度解码反推水深）。
  按 §4.3 与"不越界做集成"的指令，`surface.glsl`/`raytrace.glsl` 两个 Z1 空壳**未动**——它们的归属缺口已登记为 SC-15。
  **SC-24 更正（2026-09-06）**：用户澄清水下对标应为 Solas（原表述记反），C2 三个模块换源重写为 Solas 观感，状态回 🔶。
- **C3 ✅**：`global/dimension/nether.glsl`（481 行：`nether_lighting()` 无日光路径=方块光+熔岩辉光+红底、
  `nether_fog()` 熔岩辉光雾随高度/深度、`NetherParams` struct 传值避开冻结的 uniform 集、发光体/传送门增亮）。
  唯一需要 E1 供给的输入是 `uniform vec3 fogColor`，已在文件头标 ⚠ REQUIRED FROM E1。
- **C4 ✅**：`global/dimension/end.glsl`（778 行：`end_sky()` 真空暗天空 + `end_star_field()` 双层稠密星野、
  绕倾斜极**刚性旋转**（3D 晶格随视向旋转，非参考包的投影 2D 平移）、`end_nebula()` 微星云（默认开、4 次查表、
  比 Solas 的 9 次降配）、`end_fog()` 黑紫随深度 void 雾、`end_block_lighting()` 褪色环境光、
  `end_emissive_boost()` 含沿 Y 行进的光柱辉光）。§5 的抖动优先"查表"在本模块有一处记录在案的偏离：
  星野是稀疏点过程，256² 双线性表无法表达，仅该项用整数 hash，星云仍走 noisetex。
- **C5 🔶**：未实施，登记为 SC-17（前置三项全缺：E1 冻结、D1 的 26.x Voxy 冒烟、SC-6 实机环境；
  `check_pack.py` 无任何 Voxy 静态检查项，写出的映射层零可验证性）。C3 的 `nether_fog()` 已预留
  `borderFragDistance` 形参，接线时可直接复用。
- **C6 🔶**：`global/post/grading.glsl`（216 行）出厂参数与四套预设已交付——`apply_exposure()`、
  `apply_color_temperature()`、`apply_grading()`（vibrance 先于 saturation 再 contrast，链序照 Mellow）、
  `apply_vignette()`、`apply_output_dither()`（IGN，§5 要求）+ `grading_dimension_exposure()` 按维度补偿。
  未闭环的两点：① 插入点随 SC-16（四算子输出空间不一致，任何单一插入点都对部分算子错误，须 E1 裁决）；
  ② 验收标准本身写"用户目视确认"，且实机截图受 SC-6 阻塞。**本批不自行改管线。**
