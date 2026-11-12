# stracciatella-shaders × Astra 性能调研（batch4）

- 调研日期：2026-10-03。数据时点：包内容为本地解压快照（`reference_shaderpacks/stracciatella-shaders/`，来自 `reference_shaderpacks/zips/Stracciatella Shaders v1.6.4.1 by DrDesten.zip`，包内文件时间 2026-02-09）；下载量以任务书给定（Modrinth v1.6.4.1，170,808 下载）为准。
- 引用约定：`P:` = `reference_shaderpacks/stracciatella-shaders/shaders/`（本包 shader 根即 `shaders/`，行号相对该目录）；`A:` = `Astra/shaders/`；跨包对照用 `reference_shaderpacks/<slug>/shaders/`。
- **血统判定（决定本文口径）**：本包与已研究的 `drdestens-shaders`（v2.1.5）**同为 DrDesten 作品、共用同一套 `core/` 库**——`README.md` 文本完全一致（“# DrDesten - ShaderCore”），`core/` 目录逐文件比对仅 4 个文件有差异（`dh/textures.glsl`、`dh/uniforms.glsl`、`transform.glsl`、`vertex_transform.glsl`），其余（core.glsl、water.glsl、kernels.glsl、dither.glsl、lightmap 相关等）一致。按任务口径：**只报相对 drdestens 旧报告（`shader_research/drdestens-shaders.md`）的增量**；下文每条均写明「drdestens 已存在 / 旧报告已载 / stracciatella 新增」。
- 去重材料：`shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md` 全部读过；每条候选均附 `Astra/shaders` 的 grep 关键词与结果。

---

## 一、概况

| 项 | 事实 | 证据 |
|---|---|---|
| 定位 | 原版观感 + 彩色灯光 + 大量 QoL（波浪/水洼/雨折射/自定义星/极光/LUT/损血效果/矿石闪烁）；**无阴影图、无 PBR、无 SSR/反射、无 Bloom/TAA/DOF** | `grep -rln "shadowtex\|shadowcolor"` 0 命中；`grep -rln "bloom\|DOF\|bokeh\|SSR\|specular"` 0 命中；TAA 仅 `core/kernels.glsl` 遗留偏移表、无 TAA 程序 |
| 血统/版本 | DrDesten / v1.6.4.1（zip 名）；与 drdestens-shaders v2.1.5 同作者同 core 库；管线重排（无 `deferred1`，`composite` 号段改为彩光链） | `P:core/README.md:1-2`；core 目录 diff 结果；`P:shaders.properties:233`（profile.STRACCIATELLA） |
| 许可 | 全包仅 `P:core/README.md`，**无 LICENSE/版权文件** → 保留所有权利；只能读思路独立重写并登记（与 drdestens 报告 ⑤ 结论一致） | `find -iname "*licen*"` 0 命中；zip 清单仅 `shaders/core/README.md` |
| 规模 | 313 文件（整包口径 = 125 .fsh + 125 .vsh + 48 .glsl + 4 .gsh + 6 PNG + 3 properties + 1 lang + 1 md；其中 `lut/` 实有 lut0-lut5 共 6 张 PNG，`post_process_shaders/` 7 文件）；shader 代码 **10,843 行**（.glsl/.fsh/.vsh/.gsh，与任务书一致），加 properties/lang 共 11,898 行；3.7 MB | `find | wc -l`；`find ... -exec cat {} + | wc -l`；`du -sh`；扩展名直方图 |
| 结构 | 所有代码都在 `shaders/` 内：根目录为共享实现（`#ifdef OVERWORLD/NETHER/END` 守卫），`world0/`、`world-1/`、`world1/` 为 5 行薄壳（`#define` 维度 + `#include "/xxx.fsh"`）；另有 `core/`（共享库）、`lib/`（设置与光/雾/天逻辑）、`post_process_shaders/`、`lut/` | 例：`P:world0/composite5.fsh:1-5`；`P:world0/gbuffers_water.fsh:1-5` |

