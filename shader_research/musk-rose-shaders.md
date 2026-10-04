# Musk Rose Shaders v4.1 研读报告（面向 Astra 的可借鉴点）

> **撰写方式声明**：本报告由主代理直接撰写，**未派子代理**（本批次子代理配额耗尽，依统帅契约"worker 不可用可自行动手"的例外条款执行），深度低于同批次子代理产出的报告。
>
> **补强记录（2026-10-02，子代理执行）**：③ 由 7 条扩到 12 条、④ 由 10 行补到 14 行（每行含成本/误差）、附录由 23 条并为 13 条（含 E1-E6 修正清单）；**原有条目与既有结论一律保留**，仅就地订正 6 处错误、补注 5 处精度问题，并压缩篇幅（只精简措辞，未删任何行号引用）。
>
> 引用约定：`P:xxx:行号` = `reference_shaderpacks/musk-rose-shaders/`；`A:xxx:行号` = `Astra/shaders/`。所有行号均实际打开源文件核对（本次重读 `world0/` 各 pass、`programmes/` 其余共享文件、`uniforms/`、`shaders.properties`、`LICENSE`）；带"（补注）"的句子为追加，原句未删。

## ① 包概览

- **名称/版本**：Musk Rose Shaders。任务书标注 v4.1（来自 Modrinth 发布号）。**在本次阅读的文件（`shaders.properties`、`programmes/musk_rose_config.glsl`、`lang/en_US.lang`、`textures/credits.txt`）中未找到版本号字符串**，故版本以任务书口径记录。
- **作者**：Rin（Modrinth）；包内有 GitHub 源 `github.com/Rinloid/musk_rose_je`（来自 Modrinth 元数据）。
- **许可证**：**CC0-1.0（公共领域）**，`P:LICENSE:3`（标题）、`:35-40`（弃权正文）、`:40-43`（权利定义）、`:66`（弃权标的）；**本批次 20 包中代码级复用最自由者**（无署名/同类许可/传染性要求），详见 ⑤。
- **风格定位**：大气向半写实（Modrinth 分类 `atmosphere, iris, optifine, semi-realistic`），下载量 328,617。技术价值在**预计算大气 LUT 的离线烘焙工作流**、**导数法线的廉价 SSAO**、**4 行 UE4 移动端环境 BRDF 拟合**。
- **管线形态**：`programmes/` 存共享实现，`world0/`（主世界）、`world-1/`（下界）、`world1/`（末地）三套维度入口（各含 `gbuffers`/`deferred`/`composite[1-7]`/`final`），加 `programmes/uniforms/` 按 pass 分组的 uniform；`programmes/` 共 1448 行，配置面见 2.6。

## ② 架构与特性清单

### 2.1 预计算大气（本包最有价值的工程点）
- **LUT 以 PNG 资产随包分发**：`P:shaders/shaders.properties:1-19` 用 `texture.<stage>.colortex1X=` 把 5 张 PNG 绑到 colortex10~14，三个 stage 各声明一遍（Iris 绑定按 stage 生效）：`precomputedRayleighTheEnd/MieTheEnd.png`→colortex10/11（末地）、`voronoi.png`→colortex12（1024²，`P:shaders/programmes/musk_rose_config.glsl:14`）、`precomputedRayleigh/Mie.png`→colortex13/14（主世界）。
- **LUT 生成器是可独立运行的单文件着色器**（`P:shaders/textures/atmosphere.glsl`）：`:1` 注释指向 thebookofshaders 在线编辑器，`:21` `RESOLUTION vec2(500,500)` 与 `:23` `OUTPUT`（0=rayleigh / 1=mie）是烘焙开关，`:26-32` 是物理常数（地球/大气半径、Rayleigh/Mie 系数、两个 scale height、`MIE_DIRECTION 0.75`），`:54-99` 是 128 步球壳积分，输出经 Reinhard 压缩后写 `gl_FragColor`（`:98`、`:114`）。
- **运行时只做查找**：封装为 `getSky` / `getAtmosphere`（`P:shaders/programmes/musk_rose_sky.glsl:150-184,266-287`）（补注：消费点 `P:shaders/world0/deferred.glsl:105-106`、`P:shaders/world0/composite1.glsl:89-94`、`P:shaders/world0/composite2.glsl:105-107`，见 ③11；原句"未逐行读 LUT 消费点"作废。）

### 2.2 阴影
- **Builderb0y 的阴影畸变（三次方/立方根形式）**：`P:shaders/programmes/utils/musk_rose_shadow.glsl:22-35`。核心是 `pow(abs(x³) + abs(y³), 1/3) + SHADOW_DISTORTION`，再 `pos.xy / factor`（`:28`、`:30-34`），目的是把阴影图像素密度向玩家集中。（修正：宏名实为 `SHADOW_DISTROTION`，`P:shaders/programmes/musk_rose_config.glsl:30`、`P:shaders/shaders.properties:21`。）
- **固定 16 点采样盘**：`P:shaders/programmes/utils/musk_rose_shadow.glsl:4-20`（一颗 16 点的固定分布，非旋转抖动），供 PCF 使用。
- 阴影距离/分辨率作为滑杆暴露：`P:shaders/programmes/musk_rose_config.glsl:16-18`（`shadowMapResolution 2048`、`shadowDistance 512.0`、`sunPathRotation -40.0`）。

### 2.3 SSAO（导数法线 + 25 点固定盘）
- `P:shaders/programmes/utils/musk_rose_ssao.glsl:38-63`：**法线不用法线缓冲**，由视图空间位置的屏幕导数求得 `normalize(cross(dFdx(viewPos), dFdy(viewPos)))`（`:43`），仅需深度纹理；半径按深度反比 `0.03/(viewPos.z-bias)`（`:45`），25 点固定盘（`:4-30`）按 `vec2(1.0, aspectRatio)` 补偿（`:48`）；衰减 `sqrt(max(dp,0))*attenuation²*step(0.1,dp)`，`attenuation = 1-clamp(dist*0.6,0,1)`（`:55-58`），出处 SSDO by Yuriy O'Donnell（`:34-37`）。
  - **法线不用法线缓冲，而是由视图空间位置的屏幕导数求得**：`normalize(cross(dFdx(viewPos), dFdy(viewPos)))`（`:43`）——只需深度纹理。
  - 半径按深度反比缩放：`radius = 0.03 / (viewPos.z - bias)`（`:45`），即远处 AO 覆盖更大的世界范围但屏幕足迹不变。
  - 25 点固定盘 `occlusionSamples[25]`（`:4-30`），偏移按 `vec2(1.0, aspectRatio)` 做长宽比补偿（`:48`）。
  - 衰减：`sqrt(max(dp,0)) * attenuation² * step(0.1, dp)`，其中 `attenuation = 1 - clamp(dist*0.6, 0, 1)`（`:55-58`）。
  - 出处注明来自 SSDO by Yuriy O'Donnell（`:34-37`，附 `github.com/kayru/dssdo`）。
