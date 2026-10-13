# Astra 光影全量代码审查报告

指定模型入口：workbuddy/space-bunny（用户称 space-bunny）

审查范围：`C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发` 全仓库活跃渲染链与配置资源。按生产者→附件/输入→消费者与配置条件逐模块核对，覆盖本轮已改动文件与历史存量，不限 git diff。未读取其他审查者报告，未运行游戏、未安装工具、未做 Git 写操作。参考 `_analysis` 中 Solas/ITT3.2/Steadfast 的落点时只按需定位，不采用其结论。

已确认本轮主代理在审查期间修正的三处交界，本文按**当前实际文件**独立核对，均记为已处理：
- `Astra/shaders/shaders.properties:521-523` ITT 噪声注册条件已独立为 `defined WATER_WAVES || (defined UNDERWATER_LIGHT_SHAFTS && defined SHADOWS && UNDERWATER_SHAFT_STRENGTH > 0)`，不再被水面路径单方面门控；`:526-532` 原版太阳资源注册已从该嵌套块中移出。
- `Astra/shaders/program/water.glsl:616` 原版水下太阳 spriteUV 分母为 `0.672*alignment`，对应 `program/lit.vsh:116` 的 `vertex.xz *= 1.12`（30→33.6 半宽），内外角尺寸一致。
- `Astra/shaders/program/water.glsl:633` 平面云透射已乘 `astra_planar_cloud(direction).a`；`Astra/shaders/global/water/raytrace.glsl:257-260` 远侧 12 上限条件为 `(surfaceBudget || underwater)`，湿润地形（非 `surfaceBudget`）仍为 8。

未覆盖点：没有任何整帧 GPU/FPS 实测数据，本报告不推断 1080p 平均 144 FPS 是否达成；所有性能判断只到源码成本结构与已记录的独立分项数字。

---

## 模块 1：入口／程序调度／GLSL 条件／附件格式清屏 mip 翻转／资源及宿主兼容

覆盖：`Astra/shaders/shaders.properties`（buffer 尺度 37-255、pass 使能 296-513、customTexture 514-536、profile 564-567）、`program/scattering.vsh/.fsh`、`program/composite.vsh`、`program/itt_water_normal_cache.vsh/.fsh`、`program/water_composite.vsh/.fsh`、`composite2.vsh`、`composite3.vsh`、`prepare4.fsh`、`program/display.fsh`、`program/taa_resolve.fsh`、`program/final.fsh`、`lib/settings.glsl` 预处理器段、`block.properties`、`world-1/*` 与 `world1/*` 薄入口、`lib/transforms.glsl`。

本模块未发现可证实的 P0/P1。

核对通过的关键交界：
- mip 生成时序：`shaders.properties:203` 注释与 `program/scattering.fsh:40` 的 `#define ASTRA_SHAFT_MARCH_PASS` 配合 `global/water/light_shafts.glsl:68-69` 的 `colortex29MipmapEnabled = true` 声明保留消费端 mip，符合 Iris `stageReadsFromAlt → setupMipmapping → setupState` 顺序。
- 清屏与元数据：`prepare4.fsh` → `itt_water_normal_cache.fsh:13` `colortex29Clear = false`，与 `:21-24` 的 0 号像素写窗口元数据配套；`light_shafts.glsl:144-145` 的边缘渐弱保证过滤范围外不会读到 0 号元数据（`smoothstep(2.0,3.0,min(border.x,border.y))`，而 `water_shaft_wave_segment:87-89` 把区间裁到 `[2, EXTENT-2]`，两者一致）。
- `shaders.properties:213-217` 的 `prepare5.enabled=false` 与已删除的 `global/water/shaft_history.glsl` 一致，无悬挂采样器。
- 薄入口版本：`world-1/shadow.vsh:1` 用 `#version 430 compatibility`（`uimage3D` + `imageAtomicMax` 需 420+），其余薄入口为 400，边界正确。
- 空气侧光束剔除：`program/scattering.vsh:28-35` 在无空气消费者时把四边形裁到裁剪空间外，配合 `scattering.fsh:83-84` 的 `colortex1Clear = true` 保证附件中性。

P2：`program/scattering.fsh:88-108` 与 `:109-121` 的早退结构中，`:90` 的 `if (isEyeInWater == 1)` 在 `ASTRA_UNDERWATER_SHAFTS` 下恒真（`:88` 已保证 `isEyeInWater != 0 && !thin`，GLSL 中 `isEyeInWater` 只取 0/1），是一次多余的 uniform 比较。不改变结果，仅为冗余。

疑点（源码不足以判定为 bug）：
- `shaders.properties:70-91` 中 `colortex12` 的 `#if/#elif/#else` 结构里，`OVERWORLD_BUDGET > 0` 分支定为 65×65（云历史网格），`:181-182` 的 `colortex24/25` 同为 0.25。两者受同一条件控制，看起来自洽，但缺 Iris 实际分配尺寸的运行证据。

---

## 模块 2：阴影投射接收过滤彩影焦散与覆盖边界

覆盖：`program/shadow.vsh`（220 行）、`program/shadow.fsh`（149 行）、`global/lighting/shadowmap.glsl`（437 行）、`global/lighting/diffuse.glsl:277-399`、`global/water/caustics.glsl`、`lib/water_wave_lens.glsl`、`program/lit.vsh:216`、`program/lit.fsh:161-166`、`shaders.properties:296-372`。

本模块未发现可证实的 P0/P1。

用户关注的"阴影边缘锯齿"对应的现行实现（`diffuse.glsl:296-346`）：
- 中档（`SHADOW_FILTER_QUALITY=1`，均衡档=1）先读中心四角（`:320`），仅在 `!astraSurfaceFootprintUniform && spread>0` 时追加两个沿 `astraSurfaceFootprintGradient` 的偏移足迹（`:334`），权重 `extraWeight = 0.58 * astraSurfaceFootprintEdge`（`:328`）。
- `spread` 被 `min(spread, softRadius / worldTexel)` 限制（`:318`），`softRadius = max(0.22, 0.75*astraSurfaceShadowPixelWorld)`（`:317`）。采样组数（2）与投射结构未变，柔化只沿可见性梯度定向。
- 该实现与 `docs/当前工作.md` W13 描述一致。独立呈现的 2.010/2.021/2.063 格来自文档，本报告不把它当作正确性证明；游戏细边效果仍需实机确认。

其他核对通过点：
- 接收面平面：`lit.fsh:162-165` 在 alpha discard 与材质分支前对 `surfaceShadowCoordinate` 求导并重投影；`shadowmap.glsl:203-222` 的 `shadow_surface_reference_depths` 用 `min(referenceDepth, ...)` 防止角点外推把参考推到接收点之后。
- 硬件比较分支：`shadowmap.glsl:229-238` 对四角各做一次 `textureGather(depths, uv, references[i])`，逐角返回各自比较结果——`opaqueVisibility` 与 `allVisibility` 都是逐角正确的，`:266` 的"全暗即返回"快路径不误判。
- 彩影与焦散：`shadow.fsh:106-119` 水面写 `vec4(waterHeight,1,1,focus)`；`shadowmap.glsl:89-101` 的 `shadow_water_transmission` 按 `caster.r < WATER_HEIGHT_NONE` 分派，岸侧 contrast 0.65、水下 0.90（`:85`）。焦散是与光束分离的独立表面波场（`caustics.glsl:5-6`），符合已认可边界。
- 覆盖边界：`shadow_map_fade:120-121` 在 `shadowDistance-24 .. -8` 渐退；`shadow_uv_coverage:124-135` 用 `min(border, radialBorder)`，边距 `shadowTexelSpread + 1.5/resolution`。末地走正交方形分支（`:110-115`、`:129-130`）。连续，无跳变。
- 主世界半格原点跳变：`shaders.properties` 无 `shadowIntervalSize` 键，即使用 Iris 默认；`docs/实现与限制.md` 称 `shadowIntervalSize=0` 只在主世界禁用——**当前 properties 中未见该键**，见模块 9 疑点。

---

## 模块 3：材质直接间接照明 AO/SSS/体素/实体与手

覆盖：`global/lighting/diffuse.glsl`、`global/lighting/sss.glsl`、`lib/ao_resolve.glsl`、`program/ssao.fsh`、`program/lit.fsh`（583 行全文）、`program/lit.vsh`、`program/deferred.fsh`、`program/deferred_slot0/1/2.fsh`、`lib/ao_material.glsl`、`program/scene.glsl`。

本模块未发现可证实的 P0/P1。

核对通过点：
- SSS 无双重计数：`diffuse.glsl:140-149` 先 `sss_wrap` 再 `sss_transmission`；`:199-200` 只把 `sssTransmission*0.35` 混入 `visibility`，in-shadow 的 0.7071 因子由 `astra_lighting` 统一施加一次。
- AO 分工正确：`lit.fsh:397` 的 `color -= ambientRadiance*(1-storedAO)` 只作用于直接可见的 colortex0；`:398` 写入 colortex19 的是**未 AO 修正**的 `ambientRadiance`，由 `deferred2` + `ao_resolve.glsl` 施加恢复的 AO。这是"存原始环境光 + 延后施加"的正确分工，不是重复施加。
- 手部：`lit.fsh:561-563` 置 `lightData |= 128u`；`light_shafts.glsl:48-49` 读回并用 `MC_HAND_DEPTH` 反投影修正；`taa_resolve.fsh:101-104` 对 `isEyeInWater != 0` 全部拒绝历史。链路完整。
- AO 接收面限定：`lit.fsh:391-392` 排除手部与实体，`ssao.fsh:100` 采样端同样检查 `colortex20[q].a < 0.5`，配对一致。
- 体素光：`program/shadow.vsh:42-90` 的 `astra_voxel_write` 在四个地形阶段工作（`:62-63`),`:88` `imageAtomicMax`；`shaders.properties:374-378` 在缺 `NETHER_VOXEL_LIGHT` 或 `BLOCKLIGHT_STRENGTH<=0` 时关闭 `program.world-1/shadow.enabled`。配置与代码一致。
- 湿材质：`lit.fsh:316-346` 的 `puddle`（稀疏积水，驱动反射）与 `surfaceWet`（damp，只驱动暗化与光泽）分离，`:337` 的 `rippleFootprint < 0.08` 门控避免远处波纹查询；`:571-572` 的 `gl_FragData[1].a` 只在岩石/土类材质写 puddle mask。载体是 colortex3（RGBA8，有真实 alpha 通道），`:528-534` 的注释正确地否定了 colortex0.a（R11F_G11F_B10F 无 alpha）。

