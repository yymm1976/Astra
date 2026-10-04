# Lumina Shader - Event Horizon v1.3.9 调研报告（面向 Astra）

> **生成方式**：子代理调研（worker 子智能体，白名单只写本文件）。**包版本** v1.3.9（`P:shaders/pack.json:3`）。**调研日期** 2026-10-02。
> **引用约定**：`P:` = `reference_shaderpacks/lumina-shader-event-horizon/` 相对路径；`A:` = `Astra/shaders/` 相对路径。全部行号来自本次实读，成稿后已重开源文件核对（见附录）。

---

## ① 包概览

| 项 | 值 |
|---|---|
| 显示名 / slug | Lumina Shader - Event Horizon / `lumina-shader-event-horizon` |
| 作者/规模 | Benjiaa（`P:shaders/pack.json:5`；致谢 isuewo/SpacEagle17 `P:shaders/lib/uniforms.glsl:2-14`）；实测 1.8 MB（任务书标 0.47 MB，见备注 2），GLSL 约 13656 行 + 3 贴图 + lang + 5 个 `.placebo` |
| 管线形态 | **前向 gbuffers + 8 段 composite + deferred1 + shadowcomp(compute) + final**；world0/world-1/world1 是薄包装（`P:shaders/world0/composite5.fsh:1-7`） |
| 血统/定位 | **Complementary 衍生包**（`P:License.txt:1`；目录/命名/profile 同源），叠加自有末地黑洞-白洞、Lumina 云模型与电影感后期链；写实向，主打高级光照 + 去饱和电影调 |

**许可证关键行（`P:License.txt`，103 行）**：`:1` 标题 Complementary License Agreement 1.6；`:12-13` 再分发/改码不算 Normal Usage；`:43-52` 1.2（Modpack 亦不得改动内容）；`:58-79` 1.3（改包再分发六条件，含 `:68-72` 改名、`:73-76` 视觉须明显不同、`:77-79` 1.3.e **不得附加其它许可**）；`:81-86` 2.1 未被明确授予者一律 **All Rights Reserved**；`:88-90` 2.2 仅当前版本有效；`:92-103` 追责条款。→ 与批次二索引「保留所有权利」一致。

---

## ② 架构与特性清单

**管线/缓冲**：pass 熔断按选项关 program（`P:shaders/shaders.properties:100-114`：SHADOW/FXAA/COLORED_LIGHTING 三处）。缓冲格式表在块注释内（`P:shaders/lib/pipelineSettings.glsl:1-11`：0 R11F 主色 / 1 RGB8_SNORM 半分辨率法线 / 2 RGB16F TAA / 3 RGBA8 主输出+泛光源 / 4 normalM+反射强度 / 5 场景图+云深度+VL / 6 smoothnessD+mask+skyLightFactor / 7 RGBA16F 反射时域 / 8 SSR+顶层不透明度），清屏位与硬件比较采样在活跃行 `:13-21,26`；`colorwheel.properties:8-25` 另用 `oit.*.format` 声明 colortex0/3/4/6/8 与 shadowcolor0/1（并存问题见备注 1）。维度路由 `dimension.properties:4-8`；可选特性 `shaders.properties:117`。设置架构：9 档 profile（`:2-8`）+ screen 树（`:11-63`）+ sliders（`:66`）+ CPU 端 `smooth()`/framemod uniform（`:234-267`）。

**光照/阴影**：单入口 `DoLighting`（`P:lib/lighting/mainLighting.glsl:40-42`，`:34-36` highlightColor）；`shadow2D` 双图彩阴（`shadowSampling.glsl:10-25`）、TAA 旋转盘过滤（`:41-63`）、彩阴强度曲线（`:102-103`）、偏移随雨/维度分档（`:81-100`）；SSAO 全分辨率 2/12 抽样（`program/deferred1.glsl:54-102`）。主世界彩光体素：`image3D` r16ui + rgba16f 洪泛双缓冲，128→1024 档配 workGroups/bufferObject（`shaders.properties:152-225`）；6 邻平均 /6.42 + 染色表（`program/shadowcomp.glsl:54-72`）；采样端 `lib/voxelization/lightVoxelization.glsl:5-7,38-80`。

