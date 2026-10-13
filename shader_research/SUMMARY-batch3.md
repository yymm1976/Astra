# 第三批参考光影调研：20 款知名包的性能优化机制与 Astra 新颖借鉴点（SUMMARY-batch3）

接续状态（2026-10-03）：已根据当前源码选择并实现远处植被风场、完整 TAA 遮罩邻域 gather、云白天调色 CPU 化。本文下方保留调研原始结论；其“未实现”判断及 Bloop 三次 gather 的覆盖说明有部分误判，当前纠正与暂缓理由见[选择与实现](../docs/archive/实现与取证.md#record-019)。

日期：2026-10-03。数据时点：Modrinth 下载量与最新版本按当日 API 实测。
执行方式：Modrinth API 按下载量排序圈选 → 20 款 zip 下载并解压至 `reference_shaderpacks/<slug>/`（原件在 `reference_shaderpacks/zips/`）→ 10 个只读调研代理逐包深挖 → 每条借鉴点先对 `Astra/shaders` grep 核实「未实现」才允许列入。
上游输入：`docs/2026-10-02-shader-reference-performance.md`（上轮 14 款采用方案）、`shader_research/SUMMARY.md`、`SUMMARY-batch2.md`（上轮 42 款）。
本报告为纯调研产出，不含对 Astra 的任何代码改动。包内 file:line 相对 `reference_shaderpacks/<slug>/shaders/`（多数进一步省略 world0/program 等子目录，按文件名 find 可定位）；Astra 侧 file:line 相对 `Astra/`。

## 一、圈选与排除

### 1.1 入选 20 款（按 Modrinth 下载量降序）

| # | 包 | 版本 | 下载量 | 规模 | 血统 | 许可口径 |
|---|---|---|---|---|---|---|
| 1 | AstraLex | 93.0 | 5,284,121 | 359 文件 / 20,865 行 | BSL 8/10 系分支 | BSL 系 |
| 2 | Pastel Shaders | 1.200 | 5,030,977 | 240 文件 / 10,530 行 | BSL→Insanity→Pastel（实为 Insanity 子集） | BSL 系 |
| 3 | VanillAA | 1.3 | 3,404,145 | 24 文件 / 719 行 | 原版复刻 + BSL TAA + Chocapic 抖动 | 混合 |
| 4 | Potato Shaders | 1.0d | 3,025,817 | 174 文件 / 8,533 行 | RRe36 自研 | 保留所有权利，思路级 |
| 5 | I Like Vanilla | v1.5.0 | 2,462,312 | 384 文件 / 22,912 行 | 自研延迟管线 | What42 2.2（可条件复用，需致谢） |
| 6 | Noble Shaders | 1.9.9 | 2,306,024 | 466 文件 / 15,463 行 | 自研（Belmu），吸收 Photon/Spectrum 思路 | GPLv3 |
| 7 | Bloop Shaders | 1.8.0-Alpha-3 | 1,844,718 | 416 文件 / 23,285 行 | Bliss 血统（LPV/voxel 同构） | Bliss 系 |
| 8 | RenderPearl | 2.8.0-beta.4 | 1,366,571 | 369 文件 / 6,167 行 | 自研 compute/SSBO 架构 | pack.json 未附正文 |
| 9 | Fantasy Shaders Reimagined | 1.1 | 1,341,400 | 344 文件 / 19,483 行 | Complementary Reimagined r5.5.1 续作 | Complementary License 1.5（修改版），思路级 |
| 10 | Arc Shader | 0.15.2 | 948,384 | 340 文件 / 17,181 行 | null511 自研延迟 | MIT（可代码级借鉴） |
| 11 | Pegasus Shaders | 0.8.1 | 862,733 | 365 文件 / 30,196 行 | shaderLABS Shadow-Tutorial 模板 | 保留所有权利，思路级 |
| 12 | Pixel Perfect | 1.5.2 | 815,627 | 468 文件 / 6,991 行 | 自研（Hosek-Wilkie 天空 + LUT） | LGPLv3 |
| 13 | Builder's QOL Shaders | 2.11.0 | 698,621 | 142 文件 / 12,949 行 | OptiFine 时代自研 | 无正式 LICENSE，思路级 |
| 14 | ReShaded | 1.4.2 | 635,808 | 8 文件 / 763 行 | **非 Iris 光影**（核心着色器替换滤镜） | 不适用 |
| 15 | Soft Voxels Lite | 2.0 | 585,143 | 304 文件 / 20,061 行 | RRe36 血统 PT + Superscalar 体素 | 文件头版权，思路级 |
| 16 | LIGHT Shaders | 1.8.0 | 535,908 | 80 文件 / 12,835 行 | Chocapic13 分支 | Chocapic13 许可 |
| 17 | Simply Upscaled | 0.4.5 | 440,733 | 171 文件 / 11,640 行 | Shadow-Tutorial 模板 | ARR，明文禁 snippet，思路级 |
| 18 | Exposa Shaders | 5 | 439,585 | 248 文件 / 7,422 行 | 自研（借 bloop/Spectrum 噪声与 Chocapic LOD 思路） | 无许可文件，默认 ARR，思路级 |
| 19 | Vanilletix | 1.2.0 | 369,182 | 297 文件 / 12,340 行 | Super Duper Vanilla 同源（代码头 SDV v1.3.6） | SDV 系 |
| 20 | YoFPS | 1.0-high | 196,765 | 24 文件 / 2,118 行 | Chocapic13 低配分支（基线近 V4） | Chocapic13 许可 |

说明：YoFPS 下载量虽低，但它是本轮唯一明确以「极致性能调优」为卖点的 Chocapic 系分支，按用户「性能优化做到最好」标准破格入选；其结论主要是反面印证（见 2.4）。
规模口径：文件数按该包 `shaders/` 树计（fantasy/pegasus 两行为全目录口径，含资源与备份，与纯 shader 树差 ±5）；行数为纯代码文件口径（.glsl/.fsh/.vsh/.csh），vanillaa/yofps/simply-upscaled 三行为含 properties 的口径。

### 1.2 排除规则与被排除对象

- **已研究过（上轮 42 款 + 根目录 4 zip）**：complementary-reimagined/unbound、bsl(-classic)、photon、bliss、rethinking-voxels、makeup-ultra-fast、mellow、miniature、nostalgia、kappa、insanity、super-duper-vanilla、hysteria、fastpbr、ebin、shrimple、sildurs 两款、vanilla-plus、solas、alpha-piscium、amethyst、bvs、clarity、drdestens、eclipse、glimmer、kuda、lumina、lux、musk-rose、pyvtron、redhat、reverie、spring、tea、ushader、voyager、refrax、steadfast。
- **同引擎直系分支（避免与已研究包重复）**：spooklementary（Complementary edit）、auroras-shaders（自述基于 Complementary Unbound）、allium（Complementary edit）、opal（自述基于 BSL）、lite-shaders（MakeUp edit）、fantasy-shader-unbound（fantasy 变体）、mello（Mellow 变体）。
- **整活/滤镜向**：body-camera、cursed-fog、ctrvcr、mc-vhs、spooky-flashlight、motion-blur-fx、night-vision、retrovision、dirt-rt、emissive-trims、pixelcraft、simple-saturation、ch-motion 等。
- **非脚本渠道可得**：SEUS Renewed、Continuum、Chocapic13 官方站版本（需手工渠道；Chocapic13 V6 Lite 已在上轮覆盖，KUDA 已在 batch2 覆盖）。
- 代位说明：simply-upscaled 首次元数据请求瞬时失败，重试成功，未动用备选 just-colored-lighting。
- 与 `_analysis` 历史抓取的关系：本批 20 款中 16 款曾出现在 INDEX-batch2.md 的历史抓取清单（部分躺在 `_analysis/low-end-*` 目录），但均未做过逐包性能调研；按「上轮 42 款未研究」口径入选，特此披露（2026-10-03 审查补充）。

### 1.3 调研中查明的血统修正

- **re-shaded 不是 Iris 光影包**：无 shaders.properties/gbuffers/shadow，仅核心着色器替换 + 原版 post 链覆盖 + Sodium 覆盖；「无 mod 或 FPS 损失」的真实含义是不新增任何 pass。只保留 1 条思路级借鉴点（SSAO 距离截止）。
- **pastel 实为 Insanity 子集**：240 文件中仅 16 个有代码差异（颜色默认、云参数、三色主题档位），并回退了 Insanity 的 darknessFactor 覆盖；其技术结论以 Insanity 旧报告为基准只报增量。
- **vanilletix 与 super-duper-vanilla 同源**，只报 SDV 清单之外的增量。
- **astralex 为 BSL 分支**，本调研只报相对 BSL 的增量（对照 `reference_shaderpacks/bsl-shaders/` 与旧报告 `shader_research/bsl-shaders.md`）。

## 二、跨包汇总：经去重确认 Astra 未实现的新颖借鉴点

去重口径：每条均先对 `Astra/shaders` 做多关键词 grep（考虑不同命名），并与 10-02 采用方案文档、README 采用史、上轮两份 SUMMARY 对照后确认「Astra 无等价实现」。迁移代价为调研代理的源码级评估。

### 2.1 A 组：低代价、可直接排期

| 借鉴点 | 机制 | 来源 file:line | 代价 | Astra 侧证据（未实现） |
|---|---|---|---|---|
| 植被风天光幅度调制（距离 LOD 部分已实现） | 幅度乘 `sqr(lightmap.y)*0.9+0.1`，阴影中的植被不再摆动 | potato-shaders/gbuffers_main.vsh:84-91 | 低 | 距离门控已由本分支工作树实现：wind.glsl:233-256 `astra_foliage_wind_lod()`（128..192 格淡出后跳过位移求值，与 Potato 同源）；本行仅保留天光幅度调制——lit.vsh/shadow.vsh 调用点未按 lightmap 调幅（2026-10-03 审查更正） |
| 云入口零可见度早退 | 失明或夜间满雨无闪电时，天空像素不进云步进 | builders-qol-shaders/drawClouds.glsl:31 | 低 | Astra 只在着色末端乘 pow2(1-blindness)（clouds_planar.glsl:381），入口无 blindness/满雨判断 |
| Iris 管线级开关 | backFace 四类=false、underwaterOverlay=false、vignette=false，省背面光栅化与两个原版全屏 pass | pixel-perfect-shaders/shaders.properties:4,7,12-15；vanilletix/shaders.properties:208-216 | 低 | Astra properties 无这些键（大小写敏感 0 命中）；需先确认自绘暗角/水下叠加已完整 |
| 体积光取数门控 | 水下 4 / 空气 6 次固定采样；天空像素跳过阴影比较；仅「透明遮挡≠不透明且水面」才读 shadowcolor0 | exposa-shaders/lib/vl.glsl:29,111-123 | 低 | 可直接嵌入 volume_fog；Astra 每步无条件读彩色阴影 |
| 阴影投射顶点级剔除 | 材质位/entityId 命中即 `gl_Position=vec4(1)` 退化，树叶/实体不投影时省 shadow pass 光栅化 | i-like-vanilla/program/shadow.glsl:89-111；arc-shader/program/shadow.gsh:104-128 | 低 | Astra 仅玻璃一处固定跳过（shadow.vsh:93,99-107）+ 整体实体投影开关（性能档关闭），无树叶/实体成组的材质级剔除 |
| SSAO 距离截止 | 15 格外不算 AO，接触遮蔽远距本不可见 | re-shaded/post/transparency.fsh:34-35,83 | 低 | Astra ssao.fsh 无距离门控，12 样本对远处像素照跑 |
| 阴影采样数按视距升档 | 近 10 格 6/12 次、其外 2/6 次；实体/手再×2 | fantasy-shaders/lib/lighting/shadowSampling.glsl:46-64 | 低 | Astra 为全局统一 4/8/16 角点核，grep `shadowSamples|SHADOW_TAPS` 0 命中 |
| 单像素聚合 + 纹理广播 | 每帧一次的太阳可见度 13×13 深度采样只算 1 像素，其余像素固定 uv 读回；SALS 探针按帧时间节流 | light-shaders/composite.fsh:423-436 + final.fsh:329；fantasy-shaders/lib/atmospherics/volumetricLight.glsl:242-283 | 低 | Astra colortex10 1×1 缓冲现成；grep `SALS|sceneIntensity` 0 命中 |
| R2 黄金比例低差异序列 | 两次 fract 得每帧去相关抖动，可复现 | soft-voxels-lite/PTLight.fsh:312-345 | 低 | 可替换 godrays 的 Bayer8 起始抖动 |
| 体素更新速度档 + 写入抑制 | 按档停 prepare compute；新值与目标差 <0.5/255 跳过 imageStore | pegasus/shaders.properties:485-512；voxel_photons.csh:224-248 | 低 | Astra nether_light.csh 固定 9 次 dispatch、每步无条件写两套 image3D |
| 反射历史按贡献条件写入 | 无反射材质 writeFactor=0，跳过历史读改写 | fantasy-shaders/program/deferred1.glsl:293-302,509-511 | 低 | Astra 水反射历史（colortex28/temporal 链）无写入门 |
| 强度阈值门控写法 | rainStrength/fading/sunvisibility 不达阈值不进昂贵分支 | light-shaders/final.fsh:271-290,327-380 | 低 | 可补充 Astra 雨/光束可选路径 |
| sRGB 多项式免 pow | toLinear/toSRGB 用多项式与 x(2-x) 近似 | vanilletix/lib/utility/common.glsl:192-197 | 低 | encoding.glsl:16-22 仍用 pow(2.4/1/2.4) |
| 折射目标材质一致性回退 | 折射偏移后校验目标像素材质 ID，不一致回退中心 | builders-qol-shaders/composite1.fsh:266-274 | 低 | Astra 仅深度范围校验（refraction.glsl:24），跨材质近深度处会取错 |
| ISOLATE_RENDER_STAGE 调试档 | 逐渲染阶段隔离显示，便于逐 pass 计时 | pixel-perfect-shaders/common_defs.glsl:513 | 低 | Astra 正处测量期，可直接复用思路 |
| 雨几何云层以上剔除 | 雨条在云层以上 discard，云上部分不再走完整光照管线 | builders-qol-shaders/gbuffers_weather.fsh:24-26 | 低-中 | Astra 雨条走 lit.fsh 完整管线；需确认云上飞行的行为预期 |

### 2.2 B 组：中代价、需小规模接线

| 借鉴点 | 机制 | 来源 file:line | 代价 | Astra 侧证据 |
|---|---|---|---|---|
| 波高/焦散预计算图 | 每帧一张 256²/512² 预计算图 + mip，替代逐水面像素的多倍频噪声求导 | bloop-shaders/program/waternormals.fsh:161-168、lib/water/waterfuncs2.glsl:200-228、shaders.properties:129-133 | 中 | Astra 水面法线逐像素解析（surface.glsl:224-267）；grep 无预计算缓冲 |
| TAA gather 化 + TAA_FAST 低档 | 3×3 邻域 3 次 textureGatherOffset 替代 9 次 texelFetch；低配 1 次双线性历史 | bloop-shaders/program/taa.fsh:89-126,212-262 | 低-中 | Astra taa_resolve.fsh:88-130 仍为两次 3×3 texelFetch 循环 |
| 曝光链低档化（三选一） | 零 pass：eyeBrightnessSmooth+CPU 平滑直给 uniform（potato shaders.properties:156-161）；场景 mip 单次采样（astralex composite11.glsl:107-112）；顶点直方图（noble history_avg_luminance.glsl:52-80） | 见左 | 中 | Astra 现为 exposure.fsh 64-tap 测光 + 1×1 RGBA32F 历史；三方案均需 A/B 画质 |
| 焦散按阴影 texel 烘焙 | shadow pass 按阴影图 texel 烘 R16F shadowcolor1，水/雾全屏查表 | noble/programs/gbuffers/shadow.glsl:116-128；i-like-vanilla/program/shadow.glsl:25-51（shadowcolor0 魔数，同向二选一） | 中 | Astra 解析焦散（water/caustics.glsl）；grep `shadowcolor1` 0 命中 |
| 遮挡深度自适应半影 + 像素锁定阴影 | 半影半径 ∝ 首采样遮挡深度；查询点量化到世界网格 + 法线偏移，低分辨率不闪 | simply-upscaled/shadows.glsl:77,133-165；main_f.glsl:220-241 | 低-中 | Astra 无 blocker/penumbra（grep 0 命中）；角点核固定 |
| 低分天空背景复用 | colortex6 按 1/2-1/10 缩放装天空+云，显示混合、反射、重投影共用并开 mip | pegasus/shaders.properties:286-301、composite1.fsh:214、composite10.fsh:471 | 中 | Astra 主世界天空仍逐像素解析（deferred.fsh:305,335），仅末地有低分缓冲 |
| 反射降分辨率 + 时域重投影 + 大 stride | 反射 compute 按 0.25/0.5/0.75 分辨率，stride 16-64px，深度/速度/像素中心加权重投影 | noble/programs/composite/reflections_write.glsl:67-72,161-205 | 中 | Astra global/water/temporal.glsl 标 RETIRED 未接线，可挂载 |
| 上一帧重投影 SSR | 1/4 分辨率 prev HDR+深度，粗糙度→mip LOD 取代部分角点模糊 | arc-shader/lib/lighting/pbr.glsl:327-345、composite2.fsh:76-97 | 中 | Astra raytrace 用当前帧深度（raytrace.glsl:51）；grep prevDepth 0 命中 |
| 噪声效果共享通道 + 单次重投影 | sunrays/云共用一个 RG16 通道与一次时域重建，关闭时不写该目标 | i-like-vanilla/program/composite1.glsl:123-141,241-255 | 中 | Astra godrays/体积雾各自历史；grep `noisy` 仅注释 |
| 云方向光辅助采样降档 | 方向光辅助采样用少一层噪声的简化版，主采样不变 | i-like-vanilla/lib/vol_clouds.glsl:25,88 | 低 | clouds_planar 为首次命中模型，无辅助采样概念 |
| 云采样后半段透视重分布 | 后半采样沿 raydir/raydir.y 重新分布，远端间距随距离增大 | pegasus/stuff/fluids/clouds7.glsl:490-505,695-698 | 低 | Astra 平面云为等距步进 |
| SSR 渲染比率 + 顶点视口缩放 | 反射独立渲染比率 0.1-1.0，VSH 把全屏四边形缩进视口，消费端按比率取样 | i-like-vanilla/program/composite3.glsl:103-108、composite4.glsl:46 | 低-中 | Astra 无 render_scale 机制（grep 0 命中） |
| 体素光半速率更新 + 背向跳过 + 乒乓 | 沿 x 分半隔帧算一半、另一半拷贝；玩家背向体素沿用上帧；双 volume 按帧奇偶乒乓 | fantasy-shaders/program/shadowcomp.glsl:74-131 | 中 | Astra 下界 64³ 每帧 9 次 dispatch、无历史（nether_light.csh:1-6） |
| TAA Catmull-Rom 双采样 | 相同历史比例下更锐，间接支持更高混合权重 | exposa-shaders/prog/taa.glsl:48-54 | 中 | Astra taa_resolve 为双线性+相位对齐；grep `catmull|bicubic` 0 命中 |
| CAS 式亮度自适应锐化 | 3×3 软 min/max 振幅、窗口权重、亮度越低混合越强 | light-shaders/final.fsh:214-252 | 低 | 可作 TAA/FXAA 后可选细节恢复 |
| 帧级照明度 SSBO | 直射+SH9+均匀天空 1 工作组 compute 写 SSBO；反射 compute 内 1 线程预取共享 8×8 组 | noble/programs/prepare/illuminance_write.glsl:37-43、reflections_write.glsl:77-86 | 低-中 | 需 compute/SSBO；Astra 主世界无 SSBO（仅下界体素用 image3D） |
| 大气低分辨率 LUT | 大气写成 0.10-0.95 独立分辨率 LUT，透射/散射步数 8-32 | noble/settings.glsl:271-276、shaders.properties:382-417 | 中-高 | Astra 已有 256×128 同帧环境缓存（colortex11），增量收益有限，需评估 |

### 2.3 C 组：大工程、战略级选项

| 借鉴点 | 机制 | 来源 file:line | 代价 | 说明 |
|---|---|---|---|---|
| TAAU 全局渲染缩放 | 25-100% 渲染比率：全部 VSH 缩放 gl_Position、低分 pass 越界早退、TAA 升采样；Soft Voxels 为 0.75 + 3×3 min/max prepass + 4×4 Lanczos | noble/include/taau_scale.glsl:21-39；soft-voxels-lite/taauPrepass.fsh:72-126、temporal.fsh:308-360；i-like-vanilla 同型 | 高 | 唯一整帧平方级削减着色像素数的杠杆；需全链坐标/历史/后处理契约重写 |
| 4 级 CSM 打包单图 | 四 cascade tile 进一张阴影图，几何着色器只对相交 cascade 发射图元；每级 PCF 采样 4/3/2/1 递减；逐视锥切片拟合投影 | arc-shader/lib/shadows/csm.glsl:1,22-29,81-107、csm_render.glsl:2,100-113、program/shadow.gsh:118-146 | 高 | 近处 texel 密度与远处采样数解耦；Astra 单图 112 格为均匀预算 |
| SSBO 点光分箱 | 原子掩码去重 + 邻居格传播 + 逐格 list，像素端按 range 早退 | arc-shader/lib/ssbo/lighting.glsl:59-102,136-149 | 高 | 多光源彩光的可扩展路径；Astra 无 SSBO |
| VL 1spp + 工作组共享重建 | 每像素 1 次随机步进 + 工作组 shared 3×3 平均（5/6/5 打包、边界重算） | renderpearl/world_default/composite.csh:59-168、lib/nbh/border_cornered.glsl | 高 | 把每像素约 12 次步进/阴影查询降到 1 次 + 8 次共享读取；依赖 compute/LDS，接受噪点 |
| 16 位类型 + 供应商能力分档 | f16/i16/u8 打包 + NV/AMD 扩展回退宏，云历史/VL/后处理缓冲带宽减半 | renderpearl/prelude/compat.glsl:14-153、config.glsl:108-117 | 中-高 | Astra 全 0 命中 float16_t/subgroup；不支持的驱动自动降级 |
| GBuffer uvec4 属性打包 | 四属性打包 RGBA32UI（16bit 法线、光图+AO、材质），减目标数与取数 | exposa-shaders/lib/sampling.glsl:91-214、lib/buffer_info.glsl:1-15 | 高 | Astra 已有 R11F/RGBA8 压缩（surface_buffers.glsl:14-28），增量有限，列为观察 |
| 体素太阳 GI + 双缓冲 + 写抑制 | 从 shadowmap 采日照写入体素，方向权重/泄漏抑制；帧奇偶双缓冲 | pegasus/shaders/gi.glsl:8-28、voxel_photons.csh:105-126 | 高 | 功能扩展（默认关），非性能必需；Astra 体素无日照通道 |
| 单 pass mip 打包 Bloom | 8 级 mip 共用 1 个全分辨率缓冲、按有效屏幕区域整块裁剪循环、coord/2^m 读回 | potato-shaders/bloom.fsh:38-79、grading.fsh:67-81 | 高 | Astra 已是 0.25 捕获 + 2 pass + 4 级 mip，替换收益需实测 |

### 2.4 反面印证（明确不建议做）

- **YoFPS 的单 pass 合并**：把光照/天空/云/雾/反射/色调映射全部内联进 final.fsh 换取低开销——机制层面已被 Astra 的分档与阶段启停覆盖，Astra 不应为低配档新增单 pass 合并（yofps/final.fsh:573-617）。
- **AstraLex 的 DOWNSCALE/DITHERING_SCREEN**：只在 final 取更疏网格，不减少任何计算（program/final.glsl:433-434,468-478）。
- **Pastel 相对 Insanity 是回退**（代码差异仅 16 文件），无独立性能价值。
- **RenderPearl 光表分帧摊销**：O(n²) 去重 + SSBO 架构与 Astra 不匹配，不迁移（composite3_b.csh:43-163）。
- **ReShaded 的成对 ±offset 32 样本 AO**：比 Astra 现有 12 样本更贵，价值为负。
- **Potato 的调度弱点示例**：taaEnabled 关闭时 composite3 仍整帧写两份——低配路径要有对应的资源缩编，Astra 已有此纪律。

### 2.5 Astra 已覆盖的常见手段（本轮被反复排除，用于确认无需重复建设）

1. 帧不变量移交 CPU（≥10 款同型，含顶点级平替——BQOL/LIGHT/YoFPS 的 vsh 平替是 CPU 移交的低配版）。
2. program/阶段启停 + size.buffer 分档 + 关闭时资源缩编（Pegasus/Noble/Bloop/Exposa 同型）。
3. 云步数档、首次命中、透射中断、空区跳过、距离 break（Potato/Vanilletix/Exposa/Bloop 同型）。
4. Bloom mip 链与 tap 分档、零强度停调度。
5. SSR 有限步进 + 二分细化 + 出屏退出 + 置信度（Vanilletix/Arc 同型；本轮新角度只剩「上一帧重投影」「渲染比率」「按贡献写历史」三条，均已列入 A/B 组）。
6. TAA YCoCg 邻域钳制、植被运动历史、抖动 CPU 化（差在 gather 化与 Catmull-Rom，见 B 组）。
7. 阴影小核分档、coverage 早退、背光跳过、彩色阴影仅在遮挡时读（差在「按视距升档」「顶点级投射剔除」「自适应半影」，均已列入）。
8. 雨量门槛、雨溅落粒子颜色过滤、解析天空反射回退、维度独立程序、半分辨率 AO/VL/雾 + 保边重建。
9. 编译期材质特化（Potato 用 #define 特化 gbuffers；Astra 以模块化 + 死代码裁减达成同类效果）。

## 三、逐包调研（20 款）

### 3.1 AstraLex 93.0（BSL 分支，只报相对 BSL 增量）

- 定位：BSL 8/10 系大幅外观扩展（真实云、行星/星云、极光、星座、Kuwahara、热浪折射、屏幕雨滴），非性能向重构。359 文件 / 20,865 行。
- 管线：与 BSL 同构 composite0-14 全屏链，`program.*.enabled` 门控（shaders.properties:470-504）；**全包无独立分辨率缓冲**（仅 renderResMul=1.0）。
- 增量技术：速度/冲刺/雨强/群系标量全部下沉 properties smooth()（:623-688）；真实云固定 9 步 + 仰角门控 + 不透明度饱和早退，且按用途分预算（天空 10 步/反射 4 步，ovclouds.glsl:67-70,143、gbuffers_skybasic.glsl:271）；星座最近邻分桶（shiningstars.glsl:59-131）；POM 显式梯度 + 分层早退（parallax.glsl:14-33,66-75）；TAA 开启时彩色阴影 4 个随帧旋转样本替代 9 点十字（shadows.glsl:98-121）；自动曝光改读场景色 mip 单次抓取（composite11.glsl:107-112）。
- 去重排除：旋转阴影核（Astra 显式拒绝，diffuse.glsl:271-273）、水下焦散 4 采样（Astra 解析焦散）、云门控/早退、阴影出图早退、shadow.culling（Astra 必须 false，shaders.properties:280-282）、program 门控。
- 新颖借鉴点：星座分桶（高代价 niche）；场景 mip 单次曝光采样（中，需 mip 链生成成本对比）；POM 显式梯度组合（低，仅未来启用 POM 时）。

### 3.2 Pastel Shaders 1.200（Insanity 子集，只报增量）

- 定位：BSL→Insanity→Pastel；240 文件中仅 16 个与 Insanity 有代码差异（颜色默认、云参数、三色主题档位），并回退 darknessFactor 覆盖。240 文件 / 10,530 行。
- 增量技术：同预算下逐 tap 弯曲深度偏置（biasDistribution+IGN）做阴影软度分层（lib/lighting/shadows.glsl:47-54,73-96）；RETRO_FILTER 一并 #undef TAA/FXAA 并门控 composite6/7（shaders.properties:124-129）。
- 去重排除：9-tap 十字/SHADOW_PIXEL/BloomTile/7 步 exp2 体积光（BSL 旧报告已述）；coloring 独立通道（Astra 已完成画质/颜色分离）；sun.enabled 停原版日月（Astra 程序化日月画在原版 quad 上，不适用）。
- 新颖借鉴点：弯曲偏置阴影软度分层（低——需先确认与 Astra 角点配对核不冲突）。

### 3.3 VanillAA 1.3

- 定位：原版渲染 + TAA（血统 XorDev 复刻 + BSL TAA + Chocapic 抖动 + AMD CAS）。24 文件 / 719 行，无 shadow/deferred/water 程序。
- 技术：TAA 不单开 pass、历史原地保留（colortex2Clear=false）无 ping-pong；framemod8 CPU 算好当下标；历史为黑直接返回；缓冲格式极简；地形光照顶点完成；雾复用原版 gl_Fog；锐化 SHARPENING==0 编译期空函数。
- 去重：TAA 抖动 CPU 化、8 邻域钳制、出屏拒绝——Astra 全部已实现且更强。
- 新颖借鉴点：仅 1 条——重投影摄影机位移的深度门控（taa.glsl:15，低，需 A/B）。**结论：无高价值新借鉴点，其价值在「不做」。**

### 3.4 Potato Shaders 1.0d

- 定位：RRe36 轻量包，无阴影图/体积云/SSR。174 文件 / 8,533 行，三维度同构。
- 管线：光照在 gbuffer 前向算完，deferred 只做 AO；固定约 9 个全屏 pass；质量全靠编译期 define。
- 技术：gbuffers_main.fsh 用 #define 特化 terrain/water/entities/hand；场景色 /4 压缩 + 16F + bloom x^4 展开；天空全解析一次 getSky 供天空/雾/云/假反射；云用原版几何 + 解析 Mie；风 192 格距离门控 + 天光幅度；AO 4 步双深度 + 蓝噪声；水面 3 次有限差分 + 步长/波幅随距离；反射完全解析（天空+GGX 太阳高光）；折射 9 tap 深度感知高斯；Bloom 单 pass 8 级 mip 按有效区域裁剪；运动模糊随机提前终止；DoF 按 CoC 选 LOD；曝光零 pass（eyeBrightnessSmooth+CPU smooth）。
- 去重排除：CPU 帧不变量（Astra 更全）、蓝噪声、水面距离 LOD、octahedral/材质位、云像素材质分流、反射回退乘 skylight。
- 新颖借鉴点：植被风天光幅度调制（低——距离 LOD 部分本分支已实现，见 2.1 注）；曝光零 pass（中）；累积循环随机提前终止（中，可套体积雾/SSR）；单 pass mip 打包 Bloom（高，C 组）；场景色 /4 压缩（低）。

### 3.5 I Like Vanilla v1.5.0

- 定位：改进原版风格（4 种 STYLE），延迟管线；What42 2.2 许可（可条件复用需致谢）。384 文件 / 22,912 行。
- 管线：shadow/shadowcomp 仅在特定阴影模式或 COLORED_LIGHTING 时启用（shaders.properties:316-343）；bloom/SSS/Panini 各自条件启停。
- 技术：写目标按需切换（无噪声效果只写 colortex0，composite1.glsl:241-255）；噪声效果共享 RG16 通道 + 单次重投影 + 5-tap 空间滤波；反射独立渲染比率 0.1-1.0 + 顶点视口缩放；SSR 循环外裁剪步向量到屏幕边界 + 连续 5 次命中折半收敛；体积云步数即质量档（2-128）；深度光柱低档沿光源屏幕坐标采样；阴影投射顶点级剔除（材质位）；焦散/彩影编码成 shadowcolor0 魔数；bloom 取 colortex0 硬件 mip + 逐级缩小视口；POTATO→UNPLAYABLE 六档全联动。
- 去重排除：bloom mip（已有）、深度光柱（上轮 MakeUp 同类已列）、条件启停/材质位打包/Catmull-Rom TAA（已有或已知候选）。
- 新颖借鉴点：SSR 渲染比率（低-中）、噪声共享通道（中）、顶点级阴影剔除（低）、云方向光降档（低）、焦散 shadowcolor0 魔数（中，与 Noble 烘焙二选一）。

### 3.6 Noble Shaders 1.9.9

- 定位：Belmu 自研延迟包，GPLv3；吸收 Photon AO 切片/Spectrum 天体向量思路。466 文件 / 15,463 行。
- 管线：RGBA32UI 打包 GBuffer；deferred 依次深度合并/天空 LUT/云+云图/阴影+照明度/AO；composite 反射 compute/折射雾/bloom 8+8/TAAU；功能关闭时 pass include discard.glsl 空转。
- 技术：TAAU 25-100%（VSH 缩放 + 越界早退 + TAA 升采样，taau_scale.glsl:21-39）；每帧照明度/曝光/反射预取用单工作组 compute + SSBO + 工作组共享（illuminance_write.glsl:37-43、reflections_write.glsl:77-86）；大气 0.10-0.95 独立分辨率 LUT（步数 8-32）；云两层各自预算 + 云图 0.25 烘散射 + 步数按体积距离 0.25×-1× + 2×2 邻域全天空提前返回；地面雾/空气透视双预算（4-64/2-6 步）随距离指数增长；焦散烘 R16F shadowcolor1；PCSS blocker 8 + PCF 16 + 屏深接触阴影叠加；反射 compute 0.25-0.75 分辨率 + stride 16-64px + 加权重投影 + 天空回退直查云图；bloom 8+8 共用 colortex5；折射 Newton 迭代可提前结束。
- 去重排除：云图/云历史/云影缓存、自适应体积雾、AO 半分辨重建、mip bloom、软硬阴影比较、PCSS/TAA 邻域夹取（已知候选）。
- 新颖借鉴点：TAAU（高，C 组）；反射降分辨率+时域重投影（中，可接线 RETIRED 模块）；焦散烘焙（中）；大气 LUT（中-高）；照明度 SSBO（低-中）；顶点直方图曝光（低）。

### 3.7 Bloop Shaders 1.8.0-Alpha-3

- 定位：Bliss 血统（LPV/voxel 同构），「追求最高速度」；416 文件 / 23,285 行。
- 管线：prepare×3 → shadow → shadowcomp(LPV) → deferred(云) → deferred10(光照) → deferred20(SSR) → composite(雾/半透明/VL) → TAA → Bloom；阶段启停全在 properties；colortex6=0.25²、colortex8 随云质量、colortex7 随 HQ_WATER。
- 技术：云步数按仰角 `maxIT/sqrt(view.y)`、雾能见度 <1% 整段返回纯雾、透射 <1e-4 退出、逐步增量梯度免 mix（clouds_bloop.glsl:99-161）；云影固定 6 步；每帧波高/焦散预计算进 colortex7 并开 mip（waternormals.fsh:161-168）；天空/云底 LUT 重投影复用上帧 alpha（skymain.fsh:16-41）；PCF 前范围/背光门控 + 单采样/6-tap 两档；RSM GI 4 步黄金角 + shadowcolor mip LOD；TAA 4×4 双三次 vs TAA_FAST 单次双线性、3×3 最小深度用 textureGatherOffset（Intel 回退 9 次 texelFetch）；Bloom 1/4 缓冲 + 5-tap 六角模糊 + 噪声抖动方向。
- 去重排除：阴影小核分档/gather 早退、云距离分档/首命中、Bloom 分档+mip、云/天空历史（Astra 已有）；LPV/RTAO/SSR 属特性继承。
- 新颖借鉴点：波高/焦散预计算图（中，B 组首选）；TAA gather 化+TAA_FAST（低-中）；云整段可见度剔除（低）。注意：fog_translucent_lowres.vsh 与 RENDER_SCALE_X/Y 无调用点（死代码或外部选项，无法判定）。

### 3.8 RenderPearl 2.8.0-beta.4

- 定位：自研 compute/SSBO 架构，「现代硬件高性能」；369 文件 / 6,167 行。
- 管线：几乎所有全屏 pass 都是 compute + imageStore；SSBO bufferObject 尺寸随档位编译期切换。
- 技术：compute + 工作组包围盒 + LDS 光表 + subgroup 归约；f16/i16/u8 + 供应商扩展回退宏（compat.glsl:14-153）；顶点打包 octa 法线/11-11-10 色；光表分帧摊销（CPU frameCounter%LL_RATE 控制收集/去重/排序，顶点每面一次收集 + 距离哈希 LOD 剔除）；阴影先读 shadowtex1 硬件 PCF、solid_vis==0 不读透明/彩色、SM_DIST=0 时 shadow.fsh 空 main；VL 每像素 1 次随机步进 + 工作组 shared 3×3 平均（composite.csh:59-168）；自动曝光 atomicAdd log2 亮度到 8B SSBO；SMAA/CAS 全 compute；48³ 3D LUT 色调映射。
- 去重排除：阴影早退/距离淡出、自动曝光、BRDF 面朝向门、半分辨率 VL+保边重建（Astra 已有）；SMAA/CAS/TMMF/Colorwheel 属特性。
- 新颖借鉴点：16 位类型+能力分档（中-高，C 组）；VL 1spp+shared 重建（高，C 组）；工作组成员级 early-cull 范式（高，仅未来引入光表时）。光表分帧摊销判定为架构不匹配，不迁移。

### 3.9 Fantasy Shaders Reimagined 1.1

- 定位：Complementary Reimagined r5.5.1 血统续作（Complementary License 1.5 修改版，只能思路级借鉴）；344 文件 / 19,483 行。
- 技术：体素彩光半速率更新（沿 x 分半隔帧）+ 玩家背向体素跳过沿用上帧 + 双 volume 乒乓（shadowcomp.glsl:74-131）；近身粒子抖动 discard 削 overdraw；阴影滤波采样按视距升档（近 10 格 6/12，其外 2/6；实体/手×2）；反射指数步进 + 命中后 ≤6 细化 + roughness²×距离选 mip；反射历史按需写入（writeFactor=0）；VL 步数按强度取档；SALS 单像素节流探针求全局光柱强度。
- 去重排除：云/雾沿用 CR（上轮已述）；SSAO 低预算、CPU 帧不变量、profile 与颜色分离（Astra 已有）。
- 新颖借鉴点：体素半速率+背向跳过（中，下界直接适用）；阴影按视距升档（低）；反射历史条件写入（低）；VL 强度取档（低）；SALS 探针（低）；粒子抖动剔除（低，默认关）。

### 3.10 Arc Shader 0.15.2

- 定位：null511 自研真延迟包，MIT（可代码级借鉴）；340 文件 / 17,181 行。
- 管线：RGBA32UI GBuffer；prepare1/2 每帧产 256² 天空 LUT 与 32×16 辐照度 LUT；SSBO 光箱仅彩光开启时注册。
- 技术：4 级 CSM 打包单张阴影图 + 几何着色器按 cascade 相交发射 + 每级 PCF 4/3/2/1 递减 + 逐视锥切片拟合投影（csm.glsl、csm_render.glsl、shadow.gsh:118-146）；caster 剔除（树叶/实体/水下背面，shadow.gsh:104-128）；RENDERTARGETS 按开关裁剪输出（deferred4.fsh:57-74）；屏幕空间接触阴影（Bayer 起点、样本 24→64 随视距）；SSBO 点光分箱（原子去重+邻居传播+逐格 list）；VL 的 cascade clip 起点/步长循环外提 + 云遮挡距离终止 + 末样本抖动置 0；SSR 走上一帧 1/4 重投影 + 粗糙度→mip + 粗步进三档；Bloom 角点图集只让图集内像素工作；曝光 log 亮度存上帧 1/4 缓冲、明暗适应速度分离；水下模糊顶点退化跳过；AO/SSGI 采上帧 1/4 深度与 HDR。
- 去重排除：GBuffer 带宽压缩（Astra 已有）、Bloom mip 链、256×128 环境缓存+SH9、体积光光源矩阵外提（已有）；上帧深度 AO 与 Astra 当前帧取向冲突，不建议。
- 新颖借鉴点：阴影 caster 材质剔除（低，A 组）；VL cascade 外提+云遮挡终止（低）；上帧重投影 SSR（中，B 组）；CSM 打包（高，C 组）；接触阴影（中，可低档保贴地细节）；SSBO 光箱（高，C 组）。注意：SSR_HIZ 声明了依赖但未见 mip 声明，疑似未完成。

### 3.11 Pegasus Shaders 0.8.1

- 定位：Shadow-Tutorial 模板，「高性能+风格范围」；保留所有权利，思路级。365 文件 / 30,196 行（含备份冗余）。
- 技术：colortex6 低分天空+云背景（1/2-1/10）供显示/反射/重投影并开 mip；离屏反射缓冲 0.1-1.0 质量缩放、0 时整段停用；AA 折入 Bloom 第一通道、Bloom 直采 colortex0 mip 无中间目标；全部 gbuffers blend=off 省写带宽；云分层独立采样/光照预算 + alpha≥0.99 退出 + 后半段透视重分布 + 遮光按层顶距离截断；天空反射跨帧重投影越界回退；体素泛洪 R32UI+RGBA8、6 邻域 max、帧奇偶双缓冲、写入抑制阈值；体素太阳 GI（方向权重/泄漏抑制）；体素更新速度档停 compute；阴影 4 角双线性重建 + 核半径随深度差缩放；SSR 强度门控 + pow(i/N,4) 步进 + ray_lod mip 近似粗糙；AO 7/22 步螺旋 + 深度 LOD。
- 去重排除：云独立分辨率/步数、Bloom 分档、阴影配对四角、CPU 帧不变量、天光缓存（Astra 已有）；camshift 为死代码。
- 新颖借鉴点：低分天空背景复用（中，B 组）；离屏反射质量缩放（中）；云透视重分布（低）；体素更新档+写入抑制（低，A 组）；体素太阳 GI（高，C 组观察项）。

### 3.12 Pixel Perfect 1.5.2

- 定位：原版观感增强，LGPLv3；Hosek-Wilkie 天空 + LUT。468 文件 / 6,991 行。
- 技术：backFace 四类=false、underwaterOverlay/vignette=false；DH 实体不写主色（blend=ZERO ONE）；`use_*` 按需声明 uniform 编译期裁剪；天空系数/反照率 CPU 表达式预算；雾柱形单次 exp 无步进；雨用 3D 噪声雨幕替代粒子几何；过滤模式 4/5 的纹素对齐 4 角点；像素化阴影（世界位置量化到资源包纹素网格共享偏移）；shadowcomp1 天空 texel discard + flip 保留上帧被剔除区阴影；TAA 最近邻 4 深度选速度 + YCoCg 裁切 + 可选 bicubic；Fast GI 4 向十字 + LOD8（默认关）；ISOLATE_RENDER_STAGE 调试档。
- 去重排除：阴影 pass 分项开关、配对四角、CPU 调色、LOD 均值曝光（Astra 已有）；TAA 速度缓冲 Astra 无，不适用。
- 新颖借鉴点：管线级开关组合（低，A 组）；shadowcomp1 flip 保留（中）；像素化阴影量化（低-中）；ISOLATE_RENDER_STAGE（低，测量期直接可用）；纹素对齐 4 角点（低，流畅档备选）。注意：SSAO 选项只有声明无实现（残留）；曝光 LOD100 所需 mip 未确认生成。

### 3.13 Builder's QOL Shaders 2.11.0

- 定位：OptiFine 时代轻量原版增强；无正式 LICENSE，思路级。142 文件 / 12,949 行（另有 src/ 编辑指南）。
- 技术：无阴影图无 deferred，效果压在 4 个全屏 pass；云色/云密度/手持光/眼适应顶点级预计算（composite1.vsh:89-127）；帧不变量 CPU 表达式；有理衰减 `w/(x²+w)` 替代 exp（lib/math.glsl:9-12）；效果量复用已有 alpha 通道；云入口不可见早退（drawClouds.glsl:31）+ 云平面交段门控 + alpha≤0.001 置 false 跳过后续全部混合；云噪声 4 角插值只在需要法线时算斜率、高频八度单 tap；>10000 哨兵 ID 最短路径；波动只作用草叶上半段、1/(len²+0.5) 免 sqrt；草地 patch 噪声顶点级着色；雨云层以上 discard、天空像素直接用 fogColor；水面光照推迟到 composite、CLEAR_WATER 直接 alpha=0；折射偏移后材质一致性校验回退；分离模糊 tap 数随实际半径、屏外不取；岩浆全屏覆盖后直接 return。
- 去重排除：云单 tap 圆整采样、哨兵 ID、顶点级帧量/CPU uniform（Astra 已有或已更彻底）；半径→tap 模糊 Astra 无逐像素模糊系统，不适用。
- 新颖借鉴点：云入口零可见度早退（低，A 组）；雨云上剔除（低-中，需行为确认）；有理衰减（低，需 A/B）；云色帧级化上提（中，Astra 云色约 20 次 mix/pow 可部分上提）；折射材质一致性回退（低，A 组）。

### 3.14 ReShaded 1.4.2（非 Iris 包，降级处理）

- 定位：核心着色器替换滤镜（terrain/entity/particle + 原版 post 链 + Sodium 覆盖），需核心着色器类模组；8 文件 / 763 行。
- 技术：SSAO 只在 15 格内运行、半径按深度缩放 clamp[1,30]；32 样本拆 16 次成对 ±offset；顶点级面亮度；USE_FOG 编译期开关同时移除 varying 与分支；6 层按深度插入排序单 pass 混合。
- 去重：SSAO 预算/早退 Astra 已更强；成对 ±offset 比 Astra 12 样本更贵。
- 新颖借鉴点：仅 SSAO 距离截止（低，A 组）。其余与 Iris 管线无关。

### 3.15 Soft Voxels Lite 2.0

- 定位：RRe36 血统极简 PT 包（SSPT + 体素 PT）；文件头版权，思路级。304 文件 / 20,061 行。
- 管线：全局 0.75 渲染缩放 + TAAU（3×3 min/max prepass + 4×4 Lanczos）；shadow pass 兼任体素化；shadowcomp 1-7 建占用 mip 链；deferred PT/累积/SVGF；阶段按选项表达式启停。
- 技术：低分辨率间接光 pass 用「顶点缩放+视口裁剪+默认值写出」不另建小缓冲；三层平面云步长按高度 linStep 压缩、出层 continue、零密度跳过；层级 DDA（起点直升最粗占用级、step-up/down、双 64 次上限）；块平均色 = 图集最高 mip 一次采样（textureQueryLevels-1）；接触阴影 16 步/stride 4 自适应、越界即停；SSPT 8 步屏幕空间优先、miss 才进体素 BVH、步长按出屏距离缩放；R2 黄金比例序列 + frame255 逐样本偏移；时域累积（历史 alpha=帧数、4 邻域+sqrt(depth) 拒绝、LPV 亮度代理 rejection、跳变改 7×7 空间滤波并重置）；SVGF 3×3 方差 + 双边 r=2；Bloom 7 级 bicubic + 曝光统计打包 alpha；DOF 按 CoC 门控 30/45/60 步。
- 去重排除：阶段启停/小尺寸缓冲、时域历史校验、体素/SSPT/SVGF 链（Astra 已有「不引入」决策）、平面云分档、球面板、1×1 曝光历史（已有）。
- 新颖借鉴点：方向性接触阴影（低，可补阴影图小尺度遮蔽）；TAAU（高，C 组）；R2 序列（低，A 组）；最高 mip 取块平均色（低，储备手段）。

### 3.16 LIGHT Shaders 1.8.0

- 定位：Chocapic13 分支，靠删减功能 + 自加 TAA/物理海面换高 FPS；Chocapic13 许可。80 文件 / 12,835 行。
- 技术：逐 pass 帧常量全塞进全屏 pass 顶点着色器（composite.vsh:100-311）；TAA 强门控（0.56<depth<sky 才累积、屏内才采历史、边缘自适应权重）；每维度独立程序目录编译期消除维度分支；阴影三重门控（diffuse>0.00001 且图内 |x|,|y|<0.99 才 4 tap；水面再加 NdotL 与 |center|<0.49）；7 层 2.5D 云板 totalcloud>0.999 break；太阳色 ToD[7] 小时表插值；godrays 7 次深度判天空 + 仅 illuminationDecay>0.001 执行；**太阳可见度只在 1 像素做 13×13 深度采样再广播**（composite.fsh:423-436 + final.fsh:329）；反射 16 步可变步长 + 命中回退细分；雨滴/光晕强度阈值门控；CAS 式锐化。
- 去重排除：帧常量（Astra 已 CPU 化）、TAA（已有且更强）、阴影门控（已有）、godrays 半分辨率（已有）、维度独立程序（已有）、解析反射（已有）。
- 新颖借鉴点：单像素聚合+广播（低，A 组）；CAS 式锐化（低）；强度阈值门控（低，A 组）。注意：TAA/SHARPENING 宏默认与 GUI 列表一致性无法从源码判定。

### 3.17 Simply Upscaled 0.4.5

- 定位：Shadow-Tutorial 模板原版向包，特色实时贴图放大/过滤；ARR 明文禁 snippet，思路级。171 文件 / 11,640 行。
- 技术：BACKGROUND_RESOLUTION_DIVIDER 把 colortex1 降 0.5/0.25、消费端按 divider 调 texel；云只在 depth≈far 像素积分、CLOUDS=25 时移到 skybasic 绕开 composite；阴影查询边界外 early-out 保持受光；4/8 次采样 + 亚像素双线性重建；螺旋 + 半影半径 ∝ 遮挡深度（近似 PCSS）；像素锁定阴影（世界网格量化 + 法线偏移，低分辨率不闪）；SHADOWS=0 只解 SSS；阴影图径向畸变集中近处 texel；贴图过滤距离 >10 格立即回退硬件采样 + 距离渐变压权重 + 图集邻块边界裁剪 + 逐程序开关；POM INITIAL 30 + REFINE 10；DH 按玩家速度收缩圆盘 discard 近处。
- 去重排除：阶段熔断/缓冲缩放/云独立步数/影距淡出（已有）；4-tap 亚像素重建与 Astra 角点核同构；DH 圆盘 Astra 无 dh 程序不迁移。
- 新颖借鉴点：遮挡深度自适应半影 + 像素锁定（低-中，B 组）；距离门控贴图过滤（中——属画质特性，但其开销控制纪律值得学）。

### 3.18 Exposa Shaders 5

- 定位：自研全功能包，无许可文件（默认 ARR），思路级。248 文件 / 7,422 行。
- 技术：GBuffer 四属性打包 uvec4/RGBA32UI；blindness/darkness=0 整段跳过 VL；云只在 texcoord×缩放因子的屏幕子矩形内 raymarch（默认 1/4 像素）；先求云层交点区间再积分 + transmittance<0.05 break + 单步光学厚度≤0.001 continue；8 帧抖动 TAAU + 双边 4-tap 上采样 + 边缘掩码回退最近 texel + 历史 0.99 四重门；9 点固定螺旋 PCF + 植被 SSS 放大偏移；VL 固定 6 采样（水下 4）、天空免阴影比较、仅透明遮挡且水面才读 shadowcolor0、结果存 colortex3 供反射复用；SSR 默认 1 条 VNDF 重要性采样射线 + TAA 时域累积 + 屏幕 DDA 步长 + 命中色按距离²×粗糙度取 mip；Bloom colortex0 mip LOD4 + 1/4 分辨率 9+7 可分离高斯；TAA Catmull-Rom + YCbCr 钳制 + 亚像素对齐；水波法线单次 3D worley fetch + 3 次梯度。
- 去重排除：Bloom mip 分档/程序熔断/VL 分档（已有）；DDA/LOD 与 Astra 递增 stride+同 texel 缓存+粗糙度 LOD 同向；保边上采样与云时域门（已有）；3D worley 波场与 Astra CPU 化波场取向冲突。
- 新颖借鉴点：VL 取数门控（低，A 组首选）；GBuffer uvec4 打包（高，C 组观察）；TAA Catmull-Rom（中，B 组）；水波单次 worley（中，需 A/B）。

### 3.19 Vanilletix 1.2.0（SDV 同源，只报增量）

- 定位：复刻 SDGP 风格；与 super-duper-vanilla 1.3.8 同源（代码头 SDV v1.3.6）；297 文件 / 12,340 行。
- 增量技术：逐维度编译期砍效果（下界不定义 WORLD_LIGHT 时阴影/日月整段消失，world-1/world.glsl:5-22）；光照常量顶点阶段 flat 插值；全程序 texelFetch/显式 LOD；sRGB 与开方多项式化、x(2-x) 免 pow（common.glsl:192-197）；地表像素只用解析 getSkyBasic（零贴图），仅 depth==1 走完整天空后立即 return；体积云体素对齐取样（32m 同格复用）；硬件 PCF + 彩色阴影两级提前返回 + TAA≥2 时 1 次帧旋转采样；SSAO 4 步 swizzle 生成 4 方向 + 消费端盒式模糊（非独立 pass）；透明专用延迟着色（仅 depthtex1>depth0 像素重做）；SSR 朝相机/出屏/手持立即返回 + 置信度；光滑度<0.35 跳过反射 + Fresnel exp2 拟合；自动曝光寄生 TAA 历史 alpha；vignette/underwaterOverlay=false。
- 去重排除：顶点常量（CPU 化覆盖）、SSR 有限步进+二分+置信度（Astra 更强）、TAA 减 tap（已决策不靠时域换采样）、SSAO 4 步（Astra 12 步黄金角为质量取向）、Bloom 平铺、云区间裁剪/透射中断（已有）。
- 新颖借鉴点：vignette/underwaterOverlay 关闭（低，A 组，并入管线级开关）；sRGB 多项式（低，A 组）；云噪声体素对齐（中，仅对体素云有效，Astra 平面云迁移价值低）。注意：包内版本自相矛盾（lang 1.2.0 vs 代码头 v1.3.6）。

### 3.20 YoFPS 1.0-high

- 定位：Chocapic13 低配分支（基线近 V4），24 文件 / 2,118 行；无 shadow/composite/TAA/Bloom/SSR 程序，光照+天空+云+雾+反射+色调映射全内联 final.fsh 单 pass。
- 技术：无阴影图，日光遮蔽用光图近似 `lc*pow(aux.r,8)`；gaux1.g 材质标志分派路径；天空/云仅 land>0.9 像素执行、云层循环 alpha>0.999 break；解析天空反射；雨珠/光晕/景深/暗角默认编译期关闭；帧常量逐顶点算；太阳色温 25 项整点 LUT；解析 exp 雾；雨滴 rainStrength>0.02 门槛。
- 去重：无阴影+假阴影（Astra NO_SHADOWS 预设已有）、单 pass 合并（不学）、逐顶点常量（CPU 化覆盖）、云 break/解析反射/雨量门槛（已有）。
- 新颖借鉴点：**无**。价值为反面印证（见 2.4）。

## 四、许可与借鉴方式

- 可代码级参考：Arc（MIT）、Pixel Perfect（LGPLv3）、Noble（GPLv3，注意传染性，宜只读思路）、I Like Vanilla（What42 2.2，条件复用需致谢）。
- 思路级重写并登记 THIRD-PARTY.md（Astra 现行做法）：Potato、Pegasus、Simply Upscaled（明文禁 snippet）、Exposa（无许可）、Soft Voxels Lite、Fantasy（Complementary License 1.5 修改版）、Builder's QOL（无正式许可）、LIGHT/YoFPS（Chocapic13 许可）、AstraLex/Pastel/Bloop/VanillAA/Vanilletix（BSL/Bliss/Chocapic/SDV 系）。
- RenderPearl pack.json 未附许可正文，按保留所有权利处理。

## 五、无法判定与实机验证清单

1. 所有包均无作者基准帧时数据，本报告全部收益为源码级推断，采纳前需 Astra 实机 A/B。
2. TAAU/渲染缩放：全链坐标/历史/后处理契约重写量大，需先做一版离线坐标对齐验证。
3. 波高/焦散预计算图 vs Astra 解析法：净收益取决于分辨率与采样数，需实测。
4. 曝光低档化三方案 vs Astra 64-tap 测光：画质（闪烁/延迟）需实机对比。
5. `vignette=false`/`underwaterOverlay=false`：需实机截图确认 Astra 自绘暗角与水下吸收无双重叠加或缺失。
6. `backFace=false` 四类：需确认 Astra 水面/半透明是否依赖双面渲染（与 shadow.culling 必须 false 的既有结论同源核对）。
7. 雨几何云层以上剔除：云上飞行时是否应无雨，需行为定义。
8. Fantasy SHADOW_QUALITY 4/5 采样数与 TAA 的耦合；Arc SSR_HIZ 依赖未声明；Bloop fog_translucent_lowres.vsh / RENDER_SCALE_X/Y 无调用点；LIGHT 宏默认与 GUI 一致性；Vanilletix 版本自相矛盾；ILV 彩光 floodfill 疑似依赖仓库外生成器——以上均为源码级未决项。
9. 有理衰减 vs exp：现代 GPU 上 div 与 exp2 近价，收益存疑，须实测后定。
