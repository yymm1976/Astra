# 第四批参考光影调研：20 款包的性能机制与 Astra 新颖借鉴点（SUMMARY-batch4）

后续实施（2026-10-04）：已完成反射重复重建／深度读取复用，以及水下备用雾和天空窗口无贡献读取裁减。候选选择、当前源码与 Iris 默认值等纠正见[第四批性能选择](../docs/2026-10-04-batch4-selected-optimizations.md)。下文未实现判断与行号描述调研时源码，不等同于当前缺陷或执行要求。

日期：2026-10-03。数据时点：Modrinth 下载量与最新版本按当日 API 实测（版本取自 `_analysis/batch4_selected.json`；下载量取自 `_analysis/batch4_top200_p1.json`/`p2.json` 两页抓取，各 100 条，本批 10 款在 p1、10 款在 p2）。
执行方式：Modrinth 按下载量排序圈选 → 20 款 zip 下载并解压至 `reference_shaderpacks/<slug>/`（原件在 `reference_shaderpacks/zips/`）→ 10 个只读调研代理逐包深挖（每代理 2 包）→ 每条借鉴点先对 `Astra/shaders` grep 核实「未实现」才允许列入。
上游输入：`shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`（前三批）、`docs/2026-10-02-shader-reference-performance.md`（10-02 采用方案）、`docs/2026-10-03-batch3-selected-optimizations.md`（10-03 batch3 选择记录）。
本报告为纯调研产出，不含对 Astra 的任何代码改动。
包内 file:line 口径：相对 `reference_shaderpacks/<slug>/shaders/`；个别包 shader 根在包根（just-colored-lighting 的根文件直接位于包根、其嵌套 `shaders/` 子树在引用处带前缀；lymboshader/monophonic-shaderpack 的路径按逐包文件写法可解析到 `shaders/` 下），一律以逐包文件标注为准。Astra 侧引用带 `Astra/shaders/` 前缀，或按逐包文件的 `A:` 约定解析（`A:` = `Astra/shaders/`）；表内包名简写（cyanide、BDS、open4es、lymbo、monophonic、stracciatella、dreamlight、truelight、zayko、sundial、butter 等）指 §1.1 对应完整 slug。

## 一、圈选与排除

### 1.1 入选 20 款（按 Modrinth 下载量降序）

| # | 包（slug） | 版本 | 下载量 | 整包规模（文件/行） | 血统 | 许可口径 |
|---|---|---|---|---|---|---|
| 1 | just-colored-lighting | 1.0.2 | 619,699 | 306 文件 / 23,391 行 | 自研（timetravelbeard）；与 Pegasus 的 gi.glsl/voxel_photons 同构 | 无 LICENSE，文件头 ARR（禁修改/再分发/代码片段）→ 思路级 |
| 2 | stereos-default+ | 2.4 | 404,156 | 64 文件（17 代码 / 1,359 行） | OptiFine 时代自研；4 个天空文件用 XorDev 模板 | 无 LICENSE → 默认 ARR，思路级 |
| 3 | simplicissimus | 1.3a | 234,519 | 118 文件 / 5,020 行 | RRe36 自研（与 Potato/SVL 同作者不同代码库） | 自定义 LICENSE（ARR；代码复用需明确许可）→ 思路级 |
| 4 | trailershaders | r1.6 | 213,983 | 50 文件 / 1,483 行 | 自研（前身 BareBone Shaders） | LICENSE 明文专有 ARR → 思路级 |
| 5 | truelight-fx-lite | v5.6.3 | 190,816 | 91 文件 / 1,910 行 | 原 TrueLight FX（Mateus A. Kreuch）→ Simon L./OGCRAFTNET 维护 | MIT（可代码级，需保留版权文本） |
| 6 | blocky-shader | 0.6.1 | 181,790 | 80 文件 / 3,112 行 | dvimidh 自研；FXAA 经 BSL，体素教程代码未接线 | MIT（FXAA 片段循 BSL 渠道） |
| 7 | dercode | 2.2 | 181,670 | 437 文件 / 31,184 行 | Bliss → Derivative main 重制分支（只报增量） | 无 LICENSE，README 自述矛盾（ARR 与「随意使用」并存）→ 保守 ARR |
| 8 | daybreak-shader | 0.2 | 175,564 | 28 文件 / 800 行 | 血统无法判定（无声明、无模板痕迹） | 无 LICENSE → ARR，思路级 |
| 9 | stracciatella-shaders | 1.6.4.1 | 170,808 | 313 文件 / 10,843 行 | DrDesten；与 drdestens-shaders 同作者同 ShaderCore（只报增量） | 无 LICENSE → ARR，思路级 |
| 10 | cyanide-shaders | 1.1 | 150,284 | 35 文件 / 921 行 | OptiFine 模板谱系（block.properties 来自 XorDev） | 自定义 AGREEMENT（有条件允许使用部分代码） |
| 11 | dreamlight-shaders | 1.5 | 115,066 | 276 文件 / 4,053 行 | Mellow 的 MIT remake（只报增量） | MIT（保留 Mellow 版权行与第三方 notices） |
| 12 | vanilla_enhance | 1.2 | 111,303 | 16 文件 / 1,151 行 | 血统无法确认（无 README/LICENSE/署名） | 无任何许可文件 → ARR，思路级 |
| 13 | bds-better-default-shaders | 1.0 | 98,489 | 18 文件 / 845 行 | XorDev 模板骨架 + 自建阴影；FXAA 来自 McNopper/OpenGL | 混合：XorDev 明示授权 + FXAA Apache-2.0 全文 + 其余无声明 → 从严按思路级 |
| 14 | lymboshader | 1.2 | 95,834 | 6 文件 / 204 行 | DorNell8 自研极简 | 无 LICENSE，readme 非正式 → ARR，思路级 |
| 15 | monophonic-shaderpack | 1.1 | 94,098 | 61 文件 / 1,457 行 | Exposa 同源精简版（相对增量为零） | 无 LICENSE → ARR；vibrance 标注 belmu（GPL）存疑 |
| 16 | open4es-renewed | v1.0.1 | 91,503 | 98 文件 / 3,403 行 | BSL + HexBR_ 阴影拼装低配改造（只报增量） | LICENSE=GPLv3 全文；BSL 来源部分授权缺失存疑 |
| 17 | butter-shaders | 1.2d | 89,468 | 218 文件 / 6,639 行 | MakeUp Ultra Fast Legacy 6.80L 的 Typon 修改版（只报增量） | LGPL-3.0 |
| 18 | zayko | 9.0 | 81,003 | 367 文件 / 22,818 行 | SkyNexusHD 自研；组件级第三方注明（Robobo1221/Lottes/Complementary） | 无 LICENSE → ARR，思路级 |
| 19 | sundial-lite | 1.2.0 | 63,002 | 356 文件 / 10,407 行 | GeForceLegend 自研；算法来源注明（Shadertoy CC0/MIT 等） | GPL-3.0 |
| 20 | vanilla-advanced | 1.0.1 | 56,788 | 30 文件 / 730 行 | ThePlaneGuy45 自研；植物波动来自 Complementary Reimagined | 无 LICENSE，readme MIT 式 + 署名要求；Complementary 部分不在该授权内 |

规模口径说明：文件数/行数按逐包文件的「整包口径」实录（代码行按 .glsl/.fsh/.vsh/.csh/.gsh 等扩展名）。三处需按任务书口径校正：just-colored-lighting 整包 306 文件 / 23,391 行，任务书「18 文件 / 4,581 行」仅指其嵌套 `shaders/` 子树（核心实现，不含包根 87 个包装程序）；sundial-lite 整包 10,407 行，任务书「3,972 行」未计 `programs/` 子目录（6,435 行实质代码）；dercode 31,184 行为同扩展名口径（.glsl/.fsh/.vsh/.csh/.gsh）；含 .inc/.frag/.vert/.comp/.geom/.tes/.tcs 全部代码共 39,117 行（12 类扩展名口径，`find`+`cat`+`wc -l` 实测复现）。规模含薄壳/资源差异，不宜跨包直接对比。
下载量说明：10 款（#1-10）取自 `batch4_top200_p1.json`，10 款（#11-20）取自 `batch4_top200_p2.json`；两页为同一次按下载量排序抓取的 1-100 与 101-200 名，批内相对次序以此为准。

### 1.2 排除规则与被排除对象

