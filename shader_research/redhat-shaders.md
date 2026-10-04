# redhat-shaders 调研（面向 Astra 的可借鉴点）

> **生成方式**：子代理调研（只读 `reference_shaderpacks/redhat-shaders/`、`Astra/shaders/`、`shader_research/`、`docs/`，只写本文件）。
> **包版本**：元数据 34.3.1；包内自报 `P:shaders/lang/en_US.lang:442` = `v34.3`；`P:Changelog.txt:3` 只到 `v34.2`（不一致，以 lang 为准）。
> **调研日期**：2026-10-02。
> **引用约定**：`P:` = 相对 `reference_shaderpacks/redhat-shaders/`；`A:` = 相对 `Astra/shaders/`。行号全部来自本次实际读取；附录为成稿后重开的抽查。
> **成本纪律**：未逐个读贴图/噪声/LUT；`lib/color/data/*.glsl` 只读首尾与统计。

## ① 概览

| 项 | 实测/原文 |
|---|---|
| slug / 名 | `redhat-shaders` / RedHat Shaders；作者 MLGImposter（`P:Credits.txt:7`） |
| 版本 / 下载量 | 34.3.1 / 974,154（批次索引） |
| 许可 | **Chocapic13 Sharing Agreement**（Modrinth 标 `LicenseRef-Chocapic13-Agreement`）；原文 `P:Agreement.txt`，2410 B / 39 行 |
| 血统 | C13 派生：`P:Agreement.txt:8`（协议由 Choca_13 撰写）、`P:Credits.txt:9`（"Based on the v5.1.2"）、`P:shaders/gbuffers_terrain.fsh:12-13`（"From Chocapic13' shaders" / "Based on Chocapic13' and CYBOX"） |
| 其它上游 | BSL（`P:Credits.txt:8`，明文"Gave me permission"）、CYBOX（`:10`）、Robobo1221（`:11`）、Conquest 自动曝光/色差（`:13`）、TME（`:15`） |
| 体量（实测） | 包总计 1,071,499 B；`shaders/lib` 626,623 B、`shaders/program` 260,638 B；`lib/color/data/data1..4.glsl` 各 ~102.6 KB（4 份 ≈ 全包 38%），为逐条 `#define` 的逐小时色表 |
| 维度副本 | 根（主世界）32 文件、`world-1/`（下界）28、`world1/`（末地）28；各自 include 同名 program 副本（`P:shaders/world-1/composite.fsh:28,41`、`P:shaders/world1/composite.fsh:28,41`） |
| 无 SSAO | `P:Changelog.txt:13` "Removed SSAO"；但 `P:shaders/composite.fsh:4-8` 仍留 `#ifdef SSAO` 死分支 |

**许可原文关键行**

- `P:Agreement.txt:4`：作者自述 "I don't suggest using RedHat as a base, as this shaderpack isn't independent from Chocapic13."（`Agreement.txt:2-6` 标为 "NOT A RULE"）。
- 改编/再分发（`:10-19`）：不得把 C13 代码声称为己有（`:12`）；可分享修改版，但标题须为 `" -Name of the shaderpack- (Chocapic13' Shaders edit) "`（`:13`）；不得用变现链接（`:14`）；必须原样复制全部规则，不得自定规则（`:15`）；必须清晰署名（`:16`）；不得以旧于 C13 V4 的版本为底（`:17`）；引用网上代码须确认开源（`:18`）；只改 2-3 个常量不值得分享（`:19`）。
- 特殊层级（`:21-27`）：须 Chocapic13 **书面许可**才能用变现链接、自定义规则、自选包名；署名义务仍在（`:27`）。
- 视频/图片与分发（`:29-36`）：允许截图/视频，需在描述给出包名（`:31`）、允许变现视频（`:32`）；下载链接须指向官方帖、不得加变现链接（`:34-36`）。
- 兜底（`:38-39`）：违规可被要求下线，"Intellectual property stealing is punished by law"。

