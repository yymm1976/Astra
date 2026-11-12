# eclipseshaders（Eclipse）调研报告 — 面向 Astra 的可借鉴点

- 生成方式：子代理（ZCode worker）逐文件实读调研；本报告所有行号均来自实际读取，成稿后另有附录自抽查。
- 包版本：Eclipse v1.0，作者 gamerbenyt，下载量 425,245（批次二索引 `shader_research/SUMMARY-batch2.md:66`）。
- 调研日期：2026-10-02。
- 引用约定：`P:` = `reference_shaderpacks/eclipseshaders/` 相对路径；`A:` = `Astra/shaders/` 相对路径。
- 许可提示：**包内不存在 LICENSE 文件**（见 ① 与 ⑤），批次二索引记为 CC-BY-4.0。

## ① 概览

**目录与体量。** 包根只有 `shaders/` 一个目录，全包约 307KB（无 LICENSE/README，见 ⑤）；源码分三套：根目录（主世界/默认）、`shaders/world1/`（Iris 约定为末地，本报告按此理解并已在备注登记）、`shaders/world-1/`（下界）。三个目录的 `lib*.glsl` 是**各自全量复制**的独立函数库。

**程序集（根目录）。** `shadow`、`gbuffers_basic/skybasic/skytextured/textured/textured_lit/water/weather`、`composite`、`composite1`、`final`（`P:shaders/` 文件清单）。**没有** `gbuffers_terrain`/`entities`/`hand`、`deferred*`、`prepare*`、`shadowcomp*`、`composite2+`——地形/实体依赖 Iris 的程序回退（推断，见备注）。

**渲染管线（根目录）。** gbuffers 阶段就地完成光照并输出到 colortex0；`composite.fsh` 做水面：SSR + 水雾（`P:shaders/composite.fsh:41-128`）；`composite1.fsh` 做 SSAO（`P:shaders/composite1.fsh:57-88`）；`final.fsh` 是空壳——ACES 拟合函数已写好但调用被注释（`P:shaders/final.fsh:8-37,47-49`）。无 TAA、无历史帧、无曝光/泛光/体积。

**核心数据流（主世界）。** `gbuffers_textured_lit` 写 `01436`（颜色0/法线1/fogMask6；`P:shaders/gbuffers_textured_lit.fsh:25-30,141-148`），`gbuffers_water` 写 `0413`（颜色0/掩码4/法线1/lm.y3；`P:shaders/gbuffers_water.fsh:29-33,156-174`）；`composite` 读掩码4/法线1/lm.y3（`P:shaders/composite.fsh:34-35,43,60,114`），`composite1` 读 fogMask 抑制 AO（`P:shaders/composite1.fsh:84-87`）。

**许可证情况（原文行号无法给出）。** 对整包做 `find -iname "*license*" -o -iname "*readme*" -o -iname "*.txt" -o -iname "*.md"` 无命中，包内没有可引用的许可正文，故 ① 的"许可证原文行号"在包内无源可引；书面依据只有批次二索引：`shader_research/SUMMARY-batch2.md:47`（"可复用，须保留版权声明"）与 `:66`（CC-BY-4.0）。详见 ⑤。

**其它事实。** 选项文件名是 `shaders/shader.properties`（单数，仅 4 行：`P:shaders/shader.properties:1-4`），与约定的 `shaders.properties` 不同名；`shaders/textures/cloud.mcmeta:1-6` 只有 blur/clamp（静态贴图，无动画帧）；`shaders/block.properties:1-4` 只登记水 10060、冰 10070、玻璃/蜂蜜块 10079、传送门 10090。

## ② 架构特性清单（按子系统，带 P 行号）

