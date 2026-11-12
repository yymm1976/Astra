# Sildur's Enhanced Default Shaders v1.20 — Astra 可借鉴点调研

- **生成方式**：执行者子代理调研（批次二第 6 包）；非人工审稿，所有 `文件:行号` 来自实读，成稿后重开核对（见附录）。**调研日期 2026-10-02。**
- **包版本**：1.20（包内无版本文件，取自 `shader_research/SUMMARY-batch2.md:70`）。
- **引用约定**：`P:` = 相对 `reference_shaderpacks/sildurs-enhanced-default-shaders/`；`A:` = 相对 `Astra/shaders/`。**表格单元格内**省略这两个前缀（例：表内 `composite.fsh:145` 即 `P:shaders/composite.fsh:145`，`lib/ao_resolve.glsl:19` 即 `A:lib/ao_resolve.glsl:19`，列头已标明侧别）；正文写全路径。
- **A 侧行号时效**：Astra 有并行工作流在改（调研期间 `A:program/taa_resolve.fsh` 由 137→143 行、`A:lib/ao_resolve.glsl` 15:11 被改），A 侧行号以 **2026-10-02 15:16 状态**为准。
- **阅读范围**：P 全包 67 文件/242KB；`shaders/` 下 20 个主世界源码**全文深读**、4 个配置文件全读、维度目录逐一比对；包内无 textures 目录，噪声/法线依赖 Iris 内置 `noisetex` 与资源包 `normals`（`P:shaders/gbuffers_textured.fsh:18,34`）。摘录合规：仅行内短语，无超 5 行摘录块。

---

## ① 概览

- **定位**：Sildur 家族的原版增强档。只做四件事——**阴影、SSR 反射+折射、SSDO、TAA**；天空、云、日月、星空、体积效果全交还原版，只在少数入口接管/补雾/打补丁。**"不写"是它轻量的主因。**
- **管线规模**：11 组程序（shadow / gbuffers_textured / basic / skybasic / skytextured / clouds / composite / composite1 / final / dh_terrain / dh_water），主世界源码 2648 行。**无 deferred、无独立 gbuffers_water/entities/hand**：实体/方块/水/手持共用一条 `gbuffers_textured`，靠自定义 ID 分流（`P:shaders/gbuffers_textured.vsh:18-36`，映射 `P:shaders/block.properties:17-59`），实体特例 `P:shaders/entity.properties:1`。
- **许可证原文**：包内**无 LICENSE/README/任何独立许可文件**（全目录仅 `shaders/` 一层）。唯一声明是源码头部的 "Permissions:" 块，全文仅一句：`P:shaders/shaders.settings:8-9` — `Permissions:` / `You are not allowed to edit, copy code or share my shaderpack under a different name or claim it as yours.` 该句在 20 个文件中逐字重复（`P:shaders/composite.fsh:10-11`、`gbuffers_textured.fsh:10-11`、`shadow.fsh:10-11`、`voxy.glsl:10-11` 等；`grep -rl "You are not allowed"` 命中 20 文件，含 `world-1/voxy.glsl`）。
- **关键实测**：全包 `grep -rniE "reserved|copyright"` **零命中**——没有 Vibrant 的 `All rights reserved`/`Redistribution ... strictly prohibited` 字样，限制文本比同作者 Vibrant 短（Vibrant 原文见批次一报告 ①）。法律默认值不因"未写明"改变，见 ⑤。
- **归属**：Sildur；官网/Patreon/CurseForge 链接 `P:shaders/shaders.settings:2-6`。
- **设置面**：主屏 17 项 + 11 子屏（`P:shaders/shaders.properties:46-60`）、滑条白名单（`:62`）、仅两档 profile `Fast`/`Fancy`（`:68-69`）、CPU 侧 TAA 帧索引 `framemod8=fmod(frameCounter,8)`（`:66`）；`lang/en_US.lang` 217 行逐项 comment（`:206-217`）。

