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
- **无 TAA 的时域自适应体光采样**：`lib/atmospherics/volumetricLight/volumetricLight.glsl:9,183,321-346` 引入标量 `vlFactor`（0..1），相机静止时每帧爬升（`vlFactor = min(vlFactor + OSIEBCA, 1.0)`），运动时按 `reduceAmount` 更快回落；`nearSamples`/`farSamples` 随之增减。持久化靠 `composite1.vsh:379` 从 `colortex5` 最后一个像素 `.a` 读上一帧值——与 Astra colortex6 的 1×1 状态像素同构。
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

- **现状**：M3「云阴影」Astra **0 命中**，参照组 8/19 款非零（9/21 个集合：Photon 114、Bloop 36、Solas 27、Complementary 18、Noble 16、BSL 4、ILV 3、JCL 2）。B 组 5 款全为 0 ⇒ **低配包不做云阴影，因此 Astra 若做必须是无条件的便宜形态**。
- **依据**：BSL `lib/lighting/shadows.glsl:295-374 GetCloudShadow()`——把 2D 云噪声沿光向投影到地面，再用 `CLOUD_REVEAL`（`:325`）打孔洞透射，成本约一次噪声 fetch；守卫放在最前面的两例：Solas `lib/atmosphere/volumetrics.glsl:42-80`（先 9 点 `depthtex` 采样求 `averageDepth` 再合成 `closedSpaceFactor`）、Noble `include/atmospherics/clouds.glsl:194-196`（`if (weatherMap <= 0.05) return 0.0;`——无雨即整段退出）。
- **做法**：复用 Astra 已有云的密度场（`Astra/shaders/global/atmosphere/clouds_planar.glsl`，324 行）在**单一高度平面**上沿 `sunVec` 采样 1–2 次求遮挡，与 `shadowmap` 结果相乘；洞穴/封闭处按 `eyeBrightnessSmooth.y` 或天光贴图早退；接入 `Astra/shaders/lib/settings.glsl` 单 token，并**在 P0-1 之后让该 token 参与 profile 差量**。
- **成本**：每片元 1–2 次 fetch，仅在 `diffuse > 0` 且露天时执行。
- **许可证**：BSL = **All Rights Reserved → 只读思路**；表达式、噪声选择、`CLOUD_REVEAL` 的具体形状全部自写。PROVENANCE 按 `Astra/shaders/global/post/grading.glsl:210-212` 的既有格式记 `IDEA ONLY, no code and no formula transplanted`。
- **验证**：`python qa/tools/sc35_probe.py`（露天/遮罩一致性）；`compile_glsl.py` 穷举新 token 的两个取值。

### P0-3 · 自动曝光（mipmap 链测光，带不对称速率与守卫）

