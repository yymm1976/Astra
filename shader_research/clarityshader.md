# Clarity v1.1.3 研读报告（面向 Astra 的可借鉴点）

> **撰写方式声明**：本报告由主代理直接撰写，**未派子代理**。原因：本批次调研子代理配额耗尽（连续 10 次 `exceed quota limit`，含 `worker` 与 `Explore` 两种类型），依统帅契约"worker 调用报错即视为 worker 不可用，可自行动手"的例外条款执行。因此本报告的深度与自抽查条数低于同批次由子代理产出的报告（如 `ushader.md`），**④ 对照表的覆盖率也相应更低**，请按此打折使用。

> 引用约定：`P:xxx:行号` 指 `reference_shaderpacks/clarityshader/shaders/` 下的文件；`A:xxx:行号` 指 `Astra/shaders/` 下的文件。所有行号均已在本文成稿时打开源文件核对（自抽查记录见文末）。A 侧只核对了被引用到的行；未逐行核对的 A 侧模块会明确标注。

## ① 包概览

- **名称/版本**：Clarity。**包内没有任何版本字符串**——`P:shaders/prelude/core.glsl:3` 只有占位的 `#define VERSION v`，`P:shaders/lang/en_us.lang` 与 `P:shaders/shaders.properties` 均无版本号。任务书标注 v1.1.3（来自 Modrinth 发布号），本文按任务书口径记录。
- **作者**：Astyll（Modrinth）。下载量 1,020,666（2026-10-02 快照，本批次第 3 高）。
- **许可证**：**包内不存在任何许可证文件**——对 `reference_shaderpacks/clarityshader/` 全包递归查找 `*license*` / `*.txt` / `*.md` 结果为空集，包内只有 `shaders/` 一棵树。Modrinth 元数据标注为 `LicenseRef-All-Rights-...`（保留所有权利）。**结论：默认版权，仅可"阅读并学习"**，详见 ⑤。
- **风格定位**：原版观感 + 阴影 + 极端性能向（Modrinth 分类 `iris, optifine, potato, shadows, vanilla-like`）。真正值得研究的不是它的画面，而是它的**工程取向**：整包仅 1245 行着色器代码（含注释），却提供完整 SMAA、运动模糊、水下路径与 Voxy/DH 支持，并且**把抗锯齿与运动模糊做成 compute 着色器**。
- **管线形态**：gbuffers/shadow 极薄 → `composite.csh`（边检测 + 曝光/鲜艳度 + 运动模糊）→ `composite1.csh`（SMAA 混合权重）→ `composite2.csh`（邻域混合 + sRGB 输出）；另有一条 **`composite.fsh` 的 `#version 120` 非 compute 回退路径**（`P:shaders/composite.fsh:1-20`，只做曝光与鲜艳度，无 SMAA 无运动模糊）。

## ② 架构与特性清单

### 2.1 计算着色器与自定义图像（本包最有价值的部分）
- **三 pass compute 后处理链**：`P:shaders/composite.csh:6-7`（`local_size 16×16` + `workGroupsRender = vec2(1.0,1.0)`）、`P:shaders/composite1.csh:6-7`、`P:shaders/composite2.csh:6-7`。
- **自定义图像声明**：`P:shaders/shaders.properties:40-42` 声明 `tempCol`(rgba16)、`edge`(rg8)、`blendWeight`(rgba8) 三个 image 及其同名 sampler 视图；`P:shaders/shaders.properties:44-45` 用 `customTexture` 载入 SMAA 的 area/search 查找表（`.bin` 资产见 `shaders/tex/smaa_area.bin`、`smaa_search.bin`）。
- **必需特性按选项条件声明**：`P:shaders/shaders.properties:31` 无条件要求 `CUSTOM_IMAGES COMPUTE_SHADERS`；`:32` 在 `ANTIALIASING==1` 时追加 `ENTITY_TRANSLUCENT`。
- **图像写读纪律**：`P:shaders/composite1.csh:130-131` 注释原文 "Unconditionally write to every single texel to completely eliminate VRAM reload garbage leaks"，并在 `:243` 只在 `if (any(e))` 分支外**无条件** `imageStore`——未命中的 texel 也写 0，避免自定义图像残留上一帧数据。
- **工作项与屏幕坐标换算**：`P:shaders/composite.csh:36-39` 用 `gl_GlobalInvocationID.xy` + `pixSize` 得到 uv，配合 `texelFetch` 精确取样，不使用归一化插值。
- **供应商条件常量**：`P:shaders/prelude/core.glsl:10-11` 定义 `CONST_IMMUT` 档位，`:19-23` 展开为 `#define immut const`（仅在 NVIDIA 或强制档开启）；全文大量 `immut vec3/vec4` 局部量，例如 `P:shaders/composite1.csh:201-203`、`P:shaders/prog/generic.fsh:64-68`。

