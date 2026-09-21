# sky-clouds → 主任务：公共接入交接单

本文件是 `sky-clouds` worktree 向主任务（水体 / 公共照明 / 阴影 / 合成）申请公共接入的唯一出口。
任务范围见 `docs/parallel-development/sky-clouds.md`。**不通过直接编辑共享文件绕过边界。**

⚠ 水面反射依赖天空。改动以下任一内容前，必须先在本文件提出：天空函数接口、光照输出、云层遮挡语义。

## 填写字段（与任务书一致，不得省略）

- **接口**：需要主任务提供的函数 / uniform / 变量名，写准确名称
- **调用位置**：文件路径 + 行号 或 shader 阶段
- **参数**：类型、取值范围、单位、语义
- **原因**：不这么做会怎样；为什么无法在本 worktree 内解决
- **本侧已完成**：`sky-clouds` 侧已经改动的文件（仅限 `global/atmosphere/` 下 sky_minishita / sky_gradient / clouds_planar / stars 四个）
- **主任务侧待办**：需要对方具体改什么

---

## 待处理

### H1 — 默认 SKY_MODE 让新天空不可见（P0，只需改 shaders.properties 的一行）

- **接口**：`SKY_MODE`（settings.glsl:75 的枚举常量；`SKY_MINISHITA = 0` / `SKY_GRADIENT = 1`）
- **调用位置**：`shaders.properties:150-152`（profile.PERFORMANCE / BALANCED / ULTRA 三处都是 `SKY_MODE=0`）；
  分发点在 `Astra/shaders/global/dimension/overworld.glsl:9-15`（`astra_sky_radiance`，属公共边界）
- **参数**：枚举 0/1，无单位。1 = 本次移植的 Complementary 三向球面天空
- **原因**：所有 profile 默认 0（Minishita），所以本次移植的天空**默认画面上看不到**。
  `overworld.glsl` 的 `#if SKY_MODE == SKY_GRADIENT` 分发在公共文件里，本 worktree 不能改；
  用户在游戏内 SKY 页把 Sky Mode 切到 1 可以立即看到效果，但出厂默认值需要主任务改。
- **本侧已完成**：`Astra/shaders/global/atmosphere/sky_gradient.glsl` 已整体重写为
  Complementary r5.9 `lib/atmospherics/sky.glsl:11-99` + `lib/colors/skyColors.glsl:5-54` 的逐字移植，
  函数签名 `vec3 astra_gradient_sky(vec3 worldDir)` 保持不变，编译通过（linked=234 failed=0）
- **主任务侧待办**：把三个 profile 的 `SKY_MODE=0` 改为 `SKY_MODE=1`（或在确认画面后决定保留 0）
- **复核（2026-09-21，T14 轮实测 · 关闭本条）**：本条写时 profile 在 `:150-152`，现址 `:149-151`。
  待办已执行：`a572e5d` 把三档全置 `SKY_MODE=1`。此后 T1（`f952887`，档位重做）把 ULTRA 改为
  `SKY_MODE=0`（Minishita）。当前实测：PERFORMANCE=1、BALANCED=1、ULTRA=0。
  即"新天空出厂可见"在低/中两档成立，ULTRA 走另一条天空路径。

### H2 — 平面云默认关闭（P1）

- **接口**：`CLOUD_MODE`（`CLOUD_VANILLA = 0` / `CLOUD_PLANAR = 1` / `CLOUD_OFF = 2`）
- **调用位置**：`shaders.properties:150-151`（PERFORMANCE / BALANCED 为 `CLOUD_MODE=0`；ULTRA 已是 1）；
  分发点在 `Astra/shaders/program/scene.glsl:37-40`
- **参数**：枚举 0/1/2
- **原因**：新的平面云（圆顶形状 + 亮顶暗底）只在 `CLOUD_MODE == CLOUD_PLANAR` 下绘制，
  PERFORMANCE / BALANCED 默认走 vanilla 云，看不到本次形状改造
- **本侧已完成**：`Astra/shaders/global/atmosphere/clouds_planar.glsl` 已按
  `lib/atmospherics/clouds/cloudCoord.glsl` + `reimaginedClouds.glsl` + `lib/colors/cloudColors.glsl`
  重写形状与着色，签名 `vec4 astra_planar_cloud(vec3, vec3, vec3)` 保持不变
