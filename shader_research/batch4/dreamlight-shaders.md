# dreamlight-shaders 性能调研（batch4）

日期：2026-10-03。范围：只读调研，产物仅本文件；行号相对 `reference_shaderpacks/dreamlight-shaders/shaders/`（该包 shader 根即 `shaders/`；README/LICENSE 等包根文件在引用处写 `包根`）。
去重基线：`shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`（下称「五份材料」），以及任务背景列出的 Astra 已实现手段。

## 概况

- 定位：Modrinth v1.5，115,066 下载（任务给定）。「梦幻风格化 + 彩色光照，兼顾性能」（包根 `README.txt:1-8`）。v1.5 的主要增量是水泡沫与焦散真正接线（`README.txt:15-21`）以及清理浪费取数（`README.txt:34-36`）。
- 血统：**Mellow Shader 的 remake**（包根 `README.txt:62-64`「DreamLight Shaders is a remake of Mellow Shader by TheCMK, used under the MIT License」；`LICENSE.txt:5-8` 同样声明）。Mellow 3.4.1a 已在批次一单独调研（`shader_research/mellow.md`，下称「Mellow 报告」），因此本报告只报**相对 Mellow 的增量**。结构与 Mellow 同构（`program/` 共享源 + `world0/world-1/world1` 薄壳，如 `world0/deferred.fsh:1-4`），相对 Mellow 的实质变化是**做减法**：无 shadow 程序、无 deferred1、无描边/四季/主世界体素彩光/PBR/LQ depth/4 种云风格；内存清空标志、dither、fbm_fast、`water_thickness` 之外的噪声/云/雾实现均可在 Mellow 中找到同源版本（见去重表）。
- 许可：**MIT**（`LICENSE.txt:1-2`，Copyright (c) 2025-2026 HoneyStudios；`:5-8` 保留 Mellow 版权行）。第三方 notices 见 `LICENSE.txt:29-48`：CAS（AMD MIT，实现于 `global/post/cas.glsl:1-7`）、bloom 高斯核（glsl-fast-gaussian-blur，MIT）、SMAA（Jimenez et al.）、bayer8（Shadertoy）。**代码级改编可用**，须保留 MIT 文本/版权行与第三方声明。
- 规模：整包 278 文件；`shaders/` 树 276 文件；shader 代码（.fsh/.vsh/.glsl）**4,053 行**（wc -l 口径，与任务给定一致；266 个代码文件；另有 `shaders.properties` 137 行、3 个语言文件、2 张 SMAA 图 + 1 张云噪声图 + title.png）。约一半文件是 3-4 行的维度薄壳（world0/world-1/world1 各约 45 个），纯代码集中在 `program/`（约 50 个文件）、`global/`（8 个）、`lib/`（8 个）。
- 固定事实：**全包无 shadow 程序，`shadowtex`/`shadowcolor` 全包 grep 零命中**；无 compute/SSBO/体素彩光；无自定义 LUT 文件加载（noisetex 即 `lib/cloud_noise+normal.png`，`shaders.properties:19-20` 另把两张 SMAA 图绑定到 colortex3/colortex5）。

## 管线与调度

