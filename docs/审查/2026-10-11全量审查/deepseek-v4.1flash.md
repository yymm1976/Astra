# Astra 全量独立代码审查 — DeepSeekV4.1flash

- 指定入口：`group/auto-deepseek-v4-1-flash`（用户称 DeepSeekV4.1flash）。本报告只声明被指定的入口标识，不声称了解该入口后台实际由哪家提供商提供。
- 审查对象：`C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发`，以 `Astra/shaders/` 当前工作区文件为准（含未提交改动）。审查期间主代理已暂停源码修改，下文行号对应当前文件。
- 范围：九模块全部覆盖，沿「生产者 → 附件/输入 → 消费者」与配置条件核对，不按关键字抽查。同时读 `docs/当前工作.md`、`docs/实现与限制.md`、`README.md` 指向的入口，并按需读本地参考（ITT 3.2 `UnderwaterVolumetricFog.glsl`/`WaterWaves.glsl`）。文档与既有 AI 结论不作为正确性证明。
- 未读取其他审查者报告；未写源码或共同文档；未运行游戏、未调用子代理、未做哈希/基线/冒烟/测试/备份类流程。

## 用户五项关注点的落点

| 关注点 | 落点模块 | 当前源码可核实的事实 |
|---|---|---|
| 水面树叶倒影缺失 | 4 | 真实纹元交点查询与四角自交点接受存在，但只在主世界预算内（`ASTRA_OVERWORLD_OPTIMIZED`）编译；原始档仍走旧粗搜索。剩余漏采比例无法由源码判定 |
| 水下光束数量少且布局挤 | 5 | 每像素单一波面入射投影（`light_shafts.glsl:174`）+ 每段 4 节点、每节点 8 点路径积分；与 ITT 逐样点评估结构不同。源码不能证明数量/布局结果 |
| 水面/水下开销高于 Steadfast | 4/5/9 | 只能确认成本项（迟绘实体记录、逐角介质传输、8 点积分、RGBA16F 源图含 mip 约 10.67 MiB/张）；无整帧数据，不推断 FPS |
| 水下太阳圆而水外方 | 5 | 当前 vanilla 模式内外都是方形贴图（`water.glsl:616` 的 `0.672*alignment` 与 `lit.vsh:112-116` 的 `vertex.xz*=1.12` 对应）；程序模式内外都是半径 0.028 圆盘（`sky.fsh:107`、`water.glsl:623`）。形状按模式一致 |
| 阴影边缘锯齿 | 2 | 中档 2 个附加 lobe 沿四角可见性梯度，额外偏移受 `max(0.22格,0.75×像素世界足迹)` 限制；1536/112 影图近中心约 1 纹元≈3.3cm。算术可核，实机细边未确认 |

## 已在当前源码核实具备（主代理已改，不作为未处理项）

以下四处以当前文件为准已成立，发现时刻的旧状态不再适用：

1. `shaders.properties:517-523`：`ittWaterNoise` 在 `WATER_WAVES || (UNDERWATER_LIGHT_SHAFTS && SHADOWS && SHAFT_STRENGTH>0)` 下独立注册；`shaders.properties:526-532`：`astraSunTexture` 在 `SUN_MOON_MODE == 0` 下独立注册，并按 `MC_VERSION >= 260100` 选择 `environment/celestial/sun.png` 或 `environment/sun.png`。
2. `program/water.glsl:609-616`：vanilla 太阳贴图 UV 除数 `0.672*alignment` 与 `program/lit.vsh:112-116` 的 `vertex.xz *= 1.12`（半宽 30/距离 100）一致。
3. `program/deferred.fsh:395-435`：平面云透射按 `displayed += (clearSky + source)*(1.0-cloud.a)` 合成，星场在 418-425 并入 `clearSky`，`source` 为日月 sprite。
4. `global/water/raytrace.glsl:257-264`：远侧 12 粗查询上限仅对 `(surfaceBudget || underwater)` 生效，湿地/其他维度仍为 8。

## 模块 1 入口 / 程序调度 / GLSL 条件 / 附件格式与清屏 mip 翻转 / 资源与宿主兼容

覆盖的关键文件与交界：`shaders.properties`（缓冲尺寸 7-218、pass 使能 296-412、blend 覆盖 356-441、profile 564-567、customTexture 514-536、`iris.features.optional` 851）；`lib/settings.glsl`（enum 18-34、预算上限 382-423、`shadowIntervalSize` 428-432、清屏色 733-747）；`lib/transforms.glsl`；各 pass 外壳（`composite2/3/4/5/6/8`、`gbuffers_*`、`prepare*`、`shadow*`、`world1/`、`world-1/`）；格式声明 `lib/water_buffer_formats.glsl`、`lib/surface_buffers.glsl`、`program/lit.fsh:22`、`program/water_state.fsh:13`、`program/itt_water_normal_cache.fsh:12`、`program/shadow.fsh:47`；`lang/en_US.lang`、`lang/zh_CN.lang`。

