# bds-better-default-shaders 性能调研（batch4 · 只读）

日期：2026-10-03。范围：只读调研，产物仅本文件；未改动任何参考包或 Astra。
行号基准：相对 `reference_shaderpacks/bds-better-default-shaders/shaders/`（本包 shader 根即 `shaders/`；包根另有 1 张截图 PNG）。
去重基线：`shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`（下称「五份材料」）+ 任务背景列出的 Astra 已实现手段。每条候选均已对 `Astra/shaders` 做多关键词 grep，见「候选去重排除明细」。

## 概况

- 定位：Modrinth v1.0（98,489 下载，任务简报口径）。「原版光照 + 写实阴影 + 高性能」：保留原版几何/云/雾/光图，只加一张畸变阴影图与可选 FXAA；无延迟管线、无体积/反射/后处理链。
- 血统：`gbuffers_basic/textured/skytextured/clouds`、`block.properties` 均带 **XorDev's "Default Shaderpack"** 文件头（自称教学模板，用于 OptiFine 入门）；阴影系统（`common.glsl` 的畸变/偏置、`shadow.vsh/fsh`、`shaders.properties` 的 screen/sliders）是在该骨架上的扩建；`composite.fsh:3` 标注 FXAA 取自 McNopper/OpenGL（Apache-2.0）。与已研究 62 包无同源关系（不在 BSL/Complementary/Chocapic/Photon/SDV 等系谱内），按完整包调研。
- 许可：包根**无 LICENSE/README**（整包 19 文件：截图 1 + `shaders/` 18）。混合口径：XorDev 系文件头内嵌明示授权「You can do whatever you want with this code! Credit is not necessary, but always appreciated!」（如 `gbuffers_textured.vsh:5`）；`composite.fsh:1-207` 内嵌 Apache-2.0 全文（FXAA，`:3` 来源、`:194` Copyright Since 2013 Norbert Nopper）；其余文件（`common.glsl`、`shadow.*`、`final.*`、`shaders.properties`、`lang/`）无任何许可文本 → 默认版权保留（ARR）。按从严口径：只能思路级重写 + THIRD-PARTY.md 登记，不复制代码/结构。
- 规模：整包 19 文件（`shaders/` 树 18 文件 + 根目录截图 1 张 2.6MB）；`shaders/` 树合计 845 行（wc -l 口径）：纯代码（fsh/vsh/glsl）802 行、`block.properties` 12 行、`shaders.properties` 5 行、`lang/en_US.lang` 27 行。**无非 shaders/ 的代码目录**（仅有 lang/ 资产目录与包根截图）。

## 管线与调度

- program 清单（全部，4 组 gbuffers + 3 个链）：`shadow`（vsh/fsh）、`gbuffers_basic`、`gbuffers_clouds`、`gbuffers_skytextured`、`gbuffers_textured`（各 fsh/vsh 成对）、`composite`（仅 FXAA）、`final`。**没有 gbuffers_terrain / water / entities / hand / skybasic / deferred/其它 composite**：地形/实体/手持/水等几何依赖 Iris/OptiFine 程序回退落到 gbuffers_textured / gbuffers_basic（[假设] 具体回退链见「无法判定项」1）。
- 开关与调度：`shaders.properties:5 program.composite.enabled = FXAA` —— FXAA 选项关闭时 composite 阶段整段不调度；`:1` screen 与 `:3` sliders 暴露 9 个滑条名（影子强度/太阳角/影图分辨率/软度/半透明影/采样数/畸变因子/偏置/影距），其中 `SHADOW_DISTORT_FACTOR`、`SHADOW_BIAS` 无对应宏（见「反面印证」4）。
- 分辨率/缓冲分档：**无 `size.buffer`、无 colortex 格式/mipmap 声明、无 profile 预设、无 CPU custom uniform**；所有可调项是编译期 `#define`/`const`（`common.glsl:1-12`：`shadowMapResolution=2048`、`sunPathRotation=-40`、`shadowDistance=160`、`shadowDistanceRenderMul=1.0`、`shadowHardwareFiltering=true`、采样数默认 8 上限 16）。
- 输出：全部 gbuffers 走默认 `DRAWBUFFERS:0`（无自定义 MRT）；shadow pass 写 shadowtex0/1 + shadowcolor（`shadow.fsh:10-12`）。

## 分模块性能手法清单

### 调度与阶段启停

- `shaders.properties:5` — 编译期 option 决定 composite 阶段是否有内容（FXAA 关 = 该 pass 不跑）；材料已列 program 级熔断共识（SUMMARY.md:115）。
- `shaders.properties:1,3` + `common.glsl:1-12` — 全部画质档位以编译期 #define/const 暴露（采样 1–16、影图 128–8192、影距 16–512），关闭选项即减少对应代码；无运行期资源缩编联动。

