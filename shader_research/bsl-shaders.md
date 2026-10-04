# BSL Shaders 10.1.8 研究报告（面向 Astra 的可借鉴点）

> 调查对象：`reference_shaderpacks/bsl-shaders/`（下文 BSL 引用均相对其 `shaders/` 目录）。
> 对照工程：`Astra/shaders/`。撰写日期：2026-10-02。本报告只读参考包源码，未修改任何源文件。

## ① 包概览

- **版本**：BSL v10.1（`lang/en_US.lang:88`："BSL v10.1.8"；`lib/settings.glsl:2` 头注释 "BSL Shaders v10 Series"）。
- **作者**：Capt Tatsu（`lib/settings.glsl:2-3`，capttatsu.com）。
- **许可证**：**保留所有权利（All Rights Reserved）**。包内没有任何 LICENSE/README 授权文件（find 全包仅 `shaders/` 一个目录），仅版权头署名。BSL 官方条款禁止未经许可的改编与再分发——对 Astra 意味着：**只能借鉴思路、公式概念与参数化方向，逐字抄代码、照搬选项命名、或 fork 本体再分发都在禁区**（详见⑤）。
- **平台与规模**：Iris/OptiFine 双兼容（`lib/atmospherics/sky.glsl:69` 的 `IS_IRIS` 分支），274 个着色器文件；`program/` 存共享源（最大 `program/gbuffers_water.glsl` 907 行），`world0/world-1/world1` 全部是 13 行 include 包装器，三维度共用同一套 `program/` 源。
- **风格定位**：经典"明亮清爽、泛用型"路线，特点是**极度发达的玩家可调选项**（`shaders.properties:21-96` 约 20 个设置屏、`sliders` 一行 200+ 参数），色彩上以手调的三带天空色（白天/夜晚/天气）+ 强 Desaturation 阴影去饱和（`lib/lighting/forwardLighting.glsl:134-165`）营造"干净通透"观感。技术上是**较单体式 + 屏幕空间为主**的前向光影：无真体积光，体素彩光是可选实验特性。

## ② 架构与特性清单

### 大气 / 云
- 经验型三带天空色混合（昼 `skyCol`、夜 `lightNight`、雨 `weatherCol` 按 VoU 梯度混合）：`lib/atmospherics/sky.glsl:44-60`。
- 太阳周侧亮带（sunMix/horizonMix 双因子把日光色揉进地平线，天空与雾共用同一公式）：`lib/atmospherics/sky.glsl:36-41`、`lib/atmospherics/fog.glsl:32-38`。
- 洞口/地底天空衰减（相机深度 + 眼睛亮度 eBS 双门控）：`lib/atmospherics/sky.glsl:64-67`。
- 层次雾：距离雾 + 每日时段/天气/室内密度乘子 + 高度雾（`fog *= exp2(-max(worldPos.y - FOG_HEIGHT_Y,0)/exp2(FOG_HEIGHT_FALLOFF))`）：`lib/atmospherics/fog.glsl:106-115`；沙漠/冷群系经平滑群系 uniform 调雾密度：`shaders.properties:172-186`。
- 云双模式：①天空盒多层平面采样 `DrawCloudSkybox`（`lib/atmospherics/clouds.glsl:181`）②上/下板层间射线步进 `DrawCloudVolumetric`（`lib/atmospherics/clouds.glsl:302`，样本数 ≤32/64，`clouds.glsl:320-324`）；三种基准噪声可选 Perlin/Worley/Blocky：`clouds.glsl:3-38`；云缝透光 `CLOUD_REVEAL` sunCoverage：`clouds.glsl:204-209`。
- 星空（三重哈希噪声相乘取稀疏点）：`clouds.glsl:484-521`；极光（2D 噪声多层采样 + 高度色带）：`clouds.glsl:535-600`。
- 太阳/月亮自绘：`lib/atmospherics/sunmoon.glsl`；体积光（radial blur 型 god rays，含末地闪电路径）：`lib/atmospherics/lightShafts.glsl:30-32`。

