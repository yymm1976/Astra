# Astra 独立全量审查（2026-09-21）

**基线**：HEAD = `d3ea2d9`（B 轮收尾；工作区干净，除一份未跟踪的 `docs/2026-09-21-current-state-review.md`）。
**方法**：本报告正文的每一条结论都来自**本次实跑的命令与当前源码**，命令的原始输出落在
`qa/review-2026-09-21-*.log`。正文**不引用**任何 2026-09-20 及更早的审查报告/台账作为依据；
唯一涉及旧报告的是 §9 的对照附表，且逐行标注「旧报告声称 vs 本次实测」。
**独立性边界**：需要实机才能判定的部分（画面、帧率、其他厂商驱动）在 §8 明确列为未覆盖，
本报告不对它们发表结论。

---

## 0. 一句话结论

包在**编译与结构两个机械面上完全健康**（三档默认、8 个默认关选项全开扫描、17 项结构检查全绿，
选项面三方零缺口），**两条硬阻塞都不在代码而在"链"与"证"**：
① **许可链断裂** —— 14 个 shader 文件声明自己是 GPL-3.0-or-later 并把读者指向 `Astra/LICENSE`，
而该文件是一份 445 字节的「仅供个人使用」临时声明，**不含 GPL 原文**，且被同一行点名的
上游许可文件（`_analysis/Steadfast-0.8.0/LICENSE.md`）不在包内；
② **全项目零帧率数据** —— `design.md §8.2` 的 144/90/60 目标从未被测量（`qa/benchmarks.md` 为空模板）。
其次是一组成片的**文档腐烂**（设计文档的数值漂移、交接文档的行号失效），它们不影响构建，
但会把后来者引向错误的结论。

---

## 1. 基线（本次实跑，全部落日志）

| 门 | 命令 | 结果 |
|---|---|---|
| 编译门 · 三档默认 | `python qa/tools/compile_glsl.py` | `RESULT  linked=270  failed=0  compute=27  compute_capable=true` |
| 编译门 · 默认关选项**全开**扫描 | `python qa/tools/compile_glsl.py --set CLOUD_SHADOWS= --set AUTO_EXPOSURE= --set GODRAYS= --set GODRAYS_SUN_OCCLUSION= --set VIGNETTE= --set VOXY_SUPPORT= --set UNDERWATER_SHAFT_CALIBRATION= --set UNDERWATER_PARTICLES=` | `linked=270  failed=0  compute=27` |
| 编译门 · 穷举面（**D 轮已补跑完成**） | `python qa/tools/compile_glsl.py --matrix --jobs 2` | `RESULT_ALL  batches=11  rows=83  entries_per_row=90  linked=7470  failed=0`（日志 `qa/review-2026-09-21-matrix.log`；初稿的 `--jobs 4`「未产出」是 stdout 缓冲误判，D 轮已在 §2.3 更正） |
| 选项覆盖面（生成侧，非编译） | `python qa/tools/option_matrix.py` | 71 选项 / 41 因子 / 95 水平 / 820 因子对 / 无种子贪心覆盖阵列 **89 行 0 未覆盖对**；`declared but read nowhere: none` |
| 结构门 | `python qa/tools/check_pack.py` | `17 checks: 0 FAIL, 1 WARN, 16 PASS`（唯一 WARN = #4 的 Voxy 接线登记） |

**规模实测**（本次遍历 `Astra/shaders/`）：
249 个 `.glsl/.vsh/.fsh/.csh` 文件、**10,099 行**、10 个 compute 源（`.csh`）、
36 条 `program.*.enabled` 门、8 条 `size.buffer.*` 声明、主世界 8 个全屏 pass
（`composite`、`composite1..5`、`deferred`、`final`）。

---

## 2. 维度一：编译健康

### 2.1 三档默认 + 全开扫描（通过）

两个扫描都是 `linked=270 failed=0 compute=27`。**默认关选项全开的扫描是必要的一维**：被预处理器
排除的分支在默认扫描里根本看不见（历史上的 `GODRAYS_SUN_OCCLUSION` 非法向量比较就是这样漏过
267 次链接的）。本次一次性把 8 个默认关的布尔选项全部打开，结果不变。

### 2.2 结构检查的覆盖（17 项 0 FAIL）

