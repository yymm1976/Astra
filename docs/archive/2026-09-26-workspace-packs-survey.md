# 工作区参考光影全景调研（2026-09-26）

> 开发状态已统一到 [持续待办与实施记录](../2026-09-26-itt32-initial-implementation.md)。A1–A3、B1–B3 与可选 TAA 首版已写入；本文的候选表和“当前 Astra”描述保留为调研背景，不作为未完成清单。

本文汇总 2026-09-26 会话对工作区内 Astra 以外全部参考光影的并行调研：34 个包 + IterationT 3.2.0（另有专篇）。每包给出定位、管线、招牌技法（file:line 以 2026-09-26 本地源码为准）与 Astra 借鉴点；文末是跨包综合清单、许可边界与对既有调研结论的纠错。

Astra 路线约束（所有兼容性判断的前提）：无 TAA、前向一次算完、11 张 colortex 用 `size.buffer` 缩尺寸、静态 dither。标注「完全兼容」= 不依赖历史帧/时域累积。

---

## 一、盘点总表

| 批次 | 包 | 既往覆盖 |
|---|---|---|
| 根目录五大精读包 | Complementary r5.9（Reimagined/Unbound 双风格）、Mellow 3.4、Refrax 1.3.1、Solas 2.2b、Steadfast 0.8.0 | Complementary 下界链已移植（handoffs/nether.md）；Solas/Mellow 水链已移植（solas_water 等）；Steadfast 为出处台账基准（verbatim=14/suffix=2/rewritten=6） |
| latest-2026-09-10 | IterationT 3.2.0 | **已由 [2026-09-26-full-review-and-research.md](2026-09-26-full-review-and-research.md) §四 专篇覆盖** |
| refs-2026-09-24（10 包） | astralex、bliss、kappa、nostalgia、photon、fastpbr、miniature、shrimple、super-duper-vanilla、visual-vibrance | 09-24 批次登记（codex-refs-prompt）；本轮建立完整档案 |
| performance-study-2026-09-16 | BSL、complementary-reimagined（photon/makeup/steadfast 与他批重复） | 有 09-16 性能研究文档；本轮补档案 |
| low-end-shaders（15 包） | i-like-vanilla、just-colored-lighting、light-shaders、lite-shaders、makeup-ultra-fast、potato、re-shaded、renderpearl、sildur-fast、sildurs-vibrant、soft-voxels-lite、vanillaa（fastpbr/miniature/super-duper-vanilla 重复） | round3 + 17 包普查两份文档；本轮补充与纠错 |
| lowend-refs-2026-09-25 独有（4 包） | bloop、builders-qol、pegasus、simply-upscaled | 普查文档部分覆盖；本轮补全 |
| 非光影目录 | user-refs（目标截图对）、iris-runtime、bakinglab、npm（工具链）、astra-sc34（自有快照） | 不属调研范围 |

根目录四个 zip（Mellow/Refrax/Solas/Steadfast）与 `_analysis/` 解包版对应，未重复读取。

---

## 二、Complementary r5.9（含 Unbound 增量）

**定位**：全功能综合包标杆。两风格源码只差 `lib/common.glsl:14` 一行（SHADER_STYLE），Unbound 4 = 水/焦散/日月/极光的另一套默认值。每维度 36 fsh + 1 csh；colortex0 主色 R11F_G11F_B10F、shadowcolor1=光柱色+遮挡物高度（alpha）。选项面 230 条/8 档 profile。

招牌技法：

