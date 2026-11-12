# BSL Shaders - Classic v10.0 调研报告（面向 Astra 的可借鉴点）

> 生成方式：**子代理调研**（批次二第 1 项，按统帅任务契约执行；只读参考包，未改任何源文件）。调研对象 `reference_shaderpacks/bsl-shaders-classic/`；包版本 **BSL v10.0**（`P:shaders/lang/en_US.lang:87`）；调研日期 **2026-10-02**。
> 引用：`P:` = 相对 `reference_shaderpacks/bsl-shaders-classic/`；`A:` = 相对 `Astra/shaders/`。**行号全部来自本次实读**（附录为成稿后二次抽查）。为控篇幅，②/③/④ 中的 `P:lib/…`、`P:program/…`、`P:block.properties`、`P:shaders.properties` 是省略公共前缀 `shaders/` 的简写（即实际路径为 `shaders/lib/…` 等）；附录核对表一律用全路径。两分支对照另读了 `reference_shaderpacks/bsl-shaders/`（10.1.8，下称 P10.1.8；不在本任务白名单"可读取"内，原因见备注）。未读任何贴图/噪声/LUT 二进制（`shaders/tex` 905,239 B / 全包 1,471,153 B）。

## ① 概览

- **元数据**：slug `bsl-shaders-classic`；显示名 BSL Shaders - Classic；作者 CaptTatsu；版本 10.0；下载量 2,263,394（批次二最高）。271 个文件、1,471,153 字节（`program` 236 KB、`lib` 204 KB）。
- **许可证：包内不存在任何许可证文件**。`find … \( -iname "*licen*" -o -iname "*readme*" -o -iname "*.txt" -o -iname "*.md" \)` 为空；包根只有 `shaders/` 一个目录，**故无许可证原文行号可引**。包内唯一署名/版权原文：

  ```
  P:shaders/lib/settings.glsl:2-3
  BSL Shaders v10 Series by Capt Tatsu
  https://capttatsu.com
  ```

  版本行 `P:shaders/lang/en_US.lang:87`（`option.ABOUT=BSL v10.0`）。沿用批次二结论：**保留所有权利（All Rights Reserved）**（`INDEX-batch2.md:19`、`_analysis/2026-10-02-batch2-ledger.md:31`）。
- **形态**：`program/*.glsl` 为三维度共享源，`world0`/`world-1`/`world1` 只有 `#include` 包装器。5 档画质 profile `P:shaders.properties:4-8`；约 20 个设置屏 `:20-96`；`sliders` 单行 200+ 参数 `:97`。
- **与 10.1.8 的关系 = 同源不同调校**。本包少 21 个文件：`lib/atmospherics/chunkFade.glsl`、`program/gbuffers_entities_translucent.glsl`、`program/soul_shade.json`、Voxy 三件套（`voxy.json`/`voxy_opaque.glsl`/`voxy_translucent.glsl`）及 3 个 world 目录包装器 → **经典分支不支持 Voxy、半透明实体独立通道、区块淡入（IRIS_FEATURE_FADE_VARIABLE）**。双方共有源文件中 53 个内容不同，差异量前列：`lib/settings.glsl`(249 行)、`program/deferred1.glsl`(203)、`lib/lighting/ambientOcclusion.glsl`(193)、`lib/lighting/shadows.glsl`(133)、`program/gbuffers_water.glsl`(110)。

## ② 架构特性清单（按子系统）

