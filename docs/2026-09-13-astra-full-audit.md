# Astra 全量审查报告

> **2026-09-13 核对与修复补充：请先看 §13。** 原报告保留为审查记录；其中全局初始化器、实体距离算式、性能安全结论等有误判或证据不足，不能直接作为当前事实。

**日期**：2026-09-13　**版本**：`7e3b1e7` + 27 项未提交改动
**性质**：只读审查。**本次未修改任何代码**，仅新增本文件。
**方法**：仓库静态分析 + 三套校验器实跑 + 全树模式扫描 + 文档与台账核对。
**未做的事**：没有游戏内验证，因此**所有画面结论都不在本文范围内**。

---

## 0. 总体结论

| 维度 | 评级 | 说明 |
|---|---|---|
| 构建健康度 | **良好** | `267 linked / 0 failed / 27 compute`；`check_pack` **0 FAIL / 1 WARN / 10 PASS** |
| 架构纪律 | **良好** | 分层清晰、入口薄壳、选项注册表单一来源，且有校验器双向约束 |
| 完成度 | **中上** | 主世界日循环完整；缺口集中在后处理套件与 Voxy |
| 性能 | **中** | 已知最大项已有等价替代；**没有已知可安全落地的剩余项** |
| 出处合规 | **良好** | 台账与文件头一致，资产边界有明文规则并有校验器把关 |
| **风险护栏** | **不足** | **没有"每像素代价"的自动化护栏**——这是本次审查发现的最重要缺口 |

**一句话判断**：这是一个**工程纪律明显高于同类个人项目**的光影包——它有 11 项静态校验、18 个离线工具、
单一来源的选项注册表、逐条登记的出处台账。但它有一个**结构性盲区**：
所有护栏都只验证"**能不能编译/契约对不对**"，没有任何一项验证"**跑不跑得完**"。
末地那次 GPU 挂起能从全部 11 项校验里穿过去，根因就在这里，而不在某个人的疏忽。

---

## 1. 项目规模

| 项 | 数量 |
|---|---|
| 着色器源文件 | **245**（`.glsl` 53 / `.fsh` 96 / `.vsh` 86 / `.csh` 10） |
| 着色器总行数 | **8,493** |
| 用户选项 | **63**（布尔 23 / 滑块与枚举 40） |
| 画质档位 | 3（PERFORMANCE / BALANCED / ULTRA） |
| 设置界面分类 | 8（主屏 + LIGHTING / SHADOWS / SKY / WATER / FOG / POST / PERFORMANCE） |
| pass 级门控 | **24** 条 `program.*.enabled` |
| 离线工具 | **18** 个 Python 脚本 |
| 文档 | **34** 份 |

### 目录分层

```
shaders/
  <root>/            28 fsh   主世界 + gbuffers 入口（薄壳）
  world-1/           25 fsh   下界（+ 9 csh 体素光 compute）
  world1/            27 fsh   末地
  program/           共享实现（lit / deferred / final / composite / end_* 等）
  global/            按域分模块
    atmosphere/  clouds_planar, fog, sky_gradient, sky_minishita, stars, weather
    dimension/   overworld, nether(+colored_light,+volume), end(+geometry,+ring,+system,+blackhole)
    lighting/    blocklight, diffuse, shadowmap, sss, wind
    post/        bloom, godrays, grading
    water/       absorption, bloom_capture/resolve, caustics, light_shafts, medium_state,
                 optics, particles, raytrace, reference_light, refraction, surface
  lib/               声明层（settings / uniforms / transforms / encoding / noise …）
```

**评价**：`program/` 只做编排、`global/` 只做实现、`lib/` 只做声明——三层职责清晰，
且 `check_pack #4` 会强制"无悬挂 include、每个入口可达 settings、无未注册模块、无跨层引用"。
这是**本次审查里最扎实的一项**。

---

## 2. 构建与验证现状（实跑结果）

| 校验器 | 结果 |
|---|---|
| `compile_glsl.py`（真实 GPU 编译全部入口） | **267 linked / 0 failed / 27 compute / compute_capable=true** |
| `compile_glsl.py --undef NETHER_VOXEL_LIGHT --no-compute`（回退路径） | 通过 |
| `check_pack.py` | **0 FAIL / 1 WARN / 10 PASS** |
| `nether_voxel_model.py` | 5/5 不变量通过 |
| `shadow_filter_equiv.py` | `max_abs 9.4e-16`，等价性成立 |

### `check_pack` 的 11 项与一项 WARN

| # | 检查 | 结果 |
|---|---|---|
| 1 | settings.glsl 选项注册表（60–80 项） | PASS（63 项） |
| 2 | `shaders.properties` 的 screen/sliders/profile ↔ settings 双向一致 | PASS |
| 3 | lang 文件覆盖每个选项的标题与注释 | PASS |
| 4 | include 图分层 | **WARN** |
| 5 | lib/global 引用的引擎/原版符号必须在声明层 | PASS |
| 6 | custom uniform：properties ↔ GLSL 声明 | PASS |
| 7 | block/entity.properties 语法与 ID 合理性 | PASS |
| 8 | THIRD-PARTY 台账 ↔ 文件头 ↔ 授权规则 | PASS |
| 9 | bayer.glsl 有序抖动矩阵正确性 | PASS |
| 10 | 最小 final 链（tonemap + sRGB）存在 | PASS |
| 11 | Iris 1.11.2 解析器契约（SC-21..SC-27） | PASS |

**唯一 WARN**：`voxy_opaque.glsl` / `voxy_translucent.glsl` 等待 C5 接线。
**这是已知且有主的缺口，不是缺陷。**

---

## 3. 完成度矩阵

### 3.1 维度

| 维度 | 状态 | 说明 |
|---|---|---|
| 主世界 | **完整** | 日循环、天气、水体、体积光、后处理齐全 |
| 下界 | **完整** | 体积光 + 体素彩色光（compute + 自定义图像）+ 独立雾 |
| 末地 | **完整** | 环系（A/B 环 + 卡西尼/恩克缝）、73 天体、牧羊天体、岛群、黑洞测地线、两段式天空 |

### 3.2 日循环（用户最关心的部分之一）

| 项 | 状态 | 证据 |
|---|---|---|
| 正午 / 日落 / 夜晚三套调色板 | **有** | `sky_gradient.glsl` 的 noon/sunset/night 三段与天气调制 |
| 日出 / 月出地平线辉光 | **有** | `sunrise` / `moonrise` uniform 驱动雾与天空 |
| 星空（含白天淡出） | **有** | Complementary 规范移植，`invNoonFactor2` 控制淡出 |
| 太阳 / 月亮样式 | **有** | `SUN_MOON_MODE`：原版贴图 / 程序圆盘 |
| **月亮相位** | **有** | `astra_procedural_moon()`，含朔望分侧与新月亮度下限 |
| 雷电（点光 + 天空闪光） | **有** | `lightning_point_light` + `astra_lightning_sky_flash` |
| 昼夜过渡 | **有** | `sunProgress` / `moonProgress` 连续驱动 |

**结论：主世界日循环在完成度上没有已知缺口。**

### 3.3 效果覆盖与缺口

| 类别 | 有 | 缺 |
|---|---|---|
| 光照 | 太阳/月亮/天空/方块光、阴影（含彩色）、SSS、手持光、闪电 | — |
| 水体 | 波动、折射、反射、焦散、吸收、水下光束、颗粒、涟漪 | — |
| 大气 | 平面云、雾（含边界/洞穴/水下/下界/末地）、参考大气散射 | **体积云**（`CLOUD_MODE` 只有 原版/平面/关闭） |
| 后处理 | bloom（两级 mip）、godrays、tonemap、分级、抖动 | **DoF、运动模糊、镜头光晕、色差、锐化** |
| 抗锯齿 | — | TAA（**设计前提，刻意不做**）、SMAA |
| 集成 | — | **Distant Horizons**、**Voxy**（C5 未完成） |
| 状态效果 | — | 夜视 / 失明 / 受伤闪红的自定义处理（原版可顶） |

**判断**：缺口集中在**"镜头感"套件（DoF/光晕/色差）与 LOD 集成**。
前者按 Mellow 的判据属"小面积高频"，砍掉不影响观感；后者是工程量问题。**两者都不构成质量缺陷。**