### 水体
- 噪声双尺度水面法线（低频+高频按 `WATER_DETAIL` 混合）：`program/gbuffers_water.glsl:140-155`。
- 视差波浪：4 次迭代沿视线偏移采样高度场：`gbuffers_water.glsl:158-166`；4-tap 高度差分重建法线：`gbuffers_water.glsl:168-194`。
- 顶点波动动画（双正弦叠加）：`gbuffers_water.glsl:798-814`。
- 水雾/吸收（指数雾 + 昼夜色 tint，跨介质条件混合）：`lib/atmospherics/waterFog.glsl:5-31`，应用点 `gbuffers_water.glsl:692-705`。
- SSR：`lib/reflections/raytrace.glsl:31`（粗 reflections 另有 `lib/reflections/roughReflections.glsl`，调用点 `program/deferred1.glsl:370`）。
- "焦散"：无解析焦散，靠 `WATER_CAUSTICS` 把彩色阴影的 shadowcolor 采样 ×4/×16 放大近似水下亮斑：`lib/lighting/shadows.glsl:91-93`、`lib/atmospherics/lightShafts.glsl:90-92`。

### 阴影与光照
- 透视畸变阴影（xy 除以 distortFactor、z×0.2）：`lib/lighting/shadows.glsl:65-71`。
- 9-tap 十字滤波彩色阴影（shadowtex0/1 + shadowcolor0）：`shadows.glsl:17-27, 103-133`。
- NoL 相关动态偏置 + 距离偏置：`shadows.glsl:187-196`；`SHADOW_PIXEL` 世界坐标量化降噪：`shadows.glsl:136-139`。
- SSS：屏幕空间 12-tap 旋转盘状向内偏移采样：`shadows.glsl:225-268`（轻量 SSS 用阴影内插值近似：`shadows.glsl:97`）。
- 云影：沿太阳方向把世界点投影到云层平面，采样与云同款噪声：`lib/lighting/shadows.glsl:295-375`。
- 动态手持光：把手持方块光值按 log2/exp2 叠进 `lightmap.x`（保持光域量化曲线连续）：
  ```glsl
  float handlight = min((heldLightValue - 2.0 * length(heldLightPos)) / 15.0, 0.9333);
  lightmap.x = log2(exp2(lightmap.x * 32.0) + exp2(handlight * 32.0)) / 32.0;
  ```
  （`lib/lighting/dynamicHandlight.glsl:9-10`）；手部本体取 max：`dynamicHandlight.glsl:15-22`。
- 体素彩光 MCBL（Iris 专属，可选）：`image3D` 双缓冲 lighttex0/1 ping-pong（`shaders.properties:233-274`），compute 六邻域平均扩散（`program/shadowcomp.glsl:61-73`），发射色与染色由方块 ID 查表（`lib/lighting/voxelColorFetch.glsl:8,17` 的 GetEmission/GetTint，色表 `lib/color/blocklightColor.glsl:5` 共 50 色），相机位移补偿 `prevPos`：
  ```glsl
  ivec3 prevPos = pos + ivec3(floor(cameraPosition) - floor(previousCameraPosition));
  ```
  （`shadowcomp.glsl:108`）；屏幕空间退避 `MCBL_SS`（`lib/lighting/coloredBlocklight.glsl:115-132`），手持光源颜色注入 `lightColorsRGB`：`coloredBlocklight.glsl:1-21`。
- AO：两种屏幕空间法（method0 法线重建 GTAO 风格 / method1 深度差 GGD）：`lib/lighting/ambientOcclusion.glsl:51, 80-134`。
- 无阴影时的天空光回退曲线（按 skylight smoothstep 软关断，保证关阴影选项后画面不塌）：`lib/lighting/shadows.glsl:279-288`。
- 阴影去饱和 Desaturation（暗部向夜/雨色偏移）：`lib/lighting/forwardLighting.glsl:134-165`。

