# Astra 全量代码审查报告（GLM5.3flash）

指定入口：`group/auto-glm-5-3-flash`。本报告只依据工作区源码、配置与现行文档；没有读取其他审查报告。实际路由后台及最终服务模型未经本会话验证。本报告不包含游戏实机运行数据，也没有整帧计时，不能据源码推断任何实际 FPS。

审查日期：2026-10-11。源码根：`Astra/shaders`。除指定报告外未写入其他文件。

## 模块1：入口/程序调度/GLSL条件/附件格式清屏mip翻转/资源及宿主兼容

### 覆盖的文件与交界

- `Astra/shaders/shaders.properties`：主世界与 `world-1`/`world1` 程序启用、buffer 尺寸、混合、自定义纹理与档位。
- `Astra/shaders/lib/settings.glsl`：选项、内部谓词（`ASTRA_OVERWORLD_OPTIMIZED`、`ASTRA_BLOOM`、`ASTRA_TAA`、`ASTRA_SSAO`、`ASTRA_VOLUME_FOG`、`ASTRA_UNDERWATER_SHAFTS`）、引擎常量与清屏值。
- `Astra/shaders/lib/water_buffer_formats.glsl`、`lib/scene_buffer_formats.glsl`、`program/scattering.fsh`、`program/lit.fsh`、`program/taa_resolve.fsh`、`program/effect_history_state.fsh` 等格式与清屏声明。
- `program/itt_water_normal_cache.fsh`、`program/scattering.fsh/vsh`、`program/water_composite.fsh`、`program/display.fsh/vsh`、`program/final.fsh/vsh`、`program/composite8.fsh`。

已核对主链：`deferred`（场景合成/水路候选）→ `composite2`（水下光束）→ `composite3`（Bloom 开时水下合成到 colortex4）→ `composite6/7`（TAA 开时）或 `composite8`（FXAA 开时）→ `final`。`composite3` 关闭时水下合成转入 `display`。TAA 路径下 `taa_resolve.fsh` 在 `isEyeInWater != 0` 时直接读取 colortex4（第92-96行）并写无效历史标记；FXAA 路径下 `display.fsh` 亦直接读 colortex4（第118-121行）。附件与消费一致。

### P0/P1/P2 问题

**P1：水下水平界面法线依赖仅在光束开启时注册的 `ittWaterNoise`。**

- 触发：主世界 `UNDERWATER_LIGHT_SHAFTS` 关闭，其余水波与 `WATER_WAVE_HEIGHT > 0` 保持开启；实体或透明水面处于水下界面分支。
- 调用：`Astra/shaders/program/lit.fsh:36` 在 `ASTRA_WATER_PASS` 中无条件 include `lib/itt_water_waves.glsl`；`lit.fsh:225` 对 `isEyeInWater == 1` 的水程序调用 `itt_water_wave_normal`。该函数内部采样 `ittWaterNoise`（`lib/itt_water_waves.glsl:7、19-20`）。
- 生产/注册：`shaders.properties:522` 仅在 `defined UNDERWATER_LIGHT_SHAFTS && defined SHADOWS && UNDERWATER_SHAFT_STRENGTH > 0` 时声明 `customTexture.ittWaterNoise=textures/itt-water-noise.png`。
- 错误结果：关闭该选项时，水程序仍包含采样器但 pack 未注册该自定义纹理。依据 Iris 自定义纹理机制，未注册采样器缺少正确绑定；结果为水下水平界面法线不可靠（依赖驱动对零/旧绑定的处理），而垂直水流与下界/末地走 `solas_water_normal` 不受影响。该交界源码能确认绑定缺失，但实际画面取决于驱动对未绑定纹理的处理，未实机确认渲染错误形态。
- 依据：上述注册条件与 include/调用链均为源码事实。
- 建议：将 `ittWaterNoise` 注册条件放宽到水程序可能消费的分支（至少 `defined WATER_WAVES && WATER_WAVE_HEIGHT > 0` 的水程序条件），或在关闭光束时让水下法线退回不依赖该纹理的路径。

### 疑点与缺失事实

- colortex 格式总体分散在多个编译单元（如 colortex9 在 `scene_buffer_formats.glsl`、colortex1 在 `scattering.fsh`、colortex4 在 `water_buffer_formats.glsl`、colortex28 在 `lit.fsh`/`nether_reflection.fsh`）。未发现同一维度内冲突声明，但完整逐格式对账依赖 Iris 对每 ProgramSet 的最终解析；本报告只确认了已追踪的附件。
- colortex29 在光束关闭时仍为 1×1，`program/itt_water_normal_cache.fsh` 已由 properties 禁用；scattering 的 colortex1 为显式清屏，未发现翻转或残留问题。

