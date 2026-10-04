# Photon Shaders v1.3b 研读报告（面向 Astra 的可借鉴点）

> 引用约定：`P:xxx.glsl:行号` 指 `reference_shaderpacks/photon-shader/shaders/` 下的文件；`A:xxx.glsl:行号` 指 `Astra/shaders/` 下的文件。所有行号均已在本文成稿时打开源文件核对（自抽查记录见文末）。

## ① 包概览

- **名称/版本**：Photon Shaders，任务书给定版本 v1.3b；包内未嵌入版本字符串，`P:LICENSE:3` 标注 "Copyright © 2021-2025 Benjamin Stott ("SixthSurge")"。
- **作者**：Benjamin Stott（社区 ID：SixthSurge），长期维护，是 Iris/OptiFine 生态公认的物理向技术标杆。
- **许可证（自定义，见 `P:LICENSE:1-18`）**：
  - 允许：商业截图/视频；个人用途修改；**查阅与学习源码**（`P:LICENSE:10`）；作为模组包 redistribut。
  - 限制：**在直接或间接给创作者带来金钱收益的平台（如 Modrinth、CurseForge）再分发 Photon 或其衍生作品需作者书面许可**（`P:LICENSE:12`）；不得卖拷贝（`P:LICENSE:13`）。
- **风格定位**：物理正确路线 + 现代渲染管线：延迟着色（d4_deferred_shading）、预计算大气 LUT、compute 体素彩光（LPV）、TAA/TAAU 时域超分、5 类体积云、DH/Voxy 兼容。画质取向是"真实大气 + 电影级云"，与 Astra 的"前向 + 物理天空"同属写实系，但管线形态差异大（Photon 延迟，Astra 前向）。

## ② 架构与特性清单

### 2.1 大气与云
- **预计算大气散射（Bruneton 2020 路线）**：透射率 LUT 256×64、散射 LUT 16×64×32（`P:include/sky/atmosphere.glsl:25-26`），文件头注释直接引用 Eric Bruneton 的实现（`P:include/sky/atmosphere.glsl:118-125`）；散射 LUT 内拆"Rayleigh+多次散射"与"单次 Mie"两半（`P:include/sky/atmosphere.glsl:254-260`）。
- **物理系数**：AM0 太阳光谱反推的阳光色（`P:include/sky/atmosphere.glsl:14-20`）、Rec.709→Rec.2020 的 Rayleigh/Mie/臭氧系数（`P:include/sky/atmosphere.glsl:53-69`）、Jessie 臭氧分布（`P:include/sky/atmosphere.glsl:133-143`）。
- **解析透射率兜底**：无 LUT 时用 Chapman 函数近似气团（`P:include/sky/atmosphere.glsl:492-522`），供云的航空透视等低成本场合复用。
- **太阳/月亮 Mie 相位**：`nvidia_phase_area` 按太阳角半径积分的 RGB 三通道相位（`P:include/sky/atmosphere.glsl:83-103`）。
- **5 类体积云**：cumulus（`P:include/sky/clouds/cumulus.glsl:4`）、cumulus_congestus、altocumulus、cirrus、noctilucent（`P:shaders.properties:90` 云设置菜单逐层列出）；另有方块云 `//#define BLOCKY_CLOUDS`（`P:settings.glsl:262`）。
- **云密度场**：球壳求交（`P:include/sky/clouds/cumulus.glsl:225-230`）、预计算局部 coverage 图存 colortex8（`P:include/sky/clouds/cumulus.glsl:39-49`，开关 `P:settings.glsl:212`）、双层 3D Worley 细节侵蚀（`P:include/sky/clouds/cumulus.glsl:79-94`）。
- **云多次散射近似**：8 次迭代的 Schneider 风格衰减积分（extinction×0.4、phase_g×0.8、powder 衰减），`P:include/sky/clouds/cumulus.glsl:164-186`；光程用几何级数增长步长积分（step_growth=2.0，`P:include/sky/clouds/cumulus.glsl:110-133`）；对地面光程用高度分数直接估算（`P:include/sky/clouds/cumulus.glsl:326-330`）。
- **云相位函数**：单次 = max(Klein-Nishina, HG) 的"不合理但好看"组合（`P:include/sky/clouds/common.glsl:57-68`），多次 = 三瓣 HG 混合（`P:include/sky/clouds/common.glsl:70-77`）；powder effect（`P:include/sky/clouds/common.glsl:79-84`）。
- **多层云按视距排序混合**（`P:include/sky/clouds/common.glsl:128-141`）与云航空透视（用大气透射率比值，`P:include/sky/clouds/common.glsl:86-126`）。
- **云影**：`CLOUD_SHADOWS`（`P:settings.glsl:61`）实现于 `P:include/lighting/cloud_shadows.glsl`，且云影会放大 PCSS 半影（`P:include/lighting/shadows/pcss.glsl:246-248`）。
- **极光/彩虹/卷云检测/星野**：`P:include/sky/aurora.glsl`、`P:include/sky/rainbow.glsl`、`P:include/sky/stars.glsl`，开关见 `P:settings.glsl:176-190`。

