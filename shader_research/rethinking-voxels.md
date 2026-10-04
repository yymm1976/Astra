# Rethinking Voxels r0.1-beta9 研究报告（面向 Astra 的可借鉴点）

> 源码位置：`reference_shaderpacks/rethinking-voxels/`。下文未加前缀的文件路径均相对该包的 `shaders/` 目录；
> Astra 文件路径相对 `Astra/shaders/`。所有 `文件:行` 引用均来自本包实际源码（已抽样复核）。

---

## ① 包概览

- **版本**：r0.1-beta9。`shaderFile_Versions.txt:1-2` 表明其基线为 **Complementary Reimagined r5.5.1 + Complementary Unbound r5.5.1**；即非体素部分是 Complementary 血统（program/shadow.glsl:2 文件头仍署名 "Complementary Shaders by EminGT"），RV 增量集中在体素彩光（ACL）与体素反射。包内未发现 RV 修改者的署名文件。
- **许可证**：`License.txt:1` 为 **Complementary License Agreement 1.5**（与 Complementary 正传同族的自定义许可，非开源）。关键条款：Normal Usage 明确排除 *Redistributing (parts of) The Pack* 与 *Modifying code*（License.txt:7-13）；唯一改编通道是 1.3 "Modified Pack" 授权，要求显著署名原包并链接官网、原样保留 License.txt、名称避开 "Complementary"、视觉显著不同、不得叠加其它许可（License.txt:51-69）。对 Astra 的含义见 ⑤。
- **风格定位**：写实向 Complementary 观感 + "体素彩光 everywhere"：火把/熔岩/下界传送门等光源在近场投出真实的彩色体素阴影，方块光可穿透体积雾形成彩色光柱，体素场还反哺 connected glass、斜切边缘、水体交互涟漪与体素反射等非光照特性。
- **硬性依赖**：`shaders.properties:213` `iris.features.required=CUSTOM_IMAGES SSBO COMPUTE_SHADERS`——必须 Iris + 自定义 image + SSBO + compute。这与 Astra（Iris 专用、已用 compute）兼容。
- **规模开关**（shaders.properties:5-9 profile 行）：体素场 `VX_VOL_SIZE` 四档（96³/128³/256³/512³，见 224-246 行 image 尺寸表）；逐像素光 `BLOCKLIGHT_RESOLUTION` 1/2/3/4/6/8（prepare4_csh.glsl:6-18 按 1/n 分辨率跑 compute）；`LIGHT_TRACE_LENGTH` 默认 30 格（lib/common.glsl:52）；`GI` 默认开（lib/common.glsl:45）。

## ② 架构与特性清单

### 2.1 体素管线（核心，全链路）

**存储布局**（全部为 Iris custom image + 1 个 SSBO，shaders.properties:224-246、249）：
- `voxel_img`：R8UI 3D，方块 ID（光照物种/玻璃/冰/水等，编码见 lib/misc/voxelization.glsl:23-238 的 `GetVoxelIDs`，ID 表与 item.properties 联动）。
- `occupancyVolume`：R32I 3D，位域高度复用：bit0-7 = 各 LOD 不透明占据（shadow.glsl:225），bit8 起为半透明占据（同式 `1<<(k + 8*int(col.a<0.9))`）；bit16 = 光源位，bit17-21 = 照射距离（`lightLevel + localMat/4%32<<5 << 17`，shadow.glsl:508），bit27 = 实体光，bit28-29 = 天光档。
- `voxelCols`：R32I 3D（Y 方向 ×2，成对 texel 存上下半），打包 13bit×3 RGB + alpha，几何着色器里用 `imageAtomicAdd` 多边形累加（shadow.glsl:369-377）；bit26 = 水、bit27 = 实体（shadow.glsl:379-382）。
- `distanceFieldI`：RGBA16F 3D，**多分辨率 SDF**：RGBA 四通道各存一档 LOD 距离，Y 方向 4 倍高容纳 2 帧 ping-pong × 2 组 LOD（shadowcomp.glsl:91-98 写入时 `(frameCounter+1)%2` 偏移；采样端 voxelReading.glsl:11-16 按 `resolution/4`、`resolution%4` 选层）。
- `irradianceCacheI`：RGBA16F 3D（Y ×2 双层）：layer0 = GI 辐照、layer1 = 体素方块光（shadowcomp1.glsl:355）。
- `lightStorage`：RGBA16I 3D，屏幕空间光列表的体素版——每格存"对本格贡献最大的一个光源自Xi坐标+权重"（shadowcomp1.glsl:356-357）。
- `globalLightHashMap` SSBO：2^18 槽 ×4 uint，位置哈希（positionHashing.glsl:1-8，注明改自 David Hoskins hash13，**CC-BY-SA 4.0**）→ 打包的亚体素光源中心（1/32 精度）+ 1/32 量化颜色。

