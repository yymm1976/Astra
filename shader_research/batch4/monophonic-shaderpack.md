# monophonic-shaderpack 性能调研（第四批 batch4 · 只读）

> 日期：2026-10-03。范围：只读调研，未改动任何参考包或 Astra 源码。
> 路径约定：本文 file:line 相对 `reference_shaderpacks/monophonic-shaderpack/`（该包 shader 根在 `shaders/` 子目录；下文无前缀路径均相对包根）。Astra 侧相对 `Astra/shaders/`（写 `A:`）。
> 去重基线：已读 `shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`；其中列过的借鉴点一律不计为新颖点。
> 版本/下载量（Modrinth v1.1、94,098）来自任务简报；包内无 pack.json/README/版本号，无法本地复核。

## 概况

- 定位：轻量「玩法友好」向光影：**无阴影图、无 TAA/Bloom/SSR/体积光/云积分**，附加效果全为解析式或单 pass；全屏链仅 5 个 pass（见管线）。
- 血统：**与 batch3 已研究包 Exposa Shaders（`reference_shaderpacks/exposa-shaders/`）同源/同一代码家族**，代码级证据：① block ID 表连未更正的拼写 `mincampfire_cosy_smoke` 都相同（本包 `block.properties:3`，Exposa `shaders/block.properties` 同）；② `Time` 结构 + `byTime` 四关键帧混合逐式相同（本包 `lab/time.glsl:5-31` ↔ Exposa `shaders/lib/time.glsl`，仅排版与 night 项分母 0.03/0.04 有差）；③ vibrance 同为「Thanks to belmu」实现（`lab/color.glsl:34` ↔ Exposa `shaders/lib/color_transforms.glsl:78`）；④ entity 422/423 表一致（`entity.properties:1-2`）。本包是精简版（Exposa 248 文件、含 shadow/SSR/Bloom/TAA/DH/VL，本包 61 文件）。**故本报告只报相对 Exposa/batch3 的增量**：batch3 §3.18 对 Exposa 列出的四个点（VL 取数门控、GBuffer uvec4 打包、TAA Catmull-Rom、单次 worley 水波）在本包均不存在，本包相对增量为零（两者互为上下游无法从包内判定，见无法判定项）。
- 许可：**包内无 LICENSE/README/pack.json/版权文件**（整包递归无 `*licen*`/`*readme*`/`*.md`/`*.txt`）；按默认「保留所有权利」处理，仅思路级。注：`lab/color.glsl:34` 的 vibrance 注明来自 belmu（batch3 Noble 作者，GPLv3），若与其 GPL 实现同源则该片段许可存疑（不影响 Astra 思路级结论）。
- 规模（整包口径）：61 文件，全部在 `shaders/`（含 `tex/waternorm.png` 512×512、`tex/waternorm.png.mcmeta`、`block.properties`、`entity.properties`；包根无其它文件、无非 shaders/ 代码目录）；纯代码（.fsh/.vsh/.glsl）1,457 行（与任务简报一致）。其中 32 个 `gbuffers_*` 文件：`terrain/water/clouds/skybasic/skytextured` 5 组为自有实现（各含 fsh+vsh，共 10 文件），其余 20 个程序（17 个 1 行 `#include` 转发壳 + 3 个 `#define` 变体文件：`entities.fsh/vsh`、`hand.fsh`）共用 `gbuffers_basic` 源码。无 world-1/world1 目录（下界/末地沿用主世界程序）。

## 管线与调度

