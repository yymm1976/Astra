# Astra × 20 款参考光影包调研汇总 · 第二批次（SUMMARY-batch2）

> 依据：`shader_research/` 下批次二 20 份单包报告（slug：`ushader`、`glimmer-shaders`、`reverie_shader`、`clarityshader`、`musk-rose-shaders`、`drdestens-shaders`、`eclipseshaders`、`amethyst-shaders`、`bvs`、`kuda-shaders`、`sildurs-enhanced-default-shaders`、`tea-shaders`、`lumina-shader-event-horizon`、`lux-v1`、`redhat-shaders`、`voyager-shader-2.0`、`bsl-shaders-classic`、`spring-shaders`、`pyvtron-shaders-official-modrinth`、`alpha-piscium`）综合而成。所有 出处/行号/数字 均转引自各报告原文，本文件不新造出处；报告间矛盾一律在 ④-3 如实并列，不裁断。
> 共识度标记：「N 包印证」= N 份报告独立记载同一技术方向，并随行列出包名（短名，省略 `-shaders`/`-shader` 后缀）；未标共识度的为单一来源，不代表业界共识。
> 路径约定：Astra 侧路径相对 `Astra/shaders/`（沿用各报告的 `A:` 前缀写法）；参考包侧路径沿用各报告自身约定（各报告对 `P:` 前缀与根目录的处理不同，**转引时照抄该报告写法，未统一改写**）。
> 本文件为批次二最终版：上一轮（5/20 阶段）`SUMMARY-batch2` 的 §1.1 各包 Top 建议、§1.2 收敛结论、§1.3 未被认可方向、§1.4 许可证分层，已分别保留并扩写于 ⑤-1、⑤-2、⑤-6、⑤-7 与 ③ 表（**⑤-1 表为各包 ⑥ 段前 2 条的节选**，完整 Top5 见各单包报告）。

## ① 执行摘要

1. **整体定位**：本批 20 包的 ④/⑥ 段多处判定 Astra 现有实现更省或更全（amethyst、bsl-classic 等 5 包判 A 更省或更全）。差距集中在四处：环境镜面（粗糙度 mip + 环境 BRDF）、GI/降噪、Voxy/DH 远景观测、PBR/POM 材质与后处理风格件。
2. **共识度最高**：① 天空反射缓存按粗糙度开 mip + 环境 BRDF——glimmer、musk-rose、voyager（3 包印证；pyvtron、alpha-piscium、lux 同向补充）；② 解析/免纹理波场——glimmer、eclipseshaders、kuda、voyager（4 包印证）；③ SSR 行进/精修/未命中回退细节——eclipseshaders、kuda、spring、pyvtron、voyager（5 包印证）；④ TAA 历史重采样/统计细节——drdestens、voyager、spring、alpha-piscium、lumina（5 包印证）；⑤ 运动模糊——clarity、bvs、tea、pyvtron（4 包印证）。
3. **各子系统最密集区**：水体＝SSR 细节（5 包）＋解析波场（4 包）＋湿身/水洼（kuda、ushader、spring、voyager）＋水下吸收（redhat、eclipseshaders、tea）；大气＝静态大气资产（reverie、musk-rose、pyvtron、redhat 4 包）＋云多重散射廉价近似（glimmer、ushader、spring、voyager）＋云时域超分（ushader、reverie、alpha-piscium）＋godrays 廉价档（drdestens、kuda、pyvtron、redhat）；下界/体素光＝时域摊还 + 相机位移重投影（amethyst、spring、reverie、glimmer 4 包）与 amethyst 一整套消费端低成本细节；后处理＝tonemap 风格化算子（lumina、lux、spring、alpha-piscium 4 包）＋输出锐化（drdestens、sildurs-enhanced、lumina、alpha-piscium 4 包）。
4. **许可证硬边界**：唯一可直接搬运代码的是 musk-rose（CC0，含两处第三方边界）；须保留声明的是 glimmer（MIT）、bvs 与 eclipseshaders（按索引 CC-BY-4.0，包内无许可正文）；kuda 索引 BSD-3-Clause 与包内 `Agreement.txt:9-15` 限制性协议冲突，裁定前只借思路；spring（CC-BY-NC-SA）与 alpha-piscium（GPL-3.0）因 NC/SA 与传染性实务上只能重写；redhat（Chocapic13 共享协议）、amethyst（CLA 1.5）、lumina（CLA 1.6）、pyvtron（Copyright Claw）为自定义强条件协议；其余 9 包为保留所有权利或包内无许可文件（详见 ③）。
5. **报告口径与证据强度**：20/20 已完成（原"5/20 未完成"状态消解）；其中 clarity、musk-rose 为主代理自撰、未派子代理（报告开头有声明），深度低于其余 18 份；多份报告实测到调研期间 `Astra/` 并行工作流改动导致 `A:` 行号漂移（见 ④-2-1）；所有性能收益类建议均无帧时数据（ledger S2）。

## ② 主题化借鉴矩阵

> 行内 `P:`/`A:` 出处照抄各报告写法；档位沿用报告口径（快赢=半天内、中期=数天、长期=一周+ 或需立项）。单源行不标共识度；"N 包印证"行均列出包名。各包高价值条目覆盖率见 ⑤-1。

### ②-1 阴影与光照

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---| 
| 无阴影档方向感 | drdestens、bvs（2 包印证） | drdestens `P:lib/pbr/lighting.glsl:64-92`；bvs `P:shaders/world0/composite.fsh:45-55` | `global/lighting/diffuse.glsl:95-108` | 快赢 |
| 暗处地板光/夜间补光随天光收敛 | drdestens、bvs（2 包印证） | drdestens `P:lib/lightmap.glsl:43`；bvs `P:shaders/world0/composite.fsh:279-285` | `global/lighting/diffuse.glsl:107` | 快赢 |
| AO 距离/雾/水下淡出 | eclipseshaders、bvs、sildurs-enhanced（3 包印证） | eclipse `shaders/composite1.fsh:83-87`；bvs `P:shaders/world0/composite.fsh:343-361`| `lib/ao_resolve.glsl`、`program/ssao.fsh` | 快赢 |
| AO 采样相位螺旋/黄金角+抖动起点 | bvs、drdestens（2 包印证） | bvs `P:shaders/world0/composite.fsh:224-239`；drdestens `P:deferred.fsh:160-189` | `program/ssao.fsh:62-104` | 快赢 |
| 软阴影核与偏置解耦 | pyvtron、redhat、bsl-shaders-classic（3 包印证） | pyvtron `P:shaders/world0/gbuffers_textured.fsh:228,248`；redhat `P:program/composite.glsl:122-181`| `global/lighting/shadowmap.glsl` | 快赢 |
| 阴影畸变/偏置形式对照 | musk-rose、eclipseshaders、bsl-shaders-classic（3 包印证） | musk-rose `P:shaders/programmes/utils/musk_rose_shadow.glsl:27-34`；eclipse `shaders/distort.glsl:19-24` | `lib/distort.glsl`（实验须独立文件） | 中期 |
| 阴影越界钳制/查询边界与夜间早退 | redhat、bsl-shaders-classic（2 包印证） | redhat `P:program/composite.glsl:709-727`；bsl-classic `P:lib/lighting/shadows.glsl:159-166` | `global/lighting/shadowmap.glsl:66-80` | 快赢 |
| 彩色阴影边界/强度塑形 | ushader、eclipseshaders、lumina（3 包印证） | ushader `P:shaders/world0/deferred3.fsh:139-159`；eclipse `shaders/gbuffers_textured_lit.fsh:54-73`| `global/lighting/shadowmap.glsl` | 快赢 |
| 太阳高光解析面积光 | glimmer | `P:shaders/lib/lighting/brdf.glsl:21-65` | `global/lighting/diffuse.glsl:120-165` | 中期 |
| 屏幕空间接触阴影 | ushader、voyager（2 包印证；批次一 4 包同向） | ushader `P:shaders/lib/light/contactShadow.glsl:25-90`；voyager `P:shaders/program/shaders1/common/shadow/contact.glsl:1-40` | `global/lighting/shadowmap.glsl` | 长期 |
| 手持/方块光曲线 | redhat、pyvtron（2 包印证；批次一 3 包同向） | redhat `P:program/composite.glsl:984-1013`；pyvtron `P:shaders/Lib/TorchLightmap.glsl:13-34` | `global/lighting/blocklight.glsl` | 快赢 |
| 逐光源 `vec4(颜色, 强度)` 合成 + 三条光照曲线（点光 lightmap 五次幂 / 雨天乘子 `RAIN_CUTOFF 0.70` / 弱光区滑杆） | musk-rose（单源；③12） | musk-rose `P:shaders/programmes/musk_rose_lights.glsl:17-82`、`P:shaders/world0/deferred.glsl:82-94` | `global/lighting/blocklight.glsl`、`diffuse.glsl` | 快赢（候选曲线） |

