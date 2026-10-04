# trailershaders 性能调研（batch4）

日期：2026-10-03。范围：只读调研，产物仅本文件；行号相对 `reference_shaderpacks/trailershaders/shaders/`。
去重基线：`shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`（下称「五份材料」），以及任务背景列出的 Astra 已实现手段。

## 概况

- 定位：Modrinth vr1.6，213,983 下载。复刻 Minecraft 宣传片观感（高饱和、镜头光晕、色差、暗角、宽银幕条），并强调更高帧率（包根 `CHANGELOG.md:5-7` v1.6「Performance update / Optimized shadow resolution / Optimized underwater caustics」）。**其帧率来自功能缺席**（无 TAA/SSAO/SSR/体积雾/体积云/曝光/色调映射链以外的一切），而非调度或采样优化。
- 血统：自研/自教；前身为同作者 BareBone Shaders（`CHANGELOG.md:38-40`）。代码内无任何第三方来源标注（仅有通用噪声/tonemap 公式），与已研究的 42+20 包无同源代码关系。
- 许可：包根 `LICENSE:1` 「All Rights Reserved.」、`:3` Copyright (c) 2026 GamesofDev、`:5` 「TrailerShaders is a proprietary shader pack. Unauthorized copying, modification, distribution, or use ... strictly prohibited」→ **不能抄代码**，仅思路级参考。
- 规模：50 文件 / 1,483 行（.fsh/.vsh/.glsl；另含 `shaders/world0/textures/environment/clouds.png` 一图）。全部为 legacy `#version 120`、`gl_FragData`、OptiFine 别名（gcolor/gnormal）。

## 管线与调度

- program 清单（world0）：`shadow`(vsh/fsh)、`gbuffers_basic/clouds/entities/hand/hand_water/skybasic/skytextured/terrain/textured/textured_lit/water/weather`、`composite`（阴影 + 水下扭曲）、`final`（光晕/泛光/调色/tonemap）。**无 deferred、无 composite1..n、无 TAA/SSAO/体积链**。world-1 与 world1 各含 `gbuffers_terrain/entities` + `composite`（纯拷贝）+ `final`（色偏/下界强制泛光）。
- 开关：`shaders.properties:8` OptiFine 旧式 `options=`（Lensflare/Bloom/ChromaticAberration/CinematicBars/ToneMapPreset/CloudToggle/FoliageWave/ShadowMapping/WaterWave/UnderWaterCaustics/RainPuddles），`:5` sliders 含 ShadowSamples；**无 `program.*.enabled`、无 `size.buffer`、无分辨率分档、无 profile 系统**。
- 缓冲：全包单一颜色目标 `gcolor`(colortex0) + 深度；无自定义格式声明（`world0/composite.fsh:40-43` 的 `RG16=0 / RGBA16=1` 为自造常量，见「无法判定」）；`shadow.fsh` 输出阴影图；`gbuffers_weather.fsh:11` 把雨条写到 colortex7。
- 固定常量：`world0/composite.fsh:44-46` `sunPathRotation=-40.0`、`shadowMapResolution=2048`、`noiseTextureResolution=256`。

## 分模块性能手法清单

### 调度与阶段启停
- `world0/final.fsh:9-15` — 昂贵效果均为注释 define：`//#define Bloom`、`//#define ChromaticAberration`、`//#define CinematicBars`、`VignetteIntensity 0.0`；`#define Lensflare` 默认开。
- `world-1/final.fsh:6-7` — 下界强制开 Bloom（Quality 1）。
- `world0/gbuffers_clouds.fsh:19-22` — 云用运行期 `discard` 代替该 pass 的停调度（能力上弱于 Iris 程序门控）。
- **没有任何程序级启停/资源缩编**：关闭功能时对应 pass、缓冲、draw 仍存在（见反面印证）。

