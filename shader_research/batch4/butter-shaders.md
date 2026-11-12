# butter-shaders 调研（batch4 · Astra 视角）

> 纯只读调研，未改动 Astra / 参考包内容。file:line 基准：`reference_shaderpacks/butter-shaders/shaders/`（该包 shader 根即 `shaders/`）；Astra 侧引用未写 `Astra/` 前缀时相对 `Astra/shaders/`。
> 去重依据：`shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`。
> **同源提示：本包不是独立实现，而是已研究包 `makeup-ultra-fast-shaders`（MakeUp Ultra Fast 9.5f）的上游旧分支修改版**；下文只报相对增量，MakeUp 9.5f 报告与五份材料已列的手法一律不列为新颖点（见 ⑤ 去重排除）。

## ① 概况

- **定位**：任务给定 Modrinth v1.2d / 89,468 下载。包内 README.md:1-3 自述 `MakeUp - Ultra Fast (Legacy)` / `Version: 6.80L: Consistency`；helpful.txt 是传送/失明等测试指令。
- **血统**（对照包内 README 与代码头）：
  - 全部主体文件带 `Javier Garduño - GNU Lesser General Public License v3.0` 头（如 world0/gbuffers_terrain.fsh:1-5、lib/config.glsl:1-5、common/deferred_fragment.glsl:2-6）；
  - shaders.properties:1 为 `# MakeUp - shader.properties`，菜单含 `[MakeUp]` 组（:40、:62-63）；
  - 修改部分带 `Typon` 头（Input/GetCaustics.glsl:1-4、lib/shadow_frag.glsl:1-4），Input/composition.txt:1 自述 `//Butter - shaders`，菜单另有 `[Typon]` 组（:40-42）。
  - **相对 9.5f 的增量**：本包没有 prepare 阶段、没有 Voxy/DH 变体与 lang 目录；新增 `Input/` 预处理库（Bayer/Clamp/Const/GetCaustics/LightShaft/Time/rainbow）、`lib/past_projection_utils.glsl`、`src/cloudfog_vertex.glsl` 与 **deferred1 / deferred2 / composite3 三个附加全屏 pass**；同名文件的内容已被改写（阴影、水、雾见 ③）。