> 血缘对照：`_analysis/` 下**没有** `chocapic13-v6`（本次列目录实测），C13 本体官方直链仍缺位；本包是工作区目前唯一可直接读的 C13 血统实现。

## ② 架构特性清单

**2.1 组织/设置**：三套整份 program 副本 `P:shaders/program/{,nether/,end/}composite*.glsl`、`final.glsl`；维度差异靠改常量而非 `#ifdef`（下界天空基色 `P:shaders/program/nether/composite.glsl:99`，末地 `P:shaders/program/end/composite.glsl:99`；雾各一份 include：`P:shaders/program/nether/composite1.glsl:206`、`P:shaders/program/end/composite1.glsl:160`）。参数体系 `P:shaders/lib/defines/composite.h`（105 行）、`composite1.h`（65）、`final.h`（74），全为 `#define` + OptiFine `//[枚举]`；UI/滑条/profile 在 `P:shaders/shaders.properties:1-42,67-115,129-133,136`。

**2.2 时间与天文**：四相位权重 `P:shaders/lib/timecalculation.glsl:3-7`（被雾、SSS、焦散、光束、VL、去饱和复用）；`ToD[25]` 逐小时色表 `P:shaders/lib/color/sunlight.glsl:10-34` + 数据 `data1..4.glsl`（`:1-9` 四选一），插值 `P:shaders/program/composite.glsl:947-950` 并在 composite1/2、final、end 各复制一份；日月可见度 `pow(clamp(SdotU+0.1,0,0.1)/0.1,2)`（`composite.glsl:940-941`）；日月影切换窗 `transition_fading`（`composite.glsl:605`）。

**2.3 G-buffer 与材质**：格式常量 `P:shaders/gbuffers_terrain.fsh:37-46`、`/* DRAWBUFFERS:0246 */`（`:125`）；材质标记写进 gaux1.g `vec4(lmcoord.t, mat, lmcoord.s, 1.0)`（`gbuffers_terrain.fsh:129`），语义见 `P:shaders/gbuffers_textured_lit.fsh:53`（x=specular / y=land/shadow 早退/water=0.05 / z=torch lightmap）、水位 `mix(1.0,0.05,iswater)`（`P:shaders/gbuffers_water.fsh:138`）；ID 宏 `P:shaders/lib/entityIDs.glsl:6-23` + `P:shaders/block.properties:4-37`；法线 TBN `gbuffers_terrain.fsh:116-123`、6 向切线分支 `gbuffers_terrain.vsh:186-237`。

**2.4 阴影**：shadow pass 顶点 `P:shaders/shadow.vsh:100-177`（畸变 `:169-171`，`SHADOW_MAP_BIAS=0.85` 定义于 `P:shaders/composite.fsh:37`）；片元 `P:shaders/program/composite.glsl:641-707`：重投影 `:649-656`、斜率深度偏置 `:663-664`、三档过滤 `:672-705`（`shadowHardwareFiltering=true` `P:shaders/composite.fsh:32`）；60-tap 静态多层圆盘 `:122-181` + 高斯权循环（权重同时缩放偏置）`:679-687`；下界/末地改用共享数组 `P:shaders/lib/poisson.glsl:1-59`（`nether/composite.glsl:124`、`end/composite.glsl:125`）；越界 `:709-727`；泄漏修补 `:728-737`。

**2.5 光照与材质响应**：主块 `P:shaders/program/composite.glsl:741-834`（diffuse `:741-742`、SSS `:744-752`、手光 `:754`、焦散 `:756-763`、自发光 `:803`、bounce `:805`、天光 `:807-812`、火把 `:814-817`、合成 `:829`）；镜面 Cook-Torrance `:183-206` / Blinn-Phong `:208-226`（仅水面 `:833`）；手光物品 ID 表 `:984-1013`；调色 `ATTENUATION=3.0`/`TORCH_ATTEN=8.0`（`P:shaders/lib/defines/composite.h:17,48`）；夜去饱和 `DESATURATION_STRENGTH`（`:67`）+ `P:shaders/lib/effect/lighting/nightdesaturation.glsl:1-3`。