- **①已在库 76 款不重选**：前三批 62 款 + 根目录 zip 相关包（含 steadfast-shaders、kappa 等）。
- **②直系分支/编辑版排除**：astralcore（Complementary Unbound 编辑）、trickeds-shaders（Mellow 修改版）、bettervoxels（Rethinking Voxels fork）、lite-shaders（MakeUp 编辑）、truelightfx（与已选 truelight-fx-lite 同族取一）、bvsf / pyvtron-vx / eclipselite / lumina-lite / sildurs-basic（同家族变体）。
- **③定位不符**：visual-vibrance（滤镜）、vector / epoch / btb-back-to-basics / psx 系（复古整活）、lethal / somber / genesis / optimism（风格主题向）、phoxel-pt / lyrae / mcpt / vanillapuddingtart（路径追踪，Astra 已有「不引入 PT」决策）、单功能向（depthfield、reflective-vanilla、fluffy-fancy-clouds、better-stars 等）。
- **④换血披露**：首选 energy-shaders-java 下载解压后查明为原版核心着色器资源包（`assets/minecraft/shaders` + Sodium 覆盖，`zip_top_level` 不含 shaders.properties，非 Iris 光影），按 batch3 re-shaded 先例不符定位，改派备选 dercode；其 zip 与解压目录已核实移除（`reference_shaderpacks/energy-shaders-java` 不存在、`zips/` 无对应文件）。

### 1.3 调研中查明的血统修正

- **stracciatella 与 drdestens 同作者同 ShaderCore**：`core/` 目录逐文件比对仅 4 个文件有差异（dh/textures.glsl、dh/uniforms.glsl、transform.glsl、vertex_transform.glsl），README 文本一致；本批只报相对 drdestens 旧报告的增量。
- **monophonic 为 Exposa 同源精简版**：block ID 表连未更正拼写 `mincampfire_cosy_smoke` 都相同（monophonic-shaderpack/block.properties:3），`Time`/`byTime` 四关键帧混合逐式相同（lab/time.glsl:5-31 ↔ Exposa lib/time.glsl），vibrance 同注 belmu；相对 Exposa 增量为零。
- **dreamlight 为 Mellow 的 MIT remake**（README.txt:62-64；LICENSE.txt:5-8 保留 Mellow 版权行）：结构与 Mellow 同构，实质是「做减法」（无 shadow 程序、无 deferred1、无体素彩光/PBR/LQ depth）；只报增量。
- **butter 为 MakeUp Ultra Fast Legacy 6.80L 的 Typon 修改版**（README.md:1-3、`[MakeUp]`/`[Typon]` 菜单组、逐文件 LGPL-3.0 头），相对 9.5f 净增 deferred1/deferred2/composite3 三个全屏 pass + Input/ 预处理库；只报增量。
- **dercode 自述 Bliss → Derivative main 的重制分支**（README.txt:10,16）：Bliss 与 Derivative 均已研究，按「只报相对增量」处理；未做逐文件 diff，引用其机制前应回上游快照核对。

## 二、跨包汇总：经去重确认 Astra 未实现的新颖借鉴点

去重口径：每条均先对 `Astra/shaders` 做多关键词 grep（考虑不同命名），并与 10-02 采用方案文档、batch3 选择记录、前三批 SUMMARY 逐条对照后确认「Astra 无等价实现」。迁移代价为调研代理的源码级评估。本章 11 条条目由 13 个逐包原始新颖点合并而成（同族合并只发生在本章：B② 合并 stracciatella B1 + zayko C1；C① 合并 dercode C1 + sundial C1），逐包原始计数见第三章。

### 2.1 A 组：低代价、可直接排期（5 条）

| 借鉴点 | 机制 | 来源 file:line | 迁移代价与前置核实 | Astra 侧未实现证据 |
|---|---|---|---|---|
| A① 体素彩光方向性梯度提取（免光追的方向性 LPV） | 对同一体素光场取「沿世界法向偏移采样 L」与「中心采样 L2」，用差值塑形方向性分量（`dramaric=clamp(L-L2*0.8,0,1)*2`；`directional2=min(L2,pow(clamp((L-L2)*DBLX_MULT,0,1)))` 后按亮度/色相分解重建、保持色相）；档 7 再按材质粗糙度/SSS 混入漫反射与镜面，晶体 SSS 走折射方向查找。 | just-colored-lighting/main_f.glsl:1612-1640（档 3）、:1641-1682（档 4）、:1684-1785（档 7，含 :1703-1717 漫反射行为、:1736-1753 镜面行为）；档位由 shaders.properties:14,16 的 profile 设 `FLOODFILL_LIGHTING:7`；compute 端同思想 shaders/gi.glsl:381-403（TRACELESS_PT）。 | 低：在 `Astra/shaders/global/dimension/nether_colored_light.glsl` 增加第二个偏移采样与方向权重（约 10-20 行 + 1 个强度/开关选项，无新 pass、无新缓冲），运行时代价约 +1 次 texture3D；需 A/B 校准强度，并与下界体积雾解耦验证（Astra 体积雾当前不采样光场）。 | grep `gradient\|directional` 在体素相关模块只命中末地几何法线（Astra/shaders/global/dimension/end_geometry.glsl:230-233）与主世界天空（Astra/shaders/global/dimension/overworld.glsl:15），另 `Astra/shaders/global/dimension/end.glsl:50` 为注释命中、非实现，无体素光方向项；`astraLightSampler` 消费者仅 `Astra/shaders/global/dimension/nether_colored_light.glsl:23` 一处 textureLod 单样本，`Astra/shaders/global/dimension/nether.glsl:173-179` 只做单样本 + coverage 淡入；（与 batch3 已列的 Pegasus 体素太阳 GI 不同：本项是免光线追踪的消费端方向塑形）。 |
| A② 水下 SSR 三项硬化 | ①抖动随距离比向 0.5 收敛（`mix(dither,0.5,distRatio*0.9)`）；②深度容差 ×2×(1+4·distRatio)、前 4 步步长减半；③交点用四邻域深度方差 `ValidateDepthContinuity` 校验，远距（distRatio>0.8）直接接受命中、省掉细化。 | dercode/lib/Surface/ScreenSpaceReflections.glsl:65-76、:94-112、:124-145。 | 低：在 `Astra/shaders/global/water/raytrace.glsl` 加 3 处条件（约 15 行）；需水下发 A/B 确认不改变现有命中连续性与观感（抖动收敛减少远处闪烁/鬼影）。 | Astra 水下确实走同一 SSR 路径（`Astra/shaders/program/water.glsl:229` 在 `astra_underwater_interface` 内调 `water_raytrace`），但 `Astra/shaders/global/water/raytrace.glsl` 中 `isEyeInWater\|underwater\|distRatio\|continuity\|flicker` 均 0 命中，容差/抖动全局固定（:24、:66、:130-136）。 |
| A③ 顶点 lightmap 免矩阵快路径 | `gl_MultiTexCoord1.xy*(1./240)` 取代 `(gl_TextureMatrix[1]*gl_MultiTexCoord1).xy`；同族纹理坐标手工 mat2 路径在 OPT_UNSAFE 档。 | stracciatella-shaders/lib/vertex_transform_simple.glsl:84-92（纹理坐标 :74-82）；开关 lib/settings.glsl:10-12。 | 低：改 `Astra/shaders/program/lit.vsh:56` 一行并保留回退；需实机验证 Iris 属性值域满足 1/240 假设（上游作者自述该档可能破坏画面，故必须 A/B）。 | 全仓仅 `Astra/shaders/program/lit.vsh:56` 一处 `TextureMatrix[1]*gl_MultiTexCoord1`；`1./240` 相关命中均为 `eyeBrightnessSmooth.y/240`，无顶点属性快路径；Astra 已有直接属性先例（Astra/shaders/program/shadow.vsh:98,138 直接用 gl_MultiTexCoord0.xy）。 |
| A④ 主色缓冲免清空 | `const bool colortex0Clear = false;`（上游仅在 MC<1.19 + OPT_SAFE 启用）。 | stracciatella-shaders/lib/setup.glsl:29-33。 | 低：一行声明；前置：全像素覆盖核查（天空/半透明/粒子/hand 均须写入 colortex0）+ 1.19+ 适用性验证（作者在 1.19+ 停用且包内无原因注释）+ A/B。 | `grep colortex0Clear` 在 Astra 0 命中（仅 `Astra/shaders/lib/settings.glsl:514` 的 `colortex0ClearColor`）；Astra 唯一关闭清空的缓冲是 `colortex6`（`Astra/shaders/lib/settings.glsl:526`）。 |
| A⑤ 关闭阴影图/阴影彩色的 mip 生成 | `const bool generateShadowMipmap = false;` 与 `generateShadowColorMipmap = false;`——全程只按 LOD0 采阴影图，显式关掉每帧阴影图 mip 链生成。 | butter-shaders/lib/config.glsl:140-141。 | 低：一行 const 放进共享设置文件；前置两核实：(a) Iris 对 `generateShadowMipmap` 的默认值（若已默认 false 则零收益）；(b) Astra 有一处隐式 LOD 采样 `texture(shadowtex1, ...)`（`Astra/shaders/global/lighting/shadowmap.glsl:189` 硬件比较模式），需确认不依赖 mip 后再关，否则改显式 LOD0。 | `grep generateShadowMipmap\|generateShadowColorMipmap` 在 Astra 0 命中；`MipmapEnabled` 仅用于 colortex（Astra/shaders/prepare2.fsh:6、Astra/shaders/program/display.fsh:36,39、Astra/shaders/program/nether_reflection.fsh:24），无阴影图；`textureLod(shadow` 0 命中（阴影取数全在 LOD0：textureGather/texelFetch）。 |