- **许可**：根目录 LICENSE（7,652 字节）= **GNU LGPL v3 全文**；各文件头声明 LGPL-3.0 + 作者 Javier Garduño；README.md:25-30 有作者口头放宽（非许可条款）。可代码级借鉴，义务同 MakeUp 报告 ⑤（保留版权/许可、声明修改、随包附许可文本、THIRD-PARTY.md 登记）。
- **规模（整包口径）**：218 文件；shader 代码（.fsh/.vsh/.glsl）**205 文件 / 6,639 行**；含 shaders.properties 与 Input/*.txt 为 211 文件 / 7,022 行；另有 2 张 PNG（shaders/textures/）与根目录 README/LICENSE/Credits/helpful.txt。**非 shaders/ 的代码目录：无**。分布：Input 9 文件/426 行、lib 26/1,983、src 10/436、common 32/2,161、world0 48/789、world-1 40/486、world1 42/482。

## ② 管线与调度

**program 清单**（world0 为默认实现，world-1=#define NETHER、world1=#define THE_END 薄壳同构）：

```
shadow → gbuffers_*（terrain / textured / water / hand / hand_water / entities / block /
         clouds / skybasic / skytextured / weather / spidereyes / beaconbeam / armor_glint / basic）
      → deferred → deferred1 → deferred2 → composite → composite1 → composite2 → composite3 → final
```

- 无 prepare、无 shadowcomp、无 compute、无独立效果分辨率缓冲。
- 无独立粒子程序（world0 无 gbuffers_particles / damagedblock / line 等）；缺省程序由引擎回退（见 ⑥-4）。

**shaders.properties（166 行）**：

- 10 档 profile（no_effects → shadowless_low/medium/high → low/medium/high/extreme → all_effects/all_effects_hq，:4-13），每档由约 30 个效果宏线性降级；`program.shadow.enabled=SHADOW_CASTING` 是**唯一**的程序级熔断，四个 world 各一行（:32-35）。
- 强制渲染设置（:16-26）：`vignette=false`、`underwaterOverlay=false`、`clouds=fancy`、`sun/moon=true`、`frustum.culling=true`、`shadow.culling=true`、`separateAo=false`、`oldLighting=false`、`dynamicHandLight=true`。
- **CPU 预计算 custom uniform**（:84-163）：pixel_size / inv_aspect、`day_moment`、`day_mixer`/`night_mixer`（抛物线 f/g，公式注释 :97-98）、`day_vol_mixer`/`night_vol_mixer`/`vol_mixer`（四次幂曲线 :110-118）、`light_mix`（worldTime 阈值 :121-127）、TAA Halton-10 offset（`frame_mod = fmod(frameCounter,10)`，:129-160）、`fov_y_inv`（:163）。用法见 lib/color_utils.glsl:7-52、lib/volumetric_light.glsl、src/light_vertex.glsl。
- **缓冲分档**：无 `size.buffer`/无独立效果分辨率（全缓冲全分辨率，与 MakeUp 9.5f 同特征）；格式与清空标志写在 common/final_fragment.glsl:4-62 的注释指令（colortex0 R11F、colortex1 随 DOF 用 RGBA16F、colortex2 随 BLOOM 用 R11F/R8、colortex3 随 DOF 用 RGBA16F、gaux1/3/4 R11F、gaux2 RG8；8 个缓冲 colortex*Clear=false）。
- 各缓冲写入者（理解 ③ 用）：colortex1=场景色（solid :180-182、water :292-294、deferred :191-193、composite :249-256）；colortex2=bloom 源（composite :249-252）；colortex3=TAA 历史（composite2 :82-84）；gaux1=反射源（deferred :191-193）；gaux2=云纹理（properties:29-30 绑定）；gaux3=折射源（deferred2，Input/composition2.txt:43）；gaux4=雾/材质元数据（仅 gbuffers_skybasic 与 gbuffers_water 写，src/writebuffers.glsl:8-15、common/water_blocks_fragment.glsl:292-294）。

## ③ 分模块性能手法清单

### 3.1 调度与阶段启停

- 阴影整阶段可关：`program.shadow.enabled=SHADOW_CASTING`（shaders.properties:32-35），关后走假阴影（3.2）。
- 效果宏档位降级（:4-13）：AO/AOSTEPS、V_CLOUDS、VOL_LIGHT、BLOOM_SAMPLES、AA_TYPE、SHADOW_RES、CLOUD_STEPS_AVG、REFLECTION_SLIDER 等。
- 帧常量 CPU 化（:84-163），着色器零成本取用。
- 反面：除 shadow 外无任何 `program.*.enabled`；composite/composite1/composite2/composite3 与 deferred/deferred1/deferred2 恒跑（见 ④-4）。

### 3.2 地形光照与阴影

- 4 次硬件阴影采样 + 遮挡才读彩色阴影：`get_shadow` 对 shadowtex1/shadowtex0 各做 ±offset 两采样打包成 vec2（lib/shadow_frag.glsl:49-54）；仅当检测到遮挡且不透明/半透明可见度不同才读 shadowcolor0（:13-23）；手部程序编译期跳过彩色读（:17 `#if !defined GBUFFER_HAND`）。
- 阴影抖动半径：`current_radius = dither` × `SHADOW_BLUR` / `shadowMapResolution`（:44-47）。
- 阴影图边界淡出：顶点算 `shadow_diffuse = pow(径向距离,10)`（src/shadow_src_vertex.glsl:70-72），片元 `mix(shadow_c, 1.0, shadow_diffuse)`（common/solid_blocks_fragment.glsl:130-131、common/water_blocks_fragment.glsl:178-179）。
- 阴影距离外叶片回退：`SHADOW_LIMIT`（随 SHADOW_RES 档 = 75/100/105，lib/config.glsl:143-216）之外把叶片直射混回无阴影值（common/solid_blocks_vertex.glsl:129-135；源值 src/light_vertex.glsl:84）。画质修正性质。
- 无阴影档假阴影：`visible_sky^10` 幂衰减（src/light_vertex.glsl:147-158）。
- 洞穴最低环境光 `AVOID_DARK_LEVEL`，按天光 luma 比缩放（:130-136）。
- AO：每步正反两点（AOSTEPS=4 → 8 次深度采样，lib/ao.glsl:28-45）；手部深度差 ×1024 排除（:18）；按雾密度距离衰减（common/deferred_fragment.glsl:159-169）。
- 阴影设置：`shadowHardwareFiltering=true`（lib/config.glsl:212）、`shadowtex1Nearest=false`（:214）、`generateShadowMipmap=false` / `generateShadowColorMipmap=false`（:140-141，见 ⑤-A1）、`shadowIntervalSize=3.0`（:139）、`eyeBrightnessHalflife=6.0`/`centerDepthHalflife=1.0`（:225-226）。
- 方块光烛光曲线 + 上限：`mix(0.85,0.65,pow(nvisible_sky,10)) * (x²+pow(1.165x,6))`，clamp 4.0（src/light_vertex.glsl:27-38）。
- 阴影开启时直射再乘 `visible_sky`（:156）——用天光图当直射门（画质近似）。

### 3.3 云

- 只在天空像素跑：`linear_d > 0.9999` 门（common/deferred_fragment.glsl:93-121）。
- 上下云板交点求差 + `CLOUD_STEPS_AVG=7` 步（lib/volumetric_clouds.glsl:84-115）；云内厚度累加（:131-143）；近板 blur 带软化（:144-163）；首接触密度（:137-142）。
- 水面反射复用 `get_cloud`，步数取半 `int(CLOUD_STEPS_AVG*0.5)`（common/water_blocks_fragment.glsl:164-172）。
- 形态演化档 V_CLOUDS==2 追加同纹第二采样（lib/volumetric_clouds.glsl:116-119）。
- 反面：`clouds = fancy` 恒开（shaders.properties:19）；V_CLOUDS>0 时原版云几何未被剔除，该程序输出 vec4(0.0) 并写进 colortex1（world0/gbuffers_clouds.fsh:13-17 → common/clouds_blocks_fragment.glsl:19-24 → src/writebuffers.glsl:4-6）。

### 3.4 雾与大气

- 雾强度在顶点算：`pow(clamp(fogFragCoord/far) * eyeBrightFactor, mix(density,1,rain))`（src/fog_vertex.glsl:4-19）。
- 雾色来自屏幕空间 gaux4 **同像素**采样（src/finalcolor.glsl:19-38；:25 实体、:34 其余）。
- 天空/雾/云色用 CPU 昼夜 mixer 解析混合（lib/color_utils.glsl:16-52）。
- 下界/末地雾色简化（src/finalcolor.glsl:1-18；common/skybasic_fragment.glsl:31-33）。

### 3.5 水与水下

- 反射两档：翻转图 = 反射向量投影一次 + `pos.x = abs(pos.x)` 屏幕折叠 + 边缘 fade（lib/water.glsl:172-190）；Raymarch 档实际未运行（:23，见 ④-1）。
- 法线波 4 次噪声采样合成（:98-126），随 `lmcoord.y` 压平。
- 折射：1 次 gaux3 采样 + 深度差平方吸收曲线（:130-156）。
- 玻璃独立路径 `cristal_shader`（:237-301）；水/玻璃按 `block_type > 2.5 / 1.5` 分流（common/water_blocks_fragment.glsl:175、279）。
- 深水色 `deepCol` 每通道常量乘子（:92-94）；太阳高光解析（lib/water.glsl:78-96，用于 :219-223）。
- 水面把 `block_type` 等元数据写进 gaux4 供 tonemap 分类（common/water_blocks_fragment.glsl:292-294；消费者 lib/tone_maps.glsl:48-54：天空/水面各用不同色调曲线，`isWater = gaux4.g > 2.5`）。

### 3.6 粒子·实体·天气

- 实体发光/闪电廉价路径（common/solid_blocks_fragment.glsl:112-127、169-176）；黑实体 bug 的 `discard` 兜底（:96-100）。
- MATERIAL_GLOSS：按方块/实体 ID 三类的极廉价各向同性高光（common/solid_blocks_vertex.glsl:137-158 + common/solid_blocks_fragment.glsl:142-158 + lib/material_gloss_fragment.glsl:17-30）。
- 天气几何与主体共用 common/ 实现（world0/gbuffers_weather.fsh 薄壳）；无独立粒子程序，缺省程序回退（⑥-4）。
- 末地体积云专用实现 lib/volumetric_clouds_end.glsl（:5-110，与主世界同构、步数同样由 CLOUD_STEPS_AVG 控制）。

### 3.7 后处理与缓冲内存

- TAA：5 点（4 角+中心）方差钳制 + 速度混合 `exp(-|v_px|)*0.2+0.7`、luma 归一化抗鬼影（lib/fast_taa.glsl:12-36、40-70）；重投影在 composite2 片元（common/composite2_fragment.glsl:57-70）；同 pass 双写 colortex0（显示）+ colortex3（历史），`colortex3Clear=false`（:76-88）。
- Bloom：源在 composite 预阈值写入（`smoothstep(0.85,1.0,luma(color*exposure))*0.4`，common/composite_fragment.glsl:244-252）；composite1 用 `mipmap_bloom` 在 LOD -2 螺旋 2×BLOOM_SAMPLES 采样（lib/bloom.glsl:9-38），天空像素强度 0.15（:34-38）。
- DoF：失焦前置零——`blur_radius > min(pixel_size)` 才取 2 次 LOD -2 采样（lib/blur.glsl:12-33）。
- 运动模糊：深度门 + 坐标 clamp，固定 MOTION_BLUR_SAMPLES 次（lib/motion_blur.glsl:8-38）。
- 曝光：composite/final 顶点算 `exposure`（common/composite_vertex.glsl:64-77）；final 顶点有一段死代码（common/final_vertex.glsl:31-43，算完即置 1.0）。
- 缓冲内存：格式随效果切换、8 缓冲非清空（common/final_fragment.glsl:20-62）；无半分辨率缓冲。
- 调试：final 的四分屏 DEBUG_MODE（common/final_fragment.glsl:115-128）。
- 相对 9.5f 的净增 pass：LightShaft 屏幕空间光束（Input/LightShaft.glsl:44-91 + world0/composite3.fsh）、天空彩虹（world0/deferred1.fsh:80-92）、反射/折射源预处理（Input/composition2.txt:10-48 + world0/deferred2.fsh）。

## ④ 反面印证（不值得学）

1. **SSR Raymarch 档是死代码**：`for (int i = 0; i < 0; i++)`（lib/water.glsl:23）；`RAYMARCH_STEPS`（lib/config.glsl:31-32）与 `SSR_TYPE=1` 都不产生步进，`infinite` 恒 0、玻璃回退 `pos.x > 99.0` 永不触发（:245-247）。「宣传高性能 + 选项存在」不等于算法存在。
2. **LightShaft pass 恒调度**：默认 `//#define LightShaft`（Input/LightShaft.glsl:3），但 world0/composite3.fsh 仍每帧跑一个全屏 pass（读 colortex0 写 colortex0，Input/composition.txt:40-48）。
3. **雾缓冲生产者/消费者错位**：只有天空像素（src/writebuffers.glsl:8-15，仅 gbuffers_skybasic 定义 SET_FOG_COLOR）与水面像素（common/water_blocks_fragment.glsl:292-294）写 gaux4，而所有不透明像素按自身坐标采样它当雾色（src/finalcolor.glsl:34）。非天空/水面像素读到未定义或陈旧内容；不能作为雾做法迁移。
4. **档位不熔断 pass**：composite*/deferred* 恒跑，profile 只改片元分支（shaders.properties:4-13 无 program.*.enabled，仅 shadow 有）。
5. **原版云几何未随体素云关闭**：`clouds = fancy` 恒开（shaders.properties:19），默认 V_CLOUDS=2（lib/config.glsl:82）时原版云几何仍被光栅化并写零（world0/gbuffers_clouds.fsh:13-17 + src/writebuffers.glsl:4-6）；对比 MakeUp 9.5f 的 `#if V_CLOUDS > 0 clouds = off`（makeup-ultra-fast-shaders/shaders/shaders.properties:26-27）。
6. **代码质量缺陷**：LightShaft 里逗号运算符 `vL *= (9.0, caveFactor)`（Input/LightShaft.glsl:83）、以颜色作插值因子 `mix(sL, aL, vL)`（:68）、`texture2D(depthtex1, texcoord * -10.0)`（:53）、未用变量 w/caustics4（:89-108）；SHADOW_RES 配置表内 5/6 档完全相同（1580/0.85）、3 档 `SHADOW_DIST=4.0` 与其余档（0.7-0.85）明显不一致（疑笔误，lib/config.glsl:161-198）。
7. **相对同源 9.5f 净增 3 个全屏 pass**（deferred1/deferred2/composite3）换观感，同时删掉了 9.5f 的 prepare 等路径、也没有任何降分辨率缓冲——「Legacy 版」的性能形象主要来自功能少与档次低，而非新调度手段。

