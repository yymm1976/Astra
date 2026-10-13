# 水下光束重写改动意见（GLM5.3）

分析模型：GLM5.3（ZCode，magpie/workbuddy/glm-5.3）
日期：2026-10-10
对象：`codex/fix-render-handoff` 分支当前未提交的光束重写批次
参考基准：本地 IterationT 3.2.0（`_analysis/latest-2026-09-10/iterationT-3.2.0`）与 Solas 3.7b（`reference_shaderpacks/solas-shader`）
上游事实来源：[当前工作](当前工作.md) W04、[实现与限制](实现与限制.md)「本轮要求对应的现行实现」节

结论先行：当前实现把 ITT 的"每个水下采样点独立做一次波面折射碰撞"替换成了"整条射线共用一个水面入口 + 预计算光量图 + 大波峰包络 + 确定性固定求积"。这四个替换各自丢掉了 ITT 质感的一个来源，叠加起来正是用户看到的四个症状——像柱子、位置乱七八糟、固定不动、毫无质感。本意见主张**替换积分结构、删除包络层**，而不是在现有源图/求积框架内继续调参；管线槽位（prepare4 / composite2 / colortex29 / colortex1 / 消费端）全部保留。

---

## 一、用户症状与机制定因

| 用户症状 | 直接机制 | 代码位置 |
|---|---|---|
| 像柱子（固定均匀光柱） | 整条射线共用单一水面入口 `entry`，束内所有深度共享同一条水面采样直线；入口遮挡沿整条射线恒定（入口在影子里则整条束黑，在亮处则整条束亮） | `light_shafts.glsl` L133-136（entry/entryRay）、L96-112（入口/接受点双查询） |
| 位置乱七八糟 | 束的出现位置由 G 通道"大波峰包络"决定：ITT 最后两层噪声、空间与时间同时 ×0.30 放大成 30~50 格尺度的行波，再 pow(6~10) 锐化成稀疏亮带；与真实波纹、太阳方向均不对齐 | `itt_water_normal_cache.fsh` L48-49、`itt_water_waves.glsl` L85-109 |
| 固定位置（静止感） | 确定性 Gauss 求积明确禁用逐帧/逐像素随机相位；包络行波速度又被 0.30 时间缩放拖慢 3.3 倍；两者叠加后画面在秒级时间尺度上几乎不变 | `light_shafts.glsl` L69/L144-145 注释、`itt_water_waves.glsl` L90 |
| 毫无质感（无焦散流动细节） | 源端把 ITT 的锐利碰撞光量压缩成渐近 4 的宽带（`energy/(1+0.25*energy)`），消费端再按步长选 mip 预过滤；高频峰被两级平滑抹掉后只剩包络大结构 | `itt_water_normal_cache.fsh` L42-46、`light_shafts.glsl` L146-147 |

## 二、参考实现还原

### 2.1 ITT 3.2.0 的完整链路

**源图（波法线缓存）** —— `shaders/deferred.fsh` + `Lib/IndividualFounctions/WaterWaves.glsl`：

- deferred 阶段渲染一张 `CAUSTICS_TEX_RESOLUTION`（500）高的屏幕子区到 colortex7，**只存法线**（EncodeNormal 两通道），不存光量、不存包络（deferred.fsh L24-31）。
- 波场 = `GetWaves` 六层 noisetex 噪声（WAVE_SCALE=0.05、时间 `frameTimeCounter*0.0035`），法线由相邻两点差分（sampleDistance=12，WaterWaves.glsl L79-91）。
- 缓存图天然以 `fract(coord)` 平铺，周期 50 格，无窗口边界、无边缘渐弱（UnderwaterVolumetricFog.glsl L11-14：`coord *= 0.02; coord = fract(coord)`）。

**体积积分** —— `Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl`，由 `composite5.fsh` L273 在 `isEyeInWater==1` 时**全分辨率逐像素**调用 `color += UnderwaterVolumetricFog(vec3(0), worldPos, worldDir, cloudShadow)`：

