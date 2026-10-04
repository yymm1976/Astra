# lux-v1（Lux V1 v1.3）面向 Astra 光影的可借鉴点调研

- 生成方式：**子代理调研**（第二批第 9 包，契约由统帅下发）；全程只读参考包与 Astra 源码。
- 包版本 **1.3**（`P:AGREEMENT.txt` 落款 2023-02-04，包内无版本行，版本取批次二索引）；调研日期 **2026-10-02**。
- 引用约定：`P:` = 相对 `reference_shaderpacks/lux-v1/`；`A:` = 相对 `Astra/shaders/`。行号全部来自实读（见附录）。
- 上游元数据（未复核）：显示名 Lux V1，作者 TechDevOnGitHub，下载量 1,231,466，许可证"保留所有权利"。

## ① 概览

**体量/结构**：包根只有 `AGREEMENT.txt` + `shaders/`（865 KB）。142 个 `.fsh/.vsh` 外壳 + 51 个 `lib/*.glsl` + 24 个 `program/*.glsl`，BSL 式三段：

| 层 | 内容 | 位置 |
|---|---|---|
| 世界壳 | `world0/`（主世界）/`world-1/`（下界）/`world1/`（末地），仅 `#define`+include | `P:shaders/world-1/deferred.fsh:13-16`、`P:shaders/world1/deferred.fsh:13-16` |
| 共享实现 | `program/*.glsl`，FSH/VSH 双 `#ifdef` 段 | `P:shaders/program/composite.glsl:13,184` |
| 库 | `lib/{atmospherics,color,lighting,post,reflections,surface,util,vertex,antialiasing}` | `P:shaders/lib/global.glsl:9-11`（唯一总入口） |

**许可证原文**：包内**只有** `AGREEMENT.txt`（全包搜 `*licen*`/`*readme*` 无命中，文中引用的 `README.md` 未随包分发）。关键行：

- `P:AGREEMENT.txt:1-2`：`…most of the content in this shader was made by Capt Tatsu (https://bitslablab.com).`
- `P:AGREEMENT.txt:4`：`All the other content not provided in BSL v7.1.05 was made by me (…/TechDevOnGitHub).`
- `P:AGREEMENT.txt:6-7`：`The agreement for this shader is the same as BSL's` / `You can find it here: https://bitslablab.com/bslshaders/#download`

即**协议随 BSL（上游页面），本包无独立许可证文本**，沿用批次二索引"保留所有权利"。核心文件抬头均写 `Based on BSL Shaders v7.1.05 by Capt Tatsu`（例 `P:shaders/lib/atmospherics/sky.glsl:1-7`）——本报告据此**逐条判断 Astra 是否已从 BSL/Solas/Steadfast 吸收**。

**特别关注点**：百万下载的大气向包；天空/雾自由度组织，对照 Astra 调色板与天气系统 → ③-1/2/4/5/15/16 与 ⑥。

## ② 架构特性清单（按子系统）

**A. 大气**：天空闭式散射 `P:shaders/lib/atmospherics/sky.glsl:9-45`（mieFactor `:26-28`，`Lift(sunHeight,2)` `:16`，指数体 `:34-36`）；雾 `fog.glsl:10-35`（雾色三因素）+`:38-62`（主雾 pow(d,3)，系数 `:41-44`）+`:64-82`（失明/熔岩/派发）；体积光 `volumetricLight.glsl:39-98`（步长 `:59`，阴影图外回退 `:91-94`）；云 `clouds.glsl:11-34`+`:36-96`；星 `stars.glsl:11-22`（Planck）+`:25-56`；流星 `stars.glsl:63-115`；极光 `aurora.glsl:12-39,44-67,83-133`；边界/粉雪/水下雾 `borderFog.glsl:9-33`、`powderSnowFog.glsl:9-22`、`waterFog.glsl:9-14`；末地天空 `endSky.glsl:10-53`。