### 2.2 抗锯齿（SMAA 完整实现）
- **边检测**：`P:shaders/composite.csh:100-132`。判据用 `redmeanSq` 加权色距（`:29-33`），阈值 `SMAA_THRESHOLD=0.1`（`P:shaders/prelude/core.glsl:5`，平方比较见 `:107-108`），再乘一个**局部对比度自适应因子**（`:123-125`，`delta_max/4`）压制低对比区的假边。
- **混合权重计算**：`P:shaders/composite1.csh:193-245`。面积查找 `area()`（`:104-110`）、轴向搜索长度查表 `search_length()`（`:112-114`）、四个方向的搜索 `search_x_left/right`、`search_y_up/down`（`:116-154`）、对角线分量 `calculate_diag_weights()`（`:60-101`，含 `decode_diag_bilinear_access` 双线性补偿 `:14-23`）、拐角修正 `corner_rounding` / `detect_*_corner_pattern`（`:156-191`）。
- **邻域混合**：`P:shaders/composite2.csh:13-41`。取本 texel 与右/下邻居的四个权重分量（`:18-22`），权重和近零时直接取原色（`:24-25`），否则按水平/垂直主轴二选一取两侧样本混合（`:27-35`），最后 `srgb()` 输出（`:41`）。

### 2.3 运动模糊（与 TAA 无关的屏幕空间实现）
- `P:shaders/composite.csh:41-81`（`MOTION_BLUR > 0` 时）。重投影：由 `depthtex0` + `gbufferProjectionInverse` + `gbufferModelViewInverse` 还原世界位置，再用 `gbufferPreviousModelView` / `gbufferPreviousProjection` 投影回上一帧（`:42-53`），速度为 `uv - prevUv`（`:56`），强度乘 `0.40`（`:57`）。
- **速度钳制**：`maxVel = 0.06` 截断，防瞬移/急转拉花（`:59-64`）。
- **抖动去阶梯**：IGN 抖动（`:66-67`，`52.9829189 * fract(...)`）让 8 次等距样本在时间上错开（`:69-79`）。
- 仅对 `depth < 1.0` 的几何生效（`:42`）。

### 2.4 天空、雾、天气、水
- **天空**：`P:shaders/prog/sky.fsh:19-26` 用有理函数 `fogify(x,w)=w/(x²+w)` 把 `skyColor` 向 `fogColor` 融合，权重只取视线与"上方"的点积；`:39-50` 在 `MC_RENDER_STAGE_STARS` 阶段丢弃日月圆盘范围内的星点（`dot > 0.98`），并把 `v.tint` 增益 1.5 叠到天空色上。
- **雾**：`P:shaders/prog/generic.fsh:74-78` 取"球面距离雾"与"圆柱边界雾"的 `max`，圆柱判据为 `max(length(pe.xz), abs(pe.y))`，边界起点为 `0.9 * far`；`P:shaders/prelude/core.glsl:16` 定义 `BORDER_FOG_START_RATIO 0.9`。云另走一条只压 alpha 的路径（`P:shaders/prog/generic.fsh:70-72`，`CLOUD_FOG_END 128`，见 `P:shaders/prelude/core.glsl:15`）。
- **水与玻璃**：`P:shaders/gbuffers_water.fsh:17-18` 用自定义 block id 区分水/玻璃，`:33-42` 水按 `WATER_OPACITY`（默认 0.40，`:5`）压 alpha 并乘 1.5 过冲后 clamp（`:37`、`:50`）；玻璃走"纹理 × 顶点色"两通道相乘以保留框的不透明度（`:26-31`）。block id 定义于 `P:shaders/block.properties:1-2`。
- **云**：`P:shaders/gbuffers_clouds.fsh:8-29`，三档 `CLOUD_TYPE`（BRIGHT / DIMMED / HIDDEN），HIDDEN 直接 `discard`（`:14-15`），DIMMED 把 alpha 减半（`:23`）。
- **雨雪**：`P:shaders/gbuffers_weather.fsh:5,15,17` 一个滑杆控制不透明度并丢弃极透明片元。