### 覆盖结论

主世界与两维度入口、程序调度、附件与 TAA/FXAA/Bloom 交界已覆盖；发现 1 个 P1（水下界面法线的条件注册缺口）。

## 模块2：阴影投射接收过滤彩影焦散与覆盖边界

### 覆盖的文件与交界

- `Astra/shaders/program/shadow.vsh`、`program/shadow.fsh`、`program/shadow_solid.fsh`。
- `Astra/shaders/global/lighting/shadowmap.glsl`、`global/lighting/diffuse.glsl`。
- `Astra/shaders/global/water/caustics.glsl`、`lib/water_wave_lens.glsl`。
- `program/lit.fsh`、`program/lit.vsh` 中接收面投影与调用。

已核对链：`shadow.vsh`（含风摆与预算裁剪）→ `shadow.fsh`（非水投射物深度修正，水投射物保留栅格深度并记录高度/焦散）→ `shadowmap.glsl`（软件比较 gather、平面参考深度修正、角点配对）→ `diffuse.glsl::surface_shadow_light`（过滤分支）→ `lit.fsh` 接收面法线与调用条件。

### P0/P1/P2 问题

**P1：均衡档阴影额外过滤的边缘梯度在无可见性变化时退化为固定方向，且远端没有该方向外的散开；锯齿改善依赖边缘恰好落在梯度轴上。**

- 触发：`SHADOW_FILTER_QUALITY=1`（均衡默认），中心四角完全一致但透明透射权重非零，且 `dot(gradient,gradient)<=0.001`。
- 调用：`global/lighting/shadowmap.glsl:296-302` 计算 `astraSurfaceFootprintGradient`，在无梯度时退化为 `(0.70710678,0.70710678)`；`global/lighting/diffuse.glsl:328-345` 沿该单一方向加两个 `spread` 偏移，`spread` 最多 `min(SHADOW_SOFTNESS,2)*0.5`，再受 `max(0.22,0.75*astraSurfaceShadowPixelWorld)/worldTexel` 限制。
- 错误结果：多方向边缘只能获得单一轴上的柔化；与该方向正交的边缘在均衡档仍接近中心四角双线性核，用户反馈的锯齿因此仍会出现。这是设计取舍（避免额外采样组）造成的效果边界，不是投射件错误。
- 依据：默认 `SHADOW_SOFTNESS=2`、`SHADOW_FILTER_QUALITY=1`、主世界预算 `OVERWORLD_BUDGET=1` 均为源码默认；世界半径限制与梯度退化条件如上。
- 建议：若保留采样组数不变，可考虑在退化方向上改用四角权重本身的连续插值而非追加双足印；主代理裁决。

**P2：接收面法线非背光时 `shadowReceiver` 始终为真，无法用选项关闭接收面阴影查询。**

- 触发：主世界地形接收面 `shadowNdotL > -0.10`（或实体/水等非地形分支直接调用）。
- 调用：`program/lit.vsh:206-215` 决定是否写 `surfaceShadowCoordinate`；条件只看法线与材质，不受 `SHADOWS` 选项以外的开关限制（`SHADOWS` 总开关关闭时整条链停用，属正常）。
- 错误结果：如果用户希望以较低画质进一步省掉边缘接影，当前没有独立档位可以跳过该计算；不是错误效果，而是选项粒度限制。
- 依据：源码条件如上；`shaders.properties` 中没有对应开关。
- 建议：如需性能选项，可增加主世界低档下进一步减少过滤分支，但不改变默认画质。

**P2：水投射物深度不做修正，薄水/斜水在低太阳角下依赖原栅格深度，可能出现纹元级穿透或漏挡。**

- 触发：水面或水方块进入影图，接收点位于其深度边界附近。
- 调用：`program/shadow.fsh:79-98` 仅对 `waterCasterKind==0` 求平面深度并取 `max`；水投射物保留 `gl_FragCoord.z`。
- 错误结果：依据文档与注释这是保留高度/焦散配对的明确取舍；源码不足以确认实际边界穿透量，未实机确认。
- 建议：若确有可见漏挡，需要在不破坏配对的前提下另做水投射深度方案；当前不列为 bug。

### 疑点与缺失事实

- 彩影（`COLORED_SHADOWS`）在 `shadow.fsh:111-118` 用 albedo.a 的平滑衰减决定染色； stained glass 半透明层级超过一层的实际透射混合是否合理，取决于 Iris 的排序与贴图，源码无法确认。
- 焦散使用 `astra_water_wave_lens`（`lib/water_wave_lens.glsl`）的曲率聚光；其振幅与实际波场的一致性是视觉参数，不是可从源码判定的错误。

