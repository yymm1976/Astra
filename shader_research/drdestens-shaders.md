# drdestens-shaders × Astra 可借鉴点调研

- **生成方式**：子代理调研（统帅哥派工契约执行；本报告只写这一个文件）
- **参考包**：`reference_shaderpacks/drdestens-shaders/`（DrDestens Minecraft Shaders，作者 DrDesten，版本 **2.1.5**）
- **调研日期**：2026-10-02
- **引用约定**：`P:` = `reference_shaderpacks/drdestens-shaders/shaders/`；`A:` = `Astra/shaders/`。行号均来自实际读取；`A:` 指向工作树当前状态。
- **本包关注点**：定位"高性能 + **无阴影也好看** + PBR"；提取无 shadow map 时的方向感/接触感/遮蔽伪造手法与低预算 PBR 简化，对应 Astra 的 NO_SHADOWS 预设与性能档。

---

## ① 概览

| 项 | 事实 | 证据 |
|---|---|---|
| 体量 | 259 文件 / 约 0.35 MB；无 LICENSE、无 README（根目录仅 `shaders/`） | `find`+`wc -c` |
| 作者/版本 | DrDesten / v2.1.5 | `P:shaders/lang/en_us.lang:375-377` |
| 组织 | 单 `shaders/` 根；`core/`（作者自用 ShaderCore 库）+`lib/`+入口；`world0/` `world1/` `world-1/` 为薄壳（`#define OVERWORLD/NETHER/END`+`#include`） | `P:core/README.md:1-2`、`P:world0/final.fsh:1-4`、`P:world1/composite7.fsh:1-4` |
| 管线 | gbuffers → `deferred`(SSAO) → `deferred1`(天空/光照/雾) → `composite2`(SSR/水) → `composite3`(POM/描边/godrays) → `composite4`(TAA) → `composite5/6`(DOF) → `composite7`(bloom 瓦片+运动模糊) → `composite13`(bloom/tonemap/调色/暗角/天气) → `final`(锐化/去带) | `P:deferred.fsh:191-192`、`P:deferred1.fsh:38`、`P:composite4.fsh:94-101`、`P:composite7.fsh:86-88`、`P:composite13.fsh:163`、`P:final.fsh:149` |
| 预算取向 | 8 张 colortex、无 compute、**无 shadow pass**；SSAO 与主光照都在屏幕空间以光图当光源 | `P:lib/lightmap.glsl:47-95` |
| **默认开关（重要）** | 出厂默认 **PBR 关闭**（`//#define PBR`）、`HEIGHT_AO`/`DIRECTIONAL_LIGHTMAP` 关；`WATER_EFFECTS`、`SSAO`(质量1)、`TAA`、`BLOOM`、`GODRAYS`、`SSR_MODE 3`、`OPTIMIZE_INTERPOLATION`、`separateAo` 开 | `P:lib/settings.glsl:1,19,69,82-83,114,123,209,150,152,155,174`、`P:shaders.properties:17` |

**许可证现状（原文行号）**：包内**没有任何 LICENSE/版权文件**，全包检索 `licen|copyright|all rights|redistribut|permission|MIT|GPL|CC0|CC-BY` 只命中署名与算法名：
- `P:shaders/lang/en_us.lang:375-377`（`option.CREDITS=v2.1.5` / `value.CREDITS.0=by DrDesten`），无授权条款；
- `P:shaders.properties:231` 的 `CREDITS` 页签（GUI 定义 `:228-231`）；
- `P:core/core/sampler.glsl:64`（`mitchell()`）、`P:lib/pbr/lighting.glsl:20`（`G_Smith()`）是算法名；`P:core/README.md:1-2` 只说这是作者自家库。

**结论**：未授予任何许可（保留所有权利）；批次二索引同归类（`shader_research/SUMMARY-batch2.md:49` 列"仅可读思路，重写"层）。

---

## ② 架构特性清单（按子系统）

