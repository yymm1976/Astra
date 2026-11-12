# Hysteria Shaders v1.2.1 (Universal) 研究报告 —— Astra 可借鉴点

> 研究对象：`reference_shaderpacks/hysteria-shaders/`（398 个文件）。
> 对照目标：Astra（`Astra/shaders/`），Iris 专用前向光照光影。
> 本报告所有 `文件:行` 均相对上述两个包根目录，行号经过复核。

---

## ① 包概览

- **名称/版本**：Hysteria Shaders，版本 1.2.1（`CHANGELOG.md:1`）；"Universal" 版（同一套源码同时面向 OptiFine 与 Iris，见 §②-6）。
- **作者**：lang 面板署名 "Made with <3 by ElocinDev. Based on Photon by Sixthsurge"（`shaders/lang/en_US.lang:4`）；许可证版权行写作 "Copyright (C) 2024 nvb-uy"（`LICENSE.md:5`），两者应为同一作者的署名与法律名。
- **许可证**：AGNYA License Rev 1.3（`LICENSE.md:3`）。与借鉴直接相关的条款：
  - 第 2 条：允许**私有修改**，无需许可（`LICENSE.md:77-79`）。
  - 第 3 条：**公开分发修改版需原作者明确许可**，且须含足够自有原创内容、保持本许可证、明确署名、禁止变现（`LICENSE.md:86-95`）。
  - 第 4 条：**把本项目部分源码用作另一个原创项目的一部分，需原作者明确许可** + 署名 + 未经许可禁止变现（`LICENSE.md:101-105`）。
  - 附注：Hysteria 大量代码来自 Photon（MIT），MIT 部分单独按 MIT 条款可用，需保留版权声明（`LICENSE.md:136-147`）。
- **风格定位**：写实暗调向。典型手段是压低的月光强度（`MOON_I 0.20`，`shaders/settings.glsl:77`）、暖色低饱和方块光（`BLOCKLIGHT_R/G/B 1.00/0.75/0.60`，`shaders/settings.glsl:79-81`）、显著的洞穴填充光与雾（`CAVE_LIGHTING_I`，`shaders/settings.glsl:86`；`CAVE_FOG`，`shaders/settings.glsl:255`）。云端体渲染（cumulus/congestus/altocumulus/cirrus 四层，`shaders/settings.glsl:153-201`）与 LPV 彩光（可选）也是其卖点。
- **血统**：基于 Photon（Sixthsurge, MIT）改写实暗调，另受 BSL 系 Insanity/Madness 启发（`CREDITS.md:1-3`）。

---

## ② 架构与特性清单

### 1. 黑暗环境与光照衰减
- 方块光衰减是一条**多项式合成曲线**：`pow8 + 0.18*sqr + 0.16*dampen` 三段叠加，亮核紧、余晖长（`shaders/include/light/diffuse_lighting.glsl:31`）。
- AO 与光源距离联动：离光源越远 AO 压得越狠，近处不压（`shaders/include/light/diffuse_lighting.glsl:32`）。
- 方块光在日光下自动压暗 `1.0 - 0.2*noon*skylight - 0.2*skylight`（`shaders/include/light/diffuse_lighting.glsl:34`），并叠一项 `min(2.7*pow12, 0.9)` 保证日光下光源周围仍有强高光（`:35`）。
- 洞穴填充光：`0.15 * CAVE_LIGHTING_I * directional * ao * (1-skylight²)`，随天光平方衰减到 0（`shaders/include/light/diffuse_lighting.glsl:189`）。
- 天光衰减取平方 `sqr(skylight)`（`shaders/include/light/diffuse_lighting.glsl:41-47`），使半遮挡区域更暗，强化"暗调"。
- 可选 SH9 天光 `sh_evaluate_irradiance`（默认关）（`shaders/settings.glsl:53`、`shaders/include/light/diffuse_lighting.glsl:153-157`）。

### 2. 手持光 / 点光
- 专用文件 `shaders/include/light/handheld_lighting.glsl`（全文 53 行）。
- 衰减：`lift(rcp(dot(scene_pos,scene_pos)+1.0), 1.2)`——带 +1 偏置的平方反比，无硬半径截断（`:31-34`）。
- 近场 AO 豁免：`falloff * mix(ao, 1.0, falloff*falloff)`，光源贴脸时不受 AO 变暗（`:33`）。
- Iris 下把光心移到玩家而非相机：`scene_pos += relativeEyePosition`（`:37-40`）。
- 双手取 `max(左手, 右手)` 而非相加（`:42-45`）；颜色默认取方块光色 × 手持光值（`:27`），开 COLORED_LIGHTS 时直接查 LPV 光色表（`:19-22`）。
- 发光物品 ID 用 `item.properties` 映射（火把=10040 等，`shaders/item.properties:40-73`）。

