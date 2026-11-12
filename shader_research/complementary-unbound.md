# Complementary Shaders - Unbound r5.9.3 研读报告（面向 Astra）

> 读法约定：无前缀的 `文件:行` 均指 `reference_shaderpacks/complementary-unbound/shaders/` 下的相对路径；
> Astra 侧以 `Astra/shaders/` 为前缀。Unbound 与 Reimagined 共用同一套文件骨架（两包 shaders 目录的
> glsl/csh/fsh 文件清单完全一致），差异全部由 `SHADER_STYLE`（1=Reimagined，4=Unbound）派生的
> 风格常量在编译期分叉，因此"Unbound 独有"即风格常量选中的代码路径 + 少数 Unbound 默认开启的开关。

## ① 包概览

- 版本：r5.9.3（依据工作区目录名与本任务给定；包内 `pack.json:2` 只有描述文字"Shaders with exceptional
  attention to detail..."，源码中未发现显式版本号字符串——此点存疑，已记入备注）。
- 作者：Complementary Development / EminGT（每个 program 文件头注释 "Complementary Shaders by EminGT"，如 `program/composite3.glsl:2`）。
- 许可证：Complementary License Agreement 1.7（`License.txt:1`），自定义条款：
  - 普通使用（游玩/内容创作）自由（`License.txt` §1.1）；
  - **修改代码、再分发（部分）本身不属于 Normal Usage**（`License.txt:9-13`，§0.2）；
  - 唯一合法的"改编再发布"通道是 §1.3（`License.txt:58-80`）：署名并链接官网、原样保留该许可证文件、
    名称不得含 "Complementary" 且与原名至少 3 个字母符差异（§1.3.c，`License.txt:70-72`）、
    在白天主世界等多个常见场景下视觉必须明显不同（§1.3.d，`License.txt:74-75`）、
    不得附加其它许可证（§1.3.e）、必须有显著量的人类-written 新代码且对画面有可感知贡献（§1.3.f，`License.txt:80`）；
  - 兜底条款：未被 Grants 明确覆盖的任何用法一律 "All Rights Reserved"（`License.txt:86-88`，§2.1）。
- 风格定位：Unbound 是 Complementary 的"风格化/艳丽"分支（SHADER_STYLE 4，`lib/common.glsl:14`），
  与写实向的 Reimagined（SHADER_STYLE 1）同源不同调：默认太阳路径角 -40°（`lib/common.glsl:464`），
  水/云/日月/极光/彩虹全部走风格化编号（`lib/common.glsl:417-423`：WATER_STYLE 3、CLOUD_STYLE 3、
  SUN_MOON_STYLE 2、AURORA_STYLE 2、RAINBOW_STYLE 4）。管线为前向 gbuffer + deferred 光照 +
  7 级 composite 链 + final，支持 Iris 特性（custom images、SSBO）与 DH/Voxy。

## ② 架构与特性清单

### 大气 / 云
- 解析天空渐变：上/中/下三色带混合 + 落日色带 + "天空地面"假散射，全部为 VdotU/VdotS 幂函数（`lib/atmospherics/sky.glsl:24-46`）。
- 日月 glare：`glare = visfactor/(1-(1-visfactor)*VdotSM4) - visfactor` 的 Mie 风格亮斑，随雨/水下调色（`lib/atmospherics/sky.glsl:58-88`）。
- Unbound 体云：上/下双约束平面间的射线步进，步长按 `planeDistanceDif/stepMult` 自适应（`lib/atmospherics/clouds/unboundClouds.glsl:92-123`）；
  3D 噪声 FBM + 高度阈值塑形（`unboundClouds.glsl:60-86`），着色为"高度梯度 + 银边项 VdotSM1-4"，
  不做光传输 marching（`unboundClouds.glsl:172-175`）；透明度按距离因子幂次累积（`unboundClouds.glsl:189-190`）。
  风格开关派生自 `CLOUD_STYLE == 3`（`lib/common.glsl:581-586`），入口 `mainClouds.glsl:44-46`，在 deferred1 全分辨率执行（`program/deferred1.glsl:187-188`）。
- 主世界雾链：洞穴雾/大气雾/边界雾按序叠加，另有失明（blindness）与黑暗（darkness）效果雾（`lib/atmospherics/fog/mainFog.glsl:242-277`）。

### 水体
- 多尺度波法线：取自 `gaux4` 噪声纹理的 med/small/big 三层采样，外加 4 次迭代视差偏移（`lib/materials/specificMaterials/translucents/water.glsl:86-100`）；
  法线幅度受天光调制（`water.glsl:103`）。