---

## 二、管线与调度

- **程序清单**（根实现 + 维度薄壳）：`gbuffers_`{terrain, terrain_cutout, textured, textured_lit, transparent(水复用), basic, block, entities, hand, hand_water, armor_glint, beaconbeam, spidereyes, line, damagedblock, weather, skybasic, skytextured(+`.gsh`), clouds} → `deferred`（主光照）→ `composite`…`composite11` → `final`；另有 `dh_terrain`、`dh_water`。**无 shadow 程序**（`find -iname "*shadow*"` 0 命中）——与 drdestens 同源，光照全部由 lightmap 承担。
- **阶段分工**：composite0-3 = 彩光降采样链（`COLORED_LIGHTS`）；composite4 = 彩光时域累积（32×18）；composite5 = 调色/LUT/水下雾/雨折射/损血/速度线；composite6 = FXAA 或 HQ 上采样；composite10/11 = 外挂后处理程序（anaglyph/badtrip/comic 二段式）；final = 输出（+可选双三次放大）。
- **shaders.properties 调度面**（`P:shaders.properties`）：
  - 全局开关：`underwaterOverlay/sun/moon/vignette/rain.depth/beacon.beam.depth/oldHandLight/separateAo/oldLighting`（:1-12）——材料 batch3 A 组「Iris 管线级开关」已列（pixel-perfect/vanilletix），属同向非增量。
  - `program.*.enabled` 表达式门控（:203-228）：composite0-4 挂 `COLORED_LIGHTS`、composite6 挂 `FXAA || HQ_UPSCALING`、composite10/11 挂 `POST_PROCESS_SHADERS`。
  - `size.buffer.colortex4 = 32 18`（:194）——彩光累积槽是唯一固定尺寸缓冲，其余全屏。
  - `blend.gbuffers_hand/entities.colortex1 = off`（:198-199）；`alphaTest.*=off` 17 程序（:174-190，与 drdestens 同源，材料 SUMMARY-batch2 P14b 已列）。
  - 纹理槽分阶段绑定：`texture.gbuffers.colortex4 = minecraft:...water_still.png`（:120）、`texture.composite.colortex2 = lut/lutN.png`（:122-168）——同一槽位在不同阶段扮演水贴图/彩光累积、LUT/其他，Astra 目前 0 处使用 `texture.*`（`grep "^texture\." A:shaders.properties` 0 命中），工程价值见备注。
  - 3 条 profile（:231-233）与滑条/菜单（:239-431）——「一行式 profile/行为预设」材料已列。
  - CPU custom uniforms：太阳/月光方向、昼夜对齐、clip 坐标、`smooth()` 湿雨/相机链等（:14-116）——12 包共识「CPU 预计算」类，非增量。
- **风险分级开关**：`AGRESSIVE_OPTIMISATION`（0/1/2 → `OPT_SAFE/OPT_UNSAFE`，`P:lib/settings.glsl:10-12`）。全包仅 4 处消费：`P:lib/setup.glsl:29-33`（colortex0 免清空，且仅 MC<1.19）、`P:lib/vertex_transform_simple.glsl:74-82`（纹理坐标快路径）、`:84-92`（lightmap 坐标快路径）、`P:gbuffers_textured.vsh:12-17`/`.fsh:12-18`（noperspective/flat 插值）。其中插值项 drdestens 已有等价物（`drdestens .../lib/stddef.glsl:13` 的 `OPT_NOPERSPECTIVE`，且旧报告 2.6 已载）→ 非增量。
- **缓冲与清空**：colortex0 颜色、colortex1 lightmap RG16 打包、colortex2 LUT 槽、colortex3 雨折射 stencil、colortex4 彩光累积（`colortex4Clear=false`，`P:lib/setup.glsl:50`）、colortex5 自发光色、colortex6 降采样链；`colortex5/6Clear=true`（:51-53）。**格式声明整段在块注释内**（`P:lib/setup.glsl:4-26`），实际格式依赖 Iris 默认（drdestens 同类，材料 ④-2-4 已记录）。