**2.1 材质/PBR 通路**
- LabPBR 读取族（subsurface/porosity 以 `0.25294117647` 互斥切分，`reflectance>0.9` 判金属）—— `P:lib/pbr/pbr.glsl:10-37`、`:40-71`；F0 表 8 项硬编码 `:110-148`。
- 打包：4 个 8bit 标量经 `vec4to16x2()` 进**单张 RG16 两通道**（colortex7），`vec2x16to4()` 解包 —— `P:lib/pbr/pbr.glsl:90-93`、`P:lib/pbr/read.glsl:63-68`、`P:core/core/packing.glsl:126-139`。
- 无贴图 PBR 生成函数（`P:lib/pbr/generate.glsl:2-13`）无调用者：唯一 `#ifdef` 体为空（`P:gbuffers_terrain.fsh:65-67`）→ **死代码**。

**2.2 光照与无阴影方向感**
- 光照在 `deferred1` 一次做完：光图 → `getCustomLightmap()` → 非 PBR `color.rgb *= lightmapColor`，PBR 走 `RenderPBR()` —— `P:deferred1.fsh:101-136`（103-104、118-123、127）。
- `CookTorrance_custom()`：漫反射 = **环境光×半兰伯特** `ambientAlbedo*((kD*NdotL)*0.5+0.5)` + `spec*sq(NdotL)`；非 OVERWORLD 退化为纯方向项 —— `P:lib/pbr/lighting.glsl:64-92`、`:60-63`、分派 `:174-178`。
- 高光强度由光图方块光驱动 `clamp(mix(-1.5,1,lm.y),0,1)*sq(sq(lm.y))*lightBrightness` —— `P:lib/pbr/lighting.glsl:157-158`。
- `RenderPBR()`：`mat.ao*=sq(mat.height)`、`mat.emission*=4`、SSR 时 `albedo*=1-maxc(f0)`、SSS —— `P:lib/pbr/lighting.glsl:155-191`（160-162、164、169-171、180-185）。
- 顶点假方向光 `oldLighting()`：固定光向 `normalize(vec3(1,4,2))` 点乘顶点法线乘进 `glcolor.a`，强度 `OLD_LIGHTING_STRENGTH=0.25` —— `P:lib/vertex_lighting.glsl:1-7`、`P:gbuffers_terrain.vsh:52`、`P:lib/settings.glsl:299`。
- `getCustomLightmap()`：天光 `lm.y²`、方块光 `saturate(lm.x²*1.1)`，**天光/方块光各一条 AO 幂曲线**（0..200 滑条，100=线性），另加 `caveLight` 地板与维度替身 —— `P:lib/lightmap.glsl:12-45`（14-38、43）、`:47-95`、滑条 `P:lib/settings.glsl:24-34`。

**2.3 AO/SSAO（三档）**
- `SSAO_QUALITY 1` 无法线 8 tap 螺旋、`2/3` 为 8/16 tap Vogel 半球；AO 直接乘 `lightmap.z`；另有 `HBAO_like()` 与旧实现留档 —— `P:deferred.fsh:160-189`、`:75-101`、`:103-130`、`:132-156`、衰减函数族 `:26-45`、分派 `:194-227`。
- 半球采样**不做 TBN**：`scoord *= sign(dot(normal, scoord))` 把朝内样本镜像到外侧 —— `P:deferred.fsh:89`、`:118`。
- ID 白名单 `(id<50||id>52)&&depth!=1` `P:deferred.fsh:204`；编码 `codeID()=id/255`、解码 `getID()=floor(r*255+0.5)` —— `P:lib/gbuffers/basics.glsl:1-6`、`P:lib/composite/id.glsl:3-8`。