### ②-2 水体

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---| 
| **天空反射缓存按粗糙度开 mip+环境 BRDF 4 行** | glimmer、musk-rose、voyager（3 包印证） | glimmer `P:shaders/lib/lighting/shading.glsl:83-101`；musk-rose `P:shaders/programmes/utils/musk_rose_pbr.glsl:10-16`| `lib/sky_reflection_cache.glsl:29` | 快赢 |
| 粗糙度→mip 抖动 LOD / VNDF 取层 | pyvtron、lux、alpha-piscium（3 包印证） | pyvtron `P:shaders/world0/deferred1.fsh:71,82-104`；lux `P:shaders/lib/reflections/roughReflections.glsl:9-72`| `lib/sky_reflection_cache.glsl` | 快赢 |
| 解析/免纹理波场低配档 | glimmer、eclipseshaders、kuda、voyager（4 包印证） | glimmer `P:shaders/lib/water/waveNormals.glsl:8-98`；eclipse `shaders/waves.glsl:19-39`| `global/water/surface.glsl` | 快赢 |
| 顶点位移夹进方块空间 | tea、bvs、sildurs-enhanced（3 包印证） | tea `P:shaders/world0/gbuffers_water.vsh:45-51`；bvs `P:shaders/world0/gbuffers_terrain.vsh:79-90`| `global/water/surface.glsl` | 快赢 |
| SSR 行进/精修/未命中回退细节 | eclipseshaders、kuda、spring、pyvtron、voyager（5 包印证） | eclipse `shaders/composite.fsh:21-23,60-74,76-112,118-122`；kuda `P:composite1.fsh:456-526`| `global/water/raytrace.glsl` | 中期 |
| 反射权重×天空光/环境亮度门控 | eclipseshaders、sildurs-enhanced（2 包印证） | eclipse `shaders/composite.fsh:43,114`；sildurs `P:shaders/composite.fsh:326-331` | `program/water.glsl:228` | 快赢 |
| 折射细节 | kuda、redhat、tea（3 包印证） | kuda `composite1.fsh:599-632`；redhat `P:program/composite.glsl:626-639`| `global/water/refraction.glsl` | 快赢 |
| 水下吸收/水雾 | redhat、eclipseshaders、tea（3 包印证） | redhat `P:program/composite.glsl:797,830`；eclipse `shaders/composite.fsh:44-58`| `global/water/absorption.glsl` | 快赢 |
| 反射内复用同一雾/雾色随密度重映射 | kuda、reverie、lux（3 包印证） | kuda `P:composite1.fsh:411-415,501`；reverie `P:generic/shadow/vl.glsl:181-246`| `global/atmosphere/fog.glsl` | 中期 |
| 湿身/水洼/涟漪 | kuda、ushader、spring、voyager（4 包印证） | kuda `P:gbuffers_terrain.fsh:73-122`；ushader `P:shaders/program/gbuffer/solid.fsh:238-274`| `lib/wet_material.glsl` | 中期 |
| 焦散：水掩码调制/高度梯度色散/原子量化 | reverie、spring、alpha-piscium（3 包印证） | reverie `P:generic/shadow/main.glsl:25-40`；spring `P:shaders/lib/water/waterCaustics.glsl:26-74`| `global/water/caustics.glsl` | 中期 |
| 水下渐晕（保亮度混向深蓝） | clarity | `P:shaders/composite.csh:88-96` | `global/post/grading.glsl` | 快赢 |