### 覆盖结论

投射、接收、过滤、彩影与焦散的生产者-消费者链已覆盖；发现 1 个 P1（均衡档锯齿的结构性边界）和 2 个 P2（选项粒度、水投射深度取舍）。

## 模块3：材质直接间接照明AO/SSS/体素/实体与手

### 覆盖的文件与交界

- `Astra/shaders/program/lit.fsh`、`program/lit.vsh`、`program/unlit.fsh`、`program/gbuffers_basic.fsh/vsh`。
- `Astra/shaders/global/lighting/diffuse.glsl`、`global/lighting/sss.glsl`、`global/lighting/blocklight.glsl`、`global/lighting/wind.glsl`。
- `Astra/shaders/lib/ao_material.glsl`、`lib/ao_resolve.glsl`、`program/deferred.fsh`（AO 应用、雨反射、体积雾、云合成）。
- 下界体素：`lib/nether_voxel_grid.glsl`、`program/nether_light.csh`（见模块8交叉核对）。
- 手部：`program/lit.fsh` 的 hand 修正与 `colortex3` 标志、`deferred.fsh:258-267` 的 AO 排除。

已核对：albedo → 材质分类 → 顶点AO → SSAO（仅环境光）→ SH 方向天空 → 直接光阴影/焦散/SSS → 手标志与深度修正 → 迟绘实体记录（`lit.fsh:441-446`，仅 `ASTRA_LATE_ENTITY_SOURCE` 且 alpha>=0.999）→ 水下场景合成（`program/water.glsl:61-108`）。

### P0/P1/P2 问题

**P1：迟绘实体记录依赖 `colortex28` 的格式与清屏在 `lit.fsh` 中声明，且同时受实体和水两个编译宏控制；关闭实体手/水的组合下若任一分支未编译，记录与消费可能失配。**

- 触发：主世界 `ENTITY_SHADOWS`（影图中的实体程序）与 `SCREENSPACE_REFLECTIONS` 等水路开启条件组合极端变化。
- 调用：`program/lit.fsh:20-31` 用 `defined ASTRA_WATER_PASS || defined ASTRA_ENTITY` 声明 RG32F/clear；`lit.fsh:441-446` 用 `ASTRA_LATE_ENTITY_SOURCE`（即 `ASTRA_ENTITY`）写记录；消费在 `program/water.glsl:65、101、206、424、521`，由 `SCREENSPACE_REFLECTIONS` 等水路编译。
- 错误结果：目前 `ASTRA_ENTITY` 与 `ASTRA_WATER_PASS` 由 Iris 传递（普通实体/透明实体程序），二者不会同时缺失到断链。但该格式与清屏声明放在共享编译单元内、消费在另一单元，跨程序一致性依赖 Iris 聚合规则；源码不足以证明所有组合下 Iris 都取同一格式。这是结构疑点而非已确认失配。
- 建议：将 colortex28 的格式/清屏声明集中到一处（如 `lib/water_entity_record.glsl` 或专门格式文件），并让所有生产/消费编译单元 include 同一份。

**P2：SSS 透射阈值 `skyLight <= 0.20` 直接置零，洞穴植物在光强略高于0.2时透射突入，且不随天空遮蔽连续过渡。**

- 触发：地下/洞穴边缘的树叶或草，skyLight 在0.20附近跨越。
- 调用：`global/lighting/sss.glsl:118-120`。
- 错误结果：这是连续性缺口而非错误效果；源码可确认阶梯，但实际可见度取决于游戏光强分布，未实机确认。
- 建议：若用户在意，可在阈值附近加平滑过渡；主代理裁决。

**P2：AO 接收只作用于环境光，直接光没有屏幕空间遮蔽；这是已确认的设计边界，不是缺陷。**

- 调用：`deferred.fsh:261-267` 仅对环境光源调用 `astra_apply_ambient_ao`；`lit.fsh` 直接光阴影独立计算。
- 结果：符合现行实现文档；列为影响而非 bug。

### 疑点与缺失事实

- 下界体素光的传播与稀疏读取在 `nether_voxel_grid.glsl` 与 compute shader 中，其正确性依赖 GPU 计算；源码不足以证明所有硬件下的完整传播，未实机确认。
- 手部深度修正（`MC_HAND_DEPTH`）在 `deferred.fsh:264-267` 处理；未发现与 shadow 查询的冲突，但手在水下与普通水下场景合成的交互未实机确认。