- 与顶点 AO 分开叠加：`P:shaders/programmes/musk_rose_config.glsl:59-60` 提供 `AO_VANILLA_INTENSITY` 与 `AO_SHADER_INTENSITY` 两个独立强度。

### 2.4 PBR 材质
- `P:shaders/programmes/utils/musk_rose_pbr.glsl:1-59`：Fresnel-Schlick（`:4-8`）、**环境 BRDF 拟合（`:10-16`）**、Visible GGX（`:18-26`）、GGX 分布（`:28-34`）、Smith 几何（`:36-46`）、合成（`:48-59`）；材质来源二选一 `PBR_TEXTURE AUTO_GENERATION | LAB_PBR`（`P:shaders/programmes/musk_rose_config.glsl:10-11,90`），另有 POM（`P:shaders/programmes/utils/musk_rose_pom.glsl`，59 行）。
- **环境 BRDF 只有 4 行**，注释直接给出出处 "physically-based-shading-on-mobile"（`:10`）：
  `P:shaders/programmes/utils/musk_rose_pbr.glsl:12-15`：`vec4 r = R*vec4(-1.0,-0.0275,-0.572,0.022) + vec4(1.0,0.0425,1.04,-0.04);`、`vec2 AB = vec2(-1.04,1.04)*min(r.x*r.x, exp2(-9.28*dot(V,N)))*r.x + r.y + r.zw;`、`return F0*AB.x + AB.y;`
- 材质来源二选一：`P:shaders/programmes/musk_rose_config.glsl:10-11,90` 的 `PBR_TEXTURE AUTO_GENERATION | LAB_PBR`——要么自己从原版纹理生成粗糙度，要么直接读 LabPBR 资源包。另有 POM（`P:shaders/programmes/utils/musk_rose_pom.glsl`，59 行）。

### 2.5 水、天气、天空、雾
- 水：`P:shaders/programmes/musk_rose_water.glsl`（62 行）；参数在 `P:shaders/programmes/musk_rose_config.glsl:68-88`（波浪/焦散/视差 `WATER_PARALLAX_STEPS 6`、`COL_WATER_R/G/B`、`WATER_TRANSPARENCY 0.30`、`WATER_REFLECTANCE 0.13`、雨纹、`SSR`+`SSR_RAYTRACING`、`REFLECTRION_BLUR_INTENSITY`、`ROUGHNESS_BLUR_INTENSITY 5.0`）。波浪/焦散/云图共用一张 `voronoi.png`（`P:shaders/programmes/musk_rose_water.glsl:4-5`、`P:shaders/programmes/musk_rose_sky.glsl:10-12`）；法线为高度场有限差分（`:36-46`）、视差自迭代（`:48-60`）、焦散写进 `shadowcolor0`（`P:shaders/world0/shadow.glsl:26-28`）。
- 雨：`P:shaders/programmes/musk_rose_rain.glsl`（101 行，过程式 Ripple Splatter 移植，`:6-9` 注明出处）；`RAIN_CUTOFF 0.70`（`P:shaders/programmes/musk_rose_config.glsl:62`），分格取 max 与有限差分法线见 `:60-77`、`:89-99`；消费点 `P:shaders/world0/gbuffers.glsl:172-177`（只在 `uv1.y > 0.85` 的朝上面生效）。
- 天空：`P:shaders/programmes/musk_rose_sky.glsl`（288 行，`programmes/` 下最大的共享文件；**全包最大是 `world0/gbuffers.glsl` 338 行**——2026-10-02 修正）。云形状两套（`:15-37`/`:39-46`）、步进常量 4 档（`:48-101`）、云高 256（`:102`）、相位 `:150-163`、月相与月面 `:224-245`、星/日/月合成 `:266-287`。
- 云开关：三档并存 `ENABLE_SHADER_CLOUDS` / `ENABLE_VANILLA_CLOUDS` / `ENABLE_BLOCKY_CLOUDS`（`config:20-23,92`），另有 `ENABLE_CLOUD_SHADE` 与 `CHEAP_CLOUD_SHADE` 两档云影质量。（补注：`ENABLE_VANILLA_CLOUDS` 实际只被 `P:shaders/world-1/gbuffers.glsl:177` 消费——只影响下界原版云；主世界在 `ENABLE_SHADER_CLOUDS` 开启时由 `P:shaders/world0/gbuffers.glsl:194-196` 直接 `discard` 原版云几何。）
- 雾：`P:shaders/programmes/musk_rose_config.glsl:4-5,96-101` 用 `FOG_LINEAR 9729` / `FOG_EXP 2049` 两个魔数（即 OpenGL 的 `GL_LINEAR`/`GL_EXP` 枚举值）作为 `FOG_QUALITY` 的取值，参数为 `FOG_HEIGHT`、`FOG_DISTANCE`、`FOG_DENSITY` 及各自的 `_UNDERWATER` 变体。
- 光照颜色：**每种光源的 RGB 都由用户滑杆直接给出**——`P:shaders/programmes/musk_rose_config.glsl:32-49`（pointlight / moonlight / sunlight_day / sunlight_set / skylight 各三通道），强度另有 `UNLIT_AREA_BRIGHTNESS`、`AMBIENTLIGHT_INTENSITY`、`POINTLIGHT_INTENSITY`、`SUNLIGHT_INTENSITY`、`SKYLIGHT_INTENSITY`、`MOONLIGHT_INTENSITY`（`:51-57`）。

### 2.6 配置面
- `P:shaders/programmes/musk_rose_config.glsl` 共 109 行，几乎全是滑杆定义；`P:shaders/shaders.properties:21` 的 `sliders=` 一行把全部滑杆再列一遍（含 15 个 RGB 通道、6 个强度、5 个雾参数、风与雨、水面参数），`:23-31` 用 `screen=` 组织成 8 个设置页。
- 每档滑杆把 0.00~1.00 的**全部 101 个刻度**显式写进注释（例如 `:32`、`:59-60`），使设置页可以逐 0.01 调节。

## ③ Astra 可借鉴点