**2.1 阴影生产与采样**
- 水被剔出阴影贴图（`P:shaders/shadow.vsh:16-19`）；shadow.fsh 只传递纹理（`:12-15`），`sunPathRotation=-40.0` 写在程序里（`:6`）。
- 径向畸变 `distort()`：xy/(len(xy)+factor)、z*0.5，另有直通分支（`P:shaders/distort.glsl:1-4,8-32`）；分辨率常量 1024（`:6`）。
- `computeBias()` 用畸变逆导数让远处 bias 变大（`:19-24`）；NORMAL_BIAS 把法线投到阴影空间偏移（`gbuffers_textured_lit.vsh:50-64`、`gbuffers_water.vsh:37-54`）。
- 软阴影：noisetex 随机角旋转网格，N=2 时 169 tap（`P:shaders/shadow.glsl:11-12,14-32`）。
- 彩色阴影：`shadowtex0<shadowtex1` 检测半透明遮挡，shadowcolor0 做 tint，经 alpha*2/lm.x/inShadow 白化（`gbuffers_textured_lit.fsh:54-73`、`gbuffers_water.fsh:57-76`）。
- `ShadowBrightnessAdjusted(lm.x)` 把昼夜/雨/方块光折成一个阴影染色系数（`P:shaders/lib.glsl:51-55,63-67`）。

**2.2 水体**
- 波场：多频正弦衰减叠加 + exp 塑形（`P:shaders/waves.glsl:19-39`）；顶点 10 迭代位移（`gbuffers_water.vsh:56-62`），片元 40 迭代 + 0.001 步长中心差分法线（`gbuffers_water.fsh:79-98`）。
- SSR：固定 100 步 × 0.5、线性深度差 <0.01 命中，回退解析天空色（`composite.fsh:60-112`）；Fresnel 用 `(1-|dot|)*lmyMask`（`:114`）；命中压 Phong 高光（`:118-122`）。
- 水雾：双深度差单指数（`composite.fsh:44-58`）；水面雾用 lineardepth0（`:124-127`）。
- 输出打包：水像素写 颜色0/掩码4/法线1/lm.y3（`gbuffers_water.fsh:156-174`）。

**2.3 SSAO**
- 余弦半球采样 + TBN（`P:shaders/composite1.fsh:27-45`）；`Δdepth<0.03` 记遮挡（`:74-77`）；按 linDepth/far smoothstep 衰减并乘 fogMask(colortex6)（`:83-87`）。

**2.4 天空/云/光照色**
- 昼/黄昏/夜/雨四段 mix 状态机（`lib.glsl:79-185`）；sunVis=clamp(dot+0.3)（`:51-55`）；天空=fogify 穹顶雾 + 两组 exp 日落辉光（`:187-210`）。
- 云：skybasic 内 cloudTex + `dir.xz/(dir.y+0.5)` + time 滚动（`gbuffers_skybasic.fsh:8-11,37-47`）；星野直出 glcolor（`:27-29`）。
- 七种坐标空间互转（`lib.glsl:212-280`）。

**2.5 维度覆盖**
- world1（末地）：lib 去掉阳光/雨/eyeBrightness，函数改无参（`world1/lib_world1.glsl:1-87`）；composite 保留 SSR 删湿面（`world1/composite.fsh:3,37-116`）；根版 `gbuffers_textured_lit.vsh:38-47` 的 mc_Entity 摆动分支在 world1 版本里被删除（`world1/gbuffers_textured_lit.vsh:18-30`）。
- world-1（下界）：天空/光照退化为 pow(skyColor/fogColor,2.2)、常量雾密度（`world-1/lib_world-1.glsl:39-57`）；水程序删阴影与水雾段（对根版 diff）；lava/雪盲雾按 isEyeInWater==2/3（根版 `gbuffers_water.fsh:147-152`）。

