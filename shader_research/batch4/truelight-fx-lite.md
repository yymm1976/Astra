# truelight-fx-lite 性能调研（batch4）

> 只读调研，不含对 Astra 的任何改动。包内路径相对 `reference_shaderpacks/truelight-fx-lite/shaders/`；Astra 侧路径相对 `Astra/shaders/`。
> 版本：Modrinth v5.6.3（任务给定，包内无版本元数据文件，[假设]）。下载量 190,816（任务给定）。
> 去重口径：先读 `shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`，再对 `Astra/shaders` 多关键词 grep。

## 一、概况

- 定位：低配硬件的轻量原版风格光影。无延迟管线，光照全部在前向着色阶段完成；全屏阶段只有 composite（TAA/运动模糊）与 final（FXAA/水下焦散/光柱/Bloom/色调映射/抖动）两个。
- 血统：原 TrueLight FX（`LICENSE.md:3`，Copyright 2022 Mateus A. Kreuch）→ 现由 Simon L. / OGCRAFTNET STUDIOS 维护（`LICENSE.md:4`）。代码为 OptiFine 时代结构（根目录薄壳 `#version 120` + `ftransform()`，实际逻辑在 `program/`）；全包 grep `BSL|Complementary|Chocapic|Solas|Capt Tatsu` 零命中，与已研究包不同源，按自研口径报机制、无需报相对增量。
- 许可：MIT（`LICENSE.md:1-2`）。允许代码级借鉴，需保留版权与许可文本；本报告未复制任何实现片段。
- 规模：`shaders/` 树 91 文件 / 1910 行（.glsl/.fsh/.vsh，实检 1910）；`program/` + `common/` 共 1634 行，根目录 22 个程序文件均为「`#version 120` + 维度 define + `#include "/program/<同名>"`」薄壳。另有随包分发的 `shaders.properties.backup`（54 行重复文件，工程卫生问题）。

## 二、管线与调度

- 程序清单：gbuffers_basic / textured_lit / water / clouds / skybasic / spidereyes / armor_glint / weather、shadow、composite、final。world-1（`#define THE_NETHER`）与 world1（`#define THE_END`）为薄壳复用 `program/` 源；末地另有 `world1/gbuffers_skytextured.fsh`。
- 缓冲布局：gbuffers 写 colortex0（场景）；water 程序 `DRAWBUFFERS:067` 额外写 colortex6（法线）与 colortex7（水/冰标记，`program/gbuffers_water.fsh:158-161`）；composite `DRAWBUFFERS:13` 把 TAA 结果写 colortex1（显示色）与 colortex3（历史，`program/composite.fsh:115-123`）；final 读 colortex1/6/7。**全包无 size.buffer、无独立分辨率缓冲**，所有目标与主画面同分辨率。
- shaders.properties（54 行）无任何 `program.*.enabled` 熔断：质量/效果全部是 `shader.h` 编译期 define（BLOOM/TAA/FXAA/MOTION_BLUR/SUN_RAYS/WATER_CAUSTICS/FOG_ENHANCEMENT/REALISTIC_WAVES/WAVY_PLANTS/SMOOTH_SHADOWS，`shader.h:4-95`）。仅有的管线级开关是 `#ifndef IS_IRIS` 下停用 3 个程序（`shaders.properties:43-47`，OptiFine 兼容，与 Iris 性能无关）。
- 档位：4 个 profile（`shaders.properties:1-4`，Low→"Your PC isn't that slow, is it?"）；阴影分辨率/距离/畸变间隔为 `const`（`shader.h:61-66`，512/32 格起步）；实体影三态 `SHADOW_ENTITY` 与 `PLAYER_SHADOW` 条件开关（`shaders.properties:31-41`）；`shadow.culling=true`、`shadowBlockEntities=false`、`shadowTranslucent=false`、`shadowHardwareFiltering=true`（`shaders.properties:49-52`）；`colortex1Clear=false`、`colortex3Clear=false`（`:53-54`）。