本次在 B 轮给 `check_pack.py` 加了 **#17 内置 uniform 类型面**（`BUILTIN_UNIFORM_TYPES`，
151 个名字来自本机 `iris-fabric-1.11.2+mc26.2.jar` 的 `javap` 提取）。本次实跑：

```
[PASS] #17 built-in uniform type faces (Iris registration <-> GLSL declaration)
       . 28 built-in declaration(s) checked against 151 registered names; 0 mismatches
```

**方法学提示（本报告的一条 P2）**：#17 的表**绑定 jar 版本**；换 Iris 版本时表可能漂移，
复算配方写在 `qa/b5-uniform-type-gate-2026-09-21.log §1`。

### 2.3 穷举面（C 轮未完成 → **D 轮完成，以下是实测**）

**C 轮记录（保留）**：`--matrix --jobs 4` 后台运行约 25 分钟时日志为 0 行、`tasklist` 持续有 4 个
java 编译进程，进程被终止，当时**无法判定是工具停滞还是 stdout 块缓冲**。
**D 轮实测（2026-09-21 收尾轮，`--jobs 2`）**：同一命令**在 45 分钟硬超时内跑通**，
日志 `qa/review-2026-09-21-matrix.log`：

```
BATCH 1/11 rows=M001..M008 rc=0      ... (11 行全部 rc=0，含 BATCH 11 先于 10 落盘的乱序)
RESULT_ALL	batches=11	rows=83	entries_per_row=90	linked=7470	failed=0
matrix rc=0
```

**结论更正**：C 轮的空日志**是 stdout 块缓冲**（D 轮同一现象先复现——前 16 分钟日志 0 行，
之后一次性吐出 `BATCH 1/11 … rc=0` 并随后逐批落盘），**不是工具停滞**。
`--jobs 4` 那份同样在推进，只是被提前终止了；本轮的 45 分钟预算下、`--jobs 2` 用了约 45 分钟。

**判据**：取日志自身 `RESULT_ALL` 行的 `failed=0`（行数与 `linked` 随选项面变化，不写死）；
本次为 `rows=83 / entries_per_row=90 / linked=7470 / failed=0`，退出码 0。

替代取证（C 轮已跑，仍有效）：`python qa/tools/option_matrix.py` —— 71 选项 / 41 因子 / 95 水平 /
820 因子对 / 无种子贪心成对覆盖阵列 **89 行、0 未覆盖对**，`declared but read nowhere: none`。

它另报两条清单，C 轮逐条核验（**都不是代码缺陷**）：

| 工具的报法 | 核验（实读） | 判定 |
|---|---|---|
| `names nothing declares`: `R11F_G11F_B10F`/`RGBA16`/`RGBA16F`/`RGBA32F` | 四个格式 token 用 **`const int`** 声明（`lib/water_buffer_formats.glsl:6-11`、`program/end_illumination.fsh:6`、`program/end_sky_buffer.fsh:6`），工具只扫 `#define` | 工具扫描面局限（P2） |
| 同上：`EXTERNALLY_DEFINED_UNIFORMS`（`lib/uniforms.glsl:4`） | 设计上的“由外部 TU 提供”宏，无包内声明是正常的 | 工具报法（P2） |
| 同上：`ASTRA_VOXY_PASS`（`lib/transforms.glsl:25,35`、`lib/uniforms.glsl:97`） | 两个 voxy 入口是**空壳 stub**（`voxy_opaque.glsl:3` = `void voxy_emitFragment() {}`），**全包没有任何地方定义该宏** ⇒ 相关分支**永不进入** | **真实的未接线状态**，与 §2.4 C1 的 #4 WARN 同源（P2） |
| `constant #defines nothing reads`: `SKY_MINISHITA`/`SUN_MOON_DISCS`/`WATER_BALANCED` | 三者都**有声明**（`lib/settings.glsl:23,26,31`）且作为**比较对象**使用（`#if SKY_MODE == SKY_MINISHITA` 形态，与 `WATER_CHARACTER == WATER_COLD` 同构） | 工具扫描面局限（只找 `#ifdef`，不解析 `#if` 内的相等比较）（P2） |