**2.4 天空/雾/云/godrays**
- 解析天空 `skyBaseGradient()`：`exp2(-abs(softheight+offset)/colorScale)`（三通道尺度+偏移）+ softmax 地平线 + `exp2(-|h|*4)*sunset` 晚霞 —— `P:lib/sky.glsl:21-32`；昼夜/雨混合 `:53-63`；末地噪声扰动 `:44-49`。
- 雾：指数雾 + 去雾曲线 `2*f²/(1+f)`；`length(playerPos*vec3(1,0.1,1))` 压扁高度；`SUNSET_FOG` 距离缩放；洞雾按 `eyeBrightnessSmooth.y` 淡入 —— `P:lib/sky.glsl:95-134`（116-117、124、126）、`:65-67`。
- 云：伪体积 `vol_1=p*0.2+0.8`、`vol_2=sq(sq(p))` 乘 `(diffuse+0.75)`，写哨兵光图 —— `P:gbuffers_clouds.fsh:37-49`、`:62-64`。
- godrays：`falloff=exp2(-sqmag(rayCorrected/(fovScale*GODRAY_SIZE)))`，`falloff<=1/256` 跳过；遮挡"计数减光" `light-=1/GODRAY_STEPS`；`lightPositionClip.w>0` 门控 —— `P:composite3.fsh:180-228`（190-193、204-218）。
- 日/月切换与光方向在 properties 算：`lightPosition`（12786..23215 tick 用 moon）、`lightPositionClip`（含 w）—— `P:shaders.properties:86-96`。

**2.5 后处理**
- TAA：3×3 **lanczos3 加权源色** + min/max AABB + `mu±0.75σ` 方差裁剪 + `clipAABB()`；越界即清历史权重 —— `P:composite4.fsh:35-48`、`:50-92`（56-68、81-85）、`:129-141`；抖动 R2 序列 `P:shaders.properties:105-108`。
- DOF：CoC 于 composite4 写 colortex0.a（排除 ID 51）`P:composite4.fsh:158-184`；composite5/6 只读 alpha，六边形 bokeh 两轴向量模糊 —— `P:composite5.fsh:36-70`、`P:composite6.fsh:36-71`、`P:lib/dof.glsl:34-73`。
- Bloom：`getBloomTilesBlur()` 单 pass 把 6 级金字塔写成**瓦片图集**（`ceil(-log2(1-coord.x))`，每级 4×4 高斯，源用 colortex0 自带 mip）`P:composite7.fsh:51-83`；收端 `P:composite13.fsh:99-133`；镜头光晕 `:135-159`。
- 运动模糊：`ratio=saturate(b/a)*float(z>0.56)`（世界/屏幕运动矢量比）抑制相机平移模糊 —— `P:composite7.fsh:101-120`。
- 调色末端：`tm_reinhard_sqrt`/`tm_unreal`+`gamma_inv`；百分比换算 `1/(1-(x/300+0.5))-1`；圆/方暗角；天气层 `mix(color, weather.rgb, weather.a)` —— `P:composite13.fsh:185-229`。
- 去带+锐化：`color += (Bayer4(...)-.5)/255`；锐化量随相机位移自适应、min/max 夹过冲 —— `P:final.fsh:172-173`、`:157-160`、`:68-90`；画质缩放只缩放 final 采样坐标 `P:final.fsh:14`。

**2.6 水面/SSR/POM/优化开关**
- 水面与水吸收：`waterNormalsSine()` 三级旋转波法线（`cos*exp(sin)` 解析导数）`P:core/water.glsl:18-26,58-74`、吸收 `exp(-Δd*ρ)` `P:composite2.fsh:277-290`；SSR `P:composite2.fsh:141-189`；POM `P:composite3.fsh:118-157`（对照见 ④）
- `OPTIMIZE_INTERPOLATION` 把 `OPT_FLAT/OPT_NOPERSPECTIVE` 定义为 `flat`/`noperspective` —— `P:lib/settings.glsl:19`、`P:lib/stddef.glsl:10-19`、`P:gbuffers_terrain.fsh:23`、`P:gbuffers_water.fsh:27`。
- 全局 OptiFine 开关 + 批量 `alphaTest.program.*=off` —— `P:shaders.properties:6-13`、`:121-159`。

---

## ③ 可借鉴点（15 条）

工作量档位：半天内/数天/一周+。**"与批次一重复"**= 批次一（`shader_research/` 非 batch2 报告）已提同方向，作同向收敛证据。