### 2.2 B 组：中代价、需小规模接线（4 条）

| 借鉴点 | 机制 | 来源 file:line | 迁移代价与前置核实 | Astra 侧未实现证据 |
|---|---|---|---|---|
| B① 粒子/半透明独立简化光照缓冲 + 雾后合成 | 粒子只做「纹理 × 顶点色 × 烘焙光图」（不做阴影查询、不做方向光 BRDF、不做介质吸收），结果写独立 colortex5；composite 在雾/天空处理之后按 alpha 叠加。用独立缓冲把粒子从完整前向光照中摘出来。 | blocky-shader/gbuffers_textured_lit.fsh:12-20；programs/composite_frag.glsl:61-65、:318-320。 | 中：在 `Astra/shaders/program/lit.fsh` 为 ASTRA_PARTICLE 增加独立廉价光照分支（可直接复用 :251 的天气公式）并加选项门控；若照 blocky 独立缓冲 + 雾后合成则需新渲染目标与 composite 接线。代价是粒子失去阴影与介质衰减，必须先做画质 A/B；收益取决于粒子 overdraw（大雨/烟雾/下界粒子场才明显），源码无法判定。 | 粒子入口定义 ASTRA_PARTICLE，但 `program/lit.fsh` 内唯一分支是 :171-175 的雨溅隐藏 discard；`grep astra_light` 显示粒子仍进 :264 完整前向（阴影 + 方向性 SH + 介质）；`colortex5` 仅水面界面记录用途（Astra/shaders/lib/water_interface_record.glsl:6-16、Astra/shaders/program/water_state.fsh:15-21），无粒子缓冲；现存粒子廉价分支只覆盖天气（Astra/shaders/program/lit.fsh:249-253）。 |
| B② 屏幕空间时域彩色方块光（主世界低成本彩光；**同族合并条**：stracciatella B1 + zayko C1 MCBL） | stracciatella 链：gbuffers 把 emissive 块颜色（CL_PALETTE 64 色表 / 染色玻璃实色）写 colortex5 → composite0-3 以「非零计数平均」逐级合并到 colortex6（2×2 gather、象限递缩）→ composite4 在 32×18 的 colortex4 上做重投影时域累积（双三次读历史、mip LOD 采新样本、用「存储亮度估年龄 + 新样本亮度估重要性」的免额外通道混合、坐标/深度三种拒绝、Oklab 存储）→ deferred 双三次采样并按饱和度/vibrance 调色后混入 lightmap 方块光；手持光同链。zayko：4-tap 距离/FOV 缩放模糊 + 逐样本深度反渗漏 + 边缘 mask，与当帧发射色 10% 混合写累积缓冲，消费端重投影取上帧彩光按亮度比混入方块光。 | stracciatella-shaders/gbuffers_terrain.fsh:263-270,293-295；lib/palette.glsl:3；composite.fsh:26-49；composite1.fsh:26-53；composite2.fsh:26-53；composite3.fsh:26-53；composite4.fsh:98-146（重投影 :104-111、LOD :117-119、重要性/年龄 :121-125、拒绝 :127-136）；deferred.fsh:207-236；shaders.properties:120,194,203-217；lib/setup.glsl:49-54。zayko/program/composite.glsl:105-168；lib/lighting/coloredBlocklight.glsl:23-43；lib/settings.glsl:78；shaders.properties:121-126。 | 中：4 个极小全屏 pass + 2 个小缓冲 + gbuffers/deferred 两处接线，无 compute/SSBO；需接受屏幕空间近似的画质边界（穿墙、1 帧延迟、32×18）。**警告：stracciatella 原实现 composite1/2/3 在同 pass 读改写 colortex6 且全包无 flip 声明，「保留 screen/2、/4、/8 象限」语义与 composite4 角部采样坐标（coord/16+0.9375，composite4.fsh:117）在标准全屏视口语义下不自洽——只能重写借用，不可照搬；落地必须改为显式 flip/双缓冲与明确坐标约定。**与既有「主世界彩光路线（体素 floodfill）」存在路线竞争，采纳前需先定路线（本项定位为低成本屏幕空间对照实现）。 | `oklab\|OKLab` 在 Astra 0 命中；`colored` 仅命中下界彩光/彩色阴影/语言（Astra/shaders/global/dimension/nether.glsl:14,174、Astra/shaders/global/dimension/nether_colored_light.glsl、Astra/shaders/lib/nether_voxel_grid.glsl、Astra/shaders/program/nether_light.csh），主世界无彩光载体；`MCBL\|multicolor\|MultiColor` 0 命中；size.buffer 列表无 32×18 级光场槽。 |
| B③ 天空环境图改「八面体上半球折叠」打包 | `dir.y<0` 折到地平线，水平面按 `x/(\|x\|+y+\|z\|)` 投到正方形：等立体角、无极点过采样、无经线接缝；读写共用同一 encode/decode；另出一张约 5° 模糊软图服务粗糙反射。 | zayko/program/prepare.glsl:83-118（写入）；lib/atmospherics/skyMap.glsl:26-56（编码/解码）；program/prepare1.glsl:36-64（软图）。 | 中：改 `Astra/shaders/lib/sky_reflection_cache.glsl` 的方向映射与 `Astra/shaders/program/sky_reflection_cache.fsh` 的写入坐标（2 文件），现有跨接缝分支可删；ROUGH 模式 mip 逻辑不变；需 A/B 确认极点/地平线质量与过滤（B1 落地前建议先做离线方向映射对照）。 | Astra 天空缓存是经纬球 + 双经度 gutter：`Astra/shaders/lib/sky_reflection_cache.glsl:5-20`（258×128/256×128、fract(uv.x) 复制对侧列）、`:26-45`（跨接缝需额外两次 textureLod 手工插值）；`octahedral` 仅命中法线打包（Astra/shaders/lib/encoding.glsl:29-58、Astra/shaders/program/lit.vsh:87、Astra/shaders/program/lit.fsh:109），与天空缓存无关。 |
| B④ zayko 软图方案（**替代实现备选，不主张缺口**，照录 zayko.md 原文） | 一张 128²、约 5° 模糊的预过滤图与清晰图按粗糙度插值，替代 mip 链。 | zayko/lib/atmospherics/skyMap.glsl:39-84、program/prepare1.glsl:36-64。 | 从 zayko.md 原文照录：Astra 已有等价能力（`Astra/shaders/lib/sky_reflection_cache.glsl:40-58` 按 `log2(1+r²(mipCount-1))` 取粗糙 mip + 逐级周期过滤，`Astra/shaders/prepare2.fsh:2-8` 生成 mip）；本项只作替代实现备选，若现有 mip 方案出现粗糙反射断层/生成成本问题时可换，否则不动。 | 不列为独立缺口（无未实现证据主张）。 |

### 2.3 C 组：大工程、战略级选项（2 条）

| 借鉴点 | 机制 | 来源 file:line | 迁移代价与前置核实 | 说明 |
|---|---|---|---|---|
| C① 可见性位掩码屏幕空间 GI/AO（**同族合并条**：dercode SSIL + sundial SSVBM） | dercode SSIL：半分辨率可选 + 两段地平线搜索 + 指数步长 + 时域位掩码累积 + bent normal 镜面遮蔽。sundial SSVBM：每个实心像素 1 条（可配 1-8）屏幕射线、16 步（可配 4-128）；每步把遮挡体在半球上的角区间映射为 32 位掩码中的位（切片 CDF 映射 + 位运算），只把该步**新增可见角位**的辐射从上一 pass 已着色场景（colortex3）累积；AO=全遮挡位/32；本帧与上一帧重投影结果按 1/帧数混合（帧数打包在 colortex3.w），重投影用 2×2 加权双线性；射线步长按屏幕投影长度指数增长。整条链只需 1 条屏幕射线/像素 + 位计数，无光源列表、无体素、无 RT。 | dercode/lib/GI/GI_SSIL_Bitmask.glsl:1-25（机制总览与 `SSIL_SLICES/STEPS/HALF_RES/EXP_STEPS` 开关）、:82-180（视空间取数/地平线扫描）。sundial-lite/programs/deferred/Deferred12.frag:236-374（掩码位 :344-355、新增可见累积 :357-364、AO 计数 :368-369、帧数混合 :419-421、指数步长 :278,301-302）、:49-67（上游算法注明 Shadertoy XcdBWf，CC0/MIT 双许可）；programs/deferred/Deferred0.frag:100-134（重投影）、:176（帧数打包）。 | 高：新 GI 子系统——gbuffer 别名、半分辨率 trace pass、时域历史与重投影、indirect 光接线；建议先只做「位掩码 AO + 1 射线」A/B 再定。sundial 为 GPLv3，若采纳建议按上游 CC0/MIT 原算法独立实现（避免 GPL 传染范围扩大）。 | `grep bitmask\|occbits\|countbits\|vbgi\|ssgi` 在 Astra 0 命中；`ssgi\|screen space gi\|global illumination\|bounce` 仅 `Astra/shaders/global/lighting/wind.glsl:192` 注释含 bounce；Astra 现只有 12 样本黄金角 AO + bent normal（Astra/shaders/program/ssao.fsh:65-104），无任何 GI 载体。定位：与前三批已列 RSM/ReSTIR/体素日照并列的**第三条更省算法路线**，不重复主张「GI 方向」本身。 |
| C② DH 边界剔除与深度一致性 | 按 16×16 区块网格吸附 + 相机侧修正，三条件判定 DH 片元是否落在 vanilla `far` 内，命中则**光照前** discard；透明层用容差 0 且对 vanilla 深度逐像素比较；边界用 Bayer4 抖动过渡。 | stracciatella-shaders/lib/dh.glsl:10-30；dh_terrain.fsh:35-46；dh_water.fsh:70-93；gbuffers_transparent.fsh:79-89。 | 前置：Astra 尚无 DH/Voxy 光栅支持，须与该立项一起设计；机制本身低成本。增量声明：基础剔除 `discardDHSimple/DHDithered` 在 drdestens 2.1.5 已存在且两包逐字节相同（drdestens core/dh/discard.glsl:7-38 与同名文件 diff 为空；drdestens dh_terrain.fsh:38-39、dh_water.fsh:57-58），本项只主张 stracciatella 新增的「区块吸附变体 + dh_water 的 vanilla 深度一致性 + 光照前顺序」。 | `grep DISTANT_HORIZONS` 在 Astra 0 命中；仅有 Voxy 占位（shaders/voxy.json、program/lit_voxy.fsh、voxy_opaque.glsl、voxy_translucent.glsl，均 stub），无 DH 程序。随 DH 立项时再看。 |