### 2.5 维度与入口组织
- **`world1/`（末地）全部是单行转发**：例如 `P:shaders/world1/composite.csh:1` = `#include "/composite.csh"`，`P:shaders/world1/gbuffers_terrain.fsh:1` = `#include "/gbuffers_terrain.fsh"`。**没有 `world-1/` 目录**，即下界直接复用根程序。
- **入口风格三代同堂**：`P:shaders/gbuffers_terrain.fsh:1` 是 `#version 120` 直接透传（只乘顶点色），`P:shaders/gbuffers_clouds.fsh:1` 与 `P:shaders/gbuffers_weather.fsh:1` 是 `#version 330 compatibility` 自包含，`P:shaders/gbuffers_skytextured.fsh:1-2` 则是 `#define TEXTURE` + `#include "/prog/generic.fsh"`。
- **远景兼容**：包内带 `shaders/voxy.json`、`voxy_opaque.glsl`、`voxy_translucent.glsl`、`dh_terrain.fsh/.vsh`（各 22 行）。
- **矩阵工具**：`P:shaders/prelude/core.glsl:25-49` 手写 `rot_trans_mmul` / `proj_mmul` / `proj_inv`，用 `fma` 和分量式乘加代替整矩阵乘法。

### 2.6 设置与后处理
- **设置面极小**：`P:shaders/shaders.properties:1-23` 全部可调项只有 7 类（CLOUD_TYPE 三档、STARS、RAIN_SNOW_OPACITY、WATER_OPACITY、WATER_TEXTURE、UNDERWATER_VIGNETTE、EXPOSURE、VIBRANCE、MOTION_BLUR）加 ANTIALIASING 二档；`P:shaders/lang/en_us.lang:1-46` 是全部文案。
- **合并 pass**：曝光与鲜艳度不是独立全屏 pass，而是**搭在边检测这同一次读取里**（`P:shaders/composite.csh:83-98`），随后才写 `tempCol`。
- **水下渐晕**：`P:shaders/composite.csh:88-96`，用 `smoothstep(0.15,0.85,dist)` 把画面边缘混向 `deepBlue * l`（保留亮度 `l` 而非纯色），强度 0.85。
- 非 compute 回退：`P:shaders/composite.fsh:11-20`，`#version 120`，同样做曝光/鲜艳度，读 `gcolor/gnormal/gdepth`。

## ③ Astra 可借鉴点

1. **SMAA 作为 FXAA 与 TAA 之外的第三档抗锯齿**
   技术要点：三 pass 全 compute：边检测（低阈值 + 局部对比度自适应）→ 混合权重（area/search 查找表 + 对角分量 + 拐角修正）→ 邻域混合。比 FXAA 保细节（沿边搜索而非固定核），比 TAA 无历史、无拖影、成本与分辨率线性。Astra 现有 `ANTIALIASING [0 1 2]`（`A:lib/settings.glsl:239-240`）为正交扩展点。
   出处：`P:shaders/composite.csh:100-132`、`P:shaders/composite1.csh:104-245`、`P:shaders/composite2.csh:13-41`、`P:shaders/shaders.properties:31-32,40-45`。
   Astra 对应：`A:lib/settings.glsl:239-240`（档位定义）、`A:program/final.fsh:6`（现 FXAA 的调用点，`#include "/global/post/fxaa.glsl"`）、`A:global/post/fxaa.glsl:24-94`。
   迁移难点与工作量：**中**。需要新增 3 个自定义图像 + 2 个 customTexture 资产 + 3 个 pass，并处理 Iris 的 image/sampler 同名视图与 `clear` 语义；SMAA 的查找表资产需从外部获取（不能从本包复制，见 ⑤）。

2. **`immut` 供应商条件常量宏（纯优化，改动极小）**
   技术要点：`#if (CONST_IMMUT == 1 && defined MC_GL_VENDOR_NVIDIA) || CONST_IMMUT == 2` 时把 `immut` 展开为 `const`，让 NVIDIA 编译器把局部量放进常量缓存/立即数，省寄存器压力。
   出处：`P:shaders/prelude/core.glsl:10-11,19-23`；用例密集处 `P:shaders/composite1.csh:194,198,199,201-203,213-217,230-239`。
   Astra 对应：Astra 无同类宏；可加入 `A:lib/` 作为公共头（Astra 已有大量 `#ifndef` 头件惯例，见 `A:global/post/exposure.glsl:1-2` 的 include guard 写法）。
   迁移难点与工作量：**低**。纯预处理器，无行为变化；风险点是 AMD/Intel 上 `const` 可能反而限制优化，故保留档位开关。