**P1｜无阴影方向感：环境光乘"日光方向半兰伯特"（本包最核心）**
环境光乘 `NdotL*0.5+0.5`（NdotL 取自 `lightPosition`）+ `spec*sq(NdotL)`；非 OVERWORLD 连高光都省。无 shadow map 的方向感代价 = 3 个点乘。
- P：`P:lib/pbr/lighting.glsl:64-92`（`60-63`、`174-178`）｜A：`A:global/lighting/diffuse.glsl:95-97`（`0.67+y*0.33` 只按上下）、`:103-108`
- 工作量：**半天内**。**与批次一重复**（SUMMARY ②-6「NO_SHADOWS 档假阴影兜底 visibleSky 幂衰减」，MakeUp 单源）。差异互补：本包按**光的方位**、MakeUp 按**天空可见度**，正交可叠加。

**P2｜接触感：材质高度平方进 AO，AO 折进光图通道（零额外缓冲）**
`mat.ao *= sq(mat.height)`（LabPBR 法线 alpha 当高度）再乘进 lightmap.z；不用屏幕空间 pass、不占缓冲。
- P：`P:lib/pbr/lighting.glsl:160-162`、`P:gbuffers_terrain.fsh:73`、`P:gbuffers_water.fsh:109`｜A：`A:lib/ao_resolve.glsl:52-88`、`A:program/ssao.fsh:104-105`（Astra 的 AO 只有屏幕空间 pass + 顶点 AO，占总在 colortex20.a）
- 工作量：**数天**（Astra 无 LabPBR 高度输入，需先定高度来源）。风险：本包 `HEIGHT_AO` 默认关（`P:lib/settings.glsl:155`）。

**P3｜AO 按光源类型分开给曲线**
同一份 AO 对天光/方块光各一条幂曲线（0..200 滑条，100=线性）。
- P：`P:lib/lightmap.glsl:14-38`、`P:lib/settings.glsl:24-27`｜A：`A:global/lighting/diffuse.glsl:103-108`、`A:lib/ao_resolve.glsl:86-88`（Astra 的 AO 只扣环境光）
- 工作量：**数天**；取向冲突，需统帅裁决是否引入。

**P4｜无法线 8-tap 螺旋 SSAO（最低档，仅深度）**
8 次黄金角螺旋 + Bayer8 抖动起点 + `cubicAttenuation2()` 衰减，不读法线。
- P：`P:deferred.fsh:160-189`（配套 `:37-45`）｜A：`A:program/ssao.fsh:61-103`（12 tap，需 depth+法线，兼产 bent normal）、`A:lib/ao_material.glsl:3-6`
- 工作量：**数天**，**不建议替换**：Astra 的 AO 兼产 `A:lib/ao_resolve.glsl:19-50` 的 bent normal 供方向性天光换向，去法线会废掉 `ASTRA_DIRECTIONAL_SKYLIGHT`；只能作"方向性天光关闭档"的独立档（需裁决）。

**P5｜半球镜像代替 TBN**
`scoord *= sign(dot(normal, scoord))` 省掉 `arbitraryTBN()`（`P:core/core/matrix.glsl:65`）的 3 次 cross。
- P：`P:deferred.fsh:89`、`:118`｜A：`A:program/ssao.fsh:71-87`（Astra 在视图空间直接算 delta，本就不建 TBN）
- 工作量：**半天内**；Astra 无对应开销，仅登记备用。

**P6｜点亮地板 caveLight（暗处不纯黑且随天光收敛）**
`caveLight=LIGHTMAP_MINIMUM_LIGHT*(y*(y-2)+1)*z`：地板值是天光与 AO 的函数，天光满时归零。
- P：`P:lib/lightmap.glsl:43`、`P:lib/settings.glsl:34`｜A：`A:global/lighting/diffuse.glsl:107`、`:433-435`（`caveFloor` 夜间衰减）、`A:lib/settings.glsl:50`
- 工作量：**半天内**。Astra 已有等价结构，建议只核对"夜里洞底不过亮"的曲线。

**P7｜解析天空：三通道色标 exp2 尺度 + softmax 地平线 + 晚霞限域**
`exp2(-abs(softheight+offset)/colorScale)` 用一张常量表表达天顶-地平线梯度；`sunsetMix=exp2(-|softheight|*4)*sunset` 把晚霞锁在地平线。整包无 LUT。
- P：`P:lib/sky.glsl:21-32`、`:11-19`、`:53-67`｜A：`A:global/atmosphere/sky_gradient.glsl:158`、`:231`、`sky_minishita.glsl`
- 工作量：**数天**（整体替换不建议）；可只借 `sunsetMix` 限域写法，需对照实验。

