# Bliss Shaders 2.1.2 研究报告 — Astra 可借鉴点

研究对象：`reference_shaderpacks/bliss-shader/`（Bliss V2.1.2，Chocapic13' Shaders edit）。
所有行号均基于本仓库内该目录，撰写后已抽样复核（见文末自抽查记录）。

---

## ① 包概览

- **版本**：`profile.SHADER_VERSION_LABEL = Bliss V2.1.2`（shaders/lang/en_us.lang:1）；发行名格式 "Bliss_(版本)_chocapic13_shaders_edit"。
- **作者/血统**：X0nk 基于 Chocapic13 Shaders 的深度编辑。致谢名单（README.md:7-13）：Chocapic13（底包）、Null（voxel floodfill 彩光 LPV）、WoMspace（DOF）、Emin 与 Gri573（防漏光）、RRe36/Sixthsurge（灵感）。
- **许可证**：全部权利保留式许可，条款来自 Chocapic13（LICENSE.md:1-6）：不得声称包内代码为自己的作品；衍生包标题必须采用 "(Chocapic13' Shaders edit)" 命名格式；必须明确署名 Chocapic13；禁挂变现链接。另含少量第三方 MIT 片段（如 end_fog.glsl:1-32 的 David Hoskins / iQ hash，带独立许可头）。
- **风格定位**：Chocapic 系延迟管线（gbuffers → deferred → composite0-13 → final），主打"场景光照随时间/位置持续变化"的美术观，以**维度特化**（下界烟羽、末地涡旋雾+闪电）、**逐日天气系统**（10 套天气配置）、**LPV 体素彩光**和**极重度的可配置项**（shaders.properties:133 一条 sliders 就列了 300+ 变量）著称。面向 Iris（shaders.properties:11 声明 COMPUTE_SHADERS/CUSTOM_IMAGES/voxelizeLightBlocks 等可选特性）。