**反射/材质**：`GetReflection`（`P:lib/materials/materialMethods/reflections.glsl:34-36`；WSR 早返回 `:59-71`；raymarch `:74-90`）；粗糙度模糊 9×9 高斯 + dither 半径 + 法线/深度拒绝（`reflectionBlurFilter.glsl:1-43`）；天空反射 + GGX（`reflectionBackground.glsl:1-21`）；WSR 两级 LOD（`worldSpaceRef.glsl:226,265,299`）与玩家射线（`playerRayTracer.glsl:19,42,63`）；IPBR 大表 `terrainIPBR.glsl`（2719 行）、程序化法线 `generatedNormals.glsl:1-55`、涂层 `coatedTextures.glsl:3-30`、POM `pomEffects.glsl:12-68`。

**大气/云/雾/水**：云 `GetClouds`（`mainClouds.glsl:43-104`）+ 自有密度场（`luminaClouds.glsl:22-101`：octave/雨与高度倍增/erosion/anvil）；相机按噪声周期取模对齐（`:51-69`）；云影直采 shadowtex0（`:18-38`）；雾单入口 `DoFog`（`mainFog.glsl:251`，五种特化 `:202-250`）；泛光雾 `bloomFog.glsl:16-45`；体积光（`volumetricLight.glsl:21`，跨帧 vlFactor `composite1.glsl:290-299`）；水材质三尺度 bump（`water.glsl:101-102,268-269`）；水下色调 `composite1.glsl:243-260`。

**后期（重点）**：顺序 = composite0 雾 → 1 折射/反射/体积光/泛光雾/`pow(color,2.2)` → 2 空占位（`composite2.glsl:23`）→ 3 DOF（`composite3.glsl:96-160`）→ 4 泛光下采样（`composite4.glsl:18-43`）→ 5 泛光/分级矩阵/Lottes 三段/镜头光晕/BSL 饱和（`composite5.glsl`）→ 6 TAA（`composite6.glsl:32-46`）→ 7 FXAA（`composite7.glsl:28-37`）→ final 色差/锐化/暗角/抖动（`final.glsl:86-157`）。节奏件：`lensFlare.glsl:40-120`、`distantLightBokeh.glsl:1-27`（调用 `deferred1.glsl:181-192`）、上帝光常量 `composite.glsl:6-9`。工具件：`textRenderer.glsl` + 6 个 error_*.glsl（`final.glsl:19-42,121-141`）。

---

## ③ 可借鉴点（16 条；「与批次一重复」= 同方向已在批次一 26 份报告出现，作收敛证据）

**1. Lottes 电影色调曲线（中灰锚点 0.25 + hdrMax 8，对比度即指数）**
P: `shaders/program/composite5.glsl:40-68`（参数 `:49-53`，解析解 `:55-66`）；默认 `shaders/lib/common.glsl:277-278`
A: `lib/tonemap.glsl:191-203`（4 算子 dispatch）、`lib/settings.glsl:207`
工作量 **小**（加一个算子 + 枚举）。与批次一重复（`complementary-unbound.md:62`）。

**2. 暗部抬升 darkLift（低亮度混回 gamma 直出，权重随对比度淡出）**
P: `composite5.glsl:70-75`（`darkLiftStart=0.1`、`darkLiftMix=0.75`、`max0(0.55-|1.05-TM_CONTRAST|)/0.55`）
A: `lib/tonemap.glsl:220-228`（端点保守护曲线，无暗部抬升）
工作量 **小**。与批次一重复（`complementary-unbound.md:110-114`）。

**3. Path-to-White（高亮按亮度趋白，指数 `2-TM_WHITE_PATH`）**
P: `composite5.glsl:77-82`；默认 `common.glsl:283`（1.00）
A: `lib/tonemap.glsl:147-153`（AgX look 无白路径）
工作量 **小**。与批次一重复（`complementary-unbound.md:62`）。误差：与 AgX/ACES 肩部叠加会双重压白，只接 Uchimura/自定义曲线后。