**P8｜雾的两处廉价细节**
(a) `fog=2*sq(fog)/(1+fog)` 去雾曲线平滑起步；(b) 洞雾按 `eyeBrightnessSmooth.y*(5/240)` 把天空淡入亮色，不需额外 pass。
- P：`P:lib/sky.glsl:116-117`、`:65-67`｜A：`A:global/atmosphere/fog.glsl:67,79,208,230`、`A:lib/settings.glsl:174`
- 工作量：**半天内**（(b) 需先核 Astra 是否已有等价项，本报告未逐行读 fog.glsl）。

**P9｜godrays：解析衰减 + falloff 早退 + 遮挡计数**
不逐样本累乘 decay，只数遮挡比例 `light-=1/STEPS`，再乘解析 `falloff`；`falloff<=1/256` 整像素跳过（天空多数像素）。
- P：`P:composite3.fsh:190-193`、`:204-218`｜A：`A:global/post/godrays.glsl:53-88`（8 样本 + `illuminationDecay` 累乘）
- 工作量：**半天内**。**与批次一重复**（SUMMARY ②-6「depth-only 4-tap godrays 低档」，MakeUp 单源）。

**P10｜Bloom 瓦片金字塔（Astra 现有 mip 链更省，登记不迁移）**
6 级金字塔平铺进一张纹理，每像素只算所属瓦片 4×4 高斯，源用场景自带 mip；末端从瓦片读最模糊级做镜头光晕。
- P：`P:composite7.fsh:51-83`、`P:composite13.fsh:99-133`、`:135-159`｜A：`A:global/post/bloom.glsl:5-15,32-63,72-85`（0.25 捕获 + 软膝 + 13 tap + 4 级 mip）、`A:shaders.properties:28-30`
- 工作量：**一周+/暂缓**。Astra 的 mip 链更省；瓦片独有价值是"光晕从指定模糊级取样"（`P:composite13.fsh:147`）。**与批次一重复**（Unbound 镜头光晕，SUMMARY ②-8）。

**P11｜TAA 细节：抖动相位加权源色**
3×3 源色用 `lanczos3(x-jitter.x)*lanczos3(y-jitter.y)` 加权，把抖动相位喂进重建核。
- P：`P:composite4.fsh:56-68`（越界弃历史 `:129-132`）｜A：`A:program/taa_resolve.fsh:30-50`、`:93-127`（±1.25σ + min/max + centreTrust + 运动自适应）
- 工作量：**数天**。**与批次一重复**（SUMMARY 快赢 #10，Photon/Kappa/Mellow）。Astra 统计约束更全（本包仅 `mu±0.75σ`，无逐角点深度校验），可借仅"相位加权"。

**P12｜移动量自适应锐化 + 1/255 有序抖动去带**
`clamp(length(cam-prevCam)*1e2,0.25*AMT,1)*AMT`（静止轻、移动重）+ 邻域 min/max 夹过冲；输出前 `color+=(Bayer4(...)-0.5)/255`。
- P：`P:final.fsh:157-160`、`:68-90`、`:172-173`｜A：`A:program/final.fsh:18`（`apply_output_dither`）、`A:lib/settings.glsl:237`
- 工作量：**半天内**。Astra 已有输出抖动；锐化量公式可直接照搬参数。

**P13｜CPU 派生量：昼夜归一化（0.5=日落）+ 光方向裁剪坐标 + R2 抖动表**
昼夜各压到 0..0.5/0.5..1，使 `sunset=pow(cos(normalizedTime*tau),100)*3` 与季节无关；`lightPositionClip` 由 `gbufferProjection` 算出（godrays 零 CPU）。
- P：`P:shaders.properties:62-71,75-77,91-96,105-108,112`｜A：`A:shaders.properties:464-586`（约 140 行派生量）、`A:lib/taa_jitter.glsl:8-23`（Halton 8 点 + CPU 双帧调度）、`A:shaders.properties:559-586`
- 工作量：**半天内**。**与批次一重复**（SUMMARY ②-6「CPU 预计算 custom uniform」，12 包印证）。可核对点：光方向裁剪坐标的"背面 w 门控"与 Astra `clipLightVector/godraysOffscreenFade` 是否一致。