- **现状**：M3「自动曝光命名」Astra **0**；`Astra/shaders/lib/settings.glsl:176 #define EXPOSURE 100` 是静态滑杆；`Astra/shaders/global/post/grading.glsl:115 apply_exposure()` = `linearHDR * (EXPOSURE*0.01*grading_dimension_exposure())`——**完全没有亮度输入**。M3「Mipmap降采样」Astra 已有 3 处声明、覆盖 2 张缓冲（`program/composite1.fsh:20` 与 `program/final.fsh:24` 在 colortex2；`Astra/shaders/program/water_bloom.fsh:5 const bool colortex0MipmapEnabled = true;` 在 colortex0）已在用同一机制 ⇒ **设施存在，只缺测光用途**。〔2026-09-20 复核更正：原文"已有 2 处"与句内引用的第三处声明自相矛盾。〕
- **依据**：结构派（mip 平均）ILV `program/composite20.glsl:13`（`colortex0MipmapEnabled`）+`:202-208`（`texture2DLod(…, 10000.0)` 取最粗级 → `sqrt(getLum(·))` → `mix` 历史值）、BSL `program/composite5.glsl:57,156-163`（`exposureLod = log2(viewHeight * AUTO_EXPOSURE_RADIUS)`）、MakeUp `common/composite_vertex.glsl:74-87`（`log2(min(viewWidth,viewHeight)) - 1.0` + 5 点采样）、SDV `main/composite6.glsl:168-178`（`textureLod(colortex4, vec2(0.5), 8)` + 角落历史值 `texelFetch(colortex5, ivec2(1), 0).a`）、VanillaPlus `program/grade/exposure.vsh:37-91`；统计派（直方图中位数）Photon `program/c4_taa_exposure.vsh:39-170`。**必须采纳 Photon 的三条性质**：中位数或至少对高光截断（否则太阳入镜会整体压暗）、`:161-170` 的 NaN 守卫与**变暗/变亮不对称速率**（`AUTO_EXPOSURE_RATE_DIM_TO_BRIGHT` vs `…_BRIGHT_TO_DIM`）、`:144` 历史值存 texel(0,0) 的 alpha。兜底参考 Mellow 的 `get_min_light` 绑 `screenBrightness`/`nightVision`。
- **做法**：在 `Astra/shaders/program/water_bloom.fsh` 已有的 mipmap 链上取 `log2(min(viewWidth,viewHeight))` 一级做亮度，历史值写进任一 `colortex` 的 texel (0,0)，在 `final` 前以标量注回（ILV `program/composite20.glsl:161` 的角落写回 + `:4-5` 的 `flat in_out` 顶点算片元用），**不做新的全屏 pass**。
- **成本**：一次 mipmap fetch + 一个 1×1 历史 texel，可忽略。
- **权衡必须写明**：Complementary Reimagined（66,417,800 下载、最后发布 2026-09-15）**没有任何自动曝光**——`auto.?exposure|eyeAdaptation` 在其 `shaders/` 全仓库 **0 命中**（§2.1）。所以这一项的收益是"洞穴↔露天过渡不再需要手改滑杆"，不是"补一个缺失的必需品"。建议以**可关闭开关**引入，默认值需实机校准后才可开。〔2026-09-20 复核补充：本条与 Astra 既有设计直接冲突——`Astra/shaders/lib/settings.glsl:46` 明示 BLOCKLIGHT_SUPPRESSION "(replaces auto-exposure, design 4.1)"，以日光抑制取代自动曝光是 design.md 4.1 的已决事项。采纳本条前须先翻案 design 4.1，并把翻案理由写进 design.md 修订记录。〕
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

### P1-6 · 几何太阳遮蔽（1 像素 + alpha 广播）

- **现状**：Astra 的太阳项是 `Astra/shaders/lib/uniforms.glsl:27 uniform float godraysExposure;`，其注释自述 = 基础曝光 × 视线夹角淡出 × 屏外淡出——**三个因子全是解析量，从不采样深度**。因此"太阳被墙挡住"当前拿不到一个**全局强度标量**。注意 `GODRAYS` march 内部已有逐样本几何遮挡（`Astra/shaders/global/post/godrays.glsl:32-36` 手工深度比较、`:71-73` 逐样本乘遮挡），所谓"穿墙"实际表现为**遮挡后整体强度不回落**——隔着厚墙看向太阳方向时，光束仍按解析曝光以满强度叠加。〔2026-09-20 复核更正：原文"会穿墙"忽视了 march 内的深度遮挡。〕
- **依据**：LIGHT `composite.fsh:423-433`（单像素 13×13 深度遮挡）→ `:582 gl_FragData[0] = vec4(color,gr)` → LIGHT `final.fsh:329 float sunvisibility = texture2D(gaux1,vec2(0.0015)).a * fading;` 读回。**注意：真正的缺口不是"没有光束"（Astra 已实装并已接入），而是"光束没有几何遮挡判定"。**
- **做法**：在任一已有 composite pass 的角落像素做小窗口深度遮挡判定，结果写进**自有 buffer 的未用 alpha 分量**广播（Astra `Astra/shaders/lib/water_buffer_formats.glsl:12,15,16` 已有 R11F_G11F_B10F 声明，需另选一个带 alpha 的缓冲）。
- **成本**：一个像素的 9×9～13×13 次 `depthtex` 采样 = 对整帧成本无影响。
- **许可证**：LIGHT = Chocapic13 Sharing Agreement → **只读思路**；窗口尺寸、权重、广播载体全部自写。PROVENANCE 记 `IDEA ONLY`。
- **验证**：`python qa/tools/water_path_probe.py`（墙后太阳场景）+ `compile_glsl.py`。

### P1-7 · 焦散/消光烘焙进 shadow 阶段

