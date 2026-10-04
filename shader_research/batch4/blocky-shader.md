# blocky-shader 性能调研（batch4）

> 只读调研，不含对 Astra 的任何改动。包内路径相对 `reference_shaderpacks/blocky-shader/shaders/`；Astra 侧路径相对 `Astra/shaders/`。
> 版本：Modrinth v0.6.1（任务给定；包内 `programs/settings.glsl:1-4` 头注明 "Blocky Shaders v0.6 by dvimidh"）。下载量 181,790（任务给定）。
> 去重口径：先读 `shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`，再对 `Astra/shaders` 多关键词 grep。

## 一、概况

- 定位：原版风格、主打性能的 Minecraft Java 光影。README 自述特性：阴影、彩色阴影、Distant Horizons 支持、基础 PBR（需资源包）、FXAA、基于高度解析雾、树叶/水波动、Bloom、硬编码自发光（`README.md:12-21`）。
- 血统：dvimidh 自研（`programs/settings.glsl:1-4` 文件头；MIT 版权 2025）。第三方来源已声明：FXAA 3.11 经 Capt Tatsu's BSL 许可（`README.md:17`；`programs/include/fxaa.glsl:1-2`）；高度解析雾来自 Inigo Quilez 雾文章（`README.md:18`）；体素代码来自 timetravelbeard 教程（`programs/include/voxelizing.glsl:2-8`，且未接线）。与已研究的 62 款均不同源（仅 BSL FXAA 这一通用实现共享上游），按自研口径报机制、不需报相对增量。
- 许可：MIT（`LICENSE:1-4`，Copyright (c) 2025 dvimidh）。允许代码级借鉴并保留许可文本；FXAA 片段另有 BSL 来源，若搬运应循 BSL 渠道（与 SUMMARY-batch2 对 tea 等包的既有口径一致）。
- 规模：`shaders/` 树 80 文件 / 3112 行（.glsl/.fsh/.vsh/.csh，实检 3112）。实际逻辑集中在 `programs/`（settings、include、shadow/composite/dh 源文件），根目录程序多为一行 `#include` 薄壳。

## 二、管线与调度

- 程序清单：gbuffers_terrain / entities / hand / basic / textured / textured_lit / skybasic / skytextured / clouds / spidereyes / beaconbeam / line / armor_glint；shadow；shadowcomp_a.csh；composite、composite1/2/3（Bloom 降采样）、composite5/6（Bloom 可分离高斯）、composite18/19/20（Bloom 升采样）、composite21（FXAA+Bloom 合并）；final；dh_terrain / dh_water（Distant Horizons）。**无 gbuffers_water、无 gbuffers_weather**：水面走 terrain 的 EntityID 10006（`block.properties:1`），雨粒子走 gbuffers_textured_lit。
- 调度：光照全部在 gbuffers 前向着色完成（`programs/include/lit_frag.glsl:59-137`，入口被 terrain/hand/basic 复用）；composite 做雾、天空/DH 分支与 Bloom 捕获；Bloom 链 1→2→3 降到 1/8 → 5/6 在 1/8 上做 51-tap 可分离高斯 → 18/19/20 逐级升采样 → 21 与 FXAA 合并写回 colortex0 → final 饱和度/tonemap。
- shaders.properties 要点：`iris.features.required = SEPARATE_HARDWARE_SAMPLERS CUSTOM_IMAGES`（`:1`）；VOXEL_AREA 四档定义 cimage1/cimage2 为 R32UI 3D image（32³/64³/128³/256³，`:4-23`，默认 `VOXEL_AREA=0` 即关闭，`programs/settings.glsl:31`）；`dhShadow.enabled=false`（`:24`）；菜单分组（`:25-39`）；`mipmap.colortex1=false`（`:40`）；`separateAo=true`（`:41`）；`size.buffer.colortex2=0.5`、`colortex3=0.25`、`colortex4=0.125`（`:42-44`）；`dhClouds=off`（`:46`）；`VOXEL_AREA!=0` 时 `shadow.culling=reversed`（`:47-49`）；`customTexture.lightmaptex=minecraft:dynamic/lightmap_1`（`:51`）；5 个 profile（Default/Vanilla/Bright/Realistic/Vibrant，`:53-61`）。
- 阶段启停：**全包无一条 `program.*.enabled`**。BLOOM/FXAA 仅源码级 `#ifdef`；`profile.*` 行里 `BLOOM=false` 只去掉 shader 主体，composite1/2/3/5/6/18/19/20 仍被调度为空 pass（见反面印证）。