## ⑤ 新颖借鉴点

口径：每条已对 `Astra/shaders` 多关键词 grep；命中等价实现或五份材料已列者移入「去重排除」，不进 A/B/C。

### A 组（低代价可直接排期）

**A1. 关闭 shadow map / shadowcolor 的 mip 生成**

- 机制：`const bool generateShadowMipmap = false; const bool generateShadowColorMipmap = false;`——本包全程只按 LOD0 采阴影图，显式关掉每帧阴影图 mip 链生成。
- 来源：lib/config.glsl:140-141。
- Astra 侧未实现证据：
  - `grep -rn "generateShadowMipmap\|generateShadowColorMipmap" Astra/shaders` → **0 命中**；
  - `grep -rn "MipmapEnabled" Astra/shaders | grep -v vendor` → 仅 prepare2.fsh:6（colortex11）、program/display.fsh:36,39（colortex7/2）、program/nether_reflection.fsh:24（colortex0），**无 shadow 图**；
  - `grep -rn "textureLod(shadow\|texture2DLod(shadow" Astra/shaders` → **0 命中**（阴影取数全在 LOD0：textureGather/texelFetch，见 Astra/shaders/global/lighting/shadowmap.glsl:133-194）。
- 迁移代价：一行 const 放进被所有程序包含的设置文件即可；**前置核实两点**：(a) Iris 对 `generateShadowMipmap` 的默认值（若已默认 false 则本条无收益）；(b) Astra 有一处隐式 LOD 采样 `texture(shadowtex1, ...)`（Astra/shaders/global/lighting/shadowmap.glsl:189，硬件比较模式），需确认不依赖 mip 后才可关（否则改显式 LOD0）。