**管线组织**（world0/*.fsh 全是 4 行桩文件，按宏转发到 `dimensions/` 共享实现，如 world0/composite2.fsh:1-4 `#define OVERWORLD_SHADER` + `#include "/dimensions/composite1.fsh"`）：
deferred（烘焙天空全景 LUT + 1x1 状态格）→ deferred1（四分之一分辨率深度进 LUT）→ deferred2（低分辨率体积云）→ composite0（透明体后方雾）→ composite1（GTAO + VPS 阴影 blocker 搜索）→ composite2（主光照：直射/阴影/SSS/LPV/间接）→ composite3（VL 雾 + 水下体积）→ composite4（雾合成/折射/水下吸收）→ composite5（TAA minmax）→ composite6（TAA resolve）→ composite7-10（bloom 金字塔）→ composite11（bloom 收集 + DoF + Purkinje + tonemap）→ composite12（色彩分级 + CAS 锐化）→ final（gameplay 特效/网格线）。

**阶段 → 文件映射表**（下界/末地共用同一套 dimensions 实现，仅宏不同）：

| 管线阶段 | 实现文件（dimensions/） | 职责 |
|---|---|---|
| deferred | deferred.fsh（385 行） | 天空全景 LUT 烘焙、末地闪电计时器、天气/曝光状态格 |
| deferred1 | deferred1.fsh（57 行） | 四分之一深度写入 colortex4 图集（:46-56） |
| deferred2 | deferred2.fsh（147 行） | 低分辨率体积云（CLOUDS_QUALITY 档） |
| composite0 | fogBehindTranslucent_pass.fsh（398 行） | 水面/玻璃后方的雾与云，写 RT13 |
| composite1 | composite.fsh（544 行） | GTAO + VPS blocker 搜索预 pass |
| composite2 | composite1.fsh（1371 行，最重） | 主光照：直射、阴影、SSS、LPV、间接、手持光 |
| composite3 | composite2.fsh（448 行） | VL 雾 + 水下体积（低分辨率 + 双边放大） |
| composite4 | composite3.fsh（486 行） | 雾/云合成、折射扭曲、水下吸收、BorderFog |
| composite5 | composite4.fsh（67 行） | TAA 用 3x3 minmax（升档渲染时启用） |
| composite6 | composite5.fsh（437 行） | TAA resolve（含升档与超采样模式） |
| composite7-10 | composite6-9.fsh | bloom 高斯金字塔逐级下采样 |
| composite11 | composite10-11.fsh | bloom 七级收集（10.fsh:87-93）→ DoF → Purkinje → tonemap（11.fsh） |
| composite12 | composite12.fsh（158 行） | 色彩分级（:92-101）+ CAS 锐化（:105） |
| final | final.fsh（119 行） | gameplay 特效、取景网格线 |
| compute | setup.csh（1158 行）/ shadowcomp.csh（165 行） | LPV 光色表构建 / 体素洪泛传播 |

两个 compute（setup.csh、shadowcomp.csh）不参与逐帧场景渲染，只在 LPV 开启时维护 3D 光场，这是本包对 Iris `COMPUTE_SHADERS/CUSTOM_IMAGES` 特性（shaders.properties:11）的核心用法。

## ② 架构与特性清单

### 大气 / 云
- 物理大气（Rayleigh+Mie+臭氧）：行星半径 6731 km、大气高 110 km、标高 8/1.2 km（lib/ROBOBO_sky.glsl:9-17），10 步 + 蓝噪声 march（dimensions/deferred.fsh:260）。
- **天空全景 LUT**：每帧把"纯天空"（256x257 区域）与"天空+云+VL 雾"（再 256x257 区域）烘进 colortex4 图集（dimensions/deferred.fsh:246-297），查询接口 `skyFromTex/skyCloudsFromTex`（lib/sky_gradient.glsl:140,148）。
- 三层体积云：两层积云（100 m 厚）+ 一层高积云（lib/volumetricClouds.glsl:27-37），层间上遮蔽计算（同文件:338），按玩家在云上/云下切换前后混合序（:570-603）。
- 逐日天气：DAY0-DAY9 十档 coverage/density/上雾/洞雾滑条（shaders.properties:367-380），经 colortex4 (1,1)/(2,1) 状态格传给着色器（dimensions/all_translucent.vsh:198）。
- VL 雾：均匀/梯度/云状/雨天四分量 + 沙暴雪暴替换（lib/overworld_fog.glsl:16-40）。
- 季节变色：worldDay 驱动四季颜色插值，叶色单独配置（lib/climate_settings.glsl:11-63）。
- 群系雾/雪暴沙暴：`isSwamps/isJungles/isDarkForests` 60 秒 smooth 过渡（shaders.properties:415-419），`snowStorm/sandStorm` 由群系+雨量驱动（:441,445）。

### 水体
- 波浪：noisetex 三方向旋转采样的高度场，有限差分求法线，距离 LOD（lib/waterBump.glsl:31-57 起的实现体，采样环 :37-48）。
- 解析焦散：沿 sunVec 把世界点投影到水面，三尺度旋转波叠加后取 `exp`（lib/waterBump.glsl:1-23）。
- 反射在 gbuffers_translucent **前向完成**：fresnel（all_translucent.fsh:759）、太阳 GGX 高光、天空 LUT 反射（:785）、SSR（:797，rayTrace 定义 :250）。
- Snell's window：水下时 fresnel 改用 `(1.5+NoV)^25`（all_translucent.fsh:772-774）。
- 吸收参数化：`Water_Absorb_R/G/B` 十进位可调（lib/settings.glsl:20-22），场景合成时 `exp(-totEpsilon*dist)`（dimensions/composite3.fsh:416）。
- 水下体积光：VL march 内以焦散调制直射（dimensions/composite2.fsh:303）。
- 折射：屏幕空间 UV 扭曲 `ApplyDistortion`（dimensions/composite3.fsh:212,324）。

### 阴影与光照
- VPS 变化半影：独立预 pass 做 blocker 深度搜索（dimensions/composite.fsh:481-545），主 pass 按结果扩 PCF 半径。
- GriAndEmin 防漏光：法线偏置 + 屋顶漏光收缩（lib/Shadows.glsl:1-25）。
- 半透明彩色阴影：shadowtex0/1 + shadowcolor0 两次采样透色（dimensions/composite1.fsh:660-669）。
- 屏幕空间接触阴影（composite1.fsh:376-435）。
- LabSSS 皮肤次表面：用 blocker 深度驱动散射（composite1.fsh:711-750）。
- **LPV 体素彩光**：Iris `voxelizeLightBlocks`（shaders.properties:24）+ setup.csh 生成 per-block 光色/范围/染色表（dimensions/setup.csh:11-17,1156）+ shadowcomp.csh compute 洪泛传播、rgba8 3D 双缓冲（dimensions/shadowcomp.csh:111-142,161）、HSV 压缩编码（lib/lpv_common.glsl:2）+ 双缓冲三线性采样（lib/lpv_render.glsl:10-16）。
- GTAO（PhotonGTAO 集成）：composite 预 pass 计算、主 pass 双边上采样（dimensions/composite.fsh:446；composite1.fsh:1196）。
- 手持光源：`dynamicHandLight=true`（shaders.properties:5）。

### 后处理
- TAA：8 帧抖动 + 最近深度速度 + CatmullRom 历史 + 3x3/5tap AABB 混合钳制（dimensions/composite5.fsh:317-386），tonemap-before-blend 抗闪烁，截图模式无限累积超采样（:400-401）；TAA 升档渲染（shaders.properties:87）。
- 自动曝光：deferred 顶点阶段对 bloom 链采 50 个 R2 样本、log 域均值、0.95 时域混合（dimensions/deferred.vsh:238-245），key-value 公式（:250）+ 视杆曝光暗视觉通道（:253-264）。
- Tonemap：Hejl2015 / AgX / AgX_minimal（lib/color_transforms.glsl:34,249,291）。
- 色彩分级：shadows/mids/highlights 三段亮度蒙版乘色（dimensions/composite12.fsh:92-101）+ 亮度曲线。
- CAS 锐化（composite12.fsh:105）。
- Purkinje 暗视觉偏蓝（dimensions/composite11.fsh:147-161）。
- DoF：bokeh 散景 + anamorphic + 自动对焦 + 焦点激光笔（composite11.fsh:102-125）。
- Bloom：1/4→1/256 七级 mip 双三次收集（dimensions/composite10.fsh:87-93）。
- 游戏性特效：受伤红闪/低血量/出水/选框描边（shaders.properties:389-390 一带 screen.GAMEPLAY_EFFECTS；lib/gameplay_effects.glsl）。

### 维度特化（下界 / 末地）
- 下界：天花板垂落烟羽 plume（噪声 + 风剪切 + 顶底双衰减，lib/nether_fog.glsl:20-30），三滑条参数（plume/ceiling smoke/haze，shaders.properties:268）。
- 末地：涡旋雾（中心 (0,200,0)、旋转采样、边界衰减，lib/end_fog.glsl:72,160）、随机跳位的末地闪电（:74-82）、THE_ORB 彩色点光源模式（:179-191）、闪电计时器状态格（dimensions/deferred.fsh:322-333）。
- 下界/末地 VL 雾直接烘进全景 LUT（deferred.fsh:306-312）。

### 性能与时域
- 全景 LUT：天空/云/雾的 march 成本固定为 ~2x256² 像素/帧，全场景复用。
- 低分辨率体积云 + 抖动（dimensions/deferred2.fsh:124-126），HQ/LQ 两档步数与 LoD（lib/volumetricClouds.glsl:1-12）。
- VL 雾独立分辨率 + 双边放大（dimensions/composite2.fsh:366-372、composite3.fsh:312-318）。
- LPV rgba8 3D 纹理双缓冲（每帧一步传播），compute 共享内存缓存邻域（shadowcomp.csh:105-112）。
- 时域几乎全部依赖 TAA 聚合（云、VL、SSR 均抖动 + TAA），未见独立云历史重投影。

## ③ Astra 可借鉴点

1. **天空+云+雾合成全景板**：Bliss 把"天空"与"天空+云+VL 雾"分层烘进一张全景图，反射、水面天光、边界雾全部查表。（出处：dimensions/deferred.fsh:246-297）对应 Astra：`Astra/shaders/lib/sky_reflection_cache.glsl`（现只有 256x128 天空板）与 `Astra/shaders/global/atmosphere/clouds_planar.glsl`。难点：**低-中**——Astra 已有缓存板与时序基建，主要工作是把云合成结果按经纬度写入第二条带并处理云时域与全景板坐标的一致性。
2. **逐日天气系统（DAY0-DAY9 + 随机档）**：纯 CPU 端 custom uniform + 每档 8 个参数覆盖云量/云密/上雾/洞雾，进游戏可切天气。（出处：shaders.properties:367-380）对应 Astra：`Astra/shaders/global/atmosphere/weather.glsl` + Astra shaders.properties 的 custom uniform 基建（:435 起）。难点：**低-中**——无新渲染技术，主要是设置 UI、custom uniform 与现有雾/云密度接口对接。
3. **VPS 阴影预 pass + GriAndEmin 防漏光**：blocker 搜索独立成 pass 并双边放大；法线偏置 + "整块收缩"消除屋面漏光。（出处：dimensions/composite.fsh:481-545；lib/Shadows.glsl:5-25）对应 Astra：`Astra/shaders/global/lighting/shadowmap.glsl`。难点：**低**——Astra 已有 shadowmap 与 prepare 阶段，防漏光偏置可先以函数级重写方式落地。
4. **rod exposure + Purkinje 暗视觉**：第二条 log 均值亮度算视杆响应，夜景整体推向单色蓝绿。（出处：dimensions/deferred.vsh:253-264；composite11.fsh:147-161）对应 Astra：`Astra/shaders/global/post/exposure.glsl`（已有 one-texel 时域历史）与 `global/post/grading.glsl`。难点：**低**——在现有曝光 pass 里加一条均值通道 + grading 末尾一个混合。
5. **水下体积光内嵌解析焦散**：水下 VL march 每步用波场 exp 焦散调制太阳直射，光束呈现焦散纹理。（出处：dimensions/composite2.fsh:303）对应 Astra：`Astra/shaders/global/water/light_shafts.glsl`（已有 Solas 光束）与 `global/water/caustics.glsl`（已有解析焦散，重合度高）。难点：**低**——把已有焦散函数接入光束 march 的直射项。
6. **Snell's window**：水下看水面时把 fresnel 换成窄指数式，天然形成"透镜窗"。（出处：all_translucent.fsh:772-774）对应 Astra：`Astra/shaders/global/water/surface.glsl` / `optics.glsl`。难点：**低**（一两处分支）。[不确定]：Astra 水面是否已有等效处理，需读 surface.glsl 全文确认。
7. **沙暴/雪暴群系强雾**：以群系+雷雨驱动的 smooth uniform，把普通云雾替换为高速平移的浓雾并压平高度衰减。（出处：lib/overworld_fog.glsl:39-46；shaders.properties:441,445）对应 Astra：`global/atmosphere/weather.glsl` + `global/atmosphere/fog.glsl`。难点：**低-中**。
8. **LPV 工程形态（对照组）**：Iris 原生 `voxelizeLightBlocks` 免去自维护体素化；rgba8 3D 双缓冲 + HSV 对数压缩 + compute 共享内存邻域缓存。（出处：shaders.properties:24；shadowcomp.csh:105-161；lib/lpv_common.glsl:2）对应 Astra：`Astra/shaders/program/nether_light.csh` + `global/dimension/nether_colored_light.glsl`（现限下界、同帧重建、无时域）。难点：**高**——若想把体素彩光推广到主世界需重设计网格跟随与收敛策略；仅借鉴编码/共享内存技巧则**中**。
9. **三层体积云（长期项）**：双积云 + 高积云、层间遮蔽、按视角切换混合序、云阴影。提升最大但需 raymarch 框架。（出处：lib/volumetricClouds.glsl:27-43,555-603）对应 Astra：`global/atmosphere/clouds_planar.glsl`（现单平面 sheet）+ `cloud_temporal.glsl`。难点：**高**。
10. **Chocapic 延迟管线对前向 Astra 的结构性启示**（专项问题 d）：
    - Bliss 的水面反射其实放在 gbuffers 前向完成（all_translucent.fsh:736-801），与 Astra 前向架构同构，说明"反射查全景 LUT + 少量 SSR"完全不需要延迟管线。
    - 值得搬的是**预 pass 单一职责 + 双边放大**：GTAO、VPS blocker、VL 雾都独立低分辨率 pass。Astra 前向架构同样可在 prepare*/ssao 现有阶段套用此模式。
    - **缓冲图集复用**：colortex4 一个缓冲同时当全景 LUT 与十几个 1x1 状态格（曝光、焦点深度、天气参数、末地计时器，deferred.fsh:322-333、all_translucent.vsh:198）。Astra 有独立 effect_history/状态 buffer，思路等价，无需改。