- program 清单：`gbuffers_{armor_glint,basic,clouds,damagedblock,entities,skybasic,skytextured,spidereyes,terrain,water,weather}`、`deferred`（唯一延迟 pass：天空+云+雾+SSAO）、`composite`（godrays）、`composite2-10`（bloom 分块链）、`composite11`（bloom 合成）、`composite12`（运动模糊+TAA+曝光+tonemap+gamma+debug）、`composite13-15`（SMAA 3 pass）、`final`（DOF/锐化+显示空间调色+颗粒+暗角+8bit 抖动）、`dh_terrain`/`dh_water`。
- 调度：`shaders.properties:24-50` bloom 共 9 个 pass 按 `BLOOM` 停调度（三个维度各 9 行）；`:52-54` `composite.enabled=GODRAYS`；`:56-62` `composite13-15.enabled=SMAA`。三档 profile（`:66-68`）：FAST 关 bloom/云/水法线/反射/体积光；FANCY 默认；FABULOUS 加 SMAA/SSAO/DOF。**无 `size.buffer`/分辨率分档**（Mellow 已有 colortex5 1/4 等，本包反而没有）。
- 管线级开关：`oldLighting=false`(:2)、`vignette=false`(:3)、`underwaterOverlay=false`(:4)、`ROUND_SUN` 时 `sun=off moon=off`(:7-9)、`FANCY_CLOUDS` 时 `clouds=off`(:11-13)、`particles.ordering=mixed`(:15)、`alphaTest.gbuffers_skybasic/skytextured=false`(:125-126)、`alphaTest.gbuffers_clouds=GREATER 0.005`(:127，低配走原版云时剔透明像素)、`dhShadow.enabled=false`(:129)。
- CPU 预计算自定义 uniform：`timeAngle`/黄金比抖动 `taaJitter`/`nightStrength|dayStrength|sunsetStrength|sunriseStrength`/`sunOrMoonPosN`/`sunPosN`/`resolution`/`resolutionInv`/`isOutdoorsSmooth`（`:98-123`）——Mellow 同款体系，Astra 已实现同类（SUMMARY ②-6 首行、docs/2026-10-02 采用方案）。
- 缓冲：colortex0 主色、colortex1 bloom 分块、colortex2 SMAA 中间、colortex3/5 作 SMAA LUT 图、gaux1 TAA 历史、depthtex0/1、dhDepthTex/1；`lib/all_the_uniforms.glsl:76-81` 六个缓冲 `Clear=false`（与 Mellow `reference_shaderpacks/mellow/shaders/global/configurations.glsl:4-11` 同款）；`:85-90` 的缓冲格式声明整段在块注释内（是否被 Iris 解析未验证，见「无法判定」3）。
- 默认档（`lib/settings.glsl`）：`BLOOM`:124、`FANCY_CLOUDS`:132、`WATER_CAUSTICS`:202、`FANCY_WATER`:103、`REFLECTIONS`:105=3（翻转图）、`SSR_STEPS`:104=8 均开；`GODRAYS`:160、`HANDHELD_LIGHTS`:166、`SSAO`:170、`WATER_FOAM`:199（注释态）、`TAA_MODE`:174=0、SMAA/DOF/MOTION_BLUR/IMAGE_SHARPENING 均关。默认即「少 pass + 小固定预算」。

## 分模块性能手法清单

### 调度与阶段启停
- `shaders.properties:24-50` — bloom 全链（capture+3 级两向模糊+合成共 9 pass）按 BLOOM 整链停调度。
- `shaders.properties:52-54,56-62` — godrays / SMAA 各自 program 级停调度。
- `shaders.properties:66-68` — FAST/FANCY/FABULOUS 特性组合（含 `REFLECTIONS=0` 直接关水反射链）。
- `program/deferred.fsh:5,52-56` — SSAO 以 `#ifdef` 编译期门控并内联在 deferred 中，关闭时零成本。
- `program/composite2-10.enabled` — 关闭 BLOOM 时 9 个 pass 全部不编译（Iris 程序门控）。

### 地形光照与阴影
- `global/lighting.vsh:55-61` — 静态阴影近似：`FakeShadowFactor=smoothstep(0.85,0.96,lightmap.y)` 乘 `NdotL` 加进 `SUN_AMBIENT`，全部在**顶点级**完成；无阴影图查询。
- `global/light_colors.vsh:58-61` + `global/lighting.vsh:13-68` — 四时点天空色/直射色/环境色在顶点算成 flat varying（Mellow 光色顶点管线继承）；片元 `program/gbuffers_terrain.fsh:13-19` 仅 `texture×glcolor×MixedLights`。
- `global/lighting.vsh:26-30` — 草/叶按 `mc_midTexCoord` 上下半段给法线差异（顶点级），`program/gbuffers_terrain.vsh:8-42` 摆动植被同样只在顶点。
- `global/lighting.vsh:36-41` — 手持光在顶点写进 `lightmap.x`（幂曲线 `HANDHELD_FALLOFF_CURVE`）。
- `global/lighting.vsh:44-46` — 暗部抬升 `MIN_LIGHT_AMOUNT + screenBrightness*0.1 - 0.1` 顶点级一次。
- 无阴影程序（grep `shadowtex|shadowcolor` 零命中）；`dhShadow.enabled=false`（`shaders.properties:129`）。