1. **离线烘焙大气 LUT + 运行时纯查找（用 colortex 当 LUT 载体）** ★本报告首选
   技术要点：把物理大气散射（128 步球壳积分）放进**可独立运行的一次性生成器**（`P:shaders/textures/atmosphere.glsl`，能在网页版 shader 编辑器直接跑），产物是 Rayleigh/Mie 两张 PNG；运行时经 `texture.<stage>.colortexN=` 绑定后直接查表——代价从"每像素几十步积分"降到"一次纹理采样"。Astra 现在用解析多向调色板（`A:global/atmosphere/sky_gradient.glsl`）与 Minishita 近似（`A:global/atmosphere/sky_minishita.glsl`）替代物理散射，代价更低，但视角依赖色带、zenith 变暗、臭氧吸收都是手工近似。
   出处：`P:shaders/textures/atmosphere.glsl:1,21,23,26-32,54-99,101-114`（生成器全貌）、`P:shaders/shaders.properties:1-19`（运行时绑定，含末地独立一套）、`P:shaders/programmes/musk_rose_config.glsl:14`（噪声分辨率）。
   Astra 对应：同上两文件；纹理绑定 Astra 已在用（`A:shaders.properties` 有 `texture.*` 声明，未逐行核对）。
   迁移难点与工作量：**中**。(a) 生成器要重写成 Astra 的坐标/太阳角约定，并产出与 HDR 管线匹配的数值范围（曲线成对性见 ③11）；(b) 每个用到天空的 stage 都要重复声明绑定；(c) 要决定 LUT 只服务天空还是兼顾云与雾（复用才有成本优势）。LUT 是预烘焙的，无法响应 Astra 的天气/云量/维度调色，只适合"太阳高度角→天空色"这一层。

2. **4 行的环境 BRDF 解析拟合（补 Astra 的环境镜面缺口）**
   技术要点：`R` 为粗糙度，仅用 `R`、`NdotV` 与 `F0` 就算出环境 BRDF 的 A/B 两项（":10-16" 的 4 行），完全不需要预积分 LUT。这是 UE4 移动端方案的公开拟合（注释给出出处）。
   出处：`P:shaders/programmes/utils/musk_rose_pbr.glsl:10-16`。
   Astra 对应：**Astra 缺这一环**。已核验：Astra 的镜面路径只有 `A:lib/sky_reflection_cache.glsl:29` 的 `textureLod(colortex11, vec2(u,v), 0.0)`——**固定 mip 0，未按粗糙度分级，也没有环境 BRDF 项**；全仓 `grep` 环境 BRDF 拟合的常数（如 `-0.0275` / `0.0425`）零命中；Astra 的 GGX/Fresnel 只出现在水与末地石等具体材质（`A:global/water/surface.glsl:183`、`A:lib/end_surface.glsl:28`、`A:global/dimension/nether_reflection.glsl:20` 提到 Fresnel 已被接收端雾衰减）。（补注：限定为**共享天空缓存这条路**——下界 SSR 已有 roughness→lod（`A:global/dimension/nether_reflection.glsl:61-62`），主世界已有"粗糙度→穹顶收敛"（`A:global/dimension/overworld.glsl:49-50,56-60`）；缺"粗糙度→mip 模糊"与 BRDF，见 ③8，原结论未变。）
   迁移难点与工作量：**低**：4 行纯 ALU、无新资源/pass。**前置依赖**：粗糙度分级 mip 链（与 Glimmer 报告 ③-2 同方向）须一起做，否则只有 BRDF 项而无随粗糙度模糊的入射辐射。Astra 缓存 `colortex11` 的 mip（补注：已解决——**确实没有 mip**，全仓仅 `A:program/display.fsh:35,38`、`A:program/nether_reflection.fsh:24` 三处声明，需新开；本包缓存自带 mip（`P:shaders/world0/composite2.glsl:12`），见 ③8）。

3. **阴影畸变的"立方根"形式 vs Astra 现行的"径向长度"形式（对照，非新增）**
   技术要点：本包用 `pow(|x³|+|y³|, 1/3) + k`（`P:shaders/programmes/utils/musk_rose_shadow.glsl:27-34`），Astra 用 `length(pos) + k`（`A:lib/distort.glsl:19-21`）。两者都把密度向玩家集中，但**径向（圆对称）把密度均分到各方向，立方根（超椭圆）在坐标轴方向覆盖更大**——对屏幕对齐视锥体，轴方向即画面中央上下左右，超椭圆更省 texel。
   出处：`P:shaders/programmes/utils/musk_rose_shadow.glsl:27-34`。
   Astra 对应：`A:lib/distort.glsl:9-30`（Astra 的注释甚至给出了块/texel 的完整公式与 `SHADOW_DISTORT_CORE = 25.6` 的调优依据，来源为 Steadfast 0.8.0）。**Astra 的推导与注释更完整**；本条不是"抄"，而是"是否存在可对比的第二变量"：把指数 3 换成其他值即成为独立的画质/性能旋钮。
   迁移难点与工作量：**低**（改一个函数），但**收益未经实测**，且会改变现有细节分布与 `shadowDistanceRenderMul = 1.5` 的配合（见 `A:lib/distort.glsl:15`）；仅在确需重分配阴影细节时作候选。

4. **导数法线 SSAO：省一张法线缓冲（但 Astra 不应改）**
   技术要点：`normalize(cross(dFdx(viewPos), dFdy(viewPos)))`（`P:shaders/programmes/utils/musk_rose_ssao.glsl:43`）——法线完全由深度差求得，不需要法线缓冲；配合"半径随深度反比"（`:45`）与 25 点固定盘（`:4-30`）即可出一个便宜的 AO。
   出处：`P:shaders/programmes/utils/musk_rose_ssao.glsl:4-63`。
   Astra 对应：SSAO 用独立的半分辨率环境光/法线附件（README 记载"法线 RGBA8、顶点 AO 7 位存于 A 通道"），且**方向性天光需要 bent normal**（"可见度加权方向均值"存 colortex26）；AO 材质入口 `A:lib/ao_material.glsl:3-6`（接收体判定 `isEyeInWater == 0 && (material == 0u || material >= 11u)`）。
   **结论：不建议迁移。** 导数法线给不出 bent normal
   迁移难点与工作量：**不适用**（已判定不迁移）。

5. **POM（视差遮蔽映射）实现**
   技术要点：`P:shaders/programmes/utils/musk_rose_pom.glsl`（59 行）提供带步数控制的视差深度偏移。
   出处：`P:shaders/programmes/utils/musk_rose_pom.glsl:1-59`（初稿未细读；2026-10-02 已读，见 ③10）。
   Astra 对应：Astra 已有视差循环（`A:global/water/surface.glsl` 曾加入 `stepLength<=0` 中断与 `parallaxStrength`，见批次一账本；未逐行核对 POM 是否覆盖所有材质）。
   迁移难点与工作量：**中**。**本项为线索性记录，未做对比分析**——因本次未读该文件内部，不能给出可判定结论。