## ④ Astra 已有对应实现

| 能力 | Bliss | Astra 对应文件 | 对比 |
|---|---|---|---|
| 天空模型 | ROBOBO 物理 Rayleigh/Mie/臭氧，10 步 march（ROBOBO_sky.glsl:9-17） | `global/atmosphere/sky_gradient.glsl`（Complementary r5.9 三向解析模型，:4-7 有移植出处注释） | Bliss 物理一致性与高度表现强，成本高；Astra 美术参数化强、便宜。各有优劣 |
| 方向性天光 | 无 SH，间接 = GTAO+LPV+sky ambient | `lib/sky_sh9.glsl`（SH9 投影/求值，:5-8） | Astra 此处独有；Bliss 无对应 |
| 云 | 三层 raymarch，靠 TAA 聚合时域 | `global/atmosphere/clouds_planar.glsl`（Complementary 平面云）+ `cloud_temporal.glsl`（独立时域历史，:3-4） | Astra 云形态简单但有独立时域；Bliss 形态强时域弱。[不确定]：Bliss 是否存在云的显式重投影，本次未发现 |
| 天空反射缓存 | colortex4 全景 257x257 双区 | `lib/sky_reflection_cache.glsl`（256x128+双 gutter，:1-8） | 同构思路；Bliss 多了"含云/雾的第二区"（见借鉴点 1） |
| 水 | 反射在 gbuffers、吸收/折射在 composite | `lib/solas_water.glsl` + `global/water/`（absorption/refraction/raytrace/caustics/light_shafts/temporal/particles） | Astra 模块化与水下专项（光束/粒子/时域）更细；Bliss 的 Snell window 与 VL 内焦散是可补点 |
| 焦散 | 解析式投影焦散（waterBump.glsl:1-23） | `global/water/caustics.glsl`（Solas V2.2b 移植，:3-10） | 双方同为解析式，Astra 已覆盖 |
| 彩色阴影 | shadowtex0/1+shadowcolor0（composite1.fsh:660-669） | Astra shaders.properties 有 `COLORED_SHADOWS` 开关（:424 profile 行） | 均有；Bliss 另有半透明染色实现细节可对照。[不确定]：Astra 彩色阴影具体实现未读 |
| 阴影柔化 | VPS blocker 预 pass | `global/lighting/shadowmap.glsl` + `SHADOW_FILTER_MODE/SHADOW_SOFTNESS` | [不确定]：Astra 是否已有 blocker 搜索式 PCF，未读实现无法断言 |
| 体素彩光 | 全维度 LPV，逐帧单步传播，跨帧收敛 | `program/nether_light.csh` + `global/dimension/nether_colored_light.glsl`（Solas V3.7b 同帧扩散，:3-6 注明"无时域历史"） | Astra 同帧稳定无拖影；Bliss 覆盖全维度但依赖多帧驻留收敛。[不确定]：两者收敛/移动场景表现需实测 |
| 下界环境 | 烟羽雾 3 参数 + LPV | `global/dimension/nether.glsl` + `nether_volume.glsl` + `nether_fog_density.glsl`（五类群系雾） | Astra 群系雾分类更细；Bliss 烟羽造型更讲究（nether_fog.glsl:20-30） |
| 末地环境 | 涡旋雾+跳位闪电+Orb | `global/dimension/end_kerr.glsl`/`end_blackhole.glsl`/`end_system.glsl`（Kerr 黑洞天空） | 路线不同：Bliss 雾化叙事，Astra 几何化天体；互补而非替代 |
| 体积雾 | 低分辨率 VL + 双边放大 + 洞雾 | `global/atmosphere/volume_fog.glsl`（R2/H3 可选 overworld 体积，:7-9） | 模式相同；Bliss 的沙暴/雪暴替换与"洞雾天空压暗"是差异点 |
| 曝光/分级/tonemap | deferred.vsh 采样曝光 + rod + AgX 系 | `global/post/exposure.glsl`（one-texel 历史，:4-8）+ `grading.glsl` + `lib/tonemap.glsl` | 等价；rod/Purkinje 通道 Astra 暂无（借鉴点 4） |
| TAA | 8 帧抖动 AABB + tonemap-blend + 升档 | `lib/taa_state.glsl`/`taa_resolve.fsh`/`taa_reactive.glsl` | Astra 有 reactive 设计；Bliss 的" tonemap-before-blend"与"离屏 clamp"小技巧可参考。[不确定]：Astra resolve 内部细节未读 |
| DoF / gameplay 特效 | 有（bokeh/受伤/低血量） | 无对应（post 仅 bloom/fxaa/grading/godrays） | 若要属新功能 |

