# tea-shaders 可借鉴点调研（面向 Astra 光影）

> 生成方式：子代理调研（ZCode worker 子代理）
> 包版本：Tea Shaders `2.0.0_Dev7`，作者 unicornbloods，下载量 156,193（元数据来自 `reference_shaderpacks/INDEX-batch2.md:36`）
> 调研日期：2026-10-02
> 引用约定：`P:` = 相对 `reference_shaderpacks/tea-shaders/`；`A:` = 相对 `Astra/shaders/`。所有行号均为本次实际读取所得，未凭记忆书写。
> 本包特别关注点：大气 + 植被向；对照 Astra 的植被透光、摇曳、生物群系染色。
> 重复标注：与批次一已收录方向重复的条目在 ③ 显式标注，并给出 `shader_research/SUMMARY.md` 行号。

---

## ① 概览（含许可证原文行号）

- **体量**：348 个文件 / 约 696 KB（`find` + `du` 实测）。扩展名分布：.fsh 163、.vsh 162、.glsl 15、.lang 4、.properties 2。源码全部在 `shaders/` 下，包根目录除 `shaders/` 外为空。
- **版本与目标平台**：`P:shaders/shaders.properties:5-6` 声明 `version.1.12.2=G5`、`version.1.7.10=E7` —— 面向 OptiFine G5/E7 世代（1.12.2 与 1.7.10），无 Iris 专属特性、无 compute/SSBO/现代 buffer 格式声明。
- **维度覆盖**：`world0`（主世界）、`world-1`（下界）、`world1`（末地）、`world4`/`world7`/`world10`/`world100`（模组/自定义维度占位）。变体由入口薄壳的 `#define` 选择：`P:shaders/world-1/composite.fsh:3`（`Nether`）、`P:shaders/world1/composite.fsh:3`（`End`）、`P:shaders/world10/composite.fsh:3`（`Beneath`）。
- **渲染架构**：**全包无 shadow pass**（`find -iname "*shadow*"` 零命中，连 `shadow.fsh/.vsh` 都没有）。光照 = 原版 lightmap 采样 + 一个 BSL 系 DBAO/SSAO（`P:shaders/program/deferred.glsl`）+ 简单调色；无 PBR、无方向光阴影、无镜面/反射、无体积云/体积雾、无 SSR。
- **缓冲区约定**：colortex0=gcolor、colortex1=matID（写入 `matID*0.5` 半程打包，读回 `*2.0`）、colortex2=lmcoord。`DRAWBUFFERS:02` 见 `P:shaders/program/gbuffers_terrain.glsl:28-31`；matID 打包/解包见 `P:shaders/world0/gbuffers_water.fsh:33-39` 与 `P:shaders/program/composite.glsl:123-124`。
- **许可证：包内无任何 LICENSE / README / 说明文件。** 校验方式：全包按 `*licen*`、`*readme*`、`*.txt`、`*.md`、`*.html` 搜索零命中；根目录列表只有一个 `shaders/`。包内仅有代码内致谢（均为第三方片段出处，不是本包自身的授权声明）：
  - `P:shaders/lib/Global/Tonemaps.glsl:2` — "Some parts taken from BSL with Tatsu's permission"
  - `P:shaders/lang/en_US.lang:23` — "Permission was given by Tatsu to use his Tonemap."
  - `P:shaders/program/deferred.glsl:4` — "CODE BY BSL CAPT TATSU"
  - `P:shaders/program/composite1.glsl:5` — "DOF File, Credit to Sildur for dof base."
  - `P:shaders/lib/antialiasing/fxaa.glsl:1` — FXAA 3.11 出处链接；`P:shaders/lib/antialiasing/taa.glsl:12` — "Previous frame reprojection from Chocapic13"；`P:shaders/program/composite4.glsl:55` — Nvidia GPUGems3 出处。