### 3. 潮湿表面
- 专用文件 `shaders/include/misc/rain_puddles.glsl`（77 行）。
- 积水遮罩：低频噪声 + `wetness * biome_may_rain * max0(flat_normal.y)`（`:19-20`），室内排除 `(1-cube(blocklight))*pow5(skylight)`（`:23`）。
- **两层变暗**：先按孔隙率压暗多孔材质（系数 0.4），剩余非孔隙部分再按水面暗化（系数 0.25）（`:50-52`；常量 `:38-41`）。
- 材质替换为水面材质：f0→0.02、roughness→0.002、ssr_multiplier 提升（`:55-57`）。
- 涟漪法线：两层滚动噪声差分求梯度，随 `puddle * rainStrength` 混入（`:61-71`）。
- 孔隙率来自 LabPBR 高光贴图 B 通道低位（`shaders/include/misc/material.glsl:59`）。
- 应用点在**延迟段** composite1（重解码材质后调 `get_rain_puddles`，`shaders/program/composite1.glsl:405-425`），积水处强制非金属（`:420-423`）。

### 4. 大气 / 雾
- 体雾：自适应步数（`8*VL_QUALITY` 起步、增长因子 0.1、上限 `25*VL_QUALITY`，`shaders/include/fog/air_fog_vl.glsl:17-19`），高度衰减按 Rayleigh/Mie 双通道半衰期（`:22-32`）。
- 洞穴雾：球形距离雾，密度 × `biome_cave`，颜色 0.033（近黑蓝）（`shaders/include/fog/simple_fog.glsl:18-20,72-76`）。
- 水下体雾：4 次迭代多重散射近似（`shaders/include/fog/water_fog_vl.glsl:26,96-107`）。
- 天空：物理大气（Rayleigh/Mie/臭氧系数，`shaders/include/sky/atmosphere.glsl:46-51`），Mie 用 Klein-Nishina 能量参数（`:40`）。
- 云：deferred1 渲染云与极光（`shaders/program/deferred1.glsl:9`），deferred2 做云的时域上采样（`shaders/program/deferred2.glsl:9`；倍率 `CLOUDS_TEMPORAL_UPSCALING 4`，`shaders/settings.glsl:147`）。

### 5. 水体
- 水体几何阶段做吸收/散射近似：`water_fog_simple` + 双层返回（散射色+透过率），`shaders/program/gbuffer/translucent.glsl:594-610`；纹理高光染色 `:436`。
- 波浪法线与视差可选（`WATER_WAVES`/`WATER_PARALLAX`，`shaders/settings.glsl:368` 附近区块）。
- 折射在 composite1 延迟执行：屏幕空间偏移 + 回读深度确认折射对象在水面之后（`shaders/program/composite1.glsl:357-369`）；Snell 窗口按菲涅尔压暗（`:372-378`）。
- 阴影贴图阶段烘焙**彩色水焦散**进 shadowcolor0：`0.25*exp(-absorption*depth)*caustics`（`shaders/program/shadow.glsl:236`；焦散函数 `:199`）。

### 6. 后处理 / 调色 与 Universal 变体
- 调色：亮度/对比/饱和三参（`shaders/program/post/grade.glsl:124-126`）、黑体白平衡（`:141-143`）、橙/青/绿分色相饱和度（`:165-168`）。
- Final：CAS 锐化（原生分辨率）或 Catmull-Rom 上采样（缩放渲染）（`shaders/program/post/final.glsl:149-154`）+ 16×16 Bayer 抖动（`:156`）。
- 低档位用 TAAU 渲染缩放（`TAAU_RENDER_SCALE`，`shaders/settings.glsl:412`；lowest/low 档 0.50/0.66，`shaders/shaders.properties:1-2`）。
- **Universal 机制**：一套源码适配多环境——
  - 版本/厂商宏兜底：`MC_VERSION < 11700` 时 `gtexture→tex`、Intel 下 `attribute→in`（`shaders/include/global.glsl:3-9`）；
  - 材质格式二选一：`TEXTURE_FORMAT_LAB`/`OLD`（`shaders/settings.glsl:324-325`，解码分支 `shaders/include/misc/material.glsl:26-85`）；
  - DH 远景：18 个文件含 DH 分支（如 `shaders/program/composite1.glsl:348-403`）；
  - Iris 专属特性（CUSTOM_IMAGES 等）走 `iris.features.optional`（`shaders/shaders.properties:132`），OptiFine 开彩光时在 final 画提示图而非崩溃（`shaders/program/post/final.glsl:125-139,142-144`）；
  - 五档 profile（lowest→ultra）只开关特性/改步数，不改代码（`shaders/shaders.properties:1-5`）。