**对任务专项问题的直接回应**：
- (a) 物理大气与体积云：Bliss 是"物理大气 + 烘焙全景 + 三层 raymarch 云、时域交给 TAA"；Astra 是"解析美术天空 + 平面云 + 独立时域"。可合流的点是借鉴点 1（含云全景板）与借鉴点 9（三层云，长期）。
- (b) 下界/末地特化：Bliss 的维度差异全部做在"雾与点光源"层（nether_fog.glsl / end_fog.glsl + deferred.fsh 维度分支），光照主体共用 composite1.fsh；Astra 则把维度差异下沉到独立 compute/体素/黑洞系统，分工程度更高。Bliss 的"跳位闪电 + 计时器状态格"是低成本可借的氛围件。
- (c) 水下与水体：双方都是"gbuffers 前向反射 + 后期吸收/折射"，Bliss 独有 Snell's window 与 VL 内焦散调制；Astra 独有独立光束时域与水下粒子。互补明显，借鉴点 5/6。
- (d) 延迟管线组织对前向 Astra 的启示：见借鉴点 10 —— 真正可迁移的不是 deferred 本身，而是"预 pass 单一职责 + 低分辨率 + 双边放大"与"状态格图集"两个工程模式，两者都不要求延迟架构。

## ⑤ 借鉴可行性（许可证层面）