- **索引结论沿用**：许可状态 = **保留所有权利（无许可声明）**。批次二索引原文 `reference_shaderpacks/INDEX-batch2.md:36`：「保留所有权利」；批次二汇总 `shader_research/SUMMARY-batch2.md:49` 已把 tea-shaders 列入「仅可读思路，重写」层。

---

## ② 架构特性清单（按子系统，带 文件:行号）

| 子系统 | 实现要点 | 出处 |
|---|---|---|
| 目录/入口薄壳 | 每个 `.fsh/.vsh` 仅 `#version 120` + `#define` + `#include "/program/xxx.glsl"` | `P:shaders/world0/gbuffers_terrain.fsh:1-6`；`P:shaders/world0/deferred.fsh:1-6` |
| 共享实现分派 | 单文件内用 `#ifdef fsh`/`#ifdef Global`/`#ifdef Nether`/`#ifdef End`/`#ifdef Beneath` 承载多维度实现 | `P:shaders/program/composite.glsl:1-2,158,234,312`；`P:shaders/program/final.glsl:3,59` |
| 植被摇曳 | 噪声纹理风场 + mc_Entity 方块分类 + mc_midTexCoord 顶点锚定；每方块类不同幅度 | `P:shaders/program/gbuffers_terrain.glsl:39-43,77-85,104-158` |
| 方块分类表 | 1.13+ 段与 1.12 段两个列表；10002 单株 / 10003、10004 双株下、上 / 10005 作物 / 10006 甘蔗 / 10007 蛛网+火 / 10008 水 / 10013 树叶 / 13010 半透明 / 10010 岩浆 | `P:shaders/block.properties:2,7-28,35-49,52-92` |
| 雾 | 主世界/下界/末地/Beneath 四套独立常数；LBOFOG 陆地门控、HeightBasedFog、雨天减半、失明、岩浆雾 | `P:shaders/program/composite.glsl:86-118,145-151,158-232,234-310,312-457` |
| 天空 | skybasic 顶点重建方向 + `fogify` 解析地平线混合 + 原版星光透传 | `P:shaders/world0/gbuffers_skybasic.fsh:24-26,42-56` |
| 水面 | 顶点双正弦波 + 岸线裁剪；自定义水色 3 档；matID 打包 | `P:shaders/world0/gbuffers_water.vsh:29-30,44-52`；`P:shaders/world0/gbuffers_water.fsh:23-39` |
| 水体吸收/水雾 | `exp(-vec3(1.0,0.2,0.1)*depth)` 各向异性衰减 + 水色 mix | `P:shaders/program/composite.glsl:123-140` |
| 屏幕扭曲 | 水下/下界用 sin/cos UV 抖动，无深度校验 | `P:shaders/program/composite15.glsl:41-49`；`P:shaders/program/final.glsl:86-90` |
| 云 | 原版纹理云 + 可选 tint 滑块（world4 版本逗号表达式 bug 见末行） | `P:shaders/world0/gbuffers_clouds.fsh:19-21` |
| AO | BSL 系 DBAO：bayer64 程序化抖动 + 双向采样（角度+距离双通道） | `P:shaders/program/deferred.glsl:54-65,77-110` |
| 阴影 | 无 shadow pass，光照仅 lightmap（无方向光阴影） | 全包 find 零命中 |
| 后处理 | DOF（60 点六角 bokeh）、运动模糊、水下折射、夜视去饱和、胶片颗粒、单色、CSBOX、白世界调试 | `P:shaders/program/composite1.glsl:45-124`；`P:shaders/program/composite4.glsl:56-89`；`P:shaders/program/composite15.glsl:25-53`；`P:shaders/program/gbuffers_basic.glsl:19-32` |
| 抗锯齿 | 编译期 3 档：FXAA 3.11 / TAA / 关 | `P:shaders/program/composite2.glsl:4-31` |
| Tonemap | 6 档选择；默认 BSL 三段（曝光→白曲线→上下曲线 mix）+ saturation/vibrance | `P:shaders/program/final.glsl:31-45`；`P:shaders/lib/Global/Tonemaps.glsl:4,77-98` |
| 维度组织 | world-1/world1/world4/7/10/100 各自复制整套薄壳与滑块默认值（world4/7/100 与 world0 仅少量常数不同，`diff -rq` 实测） | `P:shaders/world4/gbuffers_terrain.fsh:1-6`；`P:shaders/world100/gbuffers_terrain.fsh:1-6` |
| 设置系统 | shaders.properties 共 64 行：sliders 一行 60+ 项、screen 树 7 组、12 个 smooth 群系 uniform（含下界群系） | `P:shaders/shaders.properties:10,13-49,53-64` |
| 本地化 | 4 种语言；选项注释带性能开销色标（绿/黄/橙/红/暗红五档） | `P:shaders/lang/en_US.lang:5-9` |
| 工程瑕疵（如实登记） | `id==1`/`id==13011` 为死分支（无 10001 方块；13011-10000=3011），`normal` 赋值未被消费；`world0/gbuffers_cloudsfsh`、`world0/gbuffers_cloudsvsh`、`world-1/gbuffers_entities copy.fsh` 为死文件；world4 云 tint 写成逗号表达式只乘 alpha（默认 `#ifdef cloudsCustom` 关闭） | `P:program/gbuffers_terrain.glsl:104-105,153-155`；`P:world4/gbuffers_clouds.fsh:19`；`P:world0/gbuffers_clouds.fsh:20` |