### 2.4 反面印证汇总：20 款共性缺陷族（用于加固 Astra 既有 program 门控不回退的自检清单）

1. **关闭不缩编/空转 pass（最多的一族）**：open4es-renewed 的 REFLECTION 关闭仍做完整 30 步 ray march（world0/deferred.fsh:296、:189-206，`#ifdef` 只包住 textureLod 一行 :199）；lymboshader 的 BLUR 关闭仍跑满 625-tap 后才 `return vec4(0.0)`（final.fsh:61-95、:90-94），FOG 关闭仍付 depthtex0 采样（:118）；blocky-shader 的 9 个 Bloom pass 无程序熔断、捕获写入无 `#ifdef`（programs/composite_frag.glsl:322-327），且 `mipmap.colortex1=false`（shaders.properties:40）与 `colortex1MipmapEnabled=true`（composite21.fsh:5）冲突；truelight-fx-lite 的 TAA 关闭仍每帧写全屏历史 colortex3（program/composite.fsh:115-123）；butter-shaders 除 shadow 外无任何 program 门控、LightShaft pass 恒调度（world0/composite3.fsh；宏默认被注释 Input/LightShaft.glsl:3）；trailershaders 关闭功能不缩 pass/缓冲，下界/末地 composite 为纯拷贝（world-1/composite.fsh:8-11）；stereos-default+ 无任何 `program.*.enabled`/`size.buffer`/profile（shaders.properties:1-12）；simplicissimus 的 deferred 默认关时仍是纯拷贝全屏 pass（deferred.fsh:77-94）；sundial-lite 的 REFLECTION_FILTER=0 时 composite1/2 仍按 REFLECTION 全屏执行（shaders.properties:58-59）；daybreak-shader 无任何设置面（无 shaders.properties，效果常开不可降档）；vanilla_enhance 写入无人消费的 MRT（gbuffers_terrain.fsh:3,360,366）。
2. **无条件读彩色阴影**：stereos 每 tap 无条件读 shadowtex0+shadowtex1+shadowcolor0（composite.fsh:90-100）；blocky 判断前先取 shadowcolor0（programs/include/functions.glsl:196）；open4es 9 点 PCF 每点无条件读（gbuffers_main.fsh:341）；BDS 默认档每 tap 读 shadowcolor.a（gbuffers_textured.fsh:72-74）；daybreak 无条件采样（programs/functions.glsl:44-54）。对照 Astra：仅出现透明遮挡时 gather（global/lighting/shadowmap.glsl:140-177）。
3. **逐调用重算帧常量**：cyanide 的时点权重在 final/gbuffers 逐调用重算（lib/TimeCalculation.glsl:5-8、program/overworld/final.glsl:86-102）；trailershaders 阴影循环内每样本重算 rand2d、泛光抖动每 tap 重算（world0/composite.fsh:74-82、world0/final.fsh:142-146）；vanilla_enhance `getSmoothDayNightColor()` 同像素最多 2 次（gbuffers_terrain.fsh:85-102）；BDS 无 custom uniform、shadowLightPosition 每顶点重算（gbuffers_textured.vsh:58）；open4es 时段常量块在 5+ 个顶点着色器重复（gbuffers_main.vsh:158-175 等）；simplicissimus 同一套雾/太阳辉光表达式在 3 个 pass 各写一遍（composite.fsh:56-82 等）。
4. **死代码/死配置**：butter 的 `for (int i = 0; i < 0; i++)` SSR 死循环（lib/water.glsl:23，RAYMARCH_STEPS/SSR_TYPE=1 都不产生步进）；dercode 3 个无消费者反射选项（Settings.glsl:20-22，PREV_REFLECTIONS/PREV_REFLECTION_SAMPLES/PREV_REFLECTION_BLEND 全包无消费）；jcl 约 20+ 死定义/半成品（settings.glsl:220 等，SOLAR_GI=1 的消费者存在但 cimage4_gi 只在 SOLAR_GI≥3 声明且写出被注释）；zayko colortex8/9 双登记 MCBL 与体素传播共用槽位（program/composite.glsl:105-168 对 composite8/9.glsl）；trailershaders 雨条写 colortex7 全包无消费者（world0/gbuffers_weather.fsh:9-14）；blocky 无效 tonemap（final.fsh:51）与未用 dhBlend（gbuffers_entities.fsh:70-71）；truelight 死宏 REACT_ON_WATER（shader.h:77）与随包分发的 shaders.properties.backup；open4es vTexCoordAM/vTexCoord/texRes 声明与顶点写入但无读取（gbuffers_main.fsh:11-12,20、vsh:187-198）；monophonic 头文件无条件采 3 张深度（lab/sample_depth.glsl:8-10）；daybreak gamma 往返（programs/lit_frag.glsl:98、composite.fsh:78-81,192）；vanilla-advanced 假引用全局变量强拉编译变体（gbuffer/gbuffers.glsl:9-10）。
5. **功能裁减式「高性能」宣传与工程手法无关（七款零新颖点的共性）**：cyanide（整包无 shadow/deferred/composite/water 程序）、dreamlight（无 shadow 程序、单 deferred 承担天空+云+雾+SSAO）、vanilla_enhance（无 shadow/composite/deferred/final/water 程序）、BDS（缺多数 gbuffers、无延迟管线）、stereos（无 deferred、全链 3 张全屏缓冲）、trailershaders（无 TAA/SSAO/SSR/体积/曝光，固定 2048 影图 + 默认 4 tap）、lymboshader（全包仅 2 个自有程序 + 625-tap 单 pass）。它们的「高性能」来自不提供功能，不提供可迁移的调度或采样机制。
6. **工程卫生反例（不构成性能点，仅记录）**：stracciatella 的 LUT 选择器指向缺失文件（shaders.properties:123-167 引用 lut0-lut20，实际只有 lut0-lut5）；dercode 的 TSR 档 0/6 坏档（program/Deferred2.glsl:47-65）；zayko 星图依赖包外工具（lib/atmospherics/nightSky.glsl:7-11）；blocky 体素链未接线（默认 VOXEL_AREA=0，shadowcomp_a.csh 只做拷贝）；cyanide 的 `isEyeInWater==0.9` 死分支（program/overworld/gbuffer/textured.glsl:25）。

本节清单用途：加固自检——Astra 既有 32 个程序级门控基点（`Astra/shaders/shaders.properties` 内 `program.<名>.enabled` 基础行 32 行、含三维度前缀共 96 行，其中 51 行=false；truelight-fx-lite 文件记「32 处」即指基础门控数）+ size.buffer 分档，不得在任何后续改动中回退为「关闭仍空转/关闭不缩编」。

### 2.5 Astra 已覆盖确认：本批被反复排除的手段族（无需重复建设）