---

## 4. 正确性与风险

### 4.1 【最高风险类】每像素代价——没有护栏

末地那次 GPU 挂起（黑洞步进每像素 512 次场景求交）**穿过了全部 11 项校验**。
这不是偶然：**现有校验体系里没有任何一项估计计算量**。

我对全树做了模式扫描（所有 `bound >= 32` 的数值循环 + 所有常量上界循环），共 16 处：

| 位置 | 上界 | 是否每像素 | 评估 |
|---|---|---|---|
| `program/end_illumination.fsh:35` | **256** | 否，**294×1 数据缓冲** | 294×256 = 7.5万次总量，**可忽略** |
| `program/deferred.fsh:32` | **96** | 是，但**仅积水像素**（`surface.a > 0.001`） | 可接受；但 96 步高于参考的 24–32，**是性能余量** |
| `global/dimension/end_geometry.glsl:175` | **96** | 是，但受**跨步约束**（每 4 步一次） | 已受控 |
| `end_blackhole.glsll:111` | `END_MARCH_STEPS`=48 | 是 | 已修复（原 256） |
| `end_geometry.glsl:199/225`、`end_system.glsl:55`、`end_blackhole.glsl:71/92/161` | `END_BODY_COUNT`=73 | 部分 | 受候选过滤约束 |
| `diffuse.glsl:191/211` | `SHADOW_FILTER_TAPS` | 是 | 4 或 16，受选项控制 |
| `nether_volume.glsl:93` | `SAMPLECOUNT`=16 | 是 | 有 transmittance 早退 |
| `light_shafts.glsl:70` | 7 或 10 | 是 | 有距离与屏幕早退 |
| `particles.glsl:127` | `PARTICLE_SHELLS` | 是 | 默认关闭 |

**结论：当前全树没有第二处"必挂"级热点。** 但**发现它们靠的是人肉扫描，不是护栏**——
下一次照样会漏。这是本文最重要的一条建议（见 §7）。

### 4.2 未完成的接口

| 项 | 状态 | 影响 |
|---|---|---|
| Voxy（C5） | `voxy_opaque.glsl` / `voxy_translucent.glsl` 已存在但未接线 | `check_pack` 的唯一 WARN；功能未生效 |

### 4.3 与设计书的偏离（已记录，非缺陷）

`docs/2026-09-11-end-final-design.md` 开头的用户口径变更已明示：
不再硬性要求"每周期仅一次环食、持续 40–70 秒"与"10 秒完全不可察觉"，
改为由真实空间交会决定次数与时长。**该偏离已写入文档，属受控变更。**

另有一处**设计书自身的错误**已在实现中被正确处理：原文要求"阴影内部不是纯黑、
应看到被透镜压缩的星场"——该要求物理上不成立（阴影内正是光线被视界捕获的区域），
正确表述是"紧邻光子环外侧的星场被强烈压缩"。**实现比设计书更正确。**

### 4.4 编译器警告

`compile_glsl.py` 报告 **0 错误、0 警告**（此前的 `ringP` 未初始化警告已在四处修复后消除）。

---

## 5. 性能状况

### 5.1 结构

| 项 | 值 |
|---|---|
| 全屏 pass | 根 `composite`/`composite1`/`composite2`/`composite3`/`composite4`/`deferred`/`final` |
| 降分辨率缓冲 | `colortex1` 0.5（或全分辨率，水下光束开启时）、`colortex2` **0.25**、`colortex9` 0.75、`colortex6/8` 各 1×1 |
| 缓冲格式 | **Iris 默认即 `RGBA`（8 位）**——已核实，故无下探空间；`colortex0/4` = `R11F_G11F_B10F`、`colortex7/8/9` = 16/32 位 |

### 5.2 已落地的优化

| 项 | 效果 |
|---|---|
| 泛光捕获 0.5 → 0.25 | fragment 数 **1/4**；抽头按 `footprint` 自动放大、mip 读取下移一层，**足迹与加权平均完全不变** |
| 背光面跳过阴影采样 | SSS/玻璃除外（它们背光仍有亮度）；判据与 `direct_lighting` 严格等价 |
| `SHADOW_FILTER_MODE=1`（可选） | 受影像素取样 **48 → 8 次**；数值等价至 **1e-15**；**默认仍走软件路径** |
| 末地黑洞步进 | 每像素场景求交 **512 → 12 次** |
| 末地天空两段式 | 昂贵几何跑 0.75 分辨率，星星全分辨率合成 |
| 末地天体数据烘焙 | 73 天体 + 环轴 + 73 朝向基烘进 294×1 RGBA32F，天空改查表 |
| 下界体积 transmittance 早退 | 稠密羽流提前退出 |

### 5.3 已知余量（**无一项可安全落地**）

| 项 | 为何不动 |
|---|---|
| 阴影软件路径的 16 抽头 | 已有 `SHADOW_FILTER_MODE=1` 等价替代，等实机确认 |
| `deferred.fsh` 的 96 步屏幕步进 | 仅在积水像素触发；降低步数会改变积水反射精度，需实机对拍 |
| 泛光捕获是 8 位 → 亮部能量被裁 | 属**质量**问题；修法是声明 `R11F_G11F_B10F`，但 `settings.glsl:244-247` 有一条与其矛盾的注释（称本次构建拒绝生效的格式声明，而 `water_buffer_formats.glsl` 的声明**确实生效**）。**需要实机答案** |
| 噪声（仅剩星场与末地两处 hash） | 占屏比小 |

**判断：Astra 目前已没有"已知且可安全落地"的性能项。** 继续优化应先补护栏，否则仍是靠猜。

---

## 6. 出处与授权

| 项 | 状态 |
|---|---|
| 台账计数 | `verbatim=14 / literal-suffix=3 / rewritten=7 / astra-only=22`（共 46 条） |
| 台账 ↔ 文件头一致性 | `check_pack #8` **PASS**（双向核对） |
| **资产边界** | 明文化：**代码级移植按专有处理并登记；图像等美术资产一律不得取用** |
| 违规历史 | 曾误引入参考的涟漪贴图，已全部删除并改为 `qa/tools/gen_rain_ripple.py` 自行生成 |
| 发布闸门 | 依 `design.md` 9.3：专有来源的条目发布前必须重写或取得授权 |

**评价**：这是我认为**最值得保留**的一套实践。
它把"哪些是抄的、哪些是自己的、发布前必须处理什么"变成了可被校验器检查的机器可读事实，
而不是靠记忆。`check_pack #8` 会同时核对台账、文件头与授权规则三方。

---

## 7. 工具链与验证体系（本文核心）

### 7.1 现有 18 个工具

编译类：`compile_glsl.py`（真实 GPU 编译，含 `--set` / `--undef` / `--no-compute` 变体）
校验类：`check_pack.py`（11 项）、`inspect_iris_properties.py`
模型类：`nether_voxel_model.py`、`shadow_filter_equiv.py`
探针类：`shadow_frustum_probe.py`、`validate_shadow_water.py`、`water_path_probe.py`、
`water_stability.py`、`sc35_probe.py`、`p01_sky_diagnosis.py`、`review_20260911_numerics.py`
生成类：`gen_rain_ripple.py`、`render_end_design.py`
台账类：`provenance_steadfast.py`、`sync_to_instance.py`
成本类：`cost_census.py`

### 7.2 覆盖边界（**关键**）

| 问题 | 有护栏吗 | 由谁覆盖 |
|---|---|---|
| 能不能编译？ | **有** | `compile_glsl.py`（真实 GPU，含全部选项变体） |
| 契约/注册表/分层自洽吗？ | **有** | `check_pack.py` 11 项 |
| 出处登记完整吗？ | **有** | `check_pack #8` + `provenance_steadfast.py` |
| 数值等价吗？ | **部分** | `shadow_filter_equiv.py`（单点）、各 probe |
| **跑得完吗？** | **没有** | ← **空白** |
| 画面对吗？ | **没有** | 只能实机，属已知边界 |

### 7.3 建议（按优先级）