### 云
- `global/sky.glsl:23-54` — 单层投影平面云：`PlayerPos.xz/(PlayerPos.y+length(xz)/6)` 映射；`fbm_clouds(CloudPos, CLOUD_QUALITY)` 一次主采样（:31），沿日月方向偏移 8 格再取一次 2-octave 吸收采样（:39）；无步进/无首命中/无历史/无体积。
- `global/sky.glsl:44-51` — 银边：对已有 `Noise`/`Absorbtion` 做带通 `smoothstep` 数学，零额外纹理采样（v1.5 删掉了此前每像素浪费的一次噪声取数，`README.txt:34-36`）。
- `program/deferred.fsh:29,42-49` — 云只在 `Depth>=1` 且 `PlayerPos.y>0` 的天空像素执行；`DIMENSION_OVERWORLD && FANCY_CLOUDS` 编译期门控。
- `program/gbuffers_clouds.vsh:8-9` — FANCY_CLOUDS 时原版云程序顶点退化 `gl_Position=vec4(-1)`（与 `clouds=off` 双保险）。
- `program/gbuffers_clouds.fsh:19-35` — 低配原版云：雾用 `len2` 代替 length，`exp(-3*HorizontalDist)` 单次；`alphaTest.gbuffers_clouds=GREATER 0.005`（properties:127）剔全透明云像素。

### 雾与大气
- `global/fog.glsl:22-30` — 边界雾：strength 先连乘 3 次（主世界共 8 次幂）再 `exp(-3x)`，每像素约 3 乘 1 exp；下界只平方一次。
- `global/fog.glsl:37-57` — 大气雾：`fbm_fast(...,1)` 单 tap 噪声扰动 + 双 `smoothstep` 高度带 + 雨天低空补偿，无步进。
- `global/fog.glsl:1-20,59-78` — 水下/岩浆/细雪三态解析雾；`get_fog_main` 对天空像素只做 lava/blindness 分支，跳过大气/边界雾（:62-74）。
- `global/sky.glsl:56-61` — 天空两带 `fogify` 有理混合（`w/(x²+w)`）。
- `global/sky.glsl:63-80` — 星场：`random(StarCoord.xz)` 单次求值复用于亮度与闪烁（v1.5 清理，`README.txt:43-45`）。
- `global/sky.glsl:82-96` — 末地双旋转 fbm 极光（2+2 octave）；`get_sky_main`(:98-109) 按维度编译期分派。

### 水与水下
- `global/water.glsl:3-8` — `water_thickness()`：一次 `depthtex1` 屏幕深度差，复用给水雾(:156)/焦散(:168)/泡沫(:199)（注释明示只付一次深度取数）。
- `global/water.glsl:10-14` — 水雾解析式 `(1-exp(-D*strength*0.08))*step(0,D)`，写进 alpha。
- `global/water.glsl:16-32` — 岸线泡沫：`smoothstep` 深度差带 + 2 次 2-octave `fbm_fast` 断带（默认关，`lib/settings.glsl:199-201`）。
- `global/water.glsl:35-52` — 焦散：两层反向旋转 `fbm_fast` + `1-|N-0.75|*2` 塑形 + `pow4` + 深度双窗口；在前向水 pass 内叠加（:166-172），无独立 pass/缓冲。
- `global/water.glsl:93-131` — SSR：步长按屏幕边界归一（:97-100）、dither 起点、`ExpectedPos.z-RealDepth>Offset.z*4` 厚度拒绝（:112）、二分细化次数 `round(Fresnel*3)`（:117）、miss 回退解析天空（:130）。
- `global/water.glsl:133-148` — flipped image 单次投影反射（`REFLECTIONS=3` 默认），校验深度/距离后取 gaux1，miss 回退天空。
- `program/gbuffers_water.fsh:34-39` — DH 深度一致性 discard；`:62` 有材质则走 `get_fancy_water`。
- `program/gbuffers_water.vsh:10-17` — 水色/群系混合在顶点算进 `glcolor`（注释「should be faster」）；`:22-40` 波浪顶点位移；`:46-48` TAA 抖动。
- `global/water.glsl:70-76` — 水法线三层纹理滚动（`lib/noise.glsl:16-26`）后归一。