**写入端（shadow pass，一鱼三吃）**：
1. 顶点级 ID 写入：`UpdateVoxelMap`（voxelization.glsl:241-263）在 shadow 顶点着色器直接 `imageStore(voxel_img, ivec3(voxelPos), uvec4(voxelData))`（261 行）；每 quad 只跑一次（shadow.glsl:686 `gl_VertexID % 4 == 0`）。只收 terrain solid/cutout/cutout_mipped/translucent 四个 renderStage（252-256 行）；水、`mat%4==1` 的非固体、方块实体一律跳过（242-245 行）。
2. 几何/片元级占据光栅化：几何着色器把三角形按 LOD k 重投影进 shadow map（`passType = 1 + localResolution<<1`，shadow.glsl:538，发射块 521-545），片元里 `imageAtomicOr(occupancyVolume, coords2, 1<<(k + 8*int(col.a < 0.9 && doTransparency)))`（shadow.glsl:225）——**用阴影贴图光栅化硬件做多 LOD 占据体素化**，alpha<0.9 记半透明位。
3. 颜色与光源种子：片元把纹理均色 `imageAtomicAdd` 进 voxelCols（shadow.glsl:369-377）；发光方块同时把亚体素中心与颜色 atomicAdd 进 globalLightHashMap（shadow.glsl:468-499，累加在 496-499），并置 occupancy 光源位 + 照射距离位（500-508 行）。**哈希表每帧由 final.fsh 增量清零**（final.glsl:146-155，按屏幕像素均摊清除）。

**SDF 构建**（shadowcomp.glsl CSH）：以 8³ workgroup、10³ shared 内存做 27 邻域跳点扩散（shadowcomp_sdf_loop.glsl:66-78），从上一帧同 LOD 平移值热启动（13-21 行），低 LOD 由高 LOD 下采样兜底（24-37 行）；`SDF_UPDATE_INTERVAL` 允许隔帧跳更新（3 行），边缘做距离淡出防体积边界跳变（87-90 行）。同一 pass 顺带把 voxelCols 颜色外扩进相邻空气格，缓解角点伪影（shadowcomp.glsl:100-124）。

**光源整理**（shadowcomp.glsl CSH_A/CSH_B）：相邻同组光源聚簇——CSH_A 把 ≤128 个相邻光源合并成单光源（均值位置/颜色回写哈希表，shadowcomp.glsl:195-279，`MAX_CLUMP_SIZE 128`）；CSH_B（`LIGHT_CLUMPING`，默认关，lib/common.glsl:58）做跨 workgroup 的 2 次下探合并（284-423 行）。

**体素方块光计算**（shadowcomp1.glsl CSH_A，逐体素）：
- 先把 irradianceCache/lightStorage 按相机整格位移搬移 + 0.99 时间衰减（shadowcomp1.glsl:34-49，42 行 `writeColors[0] *= 0.99`）；34-35 行用镜像坐标序保证多线程不读脏数据。
- 光源收集三路并集：occupancy 光源位 + 上一帧 lightStorage + 邻近 workgroup 列表（249-272 行）；按亮度权重 batcher 排序取前 `MAX_LIGHT_COUNT`。
- 对每光源做 SDF **coneTrace 软阴影**（322 行）+ `distanceFalloff`（135-147 行，可选 1/r² 档），写入 layer1；距视锥距离越大更新间隔越稀（232-234 行 `updateInterval = min(0.01*dist²+1, 10)`）。
- GI（CSH_B，362-553 行）：对表面体素做随机半球 `rayTrace`（506 行）取命中点 albedo（`getColor`）+ 命中点方块光/阳光/上一轮 GI，合成入 layer0；半透明命中用 `voxelTrace` 上色（508-512 行）。