- program 清单（Iris 名）：`gbuffers_*` 32 文件（见上）；全屏链 `deferred` → `deferred2` → `deferred4` → `composite` → `final`。**没有** `shadow`/`gbuffers_shadow`、`prepare*`、`shadowcomp*`、compute、`gbuffers_line`、DH/Voxy 程序。
- 调度：`shaders.properties:1-15` 只有 1 条 noisetex 绑定（`:1`）、6 个 screen 分组（`:3-13`）与 12 个滑块（`:15`，含 `shadowsMode` 1/2/3、`shadowSamples` 8–256）；**没有** `program.*.enabled`、`size.buffer.*`、profile、buffer 格式声明（grep 0 命中）。
- 缓冲：colortex0 gcolor、colortex1（世界法线.xy / blockid/65535 / 光图.x）、colortex2（法线贴图.rgb / AO）、colortex3（AO，`deferred2.fsh` 写、`deferred4.fsh:61` 读）、colortex4（光图.rgb / 光图.y）、colortex5（entityId/65535）；`lab/bufferinfo.glsl:1-10` 的格式声明整段在块注释内（实际格式交 Iris 默认，见无法判定项）。无历史/mip/低分缓冲。
- 阴影（无 shadow 程序）：`deferred4.fsh:8` 三档——1=屏幕空间射线求交（`deferred4.fsh:55-57` + `lab/rt.glsl:1-45`），2=天光阈值假阴影（`:87-89`），3=关闭；采样数滑块默认 64（`shaders.properties:9,15`）。
- 质量档全部编译期重编译（`#define ... //[值列表]`，如 `deferred4.fsh:3-9`、`composite.fsh:6`）。

## 分模块性能手法清单

### 调度与阶段启停
- `shaders.properties:3-15` — 无 program 启停/无 size.buffer/无 profile；低配靠滑块（`shadowsMode=3`、`shadowSamples=8`）减工作，无资源缩编。
- `lab/fog.glsl:10-12` — `#if fogMult == 0.0 return color;` 编译期关闭雾（全包唯一「关掉即省」的点）。
- 全屏链 5 pass，除 `deferred2`（只写 AO）外无额外低分缓冲；全包无多帧历史。

### 地形光照与阴影
- `deferred4.fsh:43-95` — 不透明地形全光照：光图/blockid/entityId 各一次读 + AO 模糊 + 解析阴影，无任何 shadowtex 采样。
- `deferred4.fsh:55-57` — shadowsMode=1：屏幕空间 ray march，采样数=滑条（8–256），起点加 `dither*0.1`。
- `lab/rt.glsl:11-17` — 步长二选一：DDA（`minChannel((sign(dir)-start)/dir)/sampleCount`）或固定 1/N；`:29` 出屏即 break；`:33` 命中判定 `rayVec.z > sampledDepth && !(sampledDepth < 0.56)`；`:37-44` 命中即 break 并取 colortex0。
- `deferred4.fsh:87-89` — shadowsMode=2：`shadowData *= clamp01(pow(skyLight,200)*900)`，用光图天光通道阈值化成假阴影（零阴影图/零射线）。
- `deferred4.fsh:82` — blockid 1194（叶/草）在 SS 阴影下 `lambertDiffuse=1.0`（假透光）。
- `deferred4.fsh:61` + `lab/blur.glsl:1-20` — AO 保边模糊：7×7 邻域、每 tap 2 次 `texelFetch`（AO+深度）+ `exp` 权重，合计 98 次取数/像素（仅地形像素）。
- `deferred2.fsh:19-33` — AO 本体：9 tap 世界法线点积，`bayer16(gl_FragCoord)` 抖动采样偏移，无法线/深度一致性校验；`:38-39` 只写 colortex3（DRAWBUFFERS:3）。
- `gbuffers_terrain.fsh:37-51` — `directionalLMaps`（默认注释关闭）用 dFdx/dFdy 光图坐标推光方向；`:53-57` 写 4 张 MRT。
- `deferred4.fsh:63-79` — entityId 423/500（玩家/手）跳过方块光与 AO；`:85` `shadowData=min(!isShadow, lambertDiffuse)`。

### 云
- `gbuffers_clouds.fsh:28,42-44,46-50` — 云走通用 gbuffer 路径（贴图×光图、世界法线、skyCol 雾），无自定义云积分/云影/独立预算；`gbuffers_clouds.vsh:30` 只传 eyePos。

### 雾与大气
- `lab/fog.glsl:8-16` — 距离雾：`mix(color, skyData, clamp01(pow2(length(eyePos.xz)/far)*fogMult))` 再叠 blindFog（`:3-6`）。
- `lab/sky.glsl:4-10` — 解析天空色：4 关键帧 `byTime` 三色（地平线/亮/暗）插值 + blindness/darkness 乘子；无大气散射/天空 LUT（Rayleigh/Mie 代码在 `lab/atmosphere_scattering.glsl:1-50` 整段注释）。
- `deferred.fsh:23-31` — 天空合成：对全屏像素先算 `skyCol`，再 `if(isSky) color += skyData`（先算后判，地形像素白付）。