| 技法 | 位置 | 机制 | Astra 现状 | 兼容性 |
|---|---|---|---|---|
| **档位阶梯派生** | `lib/common.glsl:537-575` | DETAIL_QUALITY 一档派生一串 define，单项 -1=跟随档位、显式值=覆盖 | 四档 profile 是 4×73 token 手写平铺 | 工程改进，档位维护量降一个量级 |
| **Bloom Fog（远雾转辉光）** | `lib/atmospherics/fog/bloomFog.glsl:13-45`；剥离/乘回 `composite1.glsl:329`→`composite5.glsl:200-206` | `1+fog⁴·k`（雨8/夜3/洞穴14/水下14/下界14），bloom 前剥离、后乘回 | 无 bloom fog；下界 haze 只在体积雾内部 | **完全兼容**；下界/雨夜/洞穴一次拿到 |
| **SSAO 内联 4/12 样本** | `program/deferred1.glsl:64-107,268,301` | 内联在 deferred，静态噪声图 dither，无模糊 pass、零时域 | **全包零 AO** | **完全兼容**；唯一能在无 TAA 内落地的环境光遮蔽；需实机定强度 |
| **水下雾二次指数曲线 + 水柱深度差** | `lib/atmospherics/fog/waterFog.glsl:10-15`；水面 alpha `translucents/water.glsl:175-194` | `1-exp(-(d/48)²)` 近场极清远场陡糊；alpha 由 depthtex0/1 之差（水柱长度）决定 | `solas_water.glsl:90` 线性消光，20 格已 45% 雾——与"蓝滤镜感"同源 | **完全兼容**；常数级改动 |
| **整屏水下扭曲+水色分级** | `final.glsl:95-98`；`composite1.glsl:267-272` | 屏幕级 UV 正弦摇摆 + 蓝青色偏 + 光束整体染色 | 无 distortion；整屏调色在 water_composite | **完全兼容**（一行；UI 边缘一起晃是其取舍） |
| **体积光近/远双段 + 权重差分** | `volumetricLight.glsl:83-129,230-264` | nearSamples 6-15 + farSamples=1 远场近似；`sliceWeight` 差分归一使换分布不改标定 | 光束 40 格定长全近场，段数一变标定就变 | 兼容；**必须保留静态 dither**，勿抄 frameCounter 黄金比 |
| **shadowcolor1.a 存遮挡物高度→场景感知光柱** | `shadow.glsl:220`（水面+3.5、玻璃归0）；探测 `volumetricLight.glsl:280-337` | 5×5 探针累加被遮挡 texel 高度→vlFactor，薄遮挡漏光 | 只有 GODRAYS_SUN_OCCLUSION 单像素淡出 | 兼容；加第二个 shadow RT 即可 |
| **FXAA 独立 pass** | `lib/antialiasing/fxaa.glsl:17,164-180`；挂 `composite7.glsl:22-24` | FXAA 3.11，纯模式不读深度 | **无 FXAA 无 TAA**，零 AA 结构性欠账 | **完全兼容**；Astra 当前唯一现成 AA 出路 |
| 半分辨率反射空洞填补 | `composite1.glsl:143-158` | 4 邻域取更深样本补天空空洞 | 有 0.25/0.5 缓冲，SSR 同理会缺天空 | 兼容、即插即用（其时域重用不可借） |
| Tonemap 三段附加 | `composite5.glsl:63-100` | darkLift 暗部提升 + whitePath 白点 + 暗部去饱和 | 四算子纯 tonemap | 兼容；专治暗部糊灰 |

Unbound 增量：云多倍频命中累积 + 逆光银边（`unboundClouds.glsl:127-195`，`a>0.9 break` 免费提前出）；云尺度驱动步长（尺寸>100 时步长÷√size）；梯度差焦散（`shadow.glsl:123-137`，4 采样差分）。r5.9→r5.9.3 只动 23 文件、不含云雾（引用雾/云结论无版本风险）。

已移植确认：nether.md 登记的下界链逐条属实；剩余未做 = netherStorm（与"前向零 compute"冲突）、coloredLightFog；其 LOW_QUALITY 斜采样（`netherStorm.glsl:19-26`，减采样不改覆盖）值得单记。热浪/灰烬 Complementary 也没有。

---

## 三、refs-2026-09-24 批次 A：astralex / bliss / kappa / nostalgia / photon

### astralex 93.0 —— 特效大杂烩 + 选项架构（202 program、271 screens/约 530 滑条/9 档）

| 技法 | 位置 | 机制 | Astra 现状 |
|---|---|---|---|
| 焦散"改 albedo"腿 | `lib/lighting/caustics.glsl:63-68` | 水下岩石 albedo 本身染水色，不只吃光 | 只有"改光"腿（`caustics.glsl:77-112`） |
| 光柱彩色阴影染色 + 屏边收缩 | `volumetricLight.glsl:27,72-81,121` | 命中 shadowcolor0 时彩影乘进光柱；屏边/fov 收 maxDist | godrays 不吃 shadowcolor、无收缩 |
| 世界曲率（伪星球） | `lib/vertex/worldCurvature.glsl:1-19` | 顶点 `dot(pos,pos)/SIZE` | 无（决策点而非调参） |
| 发光亮度三维度表 | `surface/emissiveT.glsl:10-37` + settings | 每方块×每维度×每通道硬编码 | `surface_emission.glsl` 集中表 |
| **profile 继承写法** | `shaders.properties:7-15` | `profile.MEDIUM=profile.LOW + 覆盖项` | 4 档平铺；与 Complementary 派生同向 |

### bliss 2.1.2 —— Chocapic13 系奇幻/性能（41 fsh、418 define）

| 技法 | 位置 | 机制 | Astra 现状 |
|---|---|---|---|
| 下界体雾三层单程 march | `lib/nether_fog.glsl:35-119` | 三层各自 extinction/自发光色，haze 刻意不参与 absorbance | 已移植同源（`nether_volume.glsl`）；**"每层独立色+部分层不吸收"模板可复用到末地体积雾** |
| LPV 亮度-色相解耦 | `lib/lpv_render.glsl:5-31` | `lpvCurve=pow(1-sqrt(1-v),2)` 重映射，颜色存 HSV | 有 compute 彩光但无此曲线；正对"下界泛光发白" |
| **半分辨率+固定小步数** | `res_params.glsl:16`（VL 0.5）、`settings.glsl:407-410`（云 15 步）、`volumetricClouds.glsl:258,420,610` | 云质量 0.5、步数固定 15，三层云共用一个 march | 平面云全分辨率 6..64 步——**最直接的降本参照** |
| 条件启用 pass | `shaders.properties:87` | `program.composite5.enabled=TAA_UPSCALING` | 6 条 composite 常开 |

