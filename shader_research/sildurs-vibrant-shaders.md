# Sildur's Vibrant Shaders v2.02 (Extreme) — Astra 可借鉴点研究

- 研究对象：`reference_shaderpacks/sildurs-vibrant-shaders/`（137 文件，无 lib 汇总目录，代码按程序平铺复制）
- 对照目标：`Astra/shaders/`（Iris 前向光照，Solas/Steadfast/Complementary 血统）
- 引用约定：`文件:行号` 均相对包根 `shaders/`（如 `deferred.fsh:232` 指 `reference_shaderpacks/sildurs-vibrant-shaders/shaders/deferred.fsh` 第 232 行）；Astra 侧引用相对 `Astra/shaders/`。行号经二次抽查（≥40 条重开核对）。

## ① 包概览

- 版本/风格：Sildur's Vibrant Shaders v2.02（Extreme 档）。标题、官网、Modrinth/CurseForge 链接见 `shaders.settings:3-6`。定位是"轻量增强原版观感"（Vibrant），不是物理向重拟真：光照是手调多项式而非物理积分，水体/云/雾全部围绕一张 noisetex 与解析函数构建。
- 作者/版权：Sildur，`Copyright (c) Sildur. All rights reserved.`，且明确 `Redistribution, modification, or mirroring without explicit written permission is strictly prohibited`（`shaders.settings:8-11`；每个着色器文件头部有同样声明，如 `deferred.fsh:10-13`）。
- 限制推论：不可分发、不可修改、不可镜像。对 Astra 只有"思路级参考"价值，任何代码级搬运都需要 Sildur 书面许可（见⑤）。
- 组织形态：三个世界目录（主世界 `shaders/`、下界 `world-1/`、末地 `world1/`）各自平铺完整程序；共享"设置"靠每个程序 `#include "shaders.settings"`（如 `gbuffers_water.vsh:17-22`），按 `#define gbuffers_water` 等宏裁剪同一份设置文件（`shaders.settings:16-197`）。这是 OptiFine 1.7~1.12 时代的典型组织，Iris 完全兼容，但同一函数在 5+ 文件重复（funReflections 就有三份拷贝），维护成本高。
- 兼容面：#version 120，覆盖 1.7.10 至最新（大量 `MC_VERSION` 分支，如 `gbuffers_water.fsh:73`、`gbuffers_water.fsh:373`），带 DISTANT_HORIZONS / VOXY 分支（`deferred.fsh:90-93`、`shaders.properties:13`）与 `voxy.glsl`；旧 OptiFine 的"1.16.4 前不能在 gbuffers 读纹理"限制有独立回落管线（`gbuffers_water.fsh:500-503`）。
- 规模印象：主世界全部着色器约 6000 行；单文件最大 composite1.fsh 854 行，其中约 420 行是默认关闭的镜头光斑硬编码（`composite1.fsh:180-603`）——"代码量大头在装饰性效果"是轻量包的典型形态。
- 打磨面：`lang/en_US.lang` 325 行，几乎每个开关都有 comment 与 value 别名（如 Clouds 五档的中文可读名 `lang/en_US.lang:77-81`）——老包生命力的另一半来自"设置体验"，这与④中设置面板条目互为印证。

## ② 架构与特性清单

管线（主世界）：shadow → gbuffers_* → deferred（天空+SSDO+阴影+直接光照合成）→ deferred1（金属/雨反射，`shaders.properties:13` 条件启用）→ composite（godrays/VL 掩码 + bloom 第一遍，一次 pass 写两个缓冲 `composite.fsh:2`）→ composite1（雾/bloom 合成/godrays/VL/镜头光斑）→ composite2（TAA，`shaders.properties:12`）→ final（DoF/运动模糊/色调映射/雨滴屏效）。

