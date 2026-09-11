# 全量审查 + 三个参考包的优化学习 + 执行计划

日期：2026-09-11。**本轮只审查与规划，未修改任何代码。**

---

## 一、审查结论速览

| 项 | 结果 |
|---|---|
| 编译 | **261 linked / 3 failed / 27 compute** —— 3 个失败 |
| 静态校验 | **1 FAIL / 1 WARN / 9 PASS** |
| 工作区 | **大量未提交改动**（GPT 的末地系统 + 文档） |
| 完成度 | 主世界日循环完整；**月亮无相位**；体积云/DoF/运动模糊/镜头光晕等缺失 |
| 末地新系统 | 实现质量高、基本按设计书落地，但**当前编译不过** |

**结论：GPT 的工作质量不低，但当前状态不可交付**——有 1 个使末地整条新管线无法编译的缺陷。

---

## 二、必须修复的缺陷（2 个，均为阻塞级）

### D1（阻塞）末地的 `world1/prepare` 编译失败

- **症状**：`RESULT linked=261 failed=3`，三档 profile 全部失败，失败的 entry 都是 `world1/prepare.fsh`。
- **报错**：`2(5) : error C0000: syntax error, unexpected integer constant, expecting ';'`
- **根因**：`Astra/shaders/program/end_illumination.fsh:5` 写了
  ```glsl
  // Same identifier convention as the pack's existing buffer-format declarations.
  const int RGBA16 = 0;
  const int colortex8Format = RGBA16;
  ```
  `RGBA16` 是 Iris 的**缓冲格式枚举名**。Iris 用
  `PackRenderTargetDirectives.acceptConstStringDirective("colortex"+i+"Format", …)`
  （已反编译核实）**文本解析**这行声明的字符串值，再经
  `InternalTextureFormat.fromString()` 解析，**并不会把 `RGBA16` 定义成预处理器宏**。
  但离线编译器 `qa/tools/compile_glsl.py` 的 preamble 里有 `#define RGBA16 32859`，
  于是第 5 行被替换成 `const int 32859 = 0;` → 语法错误。
- **性质**：这一行是**为满足校验器而写的**（`check_pack` 的 SC-27 会检查 `colortexNFormat` 声明）。
  它在 Iris 里能跑（多余但无害），但在离线编译器里必错，且**掩盖了真实意图**。
- **修法**：删掉第 5 行即可。第 6 行在 Iris 里由字符串解析正确处理，在离线编译器里由 preamble 的
  `#define` 正确处理。**不要**改成数字字面量（会与现有 `lib/water_buffer_formats.glsl` 的写法不一致）。
- **附带核查**：`colortex8` 目前被 `end_system.glsl` 当作 1×1 光照缓冲 `texelFetch`，
  且 `shaders.properties` 已加 `size.buffer.colortex8=1 1`。要确认**格式声明写在维度专属 pass 里
  是否对全包生效**（Iris 扫描所有 program，但这一点应由修复者实测确认）。

### D2 新选项未接入校验器要求的三处

- **症状**：`check_pack` FAIL #2 ——
  `slider option(s) missing from sliders=: END_PRECESSION_MINUTES`，
  且 `profile.PERFORMANCE / BALANCED / ULTRA: missing 1 option(s)`。
- **位置**：`Astra/shaders/lib/settings.glsl:93` 定义了
  `#define END_PRECESSION_MINUTES 36 // [20 24 28 32 36 40 44 48 52 56 60]`，
  也加进了 `screen.SKY`（`shaders.properties:142`），但**漏了**
  `sliders=`（`:159`）与三个 `profile.*`（`:152-154`）。
- **修法**：把 `END_PRECESSION_MINUTES` 追加到 `sliders=` 行，并在三档 profile 各给一个值
  （建议 30 / 36 / 36，或按档位给不同周期）。

### D3（流程）大量改动未提交

`git status` 显示 14 个已修改文件 + 6 个未跟踪文件。**必须先提交或明确丢弃**，
否则无法区分"GPT 的改动"与"后续修复的改动"，也无法回滚。

---

## 三、完成度审查

### 3.1 覆盖矩阵