- 深度消波（alpha 随水深指数收敛）：`waterFog = 1 - exp(lViewPosDifM*0.075)`（`water.glsl:193-194`）。
- 岸线泡沫：以水底深度差 yPosDif 驱动，叠加噪声阈值与水位带（`water.glsl:211-248`）。
- 水面高光：单独构造 lightNormal（波导数）求 highlightMult，并按 mip 级别混合衰减（`water.glsl:283-300`）。
- 折射：screen-space 噪声偏移 + 两次"材质掩码/深度差"校验防越界（`lib/materials/materialMethods/refraction.glsl:5-43`）。
- SSR：屏幕空间线性 30 步 + 6 步二分细化（WSR 模式 38+10）（`lib/materials/materialMethods/reflections.glsl:84-88`）。
- 焦散：在 shadow program 内写入 shadowcolor，风格 3 用波噪声的有限差分梯度生成（`program/shadow.glsl:114-140`）。
- 水下雾：距离雾以 48m 平方曲线（高质量时）或 32m 线性，`1 - exp(-fog)`（`lib/atmospherics/fog/waterFog.glsl:10-17`）。

### 阴影与光照
- 彩色阴影/彩色光轴：shadowtex1 半透光时采样 `shadowcolor1` 得彩色透射（`lib/atmospherics/volumetricLight/volumetricLight.glsl:209-216`）。
- 体积光近远双段采样：近场密集 + 远场稀疏，幂分布布点；水下把 maxDistance 压到 128m（`volumetricLight.glsl:104-127`）。
- 洪泛彩光（可选，Iris custom images）：3D 体素洪泛 + 彩光雾 raymarch，y 轴按体积高度压缩重距离（`lib/atmospherics/fog/coloredLightFog.glsl:1-52`）。
- 方块光着色：各光源（火把/熔岩/传送门/红石/魂火等）给特殊色与传播权重（`lib/colors/blocklightColors.glsl:11-27,30-50`）；
  发射体与方块光互喂的 AddSpecialLightDetail（`blocklightColors.glsl:1-7`）；发射强度随日光衰减（`lib/lighting/mainLighting.glsl:360`）。

### 后处理（重点风格化）
- 泛光：composite4 从 colortex0 的 mip 链按 7x7 二项式核把 7 个 lod 的 tile 下采样进 colortex3 图集，
  存储为 `pow(bloom/128.0, 0.25)`（`program/composite4.glsl:36-58`，图集写入 `composite4.glsl:181`）；
  composite5 读回时四次方还原（`bloom^4`），等于把混合放到 1/4 gamma 空间做"无阈值软截断"（`program/composite5.glsl:111-116`），
  合成用 `mix(color, blur, bloomStrength)` 而非加法（`composite5.glsl:142`），强度随黑暗效果自适应（`composite5.glsl:130`）。
- Bloom fog：把"会发光的雾"先除出画面再泛光，避免雾被二次泛光（`program/composite5.glsl:196-198`，`lib/atmospherics/fog/bloomFog.glsl`）。
- 色调映射：Lottes 改造版 + 三段风格化：暗部抬升（darkLift，保可读性）、白路径（path to white，高亮去色趋白）、暗部去饱和（`program/composite5.glsl:36-88`，其中三段在 66-88）。
- 饱和度/自然饱和度：BSL 式 Vibrance 实现（`composite5.glsl:89-101`）。
- 镜头光晕：解析式多元素 flare（Base/Overlap/Point/Ring 四类），8 点深度遮挡检测 + 云深度参与，最终 mix 向白色（`lib/misc/lensFlare.glsl:46-126`）。
- 远景光斑（distant light bokeh）：>60m 的远景按距离与 mip 级别混合到"远景 emissive 版本"，使远处光源变成 bokeh 光点（`lib/misc/distantLightBokeh.glsl:1-27`）。
- 输出端：水下 UV 扭曲（`program/final.glsl:95-98`）、色差（`final.glsl:102-106`）、图像锐化（`final.glsl:55-78,108-110`）、
  暗角（亮度补偿式，`final.glsl:155-159`）、输出抖动（`final.glsl:161-162`）；开关默认态见 `lib/common.glsl:147-155`
  （IMAGE_SHARPENING 5、VIGNETTE_R 默认开、CHROMA_ABERRATION 默认 0、DISTANT_LIGHT_BOKEH 默认开）。