**4. 暗部去饱和（只压暗部，不动主体饱和）**
P: `composite5.glsl:84-88`（`dpInputCurveStart=0.1`、`dpInputCurveMax=0.0`）；默认 `common.glsl:282`（0.25）
A: `lib/tonemap.glsl:206-209`（apply_saturation 为全画面常量）
工作量 **小**。与批次一重复（`complementary-unbound.md:112`；`SUMMARY.md` ②-1 亦收录 Insanity/Ebin 同类项）。

**5. 线性域 3×3 + 逐通道幂的分级矩阵**
P: `composite5.glsl:201-207`（公式与 ×0.01）；开关与默认 `common.glsl:284-296`
A: `global/post/grading.glsl:178-188`（三段增益 LGG）
工作量 **小**。Astra 更省但不能混通道；矩阵可色相旋转/去黄。方向与批次一重复（bliss/sildurs），此处补齐公式与默认值供 ⑥。

**6. BSL 式饱和度/自然饱和度三段实现**
P: `composite5.glsl:93-108`（`:94` 饱和 `+0.07` 偏移；`:98` 按因子切换灰度；`:105-107` vibrance→lightness→线性饱和）
A: `lib/tonemap.glsl:211-218`（apply_vibrance 单式）
工作量 **小**。与批次一重复（`bsl-shaders.md`）。

**7. 亮度补偿暗角（暗角增益随像素亮度降低，不压观天亮部）**
P: `final.glsl:147-151`（`1 - dot(uv-.5,uv-.5)*(1-luma)`）
A: `global/post/grading.glsl:204-225`（固定 falloff 0.55/2.0 + 末地 8%）
工作量 **极小**。与批次一重复（`complementary-unbound.md:93`）。

**8. TAA 边缘分级 + 远景收敛（近/远边缘强度表驱动三档）**
P: `lib/antialiasing/taa.glsl:1-28`（三档常量表）、`94-120`（ClampAABB + 深度差 >0.09 判边 + `farEdgeDist` 再乘 extraEdgeMult）、`181-188`（DH 强制高收敛）
A: `program/taa_resolve.fsh:87-136`、`lib/taa_state.glsl:14-32`
工作量 **中**。与批次一重复（`complementary-unbound.md:69`）。

**9. TAA 历史 Catmull-Rom 重采样 + 8 帧抖动位移分档缩放**
P: `taa.glsl:30-57`（textureCatmullRom）、`164-168`；`jitter.glsl:2-25`（8 偏移 + 0.125/0.33 缩放）
A: `lib/taa_jitter.glsl:12-19`（已有 8 帧偏移）、`program/taa_resolve.fsh:58`
工作量 **小**（Astra 缺的只是历史重采样）。与批次一重复（`complementary-unbound.md:69`）。

**10. 泛光：无阈值「1/4 gamma 存储→pow4 还原」+ 7 tile + `mix` 合成 + 黑暗自适应强度**
P: `composite4.glsl:18-43`（7×7 二项核、`pow(bloom/128,0.25)`）；`composite5.glsl:110-149`（平方两次还原、0.14 平均、`:134` `BLOOM_STRENGTH+0.2*darknessFactor`、`:136-144` 下界距离增强）
A: `global/post/bloom.glsl:32-48`（阈值 1.0+软膝 0.5+上限 16）、`167-192`（mip 0.4/0.3/0.2/0.1 加法）
工作量 **小-中**；不整体替换（取舍已记录 `bloom.glsl:3-8`），增量仅黑暗自适应。与批次一重复（`complementary-unbound.md:116-121`）。

**11. 泛光雾：雾先除出画面、泛光后乘回，避免雾被二次泛光**
P: `lib/atmospherics/fog/bloomFog.glsl:16-45`；应用点 `composite5.glsl:193-195`（除）、`composite1.glsl:283-285`（乘）
A: 无对应（泛光与雾独立）；落点 `global/post/bloom.glsl` + `global/atmosphere/fog.glsl`
工作量 **小-中**。与批次一重复（`complementary-unbound.md:61`）。

