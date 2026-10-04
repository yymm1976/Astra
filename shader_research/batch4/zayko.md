# zayko × Astra 性能调研（batch4）

- 调研日期：2026-10-03。数据时点：包内容为本地解压快照（`reference_shaderpacks/zayko/`）；版本/下载量以任务书给定（Modrinth v9.0，81,003 下载）为准，包内 `P:iris.properties:1` 有 "# Zayko Shaders 9.0" 佐证。
- 引用约定：`P:` = `reference_shaderpacks/zayko/shaders/`（本包 shader 根即 `shaders/`，行号相对该目录）；`A:` = `Astra/shaders/`。
- 去重材料：`shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md` 全部读过；每条候选均附 `Astra/shaders` 多关键词 grep 结果。

---

## 一、概况

| 项 | 事实 | 证据 |
|---|---|---|
| 定位 | 质量优先 + 高可调性：内建 PBR/自发光材质、体积云三步层、天光缓存、TAA/CAS、主世界彩光（MCBL/体素两套）、六档 profile；卖点是「每一帧只有一个天空」的统一资产化（prepare 天空图） | `P:shaders.properties:4-12`、`P:lib/atmospherics/skyMap.glsl:1-22` |
| 血统 | 无 README/无整包血统声明；作者 SkyNexusHD（FiveNova.net）。组件级来源已注明：光柱「Light shafts from Robobo1221 (modified)」、FXAA（Timothy Lottes 论文）、生成法线取自 Emin#7309 的 Complementary、水吸收常数对照 Photon 实测 | `P:lib/atmospherics/volumetricLight.glsl:49`、`P:lib/antialiasing/fxaa.glsl:4`、`P:lib/pbr/generatedNormals.glsl:4`、`P:lib/atmospherics/waterVolume.glsl:89-97` |
| 许可 | 包内**无任何 LICENSE/README/版权文件**（`find -iname "*licen*"`、非代码文件仅 properties/lang/mcmeta/json）→ 默认保留所有权利；只能读思路独立重写并登记 | `find -type f` 全清单；文件头均为 "Zayko Shaders by SkyNexusHD" |
| 规模 | 整包 **367 文件**；shader 代码 **22,818 行**（`.glsl 156 + .fsh 96 + .vsh 96`，与任务书一致）；另有 4 properties、lang×2、tex/ 4 PNG（星图/天空图/噪声/脏镜头） | `find -type f \| wc -l`；`find ... -print0 \| xargs -0 wc -l` |
| 结构 | 扁平实现：`program/*.glsl` 为唯一实现，`world0/`、`world-1/`、`world1/` 为 7 行薄壳（`#define 维度` + include）；`lib/` 11 子目录（antialiasing/atmospherics/color/design/lighting/pbr/post/reflections/surface/util/vertex）；`program/prepare*.glsl` 为几何前的天空图与地图模糊 | `P:world0/composite.fsh:1-9`、`P:program/prepare.glsl:1-25` |
| 工程特征 | GLSL **330 compatibility**；`RENDERTARGETS` 承载 >9 号缓冲；无 `size.buffer`、无 `scale.`（grep 0）——低分效果靠「象限打包 + 顶点缩放」而非缓冲声明；`iris.properties` 故意不声明 required/optional features（:7-22） | `grep "size\." P:shaders.properties` 0 命中；`P:iris.properties:7-22` |

---

## 二、管线与调度

