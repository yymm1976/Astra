# FastPBR 2.0 研读报告（面向 Astra）

研究对象：`reference_shaderpacks/fastpbr/`（FastPBR v2.0，RRe36）。对照物：`Astra/shaders/`。
所有行号基于本仓库内快照，已逐条抽查。

## ① 包概览

- 版本与作者：`option.INFO=FastPBR by RRe36`、`value.INFO.0=v2.0`（shaders/lang/en_US.lang:1-2）。
- 许可证：自定义版权协议，"Copyright (C) 2025 RRe36, All Rights Reserved"（LICENSE:1-2）；文件内头注释多写 2023（如 lib/brdf/material.glsl:4），以 LICENSE 为准。
- 硬性门槛：`iris.features.required=SSBO COMPUTE_SHADERS CUSTOM_IMAGES`（shaders/shaders.properties:128），并声明 3 个 bufferObject 与自定义 image（shaders.properties:130-135）。这是"compute 重度化"的现代管线，OptiFine 兼容性不是它的目标。
- 风格定位：190 万下载量级的"真实感但便宜"PBR 包。直接光照在 gbuffer 阶段前向完成（program/gbuffer/forward.fsh），延迟段只做镜面高光、AO/GI、云雾与后处理；大量 pass 降到 1/4 或 1/2 分辨率用 compute 跑。
- 值得注意的"诚实性"细节：设置界面里存在 `resourcepackReflectionsEnabled`（settings.glsl:79，默认注释）与 `roughReflectionsEnabled`（settings.glsl:80），但全包检索显示二者在着色器代码中零引用；composite3.fsh:94-115 定义的 GGX VNDF 采样（注明来自 zombye 的 Spectrum）同样只定义未调用。即本快照中"粗糙反射"是未接线的预留/遗留功能。

## ② 架构与特性清单

### 材质系统（labPBR 解析 / 光滑度 / 金属度 / 法线）

- labPBR 高光贴图在 gbuffer 采样一次：`uniform sampler2D specular;`（program/gbuffer/forward.fsh:56），`sceneMaterial = texture(specular, uv)`（forward.fsh:287），仅取 xy 两字节打包进 GData.w（forward.fsh:393）。通道 z（孔隙/SSS）与 w（自发费光）整包未消费——刻意省略。
- 解码在合成段进行而非 gbuffer：`decodeLabBasic`（lib/brdf/material.glsl:44-60）——
  ```
  material.roughness  = sqr(1.0 - data.r);
  material.f0         = clamp(data.g, 0.02, 0.9);
  material.conductor  = integerF0 >= 230;
  ```
  光滑度→粗糙度用平方重映射；f0 下限 0.02 上限 0.9；F0>=230 判金属。
- 金属度是"复折射率级"的：230-237 映射 8 种金属的 n/k 双系数表（lib/brdf/material.glsl:29-38），供导体 Fresnel 用；非复金属走"以反照率染色"的近似（specular.glsl:81）。
- 法线解码支持 labPBR 与旧式两种格式，由 `normalmapFormat` 选择（settings.glsl:72-73）：format 0 从 z 通道恢复 AO，format 1 用向量长度当 AO（program/gbuffer/forward.fsh:63-77）；法线贴图近全零时回退顶点法线（forward.fsh:64）。
- 材质 ID 来自 block.properties（block.10xxx 段，block.properties:1-65），水体=102，在 gbuffer 与合成段共用（world0/composite3.fsh:330-332）。
- 雨湿地面：本包没有粗糙度/颜色级的湿地响应，wetness 只作用于天空色（lib/atmos/colorsDefault.glsl:43）、云量（lib/atmos/clouds/common.glsl:62,178）与直射光颜色（program/prep/colorPrep.comp:30）；设置界面引用的 `wetnessMode` 在 settings.glsl 中未定义（shaders.properties:33 残留）。这是省出来的性能。

### 镜面与反射