- LPV 彩光：128³ 体素体积 + compute 泛洪（`shaders/settings.glsl:124`；`shaders/program/lpv/setup.csh`、`floodfill.csh`），与原版方块光按 `COLORED_LIGHTS_VANILLA_LIGHTMAP_CONTRIBUTION` 混合（`shaders/include/light/diffuse_lighting.glsl:174-178`）。

---

## ③ Astra 可借鉴点

| # | 技术描述 | 包内出处 | 对应 Astra 模块 | 迁移难点 |
|---|---------|---------|----------------|---------|
| 1 | **方块光三段衰减曲线**：`pow8(b) + 0.18*b² + 0.16*dampen(b)`，亮核紧凑、余辉渐弱，尾端 `smoothstep(0,0.125)` 消除光圈边界 | `shaders/include/light/diffuse_lighting.glsl:30-39` | `Astra/shaders/global/lighting/blocklight.glsl:89-90`（现为单一 `pow4`） | 低。替换单个幂函数为三项和，调常数即可；需回归测试与现有夜色去饱和联用 |
| 2 | **方块光-日光自动压暗**：`falloff *= 1.0 - 0.2*noon*skylight - 0.2*skylight`，白天火把不再发光但保留近源高光项 | `shaders/include/light/diffuse_lighting.glsl:34-35` | `Astra/shaders/global/lighting/blocklight.glsl:92-97`（已有 suppression，但用 `sqrt(skyLight)` 门） | 低。思路同源，可对比两者在晨昏的过渡表现后择优 |
| 3 | **AO-光源距离联动**：`falloff *= mix(cube(ao), 1.0, clamp01(falloff))`——远处 AO 全额、近光豁免 | `shaders/include/light/diffuse_lighting.glsl:32` | `Astra/shaders/global/lighting/diffuse.glsl:388` 附近（solasMinLight 与 AO 独立相乘） | 中。Astra AO 走独立 SSAO 通道（`lib/ao_material.glsl`），需要把"到局部光源的距离"信息传给 AO 采样点或改为在块光项内做 |
| 4 | **手持光平方反比 + 玩家中心 + 近场 AO 豁免**：`rcp(d²+1)^1.2`，Iris 下 `scene_pos += relativeEyePosition` 光心对玩家；双手取 max | `shaders/include/light/handheld_lighting.glsl:31-45` | `Astra/shaders/global/lighting/blocklight.glsl:62-70`（现行：相机中心、线性衰减 15 格截断） | 低-中。相对 EyePosition uniform 在 Iris 可得；重点是 15 格硬截断→连续衰减后老玩家的亮度记忆差异，需视觉校准 |
| 5 | **潮湿两层响应（孔隙率分层暗化）**：多孔材质先暗 0.4×porosity，非孔隙水面再暗 0.25；随后 f0/roughness/ssr 整体替换为水面材质 | `shaders/include/misc/rain_puddles.glsl:38-57` | `Astra/shaders/lib/wet_material.glsl:16-21`（现为按 wet class 一层暗化 + 有界高光） | 中。Astra 无 LabPBR porosity 输入，需用 blockId 湿类近似 porosity（wood≈0.6、soil≈0.8、stone≈0.2）；SSR 替换可对接 Astra 现有 `global/water/raytrace.glsl` |
| 6 | **延迟段积水合成**： puddles 放在 composite1 重解码材质后统一做，避免每个 gbuffer 程序重复实现；积水处强制非金属 | `shaders/program/composite1.glsl:405-425` | `Astra/shaders/program/lit.fsh:200-223`（在几何段做） | 高。Astra 是前向 + lit.fsh 单点亮架构，没有等价的延迟材质解码点；可作为长期重构方向而非直接搬运 |
| 7 | **室内积水排除门**：`puddle *= (1-cube(blocklight)) * pow5(skylight)`，火把旁与屋檐下不长水洼 | `shaders/include/misc/rain_puddles.glsl:23` | `Astra/shaders/global/atmosphere/weather.glsl:67`（astra_wet_ground 已有 skyLight 门，但未见 blocklight 门） | 低。Astra 已在 fragment 有 blockLight，加一项乘法即可 |
| 8 | **阴影图烘焙彩色焦散**：在 shadow pass 把水吸收×焦散写进 shadowcolor0，下游彩阴影采样即得 | `shaders/program/shadow.glsl:199,236` | `Astra/shaders/global/water/caustics.glsl`（Astra 走解析焦散） | 中。取决于 Astra 彩阴影管线（shadowmap.glsl）是否已有 per-sample 颜色调制路径；有则可作性能档位替换 |
| 9 | **洞穴雾参数**：近黑蓝色 0.033、密度 0.0033、随 `biome_cave` 调制 | `shaders/include/fog/simple_fog.glsl:18-20,72-76` | `Astra/shaders/global/atmosphere/fog.glsl` | 低。纯参数与形状对齐，注意与 Astra 洞穴最低亮度的叠加关系 |
| 10 | **体雾自适应步数**：近距离少步、按步长增长因子加密，`VL_QUALITY` 整体缩放 | `shaders/include/fog/air_fog_vl.glsl:17-19` | `Astra/shaders/global/atmosphere/volume_fog.glsl` | 中。需确认 Astra 步进结构是否支持非均匀步长；收益是低档位雾噪点更均匀 |
| 11 | **OptiFine/Iris 双后端兜底宏**：版本宏改写兼容 API（`gtexture→tex`）、Intel 宏修 attribute、Iris 独占特性优雅降级 + 用户可见提示 | `shaders/include/global.glsl:3-9`、`shaders/program/post/final.glsl:125-144`、`shaders/shaders.properties:132` | Astra 为 Iris 专用，暂无对应 | 高（仅当 Astra 决定支持 OptiFine 时）。当前可直接忽略，但 `iris.features.optional` 的"特性缺失→降级而非报错"思路值得内化 |
| 12 | **Final 的 CAS/上采样二选一**：渲染分辨率=1 时走 CAS 锐化，缩放渲染走 Catmull-Rom | `shaders/program/post/final.glsl:149-154` | `Astra/shaders/global/post/`（未见对应；Astra 无渲染缩放选项） | 中。依赖先引入 TAAU/渲染缩放（见 #6 Top 建议） |