| 领域 | 覆盖 | 说明 |
|---|---|---|
| 主世界天空 | ✅ 完整 | 正午/日落/夜晚三套调色板 + 天气调制 + 日落光带（`sky_gradient.glsl:160-176, 217`） |
| 日出日落 | ✅ | `sunrise`/`moonrise` uniform 驱动地平线辉光与雾（`fog.glsl:144`） |
| 星空 | ✅ | Complementary 规范移植，含 `invNoonFactor2` 白天淡出、`NIGHT_STAR_AMOUNT` |
| **月亮** | ⚠️ **无相位** | `sky.fsh:49-52` 恒画满月盘；**没有任何 `moonPhase` uniform**。原版 8 相月不生效 |
| 太阳/月亮样式 | ✅ | `SUN_MOON_MODE`：原版贴图 / 程序圆盘 |
| 云 | ⚠️ 仅平面 | `CLOUD_MODE` 只有 原版 / 平面 / 关闭，**无体积云** |
| 天气 | ✅ | 雨丝（原版 alpha + 纯黑）、涟漪 flipbook、湿度、闪电点光 |
| 雷电 | ⚠️ 仅点光 | `LIGHTNING_FLASH` 只做点光，**天空不闪** |
| 水体 | ✅ 很完整 | 波动/折射/反射/焦散/吸收/光束/颗粒 12 个模块 |
| 下界 | ✅ | 体积光 + 体素彩色光（compute）+ 雾 |
| 末地 | 🟡 进行中 | GPT 新系统（环系/岛群/黑洞），**当前编译不过** |
| 后处理 | ⚠️ 偏少 | 有 bloom / godrays / grading；**无 DoF、运动模糊、镜头光晕、色差、锐化**；暗角有选项但默认关 |
| 抗锯齿 | ⚠️ 无 | 无 TAA（设计决策）、无 SMAA |
| DH / Voxy | ❌ | 无 DH 支持；Voxy 仍是 TODO(C5) |
| 特殊 | ⚠️ | 有信标光束、蜘蛛眼；**无夜视/失明/受伤闪红的自定义处理** |

### 3.2 GPT 末地系统评价（实现质量）

**值得肯定的**：
- `end_ring.glsl:4-13` 的环缝密度表**与设计书完全一致**：
  内晕 0.045 / A 环 0.82 / **卡西尼缝 0.03** / B 环 0.58 / **恩克缝 0.05** / 外晕 0.06，
  外加 4 条细缝与 `1-smoothstep(0.85,1.0,u)` 的外缘柔和收束——**锐利断口 + 柔和外缘**都做到了。
- `end_ring.glsl:41` 的差速用设计书的 **1.0:0.62** 比值；`end_ring.glsl:56-66` 两颗牧羊天体
  **清空环物质 + 留下 12° 尾迹**；`end_ring.glsl:80-86` 的环自投影。
- `end_ring.glsl:95` 的暖色限制 `smoothstep(cos(25°),1,dot(...))` **正好是设计书的 ±25°**。
- `end_illumination.fsh` 用**每帧一次 1×1 的固定正交采样**（256 次）算出方向辐照度，
  再让天空与地形共读——这是"末地地形光照跟随环食"的正确接法，且成本可忽略。
- `end_system.glsl:77` 的 `end_scene_segment()` 是**真正的射线求交**，不是贴图叠加。

**自述的未完成项**（交接文档已诚实列出）：
- 环食仍是**按时间表移动的前景遮罩**，不是由远景环面 / 牧羊天体 / 黑洞统一空间模型求出的交会；
- 碎块与岛体仍是**解析明暗的方向性轮廓**，未做完整立体几何求解；
- 无实机画面依据；黑洞本体的完整规格（尺寸放大、体积感七条）**仍未做**。

### 3.3 完成度缺口清单（按用户关心的顺序）

| 优先级 | 缺口 | 影响 |
|---|---|---|
| 高 | **月亮相位** | 夜晚每天都一样；这是最容易被玩家注意到的缺失 |
| 高 | 末地黑洞**尺寸与体积感** | 设计书 L3 已定 12°~13° 与七条体积线索，代码未动 |
| 中 | 雷电天空闪光 | 雷暴时天空不亮，观感打折 |
| 中 | 体积云 | 只有平面云；`CLOUD_MODE` 三值里没有 |
| 中 | Voxy 集成 | TODO(C5)，`check_pack` 的 WARN 就是它 |
| 低 | DoF / 运动模糊 / 镜头光晕 / 色差 | 现代光影的"镜头感"套件 |
| 低 | 夜视 / 失明 / 受伤闪红 | 原版能顶，属锦上添花 |

