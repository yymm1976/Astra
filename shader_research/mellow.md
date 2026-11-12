# Mellow 3.4.1a 研究报告（面向 Astra）

> 引用格式：`shaders/…:行号` 均指 `reference_shaderpacks/mellow/shaders/` 下的文件（包根文件如 `shaders.properties` 同级）；`Astra/…` 指本工作区 Astra 包。调研日期：2026-10-02。
> Astra 的模块组织与颜色方案系统此前已参照 Mellow（`Astra/shaders/lib/color_controls.glsl:3` 记录"inspired the independent style/RGB menus"）。本报告重点回答：**3.4.1a 相对 Astra 所学版本还有什么组织/系统级新东西**，以及 **MIT 下可直接改编的边界**。

## ① 包概览

- **版本**：3.4.1a（任务指定；包内无版本字符串。注意包根 `read before you edit.txt:7-8` 声明 Modrinth/CurseForge 发行版经脚本优化、源码应取自 Codeberg——本包为可读源码版）。
- **作者**：TheCMK（`LICENSE:3`，`Copyright (c) 2026 TheCMK`）。
- **许可证**：MIT（`LICENSE:1-9`）。MIT 在光影场景的义务：**分发（含改编后再发布）时必须保留原版权与许可声明**（`LICENSE:7` "shall be included in all copies or substantial portions of the Software"）；作者额外礼貌请求（非许可条款）：保留整个 LICENSE 文件并在其上叠加自己的许可、页面上署名、不用 "Mellow" 名字与截图/logo 素材（`read before you edit.txt:4-5`）。
- **风格定位**：轻量柔和（"mellow"）写实向，单包覆盖主世界/下界/末地。兼容面异常广：Iris 与 OptiFine 双支持（`shaders.properties:1` 注释、`:194` OptiFine workaround）、Distant Horizons（`lib/distant_horizons.glsl`）、Voxy（`world_modded/voxy.json`、`shaders.properties` 内 VOXY 分支）、Colorwheel 模组 OIT（`colorwheel.properties:1` `oit=true`）；MC 版本条件编译下探到 1.17/1.21.4/1.21.9（`shaders.properties:236-240`、`sky.glsl:141`）。
- **本地化**：en_US/fr_FR/zh_CN 三语言（`lang/`），选项注释统一带性能开销标注（如 `lang/en_US.lang:2` "Performance impact: §6High"）。
- **代码形态**：所有 program 顶部直接内联整套 `lib/settings.glsl` 与 `lib/colors.glsl`（因此每个 program 文件前 ~340 行是设置展开），实现随后；`lib/settings.glsl:334` 一行切换 5 套颜色方案，`lib/colors.glsl` 每套方案 70 个通道（60 RGB + 10 标量，5 套共 350 条 `const float f_` 定义）。核心模块行数：天空 202 / 云 237 / 雾 166 / 水 185 / 光照 185 / 阴影 94 / TAA 160 / tonemap 140——单文件小而聚焦，与 Astra 的 global/ 分层粒度一致。

## ② 架构与特性清单

### 工程组织（目录/文件/设置系统）