---

## ③ 可借鉴点（≥10 条）

格式：技术 / `P:` / `A:` / 工作量。重复项显式标注。

1. **风场相位用噪声纹理按格随机**：一次 `noisetex` 采样给"振荡方向+相位"，第二次给"幅度变体"，世界坐标即相位，免 uniform。 / `P:shaders/program/gbuffers_terrain.glsl:79-81` / `A:global/lighting/wind.glsl:112-123`（Astra 的波形状来自 Complementary、接口已冻结，只可评估为低配档/形状变体，需新开槽位） / 中。
2. **摇曳幅度随世界高度线性增大 + 雨天/夜晚调制**：`pos.y/192+0.667` 使高处风更大（y=64 为 1x，y=256 为 2x），雨 `max(rainStrength,wetness)*1.5`，夜 `*(1-night*0.5)`。 / `P:shaders/program/gbuffers_terrain.glsl:78` / `A:global/lighting/wind.glsl:135-141`（Astra 只有雨 `1+0.5*rain`，无高度项、无夜晚项） / 小。
3. **摇曳的"长度守恒"下沉补偿**：偏移越大，顶点 y 按 `0.5/(|offset|²+0.5)-1` 向下沉，避免面片被拉伸。 / `P:shaders/program/gbuffers_terrain.glsl:84` / `A:global/lighting/wind.glsl:203-209`（Astra 地面植被 `wave.y=0` 保底，但叶片无长度补偿） / 小。
4. **双株植物上下段用 per-vertex 幅度差**：`mc_midTexCoord.y` 判上半顶点，再按 id 给 `amt=(top?1:0 + (id==4))*0.5*1.5` —— 上段方块摆得比下段多 50%。 / `P:shaders/program/gbuffers_terrain.glsl:127-138` / `A:program/lit.vsh:156-170`（Astra 只用 `at_midBlock.y<0` 单点门控，无上下段幅度差） / 小。
5. **岸线波位移裁剪 `clamp(wave, -fy, 1-fy)`**（fy=fract(世界Y)）：把波峰/波谷夹在水方块自身高度内，防止波峰穿出水面块或沉入下方方块。 / `P:shaders/world0/gbuffers_water.vsh:45-51` / `A:global/water/surface.glsl:205,239`（Astra 波场生成 `surface_height/surface_gradient`，未见近岸方块内裁剪） / 小（本轮最高性价比）。
6. **各向异性水吸收系数向量**（`vec3(1.0,0.2,0.1)*depth`，红衰减最快）作为可调美术方向。 / `P:shaders/program/composite.glsl:133,139` / `A:global/water/absorption.glsl:13-14,43-49,61-63`（Astra 已是双端光谱 + 单散射） / 免（**与批次一重复**：`SUMMARY.md:53` Solas 分通道吸收，单源；仅记录"方向被独立复现"）。
7. **无深度校验的屏幕 UV 三角折射**（`sin/cos(时间+UV)` 抖动 final 采样坐标，成本约 4 次三角函数，无历史/深度依赖）。 / `P:shaders/program/composite15.glsl:44-45`；`P:shaders/program/final.glsl:86-88` / `A:global/water/refraction.glsl:11-24`（Astra 是真视线折射 + depthGather 校验 + 早退）；`A:program/display.fsh:91-105` / 小（仅作可选风格档；**与批次一重复**：`SUMMARY.md:56` 水下 UV 扭曲 4 包印证）。
8. **陆地门控雾（LBOFOG）**：仅当 `depth<1` 时雾化，天空/云不受雾影响；关掉时按强度作用到天空。 / `P:shaders/program/composite.glsl:86-88,116-118` / `A:global/atmosphere/fog.glsl:61-71`（Astra 用 `skyFogStrength` 早退，等价且更省） / 免（方向印证，不新增）。
9. **维度分派用入口薄壳 define**（同一实现文件按 world 文件夹的 `#define Nether/End/Beneath/Global` 走不同常数）。 / `P:shaders/world-1/composite.fsh:3`；`P:shaders/world1/composite.fsh:3`；`P:shaders/world10/composite.fsh:3` / `A:global/dimension/nether.glsl`、`A:global/dimension/end.glsl` + Astra program 入口 / 免（**与批次一重复**：`SUMMARY.md:134` world 薄壳 6 包印证、`SUMMARY.md:135` 模组维度兜底）。
10. **自定义群系 uniform 模板**：`smooth(权重, if(in(biome, ...),1,0), 渐入, 渐出)`，含 12 个群系（含下界五群系），用于雾/染色过渡。 / `P:shaders/shaders.properties:53-64` / `A:shaders.properties:643-647`；`A:lib/settings.glsl:116-118` / 免（**与批次一重复**：`SUMMARY.md:116` CPU 预计算 12 包印证、`SUMMARY.md:89` 下界群系 smooth 5 包印证）。
11. **天空-雾解析地平线混合 `w/(x²+w)`**（一次 dot + 一次 mix 完成天顶→地平线过渡，星空透传不参与）。 / `P:shaders/world0/gbuffers_skybasic.fsh:24-26,42-45` / `A:global/atmosphere/sky_gradient.glsl:158,231`（Astra 为 SH9/调色板级） / 免（**与批次一重复**：`SUMMARY.md:71` 雾色与天空输出同源 3 包印证）。
12. **夜视/夜间去饱和**：按亮度 `0.01/(pow(brightness*w,2)+0.01)` 自适应混合去饱和色，并乘冷色 tint `vec3(0.2,1.0,2.0)`。 / `P:shaders/program/composite15.glsl:26-38` / `A:global/post/grading.glsl:129-131`；`A:lib/settings.glsl:228`（Astra 的 Purkinje 默认 0，可作风格档参数参考） / 小（**与批次一重复**：`SUMMARY.md:100` Purkinje 夜视蓝移 5 包印证）。
13. **胶片颗粒三通道错位彩色噪声**：亮度越低颗粒越强（`1-brightness*1.9`），坐标随 `frameTimeCounter*0.01` 移动防静态，RGB 用 `refcoord±0.1` 错位采样。 / `P:shaders/lib/Global/FilmGrain.glsl:18-19` / `A:global/post/grading.glsl:233-247`（Astra 只有输出 dither；无颗粒层） / 小（**与批次一重复方向**：`SUMMARY.md:149` 胶片模拟曲线，单源；同属"风格页"）。
14. **DOF：60 点六角 bokeh 表 + 9-tap 循环 + 屏幕中心自动对焦 + 手部门控**：`focus = ld(depthtex2[0.5])`，CoC 上限 `pw*15`。 / `P:shaders/program/composite1.glsl:45-124` / `A:` 全仓无景深（`grep -rln "bokeh|Depth_of_Field|DOF"` 在 Astra 零命中） / 中；与批次一 `SUMMARY.md:151` 方向相邻但不同 → 暂缓。
15. **运动模糊：GPUGems3 式 5 采样 + 手部 depth<0.56 门控 + 噪声抖动**：`maxVel=0.05` 限幅。 / `P:shaders/program/composite4.glsl:56-89` / `A:` 无运动模糊 / 中 → 暂缓。
16. **深度边缘 cel 描边**：对向四点深度差取四方向 step 均值当边缘权重直接乘颜色；`iswater` 由 gaux1 判别。 / `P:shaders/program/deferred1.glsl:40-64,79` / `A:` 无 cel 风格档 / 小（风格开关）→ 暂缓。
17. **BSL 三段 tonemap + saturation/vibrance**：`x/((x^w+1)^(1/w))` 白曲线 + 上下曲线 mix；饱和度用 `pow/lightness` 混合。 / `P:shaders/lib/Global/Tonemaps.glsl:77-98`；`P:shaders/program/final.glsl:31-45` / `A:lib/tonemap.glsl:52,151,176,191`；`A:lib/color_controls.glsl:55-64` / 免（**与批次一重复**：`SUMMARY.md:108` BSL 三段 tonemap，单源）。
18. **TAA 重投影 + 8 邻域 min/max clamp + 速度长度混合系数**：Chocapic13 重投影；`blendfactor *= clamp(1-sqrt(len)/1.999,0,1)*0.3+0.6`。 / `P:shaders/lib/antialiasing/taa.glsl:13-39,51-54` / `A:program/taa_resolve.fsh:30-52,85-129`（Astra 有 YCoCg/reactive/中心信任/历史状态，远细于本包） / 免（**与批次一重复**：`SUMMARY.md:95-99` TAA 集群，7 包印证）。
19. **程序化 bayer64 抖动做 AO 采样**（免噪声贴图，`fract(dot(...))` 递推 8 阶）。 / `P:shaders/program/deferred.glsl:54-65,121` / `A:lib/ao_resolve.glsl:19-52`（Astra AO 用空间权重+深度/法线一致性过滤，未用 dither） / 小（**与批次一方向相关**：`SUMMARY.md:116` CPU 抖动表）。
20. **1.12 世代的模组方块兼容表**（两套列表按 `MC_VERSION` 分支，1.12 段收录 BiomesOPlenty/HarvestCraft/Thaumcraft/Botania/LOTR 等大量模组植物）。 / `P:shaders/block.properties:2,35-49,67-80` / `A:block.properties:1-23`（Astra 面向 1.21.x，含 pale garden 等新方块） / 小-中（纯数据；除非 Astra 要覆盖模组生态，否则不收）→ 暂缓。