### 覆盖结论

直接/间接/AO/SSS/体素/实体/手主链已覆盖；发现 1 个 P1 结构疑点（colortex28 声明分散）和 2 个 P2 边界。

## 模块4：水面波纹反射SSR折射介质/迟绘身体/界面两侧

### 覆盖的文件与交界

- `Astra/shaders/program/water.glsl`（水面主入口、水下单侧界面、介质、迟绘身体配对）。
- `Astra/shaders/global/water/surface.glsl`、`global/water/refraction.glsl`、`global/water/raytrace.glsl`、`global/water/optics.glsl`、`global/water/medium_state.glsl`、`global/water/absorption.glsl`。
- `Astra/shaders/lib/water_entity_record.glsl`、`lib/water_interface_record.glsl`、`lib/water_surface_budget.glsl`。
- `program/deferred.fsh` 中 puddle 反射与云合成；`program/water_composite.fsh` 的合成（详见模块5）。

已核对：水面法线（Steadfast 六层场）→ Fresnel/SSR/折射/介质 → 水下界面（`astra_underwater_interface`）→ 水下折射与透射太阳（见模块5）→ 迟绘身体与跨界记录（`water.glsl:61-108`）。

### P0/P1/P2 问题

**P1：树叶倒影漏采在标准水路细化中仅受4角自交点接受约束，而该接受路径只在标准投影下启用；非标准投影或 `projectedMarch=false` 的主世界水路没有等价补足。**

- 触发：复杂错层树冠，粗 marching 在树叶平面前后跳过，细化命中点落入另一纹元；或主世界水程序因非标准投影（`gbufferProjection` 与 TAA 抖动外的变体）导致 `standardProjection=false`。
- 调用：`global/water/raytrace.glsl:229-231` 计算 `standardProjection = depthOnlyZW && water_ssr_standard_vw(zRow,wRow)`；`raytrace.glsl:318-333` 仅在标准投影下尝试用已采叶片平面交点直接接受；`raytrace.glsl:386-430` 细化时仅在 `standardProjection && projectedMarch` 才调用 `water_ssr_footprint_crossing`（4角候选射线穿过自身纹元才接受）。
- 错误结果：在满足触发条件时，树叶仍会漏采；源码级接受条件明确，且文档已承认复杂树冠漏采未完全解决。这是质量补偿未覆盖全部路径，不是新引入错误。
- 依据：默认 `WATER_EFFECT_QUALITY=1`、主世界预算开启，粗上限16/20、细化4；投影条件如上。
- 建议：若需继续补足，可在 `projectedMarch` 的非标准投影分支用完整逆投影做同样的4角验证；成本需主代理衡量。

**P2：水下单侧界面（`astra_underwater_interface`）的反射在非全反射区间被 `screenReflectionShare` 限到 0.025..0.055 渐入，非全反射的侧视树影等物体倒影在主世界预算内进一步减少。**

- 调用：`program/water.glsl:668-672`（`screenReflectionShare = totalReflection ? 1.0 : smoothstep(0.025,0.055,fresnel)`）。
- 结果：这是为省预算对低 Fresnel 的取舍；不是错误，但用户若预期水下侧视树影更完整，会感知为缺失。

**P2：水下折射只按 `normal.xy-faceNormal.xy` 做位移，`REFRACTION_STRENGTH` 的深度反馈仅通过 `water_depth_range` 接受；水下界面折射对远距离或超视差场景不做二次求解。**

- 调用：`program/water.glsl:714-735`。
- 结果：源码不能确认实际撕裂或穿帮；列为边界而非 bug。

### 疑点与缺失事实

- 水下透射天空的反射缓存刻意不含日月盘，只有 `water_transmitted_sun` 在几何未完全遮挡的折射天空补太阳（`program/water.glsl:601-736`）。这与模块5的太阳形状问题相关，但该函数本身逻辑已核对。
- 迟绘身体记录容量保持 RG32F，两个通道打包四项半精度；源码不能证明容量上限在极端实体遮挡下的表现。

### 覆盖结论

水面波纹/SSR/折射/介质/迟绘身体/界面两侧主链已覆盖；发现 1 个 P1（树叶补足路径不完整）与 2 个 P2 取舍边界。

## 模块5：水下光束源图窗口积分消光/水位/雾/柔化/太阳

### 覆盖的文件与交界