- **program/ 共享 + 四维度薄入口**：`program/` 放全部实现，`world-1/world0/world1/world_modded` 只做 `#define DIMENSION_xxx` + 一行 include（`read before you edit.txt:12-14`；实例 `world0/deferred.fsh:1-4`）。另用 `dimension.properties:4` `dimension.world_modded=*` 把**任意模组维度兜底**到同一套 program。
- **命名约定强制分层**：uniform 驼峰、函数蛇形、变量/结构体帕斯卡，避免命名冲突（`read before you edit.txt:19`）；`lib/all_the_libs.glsl:1-10` 一站式 include 十个 lib。
- **设置系统**：`lib/settings.glsl`（399 行，大头是 RGB 通道滑条值列表）+ `shaders.properties:148-190` 的 screen 树（1 个根屏 + 41 个子屏、两级以上嵌套、`columns=2/3` 排版）+ `:191` sliders 巨行。三个预设 FAST/FANCY/FABULOUS（`shaders.properties:143-145`）。
- **空 `#ifdef` 保选项技巧**：`settings.glsl:346-399` 用一批空条件块让仅出现在 `shaders.properties` profile/screen 里的选项被 Iris 认作"已使用"而不被剔除（文件内自带注释 `:346` "I love this so much"）。
- **DONTOPTIMIZE 标记**：`settings.glsl:273-276` 用 `// DONTOPTIMIZE-START/END` 防止发布脚本优化掉 const 声明。
- **按功能裁剪 pass**：`program.worldX/compositeN.enabled=OPTION`（bloom 6 连、SMAA 3 连、CA、DOF、LQ depth、begin compute，`shaders.properties:85-141`），关闭特性即整 pass 不编译。
- **CPU 预计算自定义 uniform**：太阳/月亮/日出/日落四个时间关键帧权重 `dayStrength/nightStrength/sunsetStrength/sunriseStrength`（`shaders.properties:213-216`）、TAA 抖动含黄金比例序列（`:200-211`）、雾量 `fogAmount`（`:236-240`）全部在 properties 侧算好。
- **材质 ID 表**：`block.properties` 现代分支——水=10001、树叶=10002、无方向性光照植被=10003（`block.properties:1-12`）；`item.properties` 给发光物品供手持光取色。Astra 的 10001-10007/10021-10027 基础表即源于此（`Astra/shaders/THIRD-PARTY.md:59`）。
- **摆动植被在 vsh 侧**：`program/gbuffers_terrain.vsh:981` 的 `WAVY_PLANTS` 分支（含雨天倾斜 `RAIN_TILT_STRENGTH` 与玩家拨动 `FOLIAGE_PLAYER_INTERACTION`，`settings.glsl:203-209`）。
- **纹理绑定**：SMAA 区域/搜索图、3D 噪声 `worley_perlin.bin`（`TEXTURE_3D R8 64³`）、原版云纹理、11 张可选 LUT 文件切换（`shaders.properties:49-80`）；colortex5 固定 1/4 分辨率（`:82`）。
- **彩色体素光的缓冲随档位变尺寸**：VOXEL_DISTANCE 64→256 对应 128³→512³ 的 RGBA16 image3D 双缓冲（`shaders.properties:29-44`）。

### 大气 / 云

- **四种云风格一键切换**（`settings.glsl:172` CLOUD_STYLE 0-3）：flat 平面云（`global/atmosphere/clouds.glsl:5-37`，噪声阈值+Mie 相位受光+闪电照亮 `:29-33`）、wispy（`:39-55`）、真体积云（`:57-119`，采样数随视角仰角自适应 `:65`）、**blocky 体积云**（`:127-208`：用原版云纹理做体素云，DDA 逐纹素步进 `:146-165`，太阳方向 6 步 DDA 自阴影 `:170-188`）；`DOUBLE_CLOUD_LAYERS` 叠第二层（`:214-221`）。
- **天空双层渐变**：SKY_TOP/SKY_GROUND 经 `fogify` 混合（`sky.glsl:67-73`），颜色来自颜色方案系统（见下）；方形/圆形日月可选，圆日时关闭原版日月（`sky.glsl:20-50`、`shaders.properties:15-18`）。
- 太阳眩光独立通道（`sky.glsl:52-65`）、投影单元格星星（`:75-86`）、双平面 2 样本极光（`:88-124`）、末地旋转 fbm 极光带 + `endFlashIntensity` 闪增（`:126-152`）、彩虹（`:171-202`）。
- **雾全家桶**：边界雾（幂次可调 falloff，`fog.glsl:16-35`）、大气高度雾（密度按高度与天气调制，太阳+月亮两路 godray 相位，`fog.glsl:101-142`）、godray 屏幕空间遮挡追踪（`:57-99`）、末地高度雾（`:42-55`）、岩浆/细雪雾（`:1-14`）、blindness/darkness（`:37-40`）。
- 雨天对天空做去饱和+压暗（`global/lighting/light_colors.vsh:31-35`），雨量经 `biome_precipitation` 平滑的自定义 uniform `precipitationSmooth` 驱动（`shaders.properties:233`）。
- 自定义天空盒与边界雾互斥、下界禁用自定义天空盒（`fog.glsl:148`、`settings.glsl:194-197`）——选项间依赖直接写进预处理条件，避免无效组合。
- 天空/反射/云共用同一套 `get_sun_glare`+`get_sky` 组合，水面反射直接调用云函数（`global/water.glsl:17-39`），保证天空与反射观感一致——组织上的复用点。