---

## ④ Astra 已有对应实现（含专项问题 a-d 回应）

### a) 黑暗环境光衰减与洞穴最低亮度
- **Hysteria**：黑暗感来自三件套——天光平方衰减（`diffuse_lighting.glsl:43`）、多项式方块光曲线（`:31`）、平顶洞穴填充光 `0.15*CAVE_LIGHTING_I*(1-skylight²)`（`:189`）。它避免死黑靠的是：洞穴填充光系数固定非零 + 方块光曲线的长余辉项 `0.16*dampen(b)`，光圈外仍有渐弱亮度；再加洞穴雾 0.033 底色（`simple_fog.glsl:18-20`）兜住远景。
- **Astra**：洞穴最低亮度走 `MIN_AMBIENT`（8%，`Astra/shaders/lib/settings.glsl:50`）与 `MIN_AMBIENT_COLOR` 地板（`Astra/shaders/global/lighting/diffuse.glsl:107,433-434`），另有 solasMinLight 补光（`:388`）。Astra 的地板是**常数色**保证永不纯黑；Hysteria 的填充光是**随天光渐变、带方向性项 directional_lighting** 的形式。
- **优劣**：Astra 更稳（有硬地板、可调 %），且 NIGHT 段还做洞底色调分离（`diffuse.glsl:433-435`）；Hysteria 的渐变填充在"洞口→深处"的过渡上更自然，方块光曲线（三项合成）比 Astra 的单一 pow4 层次更多。Astra 的方块光-夜色去饱和联动（`blocklight.glsl:103-114` 一带）是 Hysteria 没有的能力。