| 手段族 | 本批同型包（file:line） | Astra 侧证据（file:line） | 结论 |
|---|---|---|---|
| 顶点级帧常量/CPU 下沉 | simplicissimus shaders.properties:34-96；trailershaders world0/composite.vsh:26-44；open4es shaders.properties:4-25；dreamlight shaders.properties:98-123；zayko shaders.properties:151-197；dercode shaders.properties:112-221；stracciatella shaders.properties:14-116；butter shaders.properties:84-163；sundial shaders.properties:210-274；monophonic lab/time.glsl:12；truelight common/getDiffuse.vsh:1-12；（反面）cyanide lib/TimeCalculation.glsl:5-8、bds gbuffers_textured.vsh:58 | Astra/shaders/lib/uniforms.glsl:28-59、Astra/shaders/shaders.properties:496-523；12 包共识（前三批已列） | 已实现且更全，无新增量。 |
| SSR 有限步进 + 二分 + 置信度 + 出屏退出 + miss 回退 | truelight common/getReflectionColor.fsh:14-51；daybreak composite.fsh:127-186；open4es gbuffers_main.fsh:380-435；dreamlight global/water.glsl:93-131；zayko lib/reflections/raytrace.glsl:140-214；sundial programs/composite/Composite0.frag:116-317；monophonic lab/rt.glsl:11-44 | Astra/shaders/global/water/raytrace.glsl:45-137、:128-134、:135；Astra/shaders/program/water.glsl:340-363 | 本批仅 dercode 的水下三项硬化（A②）是新角度，其余无需重复建设。 |
| 解析天空反射回退 | jcl pbr2.glsl:41-48；daybreak composite.fsh:138-140；open4es gbuffers_main.fsh:588-591；dreamlight global/water.glsl:130；zayko lib/reflections/simpleReflections.glsl:8-58；sundial programs/composite/Composite0.frag:247-279；monophonic composite.fsh:65-77 | Astra/shaders/lib/sky_reflection_cache.glsl:48-69；Astra/shaders/program/water.glsl:207,268,329,362 | 已实现（天空缓存 + 粗糙度 mip + 解析回退）。 |
| 雨量门槛/降水简化路径 | trailershaders gbuffers_terrain.fsh:136；vanilla_enhance gbuffers_terrain.fsh:300-302；truelight program/gbuffers_weather.fsh:11-21；open4es world0/gbuffers_weather.fsh:6-11 | Astra/shaders/program/lit.fsh:249-253、:179-190；Astra/shaders/global/atmosphere/weather.glsl:21 | 已实现（天气专用分支 + 雨溅过滤）。 |
| 半分辨率 + 保边重建 | zayko 半分辨率体积光（program/composite.glsl:372-391、program/composite1.glsl:93-175）；dercode GI 半分辨率可选（lib/GI/GI_SSIL_Bitmask.glsl:1-25）；（反面）dreamlight 全分辨率 8 样本 SSAO（global/post/ssao.glsl:12-49）、monophonic 全分辨率 9-tap AO + 7×7×2 模糊（deferred2.fsh:19-33、lab/blur.glsl:1-20） | Astra/shaders/program/ssao.fsh:31,64-97；Astra/shaders/lib/ao_resolve.glsl:19-42；Astra/shaders/global/atmosphere/volume_fog.glsl:208-254 | 已实现；本批半分辨率方案与 Astra 同向，无新机制。 |
| 无阴影档伪方向光（static_shadow 兜底） | cyanide program/overworld/gbuffer/textured.glsl:61-66；dreamlight global/lighting.vsh:55-61；monophonic deferred4.fsh:87-89；zayko lib/lighting/shadows.glsl:421-430；butter src/light_vertex.glsl:147-158；bds gbuffers_textured.vsh:47-53 | Astra/shaders/global/lighting/shadowmap.glsl:250-252；Astra/shaders/global/lighting/diffuse.glsl:259-262；Astra/shaders/lib/settings.glsl:87（STATIC_SHADOW_FALLBACK） | 已实现且与 SHADOWS 门控联动，无新增量。 |
| 云透射中断/首次命中/距离 break/空区跳过 | dercode program/Deferred1.glsl:163-228、lib/Atmosphere/VolumetricClouds.glsl:2-33；zayko lib/atmospherics/clouds.glsl:315-318,370-376；sundial libs/Cloud.glsl:225-291（透射中断 :274）；jcl shaders/composite.fsh:163-167（天空像素门） | Astra/shaders/global/atmosphere/clouds_planar.glsl:274-321、:197-270；Astra/shaders/global/atmosphere/cloud_shadow_cache.glsl | 已实现（分档/首命中/距离 break/独立云影），无新增量。 |
| TAA 邻域钳制 | truelight program/composite.fsh:20-32（均值±标准差）；simplicissimus program/temporal.glsl:50-78（3×3 min/max）；butter lib/fast_taa.glsl:12-36,40-70（5 点方差）；dreamlight global/post/taa.glsl:70-83（8 邻域 AABB）；zayko lib/antialiasing/taa.glsl:24-184（YCoCg）；sundial programs/composite/Composite9.frag:35-88（YCoCg） | Astra/shaders/program/taa_resolve.fsh:28-40、:32-55、:98-102、:148-152 | 已实现 YCoCg 钳制 + gather + 反应遮罩 + 植被历史，无新增量。 |

## 三、逐包调研（20 款，浓缩自 `shader_research/batch4/<slug>.md`）

### 3.1 just-colored-lighting 1.0.2（619,699）

- 定位：Potato 级低配向快速光影，主/下界体素洪泛彩色光照 + 自动光源识别；阴影可选（SHADOWS 0-7，默认 0）；无 final/deferred/TAA/Bloom/SSR 程序，composite 默认整段停用（shaders.properties:180-189 三处熔断）。血统：自研；许可：无 LICENSE、头部 ARR 声明 → 思路级；规模：整包 306 文件 / 23,391 行（shader 根=包根；嵌套 `shaders/` 18 文件/4,581 行仅核心实现）。
- 手法：体素彩光方向性梯度三档（main_f.glsl:1612-1785）；云只在天空像素执行 + godrays 复用云深度（shaders/composite.fsh:163-167、:477-509）；洪泛 dispatch 1/3/5 阶梯（shaders.properties:328-356）。
- 新颖点：**A1（= §2.1 A①）**。
- 反面：选项面与实现大面积脱节约 20+ 死定义（settings.glsl:220 等；SOLAR_GI=1 档取不到数据、clouds2.glsl:103-106 引用未定义 `fnoise_o3d` 不可编译）；8bit 光场需每帧减 1/255 防鬼影（shaders/voxel_photons.csh:381-383），Astra 的 RGBA16F 光场精度更稳。

### 3.2 stereos-default+ 2.4（404,156）

- 定位：原版+极简风格包（阴影、水面与岩浆顶点波动），除一次 composite 合成外无自定义大气/水/云/后处理。血统：4 个天空文件为 XorDev 公共模板，其余 OptiFine 时代自研；许可：无 LICENSE → 默认 ARR；规模：64 文件（代码 17 文件 / 1,359 行）。
- 手法：4 角点双线性重建 + 旋转核 PCF（9~121 tap，composite.fsh:102-124）；下界/末地编译期整段删阴影函数与调用（world-1/composite.fsh:84-92）。
- 新颖点：**0**。
- 反面：每 tap 无条件读 shadowtex0+shadowtex1+shadowcolor0（composite.fsh:90-100）；雨天分支重复调用 `getShadow` 多跑一轮全核（:139-146）；无任何 program/size.buffer 调度面。

### 3.3 simplicissimus 1.3a（234,519）

- 定位：RRe36 极简「只加动态阴影」向，legacy `#version 120` 前向光照，TAA 单 pass 双写。血统：RRe36 自研（与 Potato/SVL 同作者不同代码库，局部 robobo1221 畸变 / Chocapic 重投影 / CaptTatsu 描边）；许可：自定义 LICENSE（ARR，代码复用需明确许可）→ 思路级；规模：118 文件 / 5,020 行。
- 手法：阴影坐标在顶点算好 + 距离/背光/分辨率对数偏置（gbuffers_solid.vsh:110-123）；影子风位移 64 格门控（shadow.vsh:65-93）；TAA 单 pass 双写当前+历史、历史不清除（program/temporal.glsl:18,80-91）。
- 新颖点：**0**。
- 反面：deferred 默认关时仍为纯拷贝全屏 pass（deferred.fsh:77-94）；bloom 8 缩放层 ×49 tap 无 mip 链（composite2.fsh:42-77），colortex2 的 mipmap 从未声明、路径可工作性存疑。

### 3.4 trailershaders r1.6（213,983）

- 定位：复刻 MC 宣传片观感（高饱和、镜头光晕、色差、暗角、宽银幕条），其「更高帧率」来自功能缺席而非调度/采样优化。血统：自研（前身 BareBone）；许可：LICENSE 明文专有 ARR → 思路级；规模：50 文件 / 1,483 行。
- 手法：太阳可见度 9×9 深度探针在 final 顶点阶段算好广播（world0/final.vsh:48-64）；13 个解析光晕（包围盒早退 + sunVisibility/雨强整体早退，world0/final.fsh:97-115）；泛光螺旋采样质量档（:130-157）。
- 新颖点：**0**。
- 反面：焦散 `getCaustics()` 在 `isEyeInWater` 判断之前无条件执行（world0/gbuffers_terrain.fsh:87-91）；雨条写 colortex7 无消费者（world0/gbuffers_weather.fsh:9-14）；阴影循环内逐样本重算哈希（world0/composite.fsh:74-82）。