- 直接镜面高光（太阳/月亮）在合成段一次性完成：非水面 `specularTrowbridgeReitzGGX`（world0/composite3.fsh:377；实现 lib/brdf/specular.glsl:61-105，D_GGX + Smith-Schlick G + 介电/导体 Fresnel），水面用 Beckmann（composite3.fsh:374；specular.glsl:107）。
- 高光能量不在合成段重算阴影：gbuffer 阶段把"直射光×阴影"与反照率用 RGBE8 编码塞进 colortex6（forward.fsh:187-195），合成段解包后 `min(直射光, DirectLight)` 截断（composite3.fsh:334-338）——高光只在被照亮处出现，天然无漏光。
- SSR 只给水面：8 步固定步进 + 屏幕空间归一化方向（world0/composite3.fsh:124-172，`const uint maxSteps = 8`），DH 区间另有 6 步 LOD 版本（composite3.fsh:182-219）；未命中回落到"投影天空盒"缓存 colortex3（composite3.fsh:223-225），天空盒缓存本身只有 256x384（shaders.properties:126）。
- 天空遮挡不靠 raymarch：用水亮度图阈值平滑（composite3.fsh:353）。
- 水面法线：解析波函数 4 次采样差分 + 5 步视差（program/gbuffer/forward.fsh:206-252），步距随视距指数缩放（forward.fsh:244）。
- 下界与主世界共用同一套 specular 管线（program/gbuffer/nether/forward.fsh:201），无维度特化。

### 阴影与光照

- 彩色阴影：shadowcolor0 + 双 shadowtex 比较，半透明遮挡>=实心遮挡时返回白（forward.fsh:126-135）。
- 软阴影：硬件 PCF `textureGather` 4 样本双线性（forward.fsh:137-158），外层 R2 低差异序列旋转圆盘，默认 4 迭代（forward.fsh:160-185；settings.glsl:46-47）。
- 天光：compute 把降采样天空盒聚合为 SH9 系数（program/prep/skylightSH.comp:1-20 共享内存归约），gbuffer 用 `ProjectIrradiance(RColorTable.SkylightSH, normal)` 取方向性天光（forward.fsh:356）。
- 环境光三档：`AMBIENT_LIGHT_MODE` 0/1/2（settings.glsl:42）——0 纯 lightmap，1 半分辨率 SSAO（BSL 授权版，HBIL.csh:62-110），2 HBIL 单次弹射 GI+AO（下条）。
- HBIL：1 slice × 4 水平样本的水平积分 GI（program/deferred/HBIL.csh:179-271），半分辨率 compute（HBIL.csh:22），历史重投影 + 双线性四点混合，历史上限 256 帧（HBIL.csh:284,323）。
- 方块光：默认曲线贴图，发光明亮物（火把等）额外乘反照率亮度（forward.fsh:371-379）。
- 漏光防护是可选开关（settings.glsl:43；forward.fsh:345-347，直接乘亮度图斜坡）。

### 大气

- 大气密度完全解析（Chapman 型闭式解，无 raymarch）：lib/atmos/air/density.glsl:5-14——
  ```
  vec3 GetAtmosphereDensity(vec3 Direction) {
      float y     = -Direction.y * planetRad;
      ...
      return vec3(z.xy, max0(z.w-z.z) * pi4) * airDensityCoeff;
  ```
- 天空散射=单次散射解析式 + 简化多次散射项（lib/atmos/air/atmosphere.glsl:33-113），含臭氧层双指数分布（lib/atmos/air/const.glsl:14-24）。
- 大气浓度随"一天八时段"线性混合并受湿度影响（shaders.properties:241-263 的 timeMorning..timeDusk 权重表与 airDensityCoeff）。
- 云分两层：体积云 + 平面云独立开关（settings.glsl:19-20），体积云步数自适应地形遮挡（world0/deferred.csh:39-45），光程遮蔽另跑 2-8 步小 march（lib/atmos/clouds/common.glsl:94-135）；整个云/大气系统跑在 1/4 分辨率 compute（world0/deferred.csh:4）。
- 末地有独立云开关与天空（settings.glsl:22-23；lib/atmos/clouds/RDim_End.glsl）。