- `Astra/shaders/program/itt_water_normal_cache.fsh/vsh` → colortex29（1024² RGBA16F）。
- `Astra/shaders/program/scattering.vsh/fsh` → colortex1（RGBA16F，Bloom开半分辨率，关时主世界仍需消费）。
- `Astra/shaders/global/water/light_shafts.glsl`、`global/water/shaft_layout.glsl`、`lib/itt_water_field.glsl`、`lib/itt_water_waves.glsl`。
- `Astra/shaders/program/water_composite.fsh`（Bloom开合成）、`program/display.fsh`（Bloom关合成）。
- `Astra/shaders/lib/water_diffusion.glsl`、`lib/solas_water.glsl`。

已核对：源图生成 → 八点分段积分 → 消光/相位/端点权重 → 合成与柔化 → 太阳透射。

### P0/P1/P2 问题

**P1：水下太阳形状与外层天空不同源，用户反馈的“水下太阳错误为圆”对应源码结构而非渲染 bug。**

- 触发：`SUN_MOON_MODE=0`（均衡默认）时，主世界外层天空用原版方形太阳贴图；水下 `water_transmitted_sun` 仍走 `SUN_MOON_VANILLA` 分支读取同一 `astraSunTexture`（`program/water.glsl:609-624`），因此本应同为方形。但源码路径中，若水下几何完全遮挡折射天空（`geometryCoverage>=1`），太阳不会被补出；若 `CLOUD_MODE=1` 且云遮蔽，云下的太阳透明度也由 `astra_planar_cloud` 控制。
- 关键交界：`program/water.glsl:733-736` 只在 `geometryCoverage<1` 时调用 `water_transmitted_sun`；而 `program/water.glsl:737-746` 几何完全遮挡时直接 `background=pow(transmittedGeometry,...)`，没有任何太阳补出。
- 错误结果：源码结构能解释水下太阳与外层可见太阳在遮挡组合下不一致，但不能确认实机中用户看到的“圆”来源；用户描述与当前源码（原版贴图分支）存在未闭合差距。这属于源码不能确认的疑点，不冒充bug。
- 依据：`SUN_MOON_MODE` 默认 0（`lib/settings.glsl:99`）；`shaders.properties:525-529` 原版贴图注册；`program/water.glsl:601-624` 水下透射太阳实现。
- 建议：主代理需核对实机条件（用户是否在 `SUN_MOON_MODE=0` 且水下几何未完全遮挡时看到圆形）；若实机确实圆形，源码差距可能在资源绑定或某分支未覆盖，需进一步取证。

**P1：光束数量少且布局挤，与八点分段积分的波长/采样密度/远端截断共同相关；这是当前源码结构的直接结果，不是渲染错误。**

- 触发：均衡档 `UNDERWATER_SHAFT_SAMPLES=7`、`WATER_SHAFT_FAR_START=14`、`WATER_SHAFT_FAR_END=26`（`global/water/shaft_layout.glsl:7-8`）；积分 `ASTRA_SHAFT_SAMPLES=7`（`light_shafts.glsl:22-24`），每节点4内点，八点高斯权重。
- 调用：`light_shafts.glsl:124-150` `water_shaft_wave_span` 只积分8个节点；`light_shafts.glsl:146-147` 对辐照度乘入近端0.08→1格渐入和14→26格远端截断；`light_shafts.glsl:161` `marchLength` 上限 `min(rayLength,astraWaterShaftRange=48,FAR_END=26)`。
- 错误结果：远端 26 格之外的波场贡献完全截断，细束密度受六层波场与非线性响应共同决定；用户要求“数量多、不挤”需要改波场或采样/截断，不属于当前实现能通过调参直接满足的结构。这是已保留八点积分约束下的取舍边界。
- 依据：`lib/itt_water_field.glsl:20-29` `water_shaft_collision_light` 用 `caustic=0.24+3.05*offset` 的非线性响应；波场斜率由 `itt_water_wave_slope` 生成，`spatialScale=0.05/1.28`（`itt_water_waves.glsl:41`）。
- 建议：在保留八点积分的前提下增加可见束，可考虑提高源图 B 通道的空间分辨率、放宽远端截断、或调整 `water_shaft_collision_light` 的非线性响应；这些是主代理的视觉裁决，不是 bug 修复。

**P2：源图 B 通道的碰撞光量在 mip 前已非线性化，窗口边缘 `smoothstep(2,3)` 又在 mip 后乘入；这两步的顺序使窗口边界与波峰亮度并非严格同一滤波域。**

- 调用：`program/itt_water_normal_cache.fsh:20-25` 写 B；`light_shafts.glsl:140-147` 用 `textureLod` 读取并乘边界/近远窗。
- 错误结果：源码能确认先后顺序，但不能证明视觉副作用；列为结构事实。