### 3.5 truelight-fx-lite v5.6.3（190,816）

- 定位：无延迟管线的轻量原版风格，全屏只有 composite（TAA/运动模糊）与 final（FXAA/焦散/光柱/Bloom/tonemap）。血统：原 TrueLight FX（Mateus A. Kreuch）→ Simon L./OGCRAFTNET 维护；许可：MIT（可代码级）；规模：91 文件 / 1,910 行。
- 手法：SSR 指数步进 + 回退细化 + 出屏 break + 透明体拒绝（common/getReflectionColor.fsh:14-51）；像素锁定阴影 1/16 格量化（common/getSunStrength.fsh:4-15）；TAA 3×3 均值±标准差钳制（program/composite.fsh:20-32）。
- 新颖点：**0**。
- 反面：TAA 关闭仍每帧写全屏历史 colortex3（program/composite.fsh:115-123）；CLOUD_STYLE=1 每像素 3×fbm(4 阶) 共 12 次噪声无早退（program/gbuffers_clouds.fsh:41-52）；随包分发 properties.backup 与死宏。

### 3.6 blocky-shader 0.6.1（181,790）

- 定位：原版风格性能向：光照在 gbuffers 前向完成，Bloom 三级降采样→1/8 可分离高斯→逐级升采样，FXAA 与 Bloom 合并 composite21。血统：dvimidh 自研（FXAA 经 BSL）；许可：MIT（FXAA 片段循 BSL）；规模：80 文件 / 3,112 行。
- 手法：粒子独立简化缓冲写 colortex5、雾后按 alpha 合成（gbuffers_textured_lit.fsh:12-20、programs/composite_frag.glsl:318-319）；云只写 colortex6 复合端叠加（gbuffers_clouds.fsh:15-17）；解析高度雾双 logistic 积分（programs/composite_frag.glsl:81-91）。
- 新颖点：**B1（= §2.2 B①）**。
- 反面：彩色阴影无条件读取（programs/include/functions.glsl:196）；Bloom 关闭后 9 个 pass 仍被调度、捕获写入无 `#ifdef BLOOM`（programs/composite_frag.glsl:322-327）；体素链未接线（默认 VOXEL_AREA=0）。

### 3.7 dercode 2.2（181,670）

- 定位：GI/彩光/体积云/反射/PBR 全家桶（1009 行 properties + 981 行 Settings），README 自述「对弱机极不优化」。血统：Bliss → Derivative main 重制分支（只报增量）；许可：无 LICENSE、README 自述矛盾 → 保守 ARR；规模：437 文件 / 31,184 行。
- 手法：水下 SSR 三项硬化（lib/Surface/ScreenSpaceReflections.glsl:65-76,94-112,124-145）；SSIL 可见位掩码屏幕空间 GI（lib/GI/GI_SSIL_Bitmask.glsl:1-25,82-180）；天空捕获带内嵌主 pass（program/Deferred0.glsl:272-308）；GI/AO 结果 2×2 四像素打包省附件（program/Deferred2.glsl:230-244,265-273）。
- 新颖点：**A1 + C1（分别并入 §2.1 A②、§2.3 C①，C1 与 sundial 同族合并）**。
- 反面：3 个反射选项无消费者（Settings.glsl:20-22）；TSR 档 0 除零、6 无相位表（program/Deferred2.glsl:47-65）；同帧两套天空/云输出并存（program/Deferred0.glsl:304-308 与 Deferred1/2 时域链），分工无注释、存在重复计算嫌疑。

### 3.8 daybreak-shader 0.2（175,564）

- 定位：原版+SSR 的 Alpha 包；程序集不完整（无 terrain/water/entities/hand/weather/clouds/final、无 shaders.properties），覆盖依赖 Iris 回退，实际代价无法按包内代码评估。血统：无法判定；许可：无 LICENSE → ARR；规模：28 文件 / 800 行。
- 手法：SSR 门控 rough<0.2 + 深度非天空（composite.fsh:127）与解析天空回退（:138-140）；粒子 renderStage 短路直接 `ambient + skyLight*albedo`（programs/functions.glsl:69-71）；有理衰减 fogify `w/(x²+w)`（:43-45）。
- 新颖点：**0**。
- 反面：1000 次固定 SSR 循环、唯一提前退出是出屏、接受阈值与步长耦合（composite.fsh:144-183）；DH 分支逐像素矩阵求逆（:97）；gamma 写读往返（programs/lit_frag.glsl:98、composite.fsh:78-81,192）。

### 3.9 stracciatella-shaders 1.6.4.1（170,808）

- 定位：原版观感 + 彩色灯光 + 大量 QoL；无阴影图/无 PBR/无 SSR/无 Bloom/TAA，彩光走屏幕空间降采样 + 32×18 时域累积链。血统：DrDesten，与 drdestens-shaders 同作者同 ShaderCore（只报增量）；许可：无 LICENSE → ARR；规模：313 文件 / 10,843 行。
- 手法：顶点 lightmap 免矩阵快路径（lib/vertex_transform_simple.glsl:84-92）；colortex0 免清空（lib/setup.glsl:29-33）；屏幕空间时域彩光链（composite0-4 + deferred 消费）；DH 边界剔除与深度一致性（lib/dh.glsl:10-30）。
- 新颖点：**A1 + A2 + B1 + C1**（A1→§2.1 A③、A2→§2.1 A④、B1→§2.2 B②（与 zayko MCBL 合并）、C1→§2.3 C②）。
- 反面：彩光链 composite1/2/3 同 pass 读改写 colortex6 且无 flip、坐标语义不自洽（composite1.fsh:26-53、composite4.fsh:117）——不可照搬；`AGRESSIVE_OPTIMISATION` 名不副实（实际只挂 4 处微优化，lib/settings.glsl:10-12）；LUT 选择器指向缺失文件（lut6-20）。

### 3.10 cyanide-shaders 1.1（150,284）

- 定位：原版+ 观感增强，宣称「几乎不影响性能」；低成本实际来源是整包没有 shadow/deferred/composite/water 程序，效果全在 gbuffers 与 final。血统：OptiFine 经典模板谱系；许可：自定义 AGREEMENT（有条件允许使用部分代码，边界需统帅裁定）；规模：35 文件 / 921 行。
- 手法：顶点级无阴影伪方向光（program/overworld/gbuffer/textured.glsl:61-66）；原版云几何零成本 + 线性雾（program/overworld/gbuffer/clouds.glsl:14-22）；盲眼/时点色并入顶点/片元一次乘除（program/overworld/gbuffer/skytex.glsl:14-34）。
- 新颖点：**0**。
- 反面：时点权重逐调用重算（lib/TimeCalculation.glsl:5-8、program/overworld/final.glsl:86-102）；雾距离取世界坐标长度（会随玩家位置漂移，program/overworld/gbuffer/textured.glsl:55-59）；`isEyeInWater==0.9` 死分支（:25）；Bloom 全分辨率 128 tap 无阈值/无降采样（program/overworld/final.glsl:57-82）。

### 3.11 dreamlight-shaders 1.5（115,066）

- 定位：梦幻风格化 + 彩光，兼顾性能；单 deferred 内完成天空+云+雾+SSAO。血统：Mellow 的 MIT remake（只报增量），相对 Mellow 做减法；许可：MIT；规模：276 文件 / 4,053 行。
- 手法：`water_thickness()` 一次 depthtex1 屏幕深度差复用给水雾/焦散/泡沫（global/water.glsl:3-8）；云为单层投影平面 + 2 次噪声采样（global/sky.glsl:23-54）；TAA Catmull-Rom + 最近深度 + AABB（global/post/taa.glsl:30-125）。
- 新颖点：**0**。
- 反面：默认反射即 flipped image 廉价路径（lib/settings.glsl:105）；全分辨率 8 样本 SSAO（global/post/ssao.glsl:12-49）；bloom 单缓冲分块靠默认关藏成本；`water_thickness` 复用未覆盖 SSR（注释优于实现）。

### 3.12 vanilla_enhance 1.2（111,303）

- 定位：轻量原版增强（光照曲线、PBR 高光、风、解析云雾、水下），无阴影图/延迟管线/体积效果；「轻量」来自不提供阴影/延迟/后处理/水体系统。血统：无 README/LICENSE/署名，不可确认；许可：ARR（默认）；规模：16 文件 / 1,151 行。
- 手法：解析天空渐变 4 色 + 晨昏 peak（gbuffers_skybasic.fsh:83-117）；解析 exp² 雾 + 三色混合（gbuffers_terrain.fsh:225-257）；水下吸收/3 次噪声焦散/正弦 godrays 内联（:314-349）。
- 新颖点：**0**。
- 反面：写入无人消费的 MRT（DRAWBUFFERS:012，gbuffers_terrain.fsh:3,360,366）；帧不变量逐像素重算（:85-102，同像素最多 2 次）；固定 2 层×6 阶 FBM 无降档（gbuffers_skybasic.fsh:37-50）；`oldLighting=true` 语义未决。