### 2.2 水体
- **Gerstner 波法线**：色散关系 ω=√(gk)（`P:include/surface/water_normal.glsl:16-17`），多倍频几何级数归一化（`P:include/surface/water_normal.glsl:70-77`），区域高度变化噪声调幅（`P:include/surface/water_normal.glsl:84-92`），流水方向支持（`P:include/surface/water_normal.glsl:24-48`）。
- **水面视差**：4 步高度场 raymarch + 插值（`P:include/surface/water_normal.glsl:168-206`，开关 WATER_PARALLAX）。
- **折射**：translucent pass 打包法线偏移，合成时按 `normal_tangent / view_distance × min(layer_dist, 8)` 偏移 UV，并用深度守卫防折射出前景（`P:program/c1_blend_layers.fsh:290-304`）。
- **SSR**：`raymarch_depth_buffer` 求交 + 命中点重投影到上一帧颜色 `colortex5`（`P:include/lighting/specular_lighting.glsl:250-256`），并在反射路径上套解析雾（`P:include/lighting/specular_lighting.glsl:271-281`）。
- **焦散（默认关）**：在**阴影 pass** 里把光线经水面法线折射后，用 dFdx/dFdy 足迹面积比的雅可比聚焦（`P:program/shadow.fsh:106-145`），与水吸收一起写进 shadowcolor0（`P:program/shadow.fsh:149-160`）；开关 `//#define WATER_CAUSTICS`（`P:settings.glsl:430`）。核心三行：

  ```glsl
  // P:program/shadow.fsh:131-133
  vec3 new_pos = world_pos +
      refract_safe(light_dir, normal, air_n / water_n) *
          (distance_through_water * WATER_CAUSTICS_INTENSITY);
  ```
- **水下光束含焦散纹理**：水雾 VL 内用 noisetex 双向采样构造焦散条纹（`P:include/fog/water_fog_vl.glsl:115-120`）。
- **远处水面（DH/LoD 水统一着色）**：`P:include/misc/distant_water.glsl:10-16`。