疑点：
- `program/ssao.fsh:48` 在水下（`isEyeInWater != 0 && !thin`）直接 return，colortex21/26 保持 clear 值 `(1.0,-1.0,0.5,0.5)`。`shaders.properties:269-291` 的 AO 使能条件不含 `isEyeInWater`，所以 `deferred2` 会在水下运行并读到全 invalid 记录。`ao_resolve.glsl` 对 invalid 的具体处理本轮未完整核对，**列为疑点而非 bug**。

---

## 模块 4：水面波纹反射 SSR 折射介质/迟绘身体/界面两侧

覆盖：`program/water.glsl`（1013 行全文）、`global/water/raytrace.glsl`（501 行）、`global/water/refraction.glsl`、`global/water/surface.glsl`、`global/water/optics.glsl`、`global/water/absorption.glsl`、`lib/water_surface_budget.glsl`、`lib/water_entity_record.glsl`、`lib/water_diffusion.glsl`、`lib/water_interface_record.glsl`。

P2（可证实，与"树叶倒影缺失"相关）：`raytrace.glsl` 的 `stride` 增长上限在主世界预算的 `projectedMarch` 路径下是死代码。
- 触发：`OVERWORLD_BUDGET > 0`（默认全部预设 = 1，`settings.glsl:334`）且 `surfaceBudget || underwater`（`:273`），即主世界水平水面与所有水下界面。
- 落点：`raytrace.glsl:286` `travel = min(previous + stride, maxTravel)` 是 fallback；`:287-303` 的 `if (projectedMarch)` 块在 `:296` 用 `travel = visibleEnd*fraction²*clipOrigin.w/mix(endW,clipOrigin.w,fraction)` 完全重算。`:372-378` 的 `stride = min(stride*1.9, 12.0)` 只在 `!projectedMarch` 时被消费。
- 后果：注释 `:372-374` 声称"更宽的步长有意省略一些薄的远物体"，在主世界预算下不成立。粗查询密度实际只由 `coarseBudget`（`:248-264`）与 `fraction²` 分布决定。
- 依据：`:287` 的条件在主世界水面恒真，`travel` 必被 `:296` 覆盖。
- 取舍标注：`docs/实现与限制.md` 明确「查询数量控制密度，不再用较少步数意外截短几何行程」「粗查询铺到完整可见投影段」，这可能是有意的均匀投影设计。若确认是设计意图，应更新 `:372-374` 的注释而非改代码；若要调远近采样密度，应调 `:295` 的幂次或 `coarseBudget`。

其他核对通过点：
- SSR 命中质量补偿（树叶）：`raytrace.glsl:145-175` 的 `water_ssr_footprint_crossing` 对四个候选只接受"射线穿过其自身纹元、原粗区间、反射侧"的交点；`:334-347` 的即时命中也要求交点 UV 仍落在该纹元。原残差判据（`:470-473`）未放宽。
- 远侧预算：`raytrace.glraytrace.glsl:257-260` 的 `(surfaceBudget || underwater) ? 12 : 8` 使湿润地形（`deferred.fsh:62` 的积水反射，`surfaceBudget=false`）保持 8，符合"仅水路用 12"的现行边界。
- 迟绘身体：`lit.fsh:442-443` 对不透明实体片元写 `water_entity_record(color, -viewPos.z)`，alpha 为 0/1 覆盖；分数透明写 `vec4(0.0)` 并通过 `shaders.properties:363-364` 的 `ONE ONE_MINUS_SRC_ALPHA` 保留先前记录。`water.glsl:78-82` 用 `record.a` 与 `-point.z` 比较并按比例缩放点，保证颜色/深度配对。**正确。**
- 共享传输的容差：`water.glsl:238`（空气反射 `depthRange <= min(0.12, 0.03+path*0.001)`）、`:258-259`（水下连续 `0.2%` 透射差）、`:267-281`（水上连续底，`tolerance = min(0.02, 0.01/max(WATER_ABSORPTION*0.01, 0.05))`），与 `water_surface_budget.glsl` 和文档描述一致。
- 界面两侧：`water.glsl:558-596` 的 `astra_vertical_water_interface`（薄片/竖流）与 `:637-742` 的 `astra_underwater_interface`（水平界面）是两条独立路径；`:758-761` 按 `abs(geometric.y) <= 0.9` 与 `belowWater` 分派。第三人称窗口中心用 `relativeEyePosition`（`:647-651`），几何/投影仍用真实相机。
- 伽马域：`:686`/`:696`/`:735`/`:739`/`:741` 的 1/2.2 与 2.2 转换在反射、fallback、背景三条腿上一致，符合 `solas_water.glsl:95-97` 记录的 Solas 既有约定（合成前存 gamma 2.2，fog 在 sqrt 空间混合，再解到线性）。

疑点：
- `water.glsl:204` 的 `gatherUV = (corner+1)/size` 与 `:242` 的 `textureLod(colortex4, uv, 0.0)` 是同一 2×2 格的不同采样点。`weights`（`:229` 用 `f = fract(location)`）与 uv 配对正确，但共享路径（`:242`）与失败路径（`:488` 用 `(location+0.5)/size`）的浮点计算顺序不同，理论上可能在格边界产生极小接缝。**需实机确认**，不作为 bug。

---

## 模块 5：水下光束源图窗口积分消光/水位/雾/柔化/太阳

覆盖：`program/itt_water_normal_cache.vsh/.fsh`、`program/scattering.vsh/.fsh`、`global/water/light_shafts.glsl`（274 行）、`lib/itt_water_field.glsl`、`lib/itt_water_waves.glsl`、`lib/water_palette.glsl`、`global/water/medium_state.glsl`、`program/water_state.fsh`、`global/water/shaft_layout.glsl`、`lib/solas_water.glsl`、`lib/solas_water_frame.glsl`、`global/water/bloom_capture.glsl`、`bloom_resolve.glsl`。

P1（可证实）：`astraWaterShaftRange`（48）与 `WATER_SHAFT_FAR_END`（26）矛盾，导致预算内的单线性读取快路径永不触发。
- 文件：`Astra/shaders/global/water/light_shafts.glsl:161`、`:187`、`:236`、`:244-248`；`Astra/shaders/lib/water_palette.glsl:11`；`Astra/shaders/global/water/shaft_layout.glsl:8`。
- 触发：任何 `UNDERWATER_LIGHT_SHAFTS` 开启的 submerged 像素（均衡档 `settings.glsl:173`=100、`:177`=7）。
- 链条：`shaft_layout.glsl:8` `WATER_SHAFT_FAR_END = 26.0`；`water_palette.glsl:11` `astraWaterShaftRange = 48.0`。`light_shafts.glsl:161` `marchLength = min(rayLength, min(astraWaterShaftRange, WATER_SHAFT_FAR_END))` = `min(rayLength, 26)`。`scattering.fsh:99-100` 把 `volume.a` 写成 `min(volume.a*128, astraWaterShaftRange)/128`，但 `volume.a` 来自 `:225` 的 `rayLength/WATER_SHAFT_MAX_DISTANCE`，`rayLength` 本身被 `:161` 截到 ≤26，所以 alpha ≤ 26/128 ≈ 0.203。
- 消费侧 `:236` `referenceLength = min(clamp(rayLength,0,128), astraWaterShaftRange)` = `min(rayLength, 48)`；`:244` 的快路径门槛 `if (referenceLength >= astraWaterShaftRange)` 即 `>= 48`。`:246` 还要求 `volumeSample.a == astraWaterShaftRange/WATER_SHAFT_MAX_DISTANCE` = 48/128 = 0.375。生产者 alpha 上限 0.203 < 0.375，**该分支在任何配置下都不可达**。
- 后果：每个水下像素都执行 `:250-271` 的四角双线性 + 逐角深度加权重建（4 次 `texelFetch`），而非文档描述的"端点足迹填满窗口时一次线性读取"。这是水路每像素额外成本的一部分。
- 建议：统一两个常量。若真实积分上限是 26，把 `astraWaterShaftRange` 改为 26.0（同时 `:244-248` 的判断即自洽）；若 48 是设计意图，把 `WATER_SHAFT_FAR_END` 提高，或让 `:161` 显式用 `astraWaterShaftRange` 并移除 `WATER_SHAFT_FAR_END` 的截断。**注意**：改任何一个都会改变实际积分距离与观感，属需用户取舍的边界，不是纯 bug 修复。

P2（可证实）：`water_shaft_wave_span` 的 `lightDir` 形参是死参数。
- `light_shafts.glsl:124-125` 签名声明 `vec3 lightDir`，函数体 `:127-150` 只用 `entry`、`entryRay`、`begin`、`span`、`angularFootprint`，从不引用 `lightDir`。`:193` 计算它并在 `:213` 传入。
- 编译器会消除，无运行时开销。但它误导读者以为积分时按光源方向再算一次光量——实际光量已在 `itt_water_normal_cache.fsh:27` 生产时按 `ittWaterFieldLight` 算好并存入 B 通道。建议删除该形参或在注释中说明。

P2（与用户关注"光束少且挤"直接相关）：波长展宽在数学上减少单位视场内的光带数量。
- 落点：`lib/itt_water_waves.glsl:46` `const float spatialScale = 0.05/1.28;`，`:47` `p = worldXZ*spatialScale - ...`，即世界尺度除以 1.28 → 波长 ×1.28。`:76` `return waves*((1.28/1.08)/79.0);` 用 1.185 的系数补偿展宽导致的梯度幅度衰减。`:84` 再乘 `0.30*WATER_WAVE_HEIGHT*0.01`（默认 100 → 0.30）。
- 后果：净效果是**波纹间距变大（光带变宽变少），但每带的斜率幅度不变**。这与"更多更细的束"的目标方向相反。`docs/当前工作.md` W04 记录「波长相对原尺度1.28、相对上轮再展宽18.5%」并承认「上轮改变没有可感区别」。
- 取舍标注：W04 明确允许改变光束数量/强度/柔和度，因此这不是越权改动。但若要达到"可见细束增加、主束散开"，当前参数方向需重新评估——增大 `:46` 的 `spatialScale` 分母会进一步减少光带数，减小它才增加。
- 建议：若目标是增加细束，应提高六层中低权重层（`:51` 权重 2、`:60` 权重 8、`:65` 权重 13）的空间频率（减小各自的 `p` 缩放因子），而不是继续展宽 `:46`。