---

## ④ Astra 已有对应实现对照（哪边更省 / 误差来源）

| 子系统 | tea-shaders（P:） | Astra（A:） | 哪边更省 | 误差来源（若采纳 tea 做法） |
|---|---|---|---|---|
| 植被摇曳 | 噪声纹理风场，2 次采样/顶点，`gbuffers_terrain.glsl:77-85` | Complementary 形状 4 sine + S4 历史可复算，`wind.glsl:112-141,167-235` | Astra 成本高但可历史重放；tea 更省且免 uniform | tea 相位依赖 `noisetex` 采样，无历史版本；Astra TAA/阴影与模型同步会破 |
| 双株植物 | per-vertex `mc_midTexCoord` 判上段 + id 加权，`:127-138` | `at_midBlock.y<0` 单点门控，`lit.vsh:156-170` | tea 信息更多（上下段可差 1.5x）；Astra 更简单 | Astra 无"上段摆更多"，长草顶端弯曲感更弱（属观感差异，非错误） |
| 植被透光（SSS） | **无 SSS**，只有 lightmap 乘，`gbuffers_terrain.glsl:26` | `sss_wrap` + `sss_transmission`（离屏/背光两半），`sss.glsl:79-88,147`；`diffuse.glsl:136-145` | Astra 贵但效果完整 | tea 的背光叶片死黑；本轮"植被向"上 **tea 无可借鉴**，价值在对照确认 Astra 的路线 |
| 群系染色 | 仅原版 glcolor + 12 个 smooth uniform（其中 `isSwamp` 声明后无消费者，`composite.glsl:33`） | 雾群系 tint + 下界调色板 + 26 色 TINT 菜单，`shaders.properties:643-647`；`settings.glsl:116-118` | Astra 更全面 | tea 群系 uniform 基本闲置（`isSwamp` 无使用点） |
| 雾 | 单次深度线性雾 + 高度乘子 + 四套维度常数，`composite.glsl:86-118` | FogV2 `pow(d,3)` + 谷雾 + 空气透视 + 群系 + 边界雾 + 六情形，`fog.glsl:67-71,127-128,147,153-177,208,230` | tea 显著更省（1 次深度 + 约 10 条指令） | tea 的高度雾是 `worldPos.y/100` 乘法，高处/虚空雾色会整体压暗；无距离归一化，远裁剪面外行为不可控 |
| 天空 | 顶点插值 skyColor/fogColor + `fogify`，`gbuffers_skybasic.fsh:24-45` | SH9 方向性天光 + 调色板梯度，`sky_gradient.glsl:158,231` | tea 极省（无 SH） | tea 天空无日/月/暮色方向性，无云影；仅适合低配档 |
| 云 | 原版纹理云 + tint 滑块，`gbuffers_clouds.fsh:19-21` | 平面云 + 时域 + 云影缓存，`clouds_planar.glsl:90-144` | tea 极省 | tea 云是原版 2D 云，无体积/无云影/无时域，Astra 不用回退 |
| 水体吸收 | `exp(-vec3(1,0.2,0.1)*depth)` 屏幕深度直接当光学深度，`composite.glsl:133,140` | Beer-Lambert 按块距离 + 双端光谱 + 单散射，`absorption.glsl:13-14,43-49,61-63,97-107` | tea 省（1 次 exp） | 屏幕空间深度≠路径长度，掠射角过吸收；无水色 body 项，深水趋黑 |
| 水下折射 | 全屏 UV 抖动 `sin/cos`，`composite15.glsl:44-45` | 视线折射 + 4-tap depthGather 校验 + 早退，`refraction.glsl:11-24` | tea 省（4 条三角函数） | 无深度校验 → 前景/背景同幅扭曲，屏幕边缘拉丝；Astra 已修此问题 |
| AO | BSL DBAO 深度 SSAO，10-200 采样，`deferred.glsl:77-110` | 独立 ssao pass + bent normal + 方向性天光交换，`ao_resolve.glsl:19-89`；`ao_material.glsl:3-5` | tea 省（无 G-buffer 法线，单深度） | 深度-only AO 在薄面/斜面漏检，且无 bent normal，无法支撑 SH9 天光 |
| TAA | 8 邻域 min/max clamp + 速度混合，`taa.glsl:13-54` | YCoCg/reactive/中心信任/历史状态，`taa_resolve.fsh:85-129` | tea 省 | 无 depth 一致性、无 reactive 遮罩 → 运动物体拖影；Astra 不必回退 |
| AA | FXAA 3.11（12 迭代）+ TAA 二选一，`composite2.glsl:4-31`；`fxaa.glsl:8-14` | FXAA + TAA + `ANTIALIASING` 档，`final.fsh:6`；`fxaa.glsl:27` | 同代方案 | 无本质差异 |
| 色调映射 | 6 档，默认 BSL 三段，`Tonemaps.glsl:77-98` | Uchimura/AgX/ACES/Reinhard + LOOK 三区 + Purkinje，`tonemap.glsl:52,151,176,191,206-220` | tea 省 | BSL 曲线无色彩管理，需手调；Astra 已有多算子 |
| 后处理风格 | DOF/运动模糊/cel/夜间去饱和/胶片颗粒/单色，`composite1.glsl:45-124` 等 | 无 DOF/运动模糊/cel；有 dither/vignette/Purkinje，`grading.glsl:233-247` | tea 功能多，Astra 省 | tea 这些是"风格页"，非正确性项 |
| 阴影 | **无 shadow pass**，只有 lightmap | shadow pass + PCSS 族 + SSS 协同 | tea 极省 | tea 无方向光阴影，Astra 的核心卖点不可退 |
| 维度组织 | 7 个 world 文件夹复制薄壳，`world-1/composite.fsh:3` 等 | `global/dimension/*` + program 入口 + `DIMENSION_*` define | 两者同构；tea 的文件夹复制更易漂移（world4 云 tint bug） | 复制默认值 → 多份滑块不同步 |
| 设置系统 | 64 行 properties + 4 语言，`shaders.properties:10,13-49` | 810 行 properties + 完整 COLORS 树 + profile，`shaders.properties:421-429,452` | Astra 更完整；tea 的 lang 性能色标可直接补 | — |