### 后处理
- Bloom：composite4 七级降采样 `BloomTile`（`program/composite4.glsl:31-62`），composite5 合成 `Bloom`（`program/composite5.glsl:109-121`）。
- 自动曝光（时域插值收敛 `exposureBlendFactor`）：`composite5.glsl:156-163, 372`；颜色分级（RGB 三通道 + 亮度 tint）：`composite5.glsl:165-172`；BSL Tonemap（去饱和矩阵 + 白点曲线 + 双段 gamma）：`composite5.glsl:233-260`。
- TAA：Catmull-Rom 历史采样（`lib/antialiasing/taa.glsl:64-88`）+ YCoCg AABB 邻域裁剪（`taa.glsl:118-134`）；FXAA（`lib/antialiasing/fxaa.glsl`）；镜头光晕 BaseLens/RingLens：`lib/post/lensFlare.glsl:3-27`；运动模糊/DoF/脏镜头在 composite2/3。
- 管线编排：deferred=AO、composite1=体积光、2=动模糊、3=DoF、4/5=bloom+调色、6=FXAA、7=TAA，全部按选项条件启停：`shaders.properties:101-125`。

### 维度特化
- 下界五群系颜色（Nether/Valley/Crimson/Warped/Basalt 五套可调色 + 平滑群系 uniform 混合）：`lib/color/netherColor.glsl:5-9`，uniform 定义 `shaders.properties:183-186`；下界雾密度独立：`lib/atmospherics/fog.glsl:162-182`。
- 末地：独立光照常数（`lib/lighting/forwardLighting.glsl:85-90`）、末影龙闪电脑间点光源 `endFlashIntensity`（`forwardLighting.glsl:88`、`lib/atmospherics/lightShafts.glsl:30-32`）。
- 雷电实体：`entityId==10101` 直接改写闪电体 albedo 泛白（仅实体自发光，无对地动态点光）：`program/gbuffers_entities.glsl:184-196`。

### 性能与时域
- 五档画质 Profile（MINIMUM→ULTRA）：`shaders.properties:4-8`。
- 程序按选项条件启停（省 pass）：`shaders.properties:101-125`。
- properties 层自定义 uniform：平滑日时间 `timeAngle`、日落阴影淡出 `shadowFade`：`shaders.properties:145-159`；`smooth()` 平滑群系过渡 uniform：`shaders.properties:168-186`。
- 全部射线步进（云/体积光/SSR）共用 TAA 抖动黄金序列重排 dither：如 `clouds.glsl:185-191`、`ambientOcclusion.glsl:62-68`；TAA 抖动在顶点级注入：`program/gbuffers_water.glsl:903-905`。
- 水洼材质响应（孔隙度单参数驱动三项输出）：
  ```glsl
  float puddleSmoothness = sqrt(1.0 - 0.75 * porosity);
  float puddleDarkening = (0.5 * porosity + 0.15);
  smoothness = mix(smoothness, 1.0, puddles * puddleSmoothness);
  f0 = max(f0, puddles * 0.02);
  albedo.rgb *= 1.0 - (puddles * puddleDarkening);
  ```
  （`lib/reflections/rainPuddles.glsl:78-86`）
- Distant Horizons / Voxy LOD 支持散布各处（如 `lib/atmospherics/fog.glsl:97-99, 132-140`；`shaders.properties:279-284`）。

## ③ Astra 可借鉴点

> 每条：技术描述 / 包内出处 / 对应 Astra 模块 / 迁移难点。均为**思路借鉴**，实现须重写（见⑤）。