核对通过点：
- 消光：`light_shafts.glsl:182-185` 入射 `water_absorption_coefficient() + 0.025*(UNDERWATER_FOG_DENSITY*0.025)`、观察 `+ 0.012*(...)`. 默认 `UNDERWATER_FOG_DENSITY=40`、`WATER_ABSORPTION=100` 时，蓝通道入射 = `0.010+0.025 = 0.035`/格、观察 = `0.022`/格，与 `docs/实现与限制.md` 完全一致。
- 相位：`:73-81` Cornette–Shanks，`g=0.7`，`mix(0.07957747, directional, 0.8)`，与文档一致。
- 八点积分保留：`:131-136` 的 8 节点 Gauss 位置/权重，`:138-149` 在每个节点代表的路径分段内积分波纹碰撞光量（`textureLod(colortex29, ..., lod)` 取 B 通道），不平均法线、不横向模糊、不用历史。**已认可的消弧纹结构完整保留。**
- 遮挡/消光/透射：`:210` 的 `water_shaft_path_visibility` 逐外层节点查入口与接受点，`:104-112` 配对 `shadowtex1−shadowtex0` 与 `shadowcolor0` 的水身份 + 0.75 格水位容差，`:116-119` 在平面云影开启时乘 `astra_cloud_transmission`. 遮挡为 0 时 `:211` 跳过该段波纹读取但分段仍前进.
- 折射方向语义自洽：`scattering.vsh:48` 的 `-refract(-lightDir, up, 1/IOR)` 产出**向上**的 `waterLightDir`（用于 `:174` 从观察点反投影到水面）；`itt_water_normal_cache.vsh:12` 的 `refract(-ittWaterFieldLight, up, 1/IOR)` 产出**向下**的 `down`（用于 `:16` 的 `max(-down.y,0.2)` 定位源图窗口中心）。两处方向相反但各自用途正确。
- 水下太阳（用户关注项）：`water.glsl:609-621` 原版模式用 sprite，`:616` 分母 `0.672*alignment` 对应 `lit.vsh:116` 的 `vertex.xz *= 1.12`（30×1.12=33.6），内外角尺寸一致。程序模式 `:622-628` 保持 `radius=0.028` 解析圆盘，是设计意图。`:607` 的 `worldSunVector.y <= 0.0` 保证夜间不画.
- 水位与身份：`water_state.fsh:43-76` 扫描 20×12 网格取最近界面，`:63` 水下跳过 `surfaceY < cameraY - 0.25`，`:81` `nearSides >= 3` 判薄片，`:87-105` 前帧状态与影图回退. D03 已记录的技术债，不是新 bug。
- 雾：`solas_water.glsl:69` `density = astra_water_haze_density() * astra_water_haze_far_gain(d)`，`water_palette.glsl:14` = `40*0.00134 = 0.0536`/格，`:21` 远端增益 `1+0.22*smoothstep(4,22,d)`. 与文档一致.

疑点：
- 末端重建的 alpha 语义：`light_shafts.glsl:162` 的 `empty` 分支返回 `rayLength/128`，而 `:225` 返回 `rayLength/128`，中间分支（早退于 `:163`/`:165`/`:167`/`:177`）都用 `rayLength` 而非 `marchLength`。消费者 `:262` 用 `min(tap.a*128, astraWaterShaftRange)` 与 `referenceLength` 比较. 若某像素的生产者走了早退（`:177` 波段裁剪失败）而其邻居正常，四角深度权重会用一个未截断的 rayLength。这看起来是**有意的**（早退时该射线确实没有光，权重低），但需要实机确认边界是否连续.

---

## 模块 6：天空日月星空晨昏云天气及相关历史

覆盖：`program/sky.fsh`（145 行）、`program/sky_gradient_cache.fsh`、`program/sky_reflection_cache.fsh`、`lib/sky_reflection_cache.glsl`、`lib/sky_gradient_cache.glsl`、`global/atmosphere/sky_gradient.glsl`、`sky_minishita.glsl`、`stars.glsl`、`clouds_planar.glsl`、`cloud_temporal.glsl`、`clouds_screen.glsl`、`cloud_shadow_cache.glsl`、`global/atmosphere/weather.glsl`、`global/atmosphere/fog.glsl`、`program/cloud_screen.fsh/.vsh`、`program/cloud_shadow_cache.fsh`、`program/clouds.fsh`、`program/prepare.fsh/.vsh`、`prepare1.fsh`、`prepare2.fsh`、`program/sky_irradiance.fsh`、`program/prepare3.fsh`、`lib/twilight.glsl`、`lib/effect_history.glsl`、`program/effect_history.vsh`、`program/effect_history_state.fsh`。

本模块未发现可证实的 P0/P1。

核对通过点：
- 晨昏（W09）：`shaders.properties:615-616` 的 `astraTwilightRise/Fade` 端点为 -9°/+4°/+14°，`:621-622` 的 `Ease` 用 C1 二次肩部（峰值斜率 4/3 = 1.333）接长线性中段（斜率 8/7 ≈ 1.143），端点/平台/中点不变，`:623` 的 `Envelope = Rise*(1-Fade)`，`:624` 乘 `1-0.7*rainStrength`. `lib/twilight.glsl:4-12` 的 `astra_twilight_strength()` 直接返回 `astraTwilightFactor`，天空、云、地形、倒影共用同一入口. **符合"过渡更丝滑缓慢、太阳角度临界点不变".**
- 日月高光肩部一致：`sky.fsh:72` 与 `water.glsl:620` 都用 `mix(vec3(2.0,1.90,1.65), vec3(2.0,1.28,0.56), astra_twilight_strength())`；`sky.fsh:82` 与 `water.glsl:620` 都调用 `astra_scene_highlights`（`twilight.glsl:138-140`，knee 1.0、softness 0.60、peak-relative 单因子）. 内外一致.
- 天空缓存接缝：`lib/sky_reflection_cache.glsl:28-46` 的 `astra_sky_cache_filtered` 在经度接缝外显式插值首/末列，非接缝区走单次 `textureLod`. `:60-61` 的 gutter 偏移 `(fract(longitude)*256+1)/258` 与 `shaders.properties:60-64` 的 258×128（非粗糙）/256×128（粗糙）匹配.
- 星空抑制：`sky.fsh:64-65`（贴图模式）与 `:133`（基础模式）都对 `MC_RENDER_STAGE_STARS` discard，Astra 自绘. `:69` 对 alpha≈0 丢弃，避免无意义写入.
- 云平面（用户 W07 相关）：`clouds_planar.glsl:301-308` 的存在门只由粗八度决定，细节八度只软化边缘不独立成云——`:307-308` `if (coarse <= existenceGate) continue;`. `:309-312` 把覆盖归给已占据的粗柱，使着色点移动到边界时不擦除该柱的不透明度. 这两条是 W07 稳定化的基础，**逻辑正确**.
- 云生产者分档：`clouds_planar.glsl:255-280` 按 `ASTRA_CLOUD_LOW_TIER`/`BALANCED_TIER`/`SKY_CACHE_WRITE`/`CLOUD_QUALITY` 选 `sampleCount`，`:313-315` 只细化已占据的粗区间. 预算内不加查询.
- 天气：`shaders.properties:391` 的 `blend.gbuffers_skytextured=SRC_ALPHA ONE ZERO ONE` 在 `CLOUD_MODE != 0` 时让 celestial 累加在黑上，再由 deferred 合成.

疑点：
- `clouds_planar.glsl:240-253` 的 `marchOffset`：屏幕生产者 + 时域历史用 `dither`，其他档用 `const 0.5`. 注释 `:242-245` 说明固定相位不锁覆盖，因为 IGN 空间去相关且移动网格偏移提供亚像素覆盖. 这个推理依赖 `astra_cloud_ign()` 的实际空间去相关性质，**本轮未读 `clouds_planar.glsl` 中 `astra_cloud_ign` 的实现**，列为疑点.

---

## 模块 7：后处理泛光调色 AA 历史重投影/显示颜色域

覆盖：`program/display.fsh`（247 行）、`program/final.fsh`、`program/taa_resolve.fsh`（186 行）、`program/taa_state.fsh`、`program/exposure.fsh`、`program/composite1.fsh`、`program/water_bloom.fsh`、`global/post/bloom.glsl`、`global/post/grading.glsl`、`global/post/fxaa.glsl`、`global/post/exposure.glsl`、`global/post/godrays.glsl`、`global/post/end_sky_tonemap.glsl`、`lib/tonemap.glsl`、`lib/dither.glsl`、`lib/taa_jitter.glsl`、`lib/taa_state.glsl`、`lib/taa_reactive.glsl`、`lib/water_buffer_formats.glsl`、`lib/effect_history.glsl`。

本模块未发现可证实的 P0/P1。

核对通过点：
- Bloom 开关下的水下合成分工：`settings.glsl:680` 定义 `ASTRA_BLOOM`. Bloom 开时 `display.fsh:14`/`:19` 的条件为假 → 不含 `light_shafts`/`water_diffusion`,改在 `:118-124` 直接读 colortex4（由 `program/water_composite.fsh:15` 的 `RENDERTARGETS: 4` 写入）. Bloom 关时 `:132-147` 在 display 内完成 `water_diffuse_scene` + `water_shafts_resolve` + `solas_water_composite`. **两条路径互斥且各自完整.**
- 避免二次精度压缩：`display.fsh:122-124` 与 `taa_resolve.fsh:93-95` 在水下都直读 colortex4，绕过 TAA 复制到低精度 colortex0. `display.fsh:111-117` 的 `sceneUV = texcoord + astra_jitter_uv()` 让其它场景缓冲仍按抖动栅格采样. **与 W 系列"避免蓝通道台阶"的修复一致.**
- 泛光双路径：`composite1.fsh:32-35` 在水下非薄片写 0 到 colortex2（水下泛光走 colortex7），`water_bloom.fsh:11` 同样在薄片 discard; `display.fsh:150-151` 水下用 `getBloom(hdr, sceneUV)`（读 colortex7），空气用 `bloom_composite(colortex2, ...)`. `:163` 的 `bloomStrength *= 1-0.28*twilight` 只作用于空气臂. **无重复泛光.**
- TAA 重投影：`taa_resolve.fsh:120-123` 天空用 `mat3` 纯旋转、非天空加相机位移差; `:128-131` 植被用自身运动输入覆盖; `:134` 的深度容差 `0.012 + min(0.04, 2*fwidth(expectedDepth))`; `:141-177` 的历史接受路径含深度一致性（`:76-78`）、颜色信任（`:146-147`）、3×3 统计裁剪（`:152-165`）、中心信任（`:170-171`）、运动衰减（`:166`）. **无相机运动冒充实体运动的常见缺陷**（实体走 reactive 拒绝）.
- FXAA 链路：`final.fsh:2-20` 在 `ANTIALIASING==1` 时读 colortex13 跑 `astra_fxaa`; `display.fsh:240-242` 在 `ASTRA_DISPLAY_PREPARE` 下写 colortex13（RGBA16，`:94`). 抖动在 FXAA 之后（`final.fsh:18`），不进 AA 输入. **正确.**
- 失明一次施加：`display.fsh:205-216` 的 `darknessFactor` 在泛光与光束之后、tonemap 之前统一施加; `water_composite.fsh:31` 与 `display.fsh:145` 的 `(1.0 - clamp(blindness,0,1))` 是水下合成侧的单次乘法. **不存在重复失明.**
- 帧元数据：`effect_history_state.fsh:14-16` 写视口/帧号/介质/时间到 colortex30 的 3 个 texel，`effect_history.vsh:19-20` 在顶点阶段读回判有效. `shaders.properties:218` `size.buffer.colortex30=3 1` 匹配.