**B. 颜色**：7 组天气色按群系权重混合 `P:shaders/lib/color/lightColor.glsl:11-33`；日月直射色 `:35-38,57-66`；天空/雾共用 sqrt 编码 `skyColor.glsl:9-18`；水色 `waterColor.glsl:9-13`；下界/末地 `netherColor.glsl:9-33`、`endColor.glsl:9-10`；方块光 `blocklightColor.glsl:9-10`；环境光 `ambientColor.glsl:9-25`。

**C. 光照/材质**：统一 `GetLighting()` `P:shaders/lib/lighting/forwardLighting.glsl:20-147`（阴影 `:77`、植被透光 `:86-91`、自发光 `:97-106`、去饱和 `:113-146`）；阴影两档+彩色+旋转核 `shadows.glsl:9-30,83-162`；AO `ambientOcclusion.glsl:9-30,32-79`；材质解析 `surface/materialGbuffers.glsl:9-70`、`materialDeferred.glsl:9-40`；视差 `surface/parallax.glsl:15-46,48-76`；方向性光照贴图 `directionalLightmap.glsl:9-35`；GGX `ggx.glsl:10-41,67-82,84-118`。

**D. 水面**（`P:shaders/program/gbuffers_water.glsl`，747 行）：Gerstner+噪声波场 14 入参 `:95-140`；双档参数 `:150-188`；视差+差分法线 `:194-225`；反照率三模式 `:343-354`；透光权重 `:356,608-610`；反射两分支+高光 `:447-511,512-585`。

**E. 后处理链**（编号即顺序）：composite `P:shaders/program/composite.glsl:91-179`（水下吸收 `:119-136`，体积光 `:165-169`）；composite1 `:58-135`；composite2/3/4 = 运动模糊/景深/泛光模糊 `composite2.glsl:30-83`、`composite3.glsl:99-171`、`composite4.glsl:78-89`；composite5 = 泛光瓦片+曝光+分级+3 种 tonemap+色差+暗角+颗粒 `composite5.glsl:105-147,349-359,383-397`；composite6 = TAA/FXAA+HSV 分级 `:52-72`、`lib/color/colorgrading/colorGrade.glsl:12-30`；final 锐化 `final.glsl:34-67`。

**F. 设置系统**：链式 profile `P:shaders/shaders.properties:4-7`；`screen=` 主网格+12 子页 `:43,46-71,74-96`；pass 门控 `:121-128`；CPU 时间/盲视 uniform `:143-155`；10 组群系 `smooth()` `:159-185`；默认值矩阵 `lib/settings.glsl:9-306`。

## ③ 可借鉴点（16 条）

> 工作量：**快赢**（半天内）/ **小**（约 1 天）/ **中**（数天）/ **大**（一周+，需立项）。"与批次一重复"= 方向已出现在批次一报告或 `SUMMARY.md` 矩阵，同时是"同方向多次出现"的收敛证据。

**1. 天空闭式散射**：mieFactor 混直射光 + `exp((skyColor-1)*sqrt(y)*7)` 垂直指数吸收，无采样。
`P:shaders/lib/atmospherics/sky.glsl:16-38` / `A:global/atmosphere/sky_gradient.glsl:158-224` / 快赢（只作地平线胶光补项）。**与批次一重复**（BSL 谱系）；增量是 `Lift(sunHeight,2)` 与雨天基色转天气色。

**2. 雾色三因素**：仰角 `top` 指数分布、朝阳 `lightmix` 暖光、雨天雾色换 `weatherCol²` 按亮度归一。
`P:shaders/lib/atmospherics/fog.glsl:16-34` / `A:global/atmosphere/fog.glsl:207-223` / 快赢。**与批次一重复**（雾色同源 3 包印证）；Astra 谷雾已更细（`A:global/atmosphere/fog.glsl:67-81`）。

**3. 体积光几何步进**：`exp2(i+dither)` 步长 7 步覆盖 128 格；投影出阴影图时 `vl += 1.0` 兜底（`:91-94`），两位深提前 break（`:62`）。
`P:shaders/lib/atmospherics/volumetricLight.glsl:51-97` / `A:global/atmosphere/volume_fog.glsl:114-150` / 快赢（各 2-3 行）。**与批次一重复**（非均匀步长 3 包印证）；Astra 已有步数档+抖动+自适应。