### 水体
- 顶点两级正弦波位移：`gbuffers_water.vsh:234-236`（0.05*sin×2 叠加，按 `fy` 断裂面 clamp 保证不脱离水面块）。
- 片元波法线：3 个旋转+滚动的 noisetex 八度（大浪/小浪/细噪声）→ `funWaterWaves` `gbuffers_water.fsh:247-268`；5 次采样有限差分求梯度 `funWaterBump` `gbuffers_water.fsh:270-283`。
- 单步视差（WaterParallax）：一次高度偏移 UV，非 raymarch，`gbuffers_water.fsh:285-290`。
- SSR：16 步 clip-space 直线步进 + 深度厚度区间测试，未命中直接回落全景天空色（`reflC = vec4(skyC,1.0)` 初始化，`gbuffers_water.fsh:206-240`，回落初值 222）。
- 菲涅尔：F0=0.5（水）/0.5*(1-alpha)（玻璃冰），`pow(1+NdotV,4)`，`gbuffers_water.fsh:461-465`，最终混合 478。
- 弃用原版水贴图、用顶点色作水色，alpha 0.85：`gbuffers_water.fsh:371-384`；水体额外 `albedo.b *= 0.66` 制造吸收偏色 `gbuffers_water.fsh:477`。
- 解析焦散打在水下地面：把地面深度反投影回世界坐标（412-417），3 层 sin/cos 网络生成焦散纹理 `funCaustics` 298-328，浅水/深水双淡出 depthMask（420-423），乘以地面阴影并按透明度衰减（426-428）；同结构复用为折射偏移 `funWaterRefraction` 331-359，保证焦散与折射波纹同相。
- 水下雾在 gbuffers 内先做一次（`gbuffers_water.fsh:92-133`），composite1 对水下视角再补一次水平线雾（`composite1.fsh:820-822`）。
- 水面阴影专用短路：水面上不做常规阴影采样，固定 `vec3(0.1)`，把采样预算让给焦散（`gbuffers_water.fsh:402-404`）。
- 波场代码按程序复制到 dh_water / block_translucent / hand_water 等入口（`dh_water.fsh` 346 行，与主水面同构），保证 Distant Horizons 水面观感一致。

### 大气/雾
- 天空=解析渐变+太阳散射：`funSkyColor` `deferred.fsh:232-276`（天顶亮度 L 244、A 245，地平渐变 grad1 248，向阳 grad3 251-254，`exp(-3.5Y)` 太阳环绕项 256-258，太阳/月亮两项合成 268-275）；调色板只在顶点算一次（sky1/sky2，`deferred.vsh:140-145`）。
- 太阳盘 `exp(-angle^3)`：`deferred.fsh:165-175`；月亮按月相表画"减影盘"：`deferred.fsh:182-229`（相位偏移表 204-212，满月/新月单独分支 193-200）；程序化星星（hash 网格 + 平方平滑）：`deferred.fsh:438-450`。
- 2D 云=弯曲云平面：视线按 `heightA-4.0*i*iMult` 取 22 层采样点（`deferred.fsh:300-304`），双 noisetex 乘积 4 八度（308-322）+ 云底 SSS 散射 327-330。
- 3D 体积云：步进 cloudIT 次、4 个预计算八度（scale/weight 常量 vec4，`deferred.fsh:378-385`）、密度式 416、raw/smooth 双色混合柔化上边缘 420-432；按相机与云层相对位置三段式初始化步进区间（347-370）；反射降级为 2 八度 + 3 步（394、479）。
- 全景天空缓存：deferred 把整球天空（含云、日、月、星）烘进 colortex6（`deferred.fsh:454-491`，写入 793），供水面反射（`gbuffers_water.fsh:467-468`）、金属/雨反射（`deferred1.fsh:321-322`）、godrays/VL 灯色采样（`composite1.fsh:139-150`）复用。
- 雾：颜色直接取"同屏天空色/原版 fogColor 兜底"，距离曲线一条 `dist/newFar*12.5-11.5+fogScaling`：`deferred.fsh:113-159`（天空混合 120，曲线 140-141，原生 fogStart/End 兜底 154）；水下/岩浆/雪以 fogColor 乘系数（149-151）；强度滑条映射成 ±11.5 的曲线平移让用户"直观调雾"（`shaders.settings:90,92`）。
- 原版元素接管：1.17+ 用 `skyColor/fogColor` 重画 skybasic（`gbuffers_skybasic.fsh:45-48`），原版云按 Clouds==1 加雾重染色（`gbuffers_clouds.fsh:50-68`），或直接 `clouds=fancy/off` 开关（`shaders.properties:1-6`）。
- 星空/默认天空盒独立开关：`customStars`（`shaders.settings:61`）与 `defskybox`（87，兼容资源包自定义天空，开启时自动停用自绘日月，`deferred.fsh:483-488`）。
- 雨滴屏效（顶点生成 4 个雨点位置）：`final.fsh:195-217` + `final.vsh:102-108`；水下/雨屏幕折射抖动：`final.fsh:259-263`。