结论：入口与调度自洽。`shadow.culling=false`（353）保留视野外必要投影；`shadowIntervalSize=0` 仅主世界（`lib/settings.glsl:428-432`），与消费端共用连续矩阵；`flip.*` 无显式键，走 Iris 默认；格式声明在多个编译单元中由同一 `settings.glsl` 状态导出，未发现冲突。尺寸与 pass 使能条件配对（例：`colortex1` 16-26 与 composite2 的 317-321、`colortex29`/`prepare4` 206-212 与 scattering 的 shafts 条件、`colortex12` 70-91 与 `ASTRA_GRADIENT_SKY_CACHE` 判定 708-711）。

`GL_ARB_shading_language_packing` 疑点已排除：仅根目录 `gbuffers_entities.fsh`、`gbuffers_entities_translucent.fsh`、`gbuffers_water.fsh` 声明该扩展；`world1/`、`world-1/` 同名外壳不声明，但它们也不会编译到使用 `packHalf2x16` 的代码——`program/lit.fsh:15-30` 与 `program/lit.fsh:437-444` 的迟绘实体记录写、以及 `program/water.glsl:16-19` 的实体记录 include，都以 `!defined DIMENSION_NETHER && !defined DIMENSION_END` 为前提。因此维度外壳既不声明也不使用该函数，不构成缺失。

`#version`：`world-1/shadow.vsh` 为 430（`uimage3D`/`imageAtomicMax` 需要 420+），根 `shadow.vsh` 与 `world1/shadow.vsh` 为 400；`world-1/shadowcomp*.csh`、`world1/setup*.csh`、`world-1/nether_light.csh` 均为 `430 compatibility`。可核实一致。

P0/P1/P2：无可以证实的问题。

未证实疑点：`lib/itt_water_field.glsl` 的 mip 生成时序依赖宿主（见模块 5）。宿主兼容性（Iris 版本对 `CUSTOM_IMAGES`/`COMPUTE_SHADERS` 缺省时的行为）按 `docs/实现与限制.md:138` 属已知 D07 债，源码内无替代实现，属缺失事实而非新缺陷。

## 模块 2 阴影投射 / 接收过滤 / 彩影焦散与覆盖边界

覆盖的关键文件与交界：`global/lighting/shadowmap.glsl`（`shadowTexelSpread` 104、`shadow_uv_coverage` 124-135、`shadow_coverage` 136-140、接收面平面状态 143-167、gather 重排 169-174、`shadow_gather_visibility` 176-200、参考深度 202-222、lobe 光照 246-356、不透明可见性 359-372、`shadow_map_position` 380-432）；`global/lighting/diffuse.glsl:277-399`；`program/shadow.vsh`、`program/shadow.fsh`（焦散焦点 A 116-118、彩影 GBA 131-147、`depth_greater` 34-38、投射面深度修正 59-74）；`shadow_solid.vsh/.fsh`；`program/lit.vsh:203-216`（接收面分类）与 `program/lit.fsh:3-6`；`lib/distort.glsl:16-17`；`lib/settings.glsl:382-423`。

结论：生产者与消费者沿同一畸变矩阵、同一纹元中心逆投影与同一组配对深度核对，未发现结构性错配。彩影只在真实半透明投射物上写入 GBA（`shadow.fsh:131-147`），水面投射物写 `A=焦散焦点`、`GB` 无读者（`shadow.fsh:104-119`），与消费端 `shadowmap.glsl:344-353` 的 `caster.r < WATER_HEIGHT_NONE` 分支对应。覆盖边界用 `shadow_map_fade`（109-123，24/8 渐退带）与 `shadow_uv_coverage`（径向 + 边框）双层渐退，未发现硬切。