## 三、分模块性能手法清单

### 调度与阶段启停
- `shaders.properties:42-44`：Bloom 链 0.5/0.25/0.125 三级显式降采样缓冲。
- `programs/settings.glsl:31`：VOXEL_AREA=0（体素彩光链默认整体关闭）。
- `shadowcomp_a.csh:1-17`：体素链唯一的 compute，仅把 cimage1 逐格 `imageAtomicExchange` 拷贝到 cimage2（无传播、无消费）。
- `gbuffers_textured_lit.fsh:12`：`RENDERTARGETS: 5`，粒子只写独立缓冲。
- `gbuffers_clouds.fsh:15-17`：`DRAWBUFFERS:06`，云只写 colortex6（不写主色，复合端叠加）。
- `programs/composite_frag.glsl:325-327`：`DRAWBUFFERS:01` 场景与 Bloom 捕获一次写出。

### 地形光照与阴影
- `programs/include/functions.glsl:194-195`：`shadowtex0HW`（硬件比较采样器）与 `shadowtex1`（不透明）两次 step 查询；`:196` `shadowcolor0` **无条件**读取；`:202-214` 按是否遮挡分三路（全可见 / 透明遮挡染色 / 不透明遮挡）；`:216-218` 水面同深度特判强制受光。
- `programs/include/functions.glsl:171-178`：`PIXEL_LOCKED_SHADOWS` 把片元世界位置量化到 `1/PIXEL_LOCKED_SHADOWS_RES` 网格（再加 0.08 法线偏移）后查阴影——像素锁定。
- `programs/include/functions.glsl:207-209`：SHADOW_FILTERING 打开时直接用硬件比较采样值当可见度（免额外 tap 的软边）。
- `programs/include/distort.glsl:2-8`：`xy/(|xy|+0.3-D/5)` 径向畸变、z 轴压缩 0.5。
- `programs/include/functions.glsl:220-256`：天光/方块光——方块光取烘焙光图 `pow(lightmap, 4.2/BLOCKLIGHTSPREAD)`、天光 8 段 sunAngle 色表、雨天去饱和；`:279` 半球环境光 `clamp(dot(up,n),0.8,1)`。
- `programs/include/lit_frag.glsl:78-82`：alpha<0.1 discard；`:100-105` 硬编码自发光材质（EntityID 10010）；`:108` 进入完整 `lightingCalculations`。
- `programs/include/lit_vert.glsl:45-58`：树叶/水面顶点位移（wave 场）；`programs/include/wave.glsl:3-13`：6 对 sin 乘积波场。
- `gbuffers_entities.fsh:70-71`：`dhBlend` 计算后从未使用（死代码）。

### 云
- `gbuffers_clouds.fsh:13`：原版云纹理 × 顶点色 × 1.3，无光照/无噪声。
- `programs/composite_frag.glsl:318`：云按 alpha 混入雾后场景（`color = mix(color, colorCloud.rgb, colorCloud.a)`）。

### 雾与大气
- `programs/composite_frag.glsl:81-91`：解析高度雾（Inigo Quilez）——双 logistic 密度沿射线 log 积分，`FOG_DECAY_START/END` 控衰减区间，含相机高度项；每像素 2 次 exp + 2 次 log。
- `programs/composite_frag.glsl:119-147`：介质切换（isEyeInWater 1/2/3 = 水/岩浆/细雪）；`:129-133` 天空像素直接返回不雾化。
- `programs/composite_frag.glsl:150-163`：主入口按 depth==1 / DH 云遮挡标志走不同分支；`:166-204` 天空与 DH 分支；`:206-260` 双深度水雾（depthtex0 水面前景 / depthtex1 不透明背景 之间混雾）；`:263-273` 天空像素重算天空色；`:275-316` CHUNK_FADE 距离淡出并再算一次天空色。
- `programs/include/fogColorCalc.glsl:1-35`：雾色三段 keyframe（晨/昼/夜）+ 雨天向天空色偏移；`programs/include/SkyColorCalc.glsl:7-65`：解析天空梯度 + 太阳光晕 `pow(sunAmount,100)`（`:63`）；`programs/include/SunColorCalc.glsl:2-29`：日色 keyframe + sunfade。