1. 眼睛→min(场景距离, 40 格)，`VFOG_QUALITY`（默认 6）步（L40-51）。
2. 每步相位 `(i + noise) * stepLength`，noise 来自 `BlueNoiseTemproal()`（golden ratio / plastic ratio 按帧进动，TemporalNoise.glsl L7-9）——**时间抖动，由 TAA 积分收敛**（L53-58）。
3. 阴影 = 每采样点一次 shadowtex 采样（step 比较，NVIDIA 分支用 shadowtex1，L63-68）。没有"入口遮挡"概念：采样点自己投影到 shadowmap，被挡即不亮。
4. **焦散光量 = 每采样点独立做一次波面折射碰撞**（`CalculateWaterCaustics`，UnderwaterVolumetricFog.glsl L23-36）：
   - 在采样点上方 1 格处取波法线：`lookupCenter = worldPos + (0,1,0)`；
   - 查找坐标 `coord = position.xz + position.y * refractDir.xz / refractDir.y`——**以采样点自身深度为参数投影到波面**，深度越深偏移越大；
   - `refract(vec3(0,1,0), wavesNormal, 1.0)` 求向下折射向量，与采样点所在水平面求碰撞点，`dist = distance(collisionPoint, worldPos)`；
   - `caustics = dist * 2.8 + 0.2`——光量直接由碰撞距离决定，波峰聚焦处碰撞近、亮。
5. `shadow *= caustics³`（立方对比，L72-73）；`shadow /= max(3.0, rayLength*0.1)`（L74）；分颜色消光 `pow((0.1,0.6,1.0)*0.99, rayLength*0.04*WATERFOG_DENSITY)`（L76）。
6. 积分后整体乘：`MiePhaseFunction(0.7, LdotV)`（g=0.7 强前向，折射光向与观察向的点积，L83-85）、`colorShadowlight * 0.04 * SUNLIGHT_INTENSITY * UNDERWATER_VFOG_DENSITY`、水色 `(0.2,0.65,1.0)`、云影（L87-93）。

ITT 质感的三个不可拆分来源：**每采样点独立的波面查找（深度方向纹理连续演变）**、**时间抖动 + TAA（高频焦散线条收敛成流动纹理而非静态图案）**、**碰撞距离三次方的原始对比（不做宽带压缩）**。

### 2.2 Solas 3.7b 的分工边界

Solas **没有波面光束**。水下涉及：

- `lib/atmosphere/volumetrics.glsl`（VL 通用 marcher）：指数步长、shadowtex0/1 + shadowcolor 采样、`calculateVLParameters` 中 `isEyeInWater==1` 分支只调整强度 `(1+2·VoL²)(0.25+1.75·sunVisibility)`、颜色混 waterColor、`maxDist /= (1+5)` 与 samplePersistence——**组织方式（透光、遮挡、距离/昼夜）而非束内细节**（L56-63、L232）。
- `lib/water/waterFog.glsl`：解析吸收 + 雾色 + 迎光 glare，无体积积分。
- 时间稳定性靠 VL 自身的 temporal blend（TAA 框架），与 ITT 的抖动收敛同理。

因此交接文档定下的分工（ITT 出束内细节与动态，Solas 出透光/遮挡/距离/昼夜组织）与两包实际能力吻合；问题不在分工，在于 Astra 把 ITT 侧的实现换成了另一个结构。

## 三、Astra 现状审计（按数据流）

1. **prepare4 / itt_water_normal_cache.fsh**（512×512 RGBA16F，128 格世界窗口，0.25 格/格，16 格步进滚动，边缘 4~8 格渐弱）：R = Fresnel 透射 × 碰撞光量（解析梯度法线，掠射距离与光量均平滑有界压缩，渐近 4）；G = 大波峰行波包络（ITT 末两层 ×0.30 时空缩放，晴天 pow 10→6）；BA = 局部折射向上斜率。
2. **scattering.vsh**：flat 输出折射光向/强度链（Solas 侧昼夜天气调制，正确保留）、单一水位、窗口原点。
3. **scattering.fsh（composite2，colortex1 @ 0.5x）water_shafts_march**：单入口投影（`entry = worldOrigin + source*(depth/source.y)`，`entryRay = ray - source*(ray.y/source.y)`），7 区间 × 4 点 Gauss，每点 textureLod 源图（足迹随步长 × entryRay 跨度 × 0.25 选 mip 0~3）× G 包络 × 近远 smoothstep × 区间端点插值的入口/接受点阴影可见性（每对 shadow_coverage + shadow_opaque_visibility + 可选云影，共 8 对）。
4. **water_composite.fsh / display.fsh**：`water_shafts_resolve` 双线性 + 角点端点距离配对拒绝 × 用户强度，Solas 水雾线性加光。此端结构健康，保留。