---

## 三、分模块性能手法清单

### 3.1 调度与阶段启停
| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:shaders.properties:203-217` | 彩光整链（composite0-4 × 三维度）由 `COLORED_LIGHTS` 一条表达式全部停调度 |
| 2 | `P:shaders.properties:219-228` | FXAA/HQ 上采样与 PP 外挂程序各自门控；对应 vsh 在关闭时把顶点移出屏外兜底（`P:composite6.vsh:8-12`） |
| 3 | 全包 | **没有 shadow 程序**：相对 drdestens（同样无 shadow）是继承；相对 Astra 是结构性削减（但要接受无实时投影） |
| 4 | `P:shaders.properties:174-190` | 17 个程序批量 `alphaTest=off`（同源，材料已列） |
| 5 | `P:shaders.properties:198-199` | 辅助缓冲单条 blend off；Astra 已有更细的同类声明（`A:shaders.properties:338-343` 等 74 行）→ 去重 |

### 3.2 地形光照与阴影
| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:gbuffers_terrain.fsh:291-292`、`P:lib/gbuffers_basics.glsl:15-17` | 不用光图颜色贴图：把 `lightmapCoord/AO/emissiveness` 4 个 8bit 打包成 RG16（`vec4to16x2`）写 colortex1，deferred 端解码重建（`P:deferred.fsh:203,236`）——省一次光照贴图采样与色带 |
| 2 | `P:lib/lightmap.glsl:56-96,98-151` | 可配置 custom lightmap：天光/方块光各自的 AO 曲线（0..200 滑条）、亮度对比、夜晚混合、caveLight 地板（与 drdestens 同源，旧报告 P3 已列） |
| 3 | `P:lib/lightmap.glsl:153-210` | 彩光叠加版 lightmap：把彩光色以「亮度归一到 palette 亮度」的方式混入方块光色（Oklab 保色相） |
| 4 | `P:gbuffers_terrain.fsh:88-91,205-209` | 方向光图：用 `dFdx(lmcoord.x)` 求方块光方向、配合生成法线做逐像素漫反射——**drdestens 已有同名机制**（`drdestens .../gbuffers_terrain.fsh:106-111`）→ 非增量 |
| 5 | `P:gbuffers_terrain.fsh:214-252` | HDR 自发光：按方块类别（白/橙/红/蓝/紫/蜡烛等）用 HSV 启发式提取 emissiveness，配合 reversetonemap 往返制造 HDR 光感；仅对 `block.emissive` 块进入 |
| 6 | `P:gbuffers_terrain.fsh:263-270,293-295` | 彩光光源：emissive 块按 `CL_PALETTE[block.data]`（`P:lib/palette.glsl:3`，64 色表；染色玻璃取实际像素色）写 colortex5 |
| 7 | `P:gbuffers_terrain.vsh:172-176`、`P:lib/lightmap_vertex.glsl:7-11` | 顶点级假方向 shading（固定光向点乘法线乘进 glcolor.a，按方块类别豁免）——与 drdestens `oldLighting()` 同族，旧报告 2.2 已载 |
| 8 | `P:lib/vertex_transform_simple.glsl:84-92` | OPT_SAFE 下顶点 lightmap 坐标走 `gl_MultiTexCoord1.xy*(1./240)`，跳过 texture matrix（见 A1） |
| 9 | `P:deferred.vsh:27-64` | 手持光在 deferred 顶点阶段算成 flat varying（颜色/亮度查表），片段端零查表——材料 batch3 BQOL「手持光顶点级预计算」同类，Astra 已有玩家中心手持光 → 去重 |

### 3.3 云
- 默认不下场：`CUSTOM_CLOUDS` 关闭（`P:lib/settings.glsl:150`），vanilla 云走 `P:gbuffers_clouds.fsh:53` 的 `color.a = fstep(0.1, color.a)`（把半透明云固化为 alpha 测试，省混合/排序）；
- 休眠代码：deferred 内联云（`P:deferred.fsh:135-197`）含 Klein-Nishina 相函数与 2 次 offset 迭代细化，但整段不可达；不列为可借鉴内容。