- TAA：Catmull-Rom 历史采样（`lib/antialiasing/taa.glsl:31-32,198`），速度/位移感知的混合因子（`taa.glsl:245`）。

### 维度特化
- 下界风暴：射线步进 + 每步 4 octave 3D 噪声的半透明风暴体积，随高度衰减、受透射色调制（`lib/atmospherics/netherStorm.glsl:31-64`）。
- 末地光束：纯 2D 噪声柱状光束（非体积），高度带衰减 + 末影闪光照亮，紫/橙双色（`lib/atmospherics/volumetricLight/enderBeams.glsl:41-64`）。
- 高质量夜空星云：`HQ_NIGHT_NEBULA` 默认开（`lib/common.glsl:566`），实现于 `lib/atmospherics/nightNebula.glsl`。
- 下界/末地通用削减：非主世界统一 `#undef` 大气雾/洞穴雾/云影/光轴烟雾（`lib/common.glsl:592-600`）。

### 性能与时域
- 云在 deferred 全分辨率逐帧重算，无独立历史，靠 IGN + TAA 黄金比抖动消噪（`mainClouds.glsl:9-16`）。
- TAA 历史存于 colortex2（RGB16F），composite6 同时承担 TAA 与 colortex3 的 mipmap 使能（`program/composite6.glsl:16,30-41`；缓冲注释 `lib/pipelineSettings.glsl:4-12`）。
- 泛光用"1/4 gamma 存储 + 四次方还原"规避 8-bit 高亮精度损失与阈值闪烁（见上）。
- 质量分档 profile：POTATO→COMPLEMENTARY+ 九档（`shaders/shaders.properties:2-9`）。

## ③ Astra 可借鉴点

1. **水下视觉链补全：全屏 UV 扭曲 + 雾色偏 + 光束水下色调**
   - 技术：入水后 final 阶段对 UV 加正弦扭曲（幅度随折射强度）；水下雾色从 vanilla fogColor 经逐通道幂次
     `pow(fogColor, vec3(0.33,0.21,0.26))` 得到偏青色调（`program/final.glsl:95-98`、`lib/common.glsl:790,799`）；
     体积光在水下用 `translucentMult`（水面颜色的开方归一）对光束做"隔着水面看"的染色，并对水面上方场景单独压暗（`lib/atmospherics/volumetricLight/volumetricLight.glsl:218-230`）。
   - 对应 Astra：`Astra/shaders/global/water/light_shafts.glsl`（已有水下光束 march）、`Astra/shaders/global/water/absorption.glsl`、`Astra/shaders/program/final.fsh`。
   - 迁移难点：低。UV 扭曲一行级；雾色偏需要与 Astra 现有水下颜色管线（absorption/medium_state）核对避免双重调色（medium_state 内容未读，不确定）。

2. **输出端风格化三件套并入 grading/final**
   - 技术：亮度补偿暗角 `1 - dot(uv-.5,uv-.5)*(1-luma)`（`final.glsl:155-159`）；径向色差 1px 级偏移（`final.glsl:102-106`）；
     4 向负核锐化且 TAA 开启时强度减半防噪声放大（`final.glsl:55-78`）。默认值策略：锐化开、暗角开、色差关（`lib/common.glsl:147-151`）。
   - 对应 Astra：`Astra/shaders/global/post/grading.glsl`（已有 apply_vignette，`grading.glsl:189`；暗角可对齐其亮度补偿式）、`Astra/shaders/program/final.fsh`。
   - 迁移难点：极低。色差/锐化是纯 final 级操作；需注意 Astra FXAA/TAA 的顺序约定。

3. **远景光斑 distantLightBokeh**
   - 技术：距离 >60m 线性增长混合因子，且乘以 miplevel（远处贴图天然变糊），把地表/方块材质颜色与发射强度
     整体替换为"远景版本"，让远处火把/灯笼在画面上变成柔和光点（`lib/misc/distantLightBokeh.glsl:1-27`）。
   - 对应 Astra：`Astra/shaders/lib/surface_emission.glsl`（发射路径）+ gbuffers 地形着色。
   - 迁移难点：中低。需要 Astra 地形着色里区分"远景 emissive 替身"，涉及 gbuffers 与 deferred 两端一致性。

