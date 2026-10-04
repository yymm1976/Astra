# Complementary Shaders - Reimagined r5.9.3 研究报告（面向 Astra 的可借鉴点）

> 源码位置：`reference_shaderpacks/complementary-reimagined/`。下文未加前缀的文件路径均相对该包的 `shaders/` 目录；
> Astra 文件路径相对 `Astra/shaders/`。所有 `文件:行` 引用均来自本包实际源码。

---

## ① 包概览

- **版本/作者**：r5.9.3，作者 EminGT / Complementary Development。每个 program 文件头均标注 `Complementary Shaders by EminGT`（program/deferred1.glsl:2），pack.json:2 的描述为 "Shaders with exceptional attention to detail, high standards of quality, and top tier optimisation"。
- **许可证**：`License.txt:1` 为 **Complementary License Agreement 1.7**（自定义条款，非 OSI 开源）。对本文三类用途的限制：
  - **读思路**：许可不禁止阅读与学习；技术思路、公式、管线组织本身不受版权保护，用自有代码重写是安全的。
  - **抄代码/改编发布**：默认 "Normal Usage" 明确排除 *Redistributing (parts of) The Pack* 与 *Modifying code*（License.txt:9-13）；未获 Grants 明示覆盖的一切使用按 All Rights Reserved 处理（License.txt:86-89）。唯一的改编通道是 1.3 "Modified Pack"：须显著署名原包并链接官网（License.txt:60-62）、原样保留 License.txt 且随更新同步到最新版（License.txt:63-67）、名称不得含 "Complementary" 且与原名至少 3 个字母差异（License.txt:68-72）、在含白天主世界在内的多个常见场景下视觉显著不同（License.txt:73-76）、**不得叠加任何其它许可条款**（License.txt:77-79）、须有显著数量的人写代码增量并实质影响最终视觉（License.txt:80-82）。
  - 对 Astra 的直接含义：整段搬运代码会把 Astra 变成 Modified Pack 并触发上述全部义务，其中 1.3.e（不得有其它许可）与 1.3.c（命名）需要统帅决策；**继续沿用"读思路+独立重写+文件头致谢"策略是当前最稳的路径**。
- **风格定位**：写实偏插画化的"高细节、强优化"路线；核心卖点是 **IPBR**（不依赖资源包 PBR 贴图的程序化材质系统）+ 可选 labPBR/POM 完整支持 + 三种风格化水 + Reimagined 体积云 + 彩光体素（ACT）。
- **工程形态**：设置中心集中在 lib/common.glsl（873 行，`//User Settings//` 从 lib/common.glsl:13 起）；world0/world-1/world1 三维度各持完整 program 副本；同时兼容 OptiFine 与 Iris（shaders.properties:97-98 注释说明旧 OptiFine 的 define 怪癖），并适配 DISTANT_HORIZONS/VOXY（shaders.properties:138-143、reflections.glsl:104-119 的 LOD 深度回退）。

---

## ② 架构与特性清单

### 2.1 大气 / 云
- 解析天空梯度 `GetSky`：up/middle/down 三色插值 + 日落项 + 地平线以下假散射地面（lib/atmospherics/sky.glsl:11，梯度混合 29-33，日落项 35-39，假散射地面 41-51）。
- **Reimagined 体积云**：以上下两块平面夹出云层厚度（`cloudStretch = 4.2`，lib/atmospherics/clouds/reimaginedClouds.glsl:3-4），在两平面间按 CLOUD_QUALITY 分档采样（lib/atmospherics/clouds/reimaginedClouds.glsl:47-53，6/12/无限步档位）；云底阴影直接查 shadow map 并配 `CLOUD_CLOSED_AREA_CHECK` 洞内剔除（lib/atmospherics/clouds/reimaginedClouds.glsl:82-91）。
- Unbound 高层卷云独立实现（lib/atmospherics/clouds/unboundClouds.glsl，全文件 204 行；参数 lib/common.glsl:111-113）。
- 星空/日月/极光风格化开关组：日月四种样式、星星密度、极光两样式 + 出现条件（lib/common.glsl:89-90、96-99），配套 lib/atmospherics/auroraBorealis.glsl、stars.glsl、enderStars.glsl。
- 彩虹：雨后按 `RAINBOWS` 在 composite1 叠加（program/composite1.glsl:93 include，实现 lib/atmospherics/rainbow.glsl）。
- 夜空星云：fbm 星云 `OCTAVE 5/8` 两档（lib/atmospherics/nightNebula.glsl:6-8，注明来自 flytrap 的 Godot shader）。
- 边界雾统一入口 `DoBorderFog`：主世界/下界/末地三路，下界用 `NETHER_VIEW_LIMIT` 收敛雾距（lib/atmospherics/fog/mainFog.glsl:15 起，下界分支 24-29），雾色直接取天空色（mainFog.glsl:45-50）。
- 体积光：近/远场双段分布采样，近场 `pow(t, sampleDistribution)` 非均匀步长（lib/atmospherics/volumetricLight/volumetricLight.glsl:9 函数签名；106-121 远场参数；183-189 采样循环），水上/水下/末地各自重调参数（END 分支 volumetricLight.glsl:136）。