### kappa 5.3 —— 技术密度最高（52 fsh、5 档继承）

| 技法 | 位置 | 机制 | Astra 现状 |
|---|---|---|---|
| 解析大气：airmass+多散射+**行星反照** | `lib/atmos/air/atmosphere.glsl:69-195`、`density.glsl:39-115` | 逐样本三行矩阵消光 + 行星当 Oren-Nayar 反射面 | 解析近似、无逐样本积分、无行星反照；**下界/末地环境光质感的现成补强** |
| 低分辨率 SSPT + 解析回退 | `sspt.fsh:20,188-240,583-600` | 关 SSPT 走"假反弹+AO×方块光"解析分支 | 无 SSGI；其三段式间接光公式可直接改善下界 |
| 顶点 AO 独立通道 | `sspt.fsh:564,592-596` | AO 走 colortex15.y 非 gl_Color.a，`VAO²` 合成 | 下界顶点 AO 是否生效未验证；**AO 走独立位更可控的答案** |
| Hammon 漫反射 | `lib/brdf/hammon.glsl:25-45` | roughness 双近似插值+多散射补偿 | 常规 Lambert/SSS；适合 netherrack 类多孔材质 |
| 云 checkerboard 帧间累积 | `deferred1.fsh:296-345` | 1/9 像素密度+帧累积 | **不采纳**（时域冲突，仅登记） |

### nostalgia 5.1 —— 胶片风 + 低分辨率经济（49 fsh、4 档）

| 技法 | 位置 | 机制 | Astra 现状 |
|---|---|---|---|
| **天空预渲染一张三用** | `deferred/skyboxPrep.fsh:6,256,327` + `skyboxApply.fsh:85` | 512² 上半"干净天空"下半"带云天空"，alpha 塞云影；主 pass 一次投影采样 | 有 258×128 反射缓存但天空仍逐像素算；**一次低分辨率 pass 换天空+云影+反射三处** |
| **下界 forward gbuffer** | `gbuffer/nether/forward.fsh:20,105-115` | 下界在 gbuffer 阶段直出 sceneColor+GBuffer，R2 拟随机抖动代 TAA | 下界走统一 deferred 全分辨率；**下界质感与性能双弱的一次性解**（world-1 目录现成） |
| 胶片分级分段样条 | `grade/grading.fsh:346,83-136,292-346` | RFilmEmulation + C5/C9 样条 + 分块曝光统计 | 无胶片曲线；纯后期无风险 |
| 间接光 1/4 分辨率 | `settings.glsl:109-114` | `indirectResReduction 4`、SSPT 2spp/1 bounce、SVGF 默认关 | 无；与 Bliss 半分辨率同向 |

### photon 1.3b —— 工程标杆（402 program、6 个 shadow 程序、3 csh）

| 技法 | 位置 | 机制 | Astra 现状 |
|---|---|---|---|
| **折射落点面积比焦散** | `shadow.fsh:106-146,154` | 光线折射前推水柱，`dFdx/dFdy` 量落点面积比→聚焦增益；同 pass 写 `exp(-absorption·depth)` | 6 波解析 Hessian 改了三轮**从未实机确认**；这是独立交叉验证+降级路径，能首次把"结构错/参数错"分开 |
| **水下光束多散射迭代+归一** | `fog/water_fog_vl.glsl:44-148` | 步数 `16+0.5·rayLen` 截 25；4 次多散射逐次减半；`scattering/●extinction` 归一、`transmittance^0.75` | 光束固定 40 格 4/7/10 段；**多散射与归一正是 Astra 光束"平"的直接原因** |
| 天空 SH 9 系数 | `d4a_generate_sky_sh.csh`、`diffuse_lighting.glsl:222-232` | compute 预烘天空 SH，`sh_evaluate_irradiance(sky_sh,bent_normal,ao)` | 无 SH；成本极低的环境光方向性 |
| 大气 LUT 借 depthtex0 | `sky/atmosphere.glsl:25-26` | 云 pass 把 depthtex0 当散射 LUT 省一张纹理 | 无 LUT；纹理预算受限时的技巧 |
| 云覆盖率场+梯度投影 | `sky/clouds/coverage_map.glsl:9-79`、`d1_clouds.fsh:109-161` | 覆盖率场 1.5e5m² 投影，远处高分近处压缩（distortion 0.8）；主步 40×20 | 全分辨率 march；**同步数先降 20 步档仍有形** |
| SSRT 屏幕空间阴影 | `shadows/ssrt.glsl:11-45` | 几何步长 2.0/厚度 10 块/10 步补接触阴影 | 无；末地掠射条纹的替代解法 |
| 彩色透射独立变换 | `pcss.glsl:250-285` | 不做漏光修正以免吃掉焦散 | 彩影链可对照 |

---

## 四、refs-2026-09-24 批次 B + 性能批次：fastpbr / miniature / shrimple / super-duper-vanilla / visual-vibrance / BSL / complementary-reimagined

### fastpbr —— labPBR 材质顶配（13 colortex 全 RGBA16F + compute + TAAU）