### 地形光照与阴影

- `gbuffers_textured.vsh:47-53` — 顶点级「简单光照」：法线分量平方加权（`nx²*0.6+ny²*0.25*(3+ny)+nz²*0.8`，封顶 1）乘进顶点色；flat 材质（`mc_Entity.x==1`）用固定法线 `(0,1,0)` 跳过法线矩阵变换——方向光代价压到每顶点一次多项式。
- `gbuffers_textured.vsh:58-72` — 顶点级 NoL 门控：`NoL<0.01`（背光）不构造 shadowPos，直接把光图坐标压暗 `coord1.y *= 1-SHADOW_STRENGTH`；向光面在顶点完成 `shadowProjection*shadowModelView` 投影 + 偏置 + 畸变（含 `/2+0.5` 归一），片元阶段不再做任何矩阵运算（仅 PCF）。
- `common.glsl:19-22` — `cubeLength` 立方范数近似径向长度，用于畸变因子（顶点级调用；相对 `length` 的指令代价未实测，本报告不把它计为收益）。
- `common.glsl:24-30` — `getShadowBias`：偏置按畸变因子（`cubeLength*0.85+0.15`）与 `log2(max(4, 影距-分辨率/8))` 缩放，法线经 shadow 投影/模型矩阵旋转；顶点级一次。
- `gbuffers_textured.fsh:66-84` — 片元只做 PCF：Vogel 盘 × `SHADOW_SAMPLES`（编译期循环展开，:70）+ 逐像素 IGN 旋转（:69,59-61），半径 = `SHADOW_SOFTNESS/shadowMapResolution`（:68）；结果以 `mix(1-强度,1,vis)` 调制光图（:83）。
- `gbuffers_textured.fsh:72-79` — `TRANSPARENT_SHADOWS` 编译期三档：2=逐 tap 用 `shadowcolor.a` 衰减半透明影（默认档，每 tap 一次 shadowcolor 读取）；1=只读 shadowtex1；0=只读 shadowtex0（后两档完全不读 shadowcolor）。
- `shadow.vsh:20-21` — 阴影 pass 顶点应用同一 `distort()`（与消费端同式），z 缩半归一到 [0,1]。
- `shadow.vsh:23-27` — `FOLIAGE_SHADOW` 未定义时，flat 材质（`mc_Entity.x==1`，block.properties:12 把草/花/甘蔗/火把等整组归到 ID 1）顶点退化 `gl_Position=vec4(10)`，整类不投射；默认定义存在（common.glsl:6）即树枝草叶照常投影。
- `shadow.fsh:9-13` — 影子片元仅 `gtexture×glcolor` 拷贝，无额外计算。

### 云

- `gbuffers_clouds.vsh:24-35` / `gbuffers_clouds.fsh:27-42` — 原版云几何 + `texture×light×blindness`，直接复用 `gl_Fog`；零 raymarch、零自定义云缓冲/历史。

### 雾与大气

- `gbuffers_textured.fsh:93-98`（及 `gbuffers_basic.fsh:26-31`、`gbuffers_clouds.fsh:34-39`） — 全包复用原版 `gl_Fog` 参数（水下 `1-exp(-d*density)`、陆地 clamp 线性两式），零自定义雾计算、零雾 pass；batch3 VanillAA 已记「雾复用原版 gl_Fog」（SUMMARY-batch3.md:158）。
- `gbuffers_skytextured.vsh/fsh`、`gbuffers_basic.vsh:23-29` — 天空/基本几何只算世界坐标与 `gl_FogFragCoord`，天空纹理仅 `×blindness`（fsh:29-32），无大气散射/天空 LUT。

### 水与水下

- `gbuffers_textured.fsh:93-98` — 水下仅 exp 雾分支（原版密度/颜色），无折射、无吸收、无焦散、无 SSR、无水面法线；水几何与其他方块共用同一 lit 程序。

### 粒子·实体·天气

- `gbuffers_basic.vsh:23-29`、`gbuffers_basic.fsh:34` — 非受光几何只乘 `(1-blindness)`；实体受击闪色走 `entityColor` 混合（gbuffers_textured.fsh:90-91）。
- 无天气/降雨专属代码；雨强度不进阴影或光照（对比 Astra 的雨天联动已实现）。

### 后处理与缓冲内存

- `composite.fsh:209-301` — 可选 FXAA（McNopper 版）：对比度早退（:253-258，`lumaMax-lumaMin <= lumaMax*lumaThreshold`）→ 方向估计（:268-274）→ 内 2 tap（:277-280）；再用 4 tap 与 luma 区间校验，越界降级回 2 tap（:285-300）。全路径最多 10 次纹素采样（`:228` 与 `:230` 各取一次中心纹素），非边缘像素 6 次后早退。
- `final.vsh:5-7` / `final.fsh:8-11` — final 仅 `texture×gl_Color` 拷贝。