### 水体

- **三档反射**（`settings.glsl:110-114`）：SSR+翻转图 / 仅翻转图 / 无。SSR 为屏幕空间定长步进 + 深度拒绝 + 二分细化（`global/water.glsl:68-102`）；**flipped_image_ref 单次投影"翻转图"廉价反射**（`:41-66`）作 fallback 或低配档。
- 粗糙反射用 vogel 32 盘可变半径模糊（`water.glsl:120-126`、`lib/util.glsl:221-228`）。
- 水法线：`noise_water` 双通道梯度，斜坡沿坡向流动（`water.glsl:9-15`）；水面额外水雾按屏幕深度差（`water.glsl:2-7`）；三种水面纹理模式 `WATER_TEXTURE_MODE 0/1/2` 可与 PBR 资源法线组合（`settings.glsl:113`、`water.glsl:151-155`）。
- **雨洼地独立程序**：`get_puddles` 无需 TBN 直接构造法线做反射（`water.glsl:168-185`）。
- 水下色调 `tint_underwater` 与生物群系水色混合（`lib/tonemap.glsl:51-58`）。无焦散、无吸收介质、无水下光束——这块 Astra 反超。

### 阴影与光照

- **前向光照全在 gbuffers，光色在顶点阶段算好**：`init_colors()` 产出 4 个 flat varying `SUN_DIRECT/SUN_AMBIENT/SKY_TOP/SKY_GROUND`（`global/lighting/light_colors.vsh:1-9`）；四时间关键帧混合（`:28-29`）、生物群系染色经 `mix_preserve_c1lum` 保亮度混合原版 skyColor（`:38`）、雨天去饱和（`:31-35`）、直射光关键帧混合 + 月相余弦调制（`:71-77`）。
- **DYNAMIC_SHADOWS 混合阴影**：影距内用 shadow map（`get_shadow_dynamic`），影距外用 lightmap 静态阴影 `smoothstep(0.85,0.96,Skylight)`（`global/lighting/shadows.glsl:52-55`），按 `shadow_fade` 距离混合两者（`global/lighting/lighting.glsl:106-119`）；开启动态档时直射×1.2/环境×0.85 补偿（`lighting.glsl:48-51`）。
- **PIXELATED_SHADOWS**：把世界坐标吸附到可调网格再投影，稳定阴影纹理（`shadows.glsl:63-73`）。
- PCF 为 vogel disk 8 样本旋转盘（`shadows.glsl:30-50`），低配为 4 tap 简单模糊（`:20-27`）；半影随 skylight 缩放（`:82-83`）。
- 彩色阴影：shadowtex0/1 + shadowcolor0 组合（`shadows.glsl:1-18`）。
- 影距过滤与漏光：`SHADOW_LIGHTLEAK_PREVENTION` 用 lightmap 钳 NdotL（手持在 0.56 深度阈值外豁免，`lighting.glsl:93-97`）；`SHADOW_FILTER` 三模式编译期选择，512 分辨率强制简单过滤（`settings.glsl:282-288`）。
- **彩色体素光（洪泛填充）**：`begin.csh` compute 六邻域扩散（`program/begin.csh:347-349`），RGBA16 双缓冲按 `frameCounter%2` 乒乓读写（`global/voxelisation.glsl:59-67`），采样端 `sqrt(C)*6` 压缩（`:46-51`），手持发光物硬编码 HSV 光色表（`:14-44`）。
- 闪电环境光按距离衰减（`lighting.glsl:14-21`）、手持光写进 lightmap.x（`:24-38`）、光晕闪烁用 noisetex 时间采样（`:40-42`）。
- PBR：法线/镜面参数解码（`global/pbr.glsl:1-30`）、cook-torrance 高光与金属漫射（`lighting.glsl:148-165`）、SSR 接入 gbuffers 光照（`:166-173`）、SSS 指数衰减（`:99-113`）、湿度孔隙度变暗（`:142-144`）。
- 四季染色：`worldDay%120` 四季 HSV 插值 + 温带群系判定（`global/seasons.glsl:1-27`）。