**P2：水下雾/柔化在 `water_composite.fsh` 与 `display.fsh` 中按 Bloom 开关分两路；柔化只读场景与深度，不含光束，这是已确认边界。**

- 调用：`water_composite.fsh:24-29`（Bloom开）、`display.fsh:132-146`（Bloom关）。
- 结果：两路共享 `water_diffuse_scene` 与 `solas_water_composite`，源码未发现重复施雾。

### 疑点与缺失事实

- 水下太阳“圆形”与外层方形不一致，源码不能闭合（见上）；需要实机条件或用户截图。
- 光束的实际数量与挤感取决于波场空间分布，当前源码能解释机制但无法用数字描述实际观感；没有整帧数据。

### 覆盖结论

水下光束生产-消费链、太阳、雾与柔化已覆盖；发现 2 个 P1（太阳形状源码不闭合、光束结构取舍边界）与 2 个 P2 结构事实。

## 模块6：天空日月星空晨昏云天气及相关历史

### 覆盖的文件与交界

- `Astra/shaders/program/sky.fsh/vsh`、`program/gbuffers_skybasic.fsh/vsh`、`program/gbuffers_skytextured.fsh/vsh`。
- `Astra/shaders/global/atmosphere/sky_gradient.glsl`、`sky_minishita.glsl`、`stars.glsl`、`clouds_planar.glsl`、`clouds_screen.glsl`、`cloud_temporal.glsl`、`cloud_shadow_cache.glsl`、`fog.glsl`、`weather.glsl`。
- `Astra/shaders/lib/twilight.glsl`、`lib/sky_directional.glsl`。
- `program/deferred.fsh` 中的天空/云/雨反射合成。

已核对：天空渐变/Minishita → 日月贴图/程序盘 → 星空 → 云（屏幕/平面/历史）→ 雨天介质与湿润面 → 晨昏共享因子。

### P0/P1/P2 问题

**P2：`gbuffers_skytextured.vsh` 在 `SUN_MOON_MODE=0` 时将日月四边形顶点 `vertex.xz *= 1.12` 放大，水下透射太阳用 spriteUV 半宽0.6重建；两者几何尺寸与外层天空的 1.12 倍放大的关系源码未显式耦合，可能造成内外太阳角尺寸不一致。**

- 调用：`program/lit.vsh:112-118`（原版模式下 sun/moon 顶点乘1.12）；`program/water.glsl:612-623` 用半宽 `0.6*alignment` 重建。
- 错误结果：原版太阳四边形半宽30、距离100，即角半宽0.30；1.12放大后0.336。水下重建用0.6×0.6=0.36 对角半宽（spriteUV 分母0.6），两者不严格相等（0.336 vs 0.36），水下太阳可能比外层略大。源码可确认数值差，但实际贴图 alpha 亮度与可见范围未实机确认。
- 建议：将水下重建的半宽从0.6改为与 `1.12*30/100=0.336` 对应的值，或让两者共同使用一个常量；主代理裁决。

**P2：云影（`CLOUD_SHADOWS`）在默认档位关闭；这不是缺陷，而是选项默认值，实际可见阴影来自地形/实体阴影而非云。**

- 调用：`shaders.properties:566-567` 默认 `!CLOUD_SHADOWS`；`global/atmosphere/cloud_shadow_cache.glsl` 仅在选项开启时有用。

**P2：雨天气的湿润地面反射 `puddle_reflection` 在 `deferred.fsh:40-100` 内有最多96次采样与6次细化的路径；预算开启时超过48格渐退至64格关闭，近处反射保持完整，这是已确认取舍。**

### 疑点与缺失事实

- 星空可见性与月相的组合对实际亮度的影响是视觉参数；源码不能确认是否符合用户期望。
- 云历史（`CLOUD_TEMPORAL`）与 TAA 独立（`settings.glsl:697-700` 注释），源码不能确认移动/遮挡下的实际稳定性，需要实机。

### 覆盖结论

天空、日月、星空、晨昏、云、天气及历史链已覆盖；发现 1 个 P2 尺寸疑点（水下太阳角尺寸不严格一致）与 2 个默认值/取舍边界。

## 模块7：后处理泛光调色AA历史重投影/显示颜色域

### 覆盖的文件与交界