### ①-补 同作者两档对照：Enhanced Default v1.20 vs Vibrant v2.02(Extreme)

Vibrant 侧引用批次一报告（**未重开 vibrant 包**，超出只读白名单）。

| 维度 | Enhanced Default（本包） | Vibrant（批次一报告） |
|---|---|---|
| 管线 | shadow → gbuffers_* → **composite（SSDO/反射/折射/godrays 全在此）** → composite1（仅 TAA） → final | shadow → **deferred**（天空/SSDO/直射光） → deferred1（金属/雨反射） → composite → composite1 → composite2(TAA) → final |
| 天空/云 | 不自绘：原版直通+末地补丁（`gbuffers_skytextured.fsh:21-34`）；1.17+ 重画 skybasic（`gbuffers_skybasic.fsh:27-30`）；**无云模型**（`gbuffers_clouds.fsh:50-51`） | 自绘渐变+日月+星+2D/3D 云五档（报告 ②；`deferred.fsh:165-275,287-433`） |
| 水/反射 | 不设 water 入口（水=ID 10008，`block.properties:44`）；15 步+惰性细化，未命中保 albedo（`composite.fsh:145-187`） | 独立 gbuffers_water：16 步 SSR+天空缓存+焦散+金属反射+视差（报告 ②③） |
| 阴影/AO | 4-tap PCF+**彩色阴影**，无 PCSS，2048/110（`shaders.settings:71-72`）；SSDO 乘进颜色（`composite.fsh:85-137,317`） | PCSS（blocker search 在顶点）+对数扭曲，Extreme 3072/110；同源 SSDO 乘进环境光 |
| TAA | 最近深度重投影+Catmull-Rom(0.82)+3x3 钳制+**对比度锐化**，无速度缓冲（`composite1.fsh:57-156`） | 同族 YCoCg 钳制，按材质跳过锐化（报告 ②；`composite2.fsh:60-157`） |
| 装饰/包体 | DoF/MB/Crossprocess/Tonemap/Celshading **都在但默认关**（`shaders.settings:15,36,38-39,44,47`）；67 文件/242KB | 光斑(420 行)、雨滴屏效、雨湿地面、涟漪、体积光；137 文件，主世界 ~6000 行 |

**结论**：ED 砍掉"需要额外 pass/资产/模型"的一切，留下"一条 gbuffers + 一条 composite 能做完"的四件套；两档共享同一套材质 ID 词汇表与同一张 noisetex 波场。**ED 的价值集中在"低档位/远距/无阴影贴图区"，Vibrant 在中档水面配方，两者互补。**

---

## ② 架构特性清单（按子系统）

**入口与分流（无 deferred 的单入口）**
- 全部几何共用 `gbuffers_textured`：贴图×lightmap×顶点色（`:202`）、法线/POM（`:212-225`）、阴影+自发光（`:227-231,144`）、反射法线编码（`:241-244`）、水色/水下 alpha（`:246-257`）、雾（`:262-275`）、MRT（`:277-278`）。
- `gl_FragData[1]` 装法线+材质：`encode()` 写材质进 `.z`（`:195-197`），消费端 `decode()`+`getmat=normal.z*2.0`（`P:shaders/composite.fsh:58-66,305,309-313`）。**格式常量 `gcolorFormat/gnormalFormat` 在块注释内**（`:21-25`，"Don't remove me"）→ 不生效，精度取决于 Iris 默认（④ 误差来源）。
- 波浪/水/冰/发光/非扩散按 `mc_Entity.x` 分区（`P:shaders/gbuffers_textured.vsh:18-36`）；`noiseTextureResolution=128`（`gbuffers_textured.fsh:18`）；`nMap` 默认 0（`P:shaders/shaders.settings:81-84`）。