### 后处理

- 曝光：加权平均亮度 + 明暗分布百分比钳制的"复杂曝光"（program/grade/exposure.vsh:38-75；settings.glsl:110-112），另有 EV 手动模式。
- TAA：closest-depth 重投影 + YCoCg AABB 邻域钳制（program/post/temporal.fsh:238-251），可选抗闪烁与亮度拒绝（settings.glsl:60）；抖动用黄金比例/ plastic 常数序列，在 properties 层算好（shaders.properties:151-156）。
- TAAU 上采样后接 FXAA 补刀（settings.glsl:128-130），渲染分辨率可缩放 `ResolutionScale`（lib/downscaleTransform.glsl:1-6，gbuffer 侧 viewport 裁剪 forward.fsh:257）。
- 锐化用 AMD CAS（program/grade/final.fsh:57,138-139）；色调映射是自定义 REC2020 样条（program/grade/grading.fsh:215,405）；色深可选 6/8/10bit（shaders.properties:262 注释）。
- 镜头：Bokeh DoF（settings.glsl:96-102）、anamorph 变形宽荧幕拉伸的泊松散景光斑（program/post/lens_0.fsh:45-56）、动态模糊（settings.glsl:123-125）、构图工具（shaders.properties:65）。

### 性能与时域

- "Fast"的实锤清单：镜面只留直接高光（粗糙反射未接线，见①）；SSR 仅水面 8 步；大气/天空/云全解析或 1/4 分辨率；HBIL/SSAO 半分辨率；直接光照前向一次算完且打包复用；labPBR 只解码 2 通道；无湿地材质、无 SSS 专用通道消费。
- 时域复用集中在三处：HBIL 历史（256 帧）、TAA（AABB 钳制）、云/雾通过半分辨率+噪声时域旋转隐含降噪；世界动画时间自定义 uniform `worldAnimTime`（shaders.properties:145）支持水面波浪与大气动画与日夜解耦。
- 全局常量表走 SSBO：RColorTable（lib/head.glsl:26-37），由 colorPrep.comp 每 pass 填充（program/prep/colorPrep.comp:16-33），避免每个 pass 重算大气光照。

## ③ Astra 可借鉴点

1. **RGBE8 打包"直射光×阴影"供合成段镜面复用**
   - 技术描述：gbuffer 阶段把每像素直射光照结果与反照率用 RGBE8 编码写进一个 RGBA16F 缓冲（4 字节×2），延迟镜面段解包取用，高光能量与实际受光状态严格一致，且大动态范围不溢出。
   - 包内出处：program/gbuffer/forward.fsh:187-195、385；world0/composite3.fsh:117-122,334-338。
   - 对应 Astra 模块：Astra/shaders/global/water/raytrace.glsl（SSR 只管水）；Astra/shaders/lib/water_buffer_formats.glsl（缓冲打包）；非水表面的高光目前依赖 global/lighting/diffuse.glsl 前向计算。
   - 迁移难点：中。Astra 是前向+逐 pass 叠加结构，没有"合成段统一镜面"的位置；若只为水面太阳高光（specular sun highlight）引入，需要在水 pass 能读到直射光×阴影——可先从阴影缓冲/colortex 复制链评估，约一个新缓冲 + 写读两端。

2. **金属 F0 表驱动导体响应（labPBR 230-237 全解码）**
   - 技术描述：F0 字节 >=230 判金属并映射 8 组 n/k 复折射率，用导体 Fresnel 给镜面上色；231-237 为"复金属"。
   - 包内出处：lib/brdf/material.glsl:44-60（解码）、29-38（金属表）；lib/brdf/specular.glsl:75-83（导体分支）。
   - 对应 Astra 模块：Astra/shaders/lib/rock_material.glsl（现有的是"纹理驱动光滑度"，无金属概念）；Astra/shaders/global/dimension/nether_reflection.glsl:7-23（固定介电 Fresnel）。
   - 迁移难点：中低。Astra 若决定支持 labPBR 资源包，这张 8 组 mat2x3 表与分支可直接照抄结构；工作量集中在 Astra 现有材质标记体系里开一个"labPBR 存在"检测位。