### ②-3 大气与云

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---| 
| 静态大气资产 | reverie、musk-rose、pyvtron、redhat（4 包印证） | reverie `P:program/prepare_a.csh:7-23`；musk-rose `P:shaders/textures/atmosphere.glsl:54-99`| `global/atmosphere/sky_gradient.glsl` | 长期（先对照） |
| 大气 LUT 的**成对搬运契约**：两轴仰角约定 + 抖动=缩放半径（`mix(0.85,1.0,bayerX64)` 压 8-bit 色带）+ 传输曲线（生成 `1-exp(-x)` / 消费 `mix` 链 + `1-exp(-1*total)`，**PNG 值不是辐射亮度**） | musk-rose（单源；③11） | musk-rose `P:shaders/textures/atmosphere.glsl:38-40,95,98,109-112`；消费端 `P:shaders/programmes/musk_rose_sky.glsl:176-183`、`P:shaders/world0/deferred.glsl:105` | `global/atmosphere/sky_gradient.glsl`（对照实验时） | 长期（先对照） |
| 云多重散射/相位廉价近似 | glimmer、ushader、spring、voyager（4 包印证） | glimmer `P:shaders/lib/atmosphere/clouds.glsl:41-65`；ushader `P:shaders/lib/atmos/CloudsCommon.glsl:28-30,56-68`| `global/atmosphere/clouds_planar.glsl` | 中期 |
| 平面云层细节 | kuda、redhat、lux（3 包印证） | kuda `P:composite1.fsh:282-366`；redhat `P:program/composite1.glsl:280,448`| `global/atmosphere/clouds_planar.glsl` | 中期 |
| 云时域超分 | ushader、reverie、alpha-piscium（3 包印证） | ushader `P:shaders/lib/frag/checkerboard.glsl:20-37`；reverie `P:generic/post/taa.glsl:115-155`| `global/atmosphere/cloud_temporal.glsl` | 中期 |
| 时间跳变历史失效 | ushader | `P:shaders/shaders.properties:247-248` | `lib/effect_history.glsl:22-37` | 快赢 |
| 云影图单通道+与云同源+多消费者 | voyager（批次一 3 包同向） | `P:shaders/program/shaders1/light3.glsl:25-70` | `global/atmosphere/cloud_shadow_cache.glsl` | 快赢 |
| godrays 廉价档 | drdestens、kuda、pyvtron、redhat（4 包印证） | drdestens `P:composite3.fsh:190-218`；kuda `P:composite.fsh:437-485`| `global/post/godrays.glsl` | 快赢 |
| 体积雾平行阴影空间行进 | ushader | `P:shaders/world0/composite.fsh:214-222,298-314` | `global/atmosphere/volume_fog.glsl:91-98` | 快赢 |
| 体积雾远近分段步长 | spring | `P:shaders/lib/atmosphere/fog.glsl:228-309` | `global/atmosphere/volume_fog.glsl` | 中期 |
| 解析高度雾 | glimmer | `P:shaders/lib/atmosphere/fog.glsl:76-151` | `global/atmosphere/fog.glsl:40-79` | 快赢 |
| 天空闭式散射补项（晚霞限域） | lux、drdestens（2 包印证） | lux `P:shaders/lib/atmospherics/sky.glsl:16-38`；drdestens `P:lib/sky.glsl:21-32,53-67` | `global/atmosphere/sky_gradient.glsl` | 快赢 |
| 极光/流星/恒星色温/星点判据 | lux、bvs（2 包印证；批次一极光 4 包同向） | lux `P:shaders/lib/atmospherics/aurora.glsl:83-133`、`stars.glsl:10-22,63-115`；bvs `P:shaders/world0/gbuffers_skybasic.vsh:15` | `global/atmosphere/`（极光新模块） | 中期 |

### ②-4 下界与体素光

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---| 
| 体素光时域摊还+相机位移重投影 | amethyst、spring、reverie、glimmer（4 包印证；批次一 7 包同向） | amethyst `P:shaders/program/shadowcomp.glsl:99-118`；spring `P:shaders/program/shadowcomp1_a.glsl:14-62`| `program/nether_light.csh` | 中期 |
| 相机背后/整组（HiZ）剔除 | amethyst、alpha-piscium（2 包印证） | amethyst `P:shaders/program/shadowcomp.glsl:11-12,72-89`；alpha `P:shaders/composite24.csh:1865-1875` | `program/nether_light.csh` | 快赢 |
| 占用图 8 位+r8ui、每 quad 单顶点写 | amethyst | `P:shaders/lib/misc/voxelization.glsl:82-298`、`P:shaders/program/shadow.glsl:300-307` | `program/shadow.vsh:42-52` | 快赢 |
| per-kind"颜色即射程"表+alpha 附加光+饱和度滑块 | amethyst | `P:shaders/lib/colors/blocklightColors.glsl:11-177`、`P:shaders/lib/lighting/mainLighting.glsl:395-397` | `program/nether_light.csh:37-47` | 快赢 |
| 染色玻璃体积滤色+角落漏光消费端夹紧 | amethyst | `P:shaders/lib/colors/blocklightColors.glsl:179-219`、`P:shaders/lib/misc/voxelization.glsl:37-57` | 体素传播 | 快赢 |
| 体素图材质侧二次利用 | amethyst | `P:shaders/lib/materials/materialMethods/connectedGlass.glsl:64,79,103` | `program/shadow.vsh:57-83` | 快赢 |
| 彩光雾/体积耦合+光柱色独立 shadowcolor | amethyst（批次一 3 包同向） | `P:shaders/lib/atmospherics/fog/coloredLightFog.glsl:4-39`、`P:shaders/program/shadow.glsl:161,187-195` | `global/dimension/nether_volume.glsl` | 中期 |
| 三轴 SDF+DDA 空体素跳步 | spring（批次一 RV 同向） | `P:shaders/program/shadowcomp_a.glsl:14-54`、`P:shaders/lib/lighting/pathTracing.glsl:246-423` | `program/nether_light.csh` 新段 | 长期 |
| 下界环境色由原版雾色驱动 | ushader | `P:shaders/world-1/deferred4.vsh:58-59` | `global/dimension/nether*.glsl` | 快赢 |
| 末地烟雾/黑洞装饰件 | ushader、lumina（2 包印证） | ushader `P:shaders/world1/composite.fsh:123-182`；lumina `lib/atmospherics/eventHorizon.glsl:105-147` | `global/dimension/end*.glsl` | 中期 |

### ②-5 后处理与调色

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---| 
| tonemap 三段风格化 | lumina（批次一多包同向） | `composite5.glsl:40-88` | `lib/tonemap.glsl:191-228` | 快赢 |
| Prism2024 色相保持 tonemap | lux | `P:shaders/lib/post/tonemap.glsl:20-193` | `lib/tonemap.glsl`（第 5 档） | 中期 |
| CDL filterOffset+每算子 additive+AgX EV | spring、alpha-piscium（2 包印证） | spring `P:shaders/lib/camera/toneMapping.glsl:150-156,106-148`；alpha `P:shaders/composite42.csh:2455` | `lib/color_controls.glsl:29-53` | 快赢 |
| 低保真自动曝光 | glimmer、bvs、voyager（3 包印证） | glimmer `P:shaders/program/c48_writeLuminance.glsl:35-41`；bvs `P:shaders/world0/composite2.fsh:107-120`| `global/post/exposure.glsl` | 快赢 |
| TAA 历史重采样/统计域细节 | drdestens、voyager、spring、alpha-piscium、lumina（5 包印证） | drdestens `P:composite4.fsh:56-68`；voyager `P:shaders/program/shaders2/common/taa.glsl:4-32`| `program/taa_resolve.fsh` | 快赢 |
| 输出锐化 | drdestens、sildurs-enhanced、lumina、alpha-piscium（4 包印证） | drdestens `P:final.fsh:68-90,157-160`；sildurs `P:shaders/composite1.fsh:131-138`| `program/final.fsh` | 快赢 |
| Bloom mip/瓦片+黑暗自适应；泛光雾 | kuda、voyager、lumina、drdestens（4 包） | kuda `P:composite3.fsh:43-98`；voyager `P:shaders/program/shaders2/common/bloom.glsl:1-39`| `global/post/bloom.glsl` | 中期 |
| 运动模糊 | clarity、bvs、tea、pyvtron（4 包印证） | clarity `P:shaders/composite.csh:41-81`；bvs `P:shaders/world0/final.fsh:194-233`| 无（新后处理档） | 中期 |
| DoF | bvs、kuda、tea（3 包印证） | bvs `P:shaders/world0/composite2.fsh:19-100`；kuda `P:final.fsh:282-320`| 无（新后处理档） | 中期 |