**阴影**
- 顶点算阴影空间+扭曲+bias：`distortion=((1-BIAS)+length(shadowpos.xy*1.25)*BIAS)*0.85`、`bias=distortion²*(0.0046*tan(acos(NdotL)))`（`gbuffers_textured.vsh:91-95`）；11 类非扩散方块强制 `NdotL=0.75`、`bias=0.0010`（`:98-111`），无阴影分支同列表固定环境光 0.60（`:334-346`）。
- 片元 4-tap `sampler2DShadow`（`gbuffers_textured.fsh:117-123`）+ 彩色阴影 `shadowtex1/shadowcolor0`（`:130-135`）；抗漏光乘 lightmap.t 与眼亮度（`:138`）；**雨天熔断**（`:128,140`）；水面留 5% 阴影（`:141`，`iswater=0.95` 见 `vsh:261`）。
- shadow pass 裁剪：水面与草类写 `texcoord.z=0`（`shadow.vsh:35-41`）；`shadow.fsh:21` 剔信标光束。

**水体（无独立入口）**
- 顶点两级正弦位移+`clamp(wave,-fy,1-fy)` 防跨块撕裂（`gbuffers_textured.vsh:59-76,252-281`）；水下 alpha 0.9、`waterTex` 开时 `*1.25`（`gbuffers_textured.fsh:246-257`）。
- 波法线 3 八度 noisetex+`rmatrix` 滚动+5 采样中心差分（`gbuffers_textured.fsh:69-101`），仅 `mat>0.9` 写法线缓冲（`:241-244`）；折射在 composite 用**另一份只有 2 八度的** `calcWaves/calcBump`（`composite.fsh:199-213`）偏移 UV（`:347-350`）。
- 反射 15 步+命中后最多 3 次细化、容差 `pow(length(rvector),1.175)`、`cdist` 边缘淡出（`composite.fsh:155-184`）；菲涅尔 `F0=0.09`+pow4（`:343-345`）；`skyReflection` 暗处退回 albedo（`:326-331`）。

**大气/雾（只有接管+补雾）**
- 1.17+ 天 = `mix(skyColor, fogColor, 0.025/(up²+0.025))`（`gbuffers_skybasic.fsh:27-30,50-57`）；云被地形挡住用 DH 深度 discard（`gbuffers_clouds.fsh:46-48`）；DH 地形用抖动半径 discard（`dh_terrain.fsh:38-40`）。
- 同一雾公式在 6 处逐字重复（`gbuffers_textured.fsh:262-275`、`dh_water.fsh:134-141` 等），曲线 `max((dist-fogStart)/(fogEnd-fogStart), dist/newFar*12.5-11.5)`，`newFar=max(far, dhRenderDistance*16)`。**无雾滑条**（仅 `Fog` 开关 `shaders.settings:52,60`）。

**后处理**
- composite = SSDO+反射+折射+godrays 一次 pass：SSDO 取 25 点表前 16（`composite.fsh:85-110,117-136`），半径随深度 `0.05/z`（`:115`）；godrays 20 步 march 深度缓冲、`land=1-near/far/far` 判天地（`:260-295`，开关 `shaders.settings:22`），光源屏坐标顶点算（`composite.vsh:27-31`）；Celshading 深度描边（`:236-257`，默认关）。
- composite1 = 纯 TAA：5-tap 最近相机深度重投影（`composite1.fsh:57-73`）、Catmull-Rom 历史 c=0.82（`:76-102`）、**RGB 域** 3x3 min/max 钳制+双权重（`:141-156`）、对比度自适应锐化（`:131-138`）、离屏早退（`:118`）、4 常量（`:37-40`）；历史 `colortex3`（`:24-25`），写回 colortex0（`:2`）。
- final = DoF（9-tap，`final.fsh:42-79`）/MB（`:81-107`）/Crossprocess（`:142-147`）/Uncharted2（`:109-119,149-151`）；手部与透明层用 depth0/1/2 判定（`:127-140`）。