### 3.4 雾与大气
| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:lib/sky.glsl:171-203` | 解析雾：`smoothstep` 施于平方距离（`fogSmoothStep`，含 FOG_START/FOG_END 两个乘子），另给 `fogBorderExp` 用乘法近似除法（`:202` 注释“Multiplication is faster”）——材料已判雾模型无借鉴价值（SUMMARY-batch2 ⑤-6） |
| 2 | `P:lib/sky.glsl:224-230,283-286` | 高级雾：高度雾用密度函数解析积分（`FE_densityI`）代替步进，`fog = 1-exp2(-len*combined)` 一步出 |
| 3 | `P:lib/sky.glsl:290-302` | 风噪声雾：3 octave `sfbm` 与 `worldNoiseMix`（随距离衰减）调制高度雾；噪声在远处仍全量计算（无早退，见反面） |
| 4 | `P:lib/settings.glsl:25-27` | FOG=Auto 时若存在 `DISTANT_HORIZONS` 自动升为 Advanced |
| 5 | `P:lib/sky.glsl:73-124` | 天空/雾色自定义色 × 昼夜/雨强在 CPU 预混（`SKY_*`/`FOG_*` 常量 + daynight/rainStrength），GPU 端只做两点 mix |
| 6 | `P:composite5.fsh:199-209` | 水下雾：密度按 `playerLMCSmooth.y`（CPU smooth 的光图）指数调制、亮度按光图与昼夜；失明/黑暗按视距平方衰减（`:211-216`） |

### 3.5 水与水下
| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:world0/gbuffers_water.fsh:1-5` | 水复用 `gbuffers_transparent` 程序（只加 `OVERWORLD` 定义），无独立水材质链 |
| 2 | `P:gbuffers_terrain.vsh:238-254` | 液体波浪纯顶点位移（一个正弦 + flowHeight 权重），片段端零开销 |
| 3 | `P:gbuffers_terrain.vsh:256-275`、`P:gbuffers_terrain.fsh:167-182`（视差 `:127-148`） | 水洼：掩码在**顶点**阶段算（天光/朝向/方块排除/snoise/雨强，乘 gl_Color.a 排除洞内），片段端只做水面贴图混合（可选折射视差） |
| 4 | `P:dh_water.fsh:85-113` | DH 水面：先与 vanilla 深度比较（在前的 vanilla 像素直接 discard），再按 texel 密度在贴图与顶点色之间混合 |
| 5 | 全包 | 无 SSR/反射/吸收链（grep 0）；水下依赖 composite5 的解析雾 |

### 3.6 粒子·实体·天气
| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:gbuffers_weather.fsh:41-46` | 雨/雪判别二选一：玩家温度阈值，或「蓝通道主导」`color.b-avg(rg)>0.25`；仅雨写 colortex3 stencil（`:36-90`），雪走普通光照 |
| 2 | `P:composite5.fsh:136-149` | 屏幕雨折射：按 stencil 强度/梯度偏移采样坐标（两档：整体摆动或梯度方向） |
| 3 | `P:lib/lightmap_vertex.glsl:13-15`、`P:gbuffers_hand.vsh:24` | 实体用 `dot(up, viewNormal)*0.35+0.65` 的顶点 shading；手持物同样处理 |
| 4 | `P:shaders.properties:199` | 实体/hand 的 colortex1 写关闭混合（保 packed lightmap 不被混） |

### 3.7 后处理与缓冲内存
| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:composite5.fsh:263-275` | 调色链（对比/饱和/振动/暗角/LUT）之后把 `luminance(color)` 写进 colortex0.a，供 FXAA 直接读（`P:composite6.fsh:18-20` 的 `getLuma`），免去 FXAA 里重复求亮度——材料 batch3 BQOL「效果量复用 alpha」同类 → 去重 |
| 2 | `P:composite6.fsh:94-106` | FXAA 3.11 HQ：沿边双向 trace 共 9 步，两侧都命中即提前 break；再加子像素项 |
| 3 | `P:final.fsh:96-105`、`P:composite6.vsh:8-12` | HQ_UPSCALING：最终以 `textureBicubic` 从 `MC_RENDER_QUALITY` 缩放的坐标上采样（宏无定义，见无法判定 2） |
| 4 | `P:lib/setup.glsl:29-57` | 按 OPT_SAFE/MC 版本选择是否清空 colortex0；colortex1/2/4 已有免清空/编码清空策略（colortex1 的编码清空色 `:41` 是可学技巧但属 drdestens 同源） |
| 5 | `P:shaders.properties:120,194` | colortex4 一槽两用（gbuffers 阶段当水面贴图、composite 阶段当 32×18 彩光累积），省一张缓冲与一个采样器 |
| 6 | `P:core/core/dither.glsl:26-28` | 8bit 写前 `ditherColor`（±0.5/255 Bayer4）在 gbuffers/deferred/composite 多处使用（画质非性能） |