---

## 四、三个参考包的优化学习

### 4.1 Steadfast 0.8.0 —— "每个效果用最少的 pass/采样/带宽做完"

**总览**：最多 4 个阶段（shadow 几何 → forward gbuffers → deferred → composite → final）；
**5 张 colortex**（其中 2 张 R8、1 张半分辨率）；**没有 G-buffer**，光照全在前向着色算完；
84 条 `uniform.*` + 147 条 `variable.*` 在 CPU 逐帧预计算。

**T0 级（高收益、几乎零难度）**

| # | 技巧 | 证据 | 省下什么 |
|---|---|---|---|
| 1 | **按需整 pass 禁用** | `shaders.properties:27,30`：`program.composite.enabled=GODRAYS`、`program.deferred.enabled=<多个效果的或>` | 整个全屏 pass 的带宽+ALU |
| 2 | **缓冲格式按需最小化** | `postprocessing.fsh:22-30`（colortex0/4 = `R11F_G11F_B10F`，注释明说 32bpp 胜过 RGBA8 且支持 HDR）；`noisy_godrays.fsh:89-97`（godrays = **R8**，"halves the required memory bandwidth basically for free"） | 稳态只有 ~40-80 bpp（典型 G-buffer 是 320+ bpp） |
| 3 | **阴影 4 tap 硬件 PCF = 16 texel** | `shadowmap.glsl:28-29,64-82`：`shadowHardwareFiltering=true` + `sampler2DShadow` | 4 次 TMU 换 16 texel 软度 |
| 4 | **alpha test 前置 discard** | `lit.fsh:395-427`：阴影采样**之前**就 `discard; return;` | 树叶/草丛等被丢弃像素完全不进入光照与阴影采样 |
| 5 | **逐面数据压进 1 个 32-bit flat varying** | `lib/encoding/face.glsl:19-40`：法线八面体 9+9bit + materialID 4bit | 1 个插槽替代 vec3 法线 + material 两路 varying |
| 6 | **位置不传 varying，反算 gl_FragCoord** | `lit.fsh:207-217`："the cost of buffering and interpolating is more expensive than the following matrix math" | 3+ 个 varying 的写入/插值带宽 |

**T1/T2 级**：阴影早退 + lightmap 兜底远处（`diffuse.glsl:306-308,337-342`）；
CPU 预计算把太阳方向的大气积分整个搬走（`shaders.properties:1250-1419`）；
大气模型只用 **2 个视线样本 × 1 个光照样本**（`minishita.glsl:378-388`，自述 200 FLOPs
对比教科书的 2000-4000 FLOPs）；
噪声改 **64×64 纹理 LUT + 硬件双线性 + `textureGather` 解析梯度**（`lib/valueNoise.glsl:24-25`，
注释给出实测 `80 FPS -> 90 FPS`）；
视差 **4 步**（`parallax.glsl:54-63`，对比常见 16-32 步）；
焦散**四重门控**（`shadowmap.glsl:106-117`）；
雾分离出 `skyFogStrength` 让近处**跳过整次天空色计算**（`fog.glsl:33-38`，注释"as if the sky
color calculation was twice as fast"）；
**编译期常量表**替代逐像素 tan/cos/归一化（`surface_noise.glsl:230-238`）。

**它明确不做**：SSAO/GI、自动曝光（`shaders.properties:646-654` "we have committed to not using eye
adaption"）、体积云/光/雾、LUT 大气、粗糙反射、彩色光照、多级阴影。

**档位**：19 个 profile，四层阶梯，**低档直接关掉整个效果**（LOW 砍焦散+SSR+折射+视差+实体阴影；
TOASTER 连阴影 pass 都不渲染）。所有采样数是**编译期常量**，低档是**真把循环从代码里删掉**。

### 4.2 Mellow v3.4 —— "一套代码 + 运行期整条禁用"

