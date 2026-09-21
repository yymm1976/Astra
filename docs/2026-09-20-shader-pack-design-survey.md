# 主流光影包源码调研 · 面向 Astra 的设计改进报告

**日期**：2026-09-20　**Astra 基准**：`main` @ `46fafab` + `docs/2026-09-20-qoder-full-review.md` 未提交改动
**性质**：只读调研。**本次未修改任何代码文件**，仅新增本文件。
**样本根目录**：`C:\Users\杨铭\Desktop\光影包\`（**22 个不同包目录**永久保存 = 本次 20 个下载条目 + 姊妹文档解包的 2 个参照包；四个分母见 §3.5 第一条。原始 zip 在 `_downloads/`，sha1 见 `_meta/downloads.json`）
**方法**：Modrinth v2 API 取数 → 按「下载量 + 发布窗口 + 代码库去重」入样 → 19 款（20 个下载条目）逐个源码解析（§2）→ 四张横切矩阵由脚本测量（§3，`_meta/matrix.py` 可复现）→ 五个维度做跨包结论（§4）→ 与 Astra 实测状态逐项对照后给出排序建议（§6）。
**未做的事**：没有游戏内验证。因此**画面质量优劣不在本文范围内**；本文只谈组织结构、算法选择、成本模型与许可证，凡涉及观感的表述均标明为「该包的意图」而非「实测结果」。

## 0. 总体结论

| 维度 | 评级 | 依据 |
|---|---|---|
| 样本可信度 | 可用，但有硬边界 | 下载量只有 Modrinth 单平台可机读；CurseForge 403，故跨平台合计不可得，已用 2 个「知名度补偿样本」显式补齐（§1.2） |
| Astra 规模位置 | 偏小且干净 | 9,804 GLSL 行 / 381 最长行 / 0.451 注释比：行数约为 A 组中位数的 55%，最长行全场最短一档，注释比全场第二（§3.1） |
| Astra 配置层写法 | 主流，不是缺陷 | `option.`/`slider.`/`tweak.`/`const.` 在全部 21 个测量集合中均为 0，Astra 的裸 `#define` + `screen`/`profile`/`sliders=` 就是生态通用做法（§4.5） |
| Astra 最大结构性离群 | **档位设计** | 3 条 profile 各列 67 个 token，其中只有 **13 个**真正随档变化（差量密度 19%；Complementary 同为平铺但密度 93%），且 `Astra/shaders/global/post/grading.glsl:63-66` 自陈三档调色参数完全相同（§6 P0-1） |
| Astra 真实功能缺口 | 3 项可核实 | 云阴影 0 命中（19 款里 8 款有）；自动曝光 0（结构信号 `MipmapEnabled` 有 3 处声明/2 张缓冲，均未用于测光）；太阳遮蔽的全局强度项全为解析量、不采深度（§6 P0-3、P1-6） |
| Astra 已被证伪的"缺口" | 4 项 | 水下光束、水上光柱、absorption 水体模型、buffer 格式声明——**均已实装且多数强于参照包**，本文不再据此提建议（§7） |
| 许可证可用性 | 15/19 只能读思路 | 仅 Mellow、RenderPearl、Miniature（MIT）可署名复用；VanillAA（MPL）只有根文件可复用、`bsl_lib/` 须重写；Noble/Bloop 为传染或 NC，必须重写（§8） |
| 本文不采纳的高频"借鉴" | 5 项 | TAA（当前阶段）、SSAO（低配组 5 款里 4 款为 0）、逐文件许可头、维度整包复制、以注释形式记录 buffer 配置（§7） |

**一句话结论**：Astra 的问题不在代码质量或功能完整度，而在**配置层的档位语义空洞**与**三个可低成本补齐的全局光照缺失项**；样本里最值得搬的不是任何特效算法，而是三件结构性的事——让档位真正改变东西、把像素成本搬到 shadow 阶段烘焙、把渲染分辨率做成连续旋钮。

---

## 1. 样本选取：依据先于结论

### 1.1 数据来源与硬限制

- **下载量与更新时间唯一来源：Modrinth v2 公共 API。**
  - 排行：`GET https://api.modrinth.com/v2/search?index=downloads&limit=100&facets=[["project_type:shader"]]`。`project_type` 对光影的取值是 `shader`（用 `categories:shaders` 返回 0 条），全库 904 个 shader 项目。
  - 许可证与仓库：`GET /v2/project/{slug}`。
  - **最后更新时间取 `GET /v2/project/{slug}/version` 中最新 release/beta/alpha 的 `date_published`。** 刻意不用 search 接口的 `date_modified`——该字段改一次项目描述就会跳一次，不反映真实发布。
- **CurseForge 不可用（已验证的硬限制）**：页面与 `api.curseforge.com/v1` 均返回 403（无 key）。因此**无法统计跨平台合计下载量**，下表所有数字仅表示 Modrinth 单平台计数，**不得用于跨主机比较**。
- 由此产生一个必须承认的偏差：主分发渠道在 CurseForge 或作者站的包，其 Modrinth 计数系统性低估知名度。这就是 §1.4 两个补偿样本的来源，并且它们被明确标注为**人工判断，不是数据结论**。

### 1.2 入样规则（按优先级顺序执行）

**A 组 · 经典老牌 / 高知名度 / 近半年仍在更新**
1. `date_published >= 2026-03-20`（今天 2026-09-20 往前推 6 个月）；
2. 按 Modrinth 下载量降序；
3. **同一代码库只计一个样本**——已验证 Complementary Reimagined 与 Unbound 为同一份代码（408 个 GLSL / 23,660 行 / 800 条 include 边逐项相同），合并为一个名额、两个下载量都列出；
4. 与 Astra 定位重合而被划入 B 组的包不占 A 组名额（MakeUp、E-LITE、Miniature）。

**B 组 · 低配向顶级优化光影（5 款）**：不要求半年窗口，只要求与 Astra 在**功能定位 / 处理方式 / 设计思路**上的重合度最高，逐个给理由（§1.3）。

**补偿样本 2 款**：Sildur's Vibrant、LIGHT Shaders。两者是生态历史级老牌（Sildur's 自 2012 年；LIGHT 是 Chocapic13' 谱系的现役续作），不满足"下载量前 10"的机械条件，但满足"知名度最高 / 经典老牌 / 近半年更新"，以显式标注入样。

### 1.3 样本清单表

**A 组（10 款 = 11 个下载条目）**

| # | 包名 | slug | 版本 | Modrinth 下载量 | 最后发布 | 作者 | 许可证 | 源码仓库 |
|---|---|---|---|---|---|---|---|---|
| A1 | Complementary Reimagined | complementary-reimagined | r5.9.3 | 66,417,800 | 2026-09-15 | EminGT | 自定义 Complementary License 1.7 | github.com/ComplementaryDevelopment |
| A1 | Complementary Unbound（同代码库） | complementary-unbound | r5.9.3 | 43,271,721 | 2026-09-15 | EminGT | 同上 | 同上 |
| A2 | BSL Shaders | bsl-shaders | 10.1.5 | 29,115,030 | 2026-09-06 | CaptTatsu | All Rights Reserved | — |
| A3 | Photon | photon-shader | v1.3b | 26,644,879 | 2026-04-14 | sixthsurge | 自定义 LicenseRef- | github.com/sixthsurge/photon |
| A4 | Solas | solas-shader | 3.7b | 16,951,533 | 2026-08-23 | Septonious | All Rights Reserved | github.com/Septonious/Solas-Shader |
| A5 | Mellow | mellow | 3.4 | 6,680,993 | 2026-08-31 | TheCMK | **MIT** | codeberg.org/TheCMK/mellow-shaders |
| A6 | I Like Vanilla | i-like-vanilla | v1.4.4 | 2,303,490 | 2026-08-01 | What42 | What42's Shader License 2.2 | github.com/What42Pizza/I-Like-Vanilla |
| A7 | Noble | noble | 1.9.8hf | 2,236,414 | 2026-09-13 | BelmuTM | **GPL-3.0-only** | github.com/BelmuTM/NobleRT |
| A8 | Bloop | bloop-shaders | 1.8.0-Alpha-3 | 1,787,198 | 2026-03-25 | espen96 | CC-BY-NC-SA-4.0 | — |
| A9 | RenderPearl | renderpearl | 2.8.0-beta.4 | 1,335,792 | 2026-07-21 | Luracasmus | **MIT** | github.com/Luracasmus/renderpearl |
| A10 | RedHat（Chocapic13' 谱系） | redhat-shaders | 34.3.1 | 952,743 | 2026-04-30 | mlgimposter | Chocapic13 Agreement | — |
| 补偿 | LIGHT Shaders | light-shaders | 1.8.0 | 504,277 | 2026-08-23 | Author87668 | Chocapic13 Sharing Agreement | github.com/At87668/LIGHT-Shaders |
| 补偿 | Sildur's Vibrant | sildurs-vibrant-shaders | 2.02 | 481,618 | 2026-09-15 | Sildur | All Rights Reserved | — |

**B 组（5 款低配向）与重合度理由**

| # | 包名 | slug | 版本 | 下载量 | 最后发布 | 作者 | 许可证 | GLSL 行 | 与 Astra 重合的理由 |
|---|---|---|---|---|---|---|---|---|---|
| B1 | MakeUp - Ultra Fast | makeup-ultra-fast-shaders | 9.5e | 12,707,939 | 2026-09-05 | KDXavier | **LGPL-3.0-or-later** | 10,674 | 全生态下载量最高的"纯性能优先"包；行数与 Astra（9,804）同量级；以极简 G-buffer + 廉价近似换帧数，与 Astra「清爽原味 + 性能」是同一命题 |
| B2 | E-LITE shaders | lite-shaders | ELT511 | 1,421,655 | 2026-06-24 | Entokito | **LGPL-3.0-or-later** | 15,398 | MakeUp 的低配分叉，是「同一份代码如何继续向下砍」的现成实验，直接对应 Astra 的 PERFORMANCE 档 |
| B3 | Miniature Shader | miniature-shader | 2.19 | 4,587,214 | 2026-07-29 | ukrech | **MIT** | **1,581** | 99 文件 / 1,581 行做到可发布质量的日常光影，是「最小代码量达到可发布」的极值样本；MIT 可直接复用 |
| B4 | VanillAA | vanillaa | 1.3 | 3,390,091 | 2023-08-31 | vriska | **MPL-2.0**（`bsl_lib/` 例外） | **728** | 20 文件 728 行，靠 TAA + 极少 pass 达成「像 vanilla 但更干净」；Astra 不用 TAA，这是「另一种办法达到同一视觉目标」的对照组 |
| B5 | Super Duper Vanilla | super-duper-vanilla | 1.3.8 | 7,797,036 | 2025-07-08 | Eldeston | FlameRender/TM Studios v1.6 | 12,296 | 7.8M 下载的 vanilla 风格低配包；include 边 1,123 为全场最高、`variable.*` 密度高，说明其"用配置层做档位"的取向与 Astra 的 `screen`/`profile` 分层最接近 |

**对照样本（仍保存、仍测量，但不占 15 个正式解析名额）**

| 包名 | slug | 下载量 | 最后发布 | 许可证 | 作为对照的理由 |
|---|---|---|---|---|---|
| Just Colored Lighting | just-colored-lighting | 610k 级 | 2025 年内 | All Rights Reserved | 彩色方块光的**上限参照**（Iris LPV 体素场路线），Astra `Astra/shaders/global/lighting/blocklight.glsl` 的正题参照 |
| Vanilla Plus | vanilla-plus-shader | 2,100,000+ | 2025-02-28 | ARR + 自拟 EULA | 体量与 Astra 最接近的 Iris-only 延迟包，且**已停更约 18 个月**——是「一个工程上不错但已死的包会留下什么」的最佳样本 |

**排除项（记录原因，避免被误读为遗漏）**
- Bliss（14.4M）、Rethinking Voxels（12.9M）：最后发布 2025-11-23 / 2025-06-19，出窗；且两者是重体积光线追踪定位，与 Astra 的低配前向路线相反，不具可迁移性。
- Insanity（7.4M）、AstraLex（5.1M）、Pastel（5.0M）、Nostalgia（4.2M）、Hysteria（3.4M）、Kappa（3.1M）：2024-08 至 2025-02 停更，出窗。
- Shrimple、FastPBR：2025-02 停更，且属"着色器替代品"技术演示而非完整光影包。
- `bsl-shaders-classic`（2.2M）：BSL 旧版分支，与 A2 同源，不重复计名额。

### 1.4 关于「源码未公开」

用户要求的兜底条款在本次**不适用**：19 款入样包（20 个下载条目）的 GLSL 源码全部随分发件公开（Modrinth 光影格式本身即 zip 内的 `shaders/` 目录），因此本文没有任何一节需要以公开文档替代源码分析。唯一接近该情形的是 A8 Bloop 与 B4 VanillAA 的**许可证文本缺失**——源码可读，但包内没有 LICENSE 文件（分别见 §2.8、§2.16），这属于合规风险而非信息缺失。

---

## 2. 逐包源码级解析

以下每节按同一骨架：组织 → 管线 → 关键实现（带 `路径:行号`）→ 低配招 → 取舍原因 → 许可证判定 → 给 Astra 的一条。A1/A2 同代码库合并叙述差异。

**引用约定**：包内路径一律相对该包的 `shaders/` 根目录（例：`lib/common.glsl` = `complementary-reimagined/shaders/lib/common.glsl`）；Astra 路径写作 `Astra/shaders/...`。本节全部 `路径:行号` 已由 `光影包/_meta/check_citations.py` 逐条核验文件存在且行号不越界（2026-09-20 复核，结果见 §9.1）。

### 2.1 A1 Complementary（Reimagined r5.9.3 / Unbound r5.9.3）

**组织**：408 GLSL / 23,660 行 / 800 include 边 / 3 维度目录 / `#version 130` ×213 + `400 compatibility` ×3 + `430 compatibility` ×3。两个变体**只差一行**：`lib/common.glsl:14 #define SHADER_STYLE 1 //[1 4]`——即"Reimagined 与 Unbound 是同一份代码的两种默认值"，这是生态里最省力的双品牌做法。

**管线**：`shadow`(+`shadowcomp`) → `gbuffers_*`（前向写 G）→ `deferred1`（云/SSDO）→ `composite*` → `final`。`program.*.enabled` 9 条、`shadowcomp` 3 条、无 `size.buffer`（`program/composite2.glsl:23` 自陈该 pass 保留未用）。

**关键实现**
- **焦散烘焙进阴影图**：`program/shadow.glsl:114-137` 用 `gaux4` 的梯度差在 shadow 阶段算焦散写入 `shadowcolor0`（`cMult = 14.0`，`color1.rgb = vec3(max0(min1(caustic*0.8+0.35))*0.65+0.35)`）。像素端只需一次纹理读取。
- **光束同样在 shadow 阶段产出**：`program/shadow.glsl:155-175` 写 `color2` = `shadowcolor1`，强度按 `:167` `factor = max(2.5 - 0.025 * length(position.xz), 0.8333) * 1.3` 随距离衰减；消费端 `lib/atmospherics/volumetricLight/volumetricLight.glsl:208-212` 只在 `shadowSample == 0 && shadowtex1` 全透明（即"该 texel 没被遮挡"）时才去读它。
- **水的吸收是单行近似**：`lib/materials/specificMaterials/translucents/water.glsl:193` `float waterFog = max0(1.0 - exp(lViewPosDifM * 0.075));`；雾色 `lib/common.glsl:790-799`（`:799` `waterFogColor = underwaterColorM2 * vec3(0.2 + 0.1 * vsBrightness)`，其中 `underwaterColorM2 = pow(fogColor, vec3(0.33, 0.21, 0.26))`）——用一个固定的 RGB 幂次向量表达"水吸红快于吸蓝"。
- **云按质量档切换实现而非切换参数**：`lib/atmospherics/clouds/mainClouds.glsl:42-46` 同一函数签名 include 不同实现文件。
- **树叶完全跳过阴影图**：`lib/materials/specificMaterials/terrain/leaves.glsl:28-29`，靠半 Lambert + 天光，省下整条 PCF。
- **8 条 profile 每条只列 14 个性能 token**（`shaders.properties:2-9`），全部平铺、零继承（M4「继承行 = 0」），且不碰任何颜色/风格 token。
- **Unbound 在共享骨架上额外提供**（Reimagined 不含）：TAA（`lib/antialiasing/taa.glsl` 251 行 + `jitter.glsl` 8 点 Chocapic 抖动序列）、`lib/voxelization` 屏幕空间方块光、`unboundClouds`（204 行 3D 云）、SSR/反射缓冲链（colortex7/8 @ `REFLECTION_RES`）、`lib/textRendering`。⇒ 两变体**默认值分层**而非功能分叉——`lib/common.glsl:14 #define SHADER_STYLE 1 //[1 4]` 一行切换，重特性全部隔离为可关断 pass + 缓冲。
- **无 TAA 的时域自适应体光采样**〔2026-09-20 执行 T8 更正：本条原文把它写成"相机静止时爬升、运动时回落"，两处都不对——驱动信号与回落条件见下方改后文本，全部行号引证见 11.F-8〕：`lib/atmospherics/volumetricLight/volumetricLight.glsl:289-346` 的**「Scene Aware」段**维护标量 `vlFactor`（0..1）：每 `int(0.06666 / frameTimeSmooth + 0.5)` 帧（约 4 帧，不是每帧）在**角点像素**上比一个阈值——`salsCheck` 是阴影图日方向 5×5 区域里遮蔽物高度（`shadowcolor1.a`）的均值，超过 `heightThreshold = 6.0` 则 `+= OSIEBCA`（`1/255`），否则 `-= OSIEBCA * reduceAmount`；`reduceAmount` 由画面五点的开阔天空判定 `skyCheck` 决定（看到天空 ⇒ 提到 3，即无遮挡场景更快回落）。它驱动的 `nearSamples` 方向是**加**：`mix(nearSamples, 1.5 * nearSamples, vlSceneIntensity)`（`:134`），而 `vlSceneIntensity = isEyeInWater != 1 ? vlFactor : 1.0`（`:16`）——**水下恒取最高档，不做自适应**。持久化靠 `program/composite1.glsl`：`:339` 在角点读回上一帧 `colortex5.a`、`:343` 写回，`:379`（该文件 `#ifdef VERTEX_SHADER` 段内，`world0/composite1.vsh` 只有 7 行、仅 `#define VERTEX_SHADER` + include）把它作为 `flat out` 广播给整趟 pass——与 Astra colortex6 的 1×1 状态像素同构。
- **近/远双段采样**：`volumetricLight.glsl:183-250`，近段逐样本查阴影，远段**完全不查阴影**、密度直接用 `eyeBrightnessM`。远场本就低频，阴影贡献趋于常数。
- **`dimension.properties`（`dimension.world0=*`）+ `shaders.properties:95-112`**：world0 通配所有模组维度；`#if SHADOW_QUALITY == -1 → program.world0/shadow.enabled=false` 按选项**整条禁用 pass**。反射分辨率做成用户选项：`lib/common.glsl:240 #define REFLECTION_RES 0.5 //[1.0 0.5]`，两张反射缓冲尺寸挂在选项上。

**为什么这么取舍**：Complementary 的设计目标是「一包含盖从核显到高端的所有人」，所以它的招全部是**把成本从像素端挪到 texel 端**（阴影图 2048² = 400 万次/帧，而屏幕是 800 万+ 像素，且阴影阶段输出被大量像素共享）。焦散与光束都是「逐 texel 算一次、所有像素读一次」。

**没有的东西**：**全包无自动曝光**。M3「自动曝光命名」命中 0；`grep -i "exposure|adaptation|luminance"` 全仓只命中 `TM_EXPOSURE` 一个常量；亮度全靠 `lib/common.glsl:750 float vsBrightness = clamp(screenBrightness, 0, 1)` 折算进颜色（散布到 `lib/lighting/minimumLighting.glsl:3`、夜天光 `lib/colors/lightAndAmbientColors.glsl:20-49`、洞穴雾 `lib/common.glsl:779`）。注意它**确实有 5 处 mipmap 声明**（`program/deferred1.glsl:20`、`program/composite.glsl:20`、`program/composite3.glsl:19`、`program/composite4.glsl:18`、`program/composite6.glsl:16`，即 M3「Mipmap降采样」=5），但没有一处接成"屏幕平均亮度 → 曝光"的测光链路。一个 66M 下载、2026-09 还在更新的包，其曝光是纯常量 + `eyeBrightnessSmooth`。这是 Astra 补自动曝光时最有力的"不做也有人气"反证——见 §6 P0-3 的权衡说明。

**许可证**：Complementary License Agreement 1.7（专有）→ **只读思路，不得复制任何一行或任何表达**。可安全迁移的是架构选择本身（把焦散/光束烘进 shadowcolor、云按档换实现、树叶跳过阴影、双变体差一行），这些属于不受保护的技术决策。

### 2.2 A2 BSL 10.1.5

**组织**：277 GLSL / 17,824 行 / 574 include 边 / 3 维度目录 / `#version 120` ×179。它是全场把 `program.*.enabled` 用得最充分的包之一：**24 条**（`shaders.properties:102-125`）。

**关键实现**
- **mipmap 链做测光**：`program/composite5.glsl:57 const bool colortex0MipmapEnabled = true;`，`:156-159` `exposureLod = log2(viewHeight * AUTO_EXPOSURE_RADIUS); exposure = length(texture2DLod(colortex0, vec2(0.5), exposureLod).rgb);`——一次 fetch 拿到屏幕平均亮度，成本与分辨率无关。
- **三个全局标量借用 1 像素**：`program/composite5.glsl:304-386` 把 `colortex2` 的像素 0 存曝光、像素 1 存太阳可见度、像素 2 存 DOF 对焦距离，并用 `exp2(-frameTime * AUTO_EXPOSURE_SPEED)` 做时域平滑。
- **阴影**：`lib/lighting/shadows.glsl:17-26` 9 抽圆盘；`:146-152` 法线偏移量按 `2048.0 / shadowMapResolution` 归一（`worldPos += worldNormal * distortNBias * 5.0 * (2048.0 / shadowMapResolution);`，换分辨率不改行为），深度 bias 同样在 `:185-195` 全部除以 `shadowMapResolution`。
- **云阴影（Astra 缺的那一项）**：`lib/lighting/shadows.glsl:295-374 GetCloudShadow()` 用 2D 噪声沿光向投影出地面暗斑，再用 `CLOUD_REVEAL` 做孔洞透射。**不做云 raymarch**，成本约等于一次噪声 fetch。
- **云四档是"换实现"而不是"改参数"**：`lib/settings.glsl:115 #define CLOUDS 2 //[0 1 2 3]`；`program/gbuffers_clouds.glsl:65-66 #if CLOUDS != 3 discard;`——只有第 3 档才提交原版云 quad，第 1 档走 `program/deferred1.glsl:388-390 DrawCloudSkybox()`，第 2 档走 `:392` 起的 raymarch。**0 档整趟云几何被 discard，最低档不是"少采样"而是"不画"**。
- **shadowcolor 有非零清屏色**：`program/shadow.glsl:45 const vec4 shadowcolor0ClearColor = vec4(0.25,0.25,0.25,1);`，避免未写入 texel 读作纯黑。
- **焦散同样烘在 shadow 阶段，但内联不拆文件**：`program/shadow.glsl` 的 `GetWaterHeightMap()` 由 `:17 #ifdef WATER_CAUSTICS` 守卫、到 `:71 return noise * WATER_CAUSTICS_STRENGTH;`；fragment 段 `:119-150` 五次采样该函数（`h0` 中心 + 四向，`:124-128`）→ `:130-133` 四个方向差分 → `:135 height = max((xDeltaA * -xDeltaB + yDeltaA * -yDeltaB), 0.0)` 五点曲率 → `:137-140` 按 `WATER_NORMALS` 档乘 48.0/24.0 → `:147 height /= sqrt(height * height / 9.0 + 1.0)` 饱和归一 → `:149 albedo.rgb *= 1.0 + height;`，`:161-163` 另把 caster albedo `*= 0.25` 让加法项读得出来，`:165 gl_FragData[0] = albedo;`。⇒ 与 Solas 同一算法、**差别只在文件组织**：Solas 把它拆成独立的水焦散文件（见 §2.4），BSL 则整段留在 shadow 主体内、全包不存在对应的独立水焦散文件。
- **CPU 侧算角度**：`shaders.properties:145-159` `variable.float.*` 预计算 `timeAngle`、`shadowFade`。

**取舍原因**：BSL 是「Iris 专有特性的最大化利用」路线——它不用 `option.`/`slider.`，但把 `program.*.enabled`、`variable.float.*`、mipmap 借用像素这三件事做到了生态最完整。

**许可证**：All Rights Reserved → **只读思路**。可迁移的是：mipmap 测光结构、1 像素标量仓库、云阴影的 2D 廉价形态、bias 按 `2048/resolution` 归一、`CLOUDS=3` 退回原版的档位语义。

### 2.3 A3 Photon v1.3b

**组织**：503 GLSL / 25,503 行 / 821 include 边 / `#version 400 compatibility` ×323 + `430` ×6。`program.*.enabled` **69 条**（全场最多），`variable.float` 30 条。

**关键实现**
- **直方图自动曝光（本次样本里最完整的一份）**：`program/c4_taa_exposure.vsh:39-41` `K = 12.5; sensitivity = 100; calibration = exp2(AUTO_EXPOSURE_BIAS) * K / sensitivity / 1.2;`；`:83-92 build_histogram` 用 `const ivec2 tiles = ivec2(32,18)`，每 tile 一次 mipmap fetch；`:123-134 get_median_luminance` 走 CDF 取中位数；`:144 previous_exposure = texelFetch(colortex5, ivec2(0), 0).a;`；`:161-170` NaN 守卫 + **变暗/变亮不对称速率**。整套逻辑写在**顶点着色器**里，32×18 = 576 个 invocation 完成一次测光。
- **不依赖 sunPosition 的法线光向**：`include/lighting/directional_lightmaps.glsl:11-18` 用 `dFdx`/`dFdy` 从光贴图梯度反推方向。
- **PCSS**：`include/lighting/shadows/pcss.glsl:105-110` 本影宽度**决定抽数**（不是固定抽数），`:153-155` 全亮时早退。
- `include/utility/sampling.glsl:4-11` Vogel 圆盘。
- **G-buffer 位打包**：`program/gbuffers_all_solid.fsh:389 pack_unorm_2x8(...)`。
- **调色在 log2 空间**：`program/c14_color_grading.fsh:114-117` 以 0.18 为中灰做对比度；`:139-167` 在 sqrt 空间做 HSL 的 orange/teal/green 分裂。
- **大气散射是 A 组最重的**：M3「大气散射」命中 297（Astra 44），且云阴影命中 114。

**取舍原因**：Photon 明确按「现代 GL4 管线」设计，不背 OptiFine 包袱，所以能用 `texelFetch`、`textureGatherOffset`、SSBO 替代方案。它的测光是**中位数而非平均数**——这直接解决"屏幕上有太阳或月亮时平均亮度暴涨"的经典失效，是 Astra 若做曝光时必须采纳的性质。

**许可证**：自定义 LicenseRef → 除 `include/post_processing/aces/`（自带 AMPAS 许可，**可署名复用**）外全部按专有处理。

### 2.4 A4 Solas 3.7b

**组织**：369 GLSL / 14,066 行 / 554 include 边 / `#version 130` ×154 + `430 compatibility` ×9。**反例**：其 `lib/common.glsl` 单文件 2,091 行——作为对照，Astra 的 `Astra/shaders/lib/settings.glsl` 是 368 行，不需要担心走到这一步。

**关键实现**
- **焦散用五点曲率**：`lib/water/waterCaustics.glsl`（43 行）里 `getWaterCaustics()` 起 `:29`，五次 `getWaterHeightMap()` 采样 → 四个方向差分 → `:41 height = max((xDeltaA*-xDeltaB + yDeltaA*-yDeltaB) * 48.0, 0.0)`——离散拉普拉斯即曲率，曲率大处聚光；注入点 `programs/shadow.glsl:63-71` `if (mat == 10001 && lmCoord.y >= 0.01) { albedo.rgb = vec3(0.3 + caustics * 0.7 * WATER_CAUSTICS_STRENGTH); albedo.rgb *= lmCoord.y; }`。同样是**阴影阶段烘焙**。
- **色调映射算子把常数做成滑杆**：`lib/post/tonemap.glsl:2-6` Uncharted2 的 A/C/E 全部暴露为用户可调。RedHat 的同类实现是把 `A`/`B`/`C` 写成 `lib/defines/final.h:73-75` 的三个**全局可变浮点**（非 `const`），既不在 `shaders.properties:136` 的 `sliders=` 列表里、也不进任何 `screen` ⇒ 用户能调 `MAX_COLOR_RANGE` 却调不了曝光/黑电平/对比度（§2.10）。
- **profile 同时覆盖值宏与 Iris 全局**：`shaders.properties:14-17` 四条链式 profile。
- **体积云三级早退**：`lib/atmosphere/volumetrics.glsl:42-80` 封闭空间守卫 → 按射线进度改步数 → 透射率阈值跳出。
- **Voxy 白名单门**：`lib/common.glsl:810-901`。
- **DRM 指纹**：包根 `../drm/drm.readme`（不在 `shaders/` 内）+ `lib/util/drm.glsl:1` `#define SOLAS_BY_SEPTONIOUS 1 //[1]`——**该宏绝不应出现在 Astra 任何文件里**，这是取证锚点。
- **V3.7b VL 水下分支完全重写**（`lib/atmosphere/volumetrics.glsl`，305 行取代 2.2b 的 127 行）：水下强度曲线 `intensity = (1 + 2·VoL²)·(0.25 + 1.75·sunVisibility)`——VoL 以**平方软瓣**进入且基线为 1（**永不归零**），只由太阳可见度定总量。2.2b 把空气与水下共用 VoL 硬门，正是「正午水下光带恒零」的病根；官方在 3.7b 按同一诊断改掉了。水下放宽朝上惩罚（VoU 因子有 0.125 地板）；光带走透明阴影彩色透射（`shadowCol²·mix(0.25, waterColor·len, 水下)`）；采样改**指数距离分布** `exp2(dither)` 每样本 ×2（1,2,4,8… 格，7 样本覆盖 64+ 格）；运行时采样数 `sampleCount = VL_SAMPLES + int(sunVisibility·(4−dfade·3+wetness·3))`。
- **waterFog 谱序吸收**：`lib/water/waterFog.glsl:4-6` `colorMult.r *= (1-abs)`、`colorMult.g *= (1-abs²·0.5)`、`colorMult *= (1-abs³·0.5)`（第三条无 swizzle，是三通道共有衰减）。净透射 r: (1-A)(1-0.5A³)、g: (1-0.5A²)(1-0.5A³)、b: (1-0.5A³)；A ∈ (0,1) 全程 r < g < b ⇒ 红衰最快、蓝衰最慢，物理正确。`WATER_FOG_EXPONENT = -2.00`（`lib/common.glsl`）确保 absorption ∈ (0,1)。
- **焦散新增三档质量模式**：`lib/water/waterCaustics.glsl` 核心仍是 5-tap 曲率法（Astra 已移植），但 `getWaterHeightMap` 新增 `WATER_NORMALS 1/2/3` 三档——2/3 档改采 .r 通道、平方增强与各向异性剪切，用更少纹理通道换不同细节/成本档。Astra 焦散目前单档——若要加质量档，这是现成范式。
- **VL 颜色随时刻向天空色混合**：`lib/atmosphere/volumetrics.glsl:131` `vlCol = fmix(lightCol, nSkyColor, timeBrightness·0.75)·0.1`——正午光带偏白、晨昏偏暖。

**许可证**：All Rights Reserved → 只读思路。特别提示：不得引入其 DRM 宏、不得复用 `lib/water/waterCaustics.glsl` 的表达式形状（曲率思路可用，系数与写法必须自写）。

### 2.5 A5 Mellow 3.4 —— **MIT，可署名复用**

**组织**：381 GLSL / 7,135 行（**行数低于 Astra 的 9,804，文件数却更多**）/ 436 include 边 / 注释比 0.362 / `#version 400 compatibility` ×280。`program.*.enabled` 52 条。

**关键实现**
- `global/lighting/shadows.glsl:44-46`：**每个 tap 各自重算畸变**（而非一次投影后线性外推），这是斜率大处不漏光的正确解法。
- SMAA 命名命中 22 处，为本次样本最高，但**不是唯一**：RenderPearl 18、Noble 1，其余 16 款为 0。Astra FXAA/SMAA 均 0。
- 白平衡/LUT 命中 62（全场最高一档），Oklab 感知色空间工具。
- 相位函数、Vogel 圆盘、`get_min_light`（绑定 `screenBrightness`/`nightVision` 求屏幕最暗值，用于曝光下界）等小件均为独立可摘取函数。
- **`global/configurations.glsl:19-26` 的 buffer 格式声明整块在注释里**（与 §2.19 VanillaPlus、§2.12 Sildur's 同一失败模式）——Astra 不存在此问题（见 §2.9 与 §6 P2-11）。

**许可证**：**MIT**。→ 可按 `Astra/THIRD-PARTY.md` 登记后**署名复用**，需在 `lib/vendor/` 保留原始 MIT 文本。仍建议只取"小件"（相位函数、Vogel、Oklab、`get_min_light`、CAS），避免成模块搬运造成理解债。

### 2.6 A6 I Like Vanilla v1.4.4

**组织**：358 GLSL / 22,802 行 / **1,433 include 边（全场最高）** / `#version 140` ×252 / **`#if` 分支 2,243（全场最高，Astra 为 88）**。

**关键实现**
- **稀疏 profile，`-1` = 不动用户当前值**：`shaders.properties:154-159`。这是 Astra 档位设计最该抄的一条语义（§6 P0-1）。
- **profile 切换编译期 buffer 尺寸**：`:208-225`，同一份代码在不同档下 `colortex` 尺寸不同。
- **双后端而非砍功能**：`basics/settings.glsl:1-3 MODERN_BACKEND`——旧后端**重算缺失的 uniform**，而不是关掉依赖它的特性。
- **mipmap 测光**：`program/composite20.glsl:11 colortex0MipmapEnabled` + `:202-208` 顶点着色器求曝光 + `:160` 以标量注回片元。M3「自动曝光命名」命中 55，全场最高。
- **五级阴影过滤**：`lib/lighting/fsh_lighting.glsl:90-187` 预计算 `vec3(x, y, weight)` 采样表并**在注释里写出显式权重和**（3.584 / 7.472 / 15.239，用于归一化验证）；`:83 bias = 0.0002 + lViewPos*0.035/shadowMapResolution`——bias 与分辨率解耦。
- **代码生成的方块 ID 表**：`generated/common.glsl:1-3`，由 `cargo run -- rebuild_ids` 生成。
- **反模式**：四份 `style_*.glsl` 各 2,063 行的差分副本——同一美术意图养出四个版本。

**许可证**：What42's Shader License 2.2 → 按专有处理，**只读思路**。`-1` 语义、双后端"重算而非关停"、bias 解耦形式均可迁移（表达式自写）。

### 2.7 A7 Noble 1.9.8hf —— **GPL-3.0-only，必须重写**

**组织**：404 GLSL / 15,193 行 / 540 include 边 / `#version 430 compatibility` ×322（全场唯一纯 430 主流）。**`size.buffer.` 42 条（全场最高）**、`float16` 命中 57、白平衡/LUT 183。

**关键实现**
- `include/utility/phase.glsl:34-68` 归一化相位函数库（HG / Schlick / 混合，全部能量归一）。
- `include/atmospherics/fog.glsl:496-527` **CDF 反演步进** + 光谱 MIS 权重做水体雾——这是本次样本中最强的水下雾模型（Astra 已有逐通道 absorption，见 §7 的"不学"说明）。
- `include/atmospherics/clouds.glsl:194-196/283/285` 三级早退（天气图 → 按射线进度改步数 → 透射率阈值）。
- `include/fragment/shadows.glsl:28-92` `traceContactShadows()`，`DDA setup` 注释在 `:36` 明示依据 McGuire & Mara (2014)（**公开论文算法，可据论文自写**；同一 DDA 亦见 `include/fragment/raytracer.glsl:23` 的完整引用行）。
- `include/utility/transforms.glsl:98-103` `getShadowBias()`——畸变感知的 log2 法线偏移，`biasAdjust = log2(max(4.0, shadowDistance - shadowMapResolution * 0.125)) * 0.1`。
- `include/post/grading.glsl:201-221` CAT02 von-Kries 白平衡。
- `include/post/exposure.glsl:57-70` **SSBO 或纹理两条后端藏在同一个宏后面**——同一份上层代码，切换存储介质。
- `shaders.properties:347-353` **滑杆直接驱动 `size.buffer.colortex12`**：用户一个旋钮改变缓冲分辨率。
- `prelude` 式跨阶段宏 `SCREEN_COORDS`；`include/utility/primitive_types.glsl` 173 行 16/8-bit 兼容层。
- **可维护性代价**：`shaders.properties:61-65` 五条 profile（POTATO/LIGHT/MEDIUM/HIGH/ULTRA）**全部平铺、零继承**，每条重复列 **25 个赋值 token**——改一个跨档公共值要动 5 行。对比 §2.1 Complementary 的 14 token/条与 §2.4 Solas 的链式继承，Noble 是"最宽且最重复"的一端。

**许可证**：**GPL-3.0-only → 传染性；Astra 现有 ARR + 专有移植结构与之不相容。禁止复制任何一行，包括相位函数与 DDA——两者都有公开论文可依，须据论文自行实现。**

### 2.8 A8 Bloop 1.8.0-Alpha-3 —— **CC-BY-NC-SA-4.0，硬阻塞**

**组织**：393 GLSL / 23,678 行 / 680 include 边 / `lib/`（按子系统 clouds/fog/lpv/rtao/shadows/ssr/taa/water）→ `program/` → `world*/` 壳。`variable.float` **112 条（全场最高）**、`break` 82 处（全场最高）。**包内无任何许可证文件**。

**关键实现**
- **百分比渲染分辨率走顶点着色器**：`program/fog_translucent_lowres.vsh:20 gl_Position.xy = (gl_Position.xy*0.5+0.5)*(0.01+VL_RENDER_RESOLUTION)*2.0-1.0;`，`VL_RENDER_RESOLUTION` 是 `[-100, 100]` 连续滑杆（`lib/settings.glsl:9`）——**1% 粒度，不需要 `size.buffer`**。这是本次调研对 Astra 最实用的一条低配机制。
- **遮挡物搜索与 PCF 融进同一循环**：`lib/shadows/shadowfunc_advanced.glsl:73-85`，`weightScale` 随 `i` 递增 ⇒ 半径渐进放大，一趟完成两件事；`:179-184` `slopeBias` × `distortStrength` 双感知 bias 且**显式对齐 texel 单位**（`INV_SHADOW_RES`）。
- `lib/shadows/shadow_misc.glsl:13 tapLocationBlueNoise` 蓝噪声旋转，一次 sin/cos 完成盘上取点。
- **整文件替换做质量降级**：`program/lighting.fsh:37-48`（`SHADOW_FILTERING`）、`:50-56`（`SSR_QUALITY` 0→normal、1→extra_low、2→low、3→hq，**命名与数值非单调**）。
- **运行时从 CIE 色度坐标构建 RGB↔XYZ**：`program/final.fsh:107-122`（公开算法）。
- **Purkinje 杆/锥夜适应**：`program/final.fsh:429-440` `rodMix = mix(1.0, lumScotopic/(1.0+lumScotopic), 1/(1.0+Purkinje_strength))`，`scotopicTint = vec3(0.2,0.5,1.0)`——直接对应 Astra 的夜间/水下色偏过渡。
- **世界壳传参**：`world0/deferred10.fsh:1` `#define OVERWORLD` + `#define altnoise` 让**一份 `program/lighting.fsh` 服务全部 gbuffers 变体**。但全仓 0 次使用 Iris 内置的 `WORLD_OVERWORLD`/`DIMENSION_OVERWORLD`，维度语义完全自造。
- `shaders.properties:21` 是 `iris.features.optional = REVERSED_CULLING COMPUTE_SHADERS CUSTOM_IMAGES BLOCK_EMISSION_ATTRIBUTE ENTITY_TRANSLUCENT`——**`optional` 而非 `required`**，即这五项缺了整包仍然加载，只是相应特性静默失效。
- 有 `.clang-format`（`BasedOnStyle: Microsoft`、`ColumnLimit:0`、`IndentPPDirectives: BeforeHash`）。Astra **没有任何格式化工具链**。
- **反模式**：5 个文件名带 `copy` 的僵尸源文件；成批空条件块；`shaders.properties:197` 一条 1,106 字符 `sliders=`，77 个 token 里只有 71 个不同——`SATURATION`、`EXPOSURE`、`CONTRAST`、`SHOULDER`、`MID_IN`、`MID_OUT` 各重复列了一次。档位侧同样是平铺：`:232-239` 八条 profile（POTATO→EXTREME）**零继承**，每条 496–513 字符、合计 4,031 字符，改一个共享开关要改八行。

**许可证**：**CC-BY-NC-SA-4.0 且包内无许可证文本 → 对 Astra 是双重硬阻塞**（NC 与发布意图不相容；SA 与 GPL/ARR 结构互斥；连"保留署名"都没有可抄的原文）。**全部必须重写。** 例外：`program/final.fsh:107-122` 是 CIE/标准色彩学公开算法、`lib/encoding.glsl:22-29` 的 `packSnorm4x8` 是 HLSL 内建函数的语义规格、`lib/noise.glsl:79-85` 带 Vlachos 2016 论文出处——这三件可依公开规范自行实现，与 Bloop 无关。

### 2.9 A9 RenderPearl 2.8.0-beta.4 —— **MIT，本次最可直接复用**

**组织**：352 GLSL / 6,519 行（**A 组最小，且比 Astra 小 34%**）/ 476 include 边 / **0 个维度目录**（用 `world_default/` 与 Iris 维度选择器）/ `#version 460 compatibility` ×1 + `460 core` ×1（全场最高版本）。`float16` 命中 **607（全场最高）**。

**关键实现**
- `prelude/compat.glsl:14-249`：**本次样本中最强的驱动兼容层**——三级扩展开关、`IRIS_VERSION >= 10902` 版本门、为 glsl-transformer bug 显式 `#undef INT16` / `#undef INT8`。
- `lib/material/specular.glsl:24-37 gen_roughness` 与 `lib/material/normal.glsl:18-41 gen_normal`：**没有 LabPBR 贴图时从材质/光照贴图程序化生成高光与法线**——这是"资源包缺图即退化"的正解。
- `lib/srgb.glsl:11-25` 无分支的分段 sRGB 精确实现。
- `lib/tonemap.glsl` 5 个算子，**每个都就地内嵌上游许可文本**。
- `lib/sm/distort.glsl:3-31` Fernández-Guasti squircle 畸变函数。
- `lib/light/shadows.glsl:99-115` 用勾股恒等式一次算出"法线偏移 + 斜率深度偏移"双量，配合 Chebyshev 距离淡出。
- `world_default/setup.csh:3-12` 用 `#warning` 做加载器探测。
- `prelude/lib.glsl:69-84` lumen/lumi 物理单位阶梯。
- **反模式**：`lib/light/shadows.glsl:4` 注释自嘲 "Terrible generated versions of sample_sm"，随后 8 份手工副本。

**取舍原因**：RenderPearl 的定位是「在低版本 GL 与残缺驱动上尽量拿到现代管线能力」，所以它最厚的部分不是特效而是**兼容层与退化路径**。Astra 同样要面对 Iris/OptiFine、glsl-transformer、AMD/NVIDIA/Intel 三驱动，这份经验完全适用。

**许可证**：**MIT** → 可署名复用；建议在 `Astra/shaders/lib/vendor/renderpearl/` 保留原文并在 `Astra/THIRD-PARTY.md` 登记。`lib/tonemap.glsl` 内联的各家上游许可文本值得作为 Astra 的引用格式模板。

### 2.10 A10 RedHat 34.3.1（Chocapic13 谱系）

**组织**：133 GLSL / 15,902 行 / **include 边仅 129**、注释比 **0.560（全场最高）**、最长行 3,910。**按 pass 拆设置头**：`lib/defines/*.h` 共 21 个文件 870 行 = 全包 GLSL 的 5.5%，却占约 40% 的 include 边。最热 include 是数据头 `/lib/color/sunlight.glsl` ×12。

**关键实现**
- **烘焙的不是 LUT 而是滑杆**：`lib/color/data/` 下 `lib/color/data/data1.glsl` 至 `lib/color/data/data4.glsl` 四个文件合计 **410,486 字节 = 整包的 38.3%**，内容是 75 条 GUI 自动生成枚举（`lib/color/data/data1.glsl:2`，行长 3,910）。真正的编译期表在 `lib/color/sunlight.glsl:1-34` 的 `const ivec4 ToD[25]`，读点 12 处（如 `program/composite.glsl:944-951`）。**收益**：片元级逐小时日光色零纹理抓取、零上传、用户可在 GUI 直接改；**代价**：包体 38%、四份里三份永不进编译单元。
- **体积光 = 沿光线步进采样阴影图本身**：`program/composite.glsl:478-536 GetVolumetricRays()`，`vl.Quality = 4.0/VL_QUALITY`（`:482`）、有序抖动起始步（`:484 find_closest`）、`vl.pushback = vec2(0.001,-0.001)`（`:493`，原注释 "Fixes light leakage from walls"）、撞不透明即 `break`（`:499`）、每步一次 `shadow2D` 比较（`:526`）。**不新增深度 pass、不建体积 buffer。**
- **阴影视锥外的接缝法**：`:711-727` UV 出界时不丢阴影，夹到 `[0.02,0.98]` 再 `smoothstep` 混到天光。
- **斜率相关深度偏移与畸变因子绑定**：`:662-664 diffthresh = pow(distortFactor*1.2,2.0)*(0.25/148.0)*tan(acos(abs(NdotL))) + ...`，并对半透明与细几何分别放宽。
- **`eyeAdapt` 作为 varying 在 composite 算一次、final 用**：`:981` → `program/final.glsl:17,359`——避免逐 pass 重算整条天空积分。
- **无 TAA / 无 FXAA / 无 SMAA / 无抖动重投影**；无 GGX（只有水面的 Blinn_Phong，`:833`）；水下**无逐通道吸收**（全包 `absorption` 命中 0）。

**编译单元结构（此处更正本报告的早期判断）**：`final.fsh:26` 先 `#include "/lib/defines/final.h"`、`:28` 才 `#include "/program/final.glsl"`，而 `lib/defines/final.h:73-75` 以全局变量声明了 `float A = 1.5; float B = 0.35; float C = 0.07;`——因此 `program/final.glsl:286-294`（默认 `lib/defines/final.h:63 #define TONEMAPPING 1` 分支）里的裸名 `A`/`C` 是**有声明的**，本报告早期把它记作"默认色调映射分支走不通的出厂缺陷"是**误判，现予撤销**。顺带一条：`A`/`B`/`C` 不在 `shaders.properties:136` 的 `sliders=` 列表里，是写死的全局量，单字母名 + 无滑杆 = 可读性问题，不是编译问题。

**这套入口模式的真实代价（实测）**：三个维度入口 `final.fsh` / `world1/final.fsh` / `world-1/final.fsh` **各 28 行**、只换两个 include 路径；被指向的三份主体 `program/final.glsl` 751 行、`program/nether/final.glsl` 757 行、`program/end/final.glsl` 611 行，其中主世界与地狱两份 **`diff` 仅 6 行**——地狱版多出的有效代码只有 3 行色调偏移（`color.r*1.09+0.07*0.7` 等）。配套设置头 `lib/defines/final.h` 与 `lib/defines/nether/final.h` **字节完全相同**（`diff` 无输出），只有 `lib/defines/end/final.h` 有差异。即：**为 3 行差异复制了 757 行主体 + 74 行设置头**。这正是 Astra §6 P1 档位继承改造要消除的那类成本。

**许可证**：Chocapic13 Agreement，`:13` 要求再分发必须改名「`-名称- (Chocapic13' Shaders edit)`」→ **Astra 不可能满足该命名要求**，因此全部按"读思路、重写表达"处理。§6 的夹 UV 接缝法、斜率偏移分层属思想级可用；任何 `diffthresh`/`eyeAdapt` 表达式逐字搬运都会触发 `:12`/`:15`。

### 2.11 补偿 · LIGHT 1.8.0

**组织**：**include 边 = 0**（复核：`grep -rh '#include' --include=*.fsh --include=*.vsh . | wc -l` = 0）。72 份 `#version 120` + 4 份 `330 compatibility`（后者全为 Physics Mod 桥接文件）。`shaders.properties` **仅 30 行、整包只有 1 个滑杆**（`:31 sliders=shadowDistance`）。

**量化的代价**：14 个文件在三维度**字节级完全相同**，三目录合计 11,550 行中 **4,658 行（40.3%）是逐字副本**；许可证正文就地复制进 72 个文件共 1,461 行（11.3%）；`float waterH(` 出现在 6 个文件、`SHADOW_QUALITY` 阶梯 16 个文件、`SHADOW_MAP_BIAS` 19 个文件、`// VOID MAIN` 横幅 355 处。

**最危险的证据：复制后静默漂移。** `composite.vsh` 与 `final.vsh` 全文只差 80 行，即约 230 行天空/眼睛适应模型被抄了两遍且**关键参数不同**：`composite.vsh:260` `eyeAdapt = log(clamp(luma(avgAmbient*eyebright),0.125,60.0))/log(2.0)*0.45;` vs `final.vsh:269` 同式但 `0.125,48.0` 与 `*0.8`；`:257` 与 `:266` 的月夜光差一个 `12.` 增益。**同一场景在 composite 与 final 里用的曝光参数不一致。** 另有 `Uncharted2Tonemap` 定义两遍（`composite.fsh:291` 与 `final.fsh:188`）常数组不同、只有前者被调用。

**关键实现（值得学的四条）**
- **1 像素太阳遮蔽 + alpha 广播**：`composite.fsh:423-433` 仅在 `texcoord.x < 0.002 && texcoord.y < 0.002` 的那一个像素里做 13×13 深度遮挡统计 → `:582 gl_FragData[0] = vec4(color, gr)` 写入 `DRAWBUFFERS:4` → `final.fsh:329 texture2D(gaux1, vec2(0.0015)).a` 读回。**不需要 compute、不需要 custom image、不新增 pass。**
- **材质标志编码进法线模长**：`composite.fsh:470 length(normal) > 0.94 && < 0.96` 判水、0.96–0.98 判冰（原注释 "material properties are stored into normal length"），**省一张 MRT**。
- **解析式眼睛适应放在顶点着色器**：`final.vsh:261-270`，零屏幕读取、零降采样。
- **球形（非 AABB）历史裁剪**：`composite1.fsh:135-143`，以及"手与 vanilla 日/月四边形必须不被 TAA 碰"的深度名单 `:110-117`（阈值 `0.56`）。
- 其余：`gbuffers_terrain.fsh:96-109` 单图径向对数畸变 + 4 抽硬件 `shadow2D`（实际 16 texel），`:104` 把滤波半径与 `rainStrength`/材质耦合；`gbuffers_terrain.vsh:138` 用 `vec4(50,62,76,89)-mc_Entity.x` 的**乘积判等**代替 4 次比较，`:135-136` 火把光强用解析式而不依赖 OptiFine 的 block.properties 机制（本包确实也没有 block.properties）。

**必须纠正的三条前提**：LIGHT **没有级联阴影**（`cascade|texArray|shadowInterval` 全 0 命中）；**没有色散**（`dispersion|chromat|prism|IOR|Abbe` 全 0）；其 TAA **不做亚像素抖动**，只用于抗水面/阴影闪烁。

**许可证**：Chocapic13 Sharing Agreement → 只读思路。`physics_ocean.fsh:6-8` 自陈波浪库上游是 `github.com/haubna/PhysicsMod`（**不是 Chocapic13**），且 `:9-10` 声明波形"has to stay identical because it is also evaluated on the CPU side"——属第三方 ABI；Astra 若做 Physics Mod 适配应对接上游，不要从 LIGHT 复制。

### 2.12 补偿 · Sildur's Vibrant 2.02

**组织**：完全扁平，129 GLSL / 18,530 行 / 111 include 边**只指向 4 个目标**，其中唯一公共头 `shaders.settings` 被 `#include "/shaders.settings"`（31 处）与 `#include "shaders.settings"`（62 处）**两种路径写法指向同一物理文件**。按 `#define <tag>` 选段载入，`:16,50,64,85,95,109,114,134,138,158,180,185` 共 12 段。

**这套组织法可量化的代价**：同一选项多段各写一遍（`#define Clouds 3` 在 `:56` 与 `:86`；`#define Refraction` 在 `:117` 与 `:166`）；4 行 TAA 抖动表被复制进 **45 个文件**（≈225 行）；14 行许可 banner 进 109 个文件（≈1,526 行，8.2%）；三份维度整包复制 = root 6,015 / world-1 6,030 / world1 6,034，合计占全包 **97.6%**；`gbuffers_block_translucent.fsh:1` 全文只有一行 `#include "gbuffers_entities_translucent.fsh"`——看着 DRY，但 `shaders.properties:16-19` 恰好需要按 pass 分别关停。

**关键实现**
- **两段式 PCSS（本包皇冠）**：`gbuffers_textured.fsh:101-122 funPCSS()` 逐片元搜遮挡物得 `pdepth`，**塞进已有法线缓冲的未用分量** `colortex2.b`（不额外开图）；`deferred.fsh:551-574` 把 `pdepth` 换成 `rdMul` 变半径，`:561 bias = distortThresh*0.0001666667*threshMul`（`distortThresh = (sqrt(1-d²)/d+0.7)/distortion`，即 `tan(acos(NdotL))` 形态）。
- **对数畸变的远端系数按影距归一**：`shaders.settings:39-45` `a = exp(Nearshadowplane)`；`b = (exp(Farshadowplane)-a)*shadowDistance/128.0`；`utilDistortion(vec2 p) = 1.0/(log(length(p)*b+a)*k)`（`k = 1.801`）。**先除 128 再乘 shadowDistance ⇒ 拉大影距时近端 texel 密度不被稀释。**
- **反射路径八度减半并重归一**：`deferred.fsh:337+ int maxOctaves = isReflection ? 2 : 4;` + `if (isReflection) noise *= 1.2; //normalize noise scale when skipping octaves`；八度指数与权重预计算成 `vec4 stepsScale = vec4(0.6,1.7142,4.8996,13.999)` / `stepsWeight = vec4(1.0,0.4493,0.2019,0.0907)` 并**在注释里写出推导公式**（`exp(j*1.05)*0.6` 与 `exp(-j*0.8)`）。
- **均值/方差时域裁剪**（非 AABB）：`composite2.fsh:111-116` `mu`、`sigma = sqrt(max(...-mu*mu,0.0))`、`varianceScale = 1.25 + clamp(rej*0.55,0.0,0.55)`；另有 YCoCg 工作空间、`wCurrent/wHistory` 亮度加权历史、按材质的 `noSharpen` 跳过。
- **焦散域扭曲**：`gbuffers_water.fsh:298-327` 3 次 `abs(sin(p.x + cos(p.y)))` 型扭曲，每次 `p *= rmatrix(2.1 + float(i)*0.14)` 旋转。

**必须纠正的前提：本版没有包内四档。** `profile.` = **0**、`option.` = 0、`tweak.` = 0、`size.buffer.` = 0。Seus/Sildur 的 lite/medium/high/extreme 是**四个独立下载包**（外部预编译）。本版唯一真正落地的"档位"是 `shaders.properties:9-13` 的 `program.X.enabled=<布尔表达式>`。⇒ **Astra 的 3 条稠密 profile 应往 ILV 的稀疏覆盖方向改，不是往 Sildur 的散文注释方向改**（`shaders.settings:37-41,70` 那种 `6=lite, 8=med, 10=high, 12=extreme` 的注释——而且 `:37` 把 `80` 写了两遍）。

**死代码陷阱**：被广泛引用的 G-buffer 格式表 `gbuffers_textured.fsh:23-34` **整块在 `/* */` 里**，因此 `colortex1Format = RGB8`、`colortex2Format = RGB16F`、`colortex4/5/6Format = R11F_G11F_B10F`、`shadowHardwareFiltering0/1`、`sunPathRotation = -40.0` **全部不生效**，且在 `world-1/`、`world1/` 又各复制一份（21 处命中全是同一注释块）。全包唯一生效的缓冲声明是 `composite2.fsh:30 const bool colortex7Clear = false;`。

**许可证**：All Rights Reserved（banner 明写于 `shaders/shaders.settings:9-13`）→ 只读思路。PCSS（Branch & Segal 公开论文）、log-distortion（Seus 时代通用技巧）、方差裁剪（Intel/Ubisoft 公开论文）均可取；Sildur 自调的 Uncharted2 常数组与 4.7/15.2 硬编码**不得照搬**。

### 2.13 B1 MakeUp - Ultra Fast 9.5e

**组织**：317 GLSL / 10,674 行 / 486 include 边 / `#version 120` ×210。`shaders.properties` 342 行、`variable.float` 19 条。

**关键实现**
- **单目标 G-buffer**：`src/writebuffers.glsl:3,6,26` 只写 `/*DRAWBUFFERS:1*/`——整个延迟路径压在一张图上。
- **顶点着色器 mipmap 测光**：`common/composite_vertex.glsl:74-87` `log2(min(viewWidth,viewHeight)) - 1.0` 取最高 mip，`mix(exposure, prev, exp(-frameTime*1.25))` 平滑，配 `common/composite_fragment.glsl:2 colortex1MipmapEnabled = true`。
- **一个滑杆驱动五个常数**：`lib/config.glsl:208-311` 单个 quality 值同时决定 `shadowMapResolution`（300→4080）等五组量——**用户不需要理解五个旋钮的相互作用**。
- `shaders.properties:44-47 program.shadow.enabled=SHADOW_CASTING` 一条关掉整趟阴影渲染。
- `lib/shadow_frag.glsl:10-31` 4 抽硬件 PCF；`src/shadow_src_vertex.glsl:22` **顶点侧**做距离自适应斜率偏移。

**许可证**：**LGPL-3.0-or-later**。GLSL 的 `#include` 是文本展开，编译单元即派生作品 → 与 Astra 的 ARR 结构不相容，**按不可复用处理**（与 GPL 的区别在于 LGPL 允许链接隔离，但 shader 的 include 模型不提供隔离边界）。思路可迁移。

### 2.14 B2 E-LITE ELT511

**必须纠正任务前提**：E-LITE 不是"在同一代码上继续向下砍"的实验——其 §0 自陈方向是**抬高上限**（在 MakeUp 基础上加效果），所以它作为 Astra 参照的价值是"低配包如何在不牺牲底线的情况下加东西"，而不是"如何砍得更狠"。

**关键实现**
- **焦散烘进 alpha**：`common/shadow_fragment.glsl:26,59-67` 写入 `shadowcolor.a`——与 Complementary/BSL/Solas 同一路线的第四例。
- **角度空间天光 LUT 复用 `gaux4`**：`common/solid_blocks_fragment.glsl:341-343` `vec2(atan(R.z,R.x)*0.1591549+0.5, acos(-R.y)*0.3183098+0.1)`——把方向向量直接当 UV，不建纹理。
- **逐维度 pass 关停**：`shaders.properties:43-46,79`，含 `program.world-1/shadow.enabled=false`（下界直接没有阴影 pass）。
- `lib/ao.glsl:8 clamp(AOSTEPS*RENDER_SCALE, 2.0, 10.0)`。
- **`RENDER_SCALE` 是死的**：`lib/config.glsl:272 #define RENDER_SCALE 1.0`，且其滑杆在 `shaders.properties:144` 被注释掉 ⇒ **推翻"低配包普遍用渲染缩放"这一假设**。

**许可证**：LGPL-3.0-or-later → 同 MakeUp，按不可复用处理。

### 2.15 B3 Miniature 2.19 —— **MIT**

**组织**：99 GLSL / **1,581 行**（全场最小完整包，为 Astra 的 16%）/ 116 include 边 / `#version 120` ×66 / 注释比 0.030（全场最低）/ 4 条链式 profile。

**关键实现**
- **原版光贴图当 LUT 用**：`common/getAmbientColor.glsl:2 texture2D(lightmap, vec2(AMBIENT_UV.s, skyLight))`——零成本获得天光色。
- **16 格量化 ⇒ 每 16 方块一次阴影采样**：`common/getLightStrength.fsh:11-12 bandify(..., SHADOW_PIXEL)`。这是全场最激进也最便宜的阴影降级。
- **与分辨率解耦、不需要法线偏移的 bias**：`:33 clamp(3.0*(shadowDepth - shadowUV.z)/shadowProjection[2].z, 0.0, 1.0)`——直接用投影矩阵的 z 分量归一，**不需要 `tan(acos(NdotL))`、不需要 sin/cos**。
- **一次法线抖动代替粗糙度锥**：`program/final.fsh:42-46`，高光只多一次采样。
- **无色调映射、无自动曝光、无 TAA**（M3 对应列全 0）。

**许可证**：**MIT，本次合规成本最低**——但**包内没有 LICENSE 文件**，Astra 若复用须自行撰写标准 MIT 声明并附来源 URL + 版本，登记进 `Astra/THIRD-PARTY.md`。

### 2.16 B4 VanillAA 1.3 —— **MPL-2.0（`bsl_lib/` 例外）**

**组织**：20 GLSL / **728 行**（全场最小）/ include 边 8 / `#version 120` ×14 / 注释比 0.358 / `shaders.properties` **11 行**。

**关键实现**：一份**最小的可用 TAA** = `shaders.properties:6` 一条 custom uniform + `composite.fsh:11 const bool colortex2Clear = false;` + `gbuffers_textured.vsh:51` 一行抖动，主循环 68 行；`bsl_lib/unsharp_mask.glsl:10,13` 锐化强度乘 `MC_RENDER_QUALITY`。
**MPL-2.0 是文件级许可**：根目录文件可复用，但 `bsl_lib/` 是 BSL 专有代码 → **该子目录必须重写**。

**该包给出的明确结论（本文采纳）**：**Astra 现在不应引入 TAA。** 触发条件是「当 Astra 开始使用随机/蓝噪声采样（PCSS、体积步进、SSGI）时，TAA 才成为必要」。在 Astra 当前确定性采样 + `break` 24 / `discard` 15 的形态下，TAA 是纯成本。

### 2.17 B5 Super Duper Vanilla 1.3.8

**组织**：327 GLSL / 12,296 行 / **1,123 include 边** / `#version 330 compatibility` ×240 / 5 条链式 profile / 40 条 `blend.*` + 30 条 `alphaTest.*` 全设 off（`:269` 注释 "set to maximize performance"）。

**关键实现**
- **阴影裁剪空间里做体积光**：`lib/rayTracing/volumetricLight.glsl`（整文件 65 行），光束块 `:38-56` 只有 19 行——7 步由 `:1 #define VOLUMETRIC_LIGHT_STEPS 7u` 决定，**全部矩阵变换外提在 `:40-45`**（`shadowProjection` × `shadowModelView` 各一次，端点差 `endPos` 已含 `volumetricStepsInverse`），循环 `:49-54` 的循环体仅两条语句：一次 `getShdCol` 采样 + `startPos += endPos`。`:50` 源码注释自陈 "No need to do anymore fancy matrix multiplications during the loop"。**这是 Astra 光束成本模型最该对齐的形态。**
- **bias 配方**：`lib/lighting/complexShadingForward.glsl:62-74` XY 偏移 ∝ `shadowMapPixelSize`、Z 固定 `exp2(-14)`，整段包在 `#if !defined HAND && !defined HAND_WATER` 里。
- **mip-8 平均亮度 + 历史存 (1,0) texel 的 alpha**：`main/composite6.glsl:168-178`（历史借用 `colortex5`）。
- **抽数依赖抗锯齿档位**：`lib/lighting/shdMapping.glsl:40-47`——`ANTI_ALIASING >= 2`（时域档）时阴影只取 1 抽，`#else` 取 2 抽，即时域与空间共用同一份采样预算。
- **水下焦散写在 shadow pass**：`main/shadow/shadow.glsl:161-177`（第五例）。
- **`gl_Position = vec4(-10)` 作废约定**：`main/shadow/shadow.glsl:107-111`，并写进 `DOCUMENTATION.md:47-48`。

**许可证**：FlameRender/TM Studios v1.6 §1.4 → 只读思路。

### 2.18 对照 · Just Colored Lighting 1.0.1

**定位**：功能面极窄的单一目的包，只做「带颜色的方块光」，靠 Iris LPV 体素场。292 GLSL / 23,603 行。**它是 Astra `Astra/shaders/global/lighting/blocklight.glsl`（191 行，已有 `BLOCKLIGHT_COLOR` 色调）的上限参照，不是下限参照**（下限参照是 §2.19 的 VanillaPlus）。

**关键实现（彩色方块光全链路）**
- **取色只要一行**：`shaders/voxelizing.glsl:277,280-284` `vec2 quad_center = (gl_TextureMatrix[0] * mc_midTexCoord).st;` 再 `textureLod(texture, quad_center, log2(float(textureSize(texture,0).x)))`——**取最高 mip = 整张贴图平均色**，零预计算、零图集元数据。
- **编码写入**：`voxelizing.glsl:391-415` `voxel_data = vec4(emmissiveness/15. * light_color.rgb, .43)`，alpha 塞不透明度类别码（`.31/.32/.33/.34/.35` 对应玻璃/楼梯类），再 `packUnorm4x8` → `:569 imageAtomicMax(cimage1, voxel_pos, integerValue)`。
- **传播**：`shaders/shaders/voxel_photons.csh:320-342` **6 邻域 `max()` 洪泛**（非加法 ⇒ 单趟只扩散一步，靠多帧收敛）；衰减两档：`:235-240` 线性 `-1/15` 或默认乘 **0.80/格**；`:259 glass_mult = vec4(voxel_data.rgb,1.)/max(max(r,g),max(b,.001))` 把**亮度与色度分离后再乘**，避免颜色越传越暗。双缓冲靠 `main_f.glsl:1570` 的 Y 维偏移实现乒乓。
- **采样**：`shaders/main_f.glsl:1593-1595` 先把法线转世界空间，再**沿法线偏移 0.9 格**采样 `foot_pos2 + .9*normals_world`——一行解决 LPV 最经典的「墙面/地板内侧体素全黑」。**这是全样本里最值得 Astra 抄走的单个想法**（若 Astra 未来走体素路线）。
- **降级兜底**：`:1796-1804` LPV 与原版光按 `torch_fade` 交叉淡入，出场即纯原版兜底 ⇒ 超出体素半径处自动回落。`:1793` 白天把方块光压到 0.20 且在日出日落窗口内衰减。
- **配置层控成本**：`shaders.properties:324-352` 用 properties 关掉 `prepare_a..d` 来削减洪泛趟数（默认每帧仅 1 趟），而非用 GLSL 分支。

**糟粕（对 Astra 有直接警示价值）**
1. `settings.glsl` 228,879 字节中 **195,952 字节（85.6%）是滑杆枚举列表**，真实内容仅 32,927 字节；最长行 **18,043 字符** = `:1237 #define BTIGHTNESS_CONTRAST 1.000 //[0.000 0.001 ... 3.000]`（0.001 步长 × 3,001 值）。⇒ 连带修正普查口径：`_meta/census.py:91` 把 `//[...]` 计成注释，所以 JCL 的"注释比 0.378"是统计假象（实测纯注释行比 0.139）。
2. `settings.glsl:944` 允许 `VOXEL_AREA` 开到 **1024** ⇒ `cimage1` 1024³ R32UI ≈ 4.3 GB + `cimage3_colored_light` 1024×2048×1024 RGBA8 ≈ 8.6 GB，合计 >12 GB 显存，且无任何范围告警——**一个把用户直接送进 OOM 的滑杆**。
3. `settings.glsl:26 #define KILL_SWITCH 0` 有正式 UI 文案（`lang/en_us.lang:371`）但**全包代码零读取**——「用户能调、调了完全没反应」比死代码更糟。
4. `main_f.glsl`（67 KB）被 **74 个 pass 各编译一遍**；gamma 在同一像素上最多被叠加三次（`main_f.glsl:2189-2191`、`:2193-2194`、`shaders/shaders/composite.fsh:549-574`），三处条件互不排斥。
5. `#version` 状态自相矛盾：90 个文件 `120` / 137 个 `430`，而 `world0/composite.fsh:1` 声明 120 后 include 的文件在 `:135/:145/:150/:159` 用 GLSL4 的 `texture()` ⇒ 120 是从模板继承的死壳。**Astra 不应模仿任何 `#version 120` 外壳。**
6. 死重量：`main_f (vx  try1 1 backup).glsl` 1,941 行随包发布 + 各 `bk` 备份，合计 2,353 行 ≈ 全包 10.1%。
7. `properties:398/:408 customTexture` 指向**其他光影包的命名空间**（`Icarus_shaders`、`simply_upscaled`），独立安装即失效。

**许可证**：ARR，且原文 "Do not steal any of this code or use \"code snippets\"" → **禁止片段级引用，只读思路。** 唯一例外性的可学之处是**组织手法**：`licensed/spaceConversions.glsl`（83 行，署名 Jessie-LC / open-source-utility-code）被放进**专用 `licensed/` 目录物理隔离并就地致谢**——这个做法应直接照搬为 Astra 的 `lib/vendor/` 规范（§6 P2-10）。

### 2.19 对照 · Vanilla Plus 3.3（已停更 18 个月）

**定位**：Iris-only 延迟渲染包，与 Astra 在「同等体量、同等目录分层」上最直接可比；净代码口径实测：

| 口径 | VanillaPlus | Astra |
|---|---|---|
| 文件 | 230 | 245 |
| 总行 | 11,388 | 9,804 |
| 其中许可头 | **4,384（38.5%）** | 0 |
| **净代码** | **7,004** | **9,804** |

⇒ **在净代码口径下 Astra 的文件更多、代码多 40%**。`_meta/census.py` 的行数统计对含大块 boilerplate 的包会系统性高估。

**关键实现（可迁移）**
- **水下消光在 shadow 阶段逐 texel 预计算**：`program/shadow/comp0.fsh:38-98` 比较 `shadowtex0`/`shadowtex1` 找透光方块、用 `shadowcolor1.x > 0.5` 标记，再把 Beer-Lambert 消光系数烘进 shadowcolor。**每 texel 一次、每帧一次、像素端零成本。**
- **一条指令拿 4 次硬件 PCF**：`program/gbuffer/forward.fsh:131-150 textureGather(shadowtex1, uv.xy, uv.z).wzxy` + `:95-97 const bool shadowHardwareFiltering = true;`（Astra 有同型路径但默认关闭，见 §6 P1-8）。
- **顶点着色器做自适应测光**：`program/grade/exposure.vsh:37-91` 瓦片化 + 中心加权 + `0.075/0.05` 非对称升降速 + `frameTime*rcp(0.033)` 归一，历史值放 `colortex4.a` 的 (0,0) 像素。
- **彩色方块光的下限**：`lib/fUtil.glsl:63-68` 一共 5 行——`color *= mix(sqr(normalize(color)), vec3(1.0), cube(intensity)); return pow5(intensity)*color;`，即取原版色调、按强度三次方向灰插值、五次幂衰减。无体素、无传播、全包 `voxelizeLightBlocks` 零命中。⇒ **对"彩色方块光"这个 Astra 议题，VP 是反面/下限参照，JCL 是上限参照。** 唯一可抄的是「用不同幂次解耦去饱和量与亮度」的一行式形状。
- **CPU 侧编排**：`shaders.properties:159 variable.int.fmod8 = frameCounter % 8` 把 8 方向 TAA 抖动表搬出 GPU；`:223-227` 用四条 `timeSunrise/Noon/Sunset/Night` 的 clamp 斜坡合成 `uniform.vec4.daytime`；`:230-244` `lightFlip`、云层光照翻转、月相平滑。
- **零成本资源复用**：`:138-139 texture.prepare/composite.colortex8 = minecraft:textures/environment/clouds.png` 把原版云贴图直接绑成彩色缓冲。
- **`lib/atmos/colorsDefault.glsl:29-34` `flat out mat4x3 lightColor; //Sunlight, Moonlight, Skylight, Blocklight`** + `:61-97` 六套 `colorPreset`——四行关键帧调色板插值，把美术调参与着色器逻辑彻底分离。

**致命缺陷（停更包的核心警示价值）**
1. **`lib/pipeline.glsl` 53 行整体被 `/* */` 包住**，既声明 `colortex0Format = RGBA16F` … `colortex11Format = R8`（`:2-12`）又写 C0–C11 用途清单，但只被 `program/grade/final.fsh:20` 包含进一个已是注释的位置。全包 grep `colortex[0-9]*Format` **只命中这一个文件** ⇒ **12 个缓冲全部运行在 Iris 默认格式上，省内存意图一行都没生效**。且 `:14-15` 连写两次 `shadowcolor0Format`。**教训：文档型清单必须与生效声明同体，否则必然腐烂。**
2. **用户可点出来的编译崩溃**：`program/grade/grading.fsh:123 #if (defined COLOR_SPACE_SRGB || defined COLOR_SPACE_DCI_P3 || …)` 这五个宏**在全包任何地方都无定义** ⇒ `:123-175` 共 53 行色彩管理永不编译；而实际生效的 `#else` 分支里 `:178 #define VIEWPORT_GAMUT 0 //[0 1 2]` 是**正式暴露给用户的选项**（`:67` 出现在 `screen.POST`，`lang/en_US.lang:230-234` 有完整文案），但 `:182`/`:186` 使用的 `sRGB_P3D65` 全包未定义（`:119` 定义的是 `sRGB_to_P3D65`）。⇒ **用户把 Display Gamut 改成 DCI-P3 或 Display P3 就让包编译失败。**
3. **同纹理读写**：`program/post/exposureDownscale.fsh:34-62` 读和写同一张 `colortex6`——明确的未定义行为。
4. **224/230 个文件各带 ~20 行许可头** = 4,384 行零信息复制；净 157,889 字节。许可合规不需要乘以文件数的副本。
5. **`worldN/` 不是派发器而是整段复制**：`world0/composite1.fsh` 536 行 / `world1/` 297 行 / `world-1/` 274 行，且**已各自漂移**（`diff` 显示 world1 缺 `uniform float wetness`、`sunAngle`、`lightFlip`、`vec3 cloudLightDir, cloudLightDirView`，整体缺 125–336 行的 `mieHG` + 云体积块）；`world0/composite2.fsh` **只存在于 `world0/`**——靠"文件缺失即不编译"来关掉下界/末地 godray，不可发现、不可维护。对比：Astra 的 `worldN/` 是 5.6 行/文件的纯派发器（`Astra/shaders/world1/composite1.fsh:1-4` = `#version` + `#define DIMENSION_END` + `#include "/program/composite1.fsh"`），维度差异靠 `#define` 传进单一真源，**明显优于 VP**。
6. **魔数 `0.56` 在两处重复且语义不同**（`program/post/temporal.fsh:53` 判"是否应用相机位移"、`program/deferred/ssao.fsh:60` 判手持物深度分界）；`lib/light/contactShadow.glsl` 127 行**整文件零消费者**（`getContactShadow` 全包只有定义处一处命中，且没有任何文件 `#include` 它）；`profile.Fast` 置位的 `cloudVolumeFastMultiscatter` 全包**只出现在 `shaders.properties:1` 那一行**——一个没有任何 GLSL 读取的孤儿 token，写了等于没写；维度差异还有一处**缩减副本**：`program/gbuffer/forward.fsh` 340 行被 20 个入口包含，`program/gbuffer/DIM/forward.fsh` 166 行仅被 `world-1/` 的 9 个 gbuffers 入口包含，两者共用同一套 `#ifndef gTRANSLUCENT` 结构与同一份 20 行许可头，下界版体量只有主世界版的 49% ⇒ 维度差异靠"另写一份短的"表达，而不是靠 `#define` 派发。
7. **未声明任何 `iris.features.required/optional`**（全包零命中），却大量使用需要较新 Iris 的机制 ⇒ 旧版 Iris 上报错点远离根因、不可诊断。

**许可证**：ARR + 自拟 EULA（`LICENSE` 4,095 B），§4 明确「即使只使用源码的一部分也需先取得许可」、§6 保留**单方面追溯变更许可**的权利——比一般 ARR 更硬的两条。且 224 个文件头写的是 "All Rights Reserved **unless otherwise explicitly stated**"，但全包没有任何一处「explicitly stated」例外 ⇒ 该 but-clause 目前为空，不能推定任何例外。**连 `img/noise2D.png`（246,073 B）都不得使用。**

**停更包给 Astra 的三条教训（本文采纳为 §6/§7 的依据）**
1. 放弃 OptiFine 兼容换来了干净架构，**也放弃了退路**：VP 用 0 个 `DRAWBUFFERS`、0 个 `#version 120` 与 `!token`/`variable.*`/`program.*.enabled` 把代码写成最好读的样子，但一旦生态变化连"降级到 OptiFine 慢慢修"的通道都不存在，也没用 `iris.features.required` 把依赖形式化。⇒ **Astra 与 VP 同侧**：实测 GLSL 侧 `IS_IRIS` **0 命中**，而 properties 侧 22 条 `variable.*` + 24 条 `uniform.*` + `profile.*`/`sliders=` + `:38-42` 的 `#if defined …#else…#endif` 全是 Iris 专属 ⇒ Astra **没有** OptiFine 退路，因此把依赖写成显式 `iris.features.required` 是必要补偿，别学 VP 的隐式假设。
2. **不可回归测试的代码一定腐烂成用户可触达的崩溃**（`VIEWPORT_GAMUT`）。⇒ Astra 值得投入一个最小的 `shaders.properties` 选项穷举编译脚本（本地手工跑也行），**优先级高于任何新特效**。
3. 许可 boilerplate 与文档型清单是两类**会独自腐烂的负债**。

---

## 3. 横向对比矩阵（本机实测，可复现）

四张表全部由 `光影包/_meta/matrix.py` 读取 `census.json` + `feature_matrix.json` + `pipeline_metrics.json` + `astra_census.json` 生成到 `光影包/_meta/matrix.md`，命令见 §9.1。**ASTRA 行是同一套脚本对本仓库 `Astra/shaders/` 的测量**，与参照包口径完全一致。M1 的「#version 分布」列按**文件**计数（每个 GLSL 文件的第一条 `#version`），因此各键之和小于「GLSL文件」列——差值是没有任何 `#version` 的纯 include 片段。

### 3.1 M1 · 结构与体量

| 包 | GLSL文件 | GLSL行 | 最长行 | 注释比 | include边 | 维度目录 | #version 分布 | props行 |
|---|---|---|---|---|---|---|---|---|
| Complementary R | 408 | 23660 | 723 | 0.099 | 800 | 3 | 130:213 400c:3 430c:3 | 968 |
| bsl-shaders | 277 | 17824 | 431 | 0.138 | 574 | 3 | 120:179 130:3 430c:3 | 790 |
| photon-shader | 503 | 25503 | 1551 | 0.244 | 821 | 3 | 400c:323 400:6 430:6 410c:3 430c:1 | 1074 |
| solas-shader | 369 | 14066 | 947 | 0.225 | 554 | 2 | 130:154 430c:9 | 1218 |
| mellow | 381 | 7135 | 1113 | 0.362 | 436 | 3 | 400c:280 430c:4 | 302 |
| ILV | 358 | 22802 | 1032 | 0.176 | 1433 | 3 | 140:252 430c:3 | 960 |
| noble | 404 | 15193 | 796 | 0.080 | 540 | 3 | 430c:322 | 534 |
| bloop-shaders | 393 | 23678 | 3623 | 0.163 | 680 | 3 | 140c:236 430c:7 150c:4 | 1101 |
| renderpearl | 352 | 6519 | 463 | 0.133 | 476 | **0** | 460c:1 460 core:1 | 322 |
| redhat-shaders | 133 | 15902 | 3910 | 0.560 | 129 | 2 | 130:86 | 193 |
| light-shaders | 76 | 12911 | 371 | 0.120 | **0** | 2 | 120:72 330c:4 | 32 |
| Sildur's | 129 | 18530 | 339 | 0.094 | 114 | 2 | 120:108 | 186 |
| MakeUp | 317 | 10674 | 928 | 0.180 | 486 | 3 | 120:210 | 342 |
| E-LITE | 342 | 15398 | 1020 | 0.140 | 798 | 3 | 120:202 130:8 | 492 |
| miniature-shader | 99 | 1581 | 118 | 0.030 | 116 | 3 | 120:66 | 77 |
| vanillaa | 20 | 728 | 196 | 0.358 | 8 | 0 | 120:14 130:2 | 11 |
| SDV | 327 | 12296 | 744 | 0.261 | 1123 | 3 | 330c:240 330 core:6 | 773 |
| JCL(对照) | 292 | 23603 | **18043** | 0.378† | 301 | 3 | 430c:109 120:90 430:28 | 1168 |
| VanillaPlus(对照) | 230 | 11388 | 531 | 0.101 | 292 | 3 | 400c:174 400:2 | 298 |
| Complementary U | 408 | 23660 | 723 | 0.099 | 800 | 3 | 130:213 400c:3 430c:3 | 968 |
| **ASTRA** | **245** | **9804** | **381** | **0.451** | **309** | **2** | **400:159 430:10 460:1** | **358** |

† 统计假象，见 §2.18 糟粕 1：`census.py` 把 `//[枚举]` 计成注释，JCL 实测纯注释行比为 0.139。

**读法**：Astra 处在「行数偏小、单行最短、注释第二厚、include 图适中」的位置。include 边/文件 = 1.26，与 Complementary 的 1.96、SDV 的 3.43、LIGHT 的 0 一起构成从"高度复用"到"零复用"的光谱——Astra 在这一维上属于复用充分的一侧。

### 3.2 M2 · 管线与 Iris 配置层

| 包 | `program.*`行 | `enabled=` | shadowcomp | 其他 |
|---|---|---|---|---|
| Complementary R/U | 9 | 9 | 3 | — |
| bsl-shaders | 24 | 24 | 3 | — |
| photon-shader | **69** | 69 | 3 | 全场最多 |
| solas-shader | 6 | 6 | 3 | — |
| mellow | 52 | 52 | 0 | — |
| ILV | 48 | 48 | 6 | — |
| noble / renderpearl / redhat / light / vanillaa / SDV | 0 | 0 | 0 | 完全不用 pass 级裁剪 |
| bloop-shaders | 34 | 34 | 3 | — |
| Sildur's | 9 | 9 | 0 | 9 条里 5 条是布尔表达式、4 条恒 `false` |
| MakeUp | 4 | 4 | 0 | — |
| E-LITE | 8 | 8 | 0 | 含 `program.world-1/shadow.enabled=false` |
| miniature-shader | 5 | 5 | 0 | — |
| JCL(对照) | 19 | 19 | 0 | — |
| VanillaPlus(对照) | 9 | 9 | 0 | — |
| **ASTRA** | **24** | **24** | **12** | shadowcomp 全场最多 |

**三条全场为 0 的事实（本身就是结论）**：`before=`（`program.X.before`）在 21 个集合中 **0 命中**；`slots.`/`view.` 在 shaders.properties 文件中 **0 命中**；`buffer/slots` 与 `custom通道` 两列全为 0 是因为本脚本只统计 properties 指令，custom image 的实测在别处（Astra 有 3 张自定义图像 + 9 个 compute 阶段，见 §4.2）。

### 3.3 M3 · 算法命中（已剥离 `//` 与 `/* */` 后计数）

| 包 | TAA | SMAA | FXAA | sampler2DShadow | shadow2D() | GGX | SSS | 大气散射 | Mipmap降采样 | 自动曝光命名 | 云阴影 | 焦散 | GodRays | HBAO/SSAO | 蓝噪声 | Bayer/IGN | ACES | Tonemap | 白平衡/LUT | sampler3D | Voxy | 视差 | 16F | RGBM |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Complementary R | 70 | 0 | 17 | 2 | 6 | 3 | 64 | 0 | 5 | 0 | 18 | 13 | 83 | 28 | 0 | 41 | 0 | 2 | 11 | 10 | 108 | 51 | 0 | 0 |
| bsl-shaders | 95 | 0 | 14 | 5 | 3 | 4 | 100 | 0 | 9 | 10 | 4 | 15 | 37 | 14 | 9 | 30 | 0 | 12 | 12 | 29 | 81 | 216 | 0 | 0 |
| photon-shader | 31 | 0 | 3 | 5 | 0 | 9 | 12 | 299 | 0 | 27 | 114 | 23 | 2 | 31 | 0 | 14 | 20 | 58 | 31 | 27 | 17 | 35 | 2 | 0 |
| solas-shader | 35 | 0 | 12 | 0 | 0 | 0 | 72 | 3 | 6 | 0 | 27 | 14 | 0 | 21 | 28 | 44 | 0 | 19 | 14 | 9 | 82 | 90 | 0 | 0 |
| mellow | 5 | 22 | 0 | 2 | 0 | 5 | 3 | 25 | 2 | 0 | 0 | 0 | 9 | 12 | 0 | 0 | 8 | 19 | 62 | 6 | 29 | 0 | 0 | 0 |
| ILV | 0 | 0 | 9 | 0 | 0 | 0 | 0 | 0 | 3 | **55** | 3 | 199 | 0 | 51 | 0 | 37 | 9 | 18 | 6 | 2 | 58 | 0 | 0 | 0 |
| noble | 28 | 1 | 0 | 0 | 0 | 8 | 89 | 144 | 0 | 2 | 16 | 16 | 0 | 42 | 6 | 34 | 19 | 17 | 183 | 4 | 51 | 27 | 57 | 6 |
| bloop-shaders | 16 | 0 | 0 | 2 | 1 | 1 | 88 | 55 | 10 | 0 | 36 | 53 | 8 | 6 | 38 | 3 | 0 | 15 | 70 | 12 | 65 | 12 | 0 | 2 |
| renderpearl | 0 | 18 | 0 | 1 | 0 | 4 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 11 | 9 | 1 | 16 | 0 | **607** | 0 |
| redhat-shaders | 0 | 0 | 0 | 3 | 23 | 0 | 52 | 0 | 12 | 38 | 0 | 104 | 20 | 11 | 0 | 0 | 0 | 48 | 15 | 0 | 0 | 4 | 0 | 0 |
| light-shaders | 9 | 0 | 0 | 18 | 72 | 0 | 9 | 0 | 0 | 33 | 0 | 16 | 5 | 0 | 0 | 0 | 0 | 9 | 84 | 4 | 0 | 0 | 0 | 0 |
| Sildur's | 121 | 0 | 0 | 12 | 4 | 0 | 3 | 0 | 0 | 18 | 0 | 33 | 19 | 9 | 0 | 0 | 0 | 9 | 26 | 0 | 59 | 27 | 0 | 0 |
| MakeUp | 0 | 0 | 3 | 8 | 17 | 0 | 0 | 0 | 3 | 0 | 0 | 0 | 10 | 11 | 0 | 0 | 0 | 0 | 23 | 0 | 65 | 0 | 0 | 2 |
| E-LITE | 0 | 0 | 9 | 7 | 21 | 0 | 0 | 0 | 3 | 0 | 0 | 7 | 14 | 20 | 0 | 0 | 2 | 6 | 31 | 0 | 153 | 0 | 0 | 2 |
| miniature-shader | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 0 | 0 | 0 | 0 | 4 | 0 | 6 | 0 | 0 | 0 |
| vanillaa | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| SDV | 1 | 0 | 1 | 2 | 0 | 0 | 6 | 0 | 2 | 8 | 0 | 19 | 0 | 15 | 0 | 0 | 0 | 10 | 9 | 1 | 0 | 59 | 0 | 11 |
| JCL(对照) | 0 | 0 | 0 | 0 | 0 | 0 | 43 | 0 | 0 | 4 | 2 | 5 | 37 | 82 | 2 | 0 | 0 | 43 | 53 | 13 | 65 | 0 | 0 | 0 |
| VanillaPlus(对照) | 0 | 0 | 0 | 2 | 0 | 3 | 0 | 37 | 1 | 4 | 0 | 0 | 22 | 6 | 25 | 11 | 0 | 4 | 8 | 0 | 0 | 0 | 0 | 0 |
| **ASTRA** | **0** | **0** | **0** | **2** | **0** | **0** | **11** | **44** | **2** | **0** | **0** | **21** | **22** | **0** | **0** | **5** | **6** | **36** | **22** | **4** | **7** | **5** | **4** | **0** |

**这张表必须连口径一起读**（§3.5）。它是**命名启发式**，不是功能普查：命中 0 可能表示"没有该功能"，也可能表示"有但用了别的标识符"。表内已被证实的两类误读：ILV 的「自动曝光命名」55 是真实命中，而 E-LITE / MakeUp 的同列 0 是**假阴性**——两者都有 mipmap 测光（`common/composite_vertex.glsl:74-87`、`lib/config.glsl`），只是没用自己的命名表里的词。因此该列只用于横向排序，功能存在性以 §2 的源码引用为准；结构侧信号看「Mipmap降采样」列（19 款里 11 款非零，加 Astra 为 13/21 个集合）。

### 3.4 M4 · 低配与配置密度

| 包 | `size.` | `view.` | profile行数 | profile继承行 | `sliders=` | screen块 | `variable.float` | break | discard | `#if`分支数 |
|---|---|---|---|---|---|---|---|---|---|---|
| Complementary R | 2 | 0 | 8 | 0 | 1 | 51 | 8 | 24 | 34 | 673 |
| bsl-shaders | 0 | 0 | 5 | **4** | 1 | 67 | 13 | 17 | 15 | 357 |
| photon-shader | 13 | 0 | 4 | 0 | 1 | 80 | 30 | 23 | 30 | 383 |
| solas-shader | 0 | 0 | 4 | 3 | 1 | 86 | 15 | 23 | 11 | 229 |
| mellow | 1 | 0 | 3 | 0 | 1 | 41 | 15 | 13 | 23 | 83 |
| ILV | 6 | 0 | 6 | 0 | 1 | 73 | 54 | 3 | 16 | **2243** |
| noble | **42** | 0 | 5 | 0 | 1 | 61 | 12 | 15 | 7 | 325 |
| bloop-shaders | 6 | 0 | 8 | 0 | 1 | 22 | **112** | **82** | 18 | 114 |
| renderpearl | 0 | 0 | 8 | 0 | 1 | 28 | 0 | **0** | 7 | 106 |
| redhat-shaders | 0 | 0 | 5 | 0 | 1 | 81 | 0 | 20 | 1 | 43 |
| light-shaders | 0 | 0 | 0 | 0 | 1 | 10 | 0 | 8 | 2 | 16 |
| Sildur's | 0 | 0 | 0 | 0 | 1 | 15 | 0 | 24 | 6 | 195 |
| MakeUp | 0 | 0 | 8 | 0 | 1 | 27 | 19 | 3 | 7 | 339 |
| E-LITE | 0 | 0 | 6 | 0 | 1 | 46 | 19 | 6 | 9 | 496 |
| miniature-shader | 0 | 0 | 4 | 3 | 1 | 8 | 0 | 1 | 3 | 28 |
| vanillaa | 0 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | 1 |
| SDV | 0 | 0 | 5 | 4 | 1 | 25 | 3 | 1 | 41 | 213 |
| JCL(对照) | 2 | 0 | 6 | 0 | 1 | 78 | 0 | 36 | 31 | 1265 |
| VanillaPlus(对照) | 3 | 0 | 3 | 2 | 1 | 43 | 34 | 11 | 13 | 34 |
| **ASTRA** | **6** | 0 | **3** | **0** | 1 | **8** | **18** | 24 | 15 | **88** |

**这张表里有三条与直觉相反的实测事实，必须写进结论**：
1. **`sliders=` 每个包都恰好 1 行**（21/21 个集合）——它是"哪些 token 用滑条渲染"的单条清单，不是每选项一行。任何"Astra 滑杆声明不够"的判断都是误读属性格式。
2. **profile 链式继承只有 5 个包用**（BSL 4、Solas 3、Miniature 3、SDV 4、VanillaPlus 2 行），**Complementary / Photon / ILV / Noble / Bloop 以及 Astra 全部是 0**。⇒ 链式不是全场共识，"没链式"因此不构成 Astra 的离群点；真正的离群点是**差量密度**：Astra 每条 profile 列出 67 个 token 而其中只有 **13 个**真正随档变化（19%），Complementary 同样平铺但每条只列 **14** 个、其中 **13** 个变化（93%）（见 §6 P0-1）。
3. **`view.` 与 `program.X.before=` 全场为 0**：这两个 Iris 机制在实际分发包里几乎没人用，Astra 不用不是缺陷。

### 3.5 口径警告（本报告的数据边界）

- **四个分母必须先钉死，后文所有分数都按此读**：**22 个保存目录**（本次 20 个下载条目 + 姊妹文档解包的 `rethinking-voxels-source`、`steadfast-shaders-source`）⊃ **20 个下载条目 = 19 款**（Complementary Reimagined 与 Unbound 经逐文件 md5 比对确认为同一份代码，算 1 款 2 条目）；**21 个测量集合 = 20 条目 + ASTRA**，即 §3 四张表的行；`_meta/ao_recheck.json` 的 **20 行 = 19 款 + ASTRA**。样本根目录下另有 7 个 `*-source` 目录与同名目录逐字节相同，不进入任何分母。
- 行数字节按文件原始编码统计，**含 boilerplate**：与 VanillaPlus 的对照（§2.19）已证明该口径对含许可头/枚举滑杆的包会系统性高估。跨包比"体量"时应优先用净代码。
- 注释比 `comment_ratio` 会把 OptiFine 式 `#define X 1 //[0 1 2]` 的行尾枚举计入注释。受影响的行：JCL 0.378（真实 0.139）、RedHat 0.560、ILV/Bloop/Solas 的峰值均有此成分。**跨包比注释密度时须先剔除 `//[` 段。**
- M3 是命名启发式，已知假阴性：E-LITE/MakeUp 的测光、Bloop 的 TAA（列 16 但 `program/taa.fsh` 293 行确实是完整 TAA）。
- M3 的 `shadow2D()` 列曾测成 Astra 0 但 `sampler2DShadow` 也 0，原因是脚本抓的是辅助函数名；已拆成两列后 Astra = `sampler2DShadow 2 / shadow2D() 0`，与 `Astra/shaders/global/lighting/shadowmap.glsl:39-40` 一致。
- M3 的「HBAO/SSAO」列是**宽松命名口径**（`HBAO|SSAO|ambientOcclusion|AO_`，且按 `feature_matrix.py` 的扩展名表把 `.h`/`.dat` 一并扫入），21 个集合里 18 个非零（零命中只有 LIGHT、VanillAA、ASTRA）——它**不能**用来回答"这个包有没有 SSAO"：Noble 该列 42 条里 **18 条来自两个 `.dat` 云噪声纹理文件**（`image/clouds/detailNoise.dat` 8、`shapeNoise.dat` 10），换成严格词表后这两个文件仍贡献 4 条（`_meta/check_noble_dat.py` 可复测）。严格口径由 `_meta/ao_recheck.py` 生成、落在 `_meta/ao_recheck.json`：只扫 GLSL、剥离注释、只认 `HBAO|SSAO|GTAO`。严格口径下 **19 款里 10 款非零、Astra 为 0，且 B 组 5 款里 4 款为 0（只有 SDV 14）**——这才是 §7 拒绝给 Astra 加 SSAO 的依据。

---

## 4. 五个维度的横向结论

### 4.1 目录与 `#include` / program 组织

生态里有四种组织范式，按复用度排序：

| 范式 | 代表 | include 边/文件 | 特征 | Astra 位置 |
|---|---|---|---|---|
| 零 include，每 pass 自包含 | LIGHT（0） | 0.00 | 40.3% 逐字副本 + 已证实的静默漂移（§2.11） | 反例 |
| 扁平 + 单个按标签分段头 | Sildur's、MakeUp、SDV | 0.9–3.4 | 同一选项多段各写一遍 | 部分接近 |
| 万能巨型头被 N 个壳包含 | JCL（`main_f.glsl` 被 74 处包含） | 1.03 | 同一份 2,373 行编译 74 遍 | 反例 |
| **功能子系统 + 每 pass 派发器** | **Complementary、Mellow、RenderPearl、Bloop、Astra** | 1.3–2.0 | `lib/`（或 `global/`）为真源，`world*/` 为薄壳 | **Astra 属于此类** |

**结论一：Astra 的组织范式与生态最优侧一致，不需要改。** 具体证据：`Astra/shaders/world1/composite1.fsh:1-4` 是 4 行纯派发器，而体量最接近的 VanillaPlus 把同一阶段抄成 536/297/274 行三份并已漂移（§2.19 缺陷 5）。

**结论二：settings 文件膨胀不是病。** 全场 settings 类文件实测：ILV 与 JCL 把配置撑到 228 KB / 85.6% 枚举（§2.18），`Astra/shaders/lib/settings.glsl` 368 行 / 81–82 个顶层 `#define`。真正的病灶不是文件长度而是**同一 token 的多处定义**（Sildur's）与**暴露但零消费者的选项**（JCL `KILL_SWITCH`、VP `VIEWPORT_GAMUT`）——Astra 应查的是后者，不是压缩前者。

**结论三：按 pass 拆设置头是可选的优化而非缺陷。** RedHat 用 21 个 `.h`（870 行 = 5.5% 代码却占 40% include 边）实现"每 pass 只吃自己要的宏"。Astra 的单一 settings + 特性门控 include（如 `Astra/shaders/program/final.fsh:24` 条件声明 `colortex2MipmapEnabled`）已部分达到同一目的，收益是编译期单元更小，代价是可发现性变差。**列为 P2 观察项，不主动改。**

### 4.2 渲染管线划分

**阶段序高度一致**：`shadow` → `gbuffers_*` → `deferred*` → `composite*` → `final`。差异全在**每段承担什么**。

- **光照发生在哪**：A 组内 BSL/Complementary/Solas/Noble/Photon/Bloop 为延迟或半延迟，RedHat/LIGHT/Sildur's/MakeUp/E-LITE/Miniature/SDV/VanillAA 为前向。**Astra 是前向**：`Astra/shaders/program/lit.fsh` 头注即 "Single lit fragment entry for native geometry"，`design.md:48` 明确"极简前向"；`deferred.fsh` 只做场景拷贝 + 水坑反射，光照模型在几何着色时评估，不在 deferred 阶段。〔2026-09-20 复核更正：原文"Astra 是延迟（lit.fsh → deferred 链）"与 lit.fsh/deferred.fsh 实际职责矛盾。〕
- **pass 级裁剪是最大分歧点**：19 款里 **13 款用 `program.X.enabled=<表达式>`**（加 Astra 为 15/21 个集合），完全不用的 6 款是 Noble、RenderPearl、RedHat、LIGHT、VanillAA、SDV。**Astra 属于用的一侧。** **关掉整趟 pass 是唯一能省掉一整次全屏成本的降级手段**，而分支只能省 ALU。
- **水面**：六个包（Complementary、BSL、Solas、E-LITE、SDV、VanillaPlus）把焦散/消光的**逐 texel 预计算搬进 shadow 阶段**（§2.1/2.2/2.4/2.14/2.17/2.19）——这六个包的共识，也是本次调研里最集中的一条水面优化（跨 A/B 组，但未过半，见 §5.1 表下的例外说明）。BSL 的 `program/shadow.glsl` 里 `WATER_CAUSTICS` 出现在 10 行（`:17/:28/:37/:44/:71/:95/:119/:161/:180/:248`，271 行文件），焦散在阴影 texel 端就写进 `albedo`。Astra 目前焦散与消光在像素端（`Astra/shaders/global/water/absorption.glsl` 80 行的 `water_extinction()` `:42-44` 与 `water_transport()` `:48-54`）。
- **体积云**：Astra `CLOUD_MODE 1`（`Astra/shaders/lib/settings.glsl:87`）。参照实现里云都在 `deferred`/`composite1` 而非独立 pass（Sildur's `deferred.fsh:337+`、RedHat `program/composite1.glsl:273-313`、BSL `lib/atmospherics/clouds.glsl`）。**独立 pass + `enabled` 裁剪是更好的形态**（Complementary 的 `lib/atmospherics/clouds/mainClouds.glsl:42-46` 按档换实现）。
- **compute 与自定义图像**：Astra 有 12 条 shadowcomp 相关声明、9 个 compute 阶段、3 张自定义图像。JCL 是本次唯一的 LPV 体素包，其调度形态值得记：**`prepare.csh` 与 `prepare_a.csh` 至 `prepare_d.csh` 全是 3 行启动器**（`#version 430` + 一个 `#define`——`prepare.csh` 是 `FIRST_FLOOD_PASS 1`、`prepare_a`/`prepare_c` 是 `FLIP_V_BUFFERS 1`、`prepare_b`/`prepare_d` 是 `FLIP_V_BUFFERS 2`——+ `#include "/shaders/voxel_photons.csh"`），用"多个外壳文件"替代"Iris 没有的原生 multi-pass compute 调度"（`shaders/voxel_photons.csh:15-122` 另有 33 段手算 `workGroups` 常量）。⇒ 蓝图 `.specs/astra-shader/design.md:48/50` 的「零 compute」表述**已在 `:517` 正式修订**为「9 个 compute 阶段 + 3 张自定义图像作为一等公民例外」，两处不矛盾，无需上报。

### 4.3 核心算法

**光照模型**：Lambert + 半球/多向环境光是全场共识。**GGX 列非零的只有 8/19 款**（9/21 个集合：Photon 9、Noble 8、Mellow 5、BSL 4、RenderPearl 4、Complementary 3、VanillaPlus 3、Bloop 1 —— 命中数全部很小），其余 11 款该列为 0，包括 RedHat/LIGHT/Sildur's/SDV/Miniature/ILV/Solas。⇒ **Astra `GGX = 0` 不是缺陷**，与低配组完全一致；SSS 命中 11 也已在多数同类包水平（前向包里 0–9 居多）。

**阴影**（横向最卷的一节，五种 bias 流派）：
| 流派 | 代表 `path:line` | 是否依赖分辨率 | 是否需三角函数 |
|---|---|---|---|
| `tan(acos(NdotL))` 斜率 × 畸变因子 | RedHat `program/composite.glsl:662-664`、Sildur's `deferred.fsh:561` | 否 | **是** |
| 距离/影距 × 固定系数 ÷ `shadowMapResolution` | ILV `lib/lighting/fsh_lighting.glsl:83`、BSL `lib/lighting/shadows.glsl:148-152` | **是（显式解耦）** | 否 |
| 投影矩阵 z 分量归一 | Miniature `common/getLightStrength.fsh:33` | 是 | **否** |
| 勾股恒等式一次求法线偏移 + 斜率 | RenderPearl `lib/light/shadows.glsl:99-115` | 部分 | 否 |
| 顶点侧距离自适应 | MakeUp `src/shadow_src_vertex.glsl:22` | — | 否 |

Astra 现状：`Astra/shaders/global/lighting/shadowmap.glsl:202 bias = end_shadow_texel_size()*0.30 + 0.015`（已按 texel 解耦，但带一项**与分辨率无关的固定偏移**，`:201` 注释自陈 "Fixed world-space offset; a camera-relative radial bias moves the edge."）与 `:207` 的另一条 `bias = 1.5*length(raw.xy)` 由 `#ifdef DIMENSION_END`（`:200`）**维度互斥**，并非同一维度内并存。⇒ 见 §6 P1-5。〔2026-09-20 复核更正：原文"并存"误述分支结构。〕

**时域**：11/19 款有 TAA 命名命中（12/21 个集合），且这只是命名口径——Bloop 列 16 而 `program/taa.fsh` 实为 293 行完整 TAA。B 组 5 款里 MakeUp/E-LITE/Miniature/SDV 均为 0，VanillAA 为 1（但它就是 TAA 包）。**Astra TAA = 0 与低配组完全一致**，且 VanillAA 明确论证了触发条件（§2.16）。

**色调映射与色彩管理**：全场共识是"tonemap 命中数普遍不低（Astra 36 属正常），但**色彩管理**（白平衡/LUT/色域矩阵）才是分水岭"。Astra 22 命中处于中游（Noble 183、Mellow 62、Bloop 70、LIGHT 84 为高侧）。真正可迁移的三条：**在 log2 空间以 0.18 为中灰做对比度**（Photon `program/c14_color_grading.fsh:114-117`）、**CAT02 von-Kries 白平衡**（Noble `include/post/grading.glsl:201-221`，GPL → 据公开标准自写）、**Purkinje 杆/锥夜适应**（Bloop `program/final.fsh:429-440`，CC-NC → 据生理光学文献自写）。

**采样**：Vogel 盘 / Poisson 表 / R2 序列 / 蓝噪声是阴影与 SSAO 的公共件。**Astra 蓝噪声 = 0、Bayer/IGN = 5**，且光束抖动当前从**外部纹理**取（`Astra/shaders/global/water/light_shafts.glsl:80 texture(solasWaterNoise, gl_FragCoord.xy / 512.0).b`）。⇒ 换成自有 `Astra/shaders/lib/bayer.glsl` 可去掉一次抓取与一张外部图（§6 P2-13）。

### 4.4 低配优化

按"实测省多少"排序，六类手段的性价比差异极大：

1. **整趟 pass 被删**（`program.X.enabled=<expr>`）——省一次全屏成本。用者 13/19 款 + Astra（15/21 个集合），Photon 69 条、Mellow 52、ILV 48、Astra 24 行声明 = **23 个唯一门**（`:38-42` 把 `composite2` 写成 `#if …` 的 true/false 两行）。逐行分类：**8 个无条件 `false`**（`:46-49`、`:62-63`、`:67-68`，维度专用）、**7 个无条件 `true`**（`:29 world1/deferred1`、`:30 world1/prepare`、`:44 composite3`、`:51 composite`、`:73/:74/:75 deferred`）、只有 **8 个真接在画质 token 上**（`:43/:45/:64/:69 BLOOM`、`:52/:70 SHADOWS`、`:65 NETHER_VOXEL_LIGHT`、`:38-42` 的 GODRAYS/shaft 复合条件）。⇒ 关得掉的是 bloom 链与结界 shadow；**三档里 `SHADOWS` 恒开 ⇒ `composite3`、`composite`、`deferred`、`shadow` 一律恒真**，且 `!GODRAYS` 也关不掉 `composite2`（它还带 `|| (UNDERWATER_LIGHT_SHAFTS && SHADOWS && …)`）。
2. **像素成本搬到 texel 端**（阴影阶段烘焙）——见 §4.2，六包共识。
3. **逐帧常量搬到 CPU**（shaders.properties 文件里的 `variable.float.*` / `variable.int.*`，非 GLSL 侧计数）——按 `variable.float` 计 Bloop 112、ILV 53、VanillaPlus 34、Photon 30、**Astra 18**；按 `variable.*` 总数计 Bloop 115、ILV 59、VanillaPlus 36、Photon 30、**Astra 22**。注意 `variable.*` 是 **Iris 专属**机制，用它的包一律已是 Iris-only；只有仍需覆盖 OptiFine 的包才会再写一份 properties 级 `mix()`/`lerp()` 双表达（Bloop `shaders.properties:410-420`），**这条对 Iris-only 的 Astra 不适用**。
4. **渲染分辨率缩放**——`size.buffer.` 只有 **8/19 款**用（Noble 42、Photon 13、ILV 6、Bloop 6、Complementary 2、VanillaPlus 3、JCL 2、Mellow 1），**Astra 6 条**。其余 **11 款完全不做**分辨率缩放，包含全部 5 款低配向包（Miniature/VanillAA/SDV/MakeUp/E-LITE 均为 0，Sildur's 亦 0）。实测每款的 `size.` 行都恰是 `size.buffer.` 行（两者计数相同），故该列不存在"用 `size.` 但不用 buffer 尺寸"的反例。⇒ 这条直接推翻了「低配包必然做渲染缩放」的预设；低配的主流手段是**减抽样 + 整段跳过 + 退回原版实现**（BSL 的 `CLOUDS=3`、Sildur's 的八度减半、Solas 的三级早退）。
5. **连续分辨率旋钮（Bloop 独占）**：`program/fog_translucent_lowres.vsh:20` 的顶点级百分比缩放，1% 粒度，不需要 `size.buffer`。这是 Astra 若要从"3 档"走向"连续降级"的最短路径（§6 P2-14）。
6. **精度取舍**：按**文件数最多的那一条 `#version`** 判定，主版本 ≤ 330 的 **14/19 款**在 M3 的 `16F` 列**全为 0**（Complementary、BSL、Solas、ILV、Bloop、RedHat、LIGHT、Sildur's、MakeUp、E-LITE、Miniature、VanillAA、SDV + 对照 JCL）——GLSL 1.x/ES2 时代精度限定符本就无收益，"低配靠 mediump"这一预设不成立。`16F` 非零的只有 RenderPearl 607、Noble 57、Photon 2 与 **Astra 4**，四者的主 `#version` 都是 400+。⇒ Astra 属于"有条件做精度分级"的那一档，而不是"被版本卡住"。

**档位设计（本次最重要的组织结论）**：
- 最省：Complementary 8 条 profile（POTATO/VERYLOW/LOW/MEDIUM/HIGH/VERYHIGH/ULTRA/COMPLEMENTARY）**同样全部平铺、零 `profile.PARENT`**，但每条只列 14 个 token，其中 13 个真正在阶梯上变化（唯一恒定的 `SSAO_QUALI_DEFINE=2`）。⇒ **平铺本身不是病，列 67 个却只改 13 个才是。**
- 最清晰：ILV 的 `shaders.properties:154-159` 用 **`-1` 表示"不动用户当前值"**，profile 因此可以是稀疏差量。
- 最完整：BSL/Solas 的 profile **同时覆盖值宏与 Iris 全局**（`shadowMapResolution`、`shadowDistance`）。
- 最差：RedHat 5 条平铺各重列 36–37 个 token，导致 `SHADOW_FILTER` 阶梯 0/0/2/1/1 与 `VL_QUALITY` 阶梯 4/6/4/4/2 **双双非单调**——档位与实测成本脱钩。
- **Astra 属于"最差"侧的结构**：3 条 profile 各列 67 个 token（行长 1219/1214/1214）、全平铺、零继承，而 67 个选项中真正随档变化的只有 **13 个**（P↔B=10、B↔U=5、P↔U=13，并集 13）。且 `Astra/shaders/global/post/grading.glsl:63-66` 自陈三档调色参数完全相同；实测三档**全部保留 SHADOWS**。⇒ §6 P0-1。

### 4.5 兼容性与异常处理

- **`option.`/`slider.`/`tweak.`/`const.` = 0 于全部 21 个集合**。Astra 的裸 `#define` + `screen`/`profile`/`sliders=` 是主流。
- **`iris.features.required/optional` 只有 3 个包写、共 4 处**：Bloop `:21`（`optional = REVERSED_CULLING COMPUTE_SHADERS CUSTOM_IMAGES BLOCK_EMISSION_ATTRIBUTE ENTITY_TRANSLUCENT`）、JCL `:215`（`optional = FADE_VARIABLE`）**与** `:219`（`required = CUSTOM_IMAGES`）、Noble `:38`（`required = SSBO COMPUTE_SHADERS CAN_DISABLE_WEATHER`）。后两处还各自包在 **properties 级预处理守卫**里——JCL 的 `:219` 在 `#if FLOODFILL_LIGHTING > 0`（`:217`）内、Noble 的 `:38` 在 `#if defined IS_IRIS`（`:36`）内 ⇒ `shaders.properties` 自身可条件化，**Astra 的 `Astra/shaders/shaders.properties:38-42` 已在用同一机制**（`#if defined GODRAYS || …` 决定 `composite2.enabled`），只是还没把依赖写成显式声明。VanillaPlus 用了大量新机制却**零声明**，结果是旧版 Iris 上报错点远离根因。**Astra 该写 `required`，这是 VP 停更教训的直接推论。**
- **双后端优于砍功能**：ILV `basics/settings.glsl:1-3 MODERN_BACKEND` 在旧后端**重算缺失的 uniform**而非关掉特性；Bloop `lib/uniforms2.glsl:151-160` 用普通变量兜底 `cloudTime`/`cloudHeight`/`heightLimit`。⇒ Astra 若引入 Iris 专属 uniform，应采用同一兜底形状。
- **材质标志编码**：LIGHT `composite.fsh:470` 用 `length(normal)` 区间编码 water/ice（省一张 MRT），且**任何把法线写坏的资源包会自动落回"陆地"分支**——这是最优雅的异常处理，因为兜底不需要判断。Sildur's 则把 `pdepth` 塞进 `colortex2.b`（同样是复用未用分量）。
- **版本策略分布**（按文件数最多的那一条 `#version` 计，19 款）：`120` 8 款（BSL、LIGHT、Sildur's、MakeUp、E-LITE、Miniature、VanillAA + 对照 JCL，为了 1.7.10 到 1.21.x 通吃）、`130` 3 款（Complementary、Solas、RedHat）、`140` 2 款（ILV、Bloop）、`330` 1 款（SDV）、`400` 3 款（Photon、Mellow + 对照 VanillaPlus）、`430` 1 款（Noble）、`460` 1 款（RenderPearl）。A 组头部已迁到 `400`/`430`；Astra 是 `400`×159 + `430`×10 + `460`×1，处于"放弃 1.7.10、拥抱 GL4"的一侧，与 Complementary/Photon/Noble 同侧。**这不需要改**，但意味着 Astra 依赖 GL4 设施（`sampler2DShadow`、`textureGather`、`texelFetch`），必须形式化声明。
- **外部集成的零配置形态**：LIGHT 的 4 个 Physics Mod 桥接文件在 `shaders.properties` 里**没有任何一行引用**——由 mod 自行发现。若 Astra 做 Physics Mod / EMB 适配，这是干净的做法。

---

## 5. 共性与各自独门

### 5.1 真共性（≥18/21 个测量集合命中，构不成差异化建议）

| 共性 | 命中（集合） | 含义 |
|---|---|---|
| 裸 `#define` token + `screen` 块 + `sliders=` 单行清单 | 21/21 | Astra 已在主流上；`sliders=` 每包恰好 1 行是属性格式使然 |
| 至少一处 `#if` 静态分支 | 21/21 | 编译期门控是共识；Astra 88 处 |
| 至少一处 `break` 或 `discard` 早退 | 20/21 | 唯一例外 VanillAA（两者皆 0）；Astra 24/15 属中位 |
| 有 tonemap 算子（`Tonemap\|Reinhard\|Filmic`） | 18/21 | 零命中的三款是 MakeUp、Miniature、VanillAA；Astra 36 命中正常 |
| 有 `profile.` 行 | 18/21 | 零命中的三款是 LIGHT、Sildur's、VanillAA——它们用别的方式分档 |

**表中唯一的例外（不到阈值，但值得单独记）**：焦散/消光的**逐 texel 预计算**只有 **6/19 款**做（§2 源码级判定，非列计数）——A 组 3 款（Complementary、BSL、Solas）+ **B 组 2 款（E-LITE、SDV）**+ 对照 VanillaPlus。⇒ 它不是全场共性，而是头部与部分低配包的共识；**但"低配组 0/5"这个说法不成立**，见 §6 P1-7。

### 5.2 各自独门（只此一家，按可迁移度排序）

| 包 | 独门 | 唯一性依据 |
|---|---|---|
| **Photon** | 顶点着色器里的**576 tile 直方图 + CDF 中位数测光** | 唯一做了完整测光直方图的包；其余最多到 mip 平均（`program/c4_taa_exposure.vsh:83-134`） |
| **Bloop** | **顶点级百分比渲染分辨率**（1% 粒度，无 `size.buffer`） | 唯一把渲染缩放做成连续滑杆且不动用 Iris 缓冲尺寸特性（`program/fog_translucent_lowres.vsh:20`） |
| **LIGHT** | **单像素 13×13 太阳遮挡 + alpha 广播** | 唯一用"1 像素做全局判定、通过 alpha 通道传播"的做法，零新 pass（`composite.fsh:423-433` → `final.fsh:329`） |
| **JCL** | **沿世界法线偏移 0.9 格采样体素** | 唯一解决 LPV 内侧全黑的一行（`main_f.glsl:1593-1595`） |
| **Complementary** | 双变体**差一行**（`lib/common.glsl:14`）+ 8 profile 改 13 token | 唯一把"两个品牌"实现成同一份代码的默认值差异 |
| **RenderPearl** | 246 行 `prelude/compat.glsl` 驱动兼容层 | 唯一系统处理 glsl-transformer 与 Iris 版本门（`:14-249`）；**且是 MIT** |
| **Sildur's** | 远端畸变系数 `b = (exp(Far)-a)*shadowDistance/128.0` | 唯一显式按影距归一畸变（`shaders.settings:39-45`）——Astra 正缺这一层 |
| **ILV** | profile 的 **`-1` = 不动用户值** 语义 + 代码生成 ID 表 | 唯一把稀疏 profile 做成正式语义（`shaders.properties:154-159`） |
| **Noble** | 单个滑杆直接驱动 `size.buffer.colortex12` | 唯一把缓冲尺寸做成用户旋钮（`shaders.properties:347-353`） |
| **Miniature** | 16 方块量化 ⇒ 每格一次阴影采样 | 唯一把阴影采样按世界区块量化降本（`common/getLightStrength.fsh:11-12`）；**且是 MIT** |
| **Mellow** | SMAA 实装 + `get_min_light` 绑 `screenBrightness`/`nightVision` | 唯一有 SMAA 且考虑了玩家亮度设置的包；**且是 MIT** |
| **SDV** | 阴影裁剪空间光束：19 行块 / 7 步、**循环内零矩阵乘法** | 唯一把光束变换全部外提（`lib/rayTracing/volumetricLight.glsl:38-56`，外提在 `:40-45`） |
| **E-LITE** | 角度空间天光 LUT 直接复用 `gaux4` 的未用通道 | 唯一用 `atan/acos` 把方向向量当 UV（`common/solid_blocks_fragment.glsl:341-343`） |
| **VanillaPlus** | 停更状态本身 | 唯一提供"不可回归测试 → 用户可触达崩溃"的完整证据链（§2.19） |

---

## 6. Astra 改进建议（按优先级）

每条含：现状（实测）→ 依据 → 做法 → 成本 → 许可证判定 → 验证方法。许可证一律与 `Astra/THIRD-PARTY.md:10-16` 的政策表交叉。**「可复用」仅指登记后取用；「只读思路」指必须全部自写表达式。**

### P0-1 · 档位重做：三档必须产生可测差异

- **现状**：`Astra/shaders/shaders.properties:171-173` 三条 profile 各列 67 个 token、全量平铺、零链式（行长 1219/1214/1214），而 **67 个中真正随档变化的只有 13 个**（P↔B=10、B↔U=5、P↔U=13）：`BLOOM`(off/on/on)、`CLOUD_MODE`(0/1/1)、`END_PRECESSION_MINUTES`(28/36/36)、`ENTITY_SHADOW_DISTANCE`(48/64/96)、`FANCY_TRANSLUCENTS`(off/on/on)、`GODRAYS`(off/off/on)、`NETHER_VOXEL_LIGHT`(off/on/on)、`SCREENSPACE_REFLECTIONS`(off/on/on)、`SCREENSPACE_REFRACTION`(off/on/on)、`SHADOW_DISTANCE`(192/256/256)、`SHADOW_RESOLUTION`(1024/2048/4096)、`SHADOW_SOFTNESS`(2/2/8)、`UNDERWATER_SHAFT_SAMPLES`(7/7/10)。其余 54 个三档完全相同，含 `SHADOWS`、`SHADOW_FILTER_MODE=0`、`WATER_CAUSTICS`、`UNDERWATER_LIGHT_SHAFTS`、`TONEMAP_OPERATOR=0`、`EXPOSURE=100`、`CONTRAST=102`。`Astra/shaders/global/post/grading.glsl:63-66` 另自陈「All three GUI profiles currently ship IDENTICAL grading values」。⇒ 三档既砍不掉 pass（§4.4-1）、也不改 bias 路径与调色，离群点在**差量密度 19%**（Complementary 同结构为 93%），不在"有没有链式"。
- **依据**：Complementary 8 条 profile **结构与 Astra 相同（平铺、零链式）却只列 14 个 token / 13 个变化** ⇒ 要学的是**差量密度**，不是链式本身；ILV `shaders.properties:154-159` 用 `-1` 表示"不动用户当前值"，profile 因此可以写成稀疏差量；BSL `:4-8`（5 条，自 `:5` 起链式）与 Solas `:14-17`（4 条，自 `:15` 起链式）的差量同时覆盖值宏与 Iris 全局（`shadowMapResolution`、`shadowDistance`）；反面是 RedHat 平铺导致 `SHADOW_FILTER` 阶梯 0/0/2/1/1 非单调（§4.4）。
- **做法**：两步且互不替代。**第一步收缩**：三条 profile 只保留真正变化的 13 个 token（可选再按 BSL/Solas 写成 `profile.X = profile.PARENT <差量>`，纯语法收益）。**第二步补差量**：`PERFORMANCE` 必须实际改动 `SHADOWS`/`CLOUD_MODE`/`UNDERWATER_LIGHT_SHAFTS`/`GODRAYS`/`SHADOW_DISTANCE`/`UNDERWATER_SHAFT_SAMPLES` 中的多数，并**首次引入 `size.buffer.*` 差量**——实测 6 条 `size.buffer.colortex1/2/6/7/8/9`（`Astra/shaders/shaders.properties:14,19,21,25,26,28`）**完全不在三档差量里**。同时把 §4.4-1 列出的 7 个恒真门中至少 `composite3`(`:44`)、`composite`(`:51`)、`world1/deferred1`(`:29`)、`world1/prepare`(`:30`) 接上真实表达式，使最低档真能删掉整趟 pass。
- **成本**：纯配置层，零 GLSL 改动，零显存/带宽风险。
- **许可证**：profile 语法是 Iris 的属性格式（API 事实，不受版权保护）；`-1` 语义属"如何组织配置"的思路级，不构成表达复制 → **无风险**。
- **验证**：`python qa/tools/inspect_iris_properties.py`（枚举 profile 差异集）+ `python qa/tools/cost_census.py`（每档的抽样总量）；并给 `check_pack.py` 新增 profile 差分检查。**注意不能只比 token 名集合**——实测三档列出的 67 个名字完全相同，必须比**取值差量**：三档两两差量各 ≥1 个（当前 10/5/13），且**差量密度 = 变化数 / 列出数**须 ≥50%（当前 19%）。

### P0-2 · 云阴影（2D 廉价形态）

- **现状**：M3「云阴影」Astra **0 命中**，参照组 8/19 款非零（9/21 个集合：Photon 114、Bloop 36、Solas 27、Complementary 18、Noble 16、BSL 4、ILV 3、JCL 2）。B 组 5 款全为 0 ⇒ **低配包不做云阴影，因此 Astra 若做必须是无条件的便宜形态**。〔2026-09-21 T14 就地更正：这个 0 是**命名启发式的假阴性**，不是机制缺失。Astra 早已有沿光向追迹云密度的 `astra_cloud_transmission`（`global/atmosphere/weather.glsl:122-136`），只是标识符里没有 `cloud`+`shadow` 相邻串。本轮按 M3 口径重建并逐包复现（只扫 GLSL 系文件、先剥 `/* */` 再剥 `//`、大小写不敏感匹配 `cloud.?shadow`）：BSL 4 / Unbound 18 / Reimagined 18 / Solas V3.7b 27 / Solas V2.2b 0 全部与表内一致，Astra 在 T14 前为 0——数字对，结论错。列生成脚本 `_meta/feature_matrix.py` 在本仓库不存在（`find` 实测零命中），口径是重建的。见 11.D-18、11.F-14〕
- **依据**：BSL `lib/lighting/shadows.glsl:295-374 GetCloudShadow()`——把 2D 云噪声沿光向投影到地面，再用 `CLOUD_REVEAL`（`:325`）打孔洞透射，成本约一次噪声 fetch；守卫放在最前面的两例：Solas `lib/atmosphere/volumetrics.glsl:42-80`（先 9 点 `depthtex` 采样求 `averageDepth` 再合成 `closedSpaceFactor`）、Noble `include/atmospherics/clouds.glsl:194-196`（`if (weatherMap <= 0.05) return 0.0;`——无雨即整段退出）。
- **做法**：复用 Astra 已有云的密度场（`Astra/shaders/global/atmosphere/clouds_planar.glsl`，324 行）在**单一高度平面**上沿 `sunVec` 采样 1–2 次求遮挡，与 `shadowmap` 结果相乘；洞穴/封闭处按 `eyeBrightnessSmooth.y` 或天光贴图早退；接入 `Astra/shaders/lib/settings.glsl` 单 token，并**在 P0-1 之后让该 token 参与 profile 差量**。
- **成本**：每片元 1–2 次 fetch，仅在 `diffuse > 0` 且露天时执行。
- **许可证**：BSL = **All Rights Reserved → 只读思路**；表达式、噪声选择、`CLOUD_REVEAL` 的具体形状全部自写。PROVENANCE 按 `Astra/shaders/global/post/grading.glsl:210-212` 的既有格式记 `IDEA ONLY, no code and no formula transplanted`。
- **验证**：`python qa/tools/sc35_probe.py`（露天/遮罩一致性）；`compile_glsl.py` 穷举新 token 的两个取值。【2026-09-21 T14 就地更正：`sc35_probe.py` 确实存在，但它的 7 个模式（`names[]` 实测，文件头文档只列到 mode 4）分属持物光／水面波／焦散／岸线折射四类，全文 `cloud` 出现 0 次，**没有任何云影或露天遮蔽场景**，本单用不上；后半条以强制开扫描 + 反向验证完成，见 11.F-14】
- **裁决（T14 · 已执行，默认关，标注待实机，见 11.F-14）**：落地形态与本条"做法"有三处实质偏离，均因先核实了包内现状。① 缺口不是"没有机制"而是"只有雨天用得上"：`astra_cloud_transmission` 早已存在并已被 `program/scene.glsl` 用来在雨天压暗直射光，而日面／月盘却无条件被同一片云遮——所以本单是把那次调用从 `astraRainFactor > 0.01` 的门里搬出来，不是新写投影。② 未建 `eastVec/northVec` 投影、未新建云噪声采样函数，沿用自有单平面追迹（每片元 2 次 `textureLod`，与本条"成本 1–2 次 fetch"一致）。③ 相乘的对象是 `params.directLightSurface` 而非 `shadowmap` 结果，露天判据用本包自有的 `static_shadow(skylight)`（即 `diffuse.glsl:253` 阴影图兜底用的那一个），不用 `eyeBrightnessSmooth.y`。掠射衰减参照 Reimagined `lib/lighting/cloudShadows.glsl:60` 的 `sqrt3(1.0 - abs(EdotL))`，表达式自写。参照引用本轮全部本地重验：BSL `lib/lighting/shadows.glsl:295` 的 `GetCloudShadow()` 与 `:325` 的 `CLOUD_REVEAL` 行号准确（BSL 无掠射衰减），Reimagined `:60` 准确；`grading.glsl` 的 PROVENANCE 格式实测在 `:213` 而非本条写的 `:210-212`。出厂三档 `!CLOUD_SHADOWS`，`git diff --stat` 对 `scene.glsl` 为 27 增 0 删 ⇒ 出厂路径逐字节未动。

### P0-3 · 自动曝光（mipmap 链测光，带不对称速率与守卫）

- **现状**：M3「自动曝光命名」Astra **0**；`Astra/shaders/lib/settings.glsl:176 #define EXPOSURE 100` 是静态滑杆；`Astra/shaders/global/post/grading.glsl:115 apply_exposure()` = `linearHDR * (EXPOSURE*0.01*grading_dimension_exposure())`——**完全没有亮度输入**。M3「Mipmap降采样」Astra 已有 3 处声明、覆盖 2 张缓冲（`program/composite1.fsh:20` 与 `program/final.fsh:24` 在 colortex2；`Astra/shaders/program/water_bloom.fsh:5 const bool colortex0MipmapEnabled = true;` 在 colortex0）已在用同一机制 ⇒ **设施存在，只缺测光用途**。〔2026-09-20 复核更正：原文"已有 2 处"与句内引用的第三处声明自相矛盾。〕〔2026-09-21 T15 就地更正：本条两处行号在写下时已偏——`#define EXPOSURE 100` 实测在 `settings.glsl:187`（本条写 `:176`），`vec3 apply_exposure()` 实测在 T15 动手前的 `grading.glsl:118`（本条写 `:115`）、T15 在该文件加入 include 与 `apply_auto_exposure` 槽后为 `:123`。"完全没有亮度输入"这一条判断成立，与行号无关；T15 之后该判断作废——见本节末「裁决」。〕
- **依据**：结构派（mip 平均）ILV `program/composite20.glsl:13`（`colortex0MipmapEnabled`）+`:202-208`（`texture2DLod(…, 10000.0)` 取最粗级 → `sqrt(getLum(·))` → `mix` 历史值）、BSL `program/composite5.glsl:57,156-163`（`exposureLod = log2(viewHeight * AUTO_EXPOSURE_RADIUS)`）、MakeUp `common/composite_vertex.glsl:74-87`（`log2(min(viewWidth,viewHeight)) - 1.0` + 5 点采样）、SDV `main/composite6.glsl:168-178`（`textureLod(colortex4, vec2(0.5), 8)` + 角落历史值 `texelFetch(colortex5, ivec2(1), 0).a`）、VanillaPlus `program/grade/exposure.vsh:37-91`；统计派（直方图中位数）Photon `program/c4_taa_exposure.vsh:39-170`。**必须采纳 Photon 的三条性质**：中位数或至少对高光截断（否则太阳入镜会整体压暗）、`:161-170` 的 NaN 守卫与**变暗/变亮不对称速率**（`AUTO_EXPOSURE_RATE_DIM_TO_BRIGHT` vs `…_BRIGHT_TO_DIM`）、`:144` 历史值存 texel(0,0) 的 alpha。兜底参考 Mellow 的 `get_min_light` 绑 `screenBrightness`/`nightVision`。
- **做法**：在 `Astra/shaders/program/water_bloom.fsh` 已有的 mipmap 链上取 `log2(min(viewWidth,viewHeight))` 一级做亮度，历史值写进任一 `colortex` 的 texel (0,0)，在 `final` 前以标量注回（ILV `program/composite20.glsl:161` 的角落写回 + `:4-5` 的 `flat in_out` 顶点算片元用），**不做新的全屏 pass**。
- **成本**：一次 mipmap fetch + 一个 1×1 历史 texel，可忽略。〔2026-09-21 T15 就地更正：本条被实测证伪两处。① "已有的 mipmap 链"是条件性的——`colortex0MipmapEnabled` 只在 `program/water_bloom.fsh:5` 声明，该 pass 的门是 `program.composite4.enabled=BLOOM`（`shaders.properties:55`），而 PERFORMANCE 档出厂 `!BLOOM`（`:149`）⇒ 在该档按本条做法启用自动曝光，会**新引入**一整条全分辨率 HDR mip 链的生成，这不是"可忽略"。② 同一条里"不做新的全屏 pass"（做法条）也不成立：任何逐帧测光都要一个自己的写入槽。实际落地成本 = 新增一个 **1 片元** pass（`composite5`，`size.buffer.colortex10=1 1`，出厂关）+ 每帧 64 次 `texelFetch` 在单片元内，与 BLOOM 完全解耦；见 design.md SC-41「对调研做法的两条实测偏离」。〕
- **权衡必须写明**：Complementary Reimagined（66,417,800 下载、最后发布 2026-09-15）**没有任何自动曝光**——`auto.?exposure|eyeAdaptation` 在其 `shaders/` 全仓库 **0 命中**（§2.1）。所以这一项的收益是"洞穴↔露天过渡不再需要手改滑杆"，不是"补一个缺失的必需品"。建议以**可关闭开关**引入，默认值需实机校准后才可开。〔2026-09-20 复核补充：本条与 Astra 既有设计直接冲突——`Astra/shaders/lib/settings.glsl:46` 明示 BLOCKLIGHT_SUPPRESSION "(replaces auto-exposure, design 4.1)"，以日光抑制取代自动曝光是 design.md 4.1 的已决事项。采纳本条前须先翻案 design 4.1，并把翻案理由写进 design.md 修订记录。〔2026-09-21 T15 就地更正：① 行号偏——`#define BLOCKLIGHT_SUPPRESSION` 实测在 `settings.glsl:48`、被引的那句注释在 `:49`（本条写 `:46`）；② 该注释措辞已按翻案决议就地改写，现文本不再声称"replaces auto-exposure"；③ 前置条件已履行：翻案写在 design.md「SC-41 自动曝光翻案与实施决议」，用户裁定为"先翻案再实现、默认关"。〕
- **许可证**：六个来源分别为 ILV What42 专有 / BSL ARR / MakeUp **LGPL-3.0+（不可复用）** / SDV FlameRender v1.6 / VanillaPlus ARR+EULA §4 / Photon 自定义 LicenseRef → **全部只读思路，表达式必须自写**。Mellow 是 MIT → `get_min_light` 的**语义规格**可署名复用。
- **验证**：`python qa/tools/p01_sky_diagnosis.py`（天空亮度基准）+ 新增测光单元脚本；先在 `BALANCED` 档默认关，实机确认无呼吸感后再进 `ULTRA`。

### P0-4 · 把逐帧常量搬到 CPU（**实测后大幅收窄，建议降级为 P2**）

- **现状（修正）**：`variable.*` 不在 GLSL 侧而在 `Astra/shaders/shaders.properties` 侧——Astra 已有 **22 条 `variable.*`**（18 float + 2 vec3 + 2 vec4）并派生 **24 条 `uniform.*`**（21 float）。参照组 `variable.float` 计数：Bloop 112、ILV 53、VanillaPlus 34、Photon 30、**Astra 18**。而本条原本点名的五类常量，Astra **已经搬了四类**：日夜权重（`:215 sunProgress`、`:217 moonProgress`、`:223 astraTwilightEnvelope`、`:226 skyVisibilityDay`）、光向（`:194 lightVector`、`:202 worldSunVector`、`:263 LdotF`、`:281 ndcLightVector`）、抖动/风相位（`:249 windChaos`、`:255 windTheta`）、光束曝光（`:289-295` 四段合成 `godraysExposure`）。⇒ **作为 P0 这条不成立。**
- **真正的残差只有一项**：**月相在 GPU 逐片元算**——`Astra/shaders/program/sky.fsh:40-41` 每片元各做一次 `0.5 + 0.5*cos(6.2831853*moonPhase/8.0)` 与 `moonPhase < 4.0 ? 1.0 : -1.0`，`Astra/shaders/global/dimension/overworld.glsl:88` 又做一次 `mix(0.82, 1.06, 1.0 - clamp(moonPhase,0.0,4.0)*0.25)`。可合并为 CPU 一帧一次的 `variable.float.astraMoonLit` + `variable.float.astraMoonLimb`。参照：VanillaPlus `shaders.properties:230-244`（月相平滑）、Bloop `:425-428`（太阳⇄月亮位置在 CPU 混合）。**收益是"单一真源 + 少三处分叉公式"，不是性能**——这三处都不在最热 pass。
- **原建议里必须删掉的一半**：`mix()`/`lerp()` 双写（Bloop `:410-420`）解决的是 Iris⇄OptiFine 差异，而 **Astra 已是事实上的 Iris-only**（GLSL 侧 `IS_IRIS` 0 命中，properties 侧却用了 46 条 Iris 专属声明，见 §2.19 教训 1）⇒ 双写对 Astra 无意义，要做的相反：把 Iris 依赖显式写成 `iris.features.required`。
- **其余依据保留**：VanillaPlus `shaders.properties:159`（`variable.int.fmod8 = frameCounter % 8`）、`:223-227`（四条 `timeSunrise/Noon/Sunset/Night` 的 clamp 斜坡合成 `uniform.vec4.daytime`）、BSL `:145-159`。
- **成本**：CPU 每帧几次浮点，GPU 少三处分叉公式。
- **许可证**：`variable.*` / `uniform.*` 是 Iris 属性格式 → **无风险**。
- **验证**：`python qa/tools/inspect_iris_properties.py` 前后对比 `variable.float` 计数；`compile_glsl.py` 编译月相相关的两个取值极端（`moonPhase` 0 与 4）。

### P1-5 · 阴影 bias 统一到一个 texel 尺度公式（残差已随 P1-9 执行 · 见 11.F-5）

- **现状**：`Astra/shaders/global/lighting/shadowmap.glsl:202 bias = end_shadow_texel_size()*0.30 + 0.015` 与 `:207` 的另一条 `bias = 1.5*length(raw.xy)` 由 `#ifdef DIMENSION_END`（`:200`）**维度互斥**——本条要求的"明确其唯一适用条件"其实已经满足；`:201` 注释自陈固定偏移项在相机相对径向下会移动边缘。⇒ 残差只剩 End 分支 `+0.015` 的归一化，与 P1-9 是同一件事。〔2026-09-20 复核更正：原文"并存"误述分支结构。〕〔2026-09-20 执行后：End 分支已并为单一纹素倍率 `:210 end_shadow_texel_size() * 0.46`，固定 `+0.015` 不再存在；非 End 分支在 `:215-216`，其掠射项已从 `SHADOW_DISTORT_FACTOR` 改接独立的 `shadowGrazingBias`（`:202`），互斥的 `#ifdef DIMENSION_END` 现在在 `:205`。〕
- **依据**：Miniature（**MIT**）`common/getLightStrength.fsh:33` 用 `clamp(3.0*(shadowDepth - shadowUV.z)/shadowProjection[2].z, 0.0, 1.0)` —— **投影矩阵 z 归一，无需 sin/cos**；ILV `lib/lighting/fsh_lighting.glsl:83` 与 BSL `lib/lighting/shadows.glsl:148-152`（`distortNBias * 5.0 * (2048.0 / shadowMapResolution)`）都显式除以 `shadowMapResolution`；RenderPearl（**MIT**）`lib/light/shadows.glsl:99-115` 用勾股恒等式一次求出法线偏移 + 斜率两项；Bloop `lib/shadows/shadowfunc_advanced.glsl:179-184` 是"斜率 × 畸变"双感知并显式对齐 `INV_SHADOW_RES`。
- **做法**：保留一个 texel 尺度公式，删掉另一条或明确其唯一适用条件；固定偏移 `+0.015` 改为按 `SHADOW_DISTANCE` 归一（与 P1-9 同一件事）。
- **成本**：局部改动，零额外采样。
- **许可证**：Miniature **MIT** → 可署名复用其语义规格；Bloop CC-NC-SA、ILV 专有、BSL ARR → 只读思路。bias 公式属数值/算法思想，但**逐字表达式**仍须按 Astra 风格自写。
- **验证**：`python qa/tools/shadow_frustum_probe.py` + `python qa/tools/validate_shadow_water.py`；`shadow_filter_equiv.py` 做前后等价性对照。

### P1-6 · 几何太阳遮蔽（1 像素 + alpha 广播）（已执行 · 见 11.F-9）

- **现状**：Astra 的太阳项是 `Astra/shaders/lib/uniforms.glsl:27 uniform float godraysExposure;`，其注释自述 = 基础曝光 × 视线夹角淡出 × 屏外淡出——**三个因子全是解析量，从不采样深度**。因此"太阳被墙挡住"当前拿不到一个**全局强度标量**。注意 `GODRAYS` march 内部已有逐样本几何遮挡（`Astra/shaders/global/post/godrays.glsl:32-36` 手工深度比较、`:71-73` 逐样本乘遮挡），所谓"穿墙"实际表现为**遮挡后整体强度不回落**——隔着厚墙看向太阳方向时，光束仍按解析曝光以满强度叠加。〔2026-09-20 复核更正：原文"会穿墙"忽视了 march 内的深度遮挡。〕
- **依据**：LIGHT `composite.fsh:423-433`（单像素 13×13 深度遮挡）→ `:582 gl_FragData[0] = vec4(color,gr)` → LIGHT `final.fsh:329 float sunvisibility = texture2D(gaux1,vec2(0.0015)).a * fading;` 读回。**注意：真正的缺口不是"没有光束"（Astra 已实装并已接入），而是"光束没有几何遮挡判定"。**〔2026-09-20 执行备注：执行 T9 时 LIGHT 原包目录已清理（`_analysis/study-2026-09-20/` 仅剩 ComplementaryUnbound_r5.9.3），上面三处行号抄自本报告、本轮未在本地重验；落地只依赖"角落像素探测 + alpha 广播"这一架构事实，不依赖行号与 13×13 这个具体尺寸。〕
- **做法**：在任一已有 composite pass 的角落像素做小窗口深度遮挡判定，结果写进**自有 buffer 的未用 alpha 分量**广播（Astra `Astra/shaders/lib/water_buffer_formats.glsl:12,15,16` 已有 R11F_G11F_B10F 声明，需另选一个带 alpha 的缓冲）。〔2026-09-20 执行后：载体 = `colortex1` 的 texel (0,0) alpha——R11F_G11F_B10F 系缓冲无 alpha 通道，而 `colortex1` 全包没有 `colortex1Format` 声明，走 Iris 默认格式；若该默认无 alpha，GL 对 `.a` 恒读 1.0，所以这条载体的最坏结果是静默空转（失败开放），不会反过来吞掉光束。窗口 = 7×7 抽、日面两侧各 ±12 深度像素，比原文的 9×9～13×13 更小；深度源 = `depthtex1`（仅不透明深度），玻璃窗与水面不得判成遮挡。越界抽点不计入分母、无在窗抽点时返回 1.0。〕
- **成本**：一个像素的 9×9～13×13 次 `depthtex` 采样 = 对整帧成本无影响。
- **许可证**：LIGHT = Chocapic13 Sharing Agreement → **只读思路**；窗口尺寸、权重、广播载体全部自写。PROVENANCE 记 `IDEA ONLY`。
- **验证**：`python qa/tools/water_path_probe.py`（墙后太阳场景）+ `compile_glsl.py`。〔2026-09-20 执行：`water_path_probe.py` 没有日面窗口场景，也没有"墙后太阳"情境，该验证条不可用。离线侧实际证据 = 两批编译（默认三档 `linked=267 failed=0 compute=27`；`GODRAYS` + `GODRAYS_SUN_OCCLUSION` 强制开单档 `linked=89 failed=0 compute=9`）+ `check_pack.py` 16 项门。观感判定进 `qa/regression-checklist.md` 17a 待实机。〕

### P1-7 · 焦散/消光烘焙进 shadow 阶段

- **现状**：Astra 的水体模型在像素端（`Astra/shaders/global/water/absorption.glsl` 80 行；`water_extinction()` `:42-44`；`water_transport()` `:48-54` 已含 `σs/σt·(1-T)` 单次散射源项）。**这条模型本身强于多数参照包**（Complementary 是 `lib/materials/specificMaterials/translucents/water.glsl:193` 的单行 `1-exp(d*0.075)`，RedHat 干脆无吸收），所以**不是为了"更正确"，是为了"同样的正确性花更少"**。〔2026-09-21 执行 T10 复核：本条要"烘"的东西**已经在包里**。`program/shadow.fsh:57-73`（`#ifdef WATER_CAUSTICS`）在水面 caster 上把 `solas_water_caustics()` 的聚焦图混进 `shadowTint`，`:74 shadowData = vec4(waterHeight, shadowTint)` 一次写出；消费方是 `global/water/light_shafts.glsl:125 texture(shadowcolor0, pos.xy).gba`——光束 march 已经在读烘好的值，而不是自己算焦散。像素端消光也**不是逐格光路 march**：`absorption.glsl:42-54`（`water_extinction`/`water_transmission`/`water_transport`）与 `:72-79`（`water_surface_medium`）全是 `exp(-d·σ)` 解析式，`d` 由几何求交给出。解析式没有"从像素端搬到 shadow 端"的成本可省——本条的收益前提在这两点上都不成立。〕
- **依据**：六例共识——Complementary `program/shadow.glsl:114-180`（焦散 + 光束）、BSL `program/shadow.glsl`、Solas `programs/shadow.glsl:58-77`、E-LITE `common/shadow_fragment.glsl:26,59-67`、SDV `main/shadow/shadow.glsl:161-177`、VanillaPlus `program/shadow/comp0.fsh:38-98`（**逐 texel 预计算 Beer-Lambert 消光系数**，最贴近 Astra 需求的一例）。〔2026-09-21 执行 T10：六例共识本身没被推翻，被推翻的是"Astra 还没有"这个前提——参照包的做法与 `program/shadow.fsh:57-73` 是同一种架构（Solas 的注释 `:55-56` 就写明是抄它的光图位置），差别只在 Astra 烘的是焦散、没烘 Beer-Lambert 消光系数，而后者在 Astra 是解析闭式、不需要表。〕
- **做法**：把与像素无关、只与"这段光路上有什么方块"有关的量（透光方块计数、逐通道消光累积）在 shadow/shadowcomp 阶段逐 texel 烘进 `shadowcolor` 的未用分量。Astra 有 12 条 shadowcomp 声明（M2 全场最多）⇒ **调度设施已经比多数参照包更完备，落地阻力小**。〔2026-09-21 执行 T10，两处实测不符。① **"未用分量"没有**：`shadowcolor0` 四个通道全花着——`global/lighting/shadowmap.glsl:49` 的头注写明 R=水面高度、GBA=透光 caster 染色，写出点 `program/shadow.fsh:74`，R 通道是 127 格窗口上的半格量化、256 个 R8 码值全部用满（精度问题已在早前轮次处理过一次）。再烘一个量要么挤掉高度、要么挤掉染色，两者都有现行消费者（`shadowmap.glsl:51-52,113,147` + `light_shafts.glsl:125` + `program/water_state.fsh:42-47`）。② **12 条 shadowcomp 声明不成立**：`shaders.properties:330-338` 实测 9 条（`shadowcomp` 与 A–H），且**每条都写着 `=NETHER_VOXEL_LIGHT`**，即 9 条全是熔岩侧体素光的开关，与"过场水面消光"无关；"设施完备 ⇒ 阻力小"这个推论对本条不成立。〕
- **成本**：shadow 阶段每 texel 一次；换所有像素端零成本。需保证 `shadowcolor` 有非零清屏色（BSL `program/shadow.glsl:44-46` 的 `vec4(0.25,...)` 教训）。〔2026-09-21 执行 T10：清屏色前提确实已满足，但**行号已漂移**——现值在 `Astra/shaders/lib/settings.glsl:369 const vec4 shadowcolor0ClearColor = vec4(1.0, 1.0, 1.0, 1.0);`（原文引 `:363`）。"换像素端零成本"这一半不成立：像素端是解析 `exp`，改成查图是**换成本而非省成本**（多一次纹理采样 + 一次烘图，省掉几条 `exp`），而烘图要挤占上面那些已被占满的通道。〕
- **许可证**：Complementary 专有 1.7、BSL ARR、Solas ARR、E-LITE/MakeUp LGPL、SDV FlameRender、VanillaPlus ARR+EULA §4 → **全部只读思路**。「烘焙进 shadowcolor」这一**架构选择**不受保护，具体 GLSL 表达式必须自写。
- **验证**：`python qa/tools/cost_census.py` 对比像素端抽样量；`validate_shadow_water.py`。〔2026-09-21 执行 T10：两条验证工具对本条均不可用——`cost_census.py` 的头注自陈它只做静态普查、**不是成本估算器**，拿它"对比抽样量"得不出本条要的结论；`validate_shadow_water.py` 当前是红的，且红因是它内嵌的 Java 侧方形 warp 模型已过时（与本轮无关的遗留项，已在线下清单）。因此本条的判定完全建立在对包内源码的直接测量上，见 §11.F-10。〕

### P1-8 · 硬件 PCF 默认档决策

- **现状**：`Astra/shaders/global/lighting/shadowmap.glsl:37-47` 两条路径都在（`SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE` → `uniform sampler2DShadow shadowtex0/1` + `SHADOW_FILTER_TAPS = 4`；`#else` → `sampler2D` + `TAPS = 16`），但 `Astra/shaders/lib/settings.glsl:57 #define SHADOW_FILTER_MODE 0` **默认走软件 16 抽**，且 `:329-336` 的 `shadowHardwareFiltering*` 仅在 mode 1 为 true。〔2026-09-21 执行 T11 复核：行号已漂移——`SHADOW_FILTER_MODE` 现值在 `settings.glsl:60`（`SHADOW_FILTER_SOFTWARE/HARDWARE` 常量在 `:33-34`），`shadowHardwareFiltering*` 三对在 `:335-342`（非 `:329-336`）。且它不是裸常量而是 GUI 选项 `#define SHADOW_FILTER_MODE 0 // [0 1]`（`lang/en_US.lang:15-18`：value.0=Software Bilinear (Default)、value.1=Hardware PCF），三档 profile 全部显式写 `SHADOW_FILTER_MODE=0`（`shaders.properties:149-151`），故"默认软件"是三档出厂配置而非仅 `settings.glsl` 一处默认。opt-in 的硬件分支不被任何出厂档选中——按 T9 立的"默认关分支须补一次强制开扫描"常设门，本轮 `compile_glsl.py --set SHADOW_FILTER_MODE=1` 强制三档走 mode 1 实测 `linked=267 failed=0`（`qa/glsl-2026-09-21-t11-hardware.log`，NVIDIA RTX 4050），并用工具的 `apply_profile_settings` 逐档验证展开确为 `#define SHADOW_FILTER_MODE 1`（对照出厂 BALANCED 展开为 `0`），排除"failed=0 其实仍编的是软件分支"这一假绿。〕
- **依据**：4 抽硬件 PCF 在 2026 年仍然够用且有两条实证——LIGHT `gbuffers_terrain.fsh:96-109`（`sampler2DShadow` + 4 角 `shadow2D` = 实际 16 texel）、VanillaPlus `program/gbuffer/forward.fsh:131-150` 用 `textureGather(shadowtex1, uv.xy, uv.z).wzxy` **一条指令拿 4 次硬件比较**（配 `:95-97 shadowHardwareFiltering`）。Astra 软件路径除 `:90-100 shadow_read_tap` 的逐 texel 夹边外，**已有两参 `textureGather`**（`:117-126 shadow_gather_visibility`，gather 原始深度后手工 `step` 比较，`:118-119` 注释自陈角序对应）——本条真正新增的只是 VanillaPlus 那种**三参 shadow-gather**（在 `sampler2DShadow` 上一条指令换 4 次硬件比较）。〔2026-09-20 复核更正：原文未提及 Astra 已有的 gather 路径。〕
- **做法**：用等价性测量决定默认值，而不是先验地选"软件更兼容"。若 `textureGather` 三参形式在目标 Iris 版本可用，把它接进硬件路径以省指令。〔2026-09-21 执行 T11 裁决：**默认档不改，本条零行为改动**（与 T8 同为纯登记单）。"用等价性测量决定默认值"已实跑 `python qa/tools/shadow_filter_equiv.py` → exit 0，`Overall max_abs=9.437e-16; FAIL=0`——在**可见性（penumbra）**这一维，软件 16 抽与硬件 4 抽数值恒等，故软件当默认**不是**因为它阴影更软（两者一样软）。真正分出高下的只有**彩色阴影**：软件逐角离散取 caster（`shadowmap.glsl:138-156`），硬件整窗只取一个中心材质近似（`diffuse.glsl:273-277`，且工具头注 `:128` 自陈"Hardware centre-tint approximation is not per-texel colour equivalence"）。这条差异 `lang/en_US.lang:16` 早已写明（"Software retains per-texel tint ... approximates transparent material boundaries with one central tint. Software is the default."）。于是"用等价性测量决定默认"的答案是：可见性打平、彩色软件更真 → **出厂默认保持软件，无需改**。"三参 shadow-gather 接进硬件路径省指令"一并**不采纳**：Astra 硬件路径是 4 个 *spread lobe*（±softness/2 偏移，`shadow_filter_uv:179-183`），而 `textureGather(sampler2DShadow,…)` 拿的是 *单个 lobe 的 2×2 四角*（正是软件路径 `shadow_gather_visibility` 已经在用的形态，只是 gather 的对象从 `sampler2D` 换 `sampler2DShadow`）；要用它就得把 4-lobe spread 换成 1-gather 足迹，那是改变硬件档观感的降级而非等价重写，且"省指令"的收益在本机**离线不可测**（`cost_census.py` 头注自陈非成本估算器、`qa/benchmarks.md` 空），证据链与 T10 成本条、T8 运动信号条同样断在此处。〕
- **成本**：仅切换默认值；风险是驱动侧 `sampler2DShadow` 行为差异 → 与 P2-13 的 `lib/compat.glsl` 有依赖关系。
- **许可证**：`sampler2DShadow` / `textureGather` 是 GLSL API 事实 → **无风险**。VanillaPlus 的具体写法 ARR → 只读思路。
- **验证**：`python qa/tools/shadow_filter_equiv.py`（两模式视觉等价性）+ `cost_census.py`；RenderPearl `world_default/setup.csh:3-12` 的 `#warning` 探测法可借用。

### P1-9 · `SHADOW_DISTORT_FACTOR` 按影距归一（已执行 · 见 11.F-5）

- **现状**：`Astra/shaders/lib/distort.glsl:7 const float SHADOW_DISTORT_FACTOR = 0.20;`（`:10 return length(pos) + SHADOW_DISTORT_FACTOR;`）**不随 `SHADOW_DISTANCE`（`Astra/shaders/lib/settings.glsl:67`，当前 256；`:219 shadowDistanceRenderMul = 1.5`）归一**。〔2026-09-20 执行后：该常量已在 `Astra/shaders/lib/distort.glsl:16-17` 改为 `SHADOW_DISTORT_CORE = 25.6` 除以 `float(SHADOW_DISTANCE)`；行号同时按实测校正，原引的 `settings.glsl:64/:216` 已漂移三行。〕
- **依据**：Sildur's `shaders.settings:39-45`：`b = (exp(Farshadowplane)-a)*shadowDistance/128.0` ⇒ **远端系数先除 128 再乘 shadowDistance，拉大影距时近端 texel 密度不被稀释**。这条同时治愈 P1-5 里 `:201` 自陈的固定偏移问题。
- **做法**：把畸变强度表达为 `f(dist, SHADOW_DISTANCE/128.0)`；在 PERFORMANCE↔ULTRA 影距变化下保持近端 texel 密度不变。
- **成本**：一个常数表达式，零运行时开销。
- **许可证 + 义务（本条最需注意）**：Sildur's = ARR → **只能取"按影距归一"这一思想，系数 `k=1.801`、`exp`/`log` 阶梯形状不得照搬**。且 `Astra/shaders/lib/distort.glsl` 是 **Steadfast GPLv3 + 附加条款的移植文件**（`§7b` 署名句 + `§7c/§7e` 强制文件名后缀），修改它必须保持这些附加义务不被削弱——**先跑 `python qa/tools/provenance_steadfast.py --quiet`，改完再跑，并用 `check_pack.py` 第 8 项与 `Astra/THIRD-PARTY.md` 对账**。
- **验证**：`shadow_frustum_probe.py`（不同 `SHADOW_DISTANCE` 下的近端 texel 密度）。

### P2-10 · `lib/vendor/` 物理隔离目录

- **依据**：JCL 把唯一真第三方文件放进 `licensed/spaceConversions.glsl` 并就地致谢（§2.18）；RenderPearl `lib/tonemap.glsl` 为每个算子就地内嵌上游许可文本。Astra 已有 `Astra/THIRD-PARTY.md` 台账但**没有物理隔离目录**。
- **做法**：新建 `Astra/shaders/lib/vendor/<upstream>/`，内含原始许可文本 + 一个 `README`，`Astra/THIRD-PARTY.md` 登记路径。**同时确立反规范：许可声明绝不乘以文件数复制**（VanillaPlus 224 份头 = 4,384 行 / 38.5%；Sildur's 109 份 = 1,526 行 / 8.2%；LIGHT 72 份 = 1,461 行 / 11.3%——三个包同一错误）。
- **许可证**：这是纯合规基础设施建设 → **降低风险**。
- **验证**：`check_pack.py` 增加一项：`lib/vendor/**` 内每个文件必须能在 `Astra/THIRD-PARTY.md` 找到登记行。

### P2-11 · buffer 清单与生效声明同体

- **现状（Astra 已做对，本节是防退化）**：Astra 的格式声明是**活的**——`Astra/shaders/lib/water_buffer_formats.glsl:12,15,16,18`（R11F_G11F_B10F ×3 + RGBA16）与 `Astra/shaders/program/end_illumination.fsh:10`（RGBA32F）、`Astra/shaders/program/end_sky_buffer.fsh:9`（RGBA16F）。
- **依据**：三个包在同一处腐烂——VanillaPlus `lib/pipeline.glsl` 53 行整体被 `/* */` 包住 ⇒ **12 个缓冲全跑在 Iris 默认格式上**；Sildur's `gbuffers_textured.fsh:23-34` 同型 ⇒ `sunPathRotation`、`shadowHardwareFiltering0/1` 一起失效；Bloop `program/final.fsh:4-47` 同型，且 `:30-38` 的两个条件分支写的是同一份声明。
- **做法**：在 `check_pack.py` 加一条静态检查：**任何出现在注释块内的 `const int colortexNFormat` / `const …Clear` 即为错误**；并要求每个被声明的格式都有至少一个消费者。
- **许可证**：无。
- **验证**：`check_pack.py` 新检查项 + `python qa/tools/sc35_image_analysis.py`。

### P2-12 · 选项穷举编译回归（优先级高于任何新特效）

- **依据**：VanillaPlus 的 `program/grade/grading.fsh:178 #define VIEWPORT_GAMUT` 是有完整 lang 文案、出现在主菜单的正式选项，改一下就让 `:182` 的未定义符号 `sRGB_P3D65` 编译失败（§2.19 缺陷 2）；JCL 的 `KILL_SWITCH` 有 UI 但零消费者（§2.18）；VanillaPlus 的 `profile.Fast` 里 `cloudVolumeFastMultiscatter` 全包零 GLSL 读取（§2.19）。**共同根因：没有"所有选项组合都编译一遍 + 每个 token 反查消费者"的习惯。**（RedHat 的 `A`/`B`/`C` 不属此类——它们有声明、能编译，只是不可调，见 §2.10。）
- **做法**：基于已有 `qa/tools/compile_glsl.py` 增加穷举模式：从 `Astra/shaders/shaders.properties` 的 `screen` 块解析全部 token 与取值域，抽样跑笛卡尔积（同族选项全组合、异族选项贪心覆盖），并对**每个 `#define` 反查是否有读取点**（抓 `KILL_SWITCH` 类）。
- **成本**：一次性脚本投入；本地跑，无 CI 依赖。
- **许可证**：无。
- **验证**：本条自身即验证工具；输出接进 `check_pack.py`。

### P2-13 · MIT 可署名复用清单（本次唯一能"直接搬"的部分）

| 件 | 来源 `path:line` | 用途 | 许可证动作 |
|---|---|---|---|
| 驱动/加载器兼容层 | RenderPearl `prelude/compat.glsl:14-249` | 新建 `Astra/shaders/lib/compat.glsl`：`IRIS_VERSION` 门、扩展三级开关、`#undef INT16/INT8` | 建 `lib/vendor/renderpearl/` + MIT 原文 |
| CAS 风格自适应锐化 | LIGHT `final.fsh:214-251`（**ARR，仅思路**）；RenderPearl/Mellow 的 AMD MIT 版 | 替换/增强现有锐化路径 | 取 MIT 实现，不取 LIGHT 的系数 |
| 归一化相位函数 | 公开论文（HG/Schlick）；Noble `include/utility/phase.glsl:34-68` **GPL 禁抄** | 水面/体积散射 | 据论文自写 |
| Vogel 圆盘 / 蓝噪声取点 | Photon `include/utility/sampling.glsl:4-11`（专有，思路）；Bloop `lib/shadows/shadow_misc.glsl:13`（CC-NC，思路） | 替换 `Astra/shaders/global/water/light_shafts.glsl:80` 的外部噪声图抓取 | 自写，`Astra/shaders/lib/bayer.glsl` 已有基础 |
| `pack_unorm_2x8` | Photon `program/gbuffers_all_solid.fsh:389`（专有，语义规格）；Bloop `lib/encoding.glsl:22-29`（CC-NC，HLSL 内建规格） | G-buffer 通道压力 | 按公开语义自写，登记为"依规范实现" |
| 原版光贴图当 LUT | Miniature `common/getAmbientColor.glsl:2` | 零成本天光色 | **MIT**，包内无 LICENSE → 自写标准 MIT 声明 + 来源 URL/版本 |
| 16 格量化阴影采样 | Miniature `common/getLightStrength.fsh:11-12` | PERFORMANCE 档降本 | **MIT**，同上 |
| SMAA | Mellow（唯一实装）| 若 Astra 要 AA，这比 TAA 便宜 | **MIT** |
| `get_min_light`（绑 `screenBrightness`/`nightVision`） | Mellow | 曝光下界 | **MIT** |
| 通用 primaries → RGB↔XYZ 矩阵 | Bloop `program/final.fsh:107-122` 的**同一算法**在 CIE 有公开规范 | 显示色域 | 依 CIE 自写，与 Bloop 无关 |

### P2-14 · 顶点级连续渲染分辨率旋钮

- **依据**：Bloop `program/fog_translucent_lowres.vsh:20`（1% 粒度，无 `size.buffer`）；Noble `shaders.properties:347-353`（滑杆驱动 `size.buffer.colortex12`）。Astra 有 6 条 `size.buffer.*` 但**没有连续旋钮**，M4 显示 3 档是唯一降级粒度。
- **做法**：给光束 / 水下光柱 / 云这三个高成本阶段各加一个顶点级百分比缩放 pass。
- **成本**：需要额外的低分辨率中间缓冲与一次上采样。
- **许可证**：Bloop **CC-BY-NC-SA → 必须重写**；Noble **GPL → 必须重写**。两条都是"用顶点输出缩放视口"的通用图形技巧 → 思想级可用。
- **验证**：`cost_census.py` 量化每个百分比下的抽样总量。
- **裁决（T12 · 暂缓，零改动，见 11.F-11/11.F-12）**：这条正是 §11.B 说的"P0-1 定调后再评估"的那次评估。结论**不投机实现**：光束缓冲那一维已由 T1 用 `#if UNDERWATER_SHAFT_SAMPLES<7` 做成随用户滑杆的两档、且其消费者按 `textureSize()` 推 tap（缩放免费），再加连续旋钮是重复；云阶段要做得新建整套低分缓冲+上采样。收益（亚档位性能/画质取舍）离线不可测（`cost_census.py` 自陈非成本估计器、`benchmarks.md` 空），许可两条参照都"必须重写"，且一个无出厂档启用、无人测过质量收益的连续滑杆正是 §7.B.6 禁止的"暴露但零消费者"化石。重开条件见 11.F-12。

### P2-15 · 反射路径的云/噪声八度减半并重归一

- **依据**：Sildur's `deferred.fsh:337+` `int maxOctaves = isReflection ? 2 : 4;` + `if (isReflection) noise *= 1.2; //normalize noise scale when skipping octaves`，配预计算 `vec4 stepsScale/stepsWeight` 与注释里的推导公式。`Astra/shaders/global/atmosphere/clouds_planar.glsl`（324 行）、`Astra/shaders/global/water/refraction.glsl`、`Astra/shaders/global/water/raytrace.glsl` **对反射路径完全不做质量降级**。
- **做法**：反射调用点传 `isReflection`，八度减半并按预计算权重重新归一（避免"少一层噪声就变暗"）。
- **许可证**：Sildur's **ARR → 只读思路**；八度权重是通用 mipmap/fBm 数学。
- **验证**：`water_path_probe.py` + `cost_census.py`。

### P1-16 · 光束时域自适应采样（vlFactor + 状态像素 + 运行时循环上界）（不采纳 · 前提证伪，见 11.F-8）

- **现状**：`Astra/shaders/global/water/light_shafts.glsl` 的 `UNDERWATER_SHAFT_SAMPLES` 是编译期常量（`Astra/shaders/lib/settings.glsl:136`，7/7/10 三档），静止观赏时质量不足、移动时白付〔2026-09-20 执行期更正：后半句从未被测得——包内没有任何水下帧时间基线，见 11.F-8〕。
- **依据**：Complementary Unbound `lib/atmospherics/volumetricLight/volumetricLight.glsl:9,183,321-346`（§2.1 新增 bullets）——`vlFactor` 持久化在 `colortex5` 末像素 `.a`，静止爬升、运动回落〔2026-09-20 执行 T8 时逐行读参照包源码证伪：驱动信号是**阴影图里的遮蔽物高度与画面是否有开阔天空**，与相机运动无关；且参照包在水下把它钉死为 1.0。全文见 11.F-8〕，驱动 `nearSamples`/`farSamples`。**前提条件须先修正**：真正的阻塞站点不是 `light_shafts.glsl:110,125`——`shadowtex1`/`shadowcolor0` 在全包没有任何 mipmap 声明，隐式 LOD 只能取到 level 0，实际无害（改 `texelFetch` 属于卫生改进）。必须修的是 `Astra/shaders/global/water/bloom_capture.glsl:21`：`colortex0` 经 `program/water_bloom.fsh:5` 开了 mip，外层 `if` 又是数据相关分支，那里才是真正的未定义行为（§9.4 前置项、本条下方）。引入运行时循环上界前须先按 Complementary Unbound 的做法消掉这类隐式 LOD 站点——它 `:201` 的注释原话："We need to use texelFetch here or a lot of Nvidia GPUs can't get a valid value"。
- **做法**：新增 1×1 缓冲挂 `astraVlFactor`——colortex6 **没有空闲通道**（`Astra/shaders/global/water/medium_state.glsl:5`：RG = 1/16 格水面高度、B = 天空通达、A = 有效位，四通道全占）；〔2026-09-20 执行期更正：升降条件按参照包应为「阴影图日方向遮蔽物均值 `salsCheck` 超阈值则 `+= OSIEBCA`、画面有开阔天空则按 `reduceAmount` 回落」，不是静止/运动；见 11.F-8〕`UNDERWATER_SHAFT_SAMPLES` 从编译期常量改为该标量驱动的运行时上界。**前置修复**：见上方「依据」——`bloom_capture.glsl:21` 是必修项（已随 T7 闭合，11.F-7），`light_shafts.glsl:110,125` 是可选卫生改进。
- **成本**：一个 1×1 状态通道 + 循环上界改运行时。
- **许可证**：时域自适应采样 + 状态像素持久化是通用图形技巧 → **无风险**。
- **裁决（T8）**：**不落地**，不留缓冲、不留选项、不留死代码。三条独立理由与全部行号引证见 11.F-8：① 参照包自己在水下把该因子恒置 1.0，搬到 Astra 唯一使用它的 `isEyeInWater == 1` 路径上净收益按参照包判断为零；② 原设想的"运动降质"信号在受调研的每个包里都没有先例，且与 Astra 无 TAA 的静态 dither 设计正面冲突；③ "白付/成本不升"两侧都不可离线测量（`qa/benchmarks.md` 无 FPS 数据，`cost_census.py` 文件头自己声明它不是成本估计器）。重开条件写在 11.F-8 末段。

### P1-17 · 水吸收侧面深度界 + 未命中近场缓释（已执行 · 见 11.F-6）

- **现状**：`Astra/shaders/program/water.glsl` 的 `water_sample_path`（改前 `:31`，现 `:45`）在空气侧用 `dot(origin−point, faceNormal)`（改前 `:80`/`:96`）求几何深度。〔2026-09-21 复核更正：**症状方向与原文相反**。该点积是"水面所在平面"到背景命中点的**垂直距离**：顶面上它就是真实水柱（无界，正确）；侧面上它退化成相机到背景的距离，于是平视一条水渠/瀑布侧面时，整段视野被当作水体吸收——**过吸收**，不是原文说的"≈0、几乎不吃吸收"。〕〔2026-09-20 复核更正：函数不在 `global/water/absorption.glsl`。〕
- **依据**：Steadfast 0.8.0 `environment/water/absorption_refraction.glsl:22-120` 三分支——① 顶面用几何深度（Astra 已有）；② 非上向水面用背景天光作深度代理 `waterDepth = (−15/16)·skylight + 1`（单条 FMA）；③ 未命中分支按距离线性减浅 `waterDepth = 0.25 + 0.75·min(−z/24, 1)`。〔2026-09-21 复核更正 ②：**不必引入 skylight 代理**。代理式已在参照包源码核对为真（`absorption_refraction.glsl:85` 取 lightmap skylight、`:92` `waterDepth = (−15/16)·skylight + 1`），其取值域就是 1/16..1 块（露天 skylight=1 ⇒ 1/16 块，全遮 ⇒ 1 块）；而 Astra 侧面上缺的正是同一个"≤1 块"上界：一个水块只在**该法线方向的邻格不是水**时才渲染这个侧面，所以沿该法线的水体厚度 ≤ 1 块。纯几何界取的正是该代理的上界，差别在代理把露天侧面再压到 1/16 块——那是"露天 ⇒ 水浅"的光度假设，而瀑布侧面恰恰露天且真有 1 块厚。本条按几何真值落地，1 块是否在瀑布上偏浓记待实机（见 11.F-6）。〕〔2026-09-20 复核更正：原文"返回固定水体色"与 miss 分支实际行为相反——Astra 的未命中是 validity=0、回落到未偏移的不透明路径（`program/water.glsl:26-27,90-112` 改前行号），无近场水体色 ⇒ 瀑布背后、浅水贴地平线处**偏亮**而非偏浓。〕
- **做法**：侧面加 `min(depth, 1.0)` 几何界（`view_player(faceNormal).y > 0.9` 判定上向面，阈值与包内既有顶面约定一致：`lit.fsh:367`/`lit.fsh:271`；几何法线来自 `faceData` 八面体解码 `lit.fsh:85`，轴向量化，硬分支安全）；未命中分支改为**以该像素的 scene copy 为背景**、按相机深度线性增浓 `mix(0.25, 23.0, clamp(−z/24,0,1))` 再走同一个 `water_surface_medium`。背景取 `colortex4` 的理由在源码里：`deferred.fsh:103` 存 colortex0 的线性 scene copy、`:185-186` 明确把 `astra_sky` 合成进去并注明"Refraction/SSR background must also contain sky"、`:190` 写出，而 `water_sample_path` 的采样点（`:80`/`:92`/`:109`）读的就是同一张缓冲的同一份未解码值。不照搬 Steadfast 的两处：它的 `background *= 1 − fade` 会与 `water_surface_medium` 内部的 `exp(−depth·σ)` 叠成双重淡出；它的 1 块深度上界属于侧面情形，套在未知水柱上会砍掉真实深水。
- **成本**：一次 `view_player` 点积 + 一个 `min` + 未命中像素一次 `texture()` 读（原本该分支零读取）。
- **许可证**：Steadfast GPLv3 + §7b/§7c 附加条款 → 可修改但须保持附加义务（`python qa/tools/provenance_steadfast.py` 前后对账）。表达式自写。
- **验证**：`water_path_probe.py` 覆盖瀑布、浅水贴地平线、平视三种边界——本轮已按此条补齐（瀑布眼平以上：mode 11/12；贴地平线未命中：mode 9/10 + 16/21；平视/竖直几何：mode 17–20），并新增 11 条针对本条的断言，见 11.F-6。这 11 条分两类：5 条（mode 9 改前式 vs mode 10 改后式）把两个表达式**编在同一次编译里并排比较**，是留档不是守门；另外 6 条读落地文件——mode 17/18 直接调 `water_surface_absorption_depth`、mode 20 用它而 mode 19 用改前点积、mode 7/8/15 跑完整 `astra_water()`。两条反向验证都做过：抽掉侧面 `min` 界 ⇒ `water_path_probe.py:280`（mode 17 墙面深度）先红、`:282`（mode 19 改前点积 vs mode 20 落地 helper）随后也红（两者取值变成逐位相同），`:281`（mode 18 顶面）不受影响——顶面本就不设界；只把未命中回落改回改前的 96 块追踪形态 ⇒ **只有** `:306`（mode 15 瀑布对 mode 7 平视）转红，同距离两者必须一致，旧式按射线方向取值差一个数量级，而 near/far 比与蓝移两条在改前也通过，只能算形状留档。

### P2-18 · `dimension.properties` 按维度裁剪管线（已执行 · 见 11.F-4）

- **现状**：Astra 所有维度跑同一套管线，下界/末地无专属 pass 但也不关掉主世界专属 pass。
- **依据**：Complementary Unbound `dimension.properties`（`dimension.world0=*`）+ `shaders.properties:95-112`（§2.1 新增 bullet）——按维度禁用/启用 pass。原文附加的"缓冲尺寸跟随维度配置"经复核**不成立**（见下）。
- **做法**：按维度关掉闲置管线 pass 用 `program.<world>/<pass>.enabled=` 一条键即可，且**不需要 `dimension.properties`**：`world0`/`world-1`/`world1` 三个目录名是 `ShaderPack` 构造器里的遗留缺省映射，仅在 `dimension.properties` 缺失或为空时生效——新写一个只声明 `world0=*` 的文件反而会顶掉这条缺省分支。colortex1 在闲置维度的分配**省不掉**：`size.buffer.*` 以裸缓冲名为键，`ShaderProperties` 没有目录上下文，四个参照包也零处使用带 world 前缀的 `size.buffer.`；`blend.*`、`texture.*`、`image.*`、`uniform.*` 同理，带 `<world>/` 前缀即永远查不到。
- **成本**：纯配置层，零 GLSL 改动。本条真实收益在下界那 9 个 `shadowcomp*` compute 调度。
- **许可证**：Iris API 事实 → **无风险**。
- **验证**：`check_pack.py` 第 16 项（键族与维度目录一致性）+ `inspect_iris_properties.py`（各维度 pass 启用表）+ 矩阵门；`cost_census.py` 的闲置缓冲显存一项因上述键限制而不可达，已撤销。

### P2-19 · 光束 / 反射分辨率用户选项

- **现状**：Astra 的光束 march 分辨率 0.5、colortex7 分辨率 0.25 是硬编码，没有用户选项。
- **依据**：Bloop `program/fog_translucent_lowres.vsh:20`（1% 粒度连续滑杆）；Noble `shaders.properties:347-353`（滑杆驱动 `size.buffer.colortex12`）；Complementary Unbound `lib/common.glsl:240 #define REFLECTION_RES 0.5 //[1.0 0.5]`（§2.1 新增 bullet）。
- **做法**：给光束 march / 反射缓冲各加一个 LOW/HIGH 选项（LOW=0.25、HIGH=0.5），低配用户再多一档退路。
- **成本**：需要额外的低分辨率中间缓冲与一次上采样。
- **许可证**：Bloop CC-NC-SA、Noble GPL → **必须重写表达式**；思路级可用。
- **验证**：`cost_census.py` 量化每个分辨率下的抽样总量。
- **裁决（T12 · 已由 T1 实质满足，零改动，见 11.F-12）**：本条按 §11.B 并入 P2-14 同单执行。前提已被 T1 顺带满足——光束 march 缓冲 colortex1 已是"随用户滑杆两档（`#if UNDERWATER_SHAFT_SAMPLES<7` → PERF 0.25 / BAL+ULTRA 0.5）"，无需另立 LOW/HIGH。且本条把 colortex7 归因错：它是**水下泛光缓冲**（`shaders.properties:32-34`，0.25 是省显存的性能选择、非待暴露的质量档），反射是屏幕空间无独立分辨率缓冲可加档。引证 `:14,19` 亦漂移到 :21/23/35。结论：不落地。

### P2-20 · 光束标定三条（Solas V3.7b 参照）

- **现状**：Astra 09-20 修复后的光束强度门 `mix(0.25+0.25·VoL, 0.45·VoL, time)` 白天端仍会归零。【2026-09-21 T13 就地更正：公式抄写准确，归因错。门在正午确实对常见视角整片归零（看海床时 `VoL=0`），但真因不是"强度门缺下限"——`refract()` 的入参用成了"指向太阳"的向量，GLSL 规范式给出 `refractSun.y = +sqrt(1-eta^2(1-sunWorld.y^2)) > 0`（正午精确等于 `(0,1,0)`：正入射不弯折），所以该方向**朝上**，与视线向下的海床像素恒为负。补下限只是把符号错的门盖住，正解是把入参改成光的传播方向。见 11.E-8】
- **依据**：Solas V3.7b `lib/atmosphere/volumetrics.glsl`（§2.4 新增 bullets）——① 强度曲线改软平方瓣 + 下限 `(1+2·VoL²)·(0.25+1.75·sunVisibility)`；② 采样改指数距离分布 `exp2(dither)` 每样本 ×2；③ 颜色随时刻向天空色混合 `fmix(lightCol, nSkyColor, timeBrightness·0.75)·0.1`。【2026-09-21 T13 本地重验：三条全部对上 V3.7b 源文件（`_analysis/latest-2026-09-10/solas-shader`，`sources.json` 记录 version=3.7b、Modrinth `Solas Shader V3.7b.zip`）——① 在 `:56` 且正是 `isEyeInWater == 1` 那一支（同支把空气侧 intensity 整体丢弃，故"替换"而非"叠加"是参照包自己的行为）；② 在 `:192-194`，`currentDist = exp2(dither)` 起步、循环 `currentDist *= 2.0`，"每样本 ×2"准确，但参照包**不设上界**、靠 `:195/:200` 两个 break 收尾；③ 在 `:130-131` 逐字符一致。未读取参照包 `drm/` 目录，未引入 `SOLAS_BY_SEPTONIOUS`】
- **做法**：三条分别替换 Astra 的对应位置——强度门、均匀步进、固定染色。
- **许可证**：Solas ARR → **只读思路**；表达式必须自写。**禁止引入 Solas DRM 宏**。
- **验证**：`light_shafts` 现有探针对拍正午/晨昏/水下三场景。【2026-09-21 T13 就地更正：该前提不成立——`qa/` 内没有任何探针走过光束门，`water_path_probe.py:216` 恰恰以 `UNDERWATER_LIGHT_SHAFTS=None` 把它关掉。全库检索 `water_shafts_march` / `water_shafts_view` / `solas_sun_visibility` / `astraSolasTimeBrightness` / `refractSun` 零命中。见 11.D-17】
- **裁决（T13 · 已执行，默认关，标注待实机，见 11.F-13）**：三条全部实装，收在单一开关 `UNDERWATER_SHAFT_CALIBRATION` 后面（沿用 T9 `GODRAYS_SUN_OCCLUSION` 的形态），三档 profile 一律 `!` 关闭 → 出厂观感逐字节不变，符合用户裁定「实现但默认关，标注待实机」。① 有一处必须偏离参照包：Solas 原式峰值 6.0，Astra 出厂正午峰值 0.45，直接替换会亮约 13 倍，故乘 `0.075 = 0.45/6` 归一化，让开关只改衰减形状不改总亮度。② 改成有界形式 `maxDist·(exp2(u)-1)`，保留"近场加密"这一实质、去掉参照包的无上界步进。③ 不照搬 `·0.1`——参照包那一项是加性光源缩放，Astra 的 `col` 是 `col*col` 染色乘子，照搬等于顺手调暗。绝对权重与混合强度都是起点值，待实机 A/B。

---

## 7. 明确不建议做的事（含被推翻的"缺口"）

**A. 本次调研推翻的既有"缺口"主张**（这些 Astra 已经有，不要再提）：

| 曾经的判断 | 实测 |
|---|---|
| "水下光束未实装" | 已实装并已接入：`Astra/shaders/global/water/light_shafts.glsl`（`:87 distort(player_shadow(point))`、`:110 texture(shadowtex1,pos.xy)`、`:80` 取 dither 并作为 `:83` 首采样偏移、`:64/:84/:92/:112` 四处早退）→ `Astra/shaders/program/water_composite.fsh:16 water_shafts_view()`，开关 `Astra/shaders/lib/settings.glsl:131`、步数 `:136` |
| "godrays 未实装" | `Astra/shaders/global/post/godrays.glsl` 80 行活跃，`Astra/shaders/program/final.fsh:26,50-61` 消费，`Astra/shaders/program/scattering.fsh` 是两段式设计的第一步 |
| "向 Solas 学吸收模型" | **方向反了**：`Astra/shaders/global/water/absorption.glsl` 有逐通道 `water_absorption_coefficient()`、三套 `WATER_CHARACTER` 谱（`:16-34`）与 `water_transport()` 的单次散射源项；Complementary 是单行指数近似，RedHat 全包 `absorption` 零命中。**Solas 提供的是"烘焙位置"，不是"模型"**（§6 P1-7） |
| "Astra 用不了/不该用 compute" | `.specs/astra-shader/design.md:50` 的「零 compute」**已在 `:517` 修订**为「9 个 compute 阶段 + 3 张自定义图像」的一等公民例外，12 条 shadowcomp 是全场最多（M2） |
| "Astra 没有 qa 工具链" | `qa/tools/` 实有 18 个脚本（含 `check_pack.py`、`compile_glsl.py`、`provenance_steadfast.py`）。此误判源自**把模组目录 `Astra/` 误当仓库根** |
| "Astra 的 buffer 格式声明是死的" | 活的：`Astra/shaders/lib/water_buffer_formats.glsl:12,15,16,18` 等 6 处（§6 P2-11） |
| "Astra 没有 GUI 选项 / 配置层落后" | `option.`/`slider.`/`tweak.` 全场为 0（§4.5），Astra 写法即主流 |

**B. 本次样本给出的"不要做"结论**：

1. **不要引入 TAA**（当前阶段）。依据：VanillAA 的显式论证（§2.16）——触发条件是"Astra 开始用随机/蓝噪声采样（PCSS、体积步进、SSGI）"；且 B 组 5 款里 4 款 TAA 为 0（MakeUp、E-LITE、Miniature、SDV），唯一非零的 VanillAA 本身就是 TAA 包。
2. **不要加 SSAO/HBAO**。严格口径（`_meta/ao_recheck.py`：只扫 GLSL、剥注释、只认 `HBAO|SSAO|GTAO`）为 **19 款里 10 款非零、Astra 0，低配组 5 款里 4 款为 0（只有 SDV 14）**。M3 的「HBAO/SSAO」列是宽松命名口径，不可当 SSAO 普查用（§3.5）。
3. **不要逐文件复制许可头**。三个包同一错误：4,384 / 1,526 / 1,461 行零信息复制。合规集中放 `LICENSE` + `lib/vendor/`。
4. **不要为了 DRY 把维度目录做成整段复制**。Sildur's 97.6%、VP 的 `world0/composite1.fsh` 三份漂移、LIGHT 40.3%、Miniature 与 ILV 的 `style_*` 差分副本，全部指向同一后果。Astra 现有 4 行派发器形态**优于全部样本**。
5. **不要以注释形式记录任何配置**（§6 P2-11）。
6. **不要引入任何暴露但零消费者的选项**。JCL `KILL_SWITCH`、VP `VIEWPORT_GAMUT`、`profile.Fast` 里的孤儿 token `cloudVolumeFastMultiscatter` 都是同一类化石；`check_pack.py` 的穷举检查（§6 P2-12）是结构性防线。
7. **不要模仿任何 `#version 120` 外壳**（JCL 的 120 是从模板继承的死壳，且其 include 目标在用 GLSL4 的 `texture()`）。Astra 是 400/430/460，保持即可，但要把依赖写成显式 `iris.features.required`。
8. **不要把画质档位做成散文注释**（Sildur's `shaders.settings:37-41,70` 的 `6=lite, 8=med, 10=high, 12=extreme`，且 `:37` 把 80 写了两遍）。
9. **不要加 100+ 调色板滑块**。Complementary Unbound `shaders.properties:68` 有 100+ 个 `LIGHT_NOON/MORNING/NIGHT/RAIN × RGB` 滑块——与 Astra design 3.3 的「少而精」直接冲突；Astra 的调色集中在 `grading.glsl` 单文件，这是更优的架构。
10. **不要现在引入 TAA**。Complementary Unbound 有完整 TAA 参考实现（§2.1），但 Astra design 2.4 已明确「无 AA」；触发条件（随机/蓝噪声采样）尚未出现，且 B 组 5 款里 4 款 TAA 为 0（与 §7.B.1 一致）。

---

## 8. 许可证风险总表

| 包 | 许可证类别 | 对 Astra 的判定 | 硬约束来源 | 本文引用是否需 `IDEA ONLY` 注 |
|---|---|---|---|---|
| Complementary R/U | 自定义 License Agreement 1.7（专有） | **只读思路** | 专有条款 | 是 |
| BSL | All Rights Reserved | **只读思路** | ARR | 是 |
| Photon | 自定义 LicenseRef | **只读思路**；例外：`include/post_processing/aces/` 自带 AMPAS 许可 → **可署名复用** | LicenseRef 全文 | 是（aces 除外） |
| Solas | All Rights Reserved | **只读思路**；**禁止引入 DRM 宏 `SOLAS_BY_SEPTONIOUS`** | ARR + `drm/drm.readme` | 是 |
| **Mellow** | **MIT** | **可署名复用** | 保留版权行与许可文本 | 否（登记） |
| I Like Vanilla | What42's Shader License 2.2 | **只读思路** | 2.2 条款 | 是 |
| **Noble** | **GPL-3.0-only** | **禁止复用（传染）**，相位函数/DDA 须据公开论文自写 | GPL-3.0 | 是（禁抄） |
| **Bloop** | **CC-BY-NC-SA-4.0** | **硬阻塞（NC + SA）**；且**包内无许可证文件** → 任何引用前须先固定来源 URL + 版本并自撰署名 | CC 条款 + Astra 发布意图 | 是（禁抄） |
| **RenderPearl** | **MIT** | **可署名复用（本次最优）**；其 `lib/tonemap.glsl` 内联上游许可的做法可作模板 | 保留许可文本 | 否（登记） |
| RedHat | Chocapic13 Agreement | **只读思路**；`:13` 强制改名条款 **Astra 不可能满足** → 不存在合规复用路径 | `:12 :13 :15 :17 :18` | 是 |
| LIGHT | Chocapic13 Sharing Agreement | **只读思路**；`physics_ocean.*` 上游为 Physics Mod（第三方 ABI），须对接 `github.com/haubna/PhysicsMod` 而非 LIGHT | 同 Chocapic13 谱系 | 是 |
| Sildur's | All Rights Reserved（banner 明写） | **只读思路** | `shaders.settings:9-13` | 是 |
| MakeUp | LGPL-3.0-or-later | **按不可复用处理**：GLSL `#include` 是文本展开，编译单元即派生，LGPL 的链接隔离在此无边界 | LGPL-3.0 | 是 |
| E-LITE | LGPL-3.0-or-later | 同上 | LGPL-3.0 | 是 |
| **Miniature** | **MIT** | **可署名复用**；**但包内无 LICENSE 文件** → Astra 须自撰标准 MIT 声明 + 来源 URL/版本 | MIT | 否（登记） |
| **VanillAA** | **MPL-2.0** | 根文件**可复用**（文件级许可，隔离性好）；**`bsl_lib/` 是 BSL 专有 → 必须重写** | MPL-2.0 + 子目录例外 | 部分（`bsl_lib/` 禁抄） |
| Super Duper Vanilla | FlameRender/TM Studios v1.6 | **只读思路** | §1.4 | 是 |
| JCL（对照） | ARR，且明文 "Do not steal any of this code or use \"code snippets\"" | **最低等级：只读思路、禁止片段级引用**；`licensed/` 的**组织做法**可照搬 | ARR + 片段禁令 + 内部矛盾（README 宣告 AR 而 `shaders/composite.fsh:3` 内嵌 MIT 免责模板但无授权段 → 不得据此推定授权） | 是（不得逐行对照） |
| VanillaPlus（对照） | ARR + 自拟 EULA | **只读思路**；EULA §4（部分使用亦需许可）+ §6（可追溯变更）比一般 ARR 更硬；**`img/noise2D.png` 亦不得使用** | `LICENSE` 4,095 B §4/§6 | 是 |

**表外两项**：`rethinking-voxels-source` 与 `steadfast-shaders-source` 不属于本次 19 款，是姊妹文档（docs/2026-09-20-reference-pack-study.md）的参照包——前者的 Complementary License Agreement 1.5、后者的 GPL-3.0 加 §7b/§7c 附加条款，由该文档单独判定。**该文档的 `path:line` 引用不在本文 `check_citations.py` 的校验范围内**（脚本的输入只有本文件），本表也只覆盖 §1 入样的 19 款。

**统一合规路径（本次采纳）**：读 → 在本文件记思想 → 按 Astra 风格（`#version 400+`、`sampler2DShadow`、`lib/` 单一 token）重写 → 在引用处按 `Astra/shaders/global/post/grading.glsl:210-212` 的既有格式写 PROVENANCE：

```
// PROVENANCE: adapted from <pack> <version> (<license>) - IDEA ONLY, no code and no formula transplanted
```

思路级引用写就地注释；**任何整文件搬运进 `lib/vendor/`（学 JCL 的 `licensed/`）+ 就地附原始许可全文**（学 RenderPearl 的 `lib/tonemap.glsl`）。Steadfast 类移植文件仍须保持 `§7b` 署名句与 `§7c/§7e` 文件名后缀义务。

---

## 9. 附录

### 9.1 复现命令

```bash
# 取数（Modrinth v2）
python _meta/collect_modrinth.py         # → modrinth_top100_enriched.json/.csv
python _meta/download_packs.py           # → _downloads/ + downloads.json（sha1）
python _meta/authors.py                  # → authors.json
# 测量：census / astra_census / feature_matrix / pipeline_metrics 四份 JSON 是 §3 四张表的唯一数据源
python _meta/census.py                   # → census.json（GLSL 结构指标，逐个保存目录）
python _meta/census_astra.py             # → astra_census.json（ASTRA 行，与 census 同口径）
python _meta/feature_matrix.py           # → feature_matrix.json（M3 命名命中、profile/sliders 计数）
python _meta/pipeline_metrics.py         # → pipeline_metrics.json（M2 pass 声明、M4 的 screen/variable/size）
python _meta/props_census.py             # → props_census.json（properties 指令词表，§4.5 用，不进矩阵）
python _meta/matrix.py                   # → matrix.md（渲染出本报告 §3.1–§3.4 四张表）
# 严格口径复核：§3.5 与 §7 的 SSAO 分母来自这里，不是来自 M3
python _meta/ao_recheck.py               # → ao_recheck.json（只扫 GLSL、剥注释；19 款 + ASTRA = 20 行）
# 口径抽查：验证 §3.5 的 .dat 假命中数与 §5.1 表里的每一行
python _meta/check_noble_dat.py          # → Noble 宽松列 42 / 严格 GLSL 25 / 两个 .dat 贡献 18（严格词表下 4）
python _meta/check_commonality.py        # → §5.1 的 tonemap 18/21、break|discard 20/21、#if 21/21、screen 21/21、sliders= 恒 1
# 表格校验：报告 §3.1–§3.4 与 matrix.md 逐格比对
python _meta/tablecheck.py               # → 872 个数值格，0 处不一致
# 分母校验：任何 "N/M 包有 X" 的句子都应由它复现
python _meta/denoms.py                   # → 21 集合与 19 款两个分母下的非零清单
# 引用校验（须 cd 到 C:\Users\杨铭\Desktop\光影包；Windows 下加 PYTHONIOENCODING=utf-8）
python _meta/check_citations.py          # → 逐条校验本报告全部 path:line 引用，按缺陷类型分桶计数
# 结构校验：数字都对但排版坏了，前两道门是查不出来的
python _meta/final_sweep.py              # → 九项：加粗冲突/加粗不成对/表格行列数/残留 /22 分母/章节缺失/§引用悬空/_meta 文件缺失/未替换标记/代码围栏配对
# 借鉴报告逐条核验（37 项检查，须 cd 到光影包根；Windows 加 PYTHONIOENCODING=utf-8）
set PYTHONIOENCODING=utf-8 && python _meta/verify_reference_study.py   # → 27 真 / 4 行号错 / 2 不成立 / 1 文件错 / 1 机理错 / 1 参数化描述错 / 1 需修正
# Astra 侧门禁（本仓库内；P0-1、P2-10、P2-11 与 P2-12 的实测数字全部由下列命令复现，Windows 加 PYTHONIOENCODING=utf-8）
python qa/tools/check_pack.py              # → 16 项，含 #12 档位取值差量、#13 选项消费者/分支符号（P2-12）、#14 缓冲声明活性/唯一/有读者（P2-11）、#15 lib/vendor 隔离与许可正文（P2-10）、#16 按维度裁剪用的键 Iris 是否解析（P2-18）
python qa/tools/test_gate_sensitivity.py   # → #14/#15/#16 的灵敏度自证：14 个场景在临时副本上注入既有缺陷形态，断言逐条精确触发且两个对照仍全绿
python qa/tools/inspect_iris_properties.py # → 驱动已安装的 iris-fabric-1.11.2 解析器，逐档解出 pass 门与缓冲尺寸后差分
python qa/tools/compile_glsl.py            # → 全量编译门
python qa/tools/compile_glsl.py --matrix   # → P2-12 选项穷举门：二组合覆盖阵列 × 89 入口；行数随选项面变，不写死（本轮实测 85 行，见 11.F-9）（--matrix-rows N 截断，截断即非零退出）
python qa/tools/compile_glsl.py --profiles ULTRA --set NAME= [--set 依赖项=]   # → 新增布尔选项必须补跑一次"把它开着"的扫描：出厂关着的分支被预处理器排除，默认三档扫描对它零感知（11.F-9）
python qa/tools/option_matrix.py           # → 只出穷举分析不做判定（因子规模、零消费者选项、未声明分支符号、零读取 #define、覆盖阵列规模）；判归 check_pack #13
```

全部脚本与解包源码在 `C:\Users\杨铭\Desktop\光影包\`，永久保存：29 个目录 = 22 个不同包（20 个下载条目 + 2 个表外参照包）+ 7 个 `*-source` 逐字节同名副本。§2 的每包 `path:line` 引用均来自该目录内的实际文件。

`check_citations.py` 最新一次运行（含 §11.E-5 与 §11.F 的 F-3 台账，且本段文字自身计入）：**扫描 515 条引用**。四类硬失败桶计数全为 0——「行号超出文件末尾」「文件名在归属包内根本不存在」「显式包/项目路径不解析」「带行号引用超出所有候选文件」。非零桶共 66 条，均为记法而非缺陷，逐桶列明：

- **「其实是 ASTRA 文件、需加 `Astra/` 前缀」17 条**：§4.2 2、§6 5、§7 1、§11 8（其中 §11.F 的 F-3 台账 5 条）、本节 1。都是正文已明确在谈 Astra 内部实现处使用了裸文件名。
- **「全样本库查无此路径」32 条**：§6 4、§9.2 3、§10.4 2、§11 23。同样是 Astra 内部模块的裸文件名（水光束、介质状态、影图采样、缓冲格式等），参照包中不存在是预期结果。
- **「带行号、跨包歧义且正文未指名」11 条**：§9.2 1、§11 10。
- **「目录层级不同」3 条**：均在 §2.1，引用 Complementary 时按包内相对路径书写（`lib/antialiasing/jitter.glsl`），而包内实际多一层 `shaders/` 根目录。
- **「建议新建、目前尚不存在」2 条**：`Astra/shaders/lib/compat.glsl`（§6 P2-10 与 §9.1 各一次），本条是待办而非缺陷。
- **「按正文归属包校验失败」1 条**：本节转述 §9.2 的 Solas `common.glsl:121` 跨包歧义引用，正文已指明归属。

非零桶的 66 条中有 41 条来自 §11：该节的裁决表用裸文件名指代 Astra 内部文件——记法简短，代价是自动解析器无从归属。§11 内一处真错已修：P2-13 行的 `lib/bayer.glsl` 曾被按上下文的 Mellow 包解析而报「no such file」，已补全为 `Astra/shaders/lib/bayer.glsl`。

引用类数字之外，§3.1–§3.4 四张表另有 `tablecheck.py` 逐格比对：872 个数值格、0 处与 `matrix.md` 不一致。第三道门 `final_sweep.py` 查的是"数字都对但排版坏了"，本次九项全绿。

### 9.2 本次调研中被推翻或纠正的前提（防止复用时再踩）

| 前提 | 结论 | 证据 |
|---|---|---|
| LIGHT 有级联阴影 | **不成立** | `cascade\|texArray\|shadowInterval` 全 0 命中；实为单图径向对数畸变 |
| LIGHT 有色散 | **不成立** | `dispersion\|chromat\|prism\|IOR\|Abbe` 全 0 |
| Sildur's 有包内四档 | **不成立** | `profile.` = 0；四档是四个独立下载包 |
| E-LITE 是"继续向下砍"的实验 | **方向相反** | 其 §0 自陈为抬高上限 |
| 低配包普遍用渲染缩放 | **不成立** | `size.buffer.` = 0 于全部 5 款低配向包；E-LITE 的 `RENDER_SCALE` 是死值（`lib/config.glsl:272 = 1.0`，滑杆在 `properties:144` 被注释） |
| RedHat `ToD[25]` 越界读 | **不成立** | `hour` 已 `mod 24` ⇒ `floor(hour)+1 ≤ 24` 合法；真实问题只是 `program/composite2.glsl:211-212` 的另一份实现（取模）与 `program/composite.glsl:947` 不一致 |
| RedHat 水下雾在 `composite2:186-207` | **误引** | 该两段分别是顶点 `main()` 与 `heldItemId` 表；实际在 `lib/effect/atmospherics/fog.glsl:22` |
| Solas 有"更重的吸收路径"可学 | **不成立且方向相反** | Astra 模型更强；只学烘焙位置（§6 P1-7） |
| Bloop 无校验工具链可对照 | 成立，但"Astra 无 `qa/`"是**误判** | `qa/` 在仓库根而非 `Astra/` 下，18 个脚本 |
| 「VP 11,388 行 > Astra 9,559 行」 | **净代码口径下反转** | VP 净 7,004（许可头 4,384）< Astra 9,804 |
| JCL 注释比 0.378 / 最长行 18,043 = 混淆 | **是打包风格** | `//[枚举]` 被 `census.py:91` 计入注释；纯注释行比 0.139；长行是 OptiFine 枚举滑杆 |
| JCL `stuff/` 作者名文件构成侵权嫌疑 | **排除** | 是作者自己另一工程的三份近重复副本（difflib 0.974/0.905），风险为自我重复（7,900 行 / 34% 包体） |
| 借鉴报告 #1「循环体已全显式 LOD」 | **不成立（证据已更正）** | 结论仍成立但站点指错过：`light_shafts.glsl:110,125` 的 `shadowtex1`/`shadowcolor0` 全包无 mipmap 声明，隐式 LOD 只取 level 0，无害。真站点是 `global/water/bloom_capture.glsl:21`——`colortex0` 经 `program/water_bloom.fsh:5` 开 mip，该行在双重循环内、外层 `:15` 是数据相关 `if`，属未定义行为。正确修法是把 mip level 显式命名下去而非 `texelFetch`——`getBloomTile` 的整个 mip 选择本来就靠 `exp2(lod)` 缩放坐标 + 梯度推导，`texelFetch` 会绕过它（§6 P1-16）。〔2026-09-20 执行期更正〕本报告原写的 `textureLod(colortex0, sampleCoord, lod)` 逐字采用不成立：梯度推出来的 level 带一项分辨率补偿，实测 λ = `lod + log2(pixelHeight * viewHeight)`，裸传 `lod` 在 1080p 短 1.26 个 level（11.F-7） |
| 借鉴报告「Unbound 多出 TAA + 体素化 + 3D 云 + SSR/反射缓冲 + textRendering」 | **部分描述错** | TAA + 体素化 + textRendering 确为 Unbound 独有；但 SSR/反射缓冲（colortex7/8）与 3D 云在 Complementary 共享 `lib/` 中已存在，不是 Unbound「多出」 |
| 借鉴报告「`lib/common.glsl:120-121` 两张反射缓冲尺寸声明」 | **文件错** | 反射缓冲尺寸在 `dimension.properties` 的尺寸指令中通过 `REFLECTION_RES` 引用，不在 `common.glsl:120-121` |
| 借鉴报告 waterFog 谱序「b×=(1-abs³·0.5)」 | **参数化描述错** | `waterFog.glsl:6` 无 swizzle ⇒ 三次项是三通道共有衰减而非 b 独享；定性结论「红衰最快、蓝衰最慢」仍成立（19 点数值扫描 r<g<b 恒成立） |
| 借鉴报告「Unbound VL 用 `texture2DShadow` 硬件比较采样器」 | **机理错** | Unbound VL 使用 `texture2D`/`texelFetch` 而非 `texture2DShadow`；不影响建议方向（P1-16 的前置修复是改隐式 LOD，与此无关） |

### 9.3 与既往审查的关系

本报告不重复 `docs/2026-09-13-astra-full-audit.md` 与 `docs/2026-09-20-qoder-full-review.md` 的代码缺陷结论；§6 的每条建议都只引用**本次样本实测**与**Astra 当前状态**两类证据。既往审查中标为开放的 `bloom_capture` 隐式 LOD 站点、README 3 行不实、模块数 53/51 权威值等项，与本报告正交，未在此重复。

### 9.4 落地顺序建议

`P0-1`（纯配置，无风险，先做）→ `P2-12`（穷举编译，为后续所有开关兜底）→ `P2-10`/`P2-11`（合规与防退化基础设施）→ `P2-18`（`dimension.properties` 按维度裁剪，纯配置）→ `P1-5`/`P1-9`（成对做，同一处 bias/畸变）→ `P1-17`（水吸收侧面 skylight 代理 + 未命中近场缓释）→ **`P1-16` 前置**：把 `global/water/bloom_capture.glsl:21` 的隐式 LOD 改为显式命级（实测须写成 `textureLod(colortex0, sampleCoord, lod + log2(pixelHeight * viewHeight))`；裸传 `lod` 会去掉隐式路径自带的分辨率补偿，11.F-7。该函数靠 `exp2(lod)` 缩放坐标 + 梯度推导选 mip，`texelFetch` 会绕过这套选择，不可用）→ `P1-16`（光束时域自适应采样，依赖前置完成）〔2026-09-20 执行结果：前置已随 T7 闭合（11.F-7）；`P1-16` 本身经 T8 逐行核对参照包源码后判为**不落地**（11.F-8），其对 `P2-20` 的阻塞随之解除〕→ `P1-6` → `P1-7` → `P1-8` → `P2-14`/`P2-19`（分辨率粒度选项）→ `P2-20`（光束标定三条，原计划随 P1-16 对拍，P1-16 不落地后改为独立做，T13）→ `P0-2` → `P0-3` → `P2-13`（MIT 可署名复用清单）→ P2 余项（含 `P0-4` 降级后的月相残差，仅一处，顺手做）。**〔2026-09-20 执行期调整〕**`P0-2`/`P0-3` 从原来的第 5 位挪到后段：这两项是全表视觉风险最高、必须实机校准后才敢放的条目，且 `P0-3` 还卡在 `design.md` §4.1 需要先行修订；把它们排在低风险、可静态验证的条目之后，能让每一步都有编译或校验脚本兜底，而不是让最高风险项挡在最前面。

## 10. 借鉴报告核收台账

### 10.1 来源说明

用户指示合并的另一份借鉴报告，经全磁盘穷举搜索（`docs/`、仓库根、`光影包/_meta/`、常见临时目录）**未找到任何 GLM 撰写的独立借鉴报告文件**。实际合并对象为本项目已有的 `docs/2026-09-20-reference-pack-study.md`（120 行，§1 六项 Unbound 机制、§2 变体对比、§3 Steadfast 吸收、§4 Solas V3.7b、§5 十二行行动建议表）。该报告由前序会话生成，本次对其全部结论逐条核验后并入本报告。

### 10.2 核验方法

1. **逐条定位源码**：对借鉴报告每条事实性声明，在 `C:\Users\杨铭\Desktop\光影包\` 下的实际解包目录中定位对应文件与行号。
2. **机器验证**：编写 `光影包/_meta/verify_reference_study.py`（37 项检查），自动读源码、比对声明与实际内容。Windows 下须 `set PYTHONIOENCODING=utf-8` 后运行。
3. **分类标注**：每项检查归入九类之一——真 / 行号错 / 文件错 / 机理错 / 机理误读 / 不成立 / 需修正 / 描述错 / 结论对参数化描述错。

### 10.3 核验结果

| 分类 | 计数 | 说明 |
|---|---|---|
| 真 | 27 | 声明与源码完全一致 |
| 行号错 | 4 | 结论正确但引用行号偏移 |
| 不成立 | 2 | 声明的前提在源码中不成立 |
| 文件错 | 1 | 结论正确但归错文件 |
| 机理错 | 1 | 对 API/采样器机制的理解有误（`texture2DShadow`） |
| 结论对参数化描述错 | 1 | waterFog 谱序定性正确（红衰最快蓝衰最慢），但第三条衰减项的参数化描述有误（共有因子误标为 b 独享） |
| 需修正 | 1 | 「循环体已全显式 LOD」前提不成立 |
| **合计** | **37** | |

### 10.4 十二条行动建议处置

| # | 建议摘要 | 处置 | 备注 |
|---|---|---|---|
| 1 | 水下光束运行时采样数自适应 | **前提修正采纳（已随 T7 闭合）；主体撤销（T8）** | `UNDERWATER_SHAFT_SAMPLES` 是用户选项 7/[4-10] 而非常量；「循环体已全显式 LOD」为假（C36），真站点是 `bloom_capture.glsl:21`（colortex0 有 mip + 数据相关分支）。修法不能逐字写成裸 `textureLod(…, lod)`——执行 T7 实测隐式梯度选的 level 自带分辨率补偿，须写 `textureLod(colortex0, sampleCoord, lod + log2(pixelHeight * viewHeight))`，否则 1080p 短 1.26 个 level（11.D-14、11.F-7）。采样数改运行时这一半经 T8 判为不落地（11.F-8）；`light_shafts.glsl:110,125` 的采样器无 mip，隐式 LOD 无害，仅卫生改进（§6 P1-16） |
| 2 | vlFactor 时域自适应 | **撤销（执行 T8 时）** | 逐行读参照包源码：`vlFactor` 的驱动信号是阴影图日方向遮蔽物高度均值与画面开阔天空判定，与相机运动无关（`volumetricLight.glsl:289-346`）；且参照包在 `isEyeInWater == 1` 时把它恒置 1.0（`:16`），而那是 Astra 唯一使用它的路径。→ 见 11.F-8 |
| 3 | 近/远两段式 VL 采样 | **撤销（执行 T8 时）** | 该做法在参照包侧服务于超出影距的远段追踪；Astra 水下 march 的 `maxDist` 是硬编码 40 块（`global/water/light_shafts.glsl:74`），而 `SHADOW_DISTANCE` 最小选项 64（`lib/settings.glsl:67`，三档 192/256/256），整段追踪本就在影距覆盖内，没有远段可分 |
| 4 | 水吸收谱序对照标定 | 采纳（修正后） | 定性结论正确，参数化描述须修正（§9.2 已记录） |
| 5 | 焦散曲率烘焙进 shadow | 采纳 | → §6 P1-7 |
| 6 | 体积云三级早退 | 采纳 | → §2.4 已记录思路 |
| 7 | 色调映射常数滑杆化 | 采纳 | 已在 Astra 滑杆体系中 |
| 8 | `dimension.properties` 按维度裁剪 | 采纳 | → §6 P2-18 |
| 9 | 反射/光束分辨率用户选项 | 采纳 | → §6 P2-19 |
| 10 | Solas 水吸收谱序作对照 | **采纳（修正后）** | 定性方向正确可作标定基准；第三条是共有衰减项非 b 独享 |
| 11 | Steadfast 水吸收 skylight 代理 | **撤销（执行 T6 时）** | 代理式在参照包侧为真（`absorption_refraction.glsl:92`），但 Astra 侧无对应缺口：侧面缺的上界是几何真值，`min(depth,1.0)` 覆盖同一取值域。→ 见 11.D-12/13 |
| 12 | 不引入 TAA | 与 §7.B.10 一致 | 当前阶段不引入 |

### 10.5 锚定

核验脚本 `verify_reference_study.py` 与本报告同批保存；复现命令见 §9.1。核验基于 commit `9df32df`（Fix the defects from the three-way shader review）之后的工作树快照。

---

## 11. 复核批注（2026-09-20，基于 Astra 实测）

**复核范围与方法**：仅依据本报告文本与 Astra 包源码逐条核对；按任务约束**未打开任何参照包**——参照包侧数字（架构分类、行数、命中计数）按报告自述采信，不再核验。Astra 侧的每一条引用均已重新打开对应文件核实；六组更正已就地写回正文并标〔2026-09-20 复核〕，本节是总账。

### 11.A 矩阵复核（M1–M4 的 Astra 侧）

- **M1 ASTRA 行全格复现**：总行/代码/注释/空行、文件数、G30/G40、五个最长文件、world-1 的 9 个 .csh、三个维度目录全部一致。总行 9559 是 wc 口径（`count('\n')`），Python `splitlines` 得 9560，属末行换行口径差，不算错误；但 §9 模块普查用 `count('\n')+1`（9804），同一份文件两种口径并存，见 11.E-3。
- **M2 ASTRA 行复现**：if 197 / for 88 / while 6 / texture 340 / fwidth 32 / pow 219 / smoothstep 183 / const 348 / uniform 145 / `#ifdef` 125 全部一致。三处口径说明（非错误）：注释比 0.451 的口径未能反推（纯 `//` 行比为 0.306）；`#if` 族总量 248 为全文匹配，剔除注释后约 88；break 25 / discard 16 各含注释中 1 处（剔注释后 24 / 15）。"shadowcomp ×12" = 9 条 `compute.shadowcomp.*` + 3 条 `image.shadowcomp.*`，与 §4.2 的表述自洽。
- **M3 Astra 侧抽查**：`variable.*` 22 / `uniform.*` 24 ✓；`size.buffer` 6 条（`:14/:19/:21/:25/:26/:28`）✓；无条件 `false` 门 8 条 ✓；bloom 链 composite1→composite2→final ✓；云阴影 0 且 `clouds_planar.glsl:42-44` 把它登记为有意不移植 ✓；「Mipmap降采样」实为 3 处声明（11.D-3）。
- **M4 / §4.4 档位数字复现**：3 条 profile 各 67 token、两两差量 10/5/13、并集 13 ✓（行长 1219/1214/1214 为"值长度"口径，含 `profile.X=` 前缀的整行长度是 1239/1231/1228，报告口径可复现）。

### 11.B §6 逐条裁决

| 条目 | 裁决 | Astra 侧依据（均已实测） |
|---|---|---|
| P0-1 profile 差量改革 | **最高价值，采纳 · 已执行（见 11.F-1，含未采纳部分）** | 67 token / 10/5/13 / 6 条 size.buffer 不在差量 / 7 恒真门全部复核成立；`inspect_iris_properties.py`、`cost_census.py` 已存在，落地成本近零 |
| P0-2 云阴影 | **高价值，采纳 · 已执行（T14，默认关待实机，见 11.F-14）** | `clouds_planar.glsl:42-44` 的 NOT PORTED 登记本轮复核为行号准确（云影那条在 `:43`），T14 后已从该表移到 `:46-49` 的"已离开本列表"注记；`docs/handoffs/sky-clouds.md` 的 H5 已按落地形态关闭。真实缺口是"晴天不投、雨天才投"的不对称而非缺机制（见 §6 现状更正）；ARR 只读思路约束已写明并落 `THIRD-PARTY.md` |
| P0-3 自动曝光 | **中价值，采纳 · 已执行（T15，默认关待实机，见 11.F-15）** | 与 design 4.1 的冲突按用户裁定走"先翻案、再实现"：翻案正文已写进 `design.md` SC-41，`settings.glsl:48-50` 的 "replaces auto-exposure" 断言已就地改写为分工表述（`BLOCKLIGHT_SUPPRESSION` 是光照项，自动曝光是显示增益），冲突不再存在；报告自身的两条成本判断经实测否掉（mipmap 换源会新增强制全分辨率 HDR mip 链、"不做新 pass"不成立，见 §6 P0-3 就地更正与 11.D-3），落地形态改为一次 1 片元的测光 pass + 64 抽网格 + 1×1 历史；"默认关 + 实机校准"的权衡原样采纳 |
| P0-4 逐帧常量 | **报告自我降级正确** | 残差复核成立（`sky.fsh:40-41` + `overworld.glsl:88` 两处逐片元月相）；Iris-only 判断成立，删掉双写一半同意 |
| P1-5 bias 统一 | **低价值，撤条并入 P1-9 · 已执行（见 11.F-5）** | "并存"系误述（`#ifdef DIMENSION_END` 互斥，改后在 `shadowmap.glsl:205-217`），适用条件已显式；残差仅 End 分支 `+0.015` 归一 |
| P1-6 几何太阳遮蔽 | **中低价值，收窄后采纳 · 已执行（见 11.F-9）** | march 内逐样本遮挡已在（`godrays.glsl:32-36,71-73`），缺口只是全局强度标量（`uniforms.glsl:27` 全解析）；1 像素窗口做法便宜。落地 = `program/scattering.fsh` 角落像素的 7×7 `depthtex1` 日面窗口 → `colortex1` texel (0,0) 的 alpha → `program/final.fsh` 一次乘子，选项 `GODRAYS_SUN_OCCLUSION` 默认关、待实机 A/B |
| P1-7 焦散烘焙 | **前提已不成立 · 未执行（见 11.F-10）** | 清屏色前提成立但行号漂移（现值在 `settings.glsl:369`，非 `:363`）；收益定位（省像素端而非更正确）写得准确，但**像素端已是解析 `exp` 而非逐格 march**（`absorption.glsl:42-54`），无成本可省；焦散烘焙**已在包内**（`program/shadow.fsh:57-73` → `light_shafts.glsl:125`）；`shadowcolor0` 四通道已占满、无"未用分量"；"12 条 shadowcomp"实测 9 条且全为熔岩侧 `NETHER_VOXEL_LIGHT` 门 |
| P1-8 硬件 PCF 默认档 | **中低价值 · 已执行，默认档经实测确认不改（见 11.F-11）** | 默认软件 16 抽成立且是三档出厂配置（`settings.glsl:60` + `shaders.properties:149-151` 全写 `=0`，报告引的 `:57` 已漂移）；软件路径已有 gather（`shadowmap.glsl:117-126`，gather 对象是 `sampler2D`），报告未提；"用等价性测量决定默认值"已跑 `shadow_filter_equiv.py`：可见性两档恒等（max_abs 9.4e-16），分出高下的只有彩色阴影中心材质近似（`lang:16` 已写明）→ 软件默认正确、不改；三参 shadow-gather 因改足迹且省指令离线不可测而不采纳 |
| P1-9 畸变归一 | **中价值，采纳 · 已执行（见 11.F-5）** | `distort.glsl:7,10` 无 SHADOW_DISTANCE 归一成立；Steadfast §7b/§7c/§7e 义务提醒与对账工具调用正确；锚值改由实测选定（`SHADOW_DISTORT_CORE = 25.6`），P1-5 的 End 残差一并闭合 |
| P2-10 vendor 隔离 | **高价值（合规基建），采纳** | 与 §7.B.3 互为表里；Astra 已有 PROVENANCE 短注惯例，迁移目标明确 |
| P2-11 buffer 声明防退化 | **高价值（防退化），采纳** | 6 处活声明复核成立（`water_buffer_formats.glsl:12,15,16,18` + `end_illumination.fsh:10` + `end_sky_buffer.fsh:9`） |
| P2-12 穷举编译 | **高价值，采纳** | `compile_glsl.py` 已有基础；化石 token 防线是结构性收益 |
| P2-13 MIT 复用清单 | **高价值** | `grading.glsl:204-208` 已有 Mellow MIT 移植先例（链序），`Astra/shaders/lib/bayer.glsl` 已有基础；逐件许可证动作标注清楚 |
| P2-14 连续分辨率旋钮 | **中低价值 · 已执行（T12 再评估后暂缓，零改动，见 11.F-12）** | 即 §11.B 承诺的"P0-1 定调后再评估"；结论不投机实现：光束缓冲已由 T1 做成随用户滑杆两档、消费者按 `textureSize()` 推 tap（缩放免费），云阶段需新建低分缓冲+上采样；收益（亚档位性能/画质）离线不可测、许可两条须重写、默认关滑杆即 §7.B.6 禁的零消费者化石 |
| P2-15 反射八度减半 | **中低价值** | 反射路径无质量降级成立（`clouds_planar`/`refraction`/`raytrace` 无 isReflection 分支）；收益限于反射像素 |
| P1-16 光束时域自适应 | **不采纳（前提证伪）· 已复核（见 11.F-8）** | 执行 T8 时逐行读参照包源码，采纳前提不成立：`vlFactor` 由阴影图遮蔽物高度与开阔天空判定驱动，与相机运动无关，且参照包在 `isEyeInWater == 1` 路径上把它恒置 1.0——Astra 唯一要接的正是该路径。零代码改动；前置修复已随 T7 闭合（11.F-7），11.D-5/6 两处前提更正仍成立 |
| P1-17 水吸收侧代理 | **中价值，采纳 · 已执行（见 11.F-6）** | 侧面几何深度确有缺陷但**方向与原文相反**：不是"≈0 不吃吸收"，而是退化成相机距离导致**过吸收**（11.D-11）；skylight 代理经实测**不必要**，被 ≤1 块的纯几何界取代（11.D-12）；文件归属与 miss 分支描述已更正（11.D-7/8）；Steadfast §7 义务对账要求合理 |
| P2-18 按维度裁剪 | **中低价值，采纳 · 已执行（见 11.F-4）** | properties 已有 8 条维度专用 `false` 门（两个维度目录各 `composite`/`composite2`/`composite3`/`composite4`），本条是把已有机制系统化；"缓冲尺寸跟随维度配置"不成立——`size.buffer.*` 以裸缓冲名为键（见 §6 P2-18 做法条） |
| P2-19 光束/反射分辨率选项 | **中低价值 · 已执行（并入 P2-14、T12 判已由 T1 满足，零改动，见 11.F-12）** | 前提已不成立：colortex1 光束缓冲已由 T1 做成随用户滑杆两档（`#if UNDERWATER_SHAFT_SAMPLES<7`→PERF 0.25/BAL+ULTRA 0.5，三档实测 4/7/10），正是"低配多一档退路"；colortex7 实为水下泛光性能缓冲（非反射/光束质量档，原报告归因错）；反射是屏幕空间无独立分辨率缓冲；引证 `shaders.properties:14,19` 已漂移到 :21/23/35 |
| P2-20 光束标定 | **中价值，采纳 · 已执行（T13，默认关待实机，见 11.F-13）** | 三条参照全部本地重验成立（Solas V3.7b `volumetrics.glsl:56/192-194/130-131`）；强度门公式抄写准确但"白天端归零"定性偏了——归零只在视线背离折射后太阳方向时发生，那是正确的前向散射；Solas ARR 与"禁止 DRM 宏"约束到位；落地为默认关的 `UNDERWATER_SHAFT_CALIBRATION`，① 需 0.075 峰值归一化才不至于亮 13 倍 |

### 11.C §7 复核

- **A 组 7 条推翻全部成立**，逐条重开对应文件核实。其中第 4 条引用的 `design.md:517` 经复核**行号准确**——`:517` 正是"零 compute/零彩光边界修订"那条（复核一度怀疑差一行，重开文件后撤销）。
- **B 组 10 条与 Astra 现状一致**：TAA / SSAO / 逐文件许可头 / 维度整包复制 / 注释记配置 / 零消费者选项 / `#version 120` 外壳 / 散文档位 / 100+ 调色滑块在 Astra 均不存在或已有等价决策。B.1 与 B.10 同为"不要现在引入 TAA"，建议合并为一条。

### 11.D 报告错误更正清单（均已就地写回正文）

1. §4.2 "Astra 是延迟（lit.fsh → deferred 链）" → 前向（`design.md:48`；lit.fsh 头注；deferred.fsh 仅场景拷贝+水坑）。
2. §4.3 与 P1-5 "两条 bias 并存" → `#ifdef DIMENSION_END` 维度互斥（改前 `shadowmap.glsl:200-209`，随 11.F-5 位移后现为 `:205-217`）。
3. §0 与 P0-3 "MipmapEnabled 仅 2 处" → 3 处声明覆盖 2 张缓冲（`composite1.fsh:20`、`final.fsh:24` 在 colortex2；`water_bloom.fsh:5` 在 colortex0）。
4. P0-3 漏报与 design 4.1 的冲突（当时写作 `settings.glsl:46` 的 "replaces auto-exposure"），已在权衡条补充。【2026-09-21 T15 补记：该 `#define` 现位于 `settings.glsl:48`、断言注释在 `:49-50`；SC-41 翻案已落地，注释按实测改写为"这是光照项、自动曝光是显示增益"的分工表述，本条冲突随之关闭。】
5. P1-16 "colortex6 空闲通道" → 四通道全占（`medium_state.glsl:5`），只能新增 1×1 缓冲。
6. P1-16 前置修复的 LOD 定性 → `light_shafts.glsl:110,125` 目标无 mipmap，实际无害；真正站点是 `bloom_capture.glsl:21`（colortex0 开 mip + 数据相关分支）。
7. P1-17 文件归属 → `program/water.glsl:31`。
8. P1-17 "Astra 返回固定水体色" → miss 是 validity=0 回落未偏移路径，视觉后果偏亮而非偏浓。
9. P1-8 未提 Astra 软件路径已有 `textureGather`（`shadowmap.glsl:124-127 shadow_gather_visibility`，gather 的是 `sampler2D` 原始深度再手工 `step`，与本条提议的 `sampler2DShadow` 比较式 gather 是两个不同重载）；默认档问题经 T11 用 `shadow_filter_equiv.py` 实测已定：可见性两档恒等、软件默认正确不改（见 11.F-11）。
10. P1-6 "会穿墙" → march 内遮挡已在，缺口是全局强度标量。
11. P1-17 侧面症状方向 → **反了**。`dot(origin−point, faceNormal)` 是背景命中点到水面所在平面的垂直距离：顶面上等于真实水柱，侧面上等于相机到背景的距离，所以竖直水壁是**过吸收**（48 块处红通道实测 0.0072，加界后 0.0739），不是原文的"≈0、几乎不吃吸收"。执行 T6 时按同一几何做 A/B 实测得到（11.F-6）。
12. P1-17 做法②（读 colortex3 skylight 作深度代理）→ **不必要**。代理的取值域本身就是 1/16..1 块（`absorption_refraction.glsl:92` 已核对），而"侧面所在水块沿该法线的邻格不是水 ⇒ 厚度 ≤ 1 块"是几何真值，`min(depth, 1.0)` 一步到位，不必为同一个上界再读一张缓冲。② 的"一个分支 + 一次 skylight 读取"成本随之改为一次 `view_player` 点积。
13. §10.4 第 11 行「Steadfast 水吸收 skylight 代理：成立、v2 备选」→ Astra 侧**没有这个缺口**（11.D-12），撤销该建议，不留 v2 备选位。
14. §9.2 与 §9.4 的 P1-16 前置修法「改成 `textureLod(colortex0, sampleCoord, lod)`」→ **不完整**。隐式梯度选出的 level 自带分辨率补偿 λ = `lod + log2(pixelHeight * viewHeight)`，裸传 `lod` 在 270/360/540/1080 分别短 0.32 / 0.32 / 0.26 / 1.26 个 level，等于在每个分辨率都把水下泛光改锐一档。执行 T7 时实测得到（11.F-7），两处已就地写回正文。
15. §6 P1-16 依据条「`vlFactor` …… 静止爬升、运动回落」→ **参照机制被本报告读错**。执行 T8 时逐行读 `volumetricLight.glsl:289-346`：该标量的两个输入是阴影图日方向 5×5 区域的遮蔽物高度均值（`salsCheck` vs `heightThreshold = 6.0`）与画面五点开阔天空判定（`skyCheck`），整段不含任何位移或速度项；参照包自己的段标题写的是 "Scene Aware"，GUI 档位名是 `Scene Aware [+]` / `Regular` / `Extreme [-]`，切换方向是**加质量**。更关键的一条：`:16` 在 `isEyeInWater == 1` 时把它恒置 1.0，而水下正是 Astra 唯一要接的路径。同次核对另出两处 §2.1 的引证误差：`composite1.vsh:379` **文件归属错**——该行在 `program/composite1.glsl` 的 `#ifdef VERTEX_SHADER` 段内，而 `world0/composite1.vsh` 只有 7 行、是一个 `#define VERTEX_SHADER` + include 的包装；"每帧爬升"**节奏错**——源码是每 `int(0.06666 / frameTimeSmooth + 0.5)` 帧一步（60fps 约每 4 帧）。三处已就地改写 §2.1。→ 见 11.F-8，本条不落地。
16. §6 P2-19 / §11.B 该行的两处误差（执行 T12 时读回出厂源发现）：① **colortex7 归因错**——P2-19 把 `colortex7=0.25` 当作"光束 march / 反射缓冲"待暴露的质量档，实测它是**水下泛光缓冲**（`shaders.properties:32-34`：quarter-res 低频模糊、空中直接 discard、全分辨率默认是纯浪费），0.25 是省显存的性能选择，不是质量旋钮；② **引证漂移**——§11.B 该行引 `shaders.properties:14,19`，`:14/:19` 现为注释，真实 `size.buffer.*` 指令在 :21/23/29/31/35/36/38。附带更正 P2-19 的核心前提：光束缓冲 colortex1 已由 T1 用 `#if UNDERWATER_SHAFT_SAMPLES<7` 做成随用户滑杆的两档（PERF 0.25 / BAL+ULTRA 0.5），"硬编码无用户选项"已不成立。→ 见 11.F-12，本条不落地。
17. §6 P2-20 的两处前提误差（执行 T13 时发现，已就地标注）：① **验证条不可用**——"用 `light_shafts` 现有探针对拍正午/晨昏/水下三场景"在 `qa/` 里不存在对应执行面，`qa/tools/water_path_probe.py:216` 恰恰做 `profile.update(SHADOWS=None, UNDERWATER_LIGHT_SHAFTS=None)`，即该探针显式关掉光束；全库检索 `water_shafts_march` / `water_shafts_view` / `solas_sun_visibility` / `astraSolasTimeBrightness` / `refractSun` 零命中，所以按原文执行得不到任何判定，三项改动的收益离线不可测。② **"白天端仍会归零"观察成立、机理判错**——出厂式 `mix(0.25+VoL*0.25, VoL*0.45, time)` 在正午（`astraSolasTimeBrightness=1`，`shaders.properties:288` 的 `max(sin(astraSolasTimeAngle*2π),0)` 在 `sunAngle=0.25` 取 1）确实退化成 `VoL*0.45` 且没有下限；但复核时把 `VoL→0` 解释成"视线背离折射后太阳方向，是前向散射应有的行为"，这一步是错的：`VoL` 的参照向量由 `light_shafts.glsl:56` 的 `refract()` 得到，而该调用把"指向太阳"的向量喂给了规范要求"光传播方向"的第一参数，折射结果**恒朝上**，于是每一个俯视海床的像素在正午恒零——正是 `:47-54` 注释自称已经修掉的场景。根因、驱动实测与一行修法见 11.E-8；P2-20 的下限只是把这道符号错的门盖住，不是修它。两条都不推翻参照本身（V3.7b 的三处表达式本轮已逐行重验，见 §6 P2-20 依据条）：①推翻的是"改完之后能被量到"，②推翻的是"这是物理上应有的行为"。→ 见 11.F-13。
18. §3.3 M3「云阴影」列对 Astra 的 **0 命中是命名启发式假阴性**（执行 T14 时发现，已就地标注 §6 P0-2 现状条）。该列的匹配串是相邻的 `cloud`+`shadow`，Astra 的同功能函数叫 `astra_cloud_transmission`（`global/atmosphere/weather.glsl:122-136`，2026-09-10 起就在雨天路径里被 `program/scene.glsl` 调用），标识符里不含该串，故计数为 0 而功能并非不存在。口径本轮按 M3 声明重建并逐包复现：只扫 GLSL 系文件（`.glsl/.vsh/.fsh/.csh/.comp/.frag`）、先剥 `/* */` 再剥 `//`、大小写不敏感匹配 `cloud.?shadow`、按文件计数求和——得 BSL 4 / Complementary Unbound 18 / Reimagined 18 / Solas V3.7b 27 / Solas V2.2b 0，与 §3.3 表内数字逐格相同，Astra 在 T14 前亦为 0。**即数字全部可复现，错的是把 0 读成"没做"**。生成该列的 `_meta/feature_matrix.py` 在本仓库不存在（`find` 实测零命中，§9 附录 `:949` 仍写着它的调用命令），口径只能重建，无法核对原脚本是否还有额外过滤。推广的教训：M3 任意一列的 0 只证明"这些包里没有这么命名的东西"，不证明行为缺失；本报告凡以 M3 的 0 作为"缺口"主证据的条目（P0-2 云阴影、P0-3 自动曝光、以及 §7 的 SSAO 严格口径条目），执行时必须先做一次跨文件的行为级检索再决定动不动手。→ 见 11.F-14。


### 11.E 复核中新发现的 Astra 侧问题（报告未提）

1. **`program/scattering.fsh:2` 注释腐烂**：称 "colortex1 is full resolution when water shafts are enabled"，但 `shaders.properties:14` 已固定 `size.buffer.colortex1=0.5`。属 §7.B.5 要防的"注释记配置"自伤，顺手修正。**执行阶段扫描发现同一失败模式另有两处，复核未捕捉**：`program/composite1.fsh:1-2` 称 colortex2 为 "half resolution"/"0.5x"，`global/post/bloom.glsl:5,82,86` 称 "half-resolution"/"2x downsample"——而 `shaders.properties:19` 与 `bloom.glsl:42` 的 `BLOOM_CAPTURE_SCALE` 早已是 `0.25`（`properties:15-18` 的注释正是记录这次 0.5→0.25 改动，只有散文没跟上）。三处均已改为指向单一真源而非重述数值；代码侧本就由 `BLOOM_CAPTURE_SCALE` 与 `textureSize` 推导，无行为缺陷，纯注释腐烂。
2. **`bloom_capture.glsl:21` 的隐式 LOD 站点**（见 11.D-6）：在项目记忆中仍为开放项，优先级应高于 P1-16 字面的前置修复。**〔已闭合：T7 / 11.F-7，站点现为 `:26`，分支条件现为 `:20`〕**
3. ~~**行数口径混用**：M1 用 wc 口径（9559）、§9 模块普查用 `count('\n')+1`（9804）~~ —— **本条经实测撤销**（2026-09-20 执行阶段）。缺陷不存在：§3.1 的 ASTRA 行写的就是 **9804**，与 `astra_census.json`（`glsl_files=245, glsl_lines=9804`）一致；`census.py:74` 与 `census_astra.py:21` 两处**都已**用 `count("\n")+1`，工具侧本就统一。`9559` 全文只出现在两处——本节 11.A 的转述，以及 §9.2 表内作为**被推翻前提的引文**（那一行本来就在记录旧数字，不是 M1 的值）。复核时把引文误当成了表格数值。独立重算 245 文件得 `count('\n')=9560`、`+1/文件=9805`，与 9804 的 1 行差是末行换行边界，属 11.A 自己说过的口径差，不是混用。
4. **三处"对报告的怀疑"经复核撤销**，记录以防将来误改：`design.md:517` 行号准确；"shadowcomp 12 条"口径自洽；§2.19 "Astra 许可头 0" 在"逐文件 boilerplate"口径下成立——Astra 的 1–4 行 PROVENANCE 短注不属于该列统计对象。
5. **`DITHERING` 是个死选项**（P0-1 新建的差分门抓出；`Astra/shaders/lang/en_US.lang:67` 与 `zh_CN.lang:67` 早就为它写好了 GUI 文案）：`Astra/shaders/lib/settings.glsl:194` 的声明形式与 `BLOOM`/`VIGNETTE` 完全一致，`OptionAnnotatedSource` 单文件扫描也不报任何 diagnostic，但它始终不在 `ShaderPackOptions.getOptionSet()` 里 ⇒ GUI 无该行、三条 profile 的 `DITHERING` token 全部无效、`#define` 行永不改写，输出抖动实际恒开。根因是 Iris 的发现规则：**布尔选项只有在某个图文件里被 `#ifdef`/`#ifndef` 引用，才会进入选项集**——`OptionAnnotatedSource.parseLine` 只把这两个前缀交给 `parseIfdef` 去填 `booleanDefineReferences`，`ShaderPackOptions` 跨文件求并集后把它当作过滤参数传给 `getOptionSet(path, names)`，而 `defined()` 根本不被解析。包内 27 个布尔选项与该规则 1:1 吻合：唯一没有 `#ifdef` 站点的正是 `DITHERING`（原先只在 `Astra/shaders/global/post/grading.glsl:186` 以 `#if defined` 出现）。已改写为 `#ifdef`，实测 Iris 发现数 89→90、差分门归零，运行行为不变（出厂默认与三档都是 true）。**本条同时推翻 `qa/tools/check_pack.py` 的 SC-28 在 2026-09-10 写下的相反结论**（"真正的要求只是选项在某处被引用，`defined()` 也算"）——那次误判正是这道门放行该缺陷的原因，规则已就地改正并从 WARN 升为硬失败。
6. **`qa/tools/water_path_probe.py` 不绑定 Iris 的 CPU 侧 uniform，空气侧读数长期被雾替换**（执行 T6 时发现，已修）：`Astra/shaders/shaders.properties:214/218/219` 的 `borderFogDistance` / `renderDistanceFogTweak` / `atmosphereFogCoefficient` 由加载器在 CPU 上算，探针没绑就恒为 0，而 `BORDER_FOG` 在 BALANCED 是开的——`smoothstep(borderFogDistance−8, borderFogDistance, d)` 在每个距离都取 1，于是**空气侧像素全部输出边界雾**、水体分支的结果根本没到屏幕上。该盲区曾让一次探针运行把七档距离全读成 `(0,0,0)`，并被误写成"回落到 +1 块地板、到处纯黑"的结论；绑定这两个量后 `air_fog_sweep` 七档归零（不再叠雾），同轮空气侧实测值见 11.F-6。以后新增消费 CPU 计算 uniform 的探针，都要按这张清单核对。
7. **一处怀疑经源码核对撤销**（防后来者重复调查）：`Astra/shaders/program/water.glsl:138,143,163` 用 `pow(…, 1/2.2)` 解码 `colortex4`，而该缓冲由 `program/deferred.fsh:190` 线性写出，看起来像解码错配。实际不是：同函数 `:164` 返回前用 `pow(…, 2.2)` 重新编码，`alpha=1` 时两次幂严格互逆，只有 `mix()` 发生在感知空间——即"在 gamma 空间合成"的刻意写法（`:130` 头注写明这是适配过的 adapter），不是缺陷。
8. **`global/water/light_shafts.glsl:55-57` 的 `refract()` 入参符号错，正午俯视海床的水下光束恒零**（执行 T13 时发现，T13 未修）：
   - **机理**：`refract(I, N, eta)` 的规范式是 `k = 1 − η²(1 − dot(N,I)²)`、`return η·I − (η·dot(N,I) + sqrt(k))·N`，第一参数要求**光的传播方向**（射向界面）、`N` 指向入射一侧。`:55` 传的是 `sunWorld = normalize(view_player(lightVector))`，而 `lightVector = shadowLightPosition/100`（`shaders.properties:172-175`）是 Iris 给的**朝光源**方向，配上 `N=(0,-1,0)` 等于把两个符号同时反掉。代入即得 `refractSun = (η·sx, +sqrt(k), η·sz)`：**y 分量对任意太阳高度角非负**，折射"光束"恒朝上。
   - **驱动实测**（一次性 GPU 探针，`Renderer: NVIDIA GeForce RTX 4050 Laptop GPU/PCIe/SSE2`，脚本未入库，数值可由上式一行推出，跑它只为排除"规范式记错"）：太阳高度 90° ⇒ `refractSun = (-0.00000, +1.00000, 0)`；45° ⇒ `(+0.58926, +0.80795, 0)`；正确写法 `refract(-sunWorld, (0,1,0), 1/1.2)` 在 90° ⇒ `(0, -1.00000, 0)`。同一探针对 `eta=1` 返回的是未弯折的 `sunWorld` 本身（45° ⇒ `(+0.70711, +0.70711, 0)`），即该组合在任何 η 下都不会翻到水平面以下。
   - **后果**：`VoL = pow(clamp(dot(ray, refractSun),0,1),1.5)` 里 `ray = normalize(view_player(viewPos))`（`:39`，眼睛→像素），俯视海床的像素 `ray.y < 0`。正午 `refractSun = (0,1,0)` ⇒ `dot = ray.y < 0` ⇒ **VoL=0 ⇒ 出厂式 `visibility` 归零并被 `:75` 提前返回**；45° 高度时 −45° 俯视 VoL=0.00000，而 45° 仰视反而 VoL=0.98201——光束出现在"朝天看"那一半空间，与其物理位置相反。归零带是 `time→1` 的午间窗口：`time ≥ 0.9` 对应 `sunAngle ∈ [0.178, 0.322]`，出厂式在 VoL=0 时只剩 `(1−time)·0.25·0.85 ≤ 0.021` 的地板（正午峰值 0.45·0.85=0.383 的约 5%）。
   - **注释断言不成立**：`:47-54` 称"折射方向在正午朝下且偏日侧，所以那正是光束应在的地方"，与上面的实测直接矛盾。git 溯源：归零随 `875fc04`（2026-09-11 按参照重写光束）进入——它把 `540dd01` 的 `VoL = mix(pow(clamp(dot(ray,airSun),0,1),1.5), 0.5, 0.25)` 里那个 0.125 下限删成裸 `pow(...)`，而 `time=1` 又抹掉 `mix` 的 0.25 地板；`9df32df`（三方审查修复 B1 / Qoder F-03 / Hunyuan B1）把 air 向量换成 `refract()`，改前改后正午俯视海床都是零，等于没修到（改前的 air 向量同样朝上）。同文件 `:119-124` 的 R4 FIX 已经记录过这条链上更早的一次符号反转（shadow 项 `1.0 - clamp(...)`），当时就写过"反向的可见性项靠柔光/焦散/相位都救不回来"。T13 的标定臂用下限把这个门盖住（VoL=0 时 0→0.15），所以 §6 P2-20「现状」与 11.D-17② 已按本条改写。
   - **旁证（同写法、无影响）**：`global/water/caustics.glsl:84` 是同一 `refract(sunWorld,(0,-1,0),1/1.2)`，但它只以 `lightVector.xz / lightVector.y`（`:92`）的比值消费，整体取反不改变比值，故焦散视差不受影响，也不为这个符号背书。同文件 `:61` 注释"GLSL's refract(I,N,1.0) degenerates to the mirror formula I − 2*dot(N,I)*N"只在 `dot(N,I)>0` 那支成立，Astra 实际命中的分支上 `eta=1` 返回原向量（实测见上）——但 0.75 的波斜率刻度是离线扫参定的（注释自陈 p10/p50/p90），不依赖该推导理由。
   - **处置**：一行为 `vec3 refractSun = -refract(sunWorld, vec3(0.0, -1.0, 0.0), 1.0 / 1.2);`（规范式对 `(I,N) → (−I,−N)` 是奇函数，故取反与改写两入参等价），并同步删掉 `:47-54` 里"朝下且偏日侧"的断言。**不并进 T13**：T13 的裁决是默认关、出厂像素逐字节不变，而本条改的正是出厂像素，收益只能在水下实机 A/B 里判。建议单开工单；验收写进 `qa/regression-checklist.md` 的待实机条目——修后应"正午俯视海床有光束、朝天看无光束"，修前相反。

9. **云影与可见云层不在同一密度刻度上（执行 T14 时发现，本单未改）**：遮蔽臂复用既有的 `astra_cloud_transmission`（`global/atmosphere/weather.glsl:122-136`），而可见平面云在 `global/atmosphere/clouds_planar.glsl:316` 用另一套刻度把同一个噪声值转成不透明度，两者对同一个 `n` 的判法差在**起点**与**硬度**两处：
   - **起点**：可见层 `coverageBias = mix(0.20, -0.20, CLOUD_COVERAGE*0.01) - 0.04 - 0.28*astraRainFactor`（`clouds_planar.glsl:181`）⇒ 下沿 `L = 0.21 + coverageBias`；遮蔽层 `threshold = 0.21 + mix(0.20, -0.20, CLOUD_COVERAGE*0.01) - 0.28*astraRainFactor`（`weather.glsl:132`）**少减了那个 `-0.04`** ⇒ 遮蔽起点恒为 `L + 0.04`。噪声落在 `[L, L+0.04)` 的云**看得见、投不出影**。
   - **硬度**：可见层是 `smoothstep(L, L+0.22, n)` 的 0.22 宽渐变，遮蔽层是 `smoothstep(threshold-0.025, threshold+0.025, n)` 的 0.05 宽硬窗口（`:133`）⇒ 影子边缘比它所来自的那片云硬约 4.4 倍，且 `mix(1.0, 0.07, cloud)`（`:134`）一旦饱和就是 0.07 地板。
   - **出厂参数下的算术对照**（`CLOUD_COVERAGE=50`、晴天、正午高日，由上面两条表达式直接算出，非画面测量）：`n = 0.21` 处可见不透明度 `smoothstep(0.17,0.39,0.21) = 0.087`，而遮蔽取 `smoothstep(0.185,0.235,0.21) = 0.5` ⇒ 透光 `0.535`，再乘本单给的权重上界 `0.75` ⇒ 地面直射光降到 **0.651**。一片"几乎透明"的云已能削掉三分之一阳光。
   - **处置**：T14 不动它。理由与 11.E-8 同类——这两条刻度都活在出厂路径上（`weather.glsl:132` 自 2026-09-10 起就在雨天压暗直射光），改阈值或改窗宽都会改变出厂像素，而"影子该比云软还是该更硬"只有实机能判。新选项 `CLOUD_SHADOWS` 出厂关 ⇒ 本条只影响打开它的人。验收写进 `qa/regression-checklist.md` 的 T14 行：开该选项后须比较"影缘与天上那片云的形状是否对得上"，若判为错位，补偿方向是 `weather.glsl:132` 补回 `-0.04`、并把 `:133` 的 ±0.025 加宽。

10. **`check_pack.py` #13 报的矩阵行数与它自己推荐的命令输出不是同一个数（执行 T14 时发现，本单未改工具）**：`#13` 结尾提示 `pairwise matrix = 87 row(s), python qa/tools/compile_glsl.py --matrix`，而实跑该命令得 `rows=92`。差在种子：`compile_glsl.covering_array_rows`（`qa/tools/compile_glsl.py:365-367`）先塞 4 行种子（1 行"全默认"+ 3 行 profile）再贪心补齐，`check_pack`/`option_matrix` 报的是**无种子**贪心。本轮同一选项面三个数实测：无种子 87 行、仅默认种子 96 行、默认+三档种子 92 行，三者 `uncovered=0`——行数不是单调量，种子越多反而越少。11.F-13 把 86 与 86 写成"独立一致"是巧合而非交叉验证，后来者不得用这两个数互为证据。**处置**：只登记口径，不改工具——两种数都是有效的两两覆盖，改法（让 #13 也报种子化行数，或让 `--matrix` 报无种子行数）都会牵动既有台账里的历史数字。台账一律照抄各自命令的真实输出，并按 `qa/regression-checklist.md` 第 1 行的"不写死数字"口径引用。**同一读码路径上另测到一条**：`option_matrix.parse_options:83` 给布尔选项的 `default` 一律填 `"true"`（真实的通断另记在 `declared` 字段），当前包 30 个布尔选项 `declared` 为 on=23 / off=7，而 `default=="true"` 命中 30/30 ⇒ `--matrix` 的第一条种子行"全默认"其实是"30 个布尔全开"，不等于出厂 `settings.glsl` 状态；真出厂面由随后三条 profile 种子行覆盖，两两覆盖面不受影响，但**不得把该行读成"出厂行"**（`CLOUD_SHADOWS` 与 `UNDERWATER_SHAFT_CALIBRATION` 都在 off 的那 7 个里）。 **【2026-09-21 T15 复测：该口径未修，数字随选项面漂移——布尔选项 30 → 31，其中 `declared` 为 off 的 7 → 8（新增 `AUTO_EXPOSURE`），`default=="true"` 仍命中 31/31。同一读法在本轮矩阵日志上实测可用：83 行里 72 行显式写出 `AUTO_EXPOSURE=false`，其余 11 行未写即为开（含被误标"全默认"的 M001），故受保护臂在穷举面中确实编译过 11 × 90 = 990 个单元；反过来说，日志里出现的 `NAME=false` 是出厂值而非偏离值，读日志时须按此反向理解。工具改动仍不在本单夹带，理由同前（会牵动历史台账的既有数字）。】**

### 11.F 执行台账（2026-09-20 起，按工单顺序）

**F-1 · T1 执行 P0-1 档位重做**

改动全部在配置层，BALANCED 逐字节未动（它是出厂档，也是与 `lib/settings.glsl` 原始默认对齐的基准锚点）：

- PERFORMANCE 关掉四项真实工作：`!SSS_FOLIAGE`、`!AIR_PERSPECTIVE`、`!WATER_CAUSTICS`、`!WAVING_FOLIAGE`，并把 `UNDERWATER_SHAFT_SAMPLES` 由 7 降到 4。
- 首次引入 `size.buffer.*` 档间差量：`Astra/shaders/shaders.properties:18-21` 以 `#if UNDERWATER_SHAFT_SAMPLES < 7` 让 colortex1 取 P=0.25 / B=U=0.5。两个消费者的取样步长都由 `textureSize()` 推导（`Astra/shaders/program/final.fsh:54`、`Astra/shaders/global/water/light_shafts.glsl:140`），因此零 GLSL 改动。
- ULTRA 首次拿到更富的实现：`SKY_MODE=0`（Minishita 物理大气）、`SUN_MOON_MODE=1`（程序化日月盘）。

实测差异（`python qa/tools/inspect_iris_properties.py`，直接驱动已安装的 `iris-fabric-1.11.2+mc26.2.jar`，不启动游戏）：

- 取值差量 15 / 7 / 19（原 10 / 5 / 13），67 个 token 中 19 个随档变化；201 条 profile 赋值全部被 Iris 的选项存储接受。
- PERFORMANCE→BALANCED 确实多调度 **14 个 pass 门**：9 条 `compute.world-1/shadowcomp*` 加 `composite1`、`composite4`、`world-1/shadow`、`world-1/composite1`、`world1/composite1`（开启门数 10 → 24）。
  【2026-09-20 P2-18 复核更正】那 9 条当时拼作 `compute.world-1.shadowcomp*.enabled`，而 Iris 根本没有 `compute.*` 键族——真实引擎里下界的 9 步 compute 在三档全都派发。把同一份包按旧拼写在临时副本上重跑本工具：`+5 gate(s) on / 15 on in BALANCED`；按 `program.world-1/shadowcomp*.enabled` 改写后才是 `+14 / 24 on`。工具随之收紧：`.enabled` 结尾的键只有 `program.` 前缀计入门，其余单独报 `DEADGATE` 并 FAIL。详见 11.F-4。
- 三档 colortex1 解出 0.25 / 0.5 / 0.5，证明逐档选项图真的到达了预处理器（colortex1 是这条链上的金丝雀）。
- 编译门：`python qa/tools/compile_glsl.py` 默认按三档各展开一遍全部 89 个入口（80 顶点/片元对 + 9 compute），实机驱动结果 `linked=267 failed=0 compute=27`，exit 0——新档位 token 与 `#ifdef DITHERING` 改写后三档都能编译链接。
- 结构门：`python qa/tools/check_pack.py` 12 项检查 0 FAIL / 11 PASS / 1 WARN（该 WARN 与 P0-1 无关）。

未采纳与不成立的部分（如实记录，防止后来者按原文再执行一遍）：

- **「第一步收缩」未执行**，差量密度因此停在 22% / 10%，不达验证条要求的 ≥50%。理由：每条 profile 都写成完整显式配置是 `design.md` 3.3 的既有约定，且收缩成稀疏差量后"选档得到的状态"将依赖用户当前值，基准锚点随之失效。密度指标想保护的"档位真的有差异"改由上面的门级实测承担。
- **「三档都必须能删 pass」的前提部分不成立**：包内不存在可提升到 ULTRA 的独有 pass，BALANCED→ULTRA 只能改成本旋钮与实现富度。差分门在该步输出 NOTE 而非 FAIL，但硬保留"PERFORMANCE 与 ULTRA 不得解出同一套调度"。
- **7 个恒真门未接表达式**：`composite3` 与 `composite` 有明确的无条件消费者（前者是最终色调输出；后者在关光束时还兼供地形光照与焦散，见 `Astra/shaders/shaders.properties:58` 头注），接档位表达式只会造出与成本无关的差量；`world1/deferred1` 与 `world1/prepare` 的开关条件按包内 `Astra/shaders/shaders.properties:40-41` 的头注属于设计项 E2 的归属，P0-1 不越权替它决定。前者即 §4.4 点名的 RedHat 反面。

**F-2 · T2 执行 P2-12 选项穷举编译回归**

三件套，判定权集中在一条门里：

- `qa/tools/option_matrix.py`（新，只读分析）：值域从 `Astra/shaders/lib/settings.glsl` 的 `#define NAME 值 // [值域]` 行解析（Iris 改写的就是这一行），因子 = 出现在任一 `#if/#elif/#ifdef/#ifndef` 里的选项；注释与字符串在解析前剥离。命令行入口**只报告不判定、恒退出 0**——"某发现是不是缺陷"需要引擎知识（加载器自己定义了哪些符号、哪些枚举臂是故意不测的），那份知识在 check #13 里，复制一遍就会让两条门对同一个包给出矛盾结论。
- `qa/tools/compile_glsl.py --matrix`（穷举编译门）：把覆盖阵列逐行展开成完整入口集（含 `--matrix-rows` 截断、`--batch-rows` 每批行数、`--jobs` 并发批数）。
- `qa/tools/check_pack.py` 第 13 项（结构判定门）：零消费者选项、未声明分支符号、零读取 `#define`、豁免过期、枚举臂取值漂移、覆盖阵列未覆盖对、与 `option_matrix` 结论分歧，七类一律 FAIL。

规模与实测：

- 67 个带值域选项 → **37 个能翻转预处理器分支**（其余 30 个只作为已选代码的取值输入），87 个层级，666 个因子对 → **83 行两两覆盖阵列，0 未覆盖对**。三个面（CLI 无种子、check #13、`--matrix` 带默认档+三档种子）在真实包上同为 83。
- 全量矩阵：`RESULT_ALL	batches=11	rows=83	entries_per_row=89	linked=7387	failed=0`，零 `COMPILE_FAIL`、零 `COVERAGE_INCOMPLETE`、退出码 0。83 × 89（80 顶点/片元对 + 9 compute）= 7387 个编译链接单元，实机驱动 `OPENGL_VERSION 4.6.0 NVIDIA 572.83`，`--jobs 3` 用时约 28 分钟。日志 `qa/glsl-2026-09-20-option-matrix.log`，每行配置对应哪些非默认取值写在日志头部（`M0xx\t<因子>=<值>`），失败行按此回查。
- 结构门：`python qa/tools/check_pack.py` → 13 项 0 FAIL / 12 PASS / 1 WARN（该 WARN 与 P2-12 无关，是 #4 接线登记）。

缺陷清单（本轮全部处置）：

1. **84 处零读取 pass 身份标记** `#define ASTRA_*`：`ASTRA_UNLIT` 36、`ASTRA_PARTICLE` 12、`ASTRA_SKY` 12、`ASTRA_GLINT` 6、`ASTRA_CLOUDS` 6、`ASTRA_DAMAGED` 6、`ASTRA_EYES` 6。有定义行、全包无一个 `#ifdef`/`#if` 读它——与 §2.18 JCL `KILL_SWITCH` 同一形态，只是这里更轻：它们与所在文件的 include 路径完全冗余（`ASTRA_SKY` 只出现在 `gbuffers_skybasic/skytextured` 的三行薄包装里），删掉不改变任何一次预处理。已删，`Astra/shaders/**` 68 文件 +5/−86 行。
2. **两处裸数字分支**：`Astra/shaders/global/lighting/shadowmap.glsl:117` 的 `#if SHADOW_FILTER_MODE == 0` 与 `Astra/shaders/lib/settings.glsl:329` 的 `== 1`，改为 `SHADOW_FILTER_SOFTWARE` / `SHADOW_FILTER_HARDWARE`，让已声明的枚举常量真有读者。这是本条唯一"补读者而非删定义"的处置——那两个 token 有真实分支归属。
3. **判为合法豁免的 9 个名字**，每条都配了实时断言而不是放行：4 个引擎像素格式 token（`RGBA16/RGBA16F/RGBA32F/R11F_G11F_B10F`，由 `shaders.properties` 消费）；2 个加载器侧符号（`ASTRA_VOXY_PASS` 属 C5 归属的 Voxy 分支、`EXTERNALLY_DEFINED_UNIFORMS` 是恒真 include 守卫，都不在 jar 里）；3 个枚举臂常量（`SKY_MINISHITA`/`SUN_MOON_DISCS`/`WATER_BALANCED` 命名的正是"没有分支测它"的那一臂，代码只判另一个值后让它落空）。check #13 要求每个豁免 token 始终等于其选项的一个真实取值——漂移即 FAIL，符号变成有读者后豁免过期也 FAIL。
4. **工具自身两处盲区**（不修就会漏报）：定义行不算读者，否则零消费者选项永远不会被报出来；`unread_macros` 与 `undeclared_guards` 用同一套 `#ifdef` 发现规则，与 check #11（SC-28 那条 Iris 发现规则）双向对齐，两条门不能互相矛盾。
5. **覆盖阵列的层级裁剪是可靠的**：只保留"出厂默认 + 至少出现在一次比较里的值"。理由是某个取值若在全包任何条件里都不出现，它展开出的翻译单元与另一个同样不被比较的取值逐字节相同——省掉的是重复劳动，不是覆盖率。

门的灵敏度已被证明（防"恒绿门"）：

- 静态侧：六种缺陷形态各注入一次，全部在 `copytree` 出的临时副本上做，真实包零改动，#13 逐条精确 FAIL。
- 编译侧：把 §2.19 的 VanillaPlus 缺陷形态原样搬进副本——新增枚举 `#define GAMUT_MODE 0 // [0 1 2]`，并在 `Astra/shaders/global/post/grading.glsl` 追加 `#if GAMUT_MODE == 2` 分支引用未定义符号 `sRGB_P3D65`。同一副本、同样只编 `final`：**三档出厂扫描 `linked=9 failed=0` 退出 0，完全看不见**；矩阵 `rows=88 linked=219 failed=45` 退出 1，首个报错 `error C1503: undefined variable "sRGB_P3D65"`，15 行命中 × 3 个维度壳。副本与注入脚本已删除。
- 运行纪律：`--log` 只在结束时写，判成败看日志里有没有 `RESULT_ALL` 行，**不看工具回执**。本轮两次矩阵运行被超时杀掉，包装器照样报 "completed (exit code 0)"，白等两轮才发现什么都没跑完。

未采纳与不成立的部分（P2-12 原文三条做法不照搬）：

- 原文"从 `shaders.properties` 的 `screen` 块解析全部 token 与取值域"→ 改从 `lib/settings.glsl` 解析：那才是 Iris 逐档改写的行，`screen` 块只决定 GUI 排布，且 `size.buffer.*`、`clouds.*` 一类条件 token 根本不在 screen 里。
- 原文"同族选项全组合（笛卡尔积）"→ **明确否决**：仅 shadow 一族（`SHADOWS × COLORED_SHADOWS × STATIC_SHADOW_FALLBACK × SHADOW_FILTER_MODE × SHADOW_DISTANCE × ENTITY_SHADOW_DISTANCE`）就 640 行，而两两覆盖已包含该族内部每一对取值组合。穷举预算从数百行降到 83 行，这条门才在本机跑得完。
- 原文"抽样"→ 实际不抽样：83 行是完整的 t=2 覆盖阵列，未覆盖对为 0；`--matrix-rows` 截断时输出 `COVERAGE_INCOMPLETE` 并非零退出，防止"小一点的矩阵"被当成通过。

接入后续每个工单的收尾：`qa/regression-checklist.md` 通用第 1 行已改写为「`python qa/tools/check_pack.py`（13 项 0 FAIL）+ `python qa/tools/compile_glsl.py --matrix`（83 行穷举 0 failed）」，T3 起每次交接按此行勾验。成本口径写清楚：矩阵门约 28 分钟（每批一个驱动 JVM ≈ 600 MB，本机空闲内存只剩 ~6 GB 时 `--jobs 3` 是实际上限），因此**逐工单**的即时回归仍跑默认三档扫描（267 单元、2–3 分钟），矩阵门在交接与里程碑收口时跑；改动选项声明、值域或任何预处理器条件的工单，收尾必须跑矩阵门。

**F-3 · T3 执行 P2-10 + P2-11 合规与防退化基建**

落地四件：`Astra/shaders/lib/vendor/README.md`（目录 + 约定正文，42 行）、`Astra/THIRD-PARTY.md:55` 新增「第三方隔离目录」节、`qa/tools/check_pack.py` 第 14（`qa/tools/check_pack.py:1286-1376`）与第 15 项（`:1378-1446`）、`qa/tools/test_gate_sensitivity.py`（新，常驻灵敏度自证）。检查项 13 → 15。

P2-11 的真实缺口不在包内，而在门内。`check_pack.py` 早已有 SC-27 那条缓冲格式检查，但它扫的是 `strip_comments(read(p))` 的结果——注释被替换成空格后，被 `/* */` 整块包住的声明**连同声明语法一起消失**，所以 VanillaPlus `lib/pipeline.glsl` 那 53 行注释块在 Astra 的门里是不可检形态。第 14 项因此不复用 `strip_comments()`，自带一个注释区间扫描器（`_comment_spans()`，`:1298`，逐字符区分 `//` 与 `/* */`，不做正则近似），判据是"具备声明语法 **且** 起点落在注释区间内"。

覆盖面比原文宽一档：原文只点名 `const int colortexNFormat` 与 `const …Clear`，第 14 项按语法形态收 `const <bool|int|float|vec4> <NAME> = …;`，NAME ∈ `{*Format, *Clear, *ClearColor, *ClearAlpha, *ClearDepth} ∪ 七个引擎标量`（含 `depthtex*` 与 `shadowMapResolution` 一族）。同一个盲区不该开两条规则。唯一性只补 `*Clear*` 一类——`*Format` 的"一个缓冲只声明一次"已由第 11 项 SC-27 管着，两条门不重复报同一件事。

实测：全包 13 条缓冲声明——`Astra/shaders/lib/settings.glsl:361,365-369` 6 条（ClearColor 与 Clear）、`Astra/shaders/lib/water_buffer_formats.glsl:12,15,16,18` 4 条 Format、`Astra/shaders/program/end_illumination.fsh:10,11`、`Astra/shaders/program/end_sky_buffer.fsh:9`——另加 47 条引擎标量声明（`entityShadowDistanceMul` 一族，仅它就占 40 处），合起来即第 14 项报告的 **60 条活声明覆盖 10 个缓冲，注释内 0 条**；每个被声明缓冲的名字读者数 colortex0=6、colortex2=1、colortex3=2、colortex4=1、colortex5=1、colortex6=1、colortex7=2、colortex8=2、colortex9=1、shadowcolor0=2，全部 ≥1。判据边界写清楚：读者 = 抹掉声明语句自身之后的代码引用（声明行本来就写着自家缓冲名，不能自证）；输出侧 `gl_FragData[N]` 是按索引写、按名字匹配不到，所以本条判"有名字读者"而**不判"有写入者"**——后者要 pass 图求值，超出静态门能诚实承担的范围。

P2-10 的第 15 项四条规则：目录与 README 必须存在；`lib/vendor/**` 内除目录自带 README.md 外的每个文件必须按全路径出现在 `Astra/THIRD-PARTY.md`；每个上游目录必须自带许可证原文（`LICENSE`/`LICENCE`/`COPYING` 前缀）；`lib/vendor/` 之外任何着色器文件出现 MIT/BSD/GPL 正文段落即 FAIL——最后一条就是那条反规范，实测全包 0 处。目录本身目前是空基座（只含约定 README），`lib/vendor/<upstream>/` 由 T16 填。

一处只有跑负例才会暴露的实现约束：登记判据是"路径字符串出现在台账里"，于是**约定正文里不能举真实形态的示例路径**。初稿在 `Astra/THIRD-PARTY.md` 里写了 `shaders/lib/vendor/renderpearl/LICENSE.txt` 当例子，任何真的叫这个名字却没登记的文件都会被误判为已登记；改成 `<upstream>/<file>` 这种不含真实文件名的写法后 s5 才真正 FAIL 出来。同类"注释里的缓冲名不能算读者"的边界由 s8 对照场景守着（注释提一句 `colortex12Format` 必须仍然全绿）。

门的灵敏度：`python qa/tools/test_gate_sensitivity.py` → **9/9 按预期**。七个注入各打一条规则，全部在 `copytree` 出的临时副本上做、真实包零改动：块注释包住的 `colortex7Format`、行注释掉的 `colortex5ClearColor`、幽灵缓冲 `colortex11Format`、重复的 `colortex6ClearColor`、未登记的 vendor 文件、缺许可证原文的上游目录、vendor 外的 MIT 正文；两个对照是"出厂包 0 FAIL"与"注释提及缓冲名仍然干净"。脚本按场景断言"归属那条 check 触发且消息命中 + 其他 check 无连带 FAIL"，退出码 = 未按预期的场景数。

顺带清掉一处死代码：`FORMAT_NAMES`（原 `qa/tools/check_pack.py:745`）是一份六项缓冲名列表，全包无引用且已过期（缺 colortex5..9、无 depthtex）。新门从声明语法推导缓冲名，不复活它，直接删。

未采纳与不成立（P2-10/P2-11 原文做法不照搬）：

- P2-11 原文的"验证"写成 `check_pack.py` 新检查项 **+ `python qa/tools/sc35_image_analysis.py`**。后半句与本条无因果关系——那是逐像素图像比对工具，防退化门判的是源码声明，不执行。
- 原文"要求每个被声明的格式都有至少一个消费者"按"名字读者"可实现、按"写入者"不可实现（见上），已按前者落地并把边界写在代码注释与门禁消息里。
- 台账登记粒度没有采用"整目录一行覆盖全部文件"：那会让 T16 新增的第二个文件悄悄免检。README.md 由目录行覆盖是唯一的例外，理由（它是 Astra 自写文本、不是第三方件）写在 `Astra/shaders/lib/vendor/README.md` 登记规则第 1 条里。

收尾门：`python qa/tools/check_pack.py` → 15 项 0 FAIL / 14 PASS / 1 WARN（WARN 仍是 #4 接线登记，与本条无关）；`python qa/tools/compile_glsl.py` 默认三档扫描 `linked=267 failed=0 compute=27`，exit 0，日志 `qa/glsl-2026-09-20-t3-compliance.log`。矩阵门未重跑，按 F-2 定的成本规则：本轮零 GLSL 语义改动、选项声明与值域一字未动。

本条初稿被报告自己的三道门抓出两处，均已按实测改正：第 14 项报 60 条，而初稿的锚点清单漏了 `Astra/shaders/program/end_illumination.fsh:11`（`colortex8ClearColor`）只列到 12 条缓冲声明、于是写成 59——教训是"门报的数字要按门的输出抄，不按记忆写"；`final_sweep.py` 第 8 项又把正文里指代"通用形式"的那个双字词当成未替换记号报红（该词本身出现在正文即命中，故此处不复述），改写后九项全绿、引用门 515 条与四类硬失败 0 不变。

**F-4 · T4 执行 P2-18 按维度裁剪管线**

原文的三条做法（新增 `dimension.properties`、按维度覆盖属性、buffer 分配跟随维度）实测下来只有一条半可执行，其余两条在 Iris 1.11.2 里根本没有对应的机制。先把引擎事实钉死（全部为 `iris-fabric-1.11.2+mc26.2` 字节码实测，非文档推断）：

1. `world0` / `world1` / `world-1` 三个目录名到维度的映射，只在 `dimension.properties` **缺失或为空**时由 `Files.exists` + `putIfAbsent` 填入默认值。也就是说包内不写这个文件才有默认映射，写一份不完整的反而会把没列出的维度变成未映射。结论：Astra 维持现状，**不新增 `dimension.properties`**，按维度裁剪全部走目录 + `program.` 命名空间。
2. `loadProperties(Path, String, Iterable<StringPair>)` 对 `shaders.properties` 只读根目录那一份，第三个参数是包选项列表而不是维度目录 ⇒ **不存在 `<world>/shaders.properties` 合并**，"按维度覆盖属性"没有任何入口。
3. 属性查找键是 `ProgramSource.getName()`，即裸 pass 名。因此 `size.buffer.*`、`blend.*`、`texture.*`、`image.*`、`uniform.*` 都不接受 `<world>/` 前缀——写成前缀形态会被存进一个永远没人查的名字下。只有 `program.` 一族带命名空间。
4. `compute.*` 键族在 1.11.2 完全没有解析器，任何拼法都是死键。

包侧改动两处，都是"把不生效的写法换成生效的写法"，不改任何视觉意图：

- 删 46 条 `blend.world*/…` 键（`Astra/shaders/shaders.properties`）。逐条核对过替身：`blend.shadow=off`（`:72`）、`blend.gbuffers_water.colortex5`（`:73`）、8 个半透明 pass 在 `#ifdef FANCY_TRANSLUCENTS` 两臂下的 root 形态（`:91-109`）、5 个 pass 的 `.colortex3=off`（`:110-114`），值一字不差。这些名空间键此前从未被查表命中，删掉后 GPU 状态零变化；真实收益是消灭了 46 条"看起来按维度配过、实际与根块各写各的"漂移源。
- 9 条 Nether 光照 compute 门改写为 `program.world-1/shadowcomp{,A..H}.enabled=NETHER_VOXEL_LIGHT`（`:330-338`），并从 `#ifdef NETHER_VOXEL_LIGHT` 内部搬到外部——只在选项已经打开之后才存在的门开不了任何东西（事实 4 同时否掉了旧拼法 `compute.world-1/shadowcomp*.enabled`）。`image.*` 与 `iris.features.optional` 仍留在 `#ifdef` 内（`:344-349`），因为加载器会拒绝声明图像却没有 `CUSTOM_IMAGES` 特性标志的包。文件 375 行 → 349 行；目录限定 `program.` 门 25 条，非 `program.` 名空间键 0 条。

**测量工具自身是 F-1 高报的根因，已一并收紧。** `qa/tools/inspect_iris_properties.py` 原本把任何以 `.enabled` 结尾的键都算作 pass 门，于是 9 条死键被计入"+14"。现在 Java 侧探测器只在 `program.` 前缀时输出 `GATE`，其余 `.enabled` 键单独输出 `DEADGATE`，Python 侧把 `DEADGATE` 汇成第四项并在有残留时直接 FAIL：「gate-shaped key(s) Iris never reads, so the pass dispatches in every tier」。负例已实测：把当前包复制到临时副本、按旧拼写还原那 9 条，工具报 `+5 gate(s) on / 15 on in BALANCED` 并 FAIL；改回 `program.` 拼法后才是 `+14 / 24 on`，且 9 条 shadowcomp 门在 PERFORMANCE 解出 `EFFECTIVE=false`。F-1 的原始记录已在 11.F-1 对应条就地更正。

新增 `qa/tools/check_pack.py` 第 16 项 `check_dimension_gating()`（`:1468-1565`），检查项 15 → 16，四条 FAIL 规则：名空间前缀出现在非 `program.` 键族；目录限定门指向未知维度目录或"目录与根都没有该 pass"；root 条件门没有目录镜像（root 门到不了维度目录，Iris 只匹配带目录前缀的键）；门条件标识符与该键自身外层的正向 `#if/#ifdef` 集合有交集（本轮搬出 `#ifdef` 的九条 shadowcomp 门正是这一类）。另两类只报 NOTE。第一类是 6 条 pass 文件只存在于包根的目录门（`program.world-1|world1/composite2|composite3|composite4.enabled=false`，`:56-59`、`:75`、`:79`；这三个 pass 在根目录 vsh+fsh 成对齐全，两个维度目录里一份都没有）。这类门的意义取决于 Iris 是否让维度目录按 pass 回落到根源码——**但两种读法下 Astra 的可观察结果相同**：若无回落，这些门只是冗余（目录本来就没这个 pass）；若有回落，`false` 恰恰就是压住根源码所需的那一句。所以包不依赖这个未定行为，NOTE 只登记不判定。顺带把问题缩小了但没关闭：`ShaderPack` 只存一个 `base` ProgramSet 加一张 `NamespacedId → ProgramSetInterface` 的 `overrides` 表，`getProgramSet(dim)` 在有目录时整体返回该目录的集合、否则返回 `base`；`ProgramSet.get(ProgramId)` 只查自家 `EnumMap`，`ProgramFallbackResolver` 的唯一回落是 `ProgramId.getFallback()`（同族改名，不是根源码）。按 pass 合并根集合若存在，只可能在维度 ProgramSet 的构造参数（那个 `Function<AbsolutePackPath, String>` 源读取器）里，本轮没有解析到那一层。参照包侧这个形态很常见：RedHat 的 `world-1`/`world1` 各省掉 `gbuffers_water`，`just-colored-lighting` 三个目录各省掉 `dh_shadow` 与 `gbuffers_line`，而根目录都照常发货。第二类 NOTE 是"每维度 buffer 尺寸不可表达"这条——`size.buffer.*` 按裸名索引，所以 P2-18 验收里的"buffer 分配跟随维度配置"在 1.11.2 无法实现，改由键族规则关闭而不是假装做到。

顺带修掉一处会让新门永不报警的校验器缺陷：SC-30（`qa/tools/check_pack.py:1005-1050`）的 `gated_programs` 现在只从 `program.*.enabled` 收集（`:1016-1020`）。旧写法同样照单收任何 `.enabled`，那 9 条死键会让 shadowcomp 阶段"看起来有门"，`:1047` 的"整个阶段没有开关条件"警告就永远不响——死键正是靠这个假象藏了很久的。

门的灵敏度：`python qa/tools/test_gate_sensitivity.py` → **14/14 按预期**。第 16 项新增五个负例（`s9` 名空间 blend 键、`s10` root 门缺目录镜像、`s11` 门被自身 `#ifdef` 藏住、`s12` 门指向不存在的 pass、`s13` 门指向未知维度目录），仍在 `copytree` 出的临时副本上注入、真实包零改动，F-3 那九个场景一并复跑无回归。

未采纳与不成立（P2-18 原文做法不照搬）：

- "新增 `dimension.properties` 以按维度裁剪管线"→ 与事实 1 相反：默认映射恰恰依赖这个文件不存在，裁剪能力全部来自 `program.<world>/<pass>.enabled`，加文件只会引入风险。
- "buffer 分配跟随维度配置"与"按维度覆盖 blend"→ 与事实 2、3 冲突，引擎侧不可表达。per-dimension blending 的正确出口是着色器源码自己写混合结果，已把这句连同实测出处写进 `shaders.properties:68-71` 的注释，防止后人再把键加回来。
- 原文未区分 `program.` 与 `compute.*`，直接把两者都当可用指令族；事实 4 使这条验收只能通过 `program.` 形态达成。

待实机：本轮关掉的是"三档全派发"这个形态，改不动的是它造成的后果能否被观察到。`Astra/shaders/program/nether_light.csh:12-16` 无条件声明 `usampler3D` / `sampler3D` / `writeonly image3D`，并以 `ivec3(8,8,8)` 派发 512 组；旧拼写下门从不生效、而 `image.*` 又随选项被预处理掉，因此"往未配置的图像单元写"在真实引擎里三档都存在过。改写后该路径在选项关闭时不再加载，是否留下过 GL 错误或性能差只能进游戏对照，记在收尾清单里。

收尾门：`python qa/tools/check_pack.py` → **16 项 0 FAIL / 15 PASS / 1 WARN**（WARN 仍是 #4 include 图接线登记，与本条无关），#16 报「32 program gate(s) (25 folder-qualified), 0 inert namespaced directive(s)」，并把上面那类门登记成「6 folder gate(s) whose pass file exists only at the pack root … 6 of them read a literal false, which switches the pass off either way」；`python qa/tools/inspect_iris_properties.py` 退出 0，三档门阶梯 `+14 / 24 on`；`python qa/tools/test_gate_sensitivity.py` → 14/14；`python qa/tools/compile_glsl.py --matrix --jobs 3` → `RESULT_ALL batches=11 rows=83 entries_per_row=89 linked=7387 failed=0`，exit 0，日志 `qa/glsl-2026-09-20-t4-dimension.log`（本轮改了 `shaders.properties` 的条件与门，按 F-2 定的成本规则矩阵门必须重跑）；`qa/iris-properties-resolved.txt` 重生成 328 行，`:308-316` 为九条 `program.world-1/shadowcomp*.enabled=1`，`compute.*` 行已归零。

**F-5 · T5 执行 P1-9 畸变按影距归一（并闭合 P1-5 残差）**

改动两处 GLSL，出厂 BALANCED 的剖面数值一并重排（这不是"默认档不动"的改动，见剖面表第二行）：

- `Astra/shaders/lib/distort.glsl:16-17`：`SHADOW_DISTORT_FACTOR` 由裸常量 `0.20` 改成 `SHADOW_DISTORT_CORE / float(SHADOW_DISTANCE)`，新常量 `SHADOW_DISTORT_CORE = 25.6` 是归一后的锚值（块半径）。`:7` 为此加上显式 `#include "/lib/settings.glsl"`——原写法靠调用方先包含 settings，改成表达式后 `SHADOW_DISTANCE` 是本文件自己读的符号。核实过：这是**包内第一处 lib→settings 直接包含**，其余读选项符号的 lib（`lib/uniforms.glsl`、`lib/transforms.glsl`）一律靠入口先展开 settings；保留这一行是不让常量初始化式隐式依赖包含顺序。守卫 `ASTRA_LIB_SETTINGS_GLSL` 已在，重复展开不会二次定义；lib→lib 嵌套包含在包内本就成立（`lib/solas_water.glsl` 包含 `lib/transforms.glsl`）。本文件唯一包含点是 `global/lighting/shadowmap.glsl:17`。
- 文件头注释按推导重写：`k = SHADOW_DISTORT_FACTOR × SHADOW_DISTANCE` 是**落到半幅边界的块半径**，不是"texel 密度减半处"——旧注释与 Steadfast 原说法在重推后不成立，`r = k` 处密度是中心的 1/4。完整剖面 `blocks/texel = 2(r+k)²/(R·k)`，中心 `2k/R`，接收面边缘落 `ρ(D) = 1/(1+a)`，边缘外空区面积占比 `1 − (1/(1+a))²`。
- P1-5 残差在 `Astra/shaders/global/lighting/shadowmap.glsl`：End 分支固定 `+0.015` 块折进纹素相对项，`:210` 现为 `end_shadow_texel_size() * 0.46`（0.46 = 原 0.30 加上出厂 2048 图下 0.015 块的纹素折算，出厂默认数值不变，整项从此随 `SHADOW_RESOLUTION` 缩放）；`:202` 新增独立常量 `shadowGrazingBias = 0.20` 并注释写明它与畸变因子解耦——归一之后若继续借用 `SHADOW_DISTORT_FACTOR`，掠射偏移会随影距档位漂走。

实测剖面（`python qa/tools/shadow_frustum_probe.py --ladder`，改前 → 改后；k = 半幅块半径，中心 = 中心 blocks/texel，交点 = 0.15 blocks/texel 退化阈值出现的半径，空区 = 接收面边缘外的图面积占比）：

| profile | D / R | k | 中心 | 交点 | 空区 |
|---|---|---|---|---|---|
| PERFORMANCE | 192 / 1024 | 38.4 → 25.6 | 0.0750 → 0.0500 | 15.9 → 18.7 | 30.6% → 22.1% |
| BALANCED | 256 / 2048 | 51.2 → 25.6 | 0.0500 → 0.0250 | 37.5 → **37.1** | 30.6% → 17.4% |
| ULTRA | 256 / 4096 | 51.2 → 25.6 | 0.0250 → 0.0125 | 74.2 → **63.1** | 30.6% → 17.4% |

- 归一不变量成立：`--all-distances` 遍历 `SHADOW_DISTANCE` 全部 8 个广告值（`settings.glsl:67` 的 64/80/96/112/128/160/192/256，R=2048），改后 k / 中心 / 交点三条恒为 25.6 / 0.0250 / 37.1；改前同一遍历里中心从 0.0125 漂到 0.0500、交点从 31.5 漂到 37.5——"影距滑块同时改细节和改距离"正是要消除的东西。代价按预言兑现：滑到 64 时空区从 30.6% 涨到 49.0%（80 档 42.6%），这段由上游 `shadowDistanceRenderMul = 1.5`（`settings.glsl:219`）部分填掉。
- ULTRA 是本条唯一实测退化点：交点 74.2 → 63.1 块。符号来自 `dr*/dk = sqrt(0.15·R/(8k)) − 1`，在 R=4096 处为正——更小的 k 换来 2× 中心细节（0.0250 → 0.0125），代价是最外 11 块的边界密度。属档间取舍而非缺陷，记待实机。
- 锚值是量出来的不是审美的：除 k=25.6 外还量过 Steadfast 自家产物 k=32（0.20×160，中心 0.0312、交点 38.1，即用 25% 中心细节换 1 块边界）与被否掉的 k=51.2（在 256 下与改前逐字节相同，但 192/1024 下中心 0.1000、交点 11.5，比现状更差）。重调只需改 `SHADOW_DISTORT_CORE` 一个数。

工具侧两处修复：`qa/tools/shadow_frustum_probe.py` 从源码正则读因子（`FACTOR_CONST` / `FACTOR_SCALED` 两种形态，出现第三种形态直接报错），因此 `--ladder` 报的是编译期真值而非常量副本；本轮再修一处——0.15 blocks/texel 交点原先取自 13 点采样网格，只会返回被采到的格点（改后 BALANCED 报 48 而真值 37.1），已换成闭式解 `r* = sqrt(0.15·R·k/2) − k` 并加"交点落在影距外则报 never within range"分支。

P1-5 / P1-9 验证条点名的 `qa/tools/validate_shadow_water.py` 本轮跑红，与 T5 无因果关系，如实记账：

- 对照证据：`git archive HEAD Astra/shaders qa/tools` 还原成临时树跑同一工具，HEAD 侧同样 FAIL。覆盖像素 154²（HEAD）→ 166²（本树，面积 +16.2%），最大深度误差 0.11305 → 0.11077（−2.0%），容差 2e-6。方向与本条意图一致（同一输入足迹下径向收缩更弱），量级远未过容差。
- 根因：该工具内嵌的 Java 参考模型（`:59` 的 `m/(.2+.8*m)`、`r=max(|qx|,|qy|)`、系数 0.25）描述的是 2026-09-09 换源**之前**的方形扭曲——最后一次 PASS 停在 09-08（`qa/render-path-verification.log`，覆盖 232²）。换源时模型没同步，之后无人再跑。修模型另开工单，T5 不夹带；工作树里那份跑不完后四项检查的截断 FAIL 日志已 `git checkout` 还原，不当作本条产物提交。

不成立与就地更正：报告原引 `distort.glsl:7,10`（改后新落点 `:16-17`）；`settings.glsl:64/:216` 实测漂到 `:67` / `:219`，已按实测校正并在正文标注；P1-5 原述两处 bias "并存"是对分支结构的误述（`#ifdef DIMENSION_END` 互斥），11.B 已据此把该行裁决为撤条并入本条。`docs/2026-09-20-reference-pack-study.md` 不含 `distort` / `SHADOW_DISTORT` 字样，本条不动它。

待实机（三项全部进 `qa/regression-checklist.md` M2 新行 6a）：ULTRA 最外 11 块的边界密度是否可辨；影距滑到 64/80 时 49.0% / 42.6% 的图外空区会不会以"远处阴影消失"的新形态出现（旧形态是远场密度粗，两者观感不同）；末地偏差项现随 `SHADOW_RESOLUTION` 缩放，在 512/1024/1536 三档下是否出自阴影条纹。

收尾门：`python qa/tools/check_pack.py` → **16 项 0 FAIL / 15 PASS / 1 WARN**（WARN 仍是 #4 include 图接线登记，与本条无关）；`python qa/tools/compile_glsl.py` 三档默认 → `linked=267 failed=0 compute=27`，exit 0，日志 `qa/glsl-2026-09-20-t5-shadow.log`；`python qa/tools/test_gate_sensitivity.py` → 14/14 按预期；`python qa/tools/provenance_steadfast.py --quiet` 计数不变（`verbatim=14 literal-suffix=2 rewritten=6 astra-only=24`）——本条只动 GLSL，该工具只分类 `shaders.properties` 表达式，不变才是预期结果；`python qa/tools/inspect_iris_properties.py` 退出 0；`python qa/tools/compile_glsl.py --matrix --jobs 4` → `RESULT_ALL batches=11 rows=83 entries_per_row=89 linked=7387 failed=0`，exit 0，日志 `qa/glsl-2026-09-20-t5-matrix.log`（11 批 `RESULT` 逐批相加 = 7387 / 0，与汇总行一致）。按 11.F-2 定的成本规则，本条其实只需三档扫描就能收口——矩阵遍历的 83 行选项空间不因本条改变（`shaders.properties` 与本条无涉）——跑全矩阵只是为了给改后的 `distort.glsl` 与 `shadowmap.glsl` 在全部选项面上留一份等价证据。

**F-6 · T6 执行 P1-17 水吸收侧面深度界 + 未命中近场缓释**

包侧只动一个文件：`Astra/shaders/program/water.glsl`（359 行，落地 sha256 `6e858683…`），三处改动。

- 新增 helper `water_surface_absorption_depth`（`:41-44`）：`dot(origin−point, faceNormal)` 之后 `view_player(faceNormal).y > 0.9 ? depth : min(depth, 1.0)`。两个调用点 `:95`（折射推进的每个 tap）与 `:112`（只用锚点的回落读）。11 行注释写明几何理由与 Steadfast 代理的对应关系。
- 未命中回落 `:339-347`：空气侧换成 `water_surface_medium(texture(colortex4, uv).rgb, mix(0.25, 23.0, clamp(−viewPos.z/24, 0, 1)), astra_water_incident(skylight))`。`belowWater`（眼在水下）那一支逐字保留 HEAD 的 `astra_water_air_sky(transmittedWorld)`——本条只改空气侧。
- 远端 23.0 不是审美值：`global/water/absorption.glsl:74` 的 `clamp(depth + 1.0, 0.0, 24.0)` 就是这条吸收曲线的量程上界，23+1 正好撞到钳位；单次散射填充用的水体自色 `(0.020, 0.160, 0.300)`（`:70`）因此成为深水回落的落点，而不是继续往黑走。

侧面界的实测（`water_path_probe.py` mode 17/18 取 helper 原值，19/20 在同一段墙面几何上比颜色）：

| 沿法线的相机—背景距离 | 1.2 块 | 8.3 块 | 48.4 块 |
|---|---|---|---|
| 墙面深度 改前 → 改后 | 1.1875 → 1.0 | 8.3125 → 1.0 | 48.4375 → 1.0 |
| 顶面深度（不设界，应保持不变） | 1.1875 | 8.3125 | 48.4375 |
| 墙面吸收 r 通道 改前 → 改后 | 0.06249 → 0.07389 | 0.00724 → 0.07389 | 0.0072 → 0.07389 |

平视 48 块处 r 提亮 10.3×、g 3.9×（0.10792 → 0.42184）、b 1.77×（0.2371 → 0.41845）；1.2 块处只差 +18%，因为那里本来就只有 1.1875 块——修正只在远处起作用，符合"远处被整段当成水体"的病灶位置。

未命中缓释的实测（mode 9 改前式 vs mode 10 改后式，同一次编译并排；x 扫 1..49 块）：

- 改前式在 7 个距离上逐位相同：`(0.0072, 0.06256, 0.13049)`。它的深度来自那条 96 块射线的垂直跨度，只取决于折射角，与"未命中有多远"无关。把水面挪到眼平以上就变成 `(0.00455, 0.00655, 0.00996)`——g 通道差 9.5×，即同一个距离上抬个视角颜色就换一档。
- 改后式按距离单调：1.2 块 `(0.02038, 0.28977, 0.62802)` → 3.8 `(0.00829, 0.24109, 0.56464)` → 8.3 `(0.00722, 0.18126, 0.47575)` → 24.8/48.4 收敛 `(0.0072, 0.09422, 0.29587)`；近端总亮度 4.7×，且每个通道在任何距离都不低于改前。眼上/眼下两组数值逐位相同 ⇒ 缓释只读距离，不再读射线角度。
- 被否掉的两个背景：换成解析天空模型的话，1.2 块处 `astra_reflection_sky`（mode 16）给 `(0.00671, 0.01609, 0.02447)`、`astra_water_air_sky`（mode 21）给 `(0.00669, 0.01594, 0.02425)`——两者彼此几乎无法区分，却比 scene copy 暗 18–26×。接缝正好落在 `mix(straight, …)` 的交接处，所以"另起一个天空模型"这条路按实测否掉。
- mode 13（同一距离扫描下单独跑 `astra_fog`）在 1..49 块四通道全部精确 0 ⇒ 回落色在该配置下不会被雾掩盖。这是本工具首次实测，HEAD 侧没有对应记录，不写成复核。零值有条件：`atmosphereFogCoefficient` 按 `shaders.properties:214/218-219` 的 CPU 公式取 `(1 + 0.01·max(0, far−200)) · (0.60/far)³`，探针 far=256 ⇒ 2.0e-8；影距缩到 64 时同一个系数大 41×，49 块处的雾就不是 0 了。所以"回落色不被雾掩盖"跟着影距走，不作为无条件结论。

端到端（完整 `astra_water()`，mode 7/8 平视、14/15 瀑布对天空，近 2 块 / 远 40 块；端到端值还叠了 Fresnel 反射混合，不等于回落式单测值）：

| 场景 | HEAD | 落地 |
|---|---|---|
| 平视·近 | (0.00677, 0.05792, 0.12069) | (0.01241, 0.25287, 0.56167) |
| 平视·远 | (0.00098, 0.00742, 0.01535) | (0.00098, 0.01109, 0.03452) |
| 瀑布·近 | (0.00422, 0.00607, 0.00923) | (0.01231, 0.25281, 0.56165) |
| 瀑布·远 | (0.00067, 0.00093, 0.00138) | (0.00098, 0.01109, 0.03452) |

HEAD 那一列自证了症状：同距离的瀑布与平视差一个数量级（g 9.5×、b 13×），而落地后两行"近"彼此差 ≤1e-3、两行"远"逐位相同——回落只按距离给色，不再按射线方向给色。

反向验证两条，都做完并复原到位（前后 sha256 一致，复跑 exit 0 且 `results.json` 与反向验证前逐键相同）：

1. 抽掉侧面 `min` 界（helper 改回 `return depth;`）⇒ `water_path_probe.py:280` 先红；反向验证那一轮产出的 `results.json` 里 `absorption_depth_wall` 与 `absorption_depth_top_face` 变成同一列（1.1875…48.4375），`wall_absorption_bounded` 与 `_unbounded` 逐位相同，故 `:282` 随后也会红；`:281` 不受影响，因为顶面本就不设界。
2. 只把未命中回落改回 HEAD 的 96 块追踪形态 ⇒ **只有** `:306` 红。`:304`（near/far 比 4×）与 `:305`（远端蓝移）在 HEAD 上同样通过（HEAD 实测比值 7.8×），这两条因此只是把落地形状钉住，不构成守门——本条真正的守门断言是 `:306` 一条，工具注释与 §6 验证条都按实测改写成这个样子。

不照搬参照包的三处，逐条理由：① `background *= 1 − fadeFactor`（`absorption_refraction.glsl:119` 前后）会与本包 `water_surface_medium` 内部的 `exp(−depth·σ)` 叠成双重淡出；② 它的 1 块深度上界只属于侧面情形，套在未知水柱上会砍掉真实深水（本包侧面用几何界、未命中用距离缓释，各取所需）；③ skylight 深度代理（`:85`/`:92`，已在参照包源码核对为真）不必引入——它给的是同一个"≤1 块"上界，外加"露天 ⇒ 水浅 1/16 块"的光度假设，而瀑布侧面恰恰露天且真有 1 块厚。

许可证：`program/water.glsl` 早在 `Astra/THIRD-PARTY.md:150` 与 `:176` 登记为"空气侧 Steadfast 0.8.0 派生，GPL-3.0-or-later + Section 7 继续适用"，本条只在该文件加思路级注释（`:312` 指名 `environment/water/absorption_refraction.glsl:97-117`，表达式全部自写），不新增登记行；`check_pack.py` 第 8 项 PASS，`provenance_steadfast.py --quiet` 前后计数不变（`verbatim=14 literal-suffix=2 rewritten=6 astra-only=24 total=46`，该工具只分类 `shaders.properties` 表达式）。

工具侧：`qa/tools/water_path_probe.py` 的 mode 循环从 0..6 扩到 0..21（新增 7..21 共 15 个采样面），文件 178 → 312 行，断言 8 → 19 条、新增的 11 条全部属于本条（分工见 §6 验证条）。`qa/water-path-followup/results.json` 重生成，新增 7..21 号 `.f32`/`.png` 产物。回归对照未动且仍绿：`medium_split_max_error` 1.49e-07、`underside_temporal_mean_difference` 0.055567、`bloom_max_below_white` 0、`air_fog_sweep` 全零。

待实机两项已进 `qa/regression-checklist.md` 新行 10a：侧面 1 块界在瀑布面/水渠侧面是否偏浓（参照包的代理会把露天侧面压到 1/16 块）；未命中缓释的增浓速率在瀑布背后与浅水贴地平线处是否衔接自然。离线只能证明"改前是把整段视野当水柱"，不能证明"1 块看起来对"。

收尾门：`python qa/tools/water_path_probe.py` → exit 0（本轮两次反向验证后复跑，`results.json` 与反向验证前逐键相同）；`python qa/tools/water_stability.py` → `boundary continuity assertions: PASS`、exit 0；`python qa/tools/check_pack.py` → 16 项 0 FAIL / 15 PASS / 1 WARN（WARN 仍是 #4 Voxy C5 接线登记，与本条无关）；`python qa/tools/compile_glsl.py` 三档默认 → `linked=267 failed=0 compute=27`，exit 0；`python qa/tools/test_gate_sensitivity.py` → 14/14 按预期；`python qa/tools/provenance_steadfast.py --quiet` 计数不变。按 11.F-2 的成本规则，本条不碰 `shaders.properties` 也不改任何选项分支，三档扫描即可收口，未跑 83 行全矩阵。

**F-7 · T7 执行 P1-16 前置：`bloom_capture.glsl` 隐式 LOD 显式命级**

包侧只动一个文件：`Astra/shaders/global/water/bloom_capture.glsl`（43 行，落地 sha256 前 16 位 `d123163c82cac357`），两处改动，唯一包含点 `program/water_bloom.fsh:6`；该 pass 在 `:10` 对 `isEyeInWater != 1` 直接 discard，影响面严格限于水下 tile bloom。

- 病灶：`texture(colortex0, sampleCoord)`（改前 `:21`，现为 `:26`）在 6×6 双循环里取隐式 mip level，外层 `:20`（改前 `:15`）是按 tile 判定的数据相关 `if`，而 `program/water_bloom.fsh:5` 声明 `const bool colortex0MipmapEnabled = true`——quad 内有 lane 跳过循环时该次读取的导数无定义。
- 修法不是本报告原写的裸 `lod`（11.D-14）。实测隐式路径选的 level 带一项分辨率补偿：**λ = `lod + log2(F)`，`F = 0.8·viewHeight / min(360.0, viewHeight)`**。因为 `:6` 已有 `pixelHeight = 0.8/min(360.0, viewHeight)` 且 `viewSize.y = 1/viewHeight`，`F` 恰等于 `pixelHeight · viewHeight`，所以 `:16` 新增的 `float level = lod + log2(pixelHeight * viewHeight);` 不引入任何新常量。删掉 `log2` 项会在 270/360/540/1080 上分别短 0.32 / 0.32 / 0.26 / 1.26 个 level——即在每个分辨率都把水下泛光改锐一档。
- `:12-15` 的四行注释写明"这就是导数当初解出的 level"与丢掉补偿项的后果；`level` 只由 `lod`、`viewHeight` 与常量决定，与像素坐标无关，因此命名它不改变任何一次读取的空间位置。

新工具 `qa/tools/bloom_lod_probe.py`（429 行）实测。它复用 `compile_glsl.py` 的 `Expander` / `parse_profiles` / `lwjgl_classpath`，在隐藏的 compat-profile GLFW 窗口里把出厂文件本身 `#include` 进来（非常识内嵌副本），渲染到 RGBA32F FBO（1 屏幕像素 = 1 fb 像素），纹理每级填常数 `R = L/8`，于是读回值直接解出硬件选的 level。6 个 mode × 4 个分辨率（480x270 / 640x360 / 960x540 / 1920x1080），驱动 `NVIDIA 572.83`，`RTX 4050 Laptop GPU/PCIe/SSE2`。

| viewHeight | F | 预测 λ(lod=3) | 改前实测 | 改后实测 | 裸传 `lod` |
|---|---|---|---|---|---|
| 270 / 360 | 0.8 | 2.6781 | 2.7765 | 2.7765 | 2.0 |
| 540 | 1.2 | 3.2630 | 3.1647 | 3.1569 | 3.0 |
| 1080 | 2.4 | 4.2630 | 4.1639 | 4.1562 | 4.0 |

lod 2/3/4/5 共 16 个点全部落在预测 ±0.15 内；同一 lod 在 270 与 1080 之间实测相差 1.39 level（解析值 1.585），所以"分辨率补偿"是量出来的效应，不是对残差的解释。

图像中性：`python qa/tools/bloom_lod_probe.py --baseline ../bloom-lod-probe/pre-fix.json` → exit 0，`level_deltas` 里 270/360 两档 8 点逐位相同（0.0000），540/1080 两档 8 点全为 −0.0078 level。−0.0078 正是探针在此类混合比例下能分辨的最小台阶（1/128 level，等于源 8-bit 编码的 1/4 码），折算到 `exp2(λ)` 决定的模糊半径是 0.54%。唯一不中性的变化是 tile 区域边界：改前驱动把 `:20` 的判定按 2×2 quad 求值，边界吸附在第 97 像素（Python 侧解同一条谓词得到的正确值是 98；亚像素偏移 1.5 与 1.75 两条扫描线都差这一格，`branch_transitions_on_quad_edge_only = true`、`shifts_the_driver_snapped = [1.5, 1.75]`）；命名显式 level 后分支不再需要共享梯度，按像素求值，边界落到 98（`transition_on_quad_edge = false`）。宽度 1 像素，位置在水下 tile bloom 区边缘。

本轮被自己的工具推翻的两条说法，先记账：

1. **"驱动的固定功能 LOD 单元只有约 ±0.1 level 精度"——不成立。** mode 5 用完全不含导数的显式 `textureLod` 打 2.00 / 2.25 / 2.50 / 2.75，读回 2.0078 / 2.1372 / 2.5137 / 2.8902（残差 +0.0078 / −0.1128 / +0.0137 / +0.1402），mode 3 的 1.5 / 2.5 / 3.5 / 4.5 落在同一条曲线上（1.5098 / 2.5137 / 3.5176 / 4.5058），四个分辨率逐位相同。这些读数里没有任何导数可言，偏差却与改前改后同源，所以它是"level → 8-bit `R` → 三线性混合 → 读回"这条链的非线性（随 level 小数部分走），不是采样器选错 level。工具文档据此改成如实口径：**绝对 level 只可信到 ±0.15，两次运行之间的差可信到 0.0078**。
2. **`pow(x, 1/8)` 那条"实测精确中性"不算独立证据。** mode 4 与 mode 5 的解码在代数上互为逆（`decode = 2048·v⁸` 正是把着色器里的 `/256` 与 `pow(·, 1/8)` 反解回 `8x`），两者相同是构造保证；该断言（`|mode4 − mode5| < 0.01`）实际只约束 float32 下 pow/^8 往返的损失。它保留，但定位从"验证往返中性"改成"约束 fp32 幂运算精度"。

旧门为什么改前绿、改后红：原断言 `|mode 0 − mode 2(footprint)| < 1e-3` 两侧同走一条非线性读回曲线，是共模比较，容差再紧也测不出绝对偏差；改后 mode 0 走显式命级、mode 2 仍是导数驱动，1e-3 立刻碎在 −0.0078 上。**没有放宽这条容差**，而是把它降级成显式记录的 `derivative_cancellation_levels`（7 个可比对：4 个 0.0、3 个 −0.0078，门限 0.02）——共模消去之后它约束的是"λ = lod + log2 F"这个模型本身；绝对 level 对预测值的核验另走 ±0.15 门，图像中性交给 `--baseline`。中途还删掉一个临时探针断言（`shipped_taps_still_derivative_driven`，0.01 阈值在 −0.0078 的真相位差上仍判 True，属误判设计而非缺陷信号）。

诚实的负面：这台机器上看不到任何接缝、闪烁或亮度差，改前形态在本驱动上是"看起来对的"。本条买到的是确定性（隐式 LOD 在别的驱动或别的 quad 排布下不保证解出同一个 level，而它决定的模糊半径在 1080p 与 360p 之间本来就差 1.26 level）加那一像素边界更正，不写成"修好了可见问题"。

参照包不跟：Solas V2.2b `shaders/lib/post/computeBloom.glsl`（36 行）同一函数 `:14` 是同样的数据相关 `if`、`:20` 同样是隐式 `texture2D`，上游自带这个 UB。〔另记：先前登记的 Solas `composite13.glsl:19` 声明 mip 的引文不在 V2.2b 树内——该树没有 `programs/composite13.glsl`，那条来自 `_analysis/latest-2026-09-10/solas-shader` 另一棵树（其 `computeBloom` 的 `if` 在 `:13`、tap 在 `:19`），不得作为 V2.2b 引证。〕包内其余显式命级读取重数为 19 处（`global/post/bloom.glsl` 7、`program/deferred.fsh` 4、`atmosphere/weather.glsl` 2、`water/caustics.glsl` 2、`water/light_shafts.glsl` 2、`atmosphere/clouds_planar.glsl` 1、`water/surface.glsl` 1），本条新增第 20 处；全部入口为 `#version 400 compatibility`，显式形式不需要新方言。

待实机一项已进 `qa/regression-checklist.md` 新行 18a：水下 tile bloom 区边缘那一像素的边界移动是否可辨、水下移动与转动视角时有无闪烁。离线能证明 level 稳定（mode 1 的四条扫描线在逼近边界时 `level_at_transition` 与区域内深度值差 < 1e-3），不能证明观感。

许可证：`bloom_capture.glsl:1` 已声明 Solas V2.2b 派生，`Astra/THIRD-PARTY.md:191` 登记该文件"保留 tile 布局、采样权重、编码与混合方程"；本条新增的是自写 level 表达式与推导注释，不改变受登记保护的方程，不新增登记行，`check_pack.py` 第 8 项 PASS。

收尾门：`python qa/tools/bloom_lod_probe.py --baseline ../bloom-lod-probe/pre-fix.json` → exit 0；同工具单跑 → exit 0；`python qa/tools/check_pack.py` → 16 项 0 FAIL / 15 PASS / 1 WARN（WARN 仍是 Voxy 接线登记，与本条无关）；`python qa/tools/compile_glsl.py` 三档默认 → `linked=267 failed=0 compute=27`，exit 0，日志 `qa/glsl-2026-09-20-t7-bloom.log`；`python qa/tools/test_gate_sensitivity.py` → 14/14；`python qa/tools/water_path_probe.py` → exit 0；`python qa/tools/provenance_steadfast.py --quiet` 计数不变（`verbatim=14 literal-suffix=2 rewritten=6 astra-only=24 total=46`）。按 11.F-2 成本规则，本条不碰 `shaders.properties` 也不改任何选项分支，三档扫描收口，未跑 83 行全矩阵。产物：`qa/bloom-lod-probe/pre-fix.json`（改前隐式形态基线，后续任何再动 level 表达式的工单用它对拍）与 `results.json`（本轮绿跑）；工具每次运行会落 283 MB 的 `.f32` 逐帧转储，已加 `.gitignore` 规则不入库。

**F-8 · T8 复核 P1-16：参照机制的驱动信号被本报告读错，本条不落地**

工单 #21 的产出是**零代码改动**（`git show --stat` 只含本文件与两份 qa 台账），因为逐行读参照包源码后，本条的采纳前提不再成立。核对全部在 `_analysis/study-2026-09-20/ComplementaryUnbound_r5.9.3/shaders`（即 §2.1/§6 引用的同一棵树）。

1. **`vlFactor` 是场景感知标量，不是相机运动标量。** 参照包自己的段标题写着答案：`lib/atmospherics/volumetricLight/volumetricLight.glsl:289` "Step 4: Calculate factor of **Scene Aware** Light Shafts"；GUI 侧 `lang/en_US.lang` 的档位名是 `option.LIGHTSHAFT_BEHAVIOUR=Light Shaft Mode` → `value.1=Scene Aware [+]` / `value.2=Regular` / `value.3=Extreme [-]`，其 comment 原话是"Scene Aware Light Shafts automatically transition between regular and extreme"——**自动切换的方向是加质量，不是省质量**。
2. **它的两个输入都与位移无关。** ① `salsCheck`（`:293-316`）：在阴影图日方向的一块 5×5 区域里取 `texelFetch(shadowtex0,…).x < 0.55` 的样本，读 `shadowcolor1.a` 的遮蔽物高度求均值，与 `heightThreshold = 6.0`（`:295`）比较；② `skyCheck`（`:319-338`）：沿画面五个点比 `depthtex0`/`depthtex1` 判"是否看到天空"，`skyCheck >= 3` 时把 `salsCheck` 强制归零并把 `reduceAmount` 由 2 提到 3。整段不含 `cameraPosition`、`previousCameraPosition`、`frameTime` 位移量或任何速度项。
3. **持久化与节奏**：只有角点像素推进累加器（`:291` `if (viewWidth + viewHeight - gl_FragCoord.x - gl_FragCoord.y < 1.5)`），每 `int(0.06666 / frameTimeSmooth + 0.5)` 帧一步（`:292`，`shaders.properties:261` `uniform.float.frameTimeSmooth = smooth(5, frameTime, 5, 5)`；60fps 下约每 4 帧），步长 `OSIEBCA = 1/255`（`lib/common.glsl:843`，注释 "One Step In Eight Bit Color Attachment"）。读写点在 `program/composite1.glsl`：`:339` 读 `colortex5` 的 `texelCoord`、`:343` 写回 `gl_FragData[1] = vec4(0,0,0, vlFactorM)`，而 `:338` 的反向守卫让非角点像素把自己的旧值原样写回——这是"全屏 pass 里保一个状态像素"的读改写技巧。同一个标量在末地被改用作龙死亡动画（`program/deferred1.glsl:509-510` 按 `isEnderDragonDead` 升降），进一步说明它是通用的"场景状态"载体。
4. **它驱动样本数的方向是加。** `vlSceneIntensity = isEyeInWater != 1 ? vlFactor : 1.0`（`:16`），随后 `nearSamples = int(mix(float(nearSamples), 1.5 * nearSamples, vlSceneIntensity))`（`:134`）、`qualityThreshold = mix(qualityThreshold, 100.0, vlSceneIntensity)`（`:132`）、`sampleDistribution = mix(sampleDistribution, 1.5, vlSceneIntensity)`（`:135`）。**决定性的一条**：参照包在 `isEyeInWater == 1` 时把该因子恒置 1.0，也就是恒取最高档、不做任何自适应。

对到 Astra 侧：本条要接的是 `water_shafts_march`，它是 `isEyeInWater == 1` 专属路径（`Astra/shaders/program/scattering.fsh:38-42` 调用，`program/water_composite.fsh:12-17` resolve）。**照搬参照包的真实信号，得到的就是参照包自己在水下写死的那个常量 1.0——机制装上去不会改变任何一帧。** 而本报告原以为可替代的"运动降质"信号没有任何参照：全 `_analysis` 树 237 处相机运动标识符（`cameraMovement|movementAmount|isMoving|movingFactor|motionFactor|velocityFactor|previousCameraPosition`）全部落在 TAA/重投影与顶点摆动路径，其中喂给样本数或循环界的同行匹配为 0；294 处具名循环界里运行时计算的那批（`sampleCount`/`iterations`/`samples`/`steps`/`shadowSamples`/…）无一个由位移派生。扫描按命名与同行表达式过滤，未做跨行数据流追踪，因此这句结论的范围是"受调研包内未见先例"，不是"不存在"。

Astra 已有的运行时循环界也不缺：`global/water/light_shafts.glsl:79` 取 `maxCurrentDist = min(rayLength, maxDist)`、`:84` `if (currentDist > maxCurrentDist) break;`、`:64` 整帧门 `if (visibility <= 0.0) return`（覆盖夜晚/背光/失明）。同一形态直接来自 Solas（`_analysis/Solas Shader V2.2b/shaders/lib/atmosphere/volumetricLight.glsl:52,62-64`：`sampleCount` 是编译期常量而界是运行时的；其云 march 更彻底，`volumetricBlockyClouds.glsl:43` 直接 `clamp(int(rayLength), 0, 16)`）。**剩下没做的只有"把编译期常量本身变成运行时值"**，而 `UNDERWATER_SHAFT_SAMPLES` 同时是三件事的除数——步长 `minDist`（`:78`）、权重归一 `pow((currentDist / maxDist) / float(SAMPLES), …)`（`:94`）、循环界（`:82`）——把它改成运行时变量必须三处同步搬，否则样本数一跳、光束总能量跟着跳，这不是可声称"图像中性"的改动。

再加一条 Astra 特有的冲突：本包无 TAA（§7.B.1/B.10 已定），`dither` 取静态噪声 `texture(solasWaterNoise, gl_FragCoord.xy / 512.0).b`（`:80`，不含 `frameTimeCounter`），所以静止相机下画面逐帧完全一致——样本数从 7 切到 4 会把光束结构直接切换出来，没有任何时域累积可以掩盖。参照包能这么切是因为它同时改的是一组量（分布、阈值、步数）且水下这条路它根本不切。

成本前提同样测不出来：`qa/benchmarks.md` 至今没有 FPS 数据（`qa/open-premises.md` 的 P-4 行已长期挂账），`qa/tools/cost_census.py:1-6` 的文件头原话是 "Loop source inventory, not an execution-cost or GPU-safety estimator… Never label lexical fetch sites as fetches/pixel"。所以本条原验证条"确认平均成本不升"在离线侧给不出证据。用户裁定「实现但默认关，标注待实机」适用于**机制价值已被证实、只是画面/性能需要实机确认**的条目；这里被推翻的是机制价值本身，不是它的观感。

裁决与一致性：与 §7.B.6（反对"零消费者选项"）以及 T2 删掉 84 个无人读取 marker define 的口径一致——落一张没人读的 1×1 缓冲加一个默认关、无参照、无实测收益的选项，正是这些防线要拦的债。**重开条件**（将来若重启，按此前提起步）：先拿到水下场景的帧时间基线，确认 `water_shafts_march` 占比可测且显著；信号按参照包的真实那条（阴影图日方向遮蔽物高度均值），不是相机运动；改动必须把 `:78` 步长与 `:94` 权重分母和 `:82` 循环界一起搬到同一个运行时变量，并给出样本数跳变时的能量守恒证据。

门：包侧零代码改动，因此没有可新增的编译或图像证据；只复跑一致性门确认文档与代码状态未漂移，四道门与 T7 收尾时逐项相同——`python qa/tools/check_pack.py` → 16 项 0 FAIL / 15 PASS / 1 WARN（WARN 仍是 Voxy C5 接线登记），exit 0；`python qa/tools/compile_glsl.py` 默认批（`BATCH 1/1 rows=PERFORMANCE..ULTRA`）→ `linked=267 failed=0 compute=27`，exit 0，日志 `qa/glsl-2026-09-20-t8-docs.log`；`python qa/tools/test_gate_sensitivity.py` → 14/14 按预期，exit 0；`python qa/tools/provenance_steadfast.py --quiet` → `verbatim=14 literal-suffix=2 rewritten=6 astra-only=24 total=46`，计数不变，exit 0。许可证侧无动作：本条未复制任何参照包表达式，`Astra/THIRD-PARTY.md` 无需新增登记行。工单 #21 关闭后解除 #26（T13 P2-20 光束标定）的依赖。

**F-9 · T9 执行 P1-6 几何太阳遮蔽（收窄后的形态）**

落地 = 一个每帧标量 + 一条 alpha 广播 + 末地一次乘子。包侧改动集中在两个文件：`Astra/shaders/program/scattering.fsh`（+53/−4，现 112 行，新函数 `godrays_sun_visibility` 在 `:51-70`、整个守卫块 `:41-71`，写入点是 `main()` 末尾的 `:103-111`）与 `Astra/shaders/program/final.fsh`（+6，消费点 `:60-65`）；其余 5 个文件是选项接线与台账（`lib/settings.glsl` +3、`shaders.properties` 4 行、两份 lang 各 +2、`THIRD-PARTY.md` 登记行）。

1. **补的是哪个洞。** `global/post/godrays.glsl:53-73` 的 march 已经在逐样本查几何遮挡（`depth_compare_sample`，`:32-37`），但两件事它做不到：`DENSITY = 0.83`（`:55`）意味着每条 march 只覆盖"本像素→光源"线段的外侧 83%，光源那一端根本不查；而且判定只看被着色像素自己那条线段。于是一根正好遮住日面、却遮不到当前像素的柱子，仍会在它身后的天空上画满强度不变的光束。本条补的就是这个全局缺口：一帧一次测出日面周围还有多少比例是开阔天空，把整场光束按该比例淡出。
2. **探针。** 以 `lightScreenPos` 为中心的 7×7 = 49 抽，半窗 `PROBE_HALF_WINDOW = 12.0` 个深度缓冲像素（换算 UV 时除以 `viewWidth/viewHeight`，因此窗口是屏幕固定像素尺度，与 `size.buffer.colortex1` 的档间差量无关）。判据与 march 同源：`texture(depthtex1, tapUV).r >= SKY_DEPTH`，`SKY_DEPTH = 1.0` 取自 `godrays.glsl:28`，`>= 1.0` 与 march 里的 `1.0 <= stored` 是同一个天空谓词。开天空占比即 `clear / probed`；49 抽全部落在屏外时（`probed == 0`）返回 1.0——没有信息就不衰减任何东西。成本：整帧 49 次深度读，只发生在一个像素上。
3. **与参照包分歧的一处：深度源。** 现有 march 读 `depthtex0`（`godrays.glsl:36`），探针刻意读 `depthtex1`（仅不透明）。理由是本包的半透明面（玻璃、水面）会写 `depthtex0`，用它可以隔着窗玻璃把整场体积光关掉。这一条是 Astra 自己的判断，不是参照包的做法，也是 `qa/regression-checklist.md` 新行 17a 第 ② 项要实机确认的东西。
4. **载体为什么是 colortex1 的 texel (0,0) alpha。** 广播用 framebuffer 空间两侧对齐——写方判 `all(lessThan(gl_FragCoord.xy, vec2(1.0)))`，读方 `texelFetch(colortex1, ivec2(0), 0).a`，两侧同一个缓冲原点，因此谁都不需要知道缓冲尺寸，也不依赖任何 UV 翻转假设，`size.buffer.colortex1` 的 0.25（PERFORMANCE）与 0.5（BALANCED/ULTRA）两档同时成立。被排除的候选：1×1 的 colortex6 四个通道已被水介质状态契约占满（`shaders.properties:31` `size.buffer.colortex6=1 1`；`global/water/medium_state.glsl:5` 的头注写明 RG=水面高度编码、B=天空可达、A=有效性）；新增专用缓冲要配一个 pass，而它得和尺寸不同的 colortex1 同画布 MRT，附件尺寸不齐不安全；显式 `R11F_G11F_B10F` 一类格式没有 alpha。**失败开放**：全包 13 处 `colortex1` 引用逐条读过，唯一的 `colortex1Format` 命中是本轮写下的那条注释本身（`scattering.fsh:14`），没有任何声明，所以走 Iris 默认格式；若该格式无 alpha，读回值是 1.0，最坏结果是这条乘子静默无效，不会画出一场缺光束的画面。alpha 在别处确实无人消费：`final.fsh` 的 3×3 只用 `.r`；`program/water_composite.fsh:19` 的 `water_shafts_resolve(colortex1, texcoord, rayLength)` 只用 `.rgb`，rayLength 由参数传入并从 `depthtex0` 重推（`global/water/light_shafts.glsl:148-153`）；水下写入分支在 `scattering.fsh:75-84` 提前 `return`，既不读也不写这一格。
5. **消费点与滑块语义。** 乘子加在 `final.fsh` 的 3×3 平滑累加之后、`/ 9.0` 与 `godraysExposure * (GODRAYS_STRENGTH * 0.01)` 之前，位置仍在 `isEyeInWater == 0 && godraysExposure > 0.0` 与 `#ifndef DIMENSION_NETHER` / `#ifndef DIMENSION_END` 的嵌套内。`GODRAYS_STRENGTH` 与 `godraysExposure` 的归属没动：滑块与视角/日面曝光仍旧只在 stage 2 生效，改滑块不会重跑 stage 1。
6. **默认与出厂画面。** 选项 `GODRAYS_SUN_OCCLUSION` 出厂关，三档 profile 一律写 `!GODRAYS_SUN_OCCLUSION`（只有 ULTRA 单独开着 `GODRAYS`），因此本轮对任何出厂配置零像素影响。这条由 `qa/iris-properties-resolved.txt` 的快照重跑逐项对上（该文件 +4/−4，正好是 `screen.POST` 的一行与三档 profile 各一处）。
7. **本轮抓到的真实缺陷是自写代码，而且只有强制开选项的扫描能抓到它。** 首版写的是 `if (gl_FragCoord.xy < vec2(1.0))`，GLSL ES 的关系运算符是纯标量的，向量比较直接非法：`2(108) : error C1020: invalid operands to "<"`（驱动 `4.6.0 NVIDIA 572.83`）。改成 `all(lessThan(gl_FragCoord.xy, vec2(1.0)))` 后编译通过。**要点**：三档默认扫描给的是 `linked=267 failed=0`，它对这段代码什么也没说——选项关着时它整个被预处理器排除，语法错误根本不存在于送进驱动的那份源码里。所以新增布尔选项的编译证据必须包含一次"把它开着"的扫描（`--set 'GODRAYS=' --set 'GODRAYS_SUN_OCCLUSION='`），本条据此追加一批。
8. **参照包引证降级为"未本地重验"。** §2.11 与 §6 P1-6 依据条里 LIGHT 1.8.0 的三处 `file:line`（`composite.fsh:423-433` / `:582` / `final.fsh:329`）抄自本报告，本轮未在本地复核——`_analysis/study-2026-09-20/` 现在只剩 `ComplementaryUnbound_r5.9.3`，原包目录已清理。两处均已就地标注，`Astra/THIRD-PARTY.md` 的登记行也改成"结论只依赖'有这种架构'，不依赖具体行号与 13×13 这个尺寸"。落地的窗口（7×7 抽、±12 像素）是本条自定的标定量。许可证分类不变，仍是**仅思路（IDEA ONLY）**，依据 Chocapic13' Sharing Agreement（只读思路，不得照搬表达式）。
9. **原验证条不可用。** §6 P1-6 的"验证"写的是用 `qa/tools/water_path_probe.py` 比对日面窗口——该工具的模式集里根本没有日面窗口场景（它覆盖水下光路与空气侧雾/吸收），照它执行得不到任何判定。已在该条就地标注。离线侧因此只能给出编译与结构证据；观感四条（遮住日面的柱子是否淡出全场、玻璃/水面是否**不**淡出、淡出是平滑还是跳变、关闭时是否与改前逐像素相同）全部进 `qa/regression-checklist.md` 行 17a，按用户裁定「实现但默认关，标注待实机」处理。

收尾门：`python qa/tools/check_pack.py` → 16 项 0 FAIL / 15 PASS / 1 WARN，exit 0（唯一 WARN 是 #4 include 图接线登记，与本条无关）。编译三批：默认三档 `python qa/tools/compile_glsl.py` → `linked=267 failed=0 compute=27`，日志 `qa/glsl-2026-09-20-t9-compile.log`；强制开 `python qa/tools/compile_glsl.py --profiles ULTRA --set GODRAYS= --set GODRAYS_SUN_OCCLUSION=` → `linked=89 failed=0 compute=9`，日志 `qa/glsl-2026-09-20-t9-on.log`（收尾时同一命令行复跑一次，`RESULT` 逐字段与留档日志一致）；全选项面 `python qa/tools/compile_glsl.py --matrix --jobs 4` → `RESULT_ALL	batches=11	rows=85	entries_per_row=89	linked=7565	failed=0`，exit 0，日志 `qa/glsl-2026-09-20-t9-matrix.log`。其余门：`python qa/tools/test_gate_sensitivity.py` → 14/14 按预期；`python qa/tools/provenance_steadfast.py --quiet` → `verbatim=14 literal-suffix=2 rewritten=6 astra-only=24 total=46`，计数不变；`python qa/tools/inspect_iris_properties.py` 退出 0；`python qa/tools/option_matrix.py` → 68 个取值表选项 / 38 个进分支的因子 / 89 个因子取值 / 703 个二组合 / 无种子覆盖阵列 84 行 0 uncovered。

**新选项确实进了穷举面**（不只是那一档手工强制）：`option_space()` 里 `GODRAYS` 与 `GODRAYS_SUN_OCCLUSION` 都是二值因子（`levels=[false,true]`、`default=true`、`to_override(true) -> ''` 即裸 `#define`）。矩阵的 85 行注记里 67 行显式把 `GODRAYS_SUN_OCCLUSION` 打到 `false`，18 行留在默认 on 档，其中 `GODRAYS` 与它同时为 on 的恰好 5 行——`M001`、`M005`、`M008`、`M014`、`M025`，`M001` 的注记就是 `(all defaults)`。也就是说新代码在穷举面里被 5 × 89 = 445 次编译覆盖到，而不是只靠那一档手工强制。选项面增量也与本条自洽：取值表选项 67→68、分支因子 37→38、因子取值 87→89、因子对 666→703（= C(38,2) − C(37,2) = 37），穷举门报 0 uncovered。

**行数两个口径，别当成互相矛盾**：84 是 `option_matrix.py` 的**无种子**贪心估算，85 是 `compile_glsl.py --matrix` 以三档 profile 为**种子**的实际行数，两个算法本就不等价（T2 建门那轮恰好都是 83 行，是巧合）。台账与 `qa/regression-checklist.md` 第 1 行一律以实测编译门 85 为准，并把"行数随选项面变化"写进句子本身，不再抄死一个数字。

---

**F-10 · T10 执行 P1-7 焦散/消光烘焙：五条前提逐点实测，本条不落地**

工单 #23 的产出是**零行为改动**。改动面 = 三个 GLSL 文件的注释（`git diff --numstat`：`global/lighting/shadowmap.glsl` +3/−0、`global/water/reference_light.glsl` +7/−0、`program/water.glsl` +4/−2）+ `docs/handoffs/nether.md` 一处就地更正 + 本报告与两份 qa 台账。**每一行改动都在 `//` 之后**，GLSL 语义、选项面、缓冲声明、清屏色全部未动，这一点由三档编译门复跑 `linked=267 failed=0 compute=27` 与 T9 留档逐字段相同来正面证明，而不是靠"我只改了注释"的自述。

1. **要烘的东西已经在包里，而且就是同一条数据通路。** `program/shadow.fsh:57-73`（`#ifdef WATER_CAUSTICS`）对水面 caster 求 `solas_water_caustics(waterCasterWorld)`（`:59`）并混进 `shadowTint`——`:64` 让水自身的染色只在焦散峰值触到、`:71` 乘 `(0.30 + focus * 1.5) * (1.0 - a32)` 保住海床底色——`:74 shadowData = vec4(waterHeight, shadowTint)` 一次写出。消费侧就是本条设想的像素端读法：`global/water/light_shafts.glsl:125 texture(shadowcolor0, pos.xy).gba`。`:55-56` 的注释自陈出处是 Solas（"Solas writes the water focusing pattern into the light map itself"），与 §6 依据条列的 Solas `programs/shadow.glsl:58-77` 同源。**"shadow 阶段烘焦散、像素端读烘好的值"不是待办，是现状。**
2. **`shadowcolor0` 没有"未用分量"可烘。** 通道占用写在 `global/lighting/shadowmap.glsl:49` 的头注里（`R: water height, GBA: transparent-caster tint`），与写出点一致；R 承载 127 格窗口上的半格量化高度，256 个 R8 码值全部用满。现行消费者逐条数过：`shadowmap.glsl:51-52`（整纹夹边 fetch）、`:113`、`:147`（PCF tap 读 caster）、`light_shafts.glsl:125`（`.gba`）、`program/water_state.fsh:42-46`（`.r` → `decode_water_height`，一帧一像素的水面高度兜底恢复）。再塞任何量都要挤掉高度或染色，两者都有活消费者，因此"烘进未用分量"这条做法在 Astra 的当前通道预算下无落点。
3. **像素端消光是解析闭式，没有可搬的成本。** `global/water/absorption.glsl:42-44`（`water_extinction`）、`:45-47`（`water_transmission`）、`:48-54`（`water_transport`，含 `σs/σt·(1-T)` 单次散射源项）、`:72-79`（`water_surface_medium`）全是 `exp(-d·σ)`，光程 `d` 由几何求交给出，不是逐格 march。§6 本条"把只与光路上有什么方块有关的量搬去 shadow 端"的隐含前提（像素端在逐格累加）在本包不成立；改成查图是把几条 `exp` 换成一次纹理采样外加一次烘图，属于**换成本而非省成本**。
4. **"12 条 shadowcomp 声明 ⇒ 落地阻力小"两个数都不对。** 实测 `shaders.properties:330-338` 是 **9 条**（`program.world-1/shadowcomp` 与 A–H），不是 12 条；且**每条后缀都是 `=NETHER_VOXEL_LIGHT`**，即 9 条全部是熔岩侧体素光的开关，与过场水面消光无关。声明条数也不承载"能烘什么"——本条缺的是通道，不是调度位。
5. **唯一还活着的、符合"焦散在像素端逐片元算"描述的站点，是刻意留下的修复，本轮无权改判。** `global/water/caustics.glsl:76 astra_water_caustics_focus()`（3×3 × 4 步视差 ≈ 每片元 36 次高度采样）全包只有一处调用：`program/lit.fsh:332`。其 `:313-321` 注释登记了来历——用户实报"海床看不到焦散"，而 `shadowcolor0` 里的烘焙值是否正确**离线不可核实**。把这条像素端 focus 换成"只信烘焙"，等于在一个实报缺陷尚未复核之前，收掉唯一已知的修复手段；这属于必须看画面才能定的量，本轮不落地。
6. **§6 本条给的两件验证工具照原文执行得不到判定。** `qa/tools/cost_census.py:2` 的 docstring 自陈 "Loop source inventory, not an execution-cost or GPU-safety estimator"，`:5` 更写明 "Never label lexical fetch sites as fetches/pixel"——用它"对比像素端抽样量"正是该工具自己禁止的用法。`validate_shadow_water.py` 当前为红：`Shadow plane mismatch`（`pixels=27556`，`max depth error=0.1107716904917071`，exit 1），红因是它内嵌 Java 模型的方形 warp 假设已过时，属与本轮无关的遗留项（在线下清单）。因此本条结论完全来自对包内源码的直接测量。

**测量时另捡到三处真实腐化，均已就地登记，没有顺手删。** ① `shadow_water_depth()`（`shadowmap.glsl:228`）**全包零调用者**：按字节级扫描（`errors='replace'`，同时打印不可读文件清单，本轮为空）只命中 1 处，即其定义本身。② `global/water/reference_light.glsl` 整个文件（158 行、19 个 `waterRef_*` 标识符）**全部不可达**——不是只有 `water_reference_lighting` 一个叶子。判据是对 19 个标识符逐个全包扫描：除 `waterRef_SkyColor` 外全部 0 命中，而唯一那 1 处命中是 `program/water.glsl:243` 的一条**注释**，不是调用；该注释断言"宽瓣来自 `waterRef_SkyColor`"，而同一 pass 的宽反射实际来自其上方的 `astra_reflection_sky`（定义在 `program/scene.glsl:53`，全包 5 处调用：`scene.glsl:184`、`program/deferred.fsh:15`、`program/lit.fsh:304`、`program/water.glsl:214` 与 `:239`）。所以那条注释已在本轮改写成正确的归因，用户实报的"太阳在水面上的反射有点弱"原话保留。`program/scene.glsl:22` 的 include 因此是把一份死代码编进每一档的每个 pass。**为什么不直接删**：删除要同时撤 `Astra/THIRD-PARTY.md:190` 对该文件的 Steadfast 登记、并复核 `docs/handoffs/nether.md` H-002 的论证落点，那是一次跨文件决策，不属于一轮烘焙调查的顺手清理；本轮只把状态写进文件头注。③ `docs/handoffs/nether.md` 的 H-002 至今把 `if (isEyeInWater == 0 && shadow_water_depth(...))` 当现行源码引用，而那个调用点早已被删——已在该文件加「2026-09-21 复核」块就地登记（原行号不重写；顺带复核出 `astra_light()` 现在 `program/scene.glsl:218-250`、熔岩早返回在 `:225`，H-001 的结论仍成立，而 H-002 因为调用点根本不存在，结论比撰写时更强）。

**本轮抓到的第二个自写缺陷，性质和 T9 那个不同：是一句过强的注释。** `reference_light.glsl` 头注的第一版写着"其余五个 helper 仍经 `waterRef_SkyColor` 被 `program/water.glsl` 活着调用"——两头都假：全包扫描显示 `waterRef_SkyColor` 零调用、`program/water.glsl` 对它的唯一提及是一条注释。那句话写在任何跨文件标识符扫描之前，是本报告要求"核实"却差点在自己新写的注释上漏掉的一格。已改成本文 ② 的实测表述。**要点**：给"某函数已死/仍活"下结论时，扫描单位必须是该文件的**全部导出标识符**而不是函数名列表，且命中要区分"调用"与"注释提及"——只按函数名扫会漏掉常量，按词面扫会把注释当成存活证据。

收尾门：`python qa/tools/check_pack.py` → 16 项 0 FAIL / 15 PASS / 1 WARN，exit 0（唯一 WARN 仍是 #4 include 图接线登记，与本条无关）；`python qa/tools/compile_glsl.py` → `linked=267 failed=0 compute=27`，日志 `qa/glsl-2026-09-21-t10-compile.log`；本轮改了 `program/water.glsl`（哪怕只是注释），因此复跑 `python qa/tools/water_path_probe.py` → exit 0，19 条 `assert`（含 `:282` 的侧面深度上界与 `:289` 的反向守卫）全部通过，即那 4 行注释未改水路径行为；`python qa/tools/provenance_steadfast.py --quiet` → `verbatim=14 literal-suffix=2 rewritten=6 astra-only=24 total=46`，计数不变（本轮未新增也未删除任何表达式级移植）。**本轮没有新增选项**，因此不触发 T9 立下的"新布尔选项须额外一次强制开扫描"门；穷举面也未变（`check_pack.py` #13 仍报 68 个选项 / 38 个分支因子 / 无种子矩阵 84 行）。§11.B 的 P1-7 行已改判为「前提已不成立 · 未执行」，并顺手记下一处行号漂移：清屏色前提的现值在 `lib/settings.glsl:369`，不是原文引的 `:363`。

**F-11 · T11 执行 P1-8 硬件 PCF 默认档：等价性测量把默认档定死，本条零行为改动**

工单 #24 的产出是**零 shader 代码改动**（与 T8 同为纯登记单，`git show --stat` 只含本文件、`qa/session-log.md` 与一份新编译日志），因为本条"用等价性测量决定默认值"这句话是可执行的，实跑之后默认档没有悬念。逐点记录：

1. **默认软件是三档出厂配置，不是待决的裸常量。** `SHADOW_FILTER_MODE` 在 `lib/settings.glsl:60` 是 GUI 选项 `#define SHADOW_FILTER_MODE 0 // [0 1]`，`lang/en_US.lang:15-18` 给了两档文案（value.0 "Software Bilinear (Default)" / value.1 "Hardware PCF"），三档 profile `shaders.properties:149-151` **全部显式写 `SHADOW_FILTER_MODE=0`**。报告原文引的 `settings.glsl:57` 与 `:329-336`（`shadowHardwareFiltering*`）均已漂移，现值分别在 `:60` 与 `:335-342`。
2. **等价性测量实跑，答案是"可见性打平"。** `python qa/tools/shadow_filter_equiv.py` → exit 0，`Overall max_abs=9.437e-16; FAIL=0`（容差 mean=0.03 / max_abs=1e-12 / std_slack=1e-12），覆盖 hard_edge/slope/noise × softness∈{1,2,4,8,16} × 2223 采样点。它建模的是**理想比较采样**：把软件 16 抽与硬件 4 抽放在同一组 lobe 位置上比可见性分布，结果逐点相同。所以"软件当默认"**不是**因为它把阴影算得更软——两档一样软。
3. **真正分出高下的只有彩色阴影，且工具明说它测不到。** 软件路径逐角离散取透明 caster 的染色（`shadowmap.glsl:138-156`，含水/玻璃混合边的每角保留），硬件路径整窗只做**一个中心材质近似**（`diffuse.glsl:264-277`，注释 "Optional approximation: one discrete material sample for the footprint"）。工具头注 `:128` 自陈其范围："Scope: visibility only. Hardware centre-tint approximation is not per-texel colour equivalence."——即本条决策依赖的那一维恰在工具射程之外。好在 `lang/en_US.lang:16` 早已把这层差异写进用户可见文案（"Software retains per-texel tint. Hardware PCF ... approximates transparent material boundaries with one central tint. Software is the default."），代码、文案、实测三者对齐。结论：**出厂默认保持软件，不改。**
4. **"三参 shadow-gather 省指令"不采纳，理由有两层。** 一是形态错配：Astra 硬件路径是 4 个 *spread lobe*（`shadow_filter_uv:179-183`，各在 ±softness/2 偏移上做**一次** `texture(sampler2DShadow, vec3)`），而 VanillaPlus 式 `textureGather(sampler2DShadow, uv.xy, uv.z).wzxy` 拿的是**单个 lobe 的 2×2 四角**——这正是 Astra 软件路径 `shadow_gather_visibility:124-127` 已在用的结构（差别只在 gather 的对象：软件 gather `sampler2D` 原始深度再手工 `step`，提议里的是 gather `sampler2DShadow` 让硬件做比较，两个不同重载）。要用 gather 换掉 spread-lobe 循环，就得把 4-lobe 软阴影足迹压成 1-gather，那是**改变硬件档观感的降级**，不是等价重写。二是收益不可离线证：`cost_census.py` 头注自陈它不是成本估算器、`qa/benchmarks.md` 为空，"省指令"两侧都测不出来——证据链在同一个地方断掉，与 T10 的成本条、T8 的运动信号条同构。
5. **顺带把 opt-in 硬件分支的编译健康度坐实（本轮唯一新增技术动作）。** 硬件分支不被任何出厂档选中，属 T9 立规那类"默认关分支，三档默认扫描看不见"的形态。`python qa/tools/compile_glsl.py --set SHADOW_FILTER_MODE=1` 强制三档走 mode 1 → `RESULT linked=267 failed=0 compute=27`，exit 0，日志 `qa/glsl-2026-09-21-t11-hardware.log`（NVIDIA RTX 4050 / 驱动 572.83）。为排除"`failed=0` 其实覆盖没生效、编的还是软件分支"这一假绿（软件/硬件对 `shadowtex0/1` 声明的是**不同采样器类型**，绿跑本身分辨不出），另用工具自己的 `apply_profile_settings` 逐档复核展开：三档在 override 下均得到 `#define SHADOW_FILTER_MODE 1`，出厂 BALANCED 无 override 时得 `0`。历史侧亦一致：旧专门日志 `glsl-shadow-pcf-hardware.log` = `linked=264 failed=0`，`--matrix` 全选项面（`glsl-2026-09-20-t9-matrix.log`）里含硬件模式的行 16 处——即该分支早被穷举门覆盖且绿。

收尾门：本条无出厂行为改动，按 11.F-2 成本规则只需与改动面匹配的门。`python qa/tools/shadow_filter_equiv.py` → exit 0 / `FAIL=0`（本条主证据）；`python qa/tools/compile_glsl.py --set SHADOW_FILTER_MODE=1` → `linked=267 failed=0 compute=27`（opt-in 分支健康度）；默认三档 `compile_glsl.py` 与 `check_pack.py`（16 项 0 FAIL）因本轮未碰出厂选项面/未碰任何被出厂档选中的代码而未重跑——改动面只有本文件与 `qa/session-log.md`。§11.B 的 P1-8 行改判为「已执行，默认档经实测确认不改」，11.D 更正清单第 9 条同步精确化 gather 的两/三参与 `sampler2D` vs `sampler2DShadow` 之分。

**F-12 · T12 执行 P2-14 + P2-19（合并条）：分辨率粒度已在 T1 落地为档位差分，连续旋钮评估后暂缓，本条零行为改动**

工单 #25 按 §11.B 的「建议与 P2-14 合并」把两条并成一单，产出同样是**零 shader/零配置改动**（`git show --stat` 只含本文件与 `qa/session-log.md`）。§11.B 给 P2-14 的裁决原话是「建议在 P0-1 定调后再评估」——那个前置（T1 / P0-1）已落地，所以本单就是那次再评估；结论是 P2-19 的诉求已被 T1 顺带满足、P2-14 的连续旋钮暂缓。逐点记录：

1. **P2-19「光束 march 分辨率硬编码、没有用户选项」的前提经 T1 已不成立。** `shaders.properties:20-24` 用 `#if UNDERWATER_SHAFT_SAMPLES < 7` 把 `size.buffer.colortex1`（光束缓冲）绑成两档：PERFORMANCE 档 `UNDERWATER_SHAFT_SAMPLES=4` 走 0.25 分支，BALANCED=7 / ULTRA=10 走 0.5 分支（`shaders.properties:149-151` 三档实测值 4/7/10；分支选择由出厂文本决定，与 T1 依赖的 Iris properties 预处理器机制一致，默认 BALANCED 的展开见 `qa/iris-properties-resolved.txt:22` = `size.buffer.colortex1=0.5`）。而 `UNDERWATER_SHAFT_SAMPLES` 本身在 `sliders=`（`shaders.properties:156`）里是用户可拖的滑杆——把它从 7 拖到 ≤6 就把光束缓冲降到 0.25。**即光束缓冲分辨率已是「随用户滑杆两档 + 随档位差分」，正是 P2-19 想要的"低配再多一档退路"，无需另立选项。**
2. **P2-19 把 colortex7 归因错了。** 工单称"colortex7 分辨率 0.25 是硬编码"并把它算进"光束 march / 反射缓冲"要加档的对象。实测 colortex7 是**水下泛光缓冲**（`shaders.properties:32-34` 注释：quarter resolution 的低频模糊量、空中该 pass 直接 discard、全分辨率默认"让每帧为一条空中就丢掉的 pass 付 1080p RGBA16 写"），它的 0.25 是**省显存的性能选择**而非待暴露的质量旋钮——把它做成用户质量档反而在鼓励把一张"本该 0.25"的缓冲开大。§11.B 该行引的 `shaders.properties:14,19` 亦已漂移（真实 `size.buffer.*` 指令在 :21/23/29/31/35/36/38，共 7 条指令 / 6 张不同缓冲）。
3. **"给反射缓冲加 LOW/HIGH" 无对象可挂。** Astra 的反射是屏幕空间（`screen.WATER` 含 `SCREENSPACE_REFLECTIONS`），`size.buffer.*` 六张缓冲里没有一张"反射渲染分辨率缓冲"可加档；反射路径的质量轴是噪声八度（P2-15），不是分辨率。本条与 P2-15 是同一处（`refraction.glsl`/`raytrace.glsl`）的两个不同 lever，不能在此重复计账。
4. **P2-14 连续顶点级百分比旋钮：评估后暂缓，不投机实现。** 提案本体要给光束/水下光柱/云各加一套低分中间缓冲 + 一次上采样。光束那一维 colortex1 的消费者已按 `textureSize()` 推 tap 偏移（`program/final.fsh:54`、`global/water/light_shafts.glsl:140`），缩放**免费**——但正因如此它已被第 1 点的双档覆盖，再加连续旋钮是重复。云目前全分辨率、无低分缓冲，加连续旋钮=新建整套低分缓冲与上采样 pass。收益不可离线证：与 T8/T10/T11 同一断点（`cost_census.py` 头注自陈不是成本估计器、`qa/benchmarks.md` 空），连续旋钮唯一价值轴是"亚档位性能/画质取舍"，只能实机 A/B。许可无干净先例：Bloop CC-BY-NC-SA、Noble GPL → 两条都"必须重写"。**关键：一个没有任何出厂档启用、质量收益无人测过的连续分辨率滑杆，正是 §7.B.6 明令禁止的"暴露但零消费者的选项"化石**——"实现但默认关"的一般规则在这里被更具体的既有裁决覆盖，故本单选择不落地。重开条件：出现真实水下/云帧时间基线，且某具体阶段（云最可能）被用户实报"亚档位粒度不够"，届时以 P2-13 的可署名 MIT 低分缓冲实现为先例。
5. **本轮唯一技术动作 = 把上述前提全部读回出厂源。** 重读 `shaders.properties` 缓冲段（:7-38）与三档 profile（:149-151）、`lib/settings.glsl` 的 `UNDERWATER_SHAFT_SAMPLES 7 // [4 5 6 7 8 9 10]`（:139）与既有 `SHADOW_RESOLUTION 2048 // [512…4096]`（:65，证明"步进式分辨率选项"在本包早有先例、但那是 shadow map 而非渲染 pass 粒度），并比对 `qa/iris-properties-resolved.txt` 默认展开。

收尾门：本条连配置都未改（只是核实现有配置已覆盖 P2-19），改动面只在本文件与 `qa/session-log.md`，无 shader/properties 触碰，编译门与 `check_pack.py` 不适用。§11.B 的 P2-14、P2-19 两行改判为「已执行 · 前提经 T1 满足 / 连续旋钮暂缓」，11.D 更正清单新增第 16 条记录 colortex7 的归因错与 `:14,19` 引证漂移。

**F-13 · T13 执行 P2-20 光束标定三条：三条全部实装，收在单一默认关开关后，出厂观感逐字节不变**

工单 #26 的行为改动集中在一个文件：`global/water/light_shafts.glsl` 三处 `#ifdef UNDERWATER_SHAFT_CALIBRATION` 包裹（+28 行）。接线另四处均为配置/文档：`lib/settings.glsl` +4（新布尔选项及其注释）、`shaders.properties` 三档各插 `!UNDERWATER_SHAFT_CALIBRATION` 并把选项名加进 `screen.WATER`（`sliders=` 不动）、`lang/en_US.lang` 与 `zh_CN.lang` 各 +2（标题 + 说明，说明里明写"所有档位默认关闭、绝对权重待实机调"）、本文件与 `Astra/THIRD-PARTY.md`。形态沿用 T9 的 `GODRAYS_SUN_OCCLUSION`：三档 profile 一律 `!` 关闭，因此对任何出厂配置零像素影响，符合用户裁定「实现但默认关，标注待实机」。逐点记录：

1. **参照包三条全部本地重验成立**（V3.7b `lib/atmosphere/volumetrics.glsl` 的 `:56` 强度式、`:192-194` 指数步进、`:130-131` 天空色混合，见 §6 本条「依据」就地补记）。许可证纪律：Solas ARR → 只读思路，三段表达式全部自写；未读 `drm/` 目录，未引入 `SOLAS_BY_SEPTONIOUS` 宏。
2. **站点① 强度门**（`light_shafts.glsl:60-75`）：标定臂 `visibility *= (1.0 + 2.0*VoL*VoL) * (0.25 + 1.75*sun) * 0.075;` 替换出厂 `mix(0.25 + 0.25*VoL, 0.45*VoL, time)`。**0.075 = 0.45/6 是必要的偏离**——参照包原式峰值 6.0（`VoL=1, sun=1`），Astra 出厂正午峰值 0.45，直接替换会亮约 13 倍；归一化后开关只改衰减形状不改总亮度。两臂在 `sun=1` 下的对照（由两条表达式直接算出的算术值，非实测）：`VoL=0` → 出厂 0.0000 / 标定 0.1500；`0.25` → 0.1125 / 0.1687；`0.5` → 0.2250 / **0.2250（精确交点）**；`0.75` → 0.3375 / 0.3188；`1.0` → 0.4500 / 0.4500。即标定臂加宽离轴光束、在 0.5 处与出厂相交、远轴更亮、正对太阳处持平。第二处已知偏离：标定臂复用 Astra 既有的 `VoL = pow(clamp(dot(...),0,1), 1.5)`，所以瓣形是 `t³` 而参照包是 `t²`。
3. **站点② 采样分布**（`:93-104`）：标定臂 `currentDist = maxDist * (exp2(u) - 1.0)` 替换出厂均匀步进 `(float(i) + dither) * minDist`。参照包是 `currentDist = exp2(dither)` 起步、循环内 `*= 2.0`、**不设上界**、靠 `:195/:200` 两个 break 收尾；Astra 取有界形式，保留"近场加密"这一实质、去掉无上界步进（无上界在 Astra 的 `minDist` 语义下会让末样本越过 `maxDist`）。分布形状是起点值，待实机 A/B。
4. **站点③ 光束染色**（`:145-154`）：标定臂 `col = mix(col, normalize(skyColor + 0.00001), time * 0.75);`。**不照搬参照包的 `·0.1`**——那一项在 Solas 里是加性光源缩放系数，Astra 的 `col` 是随后参与 `col*col` 的染色乘子，照搬等于顺手把光束调暗且离线无从判断调暗是否正确。`skyColor` 与 `time`（= `astraSolasTimeBrightness`）都复用包内既有量，未新增 uniform。
5. **本轮真正的技术产出来自查证而非实现**：§6 本条「验证」原写"用 `light_shafts` 现有探针对拍三场景"，实测该前提不存在（11.D-17 ①）；继续核查门控时抓到 `refract()` 入参方向反号这一真实缺陷，机理、驱动实测、git 来历与一行修法全部记在 11.E-8。**为什么不在 T13 里顺手修**：那道门是出厂行为，改它必然改变出厂像素，与"实现但默认关"的裁定正面冲突；且标定臂①的下限恰好会把它盖住——先修它、再评估标定臂才是正确顺序。故本单不折叠，留作独立工单。
6. **两条诚实边界**：① 三条曲线的观感收益本轮零证据（无探针覆盖光束门，见 11.D-17 ①；第 2 点的数字是表达式算术，不是画面测量）；② 光束方向轴在**两条臂上都不可判**，因为 11.E-8 让 `VoL` 的输入方向本身就是错的——这两条已写进 `qa/regression-checklist.md` 新增的 10b 行，实机判读时不得把方向性观感当作标定臂的验收。

收尾门（本轮全部实跑）：`python qa/tools/check_pack.py` → 16 项 0 FAIL / 15 PASS / 1 WARN（唯一 WARN 仍是 #4 include 图接线登记），exit 0，日志 `qa/checkpack-2026-09-21-t13.log`；选项面从 68 → **69**，#2 报三档 profile 各 69 tokens 且 `complete=True`（证明新选项在每一档都有显式声明），#3 报 `zh_CN`/`en_US` 各 69 titles + 69 comments（证明两份文案都接线），#13 报 69 options / 39 个可翻转预处理分支 / 成对矩阵 86 行，#8 报 49 条登记行。`python qa/tools/compile_glsl.py` 三档默认 → `linked=267 failed=0 compute=27 compute_capable=true`（`qa/glsl-2026-09-21-t13-default.log`）；按 T9 立的常设门跑**强制开扫描** `python qa/tools/compile_glsl.py --set UNDERWATER_SHAFT_CALIBRATION=`（未加 `--profiles`，故三档全开）→ 同为 `linked=267 failed=0 compute=27`（`qa/glsl-2026-09-21-t13-calibon.log`）。因 Expander 不求值 `#ifdef`，绿跑本身不证明分支被选中，另用工具自身 `Expander` 对 `program/scattering.fsh`（全包唯一同时 include `light_shafts.glsl`（`:35`）并调用 `water_shafts_march`（`:79`）的入口）做展开交叉核：三档出厂均得 `// profile disables UNDERWATER_SHAFT_CALIBRATION`、加 `--set` 后均得 `#define UNDERWATER_SHAFT_CALIBRATION`。穷举面 `python qa/tools/compile_glsl.py --matrix --jobs 4` → **`RESULT_ALL batches=11 rows=86 entries_per_row=89 linked=7654 failed=0`**，exit 0（`qa/glsl-2026-09-21-t13-matrix.log`；上一轮为 rows=85 / linked=7565，行数随选项面重算，未写死进任何清单）。`python qa/tools/option_matrix.py` → 69 个取值表选项 / 39 个分支因子 / 91 个因子水平 / 741 个因子对 / 无种子覆盖阵列 86 行 0 uncovered，与 `--matrix` 的 86 行独立一致【2026-09-21 T14 复核更正：这两个 86 是巧合，不是交叉验证——两个数来自不同算法（种子差异，`compile_glsl` 多塞 4 行种子），T14 同一选项面实测 87 / 96 / 92，见 11.E-10】；其"constant #defines nothing reads"清单不含新选项名，即标定代码确有消费者（§7.B.6 的反面）。受保护代码在穷举面里真正编译的规模另测：86 行中 12 行取 `CALIBRATION=true`，其中仅 4 行同时 `UNDERWATER_LIGHT_SHAFTS=true` ⇒ 光束门控代码实际参与 4×89 = 356 次编译。其余：`test_gate_sensitivity.py` 14/14；`provenance_steadfast.py --quiet` 计数不变（`verbatim=14 literal-suffix=2 rewritten=6 astra-only=24 total=46`，本条是"只读思路"，不构成表达式级移植）；`water_path_probe.py` 因本轮改了水路径文件而复跑 → exit 0。

**F-14 · T14 执行 P0-2 云阴影（2D 廉价形态）：单文件 +27 行、出厂像素不变，并新立"反向编译验证"取代 T11/T13 的弱证**

工单 #27。行为改动只有一个文件：`program/scene.glsl` **27 增 0 删**（`git diff --stat` 实测，零删除即出厂 `#else` 臂逐字节未动）。接线五处：`lib/settings.glsl` +3（`//#define CLOUD_SHADOWS // [false true]` 及两行说明）、`shaders.properties` 4 行改写（`screen.SKY` 加选项名 + 三档 profile 各插 `!CLOUD_SHADOWS`）、`lang/{zh_CN,en_US}.lang` 各 +2、`Astra/THIRD-PARTY.md` +1（新增一条 `shaders/program/scene.glsl` 的 IDEA-ONLY 登记行 ⇒ #8 的登记行数 49 → **50**）、`global/atmosphere/clouds_planar.glsl` +5−1（就地更正：把"云阴影"从该文件的 NOT PORTED 清单里摘掉，并注明消费者是 `program/scene.glsl`、`gaux4` 一个字节都没读）。形态沿用 T9/T13 的裁定「实现但默认关，标注待实机」：三档一律 `!` ⇒ 对任何出厂配置零像素影响。

1. **真实缺口不是"没有云阴影函数"**：`astra_cloud_transmission`（`global/atmosphere/weather.glsl:122-136`）早已存在且已在被调用，缺的是**不对称**——出厂臂只在 `astraRainFactor > 0.01` 时投影，即"晴天不投、雨天才投"。T14 把这条臂换成"晴天也投、雨天由密度阈值继续加重"，复用同一个函数，未新增 uniform。调研原文「做法」写的是新建沿 `sunVec` 的 1–2 次采样、乘到 `shadowmap` 结果上、洞穴按 `eyeBrightnessSmooth.y` 早退——按字面执行会写出第二个投影函数并把云影错叠到影图上（那三处偏离记在 §6 本条「裁决」）。
2. **权重刻意不含 `astraRainFactor`**：`weather.glsl:132` 已把雨量折进云密度阈值本身，再乘一次就是双计风暴。改用包内既有的 `static_shadow(skylight)` 作"全露天"判据（与 `global/lighting/diffuse.glsl:253` 的影图回落同一标准），屋顶与洞穴内因此永不接云影；`0.75` 是权重上界。
3. **掠射淡出是必需项而非装饰**：`smoothstep(0.0, 0.2, cloudLightDir.y)`。单平面追踪在地平线附近会把交点甩到几百格外、不再是本片元的遮蔽物；同一项还顺手盖住 `weather.glsl:127` 的 `lightDir.y <= 0.01 → return 0.0` 早退——没有它，夜间月光下的地面会被切到 0.25 亮度。
4. **本轮的方法产出：反向编译验证。**Expander（`qa/tools/compile_glsl.py:234-277`）只求 `#include` 与改写 `settings.glsl`，**从不求值 `#ifdef`**，所以"展开文本里有/没有某行"永远证明不了分支被选中——T11 与 T13 的 `apply_profile_settings` 交叉核证的都只是"发出了哪一行定义"，不是"哪条臂进了编译器"。本单改为把缺陷注入受保护臂再看真驱动怎么回答：向新臂插入一条对未声明标识符的读取，用同一份文件跑两侧，`--match gbuffers_terrain`。出厂侧 `RESULT linked=9 failed=0 compute=0`、rc=0 ⇒ 该臂根本没进编译器；强制开侧 `RESULT linked=6 failed=3 compute=0`、rc=1，三条 `COMPILE_FAIL {PERFORMANCE,BALANCED,ULTRA}:gbuffers_terrain.fsh fragment` 全部报 `5(263) : error C1503: undefined variable "astraT14ReverseProbeMustFail"`。一次测量同时证明"出厂排除"与"开启即生效"，两侧日志都在 `qa/glsl-2026-09-21-t14-reverse.log`。**覆盖边界如实写**：`scene.glsl` 被 47 个片元入口 include（Expander 实测计数），反向验证只做了 terrain 那 3 个入口 × 3 档 = 9 个编译单元；同一预处理器、同一文件，故"出厂排除"由构造推广到其余入口，但实测证据只到这 9 个单元。探针由哈希守护的脚本插入/还原：注入前断言 `sha256(scene.glsl) = 9e09355e387ad495fdefad13a19eeadc95b46855b0def88e4d0fde51aa55c6d6`，还原后复算同一哈希并检查残留标记（`restored sha256 match: True`、`probe markers left: False`），脚本本身不入库。
5. **两项抓到、两项刻意不折叠**：① 遮蔽臂与可见云层不在同一密度刻度上（起点少减 `-0.04`、窗宽 0.05 vs 0.22），算术对照与补偿方向全记 11.E-9——它活在出厂路径上，改它必然动出厂像素，与 T13 的 11.E-8 同类，故另立候选工单；② PERFORMANCE 档 `CLOUD_MODE=0`（非平面云）⇒ `astra_cloud_transmission` 恒返回 1.0，该档开了本选项**不会有任何变化**，这一条已写进两份 tooltip 与 checklist 7a ⑤，免得实机判读时被当成 bug。
6. **工单点名的验证工具不可用**：§6 P0-2「验证」原写两件——`sc35_probe.py`（露天/遮罩一致性）与"穷举新 token 的两个取值"。实测前者跑 7 个模式、分属持物光／水面波／焦散／岸线折射四类场景，全文 0 次出现 `cloud` 字样，判不了影缘对齐；后者本轮由强制开扫描 + 第 4 点的反向验证完成。M3 那条"对 Astra 0 命中"另有假阴性一说（11.D-18），所以本条的观感结论一律进实机，离线不做影缘对齐判定。

收尾门（与改动面匹配的六件全部实跑）：`python qa/tools/check_pack.py` → 16 项 0 FAIL / 15 PASS / 1 WARN（唯一 WARN 仍是 #4），exit 0，日志 `qa/checkpack-2026-09-21-t14.log`；选项面 69 → **70**，#2 三档各 70 tokens `complete=True`，#3 `zh_CN`/`en_US` 各 70 titles + 70 comments，#8 50 条登记行，#13 70 options / 40 个可翻转分支 / 无种子成对矩阵 87 行。`compile_glsl.py` 三档默认 → `linked=267 failed=0 compute=27`（`qa/glsl-2026-09-21-t14-default.log`），常设的**强制开扫描** `--set CLOUD_SHADOWS=` → 同为 `linked=267 failed=0 compute=27`（`-cloudshadowon.log`），两跑都针对还原后的最终字节重跑（早先 08:25/08:27 那两次跑在探针还在的副本上，作废）。穷举面 `--matrix --jobs 4` → **`RESULT_ALL batches=12 rows=92 entries_per_row=89 linked=8188 failed=0`**，exit 0（`-matrix.log`）；`option_matrix.py` → 70 / 40 因子 / 93 个因子水平 / 780 个因子对 / 无种子阵列 87 行 0 uncovered，且"constant #defines nothing reads"清单不含 `CLOUD_SHADOWS`（= 新代码确有消费者，§7.B.6 反面）；`test_gate_sensitivity.py` 14/14；`provenance_steadfast.py --quiet` 计数不变（本单只读 BSL/Reimagined 思路，不入表达式级移植计数）。`inspect_iris_properties.py` exit 0 并**重生成** `qa/iris-properties-resolved.txt`：327 行不变、5 行改动、纯 token 增（`screen.SKY` +`CLOUD_SHADOWS`、`screen.WATER` +`UNDERWATER_SHAFT_CALIBRATION`、三档 profile 各 + 两个 `!`）——这是 Iris 自己解出的结果，比"工具发出了哪行定义"硬。顺带抓到一处流程遗漏：该快照上次随改动更新是 T9 的 `a53b4ee`，T13 加了选项却没重生成，即 11.F-13 记的"出厂关闭可核"当时靠的是工具展开文本而非这份快照，本单补齐。本轮未跑：`water_path_probe.py` 与 `bloom_lod_probe.py`（未触碰 `program/water.glsl`、`global/water/bloom_capture.glsl`，按 11.F-2 成本规则跳过）。实机判定全部进 `qa/regression-checklist.md` 新增的 **7a** 行（六项：露天有影且影缘对得上天上那片云、屋顶/洞内不得有影、掠射与夜月淡出、雨天是否过暗、PERFORMANCE 档开了无变化、关掉后须逐像素相同）。

**F-15 · T15 执行 P0-3 自动曝光：按裁定先翻案 design.md 4.1 再写代码，新增 5 文件 199 行 + 一张 1×1 缓冲，出厂像素零变化，并把 T14 立的"反向编译验证"首次用作唯一分支证据**

工单 #28。改动面：新增 `global/post/exposure.glsl` 161 行（计量、历史编码、增益解码三件事的唯一契约文件）、`program/exposure.fsh` 23、`program/exposure.vsh` 7、根壳 `composite5.fsh` / `composite5.vsh` 各 4（`wc -l` 实测，新代码合计 199 行）；修改 10 个文件——`grading.glsl` +23−2、`program/final.fsh` +4−1、`lib/settings.glsl` +5−1、`shaders.properties` +15−4、两份 lang 各 +2、`Astra/THIRD-PARTY.md` +2−1（新增一条 Refrax IDEA-ONLY 登记，顺带修掉 T14 留下的 `grading.glsl:213` → `:234` 行号漂移）、`.specs/astra-shader/design.md` +32−4、`qa/regression-checklist.md` +1、快照 `qa/iris-properties-resolved.txt` +15−4（重生成）。顺序本身是裁定的一部分：`design.md` 的 SC-41 与 4.1 翻案先落地、再动 GLSL。出厂关闭形态四处：三档 `profile.*` 各插 `!AUTO_EXPOSURE`、`program.composite5.enabled=AUTO_EXPOSURE`、`program.world-1/composite5.enabled=false`、`program.world1/composite5.enabled=false`；消费点只在 `program/final.fsh` 的空中臂 `srgb_encode(apply_tonemap(apply_exposure(apply_auto_exposure(hdr))))`。`grading.glsl` 的接口契约从四槽改成**五槽**，`apply_auto_exposure` 排第一且是 LINEAR / scene-referred——槽位次序不是风格问题：一个实测场景增益必须同时处在 tone curve 与用户滑杆之外，否则它测到的正是它自己正在改变的量。

1. **翻案的具体内容**：design 4.1 的断言是"手动曝光滑杆 replaces auto-exposure"（`settings.glsl:46` 的注释是它的落点），本轮改写为"两者是乘法串联，滑杆是自动增益的乘数"，并把调研引 Photon 的三条健壮性要求（高光钳制、NaN 兜底、升降不对称速率）写成 SC-41 的验收项。调研原文的两条成本断言在实现中被证伪：① 不需要深度——计量是 8×8 = 64 次 `texelFetch` 的屏幕格点，一次深度都不读；② 不需要新增按分辨率缩放的缓冲——历史是 1×1（`size.buffer.colortex10=1 1`）。落地形状因此是"一次 1 片元的计量 pass + 64 次采样 + 一次 1×1 读写"，不是调研设想的降采样金字塔。
2. **主证据 = 反向编译验证**（T14 立的方法，本轮第一次作为唯一分支证据）。探针：把 `grading.glsl:134` 真臂的 `return linearHDR * astra_ae_gain();` 换成对未声明标识符的读取，假臂不动；合并源中该行是 `final` 链的第 134 行。[A] 出厂侧 `python qa/tools/compile_glsl.py --match final` → `RESULT linked=9 failed=0 compute=0`、rc=0 ⇒ 选项关时真臂根本没进编译器。[B] 强制侧 `--match final --set AUTO_EXPOSURE=` → `linked=0 failed=9`、rc=1，9 个编译单元（3 档 × {`final.fsh`, `world-1/final.fsh`, `world1/final.fsh`}）无一幸免，错误全部是同一条 `11(134) : error C1503: undefined variable "astraT15ReverseProbeMustFail"`。[C] 按备份字节还原，`sha256(now) == sha256(clean)`（当时测得 `37eb919f…9d53`，收尾 EOL 归一后改记 `90f72b4f…345a`，见第 7 点），全包探针串 0 命中。三段记录在 `qa/glsl-2026-09-21-t15-reverse.log`，归一后两侧又在最终字节上重跑，分别见 `qa/glsl-2026-09-21-t15-reverse-factory-final.log` 与 `-reverse-forced-final.log`。为什么这里必须是反向验证而不是绿跑：见下一点。
3. **先把编译算术解释清楚，免得下一轮把 270 读成"分支起作用了"**：`compile_glsl.py` 数的是 入口对 × 3 档，且**忽略 `program.*.enabled` 门**，所以 T14 的 267 = 89 × 3、T15 的 270 = 90 × 3，多出的那 1 个入口对就是新 `composite5`。结果是默认扫描与强制开扫描**同为** `linked=270 failed=0 compute=27`——两跑零差异，这本身就证明编译面区分不了 `#ifdef` 分支。T9 那种"比对两跑差异"的判据在本单不成立，分支证据只能来自第 2 点。
4. **像素中性判据跑在还原后的字节上**（T14 lesson ⑨ 的应用）：`qa/glsl-2026-09-21-t15-runner-postrestore.txt` 两段——10:40:27 三档默认、10:40:54 强制开，均 `linked=270 failed=0 compute=27`、rc=0。早先 10:10 / 10:12 的 `-runner.txt` 跑在探针还在的副本上，只作分支过程记录，不作像素判据。收尾又把这两次扫描在 EOL 归一后的字节上各重跑一遍，数字不变，见第 7 点。
5. **门控全部在最终字节上复跑**（含收尾 EOL 归一后的那一遍，见第 7 点）：`check_pack.py` → 16 项 0 FAIL / 15 PASS / 1 WARN（唯一 WARN 仍是 #4 的 voxy 接线登记），exit 0（`qa/checkpack-2026-09-21-t15.log`）。与 T14 日志逐项 diff 的实测增量：#1 选项 70 → **71**、布尔 30 → **31**；#2 三档各 71 tokens `complete=True`；#3 两份 lang 各 71 titles + 71 comments；#4 编译入口 182 → **186**、lib/global 模块 53 → 54、可达 51 → 52、未接线未登记 0；#6 uniform 声明 84 → **86**；#8 登记行 50 → **51**；#10 `final.fsh` 111 → 114 行；#11 报 `100/31 boolean option(s) wired`（上一轮 98/30）；#12 三档差异条数不变（15 / 7 / 19），只有密度分母 70 → 71；#13 71 options / 可翻转分支 40 → **41** / 成对矩阵 87 → **89** 行；#16 程序门 32 → **35**、限定目录门 25 → 27、根-only 目录门 6 → **8**（新增 `world-1/composite5`、`world1/composite5`，两者都读字面 `false`）。**#14 的口径本轮实测后如实记下**：它那串 `colortexN=<n>` 是"读该缓冲的文件数"而非声明数，colortex0 的 6 → 7 新增读者正是 `program/exposure.fsh`；且该清单只覆盖带 `Format`/`Clear*` 声明的缓冲，`colortex10` 一条这样的声明都没有（走 Iris 默认格式），所以它不出现在 #14 输出里——用 #14 自己的正则单独测，`colortex10` 的读者是 `global/post/exposure.glsl` 一个文件。这不是缺陷（#14 防的是"声明了却没人读"），但要记住**新增缓冲不会自动进入它的覆盖**。穷举面 `--matrix --jobs 4` → `RESULT_ALL batches=11 rows=83 entries_per_row=90 linked=7470 failed=0`、exit 0；`option_matrix.py` 同一选项面报 71 options / 41 因子 / 95 因子水平 / 820 因子对 / 无种子阵列 **89** 行 0 uncovered——83 与 89 的分歧就是 11.E-10 记下的算法差异，本轮两个数各自复现、互不印证，也没有写死进任何清单。§7.B.6 的反面对照通过：`declared but read nowhere: none`，且 `constant #defines nothing reads` 清单不含 `AUTO_EXPOSURE`。受保护臂在穷举面里真实编译的规模，按 11.E-10 的读法测得 **11 × 90 = 990** 次（83 行中 72 行显式写 `AUTO_EXPOSURE=false`、其余 11 行未写即为开）。其余：`test_gate_sensitivity.py` 14/14；`provenance_steadfast.py` 计数不变（`verbatim=14 literal-suffix=2 rewritten=6 astra-only=24 total=46`，Refrax 属 IDEA-ONLY，不入表达式级移植计数）；`inspect_iris_properties.py` exit 0 并随改动重生成快照，把 T14 抓到的"改了选项没重生成快照"那处流程漏洞补上。本轮未跑 `water_path_probe.py` 与 `bloom_lod_probe.py`：未触碰 `program/water.glsl`、`global/water/bloom_capture.glsl`，按 11.F-2 的成本规则跳过。
6. **标定值与实机边界**：`AE_KEY=0.18` 是 Astra 自己辐射单位下的中间灰，源码里直接标着 UNVERIFIED——参照包的 key 不可搬运，因为辐射单位不同。敢把这个选项放出去的前提是增益被硬夹在 `[0.60, 2.20]`，即相对用户滑杆最多 −0.73 / +1.14 挡。历史以 log2 编码存进 8-bit 缓冲，一个 code = 0.51% 增益（`AE_LOG_CODE = 0.00735 = AE_LOG_SPAN / 255`），小于屏幕上看得出的最小曝光变化——这就是"能存进对数域"的理由；`abs(targetLog − currentLog) <= AE_LOG_CODE` 时直接吸附目标，免得在存储精度以下永远抖两个格。`.a` 是有效位而不是备用通道：没有它，从未写过的 texel 会解码成 `AE_MIN_GAIN`，于是每次进世界的第一帧先把画面压暗。水下**冻结历史**而不是隔着水雾测光，出水从最后一个空气值继续。两处 `isnan` 兜底一律返回中性 1.0：宁可没有曝光修正，也不要一个看起来合理的垃圾数。八项实机判定全部进 `qa/regression-checklist.md` 新增的 **19a** 行；本轮离线证据只到"能编译、出厂不变、分支真实"这三层，一帧画面都没测过。
7. **收尾抓到的一处工作副本卫生缺陷：不改画面，但改了台账里的哈希与 diffstat**。本单收尾时发现工作副本里 `Astra/shaders/global/post/grading.glsl`（244 行全部 CRLF）与 `qa/session-log.md`（874 行 CRLF + 3 行 LF）是 CRLF，而它们的 HEAD blob 一直是 LF。成因不能从现存证据唯一确定（`core.autocrlf=true` 下的 checkout 会写出 CRLF，Windows 上 python 文本模式写入也会）。后果是可测量的：`git diff --numstat` 把 session-log 报成 **877/876 整文件重写**，第 1 段记的十个修改文件 diffstat 全部失去意义。处置：纯 EOL 归一（字节级 CRLF → LF，内容不动），归一后实测 `grading.glsl +23−2`、`session-log +7−6`，与台账数字一致；另外九个修改文件与五个新文件本来就是 LF。**HEAD blob 全为 LF ⇒ 既往提交未受影响**。因为归一动了受保护臂所在的那个文件，触碰这两个文件的门里，四件在归一后的最终字节上重跑：`check_pack.py` → 16 项 0 FAIL / 15 PASS / 1 WARN、exit 0（`qa/checkpack-2026-09-21-t15-final.log`）；三档默认扫描 → `linked=270 failed=0 compute=27`（`qa/glsl-2026-09-21-t15-default-final.log`）；强制开扫描 `--set AUTO_EXPOSURE=` → 同数（`qa/glsl-2026-09-21-t15-aeon-final.log`）；反向验证两侧 → 出厂 `linked=9 failed=0` rc=0、强制 `linked=0 failed=9` rc=1 且 9 条 `error C1503` 全报在第 134 行，两份日志合并进 `qa/glsl-2026-09-21-t15-reverse-final.log`。探针守卫哈希由此改记为 `90f72b4f0c59b4e43a6c04c44b67a81e643142c9ebc9092d9391a167de30345a`，还原后复算同一哈希、探针串零残留。教训：提交前把每个改过的文件的工作副本 EOL 与 HEAD blob 对照一遍（同时看 `git diff --numstat` 与 `git diff -w --numstat`，两者不一致就是换行漂移），别让哈希与 diffstat 记在一次工作副本换行漂移上。**未重跑的五件如实列出**：`--matrix` 穷举、`option_matrix.py`、`test_gate_sensitivity.py`、`provenance_steadfast.py` 与 `inspect_iris_properties.py`。理由是归一只改换行字节、不改任何语法与统计口径，而同一个口径最严的那件（check_pack 的 16 项逐行）已实测得**归一前后两份日志 0 行差异**；这一句是测量，前一句是推理，区别写明。