P2（可核实算术，实机未确认）：中档柔化在近中心的有效核很小。`diffuse.glsl:315-318` 先算 `worldTexel = 2*shadowDistance*SHADOW_DISTORT_FACTOR/(resolution*mapRim²)`，再令 `spread = min(SHADOW_SOFTNESS*0.5, softRadius/worldTexel)`，其中 `softRadius=max(0.22,0.75*pixelWorld)`。以均衡档 1536/112 计，`SHADOW_DISTORT_FACTOR=25.6/112≈0.2286`，近中心（`mapRim→1`）`worldTexel≈51.2/1536≈0.0333` 格；若接收面像素世界足迹约 0.02 格，则 `softRadius=0.22` 格，`spread=min(1.0, 0.22/0.0333≈6.6)=1.0` 纹元。即中档额外偏移在近中心被限制在约 1 纹元（≈3.3 cm），加上中心 2×2 双线性，总核仍小于细边所需的宽度；而在径向边缘 `worldTexel∝1/mapRim²` 迅速增大，`spread` 收缩到约 0.07 纹元，附加柔化基本退出。触发条件：均衡档 + 1536/112 + `SHADOW_FILTER_QUALITY==1`（仅 2 个附加 lobe，`diffuse.glsl:300-304`、319-346）。结果：细长投射物的边缘锯齿可能仍可见。依据：上述常量与算术。建议：若实机确认，优先考虑中档把 `softRadius` 下限从 0.22 格放宽，或在近中心允许超过 1 纹元的附加偏移；不建议以抬升影图分辨率作为默认手段（会与既定预算冲突）。这一取舍在源码注释（310-313）中已明示为有意为之，故按影响记录而非误报。

未证实疑点：`shadow.fsh:59-73` 的投射面深度修正只在 `waterCasterKind==0` 且 `|det|>1e-20` 时生效；薄投射物低于纹元宽度、纹元中心落在三角面真实范围外时仍为栅格近似（`docs/实现与限制.md:13` 已声明）。`SHADOW_FILTER_MODE=0`（软件）与硬件分支在 `shadowmap.glsl:175-200` 下的精度差异无法由源码判定。

## 模块 3 材质直接/间接照明、AO/SSS/体素、实体与手

覆盖的关键文件与交界：`program/lit.fsh`（头 1-55、MRT 槽定义 53-145、faceData 解码 189-198、水/雨 199-268、albedo/湿润 269-347、照明 348-410、湿地光泽 412-420、末地高光 421-431、迟绘实体记录 437-444、水/冰 445-462、半透明介质 463-481、TAA 反应写入 489-520、colortex3 积水掩码 521-547、水界面记录 548-556）；`program/lit.vsh:38-57`（`astra_material` 映射）；`lib/encoding.glsl`；`lib/ao_material.glsl:4-8`；`lib/ao_resolve.glsl:13-53`；`global/lighting/sss.glsl:7-58`；`global/atmosphere/weather.glsl`；`lib/water_entity_record.glsl`；`block.properties`；`entity.properties`。

结论：材质 4 位字段分配与消费自洽：`astra_material`（`lit.vsh:38-57`）产出 0..15，`lit.fsh:195-198` 解出 `water=1`、`ice=9`、`material=11`（末地石）；AO 接收者 `astra_ao_receiver`（`ao_material.glsl:4-8`）仅取 `material==0 || material>=11` 且要求空气相机或薄水片，与 `lit.fsh:392` 的写入、`deferred.fsh:268` 的消费、`lit.vsh:86-90` 的顶点 AO 预乘条件一致。迟绘实体记录用 `RG32F` 半精度打包 + `ONE/ONE_MINUS_SRC_ALPHA` 混合（`shaders.properties:363-364`），分数透明片元写零保留先前记录（`lit.fsh:442-443`），与 `water.glsl:64-65`、`water.glsl:206/424` 的读取配对。SSS 仅做阴影外 wrap，阴影内因子由 `shadowmap.glsl` 提供，二者不重复（`sss.glsl:39-47`）。

P0/P1/P2：无可以证实的问题。

未证实疑点：`lit.fsh:494` 的 TAA 反应掩码把 `material>=1 && <=10` 视为反应（含玻璃 8、冰 9），实体与手在 `!defined ASTRA_TERRAIN` 时固定 `reactive=1`（`lit.fsh:492`）；这与 D04（实体缺每实例前帧输入）一致，属已知取舍。`lib/ao_resolve.glsl:35-38` 的深度/法线一致性门限（`0.05`、`0.85`）在陡峭地形上的表现无法由源码判定。

## 模块 4 水面波纹 / 反射 / SSR / 折射介质 / 迟绘身体 / 界面两侧