### 3.13 bds-better-default-shaders 1.0（98,489）

- 定位：原版光照 + 写实阴影 + 高性能；只加一张畸变阴影图与可选 FXAA。血统：XorDev 模板骨架 + 自建阴影（FXAA 来自 McNopper/OpenGL）；许可：混合（XorDev 明示授权 + Apache-2.0 全文 + 其余无声明）→ 从严按思路级；规模：18 文件 / 845 行。
- 手法：顶点级「简单光照」+ NoL 顶点门控 + 顶点阴影投影（gbuffers_textured.vsh:47-53,58-72）；Vogel 盘 + 逐像素 IGN 旋转 PCF（gbuffers_textured.fsh:66-84）；FXAA 对比度早退 + 2/4 tap 降级（composite.fsh:209-301）。
- 新颖点：**0**。
- 反面：默认档每 tap 无条件读 shadowcolor.a（gbuffers_textured.fsh:72-74）；Vogel 采样循环内逐 tap 三角函数（:49-57,70-71）；菜单滑条 SHADOW_DISTORT_FACTOR/SHADOW_BIAS 无对应宏（悬空项）。

### 3.14 lymboshader 1.2（95,834）

- 定位：极简原版观感，全包仅地形 gbuffers + final 两条自有管线，无阴影/反射/云/天气子系统。血统：DorNell8 自研极简；许可：无 LICENSE、readme 非正式 → ARR；规模：6 文件 / 204 行（代码 166 行）。
- 手法：final 单 pass 灰度「bloom」25×25 不可分离 625 tap、核权重片元内 normpdf 现算（final.fsh:61-95）；深度幂雾 `pow(depthtex0/1.001,34)`（:118-125）。
- 新颖点：**0**。
- 反面：BLUR 关闭仍跑满 625 次采样后才 `return vec4(0.0)`（:90-94）；FOG 关闭仍付 depthtex0 采样（:118）；无 program/size.buffer/profile，低配只能重编译。

### 3.15 monophonic-shaderpack 1.1（94,098）

- 定位：轻量玩法友好向：无阴影图/TAA/Bloom/SSR/体积光，附加效果全为解析式或单 pass，全屏链 5 pass。血统：Exposa 同源精简版（相对增量为零）；许可：无 LICENSE → ARR（vibrance 标注 belmu 存疑）；规模：61 文件 / 1,457 行。
- 手法：屏幕空间射线阴影三档（deferred4.fsh:55-57、lab/rt.glsl:1-45）；天光阈值假阴影 `pow(skyLight,200)*900`（deferred4.fsh:87-89）；单张 512² 贴图水波法线一次采样（gbuffers_water.fsh:63-65）。
- 新颖点：**0**（相对 Exposa 增量为零）。
- 反面：全分辨率 9-tap AO + 7×7×2 深度加权模糊约 107 次取数/像素（deferred2.fsh:19-33、deferred4.fsh:61、lab/blur.glsl:1-20）；先算后判（deferred.fsh:23-31）；包含头即付 3 张深度采样（lab/sample_depth.glsl:8-10）。

### 3.16 open4es-renewed v1.0.1（91,503）

- 定位：低配向；BSL + HexBR_ 阴影拼装，删云/Bloom/TAA/体积/独立 SSAO，改为 gbuffers 前向 + 单 deferred + final。血统：BSL 低配改造（只报增量）；许可：LICENSE=GPLv3 全文，但 BSL 来源部分授权缺失存疑；规模：98 文件 / 3,403 行。
- 手法：反射源=上一帧场景拷贝（world0/deferred.fsh:307-310）；SSR 30 步 + 出屏 break + 4 次细化（gbuffers_main.fsh:380-435）；雨条只写 alpha 掩码、final 染色（world0/gbuffers_weather.fsh:6-11、world0/final.fsh:330-331）。
- 新颖点：**0**。
- 反面：REFLECTION 关闭仍做完整 30 步 ray march（world0/deferred.fsh:296、:189-206）；9 点阴影每点无条件读 shadowcolor0（gbuffers_main.fsh:341）；水法线单像素最多 9×5 噪声取数（:219-265）；天气几何写脏 colortex1（world0/gbuffers_weather.fsh:9-10）。

### 3.17 butter-shaders 1.2d（89,468）

- 定位：MakeUp Ultra Fast Legacy 6.80L 的 Typon 修改版；10 档 profile，仅 shadow 有程序级熔断；相对 9.5f 净增 deferred1/deferred2/composite3 三个全屏 pass。血统：MakeUp + Typon（只报增量）；许可：LGPL-3.0；规模：218 文件 / 6,639 行。
- 手法：显式关阴影图/阴影彩色 mip 生成（lib/config.glsl:140-141）；阴影 4 次硬件采样 + 遮挡才读彩色 + 手部编译期跳过（lib/shadow_frag.glsl:13-23,49-54）；TAA 5 点方差钳制 + 速度混合（lib/fast_taa.glsl:12-36,40-70）。
- 新颖点：**A1（= §2.1 A⑤）**。
- 反面：SSR Raymarch 档为 `for (int i = 0; i < 0; i++)` 死代码（lib/water.glsl:23）；LightShaft pass 恒调度（world0/composite3.fsh，宏默认注释）；雾缓冲生产者/消费者错位（仅天空/水面写 gaux4，所有不透明像素读它当雾色，src/finalcolor.glsl:34）。

### 3.18 zayko 9.0（81,003）

- 定位：质量优先 + 高可调；天空图资产化（prepare 256² 上半天球 + 128² 软图，「每一帧只有一个天空」），主世界彩光 MCBL/体素两套。血统：SkyNexusHD 自研（组件级第三方注明）；许可：无 LICENSE → ARR；规模：367 文件 / 22,818 行。
- 手法：八面体上半球折叠天空环境图（program/prepare.glsl:83-118、lib/atmospherics/skyMap.glsl:26-56）；MCBL 屏幕空间彩光（program/composite.glsl:105-168、lib/lighting/coloredBlocklight.glsl:23-43）；半分辨率体积光 4×4 重建（program/composite.glsl:372-391、program/composite1.glsl:93-175）。
- 新颖点：**B2 + C1**（B1→§2.2 B③、B2→§2.2 B④（备选）、C1 MCBL→§2.2 B②（与 stracciatella B1 合并））。
- 反面：体素彩光 2D 图集 + 跨帧乒乓天然 1 帧延迟（lib/lighting/voxelPropagate.glsl:30-46）；图集容量越界史（lib/lighting/voxelMap.glsl:36-54）；colortex8/9 双登记无互斥（composite8/9 与 MCBL 共用）；半分辨率 VL 的 4×4 重建每像素 16 次点采，贵于 Astra 2×2 双线性 + 深度带筛选。

### 3.19 sundial-lite 1.2.0（63,002）

- 定位：质量/性能/兼容平衡的延迟管线；Lite 不做体素化与世界空间光线追踪，体积光与反射「从算 2 次降到 1 次」。血统：GeForceLegend 自研（算法来源注明：Shadertoy CC0/MIT 位掩码、Intel YCoCg、NVIDIA Morton/TEA、AMD RCAS、GT7 tonemap）；许可：GPL-3.0；规模：356 文件 / 10,407 行（任务书 3,972 行仅部分树）。
- 手法：SSVBM 可见性位掩码 SSGI/AO（programs/deferred/Deferred12.frag:236-374）；单张阴影图象限打包（不透明/透明/水各占象限，programs/gbuffers/Shadow.vert:114-133、libs/Shadow.glsl:89-96）；云影 3D 噪声用 2 次 textureGather 替代 8 次取数（libs/Cloud.glsl:352-379）。
- 新颖点：**C1（= §2.3 C①，与 dercode SSIL 同族合并）**。
- 反面：零缓冲分档（无 size.buffer/renderResMul，grep 0 命中）；REFLECTION_FILTER=0 仍付 composite1/2 两趟全屏（shaders.properties:58-59）；PCSS/屏幕阴影无质量梯（programs/deferred/Deferred11.frag:28-31）；辅助标量寄生在深度/曝光缓冲的魔数 texel（programs/deferred/Deferred0.frag:168-175）。

### 3.20 vanilla-advanced 1.0.1（56,788）

- 定位：小型原版观感 + 少量 PBR/体积光；光照在 gbuffer 前向算完，所有全屏效果（体积光/水下/岩浆/细雪）合并进唯一 composite。血统：ThePlaneGuy45 自研，植物波动来自 Complementary Reimagined；许可：无 LICENSE，readme MIT 式 + 署名/禁转售（口径差，Complementary 部分不在授权内）；规模：30 文件 / 730 行。
- 手法：体积光把射线两端点变换进阴影空间、循环内只 mix + 1 次 shadowtex1（composite/composite.glsl:55-124）；水波单层正弦 + 距离衰减（util/common.glsl:58-72）；彩色阴影仅 shadowtex0 更近时读（gbuffer/gbuffers.glsl:176-186）。
- 新颖点：**0**。
- 反面：固定 324 格阴影距离 + 1024 影图、无 shadowDistance 滑条（util/common.glsl:1,9）；体积光固定 20 格均匀步长无自适应（composite/composite.glsl:75-84）；假引用全局变量强拉滑条编译变体（gbuffer/gbuffers.glsl:9-10）；无任何时域/历史复用。