1. **给 `cost_census.py` 补两个盲点**，然后把它接进 `check_pack` 作为第 12 项。
   现状的两个盲点已在工具输出里声明：
   - **分支/早退不可见**（会把只在积水像素跑的 96 步算成全区代价）
   - **循环调用取样函数时不相乘**（这正是末地那次被漏掉的原因——16 次抽头 × 被调函数内部的取样没有被相乘）
   补完后它可以对"每像素迭代数超过阈值"的改动**报警**，这是唯一能拦住同类崩溃的机制。
2. **给 `end_scene_segment` 这类重函数加"代价注释"约定**（Steadfast 的做法：
   `// Cost: 11 FLOPs (4x fma, 4x mul, 1x div, 1x pow, 1x sub)`）。
   本次修复已在 `END_MARCH_STEPS` / `END_GEOMETRY_STRIDE` 旁写了代价说明，应推广为约定。
3. 把"新增/修改循环必须报告上界"写进任务模板。

---

## 8. 文档状态

34 份文档，主线清晰：`design.md` 为规范、`docs/handoffs/` 为任务交接、
`docs/parallel-development/` 为并行边界、`docs/*.md` 为逐轮记录
（`2026-09-06` 起共 30 轮），另有 `qa/session-log.md` 按轮次存档。

**优点**：每轮都留了"做了什么、为什么、证据在哪、未做什么"。
**可改进**：`docs/` 根目录已累积 34 份平铺文件，按日期命名使得**按主题检索困难**——
建议按 `docs/rounds/`、`docs/reviews/`、`docs/design/` 归档，但这属整理，不影响正确性。

---

## 9. 风险登记表

| # | 风险 | 等级 | 现状 | 缓解 |
|---|---|---|---|---|
| R1 | **新增/修改的逐像素重循环无护栏，可能再次造成 GPU 挂起** | **高** | 无自动化检查 | 补 `cost_census` 盲点并接入 `check_pack` |
| R2 | 泛光捕获 8 位导致亮部泛光能量被裁 | 中 | 未修，且存在矛盾注释 | 需实机确认格式声明是否被接受 |
| R3 | `SHADOW_FILTER_MODE=1` 未经实机验证 | 中 | 默认关闭即安全 | 实机对比后启用 |
| R4 | Voxy 未接线 | 中 | C5 未完成 | 属工程量 |
| R5 | `deferred.fsh` 96 步屏幕步进的性能余量 | 低 | 已受积水门控 | 实机对拍后可降 |
| R6 | `settings.glsl:244-247` 的注释与 `water_buffer_formats.glsl` 的实际行为矛盾 | 低 | 已识别 | 应据实修正注释（不改行为） |
| R7 | 大量未提交改动（27 项） | 低 | 已存在于工作区 | 应尽快提交或明确丢弃 |

---

## 10. 建议（按优先级）

1. **补 `cost_census.py` 的两个盲点并接入 `check_pack`**——这是本文唯一的高优先级建议，
   因为 R1 是唯一可能"再次让游戏崩掉"的风险，而其余风险最坏也只是画面或性能。
2. **实机验证一批**：末地（崩溃修复后）、雨滴、月亮相位、雷电、泛光分辨率、`SHADOW_FILTER_MODE=1`。
   当前积压的待验证项较多，继续叠加改动会让归因变难。
3. **修正 `settings.glsl:244-247` 的注释**，使其与 `water_buffer_formats.glsl` 的实际行为一致（只改注释）。
4. **提交或丢弃那 27 项未提交改动**，恢复可回滚状态。
5. 整理 `docs/` 目录结构（可选）。

---

## 附：本次审查未覆盖的内容

- **游戏内画面正确性**：全部未覆盖（无实机）。
- **帧率实测**：只有静态启发式排序，**没有任何计时数据**。
- **Iris 之外的环境**：未评估 OptiFine 兼容性（本包依赖 Iris custom uniforms）。
- **多人/服务器场景**：未评估。
- **驱动兼容性**：只在 RTX 4050 + NVIDIA 572.83 上编译验证过。

---
---

# 11. 第二轮：代码级审查（2026-09-13 追加）

**性质**：只读。**同样未修改任何代码**，仅在本文件末尾追加本节。
**与 §0–§10 的分工**：前 10 节是元层面（结构、工具链、台账、性能启发式）；本节下沉到 GLSL 源码本身，逐项给出文件与行号。
**方法**：全树静态扫描（选项引用图 / uniform 契约 / include 解析 / 符号冲突 / 数值 hazard）+ 关键模块人工审读 + 外部事实核查。

## 11.1 新发现清单

| # | 问题 | 等级 | 位置 |
|---|---|---|---|
| **N1** | **`ENTITY_SHADOW_DISTANCE` 是"假控件"**：GUI 可调、三档预设各不相同，但没有任何 GLSL 消费它；实际行为是硬编码 `0.5`，且注释里的算式与任何预设都对不上 | **P2** | `lib/settings.glsl:65,223-230` |
| **N2** | **全局非常量初始化器 5 处**：违反 GLSL 对全局初始化器的常量表达式要求，属跨驱动可移植性风险 | **P2** | `global/water/bloom_resolve.glsl:2-3`、`bloom_capture.glsl:2-4` |
| **N3** | `#if 2 == 0` 硬编码恒假分支，无法通过任何选项打开 | P3 | `global/water/bloom_resolve.glsl:30` |
| **N4** | 两个从未定义的宏 + **一个不存在的函数**被留在条件里（Bliss 移植残留），一旦宏被定义即编译失败 | P3 | `global/dimension/nether_volume.glsl:89,146-147` |
| **N5** | 入口壳三维度手工复制（40 个 gbuffers 壳 × 3 维度 = 120 文件），改动需同步 3 处且漏改不报错 | P3 | `gbuffers_*` × `world-1/` `world1/` |
| **N6** | `apply_vibrance` 权重可 >1 导致 `mix` 外插；默认值 100 时该函数**完全空转** | P3 | `lib/tonemap.glsl:199-206` |
| **N7** | 闪电天光路径的 `normalize()` 无 epsilon 防御，与同文件点光路径的防御不一致 | P3 | `global/lighting/blocklight.glsl:130` vs `:149` |
| **N8** | 6 个枚举 token 常量从未被引用，调用点靠 `#else` 兜底 | P3 | `lib/settings.glsl:16-31` |
| **N9** | 在非统一控制流分支内取 `dFdx/dFdy`，末地星点大小会在物体边缘跳变 | P3 | `program/deferred.fsh:118` |

---

## 11.2 N1（P2）`ENTITY_SHADOW_DISTANCE` 是一个不生效的用户控件

**证据链**：

- 声明：`lib/settings.glsl:65` `#define ENTITY_SHADOW_DISTANCE 64 // [32 48 64 96 128]`
- 唯一"消费"：`lib/settings.glsl:230` `const float entityShadowDistanceMul = 0.5;` —— **这是硬编码字面量，与选项值无关**
- 全树引用统计：`ENTITY_SHADOW_DISTANCE` 在 `shaders/` 下只出现在 `screen.SHADOWS`（`:150`）、三个 profile（`:161/162/163`）、`sliders`（`:168`）和两份 lang（`:21/:86`）里 —— **没有任何 GLSL 读它**
- 语义核对：`entityShadowDistanceMul` 是 Iris 的真实 const，Complementary r5.9 的用法可证（`program/shadow.glsl:74`：`float fadeEnd = shadowDistance * entityShadowDistanceMul + 2.0;`），即**实际距离 = `SHADOW_DISTANCE` × 0.5**

**实际值 vs 界面显示值**：

| 档位 | `SHADOW_DISTANCE` | 界面显示 | 实际（×0.5） | 偏差 |
|---|---|---|---|---|
| PERFORMANCE | 192 | 48 | **96** | 2.0× |
| BALANCED | 256 | 64 | **128** | 2.0× |
| ULTRA | 256 | 96 | **128** | 1.33× |

**注释也是错的**：`lib/settings.glsl:224-228` 写"All three profiles resolve to 0.5 (48/96, 64/128, 96/192)"。
三档真实比值是 48/192=0.25、64/256=0.25、96/256=0.375，**没有一个是 0.5**；且 ULTRA 的 `SHADOW_DISTANCE` 是 256 不是 192，第三对应为 96/128。