覆盖的关键文件与交界：`program/water.glsl`（`water_source_glint` 120-134、快速足迹 193-290、`water_sample_path` 292-542、垂直界面 558-596、`water_transmitted_sun` 604-636、水下界面 638-748、`astra_water` 750-1012）；`global/water/raytrace.glsl`（预算 15-56、自适应门 54-56、`water_ssr_footprint_crossing` 124-175、`water_raytrace` 178+、自适应预算 247-267、粗步进 282-379、细化 385-461、端点重建 462-477、重载 480-499）；`global/water/refraction.glsl`；`global/water/optics.glsl`；`global/water/absorption.glsl`；`lib/water_palette.glsl`；`lib/water_surface_budget.glsl`；`lib/water_interface_record.glsl`；`lib/water_entity_record.glsl`；`program/water_composite.fsh/.vsh`；`program/display.fsh:105-147`；`gbuffers_water.*`、`gbuffers_hand_water.*`。

结论：界面两侧与介质只施一次。水上：`astra_water` 用 Schlick 下限 0.042（776）、`screenReflectionShare` 在 0.045~0.085 渐入（824）、命中后 `water_sample_path` 逐角传输（853-856）、天空回退（860-874）；水下：`astra_underwater_interface` 以玩家头部为窗口中心（641-653）、精确 Fresnel 加 0.012 抬升（657）、SSR 与折射分别处理（661-740），返回前只做一次 gamma 往返。`display.fsh` 与 `water_composite.fsh` 在水下只走其一（`ASTRA_BLOOM` 分支），未发现同一相机水段重复施雾。

P2（可核实，条件性覆盖）：树叶质量修正只在主世界预算内存在。`raytrace.glsl:124` 的 `water_ssr_footprint_crossing` 整段被 `#ifdef ASTRA_OVERWORLD_OPTIMIZED` 包裹，细化循环内的调用（423-435）同时要求 `standardProjection && projectedMarch`。因此 `OVERWORLD_BUDGET==0`（用户选「关闭」）时，叶片的真实纹元/自交点接受路径不参与，粗查询上限仍由 248-249 的 `mix(max(6,COARSE/2), COARSE, queryImportance)` 决定（`WATER_EFFECT_QUALITY==0` 时为 ≤8）。触发条件：主世界性能预算选「关闭」。结果：在原始档下，错层树冠的漏采不会获得本轮修正。依据：上述宏门。建议：若原始档也需该质量，把该函数与调用从预算宏中解出并按预算参数化，而不是整段排除；这属已记录取舍（`docs/实现与限制.md:104`），按影响记录。

P2（可核实）：水下窗口的水平中心是「近似」而非相机物理位置，源码注释自述（641-647）与 `docs/实现与限制.md:128` 一致：头部跨界面时用相机实际水深、保留玩家水平中心。触发条件：第三人称、头部与相机分处界面两侧。结果：窗口中心与真实相机位置存在已知偏差，属用户已选择的近似。

未证实疑点：`water.glsl:616` 与 `lit.vsh:112-116` 的角度对应已核实一致，但 vanilla 方形太阳在水外是硬边贴图（`sky.fsh:73-82` 已注明「hard-edged square」），因此「水外方」在 vanilla 模式是既定设计；「水下圆」的旧状态在当前源码已不成立（内外同源）。`water.glsl:932` 的 `unshiftedPath` 判定依赖 `refractedUV` 与像素中心完全相等，浮点相等在极端 UV 下是否稳定无法由源码判定。SSR 仍不能反射屏外几何（`raytrace.glsl:472-473` 的边界置信渐退），属结构限制。

## 模块 5 水下光束源图 / 窗口 / 积分消光 / 水位 / 雾 / 柔化 / 太阳

覆盖的关键文件与交界：`global/water/light_shafts.glsl`（采样数 19-25、视点 27-34、视图 36-63、mip 声明 65-69、相位 73-81、波面段 82-95、路径可见性 96-123、波面跨度 124-151、步进 152-226、解析 228-272）；`global/water/shaft_layout.glsl`；`program/scattering.vsh:24-57`；`program/scattering.fsh:79-150`；`program/itt_water_normal_cache.vsh/.fsh`；`lib/itt_water_field.glsl`；`lib/itt_water_waves.glsl`；`program/sky.fsh:60-124`；`lib/water_diffusion.glsl`；`lib/solas_water.glsl:98-128`；`program/composite2.fsh/.vsh`。