**屏幕空间逐像素光**（prepare4_csh.glsl，PER_PIXEL_LIGHT 时启用）：
- 按 1/BLOCKLIGHT_RESOLUTION 分辨率跑 32×32 compute（5-18 行）；光列表来源：上一帧 colorimg11、随机半球射线命中（302-309 行）、邻域 tile 光（317-324 行）。
- 逐光源 coneTrace（372 行）出漫射；`BLOCKLIGHT_HIGHLIGHT` 时再用 GGX 出**光源镜面高光**（397-410 行）；光源尺寸由 SDF 距离夹取（361-363 行 `lightSize = clamp(lightSize, 0.01, getDistanceField(lightPos))`）。
- 写出前做 `writeColor *= log(lWriteColor+1)/lWriteColor` 对数压缩（422-425 行），结果与光列表分别落 colorimg10/11/13，再由 prepare4_csh_a 上采样回全分辨率（prepare4_csh_a.glsl:197）。
- prepare3 在 gbuffer 前用 SDF rayTrace 重建被挡/出屏像素的深度法线（prepare3.glsl:74-84），让光列表覆盖"看不见的几何"。

**采样端**：
- 表面方块光：`readSurfaceVoxelBlocklight`（irradianceCache.glsl:16-23，含 log 压缩）或逐像素 colorimg12（mainLighting.glsl:492-506）；GI：`readIrradianceCache`（irradianceCache.glsl:9-14，mainLighting.glsl:511-513）。
- 体积方块光：`GetVolumetricBlocklight` 沿视线采 layer1（volumetricBlocklight.glsl:81-83），下界/末地独立倍率 `VBL_NETHER_MULT/VBL_END_MULT`（101-104 行）；彩色光雾 `GetColoredLightFog`（coloredLightFog.glsl:1-56）。
- 与原版光膜的混合退路：`voxelFactor = pow(min(1, 2*infnorm(vxPos/voxelVolumeSize)), 10)`（mainLighting.glsl:86），体积外平滑退回原版 blocklight（550-554 行 `blockLighting = mix(voxelBlockLighting, blockLighting, voxelFactor)`）。

### 2.2 阴影与光照（非体素部分，Complementary 血统）
- 实时阴影贴图与体素光**分工并行**：太阳/月亮仍走 shadow map（lib/lighting/shadowSampling.glsl，REALTIME_SHADOWS），体素 SDF 只管方块光源遮挡；两者在 mainLighting 内相加，交接处 16 格阴影距离淡入淡出（mainLighting.glsl:278-284 `shadowSmooth = 16.0`）。
- 阴影软化、SSAO+原版 AO 叠加、日落金色乘法等均为 Complementary 体系（lib/lighting/）。
- 彩色方块光物种表：70+ 物种逐一给色/亮度（lib/colors/blocklightColors.glsl + 设置屏 shaders.properties BLOCKCOLS 区块，约 55-120 行），包括发光矿石、蛙明灯、蜡烛逐色（voxelization.glsl:202-217 `COLORED_CANDLE_LIGHT` 分支）。

### 2.3 大气 / 云
- Complementary 全套：解析天空渐变、Reimagined 平面夹层体积云、Unbound 卷云、星空/极光/星云/彩虹、边界雾/洞穴雾。
- RV 特有：**下界灰烬风暴** `GetNetherStorm`——3D 噪声射线步进体积，`stormSample *= traceAltitudeM` 按高度衰减（lib/atmospherics/netherStorm.glsl:12-79，默认开 lib/common.glsl:168）。

### 2.4 水体
- Complementary 水体系（法线纹理三尺度、折射 UV 扰动、SSR、泡沫、水下透视）。
- **交互水波**（INTERACTIVE_WATER）：shadowcomp2 用体素场找水面高度，玩家扰动写入 shadowcolorimg2 的多 LOD 涟漪缓存（program/shadowcomp2.glsl:27-60 起，`attenuationCoeff = vec4(0.994,...)[lodIndex]`），水面法线读取该缓存产生真实扩散波纹。
- 焦散在 shadow pass 内实现（shadow.glsl:96-141，差分核心 132-137），体素场另给 `voxelCols` bit26 标记水体供其用（shadow.glsl:379）。

### 2.5 后处理
- Bloom、色调映射 + 颜色分级矩阵、FXAA、TAA、景深/动态模糊/色差/锐化、镜头光晕——全部 Complementary 血统（program/composite*.glsl、lib/colors/tonemap 相关）。

### 2.6 性能与时域
- 体素更新三重分摊：SDF 隔帧（SDF_UPDATE_INTERVAL）、体素光按距离稀疏更新（shadowcomp1.glsl:232-234）、光源聚簇减数量（shadowcomp.glsl:195-279）。
- 时域复用：哈希表光源每帧重建但列表时域复用（lightStorage/colorimg11 上一帧光 + 0.0001 权重保活，shadowcomp1.glsl:250-254）、irradianceCache 0.99 衰减累积、屏幕光列表跨帧传递。
- 光线预算：MAX_TRACE_COUNT（低配 16/高配 96）截断每像素锥追数（prepare4_csh.glsl:415-416）；RT_STEPS 控制 SDF 步进。