### 后处理

- **管线**：deferred 生成 1/4 分辨率最大混合低质深度（`program/deferred.fsh:328` DRAWBUFFERS:5 + main）→ deferred1 合成天空+云+雾+SSAO+描边（`program/deferred1.fsh:930/1181/1344/1377/1408` 五个入口函数）→ composite2-7 bloom → composite8 TAA+运动模糊+曝光+Purkinje+tonemap+LUT（`program/composite8.fsh:861-894`）→ composite9-11 SMAA → composite12 色差 → composite13 DOF → final CAS 锐化+胶片颗粒+暗角+显示空间调色（`program/final.fsh:470-497`）。
- **8 种 tonemap 算子**分发（`lib/tonemap.glsl:1-19`；`lib/tonemap_operators.glsl` 为中继文件：`:80-84` 内嵌 glsl-tone-map 的 Seguin MIT 声明，`:23` ACES 指向 BakingLab，`PBRNeutralToneMapping` 为 Khronos Apache-2.0）。
- **显示空间调色**（final，gamma 后）：vibrance/saturation/contrast 三原语（`lib/tonemap.glsl:21-37`）、9 参数通道混合器（`final.fsh:450-454`）、**暗部/中间调/高光三区调色**——按亮度在三个偏移向量间插值并**保持原亮度**（`final.fsh:457-467`）。
- LUT 文件 3D 解码（`lib/tonemap.glsl:112-127`）；Purkinje 夜视蓝移用 XYZ 空间视杆亮度近似（`:69-79`）。
- **TAA 五模式**（`settings.glsl:231`）：黄金比/隔帧抖动（`shaders.properties:200-211`）、closest-depth 运动矢量（`taa.glsl:62-73`）、Catmull-Rom 快速历史重采样（`:35-60`）、textureNicest（`:91-99`）、AABB 邻域裁剪（`:23-32`）、offcenter rejection 防鬼影（`:142-147`）、亮度差闪烁抑制（`:150-152`）、NaN 防护（`:120-124`）。
- Bloom：双 pass 6 采样高斯（`global/post/bloom.glsl:1-17`）+ tile 顶点重排（`:35-40`）。
- 其余镜头效果：DOF 连续对焦 + CoC 公式（`program/composite13.fsh:374-398`，手动对焦可选）、运动模糊（`program/composite8.fsh:872`）、色差（`program/composite12.fsh:327-338`）、SMAA 三 pass 复用 colortex3/5 存区域/搜索图（`shaders.properties:51-52,110-121`）、CAS 锐化 + 动态锐化（`program/final.fsh:379,472`）、胶片颗粒/暗角（`final.fsh:436-448`）、深度描边（`program/deferred1.fsh:1408,1497`）。

### 性能与与时域

- **USE_LQ_DEPTH**：SSR/SSAO/godray 全部消费 1/4 分辨率深度（`water.glsl:51,77`、`ssao.glsl:32`），deferred pass 用 4 邻域 max 混合生成。
- 光色顶点阶段 flat varying（前向管线一次算好，片元零重复计算）。
- 静态阴影 fallback 消除远距 shadow map 采样；`program.*.enabled` 编译期整 pass 裁剪；体素洪泛乒乓（每帧半量）；DH 噪声淡出（`settings.glsl:255-259`）；DH 地形也吃 SSAO（`SSAO_ON_LODS`，`settings.glsl:259`）。
- 时域仅 TAA 历史一档（gaux1），反射/AO 无时域复用——时域利用远弱于 Astra；TAA 关闭且无运动模糊时整段历史计算被预处理剔除（`program/composite8.fsh:864-866`）。

## ③ Astra 可借鉴点