**2.6 大气**：解析单次散射——`fx/fx2` 是反导数（`P:shaders/program/composite.glsl:228-239`），`:256,262` 用差商求积分，`getSkyColor` `:273-320`（五常数相位 `:292-296`，日月两套 `:300,312`）；环境色 1 天顶 + 4 斜向采样（`composite1.glsl:850-858`）；雾 `lib/effect/atmospherics/fog.glsl:9-13`（四相位密度）+ `:15-24`（解析式；高度密度 `getAirDensity=(max(h,60)-40)/2` 在 `composite1.glsl:201-203`）；云三套并存 `composite1.glsl:263-315`/`:431-472`/`:474-518`，共用曲率穹顶 `400*sqrt(cosT2)`（`:280,448,489`）、8 重噪声 `/1.4472`、双叶 SSS（`:298`）、alpha 累积与早退（`:307-310`）；光束 `:636-674`（相位色表 `:640`）；体积光 `composite.glsl:419-537`（8×8 Bayer `:419-441,485-490`、`pushback` 修漏 `:493`、深度早退 `:499`），配色 `composite1.glsl:209-247` + 参数 `lib/defines/composite1.h:45-53`。

**2.7 水体**：折射 `P:shaders/program/composite.glsl:610-639`（`refMult=0.0025-dot(normal,view)*0.0015` `:626`）；反射 `composite1.glsl:317-369`/`:371-417` 双套步进（`P:shaders/composite1.fsh:31-40`），连续 `sr>=maxf` 才算命中 `:341`、边缘 `1-cdist^20` 淡出 `:342`、miss 回退 `simplifiedCloud` `:554`、天空伪值 `uPos.z` `:540`；水下 `sky_absorbance` `composite.glsl:797` + 水面端 `:830`、水下雾 `composite1.glsl:419-428`；焦散 `composite.glsl:386-413`（三风格 + 四相位色 `:405-409`）；水波高度场 `gbuffers_water.fsh:61-99`、顶点位移 `gbuffers_water.vsh:74-84`、法线 `lib/effect/parallax/waternormals.glsl:1-20`。

**2.8 后期**：泛光 15-tap 单向高斯读 `gaux2` mip2（`P:shaders/program/composite2.glsl:46-73`）+ `gaux2MipmapEnabled`（`P:shaders/composite2.fsh:10`），final 再取 `composite` mip3（`final.glsl:485-507`）+ `compositeMipmapEnabled`（`P:shaders/final.fsh:24`）；色调映射三选一 `final.glsl:286-317`（开关 `lib/defines/final.h:63`）；其余后处理 `:534-557`；景深+色差 `:432-483`；镜头 10 型目录 `lib/effect/visual/lens/mainlens.glsl:537-571`。

**2.9 死开关/隐患**（只记录）：SSAO 死分支 `P:shaders/composite.fsh:4-8`；单像素日面遮挡探针（`composite1.glsl:676-700`→`mainlens.glsl:12-13`，判据为材质掩码 >0.04）；`composite1.glsl:536` 的 `max(-70.,.0)` 空操作；`shadow.vsh:131,139,143,147` 引用未声明 `worldpos`（被未定义宏屏蔽，开启即编译失败）；天空/插值函数在 5 pass × 3 维度共 15 处副本。

## ③ 可借鉴点（14 条）