## 反面印证（不值得学的性能做法）

- **默认档每 PCF tap 无条件读 `shadowcolor`**：`gbuffers_textured.fsh:72-74` 在 `TRANSPARENT_SHADOWS==2` 下每个 tap 都取一次 shadowcolor.a，无「存在透明遮挡才读」的门控；8 tap = 16 次 hardware shadow2D + 8 次 shadowcolor 采样。Astra 已有全亮 gather 早退、开放水面 gather 快路与 `COLORED_SHADOWS` 编译期门控（`Astra/shaders/global/lighting/shadowmap.glsl:140-178`），材料亦已把「彩色阴影仅在遮挡时读」列为 Astra 已有（SUMMARY-batch3.md:133）。
- **采样循环内逐 tap 三角函数**：`vogelDiscSample` 每 tap 一次 `cos/sin`（`gbuffers_textured.fsh:49-57,70-71`），可改为常量表/旋转递推；盘采样本身已在材料中列为已知方向（SUMMARY.md:22）。
- **`vec2 coord1 = coord1;` 自赋值声明**（`gbuffers_textured.fsh:65`）：无效写法，光图坐标实际依赖 varying 遮蔽；同类遮蔽 uniform 的 `float near/far` 在 vanilla_enhance 中也出现。
- **菜单悬空项**：`shaders.properties:3` 的 `SHADOW_DISTORT_FACTOR`、`SHADOW_BIAS` 在 `common.glsl:1-12` 无对应宏，滑条不生效；无 profile/size.buffer，低配只能逐滑条调，无「关效果+缩资源」联动（对照 Astra 96 处 `program.*.enabled`、52 处关闭缩编）。
- **偏置不随面朝向**：`getShadowBias(..., faceNoL)` 形参未使用（`common.glsl:24-29`），统一偏置；Astra 有 grazing bias `*(1-ndotl)`（`Astra/shaders/global/lighting/shadowmap.glsl:242-243`）与 End 分支的斜率项。
- **无帧不变量预计算**：`shaders.properties` 仅 5 行、无 custom uniform 表达式，`shadowLightPosition` 等每顶点重算（`gbuffers_textured.vsh:58`）；五份材料已列「CPU 预计算 uniform」（SUMMARY.md:116，12 包印证）。
- **FXAA 无深度/几何门控**：全屏所有高频纹理细节都进入边缘搜索与 4 tap 外扩（`composite.fsh:253-300`），且中心纹素在 `:228`/`:230` 重复采样一次；Astra 的 FXAA 有 `geometryOnly` 深度差早退（`Astra/shaders/global/post/fxaa.glsl:30-38`）与对比度阈值早退（同文件 `:48`），已更细。

## 新颖借鉴点（A/B/C）

- **A：0 条；B：0 条；C：0 条。** 本包相对 Astra 的性能手法全部落在「已实现」或「五份材料已列」两类：硬件 PCF、畸变+偏置、顶点级阴影投影、背光跳过、编译期采样档、program 熔断、FXAA 早退等（逐条见下表）；其「高性能」来自功能裁剪（无延迟、无体积、无反射、原版云/雾/光图），不提供可迁移的新机制。
- 最接近可借鉴的两项均已排除：硬件 PCF + 逐顶点 shadowPos（Astra `Astra/shaders/program/lit.vsh:181` 已顶点投影）；Vogel 盘 + IGN 抖动（材料 SUMMARY.md:22 已列、Astra 角点配对核承担同等职能 `Astra/shaders/global/lighting/diffuse.glsl:257-273`）。

### 候选去重排除明细（机制 | 包内出处 | 排除依据）