### 水与水下
- 水面在 gbuffers_terrain（EntityID 10006）；`programs/include/lit_frag.glsl:88-97` 水透明度×色彩风格、`:113-118` 亮度 clamp。
- `programs/include/functions.glsl:158-166`：WATER_STYLE=1 覆盖水粗糙度/反射率/反照率；`:294-301` 高光超阈值时太阳色×50.4 的水面闪光 hack。
- `programs/include/lit_vert.glsl:50-57` + `programs/include/wave.glsl:3-13`：顶点位移；`programs/include/functions.glsl:117-135`：片元内 3 次 `wave()`（各 12 个 sin）差分求法线。
- `programs/include/lit_frag.glsl:119-126`：水面元数据写 colortex7（rg=颜色、b=透明度、a=doit 标志）。
- `programs/composite_frag.glsl:206-260`：不透明背景与水面的双深度混雾。
- `dh_water.fsh:92-215`：DH 水面独立简化光照（无阴影、无光照图方块光之外的项）。

### 粒子·实体·天气
- `gbuffers_textured_lit.fsh:16-17`：粒子 = 纹理 × 顶点色 × 烘焙光图，无阴影/无方向光/无介质吸收；`:12` 写 colortex5；`programs/composite_frag.glsl:64,319` 雾后按 alpha 叠加。
- `gbuffers_entities.fsh:56-73`：实体走完整前向（阴影 + BRDF）。
- 无 weather 程序：雨天粒子走上述 textured_lit 简易路径。

### 后处理与缓冲内存
- `programs/composite_frag.glsl:320-324`：Bloom 阈值 `pow(max(luma-0.12,0),5)`；`:325-327` 捕获写全分辨率 colortex1（无 `#ifdef BLOOM` 保护）。
- `programs/composite1_frag.glsl:26-33` / `composite2_frag.glsl:24-31` / `composite3_frag.glsl:24-31`：中心×4 + 四角 /8 的 5-tap 降采样，逐级 0.5/0.25/0.125。
- `composite5.fsh:30-40` / `composite6.fsh:30-40`：1/8 分辨率上 ±25 tap 可分离高斯（BLOOM_SIGMA=50，权重每次重算 exp）。
- `composite18.fsh:13-41` / `composite19.fsh:14-42` / `composite20.fsh:14-42`：12-tap tent 升采样回 colortex3/2/1。
- `composite21.fsh:5`：`colortex1MipmapEnabled = true`（与 `shaders.properties:40` `mipmap.colortex1=false` 冲突，见无法判定）；`:18-34` FXAA + Bloom 合并写 colortex0。
- `final.fsh:44-57`：饱和度调整 + `mix(tonemapMe3(color), color, 0.0)`（tonemap 实际被无效化，死代码）。
- 缓冲：colortex0 场景、colortex5 粒子、colortex6 云、colortex7 水元数据、colortex1-4 Bloom 链；无统一尺寸/格式声明（`programs/settings.glsl:6-16` 的格式块整段在注释内）。

## 四、反面印证（不值得学的做法）

1. **彩色阴影无条件读取**：`programs/include/functions.glsl:196` 在判断前就 `texture(shadowcolor0,...)`，受光像素（占多数）也付一次采样；对比 Astra 只在出现透明遮挡时 gather `global/lighting/shadowmap.glsl:140,145,152-169`，且 `global/lighting/diffuse.glsl:333-345` 面向早退直接跳过整组阴影取数。
2. **Bloom 关闭不彻底**：9 个 Bloom 相关 pass 无程序级熔断，关闭时仅空 main 仍调度；`programs/composite_frag.glsl:322-327` 的捕获写入无 `#ifdef BLOOM`，关闭后仍全分辨率写 colortex1。对比 Astra「零强度停调度 + 0.25 捕获 + mip 链」（`global/post/bloom.glsl:1-18`）。
3. **解析雾重复求值**：`programs/composite_frag.glsl:87-91` 每像素 2 exp + 2 log；`:263-273` 天空像素重算天空色（结果在 `:275-316` 的 CHUNK_FADE 分支外未被使用，纯浪费）；CHUNK_FADE 分支又复算一遍。Astra 应保留现有雾公式与单次求值纪律。
4. **体素彩光链未完成，不可作为借鉴对象**：消费端整段注释（`programs/include/functions.glsl:259-265`）、写入端注释（`gbuffers_terrain.vsh:62-95`）、`shadowcomp_a.csh:11-15` 只做拷贝、默认 VOXEL_AREA=0；且 VOXEL_AREA=0 时程序仍无条件声明 cimage1/cimage2（`programs/shadow_vert.glsl:5-6`、`gbuffers_terrain.vsh:3`）而 properties 无 image.* 定义。R32UI + `packUnorm4x8` + 每 quad 单顶点写（`programs/include/voxelizing.glsl:27,50,55`）本属 SUMMARY-batch2 已列（amethyst「8 位+r8ui、每 quad 单顶点写」）。
5. **每像素 3 次 wave() 差分法线**：`programs/include/functions.glsl:117-135`，单水面像素约 36+ 三角函数（每次 12 sin），且无距离/角度早退；Astra 波场 + SSR 组合更省。
6. **死代码与配置矛盾**：`final.fsh:51` 无效 tonemap；`gbuffers_entities.fsh:70-71` 未用 `dhBlend`；`programs/include/lit_vert.glsl:25` / `lit_frag.glsl:43` 声明 `lightLevel` 但片元未使用；`shadowcomp_a.csh:14` `test` 未用；`dh_water.fsh:206-210` 未用变量；`mipmap.colortex1=false` 与 `colortex1MipmapEnabled=true` 冲突。
7. **原版云走完整纹理但无光照**：`gbuffers_clouds.fsh:13` 仅 ×1.3，云亮度完全靠 `gl_Color`，无方向/阴影响应——Astra 平面云不应参考其光照组织。