### B 组（中代价需接线）

无。

### C 组（大工程战略项）

无。

### 去重排除（本包候选 → 已列/已实现证据）

| 本包机制 | 出处 | 判定依据 |
|---|---|---|
| 无阴影档假阴影 `visibleSky^10` 幂衰减 | src/light_vertex.glsl:147-158 | 五份材料已列（MakeUp 报告 ③.1 / SUMMARY ②-6）；Astra 已有 STATIC_SHADOW_FALLBACK（lib/settings.glsl:87、global/lighting/diffuse.glsl:259-260、global/lighting/shadowmap.glsl:250） |
| 翻转图单次投影反射低档 | lib/water.glsl:172-190 | 材料已列（SUMMARY ②-2「翻转图低配反射」3 包印证；MakeUp 报告 ③.3） |
| 深度 godrays 低档（4-5 步只查深度） | lib/volumetric_light.glsl:111-129 | 材料已列（MakeUp 报告 ③.7 / SUMMARY ②-6） |
| 指数间距 3/5 步阴影图体积光 + 距离 break | lib/volumetric_light.glsl:20-52、71-104 | 材料已列（MakeUp 报告 ② VOL_LIGHT=2 六采样同族） |
| 单 pass mip Bloom（LOD -2 螺旋） | lib/bloom.glsl:9-38 | 材料已列（MakeUp 报告 ③.6）；Astra 已有 mip 链（global/post/bloom.glsl:7-22、program/display.fsh:36-39） |
| Blooom 源在既有 pass 顺带写出 | common/composite_fragment.glsl:244-252 | Astra 已有 0.25 捕获 + mip 链（材料「Bloom 0.25 捕获 + mip 链 + tap 分档」） |
| CPU 预计算昼夜/抖动/雾色 uniform | shaders.properties:84-163 | Astra 已实现（材料列「帧不变量/调色下沉 CPU」；Astra lib/uniforms.glsl:59 等） |
| 阴影 4 采样 + 遮挡才读彩色 + 手部跳过 | lib/shadow_frag.glsl:13-23、49-54 | Astra 已有更强的遮挡/半透明权重门（global/lighting/shadowmap.glsl:143-177）；材料列「遮挡时才读彩色阴影」「阴影核分档」 |
| AO 每步正反两点 + 手部排除 + 距离衰减 | lib/ao.glsl:18,28-45；common/deferred_fragment.glsl:159-169 | 材料已列（AO 距离/雾/水下淡出 3 包印证）；Astra 为半分辨率 12 采样黄金角 + 保边重建 |
| 焦散图案在阴影 pass 逐 texel 计算 | common/shadow_fragment.glsl:15-33 + Input/GetCaustics.glsl:104-113 | Astra 已有（program/shadow.fsh:62-70 写水面高度/光学斜率；消费端 global/lighting/shadowmap.glsl:151-159 textureGather） |
| 水折射深度差平方吸收曲线 | lib/water.glsl:137-153 | 材料已列（折射二次校验族 4 包印证）；Astra 为 Beer-Lambert 分通道吸收 |
| TAA 同 pass 双写当前+历史、历史不清空 | common/composite2_fragment.glsl:76-88 | 材料已列（batch3 3.3 VanillAA「TAA 不单开 pass、历史原地保留」） |
| 云只在天空像素 / 水面反射半步数复用 | common/deferred_fragment.glsl:93；common/water_blocks_fragment.glsl:164-172 | 材料已列（MakeUp 报告：云只天空像素、水面反射半步数） |
| LightShaft 采场景色 mip 累积光束 | Input/LightShaft.glsl:61、90 | 材料已列（godrays 廉价档 4 包印证 + Astra 半分辨率 godrays） |
| 材质 ID 写 gaux4 供 tonemap 分类 | common/water_blocks_fragment.glsl:292-294 + lib/tone_maps.glsl:48-54 | 材料已列（batch2 ②-9 材质策略位打包；Astra 有材质掩码体系） |
| 逐顶点雾/光照常量（顶点算 fog、直射门） | src/fog_vertex.glsl:4-19、src/light_vertex.glsl | Astra 已 CPU 化（材料「顶点常量平替」已列） |
| 各向同性材质高光 MATERIAL_GLOSS | common/solid_blocks_fragment.glsl:142-158 | 材料已列（MakeUp 报告 ②） |
| TAA Halton-10 抖动表 CPU 化 | shaders.properties:129-160 | Astra 已实现（材料「抖动 CPU 化」） |