- **现状**：Astra 的水体模型在像素端（`Astra/shaders/global/water/absorption.glsl` 80 行；`water_extinction()` `:42-44`；`water_transport()` `:48-54` 已含 `σs/σt·(1-T)` 单次散射源项）。**这条模型本身强于多数参照包**（Complementary 是 `lib/materials/specificMaterials/translucents/water.glsl:193` 的单行 `1-exp(d*0.075)`，RedHat 干脆无吸收），所以**不是为了"更正确"，是为了"同样的正确性花更少"**。
- **依据**：六例共识——Complementary `program/shadow.glsl:114-180`（焦散 + 光束）、BSL `program/shadow.glsl`、Solas `programs/shadow.glsl:58-77`、E-LITE `common/shadow_fragment.glsl:26,59-67`、SDV `main/shadow/shadow.glsl:161-177`、VanillaPlus `program/shadow/comp0.fsh:38-98`（**逐 texel 预计算 Beer-Lambert 消光系数**，最贴近 Astra 需求的一例）。
- **做法**：把与像素无关、只与"这段光路上有什么方块"有关的量（透光方块计数、逐通道消光累积）在 shadow/shadowcomp 阶段逐 texel 烘进 `shadowcolor` 的未用分量。Astra 有 12 条 shadowcomp 声明（M2 全场最多）⇒ **调度设施已经比多数参照包更完备，落地阻力小**。
- **成本**：shadow 阶段每 texel 一次；换所有像素端零成本。需保证 `shadowcolor` 有非零清屏色（BSL `program/shadow.glsl:44-46` 的 `vec4(0.25,...)` 教训）。
- **许可证**：Complementary 专有 1.7、BSL ARR、Solas ARR、E-LITE/MakeUp LGPL、SDV FlameRender、VanillaPlus ARR+EULA §4 → **全部只读思路**。「烘焙进 shadowcolor」这一**架构选择**不受保护，具体 GLSL 表达式必须自写。
- **验证**：`python qa/tools/cost_census.py` 对比像素端抽样量；`validate_shadow_water.py`。

### P1-8 · 硬件 PCF 默认档决策

- **现状**：`Astra/shaders/global/lighting/shadowmap.glsl:37-47` 两条路径都在（`SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE` → `uniform sampler2DShadow shadowtex0/1` + `SHADOW_FILTER_TAPS = 4`；`#else` → `sampler2D` + `TAPS = 16`），但 `Astra/shaders/lib/settings.glsl:57 #define SHADOW_FILTER_MODE 0` **默认走软件 16 抽**，且 `:329-336` 的 `shadowHardwareFiltering*` 仅在 mode 1 为 true。
- **依据**：4 抽硬件 PCF 在 2026 年仍然够用且有两条实证——LIGHT `gbuffers_terrain.fsh:96-109`（`sampler2DShadow` + 4 角 `shadow2D` = 实际 16 texel）、VanillaPlus `program/gbuffer/forward.fsh:131-150` 用 `textureGather(shadowtex1, uv.xy, uv.z).wzxy` **一条指令拿 4 次硬件比较**（配 `:95-97 shadowHardwareFiltering`）。Astra 软件路径除 `:90-100 shadow_read_tap` 的逐 texel 夹边外，**已有两参 `textureGather`**（`:117-126 shadow_gather_visibility`，gather 原始深度后手工 `step` 比较，`:118-119` 注释自陈角序对应）——本条真正新增的只是 VanillaPlus 那种**三参 shadow-gather**（在 `sampler2DShadow` 上一条指令换 4 次硬件比较）。〔2026-09-20 复核更正：原文未提及 Astra 已有的 gather 路径。〕
- **做法**：用等价性测量决定默认值，而不是先验地选"软件更兼容"。若 `textureGather` 三参形式在目标 Iris 版本可用，把它接进硬件路径以省指令。
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

### P2-15 · 反射路径的云/噪声八度减半并重归一

- **依据**：Sildur's `deferred.fsh:337+` `int maxOctaves = isReflection ? 2 : 4;` + `if (isReflection) noise *= 1.2; //normalize noise scale when skipping octaves`，配预计算 `vec4 stepsScale/stepsWeight` 与注释里的推导公式。`Astra/shaders/global/atmosphere/clouds_planar.glsl`（324 行）、`Astra/shaders/global/water/refraction.glsl`、`Astra/shaders/global/water/raytrace.glsl` **对反射路径完全不做质量降级**。
- **做法**：反射调用点传 `isReflection`，八度减半并按预计算权重重新归一（避免"少一层噪声就变暗"）。
- **许可证**：Sildur's **ARR → 只读思路**；八度权重是通用 mipmap/fBm 数学。
- **验证**：`water_path_probe.py` + `cost_census.py`。

### P1-16 · 光束时域自适应采样（vlFactor + 状态像素 + 运行时循环上界）