**4. 云 6 层平面堆叠**：等比平面 + 逐层 `coverage` 偏移合成，`cloudGradient` 记录首次命中层造亮顶暗底（`:74-81`）；6×6 纹理读、无步进。
`P:shaders/lib/atmospherics/clouds.glsl:36-96` / `A:global/atmosphere/clouds_planar.glsl:56-96` / 中（作 `CLOUD_QUALITY==0` 廉价云）。**部分重复**（批次一"云图视差云低档"SDV）。

**5. 极光**：`worldDay` 概率哈希 + `isCold` 群系门（`:89-91,128-130`）+ 半球投影几何 + `1-|n1+n2|` 脊状噪声（`:26-32`）；颜色 4 档。
`P:shaders/lib/atmospherics/aurora.glsl:83-133` / **Astra 无模块**（`grep -ri aurora` 仅 `A:global/atmosphere/clouds_planar.glsl:44` 一句"未移植"）/ 中。**与批次一重复**（Solas/Mellow/BSL/Complementary 4 包印证）。

**6. 流星**：投影平面划网格稀疏挑格 + 尾迹密度场（`:88-94`）+ 多层旋转叠加（`:107-112`）。
`P:shaders/lib/atmospherics/stars.glsl:63-115` / `A:global/atmosphere/stars.glsl:48-83`（仅静态星）/ 小。批次一**无对应**。

**7. 恒星色温**：Planck 黑体归一，`Hash21` 给每星独立色温（`:53`）；常量 `H/C/K` 在 `P:shaders/lib/util/constants.glsl:14-16`。
`P:shaders/lib/atmospherics/stars.glsl:10-22` / `A:global/atmosphere/stars.glsl:68`（固定冷白）/ 快赢。批次一无对应。

**8. 水体三模式 + 透光权重**：平色/乘纹理 alpha/亮度比推水色（`:345-352`）；`vlAlbedo` 的 `1-α^64` 抑制近岸全亮（`:356,608-610`）。
`P:shaders/program/gbuffers_water.glsl:343-356` / `A:global/water/surface.glsl`+`A:lib/solas_water.glsl:103-109` / 快赢。批次一无"三模式"对应。

**9. 水面视差 + 常量档**：4 步视差 + 差分法线（`:194-224`）；`WATER_NORMALS==1` 内联 14 个波参数为常量（`:150-167`）省 uniform 读取。
`P:shaders/program/gbuffers_water.glsl:142-225` / `A:global/water/surface.glsl:296-352` / 小。**与批次一重复**（Gerstner 2 包印证）。

**10. 水洼**：5 octave 阈值掩码（`:13-19`）+ bicubic 高度场（`:25-64`）+ 掠射角水膜（`:71`）。
`P:shaders/lib/reflections/rainPuddles.glsl:9-101` / `A:lib/wet_material.glsl:7-28` / 中。**与批次一重复**（水洼掩码 7 包印证）。

**11. 粗糙反射 VNDF**：球形帽可见法线采样 + `lod=sqrt(8*roughness)` 取 mip（`:44-70`）。
`P:shaders/lib/reflections/roughReflections.glsl:9-72` / `A:lib/sky_reflection_cache.glsl`（mip 0）+`A:global/water/raytrace.glsl` / 中。**部分重复**（批次一最高置信收敛项"粗糙度 mip+环境 BRDF"）。

**12. 复杂 Fresnel**：8 组金属 `n`/`k` 表由 f0 量化索引（`:45`），非金属退 Schlick。
`P:shaders/lib/reflections/complexFresnel.glsl:9-65` / **Astra 无对应** / 大（需先有金属通道）。**与批次一重复**且已入长期储备。

**13. Tonemap Prism2024**：ACES 色适应 + Prism tonescale + 通道重建色相（`:150-164`）+ `CorrectiveSaturation` 补偿（`P:shaders/program/composite5.glsl:287-307`）。
`P:shaders/lib/post/tonemap.glsl:20-193` / `A:lib/tonemap.glsl:22-160` / 中。**部分重复**（批次一 tonemap 三段式/ACES 参数面/BSL 三段式）；可作 `A:lib/settings.glsl:207` 第 5 档。