## ⑥ 无法判定项

1. **焦散写入落点**：common/shadow_fragment.glsl 只有 `gl_FragData[0]`（:23、:32）且**文件内无 DRAWBUFFERS 指令**；该颜色输出进入 shadowtex0 还是 shadowcolor0 取决于 Iris/OptiFine 的 shadow 通道绑定，无法从包内源码判定。因此 3.5/去重表里的「焦散烘进阴影图」是否实际生效不确定（对比 Astra 用显式 `RENDERTARGETS: 0` + 显式数据输出，Astra/shaders/program/shadow.fsh:36-45）。
2. **world0/deferred1.fsh 的第二输出目标**：:91 声明 `DRAWBUFFERS:14`（colortex1+colortex4）但只赋值 `gl_FragData[0]`（:92）——colortex4（反射源）是否保留/是否被写脏取决于实现，无法判定；若被清空，水面反射源链路即断。
3. **LightShaft 的 GUI 项**：ShaftMode/Strength/ColorFormat 等定义在 `#ifdef LightShaft` 内部，而该宏默认被注释（Input/LightShaft.glsl:3）。关闭状态下这些选项名在源码中不存在，Iris 菜单实际行为无法从包内判定（非性能问题）。
4. **缺省程序回退**：world0 没有 gbuffers_particles / gbuffers_damagedblock / gbuffers_line 等，引擎回退到哪个程序、回退后的光照路径是否与本包假设一致，需实机确认（源码层只能看到文件缺失）。
5. **叶子阴影距离回退**（common/solid_blocks_vertex.glsl:129-135）是纯画质修正还是兼有省采样意图，注释未说明，无法判定；且只作用于叶子。
6. 包内无作者帧时数据；A1 的实际收益（若有）需实机 A/B 与 GPU 厂商验证。