**Voxy / Distant Horizons（本包最现代的一块）**
- `voxy.json:3-40`：`excludeLodsFromVanillaDepth=false`、两个 `DrawBuffers:[0,2]`、20 项 uniform 白名单、sampler（lightmap/noisetex/depthtex1/vxDepthTexTrans）、两 patch 均 `#include "voxy.glsl"`。
- `voxy_emitFragment()`（`voxy.glsl:139-246`）重写主片元逻辑（mat `:143-151`、光图/自发光 `:156-163`、水色 `:200-212`、非扩散 NdotL=0.60 `:216-228`、反射法线 `:188-198`、MRT `:245-246`），新增两件主程序没有的：**面朝向→法线还原**（`:173-186`，`(face>>1)` 选轴、`face&1` 定正负）与**屏幕空间射线阴影**（`:108-136`：16 步、Bayer 抖动、`diff<thickness(0.05*rayL)`、`exp2(pos.z/8.0)`），深度线性化 `newFar=far+vxRenderDistance`（`:96-100`）。`world-1/voxy.glsl` 为下界版；`world1/`（末地）无 voxy 文件。

**设置与维度**
- profile 仅两档（`:68-69`）：Fast 关 TAA/SSAO/godrays，Fancy 全开；**两档都保留 Shadows+Reflections**。无"超低配"档。TAA 抖动做进几何（8 相偏移表 `gbuffers_textured.vsh:130-143,296`、`dh_terrain.vsh:26-39,48-50`），后处理只做重投影/钳制。
- 维度目录 18 文件/维，除 shadow（130 行 dummy）与 world-1 的 voxy 外全 1 行转发（`world-1/composite.fsh:1`）；dummy 原因见注：`world-1/shadow.fsh:2` "Iris needs dummy files or nether and end are broken if shadowtextures are loaded (since MC 1.21)"。
- block.properties 三套版本分支（`:14,61,82`）；10080/10081 零引用（`:48,50`），见 ⑥。

---

## ③ Astra 可借鉴点（11 条）

工作量口径：小=单文件 <50 行；中=跨 2-3 文件/需接线；大=新 pass 或新契约。全部默认 **Astra 原创重写**（依据见 ⑤）。