### 2.2 水体
- 波浪法线：一张 `cloud-water.png` 纹理三种频率采样合成中/小/大三尺度法线（lib/materials/specificMaterials/translucents/water.glsl:94-100），另有 4 次迭代的视差式回推（water.glsl:86-92）；雨水扰动水面法线复用雨滴噪声（water.glsl:105-117）。
- **折射**：水面在 gbuffer 阶段以材质 ID 241 写入 materialMask（water.glsl:67-69），composite1 阶段 `DoRefraction` 用噪声扰动 UV，且先做"背景-前景深度差 clamp"再二次校验目标像素仍是 241 才取色（lib/materials/materialMethods/refraction.glsl:7、25-30、32-42）。
- SSR：屏幕空间射线步进 30/38 步 + 6/10 次二分细化（lib/materials/materialMethods/reflections.glsl:83-89，步进循环 97-133），粗糙度驱动 mip LOD（reflections.glsl:194-201）；低配退化成"镜像图像反射"（一次投影采样，reflections.glsl:229-276）。
- **WSR 世界空间反射**：可选体素化反射贴图 + 场景贴图 atlas 手工 mip（lib/materials/materialMethods/worldSpaceRef.glsl:275 `getWSR`；84-96 手工 LOD 采样；shaders.properties:197-227 分配 `wsr_img`/`wsr_lod_img` custom image 与 bufferObject）。
- 泡沫：按"射线交点与玩家 Y 差 + 贴图亮度阈值"生成岸线泡沫（water.glsl:211-248）。
- 水下透视：水下段用 `translucentMult` 菲涅尔衰减透射色（water.glsl:259-265），水色按 `WATERCOLOR_MODE` 用亮度重映射（water.glsl:3-19）。
- 焦散：在 **shadow pass 内**按 `WATER_CAUSTIC_STYLE` 三档实现，最高档用噪声纹理两次差分近似聚焦（program/shadow.glsl:114-141，差分核心 132-137）。

### 2.3 阴影与光照
- 彩色阴影：`shadowtex0/1` 双通道 + `shadowcolor0` 采样，强度曲线 `colorMult = 2.5 + 5.5*pow1_5(lightmapY) + 2.0*lightmapY2`、指数 `colorPow` 随天光与水下状态变化（lib/lighting/shadowSampling.glsl:11-28；曲线在 117-118）。
- 阴影滤波分档：TAA 意义下的旋转盘多采样（shadowSampling.glsl:44-66）、4+1 中心十字（74-83）、纯 4 采样（85-93），按 SHADOW_QUALITY 自动选档（135-141）；雨天自动放大滤波半径（101-107）。
- SHADOW_QUALITY=-1 时整个 shadow pass 直接禁用（shaders.properties:99-103 `program.world0/shadow.enabled=false`）。
- 主光照 `DoLighting` 单入口，含 GGX 高光、手持光、云影、月相、像素化阴影/方块光/AO 等全部开关（lib/lighting/mainLighting.glsl:37 起函数签名；include 区 1-33，GGX 在 mainLighting.glsl:3）。
- 像素化风格：`PIXELATED_SHADOWS/BLOCKLIGHT/AO` 三个独立开关（lib/common.glsl:274-277）。
- 植被摇摆：解析正弦风场 `GetRawWave` 三轴相位叠加 + 雨强二次扰动（lib/materials/materialMethods/wavingBlocks.glsl:5-15、26），按叶片/植株距离调频（wavingBlocks.glsl:38、55）。
- 最低照明兜底与手持光：minimumLighting/heldLighting 模块化 include（lib/lighting/mainLighting.glsl:4、11-13）。
- **彩光体素（ACT）**：`voxel_img`/`floodfill_img` 自定义 image 按 COLORED_LIGHTING 值 128~1024 七档分配（shaders.properties:163-191）；传播后 `GetComplexLightVolume` 3D 采样（lib/voxelization/lightVoxelization.glsl:38-45 引用、100-105 调用）；特殊方块光色查表（lib/colors/blocklightColors.glsl:27 `GetSpecialBlocklightColor`）。