**12. 屏上文字报错 + Iris 可选特性协商**
P: `shaders/shaders.properties:117`；条件判定 `final.glsl:19-42`、绘制 `:121-141`；绘制器 `lib/textRendering/textRenderer.glsl`
A: 无（Astra 无 textRendering 目录）
工作量 **小-中**（工具件，不碰画面）。与批次一重复方向（`amethyst-shaders.md:169` 登记为 QA 工具）。

**13. 材质策略位打包：一个材质整数编码 SSAO/TAA/反射三套策略**
P: `lib/common.glsl:820-836`（241 水 / 251 无 SSAO 减反射 / 253 减边 TAA / 254 无 SSAO 无 TAA 减反射 / 149.5 实体反射带）；消费 `taa.glsl:139-144,178-179`、`program/composite.glsl:117`→`deferredMaterials.glsl:17-23`、`composite1.glsl:151-153`（fresnel 门控跳过反射）
A: `lib/taa_reactive.glsl:3-10`（另开 colortex16 R8）+ `program/deferred.fsh:324` 写 + `program/taa_resolve.fsh:87-100` 读
工作量 **中**。Lumina 零额外 buffer/带宽；Astra reactive 是派生量，Lumina mask 是声明量（零漏检但需维护表）。**新**。

**14. 末地黑洞/白洞解析式电影化包装（爱因斯坦环 + 光子环 + 多普勒 + 4 滑块 + 反向白洞）**
P: `lib/atmospherics/eventHorizon.glsl:1-28`（`1/angle` 偏折镜天空）、`:105-125`（back-disk `mix(R_out,R_in,smoothstep(1.0,1.35,r))`）、`:54,62`（多普勒色偏）、`:144-147`（光子环 glow）、`:188-261`（白洞）；滑块 `lib/common.glsl:114-122`、`shaders.properties:34`
A: `global/dimension/end_blackhole.glsl:23-66`（Kerr 传输图+双像序）、`end_kerr.glsl:29-43`（自旋 0.94 图集）、`end_plasma.glsl`
工作量 **小**（仅装饰件）；**不替换 Astra 主体**。**新**。

**15. 云密度场三尺度叠加 + 相机按噪声周期取模对齐（消 TAA 下云蠕动）**
P: `luminaClouds.glsl:76-101`（`1.35 + 0.1*(-y/tallness) + RAIN_DENSITY*rainFactor`；erosion `:90-93`；anvil `:95-97`）；`mainClouds.glsl:51-69`（`cameraPositionInt.xz - modFactor*(cameraPositionInt.xz/modFactor)`）
A: `global/atmosphere/clouds_planar.glsl:263-289`、`global/atmosphere/cloud_temporal.glsl`（独立历史）
工作量 **小-中**。云模型与批次一重复（`amethyst-shaders.md:25`）；取模对齐未见记载。

**16. 水面多尺度 bump 六滑块 + 掠射角法线压平**
P: `translucents/water.glsl:101-102`（三尺度加权后 `*6*(1-0.7*fresnel)*WATER_BUMPINESS`）、`:268-269`；默认 `common.glsl:76-81`
A: `global/water/surface.glsl:79-96`（4 ripple+2 crest）、`:145-160`（权重归一）、`:15,188`（footprint 滤波）
工作量 **小**；Astra 波场更物理，缺「分尺度用户振幅」；`1-0.7*fresnel`（按视角）与 Astra footprint 滤波（按屏幕足迹）可对照。与批次一重复（`bsl-shaders.md:70-74`；SUMMARY ②-2）。

---

## ④ Astra 已有对应实现对照