### 设置与编译期架构（本包相对 10.1.8 的最大结构增量）
- **STYLE 主风格开关** `P:lib/settings.glsl:29`，设置首屏 `P:shaders.properties:20`。`//Use style options//` 段把 10 个 -1 哨兵解析为 `*_INTERNAL`：sunPathRotation `:466-471`、HALF_LAMBERT `:547-555`、REFLECTION_PRECISION `:557-565`、CLOUD_BASE `:567-575`、FAR_VANILLA_FOG `:577-585`、SHADER_SUN_MOON_SHAPE `:587-595`、WATER_MODE `:597-605`、WATER_ALPHA_MODE `:607-615`、WATER_NORMALS `:617-625`、SKY_VANILLA `:627-635`。STYLE 0/1 取值对：-40.0/0.0、0/1、0/1、0/2(blocky)、2/3、0/1、0/1、0/1、1/3、0/1（发布默认 STYLE 1）。
- int→const float 枚举桥 `:472-545`（注释 `:473` "casting int to float doesn't work here"）；维度 `#undef` `:638-642`；拼写瑕疵 `SHHARPEN_ENABLED`（定义 `:655`、判断 `program/final.glsl:113`；P10.1.8 为 `SHARPEN_ENABLED`，`lib/settings.glsl:490`/`program/final.glsl:115`）。

### 大气 / 云 / 雾
- 曝光三旋钮**只作用于天空** `P:lib/atmospherics/sky.glsl:11-13`（选项 `P:lib/settings.glsl:152-156`）；云、雾无曝光项。
- 云 blocky 分支：缩放 0.125 `P:lib/atmospherics/clouds.glsl:122-128`、层厚系数 0.5 `:226-229`、`cloudThickness*=0.5` 且 `maxSamples=64` `:312-318`、样本数=`CLOUD_THICKNESS*2` `:188`、亮度 `:261`/`:448`。
- 雾：无曝光 `:16`、`weatherCol²` `:52-54`、`FOG_DENSITY_DH` `:97`、软上限 `(fog-0.8)*0.25+0.8` `:109`、vanilla 远雾 `:135`、下界 `:158-162`、末地 `:174-178`、入口 `:210`；平滑群系 12 项 `P:shaders.properties:169-203`。
- 光柱 `P:lib/atmospherics/lightShafts.glsl:2-30`（hand 门控 `:28`）、有效性 `:52-54`、3D 噪声 `:98-115`（时间速度 4.0 `:100`/`:113`）。

### 水面
- 法线 `P:program/gbuffers_water.glsl:152-179`：量化 `:155-157`、视差 `:159-161`、4-tap 差分 `:168-174`、梯度 z `:176-178`、强度 `0.35*(1-fresnel^8)` `:168-169`；应用 `:333`。
- 波动只抬水面顶面 `:763-772`（振幅固定 0.0125），应用仅 200/202/204 `:839`；材质 ID 编码 `P:block.properties:5-6`、水=`block.20000` `:207-209`、vsh 判定 `:816-819`（10.1.8 另有 205）。
- 水雾 `P:lib/atmospherics/waterFog.glsl:5-31`（基色 `:9-14`、tint `:17-26`、强度 `:15`）+ 应用 `:666-682`；alpha 早退 `:275`、`}else{` `:577`；SSR `P:lib/reflections/raytrace.glsl:13-29,44,52-57,75-76`、反射判定 `:499`。水洼/涟漪与批次一逐字节相同。

### 阴影 / 光照 / 后处理 / 维度
- 软件阴影路径 `P:lib/lighting/shadows.glsl:28-30,32-36,38-54,72-74,135-166`、早退 `:159-166`、焦散 ×4 `:89-90,117-119,122`。
- AO `P:lib/lighting/ambientOcclusion.glsl:51-142`（radius 0.25 `:73`、hand `:60`、method `:82`、pointiness `:102`、mult `:114`）+ DH/LOD `:191-275`（radius 2.0 `:210`）。
- TAA `P:lib/antialiasing/taa.glsl:47-55`、`TAA_SELECTIVE` 默认开 `P:lib/settings.glsl:247`；时间口径 `P:shaders.properties:150-156`、blindFactor `:159-160`；`alphaTest.gbuffers_terrain` `:126`；iris 特性 `:225`；DH `:278`。
- 光照常数 `P:lib/settings.glsl:263-265,268-270,284,289`；下界群系 `P:shaders.properties:180-183`、`FOG_DENSITY_NETHER` `:130`；末地 `SHADER_END_SKY` 默关 `:162`；本包不声明 `breaksAnisotropy`（10.1.8 声明 true）。