1. **Voxy 集成契约（最高价值）**：`P:shaders/voxy.json:3-40`（draw buffer/uniform/sampler 声明）+ `P:shaders/voxy.glsl:139-151,245-246`；`A:voxy.json` 是 **0 字节空文件**，`A:voxy_opaque.glsl:3-4`/`A:voxy_translucent.glsl:3-4` 是 stub，开关已留（`A:lib/settings.glsl:319` 注释态、`A:shaders.properties:429` 挂屏、四档 profile 均 `!VOXY_SUPPORT`）。照 Iris ABI 写声明不算抄，函数体须自写。**工作量：中-大。**
2. **远距/LOD 的屏幕空间阴影**：Voxy 区无 shadow map 覆盖，本包用 16 步 `depthtex1` 射线+Bayer 抖动+厚度阈值（`P:shaders/voxy.glsl:96-136,230-233`）；`A:` 无对应（Astra 无 DH/Voxy 深度路径，阴影走 `A:global/lighting/shadowmap.glsl` 贴图路径）。**工作量：中。**
3. **TAA 对比度自适应锐化（Astra 确认空档）**：3x3 均值/偏差→对比度→加权 9-tap unsharp，`TAA_sharpness=0` 时整段关（`P:shaders/composite1.fsh:131-138`）；`A:program/taa_resolve.fsh` 全程无锐化项（`A:lib/settings.glsl:239` 的 ANTIALIASING 只管相位）。**工作量：小。**（与批次一重复：vibrant 报告 ④TAA 同方向，属"同方向多次出现"。）
4. **雨天/水面的阴影熔断**：雨天跳过采样（`rainStrength<0.9`）+整体乘 `(1-rainStrength)` 平滑，水面只留 5% 阴影（`P:shaders/gbuffers_textured.fsh:128,140,141`）。**工作量：小。**
5. **按材质分类的阴影 bias/NdotL 常数表**：薄面片（草/叶/藤/火/光体等 11 类）统一 NdotL 常量+极小 bias，绕开自阴影噪点；同列表在无阴影分支改作固定环境光（`P:shaders/gbuffers_textured.vsh:98-111,334-346`）；`A:lib/ao_material.glsl:3-5` 是同类判据，`A:global/lighting/sss.glsl:79` 有 `sss_wrap`，但"免自阴影常量"未确认存在。**工作量：小。**
6. **发光体的光图解析自发光**：`modlmap=13.0-lmcoord.s*12.35`、`torch_lightmap=max(1.5/modlmap²-0.00945,0)` 叠加（`P:shaders/gbuffers_textured.fsh:112-115,144`）；`A:lib/surface_emission.glsl:6-12` 只给末地石微弱孔洞发光，`A:lib/settings.glsl:64` 的 EMISSIVE_STRENGTH 是 albedo 乘常数。可作传播光关闭时的兜底。**工作量：小。**
7. **AO 的远距淡出写法**：`mix(AO,1.0,1-exp(-len/(0.2*far-near)))` 同时做"近生效/远消失"（`P:shaders/composite.fsh:316-317`；分母未加括号，重写应写 `0.2*(far-near)`）；`A:lib/ao_resolve.glsl:19-51,54-91` 机制强得多。借"远距淡出项"，别借表（数值表是表达，须自生成）。**工作量：小。**
8. **惰性细化反射**：失败才收缩步长重试（≤3 次、`ref=0.2`、`inc=2.2`）而非固定二分（`P:shaders/composite.fsh:155-184`）；`A:global/water/raytrace.glsl:14-24,58-123` 是固定档位预算。可在 `WATER_EFFECT_QUALITY=0`（`:14-16`）改用。**工作量：中。**
9. **环境亮度驱动的反射基色门控**：只有 `skyColor` 一个 uniform，故用 `eyeBrightnessSmooth.y` 在天空色与 albedo 间混合，暗处不反天（`P:shaders/composite.fsh:326-331`）；`A:lib/sky_reflection_cache.glsl:20-30` 有方向缓存（更强）。借"暗环境降权重"纪律。**工作量：小。**（与批次一重复：batch1 ③1 天空直读回落，同方向第二次出现。）
10. **顶点位移的片段级夹紧**：`clamp(wave,-fy,1-fy)`（`fy=fract(worldY+0.001)`）保证不跨方块边界（`P:shaders/gbuffers_textured.vsh:252-269`）；`A:global/lighting/wind.glsl:5-12,36-39` 波形更强，夹紧有无未确认。**工作量：小。**
11. **维度 dummy 文件的 Iris 纪律**：`world-1/shadow.fsh`/`world1/shadow.fsh` 为空 `main()`（`P:shaders/world-1/shadow.fsh:2-3` 注明 Iris 1.21+ 载入 shadow texture 时缺 dummy 会让下界/末地坏掉），其余一律 1 行转发（`P:shaders/world-1/composite.fsh:1`）；`A:world-1/shadow.fsh:1-4` 结构等价。作为**核对项**。**工作量：小。**

**重复度汇总**：③3、③9 与批次一方向重复（见标注）；其余 9 条未在批次一出现。主动放弃的次要项：设置面板命名对照、Vibrant 已覆盖的云与焦散、ID 命名表、IRIS_END_FIX 式版本补丁（`P:shaders/gbuffers_skytextured.fsh:21-34`，Astra 末地自绘、是否受影响未确认，价值低）。

---

## ④ Astra 已有对应实现对照表