**为什么 `check_pack` 没抓到**：第 2 项校验的是"`shaders.properties` ↔ `settings.glsl` 双向一致"，而这个选项两边确实一致。它不校验"声明的选项是否真的被消费"。

**建议**：
1. 给 `check_pack` 加第 12 项：**任何出现在 `screen.*` / `sliders` / `profile.*` 中的选项，必须在 `lib/settings.glsl` 之外被至少一处 `#ifdef`/`#if`/表达式引用**。这条能一次性挡住整类"假控件"。
2. 二选一：让 `entityShadowDistanceMul` 随选项走（需要预计算字面量，见 SC-23 的解析器限制），或把该选项从 GUI/profile 里摘掉、只保留注释说明实体阴影距离固定为主阴影距离的一半。**不要维持现状**——一个能拖但没反应的滑块比没有滑块更糟。

---

## 11.3 N2（P2）全局非常量初始化器

```
global/water/bloom_resolve.glsl:2   float pixelWidth  = 1.0 / viewWidth;
global/water/bloom_resolve.glsl:3   float pixelHeight = 1.0 / viewHeight;
global/water/bloom_capture.glsl:2   float pixelHeight = 0.8 / min(360.0, viewHeight);
global/water/bloom_capture.glsl:3   float pixelWidth  = pixelHeight / (viewWidth / viewHeight);
global/water/bloom_capture.glsl:4   vec2  viewSize    = vec2(1.0 / viewWidth, 1.0 / viewHeight);
```

`viewWidth` / `viewHeight` 是 uniform，不是常量表达式。GLSL 规范要求全局变量的初始化器为常量表达式；当前在已验证的 RTX 4050 / NVIDIA 572.83 上通过，说明该驱动放宽了这条约束。

**风险**：这是**唯一一处"编译通过"依赖驱动宽容度**的地方。AMD / Intel / Mesa 上可能直接编译失败，而 §2 的 267 项编译验证覆盖不到。

**建议**：全部改为函数内局部变量，或在调用点现算。改动是纯机械的，无行为差异。

---

## 11.4 N3 / N4（P3）三处移植残留的死代码

**N3 — `global/water/bloom_resolve.glsl:30`**

```glsl
#if 2 == 0
    color = mix(color, blur, 0.25 * bloomStrength);   // 永远不可达
#else
    ...
#endif
```

`2 == 0` 是常量恒假（Solas 原作此处应是一个真实条件）。第 31 行无法通过任何选项打开。要么删掉，要么换回真实条件——留着会让读代码的人以为存在一条可选路径。

**N4 — `global/dimension/nether_volume.glsl`**

```glsl
:89    #if defined LPV_VL_FOG_ILLUMINATION && defined EXCLUDE_WRITE_TO_LUT
:90        float TorchBrightness_autoAdjust = mix(1.0, 30.0, clamp(exp(-10.0*exposure),0.0,1.0)) / 5.0;
:91    #endif
...
:146   #if defined LPV_VL_FOG_ILLUMINATION && defined EXCLUDE_WRITE_TO_LUT
:147       color += LPV_FOG_ILLUMINATION(progressW-cameraPosition, dd, dL) * TorchBrightness_autoAdjust * absorbance;
:148   #endif
```

- 两个宏在全树**没有任何 `#define`**（它们是 Bliss 的用户选项，见 `_analysis/.../bliss-shader/`）
- `LPV_FOG_ILLUMINATION` 这个函数在 Astra 中**不存在**（全树仅此一处引用）
- 因为条件恒假，现在能编译；**一旦有人定义这两个宏，立即编译失败**

**建议**：整块删除（含只被 `:147` 使用的 `TorchBrightness_autoAdjust`）。移植时应删除不可达分支，尤其当分支内引用了未移植的符号时。

---

## 11.5 N5（P3）入口壳的三维度复制

- 40 个 gbuffers 壳文件（20 个 program × fsh/vsh）× 3 个维度 = **120 个文件**
- 加上 composite / deferred / final / shadow / prepare 系列，入口壳总数约 140
- **已验证**：去掉 `#define DIMENSION_*` 那一行后，**40/40 完全相同**

```glsl
#version 400 compatibility
#define ASTRA_TERRAIN          // ← 三维度唯一差异
#define DIMENSION_NETHER       //    world-1/ 与 world1/ 各加一行
#include "/program/lit.fsh"
```

**风险**：这套设计本身是对的（薄壳 + 共享实现），但维护面是 3×。新增一个 gbuffers pass、或改一个 `ASTRA_*` 宏，要同步改 3 处；**漏改不会有任何校验报错**，只会表现为"某个维度行为不一样"，而这类问题在没有实机验证的前提下极难归因。

**建议**：保持结构，但给 `check_pack` 加一条——**三维度同名入口壳在剥离 `DIMENSION_*` 定义后必须逐字节相同**。这条校验成本极低，且和 N1 属于同一类"静态可判、动态难查"的问题。

---

## 11.6 N6（P3）`apply_vibrance` 的权重上界与默认空转

`lib/tonemap.glsl:199-206`：

```glsl
float sat = (1.0 - clamp(mx - mn, 0, 1)) * clamp(1.0 - mx, 0, 1) * get_luminance(color) * 5.0;
...
return mix(color, mix(lightness, color, intensity), sat);
```

- `sat` 理论上界 5.0，实测可达成约 **1.25**（中灰 `(0.5,0.5,0.5)`：1 × 0.5 × 0.5 × 5）。`sat > 1` 时 `mix()` 会**外插**，产生负值或 >1 的分量
- 默认 `VIBRANCE=100` → `intensity = 1.0` → 内层 `mix(lightness, color, 1.0) == color` → 外层 `mix(color, color, sat) == color`，**函数完全空转**

也就是说这个滑块的语义是：100 无效果；偏离 100 时增益被 5 倍系数放大，并可能外插出界，最后由 `apply_contrast` 里的 `clamp(color,0,1)` 截断。

**建议**：把 `sat` 也 clamp 到 `[0,1]`。这是纯防御性改动，不改变默认值下的行为（本来就是空转）。

---

## 11.7 N7（P3）闪电两条路径的防御不一致

```glsl
// global/lighting/blocklight.glsl:130  天光闪
float facing = clamp(dot(normalize(worldDir), normalize(lightningBoltPosition.xyz)), -1.0, 1.0);

// global/lighting/blocklight.glsl:149  点光（同一文件）
vec3 L = toBolt * inversesqrt(max(d2, 1e-4));
```

点光路径对零长度做了防御，天光路径的 `normalize(lightningBoltPosition.xyz)` 没有。触发条件是闪电正好落在世界原点附近（xyz ≈ 0）→ NaN。概率极低，但防御成本为零，且同文件内已经有两种写法。

---

## 11.8 N8（P3）6 个未被引用的枚举 token

`CLOUD_VANILLA`、`SKY_MINISHITA`、`SUN_MOON_DISCS`、`WATER_BALANCED`、`SHADOW_FILTER_SOFTWARE`、`SHADOW_FILTER_HARDWARE` —— 全部在 `lib/settings.glsl:16-31` 声明，全树零引用。

它们不被引用是因为调用点写成 `#if CLOUD_MODE == CLOUD_PLANAR ... #else ...`，把"0 号枚举"当成了 else 分支。**当前无 bug**，但一旦某个枚举新增 mode 2，很容易漏改 else 分支的语义。属可读性债，建议要么在 `check_pack` 里允许"枚举 0 号 token 可不被引用"，要么在声明处注明"由 else 分支承载"。

---

## 11.9 N9（P3）非统一控制流内取导数

`program/deferred.fsh:118`：

```glsl
if (depth >= 0.999999) {
    ...
    float cone = max(length(dFdx(ray)), length(dFdy(ray)));   // ← 分支内
    displayed = sky.rgb + end_starfield(ray, end_light_direction(), cone) * sky.a * ...
}
```

规范上，非统一控制流内的导数未定义。实际 GPU 按 quad 计算，通常"能跑"，但**天空/几何交界的 quad 会取到无意义的差值**。而 `cone` 在这里直接决定星点的抗锯齿大小——表现就是**末地星点在物体边缘出现大小跳变**。

**建议**：把 `dFdx/dFdy` 提到 `if` 之外计算（成本可忽略）。

---