**14. 统一抖动相位**：`fract(dither + frameTimeCounter/PHI*13.333)` 在 7 处同式（AO `ambientOcclusion.glsl:38`、体积光 `volumetricLight.glsl:48`、云 `clouds.glsl:44`、极光 `aurora.glsl:98`、粗反 `roughReflections.glsl:54`、raytrace `raytrace.glsl:39` 等），TAA 可同时收敛所有随机量。
`P:shaders/lib/lighting/ambientOcclusion.glsl:38` 等 7 处 / Astra 三处相位独立（`A:program/ssao.fsh:63`、`A:global/atmosphere/volume_fog.glsl:129`、`A:global/water/light_shafts.glsl:52`）/ 快赢。批次一无对应。

**15. 天气×群系 RGB 矩阵 + 嵌套 screen**：7 天气×4 通道 + 5 下界群系×4，群系权重由 CPU uniform 平滑（`P:shaders/shaders.properties:159-185`）；screen 二维嵌套（`:78-96`）。
`P:shaders/shaders.properties:43-96` / `A:shaders.properties:700-723`+`A:lib/color_controls.glsl:6-27` / 快赢（组织层）。**与批次一重复**；lux 独有"天气×群系"矩阵。

**16. CPU 时间 uniform（同式）**：`tAmin`→`tAlin`→`timeAngle` 与 `shadowFade` 表达式。
`P:shaders/shaders.properties:143-151` / `A:shaders.properties:594-602`（`astraSolas*`，Solas V2.2b 出处）/ 0（已具备）。两侧逐字相同（附录 #11）；**不得再以 lux 为出处**。


## ④ Astra 已有对应实现对照表