### 水与水下
- `composite.fsh:101-116` — 仅 blockid 8/9（水）执行；水面折射/高光/反射在 composite 全屏 pass 内按 GBuffer blockid 分派，无独立水面/反射 pass。
- `composite.fsh:57-63` — 折射单次采样 + `clamp01(coord)==coord` 屏幕边界校验；无深度范围校验/二次校验。
- `composite.fsh:65-77` — 天空反射：解析 `skyCol` + `1-pow2(dist_xz/far)` 距离衰减 + `getAngle` 有理角权重（`lab/common.glsl:5`：`0.07/(x²+0.07)`）+ `pow2(eyeBrightnessSmooth.y/240)` 门控（`:103`）。
- `composite.fsh:79-87` — 太阳/月亮高光：反射向量与光源方向在眼空间的 `smoothstep(0.075,0.0096,distance)`（单次，无粗糙度/能量项）。
- `gbuffers_water.fsh:63-65` — 水波法线：单张 512² `noisetex`（`shaders.properties:1`）按世界坐标 0.05 缩放 + 两个 sin/cos 滚动，每像素一次采样。
- `gbuffers_water.fsh:69-71` — 非水半透明块乘 `mix(vec3(0.25,0.35,0.5), vec3(1), NdotL)`；`deferred4.fsh:118` 水下用 `fogMix(color, waterColor^4, 5.5*eyePos)` 固定距离吸收。

### 粒子·实体·天气
- `gbuffers_weather.fsh:1` / `.vsh:1` — 雨雪直接转发 `gbuffers_basic`：走完整 gbuffer（写 MRT 01245、法线贴图采样、sRGB 解码），无天气专用轻量路径。
- `gbuffers_basic.fsh:26-37` — `#ifdef entities`：`color.a<0.15` discard + `entityId==422`（entity_shadow）discard；`:49-51` 手部 entityId 写固定值 0.00762951094。
- `gbuffers_terrain.vsh:29-33` — blockid 1194（叶/草）顶点风位移：2 个 sin + 2 个 cos，幅度随 `rainStrength` 增大（无距离 LOD）。
- 手部/armor_glint/beaconbeam/spidereyes 等全部转发 `gbuffers_basic`，无专用程序。

### 后处理与缓冲内存
- `final.fsh:28-40` — 输出链：saturation → contrast（log2/exp2）→ vibrance → Lottes tonemap（常数编译期算好，`:18-23`）→ gamma2.2 pow；单 pass，无 Bloom/TAA/曝光/锐化。
- `lab/bufferinfo.glsl:1-10` — colortex 格式声明整段在块注释内；代码却按 16 位打包回读（`gbuffers_terrain.fsh:55`、`gbuffers_basic.fsh:49`、`composite.fsh:95`、`deferred4.fsh:74` 的 `*65535`）。
- `lab/sample_depth.glsl:8-10` — 在文件作用域无条件采样 depthtex0/1/2 三张深度；包含者多付 1–2 次取样/像素（`deferred.fsh` 只用 depth1，`deferred4.fsh`/`composite.fsh` 只用 depth0/1）。
- 全链无 mip、无历史、无时间累积（无 TAA/Bloom/曝光/SSAO 时域）。

## 反面印证