**最重要的认知修正**：Mellow **不是"pass 极少的原始低配包"**。它的源码里有 16 个全屏 pass 槽位、
7 张缓冲，SSR/体积云/POM/彩色光照全都实现了。它的低配靠**三层门控**：
① `program.*.enabled=<宏>`（`shaders.properties:58-111`）整条跳过；
② 3 个 profile 只切宏；
③ 默认值极保守（动态阴影/SSAO/DoF/PBR/POM/彩色光照/水坑/描边/色差/颗粒**默认全关**）。

**实测每帧全屏 pass 数**：**FAST = 3 个**（deferred1 → composite8 → final）；
默认 = 9 个；FABULOUS = 13 个。

**第二处认知修正**：它**没有几何 deferred pass**。`deferred.fsh` 只是 1/4 分辨率深度降采样；
光照全部在 gbuffers（forward）里算完直接写 colortex0。**"少 pass"来自把光照塞进本来就必须跑的
gbuffers**，不是"合并 deferred"。

**两条最有价值的技巧**：

1. **固定尺寸 tiled bloom**（`program/composite2.vsh:9-14`）：顶点阶段把光栅化范围压进左上角
   **128×128**，整个泛光金字塔（128→64→32→64→128）都在 tile 内完成，
   **总 fragment ≈ 42k，与分辨率解耦**；升采样用加法混合省掉合成 pass。
   对比 Astra：`size.buffer.colortex2=0.5 0.5`，1080p 下每层 96 万像素 × 13 层循环 —— **数量级差距**。
2. **默认用原版光照图当"假阴影"**（`lib/settings.glsl:271` 关动态阴影；
   `shadows.glsl:54-57` 的 `get_shadow_static()` 全文只有
   `return vec3(smoothstep(0.85, 0.96, Skylight));`）—— **1 次 smoothstep 换掉整张阴影贴图**。
   且超过 `shadowDistance-32` 自动淡出切回假阴影（`lighting.glsl:106,119`）。

**其它**：`colortex3`/`colortex5` **一缓两用**（composite 阶段绑 SMAA 贴图、deferred 阶段当深度图）；
1/4 分辨率 RG16 深度供 SSAO/SSR 用；解析式雾（两条 exp）替代 raymarch；
0 步"翻转图反射"（默认档）；`FAST_TEXCOORD`/`FAST_LIGHTMAP` 跳过纹理矩阵乘法。

**它的取舍判据（最有价值的一句）**：
> 保留的每一项都作用在**大面积低频**上（天空、雾、整体明暗、色调曲线）；
> 砍掉的每一项都作用在**小面积高频、或需要额外 pass**上。
> **低频大的项留着，高频贵的项砍掉。**

**A 级"砍了会崩"清单**：光照三分离、最低环境光下限（0.15）、tonemap+曝光、天空双色渐变+时间插值、
远距离/边界雾、直射光的遮蔽感。

### 4.3 IterationT 3.2

（已有专项笔记 `docs/2026-09-11-iterationt-optimization-review.md`，其中**三处结论已被独立审查更正**：
大气 LUT 的前提、硬件 PCF 的无代价假设、"看不见所以浪费"的推断。以更正后版本为准。）

核心可借鉴项：**5 档 profile 把每个采样数一起缩放**；**`program.*.enabled` 让低档根本不编译**；
**LUT 预计算**；**时域摊销（TAA + 蓝噪声时间抖动）**——**但 Astra 无 TAA，这一条不能抄**，
必须改用空间去抖 + 解析近似。

### 4.4 三者的共同结论

| 结论 | Steadfast | Mellow | ITT |
|---|---|---|---|
| **不做 = 最快**（整 pass 门控） | ✅ `enabled=<宏>` | ✅ 16→3 个 pass | ✅ `program.*.enabled` |
| **不建 G-buffer，光照 forward** | ✅ | ✅ | ❌ 有 deferred |
| **缓冲按需降精度/降分辨率** | ✅ R8 / 32bpp | ✅ RG16 1/4 深度 | ✅ 半分辨率缓冲 |
| **用静态/假效果兜底** | ✅ lightmap 假阴影 | ✅ lightmap 假阴影 | — |
| **能预计算就预计算** | ✅ CPU uniform | ✅ 调色板 | ✅ LUT |
| **每个昂贵效果配"退化档"而非二值开关** | ✅ 编译期常量 | ✅ | ✅ 档位表 |
| **采样数越少越好（靠"够用"而非"正确"）** | ✅ 2×1 大气 | ✅ 2 次噪声云 | — |