### ②-6 性能与低配档

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---| 
| CPU 预计算/派生 uniform | drdestens、lux、pyvtron（3 包印证；批次一 12 包同向） | drdestens `P:shaders.properties:62-71`；lux `P:shaders/shaders.properties:143-151`（双出处见 ④-2-6）| `lib/uniforms.glsl` | 快赢 |
| 行为型风格预设层+一行式 Look profile | bsl-shaders-classic、spring、drdestens（3 包印证） | bsl-classic `P:lib/settings.glsl:466-471,547-635`；spring `P:shaders/shaders.properties:1-6`| `shaders.properties:444-447` | 快赢 |
| 按选项声明 Iris required 特性+图像全量写入纪律 | clarity | `P:shaders/shaders.properties:31-32`、`P:shaders/composite1.csh:130-131` | `shaders.properties:692` | 快赢 |
| `workGroupsRender` 二维全屏 compute 约定 | clarity、reverie（2 包印证） | clarity `P:shaders/composite.csh:6-7,36-39`；reverie `P:program/composite4.csh:10-14` | 无（SMAA/体积 compute 前置） | 中期 |
| RGBE8 打包共享指数进 8bit | ushader、voyager（2 包印证） | ushader `P:shaders/world0/deferred3.fsh:282-290`；voyager `P:lib/encode.glsl:18-31` | 全链替换（4K 才明显） | 中期 |
| 稀疏 tile 帧更新/惰性细化/光柱 z 检查 | voyager、sildurs-enhanced、bsl-shaders-classic（3 包印证） | voyager `P:shaders/program/shaders1/light0.glsl:22-42`；sildurs `P:shaders/composite.fsh:155-184`| `raytrace.glsl`、`volume_fog.glsl:102` | 快赢 |
| 区块加载动画/资产换运行时判据/设置面精简 | bvs、pyvtron、clarity（3 包印证） | bvs `P:shaders/world0/gbuffers_terrain.vsh:55-67`；pyvtron `P:shaders/shaders.properties:188-190` | `program/lit.vsh`+`shadow.vsh` | 快赢 |

### ②-7 工程组织与设置系统

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---| 
| Voxy/DH 集成契约+第二套前向着色 | sildurs-enhanced、glimmer、bvs（3 包印证） | sildurs `P:shaders/voxy.json:3-40`；glimmer `P:shaders/program/c0_combinedDepth.glsl:38-55`| `program/lit_voxy.fsh`（stub）、`voxy.json`（0 字节） | 中期 |
| 维度薄壳+共享 program 源；复制式结构反面对照 | bsl-shaders-classic、tea、eclipseshaders（3 包印证） | tea `P:shaders/world-1/composite.fsh:3`；eclipse `shaders/lib.glsl:1-280` vs `world1/lib_world1.glsl:1-157` | `world-1/`、`world1/` | 快赢（仅维持） |
| 天气×群系 RGB 矩阵+嵌套 screen | lux | `P:shaders/shaders.properties:43-96` | `lib/color_controls.glsl:55-61` | 中期 |
| 调色板/出厂默认值对照 | kuda、bsl-shaders-classic、spring（3 包印证） | kuda `P:composite1.vsh:136-186`；bsl-classic `P:lib/settings.glsl:263-270`| `lib/settings.glsl`、`lib/color_controls.glsl` | 快赢 |
| SSBO 常量缓冲+硬件阴影比较采样器 | reverie（采样器受 ④-1 S1 制约） | `P:lib/all_the_uniforms.glsl:124-142`、`P:generic/shadow/main.glsl:26,31` | `shaders.properties:455-460`、`global/post/godrays.glsl:30-32` | 快赢 |

### ②-8 可选风格页

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---| 
| 维度屏幕扭曲（热浪/末地抖动） | kuda | `P:world-1/final.fsh:176-188` | `program/final.fsh` | 快赢 |
| 风格化后处理 | tea、redhat（2 包印证） | tea `P:shaders/program/deferred1.glsl:40-64`；redhat `P:program/final.glsl:388-420` | `global/post/grading.glsl`、`program/final.fsh` | 中期 |
| 季节色调系统（四季+群系门控） | reverie | `P:generic/weather.glsl:1-31` | `global/atmosphere/weather.glsl` | 中期 |

### ②-9 材质与 PBR

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---| 
| LabPBR 打包/解包+孔隙度驱动 roughness/f0 | voyager、kuda、ushader、spring（4 包印证；批次一 fastpbr 同向） | voyager `P:shaders/program/shaders1/struct.glsl:12-32`；kuda `P:gbuffers_terrain.fsh:73-122`| `program/lit.fsh:287-310` | 中期 |
| 材质级光学常数覆盖表（水/冰/玻璃/黏液） | voyager（含条件重复"坑"，不可照抄） | `P:shaders/program/shaders1/struct.glsl:57-81` | `program/water.glsl:225-231` | 快赢 |
| 地形 POM | kuda、musk-rose（2 包；musk-rose 已逐行读，**判「不建议近期做」**） | kuda `P:gbuffers_terrain.fsh:124-169`；musk-rose `P:shaders/programmes/utils/musk_rose_pom.glsl:4-57`（前向 12 步 + 独立自阴影 12 步，高度取 `normals.a`） | 无（Astra 无高度图数据源，依赖资源包 LabPBR） | 长期 |
| IPBR 自发光启发式 | pyvtron、sildurs-enhanced、glimmer（3 包印证；批次一 2 包同向） | pyvtron `P:shaders/Lib/EmissiveLight.glsl:13-27`；sildurs `P:shaders/gbuffers_textured.fsh:112-115`| `lib/surface_emission.glsl` | 快赢 |
| 材质策略位打包（一整数编码三套策略） | lumina | `lib/common.glsl:820-836` | `lib/taa_reactive.glsl:3-10` | 中期 |

### ②-10 路径追踪/GI/降噪

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---| 
| ReSTIR 屏幕空间 GI 全骨架 | alpha-piscium（批次一 42 份报告 0 命中） | `P:shaders/composite18.csh:1943-1985`、`composite24.csh:1827-1856` | 无（新子系统，预研） | 长期 |
| RSM GI 与泄漏两级抑制 | voyager、spring（2 包印证；批次一 Ebin GPL 路线同向） | voyager `P:shaders/program/shaders1/common/indirect/rsm.glsl:13-84`；spring `P:shaders/lib/lighting/RSM.glsl:3-100` | 无（需重排 `program/shadow.fsh`） | 长期 |
| ReBLUR 历史长度+镜面定向降噪核 | alpha-piscium | `P:shaders/composite27.csh:1754-1780`、`composite31.csh:1429-1465` | `program/taa_resolve.fsh` | 中期 |
| 抗萤火虫 | alpha-piscium | `P:shaders/composite28.csh:1225-1272` | `lib/taa_reactive.glsl`（新） | 快赢 |
| 自适应光线预算+bin 跳过 / HiZ / 光线打包 | alpha-piscium（3 项） | `P:shaders/composite16.csh:306-310`、`composite24.csh:1865-1875,1929-1938` | `global/water/raytrace.glsl:58` | 中期～长期 |
| STBN 三维时空蓝噪声（纹理须自制） | alpha-piscium（批次一多包同向） | `P:shaders/composite18.csh:242-244,1568` | `lib/bayer.glsl:22` | 中期 |