### 阴影与光照
- 对数阴影扭曲：`shaders.settings:42-46`（`utilDistortion`），shadow pass 应用 `shadow.vsh:25-28` 并 `z/6` 压缩深度；Extreme 档默认 3072 分辨率/12 采样/距离 110（`shaders.settings:37-38,24`）。
- PCSS：顶点算遮挡搜索数据（`gbuffers_textured.vsh:95-121`），片元 8 采样 blocker search 得接触硬化半径（`gbuffers_textured.fsh:101-114`），deferred 用它扩大阴影滤波半径（`deferred.fsh:556-560`）。
- 彩色阴影：shadowtex0/1 双采样 + shadowcolor0 调制 `shadowcolor0*(s.y-s.x)+s.x`：`deferred.fsh:573-576, 582-584`。
- SSDO（16 采样，注明改自 Yuriy O'Donnell MIT 实现）：`deferred.fsh:624-652`；AO 直接乘进环境光项（732）。
- 环境/直射光是手工"bounced"多项式（NdotL/NdotU 四通道），白天/夜晚/雨天线性混合：`deferred.fsh:721-733`；日光色用 7 项 ToD 查表插值：`deferred.vsh:57-63, 87-94`。
- 眼睛自适应曝光（log 亮度 → pow eyeLight）：`deferred.vsh:102-128`。
- 手持光（距离衰减改 lightmap）：`deferred.fsh:698-700`、`gbuffers_water.vsh:195-198`；手阴影（hand 深度层比较后放大 fragpos）：`deferred.fsh:540`。
- 雨湿地面：2 八度 value-noise 水洼掩码（`deferred1.fsh:284-298`）+ Voronoi 程序涟漪法线（128-149）+ 湿度强度 `pow(wetness,0.5)*0.65-0.05` 与边缘软化 edgeSoftness（300-305）；金属/抛光块反射走同一条 16 步 SSR（330-348）；材质 ID 用 mats 浮点区间判定（`deferred.fsh:674-678`，块定义 `block.properties:44,46,57`）。
- 植被摆动：双 `funWave` 叠加的顶点位移（`gbuffers_textured.vsh:68-85`），按 mc_Entity/顶点上下半部判定位移（155-167）。
- 凹凸/POM：nMap 档位 0/1/2（`shaders.settings:139`），POM 用固定 `POM_RES` 步进循环 + GradARB 采样（`gbuffers_textured.fsh:72-88`）。

### 后处理
- Bloom 两遍：composite 半分辨率水平 7-tap（`composite.fsh:122-139`，`texcoord*4.0` 缩放 UV 读满分辨率 126），composite1 纵向 5-tap + glow/overglow 塑形（`composite1.fsh:655-674`）。
- Godrays：composite 径向 12 采样写掩码（`composite.fsh:100-118`），composite1 再 7 采样 + 三段角衰减 pow30/16/2（`composite1.fsh:622-649`）。
- VL：6 次 shadowmap 步进 + 深度感知 9-tap 双边滤波（`composite.fsh:63-93`），composite1 按距离指数合成（607-615）。
- TAA：YCoCg 空间的 3x3 均值/方差钳制（`composite2.fsh:50-51, 111-116`）、Catmull-Rom（c=0.82）历史重采样（119-141）、亮度加权混合与防闪烁项（145-155）、Y 通道带边缘限制的锐化（101-109）、最近深度重投影（67-84）。
- 色调映射：Uncharted2 + 白点归一，之后 `pow(1/Contrast)` 做对比度：`final.fsh:232-241, 274-276`。
- DoF（60 点六边形盘）、运动模糊（15 步速度累积）：`final.fsh:168-185, 65-89`；Celshading 深度边缘描边（默认关）：`composite1.fsh:681-699`。
- 镜头光斑：十几个手工椭圆 flare 叠加（`composite1.fsh:180-603`，默认关）。
- 调试视图：Showbuffer 0-7 直接显示各中间缓冲（lightmap/法线/掩码/bloom/全景天空/TAA，`shaders.settings:131` + `final.fsh:278-298`）——轻量包少有的开发体验设计。