3. **无 PBR 资源包时的观感兜底策略（反向借鉴）**
   - 技术描述：FastPBR 无兜底——specular 贴图缺失时 data=(0,0)，`roughness=sqr(1-0)=1` 全粗糙、`f0=0.02` 标准介电（lib/brdf/material.glsl:44-48），即所有原版方块退化为纯漫反射，观感靠前向直射光+AO 撑。Astra 的"光滑度由原版纹理推"（rock_material.glsl:7-19）其实是比它更强的兜底，这是 Astra 的差异化优势，应保留而非对齐 FastPBR。
   - 包内出处：lib/brdf/material.glsl:44-48（回退数值）；settings.glsl:79（资源包反射选项未实现）。
   - 对应 Astra 模块：Astra/shaders/lib/rock_material.glsl:7-19、Astra/shaders/lib/surface_emission.glsl:5-12。
   - 迁移难点：无（结论性借鉴：不需要改）。可补一个小改进——FastPBR 对法线贴图缺失回退顶点法线的写法（forward.fsh:64）值得 Astra 在未来支持 labPBR 法线时同款处理。

4. **解析大气密度闭式解**
   - 技术描述：行星半径几何 + 标高直接写出 Rayleigh/Mie/臭氧光学厚度，零迭代；单次散射+近似多次散射全部闭式。
   - 包内出处：lib/atmos/air/density.glsl:5-14；lib/atmos/air/atmosphere.glsl:33-58（照明度）与 73-113（天空散射）。
   - 对应 Astra 模块：Astra/shaders/global/atmosphere/（现有天空实现，Astra 已有物理渐变天空）；Astra/shaders/lib/sky_sh9.glsl（SH9 投影的输入端）。
   - 迁移难点：不确定——未逐行核对 Astra 现有大气是否已是解析式；若 Astra 天空已在采样层做 march，这里可省每像素几十次迭代。需先核对 Astra/global/atmosphere 现状再立项。

5. **半分辨率 compute + 共享内存归约做天光/云**
   - 技术描述：天光 SH 系数在 8x8 workgroup 内共享内存归约（skylightSH.comp:15-20）；云与大气 prep 跑 1/4 分辨率（deferred.csh:4, atmosPrep.comp:1-2）；步数按穿越厚度自适应（deferred.csh:39-45）。
   - 包内出处：program/prep/skylightSH.comp:1-20；world0/deferred.csh:4,39-45。
   - 对应 Astra 模块：Astra/shaders/lib/sky_sh9.glsl（SH9 已有，投影来源与分辨率策略可对照）；Astra/shaders/prepare*.fsh（Astra 的准备段全是 fragment，无 compute）。
   - 迁移难点：高。Astra 目前零 compute（Iris 支持但 Astra 未用，见其 voxy/引擎注释）；引入 compute 管线是架构级决定，不是单点移植。

6. **自适应步数 + 缓存天空盒的水面反射回落**
   - 技术描述：SSR 未命中不重算天空，而是查 256x384 的预投影天空缓存（projectSky/unprojectSky 双向映射，lib/atmos/project.glsl:24-35）；水亮度图阈值直接当天空遮挡（composite3.fsh:353）。
   - 包内出处：world0/composite3.fsh:223-225（readSkybox）、353（skyOcclusion）；shaders.properties:126（缓存尺寸）。
   - 对应 Astra 模块：Astra/shaders/global/water/raytrace.glsl:62（24 步 SSR，未命中回落逻辑在调用方）；Astra/shaders/lib/sky_reflection_cache.glsl（Astra 已有天空反射缓存——具体机制未核对）。
   - 迁移难点：低-中。Astra 已有 sky_reflection_cache，若其未覆盖"SSR miss → 缓存天空"，补一条查表即可；两套投影映射需对齐。