## ③ Astra 可借鉴点

1. **SDF 多分辨率距离场 + coneTrace 光源软阴影**
   - 技术：occupancy 位域 → shadowcomp_sdf_loop 的 27 邻域跳点扩散 + 上一帧热启动，得到 4 档 LOD 的 SDF（RGBA 四通道打包）；对每个可见光源锥追一次即得面光源级软影与半影。
   - 出处：shadowcomp_sdf_loop.glsl:15-21（占据→距离）、66-78（27 邻域扩散）、shadowcomp.glsl:91-98（ping-pong 存储）、voxelReading.glsl:65-108（coneTrace 本体）。
   - 对应 Astra 模块：program/nether_light.csh（现为 0.72 max 扩散，无遮挡阴影）；Astra/shaders/global/dimension/nether_colored_light.glsl 采样端。
   - 迁移难点：中高。Astra 64³ 单分辨率体量小，SDF 可只做 1-2 档 LOD；需新增一张 RGBA16F 3D image 与一个 shadowcomp 段，coneTrace/梯度函数可直接照公式重写（voxelReading.glsl:11-25 仅 ~25 行）。
2. **逐像素光源列表 + GGX 彩光高光（治"体素灯光高光粗糙"）**
   - 技术：屏幕空间 1/n 分辨率 compute，逐像素收集（上一帧列表 + 随机射线发现新光 + 邻域共享）、排序截断、逐光源 coneTrace 漫射 + GGX 镜面；分辨率 1/2-1/8 可调。
   - 出处：prepare4_csh.glsl:5-18（分辨率档）、294-324（列表来源）、372（锥追）、398-410（GGX 高光，GGX 调用在 400）、422-435（log 压缩+写出）、prepare4_csh_a.glsl:197（上采样）。
   - 对应 Astra 模块：Astra/shaders/global/dimension/nether_colored_light.glsl（当前仅三线性梯度采样，无逐像素光源概念，高光只能靠纹理粗糙度近似——这正是"体素灯光梯度粗糙高光"的根源）。
   - 迁移难点：中。Astra 下界光源密度高但物种少（11 种，program/nether_light.csh:37-46），光列表可直接从体素场种子格提取；需引入 SSBO 光源表与一张 rgba16i 列表 image。
3. **光源亚体素中心 + 每帧哈希表重建（光源"体积感"）**
   - 技术：发光几何的纹理均色与三角形重心按 1/32 精度 atomicAdd 进位置哈希 SSBO，得到非格点亮源；哈希表每帧由 final 增量清零、shadow pass 重建，免管理生命周期。
   - 出处：shadow.glsl:483-499（meanPos/meanCol 打包累加）、final.glsl:146-155（增量清除）、SSBOs.glsl:8-13（绑定 0）。
   - 对应 Astra 模块：program/shadow.vsh:47-84（`astra_voxel_write` 现按整格 imageAtomicMax 写物种 ID，光源中心恒为格心）。
   - 迁移难点：低-中。可在 Astra shadow.vsh 顶点级近似（at_midBlock 偏移均值），或照搬 SSBO 方案；注意 positionHashing.glsl:1-8 是 CC-BY-SA，需换自写哈希或加署名。
4. **体素光的时域缓存与相机平移搬移**
   - 技术：irradianceCache/lightStorage 按相机整格差移位（镜像坐标序防竞态）、0.99 衰减累积、远处格子每 N 帧才更新；光源列表跨帧保活。
   - 出处：shadowcomp1.glsl:31-50（搬移+衰减）、34-35（执行顺序技巧）、232-234（距离稀疏更新）、250-254（列表保活）。
   - 对应 Astra 模块：program/nether_light.csh（"cleared every frame; no temporal light history"，文件头注释明示同帧九段）；Astra/shaders/lib/effect_history.glsl（现有时域设施）。
   - 迁移难点：中。Astra 九段 dispatch 结构可保留，把 step0 改为"搬移+衰减"而非清零重建即可省一次种子重建并稳定低频光；需处理下界岩浆大面积闪烁的鬼影权衡。