### 粒子·实体·天气
- `program/gbuffers_entities.fsh:17-24` — `entityId==10101` 直接 alpha=1 跳过光照；其余 `entityColor` 混合 + MixedLights。
- `program/gbuffers_weather.fsh:13-24` — 雨条：`a<0.1 discard` 后直接 `apply_saturation(...,0.2)` + alpha 0.15；不做雾/时域/额外光照。
- `program/gbuffers_skytextured.fsh:9-11` — ROUND_SUN 时原版日月程序直接 `discard`（避免与自绘日盘叠加）。
- `program/gbuffers_spidereyes.fsh:15-17`、`program/gbuffers_damagedblock.fsh:12-16` — 低透明 discard / 无光照直通。

### 后处理与缓冲内存
- `program/deferred.fsh:11-62` — 单一延迟 pass 内完成天空+云+雾+SSAO：普通世界像素只读一次 colortex0 + 深度，手部像素（Depth<0.56）跳过雾与 AO。
- `program/composite2.fsh:5` + `program/composite2.vsh:7-9` — bloom 捕获：`colortex0MipmapEnabled=true` + 1/4 缩放视口把 colortex0 降采样写进 colortex1 的 1/4 分块。
- `program/composite3-10` + `program/composite5.vsh:8`/`program/composite8.vsh:8` — 同一 colortex1 内以 1/4、1/8、1/16 三分块做三级两向高斯（`global/post/bloom.glsl:3-19` 每 pass 6 tap），分块边界用 `clamp(coord)==coord` 防跨块渗色（:14-17）；`program/composite11.fsh:15-22` 三块按 1/i 权重合成。`global/post/bloom.glsl:22-32` 的 `blur3x3` 定义后全包无调用（死代码）。
- `program/composite12.fsh:34-50` — TAA 与运动模糊共用一次 `toPrevScreenPos`（:37）；`:15-29` 运动模糊按 `0.01666/frameTime` 归一；`:7-11` 按 `TAA_MODE/REFLECTIONS` 条件切换输出目标；`:52-57` 曝光/tonemap/gamma 合并；`:59-69` debug 视图。
- `global/post/taa.glsl:2-15` — 重投影（含 DH、手部深度跳过相机位移）；`:30-55` Catmull-Rom 快速历史重采样；`:57-68` 最近深度 4 角；`:70-83` 8 邻域 AABB；`:93-94` 出屏回退当前帧；`:118-125` offcenter rejection + 亮度差闪烁抑制。
- `global/post/ssao.glsl:12-49` — 全分辨率 8 样本 poisson AO（`dFdx` 法线、`clamp(8/Depth,0.5,2)` 自适应半径、16-48 格距离淡出、`ViewPos.z<-64` 早退）。
- `global/post/godrays.glsl:1-33` — 固定 `GODRAYS_QUALITY`(2-8) 屏幕步进，`Falloff>1` 早退（:4），天空深度加权；水下半段改用固体深度（:17-19）。
- `program/final.fsh:24-56` — DOF：`CoC<0.0005` 直接走 CAS/原始色（:35-41），否则 `DOF_QUALITY`(4-12) 螺旋采样；`:61-85` 在既有 final pass 内串联 vibrance/saturation/contrast/tonemap 下限/颗粒/暗角/8bit 抖动（不新增 pass）。
- `lib/util.glsl:75-97` — depthtex0/1 取数：仅当深度≥1（天空/DH）才读第二张 DH 深度图；`:39-45` 深度线性化复用 `near`。
- `lib/tonemap.glsl:2` — sRGB→线性用 3 次多项式（免 pow）；`:41-49` 保亮度混合避开除零。
- `program/dh_terrain.fsh:19-22` — `length(PlayerPos)<far-DH_CUTOFF` 的 DH 像素 discard，避免与主地形重叠着色；`:26-30` 世界网格随机淡出（DH_NOISE）。