疑点：
- `display.fsh:194` 在 `UNDERWATER_PARTICLES` 下读 `depthtex0` 的**原始** depth，而 `water_shafts_view:36-55` 做了手部修正（`:48-49`）. 粒子距离与光束端点在手部像素上可能不一致. **需实机确认**.
- `lib/water_buffer_formats.glsl`（1382 字节）中 `colortex4Format` 的具体声明本轮未逐行确认是 RGB16F. `docs/实现与限制.md` 记录为 RGB16F，但源码未验证.

---

## 模块 8：下界末地维度入口与独立效果

覆盖：`world-1/*` 与 `world1/*` 全部薄入口、`global/dimension/nether.glsl`、`nether_reflection.glsl`、`nether_colored_light.glsl`、`nether_volume.glsl`、`end.glsl`、`end_blackhole.glsl`、`end_geometry.glsl`、`end_kerr.glsl`、`end_system.glsl`、`end_disc_profile.glsl`、`end_plasma.glsl`、`program/nether_light.csh`、`program/nether_reflection.fsh`、`program/nether_reflection_resolve.fsh`、`program/end_illumination.fsh`、`program/end_reflection_cache.fsh`、`program/end_sky_buffer.fsh`、`program/end_star_catalogue.csh`、`program/end_star_rows.csh`、`lib/nether_voxel_grid.glsl`、`lib/end_reflection_cache.glsl`、`lib/end_star_catalogue.glsl`、`lib/end_surface.glsl`、`lib/rock_material.glsl`、`lib/transforms.glsl:80-114`。

本模块未发现可证实的 P0/P1.

核对通过点：
- 末地槽位重排：`world1/deferred.fsh` → `program/end_sky_buffer.fsh`（天空缓冲），`world1/deferred1.fsh` → `program/deferred.fsh`（真正场景合成）. `shaders.properties:253` `program.world1/deferred1.enabled=true` 与 `:385` `program.world1/deferred.enabled=true` 同时启用，配合 `:250` `world1/prepare1.enabled=true`（→ `end_reflection_cache.fsh`）与 `:254` `world1/prepare.enabled=true`. **这是有意的四槽位编排，非错配.**
- 下界反射：`shaders.properties:365` `world-1/composite.enabled=SCREENSPACE_REFLECTIONS`，`:373` `world-1/composite1.enabled=SCREENSPACE_REFLECTIONS`. `world-1/composite.fsh` → `program/nether_reflection.fsh`. 注意 `:363-364` 的 colortex28 blend 是包全局的（`:356-359` 注释说明 Iris 用裸 pass 名查找，`blend.world-1/<pass>` 永远不生效），所以下界也吃这条 blend——但下界 28 是反射元数据，`lit.fsh:19-25` 只在 `ASTRA_WATER_PASS || ASTRA_ENTITY` 时声明 `colortex28Format = RG32F`，下界反射的格式由 `nether_reflection.fsh` 自己声明. **配置与代码一致.**
- 下界主世界功能隔离：`shaders.properties:141-142` `world-1/prepare3.enabled=false`（不用 SH9）；`:162` `world-1/deferred2.enabled=false`（不用 AO）；`:175` `world-1/deferred1.enabled=false`（不用体积雾）. `program/lit.fsh:168-170` 在 `ASTRA_WEATHER && (NETHER||END)` 直接 discard. **隔离干净.**
- 末地阴影：`lib/transforms.glsl:107-114` 的 `player_shadow` 在 `DIMENSION_END` 走 `end_shadow_ndc`; `shadowmap.glsl:397-412` 用 `end_shadow_texel_size()` 的斜率相关偏置 + `end_light_direction()` 的深度余量; `:110-115` 的 fade 用 `end_shadow_view` 的正交 XY 与 `end_shadow_extent()`. **与"径向畸变对末地禁用"的注释一致.**
- 末地光照/表面：`lit.fsh:421-430` 的 `end_surface_specular` 用 `end_light_direction()` 与 `end_surface_visibility`/`end_surface_eclipse`; `:434` 的 `astra_end_stone_emission`; `settings.glsl:376-384` 的下界 `shadowMapResolution=64`/`shadowDistance=48`（体素体积用）与 `:385-388` 的末地 `SHADOW_RESOLUTION`/`shadowDistanceRenderMul=1.5`. **边界明确.**
- 下界着色分支：`lit.fsh:297-304` 的 `netherLava`（`faceData` bit 25，来自 `lit.vsh:96` 的 `mc_Entity.x == 10030`）做色偏 + `:374-380` 的 `peak` 归一化，不削到黑.

疑点：
- `world-1/shadow.vsh:1` 用 `#version 430 compatibility` 而其他薄入口用 400. 若宿主对某些维度目录的 GLSL 版本有硬约束，430 是否总能被接受需运行时确认. `:2-4` 已说明原因（`uimage3D` + `imageAtomicMax` 需 420+），属既有设计.
- `program/nether_light.csh`（6230 字节）的九个 compute 阶段与 `lib/nether_voxel_grid.glsl`（3885 字节）的扩散循环本轮未逐行核对.

---

## 模块 9：选项档位开关组合/性能热点及文档与现行源码不一致

覆盖：`lib/settings.glsl`（47029 字节）、`shaders.properties` 全部 profile（`:564-567`）、`Astra/README.md`、`docs/当前工作.md`、`docs/实现与限制.md`。

P1（可证实）：ULTRA 档的 `UNDERWATER_SHAFT_SAMPLES=10` 在主世界预算下被静默钳制到 7，profile 声明与实际成本不符。
- 落点：`shaders.properties:567` `profile.ULTRA=... UNDERWATER_SHAFT_SAMPLES=10 ...`; `Astra/shaders/global/water/light_shafts.glsl:21-25`
  ```
  #if !defined ASTRA_OVERWORLD_OPTIMIZED || UNDERWATER_SHAFT_SAMPLES < 7
      #define ASTRA_SHAFT_SAMPLES UNDERWATER_SHAFT_SAMPLES
  #else
      #define ASTRA_SHAFT_SAMPLES 7
  #endif
  ```
- 推导：四个 profile 全部自带 `OVERWORLD_BUDGET=1`（`:564-567`），`settings.glsl:352-353` 因此定义 `ASTRA_OVERWORLD_OPTIMIZED`. ULTRA 的 10 ≥ 7 → `ASTRA_SHAFT_SAMPLES = 7`，与 BALANCED 完全相同. PERFORMANCE 的 4 < 7 → 保持 4.
- 后果：`7 × 4 × 8 = 224` 次波纹读取在 ULTRA 与 BALANCED 下相同; profile 行末的 `10` 是死设置.
- 取舍标注：README 已声明「主世界预算仍可限制其实际开销，不因"极致"名称自动解除预算」，所以钳制本身是有意的. 问题是 profile 行内没有任何注释说明 10 会被钳制，用户读 profile 无法得知实际值. 建议在 profile 行加注释或把该 token 从 ULTRA 移除.

P1（可证实，性能热点，与"水面/水下开销高于 Steadfast"直接对应）：默认均衡档每像素水下光束的源码成本结构.
- 组成（均衡 = `OVERWORLD_BUDGET=1`、`WATER_EFFECT_QUALITY=1`、`UNDERWATER_SHAFT_SAMPLES=7`、`ANTIALIASING=1` FXAA、`BLOOM` 开）：
  - 生产侧 `program/itt_water_normal_cache.fsh`：1024×1024 RGBA16F 全场写入（`shaders.properties:207`），每像素 6 层 `itt_wave_noise` 各 1 次 `textureGather`（`itt_water_waves.glsl:51/55/60/65/70/75`）+ `water_shaft_collision_light`（`itt_water_field.glsl:19-31`，含 `normalize`、`water_fresnel`、`sqrt`、两次 `pow`).
  - 消费侧 `light_shafts.glsl:196-219`：7 区间 × 4 节点. 每节点一次 `water_shaft_path_visibility`（`:210`），内含 2 次 `shadow_gather_visibility_inside`（`:104`/`:106`）+ 2 次 `textureGather(shadowcolor0)`（`:109`，焦散开时 `:326` 类似）+ 可选 `astra_cloud_transmission`（`:117`）+ `shadow_opaque_visibility`（`:122`）；遮挡非零时再一次 `water_shaft_wave_span`（`:212`）含 8 次 `textureLod(colortex29)`（`:143`）. 上限 `28 × 8 = 224` 次源图读取 + `28` 次阴影可见性查询.
  - 重建侧 `light_shafts.glsl:250-271`：4 次 `texelFetch`（因 P1-1 的快路径不可达）.
  - 合成侧 `program/water_composite.fsh` + `lib/water_diffusion.glsl` 的场景柔化（每像素 4 组场景/深度读取）.
- 与 Steadfast 的差异：Steadfast 0.8.0 的水路不含体积光积分、不含 1024² 源图、不含 224 次纹理读取、不含独立阴影可见性查询. `docs/实现与限制.md` 引用 Steadfast 的 `raytrace.glsl:524` 注释称其水路"在四角接受后取一次颜色，倒影24轮内保留最后有效命中".
- 依据：以上全部可从源码循环边界直接数出. `docs/实现与限制.md` 记录的独立数字（源图 0.0696 + 积分 0.8100 ms，合计约减少 56%）与循环结构一致.
- **本报告不推断整帧 FPS.** 用户报告的 67/90/100 FPS 是场景读数而非平均值或分项耗时，不能据此归因到具体阶段.

