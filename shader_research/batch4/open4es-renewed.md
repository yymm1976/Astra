# open4es-renewed 调研（batch4 · Astra 视角）

> 纯只读调研，未改动 Astra / 参考包内容。file:line 基准：`reference_shaderpacks/open4es-renewed/shaders/`（该包 shader 根即 `shaders/`）；Astra 侧引用未写 `Astra/` 前缀时相对 `Astra/shaders/`。
> 去重依据：`shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`。
> **同源提示：info.txt:1-6 自述「部分代码不属于作者，属于 BSL 等」**（云/水/星空/反射/水雾/水下扭曲/水下折射/运动模糊/dither/环境色/光色/水色/常用函数与变量归 BSL；阴影归 HexBR_ 的 hexlightsimulationproject）。BSL 已在批次一研究（`shader_research/bsl-shaders.md`），故本报告只报「低配改造」相对增量。

## ① 概况

- **定位**：任务给定 Modrinth v1.0.1 / 91,503 下载；「为低配设备设计的简洁光影，Open4ES 的 Java 版 Renewed」。README.md 只有标题（无正文）；info.txt 为致谢；无作者帧时/机位数据。
- **血统**：BSL + HexBR_ 阴影的拼装改造（info.txt:1-7），作者自称 CilokGaming（lang/en_US.lang:2-4）。相对 BSL（批次一已研究）的增量是**做减法**：删掉云、Bloom、TAA、体积云/体积雾、SSAO 独立 pass、多段 composite 链与延迟光照，改为「gbuffers 内一次前向光照 + 单 deferred（SSAO/反射）+ final（tonemap/godrays/水下扭曲）」。
- **许可**：根目录 LICENSE（674 行）= **GNU GPL v3 全文**；**代码内无任何文件头版权/许可声明**（与 BSL 逐文件署名相反）。GPL 家族理论上可代码级借鉴（义务：保留许可、声明修改、随包附文本、THIRD-PARTY.md 登记）；但 info.txt 自述代码来自 BSL，而 BSL 本体为保留所有权利且包内无授权文件（SUMMARY ③），**该 GPLv3 授权对 BSL 来源部分的有效性存疑**，动代码前需统帅确认（见 备注）。
- **规模（整包口径）**：98 文件；shader 代码（.fsh/.vsh/.glsl）**88 文件 / 3,403 行**；另有 shaders.properties（38 行）、block.properties（58 行）、lang/en_US.lang、tex/1024|256 两张 noise.png（+mcmeta）；world1 与 world-1 的 final.fsh 逐字节相同。**非 shaders/ 的代码目录：无**。分布：根 shaders/ 6 文件 1,107 行（gbuffers_main.fsh 603、gbuffers_main.vsh 203、gbuffers_sky.fsh 166、gbuffers_sky.vsh 39 + 两个 properties）、world0 40/1,028、world1 22/682、world-1 22/682。

## ② 管线与调度

**program 清单**：

```
shadow（恒开）→ gbuffers_*（前向光照；colortex0=颜色，colortex1=打包法线+matID，仅 REFLECTION 开时写）
              → deferred（世界 0：SSAO + SSR/雨反射 + 反射源拷贝；世界 1/-1：colortex0→colortex4 透传）
              → final（水下 UV 扭曲 + 雨膜 + 15 步 godrays + tonemap；世界 1/-1 的 AO 也在这里）
```

- 共享源：根目录 gbuffers_main.fsh/vsh 与 gbuffers_sky.fsh/vsh；各维度只放 `#define GBUFFERS_*/OVERWORLD|NETHER|END` + include 的薄壳（如 world0/gbuffers_water.fsh:1-3）。
- **无 composite 链、无 prepare、无 shadowcomp、无 compute**；final 是唯一显示端 pass。
- 世界 0 与 世界 1/-1 的差异：world1/world-1 的 deferred 是 14 行透传拷贝（world1/deferred.fsh:1-14，`DRAWBUFFERS:4`），AO 挪进 final（world1/final.fsh:7、255-289）；world0 的 AO 在 deferred（world0/deferred.fsh:4、213-242）。

**shaders.properties（38 行）**：