3. **二维屏幕空间 compute 的 `workGroupsRender` 约定与分辨率换算**
   技术要点：全屏 compute pass 声明 `const vec2 workGroupsRender = vec2(1.0,1.0)` 与 `local_size 16×16`，用 `gl_GlobalInvocationID.xy` 直接当 texel 坐标，`pixSize` 处理归一化。这使 pass 与屏幕分辨率解耦，且避免 vsync 下的线程浪费。
   出处：`P:shaders/composite.csh:6-7,36-39`、`P:shaders/composite1.csh:6-7`、`P:shaders/composite2.csh:6-7`、`P:shaders/shaders.properties:38`（`uniform.vec2.pixSize=...`）。
   Astra 对应：`A:program/nether_light.csh:13-14` 只用**体素**约定 `const ivec3 workGroups=ivec3(8,8,8)`，全仓 `grep workGroupsRender` 无命中（Astra 目前没有二维全屏 compute pass）。约定说明见 `A:lib/nether_voxel_grid.glsl:23`。
   迁移难点与工作量：**低**（只是约定与声明），但**Astra 目前没有会用到它的 pass**——只有在采纳第 1 条（SMAA）或其它全屏 compute 后才有意义。

4. **自定义图像的"无条件全量写入"纪律**
   技术要点：自定义图像不像 framebuffer 那样每帧被清空，未写入的 texel 会保留上一帧内容并产生"回读垃圾"。Clarity 的解法是**每个 texel 都写**（未命中边缘的写 0），并在注释里点明原因。
   出处：`P:shaders/composite1.csh:130-131,243`。
   Astra 对应：Astra 的下界体素光用 `clear=true` 的 image 指令绕过该问题（见 `A:program/nether_light.csh:5-7` 的注释"cleared every frame (clear=true in the image directive)"）。**Astra 已有等价纪律**，但一旦新增非 clear 的 image（如 SMAA 的 blendWeight），这条纪律必须复用。
   迁移难点与工作量：**低**（纪律性，无代码量）。

5. **运动模糊（重投影 + 速度钳制 + IGN 抖动）**
   技术要点：屏幕空间速度 → 速度长度上限钳制（0.06）→ 8 个 IGN 抖动样本平均。全部只用上一帧矩阵，无历史缓冲、无累积，因此**不引入拖影残留**，成本固定。可作为 Astra 的一个可选后处理档。
   出处：`P:shaders/composite.csh:41-81`（重投影 `:42-53`、钳制 `:59-64`、抖动与采样 `:66-79`）。
   Astra 对应：Astra 没有运动模糊（全仓搜索 `MOTION_BLUR` / `motion_blur` 零命中）；但它已有 TAA 的"真实前帧相机 + 前帧投影"基础设施（`A:program/taa_resolve.fsh`、`A:lib/taa_state.glsl`、`A:lib/effect_history.glsl`），重投影部分可直接沿用现成 uniform。
   迁移难点与工作量：**低-中**。难点不在数学而在产品定位：Astra 的 TAA 已提供动态模糊感，运动模糊与之叠加需确认不冲突（Clarity 的做法天然独立，因为它不读历史）。

6. **`redmeanSq` 加权色距替换欧氏/luma 差**
   技术要点：`dot(d*d, vec3(2+r, 4, 3-r))`，其中 `r` 取两色红通道均值——比等权 RGB 距更接近人眼感知，成本 1 次 dot。
   出处：`P:shaders/composite.csh:29-33`。
   Astra 对应：`A:global/post/fxaa.glsl:60-94` 的边缘判据走 luma 差（以 luma 存在 alpha 通道，见 `A:global/post/fxaa.glsl:4` 的注释"display RGB + luma in alpha"）。
   迁移难点与工作量：**低**。但需注意 Astra 的 luma 是**单通道紧打包**（省带宽），换成 RGB 色距会破掉这个打包设计，需先确认收益是否值得加带宽。

7. **局部对比度自适应的边阈值**
   技术要点：候选边还需满足 `delta >= max(delta_max) / 4`（即局部最大对比的 1/4 以上），避免在低对比噪点区、渐变区产生假边。这是对固定阈值的低成本增强。
   出处：`P:shaders/composite.csh:111-128`，因子定义于 `:123`。
   Astra 对应：`A:global/post/fxaa.glsl:27-38` 用**深度轮廓门**做类似的事（`geometryOnly` 时只有深度跳变足够大才做 AA），思路相近但判据不同（深度 vs 颜色对比）。两者可叠加：深度门控几何边、对比度门控纹理边。
   迁移难点与工作量：**低**。把 `delta_max` 的四邻读取加进现有边判据即可（Astra 已经在 `:41-50` 读了四邻）。