> **本节与 §1/§7/§8 的口径差**：§1 的基线表、§7 的 P2 行与 §8 的未覆盖第 6 条写于 C 轮，
> 当时穷举面未跑通，故那三处仍写“本次未完成/未独立验证”。D 轮白名单只授权改本节，
> 因此那三处的措辞与计数**按原样保留**；穷举面的最新状态以本节为准
> （`RESULT_ALL … failed=0`，退出码 0）。

### 2.4 编译健康维度的发现

| # | 级别 | 事实 | 证据 |
|---|---|---|---|
| C1 | P2 | #4 是唯一 WARN，内容为 Voxy 接线登记（`Astra/shaders/voxy.json` 为 0 字节空文件）；本次另确认 `ASTRA_VOXY_PASS` 全包无定义、两个 voxy 入口是空壳 stub ⇒ 相关 `#ifdef` 分支永不进入 | `qa/review-2026-09-21-checkpack.log` 的 `[WARN] #4` 行；`voxy_opaque.glsl:3`；§2.3 表 |
| C2 | P2 | `#17` 的类型表绑定 jar 版本，换版需重取 | `qa/b5-uniform-type-gate-2026-09-21.log §4` |

**没有发现 P0/P1 级编译问题**：三档、全开、穷举三面全绿，且每个入口都能追到 `lib/settings.glsl`。

---

## 3. 维度二：选项面三方一致性（`settings.glsl` / `shaders.properties` / `lang`）

三方各自实测（脚本落在 `qa/review-2026-09-21-*.log`）：

| 面 | 实测 |
|---|---|
| `lib/settings.glsl` 声明 | **71 个选项**（31 布尔 + 40 取值型），其中 **8 个是注释态**（出厂关） |
| `shaders.properties` profile | PERFORMANCE / BALANCED / ULTRA 各 **71 token**（完全覆盖，无遗漏）；`!` 关断数分别为 **17 / 8 / 7** |
| `lang/zh_cn.lang` 与 `lang/en_US.lang` | 各 **71 个 `option.X` + 71 个 `option.X.comment`**；与声明集合**双向零差** |

**交叉核验（本报告做的最有价值的一步）**：把「注释态声明」与「BALANCED 档的 `!` 令牌」
两个集合相减 —— `declaration-off − profile-off = []`、`profile-off − declaration-off = []`。
即 **8 个出厂关选项在"声明"与"三档 profile"两处完全一致**，不存在"声明关着但档位打开"
或反过来的漂移。

### 发现

| # | 级别 | 事实 | 证据（复现命令） |
|---|---|---|---|
| O1 | **P2** | `UNDERWATER_SHAFT_SAMPLES` 声明 **7 档**（`settings.glsl:143` 的 `[4 5 6 7 8 9 10]`），而两份 lang 各只给 **3 个** `value.*` 标签（4/7/10）。中间 4 档在 GUI 里没有名字。 | `python` 统计：`lang/*.lang:186-188` 三行 vs `settings.glsl:143`；见 §3 表 |

**维度结论：选项面三方一致性达标**（零缺失、零多余、档位与声明互证），唯一发现是 O1 的标签覆盖不全（P2）。

---

## 4. 维度三：性能预算（RTX 4050 @1080p 的目标 vs 现状）

### 4.1 目标（来自设计文本，非实测）

`design.md §8.2` 的三档目标为 **144 / 90 / 60 FPS**（PERFORMANCE / BALANCED / ULTRA）。

### 4.2 现状：**零帧率数据**

`qa/benchmarks.md` 本次实读仍**没有任何 FPS 数字**（模板的每一格为空；B 轮只在顶部加了一段
状态说明）。仓库里能查到的"帧率"全部来自二次转述，**不是基准测量**。

### 4.3 唯一可离线量的东西：指令级

本次 A4 单建立了 `qa/tools/end_march_count.py`（GPU 计数探针，插桩在被调用函数体内），
对末地黑洞 march 的实测是：

| 量 | mean | p95 | max |
|---|---|---|---|
| `end_scene_segment` 调用/像素 | 1.0514 | 2 | 2 |
| march 步数/像素 | 1.6389 | 14 | 48 |
| disc 有效采样/像素 | 0.0610 | 0 | 18 |

并已说明其**覆盖边界**：离线 TU 不绑定 `colortex8` ⇒ `candidateCount == 0` ⇒
`end_scene_segment` 的真实成本（天体遍历）**未被覆盖**。

### 4.4 结构面（可测但不等价于帧率）