**2.6 代码质量异常（供 ⑤ 边界用）**
- `final.fsh:22-23` mul() 笔误（v[1]），`:47` ACES 调用被注释。
- `gbuffers_basic.fsh:16-19` lightmap 连乘两次。
- `world1/gbuffers_skybasic.fsh:26-28` 天空被覆盖为纯白。
- `gbuffers_textured_lit.vsh:38-47` 的 mc_Entity 8/9/10 未在 `block.properties:1-4` 登记（推断不触发）。
- `gbuffers_skybasic.fsh:8-11` cloudTex 无绑定（选项文件是单数 `shader.properties`，仅 4 行）。
- `gbuffers_water.fsh:4` worldTime 未用；`composite.fsh:131-194` 整段湿面 SSR 被注释。

## ③ 可借鉴点（12 条）

工作量口径：低 = 单文件半天内；中 = 需改接口/多 pass；高 = 需架构调整（本包无"高"级条目）。

**1. 解析正弦波场 + 有限差分法线（低配档）**
- 技术：免贴图/免噪声波高场：多频正弦逐次衰减叠加，`exp` 塑形；顶点 10 次迭代位移，片元 40 次迭代 + 0.001 步长中心差分重建法线。
- P：`shaders/waves.glsl:19-39`、`shaders/gbuffers_water.vsh:56-62`、`shaders/gbuffers_water.fsh:87-97`
- A：`global/water/surface.glsl:79-94,190-224,307-336`、`lib/settings.glsl:128`
- 工作量：低（作 WATER_WAVES 极低档）
- 重复性：**与批次一重复**（`solas-shader.md:30,87`、`bsl-shaders.md:138`；本包为该方向第三个独立样本）
- 误差：无破碎感；远距欠采样；`exp` 塑形无物理含义。

**2. SSR：固定步长 + 线性深度窗口 + 天空回退 + 命中压高光**
- 技术：`1/((1-far/near)z+far/near)` 线性化深度；反射线从 `len(eyePos)*0.03` 起步、100 步每步 0.5；命中条件为射线深度 ≥ 场景深度且差 <0.01；未命中回退解析天空色；命中时用 `(1-hit)` 压掉镜面高光。
- P：`shaders/composite.fsh:21-23,60-74,76-112,118-122`
- A：`global/water/raytrace.glsl:58-123`（0.08 起 1.6 倍扩张 + 二分 6 步 + 置信度）、`program/water.glsl:228`
- 工作量：低（低配档；压高光是一行级技巧）
- 重复性：**与批次一重复**。SSR 方向 23 份报告命中（`grep -l "SSR"`），代表 `complementary-reimagined.md:96`、`photon-shader.md:95`。
- 误差：固定步长漏薄物；0.01 窗口近紧远松；无置信度拉丝；回退不计雾与实体。

**3. 反射强度 = (1-|dot(n,v)|) × 天空光掩码 lmyMask**
- 技术：反射权重乘水面自身 sky light（lm.y 归一存 colortex3），夜里/阴影里反射自然变暗。
- P：`shaders/composite.fsh:43,114`、`shaders/gbuffers_water.fsh:168`
- A：`program/water.glsl:228`（0.025+0.975·pow5 Schlick + skylight）、`:170-174`（水下 Solas 界面 1+dot 截 0..0.5）
- 工作量：低（核对 A 的 skylight 因子是否已覆盖"夜间反射变暗"）
- 重复性：无（批次一无"反射权重乘 lm"表述）
- 误差：`1-|cos|` 非 Fresnel（正射仍 0.5 上限）镜面感偏强；夜间反射偏暗。

**4. 双深度差求水柱厚度，单指数吸收做水雾**
- 技术：`lineardepth1 - lineardepth0` 即视线穿水长度，`exp(-densities*Δd)` 后按 `pow(1-fog,2)` 混到水色。
- P：`shaders/composite.fsh:44-58`
- A：`global/water/absorption.glsl:58-71`（extinction/transmission/medium，含单次散射）
- 工作量：低（低配近似；A 已有水柱读取基建）
- 重复性：无（批次一仅 makeup/super-duper-vanilla 提到 depthtex1，未成条目）
- 误差：忽略散射/波长；Δd 是视线长度而非垂直深度，斜视偏厚。