| 子系统 | lux（`P:`） | Astra（`A:`） | 哪边更省 / 误差来源 |
|---|---|---|---|
| 天空 | 闭式散射无采样（`atmospherics/sky.glsl:9-45`） | 三分向+荒漠带+眩光（`sky_gradient.glsl:158-224`、`sky_minishita.glsl`） | Astra 更贵、自由度更高；lux 无地平线以下假散射，竖直仅一条指数 |
| 雾 | 单函数三因素+pow(d,3)（`atmospherics/fog.glsl:10-35`） | FogV2 六情形+谷雾+空气透视（`fog.glsl:101-190,67-81,207-223`） | Astra 更细；lux 省在雾色直连 sky/light。误差：Astra 谷雾两条 smoothstep，陡坡有过渡带 |
| 体积光/雾 | 阴影图空间 7 步无相位（`volumetricLight.glsl:39-98`） | 12/24/48 步+HG 相位+云透过率（`volume_fog.glsl:70-77,91-107,114-150`） | Astra 更贵但完整；lux 省在 7 步、无需 world 距离。误差：lux 无相位函数 |
| 云 | 6 平面堆叠 36 次纹理读（`clouds.glsl:36-96`） | 高度场步进（`clouds_planar.glsl:56-96`，高度 192）+时域（`cloud_temporal.glsl`） | 低档 lux 远省；默认档 Astra 更真。误差：lux 层距固定 1.6、近地平线硬收，天际线有层带感 |
| 夜空（星/极光/流星） | 逐星色温+半球投影极光+网格尾迹（`stars.glsl:25-56,63-115`、`aurora.glsl:83-133`） | 仅静态星、固定色（`stars.glsl:48-83,68`）；极光/流星无 | Astra 省但缺项；lux 成本：极光 8+6 采样、流星约 15 hash。误差：lux 极光非体求交（`aurora.glsl:76-79`），天顶畸变 |
| 水波/视差 | Gerstner+噪声+4 步视差（`gbuffers_water.glsl:102-225`） | Steadfast 波场+Nyquist+距离淡出（`global/water/surface.glsl:296-352`） | Astra 更完整；lux 省在无 footprint。误差：lux 远距波易走样（1/d^0.25 衰减但无 Nyquist 论证） |
| 水体介质 | 单指数吸收（`composite.glsl:119-136`）+vlAlbedo | Beer-Lambert+三档双端谱（`global/water/absorption.glsl:13-60`、`lib/solas_water.glsl:83-109`） | Astra 更细；lux 省在单指数无光谱。误差：lux 深水靠单色 base，缺浅绿→深蓝过渡 |
| 反射 | VNDF+几何 raytrace（`roughReflections.glsl:33-72`、`raytrace.glsl:24-84`） | `global/water/raytrace.glsl`+`lib/sky_reflection_cache.glsl`（mip 0） | Astra 省；lux 贵在 6 次 VNDF。误差：lux 无环境 BRDF 致粗糙金属过亮；Astra 无模糊入射辐射 |
| TAA | YCgCo 8 邻域 ClipAABB（`taa.glsl:50-95`） | 逐角深度校验+3×3 统计+反应式（`program/taa_resolve.fsh:22-135`） | Astra 更严谨；lux 省 8 vs 9 tap。误差：lux 在深度断裂处可接受被遮盖历史（Astra `:28-30` 专门修过） |
| AO | 5/10 采样深度双通道（`ambientOcclusion.glsl:32-79`） | 12 采样黄金角+世界半径+bent normal（`program/ssao.fsh:49-115`） | Astra 更贵但产出 bent normal；lux 省在无世界半径。误差：lux `distScale` 远处半径漂移 |
| 色调映射 | Prism2024 色相保持+校正饱和（`post/tonemap.glsl:100-193`） | 4 算子（`lib/tonemap.glsl:22-160`） | Astra 省（4 条闭式）；lux 贵在通道排序+反函数求导。误差：Prism2024 蓝偏（lux `:94-99` 自承） |
| Bloom/曝光 | 瓦片 6 级+单米普测光（`composite5.glsl:94-147`） | 0.25 捕获+mip 链（`global/post/bloom.glsl:41-48`）+`exposure.glsl` | Astra 更省（2 pass vs 6 瓦片读）。误差：lux 曝光只读单一米普（`:143`），高光易低估 |
| 维度（下界/末地） | `netherCol*0.04`+5 群系色表；16 层 Gerstner 流纹（`color/netherColor.glsl:9-33`、`atmospherics/endSky.glsl:26-53`） | 下界群系调色+九段 compute（`global/dimension/nether.glsl:39-78`）；末地 Kerr 黑洞+吸积盘 | Astra 更重更细；lux 省在单系数与纯解析求值。误差：lux 雾色与光照解耦，末地靠手感指数 |
| 设置系统 | 链式 profile+嵌套 screen+7×4 天气矩阵（`shaders.properties:4-7,43-96`） | `shaders.properties:421-447,700-723`+`lib/color_controls.glsl:6-27` | Astra profile 已链式（全量枚举）；lux screen 嵌套更省行数。误差：lux 无 per-tier 成本校验（Astra `:435-441` 有规则） |

## ⑤ 许可可行性与"重写 vs 抄"边界

**结论：保留所有权利（协议随 BSL，无独立许可证文本）。只读思路、独立重写。**

- 依据 `P:AGREEMENT.txt:1-7`；全包无 `LICENSE`/`README`，结论沿用批次索引。
- 上游关系（`P:AGREEMENT.txt:1-2,6-7`）：内容主要来自 BSL v7.1.05，协议同 BSL。**要用 BSL 谱系内容应走 BSL 自己的授权渠道；lux 不构成更宽的授权。**
- 三档边界：
  1. **可独立重写**：闭式散射形式、`1-|n1+n2|` 脊状噪声、VNDF 球形帽（论文级公开方法）、Planck 黑体（公开物理式）、golden-ratio 抖动相位、网格尾迹构造。重写不得复制函数体文本、注释措辞与常量排布。
  2. **需换来源或自推导**：`metalN/metalK`（`P:shaders/lib/reflections/complexFresnel.glsl:9-29`）、ACES/Prism 矩阵（`P:shaders/lib/post/tonemap.glsl:20-30`）、极光三色常量（`P:shaders/lib/atmospherics/aurora.glsl:41-43`）——应从公开原始出处（ACES 官方、n/k 数据库）取用并登记，不得以 lux 为出处。
  3. **禁止触碰**：`P:shaders/tex/dirt.png`（`shaders.properties:140` 注册为 dirty-lens LUT）、lang 文案、`shaders.properties` 表达式文本。