结论：生产者唯一（`prepare4`），窗口与光源在顶点计算（`itt_water_normal_cache.vsh:9-18`），空气侧在顶点裁掉整个四边形（第 10 行），片元侧再以 `isEyeInWater==1` 门控（fsh 18）。消费端 7 段 × 4 可见性节点 × 8 波面点与文档一致（`ASTRA_SHAFT_SAMPLES=7`，内层 4 节点 `light_shafts.glsl:202-218`，`water_shaft_wave_span` 8 节点 131-136）。入口向水内偏移 0.18 格、配对 `shadowtex1-shadowtex0` 透过量与水高 0.75 格匹配（96-122），平面云影只在启用时读取（116-119）。消光区分入射/观察两段（182-185、214-215），无历史加光。

P2（可核实，文档与现行源码不一致）：`docs/实现与限制.md:60` 称「在源图格距无法解析时将相应噪声方差平滑移向均值」。源码中该机制由 `lib/itt_water_waves.glsl:26-28` 的 `resolved = 1.0-smoothstep(0.5,1.25,footprint*frequency)` 实现，`mix(0.5,value,resolved)` 在 `resolved==1` 时不做任何平滑。唯一生产者 `program/itt_water_normal_cache.fsh:26` 传入 `footprint = ITT_WATER_FIELD_CELL = 64/1024 = 0.0625`（`lib/itt_water_field.glsl:9`）。六层的 `frequency = 64*max(|worldUV列|)`：以 `spatialScale=0.05/1.28`（`itt_water_waves.glsl:46`）计算，第 1 层 `max` 列长约 0.1133，`frequency≈7.25`；第 4 层约 0.0172，`frequency≈1.10`。全部六层 `footprint*frequency ≤ ≈0.453 < 0.5`，故 `resolved` 在生产端恒为 1.0，平滑分支永不生效。该门只在 `program/lit.fsh:214` 的水下界面消费路径上（`footprint = max(wavePixel,0.0625)`，远距像素可远大于 0.0625）才可能触发。结果：源图始终携带全部细波细节，细波抗混叠完全依赖消费端 mip 读取（`light_shafts.glsl:142-143`），文档所述的源侧平滑不是代码行为。依据：上述常量与算术。建议：把 `实现与限制.md` 该句改为「生产端固定以格距求值、细节由消费端 mip 过滤」，或在生产端按 mip 级别分别求值。

P2（可核实算术，实机未确认）：附加位移不缩放 `lower`。`itt_water_waves.glsl:83` 的 `return vec3(value,noise.yz*(derivative*2.0*sign(2.0*noise.x-1.0)))` 中，`derivative` 来自 `itt_wave_crest`（30-40 行），其两条分支斜率为 `-5x` 与 `-1`，且 `value` 分支在 `x<=0.2` 时为 `0.9-2.5x²`、否则为 `1-x`；导数与值在 `x=0.2` 处连续（`d(0.9-2.5x²)=-5x=-1`，`d(1-x)=-1`），故解析梯度本身连续，不构成断裂。此项仅说明梯度实现方式，不作为缺陷。

未证实疑点（对应「光束数量少且布局挤」）：每像素只有一个波面入射点 `entry = worldOrigin+source*(depth/source.y)`（`light_shafts.glsl:174`），后续 8 点只在该点沿 `entryRay` 展开（175、212-213）。ITT 参考（`_analysis/latest-2026-09-10/iterationT-3.2.0/shaders/Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl:57-73`）改为沿真实视射线步进并对每个样点做 `CalculateWaterCaustics(rayPos)`。两者结构不同，但两者的细束来源都出自同一波场，源码不足以判定「数量更少/更挤」的实际观感差异，故不列为缺陷。需要实机或独立呈现对比才能确认。

未证实疑点：`light_shafts.glsl:69` 在消费程序内声明 `colortex29MipmapEnabled=true`，注释称已按本机 Iris 1.11.2 的 `stageReadsFromAlt → setupMipmapping → setupState` 顺序核对。宿主是否确实在 `prepare4` 之后、`composite2` 之前生成 mip 无法由源码验证；若宿主顺序不同，源图 B 通道会读到上一帧或未过滤内容。属缺失事实。

## 模块 6 天空 / 日月 / 星空 / 晨昏 / 云 / 天气及相关历史

覆盖的关键文件与交界：`program/deferred.fsh`（积水反射 34-69、SSAO 260-270、平面云足迹 233-238、介质/体积 320-365、下界/末地天空 367-394、主世界天空/云合成 395-437、`obscureSky` 438-448）；`global/atmosphere/clouds_planar.glsl`；`global/atmosphere/sky_minishita.glsl`（已知问题 16-26）；`global/atmosphere/sky_gradient.glsl`（眩光 215-249、入口 262-268）；`global/atmosphere/stars.glsl`；`global/atmosphere/weather.glsl`；`global/atmosphere/clouds_screen.glsl`；`global/atmosphere/cloud_temporal.glsl`；`global/atmosphere/cloud_shadow_cache.glsl`；`global/atmosphere/fog.glsl`；`global/atmosphere/volume_fog.glsl`；`global/dimension/overworld.glsl`；`lib/twilight.glsl`；`lib/cloud_history_frame.glsl`；`lib/sky_reflection_cache.glsl`；`lib/sky_sh9.glsl`；`program/sky_reflection_cache.fsh`；`program/sky.fsh`；`program/clouds.fsh`；`gbuffers_skybasic/skytextured/clouds/weather.*`。