---

## 四、反面印证（不建议学）

1. **彩光降采样链的同 pass 读改写**：composite1/2/3 以 `DRAWBUFFERS:6` 写 colortex6 的同时 `texelFetch(colortex6, ...)` 读它（`P:composite1.fsh:26-53`、`composite2/3` 同），全包无 `flip` 声明；且「保留 screen/2、/4、/8 象限」的裁剪语义与 composite4 的角部采样坐标（`coord/16 + 0.9375`，`P:composite4.fsh:117`）在标准全屏视口语义下无法自洽（详见无法判定 1）。这套打包不能照抄，若要借必须重写为显式 flip/双缓冲与明确坐标约定。
2. **32×18 屏幕空间彩光是无遮挡近似**：穿墙泄露 + 1 帧延迟 + 大块模糊（`P:composite4.fsh:98-146`）。可作低成本对照实现，不宜当正式彩光。
3. **发布包内保留死代码/旧实现**：`P:composite4.fsh:149-210`（`#if 0` 整段旧累积实现 + `P:lib/colored_lights.glsl` 的 importance 编解码函数实际只在 `#if 0` 内被调用）、`P:deferred.vsh:43-52`（注释掉的旧手电）、`P:lib/colored_lights_mip.glsl`（仅 include guard 的空壳）。
4. **AGRESSIVE_OPTIMISATION 名不副实**：Unsafe 档没有更强内容，实际只挂 4 处微优化（清空/坐标/插值）；分级概念可学，内容价值有限。
5. **格式声明整段在块注释内**（`P:lib/setup.glsl:4-26`）：缓冲格式实际靠 Iris 默认，声明与行为不一致（drdestens 同类，材料已记录）。
6. **LUT 选择器指向缺失文件**：`P:shaders.properties:123-167` 引用 `lut0.png`-`lut20.png`，包内 `lut/` 实际只有 lut0-lut5 共 6 张——启用 `COLOR_LUT` 且选择 6-20 时会取到空纹理（发布包完整性缺陷，学习时勿照抄该开关布局）。
7. **CUSTOM_CLOUDS 大段云代码常驻但默认关闭**（`P:deferred.fsh:135-197`）：无效编译载荷；关闭时应编译期剔除而非留 `#ifdef` 空转。

---

## 五、新颖借鉴点

> 说明：以下均已先对 `Astra/shaders` 做多关键词 grep（结果随条附出），并与五份材料及 drdestens 旧报告对照；每条注明 drdestens 侧状态。

### A 组（低代价，可直接排期）