**5. 极简 G-buffer 打包：法线/掩码/lm 塞进 4 张 RT**
- 技术：colortex1=法线、colortex3=lm.y 归一、colortex4=水掩码、colortex6=雾掩码，DRAWBUFFERS 一次声明（`0413`/`01436`）。
- P：`shaders/gbuffers_water.fsh:29-33,156-174`、`shaders/gbuffers_textured_lit.fsh:25-30,141-148`
- A：`lib/water_buffer_formats.glsl:12-19`、`lib/wet_material.glsl:5`（faceData 位域）
- 工作量：低（思路对照）
- 重复性：无
- 误差：Eclipse 4 张全分辨率 RGBA 携带 4 类标量、无位域/无法线压缩；A 更省带宽。

**6. 阴影畸变偏差补偿（逆导数）与 NORMAL_BIAS**
- 技术：`computeBias()` 返回"畸变导数倒数 × 基准 bias"，让 bias 随畸变放大区域同步变大；NORMAL_BIAS 把法线投到阴影空间再乘 bias，避开 `bias/|lightDot|` 爆炸。
- P：`shaders/distort.glsl:19-24`、`shaders/gbuffers_textured_lit.vsh:57-62`、`shaders/gbuffers_water.vsh:46-53`
- A：`lib/distort.glsl:16-31`、`global/lighting/shadowmap.glsl:155-196`（grazing 0.20 + 1.5·|raw.xy|）
- 工作量：中（动 A 的 bias 需重调参并验证）
- 重复性：**与批次一重复**（`grep -l "畸变"` 命中 6 份：bsl、ebin、glimmer、musk-rose、shrimple、vanilla-plus）
- 误差：Eclipse 源码自认 shadowProjection 为 scalar（透视下是近似）；两者 bias 均为经验式。

**7. 软阴影：每像素随机旋转网格**
- 技术：`noisetex` 取随机角构造旋转矩阵，在 (2N+1)^2 网格步进比较 shadowtex1；N 由选项控制（1..6，N=2 时 169 tap）。
- P：`shaders/shadow.glsl:4,11-12,14-32`
- A：`global/lighting/shadowmap.glsl:38-146`（硬件 PCF 或 gather 四角权重；`:102`、`:134`）
- 工作量：低（无 gather 硬件的后备档）
- 重复性：**与批次一重复**（`软阴影` 命中 6 份：fastpbr、rethinking-voxels、vanilla-plus、makeup、kappa、super-duper-vanilla）
- 误差：恒定 169 tap；未绑时域会闪；A 同预算覆盖率更高。

**8. 彩色阴影的 tint 塑形公式**
- 技术：`shadowtex0 < shadowtex1` 检测半透明遮挡；tint 强度按 alpha*2、`lm.x`、`inShadow` 三次白化，得到"只在阴影里染色、亮处不染"的玻璃色。
- P：`shaders/gbuffers_textured_lit.fsh:54-73`、`shaders/gbuffers_water.fsh:57-76`
- A：`program/shadow.fsh:10,50-52`、`global/lighting/shadowmap.glsl:98-130`（按 gather 角点解析 caster）
- 工作量：低（只借塑形思路）
- 重复性：**与批次一重复**（彩色阴影 21 份命中：complementary-unbound、fastpbr、bsl 等，属高频收敛项）
- 误差：Eclipse 对 `shadowcolor0` 单点采样，与 169-tap 可见度不匹配，半影边缘整块染色；A 无此问题。

**9. SSAO 的衰减窗口与"雾掩码抑制 AO"**
- 技术：AO 仅在 `linDepth/far` 的 smoothstep 窗口内生效，衰减窗口随雨/水收紧，并乘 `1-fogMask` 让浓雾中不出脏 AO。
- P：`shaders/composite1.fsh:83-87`
- A：`program/ssao.fsh:22-116`、`lib/ao_resolve.glsl:86-88`（min(vertexAO,SSAO)+skySwap）
- 工作量：低（把体积雾/水下权重作为 AO 淡出项）
- 重复性：**与批次一重复**（SSAO 17 份命中，代表 `shrimple.md:58`、`ushader.md:190`）；"雾掩码抑制 AO"为新增细节
- 误差：Eclipse 100 tap 且无每像素旋转，无 TAA 时噪声大；A 12 tap 更省更稳。