---

## ⑤ 许可可行性与「重写 vs 抄」边界

- **事实**：tea-shaders 包内无任何许可文件，无版权声明（① 已给搜索证据）。默认版权 = **保留所有权利**；批次二索引（`INDEX-batch2.md:36`）与批次二汇总（`SUMMARY-batch2.md:49`）均已按此登记。
- **授权链不完整**：tea 内多处片段标注来自第三方（BSL/Tatsu `Tonemaps.glsl:2`、Sildur `composite1.glsl:5`、Chocapic13 `taa.glsl:12`、FXAA 3.11、Nvidia GPUGems3）。tea 作者不是这些片段的版权方，即使想"转手授权"也不成立。
- **结论（口径与批次一一致，见 `SUMMARY.md:82`）**：
  1. **可以**：读思路、记算法方向、比较参数取法、独立重写实现；
  2. **不可以**：复制代码片段、复制命名/滑块默认值表/常数表、复制贴图与噪声资产、复制 `block.properties` 方块列表；
  3. 落地时必须：重写后仍登记「思想来源：Tea Shaders 2.0.0_Dev7（unicornbloods）」到文件头 + `Astra/THIRD-PARTY.md`；
  4. **特别提醒**：③ 的 BSL tonemap、Sildur DOF、Chocapic13 TAA 若要借鉴，应直接溯源原始出处并按其许可评估，不能引用 tea 作为来源（同 Astra `wind.glsl:15-25` 换源纪律：同步改文件头与发布门）。