### 2.3 阴影与光照
- **PCSS/VPS**：blocker search 求半影 + SSS 深度（`P:include/lighting/shadows/pcss.glsl:230-250`），borrow 自 Complementary 的漏光修正（`P:include/lighting/shadows/pcss.glsl:201-205`，注明 "used with permission"）。
- **SSRT 屏幕空间阴影接力**：shadow map 距离外的几何级数屏幕空间光线步进（`P:include/lighting/shadows/ssrt.glsl:10-33`，开关 `P:settings.glsl:121`）。
- **彩色阴影**：单独的 translucent 投影位置（`P:include/lighting/shadows/pcss.glsl:259-269`）+ shadow pass 写 shadowcolor0。
- **SH9 方向性天光**：`SH_SKYLIGHT`（`P:settings.glsl:65`），实现于 `P:include/utility/spherical_harmonics.glsl`。
- **LPV 彩色方块光**：体素化（`P:include/lighting/lpv/voxelization.glsl`）+ compute floodfill 传播（`P:include/lighting/lpv/floodfill.glsl:88-112`），双 3D 纹理按帧奇偶乒乓读取（`P:include/lighting/lpv/blocklight.glsl:6-12`），与原版 lightmap 按亮度自适应混合（`P:include/lighting/lpv/blocklight.glsl:42-50`），体积 128³ 默认（`P:settings.glsl:159`）。混合策略：

  ```glsl
  // P:include/lighting/lpv/blocklight.glsl:46-49（vanilla_lightmap_contribution 为 44-45 的 exp2 衰减）
  lpv_blocklight +=
      mix(vec3(dot(mc_blocklight, luminance_weights_rec2020)),
          mc_blocklight, 0.5) *
      mc_blocklight * 0.5 * vanilla_lightmap_contribution;
  ```
- **GTAO/SSAO 双 AO**：水平弧积分 GTAO（`P:include/lighting/ao/gtao.glsl:9-10`），开关 `P:settings.glsl:143-146`。
- **手持光源/闪电闪照/暗影效果**：`P:include/lighting/handheld_lighting.glsl`、`P:include/misc/lightning_flash.glsl`、`P:include/lighting/lpv/blocklight.glsl:53-59`（darkness 抖动）。

### 2.4 后处理
- **ACES 全家桶**：`P:include/post_processing/aces/`（aces.glsl、matrices、tonescales、utility），多 tonemap 可选（`P:include/post_processing/tonemap_operators.glsl`）。
- **Bloom**：6 级降采样（c5-c10）+ 合并 + 两趟高斯（`P:program/c11_bloom_merge_buffers.fsh`、`P:program/c12_bloom_gaussian_0.fsh`）。
- **直方图自动曝光**：c4 顶点阶段直方图，曝光存历史缓冲左下角 alpha（`P:program/c4_taa_exposure.fsh:382-386`）。
- **颜色分级 + Purkinje 夜视偏蓝**：`P:program/c14_color_grading.fsh`、`P:include/misc/purkinje_shift.glsl:3-25`。
- **DOF / 运动模糊 / FXAA / CAS / 暗角**：c2/c16/c15 与 `P:shaders.properties:36`（post 菜单）。
- **丁达尔光束**：`CREPUSCULAR_RAYS` 天空级 + 雾 VL 级彩色光柱（`P:settings.glsl:172-175`、`P:settings.glsl:313`）。

### 2.5 维度特化
- **按维度目录完整分线**：world0/world-1/world1 各自 composite 链（如 `P:world-1/composite17.fsh`、`P:world1/deferred4.fsh`）。
- **下界**：群系色驱动环境光 `NETHER_USE_BIOME_COLOR`（`P:settings.glsl:101`）、环境光提亮去饱和（`P:include/lighting/diffuse_lighting.glsl:244-245`）、独立雾 `NETHER_FOG_INTENSITY`（`P:shaders.properties:31`）。
- **末地**：末地日/环境光自定义（`P:settings.glsl:108-116`）、END_SUN_EFFECT（`P:settings.glsl:177`）、END_GLOW（`P:settings.glsl:40`）、末地雾 VL（`P:include/fog/end_fog_vl.glsl`）。
- **天气系统**：温度/湿度/风三通道噪声天气 + 群系偏置（`P:include/weather/core.glsl:10-26`，开关 `P:settings.glsl:44-51`），驱动雾/云/降水。