### 性能技术
- 条件跳过整条 pass：`program.*.enabled` 由开关布尔式组合（`shaders.properties:9-13`）；旧版本直接关掉 4 个 translucency 程序（15-20）；DH 阴影默认关（28）。
- 一次烘焙多方复用：全景天空烘一次，水面/金属/雨反射与 godrays/VL 灯色全部读它（同上）。
- 半分辨率掩码 + LOD 采样：colortex3 掩码用 `texture2DLod(...,1)` 半分辨率读取（`composite1.fsh:633-641`、`composite.fsh:609`）；bloom 用缩放 UV 在小缓冲上做（`composite.fsh:126`）。
- PCSS 的 blocker search 放顶点着色器：`gbuffers_textured.vsh:95-121`；水面光照/环境光全在 vsh 算好 varying（`gbuffers_water.vsh:160-227`）。
- TAA 8 相抖动数组复用于几何、SSR 起点、VL/焦散噪声（`deferred.fsh:497-505`、`gbuffers_water.fsh:216-219`）。
- 反射降级链：反射内云 2 八度 3 步（`deferred.fsh:394, 479`）；TAA 开启时水阴影采样 6→2（`gbuffers_water.fsh:160-164`）。
- 杂项：`oldLighting=false`（`shaders.properties:39`）、`shadowTranslucent=true`（43）、frustum culling（47）、`underwaterOverlay=false`（54）。
- 阴影 pass 的内容微调：水面进阴影时去贴图用纯色（`shadow.fsh:34`）、按 mc_Entity 剔除草花/闪电/光柱阴影（`shadow.fsh:36-39`）——小成本提升阴影观感的典型做法。
- 水体入口全家桶：水面程序同时覆盖 gbuffers_water / hand_water / block_translucent / entities_translucent / particles_translucent（`shaders.properties:15-20` 按版本裁剪），保证"手持水、玻璃、粒子"与主水面共享同一套观感而非各画各的。

## ③ Astra 可借鉴点

a) 水面观感的"低成本近似"补位（对应专项问题 a）
1. **SSR 未命中的"全景天空直读"回落**。Sildur 把反射 ray 初值直接设为全景天空色（`gbuffers_water.fsh:222`），命中才换场景色。Astra 的 `global/water/raytrace.glsl`（原创 texture-gather 实现，出处注释 4-6）返回 UV+confidence 后由调用者配天色，等价物已存在；可借鉴的是"先保证天空反射像、再谈场景反射"的观感优先级与用 TAA 抖动摊薄步进噪声（`gbuffers_water.fsh:216-219`）。迁移难点：低（Astra 已有 `lib/sky_reflection_cache.glsl:5-8` 的 258×128 环境缓存可当同一角色）。
2. **解析焦散+折射同函数复用**。一个 3 层 sin/cos 网络同时输出焦散亮度（`gbuffers_water.fsh:298-328`）和折射偏移（331-359），两者波纹严格同相；并按"水下深度"做浅/深双淡出、乘地面阴影（406-429）。Astra 的 `global/water/caustics.glsl:4-9` 是 Solas 噪声纹理系，开销更高且与折射解耦。可在 PERF 档用解析版替换，或作为远距淡出项。迁移难点：中（需把相位常数与 Astra 波场对齐；函数本体约 30 行，须原创重写）。
3. **"弃水贴图+顶点色+蓝通道压暗"的水色三件套**：`gbuffers_water.fsh:371-384, 477`。三行代码得到干净可控的水色基线。Astra 走 Beer-Lambert 吸收（`global/water/absorption.glsl:9-13`，逆方块距离消光），物理上更强；可借鉴的是 interface-path 快速染色的档位即时性（与 WATER_CHARACTER 联动）。迁移难点：低。
4. **单步视差 + noisetex 三八度波法线**（`gbuffers_water.fsh:247-290`）：比 Astra `global/water/surface.glsl`（Steadfast GPLv3 value-noise 导数 + 四步视差，出处注释 4-16）便宜一个量级，观感偏"干净卡通"。适合作为 `profile.PERFORMANCE`（`shaders.properties:424`）下的水面降级，而非直接替换高档位。迁移难点：低-中。