## 11.10 已核查并排除（避免重复排查）

这几项在审查中被怀疑有问题，逐一核实后确认**无缺陷**，记录结论以免后续重复投入：

| 疑点 | 结论 | 依据 |
|---|---|---|
| `MC_HAND_DEPTH` 全树无 `#define`，只在 `qa/tools/compile_glsl.py:45` 注入 | **非缺陷**。它是 Iris 标准注入宏（`StandardMacros`，值 `0.125`），Astra 两处用法 `((d*2-1)/MC_HAND_DEPTH)*0.5+0.5` 与 Iris 文档推荐写法一致 | Iris 文档 `reference/macros/mc_hand_depth`；Bliss 亦直接使用未定义 |
| `lit.fsh` 里 `gl_FragData[1]` 被写两次，水面的 colortex5 可能被覆盖 | **非缺陷**。`gbuffers_water.fsh` 同时定义了 `ASTRA_TRANSLUCENT` 与 `ASTRA_WATER_PASS`，`#ifndef ASTRA_TRANSLUCENT` 被跳过 | `gbuffers_water.fsh:2-4` + `program/lit.fsh:227-240` |
| `bloom_capture` / `bloom_resolve` 同名 `getBloomTile` 冲突 | **非冲突**。用 include 解析验证过两者从不同时进入同一编译单元 | 全入口 include 展开扫描，命中 0 |
| 体素光写入端与读取端锚点可能错位 | **一致**。写入 `floor(center + fract(cameraPosition) + 32)`，读取 `floor(playerPos + fract(cameraPosition) + 32 + normal*0.65 - 0.5)`；代入方块中心（playerPos = k+0.5）两者都得到 `k+32` | `program/shadow.vsh:55` vs `global/dimension/nether_colored_light.glsl:13-17` |
| compute 链 ping-pong 读脏 | **正确**。9 段 step 0..8，`%2` 决定读 A/写 B 或读 B/写 A，第 8 步（偶数）最终写入 A；消费端只读 `astraLightSamplerA` | `world-1/shadowcomp*.csh` + `nether_light.csh:50-63` + `nether_colored_light.glsl:7,22` |
| 末地烘焙 294 槽越界 | **正确**。0=辐照、1..73=73 天体、74=环轴、75..293=73 个基（3×73=219），合计 294 = `size.buffer.colortex8=294 1` | `program/end_illumination.fsh:14-28` + `shaders.properties:21` |

---

## 11.11 新增风险登记（续 §9）

| # | 风险 | 等级 | 现状 | 缓解 |
|---|---|---|---|---|
| **R8** | `ENTITY_SHADOW_DISTANCE` 不生效，界面值约为实际的 1/2 | **中** | 存在 | 摘掉选项或让它真正驱动 `entityShadowDistanceMul`；并加 `check_pack` 第 12 项 |
| **R9** | 全局非常量初始化器可能在他厂驱动上编译失败 | **中** | 仅 NVIDIA 验证过 | 改为函数内局部变量 |
| **R10** | 三维度入口壳手工同步，漏改无报错 | 中 | 120 个文件 | `check_pack` 加"剥离 `DIMENSION_*` 后逐字节相同" |
| **R11** | `nether_volume.glsl` 恒假分支内引用不存在的函数 | 低 | 不可达 | 删除该分支 |
| **R12** | `#if 2 == 0` 死分支误导 | 低 | 存在 | 删除或换回真实条件 |
| **R13** | 末地星点在物体边缘大小跳变（分支内导数） | 低 | 未实机确认 | 把 `dFdx/dFdy` 提到分支外 |
| **R14** | `apply_vibrance` 权重外插 | 低 | 默认空转，无影响 | clamp `sat` 到 [0,1] |

---

## 11.12 对 §10 建议的补充

**6. 处理 N1（`ENTITY_SHADOW_DISTANCE`）**——这是本节唯一影响"用户能感知到的设置"的问题，一个能拖但没反应的滑块比没有滑块更糟。
**7. 给 `check_pack` 补两条静态规则**："选项必须被消费"（挡 N1 整类）、"三维度入口壳必须一致"（挡 N5）。两条都是纯静态、零误报、成本极低，且都能挡住"静态可判、动态难查"的问题——这与 §7 的核心结论一致：**Astra 缺的从来不是编译护栏，而是行为护栏**。
**8. 修 N2（全局非常量初始化器）后再做一次他厂驱动编译验证**——在 N2 修掉之前，跨驱动的编译验证结果没有参考价值。
9. N3/N4/N7/N8/N9 属清理项，可合并为一次提交，不影响功能。

---
---

# 12. 第三轮：未提交改动核验 + 全量复查（2026-09-13 追加）

**性质**：只读。**本轮同样未修改任何代码**，仅在本文件末尾追加本节。
**范围**：§11 之后工作区又累积了 21 个着色器文件的未提交改动（晨昏整合、末地阴影重设计、黑洞空域跳过、云/雾/水面联动）。本轮以这些改动为第一审查对象，并对全树做第二轮未覆盖的三项系统扫描。
**方法**：全档 GPU 编译矩阵实跑 + `check_pack` 复跑 + 全选项消费扫描 + 缓冲契约矩阵 + 数值 hazard 模式扫描 + 改动涉及文件逐行审读。

## 12.1 本轮验证结果（新证据）

| 验证 | 结果 |
|---|---|
| `compile_glsl.py` 全档矩阵（3 profiles × 89 入口） | **267 linked / 0 failed / 0 警告**（RTX 4050 + NVIDIA 572.83） |
| `check_pack.py` 复跑 | **0 FAIL / 1 WARN / 10 PASS**（WARN 仍是已知的 voxy C5） |
| 63 个用户选项的消费扫描 | 除 N1 外**无新假控件**（详见 §12.10） |

**关键点**：`qa/glsl-twilight-integration.log` 等近期日志均为 **89 linked**（单档/子集），即晨昏与末地改动此前只过了单档验证；本轮的 267 全档矩阵是这些改动的**首次全档通过证据**。

## 12.2 新发现清单

| # | 问题 | 等级 | 位置 |
|---|---|---|---|
| **T1** | **`pow(负底数, 2.0)` 两处**：与 N2 同类的规范外依赖，NVIDIA 上靠编译器把 `pow(x,2.0)` 折叠为 `x*x` 才能工作，exp2/log2 路径的驱动（AMD/Mesa）将产出 NaN，直接污染黑洞壳层辐射 | **P2** | `global/dimension/end_blackhole.glsl:105-106` |
| T2 | R6 解除：`settings.glsl:244-247` 的格式声明注释**双重失实**，证据已足够，不再需要实机答案 | P3 | `lib/settings.glsl:244-247` vs `program/end_illumination.fsh:10`、`program/end_sky_buffer.fsh:9`、`lib/water_buffer_formats.glsl:12-15` |
| T3 | **`CLOUD_MODE=CLOUD_OFF` 在雨天泄漏**：平面云仍混入天空；`CLOUD_VANILLA` 在雨天得到几何云+平面云双层 | P3 | `program/scene.glsl:42-47` |
| T4 | **末地强制 bloom**：`BLOOM=false`（含 PERFORMANCE 档）在末地仍跑完整 bloom 链，且无任何注释说明这是语义覆盖 | P3 | `program/final.fsh:16,36` + `shaders.properties:64` |
| T5 | `end_star_visibility` 是靠**全局可变变量的初始值巧合**维持正确的副作用通道 | P3 | `global/dimension/end_blackhole.glsl:65` → `program/end_sky_buffer.fsh:32` |
| T6 | 第二处非统一控制流内 `dFdx/dFdy`（N9 同类）：雨滴涟漪的足迹在材质边界未定义 | P3 | `global/atmosphere/weather.glsl:49`，调用点 `program/lit.fsh:135,175` |
| T7 | `size.buffer.colortex1` 无维度守卫：下界/末地在 shafts 开启时白分配全分辨率缓冲（不写不读） | P3 | `shaders.properties:8-13` |
| T8 | `final.fsh` 在 `ASTRA_UNDERWATER_SHAFTS`（无 GODRAYS）下声明 `colortex1` 但从不读取——死声明 | P3 | `program/final.fsh:25-31` |
| T9 | 黑洞空域跳过的**最差情况成本上移**：近几何像素每步 2 次段扫（48 步 → 最多 96 次），高于旧跨步方案的 12 次；典型情况远低于旧方案。有界、可接受，但 `cost_census` 应登记新模型 | P3 | `global/dimension/end_blackhole.glsl:125-142` |
| T10 | `settings.glsl:223-229` 注释重复且数值错误（"All three profiles resolve to 0.5" 出现两次，且三档真实比值是 0.25/0.25/0.375） | P3 | `lib/settings.glsl:223-229`（并入 N1 修复） |
| T11 | `surface.glsl` 四处 `float fade = 1.0;` 后接 `mix(0.5, x, fade)`——Steadfast 距离淡出的残留空操作 | P3 | `global/water/surface.glsl:201,213,233,251` |