- **program 清单**（`P:program/` + `P:shaders.properties:102-126`）：`prepare`（256² 天空图）→ `prepare1`（128² 软天空图）→ `gbuffers_`{terrain, water, water 的 late 变体, entities, entities_glowing, entities_translucent, block, block_translucent, textured, basic, beaconbeam, spidereyes, armor_glint, damagedblock, skytextured, weather} → `shadow` → `deferred`（仅 AO/GI）→ `deferred1`（主前向光照 + 天空/雾/云/水面反射的延迟部分）→ `composite`（体积光 + MCBL）→ `composite1`（VL 重建 + TAA）→ `composite2`（运动模糊）→ `composite3`（DoF）→ `composite4`（Bloom 图集）→ `composite5`（曝光/tonemap/lens flare）→ `composite6`（FXAA）→ `composite8/9`（体素彩光传播 A/B）→ `final`（CAS/描边/整活）；另有 `dh_terrain/dh_water`、`voxy_*`。
- **阶段启停**（`P:shaders.properties:102-126`）：`shadow.enabled=SHADOW`；`deferred.enabled=AO`（主光照在前向 gbuffer，延迟只为 AO）；`composite1=LIGHT_SHAFT || TAA`（一 pass 两职）；`composite2=MOTION_BLUR`、`composite3=DOF`、`composite6=FXAA && !RETRO_FILTER`、`composite8/9=VOXEL_COLORED_LIGHT`。Nether 无 shadow 程序（:104 注释）。
- **profile 链**：LOW ← LITE ← BALANCE ← HIGH ← EXHIGH ← DIVINE 逐层继承，只列增量（`P:shaders.properties:7-12`）——材料 batch3 已列「profile 增量式/链式定义」，去重。
- **管线级开关**：`dynamicHandLight/oldHandLight/oldLighting/particles.ordering/separateAo/shadow.culling/underwaterOverlay/vignette`（:14-21）；`alphaTest.gbuffers_terrain=GREATER 0.1`、clouds/hand 0.005、water 0.001、weather 0.0001（:129-135）；`shadowEntities=false`/`shadowBlockEntities=false` 由 `#ifndef SHADOW_ENTITY/SHADOW_BLOCK_ENTITY` 注入（:204-210）；late 半透明实体 `blend.*=off`（:215-220）；DH 关影并改水 blend（:223-226）。
- **纹理槽**：`texture.noise`、deferred 阶段 colortex11=星图、colortex12=天空图（星座距离场）、composite 阶段 `depthtex2=tex/dirt.png`（脏镜头）（:141-148）。
- **CPU 侧帧不变量**：`timeAngle/shadowFade/timeBrightness`、`blindFactor`、7 组群系标量、`skyMood` 每日哈希、`framemod8/2`（:151-197）——12 包共识类，去重。
- **缓冲角色**（从源码消费点归纳）：colortex0 主色；1 = 体积光象限 + 全屏色（`P:program/composite.glsl:406-408`）；3 = 法线 + flag 位（移动/延迟实体）；4 = bloom 源；5 = 场景数据（暴露在 `:41`）；6 = flag；8 = MCBL 当帧光色 / 体素传播 A；9 = MCBL 累积 / 体素传播 B；11/12 = 星图/天空图（deferred 阶段）；13 = 清晰天空图（256²，`P:program/prepare.glsl:118`）；14 = 软天空图（128²，`P:program/prepare1.glsl:64`）；15 = TAA 历史（`P:program/composite1.glsl:194`）。

---

## 三、分模块性能手法清单

### 3.1 调度与阶段启停

| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:shaders.properties:102-126` | 每效果一条表达式门控；`deferred` 只在 AO 开时运行（前向光照不吃延迟 pass）；`composite1` 由 `LIGHT_SHAFT || TAA` 合并调度 |
| 2 | `P:shaders.properties:7-12` | 六档 profile 继承链，切换只需覆盖差异项（材料已列，仅记录结构） |
| 3 | `P:program/gbuffers_basic.glsl:152-170`、`P:program/gbuffers_block.glsl:411-438`、`P:program/gbuffers_textured.glsl:191-202` | 按启用特性编译期切换 `RENDERTARGETS` 写出集合（关 TAA/MCBL/延迟实体时少写缓冲）——Astra 已有同类变体（`A:program/lit.fsh:33-72`），去重 |
| 4 | `P:program/composite1.glsl:194` | TAA 历史与光柱结果同写 `RENDERTARGETS: 0,15`，不额外开 pass |

### 3.2 地形光照与阴影

| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:lib/lighting/shadows.glsl:41-53` | 手工 `texture2DShadow2x2`（sampler2D + 显式比较 + 双线性重建）；作者注明包内 `shadowHardwareFiltering` 已关（:55-57） |
| 2 | `P:lib/lighting/shadows.glsl:78-84` | IGN 抖动仅在 TAA 开启时随帧推进；无 TAA 时冻结，避免「没有时域平均的爬行噪声」（:69-77 注释） |
| 3 | `P:lib/lighting/shadows.glsl:184-198,216-278` | PCSS：blocker 搜索用原始 `texture2D`（不过滤），**无遮挡直接返回全亮**以抵消搜索成本（:223-229）；半影在 UV 空间按深度差计算、min/max 用 texel 夹住（世界单位软度，不随影图分辨率漂移）；每 tap 先判 `tap0<1.0` 才做彩色透射计算（:259-270） |
| 4 | `P:lib/lighting/shadows.glsl:114-116,157-174` | 彩色阴影按「半透明透射份额」加权：`max(shadowtex1 - shadow0, 0)`，与旧实现相比修掉不透明遮蔽半影过亮问题 |
| 5 | `P:lib/lighting/shadows.glsl:132-153` | 水柱厚度直接从阴影图求得：水面在两深度图中差 + `shadowcolor0.a≈1` 水标记，乘光照仰角得光路水厚（供吸收/焦散/雾） |
| 6 | `P:lib/lighting/shadows.glsl:285-372` | 边界 + `skylight>0.001` 门控提前返回全亮（:314-321）；bias 各路径统一按 `shadowMapResolution` 归一 |
| 7 | `P:program/shadow.glsl:259-284` | 体素彩光体素化在 shadow pass 顶点完成：发光方块重定位到 shadowcolor1 图集格、`z=-0.9999` 抢深度；出界 `gl_Position=(-2,-2)` 剔除（配合 VOXEL_COLORED_LIGHT） |
| 8 | `P:lib/lighting/shadows.glsl:421-430` | 无阴影档兜底：`smoothstep(0.866,1,skylight)²` 天光近似（材料已有同类：MakeUp visibleSky 幂衰减，去重） |

### 3.3 云

| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:lib/atmospherics/clouds.glsl:213-228` | 反射与 DH 水面查询把云步数减半（`fadeFaster ? CLOUD_SAMPLES_DEFAULT/2 : ...`），按用途分预算；blocky 档再减 |
| 2 | `P:lib/atmospherics/clouds.glsl:230-261,269-285` | 先按距离求 `fadeEnd` 并把远端裁掉；步长由样本数反推（固定序列），起点 dither |
| 3 | `P:lib/atmospherics/clouds.glsl:315-318,370-376` | march 内 `cloud>0.95` break、超过软上限长度 break（注释记录了 break 阈值与不透明度的标定关系） |
| 4 | `P:lib/atmospherics/cloudShadow.glsl` + `P:lib/atmospherics/volumetricLight.glsl:8-10` | 云影与体积光共用同一 `cloudShadow` 采样入口（单来源、多消费者）——材料 batch2 已列，去重 |
| 5 | `P:program/deferred1.glsl:619-685` | 整屏一次云查询（含 dither/透视远景混合），不按材质重复 march；`isEyeInWater>1` 直接 alpha=0 |

### 3.4 雾与大气

| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:lib/atmospherics/fog.glsl:151-158,216` | 高度雾解析积分；Voxy/DH 视野按 `VOXY_RENDER_DISTANCE*16` 缩放并乘 `FOG_DENSITY_DH`，远处雾长度先钳 |
| 2 | `P:lib/atmospherics/weatherDensity.glsl:1-4`、`P:lib/atmospherics/weatherVariety.glsl` | 群系/维度雾密度查表 + 天气多样性，纯参数层无逐像素步进 |
| 3 | `P:program/deferred1.glsl:45-99` | `SKY_DEFERRED` 下天空/雾在 deferred1 顶点阶段预调色，片元只做插值与混合（帧量上提，材料已列） |
| 4 | `P:lib/atmospherics/nightSky.glsl:133-221` | 星空为烘焙图集 3×3 texelFetch + 逐星 `continue` 早退；星等/夜视极限逐晚计算（性能向见无法判定 1） |