| 子系统 | Lumina（P:） | Astra（A:） | 哪边更省 / 误差来源 |
|---|---|---|---|
| 色调映射 | 单算子 Lottes + 三段风格化（`composite5.glsl:40-91`） | 4 算子（`lib/tonemap.glsl:191-203`），链序 `display.fsh:171-192` | Astra 算子自由度胜；三段风格化全缺，引入需按算子标定 |
| 分级 | 线性域矩阵 `composite5.glsl:201-207` + BSL 饱和 `:93-108` | 显示域温/vibrance/sat/对比 + LGG `grading.glsl:190-197,178-188` | Astra 更省；矩阵能混通道而 LGG 不能 → 跨通道偏色无低成本等价物 |
| 泛光 | 7 tile 固定偏移 + pow4 无阈值 `composite4.glsl:18-43`、`composite5.glsl:110-149` | 软膝 prefilter + mip 加权加法 `bloom.glsl:32-48,167-192` | Lumina 无阈值有灰雾风险（取舍已记录 `bloom.glsl:3-8`）；8 位 1/4 gamma 存 HDR vs R11F |
| 抗锯齿 | TAA + FXAA311 `composite6.glsl:32-46`、`fxaa.glsl:21-204` | TAA resolve + reactive `taa_resolve.fsh:87-136`、自研 FXAA `fxaa.glsl:27-92` | Astra 自动派生省人手，Lumina 材质声明更精确且多 Catmull-Rom 历史 |
| SSAO | 全分辨率 2/12 抽样 `deferred1.glsl:54-102` | 半分辨率 + bent normal `ao_resolve.glsl:19-30`、`ao_material.glsl:3-6` | Astra 更省（半分辨率 + 天光复用）；Lumina 2 抽样档偏糙 |
| 自动曝光 | 无（仅 `TM_EXPOSURE` `common.glsl:277`） | 64 tap 几何平均 + 对数有界历史 `exposure.glsl:39-96` | Astra 独有更强，无可借 |
| 彩色方块光 | 体素 128→1024 可选 + 洪泛 + 半速率重投影 `shaders.properties:152-225`、`shadowcomp.glsl:15-30,54-72` | 固定 64³ 同帧体素 `nether_voxel_grid.glsl:18-25`、`nether_colored_light.glsl:13-25` | Astra 更省；Lumina 分辨率可调是性能旋钮，代价为残影与显存（bufferObject 至 810 MB 级） |
| 反射 | WSR 两级 LOD + 粗糙度模糊 `worldSpaceRef.glsl:226,265,299`、`reflectionBlurFilter.glsl:1-43` | 天空缓存固定 mip 0 `sky_reflection_cache.glsl:29` + SSR | Astra 更省；天空反射无粗糙度分级是短板（批次二 SUMMARY-batch2 1.2 双报告印证），Lumina 9×9 高斯+dither 即解法 |
| 云 | 逐帧重算 + IGN/TAA 抖动 `mainClouds.glsl:9-16,43-104` | 平面云 + 独立历史 `clouds_planar.glsl:263-289`、`cloud_temporal.glsl` | Astra 时域更强；Lumina 取模对齐是低成本消蠕动（不治噪点） |
| 水 | 三尺度 bump + fresnel 压平 `water.glsl:101-102` | 4 ripple+2 crest 归一 `surface.glsl:79-96,145-160` + `solas_water.glsl:19,83,115` | Astra 更完整；Lumina 仅用户振幅外露占优 |
| 末地黑洞 | 解析假体 + 手调环 + 白洞 `eventHorizon.glsl:1-150,188-261` | Kerr 传输图 + 双像序 `end_blackhole.glsl:23-66`、`end_kerr.glsl:29-43` | Astra 物理正确性完胜；Lumina 光子环与白洞是 Astra 没有的内容创意 |
| 材质 | IPBR 2719 行 + 程序化法线 + 涂层 | 湿材质三参数 `wet_material.glsl:16-21` | Astra 更省；Lumina 覆盖广（批次一 `complementary-reimagined.md:88` 已评估） |
| 设置 | 9 档 profile + CPU uniform `shaders.properties:234-267` | 4 档 profile + smooth() uniform `shaders.properties:421-447` | 量级相当（两边都有 CPU 平滑与熔断） |

---

## ⑤ 许可可行性与「重写 vs 抄」边界