**10. 阴影亮度耦合因子 ShadowBrightnessAdjusted**
- 技术：一个标量同时表达"白天阴影浓、夜里淡（0.4→0）、雨天转平、方块光高处转平"。
- P：`shaders/lib.glsl:51-55,63-67`
- A：`global/lighting/diffuse.glsl:254-260`、`global/lighting/shadowmap.glsl:200-202`
- 工作量：低（手感参考）
- 重复性：**与批次一重复**（昼夜/雨天阴影淡化是各包收敛项）
- 误差：Eclipse 的 sunVis 是 `dot+0.3` 线性斜坡，无月相/维度区分；A 有静态回退与 moon 处理。

**11. 自定义 2D 云贴图（低配云样本）**
- 技术：`gbuffers_skybasic` 内用 `dir.xz/(dir.y+0.5)` 平面投影采样平铺云图，UV 随 `time` 滚动，alpha 混入天空；`cloud.mcmeta` 只声明 blur/clamp。
- P：`shaders/gbuffers_skybasic.fsh:8-11,37-47`、`shaders/textures/cloud.mcmeta:1-6`
- A：`global/atmosphere/clouds_planar.glsl:90-93,241-341`、`lib/settings.glsl:27-29,102-113`
- 工作量：中（需新增绑定与档位；否则只作思路记录）
- 重复性：无（批次一未见自定义 2D 云贴图）
- 风险：**该实现当前是坏的**——`cloudTex/cloudScale/cloudSpeed` 无 `shaders.properties` 绑定（包内没有该文件），采样源未定义；`world1/gbuffers_skybasic.fsh:26-28` 还有把天空覆盖为纯白的残留。移植须自行声明 `uniform.sampler2D.cloudTex`。

**12. 维度覆盖的复制式结构（反面对照）**
- 技术：末地/下界各自 fork 一份 `lib*.glsl` 与程序，按维度裁掉雨/阳光/阴影代码。
- P：`shaders/lib.glsl:1-280`、`shaders/world1/lib_world1.glsl:1-157`、`shaders/world-1/lib_world-1.glsl:1-127`、`world1/composite.fsh:37-116`
- A：`global/dimension/nether.glsl:1-40`（文件共 210 行）、`global/dimension/end.glsl:1-30`（共 57 行）、`lib/distort.glsl:25-41`（维度分支）
- 工作量：低（仅结构对照，不建议照搬）
- 重复性：无
- 成本：三份库重复约 68 行坐标转换与整套 sky/light/fog 函数，改一处要同步三处；A 单套代码 + 宏。

**补充（不计入 12 条）**
- 水不进阴影贴图：`P:shaders/shadow.vsh:16-19` 把水顶点 `gl_Position=vec4(10.0)` 丢弃，与 `A:program/shadow.vsh:97-114` 需要写 `waterHeight` 供反射/焦散冲突，不能照抄。
- `const bool shadowtex0Nearest = true` 一类 Iris 过滤声明（`P:shaders/gbuffers_water.fsh:20-22`）是旧通道兼容写法；A 走 sampler2DShadow/textureGather，不需要。

## ④ Astra 已有对应实现对照表