- Bliss 的许可（LICENSE.md:4-6）明确：**不得把代码声称为自己的**；基于它的衍生必须命名 "(Chocapic13' Shaders edit)" 并显著署名。Astra 若逐行移植 Bliss/Chocapic 代码，即落入该衍生链，与 Astra 现状（Astra/LICENSE:1-5：临时"仅限个人使用"，发布前需过 design.md §9.3 发布门）直接冲突。
- **结论**：理念、算法结构、参数化思路可借鉴（本报告③即按此口径）；**禁止逐行/近似逐行复制 Bliss 任何 GLSL**。即使重写实现，也应在 `Astra/THIRD-PARTY.md` 台账登记"思想来源：Bliss 2.1.2"以满 credentials 义务。个别带 MIT 头的通用片段（hash 函数等）理论上可单独取用，但必须原样保留许可头并登记。
- 注意：Astra 已有 Steadfast(GPL) 派生的 godrays（global/post/godrays.glsl:3-8 自述），发布门待决；不要再叠加"保留所有权利"派生代码增加清偿难度。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **rod exposure + Purkinje 暗视觉通道**（借鉴点 4）：改动只在曝光/grading 两文件，夜景氛围提升立竿见影。
2. **逐日天气系统**（借鉴点 2）：Astra 已有 custom uniform 与云/雾密度接口，主要工作量在设置与调参，重玩价值高。
3. **天空+云合成全景板**（借鉴点 1）：在 sky_reflection_cache 上加"含云区"，让水面反射带上云形，工作量小、画面收益明显。
4. **水下光束内嵌焦散 + Snell's window**（借鉴点 5/6）：复用现有焦散函数，水下观感升级，改动集中在 water 模块。
5. **VPS 阴影预 pass + 防漏光偏置**（借鉴点 3）：利用现有 prepare/ssao 阶段模式接入，提升阴影质量与稳定性（长期可再评估三层体积云，收益最大但另立项）。