本包是 Complementary License 1.6 的 Modified Pack（`P:License.txt:1,58-79`），自身只有 1.3 赋予的有限权利；可取用的仅「已公开的思想」。

1. **可以**：读源码理解算法，把「暗部去饱和 0.25」「Lottes 四参数锚点」等抽象成需求，用 Astra 自己的函数/命名/宏体系重写，并在 PROVENANCE 段与 `THIRD-PARTY.md` 登记（沿用 `A:global/post/grading.glsl:253-268` 做法）。
2. **不可以**：复制代码段/注释/标识符（如 `DoBSLColorSaturation`、`darkLiftMix`）、复制选项串与 profile 行、复制 lang 文案、搬运贴图。
3. **特别禁止**：Astra 若采用自有许可证或与第三方条款并存，与 `P:License.txt:77-79`（1.3.e）**直接冲突**——「改编成本包一部分」这条路不存在；③ 各条一律按思路级重写。
4. 本次未向 `Astra/` 或本包写入任何内容（对源包只读）。

结论：**思路级可行，代码级零可行**；风险最高档（ARR + 传染性 + 追责）。

---

## ⑥ Top5 与暂缓项

### 6.1 去饱和电影调的具体参数（供 Astra 四种颜色方案对照）

（方案名对照：`A:docs/2026-10-02-colour-and-quality-options.md:9-12` Astra 原生/暖色自然/冷色通透/柔和；色调通道 `A:shaders.properties:722`、POST 行 `:428`）

| 配料 | 数值 | 位置 |
|---|---|---|
| S 曲线（对比） | `a = TM_CONTRAST = 1.28`、`d = 1.0`、`hdrMax = 8.0`、中灰锚点 `midIn = midOut = 0.25`（**无控制点数组，由 4 个标量解析生成**）；曝光 `TM_EXPOSURE 1.25`（`common.glsl:277`） | `P:shaders/program/composite5.glsl:49-53`（公式 `:55-66`） |
| 暗部抬升 | `darkLiftStart=0.1`、`darkLiftMix=0.75`，权重 `1-smoothstep(0,0.1,luma)` 再乘 `max0(0.55-|1.05-TM_CONTRAST|)/0.55` | `composite5.glsl:71-75` |
| Path to White | `wpInputCurveStart=0.0`、`wpInputCurveMax=16.0`、指数 `2-TM_WHITE_PATH`（默认 1.0），`mix(colorOut, vec3(1.0), whitePath)` | `composite5.glsl:78-82`；默认 `common.glsl:283` |
| **暗部去饱和（核心）** | `dpInputCurveStart=0.1`、`dpInputCurveMax=0.0`；量 = `0.25 × (1-smoothstep(0.0,0.1,luma))`，只把暗部混向自身灰度 | `composite5.glsl:84-88`；默认 `common.glsl:282` |
| 分级矩阵（默认恒等/关闭） | `pow(c.r,GR_RC)*vec3(GR_RR,GR_RG,GR_RB)+pow(c.g,GR_GC)*vec3(GR_GR,GR_GG,GR_GB)+pow(c.b,GR_BC)*vec3(GR_BR,GR_BG,GR_BB)`，×0.01；恒等 = 对角 100、其余 0、RC/GC/BC 1.00 | `composite5.glsl:201-207`；默认 `common.glsl:284-296`（`COLORGRADING` 默认注释掉） |
| 饱和/自然饱和 | `T_SATURATION 1.20`、`T_VIBRANCE 1.00`，实现另加 `+0.07` | `common.glsl:279,281`；`composite5.glsl:93-108`（`:94`） |
| 链序（决定以上语义） | 矩阵（线性域）→ tonemap+编码 → 镜头光晕 → BSL 饱和 → 输出 | `composite5.glsl:201-207 → 228 → 248-252`；编码 `:35-38,68` |

**最小组合建议**：`TM_DARK_DESATURATION 0.25` + Path-to-White + 亮度补偿暗角三项即可复现该包的「去饱和电影调」主体，均为显示域小函数；3×3 矩阵仅在需要**跨通道**偏色（去黄、青橙对调）时引入，否则 Astra 现有 LGG 三段增益（`lib/settings.glsl:304-312`）更省。