b) 雾与大气渐变的廉价实现（对应专项问题 b）
5. **"雾色=同屏天空色"的自一致雾**。Sildur 不维护独立雾色模型：deferred 先算 `skyC` 再喂给 fog（`deferred.fsh:782-785`），gbuffers/composite 各层重复同一公式保证水平线无缝；仅留 `fogColor` 做洞穴兜底混合（120）。Astra 的 `global/atmosphere/fog.glsl`（Steadfast FogV2，出处注释 4-9）是独立散射近似；借鉴点是"雾色直接绑 `global/atmosphere/sky_gradient.glsl`（Complementary 三方向模型，出处 5-11）的输出"，让雾与天永不漂移。迁移难点：中（要理清 Astra 雾分层，收益是一致性而非性能）。
6. **单条直觉化雾距曲线 + 滑条→曲线平移映射**：`fogDistance = dist/newFar*12.5-11.5+(density-1)*11.5`（`deferred.fsh:140-141`，滑条定义 `shaders.settings:90,92`）。把"密度滑条"翻译成曲线平移而非指数重参数化，用户感知近似线性。Astra 的 FOG_DENSITY 可参考此语义。迁移难点：低（一个映射函数）。
7. **月相减影月盘 + exp(-angle³) 太阳**：`deferred.fsh:165-229`（相位偏移表 204-212）。Astra `SUN_MOON_MODE` 已有 DISCS（`lib/settings.glsl:25-26`），但逐月相绘制是 Astra 没有的细节观感。迁移难点：低（纯几何，约 45 行）。

c) 轻量包的开关组织与默认值取舍（对应专项问题 c）
8. **布尔组合式 pass 熔断**：`program.composite.enabled=Bloom || Godrays || Volumetric_Lighting`（`shaders.properties:9-13`）——一条 pass 的全部功能都关就整条跳过。Astra 的 program/ 管线是固定组合，可借这种"pass 级熔断"让关掉 bloom+godrays 的用户少跑整条 composite。迁移难点：中（需拆 Astra program 组合并在 shaders.properties 声明条件）。
9. **设置面板按用户目标分屏，主屏只留 16 项**：主屏 `shaders.properties:62` 只放 SSDO/阴影/水反射/TAA/bloom/雾等高频项，其余 14 个子屏（64-78）+ slider 白名单（81）+ lang 重命名（`lang/en_US.lang:77-81`）。Astra 已有等价组织（`lib/settings.glsl:19-41` 枚举开关 + `shaders.properties:403-409` 分屏 + profile 424-427），体系化程度更高；可借鉴的反而是**默认值保守度**——Sildur Extreme 档默认 3072 阴影/12 采样，但 Celshading/光斑/DoF/运动模糊全关（`shaders.settings:72,78,119,125`）："贵而低感知"的效果默认不开。迁移难点：低（改默认值）。

d) 十年老包的生命力——仍划算的"老技术"（对应专项问题 d）
10. **ToD 7 项查表日光色**（`deferred.vsh:57-63, 87-94`）：一次插值得到全天日光色，比多条物理散射曲线便宜且美术可控。Astra 的 Solas 适配层已是同思路的时间参数化（`lib/solas_water.glsl:19-43`），此条佐证"查表+插值"路线不过时。
11. **顶点着色器承担每顶点可预算的工作**：PCSS 预计算（`gbuffers_textured.vsh:95-121`）、水环境光 varying（`gbuffers_water.vsh:160-227`）。Astra 的逐像素光照靠 SH9（`lib/sky_sh9.glsl:6-13`，纯数学模块）已经更优；可借鉴的是"哪些量每顶点足够"的位置选择，例如水面波法线在低档位降到顶点级。迁移难点：中（需核对 varying 带宽与 Iris 程序布局）。
12. **旋转矩阵 + 单张 noisetex 的程序纹理纪律**：水波/焦散/2D 云/3D 云/星星全部由 noisetex + rmatrix 旋转缩放生成（`gbuffers_water.fsh:243-268`、`deferred.fsh:388-411`、`438-450`），零额外纹理、零 buffer。对 Astra 的价值在 Nether/End 这类"不值得上 compute 体素"的维度补廉价氛围细节。迁移难点：低。