### 2.6 性能与时域
- **云 4× 棋盘时间上采样**：`CLOUDS_TEMPORAL_UPSCALING 4`（`P:settings.glsl:194`）、累计上限 20 帧（`P:settings.glsl:196`）；主 pass 减半步数（`P:include/sky/clouds/cumulus.glsl:201-207`）。
- **云历史重投影**：按云层世界半径判定所属层并加该层风速度（`P:program/d2_clouds_upscaling.fsh:157-179`）；disocclusion 用"上一帧 4×4 最低云距 vs 深度"判定（`P:program/d2_clouds_upscaling.fsh:109-127, 302-314`）；运动自适应邻域钳制（软 min/max，`P:program/d2_clouds_upscaling.fsh:317-350`）；offcenter rejection（`P:program/d2_clouds_upscaling.fsh:370-379`）。
- **TAA 全家福**：混合前 Reinward 压缩（`P:program/c4_taa_exposure.fsh:96-100, 315-321`）、YCoCg 软 min/max + 方差裁剪（`P:program/c4_taa_exposure.fsh:205-233`）、5×5 十字最近深度（`P:program/c4_taa_exposure.fsh:104-125`）、pixel-age 等权收敛（`P:program/c4_taa_exposure.fsh:306-311`）、offcenter rejection（`P:program/c4_taa_exposure.fsh:363-372`）。
- **TAAU 时域超分**：准备 pass 算邻域上下限（`P:program/c3_taau_prep.fsh:1-11`），置信度 + 闪烁抑制（`P:program/c4_taa_exposure.fsh:74-79, 329-361`），默认关（`P:settings.glsl:472`）。
- **画质 profile 分级**：low/medium/high/ultra 明确列开关（`P:shaders.properties:1-4`）。

### 2.7 材质与表面（PBR/资源包联动）
- **法线/高光/POM 三件套**：`//#define NORMAL_MAPPING / SPECULAR_MAPPING / POM`（`P:settings.glsl:380-382`），POM 阴影与斜率法线（`P:settings.glsl:396-398`），实现于 `P:include/surface/parallax.glsl`、`P:include/surface/material.glsl`。
- **方向性光照贴图**：`//#define DIRECTIONAL_LIGHTMAPS`（`P:settings.glsl:392`），实现于 `P:include/lighting/directional_lightmaps.glsl`。
- **雨湿地面**：`P:include/surface/rain_puddles.glsl`（水洼掩码 + 湿度渐变，`drynessHalflife/wetnessHalflife` 见 `P:settings.glsl:23-24`）。
- **边缘高亮**：`//#define EDGE_HIGHLIGHT`（`P:settings.glsl:32`），实现于 `P:include/surface/edge_highlight.glsl`。
- **硬编码材质掩码**：`P:include/misc/material_masks.glsl`（按 block id 提取 SSS/金属/发光），`P:include/misc/material_fix.glsl` 兼容修复。
- ** DH/Voxy 远景支持**：`P:program/dh_terrain.fsh`、`P:voxy.json`，远处水面统一着色见 2.2。

## ③ Astra 可借鉴点（每条：技术 / Photon 出处 / Astra 对应模块 / 迁移难点）