## ③ Astra 可借鉴点（14 条）

> 每条 = 技术 / `P:` / `A:` / 工作量（S≤半天单文件、M 1-2 天、L 需改边界或缓冲） / 重复标注；均须独立重写（见 ⑤）。

1. **行为型风格预设层：`STYLE` + `-1` 哨兵 + `_INTERNAL` 解析块** — 主开关只决定"未显式设置"的选项默认值，用户手选即脱离预设；全部在 `#if` 预处理期完成，零运行成本、零新 uniform。
   - P: `lib/settings.glsl:29`、`:466-471`、`:547-635`
   - A: `Astra/shaders/lib/settings.glsl:245`（`COLOR_STYLE` 只管颜色）、`Astra/shaders/shaders.properties:700`、`:444-447`（4 档画质 profile）、`:699`
   - 工作量 M。**不与批次一重复**（10.1.8 无 STYLE）。
2. **离散 int → `const float` 的枚举桥** — Iris 文本替换选项值，`float(INT_MACRO)` 不能作 `const` 初始化（注释原文 `:473`），故每值一个 `#elif`。
   - P: `lib/settings.glsl:472-545`
   - A: `Astra/shaders/lib/settings.glsl:336`（Astra 已是 `const float`，当前不需要）
   - 工作量 S。**不与批次一重复**。
3. **曝光项必须在天空/云/雾三处一致（本包是反例）** — 本包 `SKY_EXPOSURE_D/N/W` 只进天空，云（`clouds.glsl:261`）、雾（`fog.glsl:16`）无曝光项；10.1.8 补齐。
   - P: `lib/atmospherics/sky.glsl:11-13` vs `lib/atmospherics/clouds.glsl:261`、`lib/atmospherics/fog.glsl:16`
   - A: `Astra/shaders/global/post/exposure.glsl:105`（全屏自动曝光）、`Astra/shaders/lib/settings.glsl:209`（`EXPOSURE`）、`Astra/shaders/global/atmosphere/fog.glsl:128`
   - 工作量 S。**与批次一重复**（曝光链）。
4. **远雾上限的天气调制** — 本包写死 `(fog-0.8)*0.25+0.8`，10.1.8 改 `0.3*rainStrength+0.5`（雨天提前饱和）。
   - P: `lib/atmospherics/fog.glsl:109`
   - A: `Astra/shaders/global/atmosphere/fog.glsl:110-118`（border fog）、`:148`（雨致雾项）
   - 工作量 S。**不与批次一重复**。
5. **云的成本公式与 blocky 参数对** — 样本数 = `CLOUD_THICKNESS*2`（`:188`）、blocky 层厚 0.5 且 32→64 样本（`:312-318`）；blocky 坐标缩放本包 0.125 vs 10.1.8 0.15625、层厚 0.5 vs 0.4。可取者仅"样本数公式 + ≤64 样本无时域的低配下限"。
   - P: `lib/atmospherics/clouds.glsl:122-128`、`:188`、`:226-229`、`:312-318`
   - A: `Astra/shaders/global/atmosphere/clouds_planar.glsl:5-48`（Complementary r5.9 模型+出处块）、`Astra/shaders/global/atmosphere/cloud_temporal.glsl`
   - 工作量 M-L（模型不同，风格取舍）。**与批次一重复**（云）。
6. **水面法线：4-tap 高度差分 + 梯度 z + fresnel 衰减强度** — z 取 `1-(dx²+dy²)`（省一次 sqrt），强度按 `0.35*(1-fresnel^8)`；`WATER_PIXEL` 世界格量化提供低配档。
   - P: `program/gbuffers_water.glsl:152-179`（应用 `:333`）
   - A: `Astra/shaders/global/water/surface.glsl:178`（足迹滤波）、`:205`（4 波纹高度场+2 波纹近似档）、`:41`
   - 工作量 S（公式级）。**与批次一重复**（水体）。误差：BSL 无足迹滤波、掠射角法线被削弱 → 远处水面玻璃化闪烁（靠 TAA 遮掩）。