## 三、分模块性能手法清单

### 调度与阶段启停
- `shaders.properties:1-4`：profile 以 `!MACRO` 组合直接改编译 define，档位=功能组合。
- `shaders.properties:43-47`：非 Iris 环境停用 clouds/skybasic/armor_glint 程序（唯一程序级开关）。
- `program/composite.fsh:117-123`：TAA 关闭时仍无条件写历史目标 colortex3（`gl_FragData[1]`），历史缓冲不复用、不缩编。

### 地形光照与阴影
- `common/getSunStrength.fsh:4-15`：`SHADOW_PIXEL`（默认 16）把阴影查询世界坐标量化到 1/16 格网格后再投影——同格内所有像素共享一次阴影采样（像素锁定）。
- `common/getSunStrength.fsh:17-20`：距离超 `shadowDistance` 或 `diffuse<=0`（背光）提前返回，不投影、不采样。
- `common/getSunStrength.fsh:35-59`：SMOOTH_SHADOWS 档用黄金角螺旋（SHADOW_QUALITY 4/8/16/32 档）+ 每像素固定旋转 `random(floor(gl_FragCoord.xy))`（无帧抖动）。
- `common/getSunStrength.fsh:47,53,61-63`：`shadowDepthScale = 3.0/shadowProjection[2].z` 把深度差连续映射为 0..1 软边（单采样）。
- `common/getShadowDistortion.glsl:1-5`：`xy/(0.8|xy|+0.2)` 径向畸变，近处纹素密集。
- `common/getDiffuse.vsh:1-12`：顶点阶段算 Lambert（含薄片材质折减、雾/雨衰减），片元只乘用。
- `program/gbuffers_textured_lit.fsh:60-75`：阴影处环境光暗化+蓝移、日光按反照率亮度调制。
- `program/shadow.vsh:13-15`：`SHADOW_ENTITY==0` 时把 `mc_Entity>11000`（实体，除玩家 31000）顶点退化为 0，省 shadow pass 光栅；`:21-26` 火焰（10072）alpha=0 丢弃。
- 材质 ID 表：`block.properties:1-8`（水/冰/岩浆/矿石/草叶/树叶/火/沙）；实体表 `entity.properties:1-3`。

### 云
- `program/gbuffers_clouds.fsh:54-66`：CLOUD_STYLE=0 直接用原版云纹理 × 顶点色，与太阳/环境色混合，alpha 由顶点雾量淡出。
- `program/gbuffers_clouds.fsh:41-52,67-100`：CLOUD_STYLE=1 每像素 3 次 fbm（各 4 阶 = 12 次 2D 噪声）生成密度/造型，无早退。
- `program/gbuffers_clouds.vsh:35-36`：worldPos/fogMix 顶点级计算。

### 雾与大气
- `common/getFogMix.vsh:1-61`：解析高度雾——沿视线积分指数密度 `(1-exp(-len*t))/t`，含相机高度因子 `exp(-(cameraY-64)*b)`、昼夜/雨强度调制；由各 gbuffers 的 vsh 调用，结果以 `fogMix` varying 插值（逐顶点）。
- `common/getFogMix.vsh:16-22`：skybasic 直接 0（天空由自身梯度处理）、clouds 用远距离特判。
- `program/gbuffers_skybasic.fsh:26-53`：解析天顶/中天/地平线三段渐变 + 星星标记；地平线用有理衰减 `fogify(x,w)=w/(x²+w)`（`common/math.glsl:29-31`）。
- `program/gbuffers_skybasic.vsh:28-32`：星星颜色在顶点用位置 hash 生成。
- `world1/gbuffers_skytextured.fsh:22-31`：末地星野用方向角切片 hash + `exp(fract(...)*-drag)` 程序化生成，零贴图。
- `program/final.fsh:200-218`：水下正弦焦散直接加色（2 组 sin×sin）。
- FOG_ENHANCEMENT 金色调雾在三个程序重复（`gbuffers_textured_lit.fsh:86-91`、`gbuffers_water.fsh:93-98`、`gbuffers_skybasic.fsh:43-48`）。