6. **同一 LUT 资产按维度准备两套（末地独立大气）**
   技术要点：主世界与末地各有一套 Rayleigh/Mie PNG（`P:shaders/shaders.properties:1-7`），末地的大气常数与主世界不同。这是一条**维度特化资产**的组织样本。
   出处：`P:shaders/shaders.properties:1-7,13-19`。
   Astra 对应：Astra 的末地是 Kerr 黑洞天空（`A:global/dimension/end_kerr.glsl` 等），已有独立的维度天空，无需 LUT。
   迁移难点与工作量：**不适用**——仅作为"资产按维度成套准备"的组织参照。

7. **雾质量的两档枚举式开关**
   技术要点：用 `FOG_LINEAR 9729` / `FOG_EXP 2049` 作为 `FOG_QUALITY` 的取值（`P:shaders/programmes/musk_rose_config.glsl:4-5,96`），配置语义即 OpenGL 枚举，阅读者一眼可辨。
   出处：同上。（补注：消费点 `P:shaders/world0/composite2.glsl:29-40`，三分支 9729=GL_LINEAR / 2048=GL_EXP / 2049=GL_EXP2；`config:4-5` 把 `FOG_EXP` 定义成 **2049**，故两档滑杆实际是 GL_EXP2 与 GL_LINEAR，`2048` 分支不可达——命名与枚举值不一致，行为无碍。）
   Astra 对应：`A:global/atmosphere/fog.glsl`（235 行，含谷雾 `fog_valley_mist:67`、晨雾权重 `fog_morning_air_weight:79`、空气透视 `fog_air_perspective:208`、群系染色 `fog_biome_tint:230`）。
   迁移难点与工作量：**不适用**（Astra 的雾模型维度远高于此）；上文那处 `FOG_EXP`/`GL_EXP2` 的命名不一致仅作记录。

8. **环境镜面的完整成对链路：反射缓存 + 粗糙度→mip + 环境 BRDF（第 2 条的补强）**
   技术要点：(a) `composite1` 把"LUT 天空反射 + SSR 镜像"合进 `colortex6`：天光 >0.6 时按 `smoothstep(0.6,1.0,uv1.y)` 混入 `reflect(pos0,fNormal)` 方向天空色（`P:shaders/world0/composite1.glsl:83-94`、`:89-94`），`ENABLE_SSR` 时用 200 步屏幕光线（`:96-101`，出处 sad 的 Water-Only-Shaders，`:22-25`）或镜像 UV（`:102-107`）覆盖，写完 `:117-118`（`P:shaders/world0/composite1.glsl:83-118`）。(b) 粗糙度→mip：`colortex6MipmapEnabled`（`P:shaders/world0/composite2.glsl:12`）+ `textureLod(colortex6, uv, REFLECTRION_BLUR_INTENSITY + roughness*ROUGHNESS_BLUR_INTENSITY)`（`:79`）= `mip 0.5+5R`（`P:shaders/programmes/musk_rose_config.glsl:87-88`），`R=(1-smoothness)²`（`P:shaders/world0/gbuffers.glsl:187`，水面 `:169`、写 colortex5 `:219`）。(c) 能量拆分 `albedo *= 1.0-reflectance; albedo += reflectedImage+reflectedLight;`（`P:shaders/world0/composite2.glsl:90-91`，F0 于 `:77`）；方向光占比经同一 mip 当镜面遮蔽（`:12,77,79-80,84-91`、`P:shaders/world0/deferred.glsl:96,103`）。
   Astra 对应：`colortex11`（`A:lib/sky_reflection_cache.glsl:5-6`；每帧重写 `A:program/sky_reflection_cache.fsh:8,10-17`）消费端固定 mip 0（`A:lib/sky_reflection_cache.glsl:20-30` 的 `:29`），另见 `A:global/dimension/overworld.glsl:56-60`、`A:program/sky_irradiance.fsh:27`；下界 SSR 另有 roughness→lod（`A:global/dimension/nether_reflection.glsl:61-62`）。
   迁移难点与工作量：**中**：(a) `colortex11` 无 mip（仅 `A:program/display.fsh:35,38`、`A:program/nether_reflection.fsh:24` 三处），且每帧重写、含云（`A:program/sky_reflection_cache.fsh:13-16`）；(b) HDR R11F vs 8-bit 表，`0.5+5R` 需重标定。同第 2 条做。

9. **阴影的 RGBA 累加器：把 N·L 折进遮蔽量（对照，不迁移）**
   技术要点：阴影是 `vec4` 累加器：不透明遮挡 `+= vec4(0,0,0,1)`、半透明遮挡 `+= texture(shadowcolor0,…)`（着色阴影颜色与强度由该纹理携带，水面焦散经此入场景，`P:shaders/world0/shadow.glsl:26-28`），累加后除采样数（`P:shaders/world0/deferred.glsl:62-74`）。关键行 `shadows.a = 1.0 - mix(0.0, 1.0 - shadows.a, diffuse)`（`:77`，`diffuse = max(0, dot(shadowLightPos, fNormal))` 于 `:60`）**同时完成 N·L 衰减与遮挡**（受光但 N·L=0.5 得 0.5 强度，`P:shaders/programmes/musk_rose_lights.glsl:41-53`）——本包直射光链**没有独立 N·L 乘法**。配套：16 点固定盘 + Bayer64 抖动偏移（`P:shaders/programmes/utils/musk_rose_shadow.glsl:4-20`、`P:shaders/world0/deferred.glsl:66-67`、`P:shaders/programmes/utils/musk_rose_dither.glsl:7-15`）；偏置为深度偏移、随畸变因子平方与掠射角放大（`P:shaders/programmes/musk_rose_position.glsl:30`，`SHADOW_BIAS 0.03` 于 `P:shaders/programmes/musk_rose_config.glsl:29`）。其余 refs：`P:shaders/world0/deferred.glsl:60,62-77`、`P:shaders/programmes/musk_rose_position.glsl:22-33`、`P:shaders/programmes/musk_rose_config.glsl:29-30`。
   Astra 对应：采样更精细——`textureGather` 四角（`A:global/lighting/shadowmap.glsl:104-133`，`:112-130`）、逐角保留离散 caster、两种过滤模式（`:38-44,91-103`）；偏置是世界空间法线偏移 `1.5*length(raw.xy) + 0.20*(1-N·L)`（`:194-197`，`shadowGrazingBias` 于 `:155`）。
   迁移难点与工作量：**低，但不建议**：可借鉴两条设计变量（`vec4` 承载着色阴影；N·L 折进遮蔽省一次乘法、交界线连续），但 Astra 有独立 N·L、AO/方向性天光依赖"遮蔽"语义纯度。**保持对照记录。**