8 个全屏 pass + 10 个 compute 阶段 + 8 条缓冲尺寸声明（其中 `colortex8` 为 294×1、
`colortex9` 为 0.75、`colortex1/2/7` 为 0.25、`colortex6/10` 为 1）。

### 发现

| # | 级别 | 事实 | 证据 |
|---|---|---|---|
| P1 | **P1** | **性能预算的达成度无法判定**：目标有、结构有、**测量没有**。任何"某个改动提升帧率"的宣称在本仓库都无基线可依。 | `design.md §8.2`（目标）vs `qa/benchmarks.md`（空）vs `qa/a4-blackhole-performance-2026-09-21.log §5`（自陈不宣称帧率） |
| P2 | **P2** | 唯一可离线量化的成本面是末地黑洞 march；水下光束焦散链、云 march、Voxel 链均**无同类探针**。 | 本次遍历 `qa/tools/`：只有 `end_march_count.py` 是成本计数探针 |

---

## 5. 维度四：参照包许可合规

### 5.1 先说通过的部分（正面证据，均本次实跑）

| 项 | 结果 |
|---|---|
| 供应商隔离目录 | `Astra/shaders/lib/vendor/` **11 个文件**，逐个 sha256 与台账登记相符；两份上游许可原文逐字节相同 |
| 许可正文位置 | `check_pack.py #15` PASS：**0 file(s) carrying licence text outside it**（即许可原文只在 `lib/vendor/` 内） |
| PNG 资产哈希 | 7 张 PNG + 2 个 `.mcmeta` 的字节数与 sha256 前 16 位**与台账逐条相符**（含 `solas-water-noise.png` 与上游 `Solas V2.2b/shaders/tex/noise.png` 逐字节相同） |
| 上游包不入库 | `.gitignore` 排除 `/_analysis/` 与 `*.zip`；`git ls-files _analysis` = 0 |
| 移植链可复算 | `python qa/tools/verify_tonemap_chain.py` → `PASS lib/tonemap.glsl matches upstream glsl-tone-map and BakingLab as registered` |

### 5.2 发现