| 技法 | 位置 | 机制 | Astra 现状 |
|---|---|---|---|
| labPBR 解码 + 导体 eta 表 | `lib/brdf/material.glsl:44-57` | roughness/8 种金属 eta/f0 clamp | 无 normals/specular 采样；接资源包的现成模板，前向兼容 |
| 多散射 GGX 能量补偿 | `lib/brdf/specular.glsl:61-131` | T-R + Smith + fresnelDielectric | 单散射 GGX（`end_surface.glsl:20-31`）；单帧收敛可借 |
| HBIL 半分辨率地平线 AO | `deferred/HBIL.csh:22,179-270` | 1 slice×4 地平线 + FastAcos 积分 + antiBleed | 无 AO；低样本噪声对无 TAA 最痛，需固定抖动+空间滤波兜底 |
| TAA 依赖项 | `post/temporal.fsh` 等 | TAAU 上采样+时间去噪 | **不可借**（负例） |

### miniature —— 极小体积轻量水面样本（28 文件、全前向）

| 技法 | 位置 | 机制 | Astra 现状 |
|---|---|---|---|
| **立方翘曲阴影畸变** | `common/getShadowDistortion.glsl:1-5` | `xy /= 0.8·|xy|+0.2` 三行把中心分辨率让给近处 | **无畸变**；小 shadowMapResolution 档最缺 |
| 自适应步长 SSR + 二分 | `common/getReflectionColor.fsh:24-56` | 步长随深度差自适应，命中后二分 | 固定 24 步+6 细化 |
| glint max(r,g) 限幅 | `translucent.fsh:44-54` | 防高光过曝 | 提亮链另一套 |
| 逐顶点雾/漫反射 | `getFogMix.vsh`、`getDiffuse.vsh` | 线性量全在顶点算 | 低成本档可搬 |

### shrimple —— compute 重负载（79 pass；**重要纠错见 §八**）

| 技法 | 位置 | 机制 | Astra 现状 |
|---|---|---|---|
| 体积雾实为前向 gbuffer 逐片元 | `gbuffers_water.fsh:410` 等 4 处 + `lib/fog/fog_volume.glsl` | IGN 抖动+VOLUMETRIC_SAMPLES 步进+逐样本投影 | godrays 独立 composite；可借"抖动+低样本+空间滤波" |
| VL 双缓冲随档缩尺寸 | `shaders.properties:621-626` | `VOLUMETRIC_RES==2 → size.buffer=0.25` | 已有同类 size.buffer 阶梯 |
| 雾子系统拆分 | `lib/fog/` 7 文件 | 多套雾并行、宏裁剪 | 单一 FogV2；拆分方式可借 |
| bilateral_gaussian / composite11.csh | `composite12.fsh:223`、`composite18.fsh:202` | **前者是死代码；后者是 TAA 配套去噪** | 均不可作为参考热点 |

### super-duper-vanilla —— 原版增强取舍（33 program、POTATO→ULTRA）

| 技法 | 位置 | 机制 | Astra 现状 |
|---|---|---|---|
| **导数生成法线** | `lib/PBR/integratedPBR.glsl:13-38` | textureGrad 三偏移亮度差→slopeNormal→TBN，零额外贴图 | 无；无资源包时的材质感，前向可用 |
| **方向性 lightmap** | `lib/lighting/complexShadingForward.glsl:17-24` | dFdx/dFdy 反推光向 dot(normal) 造方向性方块光 | 点光/采样式；极便宜的单帧"假方向性" |
| 前向/延迟共享着色函数 | `complexShadingForward/Deferred` 同构 | 同一 dataPBR+光照函数两路径复用 | lit/water 各成一体（424/376 行）；抽公共 BRDF 的组织样本 |
| 降档语义：关阴影→lightmap 假阴影 | `settings.glsl:51-53` | 降档保观感不黑屏 | 档位体系已有；语义可借 |
| SSR 步数入档位 | `rayTracer.glsl` + profile | RAYTRACER_STEPS 16-32/BISTEPS 0-8 | 步数写死 24/6 |

### visual-vibrance —— 色彩分级专精（jbritain）

| 技法 | 位置 | 机制 | Astra 现状 |
|---|---|---|---|
| **PIXEL_LOCKED_LIGHTING** | `lib/lighting/shadows.glsl:35-39`、`water/waveNormals.glsl:70`、`composite1.glsl:200-207` | 世界坐标 floor(··PIXEL_SIZE)/PIXEL_SIZE 吸附后再算 viewPos/波场/折射 | **全库无吸附**；无 TAA 防闪烁核心手段，波法线/shadow 采样点可直接加 |
| 物理化 bloom（Karis 均值） | `lib/post/bloom.glsl:30-45` | 1/(1+luma) 抑火点 | capture+mip 链；单帧有效可借 |
| AgX 多 look 组织 | `lib/post/tonemap.glsl:24-140` | 算子+look 组档位 | Astra 算子覆盖更全，反向借组织方式 |
| 时间滤波默认关仍可交付 | `settings.glsl:47` | 佐证无 TAA 路线可行 | — |

### BSL —— 综合性能平衡教科书（345 define、档位最密）