10. **POM 实测判定（第 5 条的补强：本项现已逐行读）**
   技术要点：(a) **切线基由屏幕导数求得**（`P:shaders/programmes/utils/musk_rose_pom.glsl:4-15`；用 UV/位置导数反解副切线，`:14` 以 `dot(…)>0.0 ? T : -T` 校正手性后 `transpose`）→ 不需要顶点切线；(b) **图集归一化** `tanPos.xy /= atlasSize.xy / textureResolution`（`:31`、`:44`，`textureResolution = 16` 于 `:22`），把贴图集缩放折进步长；(c) **前向 12 步 + 独立自阴影 12 步**（`:34-40`、`:48-57`，`parallaxDepth 0.3` 于 `:24`，自阴影命中即 `shadows = 1.0`，`:51-53`）。高度取 `normals.a`（`:17-19`），法线由 `normals.rg` 重建（`P:shaders/world0/gbuffers.glsl:129-131`），高度另存 `colortex8.b`（`:222`）。
   出处：`P:shaders/programmes/utils/musk_rose_pom.glsl:4-15,17-19,21-40,42-57`、`P:shaders/world0/gbuffers.glsl:94-95,129-131,222`。
   Astra 对应：**无地形视差**——`parallax` 只在水中（`A:global/water/surface.glsl:293-313` 4 步自适应、`:341-347` 距离/掠射淡出；`A:global/water/caustics.glsl:35`）；地形只做"纹理色→光滑度"（`A:lib/rock_material.glsl:7-19`），且不读 LabPBR 材质纹理（全仓无 `MC_NORMAL_MAP`/`MC_SPECULAR_MAP`/`normals`）→ 高度场无数据来源。
   迁移难点与工作量：**高，不建议近期做**：(a) 高度图来源=LabPBR 互操作（等于吞下 ④ 表"材质粗糙度来源"）或程序化现造；(b) 每像素多 12 次高度+12 次自阴影采样且需太阳方向，而 Astra 材质阶段是纯查表；(c) 图集归一化两行须按 Astra 约定重写。

11. **大气 LUT 的坐标约定与传输曲线：LUT 与消费端必须成对搬运（第 1 条的补强）**
   技术要点：(a) **两轴都是仰角**——生成器把 `uv.x`/`uv.y` 各映射成一个方向的 y 分量（`P:shaders/textures/atmosphere.glsl:109-110`，方位角固定同平面），运行时 UV 照此构造 `vec2(shadowLightPos.y, viewDir0.y)*0.5+0.5`（`P:shaders/world0/deferred.glsl:105`、`P:shaders/world0/composite1.glsl:90`、`P:shaders/world0/composite2.glsl:105`）。(b) **抖动=缩放半径**——仅 deferred 处乘 `mix(0.85, 1.0, bayerX64(gl_FragCoord.xy))`（`P:shaders/world0/deferred.glsl:105`，宏见 `P:shaders/programmes/utils/musk_rose_dither.glsl:7-15`），半径收缩 0~15% 压 8-bit 色带。(c) **传输曲线成对**——生成端 `1-exp(-x)`（`P:shaders/textures/atmosphere.glsl:38-40,98`，mie 另乘 10 于 `:95`），消费端 `mix(0.2,2.0,·)`/`mix(4.0,40.0,·)`（`P:shaders/programmes/musk_rose_sky.glsl:176-178`）再 `1-exp(-1*total)`（`:183`）：**PNG 值不是辐射亮度**。其余 refs：`P:shaders/textures/atmosphere.glsl:38-40,95,98,109-112`、`P:shaders/programmes/musk_rose_sky.glsl:150-184`、`P:shaders/world0/deferred.glsl:105-106`、`P:shaders/world0/composite1.glsl:89-94`、`P:shaders/world0/composite2.glsl:105-107`。
   Astra 对应：解析调色板 + Minishita（`A:global/atmosphere/sky_gradient.glsl`、`sky_minishita.glsl`）+ 每帧重写的 `colortex11`（`A:program/sky_reflection_cache.fsh`）+ SH9 天光（`A:lib/sky_directional.glsl:12-26`）。可先做的小件：查找表 UV 加 Bayer 抖动压色带；雾色与天空色同源（`P:shaders/world0/composite2.glsl:105-108`，另乘 `eyeBrightnessSmooth.y/240` 于 `:74`），Astra 对应物是 `skyFogStrength` 调用点叠加（`A:global/atmosphere/fog.glsl:18,30-32`）。
   迁移难点与工作量：**中高**：(a) 方位角退化在本包内自洽，但 Astra 的太阳前向散射、云影、四色方案与末地/下界天空都需要方位角——LUT 只服务主世界"太阳高度角→天空色"才划算；(b) 必须连消费端曲线一起搬并重标定到 HDR 曝光链。

12. **逐光源 `vec4(颜色, 强度)` 合成 + 三条光照曲线**
   技术要点：六类光各返回 `vec4`（`.rgb` 色、`.a` 强度），由 deferred 统一相加（`P:shaders/world0/deferred.glsl:82-94`）：`getAmbientLight`/`getSkylight`/`getSunlight`/`getMoonlight`/`getPointlight`（`P:shaders/programmes/musk_rose_lights.glsl:17-27,29-39,41-53,55-65,67-76`）。三条可搬曲线：(a) 点光 lightmap 五次幂 `uv1.x^5`（`:23`、`:72`）；(b) 直射雨天乘子 `(1-rainStrength)*RAIN_CUTOFF`（`:35,49,61`，`RAIN_CUTOFF 0.70` 于 `P:shaders/programmes/musk_rose_config.glsl:62`）；(c) 弱光区滑杆 `UNLIT_AREA_BRIGHTNESS`（`:22`，`P:shaders/programmes/musk_rose_config.glsl:51`）与夜视同链。一处边界：`AMBIENTLIGHT_INTENSITY*(1.0-occlusion)`（`:24`）意味着 AO 只乘环境光；着色阴影则混进光色而非强度（`mix(sunlightCol, shadows.rgb, shadows.a)`，`:47`）。
   出处：`P:shaders/programmes/musk_rose_lights.glsl:17-27,29-39,41-53,55-65,67-76,78-82`、`P:shaders/programmes/musk_rose_config.glsl:32-57,62`。
   Astra 对应：Astra 在 `A:global/lighting/blocklight.glsl`（194 行）与 `diffuse.glsl`（490 行）做同类但更细：`blocklightSuppression`（`:88-105`）、四次幂曲线（`:75`、`:122-136`）、手持光独立一路（`:98`、`:105`）、雨天/夜晚抑制在 CPU 侧传入（`:46-48`）；AO 走 `A:lib/ao_resolve.glsl:54-92`。
   迁移难点与工作量：**低（多为"已有更细版本"）**：(a) `vec4` 约定无需改；(b) 五次幂可作为 `blocklight.glsl` 候选曲线（现四次幂）；(c) `RAIN_CUTOFF` 是"雨天全局乘子"的现成开关形态；(d) "AO 只乘环境光"与 Astra 的 `min(vertexAO, SSAO)` + SH 换向语义不同，不建议对齐。