8. **水下渐晕：保亮度混向深蓝**
   技术要点：`mix(color, deepBlue * l, smoothstep(0.15,0.85,dist) * 0.85)`——用**当前像素亮度**乘目标色，而非直接把边缘压黑，因此不丢失暗部结构。
   出处：`P:shaders/composite.csh:88-96`。
   Astra 对应：Astra 已有**全局**渐晕（`A:global/post/grading.glsl:103-105`，`VIGNETTE_STRENGTH 0.55` / `VIGNETTE_FALLOFF 2.0`），但那不是水下专项；水下显示分支的说明见 `A:global/post/grading.glsl:27`。
   迁移难点与工作量：**低**。可作为水下分支的叠加项；需先确认 Astra 水下是否已有等效对比收束（本次未逐行核对 `A:global/water/absorption.glsl` 与 `A:global/atmosphere/fog.glsl` 的水下路径）。

9. **球面 + 圆柱双判据雾取 max**
   技术要点：球面项管近处体积感，圆柱项管"远处不该有雾分层"的边界（`max(length(pe.xz), abs(pe.y))` 在接近 `far` 时强制起雾），取 `max` 保证高空与远地平线都不出现硬边。
   出处：`P:shaders/prog/generic.fsh:74-78`，常量 `P:shaders/prelude/core.glsl:16`。
   Astra 对应：`A:global/atmosphere/fog.glsl:208`（`fog_air_perspective`）、`:230`（`fog_biome_tint`）、`:163`（引用了 Solas 的指数形式）。
   迁移难点与工作量：**低-中**。Astra 的雾已远比 Clarity 复杂（含生物群系染色与空气透视），这条更适合作为"远处边界防漏"的补充判据，而非替换。

10. **按选项条件声明 Iris 必需特性**
    技术要点：默认只要求 `CUSTOM_IMAGES COMPUTE_SHADERS`，开启 SMAA 时才追加 `ENTITY_TRANSLUCENT`——避免默认档位因某个可选效果的必需特性不满足而整体加载失败。
    出处：`P:shaders/shaders.properties:31-32`。
    Astra 对应：`A:shaders.properties:692` 已声明 `iris.features.optional=CUSTOM_IMAGES COMPUTE_SHADERS`，但**没有按选项切换 `iris.features.required` 的机制**。Astra 有大量可选效果（体积雾、SSAO、方向性天光、下界体素光），若某个可选效果依赖的特性缺失，当前只能整体失败或降级不生效。
    迁移难点与工作量：**低**（改写 properties 声明），但需要先列出每个可选特性→Iris 特性的映射，属调研性工作。

11. **把曝光/鲜艳度搭进已有的全屏读取（省一次全屏 pass）**
    技术要点：边检测本来就要读 `colortex0` 与 `depthtex0`，曝光与鲜艳度就挂在这同一次读取上，再写 `tempCol`；不额外开 pass。Astra 的曝光是独立模块（`A:global/post/exposure.glsl:82` `astra_ae_meter`、`:147` `astra_ae_gain`）。
    出处：`P:shaders/composite.csh:83-98`。
    Astra 对应：`A:global/post/exposure.glsl:82,147`、`A:global/post/grading.glsl`。
    迁移难点与工作量：**中-高**。Astra 的自动曝光是**测量型**（需要独立测量 pass，`astra_ae_meter` 采样场景），与 Clarity 的固定增益型曝光不同构，不能直接合并；此条仅作"pass 预算意识"的参照，不建议照搬。

12. **极端精简的设置面（反向参照）**
    技术要点：7 类设置拿到 102 万下载。Astra 现有 163 个 `#define`（`A:lib/settings.glsl` 统计 163 行 `^#define`）与 66 个 RGB 通道设置。这不是"抄什么"，而是判断"哪些设置其实可以合并/预设化"的对照样本。
    出处：`P:shaders/shaders.properties:1-23`、`P:shaders/lang/en_us.lang:1-46`。
    Astra 对应：`A:lib/settings.glsl`、`A:shaders.properties`。
    迁移难点与工作量：**不适用**（设计取向差异，非技术移植）。

## ④ Astra 已有对应实现（对照）