**Astra 已经做对的**：forward 光照（`program/lit.fsh` 直接写 colortex0）、
部分 pass 门控（已有 22 条 `program.*.enabled`）、
`R11F_G11F_B10F` 用于 colortex0/4、godrays 半分辨率、云/光束有早退、
`size.buffer.colortex6/8=1 1`（1×1 光照缓冲）。

---

## 五、执行计划（**未改任何代码**，等确认）

### P0 · 修复阻塞缺陷（先做，否则不可交付）

| # | 动作 | 位置 | 风险 |
|---|---|---|---|
| P0-1 | 删除 `const int RGBA16 = 0;` | `program/end_illumination.fsh:5` | 极低 |
| P0-2 | `END_PRECESSION_MINUTES` 加入 `sliders=` 与三档 profile | `shaders.properties:159, 152-154` | 极低 |
| P0-3 | 提交 GPT 的全部改动（或明确丢弃） | git | 低 |
| P0-4 | 复跑 `compile_glsl.py` + `check_pack.py`，要求 **0 failed / 0 FAIL** | — | — |
| P0-5 | 同步实例 | — | — |

### P1 · 零风险优化（照抄 Steadfast T0）

| # | 动作 | 预期收益 | 依据 |
|---|---|---|---|
| P1-1 | **缓冲格式最小化**：核对每张 colortex 的实际用途，把不需要 HDR 的降到 R8/RG16 | 中高（带宽） | Steadfast `noisy_godrays.fsh:89-97` |
| P1-2 | **alpha test 前置 discard**：在阴影采样/光照之前先丢弃 | 中 | Steadfast `lit.fsh:395-427` |
| P1-3 | **阴影背面/远处早退**：背光面 `if (strength < 1e-4) return;`；超出距离直接返回 | 中 | Steadfast `diffuse.glsl:306-308` |
| P1-4 | **硬件 PCF**：`shadowHardwareFiltering`（需先核实采样器与消费者契约） | 中 | Steadfast / Mellow 都是 `true` |
| P1-5 | **把剩余"只做着色器内早退"的效果改成 `program.*.enabled` 门控** | 中 | Steadfast `enabled=GODRAYS` |
| P1-6 | **泛光改固定尺寸 tiled 金字塔** | **高**（数量级） | Mellow `composite2.vsh:9-14` |

### P2 · 中等收益

| # | 动作 | 依据 |
|---|---|---|
| P2-1 | 雾分离 `skyFogStrength`，近处跳过整次天空色计算 | Steadfast `fog.glsl:33-38` |
| P2-2 | 噪声改用纹理 LUT + 硬件双线性（替换手写 hash） | Steadfast `lib/valueNoise.glsl:24-25`（实测 +10 FPS） |
| P2-3 | 编译期常量表：把逐像素 tan/cos/归一化折进 `const` | Steadfast `surface_noise.glsl:230-238` |
| P2-4 | 阴影远处**自动降级为 lightmap 假阴影** | Mellow `lighting.glsl:106,119` |
| P2-5 | 缓冲复用：非同时启用的效果共享同一张 | Mellow `shaders.properties:50-52` |
| P2-6 | 体积效果改"先粗探再细算"+ transmittance 早退 | ITT / Mellow |

### P3 · 完成度补齐（按用户关心度排序）

| # | 动作 | 说明 |
|---|---|---|
| P3-1 | **月亮相位** | 加 `moonPhase` uniform，按相缩月光强度与盘形；补齐"夜晚星空"的完整度 |
| P3-2 | **末地黑洞尺寸与体积感** | 设计书 L3 已定 12°~13° + 七条体积线索（近侧遮挡/远侧上弧/阴影内部有透镜星场/盘厚度/多普勒/细光子环/差速自转），代码未动 |
| P3-3 | 末地环食改真实空间交会 | GPT 自述仍是定时遮罩 |
| P3-4 | 雷电天空闪光 | 现在只有点光 |
| P3-5 | Voxy 集成 | TODO(C5)，`check_pack` 的 WARN |
| P3-6 | 体积云（可选） | `CLOUD_MODE` 加第三档；按 Mellow 的判据，这属于"高频贵项"，**优先级应低于前面的低频项** |