## ④ Astra 已有对应实现（对照）

| 主题 | Astra 现状（文件:行） | 两边对比 |
|---|---|---|
| 阴影畸变 | `A:lib/distort.glsl:9-30`（径向 `length(pos)+k`，`SHADOW_DISTORT_CORE 25.6`，注释含块/texel 公式，源自 Steadfast） | 两家都有；本包是立方根/超椭圆（`P:shaders/programmes/utils/musk_rose_shadow.glsl:27-34`），**Astra 推导更完整**。误差：Astra 的常数按 256 格影距反推，换形式须整体重调。 |
| 阴影采样 | `A:global/lighting/shadowmap.glsl:177,187,194`（畸变后投影，软件/硬件比较模式） | 本包固定 16 点盘（`P:shaders/programmes/utils/musk_rose_shadow.glsl:4-20`）。**未逐行核对 Astra 的核点数与分布**，故不判优劣。（补核对：Astra 为 `textureGather` 四角 + 逐角离散 caster（`A:global/lighting/shadowmap.glsl:104-133`），原判保留、"未核对"作废。成本：本包按采样数平均着色阴影（`P:shaders/world0/deferred.glsl:70-74`）；抖动偏移（`:66-67`）对应 `A:lib/bayer.glsl:10-25`、`A:lib/dither.glsl:10-21`） |
| SSAO 法线 | 独立法线附件（半分辨率 RGBA8，README 记载）+ `A:lib/ao_material.glsl:3-6` | 本包用导数法线（`P:shaders/programmes/utils/musk_rose_ssao.glsl:43`）省一张缓冲；**Astra 的代价换来 bent normal**，不可直接替换。成本：本包省法线带宽、深度不连续处朝向易错（`:45-59` 掩盖）；Astra 用边缘感知重建（`A:lib/ao_resolve.glsl:19-52`） |
| 环境镜面 BRDF | `A:lib/sky_reflection_cache.glsl:29`（固定 mip 0）；全仓无环境 BRDF 拟合 | **Astra 缺这一环**；本包 4 行拟合（`P:shaders/programmes/utils/musk_rose_pbr.glsl:10-16`）可直接补，但需与粗糙度 mip 链配套。误差：拟合近似 + 8-bit 缓存量化叠加（完整链路见 ③8）。 |
| 材质粗糙度来源 | Astra 用方块身份/原始纹理（README 记载；`A:lib/rock_material.glsl:7-19`） | 本包有 `AUTO_GENERATION` 与 `LAB_PBR` 两条路（`P:shaders/programmes/musk_rose_config.glsl:10-11,90`）。**Astra 更省但覆盖窄**；LabPBR 是 Astra 没有的能力（全仓无 `MC_SPECULAR_MAP`/`MC_NORMAL_MAP`）。误差：LabPBR 观感不可控；自动生成以亮度平方当自发光（`P:shaders/world0/gbuffers.glsl:162-164`）会误判亮色方块。 |
| 大气 | 解析调色板 + Minishita（`A:global/atmosphere/sky_gradient.glsl`、`sky_minishita.glsl`），无 LUT | 本包离线 LUT（`P:shaders/textures/atmosphere.glsl` 生成 + `P:shaders/shaders.properties:1-19` 绑定）。**Astra 更省且能响应天气；本包低太阳角散射更正确**。误差：LUT 静态、方位角退化（③11）。 |
| 雾 | `A:global/atmosphere/fog.glsl:67,79,208,230`（谷雾/晨雾/空气透视/群系染色） | 本包仅 `FOG_HEIGHT`/`FOG_DISTANCE`/`FOG_DENSITY` ×（空气/水下）两套（`P:shaders/programmes/musk_rose_config.glsl:96-101`），**Astra 更细**。成本：本包更省（高度项一行 `exp2(fragPos0.y·(-1/FOG_HEIGHT))·FOG_DENSITY`，`P:shaders/world0/composite2.glsl:99`；雾色复用 LUT 同仰角值 `:105-108`），但该雾色只有仰角维度。 |
| 水面 | `A:global/water/`（折射/焦散/SSR/光束/吸收等） | 本包开关齐备（`P:shaders/programmes/musk_rose_config.glsl:68-88`）但规模小（`musk_rose_water.glsl` 62 行），**Astra 更完整**。成本：本包资产更省（一张 1024² `voronoi.png` 驱动波浪/焦散/云，`P:shaders/programmes/musk_rose_water.glsl:4-5`、`P:shaders/programmes/musk_rose_sky.glsl:10-12`），代价是同频谱且焦散借道 shadowcolor（`P:shaders/world0/shadow.glsl:26-28`）。 |
| 光色配置 | 66 个 RGB 通道（`docs/README.md:15` 记载） | 本包 15 RGB 滑杆 + 6 强度（`P:shaders/programmes/musk_rose_config.glsl:32-57`），**Astra 覆盖更大**。成本：本包更省；直射光无独立 N·L（折进阴影量，`P:shaders/world0/deferred.glsl:77`），改光色会同时影响明暗交界（③9/③12）。 |
| 末地天空 | Kerr 黑洞 + 吸积盘（`A:global/dimension/end_kerr.glsl`、`end_plasma.glsl`、`end_disc_profile.glsl` 等） | 本包只换一套 LUT（`P:shaders/shaders.properties:1-7`），**Astra 独有**。成本：本包仅多两张 PNG + `#if defined WORLD1` 分支（`P:shaders/programmes/musk_rose_sky.glsl:269-284`）；包内只有一套生成器常数（`P:shaders/textures/atmosphere.glsl:26-32`），末地 PNG 常数无记录、**无法复现**。 |
| 视差 / POM（地形） | `A:global/water/surface.glsl:293-313`（4 步自适应，仅水面）+ `A:lib/rock_material.glsl:7-19`（地形只映射光滑度） | 本包有完整地形 POM（`P:shaders/programmes/utils/musk_rose_pom.glsl:21-57`，见 ③10）。**省：Astra**（零高度采样）。误差：Astra 无高度图来源（不读 LabPBR `normals`）；本包 `parallaxDepth 0.3`/`textureResolution 16` 硬编码、自阴影 0/1 硬边（`:46-57`）。 |
| 阴影偏置 | `A:global/lighting/shadowmap.glsl:194-197`（世界空间法线偏移 `1.5·\|raw.xy\| + 0.20·(1-N·L)`） | 本包是深度偏移 `0.03·distortFactor²/\|N·L\|`（`P:shaders/programmes/musk_rose_position.glsl:30`）。**省：本包**。误差：本包 `1/\|N·L\|` 掠射无上界（`P:shaders/world0/deferred.glsl:60` 只有 `max(0,·)`），靠 `:77` 折进遮蔽吸收；Astra 两项有界（末地另有分支 `:157-189`）。见 ③9。 |
| 反射缓存粗糙度响应 | `A:lib/sky_reflection_cache.glsl:29`（固定 0）+ `A:global/dimension/overworld.glsl:49-50,56-60`；`A:global/dimension/nether_reflection.glsl:61-62`（下界 SSR 有 roughness→lod） | 本包开 mip 并按 `0.5+5R` 取样（`P:shaders/world0/composite2.glsl:12,79`，见 ③8）。**省：Astra**（无 mip 带宽/重标定），但只有"反射变淡"而非"变糊"。误差：`colortex11` 无 mip 声明（`A:program/display.fsh:35,38`、`A:program/nether_reflection.fsh:24` 仅三处）且每帧重写（`A:program/sky_reflection_cache.fsh:10-17`）；本包用 8-bit 表 + 半径抖动（`P:shaders/world0/deferred.glsl:105`）掩盖色带，取样最多偏置 15%。 |
| 雨滴涟漪 | `A:global/atmosphere/weather.glsl:74-117`（128×7680 预烘焙 60 帧 + 足迹滤波） | 本包过程式 ripple splatter（`P:shaders/programmes/musk_rose_rain.glsl:10-77`，`:89-99` 有限差分法线）。**省：本包**（零资产/带宽）。误差：本包按世界坐标取模、无足迹滤波，远处混叠；雨纹另用 `uv1.y > 0.85` 天光门控（`P:shaders/world0/gbuffers.glsl:172-177`）。 |