## 反面印证

1. **「兼顾性能」的本质是功能缺席 + 单延迟 pass**：无阴影程序、无体素彩光、无 PBR/材质扩展、无体积雾/体积光、无独立 AO/云缓冲、无 LQ depth；帧率不来自调度技巧。Astra 已有更强的分档与阶段启停，不应回退到单 pass 合并（与 batch3 §2.4 YoFPS 的结论一致）。
2. **默认反射即廉价路径**：`REFLECTIONS=3`（`lib/settings.glsl:105`）走 flipped image，SSR 程序只在 `REFLECTIONS>=2` 时才保留 gaux1 写回（`program/composite12.fsh:48-50`）——属观感换成本，不是可迁移优化（Astra SSR 已有二分细化+出屏退出+置信度）。
3. **全分辨率 SSAO**：`global/post/ssao.glsl:12-49` 在 deferred 内对 depth 0.56-1 的像素跑 8 样本，与屏幕像素同阶；Astra 为半分辨率+保边重建。本包靠默认关藏成本，不应照搬。
4. **云模型退化换采样数**：`global/sky.glsl:23-54` 单层投影平面 + 2 次噪声采样，无体积/视差/自阴影层次，近地平线靠 `length(xz)/6` 兜底防爆；Astra 平面云已有步数分档+首次命中+独立历史，不应为省采样退化模型。
5. **`water_thickness()` 的复用只覆盖部分消费项**：水雾/焦散/泡沫共用一次深度差，但 SSR 路径仍自己 `get_depth_solid`（`global/water.glsl:105`）再读一次 depthtex1——注释说法优于实现，说明性文字不可当证据。
6. **缓冲格式声明整段在注释内**：`lib/all_the_uniforms.glsl:85-90`；与 batch2 ④-2-4 记录的 lumina/voyager 同类坑一致，照抄注释里的格式声明无效果。
7. **死代码**：`global/post/bloom.glsl:22-32` 的 `blur3x3` 全包无调用（5 tap/9 tap 两个实现并存只留注释），与 README 自称的 v1.5「清理死代码」不完全一致。
8. **TAA 闪烁抑制的风险形态**：`global/post/taa.glsl:124` 用 `(PrevColor-Color)/ClippingMaxColor` 的亮度平方——ClippingMaxColor 分量接近 0 时的数值行为无保护（Mellow 继承，Astra 未采用该形态）。
9. **原版云的双重停渲染**：`shaders.properties:11-13` 已 `clouds=off`，`program/gbuffers_clouds.vsh:8-9` 又用退化几何；两套机制冗余，且下游 fsh（:5-8）还保留 `discard` 分支。

## 新颖借鉴点

- **A 组：无。**
- **B 组：无。**
- **C 组：无。**

理由：DreamLight 是 Mellow 的 MIT remake（`README.txt:62-64`），性能机制与 Mellow 3.4.1a（批次一已单包研究）同源；逐候选比对后全部落在「五份材料已列」或 Astra 已实现范围内。v1.5 仅有的两项功能性新增（水泡沫、水焦散）对应 SUMMARY ②-2 已列的「岸线泡沫（深度差+噪声阈值）」与 Astra 已实现的「解析焦散」，均为已知类别。逐候选去重表：