P2（可证实，文档与源码不一致）：`docs/实现与限制.md` 关于光束积分上限的表述与源码不一致.
- 文档（`docs/实现与限制.md`「水下光束读取同帧 ITT 六层波面产生的入射碰撞光量」段）称 `composite2` 存储 `A = min(ray length,48)/128`（`shaders.properties:8-10` 的注释也是"integrate at most 48 blocks"），而源码 `light_shafts.glsl:161` 实际截到 26（`WATER_SHAFT_FAR_END`）. **这与 P1-1 是同一个根因**，文档/注释的"48 blocks"来自 `astraWaterShaftRange`，源码的有效积分上限来自 `WATER_SHAFT_FAR_END`.

P1（可证实，档位组合）：PERFORMANCE 档整条 SSR 链被编译掉.
- `shaders.properties:564` `profile.PERFORMANCE` 含 `!SCREENSPACE_REFLECTIONS`; `program/water.glsl:809` 的 `#ifdef SCREENSPACE_REFLECTIONS` 整段被预处理掉; `:674` 的水下 SSR 同样. `:365` `program.world-1/composite.enabled=SCREENSPACE_REFLECTIONS` 也关. 此档水路只剩折射 + `astra_reflection_sky` 环境反射 + 高光. **符合 README 的档位表.**

P1（可证实，档位组合）：NO_SHADOWS 档整条光束链完全关闭.
- `shaders.properties:565` 含 `!SHADOWS !UNDERWATER_LIGHT_SHAFTS`. `:18` 的 colortex1 条件要求 `defined UNDERWATER_LIGHT_SHAFTS && defined SHADOWS && UNDERWATER_SHAFT_STRENGTH > 0` → 全假 → `size.buffer.colortex1=1 1`（`:25`）. `scattering.fsh:38` 的 `#ifdef UNDERWATER_LIGHT_SHAFTS` 假 → 不含 `light_shafts.glsl`. `:317-321` `program.composite2.enabled=false`. `:206-212` 的 `prepare4.enabled` 条件同样含 `defined SHADOWS` → false，`colortex29=1 1`. **整链干净关闭，无悬挂采样器、无未初始化附件.**

P2（可证实，配置与文档一致）：README 与 profile 的核对通过.
- README「四档预设均选择主世界"优先"预算，并关闭方向性天光、屏幕空间 AO 和步进体积雾」→ `:564-567` 四个 profile 全部含 `OVERWORLD_BUDGET=1 !DIRECTIONAL_SKYLIGHT !SCREENSPACE_AO !VOLUMETRIC_FOG`. **一致.**
- README「阴影至多 1536 分辨率、112 格覆盖，实体投影维持 32 格，并采用硬件深度比较」→ `settings.glsl:401-405` 的预算上限 1536、`:407-410` 的 112. 但 README 说「采用硬件深度比较」，`settings.glsl:365-369` 在 `ASTRA_OVERWORLD_OPTIMIZED` 下强制 `ASTRA_SHADOW_FILTER_MODE = SHADOW_FILTER_SOFTWARE`. **README 与源码矛盾**——这是一个可证实的文档不一致. README 的说法只适用于 `OVERWORLD_BUDGET=0`（此时 `:368` 取 `SHADOW_FILTER_MODE`，默认 `settings.glsl:68` = 0 = SOFTWARE，所以即使预算关闭默认也不是硬件）. **当前默认配置下没有任何路径使用硬件阴影比较.**
- README「实体投影维持 32 格」→ `shaders.properties:564-567` 中 PERFORMANCE=32、NO_SHADOWS=48、BALANCED=64、ULTRA=96，但 `settings.glsl` 的预算是否把实体距离钳到 32 需核对 `ENTITY_SHADOW_DISTANCE` 的引擎钳位. 本轮未读到该钳位代码.

疑点：
- `docs/实现与限制.md` 称「`shadowIntervalSize=0` 只在主世界禁用 Iris 的半格原点跳变」，但 `shaders.properties` 全文**没有 `shadowIntervalSize` 键**（grep 无结果）. 若该键确实不存在，则 Iris 使用默认值（通常为 2，即启用跳变），与文档描述不符. **这需要核对 Iris 1.11.2 的默认 `shadowIntervalSize`.** 本报告不把它列为 bug，但标为高优先疑点.
- `block.properties`（12670 字节）的完整方块→ID 映射只抽查了关键行（10001 水、10002 树叶、10003-10006 水草/花草、10010 玻璃、10011 冰、10030 岩浆、10034-10040 发光方块、10021-10027 火把类）. **未逐行核对**，可能存在未分类方块落到默认 material 0 的情况.
- `lang/zh_CN.lang`（32758 字节）与 `en_US.lang`（35028 字节）的选项描述与实际 `#define` 值的一致性未核对.
- `lib/settings.glsl`（47029 字节）中未穷举所有选项的相互影响，只核对了预算宏、阴影滤波、水面/光束、AA、天空相关.

---

## 汇总

### P0
无.

### P1（4 项）

1. **水下光束 `astraWaterShaftRange`(48) 与 `WATER_SHAFT_FAR_END`(26) 矛盾，单线性读取快路径不可达.** `global/water/light_shafts.glsl:161`/`:187`/`:236`/`:244-248`、`lib/water_palette.glsl:11`、`global/water/shaft_layout.glsl:8`. 每个水下像素被迫执行四角 `texelFetch` 重建. 这与"水路开销高于 Steadfast"一致. 修复涉及观感取舍，需用户决定统一到哪个值.

2. **ULTRA 档 `UNDERWATER_SHAFT_SAMPLES=10` 被主世界预算静默钳制到 7.** `shaders.properties:567` + `light_shafts.glsl:21-25`. profile 声明与实际成本不符，ULTRA 光束成本 = BALANCED. 属预算有意的上限，但 profile 行缺注释.

3. **README 声称主世界预算「采用硬件深度比较」，但源码在预算开启时强制软件模式.** `Astra/README.md`「性能与高级 → 主世界性能预算」段 vs `lib/settings.glsl:365-369`. 默认配置（`OVERWORLD_BUDGET=1`）下 `ASTRA_SHADOW_FILTER_MODE = SHADOW_FILTER_SOFTWARE`; 即使预算关闭，`:68` 的 `SHADOW_FILTER_MODE` 默认也是 0（SOFTWARE）. **当前没有任何配置路径使用硬件阴影比较.** 这是可直接证实的文档-源码矛盾.

4. **`docs/实现与限制.md` 的 `shadowIntervalSize=0` 描述在 `shaders.properties` 中无对应键.** 若 Iris 默认值非 0，则主世界仍在做半格原点跳变，而文档与 `docs/当前工作.md` 的相关结论假定它已禁用. 需核对 Iris 1.11.2 默认值后判定. **这是疑点升级项**：如果默认确实非 0 且文档假定为 0，则"生产与消费共用连续矩阵"的结论在游戏内不成立.

### P2（5 项）

5. `water_shaft_wave_span` 的 `lightDir` 死参数（`light_shafts.glsl:124-125`，函数体不用）. 无开销，误导阅读.

6. 波长展宽在数学上减少光带数量（`itt_water_waves.glsl:46` 的 `0.05/1.28`）. 与"更多细束"目标方向相反; W04 允许改数量故非越权，但参数方向需重估.

7. `raytrace.glsl:372-378` 的 `stride` 上限在主世界预算的 `projectedMarch` 路径下是死代码（`:296` 覆盖 `travel`）. 注释与实际不符；可能是设计意图，需确认后改注释或改码.

8. `water.glsl:204` 与 `:242`/`:488` 的采样点差异可能在 2×2 格边界产生极小接缝. 需实机确认.

9. README「实体投影维持 32 格」与 profile 里的 48/64/96 未见钳位代码. 需核对 `ENTITY_SHADOW_DISTANCE` 的引擎钳位.

### 用户当前关注点对照

| 关注点 | 源码结论 |
|---|---|
| 水面树叶倒影缺失 | 对应 P2#7（`stride` 死代码）+ `docs/实现与限制.md` 已量化的残留近似（复杂错层树冠接收率 31.36%，仍有显著漏采）. `raytrace.glsl:145-175` 的树叶质量补偿在源码层存在且逻辑正确，**不是新的源码 bug**; 不可见的部分是屏外几何与被原视角遮挡的叶片，SSR 原理上无法恢复. |
| 水下光束少且挤 | 对应 P2#6（展宽减少光带数）. `docs/当前工作.md` W04 的"上轮改变没有可感区别"与源码参数方向一致. 当前实现会继续朝"更少更宽"走，若目标是"更多更细"需反转 `:46` 的方向. |
| 水面/水下开销高于 Steadfast | 对应 P1#1（快路径不可达，每像素多 4 次 `texelFetch`）+ P1 汇总节列出的 224 次波纹读取 + 28 次阴影可见性查询 + 1024² RGBA16F 源图. Steadfast 水路不含这些. **无整帧数据，不推断 FPS.** |
| 水下太阳圆而水外方 | **已解决**：`water.glsl:616` 的 `0.672*alignment` 对应 `lit.vsh:116` 的 `vertex.xz *= 1.12`，内外角尺寸一致. 程序模式保持圆形是设计意图（`docs/实现与限制.md` 明示）. |
| 阴影边缘锯齿 | 现行柔化（`diffuse.glsl:296-346`）已沿四角可见性梯度定向，世界半径下限 0.22 格，采样组数保持. **属已落实的改动，独立呈现数字不作为正确性证明.** 游戏细边效果待实机确认; 文档同时承认「跨0.48→0.52格移动的远端画面变化未消失，不能宣布所有闪烁解决». |

### 保留行为确认（未报为问题）
- 世界波面形态：`itt_water_waves.glsl` 六层 ITT 结构、权重 2/6/8/13/30/20、滚动与 AlmostIdentity 保留（`:51-75`）.
- 八点路径积分消弧纹：`light_shafts.glsl:131-149` 的 8 节点位置/权重，`:212` 在节点代表的分段内积分，`:143` 按样点屏幕足迹取 B 的 LOD，不平均法线、不横向模糊、不用历史.
- 正常阴影投射/接收面结构：`shadow.fsh:59-73` 的平面深度修正 + `shadowmap.glsl:203-222` 的四角参考深度 + `lit.fsh:162-165` 的接收面逐片元重投影.

---

## 真实未覆盖点

以下内容本轮未完整核对，**不作正确性断言**：