1. **雨湿水洼掩码（puddle mask）+ 孔隙度材质响应**（回应专项 a）
   - 描述：BSL 用"噪声叠加平滑高度图"生成水洼 mask，并四重门控：wetness 阈值、天空光暴露（`skylight*32-31`）、朝上法线 NoU、群系排除（冷/沙漠/恶地/稀树草原不积水）；材质端由**孔隙度 porosity** 单参数推导三项：光滑度提升（`sqrt(1-0.75*porosity)`）、F0 提升到 0.02、反照率变暗（`0.5*porosity+0.15`）。
   - 出处：`lib/reflections/rainPuddles.glsl:1-23`（mask 与门控）、`rainPuddles.glsl:78-86`（材质响应）。
   - Astra 模块：`Astra/shaders/lib/wet_material.glsl`（现有三类 wet class 暗化/高光响应）、`Astra/shaders/global/lighting/diffuse.glsl:380`（湿态降阴影权重）。
   - 迁移难点：**低-中**。Astra 已有 wet class 与暗化/高光三参数，缺的是"水洼空间掩码"这一层（噪声采样 + 天空光/朝上/群系门控）与 porosity→F0 通道；需在 gbuffers 材质阶段拿得到 noisetex 与 skylight，Astra 前向管线即可满足。

2. **雨滴涟漪动态法线**
   - 描述：水洼处叠加周期性"扩散圆环"涟漪：网格随机种子 + 时间相位生成环心，两次反向流动噪声作底，4-tap 有限差分重建法线，法线强度随掠射角 fresnel 衰减。
   - 出处：`lib/reflections/rainPuddles.glsl:33-55`（GetRipple 环形波）、`rainPuddles.glsl:57-76`（4-tap 差分法线 + fresnel 衰减）。
   - Astra 模块：`Astra/shaders/lib/wet_material.glsl`（可加 `astra_wet_ripple_normal()`）→ 汇入 `Astra/shaders/lib/solas_water.glsl` 同款 TBN 差分管线。
   - 迁移难点：**低**。纯逐像素数学，无新依赖；只需与借鉴点 1 的 mask 相乘。注意每像素 5 次 noisetex 采样 ×4 tap 的开销，可按距屏幕空间距离 LOD。

3. **云影与云密度严格同源**
   - 描述：地面云影不另起炉灶，而是把世界点沿太阳向量平移到云层高度，采样与绘制云**完全相同**的噪声函数（含 wind 偏移、CLOUD_DENSITY、CLOUD_REVEAL 太阳亮斑口径），保证"看到什么云、影子就是什么形状"。
   - 出处：`lib/lighting/shadows.glsl:295-375`（GetCloudShadow，噪声分支与 `clouds.glsl:3-38` 一一对应）。
   - Astra 模块：`Astra/shaders/program/cloud_shadow_cache.fsh` 与 `Astra/shaders/global/atmosphere/clouds_planar.glsl`（Astra 已有云影缓存，但两处密度场是否同源未核实）。
   - 迁移难点：**低-中**。思路层面零成本；工程上是把 clouds_planar 的密度函数抽成共享 include 供 cache 与绘制两侧调用，属重构而非新功能。难点在 Astra 云有独立时域历史，云影 cache 的对齐需考虑历史帧云的漂移。

4. **洞口亮度 / 室内外照度贯穿**（回应专项 c 的一半）
   - 描述：BSL 用一个 eBS（eyeBrightnessSmooth）+ 相机绝对深度的双门控，把"进洞"这个状态同时打进三处：天空色向最低光照色衰减（`sky.glsl:64-67`）、雾向室内密度切换（`fog.glsl:57-62, 101-107`）、云透明度衰减（`clouds.glsl:279-281`）；uniform 在 properties 层平滑过渡。
   - 出处：`lib/atmospherics/sky.glsl:64-67`、`lib/atmospherics/fog.glsl:58-62, 101-107`、`shaders.properties:162-163`（blindFactor 平滑）。
   - Astra 模块：`Astra/shaders/global/atmosphere/sky_gradient.glsl`、`Astra/shaders/global/dimension/overworld.glsl`（Astra 是否已有同款室内外贯穿未核实，故只列借鉴方向）。
   - 迁移难点：**低**。Astra 前向架构下 eBS 可直接读；主要是把散落各模块的 eyeBrightness 判断收拢成一个共享因子。