## ③ 许可证红线表

判定均以各报告 ①⑤ 段为准（按分层从宽到严；CC-BY/BSD 类"能否抄"均以先复核许可正文为前提）。

| 包 | 许可证实况（含包内证据行号） | 能否抄代码 | 义务 / 红线 |
|---|---|---|---| 
| musk-rose-shaders | CC0-1.0（`P:LICENSE:3` 标题、`:35-40` 弃权、`:40-43` 权利定义、`:66` 弃权标的） | **能**（本批唯一可直接搬代码） | 无署名/无同类许可/无传染；三处第三方边界不由 CC0 覆盖（musk-rose ⑤ 修正）：SSDO（`P:shaders/programmes/utils/musk_rose_ssao.glsl:34-37`）、Builderb0y 畸变（`musk_rose_shadow.glsl:22-25`）；dirtyLens 贴图独立来源（`credits.txt:1`） |
| glimmer-shaders | MIT（`P:LICENSE:1,3,5-10`；保留声明义务 `:12-13`） | 能 | 副本/实质部分保留版权行与许可文本；tonyMcMapface LUT 连资产搬须一并保留 `P:shaders/textures/LICENSE-MIT_tony_mc_mapface` |
| bvs | 包内**无许可证文件**（`ls -la` 仅 `PATREON.txt`；`find -iname "*license*"` 无命中）；按索引登记为 CC-BY-4.0（`INDEX-batch2.md:25,70-71`） | 依 CC-BY 能（先复核正文） | 署名（`P:shaders/settings.glsl:1`、`P:PATREON.txt:1`）+标明修改+不得附加更严限制；CC-BY 与 GPLv3 兼容性报告未判（⑤ 5.4） |
| eclipseshaders | 包内**无许可证文件**（整包 find 无 LICENSE/README）；书面依据仅索引 CC-BY-4.0（`SUMMARY-batch2.md:47,66`）[假设] | 依 CC-BY 能（先复核正文） | 署名（gamerbenyt/Eclipse）+标明修改+保留声明+不得附加限制；5 处"本包代码≠参考实现"禁止照抄（`final.fsh:20-25` 等） |
| kuda-shaders | **两种来源并列**：包内 `P:Agreement.txt:9-15` 限制性协议（9 仅许自改、11 禁再分发/重传、12 禁使用内容；文件头 `P:composite1.fsh:13-18` 复述），无 LICENSE 文件；索引登记 BSD-3-Clause（`INDEX-batch2.md:38`）但正文不在包内 | **报告按裁定前只借思路**（不搬代码） | BSD-3 若成立：保留版权/三条款/免责、不得背书、不得附加限制、标注修改；代码含 Chocapic13（`composite1.fsh:458`）、Capt Tatsu（`composite3.fsh:45`）、robobo1221（`final.fsh:166`）血统须单独确认 |
| spring-shaders | CC-BY-NC-SA-4.0（`P:LICENSE:1,125,161-164,242,266-267,283,297`；作者三规则 `P:README.md:17`） | 实务不能（NC/SA 与 Astra GPL/MIT 派生文件硬冲突） | 禁商业（含付费墙/广告分成）；改编须同类许可、禁追加限制；只能读思路独立重写 |
| alpha-piscium | GPL-3.0-only（`P:LICENSE:1-2,71`；`:222` §2c"整个作品"；`P:README.md:46` 除 `scripts/`(MIT) 外全部 GPL） | 不能（零代码搬运） | 一经含可版权表达 Astra 须整体 GPL-3.0 分发；§10 自动传导；零资产/零命名；FidelityFX 类改取 AMD 官方 MIT 源 |
| redhat-shaders | **非纯 ARR**：Chocapic13 Sharing Agreement（`P:Agreement.txt`）——可分享修改版（标题须含 "(Chocapic13' Shaders edit)" `:13`）、禁据为己有 `:12`、禁变现链接 `:14`、须原样复制全部规则 `:15`、署名 `:16`；自选包名/规则/变现链接须 C13 书面许可 `:21-27`；允许变现视频 `:32` | 不能搬表达式；可借架构 | 强传染（采用其代码即须让 Astra 文档嵌入 C13 规则）；BSL/CYBOX/Robobo1221 等第三方片段不可转授 |
| amethyst-shaders | `P:License.txt`（91 行）= **Complementary License Agreement 1.5**（`:1`、`:9-13`、`:51-69` Modified Pack 四条件、`:71-76` 兜底 ARR）；本包是 Complementary Reimagined r5.5.1 的 Modified Pack（`P:shaderFile_Versions.txt:1-2`）；另 `anisotropicFiltering.glsl:2` 为 MPL-2.0 | 不能 | 片段搬入 Astra 不构成 Modified Pack，落入 `:71-76` 保留所有权利；不得用"Amethyst"/"Complementary"名号 |
| lumina-shader-event-horizon | `P:License.txt`（103 行）= **Complementary License Agreement 1.6**（`:1`；`:58-79` 含 `:68-72` 改名与 `:77-79` 1.3.e 不得附加其它许可；`:81-86` 兜底 ARR） | 不能 | 1.3.e 与 Astra 自有许可证/第三方条款并存直接冲突；思路级重写可行并登记 |
| pyvtron-shaders-official-modrinth | 自定义 Copyright Claw License（`P:LICENSE.txt`）：`:3` 保留所有权利、`:23` 禁再分发/入合集须显式许可、`:25` 服务器/启动器禁嵌、`:28` 仅私用修改、`:31-37` 公开修改版五条件、`:41` 跨项目使用代码/效果/贴图须显式许可 | 不能 | 代码与贴图均不得进入 Astra 仓库或发布物 |
| ushader | 保留所有权利（`P:LICENSE:1-2`；`:44-48` 传播限官方链接；`:75-81` 跨项目用源码须书面许可+署名+禁变现；`:97-98` 可随时改条款） | 不能 | 私有修改许可不覆盖搬进 Astra |
| reverie_shader | 保留所有权利（`P:LICENSE:1,3`——**缺 MIT 授权句**；`:5-11` 免责）；AMD CAS（`P:generic/post/cas.fsh:1-9`）应改从 AMD 原仓取 | 不能 | 禁成段/实现指纹搬运；provenance 头不可写"ported from"，只写"思路参考" |
| lux-v1 | ARR、协议随 BSL（`P:AGREEMENT.txt:1-2,4,6-7`）；索引登记保留所有权利 | 不能 | 用 BSL 谱系内容须走 BSL 渠道；n/k 表与 ACES/Prism 矩阵取公开原始出处；`shaders.properties:143-151` 出处为 Solas，不得追加 lux |
| clarityshader | 包内**无任何许可证文件**（递归 `*license*`/`*.txt`/`*.md` 为空）；Modrinth `LicenseRef-All-Rights-...`；按索引登记保留所有权利 | 不能 | 仅"阅读并学习"；SMAA 及 `smaa_area.bin`/`smaa_search.bin` 须取上游公开实现，不从本包复制 |
| drdestens-shaders | 包内**无任何 LICENSE/版权文件**（检索仅命中署名与算法名，`P:shaders/lang/en_us.lang:375-377`）；按索引登记保留所有权利 | 不能 | 只重写 |
| tea-shaders | 包内**无许可文件**；仅第三方片段致谢（BSL/Tatsu `P:shaders/lib/Global/Tonemaps.glsl:2`、Sildur `composite1.glsl:5`、Chocapic13 `taa.glsl:12`）；按索引登记保留所有权利 | 不能 | 作者非这些片段版权方、转授权不成立；BSL/Sildur/C13 内容须溯源原始出处 |
| sildurs-enhanced-default-shaders | 包内**无 LICENSE 文件**；唯一声明为 20 个文件头重复句（`P:shaders/shaders.settings:8-9` 禁 edit/copy/换名/声称己有）；实测无 "All rights reserved"/"copyright" | 不能 | 未声明≠可自由使用；禁行级搬运/常量表照抄/命名沿用；SSDO 取 Yury O'Donnell MIT 上游 |
| voyager-shader-2.0 | 包内**无 LICENSE、无版权声明**（检索 `licen|copyright` 零命中，仅致谢注释）；按索引登记保留所有权利 | 不能 | 解析波函数来自 Shadertoy（`water_normal.glsl:1-2`）双风险；金属 n/k 自查公开数据 |
| bsl-shaders-classic | 包内**无许可证文件**（find 为空）；唯一署名 `P:shaders/lib/settings.glsl:2-3`；按索引登记保留所有权利 | 不能 | 禁复制源码片段/define 组/常量表/lang 文案；常数只作参照系；与批次一逐字节相同文件以批次一登记为准 |