## 五、新颖借鉴点（A/B/C）

- A（低代价可直接排期）：**无**。
- B（中代价需接线）：**1 条**。
- C（大工程战略项）：**无**。

### B-1 粒子/半透明独立简化光照缓冲 + 雾后合成

- 机制：`gbuffers_textured_lit` 对粒子只做「纹理 × 顶点色 × 烘焙光图」，不做阴影查询、不做方向光 BRDF、不做介质吸收，结果写独立 colortex5（`gbuffers_textured_lit.fsh:12,16-17`）；composite 在雾/天空处理之后按 alpha 叠加（`programs/composite_frag.glsl:64,319`）。即用独立缓冲把粒子从完整前向光照中摘出来，省去每像素的阴影采样与光照求值。
- 来源：`gbuffers_textured_lit.fsh:12-20`；`programs/composite_frag.glsl:61-65,318-320`。
- Astra 侧未实现证据：
  - `grep -rn "ASTRA_PARTICLE" --include="*.fsh" --include="*.vsh" --include="*.glsl" Astra/shaders` → 粒子入口 `gbuffers_particles.fsh:1-3`、`gbuffers_particles_translucent.fsh:1-3` 定义该宏，但 `program/lit.fsh` 内唯一的 ASTRA_PARTICLE 分支是 `program/lit.fsh:171-175` 的雨溅隐藏 discard；
  - `grep -n "astra_light(" program/lit.fsh` → `program/lit.fsh:264`，粒子仍进入完整前向（阴影 + 方向性 SH + 介质）；
  - `grep -rn "colortex5" Astra` → 仅水面界面记录用途（`lib/water_interface_record.glsl:6-16`、`program/water_state.fsh:15-21`），无粒子缓冲；
  - Astra 现有的粒子廉价分支只覆盖天气：`program/lit.fsh:249-253`（雨雪用天空环境 + 方块光直给），未覆盖普通粒子。
- 迁移代价：在 `program/lit.fsh` 为 `ASTRA_PARTICLE` 增加独立廉价光照分支（可直接复用 `program/lit.fsh:251` 的天气公式）并加选项门控；若照 blocky 独立缓冲 + 雾后合成则需新渲染目标与 composite 接线。代价是粒子失去阴影与介质衰减，必须先做画质 A/B；收益取决于粒子 overdraw（大雨/烟雾/下界粒子场才明显），源码无法判定。

### 去重排除明细（机制 | 包内出处 | 排除依据）