### 水与水下
- `program/gbuffers_water.fsh:50-63`：用 depthtex1（不透明背景）与水面深度差做吸收 `1-exp(-depthDiff*0.15)`。
- `program/gbuffers_water.fsh:68-82`：水色按视距混色、`contrast(albedo,3.2*waterTexStrength)`；`:81-82` 用 `min()` 把水高光/透明度压进贴图 ba 通道。
- `program/gbuffers_water.fsh:105-128`：REALISTIC_WAVES 档每像素 3 次 noisetex 采样重建 TBN 法线。
- `program/gbuffers_water.fsh:130-156`：解析太阳高光（smoothstep 核 + exp 辉光）+ Fresnel 混向雾色。
- `program/gbuffers_water.vsh:57-67`：每方块随机数在顶点生成（水纹理强度/波形相位）；`common/getWaterWave.vsh:1-3` 为空函数（死档）。
- `common/getReflectionColor.fsh:14-51`：SSR 16 主步、步长按 RAY_MULT=2 指数增长；近距命中回退并以 REFINEMENT_MULT=0.1 收缩细化（≤4 次）；出屏 break；拒绝命中被标记的透明像素（colortex7.x>0.99）。
- `common/getReflectionColor.fsh:6-12`：反射颜色按屏幕位置加权（边缘渐隐，`1-exp2(-72.13*u*(1-u)*v²)`）。
- `program/final.fsh:178-197`：反射仅对 colortex7.x>0.99（水/冰）像素执行，Fresnel 混合。

### 粒子·实体·天气
- `program/gbuffers_weather.fsh:11-21`：雨条仅做透明度乘子（RAIN_INTENSITY）与去饱和色调，不参与光照/雾。
- `program/gbuffers_basic.fsh:12-60`：轮廓模式（HSV 彩虹/脉冲）gimmick，占 5 个 OUTLINE_MODE 分支。
- 实体影：见调度节 `SHADOW_ENTITY`；`program/shadow.vsh:13-15` 顶点级剔除。

### 后处理与缓冲内存
- `program/composite.fsh:20-32`：TAA 历史拒绝用 3×3 均值±标准差裁剪（非 min/max AABB）。
- `program/composite.fsh:53-83`：`taaActive` 门（depth>0.56 且重投影 UV 在屏内）；静态混合 0.99，差异大时降至 0.66。
- `program/composite.fsh:86-113`：运动模糊：4 次重投影速度采样 + 边界检查，仅 depth>0.56。
- `program/final.fsh:36-160`：FXAA（12 步 quality 数组、两端 reach 后 break、无边缘直接返回）。
- `program/final.fsh:220-254`：屏幕空间光柱：从太阳 UV 向像素 20 步、只累计 depth>0.999 的天空像素亮度、IGN 抖动（TAA 开启时按帧时间偏移）、出屏 break、衰减 0.96。
- `program/final.fsh:269-285`：单 pass 9-tap 十字 Bloom（三次方加权），全分辨率、无阈值/无 mip。
- `program/final.fsh:287-294`：`x/(x³+1)^(1/3)` 色调映射 + gamma1.1 + 1/255 三角 dither。
- 缓冲：colortex3 历史单缓冲原地读写（`composite.fsh:115-123`，`colortex3Clear=false`）；无 ping-pong、无缩减。

## 四、反面印证（不值得学的做法）