- **现状**：`Astra/shaders/global/water/light_shafts.glsl` 的 `UNDERWATER_SHAFT_SAMPLES` 是编译期常量（`Astra/shaders/lib/settings.glsl:136`，7/7/10 三档），静止观赏时质量不足、移动时白付。
- **依据**：Complementary Unbound `lib/atmospherics/volumetricLight/volumetricLight.glsl:9,183,321-346`（§2.1 新增 bullets）——`vlFactor` 持久化在 `colortex5` 末像素 `.a`，静止爬升、运动回落，驱动 `nearSamples`/`farSamples`。**前提条件须先修正**：真正的阻塞站点不是 `light_shafts.glsl:110,125`——`shadowtex1`/`shadowcolor0` 在全包没有任何 mipmap 声明，隐式 LOD 只能取到 level 0，实际无害（改 `texelFetch` 属于卫生改进）。必须修的是 `Astra/shaders/global/water/bloom_capture.glsl:21`：`colortex0` 经 `program/water_bloom.fsh:5` 开了 mip，外层 `if` 又是数据相关分支，那里才是真正的未定义行为（§9.4 前置项、本条下方）。引入运行时循环上界前须先按 Complementary Unbound 的做法消掉这类隐式 LOD 站点——它 `:201` 的注释原话："We need to use texelFetch here or a lot of Nvidia GPUs can't get a valid value"。
- **做法**：新增 1×1 缓冲挂 `astraVlFactor`——colortex6 **没有空闲通道**（`Astra/shaders/global/water/medium_state.glsl:5`：RG = 1/16 格水面高度、B = 天空通达、A = 有效位，四通道全占）；静止每帧 `+= OSIEBCA`、运动按 `reduceAmount` 回落；`UNDERWATER_SHAFT_SAMPLES` 从编译期常量改为该标量驱动的运行时上界。**前置修复**：见上方「依据」——`bloom_capture.glsl:21` 是必修项，`light_shafts.glsl:110,125` 是可选卫生改进。
- **成本**：一个 1×1 状态通道 + 循环上界改运行时。
- **许可证**：时域自适应采样 + 状态像素持久化是通用图形技巧 → **无风险**。
- **验证**：逐帧对比静止/运动场景的光束质量与帧时间，确认平均成本不升。

### P1-17 · 水吸收侧面 skylight 代理 + 未命中近场缓释

- **现状**：`Astra/shaders/program/water.glsl:31` 的 `water_sample_path` 在空气侧用 `dot(origin−point, faceNormal)`（`:80`/`:96`）求几何深度——竖直水壁（瀑布/流水侧面）上该值 ≈ 0，几乎不吃吸收。〔2026-09-20 复核更正：函数不在 `global/water/absorption.glsl`。〕
- **依据**：Steadfast 0.8.0 `environment/water/absorption_refraction.glsl:22-120` 三分支——① 顶面用几何深度（Astra 已有）；② **非上向水面用背景天光作深度代理** `waterDepth = (−15/16)·skylight + 1`（单条 FMA）；③ 未命中分支假设满水深 `waterDepth = 0.25 + 0.75·min(−z/24, 1)` 并按距离线性减浅（Astra 的未命中是 validity=0、回落到未偏移的不透明路径，`program/water.glsl:26-27,90-112`，无近场水体色 ⇒ 瀑布背后、浅水贴地平线处**偏亮**而非偏浓）。〔2026-09-20 复核更正：原文"返回固定水体色"与 miss 分支实际行为相反。〕
- **做法**：`water_sample_path` 增加分支——`faceNormal.y > threshold` 走几何深度（现有），否则读 colortex3 的 skylight 作代理；未命中分支加同距离线性减浅。
- **成本**：一个分支 + 一次 skylight 读取。
- **许可证**：Steadfast GPLv3 + §7b/§7c 附加条款 → 可修改但须保持附加义务（`python qa/tools/provenance_steadfast.py` 前后对账）。表达式自写。
- **验证**：`water_path_probe.py` 覆盖瀑布、浅水贴地平线、平视三种边界。

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

### P2-20 · 光束标定三条（Solas V3.7b 参照）