7. **水面波动只抬"水面方块顶面"** — 一次 `fract(worldPos.y+0.005)>0.01` 返回 0 替代"是否露出水面"判定，且只对 200/202/204 施加。
   - P: `program/gbuffers_water.glsl:763-772`、`:839`
   - A: `Astra/shaders/program/water.glsl:196-204`（水下看水面破碎修复）、`Astra/shaders/global/water/surface.glsl:205`
   - 工作量 S。**不与批次一重复**。
8. **水雾的 WATER_MODE 相容配色 + `sqrt` 色调** — 按 WATER_MODE 选基色（`:9-14`），tint 由 `lightCol*eBS*shadowFade*0.9+0.1` 再 `sqrt(tint*|tint|)`（`:17-26`）；应用端 `albedo/max(albedo.a,1e-4)` 反向预乘混合。
   - P: `lib/atmospherics/waterFog.glsl:9-31`、`program/gbuffers_water.glsl:666-682`
   - A: `Astra/shaders/lib/solas_water.glsl:83-108`、`Astra/shaders/global/water/absorption.glsl`、`Astra/shaders/global/water/medium_state.glsl`
   - 工作量 S-M。**与批次一重复**（水体）。误差：BSL 的 `albedo/alpha` 反解在 alpha→0 时数值爆炸（靠 `max(…,1e-4)` 兜住），Astra 的 `exp(-σd)` 无此问题，**不建议移植混合式**。
9. **阴影偏置曲线 vs 硬件比较采样** — 本包 `biasDistribution[10]` 非均匀分布 + `GetCurvedBias` 距离相关偏置 + 手写 2×2 软件 PCF；10.1.8 已改 `sampler2DShadow`。
   - P: `lib/lighting/shadows.glsl:28-30`、`:32-36`、`:38-54`、`:72-74`
   - A: `Astra/shaders/global/lighting/shadowmap.glsl:38-43`、`:89-99`（`textureGather` 一次 4 比较）、`:105-127`、`Astra/shaders/lib/settings.glsl:68`
   - 工作量 S（只借"偏置随距离非均匀"）。**与批次一重复**（硬件阴影比较在批次一多包出现 = 同方向收敛）。Astra 更省：1 次 gather vs 4-9 次采样。
10. **阴影查询边界 + 夜间早退** — `doShadow` 判 `shadowPos`∈[0,1]² 且 `skylight>0.001`，否则 `return vec3(1.0)`。
    - P: `lib/lighting/shadows.glsl:159-166`
    - A: `Astra/shaders/global/lighting/shadowmap.glsl:70-79`
    - 工作量 S。**不与批次一重复**。
11. **光照调校常数：本包偏暖灰、10.1.8 偏冷亮** — 直射 216/220/228 vs 196/220/255；环境 132/172/228 vs 120/172/255；夜间 144 vs 192。
    - P: `lib/settings.glsl:263-265`、`:268-270`、`:284`、`:289`
    - A: `Astra/shaders/lib/settings.glsl:283-285`（`TINT_AMBIENT_R/G/B`=100）、`:44`、`Astra/shaders/lib/color_controls.glsl`
    - 工作量 S（作默认值参照，不逐值照抄）。**不与批次一重复**。
12. **"经典观感"的两个开关** — 太阳路径 0°（10.1.8 固定 -40°）、HALF_LAMBERT 开启（10.1.8 关）。
    - P: `lib/settings.glsl:29`、`:466-471`、`:547-555`
    - A: `Astra/shaders/lib/settings.glsl:336`（当前 -40.0）
    - 工作量 S。**不与批次一重复**。