**P14｜设置项"0=中性"百分比换算 + 批量 off 开关**
(a) `1/(1-(x/300+0.5))-1` 让滑条中性值为 0；(b) properties 集中声明 `alphaTest.program.<pass>=off`（40 余行）与 `shadowTranslucent/sun/moon/rain.depth/beacon.beam.depth/oldLighting` 等。
- P：`P:composite13.fsh:192-216`、`P:core/core/color.glsl:17-37`、`P:shaders.properties:6-13`、`:121-159`｜A：`A:lib/color_controls.glsl:6-27`（"neutral at 100"）、`A:lib/tonemap.glsl:206-228`、`A:shaders.properties:263,268`
- 工作量：**半天内**。(b) 中 Astra 无 `alphaTest.program.*=off`（全仓检索无命中）——需先核实 Iris 是否已自动关闭（见备注）。

**P15｜材质/法线打包格式（观察项，不建议引入）**
4×8bit 塞进 RG16（`vec4to16x2`）与球面贴图法线 8bit×2 编码。
- P：`P:core/core/packing.glsl:126-139`、`:6-16`、`P:lib/pbr/gbuffers.glsl:3-11`、`P:lib/composite/normal.glsl:3-5`｜A：`A:lib/wet_material.glsl:7-28`、`A:lib/rock_material.glsl:7-19`、`A:lib/encoding.glsl`（程序化材质 + 位域 material ID）
- 工作量：**一周+/暂缓**；依赖 LabPBR 双贴图输入，与 Astra 设计不可拼接。

---

## ④ Astra 已有对应实现对照表

| 主题 | P 侧 | A 侧 | 哪边更省 / 误差来源 |
|---|---|---|---|
| 环境光方向性 | `P:lib/pbr/lighting.glsl:64-92`（半兰伯特+高光，3 点乘） | `A:global/lighting/diffuse.glsl:95-97` | **A 更省**；A 缺"太阳方位"各向异性 → 无阴影档朝向感弱于 P |
| AO 载体 | `P:deferred.fsh:160-189` 写 `lightmap.z`，随光图被消费 | `A:program/ssao.fsh:104-105` 独立半分辨缓冲 + `A:lib/ao_resolve.glsl:52-88` | **P 少一缓冲**；A 误差更小（边缘感知+bent normal，只扣环境光）；P 的 AO 会被"方块光 AO 曲线"放大 |
| 无阴影兜底 | 无显式兜底；`P:lib/settings.glsl:299` 顶点 0.25 方向项 | `A:global/lighting/diffuse.glsl:289-291`；`A:shaders.properties:445` | **A 更省**；A 把整块地照成无遮挡，P 的半兰伯特保留方位衰减 |
| 天空 | `P:lib/sky.glsl:21-32`（12 行 exp2，零资产） | `A:global/atmosphere/sky_gradient.glsl:158,231` + `sky_minishita` | **P 更省**；P 无语物理/天气耦合，A 覆盖天气/群系/时刻 |
| 雾 | `P:lib/sky.glsl:116-134`（~20 行） | `A:global/atmosphere/fog.glsl:67,79,208,230`（235 行） | **P 更省**；P 仅 2 参数、无体积/无群系 |
| SSAO 最低档 | `P:deferred.fsh:160-189`（8 tap，0 法线 fetch） | `A:program/ssao.fsh:61-103`（12 tap + 法线/深度 + bent normal） | **P 更省**（约半 fetch）；P 无方向信息、拐角更糊 |
| 水面波法线 | `P:core/water.glsl:18-26,58-74`（3 次正弦+解析导数） | `A:global/water/surface.glsl:190,224,281`（谱波） | **P 更省**；P 是经验波列，斜视/远处误差大。**与批次一/二重复**（Miniature 顶点 hash 水波、Solas 雨天波幅、glimmer 零纹理解析海浪） |
| 水吸收 | `P:composite2.fsh:285-288`（单通道 exp + 混色） | `A:global/water/absorption.glsl:13,55-64,97`（吸收+散射、Beer-Lambert、垂直深度积分） | **P 更省**；P 无散射/无垂直深度，浅深水过渡不如 A 平 |
| SSR | `P:composite2.fsh:141-189` + miss 回退 `:47-73` | `A:global/water/raytrace.glsl` + `A:lib/sky_reflection_cache.glsl` | **A 的 miss 有天空缓存**；P 的 `efficientSSR` 无二分细化（旧版 `:75-139` 有，已注释留档），薄几何易穿透 |
| Bloom | `P:composite7.fsh:51-83`（瓦片图集 + 场景 mip 源） | `A:global/post/bloom.glsl:5-15,32-63` | **A 更省**（少一张图集与 bicubic 读）；P 无阈值只做 `sq(getBloom*AMOUNT)` 叠加，更易发灰 |
| TAA | `P:composite4.fsh:50-92,129-141`（lanczos3 源权重、AABB+0.75σ） | `A:program/taa_resolve.fsh:30-50,93-127`（逐角点深度校验、YCoCg、±1.25σ） | **A 更全**（P 无逐角点校验，快速物体易留形状鬼影）；P 独有正向细节：抖动相位进核（`:63`） |
| 时间跳变失效 | 未见（只查 uv 越界 `P:composite4.fsh:122`） | `A:lib/taa_state.glsl:13-35`、`A:lib/effect_history.glsl:17-38` | **A 更全**；P 在 `/time set`/维度切换/视角突变时会拖影 |