1. **云的"棋盘 + 按层风重投影"时间上采样**——把云渲染降为 1/4 像素量，历史用云层世界坐标（含各层风位移）重投影，而不是屏幕深度重投影；disocclusion 用"历史 4×4 邻域最近云距 vs 场景深度"判定，运动快时做速度比例的邻域钳制，并设 20 帧累计上限防无限拖影。出处：`P:program/d2_clouds_upscaling.fsh:157-179, 252-267, 302-350, 358-385`。对应 Astra：`A:program/cloud_screen.fsh:10-31` + `A:global/atmosphere/cloud_temporal.glsl:59-100`（已有独立历史与代表距离，但重投影是"代表点前移 dt"而非云层风速度精确跟踪，也无棋盘 4×）。难点：中——Astra 平面云是单层薄片，重投影可简化成 xz 平移跟踪；棋盘 4× 需要改 colortex24/25 分辨率与 resolve 采样约定。
2. **TAA 强化四件套**——(a) 混合前 Reinward 压缩让 AA 在 SDR 空间进行，混合后逆变换；(b) 邻域统计用软 min/max（Hybrid Reconstruction）叠加方差裁剪，γ 随距离 0.75→1.25；(c) 5×5 十字最近深度做运动物体重投影锚点；(d) pixel-age 等权混合 `alpha=max(1/age, blend)` 大幅加速收敛。出处：`P:program/c4_taa_exposure.fsh:96-100, 104-125, 205-233, 306-311, 315-328`。对应 Astra：`A:program/taa_resolve.fsh:1-3, 109-118`（已有 YCoCg 方差裁剪 1.25σ 固定值与运动自适应权重，无 Reinward 预压缩、无最近深度锚点、无 pixel-age）。难点：低——全部是单 pass 内的局部改动；其中 (a) 需确认与 Astra HDR 淡出/高亮编码（65000 截断）不冲突。
3. **SSR 命中点读上一帧颜色**——反射不再只查天穹缓存，命中场景时把命中点重投影到上一帧合成结果 `colortex5`（即历史帧含动态实体），并在反射视线上补解析雾；边界衰减防屏幕边缘拉丝。出处：`P:include/lighting/specular_lighting.glsl:234-288`。对应 Astra：`A:global/water/raytrace.glsl:46-111`（求交+置信度已是自己的，但取样来源与反射雾需对照 `A:global/water/light_shafts.glsl` 之外的合成路径）。难点：中——Astra 水合成在 water_composite，需要保证历史缓冲在该 pass 之前就绪且与 TAA 状态有效位联动。
4. **阴影 PCSS + SSRT 接力**——shadow map 内做 blocker search 半影（VPS），shadow map 距离外自动切换屏幕空间阴影光线步进（几何级数步长、深度容差当厚度），两者共享 dither 使过渡平滑。出处：`P:include/lighting/shadows/pcss.glsl:230-257`、`P:include/lighting/shadows/ssrt.glsl:10-33`。对应 Astra：`A:global/lighting/shadowmap.glsl`（203 行，Astra 现行阴影采样路径）。难点：中——SSRT 需要线性深度与法线缓冲可读，Astra 前向管线在 gbuffers 阶段就地采样阴影，需把"接力判定"放在同一处，步进成本要按前向逐像素预算。
5. **LPV 双缓冲乒乓 + 原版 lightmap 自适应混合**——compute 每帧在 A/B 两个 3D 纹理间传播，读取端按 frameCounter 奇偶切换，消除读写竞争；LPV 结果按亮度指数衰减与原版 lightmap 叠加，暗处出彩光、亮处不洗白。出处：`P:include/lighting/lpv/floodfill.glsl:88-112`、`P:include/lighting/lpv/blocklight.glsl:6-12, 42-50`。对应 Astra：`A:global/dimension/nether_colored_light.glsl:4-24`（Solas 式同帧重建+compute 扩散，无跨帧历史，无乒乓需求）与 `A:lib/nether_voxel_grid.glsl`。难点：低（若只在下界叠加混合策略）/高（若扩展到主世界，需要体素化 pass 与挥发性内存管理）。
6. **云影与半影联动**——云影不是简单乘暗，而是进入 PCSS 半影计算：云影覆盖处放大半影半径，制造阴天软影。出处：`P:include/lighting/shadows/pcss.glsl:246-248`、`P:include/lighting/cloud_shadows.glsl`。对应 Astra：`A:global/atmosphere/cloud_shadow_cache.glsl` 与 `A:global/atmosphere/weather.glsl`（云影已有，未见与阴影模糊半径联动）。难点：低——在 Astra 阴影采样处把 cloudShadow 标量接入其模糊半径即可。
7. **解析透射率兜底函数**——Chapman 函数近似气团，一套 20 行代码给出任意高度/天顶角的 Rayleigh+Mie+臭氧透射率，供云着色、雾、光柱复用而不依赖 LUT。出处：`P:include/sky/atmosphere.glsl:492-522`。对应 Astra：`A:global/atmosphere/fog.glsl` 与 `A:lib/twilight.glsl` 的经验色方案（详见④）。难点：低——纯函数可直接改写；调色需与 Astra 现有渐变天空对齐。
8. **水面 Gerstner 色散波 + 高度变化调幅**——每倍频用真实色散 ω=√(gk)，波高受低频噪声滚动调幅，远处自动趋平（normal_influence 随视线掠射角平滑，`P:include/surface/water_normal.glsl:148-160`）。出处：`P:include/surface/water_normal.glsl:6-22, 70-77, 84-92, 148-160`。对应 Astra：`A:lib/solas_water.glsl`（噪声纹理双频混合，无方向波列与色散）。难点：低——替换法线函数即可，注意与焦散共用同一高度场（Astra 焦散吃 solas_water_height）。
9. **Purkinje 夜视偏移**——低照度下向杆体细胞响应色（偏蓝）迁移，日间/方块光/地下自动退出的三重门控。出处：`P:include/misc/purkinje_shift.glsl:3-25`。对应 Astra：`A:lib/tonemap.glsl` / `A:lib/color_controls.glsl`（分级链内插入点）。难点：低——需要 Astra 有"场景亮度"与"方块光亮度"两个标量入口。
10. **天气三通道状态机**——温度/湿度/风用 1D 噪声随 world_age 演化 + 群系与用户偏置，统一驱动雾密度、云 coverage、降水类型。出处：`P:include/weather/core.glsl:10-26`、`P:settings.glsl:44-51`。对应 Astra：`A:global/atmosphere/weather.glsl`（142 行）。难点：中——是设计层面的统一参数化，不是单点函数移植。