| 技法 | 位置 | 机制 | Astra 现状 |
|---|---|---|---|
| MCBL 彩光洪泛成本控制 | `shadowcomp.glsl:14,100`、`coloredBlocklight.glsl:1-24` | Y 轴半高省 2×、距离档定 workGroups、MCBL_RANDOM | 彩光仅下界/末界；扩主世界时的预算清单 |
| **阴影畸变 + 硬件 PCF gather + 着色阴影** | `shadows.glsl:65,144-160,236,248-255` | distortFactor + sampler2DShadow + shadowcolor0 着色 | 有 gather 无畸变；与 miniature 同源配套 |
| **粗糙反射 mip LOD** | `roughReflections.glsl:24-25` | `lod=log2(viewHeight·0.03125·(1-smoothness)²·fov)` 替代模糊 pass | 2x2 锥足无 LOD；反射缓冲开 mipmap 即可用 |
| 粗糙度→采样数/半径公式 | 同上 | 5x5 稀疏核按 exp2(lod-1) 偏移 | 与 CR 的 smoothness^8 收窄核同向 |

### complementary-reimagined —— 氛围重制 + 材质方法库

| 技法 | 位置 | 机制 | Astra 现状 |
|---|---|---|---|
| **smoothness 自适应反射分离滤波** | `materialMethods/reflectionBlurFilter.glsl:1-45` | 5x5 高斯×法线拒绝，`texelSize·(1-0.75·smoothness⁸)` 收窄核 | 锥足固定；直接可移植，同时改善冰面/粗糙面 |
| **彩色光雾（体素光进雾）** | `fog/coloredLightFog.glsl:1-30` | 沿视线 8 格步长累积 light volume，dither 抖起点 | 光束只做天光 shaft；洞穴/夜间氛围差异点，无 TAA 也稳 |
| 云影解析求交 | `lighting/cloudShadows.glsl:1-30` | tan(acos(dot)) 求云层投影偏移，不采样云图 | `scene.glsl:228-243` 已对齐；核对第二云层分支是否搬全 |
| 彩光洪泛优化族 | `shadowcomp.glsl:11-13,128-152` | BEHIND_PLAYER 不更新 + **HALF_RATE_SPREADING 奇偶帧半速** | nether_light 无这些开关；半速乒乓可直接用于低频光场 |
| 氛围模块化 | `lib/atmospherics/` aurora/nebula/rainbow/enderStars/netherStorm | 每项独立 glsl+宏开关 | stars.glsl 可加星云/彩虹分支不动主链 |
| 暗部去饱和 | `composite5.glsl:43-84` | 3 行电影感补丁 | grading 无此项 |

---

## 五、Mellow / Refrax / Solas / Steadfast

### Mellow 3.4（MIT，可直接派生）

| 技法 | 位置 | 机制 | Astra 现状 |
|---|---|---|---|
| **体素光增量重投影** | `program/begin.csh:4-25` | `Pos-previousCameraPosition` 平移上帧光场 + `frameCounter%2` 分向传播；128³-512³ 档位表 | 64³/8 步同帧单维；**无 TAA 兼容的扩容最省路径** |
| 云步数按仰角自适应 | `clouds.glsl:64-65,139-155` | `SampleCount=((1-N.y)·0.75+0.25)·12+1`，跨纹素精确跳跃 | 步数固定 |
| 云四档实现阶梯 | `clouds.glsl:206-231` | 同一出口下 flat/wispy/volumetric/blocky 四份，双层复用同函数换常量 | 单层 Complementary 派生 |
| 块状云噪声预烘进 buffer 通道 | `clouds.glsl:137-155` | alpha 当噪声查找，循环内 1 次 texture | 即时 fbm |
| 顶点级常量光色 flat varying | `light_colors.vsh:1-20` | SKY/SUN 色顶点算好 flat 传，voxy 退回片元 | 光色在 uniforms/片元 |
| final 内 TAA→CAS→颗粒→暗角 | `final.fsh:5-74`、`post/cas.glsl` | CAS 是 AMD MIT 头 | 无 AA/锐化 |

### Refrax 1.3.1（**All Rights Reserved，只能取思路**）

架构最新：compute LUT 全套（transmittance 256×64 / multiscatter 32×32 / skyview 192×108 / skycache 1×1，全部每帧重算不读历史）+ HiZ 六级 + 10 张 image。可借鉴（按思路自写）：

| 技法 | 位置 | 机制 | Astra 现状 |
|---|---|---|---|
| **云阴影三层 slab 打包 RGB** | `lib/clouds.glsl:187-221,227-250` | 512² rgba16f 的 RGB 各存一层云光学厚度，XZ 沿光向投影、纹素对齐锚点消闪烁 | 单平面解析 trace（`scene.glsl:226-252`）；每像素 3 次密度查询降为 1 次采样 |
| **单标量步数缩放** | `lib/settings.glsl:58-82` | PERF_SAMPLE_NUM/DEN（1/1→1/16）套所有 raymarch | 档位靠 size.buffer+逐选项常量；与既有阶梯天然叠乘 |
| 天空 LUT 全套 compute | `atmos_*.csh` | 每帧构建、azimuthal 对称参数化 | 无 LUT；可先只上 1×1 skycache 验证 |
| 半分辨率 froxel 介质 compute | `media.csh.glsl:19-21` | 0.5 分辨率直写 rgba16f image，雾/光轴/LPV 雾一次算完 | 只有解析雾；上体积雾可先做这一形态 |
| 后处理素材库 | `lib/post.glsl`、`lens.glsl` | Purkinje 位移/颗粒/RCAS/DOF 螺旋核，全无历史 | 缺颗粒/锐化/色差 |
| 下界天空=雾色×fbm 烟尘 | `atmosphere.glsl:380-387` | dimensionSky 与反射共用同一函数 | 低成本下界观感提升 |