---

## ⑤ 许可可行性与"重写 vs 抄"边界

1. **不能照抄表达式级代码**：包内无任何许可证/版权声明（① 段证据），既非 GPL/MIT 也无"可再分发"字样；搬运函数体会让 Astra 许可链缺环，且与现有登记纪律冲突（`A:global/lighting/wind.glsl:15-25` 是"照抄形状必须登记"的先例）。
2. **可做的**：读思想 → 用 Astra 自己的命名/风格/参数体系独立重写，并在 `Astra/THIRD-PARTY.md` 登记"思想来源：DrDestens Minecraft Shaders 2.1.5"。
3. **逐条边界**：
   - *照参数重写安全*：P1（半兰伯特）、P6（地板曲线）、P8a（去雾曲线）、P12（锐化/抖动公式）、P14a（百分比换算）。
   - *必须改结构再实现*：P2（高度 AO 常数）、P3（0..200 滑条语义）、P7（三通道色标表）、P9（falloff 与计数比例）、P11（lanczos3 权重）、P13（R2 常数）。
   - *不要碰*：P4（须按 Astra bent-normal 架构重设计）、P15（LabPBR 链路不匹配）、P5（Astra 无对应开销）。
4. **不要抄默认值**：其默认值（`P:lib/settings.glsl:150-174`）与 Astra 档位体系（`A:shaders.properties:444-447`）不同构。

---

## ⑥ Top5 与暂缓项

**Top5（收益/工作量/缺口契合度）**
1. **P1 无阴影方向感**：契合 NO_SHADOWS 预设 + 与批次一 MakeUp 同向收敛；只改 `ambient_sky_lighting()` 一处加开关，可与 `A:global/lighting/diffuse.glsl:95-108` 叠加（方位项×上下项）。半天内。
2. **P2 高度/材质 AO 折进环境光**：补 Astra"接触感只靠 SSAO"的单点依赖；前置是定高度来源。数天。
3. **P12 移动量自适应锐化 + 去带**：与 TAA 联动、无新缓冲、可立即目视验证。半天内。
4. **P9 godrays 解析衰减 + falloff 早退**：纯性能/画质折中，天空像素整段跳过；与批次一收敛。半天内。
5. **P6/P8a 光照地板与雾曲线**：两个"改一行曲线"的低风险观感项，可用滑条回退。半天内。