---

## 12.3 T1（P2）`pow(负底数, 2.0)`——与 N2 同类的跨驱动隐患

```glsl
// global/dimension/end_blackhole.glsl:105-106
float shell=exp(-pow((angle-criticalAngle)/shellWidth,2.0));
float halo=exp(-pow((angle-criticalAngle)/radians(0.65),2.0))*0.10;
```

`angle = acos(clamp(dot(originalRay,light),-1,1)) ∈ [0,π]`，`criticalAngle` 是小角度常量。
**射向临界角内侧的光线 `angle < criticalAngle`，底数为负**。GLSL 规范对 `pow(x,y)` 在 `x<0` 时结果未定义。
NVIDIA 编译器把 `pow(x,2.0)` 折叠为 `x*x`（这就是末地在 RTX 4050 上渲染正常的原因）；
走 `exp2(2.0*log2(x))` 通路的驱动会得到 `log2(负数)=NaN` → `shell/halo=NaN` →
`radiance += transmission * vec3(...) * (shell*1.8+halo*0.6)` 整片黑洞区域 NaN。

**与 N2 的关系**：这是第二处"编译通过依赖驱动宽容度"的点（N2 是全局非常量初始化器）。
两处都在末地/水链上，建议合并为一次"可移植性提交"（`pow(x,2.0)` → `x*x`；N2 改局部变量），
然后再做他厂驱动编译验证——否则 §11.12 第 8 条的验证结论依然无参考价值。
全树扫描确认这种形态**仅此两处**（`pow((表达式), 偶数)` 模式；其余 `pow` 底数均有 `max/clamp/abs` 或非负来源）。

---

## 12.4 T2（P3）R6 解除：格式声明注释双重失实

`lib/settings.glsl:244-247` 声称："SC-27 supersedes SC-25/26: this Iris build rejects active format
consts even in entry files... Do not restore declarations in any include layer."
两条断言都被当前包的**实际工作状态**证伪：

1. **入口文件格式 const 生效**：`program/end_illumination.fsh:10` `const int colortex8Format = RGBA32F;`
   与 `program/end_sky_buffer.fsh:9` `const int colortex9Format = RGBA16F;`。
   `colortex8` 烘焙**带符号的世界坐标**（天体中心 ±7.6、环轴方向、朝向基），8 位缓冲根本存不下——
   末地天空经多轮视觉验证正常，证明 RGBA32F 声明**确实生效**。
2. **include 层格式 const 生效**：`lib/water_buffer_formats.glsl:12-15`
   （`colortex0/4 = R11F_G11F_B10F`、`colortex7 = RGBA16`）只被 `program/final.fsh:10` 包含，
   而 §5.1 已核实当前分配正是这些格式（`colortex2` 无声明 → 默认 8 位，与 R2 的现象一致）。

**结论**：SC-27 的真实教训应是"**每个缓冲的格式 const 只能有一个声明点**"（入口文件或唯一 include 链），
而不是"任何位置都拒绝"。R6 从"需要实机答案"降级为"注释应据实改写"（只改注释，不改行为）。

---

## 12.5 T3（P3）`CLOUD_OFF` 的雨天泄漏与 `CLOUD_VANILLA` 的雨天双层

```glsl
// program/scene.glsl:39-47（astra_sky，主世界分支）
#if CLOUD_MODE == CLOUD_PLANAR
    vec4 cloud = astra_planar_cloud(worldDir);
    sky = mix(sky, cloud.rgb, cloud.a);
#else
    if (astraRainFactor > 0.01) {
        vec4 cloud = astra_planar_cloud(worldDir);
        sky = mix(sky, cloud.rgb, cloud.a * astraRainFactor);
    }
#endif
```

`#else` 分支同时覆盖 `CLOUD_VANILLA`（0）与 `CLOUD_OFF`（2）：

- **OFF + 雨天**：平面云仍混入天空（alpha 随 `astraRainFactor`），`weather.glsl:62` 的
  `astra_cloud_transmission` 也继续按云场遮挡阳光——用户明确关闭的云在雨天复活。
- **VANILLA + 雨天**：`clouds.fsh` 的几何云照常渲染，平面云又叠一层——双层云，
  且在性能最弱的 PERFORMANCE 档（`CLOUD_MODE=0`）多付一份平面云步进。

若"雨天阴天层"是刻意设计，应只对 VANILLA 生效并在注释里写明；否则给 `#else` 加
`CLOUD_MODE != CLOUD_OFF` 一行即可。

---

## 12.6 T4（P3）末地强制 bloom——未文档化的选项语义覆盖

- `shaders.properties:64` `program.world1/composite1.enabled=true`（**硬编码 true**；
  对照 `shaders.properties:59` 下界是 `=BLOOM`）。
- `program/final.fsh:16` `#if defined BLOOM || defined DIMENSION_END` 与 `:36` 同条件
  → 末地 `hdr += bloom_composite(colortex2, ...)` **无视 BLOOM 选项**。

链路本身自洽（`world1/composite1` 强制捕获 → `colortex2` 有数据；`bloom_composite` 的
`DIMENSION_END` 分支只读 0/1 级 mip 且 ×0.45，末地星空不被糊掉——`global/post/bloom.glsl:124-128`）。
问题只有两个：PERFORMANCE 档用户在末地仍付 bloom 成本；`settings.glsl:184` 的
BLOOM 注释没有说明末地例外。黑洞辉光是否属于"场景本体"而非"可选后处理"，是设计决定，
无论哪种结论都应写进注释。

---

## 12.7 T5（P3）`end_star_visibility`——靠初始值巧合维持正确的副作用通道

`global/dimension/end_blackhole.glsl:65`：`float end_star_visibility = 0.0;`（全局可变）。
`astra_end_blackhole` 在**部分出口**给它赋值（`:78` 无透镜路径、`:164` 逃逸路径），
`end_sky_buffer.fsh:32` 在 `astra_sky()` 返回后读它作为 colortex9 的 alpha，
`deferred.fsh:119` 再用它调制全分辨率星场。

**未赋值的出口**：入段即命中（`:83`）、视界吞没（`:152`）、transmission 耗尽（`:154`）、
步数耗尽未逃逸。GLSL 全局变量按调用初始化，这些路径上它保持 `0.0`——而这**恰好**等于正确值
（这些路径 transmission 都已归零）。**今天正确，靠的是初始值与所有早期出口的语义巧合**；
任何新增出口或改动初始值都会静默破坏末地星场。建议改为 `out` 参数，或在每个出口显式赋值。

---

## 12.8 未提交改动逐块核验（验证为正确，含证据）