### Solas 2.2b（**无许可声明，只能自写等价**）

| 技法 | 位置 | 机制 | Astra 现状 |
|---|---|---|---|
| 下界裁掉 3 个重型 pass | world-1 缺 composite(RSM)/composite1(ssptDenoiser)/composite2(temporal) | 不编译不执行 | world-1 已裁部分；**可把"维度裁剪"做成清单审计** |
| **体积云深度回写契约** | `volumetricClouds.glsl:154-156` | 密度超阈值把最小命中距离写 currentDepth，供水面丢弃被云挡的像素 | 云无深度契约；云改 composite 合成时的关键件 |
| 天空叠加物与云量耦合 | `skyEffects.glsl` 7 处 | 星空/银河/极光统一接收云量参数压制自身 | 缺银河/极光的云量耦合 |
| LPV 雾+闪电+萤火虫 | `lpvFog.glsl:113-160` | 距离衰减闪电、噪声萤火虫 | 廉价氛围件 |
| 固定 32 点螺旋核 DOF | `computeDOF.glsl:1-33` | 无随机采样，最接近无 TAA 的 DOF | 无 DOF |

### Steadfast 0.8.0（GPLv3+§7，出处台账基准——轻量复核）

台账外值得注意的 4 条：Minishita 采样布局（`environment/sky/minishita.glsl:454-455` 两非均匀视线样本 0.15/0.65 + 预乘覆盖——Astra 同文件自认"2×1 均匀采样靠 ASTRA_SKY_DAY_GAIN=22 补偿"，**换布点+预乘可消地平线偏色**，代价是 4 个 CPU uniform）；选项就近声明（29 处内联 vs Astra 集中 83 条）；双层卷云单通道分层（`cirrus.glsl:22,39,173-254`，"主样本偏移掩盖 value noise 伪影"技巧）；昼夜调色双枚举解耦。

---

## 六、低配 16 包档案（PERFORMANCE/NO_SHADOWS 档的主参照）