| # | 机制 | 来源 file:line | Astra 未实现证据（grep 关键词与结果） | 迁移代价 |
|---|---|---|---|---|
| A1 | 顶点 lightmap 坐标免矩阵快路径：`gl_MultiTexCoord1.xy * (1./240)` 取代 `(gl_TextureMatrix[1]*gl_MultiTexCoord1).xy`；同族还有纹理坐标的手工 mat2 路径（OPT_UNSAFE） | `P:lib/vertex_transform_simple.glsl:84-92`（纹理坐标 `:74-82`）；开关 `P:lib/settings.glsl:10-12` | `grep -rn "TextureMatrix\[1\] * gl_MultiTexCoord1" A:shaders` 全仓仅 `program/lit.vsh:56` 一处（`grep -rc "TextureMatrix\[1\]" program/*.vsh` = 1），且为 texture matrix 形式；`grep "1./240\|/ 240" A:shaders` 命中均为 `eyeBrightnessSmooth.y/240`，无顶点属性快路径。Astra 自身已有直接属性先例（`A:program/shadow.vsh:98,138` 直接用 `gl_MultiTexCoord0.xy`） | 改 `A:program/lit.vsh:56` 一行，保留回退；需实机验证 Iris 属性值域 1/240 假设（原包作者也把该项放在自称"可能破坏画面"的 OPT_SAFE 档） |
| A2 | 主色缓冲免清空：`const bool colortex0Clear = false;`（作者仅在 MC<1.19 + OPT_SAFE 启用）；同文件的编码清空色技巧属 drdestens 同源 | `P:lib/setup.glsl:29-33` | `grep -rn "colortex0Clear\b" A:shaders` 0 命中（只有 `lib/settings.glsl:514` 的 `colortex0ClearColor`）；Astra 唯一关闭清空的缓冲是 `colortex6`（`A:lib/settings.glsl:526`）。注意 drdestens 已有 `colortex1Clear=false`（`drdestens .../lib/setup.glsl:17-18`），本项增量为 colortex0 条目 | 一行声明 + 全像素覆盖核查（天空/半透明/粒子/hand 均须写入）+ A/B；作者在 1.19+ 停用该技巧，Astra 目标版本适用性须先验证 |

### B 组（中代价，需接线）

| # | 机制 | 来源 file:line | Astra 未实现证据（grep 关键词与结果） | 迁移代价 |
|---|---|---|---|---|
| B1 | **屏幕空间时域彩色光照**（低成本彩光替代 voxel floodfill）：gbuffers 把 emissive 块的颜色（`CL_PALETTE` 64 色表 / 染色玻璃实色）写入 colortex5 → composite0-3 以「非零计数平均」逐级合并到 colortex6（2×2 gather，象限递缩）→ composite4 在 32×18 的 colortex4 上做重投影时域累积（双三次读历史、mip LOD 采样新样本、用「存储亮度估年龄 + 新样本亮度估重要性」的免额外通道混合、坐标/深度三种拒绝模式、Oklab 存储）→ deferred 双三次采样并按饱和度/vibrance 调色后混入 lightmap 方块光色；手持光同链衰减；`COLORED_LIGHTS` 关闭时全链停调度 | 光源端 `P:gbuffers_terrain.fsh:263-270,291-295`；调色表 `P:lib/palette.glsl:3`；降采样 `P:composite.fsh:26-49`、`P:composite1.fsh:26-53`、`P:composite2.fsh:26-53`、`P:composite3.fsh:26-53`；累积 `P:composite4.fsh:98-146`（重投影 `:104-111`、LOD `:117-119`、重要性/年龄 `:121-125`、拒绝 `:127-136`）；消费 `P:deferred.fsh:207-236`；槽位 `P:shaders.properties:120,194`、`P:lib/setup.glsl:49-54`；门控 `P:shaders.properties:203-217` | `grep -rln "oklab\|Oklab\|OKLab" A:shaders` = 0；`grep -rln "colored" A:shaders` 仅下界/彩色阴影/语言（`global/dimension/nether.glsl:14,174`、`global/dimension/nether_colored_light.glsl`、`lib/nether_voxel_grid.glsl`、`program/nether_light.csh`），**主世界无彩光载体**；`grep -rln "reproject" A:shaders` 仅云/水下光束/下界反射（`global/atmosphere/cloud_temporal.glsl`、`global/water/shaft_history.glsl`、`program/nether_reflection.fsh` 等），无色彩光场累积器；Astra `shaders.properties` 的 `size.buffer` 列表（`A:shaders.properties:38-75`）无 32×18 级光场槽 | 4 个极小全屏 pass + 2 个小缓冲 + gbuffers/deferred 两处接线，无 compute/SSBO；需接受屏幕空间近似的画质边界（穿墙、1 帧延迟、32×18）；建议定位为「主世界彩光」的低成本对照实现（材料中 floodfill 三维度统一为既列长期方向，此项只是其替代机制，non-goal 需统帅确认） |