## ④ 存疑与待核实清单

### ④-1 统帅移交待处置项（逐条搬运 `_analysis/2026-10-02-batch2-ledger.md` S1–S8 并更新状态）

| # | 事项（含本轮更新后状态） | 出处 | 建议核实方式 |
|---|---|---|---| 
| S1 | Iris 是否支持 `SEPARATE_HARDWARE_SAMPLERS`/`HIGHER_SHADOWCOLOR`——**仍开放**；新增依赖方 glimmer、reverie、lumina（可选特性协商） | ledger S1；reverie/glimmer ①、lumina| 环境核验 Iris 特性表 |
| S2 | 全部性能类建议无帧时数据——**仍开放且范围扩大**（clarity `immut`、ushader 体积雾行进、alpha HiZ/光线预算、voyager 稀疏 tile） | ledger S2 | 落地前固定机位对照 |
| S3 | clarity 局部对比度阈值与水下渐晕取决于 Astra 是否已等效覆盖；三处 Astra 文件未逐行核对——**仍开放** | ledger S3；clarity ④ | 读 `global/water/absorption.glsl`、`stars.glsl`、`fog.glsl` 水下/far 分支 |
| S4 | 「与批次一重复」标注口径不统一——**仍开放**（批次一依 `SUMMARY.md` 可读部分；alpha 依 42 份检索；其余混合） | ledger S4 | 交叉核对时以检索证据为准 |
| S5 | 两目录未跟踪，批次一 20 包与 `INDEX.md` 未被改动只能用纪律+计数佐证——**仍开放** | ledger S5 | 审查时以目录计数/内容比对替代 diff |
| S6 | 15/20 未调研——**已消解**：20/20 报告完成（含 2 份主代理自撰），完整度 100%；自撰深度折扣见 ④-2-2 | ledger S6；本轮 | 无需动作 |
| S7 | clarityshader 包内无许可证文件（包事实）——**仍开放**；同类更广见 ④-2-3 的 9 包清单 | ledger S7；clarity ①⑤ | 动代码前复核许可正文/取上游实现 |
| S8 | musk-rose 的 CC0 未必覆盖 SSDO/Builderb0y 方法与 dirtyLens 贴图——**仍开放**；报告 ⑤ 已给逐条边界 | ledger S8；musk-rose ⑤ | 复用前确认上游许可或按方法重写 |

### ④-2 报告内「不确定」补充汇编（影响借鉴决策者）

1. **`A:` 行号漂移（`Astra/` 并行工作流）**：sildurs-enhanced（`taa_resolve.fsh` 132→137/143）、redhat（`display.fsh` 129→133、`shadowmap.glsl` 200-202→202-203）、bsl-shaders-classic（`diffuse.glsl` 442→444/453→455、`water.glsl` 208→210、`volume_fog.glsl` 漂移）。**落地前须复核全部 A: 行号**。
2. **自撰报告口径差异**：`clarityshader` 为主代理自撰、未派子代理（因配额耗尽，报告开头有声明），深度与 ④ 覆盖率低于其余 19 份；`musk-rose-shaders` 同为自撰，但已于续跑轮次由子代理**补强至达标口径**（③ 12 条 / ④ 14 行 / 附录 13 条，报告开头保留声明）。
3. **包内无任何许可类文本的包（8 包，`*licen*`/`*agreement*`/`*copying*` 递归实检为空）**：drdestens、eclipseshaders、bvs、tea、sildurs-enhanced、voyager、bsl-shaders-classic、clarityshader；另有 `kuda` 仅有 `Agreement.txt`（限制性、与 BSD-3 元数据冲突待裁决）与 Changelog/Credits。其中 bvs/eclipse 的 CC-BY-4.0 与 kuda 的 BSD-3 仅有索引/元数据来源。
4. **缓冲区格式声明在块注释内、需实测是否生效**：lumina（`P:shaders/lib/pipelineSettings.glsl:2-10` 整段在 `/* */` 内，colortex1/2/5/7 是否被 Iris 解析需实测）；同类 voyager（`P:program/buffers.glsl:61-103` 整块注释）、drdestens（`P:lib/setup.glsl` 格式块在注释内）。
5. **篇幅口径**：ushader/glimmer/reverie 报告 34.0–35.2KB，超批次一参考区间（19–29KB）17–20%（ledger 第三节）；因行号证据密集（Glimmer 162 处 `P:` 引用），未发现注水。
6. **双出处（不得追加）**：lux ③-16 指出 `A:shaders.properties:594-602` 与 `P:shaders/shaders.properties:143-151` 逐字相同，Astra 出处是 Solas V2.2b（已登记），不得追加 lux。
7. **pyvtron 未复核项**：`noiseTextureResolution=1` 与 470×470 噪声不匹配、`texture.gbuffers.colortex8` 绑定支持度、`VL_QUALITY`/`WATER_SAMPLES` 死宏——须实机确认。
8. **引用坑与检查项**：voyager 金属分支条件自第二项起全为 `==231`（不可达）、TAA `taa.glsl:49-57` 缺花括号使速度选择失效；eclipse 五处缺陷；bsl-shaders-classic ③-13（Astra 半透明水面 `albedo.a > 0.001` 早退检查，`P:program/gbuffers_water.glsl:275,577`）。
9. **redhat 暂缓项 #2**：`GODRAYS_SUN_OCCLUSION`（`A:lib/settings.glsl:234`，默认关）须先上机 A/B 再决定加"材质掩码源"第二实现。

### ④-3 报告间矛盾并列（如实并列，不裁断）