1. **全分辨率 9-tap AO + 7×7×2 深度加权模糊**（`deferred2.fsh:19-33`、`deferred4.fsh:61`、`lab/blur.glsl:1-20`）：每地形像素约 9 + 98 次取数，且 AO 本身是法线点积、无深度校验；Astra 半分辨率 12 采样 + 保边重建（`A:program/ssao.fsh:31,64-97`、`A:lib/ao_resolve.glsl:19-42`）更省更稳，不学。
2. **先算后判**：`deferred.fsh:23-31` 全屏先算 `skyCol` 再判 `isSky`；`deferred4.fsh:53` 无条件算 `bayer32`（仅 shadowsMode=1 用）；`deferred4.fsh:59` 的 `coloredShads` 门控在所有模式都执行。
3. **逐像素 RGB↔HSV 往返调方块光颜色**（`deferred4.fsh:65-71`：rgb2hsv → hsv2rgb×2）——纯色调旋转却每像素来回换算；Astra 在常量/CPU 色板完成。
4. **包含即付费**：`lab/sample_depth.glsl:8-10` 让每个包含头在文件作用域取 3 张深度，调用点无法裁剪。
5. **无 program/资源级调度**：无 `program.*.enabled`/`size.buffer`/profile（`shaders.properties` grep 0 命中）；对比 Astra（`A:shaders.properties:18-95`、`A:shaders.properties:476-479`），低配只能重编译。
6. **雨雪走完整 gbuffer**（`gbuffers_weather.fsh:1` 转发 basic，写 5 张 MRT + 法线贴图）；Astra 对雨/雪有专用分支与雨溅过滤（`A:program/lit.fsh:173-189`）。
7. **「无阴影图」换低开销不适用于 Astra**：本包以「SS 射线 / 天光阈值 / 关闭」三档替代阴影图，代价是放弃真实遮挡；Astra 生存向需要真实阴影（且已有静态兜底），不构成可迁移项。
8. **未使用工具函数**：`lab/bufferinfo.glsl:88-111`（packNormalData/unpackNormalData）、`lab/samplers.glsl:27-30`（UshorterTexFetch）、`lab/dither.glsl:20`（randF，及其调用的 pcg）无调用点（编译器裁掉，无运行时成本，也无借鉴价值）。

## 新颖借鉴点

**无（A=0 / B=0 / C=0）。** 所有可辨识机制均落入「Astra 已实现」「五份材料已列」或反面对照三类；每条候选均先对 `Astra/shaders` 做了多关键词 grep 并记录 Astra 侧证据：