| # | 技术 | P: | A: | 工作量 |
|---|---|---|---|---|
| 1 | 阴影图**越界时钳到边界 texel 采样**，再按越界距离 `smoothstep` 淡到 `sky_lightmap²` | `program/composite.glsl:709-727` | `global/lighting/shadowmap.glsl:66-80`、`global/lighting/diffuse.glsl:263-269` | 小 |
| 2 | 日面遮挡探针的**判据源**变体：材质掩码 >0.04 判"非天"，替代 depth 判据（云/半透明不被误杀） | `program/composite1.glsl:676-700` + `lib/effect/visual/lens/mainlens.glsl:12-13` | `program/scattering.fsh:56-74` + `program/display.fsh:133`（已有，depth 源） | 小 |
| 3 | 云层"曲率穹顶"平面：远天顶采样层加 `400*sqrt(cosT2)` 下沉，抑制地平线云墙 | `program/composite1.glsl:280,448,489` | `global/atmosphere/clouds_planar.glsl:228-320` | 小-中 |
| 4 | 云体积累积的能量守恒形式 `acc += c*exp(-acc.a)` + `>0.999` 早退 | `program/composite1.glsl:307-310` | `global/atmosphere/clouds_planar.glsl:296-320` | 小 |
| 5 | 折射位移随视角线性减弱（正视强、掠射弱） | `program/composite.glsl:626-639` | `global/water/refraction.glsl:11-23` | 极小 |
| 6 | 水下双尺度吸收：近场 `exp(-d/1.5)` 与远场 `exp(-d/16)` 分离，水色再乘天空亮度 | `program/composite.glsl:797,830` | `global/water/absorption.glsl:97-105`、`program/water.glsl:225-228` | 小 |
| 7 | 反射的太阳光加成按仰角加权（水面 ×45、雨/地面 ×5） | `program/composite1.glsl:561,573,586` | `program/water.glsl:293-324` | 小 |
| 8 | 软阴影核改静态多层圆盘 + 高斯权同时缩放深度偏置 | `program/composite.glsl:122-181,663-664,679-687`、`lib/poisson.glsl:1-59` | `global/lighting/diffuse.glsl:266-289`、`lib/settings.glsl:68-83` | 中 |
| 9 | 体积光/光束按相位 + 室内分强度分色（DAY/NIGHT/SSSR/INSIDE + 色调倾向） | `program/composite1.glsl:209-247`、`lib/defines/composite1.h:45-53` | `global/post/godrays.glsl:53-90`、`global/atmosphere/volume_fog.glsl:80-82` | 中 |
| 10 | 天空像素的深度替换为随太阳可见度变化的伪距离 `2000*(0.25+0.75*sunVis)` | `program/composite1.glsl:347,397,540` | `global/water/raytrace.glsl:58-123` | 小（低优先） |
| 11 | 日月影切换的时间窗淡出（各 200-300 tick） | `program/composite.glsl:605,778,805`、`composite1.glsl:66` | `lib/settings.glsl`(SUN_MOON_MODE)、`shaders.properties:602` | 小 |
| 12 | 手持发光**物品**表（火把/萤石/岩浆桶/南瓜灯 → 强度）+ 背向衰减 `sqrt(dot(N,-n)*0.5+0.51)` | `program/composite.glsl:754,984-1013` | `global/lighting/blocklight.glsl`、`shaders.properties:522` | 小 |
| 13 | 屏幕镜头水滴：5 组独立生命周期圆镜片 + `eyeBrightnessSmooth.y` 门控 | `program/final.glsl:388-420,513-522` | 无（宿主 `global/post/grading.glsl` / `program/display.fsh`） | 中 |
| 14 | 逐小时 25 键值太阳色 + 四套 COLOR_PRESET 整表（数据驱动色板） | `lib/color/sunlight.glsl:10-34`、`lib/color/data/data1..4.glsl:2-103` | `shaders.properties:611-616`、`lib/color_controls.glsl:55-77` | 中（暂缓） |

**去重标记（与已调研报告的关系）**