| 候选（本包出处） | 对照来源 | Astra 侧证据 / 排除依据 |
|---|---|---|
| 顶点光色 flat varying + 四时点权重 CPU 化（`global/light_colors.vsh:58-61`；`shaders.properties:98-123`） | Mellow 同机制（Mellow 报告 ②/④） | 五份材料已列：SUMMARY ②-6「CPU 预计算 custom uniform」12 包印证；Mellow 报告明确光色顶点化整体不建议搬（只借关键帧下沉） |
| 静态阴影近似 `NdotL×smoothstep(skylight)` 顶点级（`global/lighting.vsh:55-61`） | Mellow `get_shadow_static`（Mellow 报告 ②阴影） | Astra 已有 `static_shadow`（`Astra/shaders/global/lighting/shadowmap.glsl:250`、`Astra/shaders/global/lighting/diffuse.glsl:260`）且 `Astra/shaders/shaders.properties:235-240` 关 SHADOWS 时停 shadow pass；类别已列 |
| 无阴影程序（全包 grep `shadowtex|shadowcolor` 零命中） | 与 batch3 Astralex/原版向包同型 | Astra 已有 SHADOWS 档与静态阴影兜底；功能省略非手法 |
| Bloom 单缓冲分块 + 顶点视口缩放 + 块界 clamp 检查（`program/composite2.vsh:7-9`、`global/post/bloom.glsl:14-17`、`program/composite11.fsh:15-22`） | batch3 §2.3 C 组「单 pass mip 打包 Bloom」（potato）、A 组「顶点视口缩放/渲染比率」（ILikeVanilla） | 已列（C 组判为高代价、收益需实测）；Astra 已是 0.25 捕获+mip 链+tap 分档，替换收益未知 |
| TAA Catmull-Rom/最近深度/AABB/offcenter/闪烁抑制（`global/post/taa.glsl:30-125`） | Mellow TAA 五模式（Mellow 报告 ②） | 已列：batch2 ⑤-3 #7、batch3 B 组 Catmull-Rom；Astra 已有 YCoCg 邻域钳制/植被历史/反应遮罩 |
| 8 样本导数法线 SSAO + 距离淡出（`global/post/ssao.glsl:12-49`） | musk-rose/drdestens/bvs 同型 | batch2 ⑤-6 明确「导数法线 SSAO 维持不迁移」；batch3 A 组已列 SSAO 距离截止（re-shaded），docs/2026-10-03 已暂缓 |
| 固定步 godrays + 早退 + 天空权重（`global/post/godrays.glsl:1-33`） | MakeUp/drdestens/kuda/pyvtron 4 包 | SUMMARY ②-3「godrays 廉价档」已列；Astra 已有 godrays 与深度低档 |
| flipped image / SSR Fresnel 细化次数（`global/water.glsl:93-148`） | Mellow `flipped_image_ref`（Mellow 报告 ③4）、batch1 Bliss Fresnel 步数 | 已列：Mellow Top5-4、SUMMARY ⑤（Fresnel 调 SSR 预算明确未采用）；Astra SSR 已有二分细化+出屏退出+置信度 |
| 岸线泡沫（`global/water.glsl:16-32`） | SUMMARY ②-2「岸线泡沫（深度差+噪声阈值）」Complementary/SDV/Shrimple | 类别已列（中期）；Astra grep `foam` 零命中，属「已列未实现」，不得计新颖 |
| 水焦散噪声层（`global/water.glsl:35-52`） | SUMMARY ②-2 焦散行；Astra 已实现解析焦散（记录于 shadowcolor0） | 已实现类别，本包更弱 |
| 三层水法线 + 顶点水色（`global/water.glsl:70-76`、`program/gbuffers_water.vsh:10-17`） | Mellow `noise_water` 同构（`reference_shaderpacks/mellow/shaders/lib/noise.glsl:9-16`） | 顶点常量/帧量下沉与解析波场候选均已列 |
| sRGB 三次多项式 `to_linear`（`lib/tonemap.glsl:2`） | batch3 A 组 vanilletix sRGB 多项式 | 已列；docs/2026-10-03 明确暂缓（会改变色域、收益无依据） |
| `dither()` 按 TAA 状态切 IGN/Bayer（`lib/noise.glsl:81-90`） | Mellow `dither/ign` 同实现（`reference_shaderpacks/mellow/shaders/lib/noise.glsl:39-47`） | Mellow 继承非增量；Astra 已有 Bayer+IGN 且抖动 CPU 化，此切换为 1 行细节，不构成可排期项 |
| `fbm_fast` 单 tap/octave 廉价噪声（`lib/noise.glsl:56-68`） | Mellow 同名函数 | Mellow 继承；噪声预算类细节在 batch3 已有多包记录，价值不足以立新点（见「无法判定」1） |
| `water_thickness` 单次深度复用（`global/water.glsl:3-8`） | 本包注释自称 | 微优化，且未覆盖 SSR（反面印证 5）；Astra 吸收/焦散路径无同址重复取数问题待查，宁缺毋滥 |
| DH 惰性第二深度取数 + cutoff discard（`lib/util.glsl:75-97`、`program/dh_terrain.fsh:19-22`） | batch2 ②-7 Voxy/DH 集成契约 | 已列；Astra 无 DH（voxy.json 为 stub），机制不适用 |
| 管线开关 `vignette/underwaterOverlay/clouds=off/particles.ordering`（`shaders.properties:2-15`） | batch3 A 组「Iris 管线级开关」 | 已列；`particles.ordering=mixed` Astra 已有（`Astra/shaders/shaders.properties:233`）；docs/2026-10-03 已暂缓关闭原版叠加 |
| 缓冲 `Clear=false` 声明（`lib/all_the_uniforms.glsl:76-81`） | Mellow `reference_shaderpacks/mellow/shaders/global/configurations.glsl:4-11` 同款 | Mellow 继承；Astra 已在历史/云等缓冲使用 `colortexXClear=false`（如 `Astra/shaders/program/cloud_screen.fsh:14`、`Astra/shaders/program/taa_resolve.fsh:18`），主缓冲仍需清，非增量 |
| 银边/雨天空压暗/月相影响等外观件（`global/sky.glsl:48-51`、`lib/settings.glsl:140-141`、`global/light_colors.vsh:50-52`） | Mellow 已研究 | 非性能手法；且 Astra 已有月相（`Astra/shaders/lib/uniforms.glsl:61,123`） |