1. **像素化阴影（PIXELATED_SHADOWS）**：把阴影接收点世界坐标吸附到 1/N 格网格，消抖动且让低分辨率阴影图观感"手绘格"。出处 `global/lighting/shadows.glsl:63-73` + 设置 `lib/settings.glsl:280-281`。对应 Astra：`Astra/shaders/global/lighting/shadowmap.glsl`（采样端）、`Astra/shaders/lib/settings.glsl`（SHADOWS 屏新增开关）。迁移难点：**低**——纯采样端 ~40 行 + 2 个设置项，无新 buffer。
2. **Purkinje 夜视效应**：XYZ 空间视杆亮度近似，暗处整体蓝移，阈值随夜色/室内平滑。出处 `lib/tonemap.glsl:69-79`。对应 Astra：`Astra/shaders/global/post/grading.glsl` 或 `lib/tonemap.glsl` 之后、`Astra/shaders/shaders.properties:408` POST 屏。迁移难点：**低**——独立函数 + rgb_to_xyz 矩阵，约 30 行。
3. **保亮度三区调色（color_balance）**：Astra 的 LOOK_SHADOWS/MIDS/HIGHS 是乘法增益（`Astra/shaders/lib/color_controls.glsl:25-27`）；Mellow 是加法偏移 + 亮度守恒（`program/final.fsh:457-467`）。两者互补：偏移式对"暗部偏青/高光偏暖"类分级更直观，亮度守恒避免增益式把暗部推黑。出处同上。对应 Astra：`global/post/grading.glsl`。迁移难点：**低**。
4. **翻转图廉价反射（flipped_image_ref）**：一次屏幕投影取反射近似，无迭代。出处 `global/water.glsl:41-66`。对应 Astra：`Astra/shaders/global/water/raytrace.glsl`（SSR miss fallback 或 PERFORMANCE 档专用反射）。迁移难点：**低-中**——需接入 Astra 水合成链的反射混合点；Astra 水链模块多（`global/water/` 下 optics/raytrace/refraction 等），接入点要选在混合阶段而非光线步进阶段。
5. **blocky 云的太阳方向 DDA 自阴影**：沿太阳方向逐纹素步进累积透过率（`global/atmosphere/clouds.glsl:170-188`）。Astra 平面云是单层噪声云，可将"多次采样太阳方向衰减"思想移植到 `Astra/shaders/global/atmosphere/clouds_planar.glsl` 替代单次光照采样，提升云立体感。迁移难点：**中**——增加每像素 4-6 次噪声采样，需挂 CLOUD_QUALITY 档位。
6. **主世界彩色体素光洪泛填充**：compute 六邻域 + RGBA16 双缓冲乒乓 + sqrt 压缩（`program/begin.csh:347-349`、`global/voxelisation.glsl:46-67`）。Astra 已有下界九段 compute 体素彩光（`Astra/shaders/global/dimension/nether_colored_light.glsl`、`global/nether_light.csh`），主世界无对应。迁移难点：**高**——需主世界 voxel 图像缓冲与 IRIS optional features 声明（参照 `shaders.properties:25-44`），建议沿用 Astra 下界管线的组织直接扩展。
7. **光色顶点阶段 flat varying**：四关键帧权重 CPU uniform（`shaders.properties:213-216`）+ 顶点算光色（`light_colors.vsh:28-29,71-77`），片元零开销。Astra 光色每帧在片元侧组装 LightParams。迁移难点：**高**——Astra 前向地形要动全部 gbuffers vsh/fsh 接口，且 SH9 方向性天光结构不同，只宜借鉴"关键帧权重下沉 CPU"一点。
8. **USE_LQ_DEPTH 低质深度**：`program/deferred.fsh:328` 1/4 分辨率深度，SSR/SSAO 全消费。对应 Astra：屏幕空间 AO / SSR / 体积雾的深度读取。迁移难点：**中-高**——新增 pass+buffer+统一 `get_depth_lq` 抽象，收益是三处采样带宽降 4 倍。
9. **工程杂项**：`dimension.properties:4` `world_modded=*` 模组维度兜底；空 `#ifdef` 保选项（`settings.glsl:346-399`）；`DONTOPTIMIZE` 标记（`:273-276`）；lang 注释统一带性能开销标注（`lang/en_US.lang:2`）。迁移难点：均**极低**。
10. **极光/彩虹装饰件**：极光双平面 2 样本步进+夜色与降水门控（`sky.glsl:88-124`）、彩虹按太阳对侧几何+雨后强度门控（`:171-202`）。对应 Astra：`Astra/shaders/global/atmosphere/stars.glsl` 同级新增文件 + SKY 屏开关。迁移难点：**低**——纯装饰件、自包含，优先级低于上述五项。