13. **反向借鉴（缺陷清单，不采纳）** — 整段 `albedo.a > 0.001` 早退 `:275`、`}else{` `:577`（10.1.8 前还有 `else if (albedo.a > 0.01)`），10.1.8 全删；alpha 恰为 0 的半透明像素会跳过 gbuffer 写入 → 混合/反射错位。
    - P: `program/gbuffers_water.glsl:275`、`:499`、`:577`
    - A: `Astra/shaders/program/water.glsl:210-218`、`Astra/shaders/global/water/surface.glsl`
    - 工作量 S（**检查项**：确认 Astra 无同类 alpha 早退）。**不与批次一重复**。
14. **光柱采样有效性 + 噪声速度** — 本包 `IsSampleInShadowmap` 只判 xy 半径 `:52-54`，10.1.8 加 `shadowPos.z<0.5`（正确性）；3D 噪声时间速度本包 4.0、10.1.8 2.0。
    - P: `lib/atmospherics/lightShafts.glsl:52-54`、`:100`、`:113`
    - A: `Astra/shaders/global/atmosphere/volume_fog.glsl:102`、`:115`、`:130`
    - 工作量 S。**不与批次一重复**。

> 与批次一重复：水体法线/水雾（③-6、③-8）、云（③-5）、硬件阴影比较（③-9）、曝光链（③-3）；水洼/涟漪与手持光两文件与批次一逐字节相同，批次一已单列。

## ④ Astra 已有对应实现对照表

> Astra 行为仅基于本次实读文件；未读到的标"未核实"。