- **现状**：Astra 09-20 修复后的光束强度门 `mix(0.25+0.25·VoL, 0.45·VoL, time)` 白天端仍会归零。
- **依据**：Solas V3.7b `lib/atmosphere/volumetrics.glsl`（§2.4 新增 bullets）——① 强度曲线改软平方瓣 + 下限 `(1+2·VoL²)·(0.25+1.75·sunVisibility)`；② 采样改指数距离分布 `exp2(dither)` 每样本 ×2；③ 颜色随时刻向天空色混合 `fmix(lightCol, nSkyColor, timeBrightness·0.75)·0.1`。
- **做法**：三条分别替换 Astra 的对应位置——强度门、均匀步进、固定染色。
- **许可证**：Solas ARR → **只读思路**；表达式必须自写。**禁止引入 Solas DRM 宏**。
- **验证**：`light_shafts` 现有探针对拍正午/晨昏/水下三场景。

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
python qa/tools/compile_glsl.py --matrix   # → P2-12 选项穷举门：83 行二组合覆盖阵列 × 89 入口（--matrix-rows N 截断，截断即非零退出）
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
| 借鉴报告 #1「循环体已全显式 LOD」 | **不成立（证据已更正）** | 结论仍成立但站点指错过：`light_shafts.glsl:110,125` 的 `shadowtex1`/`shadowcolor0` 全包无 mipmap 声明，隐式 LOD 只取 level 0，无害。真站点是 `global/water/bloom_capture.glsl:21`——`colortex0` 经 `program/water_bloom.fsh:5` 开 mip，该行在双重循环内、外层 `:15` 是数据相关 `if`，属未定义行为。正确修法是把 `lod` 参数显式传下去（`textureLod(colortex0, sampleCoord, lod)`）而非 `texelFetch`——`getBloomTile` 的整个 mip 选择本来就靠 `exp2(lod)` 缩放坐标 + 梯度推导，`texelFetch` 会绕过它（§6 P1-16） |
| 借鉴报告「Unbound 多出 TAA + 体素化 + 3D 云 + SSR/反射缓冲 + textRendering」 | **部分描述错** | TAA + 体素化 + textRendering 确为 Unbound 独有；但 SSR/反射缓冲（colortex7/8）与 3D 云在 Complementary 共享 `lib/` 中已存在，不是 Unbound「多出」 |
| 借鉴报告「`lib/common.glsl:120-121` 两张反射缓冲尺寸声明」 | **文件错** | 反射缓冲尺寸在 `dimension.properties` 的尺寸指令中通过 `REFLECTION_RES` 引用，不在 `common.glsl:120-121` |
| 借鉴报告 waterFog 谱序「b×=(1-abs³·0.5)」 | **参数化描述错** | `waterFog.glsl:6` 无 swizzle ⇒ 三次项是三通道共有衰减而非 b 独享；定性结论「红衰最快、蓝衰最慢」仍成立（19 点数值扫描 r<g<b 恒成立） |
| 借鉴报告「Unbound VL 用 `texture2DShadow` 硬件比较采样器」 | **机理错** | Unbound VL 使用 `texture2D`/`texelFetch` 而非 `texture2DShadow`；不影响建议方向（P1-16 的前置修复是改隐式 LOD，与此无关） |

### 9.3 与既往审查的关系

本报告不重复 `docs/2026-09-13-astra-full-audit.md` 与 `docs/2026-09-20-qoder-full-review.md` 的代码缺陷结论；§6 的每条建议都只引用**本次样本实测**与**Astra 当前状态**两类证据。既往审查中标为开放的 `bloom_capture` 隐式 LOD 站点、README 3 行不实、模块数 53/51 权威值等项，与本报告正交，未在此重复。

### 9.4 落地顺序建议