## ④ Astra 已有对应实现

- **维度/入口组织**：两边同构（薄入口+共享实现）。差异：Astra 根目录即主世界、仅有 world-1/world1 两个目录；Mellow 显式四目录（world0/world-1/world1/world_modded）且多一个 `dimension.properties:4` 的任意模组维度兜底——Astra 遇到未注册维度时无回退。

- **颜色方案系统**：两边同构。Mellow：5 方案 × 每通道"基准值+用户偏移"、`max_const` 钳非负（`lib/colors.glsl:1,4-98`，五套为 Default/Vanilla/Choc v7/Visually Vibrant/Winter，`:100/:196/:292/:388`）；Astra：COLOR_STYLE 4 方案 × 100 中性百分比增益 + 66 通道 RGB 子页（`Astra/shaders/shaders.properties:680-697`、`lib/color_controls.glsl:5-27`）。**互有优劣**：Mellow 的"基准+偏移"用户滑条有绝对参照且五套基准色板本身是现成审美资产（MIT 可直接抄数值）；Astra 的增益语义（100=不变）更可预测，且 LOOK_* 已占三分区。Mellow 独有通道：太阳眩光、末地极光双色、下界环境光 RGB（`colors.glsl:62-84`）——Astra 分组里无对应项，属**组织级差异**。
- **色调映射**：Astra 已按设计移植 4 算子（`Astra/shaders/lib/tonemap.glsl:4-6` 来源声明）；Mellow 8 算子（`tonemap.glsl:1-19`），Astra 未移植的 4 个中 PBRNeutral 为 Apache-2.0（Astra 明确不引入），ACESFilm/Hejl2015/Lottes 为 MIT/公有可补。
- **调色**：Astra `global/post/grading.glsl` + 三原语已从 Mellow 移植；Mellow 多出通道混合器、三区调色、LUT 文件加载（`final.fsh:450-467`、`tonemap.glsl:112-127`）。
- **TAA**：Astra 有独立时域状态/反应式机制（`Astra/shaders/lib/taa_state.glsl`、`taa_reactive.glsl`）为 Mellow 所无；Mellow 的 closest-depth 矢量、Catmull-Rom 重采样、offcenter rejection 是否 Astra 已具备——**不确定，未逐行比对 `Astra/shaders/global/post` 的 TAA resolve**，不妄断。
- **水**：Astra（动态法线、SSR、折射、吸收、解析焦散、水下光束：`Astra/shaders/lib/solas_water.glsl` + `global/water/*`）显著强于 Mellow（无焦散/吸收介质/光束，水下色调只有 `tint_underwater`）。Mellow 仅 flipped_image_ref 与无 TBN puddles 两点为 Astra 所无。雨湿地面：Astra 有 `lib/wet_material.glsl`；Mellow 无独立湿材质系统，雨天反射由 puddles 程序覆盖（`water.glsl:168-185`），两者覆盖面不同（Astra 湿材质是否含屏幕空间反射——**不确定，未逐行核对**）。
- **镜头效果面**：DOF、运动模糊、色差、SMAA、CAS、胶片颗粒、LUT 文件加载、Purkinje——Astra 均无（Astra POST 屏为 tonemap/曝光/饱和/鲜艳/对比/色温/bloom/godrays/AA/抖动/暗角，`Astra/shaders/shaders.properties:408`）；其中 Astra 有 FXAA 而 Mellow 无（Astra `global/post/fxaa.glsl`）。
- **阴影**：Astra 有 STATIC_SHADOW_FALLBACK（`Astra/shaders/lib/settings.glsl:85`，实现于 `global/lighting/diffuse.glsl:255-257` `static_shadow(skyLight)` 回退）——与 Mellow `get_shadow_static` 同思想；Mellow 版多出 shadow_fade 距离混合与半影缩放细节（是否等价需对照 `diffuse.glsl` 的 `shadow_coverage`，**不确定**）。彩色阴影两边都有。像素化阴影 Astra 无。
- **大气/云**：Astra 物理渐变天空 + SH9 方向性天光 + 半分辨率平面云独立时域历史（`Astra/shaders/global/atmosphere/sky_gradient.glsl`、`lib/sky_sh9.glsl`、`cloud_temporal.glsl`）在物理量与稳定性上强于 Mellow 的两渐变+经验雾；Mellow 胜在云风格多样性（4 种）与 blocky 云 DDA。Astra 有通用体积雾与体积光（Mellow 只有 godray）。
- **下界/末地**：Astra 独立光照 + 五类群系雾 + 九段 compute 体素彩光 + Kerr 黑洞天空远超 Mellow 的三通道环境光 + fbm 末地天空。此维度 Astra 无需借鉴。
- **曝光**：Astra 有 AUTO_EXPOSURE（`Astra/shaders/shaders.properties:408`）；Mellow 为固定曝光滑条（`settings.glsl:126`），Astra 反超。
- **SSAO**：两边均为 8 样本屏幕空间 AO（Mellow `global/ssao.glsl:12-42`；Astra `global/ssao.fsh`），实现量级相当，未做性能对比。
- **摆动植被**：两边都有（Mellow `program/gbuffers_terrain.vsh:981`；Astra WAVING_FOLIAGE，`Astra/shaders/shaders.properties:424`）。季节染色（`global/seasons.glsl:1-27`）Astra 无。
- **手持光**：两边都有；Mellow 把手持光写进 lightmap.x 复用方块光衰减曲线（`lighting.glsl:24-38`），Astra 为独立 HANDHELD_LIGHTING 通道（`Astra/shaders/shaders.properties:403`）——衰减曲线组织方式不同，效果等价。