- **主任务侧待办**：决定是否把 PERFORMANCE / BALANCED 的 `CLOUD_MODE` 提到 1
- **复核（2026-09-21，T14 轮实测 · 关闭本条）**：本条写时 profile 在 `:150-151`，现址 `:149-151`。
  当前实测：PERFORMANCE=`CLOUD_MODE=0`、BALANCED=`CLOUD_MODE=1`、ULTRA=`CLOUD_MODE=1`
  （BALANCED 的 0→1 出自 `a572e5d`）。即待办取了一半：中/高两档可见平面云，低档仍是 vanilla 云。
  与 T14 的直接后果：`astra_cloud_transmission` 在 `CLOUD_MODE != CLOUD_PLANAR` 时整体退化为
  `return 1.0`（`global/atmosphere/weather.glsl:123-125`），故 PERFORMANCE 档即使手动打开
  `CLOUD_SHADOWS` 也没有云影——该选项实际只在 BALANCED / ULTRA 有效，已写进语言文件与实机清单。

### H3 — `astra_planar_cloud` 的两个光照参数已不再被读取（P2）

- **接口**：`vec4 astra_planar_cloud(vec3 worldDir, vec3 directLight, vec3 ambientLight)`
- **调用位置**：`Astra/shaders/program/scene.glsl:38`，实参为 `astra_direct_light()`、`astra_sky_ambient()`
- **参数**：`directLight` / `ambientLight` 仍为 vec3 HDR，但现在函数内部改用 Complementary 的
  `cloudLightColor` / `cloudAmbientColor`（`lib/colors/cloudColors.glsl:1-14`，由 `skyColor` 与昼夜因子推导）
- **原因**：参考的云色不是外部传入的直接光/环境光，而是自带昼夜/雨/月相一整套混合。
  改签名必须动 `program/scene.glsl`（公共边界），所以本侧保留签名、内部不使用这两个参数。
  这不会改变任何光照输出（云色不再受 `SUNLIGHT_STRENGTH` / `SKYLIGHT_STRENGTH` 影响 — 见 H4）
- **本侧已完成**：参数保留、函数内加注释说明；云色完全来自参考的 cloudColors
- **主任务侧待办**：确认后可把签名精简为 `vec4 astra_planar_cloud(vec3 worldDir)` 并同步改 scene.glsl:38

### H4 — 云与天空不再吃 SKYLIGHT_STRENGTH / SUNLIGHT_STRENGTH（P2，需确认是否符合预期）

- **接口**：`SKYLIGHT_STRENGTH`、`SUNLIGHT_STRENGTH`（settings.glsl:36 / :32）
- **调用位置**：`global/dimension/overworld.glsl:17-24`（`astra_sky_ambient`）、:42-49（`astra_direct_light`）；
  旧云色曾直接乘这两个量，新云色不再使用
- **参数**：百分比，100 = 默认
- **原因**：Complementary 的 `lightColor` / `ambientColor`（`lib/colors/lightAndAmbientColors.glsl:6-79`）
  是自带绝对亮度的调色板，不再经过 Astra 的强度滑条。这是照抄参考的直接后果，不是遗漏。
  如果用户调 `SUNLIGHT_STRENGTH` 期待云跟着变亮，行为会和之前不同
- **本侧已完成**：按参考逐字移植，未叠加任何 Astra 强度滑条
- **主任务侧待办**：确认是否接受；若不接受，需要提供一个把强度滑条乘进云色的接入点
  （例如让 `astra_planar_cloud` 重新使用 H3 里的两个参数）

### H5 — 云影（地面）需要公共接入（P2，本侧未实现）

- **接口**：`lib/lighting/cloudShadows.glsl:20-26` 的投影（用 `eastVec` / `northVec` 把云噪声投到地面）
- **调用位置**：应在 `global/lighting/diffuse.glsl` 的直射光项上乘云影系数
- **参数**：`float`，0 = 完全阴影，1 = 无遮挡；由云平面噪声采样得到
- **原因**：`global/lighting/diffuse.glsl` 是公共边界，且云噪声坐标函数现在住在
  `global/atmosphere/clouds_planar.glsl`（`astra_modify_trace_pos` / `astra_rounded_cloud_coord`）里