- 特别提示：`A:shaders.properties:594-602` 与 `P:shaders/shaders.properties:143-151` 逐字相同，**Astra 侧出处是 Solas V2.2b（已登记）**，不得追加 lux 为出处。
- 登记纪律：采纳本报告思路的重写文件按 Astra 惯例在文件头写 "idea only / original Astra implementation"（如 `A:lib/wet_material.glsl:4`）并登记 `THIRD-PARTY.md`。

## ⑥ Top5、暂缓项与天空/雾参数组织方式

### Top5

| 排名 | 事项 | 依据 | 工作量 |
|---|---|---|---|
| 1 | 流星+Planck 黑体星色（③-6/7） | `stars.glsl:11-22,63-115`；Astra 无流星、星色固定（`A:global/atmosphere/stars.glsl:68`） | 小 |
| 2 | 极光模块（③-5） | `aurora.glsl:26-133`；Astra 无模块；批次一 4 包印证 | 中 |
| 3 | 统一随机抖动相位（③-14） | AO `:38` 等 7 处同式；Astra 三处相位独立（`A:program/ssao.fsh:63` 等） | 快赢 |
| 4 | 云低档：6 平面堆叠（③-4） | `clouds.glsl:36-96`；Astra `CLOUD_QUALITY==0` 仍走高度场 | 中 |
| 5 | Prism2024 色相保持 tonemap（③-13） | `post/tonemap.glsl:100-193`+`composite5.glsl:287-307`；Astra `TONEMAP_OPERATOR` 只有 4 档且无校正饱和 | 中 |

### 暂缓项

1. 整体替换 Astra 天空——会放弃 `A:global/atmosphere/sky_gradient.glsl:30-51` 记录的调色板自由度，只作胶光补项。
2. lux 的 AO——批次一判定 SSAO 本身不迁移，且 Astra AO 必须产出 bent normal（`A:program/ssao.fsh:115`）。
3. 金属 n/k ComplexFresnel（③-12）——依赖金属材质通道，已被 `SUMMARY.md` 长期储备收编。
4. lux 的 HSV 分级（`P:shaders/lib/color/colorgrading/transforms.glsl:36-87`）——美术取向，与 Astra LOOK_* 三区调色重叠。
5. World Curvature（`P:shaders/lib/vertex/worldCurvature.glsl:9-12`，需关视锥剔除 `shaders.properties:26-31`）——与 Astra 渲染缩放方向冲突。
6. lux 边框雾（`P:shaders/lib/atmospherics/borderFog.glsl:9-33`）——Astra 已并入 `A:global/atmosphere/fog.glsl:109-116`，无增量。
7. 反照率模式 2（`P:shaders/program/gbuffers_water.glsl:349-351`）——会引入第二套水色定义，仅作美术档评估。

### 天空/雾参数的组织方式（对照 Astra 调色板+天气系统）

| 维度 | lux 的组织方式 | 位置 |
|---|---|---|
| 主菜单 | `screen=` 主网格，6 页签 | `P:shaders/shaders.properties:43` |
| 大气页 | `[ATMOSPHERICS]` = VOLUMETRIC_FOG/CLOUDS/AURORA/STARS/SHOOTING_STARS/FOG，各挂子页 | `:48`（子页 `:52-55`） |
| 云/极光子页 | 云 6 滑条（`:52`）；极光=采样数→亮度→高度→概率→着色类型→两组 RGB（`:53`） | `:52-53` |
| 调色板（旧页） | `[WEATHER_COLOR]` 7 子页×4 通道；`[NETHER_COLOR]` 5 子页；`[END_COLOR]`/`[SKY_COLOR]`/`[WATER_COLOR]`/`[BLOCKLIGHT_COLOR]` | `:74-96`（天气 `:78`，下界 `:89-94`） |
| 命名规则 | `WEATHER_{R,C,D,B,S,M,V}{R,G,B,I}`；`NETHER_{N,V,C,W,B}{R,G,B,I}`；`SKY_{R,G,B,I}`+`SKY_VANILLA` | `P:shaders/lib/settings.glsl:154-217`、`:138-143` |
| 语言 | `screen.ATMOSPHERICS`、`screen.CLOUDS=Clouds Config`、`option.WEATHER_PERBIOME` 带注释 | `P:shaders/lang/en_US.lang:12,57,588-589` |