### 地形光照与阴影
- `world0/composite.fsh:59-88` — 阴影在 composite 全屏 pass 完成：由 depthtex0 反投影世界坐标，手动深度比较 `ShadowSamples`（默认 4，滑条 1–64，`:7`）次。
- `world0/composite.fsh:61-62` — `if (dist > 0.9) return extShadow`：超 90% far 距离直接回退，不做阴影查询。
- `world0/composite.fsh:84` — `shade -= clamp((dist-0.7)*5,0,1)` 距离淡出；`:86` `max(shade, extShadow)` 保证远距保持受光。
- `world0/composite.vsh:26-44` — 日出/日落窗口的 `extShadow` 回退值与日月切换在**顶点**算好（全屏 quad 仅 4 顶点）。
- `world0/composite.fsh:103` — `step(0.99, color.a)`：水/半透明像素跳过阴影。
- `world0/composite.fsh:105-115` — 时段阴影强度（昼 0.5 / 夜 0.2）直接乘在颜色上。
- `world0/shadow.vsh:8-12` — 阴影 pass 仅做投影 + 平方畸变；`world0/shadow.fsh:8` 片元纯纹理拷贝（零加工）。
- `world0/gbuffers_terrain.fsh:83-84,133-134` — 地形光照 = 纹理×顶点色×lightmap + 火把附加色；无 N·L、无法线（全包只写 colortex0，无 gbuffer 法线）。

### 云
- `world0/gbuffers_clouds.fsh:9,19-22` — `CloudToggle==0` 直接 discard（运行期分支）。
- `world0/gbuffers_clouds.fsh:25-29` — 原版云纹理按世界 XZ 0.001 缩放 + `fract` 重复 + 每帧 1 次采样（非 raymarch）；`:32-36` 太阳 glow 混合。
- `world0/gbuffers_clouds.vsh:31-32` — 云 UV 漂移在顶点算好。

### 雾与大气
- `world0/gbuffers_skybasic.fsh:15-39` — 三段解析渐变天空（zenith/mid/horizon），`:11-13,38` 有理雾 `w/(x²+w)` 混向 fogColor。
- `world0/gbuffers_skybasic.fsh:43-44` + `world0/gbuffers_skybasic.vsh:7` — 星点由顶点 `gl_Color` 三分量相等标志直接输出，无星点纹理/程序化星空。
- `world0/gbuffers_terrain.fsh:136` — 地形雾只在雨强 >0 时按距离 mix（`rainStrength` 混合），平时不付雾计算。

### 水与水下
- `world0/gbuffers_water.fsh:16-21` — 固定水色 tint + 固定 `alpha = 0.5`（`:19`）；水面无折射/反射/波法线。
- `world0/gbuffers_water.vsh:40-48` — mc_Entity 8/9 时置 `waterFlag=1` 并透传火把光坐标（该 varying 在 fsh 内未被使用）。
- `world0/composite.fsh:117-122` — 水下全屏 UV 扭曲：1 次 `snoise` 偏移；`:119` 混入量用 `saturate(float(frameTimeCounter))`（>1 秒后恒为 1，疑似 bug）。
- `world0/gbuffers_terrain.fsh:61-78,87-91` — 水下焦散：`worldTime` 驱动的 2 次 noisetex 采样（`:77` 第二个噪声被注释丢弃）；`:87` 在 `isEyeInWater` 判断（`:89`）之前无条件执行。

### 粒子·实体·天气
- `world0/gbuffers_weather.fsh:9-14` — 雨条仅 `texture*color`，`:11` 写 `DRAWBUFFERS:7`（colortex7），全包无人读取。
- `world0/gbuffers_entities.fsh:12-14` — 实体仅 `entityColor` 染色 + lightmap，无阴影/法线。
- 无雨溅射粒子、无手持光源、天气无 rainStrength 门控。