### 3.5 水与水下

| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:lib/surface/waterHeight.glsl:87-138` | 细节波场三倍频按屏幕足迹逐级淡出（`fade=1-smoothstep(NEAR,FAR,footprint/lambda)`），`fade<0.01` 整倍频 `continue`；丢失的斜率方差累加成 roughness，供太阳高光散开 |
| 2 | `P:lib/vertex/waterWaves.glsl`（长波）+ `P:program/gbuffers_water.glsl:1200` | 长波在顶点位移、斜率为解析式（零采样、不可走样）；片元只取细节场 |
| 3 | `P:lib/reflections/raytrace.glsl:43-98` | SSR 旧版：`RT_MAX_ITERATIONS`、出屏/背相机/深度越界 break、连续命中天空两次即停（`skyHits>=2`） |
| 4 | `P:lib/reflections/raytrace.glsl:140-214` | SSR 新版（实际使用 `TraceReflection`）：步长随视距缓慢增长、每步只在「跨过深度面」时 5 步二分，命中即停；`REFLECTION_PRECISION` 切误差倍率 |
| 5 | `P:lib/reflections/simpleReflections.glsl:8-58` | 反射分档：`RAYTRACING` 关时退回 `BasicReflect`（单次解析/天空），`REFLECTION 0/1/2` 控制开关与档位 |
| 6 | `P:program/gbuffers_water.glsl:771-841` | SSR 命中与天空反射按 Fresnel 混合，`REFLECTION_SKY_FALLOFF` 用天空遮蔽压低远处反射（材料已列：反射×天光门控） |
| 7 | `P:lib/atmospherics/waterFog.glsl:13-61` + `P:lib/atmospherics/waterVolume.glsl:24-100` | 水下吸收/散射与体积光解耦；厚度从阴影图水柱取得（见 3.2-5），吸收系数为常数表 |
| 8 | `P:lib/surface/waterHeight.glsl:145-168` | 焦散用的原始高度场不带足迹过滤，只在 shadow pass 逐 texel 求（`P:program/shadow.glsl:101-133`），不逐水面像素重算 |

### 3.6 粒子·实体·天气

| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:lib/util/lateEntity.glsl` + `P:shaders.properties:215-220` | 延迟半透明实体在 deferred1 之后绘制并写 colortex6 flag，供 TAA/光柱判断停止距离；对应缓冲 blend 全关 |
| 2 | `P:program/gbuffers_weather.glsl` + `P:shaders.properties:135` | 天气程序 `alphaTest=GREATER 0.0001`，薄雨条不整段丢弃/不整段写 |
| 3 | `P:lib/reflections/rainPuddles.glsl:11-48` | 水洼掩码由噪声+湿度+天光/朝向门控，默认强度 0.4×湿度兜底（材料已列：水洼掩码，去重） |
| 4 | `P:lib/lighting/voxelPropagate.glsl:30-46` | 体素彩光传播：每体素取当前帧发射源 + 6 邻域上帧结果的 max×0.84，无自项使撤光源自然衰减（跨帧乒乓，见反面 1） |

### 3.7 后处理与缓冲内存

| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:program/prepare.glsl:83-118`、`P:program/prepare1.glsl:36-64` | **天空图资产化**：prepare 每帧只画 256² 上半天球（八面体折叠）到 colortex13 一角，不透明几何前完成；prepare1 再把它按 ~5° 模糊成 128² 软图（colortex14）。天空/云/极光只算一次，水/玻璃/粗糙反射/水下 Snell 全部查图（`P:lib/atmospherics/skyMap.glsl:26-84`） |
| 2 | `P:program/composite.glsl:372-391` | 半分辨率体积光：只在下左象限 march（`VL_RESOLUTION 2`），结果与「射线到达深度」一起写 colortex1 同一缓冲的不同区域 |
| 3 | `P:program/composite1.glsl:93-175` | VL 重建：取 4×4 个 march texel，Bayer4 的 16 个相位在整块内必各出现一次 → 等权平均精确抵消起点抖动；`keep=step(tapReach, pixelReach+VL_STEP_SIZE)` 只保留与自身射线到达深度相近的样本，全部超出时取最近样本按 reach 比例缩放兜底 |
| 4 | `P:program/composite.glsl:105-168` | MCBL 屏幕空间彩光：4-tap 距离/FOV 缩放模糊 + 逐样本深度反渗漏权重 + 屏幕边缘 mask，与当帧发射色 10% 混合后写下帧用的累积缓冲 |
| 5 | `P:lib/lighting/coloredBlocklight.glsl:23-43` | 消费端重投影取上帧彩光（`texture2DLod(colortex9,...,2)`），亮度归一后按亮度比混入方块光 |
| 6 | `P:lib/antialiasing/taa.glsl:24-32,78-84,155-184` | TAA 在色调映射前对 HDR 解算；Catmull-Rom 5 tap 历史；YCoCg 邻域裁剪；实体/手持 flag（colortex3.b）与相机速度各减历史权重；屏外历史清零 |
| 7 | `P:program/composite4.glsl:23-141` | Bloom：单 pass 把 7 级 mip 按角部图集打包进 colortex1，每像素只处理自己所属图块（`abs(coord-0.5)<padding` 门控），13-tap Jimenez + Karis 亮度加权抑制 firefly，高光软膝后 gamma 编码 |
| 8 | `P:program/composite5.glsl:176-210` | 自动曝光：单次 `texture2DLod(colortex0, vec2(0.5), exposureLod)` 从场景 mip 取亮度，帧率无关的指数平滑（材料已列：AstraLex 场景 mip 单次曝光，去重） |
| 9 | `P:program/final.glsl:143-175,282-284` | CAS 亮度自适应锐化（非 TAA 也可用）；`P:program/final.glsl:95-135` 是 TAA 后可选锐化（材料已列 CAS，去重） |
| 10 | `P:lib/util/temporalDither.glsl:1-16` | 抖动仅在 TAA 开启时随帧推进，否则冻结（与阴影 IGN 同策略，防无时域时闪烁） |

---

## 四、反面印证（不建议学）

1. **体素彩光的 2D 图集 + 跨帧乒乓不适合替换 Astra 现方案**：传播写成两个全屏 pass（`P:program/composite8.glsl:42`、`composite9.glsl:39`，各只对图集区 texel 有效），读上帧结果并带相机位移（`P:lib/lighting/voxelPropagate.glsl:30-46`）→ 天然 1 帧延迟；Astra 下界的立场是每帧清空 + 完整传播（`A:program/nether_light.csh:1-6,46-68`），2026-10-03 文档已明确暂缓分帧更新，此路不采。
2. **图集容量靠运行期判断兜底，历史上有越界读**：`VoxelSlicesThatFit`（`P:lib/lighting/voxelMap.glsl:36-54`）注释列出旧行为在 1920×1080/体积 128、512 影图/体积 128 等组合下越界 72~3584 行；即「2D 图集代替 3D 纹理」会让容量取决于屏幕分辨率与影图尺寸，Astra 的 `image3D` 无此耦合。
3. **体素发射源重定位进阴影图边缘条带是脆弱约定**：发光方块被投到 shadowcolor1 图集格、以 `z=-0.9999` 抢深度，注释自认「重叠在畸变阴影图边缘，属接受的取舍」（`P:lib/lighting/voxelMap.glsl:12-15`、`P:program/shadow.glsl:259-284`）；且 shadow map 分辨率/畸变一变就需重验。
4. **半分辨率光柱的 4×4 重建取数更多**：每像素 16 次点采（`P:program/composite1.glsl:159-171`）对 Astra 现有 2×2 双线性 + 深度带筛选（`A:global/atmosphere/volume_fog.glsl:208-254`）是更贵的一档；其相位抵消收益需与 12 次额外取数 A/B，不应直接照搬。
5. **colortex8/9 双登记**：MCBL（`P:program/composite.glsl:105-168`、`P:lib/lighting/coloredBlocklight.glsl`）与体素传播（`P:program/composite8.glsl/composite9.glsl`）共用 8/9 两个槽位，settings 无互斥（两者默认都关）——同开即互相覆盖。
6. **星空图集依赖包外工具**：`P:lib/atmospherics/nightSky.glsl:7-11` 说明星图由 `tools/gen-sky-atlas.ps1` 烘焙，但该工具未随包发布；无法复现其资产管线。
7. **`SKYBOX_*`/`AXON`/`RETRO_FILTER` 等整活与摄影件占大量分支**：`P:shaders.properties:98` 的单行塞入 30+ 效果，决策面本身不产生性能结构（与 Astra 无关，仅提示「不要按菜单规模评估性能」）。

---

## 五、新颖借鉴点

> 以下每条已先对 `Astra/shaders` 多关键词 grep，并与五份材料逐条对照；材料已列的同方向（粗糙度天空缓存 mip/环境 BRDF、云时域超分、云按用途分预算、单像素曝光、CAS、水洼、PCSS/像素锁定、反射×天光门控、mip Bloom、静态资产等）一律不重复主张。

### A 组（低代价，可直接排期）

无（本包可迁移的低代价手法均已在材料或 Astra 现实现中覆盖，见去重排除）。

### B 组（中代价，需接线）

| # | 机制 | 来源 file:line | Astra 未实现证据（grep 关键词与结果） | 迁移代价 |
|---|---|---|---|---|
| B1 | **天空环境图改「八面体上半球折叠」打包**：`dir.y<0` 折到地平线，水平面按 `x/(\|x\|+y+\|z\|)` 投到正方形，等立体角、无极点过采样、无经线接缝；读写共用同一 encode/decode；软图（另一次 5° 模糊）只服务粗糙反射 | 写入 `P:program/prepare.glsl:83-118`；编码/解码 `P:lib/atmospherics/skyMap.glsl:26-56`；软图 `P:program/prepare1.glsl:36-64` | Astra 天空缓存是**经纬球 + 双经度 gutter**：`A:lib/sky_reflection_cache.glsl:5-20`（258×128/256×128、`fract(uv.x)` 复制对侧列）、`:26-45`（跨接缝需额外两次 `textureLod` 手工插值）；`grep -rni "octahedral" A:shaders` 仅命中 `A:lib/encoding.glsl:29-58` + `A:program/lit.vsh:87`/`lit.fsh:109`（法线打包），与天空缓存无关 | 改 `A:lib/sky_reflection_cache.glsl` 的方向映射与 `A:program/sky_reflection_cache.fsh` 写入坐标（2 文件），接缝分支可删；ROUGH 模式 mip 逻辑不变；需 A/B 确认极点/地平线质量 |
| B2 | （备选，不主张为缺口）软图方案：一张 128²、约 5° 模糊的预过滤图与清晰图按粗糙度插值，替代 mip 链 | `P:lib/atmospherics/skyMap.glsl:39-84`、`P:program/prepare1.glsl:36-64` | Astra 已有等价能力：`A:lib/sky_reflection_cache.glsl:40-58` 按 `log2(1+r²(mipCount-1))` 取粗糙 mip + 逐级周期过滤（`A:prepare2.fsh:2-8` 生成 mip）；本项只作**替代实现**备选，不列为独立缺口 | 若 Astra 现 mip 方案出现粗糙反射断层/生成成本问题时可换；否则不动 |

### C 组（大工程/战略项）

| # | 机制 | 来源 file:line | Astra 未实现证据（grep 关键词与结果） | 迁移代价 |
|---|---|---|---|---|
| C1 | **屏幕空间时域彩色方块光（MCBL）**：gbuffers 把发光方块色写 colortex8 → composite 做 4-tap 距离/FOV 缩放模糊 + 深度反渗漏 + 边缘 mask，与当帧色 10% 混合写 colortex9 → 前向光照用重投影取上帧彩光、按亮度比混入方块光；一个 composite pass + 两个缓冲的「低成本主世界彩光」 | 生产 `P:program/composite.glsl:105-168`；消费 `P:lib/lighting/coloredBlocklight.glsl:23-43`；开关 `P:lib/settings.glsl:78`、调度 `P:shaders.properties:121-126` | `grep -rn "MCBL\|multicolor\|MultiColor" A:shaders` = **0 命中**；`grep -rln "colored" A:shaders` 仅下界彩光（`A:global/dimension/nether_colored_light.glsl`、`nether.glsl`、`A:lib/nether_voxel_grid.glsl`、`A:program/shadow.vsh`），主世界无彩光载体 | 新增 1 发射缓冲 + 1 累积缓冲 + 1 composite pass + gbuffer 写出 + 前向消费点（约 3 处接线）；主世界彩光在材料中是长期方向，本项是其屏幕空间近似路径；与 batch4 stracciatella B1 同族（跨包去重由统帅处置） |

### 去重排除（每条：包内出处 → 排除依据）

| 机制 | 包内出处 | 排除依据 |
|---|---|---|
| 天空图资产化（prepare 同帧、含云 alpha、粗糙度分级） | `P:program/prepare.glsl:1-25,83-118`、`P:lib/atmospherics/skyMap.glsl:1-22` | Astra 已是 prepare 阶段同帧生成 + 含云（`A:prepare.fsh:2` → `A:program/sky_reflection_cache.fsh:9-18`），粗糙分级见 `A:lib/sky_reflection_cache.glsl:40-58`；软图见 B2 备选 |
| 水面细节波场足迹 LOD + 方差转粗糙度 | `P:lib/surface/waterHeight.glsl:87-138` | Astra 已有更强等价实现：`A:global/water/surface.glsl:195-296`（`surface_footprint` 按屏幕足迹求 `surface_antialias`，`surface_gradient` 输出 `unresolved` 并入 roughness） |
| SSR 自适应步长/二分/命中早退/粗糙度误差倍率 | `P:lib/reflections/raytrace.glsl:43-214` | Astra `A:global/water/raytrace.glsl:45-137`（递增 stride + 同 texel 缓存 + 二分 + 置信度）；材料 batch2/3 已列 |
| 反射档位退回解析/天空 | `P:lib/reflections/simpleReflections.glsl:8-58` | Astra 已有天空回退（材料 batch1「SSR miss 回退」6 包印证） |
| 云步数反射/DH 减半、命中 break、距离裁剪 | `P:lib/atmospherics/clouds.glsl:213-318` | 材料 batch3 AstraLex「天空 10 步/反射 4 步」+ batch1 云分档已列；Astra 云已有分档/首命中/距离 break |
| 云影与体积光单一来源 | `P:lib/atmospherics/cloudShadow.glsl`、`P:lib/atmospherics/volumetricLight.glsl:8-10` | 材料 batch2「云影图单通道+与云同源+多消费者」已列 |
| 半分辨率体积光 + 保边重建 | `P:program/composite.glsl:372-391`、`P:program/composite1.glsl:93-175` | 背景清单「半分辨率 AO/体积雾 + 保边重建」已实现（`A:global/atmosphere/volume_fog.glsl:208-254`）；本包 4×4 重建取数更多，见反面 4 |
| 单次 mip 采样自动曝光 | `P:program/composite5.glsl:176-210` | 材料 batch3 AstraLex「场景色 mip 单次抓取」已列；Astra 为 64-tap + 1×1 历史 |
| 13-tap + Karis 加权 Bloom / mip 图集 | `P:program/composite4.glsl:23-141` | Astra `A:global/post/bloom.glsl:50-136` 已含 13-tap（高档）与 4/9 分档 + mip 链；材料 batch3 C 组「单 pass mip 打包 Bloom」已列 |
| TAA Catmull-Rom / YCoCg / 移动 flag / 速度调权 | `P:lib/antialiasing/taa.glsl:24-184` | 背景清单 Astra 已有 YCoCg 钳制 + 植被运动历史 + 反应遮罩；Catmull-Rom 与 offcenter 类细节为材料 batch2/3 已列候选 |
| CAS 锐化 | `P:program/final.glsl:143-175` | 材料 batch3（LIGHT/ILV「CAS 式亮度自适应锐化」）已列 |
| 阴影 2×2 手工过滤 + PCSS + 像素锁定 + 彩色透射加权 | `P:lib/lighting/shadows.glsl:41-278` | PCSS/像素锁定为材料已列；彩色阴影 Astra 已实现「遮挡时才读彩色阴影」；透射加权属画质修正非性能 |
| 无 TAA 时冻结 IGN/抖动 | `P:lib/lighting/shadows.glsl:78-84`、`P:lib/util/temporalDither.glsl:1-16` | Astra 阴影核不旋转、抖动已 CPU 化（背景清单），该项无可迁移差异 |
| 水洼掩码 / Snell 窗 / 水柱吸收 | `P:lib/reflections/rainPuddles.glsl:11-48`、`P:program/gbuffers_water.glsl:681`、`P:lib/lighting/shadows.glsl:132-153` | 水洼/吸收为背景清单已有；Snell 窗为材料 batch1 已列；Astra 已有焦散水面高度记录（`A:global/lighting/shadowmap.glsl:152-169`、`A:global/lighting/diffuse.glsl:376`） |
| profile 链 / CPU 帧量 / RENDERTARGETS 变体 / alphaTest / 群系平滑 | `P:shaders.properties:7-12,129-135,151-197` 等 | 材料 batch1-3 已列（Kappa/VPS profile 链、12 包 CPU 预计算、Arc RENDERTARGETS 裁剪）；Astra 已有 `A:program/lit.fsh:33-72` 变体 |
| Voxy/DH 影距联动与雾缩放 | `P:lib/atmospherics/fog.glsl:151-158` | 材料 batch2 C5「Voxy/DH 集成契约」已列，属 Astra 尚无 DH 支持的长期项 |

---

## 六、无法判定

1. **烘焙星空图集的净收益**：`P:lib/atmospherics/nightSky.glsl:133-221` 用 3×3 texelFetch + 逐星早退换掉程序化星空，但星图由包外脚本 `tools/gen-sky-atlas.ps1` 生成（包内无脚本、无源数据），Astra 无对应烘焙管线；「省 ALU vs 多 9 次取数」未实测，需先自研烘焙流程才谈迁移。
2. **八面体折叠 vs 经纬球的最终画质/性能差**：等立体角减少极点浪费、去掉接缝分支，但分辨率/过滤细节需 A/B（B1 落地前建议先做离线方向映射对照）。
3. **colortex8/9 双登记的预期**：MCBL 与 VOXEL_COLORED_LIGHT 默认都关且未见互斥逻辑，作者是否假定二者互斥无法从源码判定。
4. **`SKY_DEFERRED` 天空延迟路径与 prepare 天空图的分工**：`P:program/deferred1.glsl:45-99` 说明天空可在 deferred1 顶点预调色，同时 prepare 又产出含云天空图；可见天空最终取哪条（或叠加）未逐行穷举。
5. **颗粒化 `AO_MODE`/`VL_RESOLUTION`/`REFLECTION` 档位的实测成本阶梯**：包内无作者帧时数据，全部收益为源码级推断。
6. **许可证状态**：整包无许可文件，只能按保留所有权利做思路级借鉴并登记（与 Astra THIRD-PARTY 流程一致）。
7. **组件级同源边界**：光柱（Robobo1221 modified）、FXAA（Lottes）、生成法线（Emin/Complementary）三处为已知第三方来源，若未来考虑任何代码级借鉴须单独溯源，不能按 zayko 名义处理。