### 明确不做（保持现有取舍）

- **TAA / SMAA**：Astra 的设计前提是"无 TAA、前向一次算完"。
- **GI / RSM**：同上。
- **自动曝光**：Steadfast 都已"committed to not using"。
- **自建几何 deferred pass**：三个参考包里两个都不建，Astra 也不该建。

---

## 六、给执行者的最小行动集

如果只做一件事：**P0-1 ~ P0-4**（修 2 个缺陷 + 验证），让项目回到"可交付"。
如果做两件事：再加 **P1-6 泛光 tiled 化**——这是本次审查里**性价比最高的单项优化**。
如果做三件事：再加 **P1-1 缓冲格式最小化**。

---

## 七、执行结果（2026-09-11 收尾）

### 已完成

| 项 | 内容 | 证据 |
|---|---|---|
| **P0-1** | 删除 `end_illumination.fsh` 的 `const int RGBA16 = 0;` | 编译 261/3 → 264/0 |
| **P0-2** | `END_PRECESSION_MINUTES` 接入 `sliders=` 与三档 profile（28/36/36） | check_pack 1 FAIL → 0 FAIL |
| **P0-3** | GPT 的末地系统（环系/岛群/黑洞/光照预处理）落库 | `d523e41` |
| **P1-6** | 泛光捕获 0.5 → 0.25，抽头与 mip 层精确补偿，**足迹 4/8/16/32 px 与加权平均 10.40 px 完全不变** | fragment 数降到 1/4 |
| **P1-3** | 背光面跳过 `surface_shadow_light`（SSS/玻璃除外） | 判据与 `direct_lighting` 严格等价 |
| **P3-1** | **月亮相位**（新增 `astra_procedural_moon`，含朔望分侧与地球照下限） | 之前恒为满月 |
| **P3-4** | **雷电天空闪光**（`astra_lightning_sky_flash` 接入 `astra_sky_radiance`） | 之前只有点光 |
| **P2-6** | 下界体积步进加 transmittance 早退 | 稠密羽流时提前退出 |
| — | `ringP` 未初始化警告（**共 4 处**，第 3 处在 `end_illumination.fsh:30`） | 警告消除 |

### 核实后确认"早已完成"（无需改动）

| 项 | 结论 |
|---|---|
| **P1-2** alpha test 前置 | `lit.fsh` 118 行 discard，148 行才调 `astra_light` —— 已正确 |
| **P2-4** 阴影远处降级 | `surface_shadow_light` 已有 `STATIC_SHADOW_FALLBACK` 并由 `shadow_coverage` 混合 |
| **P3-2** 黑洞尺寸与体积感 | GPT 的测地线重写后**阴影直径 12.5°**（设计目标 12~13）、**盘长轴 30°**（目标 ~30）；近侧遮挡/远侧上弧/光子环由测地线自然涌现 |

> 关于 P3-2 附带更正：设计书第八节第 15 条要求"阴影内部不是纯黑、应看到被透镜压缩的星场"，
> **这条在物理上不成立**——阴影内是光线被视界捕获的区域，本就应当全黑。正确的表述是
> "紧邻光子环外侧的星场被强烈压缩"。GPT 的实现比该条更正确，故未按其改动。

### 追加完成：阴影硬件 PCF（可选路径）

`SHADOW_FILTER_MODE`（默认 0 = 现有软件路径，1 = 硬件 PCF）。
- `shadowmap.glsl`：模式 1 下 `shadowtex0/1` 改 `sampler2DShadow`，`shadow_read_tap` 用
  `texture(tex, vec3(coord, ref))` 硬件比较，`shadow_filter_uv` 退化为 4 个波瓣；
  `shadow_opaque_visibility` 走单次硬件比较。`settings.glsl` 按模式切
  `shadowHardwareFiltering/0/1`。
- **材质取样改为惰性**：`opaqueVisibility > allVisibility` 时才取 `shadowcolor0`
  （两者相等时无染色/高度可贡献），同时保住"空气侧水体仍需 R"的分支。
- 模式 1 的透明染色用**单次中心材质采样**近似，代码内与回归工具内都明确标注了
  这是近似、且**绝不对材质/水高通道做线性插值**。