### 后处理与缓冲内存
- `world0/final.vsh:39-81` — final 全屏 pass 的**顶点阶段**完成：`:48-50` 太阳 NDC 是否在视口内；`:53-61` 9×9=81 次 depthtex0 采样求太阳可见度（`:59` 每次 +1/81）；`:62-64` 屏幕边缘 smoothstep 淡出；`:66-79` 13 个镜头光晕屏幕坐标一次性算好经 varying 插值。
- `world0/final.fsh:97-115` — 13 个解析光晕；`sunVisibility<=0` 或 `rain>=0.3` 整体早退（`:99-100`）；每颗先用曼哈顿距离包围盒测试（`:19-26`）再做 sqrt。
- `world0/final.fsh:130-157` — 泛光：对 gcolor 全分辨率螺旋采样（Quality×steps 双层循环；默认 Q=1 时 4 次），阈值在平均之后（`bloomThreshold=1.0` 为恒等）。
- `world0/final.fsh:159-179` — 色差按质量 1–8 环采样（默认关）。
- `world0/final.fsh:235-243` — tonemap 三选一（Uncharted2/Reinhard/ACES 拟合）；`:245-246` 饱和度；`:250-255` 宽银幕黑条。
- `world0/final.fsh:221-233` — 曝光是裸 `pow(color,1.4) * 15 * Brightness * 时段系数`（无自动曝光/白点保护）。
- `world-1/composite.fsh:8-11`、`world1/composite.fsh:8-11` — 纯拷贝全屏 pass；`world-1/final.fsh:6,54` — 下界强制泛光 + red×1.8；`world1/final.fsh:11-13` — 末地三通道乘系数。

## 反面印证

1. 「更高帧率」的实现方式是删功能 + 固定低预算（2048 影图、默认 4 tap、无 TAA/SSAO/SSR/体积/曝光），不包含可迁移的调度或采样优化；不应把它当作性能标杆。
2. `world0/gbuffers_terrain.fsh:87`：`getCaustics()` 在 `if(isEyeInWater==1)`（`:89`）之前无条件执行，陆地像素白付 2 次 noisetex 采样；且 `:77` 的 `noise2` 算出即弃——应把采样移入水下分支并删除死计算。
3. `world0/gbuffers_terrain.fsh:96-128`：7 段材质 flag 分支各自重复 `texture2D(texture, texcoord)` 采样同一纹素（累计约 15 次，多数驱动会命中缓存但仍是无谓指令）——应取一次存变量。
4. `world0/composite.fsh:74-82`：阴影循环内**每样本**重算 `rand2d(shadowposition.xy * i)`（每次 2 个 sin 哈希）；应预生成一次旋转序列或查表。
5. `world0/final.fsh:142-146`：泛光抖动 `jitterCoord` 在样本循环内每 tap 重算（含 2 次 sin）；应在循环外算一次。
6. `world0/gbuffers_weather.fsh:11`：雨条写 colortex7 但全包无消费者（该 pass 的输出死掉）；应在 properties 停用该程序或接回显示链。
7. `world-1/composite.fsh:8-11` / `world1/composite.fsh:8-11`：下界/末地的 composite 是纯拷贝全屏 pass，白付一次读写；应由程序门控停用。
8. `world0/composite.fsh:40-43` 声明了从未使用的 `gnormal`/`gnormalFormat`；`world0/final.fsh:43` 声明了从未使用的 `gaux1`——管线声明与实现脱节。
9. `world0/composite.fsh:105-115,221-233`：把阴影与曝光直接乘在最终颜色上（不分离直射/天光），且时段系数按 worldTime 硬编码乘 15——观感与可维护性均差，不是可借的性能手法。
10. 全包无 `backFace`/原版 pass 关闭类管线级开关、无 buffer 尺寸分档；关闭效果后资源与 pass 不缩编（对照 Astra 的 size.buffer + 阶段启停纪律）。

## 新颖借鉴点

- A（低代价可直接排期）：**无**
- B（中代价需接线）：**无**
- C（大工程战略项）：**无**

逐候选去重（每条含 Astra 侧证据）：