结论：天空合成路径按云模式互斥且无重复计入。`deferred.fsh:395` 排除 `CLOUD_VANILLA`，`sky.fsh:138-143` 只在该模式于天空几何内画 `astra_sky`（含星场，`overworld.glsl:94-100`），`deferred.fsh:243-245` 相应把该模式的天空像素标为反应；非 vanilla 模式由 `deferred.fsh:413-425` 加入 `astra_sky_radiance` 与星场，`sky.fsh:139` 返回黑，二者不叠加。反射路径刻意不含日月盘与星点（`overworld.glsl:42-43`、`51-66`），高光由水面单独提供（`water.glsl:875-898`），未重复。晨昏共用 `astra_twilight_strength`（`lib/twilight.glsl:4-12`），天空/云/地形/倒影读取同一因子。

P0/P1/P2：无可以证实的问题。

未证实疑点：`sky_minishita.glsl:16-26` 自述两项固有缺陷（2×1 采样在长掠射路径上过消光使地平线偏橄榄、无环境光底项故需 `ASTRA_SKY_DAY_GAIN=22`），仅在 `SKY_MODE=0`（ULTRA 档）生效，源码未修，属已声明取舍。`clouds_planar.glsl` 的有限搜索 + 屏幕边缘细化在薄云边缘的抖动（W07）无法由源码判定。`lib/sky_reflection_cache.glsl` 的 258×128 含 2 列经度缝 gutter（第 5-6、14、60-64 行）与 256×128 周期过滤模式并存，映射自洽，但粗糙模式在极点附近的表现未验证。

## 模块 7 后处理泛光 / 调色 / AA / 历史重投影 / 显示颜色域

覆盖的关键文件与交界：`program/display.fsh`（TAA 场景 UV 抖动 111-117、泛光路径 118-167、空气光束 168-189、水下粒子 190-200、暗化 202-216、水下/空气显示曲线 217-237、调色与暗角 238-239、抖动与 prepare 输出 240-246）；`program/final.fsh`；`global/post/bloom.glsl`；`global/post/grading.glsl`；`global/post/exposure.glsl`；`global/post/fxaa.glsl`；`global/post/godrays.glsl`；`global/post/end_sky_tonemap.glsl`；`lib/tonemap.glsl`；`lib/dither.glsl`；`lib/taa_jitter.glsl`；`lib/taa_state.glsl`；`lib/taa_reactive.glsl`；`lib/history_frame.glsl`；`lib/effect_history.glsl`；`program/taa_resolve.fsh`；`program/display.vsh`；`program/exposure.fsh/.vsh`；`program/taa_state.fsh`；`composite6/7/8/9.*`。

结论：AA 路径互斥且输入输出网格配对。FXAA 档由 composite8 写 `colortex13`（`shaders.properties:122-132`、`display.fsh:93-96`），final 在 `ANTIALIASING==1` 时读它（`final.fsh:2-19`）；TAA 档由 composite6/7 写 `colortex0`（未抖动网格）与历史（`taa_resolve.fsh:19-22、90-105`），final 走 `display.fsh`。`display.fsh:113-117` 用 `sceneUV` 读仍在栅格网格上的 `colortex1`/`depthtex0`，用 `texcoord` 读已解析的 `colortex0`；水下时 `astra_jitter_uv()` 返回 0（`taa_jitter.glsl:11`），故两者相等，读 `colortex4` 无网格错配。曝光历史为 1×1（`exposure.glsl:26-34`），水下冻结增益（`exposure.glsl:122-126`），且 `display.vsh:48` 对普通水体跳过增益读取，空气/薄水片共用自适应路径。

P2（可核实，精度取舍已记录）：水下显示在所有 AA 档位直接读 `colortex4`（`display.fsh:122-124`），该附件在 Bloom 开启时为 RGB16F（`lib/water_buffer_formats.glsl:16-24`），关闭时为 R11F_G11F_B10F（第 26 行）。触发条件：主世界 + 水下 + Bloom 关闭。结果：水下合成在显示前经过 5 位尾数的蓝通道，`docs/实现与限制.md:76、89、94` 已量化（原格式蓝通道 57 个存储值、RGB16F 1797 个），并说明修正只在 Bloom 开启时生效。属已记录取舍，按影响记录。