1. **"mip+环境 BRDF"计数不一致**：pyvtron ③-11 自记"第 3 次"、alpha ③-7 自记"第三次"、voyager ⑥ 自列 Top5-1——三份并行撰写、各自计数。本汇总统一重算为 **3 包核心印证（glimmer、musk-rose、voyager）+3 包同向（pyvtron、alpha-piscium、lux）**，以本口径为准。
2. **kuda 许可**：索引 BSD-3-Clause vs 包内 `Agreement.txt:9-15` 限制性协议——并列；③ 表按"裁定前只借思路"处理。
3. **bvs/eclipseshaders 许可**：索引 CC-BY-4.0（Modrinth 元数据）vs 包内无许可正文（两份报告均标 [假设]）——并列，动代码前须复核。
4. **redhat 归类更正**：上一轮 `SUMMARY-batch2.md:49` 并入"保留所有权利或自定义协议"；redhat 报告 ⑤ 更正为"自定义共享协议（有条件改编—再分发）"。本汇总采纳实证并保留更正记录；amethyst 同理（索引"自定义" vs 包内 CLA 1.5）。
5. **TAA YCoCg 基线（批次一遗留）**：bsl-shaders ④（未核实）vs photon-shader ④（`taa_resolve.fsh:109-118` 已有 1.25σ）；批次二 drdestens ④ 与 alpha ③-9 支持"已有"一侧，仍以落地前实读为准。
6. **水洼/雨湿基线（批次一遗留）**：bsl-shaders ④（未见）vs sildurs-vibrant ④（`weather.glsl:21` 起 astra_puddle）；批次二 bsl-shaders-classic ④、kuda K8、ushader ④ 均按"已有"沿用——并列。
7. **GI 路线分歧**：批次一判 RSM GI 优先走 Ebin（GPL 可改编）；alpha ⑥-2 提 ReSTIR 骨架作未来模板（XL）；spring ⑥ 暂缓 RSM（判与批次一重复）；voyager ⑥ 暂缓 RSM/接触阴影/PCSS——三条路线并列待统帅。
8. **云多重散射口径变化**：批次一列"储备（需先立体积云载体）"；批次二 glimmer/ushader/spring/voyager 把它降到平面云低配档——同一主题从"储备"变为"低配档可选"。
9. **暗处/低光处理三路线并存**：批次一 MakeUp visibleSky 幂衰减 vs drdestens P1 光方位半兰伯特（报告自注正交可叠加）vs bvs ③1 夜间补光（报告自注可能与 Astra 色温分档打架、建议仅 NO_SHADOWS 档试验）——并列。

## ⑤ 落地路线图

### ⑤-1 各包 Top 建议一览（扩写原 §1.1；按各报告 ⑥ 段归纳）

| 包 | 许可 | Top 建议（报告 ⑥） |
|---|---|---| 
| ushader | ARR | ①时间跳变历史失效 ②云 9 帧棋盘超分| 
| glimmer-shaders | MIT | ①Decima 面积光高光 ②天空缓存 mip 粗糙度分级| 
| reverie_shader | ARR | ①硬件阴影比较采样器 ②重载随机化世界观参数| 
| clarityshader | 无文件/ARR | ①SMAA 第三档（上游取表）②`immut` 宏+局部对比度阈值| 
| musk-rose-shaders | CC0 | ①环境 BRDF+mip ②离线烘焙大气 LUT 预研| 
| drdestens-shaders | 无文件/ARR | ①无阴影方向感 ②高度/材质 AO| 
| eclipseshaders | 索引 CC-BY | ①双深度水柱低配水雾 ②反射×天空光掩码| 
| amethyst-shaders | CLA 1.5 | ①时域摊销传播 ②染色玻璃滤色+漏光夹紧| 
| bvs | 索引 CC-BY | ①DH/Voxy 前向着色+除式雾交接 ②区块加载动画| 
| kuda-shaders | BSD-3 存疑 | ①调色板出厂默认值对照 ②雾色随密度重映射+反射内复用雾| 
| sildurs-enhanced-default-shaders | 无文件/ARR | ①Voxy 集成契约 ②远距/LOD 屏幕空间阴影| 
| tea-shaders | 无文件/ARR | ①岸线波位移裁剪 ②摇曳高度/夜晚耦合| 
| lumina-shader-event-horizon | CLA 1.6 | ①tonemap 三段风格化 ②输出端三件套（暗角/色差/锐化）③彩色阴影强度曲线| 
| lux-v1 | ARR（BSL 协议） | ①流星+Planck 星色 ②极光模块| 
| redhat-shaders | C13 协议 | ①阴影越界钳制+淡出 ②折射视角调制| 
| voyager-shader-2.0 | 无文件/ARR | ①环境反射粗糙度分级 ②2 样本 GGXVNDF+miss 回退| 
| bsl-shaders-classic | 无文件/ARR | ①行为型风格预设层 ②经典观感两开关| 
| spring-shaders | CC-BY-NC-SA | ①TAA 色调空间统计+亮度差收缩 ②雨湿涟漪+群系门控| 
| pyvtron-shaders-official-modrinth | 自定义 | ①天空缓存 mip+抖动 LOD ②低档双阶段体积光| 
| alpha-piscium | GPL-3.0 | ①自适应光线预算+HiZ 剔除 ②GI 骨架预研| 

### ⑤-2 收敛结论（扩写原 §1.2，优先级最高）

1. **天空反射缓存按粗糙度开 mip + 环境 BRDF**——**三个独立印证：glimmer-shaders（`log2(1+roughness*(mipCount-1))` 取层）、musk-rose-shaders（4 行环境 BRDF 拟合）、voyager-shader-2.0（VNDF+miss 回退环境缓存）**。两半须合并做（musk-rose ③2 明示：只有一半观感不成立）。现状 `A:lib/sky_reflection_cache.glsl:29` 固定 mip 0、无 BRDF。工作量：低+中，不新增 pass。**musk-rose ③8 补充三个接入障碍**：`colortex11` 无 mip 声明、HDR R11F 与 8-bit 缓存需重标定、缓存已含云需写端配合。
2. **棋盘格 + 时域上采样**——由 2 包扩为 3 包：ushader（云 9 帧棋盘）、reverie（半分辨率 1/16 增量更新）、alpha-piscium（云超分+HiZ+累积上限）；落点 `A:global/atmosphere/cloud_temporal.glsl`；reverie 侧依赖其 compute 化（③-3）。
3. **物理大气 LUT**——reverie、musk-rose、pyvtron（烘焙全景）、redhat（逐小时色表）4 包同向；共同副作用是无法响应 Astra 天气与四种颜色方案，四份报告一致判"先做对照实验"（离线生成一张 LUT + 单 composite 取样对比）。
4. **"少给 CPU/GPU 加 pass，多复用已有读取"**——clarity（曝光搭进边检测）、ushader（体积雾平行阴影空间行进）、voyager（稀疏 tile 帧更新）、alpha-piscium（矩与历史同趟写入）体现同一取向；与 Astra README 记载的性能审查同类合并方向一致。

### ⑤-3 快赢 Top10（跨包择优，含来源包+工作量）