- **本侧已完成**：坐标函数（`astra_rounded_cloud_coord`、`astra_modify_trace_pos`、`astra_2d_cloud_sample`）
  已按参考实现并可直接复用；未提供云影采样函数
- **主任务侧待办**：如需云影，调用上述三个函数做 `eastVec/northVec` 投影并接入 diffuse.glsl
- **复核（2026-09-21，T14 已落地 · 关闭本条）**：已实现，但落地形态与本条设想不同——
  未新建 `eastVec/northVec` 投影，也未改 `global/lighting/diffuse.glsl`。原因：本包早已有
  沿光向追迹云密度的自有函数 `astra_cloud_transmission`（`global/atmosphere/weather.glsl:122-136`，
  单平面追迹 + 2 次 `textureLod`），且它**已经**被 `program/scene.glsl` 用于雨天压暗直射光；
  真正的缺口是「晴天不投、雨天才投」这一处不对称，而不是缺机制。故 T14 只做两件事：
  在 `program/scene.glsl:238-262` 用 `#ifdef CLOUD_SHADOWS` 把该调用从雨天门里搬出来，
  并补上参考包同样有的掠射衰减（参照 Complementary r5.9 Reimagined
  `lib/lighting/cloudShadows.glsl:60` 的 `sqrt3(1.0 - abs(EdotL))`，表达式自写）。
  遮蔽门改为本包自有的 `static_shadow(skylight)`（屋顶/洞穴不投）。出厂三档均 `!CLOUD_SHADOWS`，
  实机标定项见 `qa/regression-checklist.md` 的 T14 行。
  与参照的实质差异：Reimagined 读的是云 pass 预先渲染的 `gaux4`（因此阴影与可见云严格同形），
  Astra 是各自独立追迹密度场——`weather.glsl:132` 的阈值等于可见云层 `:316` 那条
  `smoothstep(0.21+coverageBias, 0.43+coverageBias, noise)` 的下沿，但少了 `coverageBias`
  （`:181`）里的 `-0.04`，且把 0.21→0.43 的渐变换成 ±0.025 的硬窗口，故阴影与云片存在
  注册错位（阴影只落在比可见云更浓的部分），须实机 A/B 判断是否补偿。出处登记见
  `Astra/THIRD-PARTY.md` 的 `shaders/program/scene.glsl` 行（仅思路，BSL ARR + Complementary 1.7）。

### H6 — 云的自身阴影（shadow map）未接入（P3）

- **接口**：参考的 `GetShadowOnCloud`（`mainClouds.glsl:27-38`），需要 `shadowtex0` + `PlayerToShadow`
- **调用位置**：`clouds_planar.glsl` 的 light march 里 `lightMult`（现固定 1.0）
- **参数**：`float lightMult`，0.25（阴影中）/ 1.0（受光）
- **原因**：`global/lighting/shadowmap.glsl` 是公共边界；本侧只读到云平面，没有阴影采样入口
- **本侧已完成**：`lightMult = 1.0`，双次光走查（自阴影细节）已按参考实现
- **主任务侧待办**：如需要，提供 `bool astra_cloud_shadow(vec3 worldPos)` 之类的入口

### H7 — 水下太阳可能过曝（P3，待实机确认）

- **接口**：`astra_sky_dither` / glare 里的 `glareWaterFactor`
- **调用位置**：`global/atmosphere/sky_gradient.glsl` 的 glare 段
  （参考 `lib/atmospherics/sky.glsl:70,72`：`glareWaterFactor = isEyeInWater * sunVisibility`，
  `glareColor += glareWaterFactor * vec3(7.0)`）
- **参数**：`isEyeInWater` 为 int（0/1）
- **原因**：Astra 的水下颜色由 `program/scene.glsl:65-70` `astra_underwater_color` 独立处理，
  参考这套 +7.0 的水下太阳是 Complementary 自己的水下链路。两者叠加可能让水下看太阳过曝
- **本侧已完成**：按参考逐字移植（硬约束要求照抄）
- **主任务侧待办**：实机看一眼水下太阳；若过曝，删掉 `glareWaterFactor` 那两行即可