## ④ Astra 已有对应实现（对照与优劣；不确定处如实标注）

| 主题 | Astra 文件 | 两边对比 |
|---|---|---|
| 天空数学路线 | `A:global/atmosphere/sky_gradient.glsl:5-7, 199-274` | Astra 是 Complementary r5.9 移植的"上/中/下三向调色板渐变"（纯 ALU，几乎零成本，依赖手工调色）；Photon 是 Bruneton 预计算散射（物理正确、日落/地平线自动正确，但需要 2D+3D LUT 管线与 prepare pass）。**哪边便宜**：Astra 数量级更便宜。**误差在哪**：Astra 无真实视角依赖的散射，太阳低角度的颜色带、 zenith 变暗、臭氧吸收全靠调色板近似；Photon 的误差集中在 LUT 精度与 mu_s 映射的 ad-hoc 压缩（`P:include/sky/atmosphere.glsl:227-232`）。 |
| 云 | `A:global/atmosphere/clouds_planar.glsl:56-119`、`A:program/cloud_screen.fsh:10-31`、`A:global/atmosphere/cloud_temporal.glsl:59-100` | Astra：半分辨率平面薄片（Complementary Reimagined 模型），独立时域历史（colortex24/25，代表点重投影）；Photon：完整体积云 5 层 + 4× 棋盘时间上采样。Astra 胜在成本与已稳定的历史；Photon 胜在造型（圆顶、暗底、多类型）与光照（多次散射近似）。值得注意：Astra 云坐标圆化函数本身就注明 "Thanks to SixthSurge"（`A:global/atmosphere/clouds_planar.glsl:68`），两包有共同血统。 |
| 水 SSR | `A:global/water/raytrace.glsl:62-111` | Astra：24 步几何步长 + 6 步二分细化 + 置信度（残差/脚印/边界），实现自研；Photon：深度缓冲步进 + 命中点重投影读历史帧颜色 + 反射路径雾 + 边界衰减。采样来源（历史帧 vs 当帧缓存）是最大差异；Astra 的置信度设计比 Photon 的 border attenuation 更细，Photon 的"反射含动态物体与雾"更强。 |
| 水 焦散 | `A:global/water/caustics.glsl:38-52` | 两边都走阴影色通道：Astra 用 Solas 曲率法 `max((dxA*-dxB + dyA*-dyB)*48, 0)`；Photon 用阴影 pass 内折射足迹雅可比（更物理，含水深衰减），但默认关闭且需 shadow pass 几何信息。Astra 实现更便宜、已默认开启。 |
| TAA | `A:program/taa_resolve.fsh:1-3, 14-38, 109-118`、`A:lib/taa_state.glsl:13-35` | Astra：YCoCg 方差裁剪（固定 1.25σ）、双线性历史逐 texel 深度校验、reactive 掩码、树叶速度注入、状态指纹（维度/FOV/媒体效果）整体失效；Photon：Reinward 预压缩、软 min/max+方差、最近深度锚点、pixel-age 等权、offcenter rejection、可选 TAAU。Astra 的"逐 texel 历史校验"是 Photon 没有的独门（Photon 用 Catmull-Rom+NaN 清理）；Photon 的收敛速度与运动清晰度整体更强。 |
| 维度彩光 | `A:global/dimension/nether_colored_light.glsl:4-24` | Astra：Solas V3.7b 架构改造，同帧重建、compute 扩散、无历史；Photon：LPV 乒乓 + 光发射平滑 + 与 lightmap 混合。Astra 的"无历史"换来无鬼影但每帧全量成本；Photon 的乒乓换连续性。九段 compute/五类群系雾的覆盖面 Astra 更细（Photon 下界只有整体环境光，`P:include/lighting/diffuse_lighting.glsl:244-245`）。 |
| 独立效果历史 | `A:lib/effect_history.glsl:4-8, 17-41` | Astra 已有与 TAA 解耦的效果历史（雾/反射等），含指纹失效与上一帧投影；Photon 无此抽象层（各效果各自读 colortex），但云的"代表点+像素年龄"元数据设计（`P:program/d2_clouds_upscaling.fsh:381-385`）比 Astra 的更完整。 |
| 末地天空 | `A:global/dimension/end_kerr.glsl:1-3` | Astra 是 Kerr 黑洞静态传输图集；Photon 末地只有自定义环境光/雾（见 2.5），无对应物。此项 Astra 独有，无借鉴对象。 |