## 四、逐项差异对照

| 维度 | ITT 3.2.0 | Astra 当前 | 后果 |
|---|---|---|---|
| 波面查找 | 每采样点独立，以自身深度为参数（`position.y*斜率`），fract 平铺无限域 | 整条射线一个 entry + 水面平面直线扫描 | 束内纹理不随深度演变；柱状 |
| 束的位置来源 | 每采样点碰撞距离（与波纹、太阳方向自然耦合） | G 通道预计算包络（30~50 格行波 pow 锐化） | 位置与真实波纹脱钩；稀疏错乱 |
| 时间维度 | BlueNoiseTemproal 抖动 + TAA 收敛 | 明确禁用随机相位，确定性 Gauss | 静态图案；无流动质感 |
| 高频对比 | `caustics³` 原始三次方，无上限 | 源端渐近 4 压缩 + 消费端 mip 预过滤 | 焦散线条消失；"毫无质感" |
| 遮挡 | 每采样点一次 shadowtex 采样 | 入口/接受点双查询，区间内端点插值 | 入口影子沿整条射线传播；区间内细遮挡丢失；成本更高 |
| 分辨率 | 全分辨率逐像素 | 0.5x buffer + 全分辨率 resolve | 半分辨率无时域补偿 → 块状图案 |
| 相位 | g=0.7 单次 Mie，积分后乘，全局折射光向 | g=0.45 + 60% 各向同性，逐 texel 局部斜率方向 | 方向响应弱且被滤波；迎光不够亮、侧向偏亮 |
| 积分域 | 固定 40 格 | 近 0.08~2 缓入，14~26 淡出，48 格端点标记 | 差异不大，Astra 属 Solas 侧组织，可保留 |
| 源图周期 | fract 平铺 50 格，无边界 | 128 格窗口 + 边缘渐弱 + 16 格步进 | 快速移动/换池时覆盖缺口；束忽隐忽现 |

## 五、改动意见

以下 P0/P1 构成结构替换，P2/P3 是参数与保留项。全部改动集中在四个文件：`program/itt_water_normal_cache.fsh`、`lib/itt_water_waves.glsl`、`global/water/light_shafts.glsl`、`global/water/shaft_layout.glsl`；管线槽位、buffer 尺寸、消费端、scattering.vsh 的 uniform 契约不动。

### P0-1 积分改为每采样点独立波面投影（替换单入口结构）

`water_shafts_march` 中删除 `entry`/`entryRay` 与 `water_shaft_wave_segment` 的窗口裁剪直线，改为对每个积分点：

```
采样点 worldPos = worldOrigin + ray*distance
水面下深度 dBelow = waterShaftSurface.x - worldPos.y（>0 才有效）
查找坐标 waveXZ = worldPos.xz + dBelow * 折射斜率
   折射斜率 = 平面折射向 source.xz / source.y（与现 waterShaftSource.xyz 一致）
光量 = 源图采样(waveXZ)
```

这正是 ITT `coord = position.xz + position.y * lightVector.xz/lightVector.y` 的结构：束内纹理沿深度方向连续平移、展开，柱状感消失。注意与 ITT 的差异并保留 Astra 的正确部分：ITT 用 `lookupCenter = worldPos + (0,1,0)` 粗暴假设水面在采样点上方 1 格；Astra 用真实水位（`waterShaftSurface.x`，受 D03 限制）更准确，**保留**，仅把投影参数从"相机深度"换成"采样点在水面下的深度"。

### P0-2 删除 G 通道大波峰包络，束的位置交还碰撞光量

- `itt_water_waves.glsl`：删除 `itt_water_beam_envelope` 整个函数。
- `itt_water_normal_cache.fsh`：G 通道停写包络（可改存未压缩的碰撞距离原值 `0.2+2.8*landingOffset`，供消费端做三次方，见 P0-3），`pow(mix(10,6,clearDay))` 锐化链整体删除。
- `light_shafts.glsl` L162 的 `irradiance *= wave.g 包络` 一并删除。