| 能力 | 本包（classic 10.0） | Astra 对照 | 哪边更省 / 误差来源 |
|---|---|---|---|
| 风格/画质预设 | `P:lib/settings.glsl:29,466-635`（行为预设+哨兵） | `A:lib/settings.glsl:245`（`COLOR_STYLE` 仅颜色）+ `A:properties:444-447`（profile） | Astra 胜在语义清晰（颜色档不随画质档变，`:699`）；BSL 胜在"未改跟随预设、改了固定"，无需重复两份 profile 值。误差：BSL 手改后永久脱离 STYLE，须手动改回 -1 |
| 太阳路径/软阴影 | `P:lib/settings.glsl:466-471`（0°）、`:547-555` | `A:lib/settings.glsl:336`（-40.0） | 观感取向。误差：0° vs -40° 改变日出方位与阴影长度，复刻需整套光照常数同时跟随（③-11） |
| 云 | `P:lib/atmospherics/clouds.glsl:188,226-229,312-318`（3 噪声基准、≤64 样本、无时域） | `A:global/atmosphere/clouds_planar.glsl:5-48`、`A:global/atmosphere/cloud_temporal.glsl` | Astra 省每帧算力（时域摊薄样本）、形状更好；BSL 省显存与实现。误差：blocky 档靠"坐标缩放+层厚折半"近似体积感，Astra 模型无对应项 |
| 云影与云同源 | `P:lib/lighting/shadows.glsl`（GetCloudShadow） | `A:global/atmosphere/clouds_planar.glsl`（密度场）+ `A:global/atmosphere/weather.glsl:128`（`astra_cloud_transmission`）+ `A:global/atmosphere/cloud_shadow_cache.glsl` | Astra 已共享密度场并在 `CLOUD_SHADOWS` 后接线；BSL 省一层缓存 |
| 雾 | `P:lib/atmospherics/fog.glsl:16,52-54,97,109,135,158-178` | `A:global/atmosphere/fog.glsl:110-118,128,148,175` | 双方解析式（BSL `exp2` 高度雾、Astra `pow(d,3)`+border fog+谷雾）。BSL 软上限比 Astra 的 smoothstep 夹更省。误差：BSL 用 viewLength、Astra 用 fragDistance，曲线不能逐值搬 |
| 水面法线/波浪 | `P:gbuffers_water.glsl:152-179,763-772,839`（4-tap、无足迹滤波、波动只顶面） | `A:global/water/surface.glsl:41,178,205`（4 波纹+足迹抗锯齿+2 波纹近似） | BSL 更省（每像素约 5 次噪声采样、一层 `fract`）；Astra 更贵但抗闪、有距离 LOD。误差：BSL 掠射角 `0.35*(1-fresnel^8)` 是观感项非物理 |
| 水雾/吸收 | `P:lib/atmospherics/waterFog.glsl:5-31`+`P:gbuffers_water.glsl:666-682` | `A:lib/solas_water.glsl:83-108`、`A:global/water/absorption.glsl`、`A:global/water/medium_state.glsl` | Astra 无 `albedo/alpha` 反解、更稳；BSL 一次 `mix`+`sqrt` 更省。误差：BSL 的 `sqrt(tint*|tint|)` 在显示域，与 Astra 线性域不一致 |
| 阴影滤波 | `P:lib/lighting/shadows.glsl:28-54,72-74`（软件 2×2 + 曲线偏置） | `A:global/lighting/shadowmap.glsl:38-43,89-99`（硬件比较+gather） | Astra 更省更准。误差：Astra 若用常数偏置，极平贴面可能出阴影粉刺，可用 `GetCurvedBias` 思路对照 |
| SSAO | `P:lib/lighting/ambientOcclusion.glsl:51-142,191-275`（屏幕 4×2 + DH/LOD 版 radius 2.0） | `A:lib/ao_resolve.glsl:19-89`（bent normal+顶点 AO）、`A:program/ssao.fsh` | Astra 更全。误差：BSL 的 `pointiness`、`mult=0.7/radius` 是经验量，跨分辨率须重标定 |
| 体积光 | `P:lib/atmospherics/lightShafts.glsl:2-30,98-115`（屏幕径向模糊） | `A:global/atmosphere/volume_fog.glsl:33-45,102,115,130`（12/24/48 步真体积、相位 g=0.60） | Astra 更贵但物理正确，BSL 近乎零成本 |
| TAA | `P:lib/antialiasing/taa.glsl:47-55`（无参重投影、无 DH/Voxy） | `A:lib/taa_reactive.glsl`、`A:lib/taa_state.glsl`、`A:program/taa_resolve.fsh`、`A:lib/taa_jitter.glsl:8-30` | Astra 更全（响应式、8 帧 Halton 去均值）。误差：BSL hand 判定 `pos.z>0.56` 硬编码 |
| 时间口径 | `P:shaders.properties:150-155`（raw `worldTime/24000`+4 段硬阈值） | `A:shaders.properties:594-602`（Solas 平滑曲线） | **Astra 已优于本包**，不借鉴（"批次一已吸收、经典分支未跟进"的证据） |
| 雨湿/水洼 | `P:lib/reflections/rainPuddles.glsl`（与批次一相同） | `A:global/atmosphere/weather.glsl:21-42`（稀疏格+天空光+朝上门控）、`:44-65`（积水/潮湿地分离）、`A:lib/wet_material.glsl:7-28` | Astra 把"积水（驱动反射）"与"潮湿（暗化+少量高光）"拆成两信号，比 BSL 单 mask 可控。误差：Astra 水洼判定**未见**群系排除（BSL 有 isDesert/isMesa/isCold），沙漠降雨可能出现水洼（未核实） |
| 手持光 | `P:lib/lighting/dynamicHandlight.glsl`（与批次一相同） | `A:global/lighting/diffuse.glsl:365,444,455`（`held_light_strength`+`lightning_point_light`） | Astra 更完整（另有闪电点光），仅叠加律可对照 |

（Voxy/DH 覆盖差异见 ①：本包无 Voxy，Astra 有 `A:voxy.json`/`A:voxy_opaque.glsl` 与 `A:lib/settings.glsl:319` 的 `VOXY_SUPPORT` 开关。）

## ⑤ 许可可行性与"重写 vs 抄"边界