### b) 手持光
- **Hysteria**：平方反比带 +1 偏置（无截断半径），光心在玩家（Iris `relativeEyePosition`），双手 max，近场 AO 豁免，可继承 LPV 彩光（`handheld_lighting.glsl:27-49`）。**未做**日光压制（ relies on falloff 本身）。
- **Astra**：相机中心、`clamp(base - d/15, 0, 1)` 线性 15 格硬截断（`Astra/shaders/global/lighting/blocklight.glsl:62-70`），与方块光以 `min(1, a+b)` 融合无缝（`:99`），并有玩家自身天空暴露门 `heldLightSuppression` 防止"白天手持火把漏光进洞穴"（`:95-96`）。
- **优劣**：Astra 的日光压制与融合无缝是**优势**；Hysteria 的连续衰减（无 15 格硬边）与玩家中心光心是**优势**——Astra 硬截断在 14-15 格处可见亮度跳变，且相机转身时手持光跟随视线而非身体。两者结合空间明确：保留 Astra 压制门，改衰减形式 + 换光心。

### c) 潮湿表面
- **Hysteria**：LabPBR porosity 通道驱动（`material.glsl:59`），两层暗化 + f0/roughness/SSR 整体替换 + 涟漪法线 + 室内门（`rain_puddles.glsl:16-75`），依赖 PBR 资源包提供孔隙率数据。
- **Astra**：blockId 三类（wood/soil/stone 类）+ 每类响应三元组（暗化/高光增益/高光指数，`Astra/shaders/lib/wet_material.glsl:7-21`）；暗地面（大面积潮湿）与稀疏积水（ puddle，唯一驱动反射的信号）分离（`Astra/shaders/program/lit.fsh:190-223`）；涟漪幅度跟随积水遮罩、掠射角衰减（`:216-219`）；有界解析高光复用直射光项、不触发 SSR（`:267-274`）。
- **优劣**：Astra **不依赖资源包**、且"大面积潮湿/稀疏积水"信号分离的架构（weather.glsl:23-24 明确要求二者行为不同）比 Hysteria 的单一 puddle 噪声更讲究；Astra 的稀疏积水 + 反射触发逻辑是 Hysteria 没有的。Hysteria 的**孔隙率分层暗化**（多孔先暗）与**材质整体替换到水面 BRDF**（真实 f0=0.02/roughness=0.002）是 Astra 缺的物理层次——Astra 的暗化是单层的（`lit.fsh:222`），高光是解析有界的而非真反射。不确定项：Astra 是否在别处还有 f0 调制路径，本报告仅核对了 wet_material/lit.fsh/weather.glsl 三个文件。

### d) Universal 变体（一套源码适配多硬件档）
- **Hysteria**：五档 profile 只做"开关 + 步数/分辨率缩放"（`shaders/shaders.properties:1-5`）；低两档叠加 TAAU 渲染缩放（0.50/0.66）保帧率；体雾另有独立 `VL_RENDER_SCALE 0.50`（`settings.glsl:261`）与 `VL_QUALITY`（`:253`）两个正交缩放维度；跨加载器/材质格式/DH 用编译宏分支。低档"减噪"靠 `VL_QUALITY` 提步数而非关特性（CHANGELOG 1.1.0 明确修过低档 banding）。
- **Astra**：四档 profile（PERFORMANCE/NO_SHADOWS/BALANCED/ULTRA，`Astra/shaders/shaders.properties:424-427`），以特性开关为主。在 `lib/settings.glsl` 与 `shaders.properties` 中未检索到渲染缩放（TAAU/RENDER_SCALE）类定义。
- **优劣**：Astra 四档语义清晰（含专门的 NO_SHADOWS 档）；Hysteria 的**正交缩放维度**（全局 TAAU × 雾独立分辨率/质量）让"降档不减特性"成为可能——Astra 目前降档=关特性（如 BALANCED 才有 SSR/焦散），Hysteria 的 TAAU-on-low-end 是 Astra 没有的低配手段。

### 其它对照（水体/后处理）
- 水：Astra 的水模块（SSR/折射/吸收/解析焦散/水下光束，`global/water/` 14 个文件）远比 Hysteria 完整；Hysteria 的 shadowcolor0 烘焙焦散（`shadow.glsl:236`）与 Astra 解析焦散是两条路线，Astra 优势在质量，Hysteria 优势在成本转移进 shadow pass。
- 后处理：Astra 已有 Bloom/曝光/分级/FXAA/TAA（`global/post/`）；Hysteria 的白平衡黑体计算与分色相饱和度（`grade.glsl:141-168`）是 Astra `global/post/grading.glsl` 可对照的参数化思路（未核对 Astra grading.glsl 内部是否已有，存疑）。

---

## ⑤ 借鉴可行性（许可证层面）