| 改动块 | 结论 | 关键证据 |
|---|---|---|
| 末地阴影重设计（固定投影 + 世界锚定 texel） | **caster/receiver 完全一致** | `program/shadow.vsh:124` 对 caster 同样施加 `distort`（z×0.5 → [0.25,0.75]），与接收端 `shadow_map_position` 的映射逐项相等；锚定推导 `xy = world·axis − anchor·axis`（`lib/transforms.glsl:74-78`）成立；`end_shadow_extent()` 三档恒为 96（SHADOW_DISTANCE 均 ≥192，min 失效但无害）；`shadow_uv_coverage` 末地分支改用方形边界（`global/lighting/shadowmap.glsl:73-74`）与无扭曲投影匹配 |
| 黑洞空域跳过 | **保守界成立** | `emptyDistance = min(|p−c| − 1.65r)`（`:129`）按三角不等式逐段递减，曲线下也保守；环平面界 `dot(x,axis)+END_RING_HEIGHT`（`:134`）与 `end_ring_hit` 的平面方程（`end_ring.glsl:19`）逐符号一致；`count=0` 时 `end_scene_segment` 仍测环（`end_system.glsl:88-98` 的 `end_ring_hit` 不受候选数门控） |
| `twilight.glsl` 全部新函数 | **无 NaN 路径** | `astra_twilight_atmosphere` 的 facing 归一化经 `max(...,1e-5)` 且值域有界（\|xz\| 不能同时为小）；`astra_twilight_highlights` 除法有 `max(peak,1e-5)`；`worldSunVector.xz` 在 sunPathRotation=−40° 下 \|xz\|≥0.64，无退化 |
| `sky_gradient.glsl:117` noonFactor | **归一化正确** | −40° 轨道下正午 `worldSunVector.y = cos(40°) ≈ 0.766`，`clamp(...,0,1)` 后 sqrt 恰在正午归 1 |
| `diffuse.glsl` 夜间/晨昏块 | **作用域一致** | `night`/`moonDistance` 定义与使用点处在条件完全相同的 `#if` 对内（`:310-328` vs `:348-350`）；背光跳过（`facingNdotL <= -0.05`）与 wrap 门（`smoothstep(-0.05,0.05,ndotl)`）同一边界，wrap 在背光侧的贡献被 ≤0.028 的 facing 因子限幅 |
| `water.glsl:220-227` 高光阴影门 | **成本有界、语义正确** | `glint>0.002` 门控后才有阴影采样（太阳高光带占屏比小）；覆盖外 `surface_shadow_light` 回退 1.0（开阔水面全高光），与 Complementary 行为一致 |
| `sky.fsh:88-96` 云遮日月 | **成本可忽略** | `discard` 先于云步进；仅日月盘像素（约 0.2% 屏）执行平面云 march |
| `clouds_planar.glsl` 二八度噪声 + 云天空色缓存 | **惰性求值正确** | `cloudSkyReady` 保证每像素最多一次 `astra_get_sky`；`columnDensity ∈ [0,1]`；`mat2(0.8,-0.6,0.6,0.8)` 正交旋转 |
| `scene.glsl` 晨昏雾 | **行为按注释** | `morningFog` 在 `fog.a=0` 时仍能起雾（设计意图）；`skyStrength` 作为 `in` 参数副本可写 |

---

## 12.9 缓冲契约矩阵（本轮新做的系统扫描，结论：自洽）

逐 pass 核对 `RENDERTARGETS` 与 `colortex` 读取端：

| 缓冲 | 写 | 读 | 结论 |
|---|---|---|---|
| colortex0 | gbuffers / deferred(0,4) / composite3 | 全链 | 无同 pass 反馈；flip 由引擎按"写入才翻转"管理 |
| colortex1 | composite2（`scattering.fsh`，RENDERTARGETS:1） | `water_composite`（仅 `ASTRA_UNDERWATER_SHAFTS`）、`final`（仅 GODRAYS） | 写使能条件（`shaders.properties:33-37`）覆盖所有读取配置 |
| colortex2 | composite1（0.25，mip 开） | final（4 级 mip） | 两端 `colortex2MipmapEnabled` 均声明 |
| colortex3 | 不透明 gbuffers（lit.fsh[1]，blend off） | deferred | 半透明不写它（water pass RENDERTARGETS 0,5），契约成立 |
| colortex4 | deferred（0,4 的第二槽） | gbuffers_water / particles | deferred 在 Iris 管线中先于半透明，"不透明副本先于透明物"成立 |
| colortex5 | gbuffers_water（lit.fsh[1]） | composite（`water_state`） | 每帧清除（clearColor 0） |
| colortex6 | composite（`water_state`，1×1） | `medium_state`（deferred/gbuffers） | 一帧滞后是设计（`colortex6Clear=false`） |
| colortex7 | composite4（水下 bloom） | final `getBloom`（仅 BLOOM 且水下） | 写读门控一致；discard 保留旧内容无害（仅水下眼读） |
| colortex8 | world1/prepare（294×1 RGBA32F） | 末地天空/阴影/烘焙 | 槽位划分与读取端 texelFetch 对齐（§11.10 已验，本轮复核不变） |
| colortex9 | world1/deferred（0.75，RGBA16F） | world1/deferred1 | deferred 先于 deferred1，顺序成立 |

---

## 12.10 已核查并排除（续 §11.10，避免重复排查）

| 疑点 | 结论 | 依据 |
|---|---|---|
| 63 个选项中是否还有"假控件" | **没有**。唯一 0 消费者的仍是 `ENTITY_SHADOW_DISTANCE`（N1） | 全树引用扫描 + 计数为 1 的选项逐一人工复核（`BIOME_TINT_STRENGTH`→`fog.glsl:154`、`SHADOW_SOFTNESS`→`shadowmap.glsl:56,139,146`、`WATER_ABSORPTION`→`absorption.glsl:14,35` 等均真实消费） |
| `light_shafts.glsl:113` 的 `solasWaterSqrt`/`solasWeather` 是否未声明 uniform（会静默为 0 使光束全黑） | **非缺陷**。两者是 `lib/solas_water.glsl:7-8` 的 const vec3 | 文件直读 |
| `caustics.glsl` 的 `colortex7` 命中 → 焦散是否依赖 BLOOM | **非缺陷**。命中在注释（`:51`"its colortex7"指 IterationT 的缓冲）；焦散完全出自 Solas 高度场 | 文件直读 |
| 末地 `end_light_direction` 与 (0,1,0) 叉积退化 | **不可能**。固定 23° 仰角（`lib/end_light.glsl:4`），\|cross\| = cos23° ≈ 0.92 | 文件直读 |
| `sky.fsh:36` 月亮 `normalize(cross(c,(0,0,1)))` 退化 | **不可能**。−40° 轨道下月亮方向与 ±Z 的最小夹角使 \|cross\| ≥ 0.766 | 轨道几何推导 |
| `composite.vsh` 背相机光源 `lightScreenPos` | **有守**。`clipLight.w > 0.0` 三元 + `max(w,0.0001)`，且 godraysExposure 的 offscreen 衰减先行 | `program/composite.vsh` |
| `water_state.fsh` 对全分辨率 colortex5 的 20×12 网格 texelFetch | **可忽略**。该 pass 每帧只有 1 个像素（colortex6 是 1×1） | `program/water_state.fsh:12-32` |
| `end_illumination.fsh` 单像素 256 次积分 | **可忽略**。仅 `gl_FragCoord.x==0` 一个像素承担，其余 293 像素是查表写入 | `program/end_illumination.fsh:14-59` |
| 根入口壳三维度复制（N5）是否有漏改 | **本轮抽查 `gbuffers_water`/`gbuffers_weather` 等壳的宏组合与 lit.fsh 的条件编译矩阵一致**；N5 的结构风险仍在（属 §11.5 建议的校验项，非新缺陷） | 壳文件直读 + 条件矩阵推演 |

---

## 12.11 新增风险登记（续 §11.11）

| # | 风险 | 等级 | 现状 | 缓解 |
|---|---|---|---|---|
| **R15** | `pow(负底数, 2.0)` 在他厂驱动产出 NaN，污染黑洞壳层 | **中** | 仅 NVIDIA 验证过 | 与 N2 合并为一次可移植性提交（`x*x` + 局部变量），然后做他厂编译验证 |
| R16 | `CLOUD_OFF` 雨天泄漏 / `CLOUD_VANILLA` 雨天双层云 | 低 | 存在 | `#else` 加 `CLOUD_MODE != CLOUD_OFF` 门；VANILLA 双层留作设计决定 |
| R17 | 末地 bloom 强制未被任何注释说明 | 低 | 存在 | 注释写明，或改回 BLOOM 门控 |
| R18 | `end_star_visibility` 的初始值巧合 | 低 | 正确但脆弱 | 改 `out` 参数或逐出口显式赋值 |
| R19 | colortex1 尺寸无维度守卫 + final 死声明 | 低 | 浪费显存/可读性 | 尺寸条件加 `!defined DIMENSION_NETHER && !defined DIMENSION_END`；删掉死声明 |