## 四、许可与借鉴方式

| 包 | 许可口径（逐包文件实录） | 可否代码级 | 本批借鉴方式（若采纳） |
|---|---|---|---|
| just-colored-lighting | 无 LICENSE；文件头明示 ARR（禁修改/再分发/不得用代码片段） | 否 | 思路级重写 + THIRD-PARTY.md 登记 |
| stereos-default+ | 无 LICENSE（4 天空文件为 XorDev 公共模板明示可任意用）；其余默认 ARR | 否（从严） | 思路级 |
| simplicissimus | 自定义 LICENSE 首行 ARR；§4 代码复用需明确许可 | 否 | 思路级 |
| trailershaders | LICENSE 明文「proprietary…strictly prohibited」 | 否 | 思路级 |
| truelight-fx-lite | MIT（Copyright 2022 Mateus A. Kreuch；现维护者 Simon L.） | 是（保留版权与许可文本） | 本批仍按思路级处理；若走代码级须单独台账 |
| blocky-shader | MIT（2025 dvimidh）；FXAA 片段另有 BSL 来源 | 是（FXAA 片段循 BSL 渠道） | 思路级（粒子条为独立重写） |
| dercode | 无 LICENSE；README 同时写 ARR 与「feel free to use…」→ 矛盾，按最保守 ARR | 否 | 思路级 |
| daybreak-shader | 无 LICENSE/README/版权文件 → ARR | 否 | 思路级 |
| stracciatella-shaders | 无 LICENSE（仅 core/README.md）→ ARR（与 drdestens 同处理） | 否 | 思路级 |
| cyanide-shaders | 自定义 AGREEMENT.txt：允许以其为底包/使用部分代码（署名、显著修改、不得改协议、变现需授权） | 需先裁定 | 暂按思路级；代码级需统帅先裁定协议兼容性 |
| dreamlight-shaders | MIT（HoneyStudios；保留 Mellow 版权行与 CAS/SMAA/bayer 等 notices） | 是 | 思路级（相对 Mellow 增量为零） |
| vanilla_enhance | 无任何许可/README/版权文本 → ARR | 否 | 思路级 |
| bds-better-default-shaders | 混合：XorDev 模板文件明示授权 + FXAA 内嵌 Apache-2.0 全文 + 其余无声明 ARR | 部分（分文件） | 从严按思路级 |
| lymboshader | 无 LICENSE；readme 仅非正式「可改」表述 | 否 | 思路级 |
| monophonic-shaderpack | 无 LICENSE → ARR；vibrance 片段注明 belmu（Noble/GPLv3）存疑 | 否 | 思路级 |
| open4es-renewed | GPLv3 全文；info.txt 自述部分代码属 BSL，而 BSL 本体 ARR 且无授权文件 → 上游授权存疑 | 存疑 | 思路级；动代码前须先解决 BSL 授权问题 |
| butter-shaders | LGPL-3.0（Javier Garduño；Typon 修改部分保留头） | 是（LGPL 义务） | 思路级（仅 A⑤ 一行 const 也独立重写） |
| zayko | 无 LICENSE/版权文件 → ARR；组件级第三方来源（Robobo1221/Lottes/Complementary）需单独溯源 | 否 | 思路级 |
| sundial-lite | GPL-3.0（GeForceLegend）；C① 上游算法为 Shadertoy CC0/MIT 双许可 | 是（GPL 传染注意） | 若采纳 C①，建议按 CC0/MIT 上游原算法独立实现，避免扩大 GPL 范围 |
| vanilla-advanced | 无 LICENSE 文件；readme 含 MIT 式授权 + 署名/禁转售；植物波动来自 Complementary（不在该授权内） | 口径差 | 思路级；Complementary 部分只能按 Complementary 协议单独处理 |

结论：**本批零代码级搬迁**——无论许可是否允许（MIT/LGPL/GPL 的 5 款技术上有条件），本批全部借鉴点按 Astra 现行做法「读思路 + 独立重写」，若采纳统一登记 `Astra/THIRD-PARTY.md`；涉及上游公开许可算法（sundial C① 的 Shadertoy CC0/MIT、zayko 组件级来源）单独溯源，不以包名义处理。

## 五、无法判定与实机验证清单

1. **Iris 平台语义类（采纳前置核实）**：`generateShadowMipmap`/`generateShadowColorMipmap` 的 Iris 默认值（butter A⑤；若已 false 则零收益）；`colortex0Clear=false` 对 1.19+ 的适用性（stracciatella A④，作者仅 MC<1.19 启用且无注释）；`flip.*` 属性是否真省 Iris 全屏拷贝（sundial-lite shaders.properties:21-33 共 13 条声明，Astra 0 条）；`oldLighting=true` 的确切语义（vanilla_enhance shaders.properties:2，工作区无平台文档，已研究包一律 false）；`MC_RENDER_QUALITY` 外部宏来源（stracciatella-shaders final.fsh:96,102 裸用、包内无 define，drdestens 同）。
2. **包内语义不可还原类**：stracciatella 彩光链同 pass 读改写 colortex6 无 flip、象限裁剪语义与 composite4 角点坐标（coord/16+0.9375）不自洽——是有意打包约定、驱动 UB 还是上游已修未同步无法判定，照抄前必须重写；monophonic 的 colortex 格式块整段在注释内（lab/bufferinfo.glsl:1-10），若 Iris 默认 RGBA8 则 `*65535` 打包回读会把 8/9 类 ID 量化到不可分辨；sundial 的缓冲格式块同样整段注释（programs/composite/Composite13.frag:24-38），HDR/位掩码链路是否真为 RGBA16F 未验证；butter 的焦散写入落点（common/shadow_fragment.glsl 只有 gl_FragData[0]、无 DRAWBUFFERS，进入 shadowtex0 还是 shadowcolor0 未知）。
3. **包的可用性/覆盖类**：daybreak 程序集不完整，主地形/水面是否走本包 gbuffers 未知，1000 步 SSR 的实际代价无法按包内评估；BDS/vanilla-advanced/cyanide/open4es 的命令回退链与 GUI 宏行为（源内 `#define` 与菜单选项谁优先）未实测；open4es 的 shadowcolor0 透射链有效性存疑（world0/shadow.fsh:16-20 只有 FragData[0]，9 次读取可能恒 0）；cyanide 的无 main 空程序体是否被 Iris 接受。
4. **配置自洽性存疑类**：simplicissimus bloom 两处独立开关（composite2.fsh:19、program/final.glsl:42）与 colortex2 mipmap 从未声明（composite2.fsh:24 只声明 colortex0MipmapEnabled，final 读 colortex2 缩放坐标）；blocky `mipmap.colortex1=false`（shaders.properties:40）与 `colortex1MipmapEnabled=true`（composite21.fsh:5）冲突；trailershaders 硬编码 `#define ShadowMapping` 与 GUI 选项（shaders.properties:8）并存；zayko colortex8/9 双登记是否假定互斥（默认都关）。
5. **增量边界类**：dercode 与 Bliss/Derivative 未做逐文件 diff（README 自述口径）；stracciatella 与 drdestens 的 core 仅 4 文件差异但管线重排细节未逐行回溯；dreamlight 的 `fbm_fast` 单 tap/octave 与 Astra 各用途噪声预算未做对照；jcl 的 WORK_GROUP_SIZE 64/128/256 档缺「未实现即收益」证据。
6. **风险/行为类**：blocky 粒子雾后合成的收益取决于粒子 overdraw，需固定机位 A/B；vanilla-advanced 体积光端点线性 mix 的阴影错位（省每样本除法/畸变的取舍）需 A/B；monophonic 屏幕空间阴影的近相机深度魔数（lab/rt.glsl:33）行为未知；truelight 逐顶点雾插值在大三角上的净收益与失真需实机对照；simplicissimus `world-1/world1` 风力与材质列表的版本对应未逐版本核对；lymboshader 625-tap 是否被驱动变换无法离线判定。
7. **元数据类**：stereos/lymboshader/monophonic/vanilla_enhance/zayko 等包的 Modrinth 索引许可与版本无法在包内复核（无 pack.json/LICENSE），本报告按逐包文件最保守口径处理；lymboshader 包内代码头自称「v2」（shaders/final.fsh:8）与任务书 v1.2 冲突。
8. **全局声明**：所有收益均为源码级推断，包内无作者基准帧时数据；第二至五章任何一条在采纳前都需要 Astra 实机 A/B（尤其 A② 水下发、A④ 全屏覆盖、B① 粒子画质、B② 彩光路线竞争、C① GI 立项），本报告不宣称任何已实现的帧率收益。