- **与批次一重复**：#8（`fastpbr.md:43,116-118,152` 已提"R2 圆盘 + textureGather"落同一模块；本包增量仅"权重耦合偏置"，分母 148 无出处）；#7（`fastpbr.md:150` 已将水面太阳高光列为第 1 优先）；#12（`SUMMARY.md:9` 系列共识"手持光衰减"，`bsl-shaders.md:116` 的 heldItemId 染色更完整）；#9（批次一 10 份报告含体积光，本包增量是相位+室内分色）。
- **方向重复**：#5（`complementary-unbound.md:44` 折射二次校验，与本包"视角调制"互补不重叠）；#6（水下吸收多包，增量是近/远双尺度）；#13（`bsl-shaders.md:91-93` 等为**表面**雨效果，本包是**屏幕镜头水滴**；Astra 侧 grep `DROPS|droplet` 零命中，属未占用方向）。
- **未重复**：#1、#2、#3、#4、#10 在 `shader_research/*.md` 中未见同题记载。
- **与批次二重复**：#14（`SUMMARY-batch2.md:24,26,32`：reverie/musk-rose 的 LUT 大气，已给出"静态 LUT 与四色方案冲突、先做对照实验"结论）。

## ④ Astra 已有对应实现对照表

| 主题 | RedHat（P:） | Astra（A:） | 哪边更省 | 误差来源 |
|---|---|---|---|---|
| 日月可见度 | 天顶 ±0.1 窗平方（`composite.glsl:940-941`） | CPU 预计算 `sunProgress/skyVisibilityDay`（`shaders.properties:489-500`）+ 包络 `lib/twilight.glsl:4-9` | Astra（vsh 2 条 pow → uniform 直读） | RedHat 日落后立即归零；Astra 包络跨 ±8° 且乘 `1-0.7*rain`，雨天更缓 |
| 单像素日面遮挡 | 3×3 像素内 10×10 tap 材质掩码，写 gaux2.a（`composite1.glsl:676-700`→`mainlens.glsl:12-13`） | 7×7 tap `depthtex1`，写 colortex1 texel(0,0).a，默认关（`program/scattering.fsh:56-74`、`display.fsh:133`、`lib/settings.glsl:234`） | 同量级（各一次单像素探针） | RedHat 把水面（mat=0.05）算作"可见天"，雨/水场景误报；Astra 用不透明深度不误杀光束，但云算作几何遮挡（与云密度不同源） |
| 阴影越界 | 钳边界采样 + `smoothstep(0,0.1)` 淡到天光²（`composite.glsl:709-727`） | 边界/径向 coverage `smoothstep`（`shadowmap.glsl:66-80`）+ 静态兜底（`:202-203`） | Astra（无额外采样） | RedHat 保留边界真实遮挡、缝更细，越界样本可能采错；Astra 覆盖带内无阴影细节 |
| 阴影深度偏置 | 斜率型含 `0.25/148`、`0.02/148`，半透明另用 0.0005（`composite.glsl:663-664`） | 世界单位法线偏移 + 可推导畸变（`shadowmap.glsl:192-195`、`lib/distort.glsl:9-31`） | Astra | RedHat 分母 148 无出处、换分辨率会漂；Astra 畸变/偏置随 `SHADOW_DISTANCE` 缩放 |
| 软阴影核 | 60 tap 静态四圈盘 + 高斯权（`composite.glsl:122-181,679-687`） | 4 texel Gather / 四角 lobe（`diffuse.glsl:266-289`），`SHADOW_SOFTNESS`（`settings.glsl:83`） | Astra（4~8 tap vs 60 tap） | RedHat 固定盘无旋转、图案静;Astra 大 softness 时 lobe 偏移可能出台阶 |
| 天空 | 反导数差商求单次散射（`composite.glsl:228-239,256,262`）+ 5 常数相位（`:292-296`） | Minishita 两样本大气（`sky_minishita.glsl:28-60`）+ 渐变板 + SH9（`lib/sky_sh9.glsl`） | RedHat（纯解析零采样） | RedHat 无能量守恒、只有太阳项；Astra 长掠射过消光蓝（`sky_minishita.glsl:17-19` 自陈），靠 `DAY_GAIN=22` 补 |
| 高度雾 | 单条解析式 `20*exp(-airDensity/density)*(1-exp(-d*h/density))/h`（`fog.glsl:15-24`） | 谷雾 smoothstep + `cube(distance)` 透视 + 洞穴/水下/岩浆分支（`global/atmosphere/fog.glsl:67-79,110-180`） | Astra（无 exp/除链，早退 `:89`） | RedHat 无群系/洞穴/边界雾；Astra 谷雾是折线近似（自陈 `:55-56`） |
| 云 | 3 套 + 曲率穹顶 + 8 重噪声 + 双叶 SSS（`composite1.glsl:263-315,431-472,474-518`） | slab + 列密度 + 光行进 + 时域（`clouds_planar.glsl:228-320`） | Astra（有时域，RedHat 每像素 7~11 层全算） | RedHat 云不投影、地平线靠"下弯"糊；Astra 云影与密度同源（`weather.glsl:128`） |
| 泛光 | 15-tap **单向**高斯读 gaux2 mip2 + final 取 mip3（`composite2.glsl:65`、`final.glsl:499`） | 13-tap 双滤波 + 四级 mip 加权（`global/post/bloom.glsl:50-59,167-190`） | Astra（利用 mip 链、无条纹） | RedHat 单向模糊靠 mip 掩盖方向性，小半径易出横纹 |
| 体积光 | 固定步长 + Bayer 起点 + 阴影图空间行进（`composite.glsl:419-537`） | 距离自适应步数 + 解析段积分（`volume_fog.glsl:115-158`、`lib/volume_integral.glsl`） | Astra（解析积分，无步长依赖） | RedHat 步长在剪切空间、远距出条带；`/weight` 与 `*0.15` 为经验缩放 |
| 镜头耀斑 | 10 型目录 + 16 光斑表（`mainlens.glsl:537-571`、`final.glsl:201-220`） | **无**（grep `FLARE` 零命中） | RedHat 独有 | 多数类型源自 BSL/CYBOX/TME（`Credits.txt:8,10,15`），许可不可转授 |