### C 组（大工程/含前置依赖）

| # | 机制 | 来源 file:line | Astra 未实现证据（grep 关键词与结果） | 迁移代价 |
|---|---|---|---|---|
| C1 | DH 边界剔除与深度一致性：按 16×16 区块网格吸附 + 相机侧修正，三条件判定 DH 片元是否落在 vanilla `far` 内，命中则光照前 discard；透明层用容差 0 且对 vanilla 深度逐像素比较；边界用 Bayer4 抖动过渡 | `P:lib/dh.glsl:10-30`；`P:dh_terrain.fsh:35-46`；`P:dh_water.fsh:70-93`；`P:gbuffers_transparent.fsh:79-89` | `grep -rc "DISTANT_HORIZONS" A:shaders` = 0 命中；Astra 仅有 Voxy 占位（`A:shaders/voxy.json`、`A:program/lit_voxy.fsh`、`A:voxy_opaque.glsl`、`A:voxy_translucent.glsl`），无 DH 程序 | 前置：Astra 尚无 DH/Voxy 光栅支持（材料 batch2 已列 C5 长期项），须与该立项一起设计；机制本身低成本。**增量声明**：基础剔除 `discardDHSimple/DHDithered` 在 drdestens 2.1.5 已存在且两包逐字节相同（`drdestens .../core/dh/discard.glsl:7-38` 与 stracciatella 同名文件 diff 为空；drdestens `dh_terrain.fsh:38-39`、`dh_water.fsh:57-58`），本项只主张 stracciatella 新增的「区块吸附变体 + dh_water 的 vanilla 深度一致性 + 光照前顺序」 |

### 去重排除（每条：包内出处 → 排除依据）