- **CPU 预计算 uniform**（:4-25）：`lightPositionClip`（CPU 端把日月位置乘投影矩阵，含 worldTime 判别 `between(worldTime,12786,23215)` 与 `-moonPosition.z`，:4-7）；`TimeFix`/`line0-3`/`flag_sunset|night|day`（时段的 smooth 曲线，:9-16）；`rainday`/`rainnight`/`clearStrength`；`waterFogColor`（按 day/night/sunset × rainStrength 三段混合的水雾色，:22-25）。
- `texture.gbuffers.gaux2 = tex/1024/noise.png`（:28）。
- 强制渲染设置（:31-36）：`dynamicHandLight=true`、`underwaterOverlay=false`、`shadowTranslucent=true`、`oldLighting=false`、`separateAo=true`、**`clouds=false`**。
- 菜单一行（:39）：CILOKG / TONEMAP / REFLECTION / FOG / ENABLE_SSAO / VOLUMETRIC_LIGHT / SHADOW / shadowMapResolution（选项本体是各 .fsh 顶部的 `#define`，如 gbuffers_main.fsh:3-4、world0/deferred.fsh:4-6、world0/final.fsh:5-6）。
- **无 `size.buffer`、无 `program.*.enabled`、无缓冲尺寸/清空声明**；缓冲格式写在 world0/final.fsh:51-56 的注释指令（colortex0 R11F_G11F_B10F、colortex1 RGBA16、colortex2 RGBA16、gaux1 RGBA16；world1/-1 用 RGBA8/RGB10_A2）。
- 常量（gbuffers_main.fsh:79-88）：`shadowcolor0Nearest=true`、`shadowtex0Nearest=true`、`shadowtex1Nearest=true`、`noiseTextureResolution=256`、`shadowMapResolution=2048`、`sunPathRotation=-40`、`ambientOcclusionLevel=0.5`、`shadowDistance=120`；`shadowHardwareFiltering=true` 在 world0/final.fsh:48；`wetnessHalflife=30`/`drynessHalflife=5` 在 world0/final.fsh:61-62。

## ③ 分模块性能手法清单

### 3.1 调度与阶段启停

- 全包只有 3 个阶段（shadow → gbuffers → deferred → final），且 gbuffers 前向光照省掉一整段延迟光照 pass。
- 效果以源内 `#define` 为编译期开关（REFLECTION/FOG/ENABLE_SSAO/VOLUMETRIC_LIGHT/SHADOW），经 screen/lang 暴露；关闭时相关分支整段消失（如 gbuffers_main.fsh:3、425、600；world0/deferred.fsh:6、284、307）。
- **`clouds=false`（shaders.properties:36）**：原版云渲染整体关闭；world0/gbuffers_clouds.fsh:4-7 再 `discard` 兜底。
- 反面：无 `program.*.enabled`、无 `size.buffer`、无关闭时资源缩编；REFLECTION 关时仍做 ray march（④-1）。

### 3.2 地形光照与阴影

- 前向光照在 gbuffers 一次算完：NdotL（gbuffers_main.fsh:481）、日光/环境/方块光三项（:556-561），无延迟光照 pass。
- 9 点固定盘 PCF：`shadowOffsets[9]`（:98-108），循环内对 shadowtex0/shadowtex1 各做 `step()` 软比较（:338-339），**每点无条件读 shadowcolor0**（:341），透射色 `shadowColor.xyz*(1-a)` 与不透明可见度混合（:342-344）。
- 阴影图圈外不查询：`shadowDist < 1.0 ? CalculateSunlightVisibility(...) : vec3(1.0)`（:547）；斜率相关偏移（:543-544）。
- 叶片固定 NdotL=0.5（:482）；湿度/水洼法线（:460-461、476）；specular 通道复用（`spec.z = GetLuminance(spec.xyz)` :468，水洼重映射 :495-496）；自发光取 `spec.w - step(1.0, spec.w)`（:561）。
- 方块光陡峭曲线 `pow(lmCoord.x,10)*1.2 + lmCoord.x*0.6`（:559-560）+ 指数重映射 `DrawLightMap`/`torchColorComp`（:135-145）。
- 湿面反射：非叶子像素按 `fresnel*rainStrength` 混入屏幕空间反射（world0/deferred.fsh:302）。

### 3.3 云

- 无云程序：`clouds=false` + gbuffers_clouds `discard`（gbuffers_main.fsh 与 world0/gbuffers_clouds.fsh:4-7）。这是本包低配定位的最大单项删减（Astra 已有自有云，无迁移价值）。

### 3.4 雾与大气