P2（可核实）：`exposure.glsl:45-48` 自述 `AE_KEY=0.18` 需要实机确认「普通白天帧收敛在增益 1.0 附近」，源码内标为 UNVERIFIED。触发条件：`AUTO_EXPOSURE` 开启。结果：若标定不符，整帧亮度会系统性偏移；无法由源码判定。

未证实疑点：`taa_resolve.fsh:127-131` 用 `colortex22` 的植被前帧运动替换重投影，实体仍无每实例输入（D04）；`lib/effect_history.glsl:18-38` 用 `frameCounter%4096` + 视口 + 相机位移 + 时间窗 + 维度标识校验历史，末地与下界各自独立（13-17），未发现漏检，但宿主是否在每帧正确写入 `colortex30` 的两处 texel 无法由源码验证。

## 模块 8 下界 / 末地维度入口与独立效果

覆盖的关键文件与交界：`global/dimension/nether.glsl`；`global/dimension/nether_reflection.glsl`；`global/dimension/nether_colored_light.glsl`；`global/dimension/end*.glsl`（`end`、`end_blackhole`、`end_disc_profile`、`end_geometry`、`end_kerr`、`end_plasma`、`end_system`）；`lib/nether_fog_density.glsl`；`lib/nether_voxel_grid.glsl`；`lib/nether_reflection_metadata.glsl`；`lib/end_light.glsl`；`lib/end_surface.glsl`；`lib/end_reflection_cache.glsl`；`lib/end_star_catalogue.glsl`；`program/nether_reflection.fsh`；`program/nether_reflection_resolve.fsh`；`program/nether_light.csh`；`program/end_sky_buffer.fsh`；`program/end_illumination.fsh`；`program/end_reflection_cache.fsh`；`program/end_star_catalogue.csh`；`program/end_star_rows.csh`；`world-1/*`、`world1/*` 全部入口外壳。

结论：维度入口与独立效果分离正确。下界反射用 `colortex9`（复用末地天空目标，`nether_reflection.fsh:13-14`）与 `colortex28=RGBA16F`（15），末地天空用 `colortex9=RGBA16F`（`lib/scene_buffer_formats.glsl:7`）+ 原生尺寸（`shaders.properties:52`），二者不共用生产者（`shaders.properties:250-254`）。末地星表算术已核：512 行元数据 + Σ 各纬圈格数（`END_STAR_ROWS=512`、`END_STAR_EQUATOR_CELLS=1200`，`lib/end_star_catalogue.glsl:5-6`）共 391670 槽位，缓冲 1024×384=393216，余量 1546，无越界；`end_star_rows.csh:32-33` 与 `end_star_catalogue.csh:15` 的线性化（`slot%1024`、`slot/1024`）与 `lib/end_star_catalogue.glsl:19-23` 的读取一致。`end_illumination.fsh` 的槽位分区（74 特例、294..314 岛形、315 星旋转、>=75 基底）与 `end_geometry.glsl`、`end_system.glsl:30` 的读取一致。

P0/P1/P2：无可以证实的问题。

未证实疑点：`world1/setup.csh`→`setup1.csh`→`setup2.csh` 的三段 compute 依赖宿主在 dispatch 间插入图像/纹理屏障（`world1/setup2.csh:2-5` 自述），源码无法验证。`global/dimension/nether_volume.glsl` 与 `global/water/temporal.glsl` 均已退役（前者仅 `shaders.properties:796` 注释提及、后者仅自身文件头，`rg` 确认无活跃 include），不列为未处理项，但文件仍留在包内，属可清理项。

## 模块 9 选项档位/开关组合、性能热点、文档与现行源码一致性

覆盖的关键文件与交界：`shaders.properties`（profile 564-567、sliders 572、screen 布局 548、865-870）；`lib/settings.glsl`（`OVERWORLD_BUDGET` 334-357、`ASTRA_OVERWORLD_OPTIMIZED` 352-354、`ASTRA_SHADOW_FILTER_MODE` 365-369、实体投影表 448-478、`ASTRA_*` 特性宏 678-732、清屏色 733-747）；`docs/当前工作.md`；`docs/实现与限制.md`；`Astra/README.md`。