7. **R2 序列旋转圆盘软阴影（硬件 PCF 内核）**
   - 技术描述：textureGather 4 样本双线性作为最小过滤单元，外层 R2 低差异序列做旋转泊松盘，迭代数可调（4-16）。
   - 包内出处：program/gbuffer/forward.fsh:137-185；settings.glsl:46-47。
   - 对应 Astra 模块：Astra/shaders/shadow.fsh / lib/settings.glsl:33-75（SHADOW_FILTER_MODE 分硬件/软件，QUALITY 0-2）。
   - 迁移难点：低。Astra 已有等价的硬件滤波档（SHADOW_FILTER_HARDWARE），此条只在 Astra 软件档出现条带/噪点时可参考其 R2 序列实现（约 15 行）。

8. **复杂曝光（明暗百分位钳制）**
   - 技术描述：加权平均亮度外，再统计高于/低于均值指定百分比的亮度分布，双向钳制防止暗场/亮场曝光漂移。
   - 包内出处：program/grade/exposure.vsh:38-75；settings.glsl:105-112。
   - 对应 Astra 模块：Astra/shaders/lib/tonemap.glsl 与 global/post/（Astra 已有曝光/色调映射，具体是否带百分位钳制未核对）。
   - 迁移难点：中低。逻辑约 40 行，但需要 Astra 曝光统计的现有数据通路支持二次遍历。

## ④ Astra 已有对应实现（对照表）

| 能力 | FastPBR 出处 | Astra 对应 | 两边优劣 |
|---|---|---|---|
| 原版纹理→光滑度 | 无（回退全粗糙，material.glsl:44-48） | lib/rock_material.glsl:7-19（按 block.properties 材质 ID 用原始纹理色映射光滑度） | Astra 明确占优：无 PBR 包用户能看到下界岩/冰面等的差异化反射；FastPBR 用户无包时全场哑光。优劣判断依据双方源码，确定。 |
| 下界岩反射 | 无维度特化（nether/forward.fsh:201 共用主世界管线） | global/dimension/nether_reflection.glsl:7-62（下界岩专用 Fresnel+SSR+边缘置信度，注记源自 Complementary r5.9） | Astra 占优（下界观感）；FastPBR 占优（管线统一、维护简单）。 |
| 水面 SSR | composite3.fsh:124-172（8 步，缺 DH 6 步 LOD） | global/water/raytrace.glsl:62（24 步 + gather + 置信度） | Astra 质量占优，FastPBR 速度占优；Astra 24 步无 LOD 粗搜，远处命中率/成本比未测，不确定。 |
| SH 天光 | prep/skylightSH.comp（compute 归约） | lib/sky_sh9.glsl:1-23（SH9 投影与求值，fragment 侧） | 方向性天光两边都有；分辨率与成本对比未实测，不确定。 |
| 屏幕空间 AO/GI | HBIL.csh（半分辨率 compute，可单次弹射） | lib/ao_material.glsl:1-7 + AO_STRENGTH/AO_RADIUS（设置见 shaders.properties:424-427） | FastPBR 功能占优（AO+GI 一体、含 DH 支持）；Astra 的 AO 接收面按材质白名单（ao_material.glsl:3-6），调控粒度不同。 |
| 镜面高光 | GGX+导体/介电 Fresnel（specular.glsl:61-105），能量来自打包直射光 | global/lighting/diffuse.glsl（前向光照；非水表面专用镜面未在本次核对范围内） | FastPBR 高光-阴影一致性有结构性保证；Astra 对应实现未核对，不下结论。 |
| 彩色阴影 | forward.fsh:126-135 | 设置项 COLORED_SHADOWS（shaders.properties:424）；实现位置未核对 | 双方都有该特性；实现细节未核对，不确定。 |
| 水体：波浪/焦散/吸收/光束 | 波浪视差（forward.fsh:206-252）、自定义水色（settings.glsl:34-38）；无焦散、无水下光束 | global/water/（absorption/caustics/light_shafts/refraction/particles 全套） | Astra 特性面占优；FastPBR 胜在便宜。 |
| 体积/平面云 | deferred.csh（1/4 分辨率 compute） | CLOUD_MODE/CLOUD_QUALITY（shaders.properties:424-427），半分辨率平面云（任务背景自述） | 双方都有分层云；步数与分辨率策略不同，未实测对比，不确定。 |
| 曝光/TAA/锐化 | exposure.vsh / temporal.fsh / final.fsh CAS | global/post/ + lib/tonemap.glsl、lib/taa_*.glsl | 两边都有完整后处理链；FastPBR 有 REC2020 宽色域与 10bit 输出选项（shaders.properties:262、screen.POST 的 VIEWPORT_GAMUT），Astra 对应支持情况未核对，不确定。 |