## ⑤ 借鉴可行性（许可证层面）

**CC0-1.0，本批次最宽松**。行号：`P:LICENSE:3`（"CC0 1.0 Universal" 标题）、`P:LICENSE:35-40`（弃权声明正文）、`P:LICENSE:40-43`（Copyright and Related Rights 定义；**2026-10-02 修正**：初稿引作 `:42`，定义起点是 `:40`）、`P:LICENSE:66`（弃权标的）。

- **代码级复用允许**：CC0 弃权全部版权与相关权利，不要求署名/同类许可、无传染性——**本批次唯一可直接搬运代码段的包**（MIT/BSD 需留版权声明、CC-BY 需署名、GPL 有传染性、CC-BY-NC-SA 有非商业与同类限制）。
- **仍建议保留出处登记**：CC0 不强制，但 Astra 的 `THIRD-PARTY.md` 已在登记来源，成本为零。
- **三处非 CC0 边界**（修正：初稿写"两处"但列了三条）：(1) `P:shaders/programmes/utils/musk_rose_ssao.glsl:34-37` 来源 SSDO by Yuriy O'Donnell（附 `github.com/kayru/dssdo`），上游许可不由本包 CC0 覆盖；(2) `P:shaders/programmes/utils/musk_rose_shadow.glsl:22-25` 的畸变来自 Builderb0y（附 Discord），建议按方法重写；(3) `P:shaders/textures/credits.txt:1` 的贴图 `dirtyLens.png` 有独立来源，不要连带搬运。
- **另一条边界**：Astra 的 `A:lib/distort.glsl:4-6` 已从 Steadfast（GPL-3.0-or-later + Section 7 附加条款）取了阴影畸变投影公式，该文件已被 GPL 血统覆盖——**不要把 Musk Rose 的畸变代码直接搬进这个文件**；③3 的对照实验应放在独立文件并注明"方法对照，非代码移植"。

## ⑥ Top3 优先建议（按 收益/工作量 排序）

1. **环境 BRDF 4 行拟合 + 天空缓存粗糙度 mip（③2）** —— 收益：给所有材质的**环境镜面**补上物理正确的粗糙度响应，这是 Astra 唯一"完全缺失"的一环（已核验 `A:lib/sky_reflection_cache.glsl:29` 固定 mip 0、无 BRDF 项）。工作量：低（BRDF）+ 中（mip 链，与 Glimmer 报告同方向合并做）。**建议先做**：不引入新 pass、不动管线结构。
2. **离线烘焙大气 LUT 的可行性预研（③1）** —— 收益：用"一次纹理采样"换掉手工调色板的视角依赖色偏；工作量：中。**开工前须回答**：(a) LUT 只由太阳高度角驱动，天气/云量/四色方案要不要再叠调制、还剩多少收益？(b) 末地有 Kerr 天空、下界有独立雾与彩光，只服务主世界是否划算？(c) 生成器要用 Astra 坐标与色域重写并纳管，是否接受双份维护？建议先做"单 composite 取样对比解析天空"的对照实验。
3. **阴影畸变形式的对照实验（③3）** —— 收益：同等阴影图分辨率下以密度分布换画面中央/轴方向清晰度；工作量：低。**注意许可**（⑤）：`A:lib/distort.glsl` 已有 GPL 血统，实验须放独立文件，且须与 `shadowDistanceRenderMul` 一起调（`A:lib/distort.glsl:15`）。

**暂缓项**

- **导数法线 SSAO（③4）**：判定**不迁移**（Astra 的 AO 核要产出 bent normal 供方向性天光，导数法线给不出）；记录此项只为解释现有法线缓冲带宽的用途。
- **POM（③5）**：初稿"未读实现、无法判定"，2026-10-02 已读，判定见 ③10（缺高度图数据源、每像素多 24 次采样，**不建议近期做**）。
- **末地 LUT、雾模型、水面、光色配置**：Astra 覆盖已更细，不建议回退。
- **LabPBR 资源包互操作**：属"新增产品功能"，不在本批次范围。