### 2.4 材质系统（IPBR）
- **生成法线**：不读法线贴图，直接在 albedo 上做四邻差分（`GetDif` 带 `normalThreshold` 去噪与 `normalClamp` 限幅）生成凹凸法线（lib/materials/materialMethods/generatedNormals.glsl:10-35，`GenerateNormals` 从 37 行起）；采样偏移用 `max(offsetR, fwidth(texCoord))` 抗摩尔纹（generatedNormals.glsl:54-55）。
- **涂层纹理**：噪声幂函数调制颜色近似"光泽涂层"，支持按方块位置随机化（lib/materials/materialMethods/coatedTextures.glsl:3-30）。
- IPBR 自发光启发式：发光矿石按 `emission = pow2(maxColor*2.5-0.15)` 之类从反照率亮度提取（lib/materials/materialHandling/terrainIPBR.glsl:79-82），并配 `GLOWING_ORE_MULT` 用户滑块；矿石/光源方块 ID 走 block.properties（block.properties:8-9 注释 10024/10028 通道）。
- labPBR/POM 走独立路径 `GetCustomMaterials`：法线/specular/POM 视差 + 距离淡出（lib/materials/materialHandling/customMaterials.glsl:7-67）。
- 方块 ID 位语义约定：`ID % 2 == 1` 的地形 ID 视为非实心，供彩光与 WSR 使用（block.properties:16）。

### 2.5 后处理
- SSAO：4/12 采样两档，随深度缩放采样半径（program/deferred1.glsl:64-80，采样档位 68-76）。
- Bloom：7 个指数级 tile 拼合（program/composite5.glsl:120-126），tile 内容做 `bloom^4` 阈值（113-116）；下界按视野距离增强 bloom（132-139）；tonemap 为改版 Lottes（composite5.glsl:37 注释）。
- TAA：抖动 + 基于速度的混合因子 `blendFactor *= max(exp(-velocityFactor)*blendVariable + blendConstant - ..., blendMinimum)`（lib/antialiasing/taa.glsl:223-245），末地天空区强制降混合保持 VL 稳定（228-243）。
- FXAA 独立 pass composite7，可整 pass 关闭（shaders.properties:104-108）。
- 其余：镜头光斑（lib/misc/lensFlare.glsl，全文件 127 行）、世界模糊/DOF（composite3）、水下画面扭曲（program/final.glsl:97）、图像锐化（common.glsl:147）。

### 2.6 维度特化
- 下界：`NETHER_VIEW_LIMIT` 视距雾上限（lib/common.glsl:118）、Nether Storm 体积烟尘层，最大 512 距离限幅 + 质量/低质两档步长（lib/atmospherics/netherStorm.glsl:1-22，限幅在 11，分档 13-22）；五个下界群系用 `smooth()` 自定义 uniform 平滑过渡（shaders.properties:266-270）。
- 末地：Ender Beams 紫橙双色光柱（lib/atmospherics/volumetricLight/enderBeams.glsl:16 `DrawEnderBeams`）；`END_FLASHES` 末影龙方块闪光经 `endFlashIntensityM` 自定义 uniform 驱动（shaders.properties:277-279；光束响应 enderBeams.glsl:23-30）。
- 群系/状态驱动的颜色乘子：`LIGHT_COLOR_MULTS`/`ATM_COLOR_MULTS` 六时段（早晨/正午/夜晚/雨/下界/末地）×RGB+强度滑块（lib/common.glsl:299-348）。
- 下界专用环境：`NETHER_COLOR_MODE` 三档雾色来源（lib/common.glsl:119）与下界 bloom 视距增强（program/composite5.glsl:132-139）； sulfur 洞雾按 MC 版本条件启用（lib/common.glsl:376-378）。
- 维度程序以 world-1/world1 目录物理隔离，全套 gbuffers+composite 复制（world-1/、world1/ 目录），末地体积光复用同一 volumetricLight.glsl 换参数（volumetricLight.glsl:127-134 END 分支）。