## 无法判定项

1. **`fbm_fast` 单 tap/octave 与 Astra 噪声预算的对照未做**：本包把「雾/泡沫/焦散」用单 tap 版本、云主采样用 3-tap 版本（`lib/noise.glsl:2-7,28-40,56-68`），Astra 侧未逐函数统计不同用途的噪声 tap 数，无法判断是否存在可迁移的「按用途分噪声档」机会；且该函数为 Mellow 继承，非本包增量。
2. **`colortex0MipmapEnabled=true`（`program/composite2.fsh:5`）+ 1/4 视口是否真读 mip 未验证**：若 Iris 在声明 pass 之后才生成 mip 链，则 composite2 读的是 level 0，只是普通降采样；两种解释下的成本/画质不同，未实机验证，故不列为新颖点。
3. **`lib/all_the_uniforms.glsl:85-90` 注释内缓冲格式是否生效**：与 batch2 记录的 lumina/voyager 同类坑一致，未实机验证。
4. **`get_depth`/`get_depth_solid` 的 DH 惰性第二取数**（`lib/util.glsl:75-97`）在非 DH 环境收益为零；Astra 无 DH 支持（`voxy.json` 为 stub），暂不适用。
5. **默认档性能声明无帧时数据**：README 无任何基准，全部结论为源码级推断；实机 A/B 前不能把「smooth performance」当结论。另：本包 4,053 行中约半数是维度薄壳，规模数字不宜直接与单文件实现包对比。