**lux 默认值矩阵**：天空 `96/160/220` I=1.00（`lib/settings.glsl:140-143`）；水 `180/224/255` I=0.30 A=0.85 F=48.0 MODE=0（`:145-152`）；天气 7 组（雨 176/224/255、冷 216/240/255、沙漠 255/232/180、恶地 255/216/176、沼泽 200/224/160、蘑菇 216/216/255、稀树 224/224/224，亮度 1.20）（`:154-187`）；下界 N/V/C/W/B = 255/96/32、32/236/255、255/32/24、51/216/255、236/216/255，亮度 1.00/0.60/1.20/0.50/0.55（`:189-212`）；末地 120/104/255（`:214-217`）；云 `4/11.0/15.0/1.00/1.0/1.00`（`:243-248`）；极光 `8/6/5.5/12.5/0`（`:227-231`）；`FOG_DENSITY 1.00`、`WEATHER_OPACITY 1.00`、`WEATHER_PERBIOME` 开（`:280-288`）。

**Astra 侧对应位置**：主菜单 `A:shaders.properties:421`；`screen.SKY`/`screen.FOG` 平铺页 `:425,427`；颜色四层嵌套 `screen.COLORS → [SKY_COLORS]/[LIGHT_COLORS]/[DIMENSION_COLORS]/[TONE_COLORS]` `:700-723`；`TINT_*` 默认全 100 `A:lib/settings.glsl:247-290`；调色板 CPU 组装 `A:lib/color_controls.glsl:6-27`、增益应用 `:55-83`。

**差异要点**：lux 是"**天气/群系 → RGB 三元组**"横向矩阵（表驱动，28+20 通道）；Astra 是"**时段/光源 → 标量增益**"纵向嵌套（`COLOR_STYLE`+0-200 百分比），时段混合曲线在 `A:shaders.properties:761-782` 表达式图里而非滑条。两者不冲突：引入 lux 天气矩阵的落点是新增一层 `WEATHER_*` 增益乘在 `A:lib/color_controls.glsl:55-61`（太阳/天空增益）之后，而非替换现有 TINT_*。

## 附录：自抽查（12 条；成稿后重开源文件核对）

核对方式：对每条引用执行 `sed -n '<行号>p' <文件>`（`chk(){ sed -n "${2}p" "$1"; }`），目视比对正文描述与实际内容；"✅"= 行号与内容一致。