## ⑤ 许可可行性与"重写 vs 抄"边界

**授权事实**：根许可**不是**"保留所有权利"，而是上游 C13 共享协议（`P:Agreement.txt:8-39`），包作者另加"不建议以本包为底"（`:4`）。第三层是**不可转授**的第三方代码：BSL（`Credits.txt:8`）、CYBOX（`:10`）、Robobo1221（`:11`）、Conquest（`:13`）、TME（`:15`）。

**与批次二其它包的差异（点名）**：
1. 批次二的"保留所有权利/自定义专有"包（`ushader`、`reverie_shader`、`clarityshader`、`lux-v1`、`amethyst-shaders`、`tea-shaders`、`lumina-shader-event-horizon` 等，`SUMMARY-batch2.md:22,24,49`）连"改编—再分发"都没有书面许可；本包 `Agreement.txt:13` 明文允许分享修改版、`:32` 明文允许变现视频。
2. 但条件是**强传染**：原样复制全部规则（`:15`）、标题须含 "(Chocapic13' Shaders edit)"（`:13`）、署名（`:16`）、不得据为己有（`:12`）、不得变现链接（`:14`）、不得以 <V4 为底（`:17`）；自选包名/规则/变现链接需书面许可（`:21-27`）。故本包属"**可读思路、可借架构、不可搬运表达式**"，宽于保留所有权利、严于 MIT/CC-BY，且与 Astra 单一根许可不兼容（`Astra/LICENSE:3-9`）。
3. **归类更正**：批次二开箱前把本包并入"保留所有权利或自定义协议"（`SUMMARY-batch2.md:49`）；读原文后应改归"自定义共享协议（有条件的改编—再分发许可）"。