1. **无阶段熔断、关闭不缩编**：TAA/MOTION_BLUR/REFLECTIONS=0 只让代码消失，composite/final 全屏 pass 照跑，且 TAA 关闭时仍每帧写全屏历史 colortex3（`program/composite.fsh:115-123`）。Astra 已有 32 处 `program.*.enabled` + size.buffer 分档，不应退化。
2. **CLOUD_STYLE=1 每像素 3×fbm(4 阶)**（`gbuffers_clouds.fsh:41-52,72-75`）：12 次噪声/像素且无距离、密度、透射早退，比 Astra 平面云贵且无预算保护。
3. **逐顶点雾插值**（`common/getFogMix.vsh` 由 vsh 调用，`fogMix` varying）：小地形面可行，但水/云/天空大三角上雾梯度插值失真；Astra 逐像素高度雾 + 天气耦合不应为此降级。
4. **final 单 pass 内联后处理链**（FXAA→焦散→光柱→Bloom→tonemap→dither）：SUMMARY-batch3 §2.4 已判「单 pass 合并不学」（YoFPS），Astra 维持分阶段 + 熔断。
5. **阴影滤波旋转核**：SMOOTH_SHADOWS 开工即每像素 R2 盘 + 随机旋转（`getSunStrength.fsh:35-59`），Astra 已显式拒绝旋转核（SUMMARY-batch3 §3.1 去重排除），且该包无时域去噪，采样不足时噪点直接上屏。
6. **工程卫生**：`final.fsh:9-12` 声明 colortex2/colortex3 未使用；`shader.h:77` `REACT_ON_WATER` 死宏；`common/getWaterWave.vsh` 空函数；`shaders.properties.backup` 重复文件随包分发。

## 五、新颖借鉴点（A/B/C）

- A（低代价可直接排期）：**无**。
- B（中代价需接线）：**无**。
- C（大工程战略项）：**无**。

结论：本包全部性能手法均已被五份材料列为已知方向（去重排除见下表），或 Astra 已有等价/更强实现；无「Astra 未实现且未列」的新颖点。

### 去重排除明细（机制 | 包内出处 | 排除依据）