### 6.2 Top5（按 提升/工作量）

1. **Tonemap 三段风格化**（暗部抬升 + Path-to-White + 暗部去饱和）——服务主打观感，纯显示域，可与 4 算子并存；对照 ③.2/3/4。
2. **输出端三件套**：亮度补偿暗角 + 径向色差（`final.glsl:96-100`）+ 4 向负核锐化（`final.glsl:49-72,102-104`，TAA 开时强度减半）——工作量极小；对照 ③.7。
3. **彩色阴影强度曲线**：`colorMult = 2.5+5.5*lmY^1.5+2*lmY²`、`colorPow = mix(1.5+0.5*(非水下), 0.5, lmY⁴)` 与采样偏移随雨/维度分档（`shadowSampling.glsl:81-103`）——改 `shadowmap.glsl` 数值即可。
4. **TAA 手感表 + Catmull-Rom 历史**（`taa.glsl:1-28,30-57,94-120`）——纯参数/采样升级；对照 ③.8/9。
5. **泛光黑暗自适应 + 泛光雾**（`composite5.glsl:134`、`bloomFog.glsl:16-45`）——夜景/下界/洞穴收益大；对照 ③.10/11。

### 6.3 暂缓项

- **WSR 体素反射/玩家射线**（`worldSpaceRef.glsl:226,265,299`）：需 SSBO + 体素化 + 手工 mip，批次一 `complementary-reimagined.md:97` 已判「很高」。
- **水洼体素**（`puddleVoxelization.glsl:1-33`）：需 shadow pass 写 `puddle_img` 且与彩光同开（`common.glsl:531-533`）；Astra 湿材质已覆盖观感主体（`bsl-shaders.md:70-74`）。
- **末地黑洞替换 / 3×3 矩阵分级 / 解析镜头光晕**：前者 Astra Kerr 解算更强（只取光子环/白洞）；矩阵与 Astra 通道倍率体系重叠；光晕在写实定位易显廉价，批次一 `complementary-unbound.md:104-108` 同判「默认关」。
- **屏上报错文本**（③.12）：工具价值，QA 阶段单独评估。
- **云取模对齐**（③.15 后半）：需先确认 Astra 云历史是否真有蠕动残差。

---

## 附录：引用自抽查记录（24 条，逐条重开源文件打印核对；`P:` 省略 `shaders/` 前缀）