**"重写 vs 抄"边界**：
- 可借：算法与架构（越界钳制+淡出、单像素日面探针、曲率穹顶云、权重耦合偏置）。Astra 已有先例——`Astra/THIRD-PARTY.md:70` 把同谱系（LIGHT Shaders 1.8.0）的遮挡探针登记为 **IDEA ONLY**，并列出全部自写决定（7×7 抽、±12 px 窗、depthtex1 源、越界不计分母、无样本失败开放、载体复用 colortex1 texel(0,0) alpha、消费点一次 texelFetch）。新增"材质掩码源"变体应循此模式并追加台账行。
- 不可借：表达式级复制（`fx/fx2` 反导数、`0.25/148`、`400*sqrt(cosT2)`、`5.0+SdotU*45.0`、`max(noise-1.7,0)`、`/1.4472`）；`data1..4.glsl` 色表（C13 美术资产）；`lib/effect/visual/lens/types/*` 与 `{stars,grain,cinematicborders}.glsl`（BSL/CYBOX/TME 来源，`Credits.txt:8,10,15`）。
- 风险：`:15` 的"复制全部规则"意味着采用该协议代码就得让 Astra 的许可与文档嵌入 C13 规则；`Agreement.txt:4` 自述"不是独立作品"说明其 C13 代码占比极高，逐行判定成本高于直接重写。实操沿用批次一/二共识（`SUMMARY.md:9`）：读思路 + 独立重写 + 文件头致谢 + THIRD-PARTY.md 登记。

## ⑥ Top5 + 暂缓项

**Top5**

1. **#1 阴影越界钳制 + 淡出**：现成 12 行结构补进 `global/lighting/shadowmap.glsl:66-80`，消除 `SHADOW_DISTANCE` 边界 V 形缝与越界跳变。纯思路，无表达式搬运。
2. **#5 折射视角调制**：`REFRACTION_STRENGTH*(1-k*|dot(normal,view)|)` 一条 mix，落 `global/water/refraction.glsl:16`；与已有深度差校验互补，工作量极小。
3. **#3 云层曲率穹顶**：在 `clouds_planar.glsl:228` 的 slab 交点加下沉量，改善地平线云墙；不动密度场与云影通路，需 A/B 确认与 `borderFog` 不冲突。
4. **#9 体积光相位 + 室内分色**：`global/post/godrays.glsl:53-90` 单强度拆 DAY/NIGHT/SSSR/INSIDE（`volume_fog.glsl:80-82` 已有室内混合可复用）。工作量中（动 settings/lang/滑条）。
5. **#4 云累积能量守恒 + 早退**：若 Astra 仍是逐层线性叠加则替换，否则关闭该项。

（#2 价值最高但 Astra 已有同谱系实现，故不进 Top5。）

**暂缓项**

- **#2 日面探针"材质掩码源"变体**：先让 `GODRAYS_SUN_OCCLUSION`（`lib/settings.glsl:234`，默认关）上机 A/B，再决定是否加第二实现。
- **#8 60-tap 圆盘**：与批次一 `fastpbr` 同向且更贵；除非实测到软阴影台阶。
- **#14 逐小时色表**：与 Astra 四色方案 + CPU 解析式冲突，`SUMMARY-batch2.md:32` 已给"先做对照实验"结论。
- **#10 天空伪距离**：magic 2000 与 `borderFogDistance` 耦合风险高，收益仅限 SSR miss 边缘。
- **POM/视差**（`P:lib/effect/parallax/pom.glsl:1-18`）：需资源包高度图，Astra 无此约定。
- **镜头耀斑目录**：Astra 完全没有此效果；属风格件，多数类型许可不可转授。

## 附录：自抽查（成稿后重开源文件核对，12 条）

做法：成稿后逐行 `sed -n` 重新打印并与正文声称比对。全部命中。