| 包 | 定位 | 关键技法（file:line） | Astra 借鉴点 |
|---|---|---|---|
| sildur-fast | 3 后处理极简 | profile.Fast 一行关 6 项 + **影距 90**（`shaders.properties:68`）；反射=单次 UV 偏移采样（`composite.fsh:122`） | Astra PERFORMANCE 影距 192，有 ~2× 余量；低档用偏移采样代降步数 |
| re-shaded | 0 个 Iris pass（替换 core shader） | 复用原版 `apply_fog()`（`terrain.fsh:16`）、面亮度常数 | 极低配可留"原版雾函数逃生档" |
| vanillaa | 原版+后处理 | **CAS 锐化**（`final.fsh:26-103`，AMD MIT 内嵌许可，9 tap 三态写法）；按用途分精度注释（R11F/RGB8/RGBA16） | ★ Astra 零 AA 零锐化，CAS 许可干净可直接填 final 空档 |
| light-shaders | 极简 Chocapic | TAA 默认开只作用世界几何（`composite1.fsh:49,105-114`）；CAS 式 sharpen；TAA 在后处理前的顺序纪律 | 佐证"连极简包都靠 TAA"——Astra 需 CAS/FXAA 对冲 |
| lite-shaders | 7 后处理 | **单一 RENDER_SCALE 乘进所有步数循环**（`config.glsl:272`、`ao.glsl:8`、`volumetric_light.glsl:31`、`bloom.glsl:12`、`lod.glsl:3-4`）；`profile.no_effects` 一行关 20+ 项 | ★ 一个标量统管成本，比 4×73 token 枚举单调可证 |
| makeup-ultra-fast | 10 档 | CPU 侧派生链 `softLod=log2(viewHeight/softBaseSize)`（`shaders.properties:224-228`）；mipmap_bloom 零额外缓冲；R8 单通道缓冲实例 | 档位同时改数值（BLOOM_SAMPLES 等），Astra NO_SHADOWS 可再分三级 |
| potato | 极限省（无 shadow 程序） | **固定标量 HDR 压缩** `compressSceneColor=clamp16F(c)/4`（`head.glsl:26-32`）；**折射辅助=深度感知 9-tap 模糊**（`composite1.fsh:99-115`，仅透明在前才跑）；单 tap 折射+屏边回退 | ★ 低档折射从"直接关掉"变"9-tap 观感"，成本比 96 步 SSR 低一个量级 |
| renderpearl | 全 compute 后处理 | **SSBO 光源表**（`buf/ll.glsl:5-6`，顶点按 chebyshev 取用）；COMPAT 屏把驱动能力当编译选项（`shaders.properties:37-39`）；gbuffers 塌缩 3 程序 | 第三种彩光路线（表驱动）；省编译不省帧 |
| soft-voxels-lite | 1spp+跨帧累积 | SVGF 数值档去噪（`settings.glsl:92-98`） | 不采用（时域，D 级） |
| bloop | 37 条 enable 规则 | **粗糙面用 mip `mix(1.5,8.0,roughness)` 代采样**（`reflection_lib.glsl:97-98,449,458`）；RT_SIMPLE 包围盒求交定步长（`reflection_lib_fast.glsl:5-25`）；POTATO 档 SSR_STEPS=2 | 步数化+粗糙度→mip |
| builders-qol | 4 后处理 | **模糊强度存 alpha**（`composite1.fsh:643-761`，六透明介质源取 max）+ **仅沿 Y 的 1D 模糊**（`final.fsh:19-56`，`fogify` 廉价钟形、`sqrt(avg.rgb/avg.a)` 保能量）；程序化末地天空画在几何 pass（`gbuffers_block.fsh:31-39`） | ★ 半成本模糊 + alpha 携带后处理参数 |
| pegasus | 9 档 | **阴影核宽按影图分辨率归一**（`shadows.glsl:77,133`）；BACKGROUND_RESOLUTION_DIVIDER 伪降采样（只改步长不建缓冲，`settings.glsl:226`）；条件声明 `colortex1Format=R16F` | Astra SHADOW_SOFTNESS 未按分辨率归一（B3 欠账）直接可借；注意其 `pow(x,1.0)` 恒等调用是反面教材 |
| simply-upscaled | 6 档 | **保边纹理放大**（`Better_3D_Textures.glsl:718-771`，色差扭曲混合权重=相似色软过渡异色保硬边）；距离门控启用（`:865-895`）；各质量档等成本 | ★★ 纯空间、无历史，正对无 TAA 缺口的清晰化方案 |
| just-colored-lighting | 5 compute+composite | **RGBA8 4B/体素**（`voxel_photons.csh:321`）；**同一 image 上下半 ping-pong**（`:200-205`，不分配第二张图）；更新间隔买轮数（`shaders.properties:328-355`） | Astra 8B/体素×2+ID；**内存减半手法直接可用** |
| i-like-vanilla | 结构参考（18 后处理） | **体积 Y 减半+世界锚定环绕寻址**（`coloredLightingUtils.glsl:5-13`，移动零成本）；**单 dispatch 泛洪+16KB LDS**（`shadowcomp.glsl:38-70`，9→1 dispatch）；`voxelIds R8UI`+RGB10_A2=12B/体素；逐方块 ID 代码生成（`generated/`） | ★★ Astra 20B/体素全高 64³×9 dispatch——四条全可对表 |
| sildurs-vibrant | 6 后处理 5 门 | composite2=TAA 独占、deferred1 按材质需求存在（`shaders.properties:9-13`） | Astra composite/composite3 无条件 true；档位差=pass 与门的差 |

---

## 七、跨包综合：Astra 借鉴优先级

### 7.1 无 TAA 缺口的对冲（最高优先——Astra 零 AA 零锐化、无防闪烁手段）
1. **CAS 锐化**：vanillaa `final.fsh:26-103`（AMD MIT、9 tap、许可干净）——落进 final 既有全屏 pass。
2. **FXAA 3.11 独立 pass**：Complementary `lib/antialiasing/fxaa.glsl`——纯模式不读深度。
3. **PIXEL_LOCKED_LIGHTING**：visual-vibrance `shadows.glsl:35-39` 等——世界坐标吸附，波法线/shadow 采样点/彩光注入点几行 floor，防高频闪烁。
4. **保边纹理放大**：simply-upscaled `:718-771`——近处才付费、各档等成本。
5. 佐证：visual-vibrance 与 builders-qol 都证明"默认无 TAA 也能交付"，但前提是像素锁定/空间滤波补齐。

### 7.2 主世界性能（第二薄弱环节）
1. **天空预渲染三用**（nostalgia）：一张 512² = 天空+云影+反射，换掉三处重复计算。
2. **半分辨率体积+固定步数**（bliss VL 0.5/云 15 步）+ **间接光 1/4 分辨率**（nostalgia）+ **SSAO 内联 4/12 样本**（Complementary，兼补 AO 缺口）。
3. **云步数仰角自适应**（Mellow）+ **尺度驱动步长**（Unbound）+ **覆盖率场梯度投影**（photon）。
4. **单标量步数缩放**（lite-shaders RENDER_SCALE / Refrax PERF_SAMPLE）与 **profile 继承**（astralex/Complementary）作为工程底座。
5. 条件启用 pass（bliss/sildurs-vibrant）：把 Astra 无条件常开的 composite 逐个过一遍维度/功能门。