| 机制 | 包内出处 | 排除依据 |
|---|---|---|
| 像素锁定阴影（世界网格量化 + 法线偏移） | `programs/include/functions.glsl:171-178` | SUMMARY-batch3.md:89,262-264 已列（simply-upscaled，B 组）。Astra grep `PIXEL_LOCK|pixel_lock|SHADOW_PIXEL|snap|quantiz` 无功能命中（仅注释/编码模块） |
| 硬件比较采样器/PCF | `shaders.properties:1`；`programs/include/functions.glsl:194,207-209` | Astra 已有 `sampler2DShadow` + `shadow_gather_visibility`（`global/lighting/shadowmap.glsl:40-41,120-130`）与 `shadowHardwareFiltering`（`lib/settings.glsl:451-453`）；SUMMARY-batch2.md:121（reverie）已列 |
| 彩色阴影（shadowcolor0 染色） | `programs/include/functions.glsl:196,211` | Astra 已实现彩色阴影，且遮挡时才读（`global/lighting/shadowmap.glsl:145-177`）；SUMMARY.md ②-1 已列 |
| 解析高度雾（IQ 双 logistic 积分） | `programs/composite_frag.glsl:81-91` | SUMMARY-batch2.md:68（glimmer 解析高度雾）已列；Astra `global/atmosphere/fog.glsl` |
| 双深度水雾（depthtex0/depthtex1 间混雾） | `programs/composite_frag.glsl:218-260` | SUMMARY-batch2.md:230（⑤-1 表，eclipse「双深度水柱低配水雾」）已列 |
| DH 集成（depth==1 交接、只补天空像素） | `programs/dh_terrain_frag.glsl:141-143,202-206`；`dh_water.fsh:199-204` | SUMMARY-batch2.md:117（sildurs/glimmer/bvs「Voxy/DH 集成契约 + 第二套前向着色」）已列；Astra 已有 voxy 骨架（`program/lit_voxy.fsh:1-8`、`voxy_opaque.glsl:1-4`，均 TODO stub、`voxy.json` 0 字节） |
| 云独立缓冲 + 雾后合成 | `gbuffers_clouds.fsh:15-17`；`programs/composite_frag.glsl:318` | Astra 已是独立云程序 + 屏幕云/元数据双缓冲（`program/clouds.fsh:14-16`、`program/cloud_screen.fsh:19-38`），任务背景已列 |
| Bloom 降采样链 / dual-kawase 升采样 | `composite1-3`、`composite5/6`、`composite18-21` | Astra 已是 0.25 捕获 + mip 链两 pass（`global/post/bloom.glsl:1-18`）；SUMMARY-batch3 §2.5 #4 已列 mip/tap 分档 |
| 后处理合 pass（FXAA+bloom 同 pass） | `composite21.fsh:18-34` | SUMMARY-batch3 §2.4 已明确不学单 pass 合并（YoFPS）；Astra 维持分阶段 + 熔断 |
| separateAo 门控 | `shaders.properties:41` | Astra 已有同名条件开关（`shaders.properties:236-239`） |
| AO 强度指数 | `programs/include/functions.glsl:303,306` | Astra 有 AO 物料/重建链（`lib/ao_material.glsl`、`lib/ao_resolve.glsl`、`program/ssao.fsh`） |
| 硬编码自发光材质 | `programs/include/lit_frag.glsl:100-105` | SUMMARY.md ②-1「IPBR 自发光启发式」已列 |
| 烘焙光图取方块光（customTexture.lightmaptex） | `shaders.properties:51`；`programs/include/functions.glsl:220` | Astra 已有自定义纹理机制（`shaders.properties:441-448`）与方块光模块（`global/lighting/blocklight.glsl`） |
| profile 预设 | `shaders.properties:53-61` | 已列（Kappa/Miniature/BQOL 等 profile 定义） |
| FXAA 3.11 | `programs/include/fxaa.glsl:1-2` | Astra 已有 `global/post/fxaa.glsl`；实现来源为 BSL（非本包原创） |
| 基础 PBR（法线/高光/粗糙度） | `programs/include/functions.glsl:14-58,136-156` | 任务背景：Astra 已实现前向 PBR 材质链 |
| 水面并入 terrain 程序（少一个 gbuffers_water） | `block.properties:1` | 架构选择（水量/半透明仍照常光栅），非可省计算的手法；Astra 独立 water 程序 |

## 六、无法判定项

1. `mipmap.colortex1=false`（`shaders.properties:40`）与 `composite21.fsh:5` 的 `const bool colortex1MipmapEnabled = true` 冲突：Iris 以哪个为准未实测，直接影响 Bloom 缓冲的显存与采样带宽。
2. VOXEL_AREA=0 时 `shadowcomp_a.csh` 仍声明并使用 cimage1/cimage2，而 properties 无 `image.*` 定义：Iris 是报错、降级还是跳过编译未实测（体素链整体未接线，不建议在确认前参考）。
3. `SHADOW_FILTERING` 默认 false，仅 profile.Bright/Realistic 打开；SEPARATE_HARDWARE_SAMPLERS 依赖在 Astra 环境的行为需环境核验（SUMMARY-batch2 ④-1 S1 仍开放）。
4. 粒子雾后合成（B-1）的实际收益取决于粒子像素占比与 overdraw，源码无法判定，需固定机位 A/B。
5. `dhShadow.enabled=false` 与 `dhClouds=off` 对 DH 场景的净收益（Astra 无 DH 程序，暂时不适用）。