| # | 引用 | 核对结果 |
|---|---|---|
| 1 | `P:AGREEMENT.txt:1-2,4,6-7` | 打印 `…heavily based on BSL (v7.1.05)…` / `…made by me (github.com/TechDevOnGitHub).` / `agreement same as BSL's / bitslablab.com/bslshaders/#download` ✅ |
| 2 | `P:shaders/lib/atmospherics/sky.glsl:9,16,26,36` | `9 vec3 GetSkyColor(...)` / `16 …smoothstep(0.0, 0.5, Lift(sunHeight, 2.0));` / `26 …mieFactor = sunDot * (1.0 - sunHeight) * sunHeightLifted;` / `36 …exp((skyColor - 1.0) * y * 7.0);` ✅ |
| 3 | `P:shaders/lib/atmospherics/fog.glsl:23,41,44` | `23 top = exp(-1.4*halfNdotU*halfNdotU*(1.0+sunVisibility)*(1.0-rainStrength));` / `41 fog = viewDist*FOG_DENSITY/256.0;` / `44 fog = 1.0 - exp(-fog*eBS);` ✅ |
| 4 | `P:shaders/lib/atmospherics/volumetricLight.glsl:59,86` | `59 float minDist = exp2(i + dither) - 0.9;` / `86 if (depth0 < minDist) sample0 *= color;` ✅ |
| 5 | `P:shaders/lib/atmospherics/clouds.glsl:62,66,93` | `62 for (int i = 0; i < 6; i++)` / `66 planeCoord = worldPos * ((CLOUD_HEIGHT + (i+dither)*1.6)/worldPos.y) * 0.004;` / `93 …1. - exp2(-(cosT - 0.1)*40.0)…` ✅ |
| 6 | `P:shaders/lib/atmospherics/aurora.glsl:85,87,112` | `85 float probabilityHash = Hash11(worldDay * 239.996322973);` / `87 …probabilityHash > AURORA_PROBABILITY) return vec4(0.0);` / `112 …worldPos.xz * (AURORA_HEIGHT + (i+dither)*iMult)/worldPos.y * 0.0005;` ✅ |
| 7 | `P:shaders/lib/atmospherics/stars.glsl:53,63,74` | `53 star *= RadiationBlackbody(Hash21(gridID*1258.35)*37000.0 + 3000.0);` / `63 vec3 GetShootingStarLayer(...)` / `74 …SHOOTING_STARS_SCALE…` ✅ |
| 8 | `P:shaders/program/gbuffers_water.glsl:200,345,356,419,447,512` | `200 float height = (GetWaterHeightMap(parallaxPos, viewPos) - 0.5)*0.24;` / `345 #if WATER_MODE == 0` / `356 vlAlbedo = mix(vec3(1.0), albedo.rgb, sqrt(albedo.a))*(1.0-pow(albedo.a,64.0));` / `447 if (water > 0.5 \|\| (translucent > 0.5 && albedo.a < 0.95))` / `512 else` ✅ |
| 9 | `P:shaders/lib/post/tonemap.glsl:100,111,163,186` | `100 vec3 TonemapPrism2024(vec3 color)` / `111 tsCol = …Tonescale(color*ACESInputMat)*ACESOutputMat;` / `163 color[minIdx] = (1.0 - S)*maxC;` / `186 float kDesat = …` ✅ |
| 10 | `P:shaders/lib/reflections/complexFresnel.glsl:45` + `P:shaders/program/deferred.glsl:160` | `45 int metalIndex = int(f0 * 255.0) - 230;` / `160 if (f0 >= 0.9 && f0 < 1.0) fresnel3 = ComplexFresnel(fresnel, f0);` ✅ |
| 11 | ③-14 的 7 处同相位；`P:shaders/shaders.properties:143,149` vs `A:shaders.properties:594,602` | grep `frameTimeCounter / PHI * 13.333` 命中 `ambientOcclusion.glsl:38`、`volumetricLight.glsl:48`、`clouds.glsl:44`、`aurora.glsl:98`、`roughReflections.glsl:54`、`raytrace.glsl:39`；`143 variable.float.tAmin=frac(sunAngle - 0.033333333)` / `A:594 variable.float.astraSolasTAmin=frac(sunAngle - 0.033333333)`（逐字同式）✅ |
| 12 | `A:global/atmosphere/fog.glsl:67,147,208` / `A:global/atmosphere/stars.glsl:68` / `A:program/ssao.fsh:63` | `67 float fog_valley_mist(float worldY)` / `147 atmosphereFog *= 1.10 + 2.2*astraRainFactor*caveFogTransition;` / `68 return 40.0 * star * vec3(0.38, 0.4, 0.5);` / `63 float angle=float(i)*2.39996323;` ✅（三处抖动相位各异，佐证 ③-14） |

补充核对（非行号类）：全包 `find` 计数与 ① 体量一致（142 外壳/51 lib/24 program）；全包搜许可证只命中 `AGREEMENT.txt`。**未覆盖**：按成本纪律未逐个读贴图/噪声/LUT（`tex/dirt.png` 仅登记用途）；`powderSnowFog.glsl`、`vertex/waving.glsl` 只读到函数级；`gbuffers_block|entities|hand|textured.glsl`（合计约 1400 行）与 `composite4.glsl` 内部细节未展开——它们与已读文件共用 `GetLighting`/`GetMaterials` 模板，判断无 ③ 增量。