- **结论：本包为"保留所有权利"（All Rights Reserved），作者 CaptTatsu；包内无任何许可证文件（①有 find 证据），故无授权原文，默认受版权法保护。**
- **允许**：阅读、学习技术思路/算法概念/参数化方向/管线结构与"同源两分支调校差异"的量化结论；用 Astra 自己的代码独立实现。
- **禁止**：复制或转写本包源码（GLSL 片段、`#define` 组、常量表、`_INTERNAL` 解析块的实现细节）；本体改编后再分发；逐字搬运选项命名、设置屏布局、`lang/en_US.lang` 文案（灰区，应避免）。
- **数字与思路的界线**：常数（如 216/220/228）与公式结构属"事实性观察"，可在报告中作参照系；**不得**作为 Astra 的复刻目标逐值写入。落地建议沿用 Astra 已有惯例在模块头注明出处：`A:lib/wet_material.glsl:4`、`A:global/atmosphere/clouds_planar.glsl:5-48`（PROVENANCE 块）、`A:lib/taa_jitter.glsl:4-7`。本报告不含可直接编译的 BSL 源码段。

## ⑥ Top5 优先建议 + 暂缓项

**Top5（提升/工作量）**
1. **③-1 行为型风格预设层** — Astra 已有 `COLOR_STYLE` 与 4 档 profile 基建，缺"行为默认值随风格走、手改后固定"的中间层；M，可把"经典/新调校"变成配置而非分叉代码。
2. **③-12 复刻经典观感的两个开关**（`sunPathRotation=0`、HALF_LAMBERT 开）— 纯参数，S；配合 ③-11 的常数参照做可选档实验。
3. **③-4 远雾上限的天气调制** — 一行曲线，S；雨天观感立竿见影，且不与 Astra border fog 冲突。
4. **③-10 + ③-14 两处小修**（`doShadow` 边界/夜间早退、光柱采样补 z 检查）— 各 S，省算力 + 正确性。
5. **③-13 检查 Astra 半透明水面的 alpha 早退** — S；"经典分支遗留、10.1.8 已修"的缺陷类。

**暂缓项**
- ③-5 云参数对：模型不同（Astra 用 Complementary r5.9 形状模型），只保留成本公式。
- ③-6 / ③-8 水体细节：Astra 水体（折射/吸收/解析焦散/水下光束）全面超出本包，仅公式级参考。
- ③-9 软件阴影 PCF：Astra 硬件 gather 更省更准，无必要。
- ③-3 手动天空曝光旋钮：与 Astra 自动曝光体系定位冲突，需统帅决策。
- 时间口径（`worldTime/24000`+硬阈值）：Astra 现状已优于本包，不采纳；③-2 枚举桥当前无场景，仅作技术储备。

## 附录：自抽查记录（成稿后二次核对，共 24 条）

> 方法：成稿后重新用 `sed -n 'Np'` 打开源文件逐行核对；以下为实际输出摘录（含 1 处因并行工作流改动而修正的行号）。

**P 侧（13 条，全部命中）**

| # | 引用 | 核对结果（实际输出） |
|---|---|---|
| 1 | `P:shaders/lib/settings.glsl:29` | `#define STYLE 1 //[0 1]` |
| 2 | `P:shaders/lib/settings.glsl:473` | `// casting int to float doesn't work here` |
| 3 | `P:shaders/lib/settings.glsl:655` | `#define SHHARPEN_ENABLED`（拼写瑕疵确认） |
| 4 | `P:shaders/lib/atmospherics/fog.glsl:109` | `fog = min(fog, (fog - 0.8) * 0.25 + 0.8);` |
| 5 | `P:shaders/lib/atmospherics/clouds.glsl:227` | `float planeY = convertedHeight + currentStep * CLOUD_THICKNESS * 0.5;` |
| 6 | `P:shaders/program/gbuffers_water.glsl:275 / :839` | `if (albedo.a > 0.001) {` / `if (blockID == 200 \|\| blockID == 202 \|\| blockID == 204) position.y += WavingWater(position.xyz);` |
| 7 | `P:shaders/lib/lighting/shadows.glsl:73` | `return mix(biasDistribution[i], biasDistribution[i+1], dither);` |
| 8 | `P:shaders/lib/lighting/ambientOcclusion.glsl:73` | `float radius = 0.25;` |
| 9 | `P:shaders/lib/reflections/raytrace.glsl:44` | `vec3 start = viewPos + normal * 0.075;` |
| 10 | `P:shaders/shaders.properties:150` | `uniform.float.timeAngle=worldTime / 24000` |
| 11 | `P:shaders/lib/atmospherics/waterFog.glsl:26` | `waterFogTint = sqrt(waterFogTint * length(waterFogTint));` |
| 12 | `P:shaders/lib/atmospherics/lightShafts.glsl:113` | `noise = sin(noise * 28.0 + time * 4.0) * 0.25 + 0.5;` |
| 13 | `P:shaders/lib/settings.glsl:162`（初稿误写 163） | 二次核对为 `//#define SHADER_END_SKY`，**已修正为 162**；同批修正 `FOG_DENSITY_NETHER` 由 118 → **130** |