（未核对项：Astra `A:global/lighting/diffuse.glsl`、`A:global/post/godrays.glsl` 本次未逐行阅读，未对其内容下结论。）

## ⑤ 借鉴可行性（许可证层面）

- **读思路、重写实现：允许**。`P:LICENSE:10` 明确允许 "Examine and learn from Photon Shaders's source code"；Astra 只要在自己的代码中独立实现相同数学/算法思想（如本文③列出的技术），不构成"再分发 Photon 的衍生作品"。
- **抄代码：高风险**。若逐行或近逐行搬运（如 atmosphere.glsl 的映射函数、c4 的 TAA 代码），Astra 整体可能被认定为 derivative work；一旦 Astra 上架 Modrinth/CurseForge 等带收益平台即触发 `P:LICENSE:14` 的书面许可要求。结论：**借鉴算法与参数思想可行；直接复制代码段需先取得 SixthSurge 书面许可或做到"思想重写、表达独立"**。另注意 Photon 自己也在 `P:include/lighting/shadows/pcss.glsl:201-205` 标注从 Complementary 借代码是 "used with permission"，说明社区惯例是取得许可后注明出处。
- 附带：Astra 的 sky_gradient/clouds_planar 已含 Complementary r5.9 的移植血统（`A:global/atmosphere/sky_gradient.glsl:5-11`），其许可证状态不在本报告范围，但沿用同一"思想重写"原则。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **TAA 四件套（③2）**——提升：全场画质（云/SSR/体素雾全靠时域稳定）；工作量：低，单 pass 局部改动。先做 (d) pixel-age 等权收敛与 (b) 软 min/max，风险最小收益最快。
2. **云时间上采样升级（③1）**——提升：把现有半分辨率云的视觉余量换成更高步数/更大细节，或直接降回 1/2 分辨率省一半云预算；工作量：中，重投影改"云层 xz 风速跟踪"即可，棋盘 4× 可作为第二阶段。
3. **SSR 读历史帧颜色（③3）**——提升：水面反射从"天穹+当帧"升级为含实体与雾的真实反射，是水面质感跃升；工作量：中，依赖 pass 顺序与历史有效性位。
4. **云影-半影联动（③6）**——提升：阴天软影的"大片感"，改动只有几行；工作量：极低。
5. **Gerstner 色散水波（③8）**——提升：水面波列方向性与近岸观感；工作量：低，但需与焦散高度场同步改（Astra 焦散直接消费 solas_water_height，替换时两者要一起动）。