| 候选（本包出处） | 去重依据 |
|---|---|
| 太阳可见度 9×9 深度探针 + 顶点阶段广播（`world0/final.vsh:48-64`） | batch3 §2.1 A 组「单像素聚合 + 纹理广播」（LIGHT 13×13 + final 广播）已列；Astra 自身已有 `program/scattering.fsh:55-84` 单像素 7×7 `godrays_sun_visibility` + `:139` texel(0,0) 广播（49 次/帧，比 4 顶点×81 更省），双重覆盖 |
| 阴影距离早退/淡出（`world0/composite.fsh:61-62,84`） | 五份材料已列「阴影越界钳制/夜间早退」「距离淡出」；Astra `global/lighting/shadowmap.glsl:91` 有距离 smoothstep 淡出，`shaders.properties:476` 性能档 `SHADOW_DISTANCE=112` |
| 半透明/水面跳过阴影（`world0/composite.fsh:103`） | Astra 已有「遮挡时才读彩色阴影」「背光跳过」与材质门控（`global/lighting/diffuse.glsl:335,398`） |
| `extShadow` 日出日落回退在顶点算（`world0/composite.vsh:26-44`） | Astra「帧不变量/调色下沉 CPU（uniform 预计算、顶点常量平替）」已实现（任务背景） |
| 云开关 discard（`world0/gbuffers_clouds.fsh:19-22`） | Astra 有程序级启停（`shaders.properties:88-104` `program.*/composite6/7.enabled` 等）与云像素 discard（`program/clouds.fsh:27,31`），机制已内化且更省 |
| 雨坑/焦散噪声门控（`world0/gbuffers_terrain.fsh:37-59,87-91`） | 五份材料已列水洼掩码（SUMMARY ②-2 首行，7 包印证）与焦散族；Astra 已有 `lib/wet_material.glsl`、`global/water/caustics.glsl` |
| 镜头光晕/色差/宽银幕条（`world0/final.fsh:97-179,250-255`） | 属风格件而非性能手法；镜头光晕已在 SUMMARY ②-8「老式解析镜头光晕（默认关）」列出；Astra 无该功能（grep `lensflare|flare` 0 命中），本包变体不构成新的性能手法 |
| 水下 UV 扭曲 1 次 snoise（`world0/composite.fsh:117-122`） | 与 Astra 水下链（按距离吸收、解析焦散、独立历史光束）取向不同；且其混入量表达式疑似 bug，不作为借点 |
| CPU/顶点常量（`world0/composite.vsh:26-44`） | Astra 已实现且更彻底 |

结论：**该包没有 Astra 未实现、且未被五份材料列出的性能手法**。其调研价值集中在「以删功能换帧率」的反面印证，以及少量取样纪律问题（上面 2–5 条）——这些属于本包实现缺陷，不构成可排期的新颖点。

## 无法判定项

1. `world0/composite.fsh:40-43` 自造 `const int RG16=0; const int RGBA16=1;` 覆盖内置格式枚举，`gnormalFormat` 未被使用、`gnormal` 无任何写入/读取：这些声明是否对 Iris 生效、实际 colortex0 格式为何，无法静态判定。
2. `world0/composite.fsh:5` 硬编码 `#define ShadowMapping`，而 `shaders.properties:8` 又把它列为 `ShadowMapping:0,1` GUI 选项（默认 0=OFF）：最终该 define 是否被选项覆盖，无法从源码静态判定（影响「阴影默认是否运行」的结论）。
3. `world0/gbuffers_weather.fsh:11` 的 colortex7 是否被 Iris 以默认方式合并显示无法确认（代码内无消费者）；若确实无消费者，雨条功能实际是死输出。
4. `world-1/final.fsh:6-7` 下界强制开 Bloom 且 `:54` red×1.8，与 `world1/final.fsh:11-13` 无 Bloom + 三通道衰减不一致，是否为未完成分支无法判定。
5. `world0/composite.fsh:119` 的 `saturate(float(frameTimeCounter))` 疑似应为常量/渐变门控；行为无法静态判定。
6. 包内无任何作者基准帧时数据；本报告的收益判断均为源码级推断。