1. **云时域历史（`global/atmosphere/cloud_temporal.glsl`，11255 字节）的重投影契约.** W07（薄云边缘抖动）的实现未逐行验证; 只核对了 `clouds_planar.glsl:301-315` 的存在门与覆盖归属.
2. **`astra_cloud_ign()` 的空间去相关性质**（`clouds_planar.glsl:240` 依赖它论证固定相位不锁覆盖）.
3. **星空（`global/atmosphere/stars.glsl`，6413 字节）与云屏幕生产者（`program/cloud_screen.fsh`，5488 字节）的完整实现.**
4. **水下柔化的四方向核（`lib/water_diffusion.glsl`，7280 字节).** 只核对了调用点与参数范围.
5. **末地计算着色器（`program/end_star_catalogue.csh` 814 字节、`end_star_rows.csh` 1414 字节）与下界体素扩散（`program/nether_light.csh` 6230 字节、`lib/nether_voxel_grid.glsl` 3885 字节）.**
6. **`lib/water_buffer_formats.glsl` 中 `colortex4Format` 的具体声明**（文档称 RGB16F，源码未逐行确认）.
7. **`block.properties` 的完整方块→ID 映射**（12670 字节，只抽查关键行）.
8. **选项描述文件（`lang/zh_CN.lang` 32758 字节、`en_US.lang` 35028 字节）与实际 `#define` 值的一致性.**
9. **`lib/settings.glsl`（47029 字节）中未穷举的选项相互影响**，特别是 `ENTITY_SHADOW_DISTANCE` 的引擎钳位.
10. **Iris 1.11.2 的 `shadowIntervalSize` 默认值**（决定 P1#4 是文档误解还是实际行为差异）.
11. **AO 在水下路径的行为**：`ssao.fsh:48` 水下直接 return，`ao_resolve.glsl` 对全 invalid 的 colortex21 的处理未完整核对.
12. **所有整帧 GPU 性能数据.** 本报告所有性能判断只到源码成本结构与 `docs/实现与限制.md` 已记录的独立分项数字（源图 0.0696 ms、积分 0.8100 ms、倒影腿 0.3072 ms、50% 关闭投影长度 2.010/2.021/2.063 格），**不推断 1080p 平均 144 FPS 是否达成**.

---

# 增补：第二独立轮（补足首轮明确未读的活跃源码交界）

指定模型入口：workbuddy/space-bunny（用户称 space-bunny）。本节为同一份独立审查的第二轮追加，只增补、不改写上文任何结论；被下文推翻的上文条目按「撤销」处理并保留原文。本轮以当前实际文件为准，未读取其他审查报告，未修改任何源码。

## A. 撤销：光束积分长度与端点 alpha 是两个独立变量（P1#1 及依赖它的全部结论）

用户指出的链条经逐行复核成立，原文 P1#1 的推理前提错误，据此撤销。

`global/water/light_shafts.glsl`:
- `:152` `water_shafts_march(vec2 uv, out vec3 viewPos, out float marchLength)`——签名确实把 `marchLength` 作为独立 `out`。
- `:155` `water_shafts_view(uv, rayLength, sceneDepth, sceneFlags)`；`:53` `rayLength = min(length(viewPos - water_shafts_view_origin()), WATER_SHAFT_MAX_DISTANCE)`，其中 `WATER_SHAFT_MAX_DISTANCE = 128.0`（`:13`）。这是**端点到相机的真实距离**，被 128 上限截断，与积分窗口无关。
- `:161` `marchLength = min(rayLength, min(astraWaterShaftRange, WATER_SHAFT_FAR_END))`，`:170` 再被水面高度 `min(marchLength, depth/ray.y)` 收紧。这是**积分上限**，由 `astraWaterShaftRange = 48.0`（`lib/water_palette.glsl:11`）与 `WATER_SHAFT_FAR_END = 26.0`（`global/water/shaft_layout.glsl:8`）共同决定。
- `:171` `end = marchLength`；`:187` `stepLength = min(astraWaterShaftRange, WATER_SHAFT_FAR_END)/ASTRA_SHAFT_SAMPLES`；`:196-219` 循环只积分到 `end`。所以积分区间确实最多 26 格。
- **`:225` `return vec4(max(integral, vec3(0.0)), rayLength/WATER_SHAFT_MAX_DISTANCE);`——返回的 alpha 是 `rayLength/128`，不是 `marchLength/128`。** `marchLength` 在函数内只用于积分边界，函数返回后即失效。

因此「`marchLength <= 26` ⇒ `alpha <= 26/128`」不成立，α 的取值范围是 `[0, 48/128]`（经 `program/scattering.fsh:99-100` 封顶），与积分窗口无关。撤销下列原文结论：

1. **撤销 P1#1 的问题定性**（「`astraWaterShaftRange`(48) 与 `WATER_SHAFT_FAR_END`(26) 矛盾，单线性读取快路径不可达」）。`light_shafts.glsl:244` 的快路径条件是 `referenceLength >= astraWaterShaftRange`，其中 `referenceLength = min(clamp(rayLength,0,128), 48)`（`:236`），判定的是**端点距离**而非积分长度。当端点距相机 ≥ 48 格时条件为真，随后 `:246` 检查 `volumeSample.a == astraWaterShaftRange/WATER_SHAFT_MAX_DISTANCE`（即 α == 48/128）以确认该 texel 覆盖完整窗口。两者语义自洽，**不存在我原报告所称的"矛盾"或"快路径因 26 上限而不可达"**。

2. **撤销依赖该前提的采样成本结论**：模块 5「重建侧 `light_shafts.glsl:250-271`：4 次 `texelFetch`（因 P1-1 的快路径不可达）」与模块 9 P1#1 关联的「每像素多 4 次 `texelFetch`」表述均作废。正确表述：快路径**在端点距离 ≥ 48 格时可达**（1 次 `textureLod`），在近处或混合距离时走 4 次 `texelFetch` 的距离加权重建（`:257-267`）。四 texel 分支是近场常态而非全屏强制。

3. **撤销 P2「`docs/实现与限制.md` 关于光束积分上限的表述与源码不一致」**（原文标为与 P1-1 同根因）。重核后两者一致：`shaders.properties:8-10` 注释「integrate at most 48 blocks」描述的是**端点 alpha 的存储上限**（`scattering.fsh:99` 的 48 封顶）；源码的有效**积分**上限 26 由 `WATER_SHAFT_FAR_END` 控制，是另一个量。文档与源码各自描述不同变量，无可证实矛盾。

保留的观察（不依赖上述撤销项）：`WATER_SHAFT_FAR_END = 26` 与 `astraWaterShaftRange = 48` 确实是两个不同的窗口常数，`shaft_layout.glsl:7-8` 的 `FAR_START=14 / FAR_END=26` 参与 `:147` 的远端渐弱。**这仍是一个观感取舍点**（积分只到 26 而 alpha 允许到 48，意味着 26–48 段的端点在 `:244` 走快路径却拿不到超出 26 的积分能量），但它不是 bug，需要用户决定是否统一；我不把它当 P1。

## B. 撤销：`shadowIntervalSize` 由 `settings.glsl` const 控制，不是缺键

原文疑点「`shaders.properties` 全文没有 `shadowIntervalSize` 键…可能与文档描述不符」作废。该键是 Iris 读取的 `const`，不在 properties：`lib/settings.glsl:425-432`

```
// Iris's world-grid snap cannot align texels after radial distortion ...
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
const float shadowIntervalSize   = 0.0;
#else
const float shadowIntervalSize   = 0.5;
#endif
```

主世界恒为 `0.0`（禁用半格原点跳变），与 `docs/实现与限制.md` 的描述一致；下界/末地保留 Iris 默认 0.5。文档正确，**原疑点撤销**。

## C. 逐项补读：首轮列为未读的活跃源码交界

以下每项都按生产者→附件/输入→消费者与配置条件核对，行号为当前文件。

### C1 云时域历史（模块 6 + 模块 7）

覆盖：`global/atmosphere/cloud_temporal.glsl`（194 行，全文）、`program/cloud_screen.vsh/.fsh`、`lib/cloud_history_frame.glsl`、`lib/history_frame.glsl`、`global/atmosphere/clouds_screen.glsl`、`lib/cloud_sample_grid.glsl`、`shaders.properties:176-196`。

生产者链路核对通过：
- `cloud_screen.fsh:21` `/* RENDERTARGETS: 24,25 */`；`:30` 生产网格偏移 `astra_cloud_grid_offset(frameCounter, textureSize(colortex24,0))`，`:95-97` 写 `colortex24`（混合后 premultiplied 云）与 `colortex25`（元数据）。
- `:118` 的 `sampledVisible` 实参为 `visibleCloud && !occluded`，与 `:73` 的空列保护一致。
- `cloud_temporal.glsl:31-42` 声明 `colortex24Format = RGBA16F`、`colortex25Format = RGBA16F`、`colortex24Clear = false`（`RGBA16F` 由包含方 `cloud_screen.fsh:13-14` 提供，注释 `:25-27` 说明 Iris 预处理器对非选项 token 的 `#ifndef` 一律为真，故不得二次定义——这是真实的 Iris 行为约束，不是遗漏）。
- 重投影契约（`:109-123`）：先用 `dt = frameTime` 按 `astra_modify_trace_pos` 的 `z_world = c + t` 反向补偿 `vec3(0,0,dt)`，再用真实 `gbufferPreviousModelView/Projection` 与 `previousCameraPosition` 投影，`:118` 反加上一帧 jitter，`:119` 减上一帧网格偏移。**方向正确，不依赖 TAA 开关**（`cloud_history_frame.glsl:4-8` 在 `!ASTRA_TAA` 下自行声明前帧矩阵）。
- 每 texel 代表距离校验（`:132-152`）：`distanceTolerance = 16 + expectedDistance*0.03`，四角按 `meta.r` 过滤后再按 `meta.g`（帧号 mod 2048）与 `meta.b`（viewWidth 指纹）一致性过滤，避免跨帧/跨分辨率混入。
- 权重抑制（`:170-189`）：色彩跳变与覆盖跳变各有一条 `smoothstep` 衰减，空列另有 `emptyMotionWeight`（`:160-167`，按去除双 jitter 后的真实屏幕运动 `smoothstep(0.5,2.0)` 抑制），因此"薄云边缘抖动"（W07）有对应的实现而非文档空话。

帧有效性入口：`cloud_screen.vsh:12` `cloudFrameValid = int(astra_cloud_history_frame_valid())`，`flat out`；`.fsh` 侧 `cloud_temporal.glsl:44` `flat in`。有效性判据 `cloud_history_frame.glsl:12-16`：时间不连续、`frameCounter <= 1`、`frameTime` 越界（<0 或 >0.5）或 `history_frame.glsl` 的相机位移 >8 格 / 投影矩阵变化超 1e-4 时全部拒绝。**未见可证实缺陷**。