- `light_shafts.glsl` 模式 1 复用 `shadow_opaque_visibility`，不再直接 `texelFetch`。

**独立验收（我自己重跑，不采信他人日志）**：
| 检查 | 结果 |
|---|---|
| `check_pack.py` | **0 FAIL / 1 WARN / 10 PASS** |
| 默认（软件）路径全量编译 | `264 linked / 0 failed / 27 compute` |
| **把默认值改成 1** 后全量编译 | `264 linked / 0 failed`，**0 警告**（确证硬件分支是真实可编译的 GLSL） |
| `qa/tools/shadow_filter_equiv.py` | **max_abs = 9.4e-16**，FAIL=0 |

**关键结论**：回归工具在合成深度场上对比了两条路径，max_abs ≈ **1e-15 量级** ——
说明**两者数学上等价**（软件路径的 4 波瓣×4 角双线性，与硬件 2×2 比较后过滤，是同一运算），
不只是"在容差内相似"。因此模式 1 的可见度输出与模式 0 一致，**唯一差异是透明染色的中心采样近似**。

| 项 | 现状 | 模式 1 |
|---|---|---|
| 受影像素取样 | 16 抽头 × 3 张 = 48 次 | 4 次比较 × 2 张 = **8 次** + 按需 1 次材质 |

### 未执行（附原因）

| 项 | 原因 |
|---|---|
| **P2-2** 噪声改纹理 LUT | 会触及空气/水/云/末地等多个模块，改动面大且无法实机验证 |
| **P2-3** 编译期常量表 | 需要先定位热点；本包的水面噪声已经是常量数组形式 |
| **P2-5** 缓冲复用 | 需要逐张审计 colortex 的启用互斥关系，属重构级 |
| **P3-3** 环食改真实空间交会 | GPT 自述仍是定时遮罩；改为统一空间模型求交是大改造 |
| **P3-5** Voxy 集成 | 需要 `voxy.json` 与独立入口，仍是 C5 |
| **P3-6** 体积云 | 按 Mellow 判据属"高频贵项"，优先级本就最低 |

### 最终状态

`264 linked / 0 failed / 27 compute`；关闭态 `237 / 0`；
`check_pack` **0 FAIL / 1 WARN / 10 PASS**（WARN 为 Voxy 占位）；
`nether_voxel_model` 5/5；实例已同步。

### 阴影硬件 PCF 可选路径接续

依据 `docs/2026-09-11-task-shadow-hardware-pcf.md`，新增 `SHADOW_FILTER_MODE=0/1`。默认与三档 profile 全部保持 0，阴影分辨率、距离、柔和度与投影扭曲均未改动；没有新增缓冲或渲染阶段。

| 项 | 当前实现 |
|---|---|
| 选项接入 | settings 枚举、SHADOWS 页面、三档 profile、中英文标题/说明/取值全部接齐 |
| 硬件路径 | 两张深度图使用 `sampler2DShadow`；4 波瓣 × 2 张图，共 8 次比较采样，透明遮挡存在时再读 1 次中心材质 |
| 软件路径 | 保留 16 个角点及原权重；只在不透明/全部可见度不同、材质确实参与结果时读取 caster |
| 体积和末地消费点 | `shadow_opaque_visibility` 按模式切换；水下光束在硬件模式使用比较采样，默认模式保留原计算 |
| 数值工具 | `qa/tools/shadow_filter_equiv.py`；硬边、斜面、固定随机噪声，五档柔和度，共 33345 个接收点案例 |

需要更正原任务书的说明：当前软件实现本来就是“逐纹素比较，然后双线性过滤”。在同一波瓣坐标、LEQUAL 比较和边缘钳制下，理想硬件 PCF 与其纯可见度数学等价，不能承诺额外柔化。真正的可选取舍是透明材质采用中心染色近似，材质交界处不保证与软件逐纹素结果相同。数值工具只对可见度作等价判定，不把它当成完整染色图像的等价证明。

关闭彩色阴影且相机在空气中，也可能在看水底；原路径需要 caster.R 判断水面透光。因此不能无条件删除这类材质读取。当前对不涉及透明遮挡的像素完全跳过材质读取；硬件路径其余情况下最多一次，软件路径保留必要的逐纹素配对。