`P0-1`（纯配置，无风险，先做）→ `P2-12`（穷举编译，为后续所有开关兜底）→ `P2-10`/`P2-11`（合规与防退化基础设施）→ `P2-18`（`dimension.properties` 按维度裁剪，纯配置）→ `P1-5`/`P1-9`（成对做，同一处 bias/畸变）→ `P1-17`（水吸收侧面 skylight 代理 + 未命中近场缓释）→ **`P1-16` 前置**：把 `global/water/bloom_capture.glsl:21` 的隐式 LOD 改为 `textureLod(colortex0, sampleCoord, lod)`（该函数靠 `exp2(lod)` 缩放坐标 + 梯度推导选 mip，`texelFetch` 会绕过这套选择，不可用）→ `P1-16`（光束时域自适应采样，依赖前置完成）→ `P1-6` → `P1-7` → `P1-8` → `P2-14`/`P2-19`（分辨率粒度选项）→ `P2-20`（光束标定三条，随 P1-16 对拍）→ `P0-2` → `P0-3` → `P2-13`（MIT 可署名复用清单）→ P2 余项（含 `P0-4` 降级后的月相残差，仅一处，顺手做）。**〔2026-09-20 执行期调整〕**`P0-2`/`P0-3` 从原来的第 5 位挪到后段：这两项是全表视觉风险最高、必须实机校准后才敢放的条目，且 `P0-3` 还卡在 `design.md` §4.1 需要先行修订；把它们排在低风险、可静态验证的条目之后，能让每一步都有编译或校验脚本兜底，而不是让最高风险项挡在最前面。

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
| 1 | 水下光束运行时采样数自适应 | **采纳，但前提须修正** | `UNDERWATER_SHAFT_SAMPLES` 是用户选项 7/[4-10] 而非常量；「循环体已全显式 LOD」为假（C36），但真站点是 `bloom_capture.glsl:21`（colortex0 有 mip + 数据相关分支），修法 `textureLod(…, lod)`；`light_shafts.glsl:110,125` 的采样器无 mip，隐式 LOD 无害，仅卫生改进（§6 P1-16） |
| 2 | vlFactor 时域自适应 | 采纳 | → §6 P1-16 |
| 3 | 近/远两段式 VL 采样 | 采纳 | → §6 P1-16 描述 |
| 4 | 水吸收谱序对照标定 | 采纳（修正后） | 定性结论正确，参数化描述须修正（§9.2 已记录） |
| 5 | 焦散曲率烘焙进 shadow | 采纳 | → §6 P1-7 |
| 6 | 体积云三级早退 | 采纳 | → §2.4 已记录思路 |
| 7 | 色调映射常数滑杆化 | 采纳 | 已在 Astra 滑杆体系中 |
| 8 | `dimension.properties` 按维度裁剪 | 采纳 | → §6 P2-18 |
| 9 | 反射/光束分辨率用户选项 | 采纳 | → §6 P2-19 |
| 10 | Solas 水吸收谱序作对照 | **采纳（修正后）** | 定性方向正确可作标定基准；第三条是共有衰减项非 b 独享 |
| 11 | Steadfast 水吸收 skylight 代理 | 成立、v2 备选 | → §6 P1-17 |
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
| P0-2 云阴影 | **高价值，采纳** | 与 `clouds_planar.glsl:42-44` 自己的 NOT PORTED 登记对齐（该登记还指向 `docs/handoffs/sky-clouds.md` 的边界约定，动手前先读）；ARR 只读思路约束已写明 |
| P0-3 自动曝光 | **中价值，前置翻案** | 与 design 4.1 已决事项冲突（`settings.glsl:46` "replaces auto-exposure"），报告未提及，须先翻案；报告自身"默认关 + 实机校准"的权衡合理；Mipmap 口径见 11.D-3 |
| P0-4 逐帧常量 | **报告自我降级正确** | 残差复核成立（`sky.fsh:40-41` + `overworld.glsl:88` 两处逐片元月相）；Iris-only 判断成立，删掉双写一半同意 |
| P1-5 bias 统一 | **低价值，撤条并入 P1-9 · 已执行（见 11.F-5）** | "并存"系误述（`#ifdef DIMENSION_END` 互斥，改后在 `shadowmap.glsl:205-217`），适用条件已显式；残差仅 End 分支 `+0.015` 归一 |
| P1-6 几何太阳遮蔽 | **中低价值，收窄后采纳** | march 内逐样本遮挡已在（`godrays.glsl:32-36,71-73`），缺口只是全局强度标量（`uniforms.glsl:27` 全解析）；1 像素窗口做法便宜 |
| P1-7 焦散烘焙 | **中价值，采纳** | 清屏色前提已满足（`settings.glsl:363` 显式白）；收益定位（省像素端而非更正确）写得准确 |
| P1-8 硬件 PCF 默认档 | **中低价值** | 默认软件 16 抽（`settings.glsl:57`）成立；但软件路径已有两参 `textureGather`（`shadowmap.glsl:117-126`），报告未提；同意"用等价性测量决定默认值" |
| P1-9 畸变归一 | **中价值，采纳 · 已执行（见 11.F-5）** | `distort.glsl:7,10` 无 SHADOW_DISTANCE 归一成立；Steadfast §7b/§7c/§7e 义务提醒与对账工具调用正确；锚值改由实测选定（`SHADOW_DISTORT_CORE = 25.6`），P1-5 的 End 残差一并闭合 |
| P2-10 vendor 隔离 | **高价值（合规基建），采纳** | 与 §7.B.3 互为表里；Astra 已有 PROVENANCE 短注惯例，迁移目标明确 |
| P2-11 buffer 声明防退化 | **高价值（防退化），采纳** | 6 处活声明复核成立（`water_buffer_formats.glsl:12,15,16,18` + `end_illumination.fsh:10` + `end_sky_buffer.fsh:9`） |
| P2-12 穷举编译 | **高价值，采纳** | `compile_glsl.py` 已有基础；化石 token 防线是结构性收益 |
| P2-13 MIT 复用清单 | **高价值** | `grading.glsl:204-208` 已有 Mellow MIT 移植先例（链序），`Astra/shaders/lib/bayer.glsl` 已有基础；逐件许可证动作标注清楚 |
| P2-14 连续分辨率旋钮 | **中低价值** | 是 3 档之外的粒度补充，建议在 P0-1 定调后再评估 |
| P2-15 反射八度减半 | **中低价值** | 反射路径无质量降级成立（`clouds_planar`/`refraction`/`raytrace` 无 isReflection 分支）；收益限于反射像素 |
| P1-16 光束时域自适应 | **中价值，前提修正后采纳** | 两处前提更正（11.D-5/6）；状态像素须用新 1×1 缓冲；前置修复并入真正的 mipmapped 站点 |
| P1-17 水吸收侧代理 | **中价值，采纳** | 垂直壁问题成立（`water.glsl:80/:96` 的几何深度）；文件归属与 miss 分支描述已更正（11.D-7/8）；Steadfast §7 义务对账要求合理 |
| P2-18 按维度裁剪 | **中低价值，采纳 · 已执行（见 11.F-4）** | properties 已有 8 条维度专用 `false` 门（两个维度目录各 `composite`/`composite2`/`composite3`/`composite4`），本条是把已有机制系统化；"缓冲尺寸跟随维度配置"不成立——`size.buffer.*` 以裸缓冲名为键（见 §6 P2-18 做法条） |
| P2-19 光束/反射分辨率选项 | **中低价值，建议与 P2-14 合并** | 硬编码 0.5/0.25 成立（`shaders.properties:14,19`）；与 P2-14 同属分辨率粒度 |
| P2-20 光束标定 | **中价值，采纳** | 强度门复核成立（`light_shafts.glsl:62`）；Solas ARR 与"禁止 DRM 宏"约束到位 |

