# Astra Shader 设计方案（兼 Goal 计划）

> 当前用途（2026-10-09）：本文保留原设计与带编号的决定，按需用于追溯，不是当前功能清单或执行计划。当前使用行为见 [Astra README](../../Astra/README.md)，待办、技术债与规划见 [当前工作](../../docs/当前工作.md)。旧 v1 排除项、帧率分档与阶段状态不能替代已经实施的 TAA、AO、体积雾、彩光及当前主世界目标。

> 当前入口说明更新于 2026-09-25。运行参数以 `Astra/shaders/lib/settings.glsl` 与 `shaders.properties` 为准；带日期的 SC 决议保留历史语境，不能当作当前参数表。文档状态见 [docs/README.md](../../docs/README.md)，本地参考包配置见 [qa/tools/README.md](../../qa/tools/README.md)。

> 2026-10-08 源码说明：SC-40 的“三张自定义图像”是 09-20 的历史数量；10-07 增加光源区域汇总后，下界现为四张图像，初始化加八级传播仍为九个计算阶段。末地星表初始化也使用计算着色器。当前目标仍为支持这些功能的 Iris / RTX 4050 环境；`iris.features.optional` 不代表已实现缺少计算着色器或自定义图像时的兼容路径。详见 [本轮审查第五节](../../docs/archive/实现与取证.md#record-060)。

**版本：** v1.1（设计稿，2026-09-05）
**状态：** 设计稿已进入实施；原文的"待用户复查"只描述 2026-09-05 当时，不是当前状态
**参考分析副本：** `_analysis/`（Mellow Shader v3.4 / Refrax_v1.3.1 / Solas Shader V2.2b / Steadfast-0.8.0）

---

## 0. 总目标

基于四包（Steadfast / Refrax / Solas / Mellow）开发 Iris 光影包 **Astra v1**，达到 §8 全部验收标准：

- **路线**：清爽原味 + 性能；效果三对标——**水面 ≈ Steadfast、水下 ≈ Solas、整体色调 ≈ Refrax**（SC-24：用户 2026-09-06 更正，与最初表述方向相反）
- **平台**：Iris 专用，MC 1.21.x + 26.1/26.2，远景仅 Voxy
- **硬指标（已被现目标取代）**：RTX 4050 @1080p 流畅/均衡/极致 ≥ 144/90/60 FPS；下界/末地一等公民特调且同标准。现目标为原生1080p、平均至少144 FPS、95%常规帧不超过6.94 ms，见 [当前工作](../../docs/当前工作.md)；三档分档不再是验收口径
- **边界**：v1 不做 PBR/体积云/彩光/GI/TAA/DH（v2+ 候选见 §11）。**其中 TAA、体积雾与彩光此后已实施**，本节只记录 v1 当时的设计排除范围

## 1. 项目定位

**Astra**（拉丁语：星辰）是一个 **Iris 专用** Minecraft Java 版光影包，设计哲学为 **"清爽原味 + 性能"**：不抢戏、快、细节克制，但在水、大气、色彩科学上达到一线水准。

### 1.1 效果标杆（用户指定）

| 维度 | 对标 | 取材方式 |
|---|---|---|
| 整体风格 / 色彩 | **Refrax** | 学习其色彩分级思路、空气透视、氛围营造；参数与代码按我们的管线重写（专有许可，见 §9） |
| 性能 / **水面效果** | **Steadfast** | 渲染内核与水面波形（解析导数程序波浪、Nyquist 受限、自适应视差）直接借鉴（GPLv3，个人使用无碍） |
| **水下效果** | **Solas** | 水下雾/吸收/焦散的观感对标其实现（无许可声明，个人使用无碍，见 §9） |
| 工程骨架 | **Mellow** | 四层目录结构、命名规范、设置 GUI、维度壳、Voxy 层（MIT） |

### 1.2 平台与硬件基线

- **加载器**：Iris 专用（不写 OptiFine 兼容分支，不写 `IS_IRIS` 回退）。功能可假定 Iris 特性存在：custom uniforms、`voxy.json`、`renderStage` 等。
- **MC 版本矩阵**：1.21.x（含 1.21.4/1.21.5 方块集）+ **26.1 / 26.2**（新版本号体系）。用 `MC_VERSION` 守卫处理版本差异（参考 Mellow 的 `12104`/`12109`/`260100` 阶梯）。
- **硬件基准**：RTX 4050 Laptop（6GB VRAM），带宽预算按移动级显存设计。性能目标（1080p）：**流畅档 ≥144 / 均衡档 ≥90 / 极致档 ≥60 FPS**（森林/村庄/水下典型场景）——**此三档分档已被现目标取代**（原生1080p、平均至少144 FPS、95%常规帧不超过6.94 ms），见 [当前工作](../../docs/当前工作.md)。默认均衡档刻意轻量：godrays 默认关，所有可选 pass 均可按 `program.enabled` 整体卸载。
- **远景模组**：**仅 Voxy**（不做 Distant Horizons）。

### 1.3 命名

`Astra` 在 Modrinth 无同名光影（已核查）；需注意与高下载量的 AstraLex（BSL 编辑版）区分，发布物描述中须避免简称混淆。此为品牌层面备注，不阻塞开发。

---

## 2. 架构总览

### 2.1 渲染路线：极简前向（Forward），零 compute

沿用 Steadfast 路线：**全部主光照在 gbuffers 阶段一次算完**，无 G-buffer 维护成本、无 compute shader、无 TAA。后处理只保留"便宜且必要"的少数 pass。这是与"清爽原味 + 性能"最匹配的形态，也使代码量可控（对标 Steadfast 的 109 文件 / 8.6k 行）。

### 2.2 Pass 链（主世界）

```
shadow ──► gbuffers_*（前向光照，单一 lit 入口）──► composite（godrays，可选）
                                                     │
        deferred（copy_and_fog，仅水效果开启时）──────┤
                                                     ▼
        composite1（bloom 采集，可选）──► final（bloom 合成 + tonemap + 调色 + 抖动）
```

| Pass | 职责 | 启用条件 |
|---|---|---|
| `shadow` | 单级 shadow map；`shadowcolor0` 的 R 通道编码水面高度（供水下焦散反推水深），GBA 通道存半透明染色 | 常驻 |
| `gbuffers_*` | 全部受光几何，include 统一实现（见 §3.2）；天空/云/无光体独立入口 | 常驻 |
| `composite` | 半分辨率空气 godray 密度；水下沿视线累计阴影散射（SC-33） | `GODRAYS` 或 `UNDERWATER_LIGHT_SHAFTS && SHADOWS && UNDERWATER_SHAFT_STRENGTH > 0` |
| `deferred` | 复制未施加介质的 colortex0→colortex4（作 SSR/折射背景源），对 colortex0 不透明场景施加吸收与雾 | `SCREENSPACE_REFLECTIONS \|\| SCREENSPACE_REFRACTION \|\| WATER_ABSORPTION > 0` |
| `composite1` | bloom 采集：半分辨率缓冲 + mipmap 多级采样 | `program.enabled=BLOOM` |
| `final` | godray 平滑 + 上采样、bloom 合成、水下颗粒、exposure、tonemap、sRGB、色彩分级、输出抖动 | 常驻 |

下界/末地走同一套 `program/` 实现（维度壳注入宏），裁剪日光相关特性（见 §4.5）。

> **决议（SC-4，E 系，2026-09-05）：维度上下文只由目录注入。** Iris 无可靠的"当前维度"uniform，根层 `shaders/gbuffers_*` 是任何缺少 `world*/` 覆盖的维度的默认实现——所以维度信息只能从目录进来。据此：根层 = 维度中立实现（主世界语义是其默认值），`world-1/` 注入 `DIMENSION_NETHER`、`world1/` 注入 `DIMENSION_END`，**不建 `world0/`**。实测范式：Refrax v1.3.1 根层 86 个程序（含 42 个 `gbuffers_*`）+ 仅 `world-1/`、`world1/`，Solas V2.2b 同形（58 / 28），两者都没有 `world0/` 也没有 `dimension.properties`。因本表的维度裁剪与 §4.5 的光照路径重构落在几何阶段，`world-1/`、`world1/` **必须同时提供 `gbuffers_*` 覆盖壳**（现各 5 对 post/shadow 壳不足以支撑 §4.5）。
> **决议（SC-3，E 系，2026-09-05）：v1 不引入 `world_modded/` 与 `dimension.properties`。** 模组/自定义维度继承根层链、按主世界语义渲染（Refrax、Solas 的实际行为即如此，无需额外目录）。"模组维度专用壳"移入 §11 v2 候选；M4 的 README 须把这条边界写成一行已知限制。
> **决议（SC-9，E 系，2026-09-05）：占位期"可编译"不等于"可显示"。** 见 §7 M1 注。

### 2.3 缓冲区布局（格式目标受 SC-27 默认格式决议约束）

**最新四图续修更正（2026-09-08）：下文历史中“shadow 前恢复 gbufferModelViewInverse[3] 的 T”全部作废。** 实例 Iris ShadowRenderer 直接给 Sodium 独立的 shadow MODELVIEW；Sodium region offset 已减完整相机位置。shadow 生成端还原的点、所有接收端输入均为真正相机相对世界坐标，禁止再混入主相机逆矩阵平移。主相机视空间还原继续只用旋转。水色当前分工为：空气侧界面到床面的艺术化透射负责青色，入水照明/水下相机体积负责较清澈的偏蓝传播；水中散射与床面焦散共用 water_sun_focus。详见 `docs/2026-09-08-four-image-coordinate-repair.md`。

**2026-09-08 最新六图退回后的实际路径（优先于下方历史记录）：** shadow → opaque gbuffers → deferred → translucent gbuffers → composite（水体状态）→ composite1（可选 bloom）→ composite2（可选散射）→ final。水下散射开启时 colortex1 为全分辨率，编码距离上限 96 格，final 精确读取对应像素。水体状态也被地形照明与焦散消费，因此不随光束选项关闭。主世界新增以下两项，继续使用 Iris 默认 RGBA8：

| 缓冲 | 尺寸 | 写入 / 读取约定 |
|---|---|---|
| colortex5 | 全分辨率 | gbuffers_water 写水平水面的世界高度 RG（16-bit，1/16 格）、B 天空光、A 有效性；每帧清零，非水片元 A=0 保留已有水面标记。 |
| colortex6 | **1×1 像素** | composite 从可见水面选最近局部界面；RG/B/A 同上。不逐帧清除；看不到界面时保留已观察到的水高。composite2 读本帧状态，opaque 照明/焦散读上一帧。整数尺寸已用实例 Iris TextureScaleOverride 类确认。 |

阴影投影物改用 `shadow.culling=false` 的距离裁剪，`shadowDistanceRenderMul=1.5`；接收端 SHADOW_DISTANCE 与原有渐隐保持。状态尚无有效界面时保留阴影水高回退；首帧在水下且两个来源均不可见时仍无法确定水柱高度。这是已知限制，不能据源码与编译认定视觉通过。

**决议：E1/E2（2026-09-05）冻结实际顺序为 shadow → opaque gbuffers → deferred（可选）→ translucent gbuffers → composite（可选）→ composite1（可选）→ final。** deferred 在半透明之前运行，不可在它里面读取本帧水面法线或水面深度。开启副本时，不透明 lit 输出未施加介质的 HDR，deferred 同时写 colortex4 原色副本与 colortex0 已吸收/雾化场景；半透明 lit 随后自行施加一次介质。关闭副本时，lit 直接施加介质。防止水面采样已雾化背景后再雾化一次。水面在后续 gbuffers_water 采副本与 depthtex1；禁止采正在写入的 colortex0。启用条件为 `SCREENSPACE_REFLECTIONS || SCREENSPACE_REFRACTION || WATER_ABSORPTION > 0`，各维度分别声明。新增 `gbuffers_block_translucent` 与 `gbuffers_particles_translucent` 两对几何壳保证这些几何在副本之后绘制；其余后处理 pass 数不变。依据：[Iris deferred](https://shaders.properties/current/reference/programs/deferred/)、[Iris gbuffers](https://shaders.properties/current/reference/programs/gbuffers/)。旧图仅表示依赖，执行时序以本条为准。

**决议：E1/E2 缓冲用途冻结。** 保持本节六种格式；colortex3 只由不透明 lit 写 skylight+HAND标识（见后续R8位域决议），透明/天空/无光体只写 colortex0；colortex3 每帧清为127/255。colortex4 为尚未施加介质的线性 HDR 不透明副本，仅 deferred 写（RENDERTARGETS:0,4）；关闭 deferred 时消费者必须编译裁剪，不以关闭 pass 推断显存一定释放。colortex0 每帧清零；shadowcolor0 清为 `vec4(1)`，R=1 为无水哨兵，水高度编码仍用 B1 的 UNORM16 映射 `0.5 - worldY / 2048`（原表“SNORM”指语义映射，并非纹理格式）；GBA 存线性染色，shadow 禁止混合。水面高度只接收朝上水面，绝对 Y=shadow 逆变换后 Y−gbufferModelViewInverse[3].y+cameraPosition.y。普通 shadow 坐标接受 camera-relative playerPos，进入 shadowModelView 前只加 gbufferModelViewInverse[3].xyz，禁止加绝对 cameraPosition。B1 按此修正现有生产者/消费者；不重写阴影算法。

| 缓冲 | 格式 | 尺寸 | 用途 |
|---|---|---|---|
| colortex0 | R11F_G11F_B10F | 1x | 主 HDR 场景色（32-bit，无 alpha——前向混合永远画在不透明背景上） |
| colortex1 | RGBA8（沿用 Iris 默认，SC-33） | 0.5x | 空气：R 为 godray 密度；水下：RGB 为平方根编码散射色，A 为 0–48 格视线距离 |
| colortex2 | R11F_G11F_B10F | 0.5x | bloom 采集缓冲（靠 mipmap 提供多级亮度） |
| colortex3 | R8 | 1x | skylight 存储（水下吸收启发式 + 静态阴影回退用） |
| colortex4 | R11F_G11F_B10F | 1x | 不透明场景副本（SSR/折射背景源，仅水效果开启时存在） |
| shadowcolor0 | RGBA16 | shadow res | R 通道：水面高度（SNORM 编码，焦散反推水深）；GBA 通道：彩色阴影染色 |

> **决议（随 SC-10）：格式声明集中在一处且必须是活代码。** `const int colortexNFormat` 只有在 Iris 实际编译到的 include 闭包里才生效，写在注释块内等于没声明（现状：本表 6 条格式全部位于 `program/final.fsh` 的 `/* */` 内，§2.3 未落地）。取 Mellow 的单点范式——全部格式声明放在 `lib/settings.glsl` 的 ENGINE KNOBS 块，随 §3.2 决议的分层对全 pass 生效。参照实测：Mellow 集中在 `global/configurations.glsl:20-25`，Solas 集中在 `program/final.glsl:12-19`，Steadfast 拆给各写入方（`post/copy_and_fog.fsh` 等），三种都能用，本包选集中式。

> **决议（随 SC-25/SC-26，推翻 SC-10 的实施位置，2026-09-06）：格式 const 必须声明在入口壳内，禁止放 lib/program 等任何 include 层。** 实机四、五轮实证：Iris 1.11.2 会从 include 展开源**读取** const（ClearColor 等已生效）但**只改写它直接编译的入口壳文本**中的格式令牌——lib（第四轮 C1503）与 program（第五轮 C1503）层级均原样漏到驱动。关键反证：唯一采用 lib 集中式的 Mellow，其发布版把格式声明整块注释掉、靠 Iris 默认格式运行。现 6 条格式声明位于 root/world-1/world1 的 final.fsh 入口壳（final 永远参与编译），无行尾注释。附带（SC-26）：实例装有 Voxy 时 Iris 定义 `VOXY` 宏，`lib/uniforms.glsl` 已补 `vxModelView/vxModelViewInv` 声明。

> **决议（随 SC-27，再推翻上两条，2026-09-06）：v1 全线使用 Iris 默认缓冲格式，格式 const 一律注释。** 决定性对照：本 Iris（1.11.2+mc26.2）上实际可用的 Complementary r5.8.1，其格式声明整块被注释；Mellow 发布版同样——五个参照包零反例，任何位置的活跃格式 const 都会 C1503。§2.3 表格保留为设计意图（带宽目标），恢复格式声明的机制待查（roadmap）；短期代价：HDR 精度与带宽回归默认，`shadowcolor0` 水面高度编码精度下降待实机确认。noise 纹理改走 `textures/noise.png` 自动绑定（删除全部 `texture.*.noisetex` 指令——本版 Iris 对 composite1/final 等阶段名报 Unknown texture stage）。

> **修订（2026-09-26 追认，取代上条"一律注释"）：SC-27 的"格式 const 一律注释"经 2026-09-10 复核为误诊。** 现行 operative 规则见 `qa/tools/check_pack.py:830-834`：缓冲区名称合法（colortexN / shadowcolorN / depthtexN）、值为整数或全大写引擎 token、每缓冲唯一声明、声明由 `#ifndef` 守卫。§2.3 表格的默认格式目标与 SC-33 关于 colortex1 保留 RGBA 的结论不受影响；已获追认的两个活跃实例（`global/post/exposure.glsl:31` 的 `colortex10Format = RGBA32F`、`program/shadow.fsh:34` 的 `shadowcolor0Format = RGBA16F`）记于 `escalations.md`（2026-09-26）。

**决议：E1/E2（SC-32，2026-09-07）水下颗粒从 deferred 移到 final 的显示合成。** 半透明水面在背景重建分支输出 alpha=1，会覆盖 deferred 内的颗粒；颗粒因此必须在半透明完成后、tonemap 前叠加。final 用现有 depthtex0 的最近可见表面约束颗粒距离，不写 colortex4；deferred 启用条件与 ASTRA_SCENE_COPY 保持一致，仅由 SSR/折射/吸收决定，UNDERWATER_PARTICLES 不强开副本。不增加 pass、缓冲、varying，默认格式仍按 SC-27；显示端新增一次水下深度读取，三层颗粒计算移位而非重复执行。

**决议：E1/E2（SC-33，2026-09-07）水下光束复用 composite 与 colortex1。** 根层 composite 由空气光束或有效的水下光束选项启用，条件在 shaders.properties 预处理后写成 true/false；下界/末地仍禁用。水下输出 RGB=`sqrt(scatter/4)`、A=`min(rayLength,48)/48`；final 以四邻域、距离权重重建，解码后加到 HDR，再叠颗粒与既有显示链。colortex1 不再可降为 R8，必须保留 RGBA；SC-27 默认格式路线保持，不增加活跃格式 const、pass 或几何 varying。关闭彩色阴影和焦散不影响水下光束独立读取 shadowtex1/shadowcolor0。

### 2.4 抗锯齿决定：无 AA pass（架构级）

**决议：E1（2026-09-06）colortex3 的 R8 负载定为低7bit skylight、高1bit HAND 投影标识。** 低7bit按 round(skylight×127)量化；HAND加128后除255写入。清为127/255，deferred必须texelFetch、round还原后拆位，不允许对标志双线性插值；HAND先在NDC除MC_HAND_DEPTH再重建。其余用途仍为skylight，不加缓冲或varying。该位解决手部在deferred再次重建时丢失压深信息的问题。

- 不设 TAA/FXAA/SMAA 任何 AA pass。
- 高频闪烁在**源头**消除：水面波采用 Nyquist 频率受限的波形（解析导数 + 屏幕像素足迹驱动的细节衰减，Steadfast 方法），远处自动降低法线细节并提升 roughness。
- 面板抖动：输出用 IGN/Bayer 抖动抑制 banding；Voxy/远景过渡用抖动 stipple 淡入淡出。
- 折射/SSR 命中用 `textureGather` min/max 深度拒绝，避免无 TAA 下的边缘噪声。

---

## 3. 工程结构

### 3.1 目录（Mellow 四层范式）

```
Astra/
├── shaders/
│   ├── lib/                      # 基础层：无依赖或低依赖工具
│   │   ├── settings.glsl         # 全部用户选项（唯一来源）
│   │   ├── uniforms.glsl         # 统一 uniform 声明（含 custom uniforms）
│   │   ├── colors.glsl           # 调色板 / 光色常量
│   │   ├── encoding.glsl         # 八面体法线、逐面打包、sRGB
│   │   ├── transforms.glsl       # 空间变换宏/函数
│   │   ├── distort.glsl          # shadow扭曲
│   │   ├── noise.glsl, bayer.glsl, dither.glsl
│   │   └── tonemap.glsl          # 多算子（Uchimura/AgX/ACES/Reinhard-Jodie，自 Mellow 移植）
│   ├── global/                   # 功能模块层（按需 include）
│   │   ├── lighting/  (diffuse.glsl, shadowmap.glsl, blocklight.glsl, sss.glsl, wind.glsl)
│   │   ├── atmosphere/(sky_minishita.glsl, sky_gradient.glsl, fog.glsl, stars.glsl, clouds_planar.glsl)
│   │   ├── water/     (surface.glsl, raytrace.glsl, refraction.glsl, absorption.glsl, caustics.glsl)
│   │   ├── post/      (godrays.glsl, bloom.glsl, grading.glsl)
│   │   └── dimension/ (overworld.glsl, nether.glsl, end.glsl)   # 各维度天空/雾/光色
│   ├── program/                  # pass 实现（薄）
│   │   ├── lit.fsh / lit.vsh     # 所有受光几何唯一入口（宏变体：TERRAIN/ENTITY/HAND/WATER/WEATHER…）
│   │   ├── lit_voxy.fsh          # Voxy 入口（GLSL 460 core，voxy_emitFragment）
│   │   ├── unlit.fsh, sky.fsh, clouds.fsh
│   │   ├── shadow.fsh / shadow.vsh
│   │   ├── composite.fsh, deferred.fsh, composite1.fsh, final.fsh（+各自 vsh）
│   ├── world-1/ world1/          # 维度壳：#version + 维度宏 + include program/（根层即主世界，无 world0/，见 §2.2）
│   ├── gbuffers_*.fsh/vsh …      # 顶层薄包装：#version + 变体宏 + include program/lit（维度壳另需覆盖）
│   ├── voxy.json + voxy_opaque.glsl + voxy_translucent.glsl
│   ├── shaders.properties / block.properties / entity.properties
│   ├── lang/ (en_US.lang, zh_CN.lang)
│   └── tex/ (noise.png 最小噪声资源)
├── LICENSE（暂定：个人使用；发布前重新决定，见 §9）
├── THIRD-PARTY.md                # 逐模块出处与许可台账（§9.2）
└── README.md
```

### 3.2 命名与代码规范（沿用 Mellow 约定）

- uniform = `camelCase`；函数 = `snake_case`；类型/结构体 = `PascalCase`；宏常量 = `UPPER_SNAKE`
- GLSL 版本：主体 `#version 400 compatibility`（含 textureGather/派生函数，免扩展检测舞蹈）；`lit_voxy` 等核心态文件用 `#version 460 core`
- 每个被 include 的模块带 include guard；文件头一行注释声明依赖的 uniform（Steadfast 的 `// Uniforms: none` 习惯）
- 借用代码文件头注明来源包与许可（格式见 §9.2）
- 注释写"为什么"，不写"做了什么"；非平凡算法附出处链接（对齐 Steadfast 水准）

**决议（SC-10，E 系，2026-09-05）：include 分层协议（三层，禁止在薄包装里盲插 lib）。**

1. **顶层 `gbuffers_*` 与 `world*/*` 壳**：只有 `#version` + 变体/维度宏 + `#include "/program/X"`，不碰 lib——壳的全部价值就是"只注入宏"。
2. **`program/*`**：`lib` 的唯一入口。顺序固定为 `/lib/settings.glsl` → `/lib/uniforms.glsl` → 本 pass 所需的 `global/*`。用户选项在 GPU 侧可达 ⟺ 有 program include 了 settings.glsl。
3. **`global/*`**：只 include `lib/*`，不得反向依赖 `program/*`。

由此"模块可达性"的判据从"全模块零 orphan"改为：**被消费的模块零 orphan + 每个编译入口的 include 闭包含 `lib/settings.glsl`**。消费者任务尚未开工的 `global/*`（如 `water/*` 之于 C2）在其里程碑前只报 WARN，不阻塞。校验器（`qa/tools/check_pack.py` 第 4 项）按此改造，接线实现随 E1 的 lit/final 链一并交付。

**决议：E1（SC-4/10/18，2026-09-05）几何接口与壳清单冻结。** 所有壳为 `#version 400 compatibility`、宏、include program；根层没有 DIMENSION 宏，world-1/world1 分别追加 DIMENSION_NETHER/DIMENSION_END，完整覆盖下面 20 对 gbuffers，禁止部分覆盖。共享顶点入口为 program/lit.vsh；受光 FS 为 program/lit.fsh，无光为 unlit.fsh，天空为 sky.fsh，云为 clouds.fsh。Z1 执行壳生成，不改模块本体。

| gbuffers 后缀 | 宏（ASTRA_ 前缀） | FS |
|---|---|---|
| terrain | TERRAIN | lit |
| water | TERRAIN, TRANSLUCENT, WATER_PASS | lit |
| entities / entities_translucent | ENTITY / ENTITY, TRANSLUCENT | lit |
| block / block_translucent | BLOCK / BLOCK, TRANSLUCENT | lit |
| hand / hand_water | HAND / HAND, TRANSLUCENT | lit |
| textured_lit / particles_translucent | PARTICLE / PARTICLE, TRANSLUCENT | lit |
| weather | WEATHER, TRANSLUCENT | lit |
| basic | BASIC, UNLIT | unlit |
| textured | UNLIT | unlit |
| damagedblock | TERRAIN, UNLIT, DAMAGED | unlit |
| armor_glint | UNLIT, GLINT | unlit |
| spidereyes | UNLIT, EYES | unlit |
| beaconbeam | UNLIT, BEAM, TRANSLUCENT | unlit |
| skybasic / skytextured | SKY / SKY, SKY_TEXTURED | sky |
| clouds | CLOUDS, TRANSLUCENT | clouds |

| varying | 插值 | 标量数 | 语义 |
|---|---|---:|---|
| vec2 texcoord | smooth | 2 | atlas UV |
| vec2 lightcoord | smooth | 2 | lightmap 原始 0..1，FS 映射为等级 0..1 |
| vec4 tint | smooth | 4 | sRGB 顶点染色与 alpha/AO（保持原版 AO） |
| uint faceData | flat | 1 | normal oct Y bits 0–8，oct X bits 9–17，material bits 18–21，预留 bits 22–31 清零 |
| **上限** | | **9（36 B/vertex 逻辑载荷，4 个声明）** | 无位置/切线/shadowPos varying；这是接口预算，不是驱动实际寄存器数 |

**决议：E1 逐面“9-bit”指每轴 9 bit，共 18 bit，18+4+10=32。** normal 为 world 方向；材质 0=普通，1=水，2=叶，3=无方向植物，4/5/6=小/双层下/双层上植物，7=portal，8=透明玻璃，9=冰，10=发光体，其余保留。VS 按 block/entity ID 映射；FS 从 gl_FragCoord.xy/viewSize 与深度重建 viewPos，HAND 在 NDC z 除 MC_HAND_DEPTH 后重建；camera-relative playerPos=mat3(gbufferModelViewInverse)*viewPos。禁止以顶点世界绝对位置乘 shadowModelView。宏不互相推断 ENTITY/BLOCK/HAND 的材质 uniform；各变体显式取 entityId/blockEntityId/currentRenderedItemId。

**决议：E1 的 program 组合顺序冻结为 settings→uniforms→lib 工具→shadowmap/blocklight/sss/diffuse→维度模块→大气模块→水模块。** 新增 program/scene.glsl 作为 program 内共用组合器，global 不 include 其他 global；对外函数 `astra_light(albedo, normal, playerPos, skylight, blocklight, material)`、`astra_fog(playerPos, skylight)`（RGB 雾色，A 雾量）、`astra_sky(worldDir)`（线性 HDR）。D2 提供 `astra_sky_radiance(vec3 worldDir)`、`astra_sky_reflection(vec3 worldDir,float roughness)`、`astra_sky_ambient()`、`astra_direct_light()`，均线性 HDR、无 tonemap、无 varying；天空反射接口不含太阳/月亮圆盘，避免 SSR 失败时高亮点闪烁。E1 先交可显示接线，D2 在此接口上替换主世界临时天空，不改 varying/pass。

**决议：E1（SC-32，2026-09-07）原生几何与 Voxy 的变换宏分离。** Iris 的 VOXY 表示模组可用，不表示当前程序属于 Voxy。只有显式 ASTRA_VOXY_PASS 入口可声明并消费 vxModelView/vxModelViewInv；所有原生 gbuffers/deferred/final 固定使用 gbufferModelView 体系，即使 VOXY 已定义。C5 后续实际入口按此协议接入；本次不注册尚未实现的 Voxy patch，VOXY_SUPPORT 的未接线状态不靠空引用掩盖。

### 3.3 设置系统

- 规模目标：**60–80 个用户选项**（清爽哲学：少而精；对比 Mellow 205 / Refrax 542）
- GUI 主屏 7 分类：`光照 / 阴影 / 天空 / 水 / 雾 / 后处理 / 性能+高级`；每个选项配一句 `.comment` 说明（Refrax 的用户引导文化）
- **Profile 四档**：`PERFORMANCE（流畅）/ BALANCED（均衡，默认）/ ULTRA（极致）/ NO_SHADOWS（无实时阴影）`。前三档为画质阶梯，NO_SHADOWS 另行关闭 shadow 阶段。四档均为完整显式配置，具体值以 `shaders.properties` 为准。
- 语言：`zh_CN`（主）+ `en_US`；zh_CN 保留性能影响标注习惯（Mellow 风格）

---

## 4. 功能规格（v1 基础盘）

### 4.1 光照（global/lighting/）

| 项 | 设计 | 来源 |
|---|---|---|
| 直射光 | Lambert + 自适应 normal-offset bias（sampler2DShadow 硬件 PCF + 4-tap 软化，≤16 texel） | Steadfast |
| 环境光 | 仿原版方向性环境光 `(0.67+0.33·Ny)`、skylight 立方衰减、minAmbient 洞穴底色 | Steadfast |
| 方块光 | `pow⁴` 衰减 + **日光压制**（blocklightSuppression：日光越强方块光越弱）——本行原写"替代自动曝光"，SC-41（2026-09-21）已推翻该排他论断：压制是**光照项**、自动曝光是**显示增益**，二者不同轴且可并存；本机制与出厂状态均不变 | Steadfast |
| 彩色阴影 | shadowcolor0 染色（**染色玻璃/水/染色板投彩色影；透明玻璃不投影**） | Steadfast |
| 静态阴影回退 | 影距外用 skylight 阈值近似（`smoothstep(13.5/15, 14.5/15)`），5–10 格交叉淡化 | Steadfast（源自 Photon） |
| SSS | 叶子/植被经验近似：影内固定 0.7071 直射 + 前向散射提升 | Steadfast |
| 手持光 | 动态手持光源，可调强度 | Steadfast |
| 闪电 | `lightningBoltPosition` 点光源 + 天空辉光（廉价、效果好） | Steadfast/Solas |
| 植被摇曳 | 顶点位移式温和摇曳（树叶/作物/植物，风参数 custom uniform CPU 预算）；默认开、可关；不做风场纹理/交互形变 | Steadfast（`WaveFoliage` 模式） |

**决议（SC-13，E 系，2026-09-05）：阴影引擎旋钮语义定死三条，执行归 B1。**

- 实体影锥的距离乘链为 `shadowDistance * shadowDistanceRenderMul * entityShadowDistanceMul`。当前 render multiplier 为 1.5，设置文件的字面量表预先除去该因子；PERFORMANCE、BALANCED、ULTRA 的名义实体影距分别为 48、64、96 格。NO_SHADOWS 使用流畅档参数但关闭阴影阶段。Iris 1.11.2 的调用关系见 `qa/open-premises.md` P-2。
- `SHADOW_SOFTNESS` 控制核宽；三个画质档的值为 2/2/8，NO_SHADOWS 为 2。采样数不随该选项改变。
- `SHADOW_FILTER_MODE` 默认软件比较；硬件模式使用逐纹素比较 gather，保留颜色与深度的对应。`shadowHardwareFiltering` 随选项取字面量，不固定为 true。

### 4.2 天空与大气（global/atmosphere/）

| 项 | 设计 | 来源 |
|---|---|---|
| 天空 | **Minishita** 迷你物理大气（2 视采样 + 1 光采样，Cornette-Shanks Mie，≈200 FLOPs）；备选简单渐变模式 | Steadfast |
| 日月 | 默认原版日月纹理直通；可选程序圆日圆月（关闭原版贴图） | Mellow 思路 |
| 星星 | 立方体面 cell-hash 网格，微闪烁；`v stars` 无银河贴图 | Steadfast/Solas |
| 雾 | FogV2 模型：大气雾 `pow(d,3)`（系数 CPU 预算）+ 边界雾 + 洞穴雾切换 + 失明/熔岩/水下特例；`skyFogStrength` 低时跳过天空色计算 | Steadfast |
| 空气透视 | 雾色随视向-太阳夹角偏移（晨昏地平线染色）——Refrax 风格的廉价实现点 | Refrax 思路，自实现 |
| 生物群系 | 雾/环境光带轻微 biome tint（custom uniform 平滑温度/湿度） | Refrax 思路，自实现 |
| 云 | 默认：原版云直通+调色；可选项：平面 wispy 云（噪声多层，极便宜） | Mellow |
| 云影 | 已落地为 `CLOUD_SHADOWS` 选项（2026-09-21 T14 `3d13037`，本行原写"v1 不做"是腐烂）：复用出厂既有的单平面云密度场 `astra_cloud_transmission` 沿光向投到地面，2D 廉价形态而非 Refrax 3-slab；三档一律 `!`，强度与掠射淡出待实机 | BSL / Complementary Reimagined 思路 |

**决议（SC-12，E 系，2026-09-05）：平面 wispy 云实现归 D2。** 云与 Minishita 天空/日月/星星共用同一条大气链（视向、太阳角、雾混合全在同一处），拆给两档会产出两套接口；`global/atmosphere/clouds_planar.glsl` 与 `program/clouds.fsh` 的消费者由 D2 任务行确立。`CLOUD_MODE` 保持 0/1/2 三档不砍。

**决议：E1/D2（SC-32，2026-09-07）主世界远端户外雾直接消费 astra_sky_radiance 的同视向颜色。** 不再用混入环境色的粗糙反射接口代替天空背景。两采样 Minishita 在掠射/负仰角的积分会过度消耗蓝色，最低积分仰角固定为 sin(elevation)=0.10，保留方位角向地平线及下半球延伸；这是低采样大气近似，不是新加一道染色。群系色仅保留在薄雾，完全雾化端回归该天空色；反射也共享修正后的大气源。保留两次视路径采样，不增加大气 pass。

### 4.3 水（global/water/）——v1 视觉核心

| 项 | 设计 | 来源 |
|---|---|---|
| **水面** | **解析导数程序波浪 + Nyquist 比率受限 + 4 步自适应视差**（Steadfast `environment/water/` 方案——解析导数省一半 ALU、按屏幕像素足迹抑制超 Nyquist 波层抬 roughness，无 TAA 下不闪） | **Steadfast（SC-24 更正后为水面主对标）** |
| SSR | 水面/冰**顶面**专属：固定起点 20 粗步 + 4 细化；`textureGather` 深度拒绝；失败回退解析天空反射（Minishita 反射色） | Steadfast |
| 折射 | 屏幕空间法线扰动偏移（Solas composite 手法）；深度拒绝防误采 | Solas（SC-24） |
| 水下吸收 | Solas waterFog 观感对标：雾色随深度/天光渐变、吸收曲线使其"清而不灰" | Solas（SC-24） |
| 焦散 | Solas waterCaustics 观感对标：噪声高度差分焦散、随阴影投射 | Solas（SC-24） |
| 水下氛围 | Solas 水下雾色/氛围（含下界熔岩雾联动的独立处理） | Solas（SC-24） |
| 半透明 | 预乘 alpha 混合（`FANCY_TRANSLUCENTS`：blend `ONE, ONE_MINUS_SRC_ALPHA`），支持反射/折射混合自由度 | Steadfast |

**决议（SC-24，用户更正，2026-09-06）：水效果对标方向对调——水面 = Steadfast、水下 = Solas**（用户澄清最初"Steadfast 水下最漂亮、Solas 水面最漂亮"是记反了）。工程含义：C2（水下三件套）与 C7（水面/SSR）的**参考源对调重写模块本体**，接口/接线/E2 总成不变；SSR 射线追踪与预乘 alpha 仍为 Steadfast 基础设施（它们是管线件而非观感件）。§8.3 验收判据同步对调。

**决议（SC-1，E 系追认，2026-09-05）：`WATER_ABSORPTION` 为 0–100 滑条，0 = 关。** 不引入 OFF/LOW/HIGH 枚举：吸收强度本就是连续量，三档水性格（`waterCharacter`）已经承担"分类"职责，再叠一层枚举会让同一效果有两个互相打架的控制点。deferred 的启用条件据同一决议写为 `WATER_ABSORPTION > 0`（§2.2 已同步）。

**决议：E2（SC-15，2026-09-06）将 surface/raytrace 的独立实现下放 C7，E2 只消费与集成。** 不采原上报把模块本体全部抬到 E2 的推荐。新增 C7 归高级Ⅱ，不增用户选项；surface 返回 world normal+roughness，SSR 返回线性 RGB+confidence，失败 confidence=0，交由 D2 无圆盘/星点反射色回退。波导数在片元 alpha 拒绝前求值；屏幕足迹连续抑制超过 Nyquist 的波层并抬 roughness；SSR 使用固定空间起点、20粗步（步距最多2倍增长）+4细化、gather深度跨度拒绝，禁止帧号抖动。

**决议：E2 深度与混合契约。** C2 的吸收系数来自 normalized depth，不是每格系数：E2 将水程除32并夹0..1后调用 water_absorption。水上水程取水面到折射背景，天空无深度取32格上限；水下过界面的水程取相机到水面。raw colortex4 从不重复施加吸收。折射/吸收开启时水面已组装背景+透射+反射，输出 alpha=1，避免把同一背景再混一次；普通透明材质/关闭背景重建的水走纹理 alpha，FANCY_TRANSLUCENTS 时 RGB 预乘，blend=ONE/ONE_MINUS_SRC_ALPHA，否则普通直通 alpha。冰只在顶面反射：gbuffers_water 的透明冰可 SSR；在 deferred 前绘制的不透明冰使用解析天空回退，不增加几何数据缓冲或后处理 pass。多层半透明互相反射不在本次不透明副本契约内。

**决议：E1/D2 平面云由 skybasic 的天空函数合成，CLOUD_MODE=1 时 gbuffers_clouds 丢弃原版云几何。** 避免用原版云网格裁剪 wispy 图案；不增加 pass/varying。日月仍由 skytextured 的 renderStage 分流；下界/末地不调用主世界大气、云、日月及 godrays。SKYLIGHT_STRENGTH 只在 C1 乘一次，D2 返回未乘选项的调色值。

**决议：E2（2026-09-06）焦散同属无TAA约束。** C2保留crest算法，接受E1在alpha拒绝前计算的world blocks/pixel足迹，按最短波长连续衰减高频贡献，未解析时回到中性；48–64格连续退出。shadow VS逆变换后的点先减gbufferModelViewInverse[3].xyz转换到统一camera-relative坐标，再取绝对水高和风场；重新进入shadowModelView前加回该偏移。不得把脚部相对点和相机相对点混用。

**决议：E2（SC-32，2026-09-07）折射边缘回接必须混合完整光路。** 未偏移与折射背景分别按各自深度计算吸收/雾色，再按相对亮度连续权重混合；禁止只恢复 RGB 却沿用另一条光路的水程。水面视差与法线共用 0.15×WATER_WAVE_HEIGHT 的高度尺度，掠射夹取使用单位视向，最终波层足迹包含视差放大。SSR 的 28–96 格与 roughness 0.10–0.28 淡出保持连续，权重已为零时不再执行追踪。公开五模块接口与既有 20+4 追踪预算不变。

**决议：E2（SC-32，2026-09-07）水下颗粒采用世界坐标晶格，final 为唯一消费者。** 三个视距壳层（3/6/12 格）仍是稀疏近似；每个颗粒的完整柔边限制在 cell 内，几何遮挡边缘连续淡出，时间由参数传入。该改动减少随镜头漂移和 cell 边缘跳变，不据此宣称动态无闪烁已通过。

SC-32 水面细节补充：未解析波层的 roughness 采用与波相位无关的平均坡度估计；禁止把被 Nyquist 过滤掉的高频梯度幅值重新混入粗糙度，否则会经反射把同一高频变化带回画面。该估计是源头抑制措施，不构成实机稳定性结论。

**决议：E2（SC-33，2026-09-07）以有遮挡的水下散射替换 scene.glsl 的角向亮晕。** 新增 global/water/light_shafts.glsl，参考本地 Solas volumetricLight 的视线累计阴影思路，积分权重、宽尺度水面聚光与深度重建由 Astra 自写。每条视线只积分至最近 depthtex0 表面或 48 格，三档为 16/24/32 段；shadowtex1 阻止实体漏光，shadowtex0 与 shadowcolor0.R 确认光线经过水面，沿光线投影的低频水面图案调制强度。水高只用于图案锚点与光程衰减，不作精确水面裁剪；默认格式的量化误差仍需画面确认。固定空间 Bayer 起点，无帧号抖动；光源离屏仍可散射，日落、雨天与失明连续减弱。默认三档开启水下阳光束，新增独立开关、强度与精细度，沿用 WATER_CHARACTER 和既有水下雾量，不靠加厚雾制造亮度。此为有限步数、单次散射近似，游戏观感与动态稳定性尚待第三轮材料。

### 4.4 后处理（global/post/ + final）

**决议：E1（SC-16，2026-09-05）全部 tonemap 算子返回 display-linear RGB；final 唯一顺序为 HDR+bloom+godrays → exposure → tonemap → srgb_encode → grading → vignette → 输出抖动 → clamp。** C6 参数保持原值。更正 SC-16 的数学前提：AgX 末尾 pow(2.2) 是 EOTF，输出是线性显示值，不是 sRGB 编码；不得移除。Uchimura 与 Reinhard-Jodie 也按线性输出消费。ACES 保留矩阵/RRT fit，去掉输入 pow(1/2.2) 与尾部 to_linear 两个不相容变换；AgX CDL pow 输入钳为非负。Z5 按指令修正算子适配；C6 接入位置已解除，用户目视裁决仍待实机。依据：[Filament AgX 实现](https://github.com/google/filament/blob/main/filament/src/ToneMapper.cpp)、[ACES fitted 原实现](https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl)。

| 项 | 设计 | 来源 |
|---|---|---|
| godrays | 半分辨率 R8 两段式（composite 噪声图 + final 平滑）；曝光/视角/离屏三重淡出全部 CPU 预算 | Steadfast |
| bloom | **两 pass 方案**：composite1 半分辨率软阈值采集（mipmap 多级）+ final 合成 | Solas 结构（比 Mellow 6-pass 金字塔省 4 个 pass） |
| tonemap | 默认 **Uchimura**；可选 AgX / ACES / Reinhard-Jodie（自 Mellow `tonemap_operators.glsl` 移植，MIT，带出处） | Mellow |
| 色彩分级 | 曝光/饱和/自然饱和/对比/色温；**出厂默认值以 Refrax 风格为校准目标**（起始值：饱和 1.12 / 自然饱和 1.15 / 对比 1.04，开发期对照 Refrax 截图迭代） | Refrax 风格目标 |
| 风格层 | 所有风格参数集中在 `global/post/grading.glsl` 单一预设块——整包"观感"只调这一个文件 | 设计约定 |
| 抖动 | IGN 输出抖动（无 AA 下防 banding 的必需品） | Steadfast |
| 自动曝光 | **SC-41（2026-09-21）新增加入本表**：`AUTO_EXPOSURE` 可关选项、三档出厂 `!`；有界场景增益（夹在 `[AE_MIN, AE_MAX]` 内）乘在用户 `EXPOSURE` 滑杆之上，逐帧一次 1 片元测光 + 帧时间归一的不对称平滑，只在主世界空气路径生效 | 调研 §6 P0-3 |
| 明确不做 | 暗角（默认）、色差、胶片颗粒、DOF、运动模糊、描边（自动曝光原列本行，SC-41 移出） | 清爽哲学 |

**决议：E1（SC-32，2026-09-07）final 在既有 HDR+bloom+godrays 后追加水下颗粒，再执行 SC-16 单次 sRGB 链。** 颗粒不参与 bloom 采集，避免微尘被再次扩成光斑。godrays 保持 8 次深度采样，取消额外起点采样；60°视角阈值为0.5，曝光因子夹0..1，离屏深度不采样。该项修复屏幕空间光束边缘，不将 scene.glsl 的水下角向亮晕表述为有遮挡的体积光束。

SC-33 覆盖上述水下部分：空气 godrays 只在 isEyeInWater=0 合成；水下散射单独解码且仅在主世界水中合成，均衡档无需开启 GODRAYS。不透明手部沿用 colortex3 的 HAND 位修正压深，并确认 depthtex0 仍等于对应 depthtex1 后才应用，避免将其后标记错用到更近的半透明表面。

### 4.5 下界与末地特调（一等公民，非主世界的参数回退）

维度差异全部收敛在 `global/dimension/` 三个文件中（`overworld/nether/end.glsl` 各自提供天空、雾、环境光/光色函数），`world-1/world1` 壳注入宏后其余管线复用；`shaders.properties` 按维度裁剪无关 pass。**每个维度有明确的专属设计目标，验收时两维度截图必须能独立辨识为"被设计过"。**

**下界（NETHER）**——最容易掉帧也最容易被敷衍的维度，性能与效果同主世界标准：

- 光照路径重构：无天光/日光；环境光 = 方块光 + 熔岩海辉光 + 基础红色环境底
- 熔岩辉光雾：颜色/密度随高度与深度变化（贴近熔岩面更浓更亮）
- 独立大气：红/橙渐变天空、下界雾的密度与高度曲线独立于主世界参数
- 发光体与传送门增亮；下界特有的暗区呼吸感（blocklight 曲线单独调）
- 取材：Mellow 维度壳 + Solas nether 氛围思路

**末地（END）**：

- 真空暗天空 + 稠密星野（含缓慢旋转，低成本）、可选微弱星云（默认开、低强度）
- 末地石褪色环境光、void 雾随深度渐变（黑紫→黑）
- 传送门/折跃光柱的辉光处理；主世界云/日光相关特性整体裁剪
- 取材：Mellow end 思路 + Solas end 星云（低配版）

主世界 = §4.1–4.4 全部内容。

### 4.6 Voxy 支持

**决议：E1（SC-17，2026-09-06）在C5适配完成前，voxy.json保持空文件，以明确不注册Voxy patch。** C5从用户实例voxy-0.2.18-beta.jar的IrisShaderPatch.makePatch字节码确认空白内容直接返回null，且早于读取两个patch源码。现有无参callback与真实VoxyFragmentParameters签名不符，禁止启用；后续C5完成官方参数映射再注册。VOXY_SUPPORT目前尚无有效开启实现，GUI开关也不能使LOD获得支持。此为已知实验性限制，不阻断原生几何链。

**决议：E1（SC-17，2026-09-06）C5 的共享消费边界是 program/scene.glsl，复用 astra_light/astra_fog/astra_sky；原生varying不套给Voxy，Voxy几何属性由官方参数结构映射。** EXTERNALLY_DEFINED_UNIFORMS 要完整提供uniform集合，不允许局部重复声明。默认VOXY_SUPPORT仍关，支持状态须依据真实适配而非关闭选项推断；D1确认0.2.18-beta调用约定后由C5继续。


- `voxy.json` + `voxy_opaque.glsl` / `voxy_translucent.glsl`（`voxy_emitFragment` 入口）
- `lit_voxy.fsh` 通过 `EXTERNALLY_DEFINED_UNIFORMS` 宏复用同一套光照/水/雾模块（Steadfast 模式）
- Voxy 内部 uniform 映射层参考 Mellow/Steadfast 两家现成实现
- 标记为"实验特性"（26.x 上的 Voxy 兼容性需 M3 实测）

---

## 5. 性能设计（继承 Steadfast 方法论，作为硬性评审项）

- **带宽**：缓冲格式最小化（§2.3）；godrays/bloom 半分辨率；逐面数据打包进单个 `flat uint`（八面体法线每轴9-bit，共18-bit + 4-bit 材质 ID，预留10-bit）；FS 重建视空间位置（不传 varying）；仅传必要的 varying
- **ALU**：解析导数代替 FDM；FMA 形式书写数学；噪声优先查表（noisetex 硬件双线性）而非 hash
- **CPU 卸载**：天空/雾/godrays 曝光/风场参数全部走 custom uniforms 在 properties 里预计算——`shaders.properties` 本身是最大的"库文件"
- **早退**：`NdotL≤0` 不采阴影；godrays 曝光≤0 整 pass 早退；雾强度低跳过天空色；glass 不投影；`shadowDistanceRenderMul=1.0` 盒式剔除
- **免掉的整条管线**：无 G-buffer、无 SSAO（原版 smooth AO）、无 TAA、无 compute

---

## 6. 版本兼容计划

| 风险点 | 策略 |
|---|---|
| MC 1.21.4+ 方块/特征（pale garden 等） | block.properties 收录 Mellow 的 1.21.4/1.21.5 方块表（MIT 可复用） |
| 26.x 新版本号 | `MC_VERSION >= 260100` 分支（Mellow 已趟过 26.1 的坑，直接参考其 guard 写法）；26.2 差异待骨架阶段冒烟时确认 |
| Iris 版本底线 | 骨架阶段用 `iris.features.required` 显式声明实际用到的特性集；预计无 CUSTOM_IMAGES 需求（v1 无彩光/无 3D 纹理），底线上探空间大 |
| endFlash 等 1.21.9+ uniform | MC_VERSION 守卫 + 缺失时静默降级 |

**决议（SC-11，E 系，2026-09-05）：不照抄参考包的守卫——空守卫是误导性的死字。** 执行归 D1：

- `MC_VERSION >= 260100` 分支**只在出现真实 API 差异时**按 Mellow 写法补（其 `12104/12109/260100` 三级守卫可直接照章）。v1 现状是零版本分歧代码，先塞一堆 `#if` 只会让冒烟时的报错定位更难。
- `iris.features.required` **在首个被 gate 的特性落地时才声明**。v1 无彩光/无自定义图像，现在写 `CUSTOM_IMAGES` 会凭空抬高 Iris 底线、把老版本用户挡在门外。
- Iris 与 MC 的实际底线由 D1 双版本冒烟实测后回填本节；实测前 README 的 26.x 支持度保持"待验证"措辞，不写成承诺。

### D1 兼容守卫清单（2026-09-05 落档；离线核查 + 线上调研，实机冒烟待 SC-6）

**A. 现状核查（磁盘证据）**：`Astra/shaders/` 全文 `MC_VERSION` / `iris.features` 零命中（仅 README 设计声明行）→ 当前守卫清单为**空**，符合 SC-11"零版本分歧代码"前提，本轮不写入任何 `#if`。Astra 已消费的版本敏感 uniform 仅 `lightningBoltPosition`（`global/lighting/blocklight.glsl:52`、`diffuse.glsl:77`）与 `eyeBrightness`（长期稳定）；未消费 `endFlash*`、`renderStage`、`darknessFactor`、`biome` 常量、custom images。

**B. 参照包守卫编目 → Astra 处置**（守卫是下界语义 `>=`，低版本号守卫在 26.x 自然成立）：

| 守卫点 | 出处（实测位置） | 守护的 API | Astra 消费？ | 处置 |
|---|---|---|---|---|
| `>= 11300` | Mellow `block.properties:4` | 扁平化方块 ID | 否（矩阵下限 1.21.x） | 不需要 |
| `>= 11700` | Mellow `gbuffers_basic.fsh:28` | `renderStage` OUTLINE | 否 | 若 E1 引入描边处理再评估 |
| `>= 12104` | Mellow `shaders.properties:208` | `BIOME_PALE_GARDEN` 常量 | 否（block.properties 的 pale garden 条目是数据非 API） | 不需要 |
| `>= 12106` | Mellow `gbuffers_clouds.fsh:38` | 云距离归一化 | D2 平面云消费者相关 | D2 开工时实测决定 |
| `>= 12109` | Mellow `sky.glsl:120`、`voxy.json:8` | `endFlashPosition/Intensity` | 否 | 上表风险行保留：后续引入 endFlash 必须带此守卫 |
| `iris.features.required=CUSTOM_IMAGES …` | Mellow `shaders.properties:27`、Solas `:123` | 体素/LPV 自定义图像 | 否（v1 无彩光） | 不声明（SC-11） |

**C. 事实更正（D1 实测）**：§1.2 与 SC-11 所称"Mellow 的 `12104/12109/260100` 阶梯""Mellow 已趟过 26.1 的坑"不成立——本地 `_analysis/Mellow Shader v3.4/` 全文 grep `2601` 零命中，其最高守卫为 `12109`。**本工程无 260100 参照实例**；26.x 守卫只能在冒烟实测到真实 API 差异后自写，`#if MC_VERSION >= 260100` 的写法本身按 Mellow 既有守卫同形即可。

**D. 26.x 基线（线上调研 2026-09-05，非实机实测）**：

- Iris 支持时间线：26.1 自 Iris 1.10.7（2026-03-25）；26.2 自 1.11.0（2026-06-17，官方注明 Vulkan 不支持——本包 OpenGL 管线不受影响）。
- **建议底线**：26.1.x 用 Iris ≥1.11.3（2026-08-04，"Fixed many bugs exclusive to 26.1"）；26.2 用 ≥1.11.2（Sodium 0.9.1）。1.10.7–1.11.3 连续修 pack bug 证明 26.1 初期的加载器侧问题已在底线版本收敛。
- MC 26.1 渲染变更（官方 changelog）：核心 rendertype 合并精简、block/terrain 顶点不再带 Normal 属性、lightmap 采样路径调整、方块光色调/环境光/夜视改数据驱动 environment attributes、暗处光照算法修正。均位于 Iris 适配层之下；**pack 可见影响（`eyeBrightness`/`fogColor`/光照贴图语义是否漂移）只能实机确认**。
- 26.2 未见 pack 格式层变更公告，Iris 侧从 1.11.0 起即为正式支持。

**E. 冒烟计划（SC-6 解除后执行，对应验收"双版本零报错"）**：

1. 三环境加载：1.21.x（建议 1.21.11 + Iris 1.10.7+）、26.1.2（Iris ≥1.11.3）、26.2（Iris ≥1.11.2）；判据：日志零 ERROR、三维度出图（M1 判据"可编译且不涂黑"）。
2. 重点 diff 26.1 的 `eyeBrightness` / `fogColor` / 光照贴图语义（§D 的 environment attributes 改造）；实测到差异才按 Mellow 写法补 `#if MC_VERSION >= 260100`，并回填本清单 B 表。
3. Voxy × 26.x（SC-17 前置三项之一）同场冒烟。
4. 冒烟结论回填本节与 README；实测前 README 维持"26.x 待验证"（SC-11）。
5. 顺带核验 `check_pack.py` #7 提示的 12 个在四个参照包均无先例的方块 ID（`minecraft:ice`、`blue_ice`、`conduit`、`glass` 等，多为 26.x 更名/新增），在 26.1/26.2 实例内确认实际注册名。

---

## 7. 里程碑计划（轻量四步，无流程仪式）

| # | 里程碑 | 内容 | 验收标准 |
|---|---|---|---|
| **M1** | 骨架 | git init（`.gitignore` 排除 `_analysis/`）、§3.1 目录、空 program、缓冲声明、最小 final 链（tonemap+sRGB，否则看不到正确画面）、THIRD-PARTY.md 台账 | Iris 在 1.21.x 与 26.1 加载零报错，三维度显示原版画面 |
| **M2** | 主世界 | 阴影→光照→天空→雾→水（水面/SSR/折射/吸收/焦散）依序接入，对照"参考截图三连"（Steadfast 水面 / Solas 水下 / Refrax 色调）校准 | 水/天空/雾目视达标（§8.3 对应项） |
| **M3** | 维度与 Voxy | 下界/末地特调（§4.5）、Voxy 接入实测 | 两维度达到 §4.5 专属设计目标且帧率同主世界标准；Voxy 可用 |
| **M4** | 收尾 | bloom/godrays、风格层校准、四档 profile、zh_CN/en_US 文案、README | §8 全项通过 = v1 完成 |

> **决议（SC-9，E 系，2026-09-05）：M1 的"最小 final 链"含两端，实现归 E1。** 验收项"三维度显示原版画面"要求 `gbuffers_* → colortex0 → final → 屏幕`整条链透传：骨架期 16 个占位程序把 `program/lit.fsh` 写成 `gl_FragData[0] = vec4(0.0)`，几何阶段就把画面涂黑了，`final` 无论怎么补 tonemap+sRGB 都不可能显示原版画面（这是原上报证据里漏掉的一半）。据同一决议，占位期的判据从"能编译"改述为"**能编译且不涂黑**"：`lit`/`unlit`/`sky`/`clouds` 输出顶点色透传，`final` 采 `colortex0` 走 tonemap+sRGB。接线与 varying 预算随 SC-10 分层协议一次交付。

---

## 8. 验收标准（v1）

1. Iris 下 1.21.x 与 26.1/26.2 编译零错误
2. RTX 4050 Laptop @1080p：**流畅档 ≥144 / 均衡档 ≥90 / 极致档 ≥60 FPS**（森林/村庄/水下典型场景）；**下界同标准**（方块光密集是最易掉帧的维度，优先验证）。**此项已由现目标取代**：原生1080p、平均至少144 FPS、95%常规帧不超过6.94 ms，见 [当前工作](../../docs/当前工作.md)
3. 目视三达标：**水面 ≈ Steadfast、水下 ≈ Solas**、整体色调 ≈ Refrax（参考截图集；SC-24 对调后口径）
4. 下界/末地特调达到可独立展示水准（对照 §4.5，而非主世界参数自动回退）
5. 主世界清爽不抢戏：默认无暗角/颗粒/色差，昼间通透、夜晚方块光不糊屏
6. zh_CN 设置全覆盖；四档 profile 一键切换（名称见 §3.3）
7. Voxy 可用（或明确标注实验性与已知问题）

---

## 9. 许可与出处管理

### 9.1 现状

当前定位为**个人使用**，四包代码均可自由借鉴。四包许可事实：

| 包 | 许可 | 借用政策（个人使用期） |
|---|---|---|
| Mellow | MIT | 自由，保留出处注释 |
| Steadfast | GPLv3 + 附加条款 | 自由；**文件头保留 GPL 声明** |
| Refrax | 保留所有权利 | 允许借鉴，但**结构级照抄逐处登记**（见下） |
| Solas | 未声明（默认版权） | 同上 |

### 9.2 出处台账（开发第一天就建立）

`THIRD-PARTY.md` 按模块登记：`模块路径 | 来源包 | 借用类型（逐行移植 / 结构借鉴 / 仅思路）| 许可`。凡"逐行移植"的 Refrax/Solas 代码在文件头加 `// PROVENANCE: adapted from Refrax v1.3.1 (proprietary) — REWRITE REQUIRED before distribution` 类标记。

### 9.3 发布闸门（若未来决定公开发布，触发以下流程）

1. 清点 THIRD-PARTY.md 中 Refrax/Solas 来源的"逐行移植"项 → **全部重写**（思路保留、表达自写）
2. 决策 Steadfast 来源模块：a) 整包转 GPLv3 + 遵守命名附加条款（名称须带 `(edit of coderbot's Steadfast)`，与"Astra"品牌冲突）→ 不推荐；b) 重写 Steadfast 派生模块后以自选许可发布（推荐路径）
3. Mellow 来源模块仅须保留 MIT 署名，无需重写
4. 届时重新评估本设计文档中所有"来源"标注

---

## 10. 风险登记

| 风险 | 对策 |
|---|---|
| MC 26.x 着色器接口变动 | Mellow 已适配 26.1 作参考；骨架阶段即做双版本冒烟，问题前置 |
| 无 TAA 下水面/SSR 闪烁 | Nyquist 受限波形 + 足迹细节衰减 + 深度拒绝（§2.4）；主世界阶段专项验证 |
| Voxy × 26.x 兼容未知 | 实测；不行则标实验特性并文档化 |
| 未来发布时专有代码污染 | THIRD-PARTY.md 台账从骨架阶段维护（§9） |

---

## 11. 范围外备忘（roadmap，v2+ 候选）

按优先级：PBR/labPBR 材质系统（Mellow 可整体移植，MIT）→ 模组维度专用壳（`world_modded/` + `dimension.properties`，见 §2.2 SC-3 决议：v1 由模组维度继承根层链）→ 体积云（Solas/Refrax 思路）→ 云影（Refrax 3-slab）→ 彩色光源 floodfill（Mellow，MIT，需 Iris CUSTOM_IMAGES）→ GI/RSM（Solas 思路）→ 极光/银河。**架构已为以上留出扩展空间**（lib/global 分层使新模块独立挂载；无 AA 决定需在体积云引入时重新评估）。

---

## 12. 计划状态（2026-09-07 E 系更新）

用户最新指令覆盖早期分工流程：本次对话禁止下放及子代理，由当前模型独立完成修改；所有问题集中交付后用户再看画面，不再逐项中断。任务编号保留为模块责任记录，不表示本轮另行派工。SC-32 为整体审查后的集成决议与细节修复；SC-33 为续作补齐的水下阴影分束。

| 里程碑 | 当前状态与剩余责任 |
|---|---|
| M1 | 🔶 E1统一入口已交付；MC26.2/Iris1.11.2 主世界已由用户确认加载与出图。SC-32 修正 VOXY 可用宏误选原生矩阵。1.21.x 与其他维度运行证据仍待补。 |
| M2 | 🔶 五模块与 SC-24 换源已接入；第二轮截图暴露的差距经 SC-31/32 源码处置，SC-33 接入水下阴影分束；水面、水下与动态稳定性尚未获得修改后的画面裁决。 |
| M3 | 🔶 C3/C4几何入口可达；SC-17交还C5/D1继续Voxy适配。两维度视觉/FPS待实机；原有专属模块不重写。 |
| M4 | 四档配置已落地：FOG=50、SKY_FOG=15、UNDERWATER_FOG=40、SAT=100、VIB=100、CONTRAST=102。历史游戏截图与瞬时帧率不代表当前画面或持续帧率；视觉结论仍待当前游戏材料。 |

SC-6 的环境阻断已经解除，第一、二轮运行材料见 qa/screenshots/2026-09-06。尚缺的是本次修改后的画面，不是实例路径。SC-14 继续仅约束未来发布；C5 Voxy 完整映射仍属 M3，当前宏修复不代表 Voxy 已完成。

E1–E4 不整体标完成：本次完成可由源码确认的修复与书面裁决，最终观感及帧率仍以用户后续集中提供的运行材料为准。

## SC-34-F1 当前光路决议（2026-09-07）

**决议：E1/E2，当前模型独立执行。** 保留磁盘上已完成的 SC-34 坐标/水高/光照工作；新增变更属于用户新截图要求的光路续修。旧 SC-35/36 注释和 SC-37 日志不作为画面通过依据。

- 现有实际时序为 shadow → opaque lit → deferred → translucent water/lit → composite → composite1 → final。`ASTRA_SCENE_COPY` 与三维度 deferred 已在接手时常开，当前继续如此；旧“由三个水效果开关决定副本”的文字不再描述实际行为。colortex4 保留未施加视线介质的 opaque 色，水面不得采正在写入的 colortex0。
- 光学接口新增 `global/water/optics.glsl`：IOR=1.333、完整 Fresnel/全反射、Snell 日光方向、归一化 HG 相函数。水面只构造一份有效界面法线并据此产生光线；Fresnel 不随 skylight 改变。
- `water_raytrace` 现在接收已求好的射线并返回 UV/depth/confidence，不返回与深度脱离的 RGB；20+4 步后增加同面局部平面求交和命中位置读取。`refract_trace` 返回折射射线投影位置，由调用方逐点取得颜色和深度；原 Solas 屏幕偏移与最远深度策略已替换，历史出处保留。
- `astra_light` / `diffuse_lighting` 新增 `out directRadiance`，仅供同一 fragment 的焦散调制使用，不新增 varying。环境光、方块光不参与焦散放大；入水直射包含入口透射与光源至物体的水程，不对 air-side 物体因相机入水而强行套水下照明。
- 水面另一段逐点先传播再过滤；眼睛到界面的介质只作用一次。眼睛段散射源取眼部环境天光，避免远处受光方块的低 lightmap 使整个水体变黑。太阳散射与环境散射分开；界面与 composite 共用 `astra_water_sun_source`，相同 sigma 与相函数。移除旧角向增亮、独立聚光图案和额外 gain。
- composite 仍为半尺寸，colortex1 RGB 仍是 sqrt(scatter/4)，A 记录 0–96 格距离；16/24/32 段按实际可见水程分配。final 重建重新读取对应位置的完整尺寸深度，不用量化距离的宽阈值混入背景。
- bloom 软阈值从现有 1.0 起算，普通沙地不作为外溢光源；保留沙地本色和最终色彩链。继续使用 SC-27 默认格式，其高值裁剪限制尚未解除。

无新增 pass、缓冲、用户选项或 varying；新采样开销和视觉效果都需实际运行材料。屏幕外几何、水中折射后的完整遮挡仍受单层场景副本及单张直线 shadow map 限制。E2/E4 维持待实测，不把光束或固定场景移动玩家的阴影稳定性标为通过。

## SC-35 坐标、折射边缘与水下遮罩决议（2026-09-08）

**决议：E1/E2。** 所有 `playerPos` 一律表示不含 render-origin translation T 的相机相对世界坐标；view/player 互转只使用 `mat3(gbufferModelView[Inverse])`。绝对世界锚点只能写成 `playerPos + cameraPosition`。只有 shadow 投影入口显式加 `gbufferModelViewInverse[3].xyz`，shadow 顶点生产端也以同一个量减/加 T；不得以 `shadowModelViewInverse[3]` 代替 T。

水面在 translucent pass 中以 `depthtex1`（排除透明几何的 opaque depth）配对 deferred 的 `colortex4`；`depthtex0` 保留给透明绘制完成后的最近深度、final 粒子和水下光束边界。折射界面侧判断在 ±0.02 格内连续化；折射路径失效时混合到未偏移的完整 opaque 光路，再由该路径自己的有效度退到深水/天空，不允许未偏移路径以更高置信度无条件覆盖有效折射。

透明水面阴影覆盖定义为 `max(opaqueVisibility - allVisibility, 0)`。禁止 `opaqueVisibility * (1 - allVisibility)`：两张 PCF 图在同一不透明边缘均为 0.5 时，乘积会凭空产生 0.25 的水面透光。焦散在水面下 0.15–0.75 格建立后再衰减，避免量化水高边界成为最亮处；波层距离 LOD 只衰减相对均值的变化，不得改变视差高度的 DC 分量。

## SC-40 决议补登（2026-09-20 三方审查汇总，见 docs/2026-09-20-final-consolidated-review.md）

**决议：E1/E2。** 以下偏离与例外自本轮起登记在案，均为已发生事实的追认或修订：

- **水色分工修订（覆盖 §4.3/SC-34 的"空气侧只做吸收"禁令）**：空气侧在吸收之外增加受控的水体单次散射项（`water_body_color × (1−T)`），空气侧观感目标定为"青绿→深蓝的深度行程 + 菲涅尔反射叠加"；水下体积源仍然不进入空气侧路径。
- **lit varying 预算重订（覆盖 §3.2 的 9 标量冻结）**：按 pass 组合上限计——基础 9（texcoord/lightcoord/tint/faceData）+ 位置/阴影 6（cameraRelativePosition/surfaceShadowPosition）+ 水面切线系 10，逐顶点预投影是性能取舍；新增位置/shadow varying 必须过闸门。
- **"零 compute/零彩光"边界修订（覆盖 §0/§2.1）**：下界体素彩色光（9 个 compute 阶段 + 3 张自定义图像）自 NETHER_VOXEL_LIGHT 起为一等公民例外。
- **global→global 子分层承认（覆盖 §3.2 决议字句）**：大气（clouds_planar/stars→sky_gradient）、末地（end→end_blackhole→end_system→end_ring→end_geometry）、后期（post/grading→post/exposure，SC-41）三条单向链合法；校验器须补 global 内部边规则。
- **SKY_MODE 出厂=渐变（覆盖 §4.2 的 Minishita 默认）**：Complementary 渐变移植为出厂天空，Minishita 为可选手动档；在其获得天穹 LUT 之前不得改回默认（逐像素 2 视采样 + 1 光采样积分不可接受）。
- **deferred 恒开重申（§2.2 旧条件作废，沿 SC-34-F1）**：ASTRA_SCENE_COPY 与三维度 deferred 常开是现行契约；条件化属未来演进，须先改本条。
- **colortex5 语义重申**：RG=水面高度、B=天光、A=水面有效性标志（water_state.fsh 消费），任何 pass 不得挪作他用。

## SC-41 自动曝光翻案与实施决议（2026-09-21，调研 §6 P0-3 / 工单 T15）

**决议：E1/E2，用户裁定"先翻案 design 4.1 再实现，默认关"。** 本节推翻 §4.1 方块光行与 §4.4"明确不做"行里"以日光抑制取代自动曝光"这一排他论断，把自动曝光改为**可关选项 `AUTO_EXPOSURE`、三档出厂 `!`**。翻案理由不是"参照包都有所以要有"：Complementary Reimagined（66,417,800 下载）全包 `auto.?exposure|eyeAdaptation` 零命中，调研已核实。成立的那一条是**洞穴↔露天过渡**——本包是"日光越强方块光越弱"的压制模型，走进洞穴时压制项归零、天光项同时归零，画面对暗部的唯一补偿手段只剩用户手改 `EXPOSURE` 滑杆；压制项作用于**光照**，无法补偿一个已经整体偏暗的场景。收益按调研 §11.D 的判词记为"少一次手改滑杆"，不记为"补齐必需品"。

**不翻案的部分**：`BLOCKLIGHT_SUPPRESSION` 机制、其出厂开启状态、以及它相对 `EXPOSURE` 的优先级全部不变。二者不同轴——压制改的是"方块光在被日光照射时贡献多少"，自动曝光改的是"场景线性 HDR 进曲线前整体乘多少"。`settings.glsl:49` 的 "(replaces auto-exposure, design 4.1)" 措辞随本条就地更正。

**实施契约（缓冲、pass、编码、消费点）**

- 测光 = 新增 `composite5`，片元数每帧 1（`program/exposure.fsh`），输出 `colortex10`，`size.buffer.colortex10=1 1`。1 片元 pass 的先例是本包既有的 `program/water_state.fsh`（composite，写 `colortex6`，同为 1×1、逐帧不清零）；跨帧持久历史即靠这一条性质成立。
- 时序合法性：`colortex0` 的最后一个写者是 composite3（`water_composite.fsh`），composite4 写 `colortex7`，故 composite5 读到的 `colortex0` 正是 final 将消费的那份场景线性 HDR。测光不得放在 composite3 之前，也不得放在写 `colortex0` 的 pass 内（禁止读正在写的缓冲，§2.2 既有禁令）。
- 门控：`program.composite5.enabled=AUTO_EXPOSURE` 与两条 `program.world-1|world1/composite5.enabled=false` 一律写在 properties 预处理分支**之外**——`check_pack` #16 明文规定坐在 `#ifdef X` 里的门恰在需要关掉它时消失（`:327-329` 的 voxel 门同一教训）。下界/末地不测光：两维度的出厂曝光走 `GRADING_EXPOSURE_NETHER/END`（`global/post/grading.glsl:77,81`），是纯维度常量，掺进场景相关增益会同时毁掉"两维度可独立辨识"的一等公民目标（§4.5）。
- 历史编码必须格式无关（SC-27 2026-09-26 修订：允许格式 const，规则为名称合法 + 全大写引擎 token + 每缓冲唯一声明 + `#ifndef` 守卫）：`t = (log2(gain) - log2(AE_MIN)) / (log2(AE_MAX) - log2(AE_MIN))` 夹到 `[0,1]` 存 `.r`。默认格式无论 RGBA8 还是 RGBA16F 都能原样承载 `[0,1]`；按 `water_pack_surface_height` 对 `colortex6` 的 255 量化处理解，本包实际按 8-bit 归一化对待 1×1 缓冲，故 `[0.60, 2.20]` 的 1.874 octaves 摊到 255 码 = 每码 0.51% 增益台阶，量化台阶不可见且被平滑吸收。
- 消费点：`global/post/grading.glsl` 的 `apply_auto_exposure()`，线性/前置 tonemap，紧接 `apply_exposure()` 之前。`apply_exposure` 仍是用户滑杆的唯一落点；新增这一槽而非把两件事塞进同一函数，是为了让"用户增益"与"传感器增益"各自可关。

**对调研「做法」的两条实测偏离**

1. 调研要求"在 `program/water_bloom.fsh` 已有的 mipmap 链上取最粗一级做亮度"。**不采纳**，两条实测理由：① 那条链属于 `colortex0`，其 `colortex0MipmapEnabled` 声明只在 `program/water_bloom.fsh:5` 出现，而 composite4 的门是 `program.composite4.enabled=BLOOM`（properties:55）且 PERFORMANCE 档出厂 `!BLOOM`（`:149`）——在该档启用本选项会**新引入**一整条全分辨率 HDR mip 链的生成，与调研「成本」条"一次 mipmap fetch…可忽略"直接矛盾；② 1 片元视口内没有相邻片元，隐式 LOD 的导数无定义，取级本身不可靠。改为**定步长 `texelFetch` 网格**（`AE_GRID=8` → 64 次整数取点，`textureSize()` 推步距），零带宽、零格式假设、与 BLOOM 完全解耦；`texelFetch` 亦是 `water_state.fsh` 在同型 1 片元 pass 里已经采用的取点方式。
2. 调研「依据」点名的六包一律用 mipmap 或直方图，本包两者都不用。这是主动偏离，不是遗漏；若日后 `colortex0` 的 mip 链成为常态（例如 PERFORMANCE 也开 BLOOM），可再评估换源，但**测光源不得依赖任何会被别的开关关掉的缓冲**——`colortex2`（泛光采集）当年就是因 `BLOOM` 开关会改变曝光而被排除。

**工单要求采纳的三条性质，落点**

- *对高光截断*（Photon `program/c4_taa_exposure.vsh:39-170` 的中位数诉求的等价形式）：逐抽先 `clamp(luminance, AE_FLOOR, AE_CLIP)` 再进 `log2`，太阳入镜不再抬走整体测光。本包不做直方图中位数——一帧一个片元拿不到分布。
- *NaN 守卫*：历史有效性用 `.a` 标志位而非"数值 ≤0"判定（Refrax 的 `prev<=0.0` 判据在 `[0.60,2.20]` 的码域会把"增益触底"误判成"无历史"）；解出的历史码若非有限也当帧用 target 重置。测光自身若得 NaN 直接返回中性 1.0。
- *变暗/变亮不对称速率*：`AE_RATE_FAST`（场景变亮 → 增益下降，2.5）快、`AE_RATE_SLOW`（场景变暗 → 增益上升，0.5）慢，出洞不炸白；混合权重按帧时间归一 `1 - exp(-frameTime·rate)`，故与帧率无关。混合在 `log2` 域做，且差值不足一个量化码（`AE_LOG_CODE`）时直接吸附到 target，否则 8-bit 历史会在两个码之间永远抖动。

**出厂足迹与验收边界**：选项关 ⇒ composite5 不编译、`colortex10` 只余一张 1×1 纹理、`apply_auto_exposure` 原样返回输入，出厂像素零变化（判据：三档默认扫描 + `qa/iris-properties-resolved.txt` 快照 + 反向编译验证）。开起来的观感——呼吸感、洞穴进出节奏、日面入镜是否仍压暗、水下冻结是否正确——全部离线不可判，进 `qa/regression-checklist.md` 待实机行；本节不构成"无闪变"或"性能可接受"的结论。附带补记：§4.2 云影行原写"v1 不做"，实际已由 T14 `3d13037` 落地，本轮同批更正。

## 水底折射配对、弱倒影天空占比与视差取消决议（2026-10-13，用户要求）

用户在水面性能探索授权（允许降低波面、倒影、折射及岸边细节）下明确要求三项改动，源码已落实并同步开发实例；本节替代 §4.3 水面行"4 步自适应视差"及 SC-32 中"水面视差与法线共用高度尺度、最终波层足迹包含视差放大"的位移部分，原条目保留为当时的决议记录。

- **水底折射读取一个配对像素**：空气侧水平水底的 `water_refracted_uv` 背景与折射目标各改为一次纹素自身深度读取；2×2 四角 gather、同格足迹复用与 `acceptedFootprint` 出参退出。传输由新的 `water_transmission_sample` 完成：折射UV所在纹元的颜色、深度与晚实体记录同帧配对，一次水柱/水雾传输。竖流水、水下界面的折射候选四角接受（`water_depth_footprint` 保留）与全部反射消费路径不变。SC-32 "折射边缘回接必须混合完整光路"仍成立：`unshiftedPath`、直路回退与远场深水介质候选均按各自配对端点计算。
- **弱物体倒影更多使用天空环境**：主世界预算内，水上水平面的物体SSR渐入窗口由菲涅尔 0.08～0.16 上移至 0.14～0.26；法线附近弱反射由 `astra_reflection_sky` 环境承载，掠射强倒影与日月 glint 路径不变。水下界面窗口（0.025～0.055）不在本项范围。
- **取消水面波纹视差位移**：`surface_parallax`、`surface_height` 及其高度读取在全部档位删除；`water_surface` 直接在片元几何 XZ 求六层解析梯度法线。Nyquist 足迹过滤、远细波渐退、粗糙度能量与波层参数保持。§4.3 的"解析导数 + Nyquist 比率受限"仍是水面设计，位移部分作废。
- 本轮未重跑独立 GPU 计量；不能把删除的读取数换算成帧率。实机帧率、折射边缘锯齿、弱倒影观感与无位移波面动态待用户画面确认，现状与待办由 `docs/当前工作.md` W16 维护。