## ④ Astra 已有对应实现（对照）

- **SSR**：Sildur 16 步线性 march + 厚度区间（`gbuffers_water.fsh:206-240`）vs Astra `global/water/raytrace.glsl`（texture-gather、置信度返回，注释声明无源码并入 4-6）。Astra 更强（精度/可组合性）；Sildur 胜在无 gather 依赖、老 GPU 兼容、实现 40 行。结论：Astra 优。
- **波法线/视差**：Sildur noisetex 三八度 + 单步视差（`gbuffers_water.fsh:247-290`）vs Astra `global/water/surface.glsl`（Steadfast value-noise 导数 + 四步视差，出处 4-16）。Astra 物理感更好但更贵；Sildur 适合降档。各有所长。
- **焦散**：Sildur 解析网络打在水下地面并按深度/阴影调制（`gbuffers_water.fsh:298-328, 406-429`）vs Astra `global/water/caustics.glsl:4-9`（Solas 噪声高度场）。Astra 是否也向水下方块表面投射焦散未逐行确认（`program/water.glsl` 消费端未全读，不确定）；Sildur 的"深度淡出 + 阴影调制 + 与折射同相"是确认可取的三细节。
- **折射**：Sildur 波场偏移 UV（`gbuffers_water.fsh:331-359`）vs Astra `global/water/refraction.glsl`（Steadfast 深度 gather + 屏幕外回退，出处 3-5）。Astra 优（几何正确），Sildur 便宜且自带动画。
- **水下光**：Sildur 无专门水下光束，靠 fog 色乘系数与"水下再补一次雾"（`deferred.fsh:149-151`、`composite1.fsh:820-822`）；Astra `global/water/light_shafts.glsl` + `shaft_history.glsl` 有时域历史光束。Astra 优。
- **天空**：Sildur 解析 L/A 渐变 + 手工调色（`deferred.fsh:232-276`）vs Astra `global/atmosphere/sky_gradient.glsl`（Complementary 三方向模型，出处与映射逐条注释 5-50）。Astra 表达力强；Sildur 便宜一个数量级且"够看"。各有所长，Astra 无需回退。
- **天空环境缓存**：Sildur 全景 colortex6（deferred 每帧烘一次，`deferred.fsh:454-491`）vs Astra `lib/sky_reflection_cache.glsl`（258×128 专用缓存，含接缝复制 5-8）。Astra 优。
- **云**：Sildur 2D 弯曲平面 / 3D 体积云双方案 + 5 档选项（`deferred.fsh:287-333, 337-433`；`lang/en_US.lang:77-81`）vs Astra `global/atmosphere/clouds_planar.glsl`（Complementary 云模型，出处 4-14）+ `cloud_temporal.glsl` 半分辨率独立历史。Astra 质量高；Sildur 的"反射降级 2 八度 3 步"（394、479）与 Off/原版/2D/VL/2D+VL 五档粒度值得抄。各有所长。
- **雾**：Sildur 自一致天空雾（`deferred.fsh:113-159`）vs Astra `global/atmosphere/fog.glsl`（Steadfast FogV2，含空气透视/边界雾/洞穴雾）。Astra 优；可借鉴仅"雾色绑天空输出"的一致性思路（见③5）。
- **雨湿**：Sildur 水洼+涟漪+金属反射一条流水线（`deferred1.fsh:275-348`）vs Astra `global/atmosphere/weather.glsl`（`astra_rain_exposure`:4-11 已修过曝曲线，`astra_puddle`:21 起的掩码与涟漪环）。Astra 掩码/时序更讲究（明确修过 wetness 记忆残留）；Sildur 的 Voronoi 涟漪法线（128-149）与水洼边缘软化 edgeSoftness（304-305）是可对表的两处细节。各有所长。
- **阴影**：Sildur PCSS+彩色阴影+对数扭曲（`deferred.fsh:535-592`、`shaders.settings:42-46`）vs Astra `global/lighting/shadowmap.glsl` + `SHADOW_FILTER_*`/`COLORED_SHADOWS` 档位（`lib/settings.glsl:68-85`）。Astra 档位更细；Sildur 的"blocker search 在顶点算"（`gbuffers_textured.vsh:95-121`）是独立可借鉴项（Astra shadow.vsh 是否有同类预计算未读，不确定）。Astra 优。
- **AO**：Sildur SSDO 16 采样单帧（`deferred.fsh:624-652`）vs Astra `lib/ao_material.glsl` + `ao_resolve.glsl`（含时序，未深读，优劣不确定，仅从结构推断 Astra 更完整）。
- **TAA**：Sildur YCoCg+方差钳制+Catmull-Rom（`composite2.fsh:60-157`）vs Astra `lib/effect_history.glsl` / `taa_jitter.glsl`（未深读，优劣不确定）。Sildur 值得抄的细节：按材质跳过锐化（`composite2.fsh:61-62` mats 判定）、天空分支免锐化（165）。
- **色调映射**：Sildur 单一 Uncharted2 + Contrast 指数（`final.fsh:232-241, 274-276`）vs Astra 四算子可选（`lib/settings.glsl:19-22`；`lib/tonemap.glsl:4-13`，Mellow MIT 血统）。Astra 优。
- **后处理阵列**：Sildur 的 DoF/运动模糊/Celshading/镜头光斑/雨滴屏效 Astra 均无对应（`final.fsh:65-217`、`composite1.fsh:681-699, 180-603`）——属于风格化选项，是否补齐是产品决策而非技术缺口。
- **植被摆动/POM**：Sildur 双 funWave 摆动 + nMap 三档 POM（`gbuffers_textured.vsh:68-85`、`gbuffers_textured.fsh:72-88`）vs Astra `global/lighting/wind.glsl`（未深读，对照不确定）。
- **维度差异**：Sildur 下界只是把雾色压暗的简化复制（`world-1/deferred.fsh:113-122`），末地同理；Astra 有独立 Nether 体素彩光/群系雾与 End Kerr 天空（`global/dimension/nether_colored_light.glsl`、`end_kerr.glsl`）。Astra 全面占优，此维度无可借鉴。
- **手持光**：Sildur 把手持亮度直接折算进 lightmap 并按距离衰减（`deferred.fsh:698-700`、`gbuffers_water.vsh:195-198`，双手取 max）vs Astra `HANDHELD_LIGHTING`（`lib/settings.glsl:58-60`，实现未深读，优劣不确定）。
- **顶点波位移**：Sildur 顶点两级正弦位移（`gbuffers_water.vsh:234-236`，几何真的动）vs Astra 的波场主要作用于法线/视差（`global/water/surface.glsl`，几何位移未确认）。Sildur 的"几何起伏+法线细节"双层结构是水面动感的来源之一，值得对照确认 Astra 是否缺几何层。