消费者：`clouds_screen.glsl:5-13` 在 `ASTRA_CLOUD_TEMPORAL` 下采样 `colortex24`（否则 `colortex12`）；`:34-44` `astra_screen_cloud_sample` 先按当前帧网格偏移反解 UV 再取样；`:49-61` `astra_screen_cloud` 在地形终点贴近时重新 march，否则用缓存。`colortex24/25` 尺度 `shaders.properties:179-196`：`CLOUD_MODE == 1 && CLOUD_TEMPORAL` 时按预算/质量取 0.25/0.25/0.5/1.0，否则 `1 1`。

尺寸一致性核对：`cloud_temporal.glsl:120` 用 `textureSize(colortex24,0)` 自身计算 margin 与网格偏移，`:128` 同样用 `textureSize(colortex24,0)` 取历史尺寸——**全部按运行时实际尺寸，不硬编码**，因此与 properties 的多分支尺度自洽。**P0/P1：无**。

疑点：`ASTRA_CLOUD_TEMPORAL_WEIGHT = 0.90`（`:48`）与 `EMPTY_WEIGHT = 0.95`（`:52`）注释自承「needs in-game A/B like every constant in this module」。这是**已承认的未验证取舍**，非缺陷；且 `weight *= coverage`（`:181/:183`）使薄云实际历史占比低于名义值。不冒充 bug。

### C2 水下四方向柔化（模块 5）

覆盖：`lib/water_diffusion.glsl`（120 行，全文）。

核对通过：
- 方向核 `:69-80`：主世界预算（`ASTRA_OVERWORLD_OPTIMIZED`）下为四个对角 `0.70710678`（各轴正负），非预算路径为四条轴向 `vec2(±1,0)/(0,±1)`。`:70-72` 注释说明旧版"单对角对"沿单轴涂抹、实测像没有模糊，故改为四抽头环——**这是针对用户"水下布局挤/不清晰"的实际改动，不是简化呈现**。
- 半径随输出高度缩放 `:66-68`：`mix(1.2,3.0,distanceBlend) * viewHeight/1080`，保证 1080p 与其他分辨率观感一致。
- 深度边缘守卫 `:92-103`：子像素偏移回到中心深度时复用中心深度（颜色仍按自身 UV 双线性），前向 tap 以 `smoothstep(-1.2,-0.2, signedDepth/depthTolerance)` 归零（属于更近的不同表面），同深度与更远 tap 保留——水下远景地形仍会柔化。
- 雾深捷径 `:39-45`：`hazeDistance = rayLength²/(rayLength+2)` 与 `astra_water_haze_density/far_gain` 估算的雾深超过 `smoothstep(2.2,3.4)` 后直接返回中心，避免在雾已压平场景时做无用 4 抽头。`UNDERWATER_FOG_DENSITY <= 0` 直接返回（`:25-26`）。
- 材质/手记录复用 `:52-61`：水面接口水平/侧面（`water_interface_is_horizontal/side`）与手持记录（flag 128）直接跳过柔化，head-level 水窗与瀑布壁保留波纹细节。注释 `:11` 明示该文件"never touches colortex1"，**因此不会掩盖加性光束颗粒**。
- TAA 偏移一致性 `:104-106`：颜色网格与深度网格携带相同偏移（颜色未抖动、深度已光栅化），只对完全相同的几何复用深度。

未发现可证实 P0/P1/P2。**疑点**：`:67` 半径上限 3.0 像素（1080p）是硬编码观感常数，无 A/B 记录；`strength` 上限 0.48（`:42`）同样自承经验值。属未验证取舍，非缺陷。

### C3 下界/末地计算着色器与体素扩散（模块 8）

覆盖：`program/nether_light.csh`（129 行，全文）、`lib/nether_voxel_grid.glsl`（71 行，全文）、`program/end_star_catalogue.csh`（18 行，全文）、`program/end_star_rows.csh`（36 行，全文）、`lib/end_star_catalogue.glsl`、`world1/setup.csh/setup1.csh/setup2.csh`、`shaders.properties:65-67/:808-861`。

下界体素光核对通过：
- 九步链由 properties 从外部开关（`:827-847`）：`program.world-1/shadowcomp{,1..8}.enabled` 在 `#if defined SHADOWS && defined NETHER_VOXEL_LIGHT && BLOCKLIGHT_STRENGTH > 0` 下全开，否则全关——`:812-816` 与 `:822-824` 注释明确记录 Iris 只解析 `program.*` 维度命名族、`compute.*` 拼写是死键，两分支都显式列出每个键以免漏关。`world-1/shadowcomp*.csh:2` 各自 `#define ASTRA_LIGHT_STEP 0..8`。
- `nether_light.csh:14` `workGroups = ivec3(8,8,8)` 与 `:13` `local_size 8,8,8` → 64³，与 `nether_voxel_grid.glsl:35` `ASTRA_NETHER_VOXEL_SIZE 64` 及 properties `:856-860` 的 `64 64 64` 图像尺寸一致，三处对齐（头文件 `:18-33` 把这些字面量列为不可从该头派生的外部接口）。
- 步 0 只重建源活动并 `imageAtomicOr` 到 tiles 位图（`:98-103`，`tile = WorkGroupID>>1` → 4³ 个 16³ tile 编入两个 R32UI texel，与 properties `:858` 的 `2 1` 及头文件 `:25-27` 一致）；步 >0 才做 6 邻域 `max` 传播（`:110-126`，`incoming*0.72` 衰减）；奇偶步交替读写 `astraLightA/B`（`:46-50`、`:116-120`），ping-pong 无自读。
- `world-1/shadow.vsh:1` 用 `#version 430 compatibility`（`uimage3D` + `imageAtomicMax` 需 420+），其余维度薄入口为 400——版本边界正确。

未发现可证实 P0/P1/P2。**疑点**：`:32-33` 的 tile 掩码扫描窗口 `start ± ASTRA_LIGHT_STEP` 只在传播步使用，理论上步 8 时 `high - low` 可达 24（>16 tile 宽度），但 `>>4` 后仍落在 `low.z..high.z` 实际 tile 范围内且 `xMask` 以 `high.x-low.x+1` 位构造——**我未运行验证 8 步时的位掩码是否越界读取 tile 位图**，标为疑点不冒充 bug。

末地星表核对通过：
- `end_star_rows.csh`（1 个 workgroup，64 lane，每 lane 8 行）先写 512 条行元数据到 `colorimg31` 的第 0 行（`:32-33`，`vec4(columns, hash, offset, 1)`），`:26` `barrier()` 后用 `rowBlockTotals` 前缀和算全局 offset；`end_star_catalogue.csh`（151×64 workgroups）读元数据行、按 `slot = row.z + cell.x` 把星点哈希写入 `colorimg31` 的二维区（`:12-17`）。生产者顺序由 `world1/setup.csh`（rows）→ `setup1.csh`（catalogue）→ `setup2.csh`（1×1 空 dispatch，仅为宿主 image barrier，`:1-7` 注释说明 Iris 1.11.2 在 dispatch 前插入屏障）保证可见性。`lib/end_star_catalogue.glsl:16-22` 的读侧 `end_star_row/presence` 与写侧 slot 布局 `slot%1024, slot/1024` 对齐。
- `end_star_catalogue.csh:8` `layout(rgba32f) uniform image2D colorimg31` 与 properties `:67` `size.buffer.colortex31=1024 384`、头文件 `:12` `colortex31Format = RGBA32F`、`colortex31Clear = false` 一致。`:11` 边界 `cell.x>=1200 || cell.y>=512` 与 `END_STAR_EQUATOR_CELLS=1200 / END_STAR_ROWS=512`（头文件 `:5-6`）一致。

未发现可证实 P0/P1/P2。**疑点**：`colortex31Clear = false` 且无任何 clear 路径，两个 setup dispatch 每帧重写全部槽位，理论上不依赖初值；但若 Iris 在某帧跳过 setup（如维度切换首帧）而消费者已就采样，未初始化 FP32 内容的风险**缺运行证据**，不冒充 bug。

### C4 格式声明（模块 1）

核对 `water_buffer_formats.glsl`、`surface_buffers.glsl`、`cloud_buffer_formats.glsl`、`end_star_catalogue.glsl` 与消费者：
- `water_buffer_formats.glsl:12/:15/:24/:26/:30` 分别声明 `colortex0/2/4/7`。`colortex4Format` 在 `ASTRA_BLOOM && !NETHER && !END` 时为 `RGB16F`（`:24`），否则 `R11F_G11F_B10F`（`:26`）——**文档称 RGB16F 与源码一致**。生产者 `program/itt_water_normal_cache.fsh:13-14` 与消费者 `taa_resolve.fsh:6-8`（仅主世界泛光）条件相同，格式与用途对齐。
- `surface_buffers.glsl:14/:17/:24/:28` 在 `ASTRA_SSAO` / `ASTRA_SSAO && ASTRA_DIRECTIONAL_SKYLIGHT` / `ASTRA_TAA` 下分别声明 `colortex19/20/27/22`，全部带 `ClearColor`；`RGBA16F`/`RGBA8` 由 `:3-12` 的 `#ifndef` 保护避免二次定义（Iris 预处理器约束）。
- `cloud_buffer_formats.glsl:13` `colortex12Format = RGBA16F`，两个生产者 `cloud_screen.fsh`（无历史时）与 `sky_gradient_cache.fsh`（低频天空表）共用——头文件 `:4-6` 注释说明格式单一来源。`sky_gradient_cache.fsh:7` `/* RENDERTARGETS: 12 */` 与 `cloud_screen.fsh:25` `/* RENDERTARGETS: 12 */` 二选一受 `settings.glsl:707-711` `ASTRA_GRADIENT_SKY_CACHE` 与 `:700-704` `ASTRA_CLOUD_TEMPORAL` 互斥门控（云历史开时 12 归天空表用）。**无格式冲突**。

原文未读点 6（`colortex4Format` 具体声明）**关闭**：与文档一致。

### C5 材质映射（模块 3 / 模块 9）

`block.properties` 抽查（全文 12670 字节，本轮读前 60 行 + 关键行）：`:29` 水（10001）、`:32` 树叶/藤/苔（10002，SSS 合格）、`:35-37` 无方向光植被（10003）、`:40` 一格高 waving 小植物（10004）、`:43/:46` 双格植物上下半（10005/10006）、`:49` 末地传送门星效（10007）、`:53` 末地石粗糙高光（10012）、`:55` 黑曜石独立湿标志（10017，lighting material 仍 0）、`:59` 阴影透明玻璃（10010，投射彩色影经 shadowcolor0）。**头部注释 `:4-23` 的 ID 分配表与各行实际映射一致**，未发现未分类方块落入 material 0 的证据。原文未读点 7 降级为低优先残留（未逐行核对全部 12670 字节），不再列为活跃缺口。