### 11.C §7 复核

- **A 组 7 条推翻全部成立**，逐条重开对应文件核实。其中第 4 条引用的 `design.md:517` 经复核**行号准确**——`:517` 正是"零 compute/零彩光边界修订"那条（复核一度怀疑差一行，重开文件后撤销）。
- **B 组 10 条与 Astra 现状一致**：TAA / SSAO / 逐文件许可头 / 维度整包复制 / 注释记配置 / 零消费者选项 / `#version 120` 外壳 / 散文档位 / 100+ 调色滑块在 Astra 均不存在或已有等价决策。B.1 与 B.10 同为"不要现在引入 TAA"，建议合并为一条。

### 11.D 报告错误更正清单（均已就地写回正文）

1. §4.2 "Astra 是延迟（lit.fsh → deferred 链）" → 前向（`design.md:48`；lit.fsh 头注；deferred.fsh 仅场景拷贝+水坑）。
2. §4.3 与 P1-5 "两条 bias 并存" → `#ifdef DIMENSION_END` 维度互斥（改前 `shadowmap.glsl:200-209`，随 11.F-5 位移后现为 `:205-217`）。
3. §0 与 P0-3 "MipmapEnabled 仅 2 处" → 3 处声明覆盖 2 张缓冲（`composite1.fsh:20`、`final.fsh:24` 在 colortex2；`water_bloom.fsh:5` 在 colortex0）。
4. P0-3 漏报与 design 4.1 的冲突（`settings.glsl:46` "replaces auto-exposure"），已在权衡条补充。
5. P1-16 "colortex6 空闲通道" → 四通道全占（`medium_state.glsl:5`），只能新增 1×1 缓冲。
6. P1-16 前置修复的 LOD 定性 → `light_shafts.glsl:110,125` 目标无 mipmap，实际无害；真正站点是 `bloom_capture.glsl:21`（colortex0 开 mip + 数据相关分支）。
7. P1-17 文件归属 → `program/water.glsl:31`。
8. P1-17 "Astra 返回固定水体色" → miss 是 validity=0 回落未偏移路径，视觉后果偏亮而非偏浓。
9. P1-8 未提 Astra 软件路径已有两参 `textureGather`（`shadowmap.glsl:117-126`）。
10. P1-6 "会穿墙" → march 内遮挡已在，缺口是全局强度标量。