- 解析天空 `GetSky`（gbuffers_main.fsh:302-315：两色 + fogify 高度混合），天空 pass 直接复用（gbuffers_sky.fsh:156-159）。
- 距离雾按视线距离幂 `fogDist = pow(length(viewPos)/far, 3)`（world0/deferred.fsh:276-277），仅非天空像素（:279-287）。
- 水下雾：`1-exp(-2*length(viewPos)/24)`（gbuffers_main.fsh:317-328）。
- 雨膜在 final：屏幕空间 `rainMask` 乘暗化 + 加色（world0/final.fsh:294、330-331）。
- 时段色板 4 组（morning/day/evening/night）+ 天气混色（gbuffers_main.fsh:509-538；final 重复一份 :315-325）。

### 3.5 水与水下

- 水面 albedo 直接置黑只留 alpha 0.5（gbuffers_main.fsh:471），颜色全在片元算。
- 水波法线：`GetWaterHeightMap` 5 次噪声叠加（:219-237），`GetParallaxWaves` 4 步视差（:239-247），`GetWaterNormal` 5 点差分（:249-265）——**每个水面像素最多 9 次高度采样 × 5 次噪声取数**；含距离/掠射门 `mult`（:221、226）。
- 水下吸收/雾 `GetWaterFog`（:317-328）+ `albedo.w` 混合（:574-577）。
- SSR `Raytrace`：30 步上限、出屏 ±0.05 即 break、命中后最多 4 次细化、border 遮罩（:380-413、415-435）；反射回退解析天空 + 星空（:588-589）。
- 反射源 = 上一帧拷贝：deferred 在 REFLECTION 开时把场景色写 colortex4（world0/deferred.fsh:307-310），水面/雨反射读它。

### 3.6 粒子·实体·天气

- 天气只写 rainMask：`gl_FragData[0] = vec4(0,0,0,albedo.w)` 到 colortex1（world0/gbuffers_weather.fsh:6-11），final 按 alpha 染色（world0/final.fsh:330-331）。
- 实体/手/粒子共用主程序薄壳；无独立粒子程序，缺省回退到 textured/basic。
- 末地/下界与主世界共用同一份光照常量与时段模型（gbuffers_main.fsh:509-538 无维度分支，仅 `GetSky` 有 `#ifdef OVERWORLD`，:310-314）。

### 3.7 后处理与缓冲内存

- final 单 pass 完成：水下 UV 扭曲（world0/final.fsh:96-103，单 sin 无纹理）、雨膜、15 步屏幕空间 godrays（:256-286）、tonemap 枚举（7 种，:105-209；默认 ProjectTonemap = 去饱和 + Uncharted2 白点缩放，:105-115）。
- godrays 入口门：`if (lightPositionClip.w > 0.0)`（:257，光源在镜前才走）；步数固定 15、无提前退出（:267-278）。
- 缓冲格式注释声明（:51-56）；无 TAA/Bloom/DoF/运动模糊程序（全包 grep 0 命中，与 info.txt 致谢 BSL 的条目不符，属删减后遗留）；
- 上一帧反射源拷贝（world0/deferred.fsh:307-310）。

## ④ 反面印证（不值得学）