| 子系统 | Eclipse（P:） | Astra（A:） | 哪边更省 | 误差/机制差异 |
| --- | --- | --- | --- | --- |
| 水面波与法线 | 解析正弦叠加+差分，`shaders/waves.glsl:19-39`、`shaders/gbuffers_water.fsh:87-97` | 噪声波场+导数+视差+Nyquist，`global/water/surface.glsl:79-94,190-281` | Eclipse 省一个量级（3 次 sin×40 迭代 vs 噪声导数链） | Eclipse 无破碎/无滤波，远距欠采样；A 有 footprint 抗闪 |
| SSR | 100 步定步长+窗口判定，`shaders/composite.fsh:76-112` | 自适应步长+二分+置信度，`global/water/raytrace.glsl:58-123` | Eclipse 省（无细化/无置信度） | Eclipse 漏薄物、边缘拉丝；A 有残差/边界衰减 |
| 水面 Fresnel/反射权重 | `(1-|dot|)*lm`，`shaders/composite.fsh:114` | Schlick 0.025+0.975·pow5，`program/water.glsl:228` | Eclipse 省 | Eclipse 非物理、夜间偏暗；A 用 skylight 缩放 |
| 水雾/吸收 | 双深度差单指数，`shaders/composite.fsh:44-58` | 光谱吸收+单次散射，`global/water/absorption.glsl:58-71` | Eclipse 省 | Eclipse 无散射/波长；A 能量守恒 |
| 缓冲打包 | 4 张 RT 记法线/掩码/lm，`shaders/gbuffers_water.fsh:29-33` | 位域+格式声明，`lib/water_buffer_formats.glsl:12-19`、`lib/wet_material.glsl:5` | A 更省带宽 | Eclipse 无 material 位域 |
| 阴影畸变与 bias | 逆导数 bias+法线偏移，`shaders/distort.glsl:19-24`、`shaders/gbuffers_textured_lit.vsh:57-62` | Steadfast 畸变+bias 经验式，`lib/distort.glsl:16-31`、`global/lighting/shadowmap.glsl:155-196` | 相当（A 含 End 特化更通用） | 两者 bias 均为经验式；Eclipse 假设投影为 scalar |
| 软阴影 | 旋转网格 169 tap，`shaders/shadow.glsl:14-32` | gather 四角/硬件 PCF 分档，`global/lighting/shadowmap.glsl:38-146` | A 更省（同预算覆盖更高） | Eclipse 无时域绑定会闪；A 分档可控 |
| 彩色阴影 | 单点 shadowcolor0 tint，`shaders/gbuffers_textured_lit.fsh:54-73` | GBA tint+四角解析，`program/shadow.fsh:50-52`、`global/lighting/shadowmap.glsl:98-130` | A 更准（同样本量） | Eclipse 半影边缘色渗 |
| SSAO/AO | 100 tap 半球+深度窗，`shaders/composite1.fsh:27-87` | 12 tap 螺旋+bent normal，`program/ssao.fsh:61-104`、`lib/ao_resolve.glsl:86-88` | A 省 8 倍采样 | Eclipse 无每像素旋转；A 有合理性检查与方向性天光 |
| 天空/光照色 | 三段 mix 状态机，`shaders/lib.glsl:79-210` | SH9+方向性天空+Minishita 散射，`lib/sky_sh9.glsl:69-201`、`lib/sky_directional.glsl:12`、`global/atmosphere/*` | A 远超 | Eclipse 无 SH/云影/体积；只可作低配色彩手感参考 |
| 云 | 2D 贴图投影（当前失效），`shaders/gbuffers_skybasic.fsh:37-47` | 体积 planar/vanilla/off 三档，`global/atmosphere/clouds_planar.glsl:241-341`、`lib/settings.glsl:27-29` | A 完整可用 | Eclipse 绑定缺失+末地白覆盖残留 |
| 维度 | 三份 lib 复制，`shaders/world1/lib_world1.glsl:1-157`、`world-1/lib_world-1.glsl:1-127` | 单套+宏，`global/dimension/nether.glsl:1-40`、`end.glsl:1-30` | A 维护省 | Eclipse 改一处要同步三处 |
| 时域/后处理 | 无 TAA/history；final 空壳，`shaders/final.fsh:42-49` | TAA+effect history+display 色调链，`lib/effect_history.glsl:17-43`、`program/display.fsh:165-180`、`program/taa_resolve.fsh` | A 全套 | Eclipse 的 SSR/云无时域稳定手段 |
| 色调映射 | BakingLab ACES 拟合但有 bug 且被注释，`shaders/final.fsh:20-25,47` | BakingLab ACES 正确版+AgX/Uchimura 等，`lib/tonemap.glsl:170-187`、`lib/vendor/bakinglab/*` | A 正确且多算子 | Eclipse 的 `mul()` 有实错，不可抄 |
| 设置/选项 | `shaders/shader.properties` 4 行（疑似命名错误），`shaders/shader.properties:1-4` | `shaders.properties` 810 行+`lib/settings.glsl` 524 行+双语 lang | A | Eclipse 选项/`cloudTex` 绑定基本不可用 |