| # | 级别 | 事实 | 证据（复现） |
|---|---|---|---|
| **L1** | **P1** | **GPL 指针链断裂**：14 个 shader 文件（41 行）声明"本文件是 Steadfast 的派生，按 GPL-3.0-or-later 授权；见 `Astra/LICENSE` 与 `_analysis/Steadfast-0.8.0/LICENSE.md`"，但 —— `Astra/LICENSE` 实为 **445 字节**的「Interim status: **PERSONAL USE ONLY**」声明（自陈"借用了许可尚不允许再分发的第三方代码"，并要求发布前跑 `design.md §9.3` 门），**不含 GPL 原文**；而 `_analysis/` **不进包**。收件人只有 shaderpack 时无法获得被要求的许可原文。（该临时状态部分缓解了"违约"判定，但**不缓解"指针指向一份不是该许可的文件"这一事实**；它是发布门的硬阻塞项。） | `python -c "print(open('Astra/LICENSE').read())"`（445 字节）；`Astra/shaders/global/lighting/{diffuse,blocklight,shadowmap}.glsl:9-13` 等 14 文件 41 行 |
| **L2** | **P1** | **Steadfast §7 的署名与改名条款在包内零命中**：条款要求"在描述页显眼处出现 `Steadfast is free and open-source software developed by coderbot`、且派生包名以 `(edit of coderbot's Steadfast)` 结尾"。全包搜这两个字符串：前者 **0 命中**，后者仅出现在 `THIRD-PARTY.md` 的描述里（不是包名/README）。 | 上游条款 `_analysis/Steadfast-0.8.0/LICENSE-ADDITIONAL-TERMS.md:6-9,17-23`；包内 python 搜索 |
| **L3** | **P1** | **Complementary License 1.7 的三条硬条件均不成立**：上游要求 ① 保留其许可文件在包内、② 不得附加其它许可条款、③ 描述页署名 + 官网链接。本包**没有** Complementary 的许可文件（`find Astra -iname 'License*'` 只有 `Astra/LICENSE` 与两份 vendor MIT），却**自带** `Astra/LICENSE` + 14 个文件的 GPL-3.0-or-later 声明（与 ② 直接冲突），README 亦无署名（③）。而包内有 **19 个 shader 文件**提到 Complementary。 | 上游 `_analysis/Complementary r5.9/Reimagined/License.txt §1.3(a)(b)(e)`；包内 `find`/`python` 统计 |
| **L4** | **P1** | **Bliss 的派生物在包里，而其许可从未登记**：`nether_volume.glsl` 自陈 "Adapted from X0nk Bliss Stable `lib/nether_fog.glsl`"，`bliss-nether-noise.png` 与上游 `noises.png` **逐字节相同**；而上游 Bliss 的许可文件全文只有一行：`© 2020 Chocapic13. All rights reserved.`（**ARR，不是可再分发许可**）。`THIRD-PARTY.md` 的许可事实表只列 Mellow/Steadfast/Complementary/Refrax/Solas 五行，**没有 Bliss**，也没有针对它的 `REWRITE REQUIRED` 标记（对照：`bloom.glsl:11-13` 有该标记）。 | 上游 `_analysis/latest-2026-09-10/bliss-Stable/.../LICENSE.md`；`Astra/shaders/global/dimension/nether_volume.glsl:1-14`；PNG 哈希 695035/`77d1aa0c2195a4f6` |
| L5 | P2 | `check_pack.py #15` 的许可正文黑名单**大小写敏感**：GPLv3 官方逐文件声明（mixed case）与 §7 条款措辞**都不命中**，只有全大写 `GNU GENERAL PUBLIC LICENSE` 命中 ⇒ 该门的 PASS 不能当作"许可正文只在 vendor"的证据（在 12 个文件声明 GPL-3.0-or-later 的情况下它仍然 PASS）。 | `qa/tools/check_pack.py:1390-1394` 的三个 pattern + 本次实测 |
| L6 | P2 | `check_pack.py #8` 的头部正则 `(?://\|/\*)\s*From\s+([^\n]+)` 要求 `From` 紧跟注释符，而 `blocklight.glsl:9` / `colors.glsl:12` 的 `From` 前有前缀 ⇒ 两文件**结构性漏检**；即使匹配，basename 兜底也会被台账别处的同名文件撞名放过。 | 复刻该正则实测：`check 8 sees 12 header file(s)`，两文件均 `False` |
| L7 | P2 | README 的许可摘要**低估来源构成**：`Astra/README.md:54` 只列 Mellow/Steadfast/Refrax/Solas，而包内有 Complementary（19 文件）、Bliss（PNG + GLSL 派生）、LIGHT/BSL（ARR 措辞 2 处）。 | `python` 统计包内 `Complementary` 出现文件数 = 19 |
| L8 | P2 | 台账声明的"文件头标记"在源码里不存在：`THIRD-PARTY.md:50/51` 称 `nether.glsl` / `end.glsl` 头部有 `PROVENANCE: ... REWRITE REQUIRED`，实测两文件该字符串计数 **0**。 | `python` 计数 |

**维度结论**：**合规是本次审查最重的一维**。四条 P1 都指向同一件事 —— 这个包的"出处台账"
（`THIRD-PARTY.md`）做得比它的"许可链"更完整：台账如实登记了每个来源与借用级别，
但**包内没有对应的许可原文、没有满足条件式条款的署名、且 `LICENSE` 与文件头声明的许可不是同一个**。
`Astra/LICENSE` 自己把这一切标为"临时状态"，所以**这不是"已发生的违规"，而是"发布门尚未通过"
的机械证据**。

---

## 6. 维度五：与 `design.md` / `docs/handoffs/*` 的偏差

### 6.1 发现（已按可测性筛除"建议重构/重命名"类）