**暂缓项**
- **P4 无 normal SSAO**：与 bent-normal/方向性天光设计冲突（`A:lib/ao_resolve.glsl:19-50`）；批次一已判定"导数法线 SSAO 不迁移"（SUMMARY-batch2:37），同取舍的另一端，**不建议**。
- **P10 Bloom 瓦片**：Astra 的 mip 链更省；仅"光晕取指定模糊级"有价值，而镜头光晕本身是批次一风格页项（SUMMARY ②-8）。**暂缓**。
- **P15 LabPBR 打包 / POM**：Astra 无 LabPBR 输入通路、无 POM 子系统，要么立项要么不动。**暂缓**。
- **P7 解析天空替换**：会丢 Minishita 物理与天气/颜色方案耦合；如做只借 `sunsetMix` 限域。**暂缓**。
- **P13 的 R2 抖动表**：Astra 已有 Halton 8 点 + CPU 双帧调度（`A:lib/taa_jitter.glsl:8-23`），批次一 12 包已提。**暂缓**。
- **P14b 批量 alphaTest off**：先核实 Iris 1.11.x 是否已默认关闭（Astra 现未声明），否则无收益。**半暂缓（先核实）**。

---

## 附录：自抽查（成稿后重开源文件核对行号）

方法：用 `awk` 二次读取逐条核对（抽查 12 条，≥8 条要求）；下表为二次读取所见原文关键词。

| # | 引用 | 核对结果 |
|---|---|---|
| 1 | `P:lib/pbr/lighting.glsl:64/88/91` | 通过。:64 `vec3 CookTorrance_custom(...)`；:88 `ambientAlbedo * ((kD * NdotL) * 0.5 + 0.5) +`；:91 `return BRDF;` |
| 2 | `P:lib/lightmap.glsl:14/28/43` | 通过。:14-18 天光 AO 分支；:28 `saturate(lightmap.x * lightmap.x * 1.1)`；:43 `float caveLight = LIGHTMAP_MINIMUM_LIGHT * (...)` |
| 3 | `P:composite7.fsh:51/53/74` | 通过。:51 `getBloomTilesBlur`；:53 `ceil( -log2(1 - coord.x) )`；:74 `gaussian_4[x + 1] * gaussian_4[y + 1]` |
| 4 | `A:program/ssao.fsh:104-105` | 通过。:104 `gl_FragData[0]=vec4(visibility,log2(1.0+max(-centre.z,0.0)),`；:105 `encode_unit_vector(worldNormal)*0.5+0.5);` |
| 5 | `A:lib/ao_resolve.glsl:87-88` | 通过。:87 `float extra=max(vertexAO-min(vertexAO,visibility),0.0);`；:88 `return max(scene-ambient*extra+skySwap,vec3(0.0));` |
| 6 | `A:program/taa_resolve.fsh:111-112` | 通过。`lo = max(lo,mean-1.25*sigma);` / `hi = min(hi,mean+1.25*sigma);` |
| 7 | `A:lib/taa_jitter.glsl:8/12/18` | 通过。:8 `astra_jitter_uv_for`；:12 `const vec2 offsets[8]`；:18 `(offsets[max(frame,0) % 8] + vec2(0.0546875, 0.0))` |
| 8 | `A:shaders.properties:445` | 通过。`profile.NO_SHADOWS=...` 行内确认含 `!SHADOWS`、`!SCREENSPACE_AO`、`STATIC_SHADOW_FALLBACK` |
| 9 | `A:global/post/bloom.glsl:48` | 通过。`const float BLOOM_CAPTURE_SCALE = 0.25;` |
| 10 | `A:lib/wet_material.glsl:7/16/23` | 通过。:7 `astra_wet_class`；:16 `astra_wet_material`；:23 `astra_wet_gloss` |
| 11 | `A:lib/rock_material.glsl:7/18-19` | 通过。:7 `astra_rock_smoothness`；:18 `return 0.0;`；:19 `}` |
| 12 | `A:global/lighting/wind.glsl:112/118-120` | 通过。:112 `wind_wave_shape`；:118-120 三条 `wave.*` |

（抽查全部二次读取通过，未发现行号漂移。附带确认：`P:lib/setup.glsl` 的 colortex 格式块整体在注释内——迁移 P15 必须自己声明格式；`P:gbuffers_terrain.fsh:65-67` 为空 `#ifdef`、`generate*` 无调用者。）