| 机制 | 包内出处 | 排除依据 |
|---|---|---|
| 像素锁定阴影（世界网格量化查询点） | `common/getSunStrength.fsh:4-15` | SUMMARY-batch3.md:89,262-264 已列（simply-upscaled「像素锁定阴影」B 组）。Astra grep `PIXEL_LOCK|pixel_lock|SHADOW_PIXEL|snap|quantiz`（*.glsl/*.fsh/*.vsh/*.csh/*.properties）无功能命中——仅注释与编码模块（`lib/encoding.glsl:47` 八面体量化、`lib/uniforms.glsl:49` 云影锚点注释） |
| 黄金角/R2 盘采样 + 旋转核 | `common/getSunStrength.fsh:35-59` | SUMMARY-batch3.md:72 已列（soft-voxels R2，A 组）；旋转核 Astra 显式拒绝（SUMMARY-batch3 §3.1）；Astra grep `GOLDEN|golden|spiral|R2_SEQ` 仅 `program/nether_reflection.fsh:49-56` 相位用途，非阴影滤波 |
| 深度差调幅软边（零额外采样） | `common/getSunStrength.fsh:47,61-63` | Astra 已有四角 gather 双线性 + lobe 分档 + coverage 早退（`global/lighting/shadowmap.glsl:138-145`、`global/lighting/diffuse.glsl:270-287`） |
| 背光/超距阴影早退 | `common/getSunStrength.fsh:17-20` | Astra 同机制：`global/lighting/diffuse.glsl:333-345` 面向早退注释与逻辑 |
| 阴影投射顶点级剔除（实体/火焰） | `program/shadow.vsh:13-15,21-26` | SUMMARY-batch3.md:68 已列（i-like-vanilla/arc，A 组） |
| 运动模糊（速度重投影 4-tap） | `program/composite.fsh:86-113` | SUMMARY-batch2.md:98 已列（clarity/bvs/tea/pyvtron，中期）。Astra grep `MOTION_BLUR|motionBlur|motion_blur` 0 命中（未实现但已列，不重复计新颖） |
| TAA 方差钳制/自适应混合/天空与出屏门 | `program/composite.fsh:20-32,53-83` | Astra TAA 已有 YCoCg 邻域钳制、反应遮罩、天空处理（`program/taa_resolve.fsh:32-55,98-102`），更强 |
| FXAA 3.11 次数数组与提前退出 | `program/final.fsh:36-160` | Astra 已有 `global/post/fxaa.glsl` |
| 深度门控天空亮度光柱 | `program/final.fsh:220-254` | Astra 光柱已为 8 采样深度行进 + Bayer 抖动（`global/post/godrays.glsl:63-87`）；batch1 MakeUp「depth-only godrays」已列 |
| 单 pass 9-tap Bloom | `program/final.fsh:269-285` | Astra 已是 0.25 捕获 + mip 链 + tap 分档（`global/post/bloom.glsl:1-40`），更省更优 |
| 水面解析太阳高光（core+glow） | `program/gbuffers_water.fsh:130-156` | SUMMARY.md ②-7 FastPBR 行已建立 Astra「水面太阳高光链路」 |
| 片段 3 次噪声波法线 | `program/gbuffers_water.fsh:105-128` | SUMMARY-batch2 ②-2「解析/免纹理波场」4 包已列；Astra 有 solas 波场（`lib/solas_water.glsl`） |
| SSR 指数步进 + 回退细化 + 出屏退出 + 透明体拒绝 | `common/getReflectionColor.fsh:14-51` | Astra 已有 stride×1.6 递增 + 二分细化 + 出屏退出 + 同纹素缓存（`global/water/raytrace.glsl:60-127`）；batch1 「SSR 行进效率细节」已列 |
| SSR 屏边置信度渐隐 | `common/getReflectionColor.fsh:6-12` | Astra 等价：`global/water/raytrace.glsl:135` `confidence *= smoothstep(0.0,0.03,edge)` |
| 水吸收按深度差 | `program/gbuffers_water.fsh:56-63` | Astra Beer-Lambert 距离吸收（`global/water/absorption.glsl:8-12`），任务背景已列「水下吸收按距离」 |
| 解析高度雾 | `common/getFogMix.vsh:38-46` | SUMMARY-batch2.md:68（glimmer 解析高度雾）已列；Astra `global/atmosphere/fog.glsl` |
| 顶点级风/光照下移 | `program/gbuffers_textured_lit.vsh:64-101` | SUMMARY-batch3.md:127 §2.5 #1「顶点级平替」已列；Astra 风距离 LOD（`global/lighting/wind.glsl`，batch3 已实现） |
| 矿石自发光启发式 | `program/gbuffers_textured_lit.fsh:51-56` | SUMMARY.md ②-1「IPBR 自发光启发式」已列 |
| 方块光曲线 x√x + x³ | `common/getTorchStrength.vsh:2-4` | SUMMARY.md ②-1「方块光衰减曲线」已列 |
| shadowEntities/shadowPlayer/clear 开关 | `shaders.properties:31-41,49-54` | Astra 已有完整同名开关（`shaders.properties:243-249,282-284`）与多处 `colortexClear=false`（如 `program/taa_resolve.fsh:18`） |
| 4 档 profile | `shaders.properties:1-4` | 已列（Kappa/Miniature profile 定义） |
| 光柱/Bloom 等分项编译开关 | `shader.h:4-95` | 编译期开关属已知；Astra 的差异是追加程序级熔断，非新颖 |

## 六、无法判定项

1. `SMOOTH_SHADOWS` 逐像素固定旋转（非帧抖动）在 8/16 采样下的实际噪点水平及其与 FXAA/TAA 的交互，源码无法判定，需实机 A/B（方向已按材料排除，仅记录）。
2. `common/getFogMix.vsh:38-46` 顶点插值的净收益与几何尺寸强相关（本文列为反面），若仅用于 1×1 地形面可能无可见代价——需实机对照。
3. `getFogMix.vsh:16-22` 的 1.17+ 原生雾覆盖语义（`fogEnd<far` 等）与 Iris 行为是否一致未实测。
4. `SHADOW_PIXEL`（1/16 格量化）与 FXAA 的组合在低阴影分辨率下的量化边界观感未实测。