### 对照方法说明
- Sildur 侧行号来自对主世界 `shaders/` 目录的逐文件阅读；world-1/world1 与主世界同名文件结构相同、仅常量不同，未逐一深读。
- Astra 侧仅对照任务定位中列出的模块，`global/lighting/wind.glsl`、`lib/effect_history.glsl`、`lib/ao_*.glsl`、`program/water.glsl` 消费端等未逐行读完的位置在④中已标注"不确定/未深读"，未编造结论。

## ⑤ 借鉴可行性（许可证层面）

- Sildur's Vibrant Shaders 为**保留所有权利**：`shaders.settings:8-11` 明文禁止"Redistribution, modification, or mirroring without explicit written permission"。它与 Astra 现有第三方基础（GPLv3 Steadfast、经授权的 Solas、MIT Mellow，见各文件头注释）**许可证不兼容**。
- `Astra/THIRD-PARTY.md` 目前没有 Sildur 的许可/出处条目（仅在 :96 的头注释统计句中被提及一次），即现状下不存在任何已登记的 Sildur 派生代码，Astra 的合规状态是干净的。
- 结论：**禁止任何代码级搬运/改写/直译**，包括"换变量名照抄结构"；只允许黑盒级别的思路参考（算法思想本身不受版权保护，但具体表达受保护）。若确需引入③中某条的具体实现，必须先取得 Sildur 书面许可并登记 `THIRD-PARTY.md`。③中所有条目默认以 Astra 原创重写为前提。
- 实操建议：③中每条借鉴点落地时，Astra 侧应在对应新模块头部写明"设计思路参考 Sildur's Vibrant（黑盒观察），实现为原创"之类的出处注释，与 `global/water/raytrace.glsl:4-6` 的既有做法保持一致。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **PERF 档水面降级管线**（③1/③4/③2 组合）：给 `profile.PERFORMANCE`（`shaders.properties:424`）补一套"廉价但完整"的水面——单步视差波法线 + 天空直读反射 + 解析焦散，替代现在"全开或全关"。提升大（低配机保住水面观感）、工作量中、无许可证风险（原创重写）。
2. **解析焦散的深度淡出与阴影调制**（③2 的消费端部分）：即使高档位，也把焦散对水深的浅/深淡出与地面阴影调制（`gbuffers_water.fsh:420-428` 思路）补进 `global/water/caustics.glsl` 消费端，修正浅水过曝/深水穿透假象。提升中-大、工作量小-中。
3. **pass 级熔断开关**（③8）：按 Bloom/Godrays/VL 布尔组合跳过整条 composite pass，低配收益直接。提升中、工作量中。
4. **雾色与 sky_gradient 输出的一致性绑法**（③5）：让 `global/atmosphere/fog.glsl` 的远距雾色直接取天空缓存采样，消除雾/天色漂移。提升中（观感一致性）、工作量中。
5. **"贵而低感知默认关"的默认值审计**（③9/③6）：对照 Sildur 的默认取舍（Celshading/DoF/光斑/运动模糊全关，`shaders.settings:72-126`）复查 Astra 各 profile 默认值；顺带把 FOG_DENSITY 滑条改成"曲线平移"语义。提升小-中、工作量小。