结论：档位与源码配对自洽。均衡档 `SHADOW_RESOLUTION=2048` 被 `lib/settings.glsl:401-405` 上限压到 1536、`SHADOW_DISTANCE=192` 压到 112（407-411）、`ENTITY_SHADOW_DISTANCE=64` 经 `entityShadowDistanceMul=0.253968254`（455-457）对应 32 格；`UNDERWATER_SHAFT_SAMPLES=7` 与 `colortex1=0.5`（`shaders.properties:19-23`）配对；`WATER_EFFECT_QUALITY=1` 对应 `ASTRA_WATER_TRACE_BUDGET=20`、`REFINE=4`、`FAR_COARSE=12`（`raytrace.glsl:38-51`）。预算为「上限」，不抬高更低档（`raytrace.glsl:28-37` 注释与实现一致）。

文档与源码一致性抽查结果：`docs/实现与限制.md:66`「至多 28 个遮挡点及 224 个波纹读取」= 7 段 × 4 节点 = 28、7 × 4 × 8 = 224，与 `light_shafts.glsl:196-218` 一致；`:70`「含 mip 每张约 10.67 MiB」= 1024²×RGBA16F 8 MiB × 4/3，一致；`:104`「远侧中档粗查询上限 12（原 8），加四细化至多 16，总上限仍 20」与 `raytrace.glsl:46、51` 一致；`:110` 的 26.1 资源路径分支与 `shaders.properties:527-531` 一致；`:138` 的半精度扩展声明与根外壳一致。`docs/当前工作.md:19` 与 `:31-34` 的五项反馈与 W13/W04/W14/W03 状态与源码中已落地的改动一致。

发现的不一致：见模块 5 的 P2（`docs/实现与限制.md:60` 的源侧噪声平滑在唯一生产者中不生效）。其余抽查未发现文档与现行源码冲突。

性能与 FPS：工作区与文档中不存在整帧数据。`docs/当前工作.md:11-17` 明确是用户场景读数（水面 90 / 混合 67 / 水下 100），不是平均值或分项耗时；`docs/实现与限制.md` 的 RTX4050 数字为独立组件计时并显式声明不能换算 FPS。因此**不能判断主世界原生 1080p 平均 144 FPS 是否达标**，本报告不作任何 FPS 推断。

## 未证实疑点与缺失事实汇总

1. 水下光束「数量少且布局挤」的观感无法由源码判定（模块 5 结构差异已记录，但不构成可证缺陷）。
2. 树叶倒影剩余漏采比例无实机数据；`docs/实现与限制.md:104` 自述复杂错层树冠接收率 22.79%→31.36%，仍显著遗漏。
3. `colortex29` mip 生成时序、末地三段 compute 屏障、下界体素九段 compute 顺序，均依赖宿主行为，源码内无法验证。
4. 阴影细边锯齿在均衡档的实际可见度未确认（模块 2 的算术只说明有效核很小）。
5. 自动曝光 `AE_KEY=0.18` 的白天收敛点未确认（源码自标 UNVERIFIED）。
6. 无任何整帧 FPS 或分项 GPU 实测；144 FPS 目标不可评估。
7. 缺 `CUSTOM_IMAGES`/`COMPUTE_SHADERS` 时的完整兼容路径（D07），`iris.features.optional` 不等于已有替代实现。

## 严重问题摘要

本次九模块全覆盖未发现可证实的 P0 缺陷；未发现结构性错配、附件/格式冲突、生产者-消费者配对错误或清屏/翻转缺失。可核实的问题为 P2 级：

- 模块 5 / 9：`docs/实现与限制.md:60` 所述的源图侧噪声方差平滑在唯一生产者中恒不生效（`itt_water_waves.glsl:26-28` 的 `resolved` 恒为 1.0），源图始终携带全部细波细节，抗混叠只靠消费端 mip；文档描述与代码行为不一致。
- 模块 2：均衡档 1536/112 下，中档附加柔化在近中心被限制在约 1 纹元、在径向边缘收缩到约 0.07 纹元，细边锯齿可能仍可见（算术可核，实机未确认）。
- 模块 4：树叶真实纹元交点路径只在 `ASTRA_OVERWORLD_OPTIMIZED` 下编译，主世界预算选「关闭」时不参与，原始档不获得本轮质量修正。
- 模块 7：Bloom 关闭时水下显示经 R11F_G11F_B10F 蓝通道（5 位尾数），精度修正只在 Bloom 开启时生效。

以上 P2 均为源码注释或文档已声明取舍者，按影响记录，不作为误报。真实未覆盖点见上一节；无整帧数据时不对实际帧率作任何结论。