4. **解析镜头光晕（可选开关，默认关）**
   - 技术：以投影后的太阳/月亮位置为锚，四类解析元素叠加；遮挡用屏幕边缘 4 偏移 ×2 = 8 个深度样本估算，
     云线性深度（colortex5.a）参与遮挡，最终 `mix(color, vec3(1.0), flare)`（`lib/misc/lensFlare.glsl:58-76,88-110,126`）。
   - 对应 Astra：`Astra/shaders/global/post/godrays.glsl`（已有光源屏幕位置计算思路）、`grading.glsl` 后的 final 阶段。
   - 迁移难点：中。实现不难，难在"写实定位下如何不廉价"——建议默认关闭（Unbound 自己也默认 LENSFLARE_MODE 0，`lib/common.glsl:153`）。

5. **Tonemap 的暗部抬升 / 白路径 / 暗部去饱和**
   - 技术：在 Lottes 主曲线后串三段亮度域调整：暗部按 `smoothstep(0.1,0,luma)` 混回 gamma 直出保可读性；
     高亮按亮度平滑趋白；暗部按亮度去饱和防死黑发色（`program/composite5.glsl:66-88`）。
   - 对应 Astra：`Astra/shaders/lib/tonemap.glsl`（Reinhard-Jodie 与 Uchimura，`tonemap.glsl:23,32`）、`Astra/shaders/global/post/grading.glsl:175`（apply_grading 之后追加）。
   - 迁移难点：低。纯显示域函数，可做成可选开关；需确认与 Astra 自动曝光的先后关系。

6. **（备选）无阈值泛光的 1/4 gamma 存储**
   - 技术：见 ② 泛光条目（`program/composite4.glsl:50`、`program/composite5.glsl:113-116`）。优点是无阈值噪声、
     高光过渡自然；缺点是弱光源也泛光、偏"氛围"而非物理。
   - 对应 Astra：`Astra/shaders/global/post/bloom.glsl`（已有软膝阈值 prefilter，`bloom.glsl:69`）——Astra 的注释明确记载是从
     Solas 的无阈值方案换到阈值方案（`Astra/shaders/global/water/bloom_capture.glsl:1-4`），即**已经做过这个取舍**。
   - 迁移难点：不建议整体替换；仅当 Astra 阈值方案出现硬截断闪烁时，可借"存储域压缩"思路改造 prefilter 输出域。

## ④ Astra 已有对应实现（对照）

- 云：Unbound 双平面体云无历史、逐帧重算靠 TAA（`unboundClouds.glsl:9-16,120-123`）；Astra 有
  `Astra/shaders/global/atmosphere/clouds_planar.glsl`（412 行）+ `cloud_temporal.glsl`（独立时域历史，
  `cloud_temporal.glsl:3-4,59`）。结论：Astra 时域手段更强；Unbound 的"高度带约束 + 步数自适应"是性能优点。
  两边步进/噪声细节孰优——Astra clouds_planar 未逐行读，**不确定**。
- 泛光：Astra 阈值 HDR 金字塔（`bloom.glsl:69` prefilter、13-tap 双滤波下采样）vs Unbound 无阈值 1/4 gamma tile
  （`composite4.glsl:50`）。Astra 更物理、Unbound 更稳但泛灰；Astra 已有明确取舍记录（`bloom_capture.glsl:1-4`）。
- 水下光束：Astra `light_shafts.glsl:28-81`（水下 128m 上限、shadowcolor0 彩色、积分压缩存储 resolve）
  与 Unbound `volumetricLight.glsl:104-127,209-216`（近远双段、shadowcolor1 彩色、水下 128m 上限）思路高度同源；
  Unbound 独有的"水下看水面"光束染色（`volumetricLight.glsl:218-230`）在 Astra 是否有对应——**不确定**（light_shafts.glsl 未逐行核对到该分支）。
- 水下颜色/介质：Astra 有 `global/water/absorption.glsl`、`medium_state.glsl`、`light_shafts.glsl`，但内容未读，与
  Unbound 水下雾色偏（`common.glsl:790,799`）谁更完整——**不确定**。
- 折射/SSR/焦散：Astra 有 `global/water/refraction.glsl`、`raytrace.glsl`（water_raytrace，`raytrace.glsl:46`）、
  `caustics.glsl`（解析焦散 solas_water_caustics，`caustics.glsl:38`）；Unbound 分别为
  `refraction.glsl:5-43`、`reflections.glsl:84-88`、`shadow.glsl:114-140`。两边量级相当；Astra 焦散是解析式、
  Unbound 是 shadow-map 域噪声梯度式（后者能让焦散跟着彩色阴影/光轴走，是独有视角，但 Astra 已有解析焦散，不构成需求）。