| # | 对象 | 核对结果（实际打印） |
|---|---|---|
| 1 | `P:Agreement.txt:13,15,16,17` | **通过**：`:13` 标题方案原文；`:15` "copy paste all these rules in your post…you cannot make your own rules"；`:16` "I have to be clearly credited"；`:17` 不得以 <C13 V4 为底 |
| 2 | `P:Credits.txt:8,9,10,11,15` | **通过**：`:8` BSL "Gave me permission"；`:9` "Based on the v5.1.2"；`:10` CYBOX；`:11` Robobo1221；`:15` TME |
| 3 | `P:shaders/lib/timecalculation.glsl:3-7` | **通过**：`:3` `timefract = worldTime`；`:4-7` 四条 clamp 三角波 |
| 4 | `P:shaders/program/composite.glsl:605` | **通过**：行尾 `//fading between sun/moon shadows`，含 12000/13500、22500/23400 两窗 |
| 5 | `P:shaders/program/composite.glsl:663-664` | **通过**：`:663` 含 `0.25/148.0`、`0.02/148.0`、`tan(acos(abs(NdotL)))`；`:664` `mix(diffthresh,0.0005,translucent)` |
| 6 | `P:shaders/program/composite.glsl:709-727` | **通过**：`:710` "Outside shadow map bounds."；`:717` `clamp(...,vec2(0.02),vec2(0.98))`；`:725` `mix(shading, sky_lightmap*sky_lightmap, smoothstep(0.0,0.1,outside_uv))` |
| 7 | `P:shaders/program/composite1.glsl:680-689` | **通过**：`:680` "only on one pixel"；`:681` `texcoord.x < 3.0*pw && … 3.0*ph`；`:682-683` `i,j<10`；`:685` `+= 1.0-float(temp > 0.04)`；`:689` `/= nb` |
| 8 | `P:shaders/program/composite1.glsl:307-310`（**原稿误写 469-472，核对时更正**） | **通过**：`:307` `totalcloud += vec4(c.rgb*exp(-totalcloud.a),cl);`；`:308` `min(...,1.0)`；`:310` `>0.999 break`；旁证 `drawCloud` 同类早退在 `:468` |
| 9 | `P:shaders/program/final.glsl:388-420` | **通过**：`:390` `lifetime = 4.0`；`:392` `drop = vec2(0.0,fract(frameTimeCounter/20.0))`；`:397-416` 五组 `gen` + `gen_circular_lens`（0.04/0.023/0.03/0.05/0.05）；`:417` `eyeBrightnessSmooth.y-220)/15.0` |
| 10 | `P:shaders/lib/effect/visual/lens/mainlens.glsl:12-13` | **通过**：两行均为 `min(texture2D(gaux2,vec2(0.0)).a,1.0)`（`:12` 另乘 `fading`） |
| 11 | `A:global/lighting/shadowmap.glsl:66-80` | **通过**：`:66` `shadow_uv_coverage()`；`:69` `margin = shadowTexelSpread + 1.5/shadowMapResolution`；`:70` z 越界返 0；`:72/:75` 两分支 `smoothstep(margin, margin*2.0, …)` |
| 12 | `A:program/scattering.fsh:56-74` | **通过**：`:56` `godrays_sun_visibility()`；`:57` `PROBE_TAPS = 7`；`:58` `PROBE_HALF_WINDOW = 12.0`；`:70` `texture(depthtex1, tapUV)`；`:74` 无样本返回 1.0 |

**A: 引用二次核对**：成稿后实测 `Astra/` 有并行工作流未提交改动（含本报告引用的 `shadowmap.glsl`、`volume_fog.glsl`、`raytrace.glsl`、`display.fsh`），故 40 条 `A:` 引用全部重开确认：仅两处漂移——`program/display.fsh` 消费点 `129→133`、`shadowmap.glsl` 静态兜底 `200-202→202-203`（均已改），其余未变。

**P: 侧额外发现（已回填）**：③#14 与 ⑤ 原引 `SUMMARY-batch2.md:15,17,53` 有误，改为 `:24`/`:26`/`:32`/`:49`；批次一引用的 `fastpbr.md`、`complementary-unbound.md`、`bsl-shaders.md`、`SUMMARY.md` 各条也逐条重开确认。