| 主题 | Astra 现状（文件:行） | 两边对比 |
|---|---|---|
| 抗锯齿 | `A:lib/settings.glsl:239-240`（0 关 / 1 FXAA / 2 TAA）；FXAA 实现 `A:global/post/fxaa.glsl:24-94`，调用点 `A:program/final.fsh:6` | Astra 是"关 / FXAA / TAA"三选一，缺 **SMAA** 这档。Astra 的 FXAA 有 Clarity 没有的**深度轮廓门**（`A:global/post/fxaa.glsl:27-38`，只在几何轮廓上做 AA）与**有界 24 次 luma 读取**（`:60-94`）；Clarity 的 SMAA 有 Astra 没有的**沿边搜索 + 面积查找表 + 拐角修正**，边缘质量更高。两者不是替代关系，是互补档位。 |
| 自定义图像 | `A:program/nether_light.csh:13-14`（体素 compute，`workGroups ivec3`）；图像 clear 语义见 `A:program/nether_light.csh:5-7` 注释 | Astra 已有 image 用法与"每帧清空"纪律，但**没有二维全屏 compute 的 `workGroupsRender` 约定**（全仓零命中）。Clarity 补上了这块约定样本。 |
| 必需特性声明 | `A:shaders.properties:692`（`iris.features.optional=CUSTOM_IMAGES COMPUTE_SHADERS`） | Astra 只声明 optional，未做"按选项切换 required"。Clarity 展示了条件声明的写法（`P:shaders/shaders.properties:32`）。**哪边更省**：都是编译期字符串，成本相同；差别只在"特性缺失时的报错/降级行为"。 |
| 运动模糊 | **无**（全仓 `MOTION_BLUR` 零命中） | Clarity 提供一套无法失的屏幕空间实现。误差来源：Clarity 的模糊在**当帧已做曝光/鲜艳度之后**、在 sRGB 转换之前，与 Astra 的 HDR 管线位置需要重新对齐。 |
| 渐晕 | `A:global/post/grading.glsl:103-105`（全局，强度 0.55） | Astra 有全局渐晕但没有**水下专项**；Clarity 的"保亮度混深蓝"在暗部保结构上更精细。误差来源：Astra 的水下已经过吸收模型（`A:global/water/absorption.glsl`，**本次未逐行核对**），叠加渐晕可能重复压暗，需要实机确认。 |
| 雾 | `A:global/atmosphere/fog.glsl:208,230,163`（空气透视 + 生物群系染色 + Solas 指数形式） | Astra 的雾在维度、群系、天气上都远比 Clarity 细。Clarity 唯一的结构性补充是"圆柱边界雾"（`P:shaders/prog/generic.fsh:76-77`）。**Astra 没有逐行核对是否存在等效的 far 边界强制起雾**，故此项的"是否已经更省"无法判定。 |
| 天空 | `A:global/atmosphere/sky_gradient.glsl`、`sky_minishita.glsl`（多向调色板 + 物理散射） | Clarity 的 `fogify` 是 6 行的地平线融合，Astra 的天穹已远超此。唯一可借的是 `P:shaders/prog/sky.fsh:39-50` 的**星点日月剔除**（`dot > 0.98` 时丢弃星），Astra 的 `A:global/atmosphere/stars.glsl` **本次未核对**是否已有该处理。 |
| 水/玻璃入口 | `A:gbuffers_water.fsh`、`A:global/water/*`（含折射/焦散/光束） | Clarity 只有"压 alpha + 顶点色相乘"（`P:shaders/gbuffers_water.fsh:33-48`），层级低得多。其 `blockId` 分支（`:17-18`）在 Astra 由 `A:block.properties` 承担。**结论：无可借鉴，仅作最低配参照。** |
| 维度组织 | Astra README 记载"根目录、`world-1/`、`world1/` 薄入口" | 两家做法一致；Clarity 的 `world1/*` 是纯单行 `#include` 转发（`P:shaders/world1/composite.csh:1`），且**没有 `world-1/`**（下界直接复用根程序）。Astra 的下界有自己的链，覆盖更细。 |
| 设置面 | 163 个 `#define`（`A:lib/settings.glsl`）+ 66 个 RGB 设置 | Clarity 7 类。无对错，仅规模对照。 |

**④ 覆盖率声明**：本表未覆盖 Astra 的下界体素光、末地 Kerr 天空、TAA 细节、SSAO、方向性天光、体积雾六个模块（Clarity 无对应物），也未逐行核对 `A:global/water/absorption.glsl`、`A:global/atmosphere/stars.glsl`、`A:global/atmosphere/fog.glsl` 的水下与星辰分支——上表中这三处已标注"未核对"。