| # | 快赢项 | 来源包（工作量） |
|---|---|---| 
| 1 | 环境镜面补齐：天空缓存 mip 分级+环境 BRDF | glimmer+musk-rose+voyager（3 包印证；低+中） |
| 2 | 时间跳变历史失效（/time set 拖影） | ushader（半天内） |
| 3 | 无阴影档方向感+夜间补光 | drdestens、bvs（半天内） |
| 4 | 软阴影偏置/边界/彩边三小修 | redhat、bsl-classic、ushader（半天内） |
| 5 | godrays 低档（解析衰减+falloff 早退+双阶段） | drdestens、pyvtron、kuda（半天内） |
| 6 | 解析波场低配档（免纹理） | glimmer、eclipse、kuda、voyager（数天） |
| 7 | TAA 手感（对比度锐化+色调空间统计+相位加权） | sildurs-enhanced、spring、drdestens（数天） |
| 8 | 湿身/水洼/涟漪补齐 | kuda、spring、voyager（数天） |
| 9 | 低保真曝光/亮度补偿暗角/移动量去带 | bvs、glimmer、voyager、lumina、drdestens（半天内） |
| 10 | 设置层（行为预设+Look profile+中性换算） | bsl-classic、spring、drdestens（半天内） |

### ⑤-4 中期（数天～一周+，按依赖排序）

- 体素时域摊还（amethyst 半速率+重投影+背后早退；spring 0.98 重投影）——主世界彩光与下界收敛加速的前提。
- amethyst 消费端细节群（染色玻璃滤色、漏光夹紧、per-kind 光色表、r8ui 占用图、体素图复用）——零新 pass。
- 云三件：多重散射廉价近似（glimmer+ushader+spring+voyager）、时域超分（ushader+reverie+alpha）、平面云低档（kuda+redhat+lux）。
- 雾同源/复用（kuda+reverie+lux）与体积雾远近分段步长（spring）；材质 PBR：LabPBR 孔隙度（voyager+kuda+ushader+spring）、自发光两级门（pyvtron+sildurs+glimmer）、光学常数表（voyager）。
- 后处理：tonemap 算子（lumina+lux+spring+alpha）、运动模糊（clarity+bvs+tea+pyvtron）、DoF（bvs+kuda+tea）、bloom 增量（kuda+voyager+lumina）、抗萤火虫（alpha）。
- Voxy/DH 三件套（sildurs-enhanced+glimmer+bvs）——归口 C5；折射/吸收/SSR 细节（kuda+redhat+tea+eclipse+spring+pyvtron，工作量大头在参数重校）。

### ⑤-5 长期储备（一周+ 或需立项）

- ReSTIR GI 骨架预研（alpha-piscium，XL）与 RSM GI（voyager+spring；批次一判优先走 Ebin GPL 路线）。
- HiZ 深度金字塔/光线打包/自适应光线预算（alpha-piscium）——GI 与 SSR 通用基建。
- 地形 POM（kuda、musk-rose；musk-rose ③10 实测判定「不建议近期做」：Astra 无高度图数据源、每像素多 12+12 次采样）与金属 n/k 表（lux）。
- 静态大气 LUT 全量接入（reverie+musk-rose+pyvtron+redhat）——先对照实验。
- 三层半透明深度（alpha）、水坑体素化（amethyst+lumina）、主世界彩光推广（amethyst+glimmer+reverie+spring 等；Mellow 报告保留意见见 `shader_research/mellow.md:126`（⑥ 段））。

### ⑤-6 未获认可/明确不建议方向（扩写原 §1.3）

- **导数法线 SSAO**：维持不迁移（musk-rose ③4 判定无法提供 bent normal；drdestens P4 同判；bvs 相位螺旋只改采样分布，不省法线缓冲）。
- **雾模型整体**：musk-rose 仅 3 参数×2 套，Astra `global/atmosphere/fog.glsl`（235 行）覆盖更细——无借鉴价值。
- **水面/云整体替换**：musk-rose 水面规模远低于 Astra；bsl-shaders-classic 判"Astra 水体全面超出本包"；amethyst 判云"A 领先一代"。
- **高采样默认值与可疑实现**：eclipse 100-tap SSAO/169-tap 软阴影比 Astra 贵 8 倍以上；pyvtron 450 样本 SSR、帧反馈 bloom（曝光源可疑）、固定 100 步体积雾；eclipse ACES 拟合有实错；voyager 金属分支条件重复不可达；无阈值/固定步长 SSR 整体照搬。
- **与天气/色板强耦合的静态资产**：逐小时色表（redhat #14）、烘焙全景（pyvtron）只宜小范围对照；`parallax/voxel 高度`（spring 判破坏 bent normal/方向性天光基础）不迁移。

### ⑤-7 许可证分层（扩写原 §1.4，逐包结论见 ③）

- **可直接复用代码**：musk-rose（CC0；两处上游方法 + dirtyLens 贴图边界按 ③/④-1 S8 处理）。
- **可复用，须保留版权/许可声明**：glimmer（MIT）；bvs、eclipseshaders（索引 CC-BY-4.0，包内无正文，动代码前先复核）；kuda（索引 BSD-3 与包内协议冲突，裁定前只借思路）。
- **传染性，尽量避免搬代码**：spring（CC-BY-NC-SA，NC/SA 与 Astra 现状硬冲突→实务只重写）；alpha-piscium（GPL-3.0，零搬运）。
- **仅可读思路、重写**：ushader、reverie、clarity、drdestens、tea、sildurs-enhanced、lux、voyager、bsl-shaders-classic、redhat（有条件改编—再分发）、amethyst、lumina、pyvtron。

---

*本汇总只汇编与转引，不替代任何单包报告；各条实施前请回到对应报告核对上下文与不确定项（④）。*

## ⑥ Astra 接续落实（2026-10-02）

用户要求依据本批次材料修改项目后，以下三项已写入当前 Astra 源码；上文 `A:` 行号仍表示调研时快照，现行接口与采用边界见[实施记录](../docs/archive/实现与取证.md#record-009)。

| 汇总建议 | 本次落地 | 默认行为 / 取舍 |
|---|---|---|
| ⑤-3 #2 时间跳变历史失效 | CPU 周期时钟信号，接入 TAA、独立云、下界反射、水下光束及空气曝光 | 自动启用；不新增历史附件或阶段 |
| ⑤-2 #4 体积雾平行阴影空间行进 | 原点、方向变换移至每条射线的循环外，保留各采样点齐次除法和阴影畸变 | 启用体积雾时生效；保留步数、密度及积分模型 |
| ⑤-2 #1 天空缓存 mip + 环境 BRDF | 周期逐层过滤、既有 prepare2 生成 mip、环境相对能量接入水 / 冰 / 积水退路 | 新增“粗糙天空反射”，默认关闭；明确有额外开销 |

BRDF 拟合仅改编 Musk Rose 的上述 CC0 文件并保留来源；其余新增实现只采用报告思路。棋盘云、静态大气 LUT、额外 POM 与 GI 等保留为研究方向，未整体替换当前天空、水体或云模型。