## ⑤ 借鉴可行性（MIT 合规边界）

- **直接改编（复制代码/数值）**：在 Astra 的发布物中保留 `LICENSE` 原文（版权行 `Copyright (c) 2026 TheCMK` + 许可正文），沿用 Astra 现行惯例三件套：被改编文件头部 `// Immediate source: Mellow v3.4 by TheCMK (MIT)` 注释、`Astra/THIRD-PARTY.md` 逐文件登记、上游随包存档。**特别注意**：Mellow 是"逐文件中继"包——`lib/tonemap_operators.glsl:80-84` 内嵌 Damien Seguin 的 MIT 声明、`:23` 指向 BakingLab、`PBRNeutralToneMapping` 是 Khronos Apache-2.0；改编时应保留**该文件里实际声明的那个持有人**而非只写包根持有人（此坑 Astra 已在 `Astra/shaders/THIRD-PARTY.md:24,49` 记录并处理过）。新增改编（如本次建议的 shadows.glsl/water.glsl/final.fsl 片段）经复核这些文件内部无第三方中继声明，持有人即 TheCMK，处理方式与 `THIRD-PARTY.md:50,56` 已登记的 util/transforms/noise 移植相同。颜色方案数值表（`colors.glsl`）是纯数据，同样 MIT，可直接抄但需登记。
- **思想借鉴（算法/组织方式）**：无许可义务；按 Astra 现行做法在文件头写一行 inspired 说明（如 `Astra/shaders/lib/color_controls.glsl:3`），不改许可结构。
- **作者礼貌请求（非法律义务，建议遵守）**：不用 "Mellow" 名字与截图/logo（`read before you edit.txt:5`）；页面署名；取码自 Codeberg（`:8`）。
- **义务最小集合**（供新增 MIT 改编时套用）：① 改编文件头一行 Immediate source 注释（持有人 + 许可 + 出处文件）；② THIRD-PARTY.md 表格登记（来源/改编方式/许可/文件头四列，格式同 `Astra/shaders/THIRD-PARTY.md:50`）；③ 发布物根目录保留 MIT 许可正文一份。思想上借鉴（不复制表达式）三项都不触发。
- **反向边界**：Astra 当前含 GPLv3（Steadfast 派生）与专有（Refrax）模块（`THIRD-PARTY.md:55` 等）。**GPLv3 模块的内容不能单向流入"纯 MIT 来源"的新文件**——从 Mellow 新增改编时，落点文件不得同时包含 Steadfast 派生内容，否则整文件被同化为 GPLv3。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **PIXELATED_SHADOWS**——工作量最低（采样端 ~40 行+2 设置），收益直接（低分辨率阴影档观感稳定），可默认仅 ULTRA 开。
2. **Purkinje 夜视蓝移**——~30 行独立函数挂 POST 链，夜景辨识度提升明显，零管线改动。
3. **保亮度三区调色**——Astra LOOK_* 已有基础设施，补"加法偏移+亮度守恒"变体各 ~15 行，把现有三分区从增益升级为可选双模式。
4. **flipped_image_ref 翻转图反射**——给 PERFORMANCE 档零成本水反射，或作 SSR miss 的 fallback 填缝；Astra 水合成链现成。
5. **平面云太阳方向多次衰减**——把 blocky 云 DDA 的"沿光累积透过率"思想缩水为 4-6 次噪声采样挂进 CLOUD_QUALITY 高档，提升云立体感，代价可控。