## ⑤ 借鉴可行性（许可证层面）

**本包没有许可证文件**。对 `reference_shaderpacks/clarityshader/` 全包递归检索 `*license*`、`*.txt`、`*.md` 全部为空，包内只有 `shaders/` 一棵源码树；`P:shaders/prelude/core.glsl:1-11` 是唯一的"头部声明"位置，里面只有版本占位与 SMAA 参数，**没有任何版权、许可或作者声明**。Modrinth 元数据侧标注为 `LicenseRef-All-Rights-...`。

因此**无法引用许可证原文行号**（不存在这样的行），判定只能依默认规则：

- **读思路、独立重写：可行**。算法思想（如"用局部对比度自适应阈值抑制假边""用圆柱判据补 far 边界雾"）不受版权保护，独立实现不构成侵权。本报告 ③ 中的第 2、4、6、7、9、10 条都属于这一档，风险低。
- **直接抄代码：高风险**。没有许可授权，逐行或近逐行搬运（尤其 `P:shaders/composite1.csh:104-245` 的 SMAA 权重计算、`P:shaders/composite.csh:41-81` 的运动模糊）会落入"保留所有权利"的默认限制；Astra 若上架任何平台都可能被下架或追责。
- **重要旁路**：SMAA 本身是 **Jimenez 等人公开发表的算法**（有官方开源实现与论文，许可是 MIT 系）。**若确实要落地 SMAA，应取上游公开实现或自行依论文实现，而不是从本包复制**——这既回避了 Clarity 的许可问题，也拿到了质量更有保证的参考实现。同理，IGN 抖动常数（`52.9829189`）来自 Jorge Jimenez 的公开成果。
- 本报告 ③ 第 1 条若采纳，**资产（`shaders/tex/smaa_area.bin`、`smaa_search.bin`）同样不能从本包复制**，需从上游 SMAA 发行版获取。

**结论**：Clarity 对本批次的价值应限定为"**工程取向样本**"（compute 化后处理、pass 预算、图像写读纪律、设置面克制），代码级复用一律走"重写 + 上游公开实现"路线。

## ⑥ Top3 优先建议（按 收益/工作量 排序）

1. **SMAA 作为第三档抗锯齿（③1）** —— 收益：补上"比 FXAA 干净、比 TAA 无历史负担"的中间档，对动态场景（云、水、植被）比现有的 `geometryOnly` FXAA 更完整；工作量：中。**前置条件**：从上游 SMAA 公开实现取查找表，不从本包复制。建议先做一个离线对照（固定机位四屏：关 / FXAA / SMAA / TAA），确认在 Astra 的 HDR→显示映射链里 SMAA 应放在哪一步——注意 Clarity 把它放在曝光之后、sRGB 之前（`P:shaders/composite.csh:98` 写 linear 值给 `tempCol`，`P:shaders/composite2.csh:41` 才 `srgb()`）。
2. **`immut` 宏 + 局部对比度阈值 + 边阈值自查（③2、③7）** —— 收益：纯优化与抗噪，直接改善现有 FXAA 的稳定性和寄存器压力；工作量：低。`immut` 是纯预处理，可先在单个 pass 试水并用同一机位对比帧时；对比度阈值改的是 `A:global/post/fxaa.glsl` 里已经存在的四邻读取（`:41-50`），不加带宽。
3. **水下渐晕专项（③8）** —— 收益：水下"闭拢感"，几行代码；工作量：低。**但必须先核对 Astra 水下是否已有等效压暗**（`A:global/water/absorption.glsl` 与 `A:global/atmosphere/fog.glsl` 的水下分支本次未读），否则会重复压暗。

**暂缓项**

- **运动模糊（③5）**：Astra 已有 TAA，运动模糊与之叠加的产品定位不清晰；且它在 Clarity 里位于曝光之后，移植到 Astra 需要先决定它在 HDR 链中的位置。建议等前三项落地、且用户明确要求"电影感"档位时再评估。
- **曝光/鲜艳度合并进边检测 pass（③11）**：Astra 的自动曝光是测量型（`A:global/post/exposure.glsl:82`），与 Clarity 的固定增益不同构，不可直接合并。
- **SMAA 的对角分量与拐角修正（`P:shaders/composite1.csh:60-101,156-191`）**：这两块占总代码量一半以上，收益集中在细长斜边与文字/UI 边缘；首版实现可先取轴向分量（`:116-154`）+ 面积查找（`:104-110`），验证收益后再决定是否补齐。**注意此判断未经实测，属推测。**