1. `P:program/composite5.glsl:40` → `void DoCompTonemap(inout vec3 color) {` 命中
2. `P:program/composite5.glsl:201,203,206` → `#ifdef COLORGRADING` / `pow(color.r, GR_RC)*vec3(GR_RR,GR_RG,GR_RB)+` / `color *= 0.01;` 命中
3. `P:lib/common.glsl:277-283` → 277 1.25 / 278 1.28 / 279 1.20 / 281 1.00 / 282 0.25 / 283 1.00 命中
4. `P:program/composite4.glsl:42` → `return pow(bloom / 128.0, vec3(0.25));` 命中
5. `P:lib/lighting/shadowSampling.glsl:102-103` → colorMult `2.5+5.5*pow1_5(lmY)+2.0*pow2(lmY)`；colorPow `mix(1.5+0.5*…,0.5,pow2(pow2(lmY)))` 命中
6. `P:lib/atmospherics/eventHorizon.glsl:110` → `mix(R_out, R_in, smoothstep(1.0, 1.35, r))` 命中
7. `P:program/final.glsl:149` → `1.0 - dot(texCoordMin, texCoordMin) * (1.0 - GetLuminance(color))` 命中
8. `P:lib/common.glsl:827-832` → 241.0 Water / 251.0 No SSAO / 253.0 Reduced Edge TAA / 254.0 No SSAO,No TAA 命中
9. `P:lib/atmospherics/clouds/luminaClouds.glsl:76-81` → `#define LUMINA_CLOUD_BASE_ADD 1.35` / `+ LUMINA_CLOUD_RAIN_DENSITY * rainFactor;` 命中
10. `P:lib/pipelineSettings.glsl:13,21,26` → colortex0Clear / colortex8Clear / `shadowHardwareFiltering = true` 命中
11. `P:colorwheel.properties:8,10` → `oit = true` / `oit.gbuffers.coefficientRanks = 3,3` 命中
12. `P:lib/atmospherics/volumetricLight.glsl:21,32-34` → `GetVolumetricLight(` / chunkFade 三行 命中
13. `P:lib/lighting/mainLighting.glsl:40` → `void DoLighting(inout vec4 color, …` 命中
14. `A:lib/tonemap.glsl:191,193,203` → `apply_tonemap` / `#if TONEMAP_OPERATOR == TONEMAP_UCHIMURA` 命中
15. `A:lib/tonemap.glsl:226` → `vec3 curved = 0.5 * pow(2.0 * min(c,1.0-c), vec3(contrast));` 命中
16. `A:global/post/grading.glsl:190,195` → `apply_grading` / `color = apply_tonal_balance(color);` 命中
17. `A:global/post/bloom.glsl:32,48,185-188` → `BLOOM_THRESHOLD 1.0` / `BLOOM_CAPTURE_SCALE 0.25` / mip 0.40+0.30+0.20+0.10 命中
18. `A:lib/taa_reactive.glsl:7-8` → `colortex16Format = R8` / `colortex16Clear = true` 命中
19. `A:program/display.fsh:176` → `srgb_encode(apply_tonemap(apply_exposure(apply_auto_exposure(astra_purkinje(hdr)))))` 命中
20. `A:lib/sky_reflection_cache.glsl:29` → `textureLod(colortex11, vec2(u, v), 0.0)`（固定 mip 0） 命中
21. `A:lib/wet_material.glsl:16-21` → 三档 wetClass 返回 + 默认 命中
22. `A:global/dimension/end_blackhole.glsl:23`、`end_kerr.glsl:29` → 两函数名命中
23. `A:lib/nether_voxel_grid.glsl:21,23` → `astraVoxelImage / astraLightA … 64 64 64` / `local_size 8³, workGroups ivec3(8,8,8)` 命中
24. `A:docs/2026-10-02-colour-and-quality-options.md:9-12` → 四行方案名 命中

**核对中修正 1 处**：③.13 初稿把 `deferred1.glsl:117` 写成 deferredMaterials 分派，实为 `nightNebula.glsl` 的 include；已改为 `composite.glsl:117` + `deferredMaterials.glsl:17-23`。

---

## 备注（需统帅处置）

1. [疑问] 缓冲格式声明并存：`P:shaders/lib/pipelineSettings.glsl:2-10` 整段在 `/* */` 内，而 `colorwheel.properties:8-25` 只用 `oit.*.format` 声明参与 OIT 的 colortex0/3/4/6/8 与 shadowcolor0/1。colortex1/2/5/7 的格式若只存在于注释里，是否被 Iris 解析（其解析按行正则、通常不识别块注释）需实测；只登记事实。
2. [疑问] 任务书标「全包 0.47MB」，实测 1.8 MB；疑为压缩包/解压副本之别。
3. [假设] 本包与 `complementary-unbound` 同源但版本不同（本包 `DoCompTonemap` 在 40-91，批次一报告记 36-88）；③ 行号一律以本包实测为准，未转引批次一。
4. [假设] ⑥ 参数按出厂默认取值（`COLORGRADING` 关闭、`TM_WHITE_PATH 1.00`）：该包出厂靠 tonemap 三段项出调子，包内无恒等以外的 GR_* 预设可抄。
5. [建议] 暗部去饱和建议只挂「柔和」「冷色通透」两方案并做成方案内常量，避免与 `A:lib/settings.glsl:214` 的 SATURATION 滑杆语义重叠。
6. [建议] ③.14 只立项「光子环 glow + 白洞开关」，不替换 Astra 主体（Kerr 解算更强）。
7. [阻塞] 无。全程只读 `Astra/`（并行工作流未提交改动未被触碰），仅新建本文件。