## ⑤ 许可可行性与"重写 vs 抄"边界

**许可事实。** 包内无 LICENSE/README/任何许可文本文件（整包 `find` 只返回 `shaders/` 内容），因此报告无法引用"许可证原文行号"。书证只有批次二索引两条：`shader_research/SUMMARY-batch2.md:47` 将本包列入"可复用，须保留版权声明"，`:66` 记录为 **CC-BY-4.0**。[假设] 以该索引和 Modrinth 元数据为准，CC-BY-4.0 成立；若统帅要动代码，建议先从原始下载 zip/页面复核许可正文（本包解压目录内没有，见备注）。

**若为 CC-BY-4.0，义务为（标准条款，无 NC/SA）：**
1. 署名（BY）：保留作者名（gamerbenyt）与作品名（Eclipse）、许可标识 CC-BY-4.0，并给出许可全文链接；
2. 标明修改：注明"基于 Eclipse v1.0 修改"并简述改动（BY 区别于 CC0 的关键义务）；
3. 保留声明：不删除原版权/许可/免责声明（本包本就没有，需 Astra 侧补记来源）；
4. 不得附加限制；CC-BY-4.0 允许商用与闭源分发（其与 Astra 现有 GPL 混合仓库的单向兼容结论建议由统帅复核，见备注）。

**"搬代码" vs "重写"边界（针对本包）：**
- 可以搬：小纯函数与常量（如 `waves.glsl` 的波场公式、`distort.glsl` 的 `computeBias` 代数式），前提是补 `Astra/THIRD-PARTY.md` 来源行（作品名/作者/版本/许可/文件行号）并在目标文件头加来源注释；
- 建议重写（只借思路）：水雾、SSAO 衰减、彩色阴影塑形、云采样——Astra 已有更完整实现，照搬会退化，且这些代码与 Eclipse 的旧式 gamma（到处 `pow 2.2`/`pow 1/2.2`）和 4-RT 布局强耦合；
- 禁止照抄：`final.fsh:20-25`（`mul()` 实错）、`gbuffers_basic.fsh:16-19`（双重 lightmap）、`world1/gbuffers_skybasic.fsh:26-28`（纯白覆盖）、`gbuffers_textured_lit.vsh:38-47`（未登记的 mc_Entity 分支）、`gbuffers_skybasic.fsh:8-11`（无绑定的 cloudTex）。这五处是"本包代码≠参考实现"的直接证据；
- 署名形式建议：Astra 侧统一写 "Eclipse v1.0 by gamerbenyt (CC-BY-4.0), https://modrinth.com/shader/eclipseshaders, 用作 X 的思路/函数，改动：…"；若只借思路不搬表达式，也建议在 THIRD-PARTY 记一行"思路来源"，避免日后追溯断链。

## ⑥ Top5 + 暂缓项