| 候选机制 | 包内出处 | 排除依据 |
|---|---|---|
| 硬件 PCF（sampler2DShadow + shadow2D + `shadowHardwareFiltering` const） | common.glsl:12; gbuffers_textured.fsh:19-20,74-78 | Astra 已有硬件/软件比较模式分流：`Astra/shaders/lib/settings.glsl:34,68,450-457`、`Astra/shaders/global/lighting/shadowmap.glsl:39-45,119-131`；grep `shadowHardwareFiltering\|sampler2DShadow` 命中 |
| 径向畸变 + 畸变补偿法线偏置 + 顶点级 shadowPos | common.glsl:19-38; gbuffers_textured.vsh:62-68 | 材料已列「阴影畸变/偏置形式对照」（SUMMARY-batch2.md:29）；Astra 已有 `Astra/shaders/lib/distort.glsl:19-31` + `Astra/shaders/global/lighting/shadowmap.glsl:205-246`（偏置含畸变项 `:242-243`）+ 顶点投影 `Astra/shaders/program/lit.vsh:181`（「坐标在顶点投影后插值」契约见 `Astra/shaders/global/lighting/shadowmap.glsl:15` 注释） |
| Vogel 盘 + IGN 逐像素旋转 PCF | gbuffers_textured.fsh:49-61,68-71 | 材料已列「R2/黄金角旋转盘抖动 PCF（4 包印证）」（SUMMARY.md:22）；Astra 现为角点配对核 `Astra/shaders/global/lighting/diffuse.glsl:257-273`，功能等价 |
| 阴影采样数编译期 1–16 档 | common.glsl:3 | Astra 影核分档 4/8/16（材料 SUMMARY.md:115-116 已列；`Astra/shaders/global/lighting/diffuse.glsl:270-291` lobeCount 分档），属已覆盖手段（batch3 §2.5-7） |
| 背光（NoL<0.01）顶点跳过 + 光图预暗化 | gbuffers_textured.vsh:69-72 | Astra 背光跳过 + 静态阴影兜底：`Astra/shaders/global/lighting/diffuse.glsl:259-263,331-343`；batch3 §2.5-7/2.5-8 已列 |
| 树叶/草投影顶点退化（`#ifndef FOLIAGE_SHADOW`） | shadow.vsh:23-27; common.glsl:6 | 材料 batch3 §2.1 已列「阴影投射顶点级剔除」（SUMMARY-batch3.md:68）；Astra 当前有材质级提前退出（`Astra/shaders/program/shadow.vsh:52-58,97-102`）整体实体投影开关（任务背景） |
| 半透明/彩色阴影编译期三档 | gbuffers_textured.fsh:72-79 | Astra `Astra/shaders/global/lighting/shadowmap.glsl:140-178`（全亮 gather 早退 `:140`、开放水面 gather 快路 `:151-163`、`COLORED_SHADOWS` #ifdef `:171-173`、水镜头 `:174-177`）更细；材料已列「彩色阴影仅在遮挡时读」 |
| program 级 pass 熔断（FXAA 关=composite 不跑） | shaders.properties:5 | 材料共识「程序级 pass 熔断」（SUMMARY.md:115，10 包印证）；Astra 96 处 `program.*.enabled`（`Astra/shaders/shaders.properties:88-104` 等） |
| FXAA 对比度早退 + 2/4 tap 降级 | composite.fsh:217-220,253-258,289-300 | Astra `Astra/shaders/global/post/fxaa.glsl:30-38,48` 已有深度几何门控与对比度早退；属已实现 |
| 顶点级面方向光近似（法线平方加权 + flat 法线） | gbuffers_textured.vsh:47-53 | 材料已列「无阴影档方向感」（SUMMARY-batch2.md:24，drdestens/bvs）与「光照常量顶点阶段」（SUMMARY-batch3.md:276）；Astra 为前向逐像素光照，不可替换 |
| 原版几何云 + 原版 `gl_Fog` 复用 | gbuffers_clouds.fsh:27-42; gbuffers_textured.fsh:93-98 | batch3 VanillAA 已记「雾复用原版 gl_Fog」（SUMMARY-batch3.md:158）；Astra 已有独立云/雾模型（不适用；SUMMARY-batch2 ⑤-6 雾模型判无借鉴价值） |
| `shadowDistanceRenderMul=1.0` | common.glsl:10 | Astra `Astra/shaders/lib/settings.glsl:335`（=1.5，配 `Astra/shaders/lib/distort.glsl:15` 注释的畸变外圈利用） |
| 空 `#ifdef FXAA #endif` 保选项 | common.glsl:14-16 | 材料已列 Mellow「空 #ifdef 保选项技巧」（SUMMARY.md:136） |

## 无法判定项

1. **程序回退链未核证**：包内缺 `gbuffers_terrain/water/entities/hand/skybasic`，其实际渲染依赖 Iris/OptiFine 把缺件回退到 `gbuffers_textured`/`gbuffers_basic`；工作区无平台文档，无法确认「地形/实体/手持/水全走同一 lit 路径」的准确范围（影响管线描述，不影响「无新颖性能手法」的结论）。
2. **畸变形式对照的增益**：`cubeLength` 立方范数（common.glsl:19-22,32-38）相对 Astra `length` 径向畸变（`Astra/shaders/lib/distort.glsl:19-31`）的纹素分布差异与常数换算无法从源码判定；材料已把该方向列为中期候选（SUMMARY-batch2.md:29），如需采纳应先做独立对照实验（且 Astra 侧要求实验放独立文件）。
3. **`TRANSPARENT_SHADOWS` 的平台语义**：Iris 下 `shadowtex1`/`shadowcolor` 对半透明 caster 的 alpha 填充细节未查证；不影响「Astra 已有更强等价门控、无需借鉴」的判断。