---

## ⑥ Top5 + 暂缓项

按本轮「大气 + 植被向」与 Astra 实际缺口排序（均只读思路、独立重写）：

1. **岸线波位移裁剪**（`P:world0/gbuffers_water.vsh:45-51` → `A:global/water/surface.glsl:205,239` 或水面顶点阶段）——小，治"波峰穿模"观感问题。
2. **摇曳高度/夜晚耦合**（`P:gbuffers_terrain.glsl:78` → `A:global/lighting/wind.glsl:135-141`）——小，给 `astra_wind_wave` 的强度链加高度与 night 因子（注意 S4 历史复算需同参）。
3. **摇曳长度守恒下沉补偿**（`P:gbuffers_terrain.glsl:84` → `A:global/lighting/wind.glsl:203-210`）——小，叶片摆动时避免面片拉伸。
4. **双株植物上下段 per-vertex 幅度差**（`P:gbuffers_terrain.glsl:127-138` → `A:program/lit.vsh:156-170` + `wind.glsl` 分类参数）——小，长草/花丛弯曲更自然。
5. **噪声纹理风场相位（低配档/形状变体评估）**（`P:gbuffers_terrain.glsl:79-81` → `A:global/lighting/wind.glsl`）——中，作为高成本 sine 形状之外的备选，需先做 A/B 观感与 TAA 稳定性对照。