**明确不建议直接搬**：光色顶点阶段 flat varying 管线（③7，需重写 Astra 全部 gbuffers 接口，且 SH9 天光结构不容）与主世界彩色体素光洪泛（③6，仅当用户明确要主世界彩光时再立项）；PBRNeutralToneMapping（Apache-2.0，Astra 已有先例不引入）。

---

### 引用自查记录

按验收标准 2，写作完成后重新打开文件抽查了 15 条 `文件:行` 引用，全部命中（含据此修正 3 处：`seasons.glsl` 起始行 3→1、`light_colors.vsh` 生物群系混合 37→38 与月相区间 69-76→71-77、`Astra/shaders/lib/tonemap.glsl` 来源声明 2-6→4-6）：

1. `shaders.properties:143` = `profile.FAST=…`；`:213` = `uniform.float.nightStrength=…`
2. `lib/settings.glsl:334` = `#define COLOR_SCHEME 1 // [1 2 3 4 5]`
3. `lib/colors.glsl:100/196/292/388` = `#elif COLOR_SCHEME == 2/3/4/5`
4. `lib/tonemap.glsl:69` = `vec3 purkinje_effect(vec3 Color) {`
5. `global/lighting/shadows.glsl:52` = `get_shadow_static`；`:63` = `#ifdef PIXELATED_SHADOWS`
6. `global/voxelisation.glsl:46` = `filter_floodfill`；`:59` = `frameCounter % 2 == 1`
7. `global/water.glsl:41` = `flipped_image_ref`；`:68` = `ssr(`
8. `global/atmosphere/clouds.glsl:170/175` = 太阳方向 DDA 注释与 6 步循环
9. `global/post/taa.glsl:142` = offcenter rejection 注释
10. `program/final.fsh:457` = `color_balance`；`program/composite8.fsh:861/885/891/894` = main/曝光/tonemap/LUT
11. `program/deferred.fsh:328` = `/* DRAWBUFFERS:5 */`；`program/begin.csh:347-349` = 六邻域累加
12. `global/lighting/light_colors.vsh:28/29/38/71/77` = 关键帧混合/生物群系混合/直射光混合/月相
13. `global/atmosphere/sky.glsl:141` = `#if MC_VERSION >= 12109`
14. `lib/tonemap_operators.glsl:23/80-84` = BakingLab URL 与 Seguin MIT 声明
15. `Astra/shaders/lib/color_controls.glsl:3`（inspired 声明）、`:25-27`（LOOK_*）；`Astra/shaders/global/lighting/diffuse.glsl:255-257`（static_shadow fallback）
16. `shaders.properties` screen 子屏总数 41（grep `^screen\.` 实测）；`lib/colors.glsl` 每方案 70 通道（grep `const float f_` 于 4-98 行实测 70）
17. `program/composite13.fsh:374-398`（DOF 采样循环与 CoC）、`program/gbuffers_terrain.vsh:981`（`WAVY_PLANTS` 分支）、`program/deferred1.fsh:1408/1497`（描边函数与调用点）
