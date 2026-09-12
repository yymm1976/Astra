# Astra 全量审查报告

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