| 本包机制 | 出处 | 排除依据（Astra 侧证据） |
|---|---|---|
| 天光阈值假阴影 `pow(skyLight,200)*900` | `deferred4.fsh:87-89` | Astra 已实现同族：`A:global/lighting/shadowmap.glsl:250-252` `static_shadow(skyLight)=smoothstep(13.5/15,14.5/15,skyLight)`；`A:global/lighting/diffuse.glsl:259-262` 消费；选项 `STATIC_SHADOW_FALLBACK`（`A:lib/settings.glsl:87`） |
| 屏幕空间射线阴影（整屏替代阴影图，滑条 8–256） | `deferred4.fsh:55-57`、`lab/rt.glsl:1-45`、`shaders.properties:9,15` | Astra 无实现（`grep -rni "ssrt\|contact.shadow\|screen.space.shadow" A:` 0 命中），但机制族已列：`SUMMARY.md:29`（屏幕空间接触阴影 4 包印证，长期）、`SUMMARY.md:37`（Photon SSRT，长期）、`SUMMARY-batch3.md:89`（遮挡深度自适应半影/像素锁定，B 组）；DDA/出屏退出与 Astra SSR 同类（`A:global/water/raytrace.glsl`） |
| 叶类假 SSS（`lambertDiffuse=1.0`） | `deferred4.fsh:82` | Astra 已实现植被透光：`A:global/lighting/sss.glsl:79` `sss_wrap`、`A:global/lighting/diffuse.glsl:141,148,199-200` |
| 9-tap 法线点积 AO + bayer 抖动偏移 | `deferred2.fsh:19-33` | Astra `A:program/ssao.fsh:31,64-97`（半分辨率、12 采样黄金角、双深度/法线配对、水中早退 `:29`）+ `A:lib/ao_resolve.glsl:19-42` 保边重建；AO 抖动起点已列 `SUMMARY-batch2.md:27` |
| 7×7 深度加权 AO 模糊 | `lab/blur.glsl:1-20`（调用 `deferred4.fsh:61`） | 同属 Astra 保边重采样（`A:lib/ao_resolve.glsl`），且 Astra 在半分辨率上做更便宜 |
| 解析天空反射 + 距离衰减 + 亮度门控 | `composite.fsh:65-77,103` | Astra `A:lib/sky_reflection_cache.glsl:48-69`（粗糙度 mip）、`A:program/water.glsl:207,268,329,362`；「反射权重×天空光门控」已列 `SUMMARY-batch2.md:46`；eyeSky 门控见 `A:lib/solas_water.glsl:100,123` |
| 解析太阳高光（反射向↔日月方向 smoothstep） | `composite.fsh:79-87` | Astra 太阳 glint：`A:program/water.glsl:376-381`（`pow(sunAlign, sharpness)`）；「太阳高光解析面积光」已列 `SUMMARY-batch2.md:32` |
| 单 tap 贴图水波法线 | `gbuffers_water.fsh:63-65` | Astra 解析波场 `A:lib/water_wave_lens.glsl:6,19-33`；免纹理波场方向已列 `SUMMARY-batch2.md:43`（4 包），反向贴图化无收益证据 |
| 折射单次采样 + 屏外校验 | `composite.fsh:57-63` | Astra 更强：`A:global/water/refraction.glsl:14-25`（零位移早退、textureGather 深度范围、屏外可见度混合、遮挡回退） |
| 有理角权重 `0.07/(x²+0.07)` | `lab/common.glsl:5` | 已列 `SUMMARY-batch3.md:233`「有理衰减 `w/(x²+w)` 替代 exp」（Builder's QOL） |
| 叶/草顶点风位移 | `gbuffers_terrain.vsh:29-33` | Astra `A:global/lighting/wind.glsl:236-247`（含 128–192 格距离 LOD） |
| 帧常量 byTime 四关键帧 | `lab/time.glsl:12` | Astra 已 CPU 预计算（`A:shaders.properties:496-523` 的 uniform.*/variable.* 表达式） |
| GBuffer 打包（blockid/entityId ÷65535、法线 z 重建） | `gbuffers_terrain.fsh:53-57`、`gbuffers_basic.fsh:49-60` | Astra 自有压缩 GBuffer（`A:lib/surface_buffers.glsl:14-28`）；GBuffer 打包方向已列 `SUMMARY-batch3.md:112` |
| 编译期雾关闭 | `lab/fog.glsl:10-12` | Astra program 阶段启停/分档（`A:shaders.properties:18-95,476-479`）；已列批次一/三 |
| 实体 alpha discard 0.15 | `gbuffers_basic.fsh:26-29` | Astra `A:program/lit.fsh:179,186,189`（alphaTestRef/雨雪阈值） |
| 稀疏写目标（DRAWBUFFERS:3 只写 AO；地形 0124） | `deferred2.fsh:38`、`gbuffers_terrain.fsh:53` | 已列 `SUMMARY-batch3.md:173`「写目标按需切换」；Astra RENDERTARGETS 按需（`A:program/ssao.fsh:18-20`） |
| PCG/bayer 抖动机具 | `lab/dither.glsl:13-20` | Astra `A:lib/bayer.glsl` 已有；无性能增量 |

结论：本包性能价值为**反面对照**（见上节）与「同源 Exposa 的精简版」定位，不产出可排期借鉴点。

## 无法判定项

1. **缓冲格式精度**：`lab/bufferinfo.glsl:1-10` 的 `colortex*Format` 声明全部在块注释内、未生效；若 Iris 默认 RGBA8，则 blockid/entityId 的 `*65535` 打包回读（`gbuffers_basic.fsh:49`、`gbuffers_terrain.fsh:55`、`composite.fsh:95`、`deferred4.fsh:74`）会把 8/9 一类 ID 量化到不可分辨（水效果可能整条不触发）。离线无法确认 Iris 默认格式，故不作断言。
2. **屏幕空间阴影的真实观感/开销**（`shadowSamples` 8–256）：无实机数据；`lab/rt.glsl:33` 的 `!(sampledDepth < 0.56)` 近相机深度排除是硬编码魔数，行为影响无法离线判断。
3. **与 Exposa 的上下游关系**：两者同源证据充分（见概况），但谁派生谁、是否共同祖源，包内无版本/提交信息可判定。
4. **同源片段许可传导**：`lab/color.glsl:34` 的 vibrance 注明 belmu（Noble/GPLv3 作者），是否与其 GPL 实现同源无法从包内判定。