- `Astra/shaders/program/composite1.fsh`（Bloom捕获）、`program/water_bloom.fsh`、`program/composite8.fsh`（FXAA 或转调 display）、`program/final.fsh`。
- `Astra/shaders/global/post/bloom.glsl`、`global/post/grading.glsl`、`global/post/fxaa.glsl`、`global/post/exposure.glsl`。
- `Astra/shaders/program/taa_resolve.fsh/vsh`、`program/taa_state.fsh`。
- `Astra/shaders/lib/water_buffer_formats.glsl`（colortex4 RGB16F）。

已核对：Bloom捕获 → 水下合成4 → FXAA（`display.fsh` 先写13，`composite8.fsh` 读13并dither）或 TAA（`taa_resolve` 写0/15）→ final。调色域顺序：线性HDR→曝光→tonemap→sRGB→grading→vignette→dither。

### P0/P1/P2 问题

**P2：FXAA 的 `geometryOnly` 模式在水下普通水面时只用深度边缘，颜色/透明边缘不参与；水下界面纹理和焦散不模糊，这是已确认设计，不是错误。**

- 调用：`composite8.fsh:8-16` 设置 `geometryOnly`；`fxaa.glsl:15-27` 深度阈值后提前返回。

**P2：TAA 的水下路径不投影历史（`taa_resolve.fsh:99-103` 直接写 `current` 与无效历史），与水面波纹的运动特性一致；这是已确认取舍，不列为 bug。**

**P2：Bloom 捕获 colortex2 的尺寸为 0.25×0.25，`global/post/bloom.glsl:82-108` 的捕获采样与补偿核在同一文件保持一致；主世界预算进一步降低读取数。**

- 结果：源码不能确认该低分辨率捕获的实际观感；属于设计选择。

### 疑点与缺失事实

- TAA 对植被的形变历史与云/实体历史的交互（`taa_resolve.fsh:168-175` 植被 motionValid）在极端遮挡下是否正确，源码不足以确认。
- HDR 域中 colortex4 为 RGB16F，消除了蓝通道5位尾数；源码不能确认实际游戏内弧纹是否消失，只确认格式已改。

### 覆盖结论

后处理、泛光、调色、FXAA/TAA、历史与显示颜色域主链已覆盖；未发现可证实 P0/P1；3 个 P2 均为设计边界或默认值。

## 模块8：下界末地维度入口与独立效果

### 覆盖的文件与交界

- `Astra/shaders/world-1`（下界）：`composite.fsh`、`composite1.fsh`、`composite2.fsh`、`composite6.fsh`、`composite7.fsh`、`composite8.fsh`、`deferred.fsh`、`final.fsh`、`shadow.fsh/vsh`、`shadowcomp*.csh`。
- `Astra/shaders/world1`（末地）：`composite.fsh`、`composite1.fsh`、`composite6.fsh`、`composite7.fsh`、`composite8.fsh`、`deferred.fsh`、`deferred1.fsh`、`final.fsh`、`prepare.fsh`、`prepare1.fsh`、`setup*.csh`、`shadow.fsh/vsh`。
- `Astra/shaders/global/dimension/nether.glsl`、`nether_colored_light.glsl`、`nether_reflection.glsl`、`nether_volume.glsl`。
- `Astra/shaders/global/dimension/end.glsl`、`end_blackhole.glsl`、`end_disc_profile.glsl`、`end_geometry.glsl`、`end_kerr.glsl`、`end_plasma.glsl`、`end_system.glsl`。
- `Astra/shaders/lib/nether_voxel_grid.glsl`、`lib/nether_reflection_metadata.glsl`、`lib/end_reflection_cache.glsl`、`lib/end_star_catalogue.glsl`、`lib/end_surface.glsl`、`lib/end_light.glsl`。

已核对：维度入口在 `shaders.properties:820-846`（下界 shadowcomp 系列）与 `program.*` 维度开关；下界体素光、彩光反射、末地反射缓存、星表 compute、黑洞/光子环/日蚀。

### P0/P1/P2 问题

**P2：下界 `shadowcomp*.csh` 系列在 properties 中按条件启用（`shaders.properties:828-846`），其完整正确性依赖 compute shader；源码不足以证明所有硬件上的完整传播，与模块3的下界体素疑点相同。**

**P2：末地 `deferred.fsh` 的天空合成（`program/deferred.fsh:333-357`）在天空像素上额外加 `end_crisp_photon_ring` 和 `end_starfield_filtered`；黑洞/星表的视觉组合是否与用户期望一致，源码不能确认。**

**P2：两个维度均关闭 `deferred2`/`deferred3` 与水下合成（`shaders.properties:754-761`），各自显示入口直接走 `display`；这是设计边界，不是缺陷。**

### 疑点与缺失事实