5. **手持光按光域曲线叠加**（回应专项 c）
   - 描述：BSL 不把手持光当独立点光源，而是折算成虚拟 blocklight 值，用 `log2(exp2(lm*32)+exp2(hl*32))/32` 在光域上做"物理叠加"（两盏光叠一起不会超 1），保持后续所有 blocklight 曲线（pow10 等）行为一致；另给手部本体单独 `max` 路径。
   - 出处：`lib/lighting/dynamicHandlight.glsl:9-10`（光域 softmax 叠加）、`dynamicHandlight.glsl:15-22`（手部路径）。
   - Astra 模块：`Astra/shaders/global/lighting/diffuse.glsl:389, 448-454`（`held_light_strength`，CPU 侧 `pow(heldBlockLightValue/15,4)` 基线 + 抑制项）。
   - 迁移难点：**低**。Astra 已有 held light 通路，只需比较两种叠加律（Astra 现状为独立项求和还是 max 未核实）；softmax 公式 3 行可独立重写。**注意**：Astra 的闪电点光（`diffuse.glsl:456-458` `lightning_point_light`）比 BSL 的"只把闪电实体改白"（`program/gbuffers_entities.glsl:184-196`）先进，此方向无需借鉴。

6. **体素彩光的屏幕空间退避 + 手持光源染色**（回应专项 c）
   - 描述：BSL 在体素范围外/低配下，退避到"上一帧屏幕空间彩光重投影 + 上采样"（MCBL_SS），两路按体素边界软混合；手持火把等通过 heldItemId 查 `lightColorsRGB` 表把光源颜色注入体素场。
   - 出处：`lib/lighting/coloredBlocklight.glsl:115-132`（屏幕空间退避）、`coloredBlocklight.glsl:1-21`（手持光颜色）、`coloredBlocklight.glsl:50-78`（三线性手写插值防闪烁）。
   - Astra 模块：`Astra/shaders/program/nether_light.csh`（Astra 九段 compute 体素彩光，仅下界）、`Astra/shaders/global/dimension/nether_colored_light.glsl:13-26`。
   - 迁移难点：**中**。屏幕空间退避需要额外的历史缓冲与重投影（Astra 的 `lib/effect_history.glsl` 基建可复用）；手持光染色只需在 emission 写入端查物品 ID 表。若 Astra 主世界不扩体素彩光，则仅手持光颜色部分值得移植。

7. **BSL Tonemap 的"去饱和→tonemap→再饱和"三段式**
   - 描述：tonemap 前先施加固定去饱和矩阵，映射后再乘其逆矩阵，保证高亮压缩不失色偏；白点曲线 `color/(pow(color,w)+1)^(1/w)` 与按亮度的双段 gamma 都做成玩家可调滑条。
   - 出处：`program/composite5.glsl:233-260`。
   - Astra 模块：`Astra/shaders/lib/tonemap.glsl`、`Astra/shaders/global/post/grading.glsl`。
   - 迁移难点：**低**。纯后处理数学；但 Astra 已有自己的 grading/tonemap 体系，是否引入取决于美术取向而非技术缺口（需统帅决策，见备注）。

## ④ Astra 已有对应实现（对照与优劣）

> Astra 行为描述仅基于本次实际阅读的文件；未读到的内部实现标注"不确定"。