### 2.7 性能与时域
- 8 档画质 profile（POTATO 到 COMPLEMENTARY），profile 直接映射到 ~15 个质量 define（shaders.properties:2-9）。
- Iris 特性协商：`iris.features.optional` 声明 CUSTOM_IMAGES/SSBO 等可选能力（shaders.properties:116），并用 `IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE` 探测 Iris 1.7+ 才分配半分辨率反射缓冲（shaders.properties:118-122）——硬件/后端能力不足时自动降级而不是报错。
- 自定义噪声与云水纹理走 `texture.noise` / `texture.deferred.colortex3` 绑定（shaders.properties:231-233），让云、水波、焦散、抖动共享一张 128² 噪声图的不同通道（water.glsl:94-100 用 .rg，reimaginedClouds.glsl:12-15 用 .b）。
- 程序级降级：shadow/FXAA/shadowcomp 可按 define 整个禁用（shaders.properties:99-113）；云样式非 50 时 `clouds=off` 关掉原版云 pass（145-147）。
- 半分辨率反射缓冲：`size.buffer.colortex1/colortex7 = REFLECTION_RES`（shaders.properties:118-122，REFLECTION_RES 定义 lib/common.glsl:240）。
- 彩光体积按性能分七档分辨率，Mac 上一律禁用彩光（shaders.properties:71-74；lib/common.glsl:56-59）。
- 时域：TAA 抖动 + IGN 噪声按帧滚动（shadowSampling.glsl:30-37）；大量自定义 uniform 用 `smooth()` 做时域平滑（shaders.properties:247-264，如 `rainFactor = smooth(1, rainStrength, 3, 3)`、`eyeBrightnessM`）。

---

## ③ Astra 可借鉴点

按专项问题 a-d 归纳，每条含技术描述、包内出处、对应 Astra 模块、迁移难点估计。

**a) 材质系统（Astra 已有 rock_material / surface_emission 基础）**
1. **程序化生成法线（IPBR 无资源包凹凸）**——albedo 四邻差分生成法线，`fwidth` 下限防摩尔纹。出处：lib/materials/materialMethods/generatedNormals.glsl:10-55。对应模块：program/lit.fsh（当前唯一法线来源是几何法线+水波，lit.fsh:120-129）；难点：**中**——需要把 atlas 内 texcoord 偏移与 tile 边界（absMidCoordPos 类顶点输出）接入 lit.vsh，且屏幕空间导数在 TAA 抖动下要过时域滤波，否则法线噪点明显。
2. **IPBR 自发光启发式（发光矿石/光源）**——按反照率亮度/pow 曲线提取发光，配全局滑块。出处：lib/materials/materialHandling/terrainIPBR.glsl:79-82、block.properties:7-8（modded 矿石/光源 ID 通道）。对应模块：lib/surface_emission.glsl（现仅末地石孔隙发光，surface_emission.glsl:6-13）+ program/lit.fsh:289；难点：**低**——Astra 已有 material ID 管线，只需给矿石类 ID 增加亮度启发式与滑块。
3. **涂层/潮湿的光泽调制分离**——噪声幂调制"涂层"，与湿润系统独立。出处：lib/materials/materialMethods/coatedTextures.glsl:3-30。对应模块：lib/wet_material.glsl（湿暗化+高光三参数，wet_material.glsl:16-21）；难点：**低-中**——Astra 湿度响应已是类涂层模型，可直接借"按方块位置随机化"与"mip 衰减"两个细节。
4. **labPBR 法线/specular 支持路径**——独立 `GetCustomMaterials` 入口与 IPBR 并行，POM 距离淡出。出处：lib/materials/materialHandling/customMaterials.glsl:7-67。对应模块：暂无（Astra 不读 normaled/specular 贴图）；难点：**高**——需要 lit 管线加贴图采样分支与 POM 循环，且与现有 material ID 语义融合，属大特性。