5. **体积方块光 / 彩色光雾统一场**
   - 技术：体积雾采样与屏幕雾共用同一 irradianceCache layer1，无需独立传播；下界/末地各有强度倍率；对数压缩防过曝。
   - 出处：volumetricBlocklight.glsl:81-83、101-105；coloredLightFog.glsl:1-56（尤其 40-48 的强度塑形）；irradianceCache.glsl:25-30。
   - 对应 Astra 模块：Astra/shaders/global/dimension/nether_volume.glsl（现按 Bliss 噪声密度场，光色未与体素光场耦合，见其 1-9 行注释）；nether_fog_density.glsl。
   - 迁移难点：低。Astra 已有 64³ 彩光场与体积 march 骨架，把 nether_volume 的 in-scatter 项换成体素场三线性采样即可，工作量最小、观感收益直接（岩浆湖光柱）。
6. **半透明体的彩光染色**
   - 技术：occupancy bit8 起记半透明占据，锥追路径命中半透明体时取 `getColor` 染色（TRANSLUCENT_LIGHT_TINT）；下界传送门/染色玻璃/冰均入体素场（voxelization.glsl:222-231）。
   - 出处：voxelReading.glsl:91-99（锥追内染色）、shadowcomp1.glsl:324-336（光源路径染色）、voxelization.glsl:222-231。
   - 对应 Astra 模块：program/nether_light.csh（现在扩散只跨空格，半透明与实心同为阻断，无染色）；Astra/shaders/global/dimension/nether.glsl。
   - 迁移难点：低。Astra 下界物种编码有空闲位（bit9-11 已用于火/岩浆），加一个"半透明"位 + 扩散衰减染色即可。
7. **体素场的非光照复用**
   - 技术：同一 voxel_sampler/occupancy 场驱动 connected glass 判定、斜切边缘、末地传送门检测、摆动植物互斥、体素反射兜底。
   - 出处：connectedGlass.glsl:64-103、slantedEdges.glsl:21-27、reflections.glsl:174-209（SSR 失败后用 SDF rayTrace + getColor 补反射色）。
   - 对应 Astra 模块：Astra/shaders/lib/solas_water.glsl（水体）、surface_buffers.glsl；体素反射可挂 global/post 的 SSR 失败分支。
   - 迁移难点：低-中（每项独立，按需挑拣；reflections 兜底对下界岩浆面反射尤其划算）。
8. **体积外平滑退路与对数亮度压缩**
   - 技术：体素场覆盖不到处用 `voxelFactor` 平滑混回原版光膜；所有光色写读两端做 `log(l+1)/l` 压缩防过曝。
   - 出处：mainLighting.glsl:86、550-554；prepare4_csh.glsl:422-425、irradianceCache.glsl:20-22。
   - 对应 Astra 模块：global/dimension/nether_colored_light.glsl:9-13 的 `astra_nether_alignment` 边缘对齐（思路同源，但仅处理边界、无亮度压缩）。
   - 迁移难点：低。两处都是几行公式。

**专项问题回应**：
- a) 体素化范围：RV 只收 terrain 四类渲染阶段（voxelization.glsl:252-256），水与非固体明确剔除（242-245 行），但玻璃/冰/传送门/粘液块以**专用 ID + 半透明位**进体素场（222-231 行）用于染色与遮挡；发光方块按 ID 表进（23-238 行）。Astra 现行"发光方块保留实心身份"（shadow.vsh bit8 solid 与物种位并存，nether_light.csh:5-14）与 RV 一致，RV 的增量是**半透明身份**而非取消实心身份。
- b) 彩色光传播：RV **不做洪水填充**——r0.1-beta9 已改为"点光源锥追 + 辐照度缓存"路线；Astra 的 0.72 max 扩散（nether_light.csh:89-96）是 Solas 系洪水填充。两者存储（RGBA16F 场 + 光源表）类似，算法与更新策略不同。
- c) 软硬阴影关系：太阳/月亮走 shadow map，方块光走 SDF 锥追（分工见 2.2）；无"漏光"补丁问题——遮挡由 SDF 解析给出，半影宽度由锥角（光源尺寸）控制（prepare4_csh.glsl:361-372）；体积边界用 voxelFactor 混回原版光膜（mainLighting.glsl:554）防"过暗/断光"。
- d) 非体素部分：大气/云/水/后处理为 Complementary 血统，Astra 已有同级或更强实现（物理天空、SH9、SSR 水、下界独立光照），不再值得搬；仍值得拿的是 2.4 交互水波、下界灰烬风暴（netherStorm.glsl:12-79）与 2.5 之外的彩色光雾塑形（coloredLightFog.glsl:40-48）。