| 机制 | 包内出处 | 排除依据 |
|---|---|---|
| 方向光图（dFdx(lmcoord) 求光向） | `P:gbuffers_terrain.fsh:88-91,205-209` | drdestens 已有同名机制（`drdestens .../gbuffers_terrain.fsh:106-111`、`DIRECTIONAL_LIGHTMAP`）→ 非增量 |
| DH 基础剔除与 Bayer 平滑 | `P:core/dh/discard.glsl:7-38`、`P:gbuffers_terrain.fsh:116-120` | 与 drdestens 逐字节相同（增量并入 C1） |
| custom lightmap（RG16 打包 + 曲线） | `P:gbuffers_terrain.fsh:291-292`、`P:lib/lightmap.glsl:56-96` | drdestens 同源同函数，旧报告 P3 已列 AO 分曲线 |
| `alphaTest.program.*=off` | `P:shaders.properties:174-190` | drdestens 同源；材料 SUMMARY-batch2（P14b）已列 |
| 辅助缓冲 blend off | `P:shaders.properties:198-199` | Astra 已有更细同类（`A:shaders.properties:338-343`，共 74 行 blend 声明）；材料 batch3 Pegasus 已列 |
| noperspective/flat 插值 | `P:gbuffers_textured.vsh/fsh:12-18` | drdestens `lib/stddef.glsl:13` + 旧报告 2.6 已载；收益存疑（无法判定 5） |
| 顶点手电光 / CPU smooth 链 / profile | `P:deferred.vsh:27-64`、`P:shaders.properties:14-116,231-233` | 材料已列：batch3 BQOL 顶点级预计算、12 包共识 CPU 预计算、一行式 profile |
| 水洼掩码+水面贴图+视差 | `P:gbuffers_terrain.vsh:256-275`、`:167-182` | 材料「水洼掩码+孔隙度」（7 包印证）已列；Astra 已有 `A:global/atmosphere/weather.glsl:21` `astra_puddle`（片段侧稀疏 cell+早退，`A:program/lit.fsh:226`），顶点化不更省，不建议迁移 |
| 液体顶点波浪 | `P:gbuffers_terrain.vsh:238-254` | 材料「顶点位移夹进方块空间」（tea/bvs/sildurs，快赢）已列 |
| 雨条蓝主导判定 / 屏幕雨折射 | `P:gbuffers_weather.fsh:41-76`、`P:composite5.fsh:136-149` | 视觉特性；Astra 已有雨溅粒子颜色过滤，无性能增量 |
| 解析 smoothstep 雾 / 高度雾解析积分 / 噪声雾 | `P:lib/sky.glsl:171-203,224-230,290-302` | 材料 SUMMARY-batch2 ⑤-6 判「雾模型无借鉴价值」；解析高度雾已列 |
| FXAA（luma 存 alpha）/ LUT 调色 / 自定义星 / 极光 GS / PP 程序 / 损血效果 | `P:composite5.fsh:263-275`、`P:composite6.fsh:94-106`、`P:lib/stars.glsl`、`P:gbuffers_skytextured.gsh:58-95`、`P:composite10.fsh` | 材料 batch3 BQOL「alpha 复用」同类；其余为视觉特性，非性能手法 |
| 纹理槽分阶段绑定 | `P:shaders.properties:120-168` | 工程手法；Astra `grep "^texture\." A:shaders.properties` 0 命中。性能价值仅省槽位/采样器，已记入备注，不列 A/B/C |
| 8bit 写前 dither | `P:core/core/dither.glsl:26-28` | 画质（去带），非性能 |
| MC_RENDER_QUALITY/HQ 上采样 | `P:final.fsh:96-105` | 渲染缩放/TAAU 属材料已列 C 组；宏来源不明（无法判定 2） |

---

## 六、无法判定

1. **彩光降采样链的读改写语义无法还原**：composite1-3 在无 `flip` 的情况下同 pass 读改写 colortex6（`P:composite1.fsh:26-53` 等），且象限清零与 composite4 角部采样（`P:composite4.fsh:117` 的 `coord/16+0.9375`）在标准全屏语义下不自洽。无法判定这是有意的打包约定、依赖驱动行为的 UB，还是已被上游修复但本快照未同步；**照抄前必须重写为显式 flip/双缓冲与明确坐标约定**。
2. **`MC_RENDER_QUALITY` 来源不明**：仅出现在 `P:final.fsh:96,102`，包内（含 zip 全清单）无任何 `#define`；同库 drdestens 的 `final.fsh:14,61,70` 同样裸用。无法判定是否由外部运行环境/构建注入；不列为借鉴点。
3. **缓冲格式声明是否生效**：`P:lib/setup.glsl:4-26` 的格式块整体在块注释内，实际格式依赖 Iris 默认（需实机纹理信息验证；材料 ④-2-4 已记录同类）。
4. **colortex0 免清空的适用性**：作者仅在 MC<1.19 启用（`P:lib/setup.glsl:30-31`），Astra 目标版本更高，1.19+ 不启用的原因在包内无注释，适用性未知。
5. **插值限定符收益存疑**：`noperspective/flat` 在光栅化阶段的插值开销在现代 GPU 上很小，本包自述可能破坏画面（`option.AGRESSIVE_OPTIMISATION.comment`），是否值得迁移需实测，本轮不列 A/B/C。
6. **着色器被引用完整性无法穷举验证**：`P:lib/colored_lights_mip.glsl` 为空壳、`composite4.fsh:149-210` 有 `#if 0` 旧实现，无法判定彩光系统是否有未发布完成的 mip/衰减路径。