| 技术 | 本包（P:） | Astra（A:） | 哪边更省 / 误差来源 |
|---|---|---|---|
| Voxy 集成 | `voxy.json:3-40`、`voxy.glsl:139-246`（完整） | `voxy.json`（空 0B）、`voxy_opaque.glsl:3-4`、开关 `lib/settings.glsl:319` | **本包唯一全面领先项**。误差：LOD 面法线由 `face` 位还原、深度用 `vxProjInv`（`voxy.glsl:85-90,173-186`），与主场景非同一矩阵 |
| 远距阴影 | 屏幕空间 16 步+厚度+抖动（`voxy.glsl:108-136`） | 无（grep 仅命中开关）；`global/lighting/shadowmap.glsl` 为贴图路径 | 本包省（无需 shadow map 覆盖 LOD）。误差：只认首个深度交叉+固定厚度，细长遮挡漏判 |
| 阴影滤波 | 4-tap `shadow2D`（`gbuffers_textured.fsh:117-123`）+顶点 bias 分类表（`vsh:91-111`） | `lib/settings.glsl:68,83` 档位+`shadowmap.glsl` | Astra 更省更细。误差：本包 `tan(acos(NdotL))` 放大 bias 致掠射角漏光；Astra 的 `sss_wrap`（`sss.glsl:79`）会改有效 NdotL，重写须与 bias 分离 |
| SSDO/AO | 16/25 采样、单帧、乘进颜色（`composite.fsh:85-137,317`） | `lib/ao_resolve.glsl:19-51,54-91`（半分辨率+4-tap+bent normal）、`ao_material.glsl:3-5` | Astra 更强；本包省在实现。误差：本包无重投影会闪；Astra 容差 `0.05`（`:34`）与法线阈值 `0.85`（`:37`）决定重建质量 |
| 反射 SSR | 15 步+惰性细化，未命中保 albedo（`composite.fsh:155-184`） | `global/water/raytrace.glsl:14-24,58-123`（二分+footprint+confidence） | Astra 更稳；本包省在无 gather/history。误差：本包未命中反出自己；波法线与折射偏移来自两份不同参数的 `calcWaves`（`composite.fsh:199-213` vs `gbuffers_textured.fsh:69-86`）→不同相 |
| 折射 | 波场梯度偏移 UV（`composite.fsh:347-350`） | `global/water/refraction.glsl:6-10,11-24`（gather 深度区间+屏外回退） | Astra 省且几何正确；本包偏移量是美术参数（`*0.05`），无折射率依据 |
| TAA | `composite1.fsh:57-156`（无速度缓冲：最近深度重投影+Catmull-Rom+RGB 钳制+锐化） | `program/taa_resolve.fsh:20-30,58,63,86,99-100,137-138`、`taa_state.glsl:13-34`、`taa_jitter.glsl:8-19` | Astra 更完整；本包省在无 colortex 分配与 CPU 相位。误差：`previousPosition.xy = texcoord + (prev - closest.xy)`（`composite1.fsh:112`）是屏幕空间近似，旋转/快移会鬼影 |
| 自发光 | 光图解析式（`gbuffers_textured.fsh:112-115`） | `lib/surface_emission.glsl:6-12`（仅末地石）+`settings.glsl:64`+彩色发光体 `block.properties:91-112` | Astra 彩色分组更强；本包省（不需材质分类）。误差：本包只亮自身、与周边传播光不一致，亮块"浮"在暗地上 |
| DoF/MB/Tonemap/Cel | `final.fsh:42-107,109-119,142-151`、`composite.fsh:236-257`（默认关） | **无对应**（grep DEPTH_OF_FIELD/MOTION_BLUR 零命中）；色调映射 `lib/tonemap.glsl:4-13`（4 算子） | 本包独有但属风格选项。误差：本包 DoF 单点焦点（`final.fsh:52,64-68`），快速推进时焦点跳 |
| MRT 管理 | 显式写 `gl_FragData[1]=vec4(0)`（`composite.fsh:385-386`）；格式声明被注释（`gbuffers_textured.fsh:21-25`） | `taa_resolve.fsh:20` `/* RENDERTARGETS: 0,15 */`+显式格式常量 | Astra 机制更明确。误差：本包材质存 `gnormal.z`（`:196`）而格式常量未生效 → 精度依赖 Iris 默认，`0.9/1.9/2.1` 阈值（`composite.fsh:311-312`）低精度下会误判 |
| 设置面板 | 17 主项+11 子屏（`shaders.properties:46-62`）；**两档都留阴影+反射**（`:68-69`） | `shaders.properties:429,444-447`（4 档+屏） | Astra 档位更细；本包胜在默认保守（DoF/MB/Cel/Crossprocess/Tonemap 全默认关，`settings:15,36,38-39,44,47`）。误差：无（配置层） |