束的出现位置由此回到与波纹、太阳折射方向自然耦合的碰撞距离上——这是 ITT"位置不乱"的根本原因。晴天增强不靠包络锐化，继续由 scattering.vsh 的 `mix(0.32,1.35,clearDay)` 强度链承担（Solas 侧，已在）。

### P0-3 恢复时间抖动，由 TAA 收敛

- 步进相位加 `(interval + node) 基础上叠加逐像素 blue-noise × 帧进动偏移`（Astra 已有 TAA 基建：`astra_jitter_uv`、frameCounter；无现成 BlueNoiseTemproal 就用 bayer64 + golden ratio 帧进动，与 ITT 的 `BayerTemproal`/`BlueNoiseTemproal` 同构）。
- 抖动幅度限制在单区间内（≤ stepLength），不会引入横移糊脸；束的空间位置由世界坐标查找决定，抖动只影响采样相位。
- ASTRA_TAA 关闭时退化为静止噪点（与 ITT 无 TAA 档行为一致），可接受；不要为无 TAA 档回退到确定性模式（那正是现在的静止图案）。
- 同步修改 `light_shafts.glsl` 头部"no per-pixel or per-frame random phase"的设计注释与 docs 表述——该约束是本批次引入的，不是长期决议。

### P0-4 高频对比解压：源端存原值，三次方移到消费端

- 源图 R（或 G，见 P0-2）改存 `transmission × (0.2 + 2.8*landingOffset)` 的**未压缩**值；删除 `energy = energy/(1+0.25*energy)` 渐近压缩（itt_water_normal_cache.fsh L45-46）。
- 消费端每采样点做 `caustics³`（ITT 原式），mip 选择从"按步长跨度预过滤"改为"按半分辨率 texel 足迹固定 lod 0~1"——预过滤的目的是抗混叠，但和三次方一起做等于把峰先磨平再放大；先立方后滤波才有 ITT 的亮线。
- 混叠由 P0-3 的时间抖动 + TAA 承担，这正是 ITT 的分工。若实测 TAA 关闭档闪烁不可接受，再在**消费端**对 caustics³ 后的值做一次窄滤波，而不是回到源端压缩。

### P1-1 遮挡查询改回每采样点单查询

`water_shaft_path_visibility` 的"入口点 + 接受点"双投影结构（L96-112）删除，改为每个积分点一次 shadowmap 投影（ITT 方式：采样点世界坐标 → shadowProjection → distort → shadowtex 采样，可用现有 `shadow_opaque_visibility`）。理由：

- 现结构的入口影子沿整条射线恒定传播，是"柱子"感的第三个来源；
- 入口点本应随采样点各自沿折射光回溯到水面（每点一个入口），现结构用相机正上方单一 entry 近似，两者都不如"采样点直接投影"来得便宜且正确——shadowmap 记录的就是空气侧遮挡体，采样点被遮挡即无光，折射偏差是两侧共有的近似（交接文档已承认"影图仍为空气方向"）。
- 成本从 8 对 ×（coverage+visibility+云影）降为 ≤ 步数次单采样；云影保留现接法（乘在可见性上）。

### P1-2 源图域改为 fract 平铺（或窗口连续跟随，二选一，推荐前者）

ITT 的 `fract(coord)` 平铺使其无窗口边界。Astra 源图周期即窗口宽度 128 格：查找坐标 `waveXZ - 窗口原点` 后 `fract(·/128)` 平铺。接缝是噪声纹理的不连续——ITT 的 50 格平铺同样是噪声不连续接缝，实践可接受。若不接受接缝，备选是窗口每帧连续跟随相机（`origin = floor(camera.xz)`，无 16 格步进、无边缘渐弱），代价是每格 texel 内容随相机移动全部重算（本来就是全图每帧重写，实际无额外成本）。**不要**保留现在的"16 格步进 + 边缘渐弱"组合——它同时制造覆盖缺口与边缘忽隐忽现。

注意：平铺域查找坐标必须用**绝对世界坐标**（含 cameraPosition），与源图生产一致；`waterShaftFieldOrigin` 的零 texel 偏移协议保留。

### P1-3 相位函数对齐 ITT 参数