- 彩光体素：Astra 已有下界 compute 体素彩光（`global/dimension/nether_colored_light.glsl`、`nether_volume.glsl`、
  `lib/nether_voxel_grid.glsl`）；Unbound 的彩光同时覆盖主世界（`coloredLightFog.glsl:1-52`）。Astra 主世界无彩光，
  这属于体系性差异而非单点借鉴。
- 雾/天光：Astra 物理渐变天空（`global/atmosphere/sky_gradient.glsl`）+ SH9 方向性天光（`lib/sky_sh9.glsl:5-7`）
  比Unbound 解析三色带渐变（`sky.glsl:24-46`）更物理；Unbound 的 glare（`sky.glsl:58-88`）Astra 是否有等价物——**不确定**。
- 后处理框架：Astra grading（温度/自然饱和/饱和/对比/暗角/输出抖动，`grading.glsl:156-189`）已覆盖 Unbound 的
  T_SATURATION/T_VIBRANCE/vignette/dither；缺色差、锐化、水下扭曲、lens flare、bokeh（基于 Astra 目录清单，未见对应文件名）。
- 维度特化：Astra 末地 Kerr 黑洞天空、下界五类群系雾为 Unbound 所无；Unbound 的下界风暴/末地光束 Astra 有独立实现，
  孰优未对比（Astra global/dimension 各文件未逐行读，**不确定**）。

## ⑤ 借鉴可行性（许可证层面）

- **读思路、用算法思想、自己实现**：不受限。版权保护表达不保护思想；且 Astra 现行做法（如 bloom 注释中标注
  provenance 并重写，`Astra/shaders/global/water/bloom_capture.glsl:1-4`）即此路线，继续沿用最安全。
- **直接抄代码/整段改编发布**：必须满足 §1.3 全部六项（`License.txt:58-80`）——署名+官网链接、保留并随更新同步
  License.txt、改名（≥3 字母符差异、不得含 "Complementary"）、视觉明显不同、不得附加其它许可证（§1.3.e）、
  显著人类-written 新增。其中 §1.3.e 与 Astra 若采用自有许可证/第三方条款并存的做法**直接冲突**，是硬约束。
- 结论：**思路级借鉴：可行且鼓励注明出处；代码级搬运：仅在 Astra 愿意整体接受 Complementary 条款（含放弃自有许可证）时才可行**。
  本报告第 ③ 节各条均按"思路级、自行实现"给出。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **水下视觉链补全**（UV 扭曲 + 雾色偏 + 水下光束染色）——水是 Astra 主打卖点，三项改动小、体感提升立竿见影；对照 ③.1。
2. **输出端三件套并入 grading/final**（亮度补偿暗角对齐、可选色差、TAA 感知锐化）——工作量最小，画面完成度提升明显；对照 ③.2。
3. **Tonemap 三段风格化开关**（暗部抬升/白路径/暗部去饱和）——低工作量，直接补齐 Astra lib/tonemap 的显示端短板；对照 ③.5。
4. **远景光斑 bokeh**——中低工作量，夜景/大型建筑场景提升显著，且与 Astra 的 surface_emission 路径天然契合；对照 ③.3。
5. **解析镜头光晕（默认关）**——中工作量、纯可选，作为风格化彩蛋而非默认写实外观；对照 ③.4。

## 附：引用自抽查记录

完成后按验收标准 2 重新打开文件核对了以下 10 条（均命中）：
1. `lib/common.glsl:586` CLOUDS_UNBOUND 定义 —— grep 命中。
2. `lib/common.glsl:790,799` 水下雾色偏与 waterFogColor —— grep 命中。
3. `program/composite4.glsl:50` `return pow(bloom / 128.0, vec3(0.25));` —— grep 命中。
4. `program/composite5.glsl:114-116` `bloom *= bloom; bloom *= bloom; return bloom * 128.0;` —— grep 命中。
5. `program/composite5.glsl:142` `color = mix(color, blur, bloomStrength);` —— grep 命中。
6. `lib/misc/lensFlare.glsl:126` `color = mix(color, vec3(1.0), flare);` —— grep 命中。
7. `lib/misc/distantLightBokeh.glsl:1` GetDistantLightBokehMix —— grep 命中。
8. `lib/materials/materialMethods/reflections.glsl:84-85` sampleCount=30 / refinementCount=6 —— grep 命中。
9. `lib/antialiasing/taa.glsl:245` blendFactor 速度项 —— grep 命中。
10. `License.txt:58,80,86` §1.3 / §1.3.f / §2.1 —— grep 命中。