（"雾"一行与批次一 ④ 同向且结论一致，为避免重复不列表；本包侧证据见 ② 的雾条目。）

---

## ⑤ 许可可行性与"重写 vs 抄"边界

- **状态**：无 LICENSE 文件；唯一声明是 20 个文件头重复的一句禁止（`P:shaders/shaders.settings:8-9`）。实测无 `All rights reserved`/`copyright`，但**"未声明"不等于可自由使用**——无授权即默认著作权保留，该句已明确禁止 edit/copy code/换名分享/声称己有。批次二索引亦列入"仅可读思路，重写"（`shader_research/SUMMARY-batch2.md:49`）。**允许**：阅读算法、记录结构与参数、黑盒观察观感、写进设计文档。
- **禁止**：行级搬运、变量级直译、常量表照抄（25 点磁盘表、8 相抖动表等**数值表属表达**，须自生成）、函数命名沿用（`calcWaves/calcBump/calcRays/decode/encode`）、注释块逐字复制。可循范例：`A:global/water/raytrace.glsl:4-8`、`A:lib/wet_material.glsl:4`。
- **两个第三方例外，应走各自上游**：① `P:shaders/composite.fsh:112` 自述 SSDO 改自 Yury O'Donnell 的 MIT 实现（github.com/kayru/dssdo）——若 Astra 要 SSDO，**直接取 MIT 上游**；② `P:shaders/composite1.fsh:17-18` 自述 TAA 基于 Chocapic13——非自由许可，**不可作来源**，Astra 的 TAA 已是原创（`A:program/taa_resolve.fsh:1-2`）。
- **Astra 合规现状**：`Astra/THIRD-PARTY.md` 无 Sildur 条目（批次一已核），本报告**零代码引入**；日后引入须先取书面许可并登记。

---

## ⑥ Top5 + 暂缓项

**Top5（按 提升/工作量）**
1. **Voxy 集成契约落地**（③1）：`A:voxy.json` 0 字节、`A:voxy_opaque.glsl:3-4` 仍是 stub，而开关/屏位已就绪（`A:lib/settings.glsl:319`、`A:shaders.properties:429`）。提升大、工作量中-大、许可零风险。
2. **远距/LOD 屏幕空间阴影**（③2）：没它则 LOD 区在阴影下整体"平掉"。提升中-大、工作量中，可与 1 合并为一个工作流。
3. **TAA 对比度自适应锐化**（③3）：Astra 确认无锐化项，成本极低而 TAA 必软。工作量小。
4. **雨天阴影熔断 + 材质 bias/NdotL 常数表**（③4+③5）：两个小改动消掉"雨天闪变/薄面片自阴影噪点"两类痛点。工作量小。
5. **profile 分层优先级审计**（③8+④设置面板行）：本包两档都保留 `Shadows`/`Reflections`，砍的是 AO/TAA/godrays（`P:shaders/shaders.properties:68-69`）；对照 `A:shaders.properties:444` PERFORMANCE（已关 SSR/折射/焦散/bloom/godrays）。可评估最低档保留一项廉价水反射。