### H8 — 远端云噪声精度（P3，暂未处理）

- **接口**：参考 `mainClouds.glsl:56-78` 的 `modFactor` 相机位置回绕，依赖 `cameraPositionInt` /
  `cameraPositionBestFract`（Iris uniform）
- **调用位置**：`clouds_planar.glsl` 的 `tracePos = cameraPosition + ...`
- **参数**：`cameraPosition` 为世界坐标，可达 ±30e6
- **原因**：Astra 未声明 `cameraPositionInt`，新增 uniform 需要动 `lib/uniforms.glsl`（公共边界）。
  不回绕时，30e6 处 float32 分辨率约 1.8 格，乘 `cloudNarrowness = 0.07` 后约 1/8 噪声纹素，
  极远端云可能出现轻微抖动（旧的平面云实现有同样问题，非回归）
- **本侧已完成**：沿用 `cameraPosition`，未做回绕
- **主任务侧待办**：如需修，在 `lib/uniforms.glsl` 补 `cameraPositionInt` / `cameraPositionBestFract`

### H9 — Minishita 的后续改造需要 CPU 侧 uniform（P3，可选）

- **接口**：`rayleighStrengthSun` / `rayleighStrengthMoon`（vec3）、`mieStrengthSun` / `mieStrengthMoon`（float）、
  `daySkyOverridePremultiplied` / `nightSkyOverridePremultiplied`（vec4）、`ambientSkyColor`（vec3）
- **调用位置**：`Astra/shaders/global/atmosphere/sky_minishita.glsl`（本次**未改逻辑**，只补了归属注释）
- **参数**：散射系数 × 曝光；override 为预乘 alpha 的 vec4
- **原因**：Complementary 没有物理大气模型，`sky_minishita.glsl` 属「参考没有的 Astra 自有设计」，
  按任务书要求保留并标注。另一个参考 `_analysis/Steadfast-0.8.0/shaders/environment/sky/minishita.glsl`
  有同思路的更好版本（0.15/0.65 非均匀采样、t=0.15 光照采样、硬编码环境蓝、保亮度的日夜 override），
  但它的强度/override 全是 CPU 预计算 uniform，定义在 `shaders.properties` = 公共边界
- **本侧已完成**：`sky_minishita.glsl` 逻辑零改动，文件头写明归属、三个已知问题
  （地平橄榄绿 / 0.10 硬截断 / 缺环境项）与可选升级路径
- **主任务侧待办**：决定是否引入上述 uniform；不引入则 Minishita 维持现状

---

## 已接入

无。

---

## 本侧改动汇总（2026-09-10）

| 文件 | 改动 |
|---|---|
| `global/atmosphere/sky_gradient.glsl` | 整体重写为 Complementary 三向球面天空（GetSky + skyColors + 参考工具函数）；原来那条单轴渐变被替换 |
| `global/atmosphere/stars.glsl` | 整体重写为 Complementary 球面投影星场（替换原来的立方体面 cell hash） |
| `global/atmosphere/clouds_planar.glsl` | 形状改为参考的上下平面间走查 + 垂直阈值噪声；着色改为亮顶暗底 + 双次光走查 + cloudColors |
| `global/atmosphere/sky_minishita.glsl` | 仅文件头注释（归属标注 + 已知问题 + 升级路径），逻辑零改动 |

验证：`python qa/tools/compile_glsl.py` → linked=234 failed=0；
追加 `--set SKY_MODE=1 --set CLOUD_MODE=1` 与 `--profiles PERFORMANCE BALANCED ULTRA` 同样 0 失败。
**没有 Iris 实例，画面未验证。**

参考因子映射（全部写在代码注释里）：
`noonFactor` ← `sunProgress`；`nightFactor` ← `1 - skyVisibilityDay`；`rainFactor` ← `rainStrength`；
`vsBrightness` ← 常量 1.0（Astra 无 `screenBrightness`）；`syncedTime` ← `frameTimeCounter`；
`sunFactor` / `sunVisibility` / `shadowTime` 由 `worldSunVector.y` 逐字还原。

---
本文件由 `docs/parallel-development/sky-clouds.md` 第 12 行、第 18 行要求建立。