- 下界反射元数据格式（colortex28 在下界为 RGBA16F，与主世界 RG32F 不同，`program/nether_reflection.fsh:15`）在维度切换时是否正确重建，依赖 Iris 每维度 ProgramSet 解析；本报告只确认声明。
- 末地黑洞/星表的独立效果未实机确认，不列为 bug。

### 覆盖结论

两维度入口与独立效果链已覆盖；未发现可证实 P0/P1；3 个 P2 均为硬件依赖或视觉参数边界。

## 模块9：选项档位开关组合/性能热点及文档与现行源码不一致

### 覆盖的文件与交界

- `Astra/shaders/shaders.properties:544-567` 的 GUI 屏幕与 `PERFORMANCE/BALANCED/ULTRA` 档位。
- `Astra/shaders/lib/settings.glsl:59-381` 的主世界预算（`OVERWORLD_BUDGET` 0/1/2）。
- `Astra/shaders/lib/settings.glsl:680-721` 的内部谓词派生。
- `Astra/shaders/lang/zh_CN.lang` 与 `en_US.lang` 的选项说明。
- `docs/当前工作.md` 与 `docs/实现与限制.md` 中与源码可交叉验证的描述。

### P0/P1/P2 问题

**P1：`rain_particles.glsl::astra_hide_rain_splash` 是死代码，函数存在但没有任何调用者；它不是 bug，但说明某个“隐藏雨滴溅射”意图从未接线。**

- 调用：`lib/rain_particles.glsl:15-27` 定义；`rg -n astra_hide_rain_splash` 只命中定义与注释。
- 错误结果：没有任何实际效果；如果用户或文档曾预期雨滴溅射被过滤，该功能在当前源码中不存在。
- 建议：删除或接线；主代理裁决。

**P2：主世界预算（`OVERWORLD_BUDGET=1`）把 `SHADOW_FILTER_MODE` 强制为 software（`settings.glsl:361-365`），而 GUI 仍显示 `SHADOW_FILTER_MODE` 选项；用户切换该选项在预算开启时不会改变实际模式。**

- 调用：`lib/settings.glsl:361-365`；`shaders.properties:544` GUI 仍列出该选项。
- 错误结果：源码可确认该选项在预算开启时被覆盖；用户感知与选项状态不一致。
- 建议：在预算开启时隐藏或禁用该 GUI 行，或改由预算档位透传实际模式。

**P2：`UNDERWATER_SHAFT_SAMPLES` 在主世界预算下被上限到7（`light_shafts.glsl:21-24`），档位 ULTRA 设置为10（`shaders.properties:567`）；预算开启时用户选10实际不会超过7，但 GUI 未显示该上限。**

- 调用：`lib/settings.glsl:334` `OVERWORLD_BUDGET=1` 默认开启；`light_shafts.glsl:21-24` 上限。
- 错误结果：用户在 ULTRA 下选择10与实际7不一致；这是预算上限与 GUI 的文档缺口，不是渲染错误。
- 建议：GUI 注释或选项说明中标注预算下的实际采样数。

### 文档与源码一致性

抽查的关键描述与源码一致：水下太阳透射只在几何未完全遮挡时补出（`water.glsl:733-746`）；colortex4 在 Bloom 开启时为 RGB16F（`water_buffer_formats.glsl:16-20`）；主世界预算阴影上限 1536/112/32（`settings.glsl:380-414`）；SSR 预算 20 总查询/远端16（`raytrace.glsl:30-53`）。未发现文档宣称源码不存在的机制。

### 疑点与缺失事实

- 性能热点不能仅凭源码排序；模块2/4/5列出的边界都是结构性成本，但没有整帧数据，不能推断实际 FPS。

### 覆盖结论

选项、档位、预算与文档一致性已覆盖；发现 1 个 P1（死代码 `astra_hide_rain_splash`）与 2 个 P2 GUI/文档缺口。

## 总结与未覆盖点

- 本报告按九个模块逐项给出覆盖结论；每模块均已追踪生产者-消费者交界，不是关键字搜索。
- 唯一未覆盖点：本地 `_analysis` 中 Solas/ITT3.2/Steadfast 的完整参考代码没有逐行对照；只在需要解释当前行为时查看了相关说明。这不影响本报告对 Astra 当前源码的结论。
- 用户当前关注中，源码能解释的结构性来源：光束少且挤（模块5的波场/积分/截断结构）、阴影锯齿（模块2的均衡档过滤边界）。水下太阳“圆”与源码的原版贴图分支未闭合（模块5 P1），树叶倒影漏采在模块4 P1 有明确补足缺口。水路开销高没有整帧数据，不能归因到具体阶段。