---

## 12.12 对 §11.12 建议的补充

10. **T1 与 N2 合并修复后立即安排他厂驱动编译验证**（顺序同 §11.12 第 8 条，现在阻塞项变成两个）。
11. **T3 一行门控**（`scene.glsl:42-47` 的 `#else` 加 `CLOUD_MODE != CLOUD_OFF`）——除非"雨天阴天层"被确认为设计，届时改注释而非改代码。
12. **T4 二选一**：在 `settings.glsl:184` 写明"末地始终启用 bloom"，或把 `world1/composite1` 与 `final.fsh` 的 `DIMENSION_END` 分支改回 BLOOM 门控。
13. **T2/T10 并入 N1 的提交**：`settings.glsl:223-229` 删掉重复且数值错误的注释行；`:244-247` 按 §12.4 的结论改写（只改注释）。
14. **`cost_census.py` 登记黑洞新成本模型**：空域跳过使典型像素几何求交≈0，但掠射环平面的像素最差 96 次段扫（仍远小于挂起前的 512）——工具的"循环上界"视角对这类**动态门控**循环会同时高估典型、低估最差，这正是 §7.3 第 1 条要补的第二个盲点的又一个实例。
15. `docs/` 平铺文档已增至 47 份（§8 时为 34 份），归档建议的优先级上调。

**本轮边界（与 §附录 相同）**：无实机画面、无帧率数据；末地阴影重设计与晨昏联动只通过了静态与编译验证，视觉效果仍待游戏内确认。

---

## 13. 源码核对、必要性判断与处理（2026-09-13）

### 13.1 需要纠正的结论

1. **N2 的规范归因不成立。** 本包使用桌面 GLSL 4.00。规范 §4.3 允许无存储限定符的普通全局变量初始化，§4.3.2 要求常量表达式的是 `const` 初始化器；不能把普通全局变量依赖 uniform 直接判成 NVIDIA 扩展宽容，也不能据此断言其他厂商必然失败。本轮把 capture 的三个尺寸值局部化、移除 resolve 的两个未使用尺寸变量，属于收窄作用域和清理。[GLSL 4.00 官方规范](https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.4.00.pdf)
2. **N1 确实成立，但原距离表漏了 1.5。** 本地 Iris `ShadowRenderer.txt` 中实体分支先将 `renderDistanceMultiplier` 与 `entityShadowDistanceMultiplier` 相乘，再由 `createShadowFrustum` 乘 `halfPlaneLength`。当前距离剔除模式下名义半径是 `SHADOW_DISTANCE × 1.5 × entityShadowDistanceMul`，还受游戏视距约束。旧三档名义半径为 144 / 192 / 192，而非报告的 96 / 128 / 128。本轮按用户实体距离除以 `SHADOW_DISTANCE × 1.5` 枚举全部 8×5 个组合的字面量，避免 Iris 把算术表达式当数字解析。
3. **T1 是真实的未定义运算，但厂商结论过强。** GLSL 的 `pow` 对负底数结果未定义，即便指数为 2；可以确认风险，不能在没有对应驱动证据时断言 NVIDIA 一定如何折叠、AMD/Mesa 一定如何执行。已改为偏移量自乘。[GLSL 4.00 官方规范 §8.2](https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.4.00.pdf)
4. **不能从静态扫描得出“没有第二处必挂热点”或“没有可安全优化项”。** 旧 `cost_census` 只在纹理调用同一行找循环，跨行循环体不计倍率；也没有配置预处理、可达函数分析、递归调用图或真实分辨率应用。原说明甚至比实际能力更强。它不能提供每像素执行量，更不能证明 GPU 安全。
5. **硬件 PCF 的“完全等价”限于标量过滤模型。** 当前硬件路径在材质/彩色透射上使用中心样本近似，不能把单独权重算式的等价性推广为整条阴影链等价。保留现有默认模式。
6. **功能存在不等于视觉完成。** 日夜函数存在无法反驳用户的画面反馈；夜视、失明、实体受伤颜色在 `diffuse.glsl`、`fog.glsl`、`lit.fsh` 中已有明确处理，§3.3 的“完全缺失”也不准确。
7. **成本数字须以当前路径为准。** 黑洞空域跳过已取代固定跨步，不能继续写成每像素固定 12 次；最多 96 次候选段调用之外还有入段/逃逸，以及被调函数内部遍历。294 槽烘焙中仅第 0 槽执行 256 点积分，不能算成 294×256。T9/§12.10 对这两点的修正优先于旧段落。

### 13.2 已处理的真实问题与低成本清理

| 原条目 | 核对结果与处理 |
|---|---|
| N1 / T10 | 实体距离控件接入全部合法组合，按实际 Iris 公式换算；删除重复且失实的注释。 |
| N2 / N3 | N2 不是规范违规；尺寸变量局部化/删除未使用项。N3 恒假分支删除，保留现有生效的泛光算法。 |
| N4 | 删除两个未移植宏保护的 LPV 调用与专用临时变量，现有下界体积光不变。 |
| N7 | 闪电天空方向改为有下限的长度归一化，消除零向量风险。触发条件是传入向量为零，不能简单等同于世界原点。 |
| N9 / T6 | 末地星点锥角在深度分支之前计算；雨涟漪足迹在材质分支和 alpha 丢弃之前计算并显式传入。 |
| T1 | 黑洞壳层与光晕的高斯偏移改为自乘。 |
| R2 / R6 / T2 | colortex2 改为 R11F_G11F_B10F，保留 HDR 泛光能量；与默认 RGBA8 同为每像素 32 位。修正格式声明注释。亮部泛光可能因此比旧截断结果更强，这是修复的效果差异。 |
| T3 | 平面云只在 CLOUD_PLANAR 模式绘制；原版云由自身几何通道负责；关闭云不再于雨天复活。非平面云模式不再投射虚构的程序云场遮挡。 |
| T4 | 末地捕获和最终合成统一服从 BLOOM；黑洞本身的辐射/光子环仍由场景计算。 |
| T5 | 在黑洞函数入口显式重置星场可见性输出，覆盖每次调用的早退路径，不再依赖着色器全局初始化只执行一次。 |
| T8 | final 只在真正读取 GODRAYS 时声明 colortex1；水下光束的读取仍属于 water_composite。 |
| R1 / T9 | 将失真的成本排名脚本改成诚实的循环源码清单：列位置、完整循环头、体内采样点及调用名；不猜动态上界、不把源码采样点称为每像素取样次数。附当前黑洞/烘焙/积水路径说明。 |

### 13.3 权衡后未采纳的建议

| 原条目 | 原因 |
|---|---|
| N5、选项消费者规则 | 入口薄壳复制是引擎接口，未发现具体漏接；“所有维度去掉宏后必须相同”和“settings 之外必须消费”都过强，设置文件本身可合法生成引擎指令。没有新增这种误报规则。 |
| N6 | VIBRANCE=100 是有意的恒等档；编译器可消去该计算。非默认档的外插是增益行为，灰色样例虽权重大于 1，但被插值的两色相同，并未证明像素出错。本轮不改变已有滑块手感。 |
| N8 / T11 | 枚举名称与被编译器消去的单位系数没有实际运行缺陷，保留可读的来源结构。 |
| T7 | properties 尺寸指令是公共配置，不能直接套用入口 GLSL 的 DIMENSION_END/NETHER 宏来声称实现逐维度分配；也没有新增实际显存分配证据。已删除明确的死 sampler，不采用报告建议的无效宏守卫。 |
| R1 接入强制规则 | 没有配置预处理、完整调用图与运行计时的工具不能充当防 GPU 挂起的保证，也不是唯一可行机制。源码清单用于定位审读对象，不接入这种强制规则。 |
| R3 / R5 | 不强制开启硬件 PCF、不减少积水步数，避免把材质近似和精度变化当成无损修复。 |
| Voxy / DH / 镜头效果、文档搬迁、工作区提交或丢弃 | 属新增功能或整理事项，未发现必须通过这些动作解决的本轮缺陷；保留现有工作区内容与目录。 |

shader 修复已同步游戏实例 Astra。当前结论来自源码、规范和本地 Iris 实现；没有新增其他厂商驱动、实际帧率或修改后游戏画面的证据。