## 附：自抽查记录（共 13 条：初稿 1 组 + 补强核对 6 条 + 错误清单 E1-E6）

**A. 初稿核对（原 1-23 条归并为 1 组，均一致）**：P 侧 `P:LICENSE:3,35-40,40-43,66`、`P:shaders/shaders.properties:1-19`、`P:shaders/textures/atmosphere.glsl:1,21,23,26-32,54-99,101-114`、`P:shaders/programmes/utils/musk_rose_shadow.glsl:4-20,27-34`、`P:shaders/programmes/utils/musk_rose_ssao.glsl:34-37,43,45`、`P:shaders/programmes/utils/musk_rose_pbr.glsl:10-16`、`P:shaders/programmes/musk_rose_config.glsl:4-5,10-11,14,16-18,59-60,90,96`、`P:shaders/textures/credits.txt:1`；A 侧 `A:lib/distort.glsl:4-6,16-21`、`A:lib/sky_reflection_cache.glsl:29`、`A:lib/ao_material.glsl:3-6`、全仓环境 BRDF 常量 `grep` 零命中、`A:global/atmosphere/fog.glsl:67,79,208,230`。（原 23 条在本次压缩中归并；标题原写"14 条"实为 23 条，见 E4。）

**B. 2026-10-02 补强核对（6 条，覆盖 ③8-12 与 ④ 新增行，均一致）**

1. 反射缓存链（③8）：`P:shaders/world0/composite1.glsl:83-118`、`P:shaders/world0/composite2.glsl:12,77,79-91`、`P:shaders/programmes/musk_rose_config.glsl:87-88`、`P:shaders/world0/gbuffers.glsl:169,187,219`、`P:shaders/world0/deferred.glsl:96,103`；A 侧 `A:lib/sky_reflection_cache.glsl:5-6,29`、`A:program/sky_reflection_cache.fsh:8,10-17`、`A:program/display.fsh:35,38`、`A:program/nether_reflection.fsh:24`、`A:global/dimension/overworld.glsl:49-60`、`A:global/dimension/nether_reflection.glsl:61-62`——一致；`colortex11` 无 mip 声明。
2. LUT 坐标/曲线与雾枚举（③11、③7）：`P:shaders/textures/atmosphere.glsl:38-40,95,98,109-112`、`P:shaders/programmes/musk_rose_sky.glsl:176-178,183`、`P:shaders/world0/deferred.glsl:105-106`、`P:shaders/world0/composite1.glsl:89-94`、`P:shaders/world0/composite2.glsl:105-108`；`P:shaders/world0/composite2.glsl:29-40`+`P:shaders/programmes/musk_rose_config.glsl:4-5,96`（`FOG_EXP`=2049，`2048` 不可达）——一致。
3. 阴影（③9）：`P:shaders/world0/deferred.glsl:60,62-77`、`P:shaders/programmes/musk_rose_position.glsl:22-33`、`P:shaders/programmes/utils/musk_rose_dither.glsl:7-15`、`P:shaders/world0/shadow.glsl:26-28`、`P:shaders/programmes/musk_rose_config.glsl:29-30`；对照 `A:global/lighting/shadowmap.glsl:104-133,194-197`——一致。
4. POM 与材质（③10）：`P:shaders/programmes/utils/musk_rose_pom.glsl:4-15,17-19,21-40,42-57`、`P:shaders/world0/gbuffers.glsl:94-95,129-131,222`；`A:global/water/surface.glsl:293-313,341-347`、`A:lib/rock_material.glsl:7-19`、全仓无 LabPBR 采样器——一致。
5. 光源与噪声复用（③12）：`P:shaders/programmes/musk_rose_lights.glsl:17-27,29-39,41-53,55-65,67-76`、`P:shaders/programmes/musk_rose_config.glsl:51,62`、`P:shaders/world0/deferred.glsl:82-94`；`P:shaders/programmes/musk_rose_water.glsl:4-5`、`P:shaders/programmes/musk_rose_sky.glsl:10-12`、`P:shaders/shaders.properties:9-11`、`P:shaders/programmes/musk_rose_config.glsl:14`——一致。
6. 计数与命名证据（E1-E3/P3/P5）：行数 `world0/gbuffers.glsl` 338 / `world-1` 312 / `world1` 308 / `musk_rose_sky.glsl` 288；`P:shaders/programmes/musk_rose_config.glsl:30`=`SHADOW_DISTROTION`（`P:shaders/shaders.properties:21` 同名）；`P:LICENSE:40-43` 起点 `:40`；`P:shaders/world-1/gbuffers.glsl:177` 是 `ENABLE_VANILLA_CLOUDS` 唯一消费点（主世界由 `P:shaders/world0/gbuffers.glsl:194-196` discard）；`P:shaders/programmes/utils/musk_rose_bloom.glsl:1-3` 空壳。

**C. 发现并修正的错误清单（2026-10-02，逐条保留）**

- **E1** ② 2.5："288 行，本包最大的单个文件"→全包最大为 `world0/gbuffers.glsl` 338 行。已改注。
- **E2** ② 2.2：宏名 `SHADOW_DISTORTION`→包内实为 `SHADOW_DISTROTION`（`config.glsl:30`）。已补注。
- **E3** ⑤ 与旧附录第 3 条：`P:LICENSE:42` → 定义起点应为 `:40`；已改正。
- **E4** 附录标题："（14 条）"→实际 23 条。已改。
- **E5** ④ 覆盖率声明：称两行已降级，但表中并无 POM 行（POM 只在 ③5）。已改注；该声明段随本次压缩删除。
- **E6** ⑤ 非 CC0 边界小节："两处"但列了三条 → 改为"三处"。
- 精度补注 P1-P5 已并入 B 组（P1→③2/B2、P2→B3、P3→B11、P4→B7、P5→B8），不再单列。

**未核对项（统一声明）**：初稿列"未逐行阅读"的 `musk_rose_sky/water/pom/lights/rain/blur/filter/dither.glsl` 与 `world0/` 各 pass **本次已全部读取**（见附录 B 组）。**仍未逐行读**：`world-1/`、`world1/` 两套入口全部 pass、`lang/*.lang`（仅统计 `option.` 70/`value.` 4 条）、`attributes/attribute_for_all.glsl`、`uniforms/uniform_shadow.glsl`；Astra 侧 `A:global/water/absorption.glsl`、`A:global/atmosphere/stars.glsl`、`volume_fog.glsl`、`A:global/lighting/diffuse.glsl`（只读片段）。