### C6 语言文件一致性（模块 9）

程序化比对 `lang/zh_CN.lang` 与 `lang/en_US.lang`：`option.*` 键集**完全一致**（各 161 键，无单边键）。`option.*` 键与 `lib/settings.glsl` 的 `#define NAME` / `const` 集合比对：166 个选项 define，161 个 lang 键，差集为 `AUTO_EXPOSURE / CLOUD_SHADOWS / DIRECTIONAL_SKYLIGHT / GODRAYS / GODRAYS_SUN_OCCLUSION / ROUGH_SKY_REFLECTIONS / SCREENSPACE_AO / UNDERWATER_PARTICLES / VIGNETTE / VOLUMETRIC_FOG / VOXY_SUPPORT / sunPathRotation`——逐一核实：前 11 项在 settings 中以注释形式 `//#define NAME // [false true]` 存在（`:37/:39/:116/:146/:169/:204/:227/:246/:250/:257/:343`），`sunPathRotation` 是 `const float`（`:434`）。**因此无 lang 键指向不存在的选项**。原文未读点 8 关闭：无不一致。描述文字与 `#define` 具体取值的逐条语义核对仍有限，但键级一致性已证实。

### C7 实体距离钳位（模块 2 / 模块 9）

原文疑点「README『实体投影维持 32 格』与 profile 里的 48/64/96 未见钳位代码」**升级为已解答**。钳位在 `lib/settings.glsl:446-457` 的主世界预算分支：

```
#if defined ASTRA_OVERWORLD_OPTIMIZED
#if SHADOW_DISTANCE == 64
const float entityShadowDistanceMul = 0.444444444;   // 64*...=~28.4? 语义见下
...
#else
const float entityShadowDistanceMul = 0.253968254;
#endif
```

`settings.glsl:439-441` 注释说明 Iris 把 `shadowDistance * shadowDistanceRenderMul * entityShadowDistanceMul` 相乘后交给 `createShadowFrustum`。预算分支只按 `SHADOW_DISTANCE` 选一个固定比值（64→0.4444…、80→0.3556…、96→0.2963…、其余→0.253968…），对应把实体投射距离**统一钳到约 32 格**（例：`SHADOW_DISTANCE=112` 时 `112*1.125*0.253968≈32.0`）。profile 里的 `ENTITY_SHADOW_DISTANCE=48/64/96` 在**预算开启**（四档 profile 全部 `OVERWORLD_BUDGET=1`）时被该分支忽略，README「实体投影维持 32 格」**与源码一致**，不是矛盾。原文 P2#9 与疑点「需核对钳位」**关闭**。

未发现可证实 P0/P1/P2。**疑点**：`ENTITY_SHADOW_DISTANCE` 在预算开启时是死设置（`settings.glsl:448-457` 分支不引用它），与光束样本数（模块 9 P2）属同类"profile 声明被预算静默钳制"现象；但此处 README 已声明预算语义，属有意钳制，仅标注影响。

### C8 AO 水下分支（模块 3）

覆盖：`program/ssao.fsh`（134 行，全文）、`lib/ao_resolve.glsl`（99 行，全文）、`lib/ao_material.glsl`（9 行，全文）、`program/lit.fsh:382-411`。

核对通过：
- 生产侧 `ssao.fsh:42` 先写中性 `gl_FragData[0] = vec4(1.0,-1.0,0.5,0.5)`，`:48` 水下非薄水膜直接 return——所以水下像素的 `colortex21` 保持 `visibility=1.0, depth=-1.0`。`:46` 方向天光槽在 return 前已写中性。
- 消费侧 `ao_resolve.glsl:33-35`：每角读 `colortex21`，`depthDifference = abs(ao.g - depth)`，`:35` `if (ao.g < 0.0 || depthDifference > 0.05) continue;`——**全 invalid（`ao.g=-1`）的水下角全部被拒**，`weightSum` 保持 0，`:52` `return weightSum > 0.00001 ? sum/weightSum : 1.0;` 返回 1.0，即**水下不施加 SSAO 变暗**。原文未读点 11 关闭：行为正确，无悬挂/错误采样。
- `ao_resolve.glsl:55-58` `astra_apply_ambient_ao` 也在 `isEyeInWater != 0 && !water_is_thin_sheet()` 时直接返回场景；`ao_material.glsl:4-8` `astra_ao_receiver` 同样以 `isEyeInWater == 0 || water_is_thin_sheet()` 为前提，且材质需 `material == 0u || material >= 11u`（排除 1..10 的水/植被/玻璃类）。
- 生产侧 `lit.fsh:392-402` 仅在 `astra_ao_receiver(material)` 且非 translucent 时写 `colortex19/20`（ambient + 打包法线/AO 字节），水下片元不写 → 消费侧 `:57` `normal.a < 0.5` 时同样早退。**生产者与消费者在水下判定上完全一致**（同一 `water_is_thin_sheet()` 谓词）。

未发现可证实 P0/P1/P2。

### C9 后处理/AA/历史的补充交叉核对（模块 7）

覆盖：`program/taa_state.fsh`、`program/taa_resolve.fsh`（186 行，全文）、`lib/taa_state.glsl`、`lib/taa_reactive.glsl`、`lib/taa_jitter.glsl`、`program/effect_history.vsh/.fsh`、`lib/effect_history.glsl`、`program/nether_reflection.fsh`。

- TAA 状态元数据与云历史、效果历史采用**同一套 `viewport/effects/identity` 三行契约**（`taa_state.fsh:14-23`、`effect_history_state.fsh:14-16`、`cloud_temporal.glsl:68-86`），帧号取 `frameCounter % 4096`（TAA/效果）或 `% 2048`（云，`:68`），有效性判据一致。无跨模块不一致。
- `taa_resolve.fsh:99-105` 水中（`isEyeInWater != 0`）直接用当前帧并把历史标记为 `-1`（无效），与 `taa_state.glsl:24` 的 `viewport.w != float(isEyeInWater)` 门控配合——**入水当帧历史自动作废**。`:101` 在导数前早退，符合 GLSL 规范。
- `taa_resolve.fsh:88-91` 场景采样加当前 jitter 而历史/输出不抖动；`lib/taa_jitter.glsl:35-37` `astra_jitter_clip` 同步加 `2*uv*w`，`:11`/`:28` 水中返回零抖动——**生产与消费抖动一致**。
- `taa_resolve.fsh:114-119` 无有效帧时仍计算 reactive 并写深度身份，保证次帧可恢复；`:174` 用 YCoCg 空间做包围盒裁剪，`:172` 权重 `mix(0.92,0.70,motion)*(1-reactive)*h.a*colorTrust*centreTrust`——多项抑制保守。**未见鬼影/拖影的可证实逻辑缺陷**。
- 下界反射 `nether_reflection.fsh:75-143` 历史重投影：`:79` `astra_effect_previous_screen` 用真实前帧矩阵，`:100-103` `sharedPenalty` 同时惩罚屏幕位移、相机位移、接收体位移与出屏，`:129` 额外按法线差 12 倍惩罚，`:134` 新帧权重 `min/valid` 夹在 [0,1]——保守稳定。`:81-82` 显式过滤 NaN/Inf/出屏。**核对通过**。

未发现可证实 P0/P1/P2。

## D. 本轮新增的确定性问题

**无新增 P0。** 本轮逐行补读未发现新的可证实 P0/P1/P2；唯一实质动作是撤销原 P1#1 及其三处依赖结论、关闭两项疑点/未读点。撤销后，原文 P1 从 4 项降为 3 项（#2 ULTRA 样本数钳制、#3 README 硬件深度比较矛盾、#4 `shadowIntervalSize`——后者已在 B 节撤销），实际存活的 P1 为 2 项：

1. **P1#2（存留）** ULTRA `UNDERWATER_SHAFT_SAMPLES=10` 被主世界预算钳到 7（`shaders.properties:567` + `light_shafts.glsl:21-25`）。属有意钳制，profile 行缺注释。
2. **P1#3（存留，且本轮已补全证据链）** README 称主世界预算「采用硬件深度比较」，`settings.glsl:365-369` 在预算开启时强制 `ASTRA_SHADOW_FILTER_MODE = SHADOW_FILTER_SOFTWARE`，且 `:68` 默认 `SHADOW_FILTER_MODE 0` 亦为软件。本轮补核 `settings.glsl:657-667`：Iris 侧布尔 `shadowHardwareFiltering{,0,1}` 由**同一个** `ASTRA_SHADOW_FILTER_MODE` 派生（`#if ASTRA_SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE`），不是另一套机制。因此**预算开启的主世界下，着色器内所有软件/硬件过滤分支都取软件路径，当前无任何默认配置使用硬件比较**。这是可证实的文档-源码矛盾。

## E. 本轮后的真实剩余缺口

以下为本轮**仍未能从源码确认**的事实，不作正确性断言：

1. **全部整帧 GPU 性能**。无任何整帧数据，**不推断 1080p 平均 144 FPS**。所有成本只到源码循环结构与 `docs/实现与限制.md` 已记录的独立分项数字。
2. **下界体素 8 步传播时 tile 位掩码是否越界**（`nether_light.csh:32-38`，见 C3 疑点）需实机或离线复算。
3. **`colortex31` 在维度切换首帧是否可能未初始化即被采样**（C3 疑点）缺运行证据。
4. **`block.properties` 全部 12670 字节未逐行核对**（C5 只抽查头部与关键行；键级映射一致但个别方块归属未穷举）。
5. **lang 描述文字与各 `#define` 取值的逐条语义**未穷举（C6 只证实键级一致，无错键；描述与具体取值的语义对应仍可能有个别偏差）。
6. **光束积分窗口 26 与端点窗口 48 的观感取舍**（A 节保留项）需用户决定是否统一，非缺陷但影响水下远处光束能量分布。
7. **`lib/settings.glsl`（47029 字节）中未穷举的选项相互影响**，除光束样本数与实体距离外，仍可能有其他选项在特定组合下互相覆盖。

撤销后，原文 P2 五项（#5 `lightDir` 死参数、#6 波长展宽、#7 `stride` 死代码、#8 采样点接缝、#9 实体距离）经本轮复核：#9 关闭（见 C7）；#7 措辞需限定为"仅在 `projectedMarch` 路径下失效"，因下界/末地与预算 0 的湿地形仍走 `stride`（`raytrace.glsl:272-273` 门控、`:286/:375/:377` 使用），但结论"主世界预算下为死代码"本身正确，不撤销。P2 其余项未在本轮重核，维持原文。