### 11.E 复核中新发现的 Astra 侧问题（报告未提）

1. **`program/scattering.fsh:2` 注释腐烂**：称 "colortex1 is full resolution when water shafts are enabled"，但 `shaders.properties:14` 已固定 `size.buffer.colortex1=0.5`。属 §7.B.5 要防的"注释记配置"自伤，顺手修正。**执行阶段扫描发现同一失败模式另有两处，复核未捕捉**：`program/composite1.fsh:1-2` 称 colortex2 为 "half resolution"/"0.5x"，`global/post/bloom.glsl:5,82,86` 称 "half-resolution"/"2x downsample"——而 `shaders.properties:19` 与 `bloom.glsl:42` 的 `BLOOM_CAPTURE_SCALE` 早已是 `0.25`（`properties:15-18` 的注释正是记录这次 0.5→0.25 改动，只有散文没跟上）。三处均已改为指向单一真源而非重述数值；代码侧本就由 `BLOOM_CAPTURE_SCALE` 与 `textureSize` 推导，无行为缺陷，纯注释腐烂。
2. **`bloom_capture.glsl:21` 的隐式 LOD 站点**（见 11.D-6）：在项目记忆中仍为开放项，优先级应高于 P1-16 字面的前置修复。
3. ~~**行数口径混用**：M1 用 wc 口径（9559）、§9 模块普查用 `count('\n')+1`（9804）~~ —— **本条经实测撤销**（2026-09-20 执行阶段）。缺陷不存在：§3.1 的 ASTRA 行写的就是 **9804**，与 `astra_census.json`（`glsl_files=245, glsl_lines=9804`）一致；`census.py:74` 与 `census_astra.py:21` 两处**都已**用 `count("\n")+1`，工具侧本就统一。`9559` 全文只出现在两处——本节 11.A 的转述，以及 §9.2 表内作为**被推翻前提的引文**（那一行本来就在记录旧数字，不是 M1 的值）。复核时把引文误当成了表格数值。独立重算 245 文件得 `count('\n')=9560`、`+1/文件=9805`，与 9804 的 1 行差是末行换行边界，属 11.A 自己说过的口径差，不是混用。
4. **三处"对报告的怀疑"经复核撤销**，记录以防将来误改：`design.md:517` 行号准确；"shadowcomp 12 条"口径自洽；§2.19 "Astra 许可头 0" 在"逐文件 boilerplate"口径下成立——Astra 的 1–4 行 PROVENANCE 短注不属于该列统计对象。
5. **`DITHERING` 是个死选项**（P0-1 新建的差分门抓出；`Astra/shaders/lang/en_US.lang:67` 与 `zh_CN.lang:67` 早就为它写好了 GUI 文案）：`Astra/shaders/lib/settings.glsl:194` 的声明形式与 `BLOOM`/`VIGNETTE` 完全一致，`OptionAnnotatedSource` 单文件扫描也不报任何 diagnostic，但它始终不在 `ShaderPackOptions.getOptionSet()` 里 ⇒ GUI 无该行、三条 profile 的 `DITHERING` token 全部无效、`#define` 行永不改写，输出抖动实际恒开。根因是 Iris 的发现规则：**布尔选项只有在某个图文件里被 `#ifdef`/`#ifndef` 引用，才会进入选项集**——`OptionAnnotatedSource.parseLine` 只把这两个前缀交给 `parseIfdef` 去填 `booleanDefineReferences`，`ShaderPackOptions` 跨文件求并集后把它当作过滤参数传给 `getOptionSet(path, names)`，而 `defined()` 根本不被解析。包内 27 个布尔选项与该规则 1:1 吻合：唯一没有 `#ifdef` 站点的正是 `DITHERING`（原先只在 `Astra/shaders/global/post/grading.glsl:186` 以 `#if defined` 出现）。已改写为 `#ifdef`，实测 Iris 发现数 89→90、差分门归零，运行行为不变（出厂默认与三档都是 true）。**本条同时推翻 `qa/tools/check_pack.py` 的 SC-28 在 2026-09-10 写下的相反结论**（"真正的要求只是选项在某处被引用，`defined()` 也算"）——那次误判正是这道门放行该缺陷的原因，规则已就地改正并从 WARN 升为硬失败。

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