**暂缓项**：DOF（③-14）、运动模糊（③-15）、cel 描边（③-16）、夜视去饱和/胶片颗粒（③-12、③-13，批次一已覆盖且属风格页）、BSL tonemap/TAA/AO 抖动/群系 uniform/world 薄壳（③ 已标重复，Astra 现状不低于本包）、1.12 模组方块兼容表（③-20，与 Astra 目标版本不符）、无 shadow pass 的纯 lightmap 路线（不适用）。

---

## 附录：自抽查记录（成稿后重新打开源文件核对）

核对方法：`sed -n '<行号>p'` / `grep -n` 重新打开源文件；下列行号为核对后确认值（"结果"栏为二次读取的原文摘录）。

| # | 引用 | 核对命令 | 结果 |
|---|---|---|---|
| 1 | `P:shaders/program/gbuffers_terrain.glsl:78` | `sed -n '78p'` | 命中 `baseWindAmt = min(rainStrength,wetness)*1.5 + (pos.y/192.0+0.66666666)*(1.0-night*0.5)` |
| 2 | `P:shaders/program/gbuffers_terrain.glsl:84` | `sed -n '84p'` | 命中 `0.5/(lengthSquared2(offset)+0.5)-1.0` 下沉补偿 |
| 3 | `P:shaders/program/gbuffers_terrain.glsl:131` | `sed -n '131p'` | 命中 `amt = (float(texcoord.y<mc_midTexCoord.y)+float(id==4))*0.5` |
| 4 | `P:shaders/world0/gbuffers_water.vsh:45-51` | `sed -n '45,51p'` | 命中 `fy=fract(...)`、双 sin 波、`clamp(wave,-fy,1.0-fy)` |
| 5 | `P:shaders/program/composite.glsl:133` | `sed -n '133p'` | 命中 `color *= exp(-vec3(1.0,0.2,0.1)*depth);` |
| 6 | `P:shaders/program/composite15.glsl:44-45` | `sed -n '44,45p'` | 命中 sin/cos 折射与 `refraction*0.002*AMOUNT` |
| 7 | `P:shaders/lib/Global/FilmGrain.glsl:18-19` | `sed -n '18,19p'` | 命中 `refcoord = texcoord.st + frameTimeCounter*0.01` 与 `±0.1` 三通道错位 |
| 8 | `P:shaders/program/deferred.glsl:121` | `sed -n '121p'` | 命中 `float dither = bayer64(gl_FragCoord.xy);` |
| 9 | `P:shaders/program/gbuffers_terrain.glsl:104-105,153-155` | `sed -n '104,105p;153,155p'` | 命中 `mc_Entity.x>10000.0`、`id=int(...)-10000`、`id==13011`：13011→3011，死分支结论成立 |
| 10 | `P:shaders/world4/gbuffers_clouds.fsh:19` | `grep -n cloud` | 命中逗号表达式行。**原稿曾写 :20（实为 `#endif`），二次核对后已更正为 :19**；world0 同行 `:20` 为正确的 `vec4(...)` |
| 11 | `A:global/lighting/wind.glsl:135-141` | `sed -n '135,141p'` | 命中 `astra_wind_wave(...)` 与 `(1.0+0.5*rainAmount)` |
| 12 | `A:global/water/surface.glsl:205` | `sed -n '205p'` | 命中 `float surface_height(vec2 worldPos, SurfaceFootprint footprint, ...)` |
| 13 | `A:lib/ao_resolve.glsl:19` | `sed -n '19p'` | 命中 `astra_ao_visibility(..., out vec3 bentNormal)` |
| 14 | `A:shaders.properties:643` | `sed -n '643p'` | 命中 `astraNetherWastes=smooth(80, if(in(biome, BIOME_NETHER_WASTES), 1, 0), 8, 8)` |

核对结论：14 条中 13 条一致；第 10 条行号偏差已更正。所有引用均来自本轮实际读取。