| # | 级别 | 事实 | 证据 |
|---|---|---|---|
| D1 | **P1** | **下界天空是平铺 tint，没有 §4.5 要求的红/橙渐变**：`vec3 nether_sky(vec3 worldViewDir, vec3 tint) { return tint; }` —— `worldViewDir` 未被使用。 | `Astra/shaders/global/dimension/nether.glsl:105` vs `design.md:321` |
| D2 | **P1** | **下界雾的"颜色随高度变化"只有颜色没有密度**：`fogDensity = fragDistance * NETHER_FOG_NEAR_COEFF` 只依赖距离，`fogColor = tint` 只依赖群系；没有 worldY/proximity 项。 | `nether.glsl:75`（本次 A7 只改了系数，未加高度项）vs `design.md:320` |
| D3 | **P1** | **水下光束的三处设计值与源码不符且互相矛盾**：源码编码是 `rayLength/128.0` + 四次方根（`light_shafts.glsl:172`、`WATER_SHAFT_MAX_DISTANCE = 128.0` 在 `:7`），而设计文本写 `§2.3:97`=48、`SC-33:111`=`min(rayLength,48)/48`、`SC-34-F1:499`=96。 | 三处 design 行 vs `light_shafts.glsl:7,172` |
| D4 | **P1** | **SC-33 说"final 重建水下光束"，实际重建发生在 `composite3`**：`program/water_composite.fsh:19` 调 `water_shafts_resolve(colortex1, …)`；而 `program/final.fsh:53` 的 colortex1 分支条件是 `isEyeInWater == 0`。 | 两个 program 文件的行 |
| D5 | **P1** | **硬件 PCF 被选项化且默认关**（`settings.glsl:61` 默认 0、三档亦然 ⇒ `shadowHardwareFiltering = false`），而 `design.md:243` 把它写成不可选的前提。 | `settings.glsl:61` + `shaders.properties:160-162` |
| D6 | **P2** | **格式 const 的禁令已被工具自身推翻而设计文本未更新**：`lib/water_buffer_formats.glsl:12,15,16,18`、`program/end_illumination.fsh:10`、`program/end_sky_buffer.fsh:9` 是**活跃**声明，违反 `design.md:107`（SC-27）与 `:105`（SC-25）；而 `qa/tools/check_pack.py:825-830` 明文写着该禁令是误判（Bliss/Complementary 都这么声明且在 Iris 1.11.2 上正常加载）。 | 双方行号 |
| D7 | P2 | 设计数值成片过期：三档阴影参数（design `:240` 写 48/96、64/128、96/192 与恒 0.5，源码是 48/192、64/256、96/256）、`shadowDistanceRenderMul`（design `:353` 写 1.0，源码 `settings.glsl:233` 是 1.5）、出厂色调（design `:303/:484` 写 SAT=105/VIB=108/FOG=65/SKY_FOG=25/UW_FOG=55，源码是 100/100/102、50/15/40）、`SKY_MODE` 极致档（design `:520` 要求不得改回默认，`shaders.properties:162` 是 `SKY_MODE=0`）。 | 各 design 行 vs 各源码行 |
| D8 | P2 | 目录/文件名过期：design `:138` 列 `noise.glsl`、`:157` 列 `tex/noise.png`（均不存在，目录是 `textures/`）；design/README/handoff 写 `zh_CN` 而磁盘是 `zh_cn.lang`。 | `ls` 实测 |
| D9 | **P2** | **交接文档的行号成片腐烂**：`docs/handoffs/nether.md` 24 条抽查里 **14 条失效**（`program/scene.glsl` 因反复加长使所有指向它的行号偏移、`lit.vsh:29` 现指向另一个 id、`block.properties` 的熔岩组已拆为独立 id `10030`、若干"DEAD 保留"常量已删）；`end.md` 5 条（`colortex8` 实为 294×1 非 1×1 等）。 | 三份 drift 日志 |
| D10 | P2 | README 引用数字过期：`Astra/README.md:39` 在 B 轮已改为 186/54/52，本次实跑 `check_pack #4` 自报 **186 entries / 53 lib-global modules / 51 reachable** ⇒ 模块与可达数仍差 1。 | `qa/review-2026-09-21-checkpack.log` 的 #4 行 vs `README.md:39` |

**维度结论**：设计与交接文档的**行号与数值**是这一维度的主要问题（D6–D10 共 5 条 P2），
而 **P1 的四条（D1–D5）是"设计声明了但源码没做/做在别处"** —— 它们不是文档腐烂，
是**实现与设计的真实分叉**，其中 D3/D4/D5 会影响后续任何按设计文本执行的改动。

---

## 7. 分级汇总