### 7.3 水下（接线修复之后的观感增量）
1. **雾曲线换二次指数 + 水柱深度差 alpha**（Complementary）——治"蓝滤镜感"，常数级改动。
2. **光束多散射迭代 + 散射/消光归一**（photon）——治"光束平"。
3. **体积光近/远双段 + 权重差分**（Complementary）——40 格硬上限接远场腿 + 标定稳定。
4. **折射面积比焦散**（photon shadow pass）——解析 Hessian 的独立交叉验证/降级路径。
5. 整屏水色分级+正弦扭曲（Complementary，一行）；焦散 albedo 腿（astralex）。

### 7.4 下界/末地氛围
1. **Bloom Fog**（Complementary）——下界热霾一处改动三维度受益。
2. **下界 forward gbuffer**（nostalgia）——质感与性能双收。
3. **行星反照+多散射**（kappa）/ **天空 SH**（photon）——环境光方向性质感。
4. LPV 亮度-色相解耦（bliss）、雾色×fbm 烟尘（Refrax 思路）、彩光雾（CR）。
5. 末地体积雾可复用 bliss"每层独立色+部分层不吸收"模板。

### 7.5 彩光体积（下界 compute 链瘦身）
i-like-vanilla（Y 减半+环绕寻址+单 dispatch LDS）+ just-colored-lighting（RGBA8/上下半 ping-pong）+ Mellow（位置差重投影扩 128³）+ BSL（HALF_RATE/BEHIND_PLAYER）——四包拼出一套完整的"扩容又省带宽"方案。

### 7.6 材质与后期
导数生成法线+方向性 lightmap（SDV）；labPBR 解码+多散射 GGX（fastpbr，接资源包时）；Hammon 漫反射（kappa）；tonemap 三段附加（Complementary）+暗部去饱和（CR）+Karis bloom（visual-vibrance）；alpha 携带后处理参数+1D Y 模糊（builders-qol）；固定标量 HDR 压缩+折射辅助模糊（potato）。

### 7.7 工程手法
阴影畸变（miniature/BSL 三行）+核宽按分辨率归一（pegasus，B3 欠账）；云深度回写契约（Solas）；粗糙反射 mip LOD（BSL/bloop）；Astra 无 TAA 可用的 DOF=固定螺旋核（Solas）；flat varying 顶点光色（Mellow）；选项就近声明（Steadfast）；COMPAT 驱动能力选项（renderpearl）。

---

## 八、对既有调研结论的纠错（本轮核实）

1. **vanillaa 无 SMAA**：round3 基线记"可选 SMAA/CAS"，实际全包 grep SMAA 0 命中，只有 unsharp/CAS 两态。
2. **potato 的省法不是 const 数组**：真正的杠杆是折射辅助模糊 + 固定标量 HDR 压缩。
3. **shrimple bilateral_gaussian 是死代码**：`composite12.fsh:223`、`composite18.fsh:202` 两处 include 均被注释，词法清点第一名不在运行路径；真实热点是 4 个前向 gbuffer 里的 fog_volume。
4. **_TECHNIQUE_SCAN.json 的 lowprec_formats 口径不可信**：给 light-shaders 记 12 条低精度格式，源码实际一条格式声明都没有。
5. **pegasus `pow(abs(sdist),1.0)` 是恒等调用**——低配包里也有纯浪费，抄之前必读指数。
6. 顺带核实：Astra 末地石发光（END_STONE_GLOW）在当前源码已有门控实现且四档覆盖（审查已确认 F-6），旧任务清单"末地石无发光"的说法过时。

---

## 九、许可边界（移植前必查）

| 许可 | 包 | 处理方式 |
|---|---|---|
| MIT | Mellow 3.4；vanillaa 内嵌的 CAS（AMD MIT） | 可派生，保留许可头 |
| GPLv3 + §7 附加条款 | Steadfast 0.8.0 | 已按派生处理（THIRD-PARTY 台账）；继续沿用 |
| All Rights Reserved | Refrax 1.3.1 | **只能取思路自写**，禁止复制/再分发 |
| 未声明 | Solas 2.2b | 只能自写等价实现 |
| 未核查 | Complementary、astralex、bliss、kappa、nostalgia、photon、fastpbr、miniature、shrimple、SDV、visual-vibrance、BSL、CR、低配各包 | 本轮未逐一核查 LICENCE，移植表达式前必须先查 |

---

## 十、与既有报告的关系

- IterationT 3.2.0 专篇：[2026-09-26-full-review-and-research.md](2026-09-26-full-review-and-research.md) §四（本文不重复）。
- **注意**：full-review 报告的部分结论已被 [2026-09-26-itt32-design-study.md](2026-09-26-itt32-design-study.md) §6 依据源码与 Iris 官方文档更正（ITT 黑洞存在性、水下 fresnel 推导、colortex4 时序、下界 shadowDistanceRenderMul 等）；本文各包档案未复用被更正的论断，但阅读前者时须以更正版为准。
- 既有文档仍有效的结论：round3 与 17 包普查的低配结论（本文只做补充与纠错）；codex-refs-prompt 的批次登记。
- 本文与 full-review 报告共同构成 2026-09-26 的调研闭环：**前者回答"我们自己的代码怎么样"，本文回答"别人有什么好东西"**。