## 附：自抽查记录（13 条，成稿后逐一重新打开核对）

1. `P:shaders/prelude/core.glsl:3` `#define VERSION v`（版本占位）—— 核对一致。
2. `P:shaders/prelude/core.glsl:5` `SMAA_THRESHOLD 0.1` —— 核对一致。
3. `P:shaders/prelude/core.glsl:10-11` `DEBUG_BW` / `CONST_IMMUT` —— 核对一致。
4. `P:shaders/prelude/core.glsl:19-23` `immut` 宏定义（NVIDIA 条件）—— 核对一致。
5. `P:shaders/prelude/core.glsl:25-49` 三个矩阵工具函数 —— 核对一致（25 `rot_trans_mmul(mat4,vec2)`、29 重载、33 `proj_mmul`、41 `proj_inv`）。
6. `P:shaders/composite.csh:29-33` `redmeanSq`，权重 `vec3(2.0+r, 4.0, 3.0-r)` —— 核对一致。
7. `P:shaders/composite.csh:57` `velocity *= MOTION_BLUR * 0.40;` —— 核对一致。
8. `P:shaders/composite.csh:60-64` `maxVel = 0.06` 钳制 —— 核对一致。
9. `P:shaders/composite.csh:88-96` 水下渐晕，`smoothstep(0.15, 0.85, dist)`、`deepBlue = vec3(0.02,0.15,0.5)`、系数 0.85 —— 核对一致。
10. `P:shaders/composite.csh:123-125` `local_contrast_factor_sq = 4.0` 与 `temp` 判据 —— 核对一致。
11. `P:shaders/composite1.csh:130-131` 无条件写入的注释原文 —— 核对一致（"Unconditionally write to every single texel to completely eliminate VRAM reload garbage leaks"）。
12. `P:shaders/composite2.csh:41` `imageStore(colorimg0, texel, vec4(srgb(color), 0.0));` —— 核对一致。
13. `P:shaders/prog/generic.fsh:74-78` 球面/圆柱雾取 max，`BORDER_FOG_START_RATIO * far` —— 核对一致。
14. `P:shaders/shaders.properties:31-32` `iris.features.required=CUSTOM_IMAGES COMPUTE_SHADERS` 及其条件追加 —— 核对一致。
15. `P:shaders/shaders.properties:40-42` 三个 `image.*` 声明 —— 核对一致。
16. `P:shaders/gbuffers_water.fsh:17-18` blockId 10001/10002 —— 核对一致（`abs(blockId-10001.0) < 0.5`）。
17. `P:shaders/world1/composite.csh:1` = `#include "/composite.csh"` —— 核对一致。
18. `P:shaders/block.properties:1-2` —— 核对一致。
19. A 侧：`A:lib/settings.glsl:239-240` `ANTIALIASING 1 // [0 1 2]` 与"0 off, 1 display-space FXAA, 2 HDR temporal AA"注释 —— 核对一致。
20. A 侧：`A:program/final.fsh:6` `#include "/global/post/fxaa.glsl"` —— 核对一致。
21. A 侧：`A:global/post/fxaa.glsl:27-38` `geometryOnly` 深度轮廓门（阈值 `max((1.0-depth)*0.08, 0.00001)`）—— 核对一致。
22. A 侧：`A:global/post/grading.glsl:103-105` `VIGNETTE_STRENGTH 0.55` / `VIGNETTE_FALLOFF 2.0` —— 核对一致。
23. A 侧：`A:shaders.properties:692` `iris.features.optional=CUSTOM_IMAGES COMPUTE_SHADERS` —— 核对一致。
24. A 侧：`A:program/nether_light.csh:13-14` `local_size 8×8×8` + `workGroups ivec3(8,8,8)` —— 核对一致。
25. A 侧：全仓 `grep workGroupsRender` 零命中 —— 核对一致（用于支撑"③3 Astra 无二维全屏 compute 约定"）。

**未核对项（明确声明）**：`A:global/water/absorption.glsl`、`A:global/atmosphere/stars.glsl`、`A:global/atmosphere/fog.glsl` 的水下/星辰/far 边界分支未逐行阅读；③8、④ 表中相关结论已相应标注为"需实机或后续核对"。Clarity 的 `world1/gbuffers_*.fsh` 除抽样两件外未逐一打开，但其为单行 `#include` 转发的模式已由多个样本（`world1/composite.csh`、`world1/gbuffers_terrain.fsh`、`world1/gbuffers_basic.fsh`）确认。