| 级别 | 条数 | 条目 |
|---|---|---|
| **P0** | 0 | —— （无"会导致构建失败或运行错误"的发现；三档/全开/穷举三面全绿） |
| **P1** | 10 | L1（GPL 指针链断裂）、L2（Steadfast §7 未满足）、L3（Complementary 1.7 未满足）、L4（Bliss ARR 派生未登记）、P1-性能（预算无测量）、D1（下界天空无渐变）、D2（下界雾无高度项）、D3（光束三处设计值互斥）、D4（SC-33 归属错）、D5（硬件 PCF 前提与实现不符） |
| **P2** | 15 | C1、C2、O1、P2-性能（无同类探针）、L5、L6、L7、L8、D6、D7、D8、D9、D10、**穷举面本次未完成**（§2.3，不含数字）、**`option_matrix.py` 的两处扫描面局限**（§2.3 表） |

**读法**：四条许可类 P1（L1–L4）**同源**（台账完整、许可链不完整），可作为一个发布门工单处理；
四条设计分叉 P1（D1–D5）**同源**（设计文本写在功能落地之前，之后未回填）；
性能 P1 是**唯一的"缺测量"型**问题，其余都是"缺对齐"型。

---

## 8. 未覆盖 / 无法离线判定（如实列出）

1. **一切实机相关**：实际帧率（`design §8.2` 的目标）、画面观感、Iris 真实加载行为、
   纹理绑定 —— 本机无正在运行的 Iris 实例，本报告不对其发表结论。
2. **跨驱动**：全部编译证据来自 `NVIDIA GeForce RTX 4050 Laptop` 一家（`compile_glsl.py` 自报
   `compute_capable=true`）；AMD/Intel/Mesa 零验证。
3. **传播行为**：L1–L4 约束的是"分发/传播"；本仓库不含发布物（无 zip、无发布页），
   所以本报告只证实"包内文件不满足这些条件"，**不判定是否已发生违规传播**。
4. **上游原件的缺失**：LIGHT Shaders 1.8.0 本地不存在（台账自陈已清理）；
   Solas V2.2b 本地只有 `shaders/`（其"未声明许可"无法再用上游原件佐证）。
5. **`check_pack.py` 第 8 项的完整行为**：本次只复刻并实测了它的头部正则与 basename 兜底两处。
6. **选项穷举编译面（`--matrix`）**：本次未产出结果（§2.3），所以“选项面的每一种取值组合都能编译”这一命题**在本次审查里没有被独立验证**；已验证的是三档默认与 8 项全开两面，以及生成侧的覆盖阵列。

---

## 9. 新旧对照表（旧报告声称 vs 本次实测）

> 本表是**唯一**引用旧材料的部分，且只用于对照：左列是旧报告的**声称**（引用其原文位置），
> 右列是**本次实跑的实测值**或**当前源码行**。旧报告的准确性本身不在本报告的评价范围内，
> 这里只回答"那句声称今天还成不成立"。
> 旧材料：`docs/2026-09-20-*-review*.md`、`docs/2026-09-13-astra-full-audit.md`、
> `docs/2026-09-21-current-state-review.md`（未跟踪）。