## ⑤ 借鉴可行性（许可证层面）

- LICENSE 为"保留所有权利"自定义协议：第 2 条允许**私有修改**（LICENSE:54-58）；第 3 条要求公开修改版须获作者明确许可（LICENSE:62 起）；**第 4 条明确：把本项目部分源码用作另一个原创项目的一部分，需要作者明确许可 + 署名 + 禁止未授权商业化**（LICENSE:75 起，grep 定位于第 75 行）。
- 结论：**逐行抄代码到 Astra 不可行**（Astra 若公开发布即需 RRe36 书面许可）；可行的是：阅读理解后以 Astra 自己的架构重写思路与算法（算法/思想不受版权保护，但注意 Astra 对第三方来源的署名惯例，如 nether_reflection.glsl 头部注明 Adapted from Complementary——若日后真向 RRe36 取得许可，同款标注即可）。本报告所有摘录均 ≤5 行，属研究性引用。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **水面太阳高光（specular sun highlight）**：用 FastPBR 的"直射光打包复用"思想（forward.fsh:187-195）给 Astra 水面加 GGX 太阳高光，含 bez 水波法线已就绪（global/water/surface.glsl）。提升大（水面日照闪烁是观感第一印象）、工作量小-中（一个缓冲或复用现有链）。
2. **SSR 未命中回落接入 sky_reflection_cache**：对齐 composite3.fsh:223-225 的"miss→缓存天空"模式，消除 Astra SSR miss 时的天空重算或黑边。提升中、工作量小。
3. **R2 旋转圆盘软阴影内核**：抄结构不抄码，给 Astra 软件阴影档（SHADOW_FILTER_MODE=0）换 R2 序列。提升中、工作量小（~20 行）。
4. **labPBR 支持前置调研（F0/光滑度双通道解码）**：按 material.glsl:44-60 的解码语义，在 Astra 材质标记体系加"检测到 labPBR specular 时覆盖纹理启发式"的开关，两条路径并存（无包用户不受影响）。提升大但工作量大，属中期项。
5. **百分位钳制曝光**：exposure.vsh:38-75 的明暗双向钳制，防洞穴/雪原极端场景曝光振荡。提升中、工作量中低（依赖 Astra 曝光统计通路）。

## 附：引用自抽查记录

写毕后重开文件核对 ≥8 条（2026-10-02）：en_US.lang:1-2 ✓、shaders.properties:126,128,145,151-156 ✓、settings.glsl:42,72-73,79-81 ✓、material.glsl:29-38,44-60 ✓、forward.fsh:63-77,126-135,137-185,187-195,206-252,287,342,356,371-379,385,391-393 ✓、composite3.fsh:94-115,117-122,124-172,223-225,330-342,353,359-377 ✓、specular.glsl:61-105 ✓、HBIL.csh:22,62-110,179-181,240-271,284 ✓、density.glsl:5-14 ✓、deferred.csh:4,39-45 ✓、temporal.fsh:238-251 ✓、grading.fsh:215,405 ✓、head.glsl:26-37 ✓、downscaleTransform.glsl:1-6 ✓；Astra 侧 rock_material.glsl:7-19 ✓、nether_reflection.glsl:7-62 ✓、raytrace.glsl:62 ✓、sky_sh9.glsl:1-23 ✓、ao_material.glsl:3-6 ✓、shaders.properties:424-427 ✓。