- **结论：技术思路与参数可自由借鉴；逐行代码搬运需先取得 nvb-uy (ElocinDev) 的书面许可。**
- AGNYA 第 4 条明确：将本包部分源码用作另一原创项目的一部分需作者明确许可（`LICENSE.md:101-105`）；第 3 条：公开分发基于它的修改版同样需许可（`LICENSE.md:86-95`）。私有试验不受限（第 2 条，`LICENSE.md:77-79`）。
- 安全路径：
  1. 只参考公开文档/本报告描述的**算法思想与公式形态**，在 Astra 中独立实现（如衰减曲线、两层暗化的结构性思路）；
  2. 常数数值（如 0.18/0.16/1.2/0.25）单独看是参数，但成组照搬仍建议注明灵感来源并最好获得许可；
  3. 若要整段搬运（如 handheld_lighting.glsl 全函数），先联系作者取得第 4 条许可并在 Astra 署名；
  4. Hysteria 中源自 Photon 的部分本就是 MIT（`LICENSE.md:136-147`），**优先去 Photon 上游取同类代码**即可仅承担 MIT 义务（保留版权声明），这是比引用 Hysteria 更干净的路径。
- Astra 若日后公开分发含 Hysteria 派生内容的版本，还须遵守"不得更换许可证、禁止变现"两附加条件。

---

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **手持光重做：连续衰减 + 玩家中心 + 保留 Astra 压制门**（借鉴点 #4 + Astra 既有优势）
   提升：消除 15 格硬边、转身不再拖光；工作量小（改 `global/lighting/blocklight.glsl:62-70` 约 10 行 + 引入 `relativeEyePosition`）。性价比最高。
2. **方块光三段衰减曲线替换 pow4**（借鉴点 #1，可并入 #2 的日光压暗对比）
   提升：黑暗环境下火把层次感直接对标 Hysteria 主打卖点；工作量小（`global/lighting/blocklight.glsl:89-90` 单点替换 + 调参）。
3. **潮湿两层暗化 + 室内积水门**（借鉴点 #5 前半 + #7）
   提升：雨湿是 Astra 已有特性的"完成度"补全，多孔材质先暗更真实；工作量中（`lib/wet_material.glsl` 加 porosity 近似列 + `lit.fsh:222` 改两项 + `weather.glsl` 加 blocklight 门），不动反射架构、风险可控。
4. **引入 TAAU/渲染缩放 + Final CAS/上采样二选一**（借鉴点 #12、§②-6）
   提升：给 Astra 增加第四档之外的正交性能旋钮，中低配用户收益最大；工作量中大（涉及全部 pass 的 uv 缩放一致性），建议独立排期。
5. **shadowcolor0 烘焙焦散作为焦散性能档**（借鉴点 #8）
   提升：低档位获得彩色焦散而几乎零屏幕空间成本；工作量中（需核对 `global/shadow/shadowmap.glsl` 彩阴影采样路径后决定），排序靠后因 Astra 解析焦散已是完整方案。

---

## 附：引用抽查记录

写报告后已重新打开文件核对以下引用（抽样 ≥8 条，全部一致）：
1. `shaders/include/light/handheld_lighting.glsl:32` — falloff 公式行 ✓
2. `shaders/include/light/diffuse_lighting.glsl:31` — pow8+0.18sqr+0.16dampen ✓
3. `shaders/include/light/diffuse_lighting.glsl:189` — 洞穴填充光 ✓
4. `shaders/include/misc/rain_puddles.glsl:23` — 室内排除门 ✓
5. `shaders/program/composite1.glsl:409` — get_rain_puddles 调用 ✓
6. `shaders/settings.glsl:147` — CLOUDS_TEMPORAL_UPSCALING ✓
7. `shaders/shaders.properties:132` — iris.features.optional ✓
8. `shaders/include/misc/material.glsl:59` — porosity 解码 ✓
9. `shaders/program/post/final.glsl:149-154` — CAS/Catmull-Rom ✓
10. `shaders/include/fog/simple_fog.glsl:18-20` — 洞穴雾常量 ✓
11. `Astra/shaders/global/lighting/blocklight.glsl:62-70` — Astra 线性手持光 ✓
12. `Astra/shaders/lib/wet_material.glsl:16-21` — Astra 湿响应三元组 ✓
13. `Astra/shaders/shaders.properties:424-427` — Astra 四档 profile ✓
14. `LICENSE.md:101-105` — AGNYA 第 4 条 ✓