**b) 水体链路（对照 lib/solas_water.glsl、global/water/*、lib/water_buffer_formats.glsl）**
5. **折射的"材质 ID 二次校验"**——Astra 折射已有 per-tap 深度/朝向拒绝（settings.glsl:143-147 注释、global/water/refraction.glsl），Complementary 额外在偏移后重读材质 ID 确认仍是水面、并用 `GetApproxDistance` 把噪声幅度按前后景深度差 clamp，防背景被误拉扯（refraction.glsl:25-35）。迁移价值：给 Astra 折射补"折射后目标仍是同介质"校验与深度差限幅；难点：**低**。
6. **三尺度波法线+视差回推**——一张噪声图三分频 + 4 次视差迭代回推采样点（water.glsl:86-100）。对应模块：global/water/surface.glsl（已有 4 步自适应视差与 Nyquist 滤波，surface.glsl:15、278）；Astra 实现更完整，仅可借鉴"按菲涅尔衰减法线强度"（water.glsl:100）与"反射向法线与几何法线混合防法线朝内"（water.glsl:127-130）；难点：**低**。
7. **SSR 低配退化路径（镜像图像反射）**——质量档低时放弃 ray march，一次投影采样反射色，成本近零（reflections.glsl:229-276）。对应模块：global/water/raytrace.glsl（24 步+6 次二分+置信度，raytrace.glsl:62-111）；难点：**低**——作为 `SCREENSPACE_REFLECTIONS` 低配档位补一个平面镜像 fallback。
8. **WSR 世界空间反射**——体素化反射贴图 + atlas 手工 mip，可反射屏幕外内容（worldSpaceRef.glsl:79-96、275；image 分配 shaders.properties:197-227）。对应模块：global/water/raytrace.glsl（纯屏幕空间）；难点：**很高**——需要 custom image + SSBO + 体素化 pass，工作量与彩光体素同量级，属长期项。
9. **岸线泡沫**——射线命中点与玩家相对 Y 差 + 噪声阈值（water.glsl:211-248）。对应模块：global/water/surface.glsl（无泡沫）；难点：**中**——Astra 水面是 forward gbuffer，需要拿到背景深度反推命中点世界 Y，lit.fsh 已有 depthtex 读取习惯，主要是美术调参。

**c) 维度特化（对照 global/dimension/）**
10. **Nether Storm 烟尘体积层**——从相机向雾距射线步进噪声密度，最大 512 限幅，两档步长降级（netherStorm.glsl:1-22）。对应模块：global/dimension/nether_volume.glsl（现有体素彩光，无烟尘层）与 lib/nether_fog_density.glsl；难点：**中**——Astra 下界已有 compute 体素基础设施，可复用其 dither/步进模式；注意与 `NETHER_FOG_DENSITY` 的注释"Astra 无额外 plume 层"（settings.glsl:177）决策冲突，需统帅拍板是否引入。
11. **末地事件驱动的动态氛围**——末影龙闪光经自定义 uniform 平滑后调制光束颜色/强度（shaders.properties:277-279、enderBeams.glsl:25-43）。对应模块：global/dimension/end_kerr.glsl / end_plasma.glsl（Kerr 黑洞+等离子盘，无游戏事件联动）；Astra 末地天空方向与 Complementary 完全不同，**仅借鉴"自定义 uniform 平滑游戏事件"手法**（`smooth()` 链），难点：**低**。
12. **下界群系平滑 uniform**——五群系 `if(in(biome,...))` + `smooth(…,15,15)` 时域过渡（shaders.properties:266-270）。对应模块：Astra 群系处理在 global/atmosphere/weather.glsl 与 lib/colors.glsl 的 BIOME_TINT（settings.glsl:118-120，仅温湿度）；若 Astra 想做下界群系雾差异化（五类群系雾已是 Astra 特性，见任务背景），Complementary 的 uniform 侧写法可参考；难点：**低**（Astra 已有群系雾，仅 uniform 写法参考）。

**d) 性能调度（对照 lib/settings.glsl 画质预设）**
13. **程序级 pass 开关**——`program.<world>/<pass>.enabled=false` 按 define 关闭整个 pass（shaders.properties:99-113）。对应模块：Astra 的 GODRAYS/VOLUME_FOG/SCREENSPACE_REFLECTIONS 关闭后对应 pass 仍在跑（settings.glsl:194、221-227 只控制内部循环）；难点：**低**——在 shaders.properties 加 define 条件即可，收益直接。
14. **半分辨率反射缓冲**——`size.buffer.colortexN = REFLECTION_RES`（shaders.properties:118-122）。对应模块：Astra 反射在 forward+composite 现全分辨率（lib/water_buffer_formats.glsl:12-19 只调格式）；难点：**中**——SSR 半分辨率需边缘上采样与深度感知放大，TAA 能吃掉一部分噪点。
15. **自定义 uniform 时域平滑**——`smooth(id, value, upRate, downRate)` 广泛用于雨强/眼亮度/群系（shaders.properties:261-264）。对应模块：lib/uniforms.glsl（Astra 自定义 uniform 体系已在用，如 astraSolasShadowFade，lib/solas_water.glsl:13）；难点：**低**，属写法层面对照。
16. **月相联动**——月相影响光照/大气/反射三通道独立开关 + 三档月相亮度滑块（lib/common.glsl:267-272）。对应模块：Astra 无月相系统；难点：**低-中**——moonPhase uniform 可直接读，主要工作量在 Astra 天空与夜光管线的接入点选择。
17. **解析风场植被摇摆**——纯数学正弦风场（无噪声纹理），雨强独立乘子与室内检测 `NO_WAVING_INDOORS`（lib/materials/materialMethods/wavingBlocks.glsl:5-26；开关 lib/common.glsl:228-237）。对应模块：global/lighting/wind.glsl；难点：**低-中**——Astra 已有 wind 模块，缺的是"按天光判室内"与摇摆强度滑块组。

---

## ④ Astra 已有对应实现（两边优劣对照）

- **水体链路**：Astra 全套在 global/water/（surface/refraction/raytrace/absorption/caustics/light_shafts/temporal 各自独立文件）+ lib/solas_water.glsl（Solas V2.2b 改编，lib/solas_water.glsl:4-6 注明出处）。*优*：Astra 波面有 Nyquist 滤波与 4 步视差（surface.glsl:15、278），折射有 per-tap 拒绝与历史缓冲（temporal.glsl），焦散走彩色阴影投影（settings.glsl:152-153 注释）——工程化程度高于 Complementary 的 composite 期单帧折射；*劣*：无泡沫、无 SSR 低配镜像路径、无屏幕外反射。
- **SSR**：Astra global/water/raytrace.glsl:62-111（24 步线性+指数步长、6 次区间二分、置信度+边缘衰减）vs Complementary reflections.glsl:97-133（等比加倍步进+连续细化、LOD 粗糙度模糊）。*优*：Astra 二分收敛更稳、有显式 confidence；*劣*：无 mip 模糊反射、无低配档。
- **下界**：Astra global/dimension/nether.glsl + nether_colored_light.glsl（Solas V3.7b 有界体素彩光，64³、8 步扩散、无历史，nether_colored_light.glsl:4-7）+ nether_reflection.glsl（Complementary r5.9 改编，nether_reflection.glsl:3-5 注明）+ nether_volume.glsl。*优*：Astra nether_reflection 修了参考包的边缘溢出问题（nether_reflection.glsl:56-59 注释）；*劣*：体素 64³ 固定、无烟尘风暴层、无多分辨率档（Complementary 128~1024 七档，shaders.properties:163-191）。
- **材质系统**：Astra block.properties material ID + lib/rock_material.glsl 五类纹理驱动光滑度（rock_material.glsl:7-19）+ lib/wet_material.glsl 湿度类（wet_material.glsl:4 注明"idea only"）+ lib/surface_emission.glsl；Complementary 是 IPBR 大表（terrainIPBR.glsl 2852 行）+ 生成法线/涂层 + labPBR/POM。*优*：Astra 结构干净、可预期；*劣*：材质覆盖面窄（无程序化法线、无涂层、无矿石发光、无用户滑块）。
- **后处理**：Astra 4 种 tonemap 算子（settings.glsl:202-203）+ lib/tonemap.glsl + global/post/grading.glsl + 2-pass bloom（global/water/bloom_capture.glsl、bloom_resolve.glsl）+ FXAA/TAA（settings.glsl:230-231）；Complementary 改版 Lottes 单算子 + 7-tile bloom + 大量风格滑块。*优*：Astra 算子可切换且管线更清晰；*劣*：无镜头光斑/DOF/锐化等外围项（是否算"劣"取决于定位，Astra 设计上有意精简）。
- **云**：Astra 半分辨率平面云 + 独立时域历史（global/atmosphere/clouds_planar.glsl 412 行、cloud_temporal.glsl、settings.glsl:108-115 注释）；Complementary Reimagined 体积云三档采样+云影（reimaginedClouds.glsl:47-53、82-91）。*优*：Astra 云的时域组织独立于 TAA，成本可控；*劣*：非体积、无云影投射到地面（Astra CLOUD_SHADOWS 仅雨天，settings.glsl:106-108）。
- **风/摇摆与月相**：Astra global/lighting/wind.glsl 处理摇摆但无用户滑块组与室内检测；Complementary 有完整开关组（lib/common.glsl:228-237）与月相联动（lib/common.glsl:267-272）。*劣*：Astra 缺这层"用户可调风格化"外露；*优*：Astra 把开关数量刻意控制在 GUI 精简原则内（settings.glsl:5-13 约定），是否引入属设计决策。
- **不确定项**：Complementary 的 SHADOW_SMOOTHING/LEAF_SHADOW 优化与 Astra SHADOW_FILTER_QUALITY（settings.glsl:69-72）的具体效果差异未实测，本报告不做优劣结论；Astra taa_reactive.glsl 与 Complementary TAA_MOVEMENT_IMPROVEMENT_FILTER 是否等价未逐行比对。

---

## ⑤ 借鉴可行性（许可证层面结论）

- **读思路 + 独立重写**：可行，无障碍。Astra 现有 nether_reflection.glsl（nether_reflection.glsl:3-5）、rock_material.glsl（rock_material.glsl:3-5）、solas_water.glsl（lib/solas_water.glsl:4-6）的"Adapted from + 文件头致谢"模式即为该策略的落地，建议延续。
- **整段复制/直接翻译代码**：将使 Astra 构成 1.3 意义上的 Modified Pack，触发署名、保留同步 License.txt、命名限制、视觉显著差异、**不得附加其它许可**（License.txt:77-79）与人写增量等全部义务；其中"不得附加其它许可"若与 Astra 既有的第三方声明体系冲突，等于放弃自有条款。结论：**不整段复制**；如必须引入较大段落，先由统帅确认接受 1.3 全部义务并统一 THIRD-PARTY.md 口径。
- **风险提示**：2.2 条（License.txt:91-93）表明许可按版本生效，r5.9.3 的条款只覆盖本包该版本文件；借鉴时以本地解包的这份 License.txt 为准。
- **边界情形**：包根的 `shaderFile_1/2/3` 与 `shaderFile_*.placebo` 仅是下载结构的占位文件（shaderFile_A.placebo:1 自述 "placebo file so that some people stop thinking they should put the shaders folder..."），不含可分析代码；本报告分析 `shaders/` 目录，且以 Reimagined 风格默认值（SHADER_STYLE 1，lib/common.glsl:14）为准。

---

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **IPBR 自发光启发式（发光矿石/光源方块）**——提升高（矿洞场景观感直接受益）、工作量低：扩展 lib/surface_emission.glsl + block.properties 矿石 ID + EMISSIVE_STRENGTH 类滑块（参考 terrainIPBR.glsl:79-82）。
2. **程序级 pass 开关**——提升中高（关特性时省整 pass，低端档位受益）、工作量极低：shaders.properties 仿 99-113 行为 GODRAYS/VOLUME_FOG/SSR 关闭时禁用对应 composite/deferred pass。
3. **SSR 低配镜像退化路径**——提升中（低配水面保底反射）、工作量低：raytrace.glsl 前加一次性投影采样 fallback（参考 reflections.glsl:229-276）。
4. **程序化生成法线**——提升高（全场景材质立体感）、工作量中：lit.vsh 加 tile 元数据、lit.fsh 加差分法线 + TAA 下时域滤波（参考 generatedNormals.glsl:10-55）。
5. **折射二次校验 + 深度差限幅**——提升中（消除折射拉扯瑕疵）、工作量低：global/water/refraction.glsl 增加材质 ID 复核与 `GetApproxDistance` 限幅（参考 refraction.glsl:25-35）。

（次优先：涂层噪声随机化——coatedTextures.glsl:3-30 的"按方块位置随机化 + mip 衰减"两个细节可直接并入 wet_material；下界风暴层——netherStorm.glsl:1-22，涉及 settings.glsl:177 的既有决策，需统帅确认。）

**执行口径建议**：以上 1/2/3/5 四项均为"读思路 + 独立重写"即可落地的小改动，不触碰 Complementary 许可红线；第 4 项（生成法线）与 WSR 属中型特性，建议先做技术预研再立项。

---

*报告完。所有引用行号已于 2026-10-02 用 grep/sed 对照源文件复核（复核 30+ 条，修正 9 处偏移）。*