1. **REFLECTION 关闭时仍做完整 ray march**：`SimpleReflection`→`Raytrace`（30 步循环）无条件调用（world0/deferred.fsh:296、189-206），`#ifdef REFLECTION` 只包住 `color = textureLod(gaux1,...)` 一行（:199）；该档下步进结果只用于 `pos.z < 1.0` 门与 border，属纯浪费。对照 Astra：效果关时靠 program 门/早退整段停（docs 已列「阶段启停 + 零强度停调度」）。
2. **9 点阴影每点无条件读 shadowcolor0**（gbuffers_main.fsh:341）：不透明遮挡占绝大多数像素，本可像 Astra 一样「遮挡/半透明权重>0 才读」（Astra 见 global/lighting/shadowmap.glsl:143-177：先 gather 水位/可见度，再按透明权重逐角 `texelFetch`）。
3. **昂贵反射/星空在无消费时也每像素计算**：deferred 无条件算 `SimpleReflection` + `GetSky(rePos)` + `DrawStars`（world0/deferred.fsh:296-299），实际只用 `fresnel*rainStrength`（:302）；final 里 godrays 有门但雨膜/天空色同样全屏计算（world0/final.fsh:294、330-331）。
4. **godrays 双分支完全相同**（world0/final.fsh:269-277 `isEyeInWater != 0` 与 else 一字不差），15 步无早退/无 sky 起点裁剪。
5. **维度复制式结构**：world1/final.fsh 与 world-1/final.fsh 逐字节相同；world0 与 world1 的 final 是同一模板的两份拷贝（AO 位置/格式声明不同）；时段常量块在 5+ 个顶点着色器里重复（gbuffers_main.vsh:158-175、gbuffers_sky.vsh:16-33、world0/deferred.vsh:16-38、world0/final.vsh:13-31、world-1/world1/final.vsh）——Astra 已统一为 CPU uniform。
6. **死代码/死数据**：`vTexCoordAM`/`vTexCoord`/`texRes` 在 gbuffers_main.fsh:11-12,20 声明、main 中无任何使用（vsh:187-198 白算）；`timeVector.w`（MORNING）在 6 处顶点着色器计算但全包无人读取（gbuffers_main.vsh:175 等）；`eastVec` 传入 deferred 未用（world0/deferred.vsh:20）；`fadeSun`（gbuffers_main.fsh:492）与 `highlight` 恒 0（:500、561）白算。
7. **`#if !defined GBUFFERS_WATER || !defined GBUFFERS_HAND_WATER` 逻辑错误**（gbuffers_main.fsh:488-490、563-565）：两个宏不会同时定义，条件恒真，sRGB 往返对水/手水也执行（多两次 pow，且与注释意图相反）。
8. **天气几何写脏 GBuffer 辅助缓冲**：weather 用 `DRAWBUFFERS:1` 覆盖 colortex1（法线+matID 缓冲，world0/gbuffers_weather.fsh:9-10），而 deferred 以 colortex1.xy 解法线、.z 取 matID（world0/deferred.fsh:247、252）——雨像素上的法线/matID 被 (0,0,0,mask) 覆盖；仅在 REFLECTION 开时 colortex1 才有用，属隐式耦合。
9. **水法线成本与观感不成比例**：单像素最多 9×5 噪声取数（3.5），且视差 4 步不改 footprint，远距离仍全额执行（只有幅值衰减）。

## ⑤ 新颖借鉴点

### A 组（低代价可直接排期）

无。

### B 组（中代价需接线）

无。

### C 组（大工程战略项）

无。

**判定说明**：本包所有可迁移的性能机制都能在 Astra 现有实现或五份材料中找到等价项（下表逐条对照）；反向的浪费模式已收入 ④。故本包结论为「无新颖借鉴点」，价值在反面印证与低配对照。

### 去重排除（本包候选手法 → 已列/已实现证据）