**Top5（按"低风险×可验证收益"排序）：**
1. 双深度水柱厚度作低配水雾（③4）——A 已有 depthtex1 基建，一行级近似，先做参数实验。
2. 反射权重乘天空光掩码（③3）——核对 A `program/water.glsl:228` 的 skylight 因子是否已覆盖"夜间反射变暗"，不足则补。
3. 雾/水下权重抑制 AO（③9 子项）——让 `program/ssao.fsh` 在浓雾/水下淡出，消除脏 AO，风险极低。
4. 低配档的正弦波场（③1）——为 WATER_EFFECT_QUALITY=0 提供免噪声/免视差的降级路径，性能收益明确。
5. 阴影软采样后备档（③7）——仅为无 gather 环境或 SHADOW_FILTER_MODE=0 保留，169 tap 版本不建议默认启用。

**暂缓项：**
- 2D 云贴图（③11）：绑定缺失、末地白覆盖残留，且与 Astra CLOUD_VANILLA/PLANAR 档位重叠；
- 彩色阴影塑形公式（③8）：A 更准，照搬会把半影边缘色渗引入；
- ACES 拟合代码（③表）：本包版本有实错，A 的 `lib/tonemap.glsl:170-187` 已正确且来源合规；
- 复制式维度覆盖（③12）：维护成本只增不减；
- 100-tap SSAO / 169-tap 软阴影默认值：比 A 现方案贵 8 倍以上。

## 附录：自抽查记录（成稿后重开源文件核对行号，2026-10-02）

抽查方式：对下列引用用 `sed -n`/`cat -n`/`grep -n` 重新定位（成稿后执行），记录核对结果。

1. `P:shaders/waves.glsl:19-39` — 19 循环、39 行 `return exp(...)-0.4`。OK
2. `P:shaders/composite.fsh:114` — reflectionFactor 行。OK
3. `P:shaders/composite.fsh:76/112` — SSR 开关边界（100 步循环在内）。OK
4. `P:shaders/composite.fsh:44-58` — 水雾段（45-47 取深度、54 fogFactors）。OK
5. `P:shaders/shadow.glsl:14/32` — `GetShadow()` 起止。OK
6. `P:shaders/distort.glsl:19/24` — `computeBias()` 起止（返回式 23）。OK
7. `P:shaders/final.fsh:22,23,47` — v[1] 笔误与注释调用行。OK
8. `P:shaders/world1/composite.fsh:37/116` — 水反射块起止。OK
9. `P:shaders/world-1/lib_world-1.glsl:39-57` — 常量天空/雾函数。OK
10. `P:shaders/world1/gbuffers_textured_lit.vsh:18-30` — 确认无 mc_Entity 摆动分支（初稿误记在 world1，已改为引用根版 38-47）。修正 1
11. `A:global/water/raytrace.glsl:58/123` — 起止（74-93 粗步进、98-114 二分、116-123 置信度）。OK
12. `A:program/water.glsl:228/170-174` — Fresnel 行与水下界面 1+dot 行（174）。修正 1（初稿曾引 181-183）
13. `A:global/lighting/shadowmap.glsl:38/102/134/146` — 分档与两个采样函数。OK
14. `A:global/lighting/shadowmap.glsl:155/196/200` — `shadow_map_position` 止于 196，`static_shadow` 在 200。OK
15. `A:program/ssao.fsh:61/104` — 12 方向循环与返回。OK
16. `A:lib/ao_resolve.glsl:86-88` — min(vertex AO, SSAO)。OK
17. `A:lib/tonemap.glsl:170/176/187` — ACES 区间。修正 1（初稿 170-181，181 为空行）
18. `A:lib/effect_history.glsl:17/31/39` — 三个函数起止。OK

修正记录：共修 4 处——(a) `A:lib/tonemap.glsl` ACES 由 170-181 改为 170-187；(b) `A:program/water.glsl` 水下界面由 `:181-183` 改为 `:170-174`；(c) ② 2.5 的 mc_Entity 摆动分支由 world1 版移到根版 `gbuffers_textured_lit.vsh:38-47`（world1 版实测无该分支）；(d) 根版 composite 水块区间由 41-127 改为 41-128。其余引用复核一致。