排序依据：1/2 直接作用于 Astra 的核心卖点（水面），且都是"补空档"而非"重做已有件"；3/4 是结构性收益（性能与一致性）；5 是纯配置层面、几乎零风险的收尾项。Sildur 与 Astra 许可证不兼容这一前提已计入每条的工作量评估（均需原创重写）。

## 结论一句话

Sildur's Vibrant 的价值不在任何单项技术（Astra 的对应件几乎都更强），而在它的**性价比配方**：同一张 noisetex + 解析函数 + 顶点预处理 + pass 熔断 + 保守默认值，用约六千行做出千万级下载的观感——这正是 Astra 的 PERFORMANCE 档最缺的一课。

（其余未进 Top5 但已记录：月相月盘③7、顶点预处理位置③11、Nether 廉价氛围细节③12、反射云降级与云选项五档④云条目、雨涟漪/edgeSoftness④雨湿条目、TAA 按材质跳过锐化④TAA 条目。）

## 附：引用自抽查记录

- 完成后重开文件核对引用共 40+ 处，覆盖水体（gbuffers_water 7 处）、大气/雾（deferred 9 处）、阴影（3 文件 6 处）、后处理（composite/composite1/composite2/final 12 处）、配置（properties/settings/lang/block.properties 8 处）、Astra 侧（17 处）。
- 抽查方式：`sed -n '<行号>p'` 重新打印目标行与报告声称的内容比对；发现并当场修正 2 处（dh_water 行数 345→346、composite1.fash→composite1.fsh 笔误），修正后复核全部一致，无错行。
- 摘录合规：报告正文仅含行内代码短语（如 `exp(-angle^3)`、`fogDistance = dist/newFar*12.5-11.5+fogScaling`），无超过 5 行的代码摘录块。
- 阅读覆盖度：主世界 14 个核心文件全文深读（water/sky/shadow/post 链路全部程序），其余 gbuffers 入口扫读；world-1/world1 仅抽查与主世界的差异点。