- g 从 0.45 提到 0.7，各向同性混合从 40% 降到 ≤20%（或直接 0，与 ITT 一致）。
- 方向向量用**全局折射光向**（waterShaftSource.xyz）与观察向的点积，在积分后单次计算；删除逐 texel 的 BA 局部斜率方向（L168 的 `normalize(vec3(wave.b,1.0,wave.a))`）。逐 texel 方向经源图半精度与滤波后近似意义有限，还占掉源图一半通道。
- BA 通道腾出后：R 存透射、G 存未压缩碰撞距离（P0-2/P0-4）、BA 可存法线 XZ 斜率供将来调试，或干脆保留 BA 写零。

### P2 参数与步数（结构替换后重调）

- 区间数 7 → 5 起步：ITT 默认 6 步即有质感，因为细节由每次查找决定而非步数；每步查找从"mip 预滤波光量"变为"原值 + 立方"，信息密度更高。抖动开启后有效样本 = 步数 × 帧数。
- `shaft_layout.glsl` 的近处缓入（0.08~2）与远处淡出（14~26）保留——这是 Astra/Solas 侧的距离组织，ITT 无此层但 Astra 的"近处可读、范围有限"要求来自用户，不退。
- 强度链（scattering.vsh 的 visibility、`astraWaterShaftTintSqrt`、`astraWaterTransmissionTint`、`waterShaftSource.w*0.085`）数值在结构替换后需重新标定一次：删除包络后光量的分布完全不同，现常数必然偏暗或偏亮；以 ITT 的 `0.04 * SUNLIGHT_INTENSITY * VFOG_DENSITY` 与 `(0.2,0.65,1.0)` 为标定起点。

### P3 明确保留项（Solas 分工 + 既有决议）

- scattering.vsh 的昼夜/天气/失明/阴影渐退强度链（L39-45）。
- 真实水位入口与薄水/侧流水跳过（`water_is_thin_sheet`、水位低于观察起点 0.032 不生成）——Astra 比 ITT 正确的部分。
- 消费端 `water_shafts_resolve` 的端点距离配对与弱支持渐弱、排除手部、Solas 水雾线性加光、Bloom 双路径共用。
- 半分辨率 colortex1 + 全分辨率 resolve 槽位不变（抖动 + TAA 才是半分辨率的正确搭档；若实测 TAA 关闭档不可接受，再讨论全分辨率减步，本轮不动）。
- 水底焦散独立表面路径、48 格端点重建标记。

### 本轮明确不做

- 不加回固定光圈、四深度聚光表、逐格 DDA、局部反求、光束独立历史（均为已否决路径；shaft_history.glsl 保持 RETIRED）。
- 不动水面 Steadfast 波面、折射、菲涅尔环、W05/W07-W12 各事项。
- 不处理 Voxy 零视口（与光束无证实关联）。

## 六、性能预期与风险

**成本账（均衡档，半分辨率）**：
- 删除：prepare4 两层包络噪声积分（512² × 2 层）、march 的 8 对入口/接受点阴影查询与区间扫描开销、G 通道乘法。
- 新增：每积分点一次 shadowtex 采样（≤5 次，替代 8 对双查询）、抖动噪声读取。
- 净变化预期持平或更低；真正的不确定项是立方对比后的亮度峰值对 Bloom 的影响，需实测。**不据此宣布帧率结论**，按工作页规则等实测。

**风险与对策**：
1. TAA 关闭档噪点：先接受（ITT 同行为）；不可接受时消费端窄滤波（P0-4 附注）。
2. 平铺接缝：噪声不连续，与 ITT 实践同级；备选连续跟随窗口（P1-2）。
3. 光量分布变化导致的过曝/过暗：P2 标定项，预留一次参数轮。
4. D03 水位限制不因结构替换消失：换池瞬间仍可能缺束，属已知限制，不新增兜底。

## 七、验证清单（实现后逐项）

1. 晴天正午静水：束随波纹流动、深度方向纹理展开，不再是等宽竖柱。
2. 相机横移/转动：束在世界中位置固定（视差正确），无忽隐忽现（平铺/窗口）。
3. 船/桥墩阴影：影缘在束上逐段出现（单点遮挡），不再整条束明灭。
4. TAA 开/关对比：开=平滑收敛；关=噪点但不呈块状图案。
5. 迎光看太阳：束显著增亮（g=0.7 前向）；侧向受抑。
6. 晨昏/夜间/雨天：强度链平滑减弱，无跳变。
7. 均衡档帧率与 Bloom 峰值实测记录。