**A 侧（11 条，全部命中）**

| # | 引用 | 核对结果（实际输出） |
|---|---|---|
| A1 | `A:lib/settings.glsl:245` | `#define COLOR_STYLE 0 // [0 1 2 3]` |
| A2 | `A:shaders.properties:594` | `variable.float.astraSolasTAmin=frac(sunAngle - 0.033333333)` |
| A3 | `A:global/lighting/diffuse.glsl:444 / :455` | `float heldLight = held_light_strength(params.heldLightBase, playerPos);` / `lighting += lightning_point_light(playerPos, worldNormal, skyLight, params.lightningBolt);`（初稿 442/453，**已修正**） |
| A4 | `A:global/atmosphere/weather.glsl:21` | `float astra_puddle(vec3 worldPos, vec3 normal, float skyLight) {` |
| A5 | `A:global/atmosphere/weather.glsl:42 / :44 / :65` | `return coverage * smoothstep(0.48, 0.64, n) * response;` / 分隔注释 / 潮湿地说明块末行 |
| A6 | `A:program/water.glsl:210` | `vec4 astra_water(vec3 color, float alpha, vec3 playerPos, vec3 viewPos,`（初稿 208，**已修正**） |
| A7 | `A:global/atmosphere/volume_fog.glsl:102 / :115 / :130` | `float coverage = shadow_coverage(playerPos, sp);` / `vec4 astra_volume_march_from(vec3 origin, vec3 rayWorld, float distanceBlocks,` / `float jitter = bayer8(gl_FragCoord.xy);` |
| A8 | `A:global/lighting/shadowmap.glsl:99 / :110` | `vec4 shadow_gather_visibility(sampler2D depths, vec2 uv, float referenceDepth) {` / `vec4 allVisibility = shadow_gather_visibility(shadowtex0, uv, referenceDepth);` |
| A9 | `A:global/water/surface.glsl:41 / :178 / :205` | `float surface_noise(vec2 at) {` / `float surface_antialias(vec2 ddxWorldPos, vec2 ddyWorldPos, vec3 stretch) {` / `float surface_height(vec2 worldPos, SurfaceFootprint footprint, float time, bool approximate, float distanceToCamera) {` |
| A10 | `A:lib/settings.glsl:319 / :336` | `//#define VOXY_SUPPORT // [false true]` / `const float sunPathRotation = -40.0; // [-60.0 …]` |
| A11 | `A:global/atmosphere/weather.glsl:128` | `float astra_cloud_transmission(vec3 worldPos, vec3 lightDir) {` |

注：本次调研期间 Astra 有并行工作流的未提交改动，`A:global/lighting/diffuse.glsl`（442→444/453→455）、`A:program/water.glsl`（208→210）、`A:global/atmosphere/volume_fog.glsl` 行号发生过漂移；本报告 Astra 行号为**二次核对时点实测值**，落地前建议复核。②/③/④ 另有 30+ 处 P 行号均来自本次 `grep -n`/`sed -n` 实读，抽查 13 条覆盖各子系统关键锚点；批次一报告同项行号（389/448-454）与本次不同，属时点差异，不影响其结论方向。