| 能力 | BSL 出处 | Astra 对照 | 两边优劣 |
|---|---|---|---|
| 天空模型 | `lib/atmospherics/sky.glsl:2-80` 手调三带经验混合 | `Astra/shaders/global/atmosphere/sky_gradient.glsl`（Complementary r5.9 三向模型移植，文件头有逐行出处记录） | Astra 优：模型结构化、方向性天光 SH9 可共用；BSL 优：曝光/去饱和等玩家参数面极宽。风格取舍，无绝对优劣 |
| 平面云 | `clouds.glsl:181, 302` 双模式，≤32/64 样本，无时域 | `Astra/shaders/global/atmosphere/clouds_planar.glsl`（Complementary 形状模型 + 半分辨率独立时域历史） | Astra 优：时域历史降噪、形状（圆顶暗底）；BSL 优：三种基准噪声可选、云影同源采样（借鉴点 3） |
| 雨湿地面（专项 a） | `rainPuddles.glsl:1-23, 78-86`：噪声水洼 mask + porosity→光滑度/F0/暗化 + 群系排除 + 涟漪法线 | `Astra/shaders/lib/wet_material.glsl:6-27`：三类 wet class（木/土/石）各自"暗化+高光增益+高光指数"，文件头注明"idea only, original implementation" | BSL 优：有空间水洼掩码与孔隙度物理映射、涟漪动态法线；Astra 优：材质分类比 BSL 的单一 porosity 更细（BSL 的 porosity 来自材质纹理 alpha 通道约定，Astra 是方块 ID 分类——两边口径不同，各有取舍）。Astra 目前**未见**水洼掩码与涟漪（未在已读文件中发现，不确定是否有） |
| 手持光（专项 c） | `dynamicHandlight.glsl:2-22`：光域 softmax 叠加 + 手部 max | `Astra/shaders/global/lighting/diffuse.glsl:389, 448-454`（`held_light_strength`） | 两者参数化路径不同（BSL 动态距离衰减 vs Astra CPU pow4 + 抑制）；Astra 另有闪电点光，此项 Astra 更完整，仅叠加律可参考 |
| 体素彩光 | `program/shadowcomp.glsl:61-125`：双缓冲 ping-pong 六邻域扩散，跨帧时域积累（相机平移补偿），有屏幕空间退避与手持光染色 | `Astra/shaders/program/nether_light.csh`（shadowcomp+shadowcompA..H 九段，同帧扩散）+ `global/dimension/nether_colored_light.glsl`（Solas V3.7b 架构，bounded 同帧体，无时域历史） | Astra 优：同帧无残影、无跨帧拖尾伪影；BSL 优：时域积累把扩散成本摊到多帧（更省每帧算力）、跨帧光晕自然、有手持光源颜色与屏幕空间退避 |
| 水体 | `gbuffers_water.glsl:140-194, 692-705`：噪声法线+视差波+SSR+水雾 | `Astra/shaders/global/water/`（surface/raytrace/refraction/absorption/caustics/light_shafts/medium_state 全套） | Astra 明显更全（折射、吸收、解析焦散、水下光束 BSL 均无或仅为阴影色近似）；BSL 可取的仅视差波浪（借鉴价值低，Astra 法线体系已更细） |
| 焦散 | `shadows.glsl:91-93` shadowcolor ×4 放大近似 | `Astra/shaders/global/water/caustics.glsl` 解析焦散 | Astra 优（物理近似 vs 屏幕空间 hack）；无需借鉴 |
| 体积光 | `lightShafts.glsl` 屏幕空间径向模糊 | `Astra/shaders/global/water/light_shafts.glsl` + `shaft_history.glsl`（时域光束） | Astra 优；无需借鉴 |
| 后处理链 | `composite4/5/6/7.glsl` + `taa.glsl` | `Astra/shaders/global/post/`（bloom/exposure/grading/fxaa）+ `lib/taa_state.glsl, taa_reactive.glsl` | Astra 有响应式 TAA，细节内部未核实不评优劣；BSL 的 YCoCg AABB 裁剪（`taa.glsl:118-134`）是行业通用件，若 Astra 未含可低成本补 |
| 维度特化 | 下界五群系色 `netherColor.glsl:5-9` + 群系 uniform；末地闪光 `forwardLighting.glsl:85-90` | `Astra/shaders/global/dimension/nether.glsl`（五类群系雾）、`end*.glsl`（Kerr 黑洞天空体系） | 两边覆盖面相当，Astra 末地方向远超 BSL（BSL 末地仅静态色+闪光） |