---

## 自抽查记录（引用复核）

撰写后重新打开文件核对（≥8 条，全部命中）：
1. shaders/lang/en_us.lang:1 = `profile.SHADER_VERSION_LABEL = Bliss V2.1.2` ✓
2. lib/ROBOBO_sky.glsl:14,16,17 = `sky_planetRadius 6731e3` / `sky_atmosphereHeight 110e3` / `sky_scaleHeights vec2(8.0e3,1.2e3)` ✓
3. dimensions/deferred.fsh:246 = `/// --- ATMOSPHERE IMAGE --- ///`，:260 = `calculateAtmosphere(...10, blueNoise())` ✓
4. lib/volumetricClouds.glsl:41 = `LAYER0_COVERAGE = mix(dailyWeatherParams0.x, Rain_coverage, rainStrength)`，:570 = 高低混合序注释 ✓
5. lib/overworld_fog.glsl:39-40 = IntenseFogs（沙/雪暴替换）✓
6. lib/nether_fog.glsl:20,26 = Plumes / RoofToFloorDensityFalloff ✓
7. lib/end_fog.glsl:72,74,179 = vortexPos / lightningPos / LightSourceColors ✓
8. dimensions/all_translucent.fsh:772 = `#ifdef SNELLS_WINDOW`，:785 = skyCloudsFromTex 反射，:797 = rayTrace SSR ✓
9. dimensions/composite1.fsh:641 = ComputeShadowMap，:660-669 = TRANSLUCENT_COLORED_SHADOWS + shadowcolor0 ✓
10. dimensions/composite5.fsh:317 = computeTAA，:400-401 = 截图模式累积 ✓
11. dimensions/deferred.vsh:250,253 = targetExposure / targetrodExposure ✓
12. lib/color_transforms.glsl:249,291 = ToneMap_AgX / ToneMap_AgX_minimal ✓
13. dimensions/shadowcomp.csh:142,161 = mixNeighbours / imageStore(imgLpv1 ✓
14. dimensions/composite10.fsh:87-93 = 七级 bloom 双三次收集 ✓
15. LICENSE.md:4,6 = "not allowed to claim any of the code" / 标题格式条款 ✓