**暂缓项**
- DoF/MB/Crossprocess/Celshading（`P:shaders/final.fsh:42-107,142-147`、`composite.fsh:236-257`）：Astra 无对应，但属风格化产品决策，本包实现是"能跑的最小版"。**与批次一重复**（vibrant 报告 ④ 已列）。
- 月相月盘/3D 体积云/解析焦散/金属反射/雨湿地面：本包**都没有**，属 Vibrant 范围。
- **反面教训**：`10080`/`10081`（`P:shaders/block.properties:48,50`）是零引用死材质类——Astra 的 4-bit 打包材质域预算紧张（`A:block.properties:4-20`），不应复制无消费者的分类；`P:shaders/gbuffers_textured.fsh:21-25` 的"Don't remove me 却被注释"也不应模仿，Astra 用显式格式常量（`A:program/taa_resolve.fsh:20`）。

---

## 附录：自抽查记录（成稿后重开源文件核对，12 条）

方式：成稿后重执行 `sed -n '<行号>p'` / `grep -n` 打印目标行，与正文声称逐字比对。

| # | 引用 | 声称内容 | 核对结果 |
|---|---|---|---|
| 1 | `P:shaders/shaders.settings:9` | 唯一 Permissions 禁止句 | ✅ 一致（逐字相同） |
| 2 | `P:shaders/composite.fsh:85` | 25 点磁盘表起行 | ✅ 一致 `const vec2 check_offsets[25] = vec2[25](...` |
| 3 | `P:shaders/composite.fsh:112` | SSDO 出处 MIT 注释 | ✅ 一致（含 kayru/dssdo 链接） |
| 4 | `P:shaders/composite.fsh:343-345` | F0=0.09 与 pow4 菲涅尔 | ✅ 一致（三行全对） |
| 5 | `P:shaders/gbuffers_textured.fsh:113` | `modlmap=13.0-lmcoord.s*12.35` | ✅ 一致 |
| 6 | `P:shaders/gbuffers_textured.vsh:91` | distortion 公式 | ✅ 一致（`*0.85` 结尾） |
| 7 | `P:shaders/composite1.fsh:37` | BLEND_FACTOR 0.1 | ✅ 一致 |
| 8 | `P:shaders/final.fsh:110` | Uncharted2Tonemap 定义 | ✅ 一致 |
| 9 | `P:shaders/voxy.glsl:139` | voxy_emitFragment 签名 | ✅ 一致（`VoxyFragmentParameters`） |
| 10 | `P:shaders/world-1/shadow.fsh:2` | Iris dummy 注释 | ✅ 一致（含 "since MC 1.21"） |
| 11 | `A:voxy.json` | 0 字节空文件 | ✅ 一致（`wc -c`=0） |
| 12 | `A:program/taa_resolve.fsh:137-138` | 输出与负深度反应标记 | ✅ 一致（138 行 `gl_FragData[1]=vec4(min(resolved,...), -1.0 : storedDepth)`） |

**核对中发现并已修正的问题（如实记录）**
1. `A:program/taa_resolve.fsh` 原引用（132 行=反应标记）**在调研期间失效**：该文件 2026-10-02 15:16 被并行工作流改动（137→143 行），现正确行号为 **132=`resolved = mix(...)`、137-138=输出**；正文已改用 137-138，头部已标注 A 侧行号时效。
2. `A:lib/ao_resolve.glsl`（15:11 被改）与 `A:global/lighting/*`（15:08-15:11）本轮全部重核：`19/34/37/54/89`、`blocklight:59-60`、`wind:5-12,36-39` 通过。
3. 其余 A 侧引用（`settings.glsl:319`、`raytrace.glsl:14-24`、`refraction.glsl:6-10`、`sky_reflection_cache.glsl:4-6,20-30`、`taa_jitter.glsl:8-19`、`taa_state.glsl:13-34`、`effect_history.glsl:17-30`、`fog.glsl:127-132`）均在各自文件最后修改时间之后复核，一致。
4. P 侧 12 条抽查全部一致、无错行；报告无超 5 行摘录块。阅读覆盖度：P 侧主世界 20 源码+4 配置全读、维度目录逐一 diff；A 侧未读位置在 ④ 已标"未确认"。