**专项 d：大单体文件的组织教训（反向启示）**
BSL 的单体性体现在：① `program/gbuffers_water.glsl`（907 行）把顶点动画、材质解码、水面法线、反射、水雾全部内联，功能边界只能靠注释行找；② 太阳向量/公共变量在每个 gbuffers 顶点着色器里重复粘贴（如 `gbuffers_water.glsl:870-887` 的 sunVec 十行三角函数，同样代码存在于 terrain/block/entities/hand 等约 10 个文件）；③ 特性开关矩阵（`#if WATER_NORMALS` × `REFLECTION_MODE` × `MATERIAL_FORMAT`）内联在函数体里，改一处要跨多个 program 同步。对 Astra 的启示：Astra 的 `lib/` 模块化（settings/uniforms/transforms/colors 单一来源）正是正确方向，应继续守住——公共向量与坐标变换绝不复制进 program 层；同时 BSL 证明 `world0/` 13 行包装器 + 共享 `program/` 源是三维度共用代码的低成本方案，Astra 的 `world-1/shadowcomp*.csh` 步进包装（`world-1/shadowcompA.csh:3` 的 `#include "/program/nether_light.csh"` + `ASTRA_LIGHT_STEP` 宏）与 BSL 思路同源，方向一致。

## ⑤ 借鉴可行性（许可证层面）

- **结论：BSL Shaders 为"保留所有权利"（All Rights Reserved）授权，作者 Capt Tatsu。包内无任何授权文件或开源许可声明（全包 find 无 LICENSE/README），默认版权法保护**。因此：
  - **允许**：阅读、学习、借鉴技术思路、算法概念、参数化方向与管线结构；用自己的原创代码实现。
  - **禁止**：复制/转写 BSL 源码（含 GLSL 片段、常量表、选项值序列的逐字照搬）；禁止对 BSL 本体改编后再分发。
  - **灰区**：选项命名、设置屏文案、噪声纹理（`tex/noise.png` 有版权）也不应照搬。
- Astra 已有合规先例可循：`Astra/shaders/lib/wet_material.glsl:4`（"ITT 3.2 material-dependent wetness: idea only, original Astra implementation"）与 `clouds_planar.glsl` 文件头的"PROVENANCE / WHAT CHANGED / NOT PORTED"出处注释格式。**建议沿用该模式：每借鉴一处，在 Astra 模块头注明"idea from BSL vX.Y（文件名），original implementation"**。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **补齐雨湿水洼掩码 + 孔隙度材质响应**（借鉴点 1）：Astra 已有 wet class 骨架，补"噪声水洼 mask + 天空光/朝上/群系门控 + porosity→光滑度/F0"三件套即可把雨湿从"全场均匀湿"升级为"水洼+湿痕"，视觉提升大、实现量小（一个 lib 文件 + gbuffers 接线）。
2. **雨滴涟漪动态法线**（借鉴点 2）：依赖建议 1 的 mask，纯数学实现约 40 行，雨天地面质感提升显著。
3. **云影与云密度同源化**（借鉴点 3）：把 `clouds_planar.glsl` 密度函数抽为共享 include，供 `cloud_shadow_cache.fsh` 与云绘制两侧调用，消除"影子的云和天上的云不一致"类隐患，属低成本重构。
4. **手持光叠加律复核**（借鉴点 5）：对照 BSL 光域 softmax，确认 Astra `held_light_strength` 的叠加在多光源/强光源下不溢出不跳变，3 行公式级改动。
5. **洞口/室内照度贯穿**（借鉴点 4）：把 eBS+相机深度门控统一成一个共享因子，打进天空、雾、云三处，解决"进洞天空还亮"的观感问题；工作量略大（跨 3 个模块）但都是接线不是新算法。

> 未列入 Top5：体素彩光扩展到主世界（借鉴点 6）提升大但涉及 Iris image3D 全套基建与性能预算，超出小步迭代范畴；BSL Tonemap（借鉴点 7）属美术取向，需统帅拍板。