| # | 旧报告声称（出处） | 本次实测 | 判定 |
|---|---|---|---|
| 1 | "`linked=267 failed=0 compute=27`"（current-state-review §1，基准 `b20abd0`） | `linked=270 failed=0 compute=27`（§1） | **过时**（T15 起为 270：多了 composite5 入口对） |
| 2 | "67 个选项（27 bool + 40 slider/enum）"（同上 §2） | **71 个选项（31 bool + 40 取值）**（§3） | **过时**（T9/T13/T14/T15 各加一个布尔） |
| 3 | "182 个编译入口"（同上 §2） | `check_pack #4` 自报 **186**（§1、§6 D10） | **过时** |
| 4 | "10 个 compute 阶段"（同上 §2） | **9 个 `shadowcomp*` 门 + 1 个 include-only 模块 `nether_light.csh`**（`shaders.properties` 的 `.enabled` 声明数 = 9；`Astra/README.md:20` 亦写 9） | **过时/口径错**（10 是 `.csh` 文件数） |
| 5 | "session-log 最后一条是 `9df32df`，其后 9 个 commit 无会话记录"（同上 §5.1） | `qa/session-log.md` 现有 T0–T17 整节 + A 轮 + B 轮三节，逐条挂哈希 | **已被修复**（不再成立） |
| 6 | "`RENDER_SCALE` 是死的——滑杆在 properties 里被注释"（同上 §3） | 全包搜 `RENDER_SCALE` → **0 命中**（该符号属参照包 E-LITE，不是本包选项） | **驳回**（张冠李戴） |
| 7 | "P0-1 半成落差**没有任何文档记录**"（同上 §3/§5.5） | `docs/2026-09-20-shader-pack-design-survey.md` §11.F-1（:1150）逐字写着"差量密度因此停在 22% / 10%" | **驳回** |
| 8 | 三方审查的"水色默认档绿蓝系数反了、深度 clamp 16 冻结"（2026-09-20 三份 review） | 当前源码是**按 `appearanceDepth` 插值的双端谱**（A1 单），`clamp(…, 24.0)`；16 冻结与单谱均已不在 | **已被修复**（描述的是修复前状态） |
| 9 | "水下光束是量级问题不是接线问题"（同上，B1 结论） | 当前源码的 `refract` 门已被 A2 改为以光在水中的传播方向为轴；离线探针（`shaft_refract_probe.py`）显示修前俯视半球 87.8% 为 0 | **部分过时**（"接线正确"仍成立；"方向"一维已被修） |
| 10 | "`shadow_water_depth()` 全包 0 调用者"（2026-09-20 qoder F-10 / GLM F-2） | 本次复扫：**仍 0 调用者**（`shadowmap.glsl:228` 定义，唯一外部提及是 A6 报告与 handoff） | **仍然成立** |
| 11 | "`colortex5.a` 被 SC-39 写成 0 导致 blend 连带 rgb 失效"（同上 C1） | `program/lit.fsh:355-358` 的注释自陈该覆写及其经 SRC_ALPHA blend 的连带效应，`:378` 现写完整 `gl_FragData[1]`、`:381` 单独写 `.a`；A2 单实测 `deferred.fsh:137-158` 门控读 `colortex3.a` | **已被修复** |
| 12 | "植被透光乘子展开 = 0.30+1.02t−0.32t²，是变暗不是增益"（同上 C3） | 当前为"只加不减"的 mix 形式（2026-09-20 修复轮登记；本次未复算） | **已被修复**（本次未独立复算，按源码注释） |
| 13 | "`deferred.fsh:146-147` 的 `puddle_reflection` 无条件求值"（同上 C4） | 当前 `:155-157` 为 `weight = standingWater*upFacing*rippled*fresnel; if (weight > 0.001) …`，四因子**门控调用** | **已被修复** |
| 14 | "焦散链 504–720 次/像素，比 composite4 的 144 次还大"（同上 C6） | `light_shafts.glsl:142` 起的注释写明该处已从 72-fetch 的 3×3 focus 换成一个 10-fetch 的曲率场，`:138` 的调用点与之对应；**本次未做 fetch 计数实测**，证据是源码注释与代码结构 | **已被修复（按源码自陈，未独立复算）** |

**对照表结论**：旧材料的**结构判据**（三方一致性、死链清单、档位差量）大体仍然有用，
但**所有数字型结论都已漂移**（入口 182→186、选项 67→71、链接 267→270），
而 2026-09-20 修复轮的多数具体缺陷（C1/C3/C4/C6、水色、光束接线）**已经不在源码里**。
按本表的读法：引用旧报告时应**只引用其方法与分类**，数字必须重跑。

---

## 附：本报告用到的命令（全部可复算）

```
python qa/tools/compile_glsl.py                       # 三档默认
python qa/tools/compile_glsl.py --set CLOUD_SHADOWS= --set AUTO_EXPOSURE= --set GODRAYS= \
       --set GODRAYS_SUN_OCCLUSION= --set VIGNETTE= --set VOXY_SUPPORT= \
       --set UNDERWATER_SHAFT_CALIBRATION= --set UNDERWATER_PARTICLES=      # 默认关全开
python qa/tools/compile_glsl.py --matrix --jobs 4     # 穷举面（本次未产出结果，见 §2.3）
python qa/tools/option_matrix.py                      # 选项覆盖面（生成侧，本次跑通）
python qa/tools/check_pack.py                         # 17 项结构检查
python qa/tools/end_march_count.py --panorama         # 唯一的成本计数探针（A4）
python qa/tools/verify_tonemap_chain.py               # 移植链可复算
ls Astra/shaders/lang ; python - <<'PY' … PY          # 选项面三方统计（见 §3）
```