暂缓：Bruneton LUT 大气（③7 的 Chapman 兜底函数除外）——管线收益/成本比在 Astra 现阶段不划算；LPV 主世界扩展——超出下界彩光现有边界。

## 附：自抽查记录（≥8 条，成稿后逐一重新打开核对）

1. `P:include/sky/atmosphere.glsl:25-26` LUT 分辨率 —— 核对一致。
2. `P:include/sky/atmosphere.glsl:492-522` Chapman 兜底 —— 核对一致（492 为函数定义行）。
3. `P:include/sky/clouds/cumulus.glsl:164-186` 8 次迭代多次散射循环 —— 核对一致（164 for，186 return）。
4. `P:program/d2_clouds_upscaling.fsh:157-179` 按层风速度重投影 —— 核对一致。
5. `P:program/c4_taa_exposure.fsh:104-125` 最近深度 5×5 十字 —— 核对一致。
6. `P:program/c4_taa_exposure.fsh:384-386` 曝光存 alpha —— 核对一致（384 if，385 赋值）。
7. `P:include/surface/water_normal.glsl:16-17` 色散 ω=√(gk) —— 核对一致。
8. `P:program/shadow.fsh:106-145` get_water_caustics 折射足迹 —— 核对一致（106 函数起，144 return）。
9. `P:include/lighting/shadows/pcss.glsl:246-248` 云影放大半影 —— 核对一致。
10. `P:include/lighting/lpv/blocklight.glsl:42-50` lightmap 自适应混合 —— 核对一致。
11. `P:program/c1_blend_layers.fsh:290-304` 折射偏移与深度守卫 —— 核对一致（290 #if 起，302-304 深度混合）。
12. `P:include/misc/purkinje_shift.glsl:3-25` —— 核对一致。
13. `A:global/water/caustics.glsl:38-52` —— 核对一致。
14. `A:program/taa_resolve.fsh:109-118` 方差裁剪与权重 —— 核对一致（1.25σ 裁剪在 111-112，权重在 118）。
15. `A:global/atmosphere/clouds_planar.glsl:68` "Thanks to SixthSurge" —— 核对一致。
16. `P:settings.glsl:194,196` 云时间上采样/累计上限 —— 核对一致。
17. `P:shaders.properties:1-4` profile 定义 —— 核对一致。
18. `P:LICENSE:3,10,12` 版权/学习权/平台限制 —— 核对一致（10 为 "Examine and learn..." 行，12 为 Modrinth/CurseForge 限制行）。
19. `A:lib/taa_state.glsl:13-35` 状态指纹函数范围 —— 核对一致。
20. `A:lib/effect_history.glsl:4-8, 17-41` 独立于 TAA 的历史 uniforms 与有效期函数 —— 核对一致。
21. `P:include/lighting/lpv/floodfill.glsl:88-112` update_lpv 至 imageStore —— 核对一致。