## ④ Astra 已有对应实现

| 能力 | Astra 侧 | 两边对比 |
|---|---|---|
| 下界体素彩光场 | global/dimension/nether_colored_light.glsl（26 行，三线性采样 + 边缘对齐）、program/nether_light.csh（106 行九段 max 扩散）、program/shadow.vsh:47-84 写入 | Astra：同帧 8 步扩散、无历史、无遮挡阴影、格心光源；RV：SDF 锥追软影 + 亚体素光源 + 时域缓存。RV 光影质量明显更高，Astra 胜在成本可预测（固定九段、无 SSBO） |
| 体量雾与光柱 | global/dimension/nether_volume.glsl（Bliss 噪声密度，1-9 行注释明确单散射合成）+ nether_fog_density.glsl | Astra 密度场与彩光场**未耦合**（不确定是否已有 RayMarch 内采样彩光场——本报告仅核对了 nether_volume.glsl 前 40 行，未发现耦合项）；RV 的体积方块光直接读传播场（volumetricBlocklight.glsl:81-83），彩色光柱是自然产物 |
| 群系雾/下界氛围 | global/dimension/nether.glsl（五类群系雾） | Astra 覆盖且更细（RV 仅有 NETHER_COLOR_MODE/VIEW_LIMIT/风暴，见 shaders.properties NETHER_SETTINGS 屏） |
| 水体（法线/SSR/折射/焦散） | lib/solas_water.glsl、global/water/、water_buffer_formats.glsl | 双方同级；RV 多出体素交互涟漪（shadowcomp2），Astra 多出解析焦散/水下光束（背景所述，未逐行核对） |
| 阴影 | 彩色阴影（背景所述，Astra/shaders/global/lighting/ 未逐行核对） | RV 太阳阴影为 Complementary 体系 + 体素光独立；Astra 彩色阴影方案不同源，不可直接互推 |
| 屏幕空间 AO / TAA / Bloom / 色调映射 | global/post/、lib/tonemap.glsl、lib/taa_*.glsl | 双方均有；RV 版本即 Complementary r5.5.1 版，Astra 无需回搬 |
| 发光表面处理 | lib/surface_emission.glsl | RV 用 IPBR 程序化发光（Complementary 体系）；思路可参考但实现路线不同，未深入对比 |

（按契约：未逐行核对处以"背景所述/未核对"注明，不编造 Astra 行为。）

## ⑤ 借鉴可行性（许可证层面）

- RV 的 `License.txt:1` 是 Complementary License Agreement 1.5：**阅读学习不受限**；逐段复制或改编其代码发布，会把 Astra 变成 1.3 定义的 "Modified Pack"，触发署名/保 License/命名/视觉差异/不得叠加许可等全套义务（License.txt:51-69）。其中 1.3 的"不得叠加其它许可"与"名称避让"对 Astra 的发布模式是实质负担。
- 结论：**沿用 Astra 现行策略——读思路、按公式独立重写、文件头致谢**，与既有 photon/solas 报告的处理一致，合规风险低。特例：`lib/vx/positionHashing.glsl:1-8` 的哈希注明源自 David Hoskins（CC-BY-SA 4.0），若连函数一起采用需附署名，建议自写等价哈希规避。
- 另注意：RV 本身即 Complementary 的 Modified Pack，其体素增量是"合规改编"的既有先例，但先例不构成 Astra 免除 1.3 义务的理由。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **体量雾耦合彩光场**（③-5）：把 nether_volume.glsl 的 in-scatter 项换成对 astraLightSamplerA 的三线性采样，改动 ~20 行，下界岩浆/火光柱收益立现。
2. **SDF + 光源 coneTrace 软阴影**（③-1）：单档 SDF 起步（64³ 只需一档），给下界彩光加半影与遮挡，根治"岩浆光穿透墙壁"类错误；工作量 1-2 个新文件 + 1 个 compute 段。
3. **逐像素光源列表 + GGX 高光**（③-2）：1/2 分辨率起步，直接回应"体素灯光梯度粗糙高光"；依赖 ② 的 SDF，建议第二期。
4. **光源亚体素中心**（③-3）：shadow.vsh 顶点级近似即可先做（at_midBlock 均值），让岩浆湖光心不再整格跳动。
5. **半透明染色 + 边缘退路**（③-6/③-8）：occupancy 空闲位记半透明，扩散染色；配合 voxelFactor 式边缘混合，两者都是小改动。