| 本包机制 | 出处 | 判定依据 |
|---|---|---|
| 雨条不进光照/阴影链（只留 alpha 掩码）+ final 染色 | world0/gbuffers_weather.fsh:6-11；world0/final.fsh:294、330-331 | Astra 已等价实现且更完整：`program/lit.fsh:249-253` 降水只用天空环境 + 方块光（注释明示跳过 surface lighting/shadow/SH），:179-190 只留强纹理条纹 + 降透明度 + 染色；另有 `gbuffers_weather.vsh` 雨幕剪切（program/lit.vsh:118-130） |
| 原版云几何 discard + `clouds=false` | world0/gbuffers_clouds.fsh:4-7；shaders.properties:36 | Astra 已有：`shaders.properties:314 clouds=off`；`program/clouds.fsh:26-33`（CLOUD_OFF/平面云时 discard 几何） |
| 9 点 PCF + shadowtex0/1 手写 step 比较 | gbuffers_main.fsh:98-108、330-351 | 材料已列「阴影核分档 / 软件-硬件比较模式」（Astra lib/settings.glsl:451-457 + global/lighting/shadowmap.glsl:133-194） |
| 阴影图圈外不查询（返回全亮） | gbuffers_main.fsh:547 | 材料已列（batch2「阴影越界钳制/查询边界」2 包印证；Astra global/lighting/shadowmap.glsl:66-80 类） |
| SSAO 10 步 × 正反 2 点 + `pow(ao, ambientOcclusionLevel)` | world0/deferred.fsh:213-242 | 材料已列（AO 距离淡出/相位螺旋族）；Astra 为半分辨率 12 采样黄金角 + 保边重建 |
| SSR 30 步 + 出屏 break + 4 次细化 + border 置信 | gbuffers_main.fsh:380-435 | 材料已列（SUMMARY ②-2/§2.5：有限步进 + 二分细化 + 出屏退出 + 置信度） |
| 反射源 = 上一帧场景拷贝 | world0/deferred.fsh:307-310 | 材料已列（batch3 B 组「上一帧重投影 SSR」arc-shader；Astra 水反射历史模块 RETIRED/槽位已改用途） |
| 解析天空 + SSR miss 回退天空/星空 | gbuffers_main.fsh:302-315、588-591 | 材料已列（SSR miss 回退 6 包印证；Astra lib/sky_reflection_cache.glsl + 解析回退） |
| 湿面/水洼：noisetex 掩码 + spec 重映射 + 涟漪法线 | gbuffers_main.fsh:460-461、476、495-496、184-217 | 材料已列（水洼掩码 + 孔隙度材质响应 7 包印证；Astra `lib/wet_material.glsl`、`astra_puddle`、`astra_rain_ripple`，program/lit.fsh:157-166、229-237） |
| 水下吸收指数 + 水下 UV 扭曲 | gbuffers_main.fsh:317-328；world0/final.fsh:96-103 | 材料已列（batch1 ②-2「水下 UV 扭曲 + 雾色偏」4 包印证；Astra global/water/absorption.glsl / optics.glsl） |
| CPU 预计算：投影太阳位置/时段曲线/水雾色 | shaders.properties:4-25 | Astra 已实现（材料「帧不变量/调色下沉 CPU」；Astra lib/uniforms.glsl:28-59 等） |
| godrays 入口 w>0 门 + 固定步数屏幕空间 | world0/final.fsh:256-286 | Astra 已有 CPU 端 `godraysOffscreenFade`（shaders.properties:603-613，含 `clipLightVector.w > 0.0`）与半分辨率 8 样本 + 二段平滑（global/post/godrays.glsl:44-80；program/scattering.fsh:120 为零强度早退） |
| 法线 2 通道打包（Encode322/Decode223）+ matID 进 .z | gbuffers_main.fsh:130-133、600-603；world0/deferred.fsh:247、252 | 材料已列（batch3 C 组 GBuffer 打包观察项）；Astra 已有 RGBA8/R11F 压缩（lib/surface_buffers.glsl:14-29） |
| 自发光从 specular alpha 整数部分提取 | gbuffers_main.fsh:561 | 材料已列（IPBR 自发光启发式，SUMMARY ②-1；Astra lib/surface_emission.glsl） |
| 时段色板/天气混色 + 雨天阴影衰减 | gbuffers_main.fsh:505-553 | 材料已列（batch1 ②-1 雨天阴影衰减 + 天光补偿）；Astra 已有 weather.glsl 与 shadowmap 雨天项 |
| 云上无雨/手光/材质位等小项 | — | 与材料 2.5「Astra 已覆盖手段」逐条对应 |

## ⑥ 无法判定项

1. **shadowcolor0 透射色链的实际有效性**：world0/shadow.fsh 只有 `/* DRAWBUFFERS:0 */` + `gl_FragData[0] = albedo`（:16-20），包内无 shadowcolor0 写入端；但 `shadowTranslucent=true`（shaders.properties:33）时引擎侧是否把半透明几何颜色并入 shadowcolor0，无法从包内源码判定。若实际为空，gbuffers_main.fsh:341 的 9 次读取恒得 0（彩阴/透射逻辑与那 9 次取数均为浪费）——需实机验证。
2. **GUI 宏选项行为**：`//#define REFLECTION`（gbuffers_main.fsh:3）、`//#define FOG`（world0/deferred.fsh:5）、`#define ENABLE_SSAO`/`VOLUMETRIC_LIGHT` 等由 screen/lang 暴露，Iris 实际能否按菜单切换取决于引擎对「源内 #define + lang 选项」的处理，源码层无法判定（影响的是 ④-1 是否发生在默认配置）。
3. **维度差异输出残留**：world0 与 world1/-1 的 colortex1 格式（RGBA16 vs RGBA8）与 AO 位置不同，是否造成同机不同维度画质/开销差异，需实机确认。
4. **`texRes`/`vTexCoordAM` 设计意图**：声明+顶点写入但全包无读取（3.7/④-6），是未完成的重采样功能还是遗留死代码，无法判定（不影响性能结论）。
5. info.txt 致谢的 BSL 运动模糊在本包中不存在（全包 0 命中）；是删减遗留还是另有分支，无法判定。
6. 全部结论为源码级推断，包内无帧时数据；「低配」收益需 Astra 实机 A/B（尤其 ④-1、④-2 的可回收量）。
