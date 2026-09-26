# Astra 光影 全量审查报告（2026-09-25）

> 状态：部分结论已失效。F-1/F-3/F-5/F-6 已处理，F-4 为工具误报且已修，F-2 路径错误指控不成立；270 次链接只对应默认三档。原文保留为历史审查，当前入口见 [文档索引](README.md)。

**审查对象**：`Astra/`（Iris 专用 Minecraft 光影包）+ `qa/`（验证工具与证据）+ `.specs/`（规范）+ `docs/`（历史报告）
**审查基线**：`HEAD = b49e3d2`（`codex/fix-render-handoff`），工作树中 `Astra/` **零改动**（源码全部已提交）
**审查方式**：全部结论基于本轮**实跑与实读**：`check_pack.py` / `compile_glsl.py` / `provenance_steadfast.py` / `test_gate_sensitivity.py`，以及对**本机真实安装的 Iris jar 的字节码反汇编**。无实机加载验证（本机无对应可运行实例）。

---

## 0. 结论摘要

| 维度 | 判定 | 关键依据 |
|---|---|---|
| 着色器可编译性 | **良好** | 真驱动实跑：`linked=270 failed=0`，覆盖四档 profile，NVIDIA RTX 4050 / GL 4.6 |
| 静态校验门（项目自建） | **红灯** | `check_pack.py` = `17 checks: 4 FAIL, 1 WARN, 12 PASS`，exit 1 |
| 4 个 FAIL 的性质 | **3 真缺陷 + 1 校验器误报** | 逐条字节码/源码复核，见 §2 |
| Iris 选项注册契约 | **存在 1 处高危缺陷** | `NETHER_VOXEL_LIGHT` 不被 Iris 发现（**已用 1.8.12 与 1.11.2 双版本字节码证实**） |
| 许可合规 | **发布阻塞（已知且已记录）** | 13 个文件自声明 GPL-3.0-or-later，另有 3 个 Refrax 专有派生；包 LICENSE 为"个人使用" |
| 文档准确性 | **系统性腐烂** | README 冻结于 2026-09-21，落后 6 个提交；多处量化断言与代码冲突 |
| 工程卫生 | **纪律很好，执行有漏** | 门禁存在但为红；工具不可在干净克隆上运行；72.8 MB 可再生二进制被跟踪 |
| 验证工具可信度 | **部分不可信** | 元测试 `test_gate_sensitivity.py` 崩溃，仅覆盖 17 项检查中的 3 项 |

**一句话**：代码质量与工程纪律明显高于同类自制光影包（真驱动编译门、机读许可台账、规范驱动开发），但**三道防线同时存在缺口**——校验门是红的、门的元测试是坏的、门在干净克隆上跑不起来；而唯一一个"用户可感知"的严重功能缺陷正落在这些缺口的交叉处，且**没有任何一道防线在第一时间拦住它**。

---

## 1. 已核实的"干净面"（先说好消息，避免误判）

这些是我逐个实跑/实读确认**成立**的，不是照抄文档：

1. **全部着色器能编译**：`python qa/tools/compile_glsl.py` → `OPENGL_RENDERER NVIDIA GeForce RTX 4050 Laptop GPU / 4.6.0`、`RESULT linked=270 failed=0 compute=27 compute_capable=true`，四档 profile 全部通过。这比"离线静态检查"强得多——它真的调用了驱动。
2. **"出厂默认 = BALANCED"锚点成立**：我独立复算 70 个 profile token 与 `lib/settings.glsl` 原始默认值，**零偏差**。README 把这条当基准锚，确实守住了。
3. **`Astra/` 源码零脏**：`git status --short -- Astra` 为空；未提交的只有 QA 日志/图像/文档。
4. **单一职责的 `#include` 层次没有被破坏**：`program/`、`lib/`、`global/`、`world*/` 分层清晰，无悬空 include。
5. **`lib/vendor/` 隔离纪律到位**：第三方原文与许可正文只出现在 `lib/vendor/<upstream>/`，包内其他文件不重复许可全文（check #15 PASS，我也抽查了目录结构）。
6. **选项矩阵与 GUI/lang 覆盖度高**：73 个选项 × 7 分类 × zh_CN/en_US 双语 title+comment 齐全（check #3 PASS）。
7. **"零 compute"边界被正式修订而非偷偷违反**：`design.md:518` 明确把下界体素光列为"一等公民例外"，覆盖 §0/§2.1。这是**正确的规范管理**——先翻案再实现。
8. **`world1/` 与 `world-1/` 不是重复副本**（我原本怀疑）：50 个同名文件逐字节比对，差异恰为 `NETHER`(6 字符) − `END`(3 字符) = +3 字节；归一化维度宏后仅 2 个文件真差异，且两处均为刻意且有注释（`world1/deferred.fsh` 挂末地天空缓冲；`world-1/shadow.vsh` 需 `#version 430` 以支持 `imageAtomicMax`）。**无需清理**。

---

## 2. 四个 FAIL 的逐条裁定（审查核心）

> 方法说明：每一条我都打开源码复核，并区分"校验器说得对"与"校验器自己错了"。

### F-1 【P0｜真缺陷】`NETHER_VOXEL_LIGHT` 对 Iris 不可发现 —— 已用字节码证实

**校验器**：#11 FAIL —「boolean option NETHER_VOXEL_LIGHT is only referenced through defined() … with no #ifdef/#ifndef site, so Iris never discovers it」

**我如何独立证实（关键：不信注释，信字节码）**

本机存在**两个真实 Iris 实例**（1.21.1 的 `iris-neoforge-1.8.12`、以及本项目目标版本 26.2 的 `iris-fabric-1.11.2+mc26.2`）。我解包并反汇编了二者的 `OptionAnnotatedSource`：

```
Iris 1.11.2  OptionAnnotatedSource.parseLine（110 字节）
  ldc '#define'  → ifne 37
  ldc 'const'    → ifne 37
  ldc '#ifdef'   → ifne 37
  ldc '#ifndef'  → ifne 37
  ...（仅 #ifdef / #ifndef 流入 parseIfdef，而它是 booleanDefineReferences 的唯一写入者）
```

并且对**整个 jar 做常量池扫描**：1.11.2 的 `OptionAnnotatedSource` 里**根本不存在** `#if` 或 `defined` 这两个字符串（只有 `#define` / `#ifdef` / `#ifndef`）。唯一出现 `defined` 的选项相关类是 `OptionMenuElement`，而那是报错文案 `Unable to resolve shader pack option menu element ... defined in shaders.properties` 的一部分，与预处理无关。

**结论：校验器的判断正确，且这是真缺陷，不是误报。**

**包内实际写法**（全包仅 3 处，全部是 `#if defined`，**零处** `#ifdef`/`#ifndef`）：

| 位置 | 写法 |
|---|---|
| `shaders.properties:394` | `#if defined NETHER_VOXEL_LIGHT && defined SHADOWS` |
| `global/dimension/nether.glsl:11` | `#if defined NETHER_VOXEL_LIGHT && defined SHADOWS` |
| `global/dimension/nether.glsl:174` | `#if defined NETHER_VOXEL_LIGHT && defined SHADOWS` |

**为什么严重（超出"少一个 GUI 勾选框"）**

`#define NETHER_VOXEL_LIGHT` 的原始行位于 `lib/settings.glsl:179`。Iris 只重写它**发现**的选项行；未发现的选项行**原样保留**，而它是**裸 `#define`（无值）= 恒为真**。于是一串连锁后果：

1. `#if defined NETHER_VOXEL_LIGHT && defined SHADOWS` **恒等于** `#ifdef SHADOWS`；
2. `shaders.properties:380-388` 的 9 个 compute 阶段门 `SHADOWS && NETHER_VOXEL_LIGHT` **只受 `SHADOWS` 支配**；
3. **PERFORMANCE 与 NO_SHADOWS 两档的 `!NETHER_VOXEL_LIGHT`（尝试关闭）是死 token**——低配档想省下 9 阶段体素光链，省不掉；
4. GUI 无该行（`screen.FOG` 在 `shaders.properties:153` 列了它，但 Iris 解析不到 → 正是 `lib/uniforms.glsl:107-109` 自己描述的 "Unable to resolve shader pack option menu element" 场景）；
5. `zh_cn.lang:56/121` 与 `en_US.lang` 已写好"可关"文案，**文案悬空**。

**最刺眼的一点**：项目**已经知道并修过同一类缺陷**——`lib/uniforms.glsl:107-115` 专门为 `VOXY_SUPPORT` 加了一个"仅为让 Iris 发现该选项"的 `#ifdef` 引导站点，注释还写明「Iris keeps a boolean option only when some compiled shader source references it」。同一个文件里，一个选项被正确引导，另一个被漏掉。

**附带自相矛盾**：`global/dimension/nether.glsl:9-10` 的亲笔注释写「the option itself uses a **plain #ifdef** so Iris registers the boolean (SC-28)」，紧接着的 `:11` 却是 `#if defined`。**注释与它自己的下一行代码矛盾**。

**修法（二选一，推荐前者）**：在任一被编译的着色器源里加真站点，例如 `global/dimension/nether.glsl` 或 `lib/uniforms.glsl`：
```glsl
#ifdef NETHER_VOXEL_LIGHT
const bool astraNetherVoxelBootstrap = true;   // 仅为让 Iris 注册该选项，不守卫任何逻辑
#endif
```
同步修正 `nether.glsl:9-10` 的注释。（这正是 `DITHERING` 历史上被修好的方式。）

---

### F-2 【P0｜真缺陷·新发现】`world1/` 的 deferred 门写错文件夹名，是死门

**这一条校验器没有报**，是我在核对同一缺陷类（"gate 指向不存在的目标"）时发现的。

`world1/`（末地）的 `program.` 门共 10 条，其中 9 条用 `program.world1/...`，但：

```
shaders.properties:43   program.world1/deferred1.enabled=true   ← 用 world1/
shaders.properties:100  program.world1/shadow.enabled=SHADOWS   ← 用 world1/
shaders.properties:104  program.world1/deferred.enabled=true    ← 用 world1/  ✗
```

而末地文件夹里**存在的是 `world1/deferred.fsh`**（其内容为 `#define DIMENSION_END` + `#include "/program/end_sky_buffer.fsh"`）。因此 `:104` 这个键指向一个**不存在的 pass**，Iris 永远不会查询它 —— **死门**。`grep 'deferred'` 在 properties 里只有 `program.deferred`（根层）、`program.world-1/deferred`、`program.world1/deferred`、`program.world1/deferred1`，不存在 `world1/deferred`。

**影响**：由于根层 `program.deferred.enabled=true`（`:102`）无条件生效，而 Iris 对未命中的门回退到根层/默认，末地的 deferred 槽**实际仍被启用**，所以**画面大概率不受影响**——但这条门是"写了以为生效、实际是空转"的假防线。**如果将来有人把根层门改成条件式，末地会在无声中失去天空缓冲 pass。**

**同一缺陷类的第三例（供交叉验证）**：`shaders.properties:367` 的注释自己记录了历史上前身写法 `compute.world-1/shadowcompX.enabled` 被"parsed by no handler and was silently dead"。也就是说，**"门键拼错 → 静默失效"在本项目已发生过至少两次，这是第三次。**

**修法**：`:104` 改为 `program.world1/deferred.enabled=true`。并建议为 check #16 增加一条"门键的 `<folder>/<pass>` 必须真实存在"的断言（该检查当前只验证 folder 名合法性，不验证 pass 名存在性）。

---

### F-3 【P1｜真缺陷】`THIRD-PARTY.md` 台账计数陈旧

- 台账两处写 `astra-only=27`、合计 `49`（`THIRD-PARTY.md:29`、`:77`，标题 `:100`）。
- 实跑 `provenance_steadfast.py --quiet` → **`astra-only=35`、`total=57`**。
- 独立交叉验证（走**另一条代码路径**）：`check_pack.py` #6 自报自定义 uniform 为 `32 uniform.* + 25 variable.* = 57`，而台账自述口径为 `27 + 22 = 49`。差值 +5 / +3 恰为 +8，与 astra-only 的 +8 一致 —— 证明分类器是稳定的，**是台账漏更新，不是工具漂移**。
- 诱因：2026-09-21 之后新增了 8 条自写表达式（月相 CPU 标量、`ASTRA_*` 标量等）。

**影响**：台账是 SC-14 发布门的输入，计数错误会让"发布前须重写清单"不完整。

**修法**：`:29`/`:77`/`:100` 的 27→35、合计 49→57（顺带修正同文件内 24/21 的相互矛盾基数）。

---

### F-4 【P2｜校验器误报】`SHADOW_FILTER_SOFTWARE` 并非死代码 —— **不要按提示删除**

**校验器**：#13 FAIL —「has no reader anywhere … the code path it documents no longer exists. Delete it or restore the branch」

**裁定：检测正确，结论错误。**

- 检索属实：全包 `SHADOW_FILTER_SOFTWARE` 仅出现在 `lib/settings.glsl:33`。
- 但它标注的**软件分支正是出厂发货路径**：
  ```glsl
  // lib/settings.glsl:348
  #if SHADOW_FILTER_MODE == SHADOW_FILTER_HARDWARE
      const bool shadowHardwareFiltering = true;   // 硬件臂
  #else
      const bool shadowHardwareFiltering = false;  // ← 软件臂 = 实际发货
  #endif
  ```
  `SHADOW_FILTER_SOFTWARE = 0`、`SHADOW_FILTER_MODE` 默认 `0`，且**四档 profile 全部** `SHADOW_FILTER_MODE=0`。即：该符号命名的是**被选中的那一臂**，而分支测试的是**另一值**并让它 fall through —— 这正是 `check_pack.py:1210-1214` 的 `ENUM_ARM_TOKENS` 豁免表存在的理由。
- **校验器自相矛盾**：`option_matrix.py` 同时列出 4 个"无读者常量宏"——`SHADOW_FILTER_SOFTWARE, SKY_MINISHITA, SUN_MOON_DISCS, WATER_BALANCED`——而 #13 只因后三者**在豁免表里**才没有误报。`WATER_BALANCED` 与本案完全同构（它也是 `WATER_CHARACTER` 的出厂默认臂）。
- 项目文档也已记录"保留这些 token"的决定（两份 2026-09-20 历史审查报告中的 A8 与 F-20 条目；报告已于 2026-09-26 清理，可在 git 历史查阅）。

**修法**：把 `SHADOW_FILTER_SOFTWARE` 加入 `ENUM_ARM_TOKENS`（一行）。**若照提示字面删除，会丢掉落库默认臂的唯一文档。** 这是本次审查中**最重要的"不要照着做"的一条**。

---

### F-5 【P2｜文档漂移，非代码缺陷】profile 数量 4 ≠ 规范写的 3

- `design.md:217` 写「**Profile 三档**：流畅 / 均衡 / 极致」；实际 `shaders.properties:171-174` 有 **4** 档，第 4 档 `NO_SHADOWS`（`lang:195` 亦有译文"无实时阴影"），且 `docs/2026-09-24-handoff-resolution.md:23` 记录了它是有意新增的性能档。
- **校验器自身也不一致**：`check_pack.py:1075` 的 `TIER_ORDER = ("PERFORMANCE","BALANCED","ULTRA")` 主动把 `NO_SHADOWS` 排除在阶梯之外，#12 也只走三档。即 #2 因"4≠3"报 FAIL，#12 却刻意忽略第 4 档。
- **真实缺陷是规范过期**，代码是对的。

**修法**：更新 `design.md:217`（改为 4 档，或把 `NO_SHADOWS` 明确标注为"非阶梯型冒烟档"）。

---

### F-6 【P2｜真缺陷】3 个选项不在任何 profile 内 —— "完整显式配置"不成立

**校验器**：#2 FAIL — 四档 profile **各自**缺 `DEBUG_VERTEX_AO`、`END_STONE_GLOW`、`NETHERRACK_GLOW`。

我独立复算确认（自写脚本，不复用校验器逻辑）：73 个选项，四档各只写 70 个 token，恰好缺这 3 个。

三者情况**不同**，必须分开处理：

| 选项 | 性质 | 处理 |
|---|---|---|
| `END_STONE_GLOW` | **活选项**（`lib/surface_emission.glsl:13` 读它） | 补进四档 profile |
| `NETHERRACK_GLOW` | **活选项**（`lib/surface_emission.glsl:38` 读它） | 补进四档 profile |
| `DEBUG_VERTEX_AO` | **调试选项**，在 PERFORMANCE 屏（`:155`）暴露给用户 | 见下 |

**为什么 `DEBUG_VERTEX_AO` 值得单独点名**：它在 `final.fsh:56`、`deferred.fsh:99`、`lit.fsh:359`、`water_composite.fsh:16` 被 `#if DEBUG_VERTEX_AO == 1` 读取（有人读，不是死代码），但它是一个**开发者调试开关**（"1 直接显示地形 AO"），却被放进面向用户的"性能 + 高级"分类。这属于**面向用户的界面泄漏**，低优先级但不该留。

**目前无功能影响**：三者出厂默认值（100/100/0）与 profile 缺省回退值相同，且我验证了"原始默认 = BALANCED"锚点仍然成立。**但设计文档承诺的"完整显式配置"这一性质已被破坏**——任何未来调整这三者默认值的人，会得到一个"四档都不覆盖、且无人告警"的静默不一致。

**顺带一个校验器盲区**（价值高、修起来便宜）：check #12 声称验证"原始默认 = BALANCED"，但它的实现是 `keys = list(prof["BALANCED"])`（`check_pack.py:1122`）——**只遍历 BALANCED 自己列出的 70 个键**。因此这 3 个恰好被排除的选项**永远不会**被这条锚点比较。改成遍历 `set(opts)` 即可，成本一行。

---

## 3. 其他重要发现（非 FAIL，但影响可靠性/合规）

### 3.1 【P0｜工具可靠性】校验门在干净克隆上会崩溃，而非报错

`check_pack.py:658-663` 把 `import provenance_steadfast` 包在 `try` 里，但下一行 `:664` 的 `measured = provenance_steadfast.counts()` **在 try 之外**；该函数会打开 `_analysis/Steadfast-0.8.0/shaders/shaders.properties`，而 `_analysis/` 是 gitignore 的（`.gitignore:2`）。

**后果**：`git clone && python qa/tools/check_pack.py` **以 traceback 崩在 check 8**，退出码 1 —— 与"恰好一个 FAIL"在脚本里**无法区分**。这比任何一个单条 FAIL 都更严重，因为它是"门根本不成立"。

（对照：check #7 对缺失参考语料**会**优雅降级为 WARN（`:585-587`），说明作者知道要处理这种情况，只是 #8 漏了。）

### 3.2 【P0｜工具可靠性】门的元测试（meta-test）本身是坏的

`python qa/tools/test_gate_sensitivity.py` → **我实跑复现：exit 1，崩溃**：

```
MISFIRE baseline-no-defect              exit=4 4 FAIL | collateral: 2, 8, 11, 13
MISFIRE prose-buffer-mention-control    exit=4 4 FAIL | collateral: 2, 8, 11, 13
PASS    block-commented-colortex7Format / line-commented / phantom-buffer / duplicate
PASS    vendor-file-absent / vendor-dir-without-licence / licence-outside-vendor
PASS    namespaced-blend-key / root-gate-without-folder-mirror
Traceback ... line 181 in <module>   →  line 127 s11_gate_hidden_by_own_ifdef
AssertionError: anchor 'program.world-1/shadowcomp.enabled=NETHE' found 0x
```

**两处独立故障**：

1. **锚点腐烂（崩溃）**：`:127` 断言原文 `program.world-1/shadowcomp.enabled=NETHER_VOXEL_LIGHT`，而真实行已变为 `=SHADOWS && NETHER_VOXEL_LIGHT`（`:380-388` 加了 `SHADOWS &&`）。场景 11/14 处中止，**导致收尾的 `shutil.rmtree` 不执行**——我实测确认：每次失败都在 `%TEMP%` 泄漏一份 **64.5 MB 的 `astra-gate-*` 副本**（我已清理本次泄漏）。**这个测试正在往磁盘里堆垃圾。**
2. **语义必然失败**：两个 control 场景要求"整个校验器零 FAIL"（`:186`），而当前有 4 个真 FAIL → **必然 MISFIRE**。即便修好锚点，controls 仍然红。
3. **覆盖度过度宣称**：期望检查号只有 14/15/16，`collateral` 白名单也只有 14/15/16 → 该套件只证明 **17 项检查中的 3 项**会触发。**#11（前提最微妙、也正是能拦住 `DITHERING` 的那一项）没有任何反向测试。**

**后果**：任何文档里"`test_gate_sensitivity.py` → 14/14 按预期"的收尾门声明，**现在都是假的**。我实跑观测为 9 PASS / 2 MISFIRE / 崩溃。

### 3.3 【P0｜合规】GPL 代码在包内，但包不是 GPL

- **13 个文件**在文件头自声明 `GPL-3.0-or-later`：`global/atmosphere/fog.glsl`、`global/lighting/{blocklight,diffuse,shadowmap,sss}.glsl`、`global/post/godrays.glsl`、`global/water/{refraction,surface}.glsl`、`lib/{colors,distort}.glsl`、`program/{shadow.fsh,shadow.vsh,water.glsl}`（我 grep 复核，逐条命中）。
- **另有 3 个文件**带 Refrax 专有派生的 `REWRITE REQUIRED before distribution`：`global/lighting/blocklight.glsl:20`、`global/post/bloom.glsl:12`、`lib/colors.glsl:20`。
- 而 `Astra/LICENSE` 是 **9 行"PERSONAL USE ONLY"临时声明**，**不含 GPL 正文，也不授予 GPL 权利**。多个文件头写「see Astra/LICENSE」，这是一个**悬空指向**——LICENSE 里没有它们所指的内容。
- `check #15` PASS（"包内 vendor 之外无许可正文"）恰恰是**因为包内没有 GPL 正文**——该检查把"缺正文"当成"干净"，这是**方向性误设**。

**关于是否已构成问题，需精确表述**：作为**未发布的个人使用**，这与 `LICENSE` 的临时声明**内部一致**，且项目已把发布闸门（`design.md §9.3` / SC-14）和"发布前必须重写或整包转 GPL"写在 README:54 与 LICENSE 里——**这个风险是被识别并记录的，不是被隐瞒的**。但是：GPLv3 第 10 条明确禁止对行使 GPL 权利附加进一步限制，而"PERSONAL USE ONLY"就是这么一条限制。**一旦这份工作以任何形式分发（含给朋友、上传包管理、放进整合包），当前 LICENSE 与文件头就互相冲突。** 这不阻塞开发，**阻塞发布**，且发布前必须真正执行重写清单——而该清单目前**计数是错的**（见 F-3），**且缺失 2 个应登记文件**。

### 3.4 【P1｜合规】台账缺 2 行，且多行与文件头矛盾

台账自述规则是「每新增一个来自参考包的文件/片段即登记，保持零偏差」（`THIRD-PARTY.md:3`），但：

- **缺登记**：`global/lighting/blocklight.glsl` 与 `lib/colors.glsl` 都带**双来源头**（Steadfast GPL 段 + Refrax `REWRITE REQUIRED`），却无登记行。**这两个恰是"发布前必须重写"的清单项，漏登记 = 发布门漏项。**
- **行与文件头矛盾**：`:47` 说 `global/water/refraction.glsl` 头注是 `Historical provenance: From Solas V2.2b`，而文件头实为 `Adapted from Steadfast 0.8.0 … GPL-3.0-or-later`（台账 `:191` 又写 Steadfast，**同一文件在台账内被登记为两个不同许可来源**）。
- **`:139` 声称三个 Solas 水文件头均带 `// From Solas V2.2b` + `REWRITE REQUIRED`** —— 三个都不符：`absorption.glsl` 无标记、`caustics.glsl` 只有 `Adapted from Solas`（无 REWRITE）、`refraction.glsl` 实际是 Steadfast。
- **`:374`（16.4 节）记 steadfast PNG 为 14561 字节 / 前缀 `b9502f10…`"待裁定"**，而同文件 `:195` 已写"用户裁定重生成，新 png 14517 字节 / `181f0d97…`"。**同一文件内前后矛盾**，后者才是事实（`qa/session-log.md:946` 记录该处置已闭环）。
- **`:54` 称 light_shafts.glsl 头注为 `// Written for Astra (SC-33)`** —— 实际头注是 `Adapted from Solas V2.2b volumetricLight.glsl … by Septonious`，且台账 `:307` 又把它记为 IterationT 结构移植。**三处口径互不相容。**

**好消息**：台账中**可机械验证**的部分非常扎实——16.1 的 8 个 vendor 文件、16.4 的 4 张 PNG + 3 张 ripple + 2 个 `.mcmeta` 的**字节数与 SHA256 前缀全部逐条相符**（独立复算）。问题集中在**计数与"文件头标记"列**这类需要人工同步的叙述性字段。

### 3.5 【P1｜文档】README 系统性陈旧：落后 HEAD 6 个提交

`Astra/README.md` 最后一次修改是 **2026-09-21**（提交 `2b2d736` "correct three stale facts"），其后 HEAD 又落了 **5 个提交**（9-24 ×2、9-25 ×3）。结果 README 里出现了**方向相反**的错误：

| README 断言 | 现实 | 判定 |
|---|---|---|
| `:39` 「整体 **16 checks: 0 FAIL, 1 WARN, 15 PASS**」 | **17 checks: 4 FAIL, 1 WARN, 12 PASS**（我实跑） | 对外"自检通过"声明失真 |
| `:39` 「52/54 模块可达」 | 当前 check #4 报 `58 lib/global modules, 56 reachable` | 计数陈旧（当日口径确实正确，属正常腐烂） |
| `:40` 「**两个水模块暂无生产者**：`global/water/surface.glsl` 与 `raytrace.glsl` 无人认领」 | **两者都已接线**：`gbuffers_water.fsh:4` `#define ASTRA_WATER_PASS` → `program/lit.fsh:11-12` → `program/water.glsl:12-13`。我已逐行走通三套维度壳 | **把已完成的工作说成没人做** |
| `:41` 「**无实机验证数据**：加载冒烟、**截图**、帧率跑分均未执行」 | `qa/screenshots/` 有 **24 张真实截图**（2026-09-06 的 19 张含内嵌 FPS 标注如 `17-astra-surface-morning-143fps.png`、`19-astra-distant-grayfog-170fps.png`；09-07 的 4 张），提交于 2026-09-08 | **与仓库内证据直接冲突** |
| `:49` `../qa/screenshots/`（**当前仅有占位文件——尚无实机截图**） | 同上，且 `qa/screenshots/2026-09-06/README.md` 自述为"当前 Astra 实机画面" | 同上 |
| `:20` 「NETHER_VOXEL_LIGHT **可关**」 | 不可发现（F-1），PERFORMANCE/NO_SHADOWS 的关闭 token 是死的 | 功能承诺不成立 |
| `:12`/`:27`/`:35` 「**三档** profile」「profile 为**完整显式配置**」 | 4 档；四档各缺 3 项 | 两点均不成立 |
| `:54` 「Mellow **6 个 lib 模块**」「Refrax 与 Solas **仅分类思路级借鉴**」 | Mellow 逐行 lib 模块实为 **4** 个；Refrax 在 `bloom.glsl` 是**公式级移植**（台账 `:39` 自己写"公式级"）；Solas 在 5 个文件是表达式/适配级 | 许可定位摘要失真 |
| `:22` 「`shaders.properties:162` `SKY_MODE=0`」 | `:162` 是注释行；`SKY_MODE=0` 在 `:174`（内容对、**引用位错**） | 引用腐烂 |
| `:32` 「`shaders.properties:160-162`」体积光档位门 | `:160-163` 是纯注释块；`GODRAYS` 在 `:174` | 引用腐烂 |
| `:39` 引 `qa/b9-…log:146` 作 182/186 对照 | 该行是章节标题 | 引用腐烂 |
| `:21` 「SSR（**顶面专属**，天空回退）」 | `program/water.glsl` 在所有水上水片元调用 SSR，**无顶面判据**；冰反而**完全不走 SSR**（`:213-220` 提前 return） | 描述不准确 |
| `:23` 「日光压制（**替代**自动曝光、无闪变）」 | `lib/settings.glsl:49-50` 自注「until **SC-41 overturned that**」；且"无闪变"无实机证据 | 框架已被自身推翻 |

**这构成一个回路**：README 说"没数据、没接线、0 FAIL"，而仓库里同时有截图、有接线、有 4 个 FAIL —— 一份**反向误导**的门面文档，比没有文档更糟。建议 README 改为引用**符号名 + 段落名**而非裸行号（`shaders.properties` 的注释块还在持续增长，行号必然腐烂）。

**`design.md` 亦有可机械证伪的量化漂移**（我逐条核对）：`:240` 称实体影距/影距"三档恒为 0.5"（实际 48/192、64/256、96/256 → 0.167/0.167/0.25）；`:242` 称 `SHADOW_SOFTNESS` "三档 2/4/16"（实际 2/2/8）；`:276` 与 `lib/settings.glsl:129` 称 `WATER_ABSORPTION > 0` 才启用 deferred（`shaders.properties:102` 实为**无条件** `true`，且全包无该表达式）；`:278` 称 SSR "20 粗步 + 4 细化"（实际 24 + 6）；`:292` 称水下光束"三档 16/24/32 段"（实际 **4/7/10**）；`:484` 称出厂 FOG=65/SKY=25/UW=55/SAT=105/VIB=108（实际 50/15/40/100/100，对比 102）。

### 3.6 【P1｜工程卫生】仓库卫生问题（摘要，证据见附）

- **72.8 MB 可再生二进制被 git 跟踪**，而 `.gitignore:18,21` 明文要排除它们（`git check-ignore --no-index` 确认这些路径**确实匹配**忽略规则却仍被跟踪——即规则写入后**从未 `git rm --cached`**）。最大两个：`qa/end-design/counts-{baseline,after}.npy` 各 12.6 MB。副作用：`qa/` 下 28 个文件**永久处于 modified** 状态，把真实改动淹没在 diff 噪音里；`results.json` 每次重跑产生数百行 churn。
- **`.git` 未打包**：`git count-objects -vH` → `size: 120.34 MiB, in-pack: 0, packs: 0`（一次 `git gc` 可显著回收）；另有 1 个 dangling commit。
- **`main` 陈旧**：HEAD（`codex/fix-render-handoff`）领先 `main` **5 个提交**，`main` 完全被其包含；5 个 `codex-*` 分支已 `--merged main`（**无工作被困**，只是未删）。**实际缺陷是 `main` 4 天没被快进，"main"已不再等于"最新"。**
- **4 处机器相关绝对路径**：`inspect_iris_properties.py:26` `MC = Path('D:/zhenhebao/.minecraft')` —— **无 argparse，换机即硬故障**（最严重）；`compile_glsl.py:22` 与 `sync_to_instance.py:21` 有 CLI 覆盖参数（可接受）；`qa/water-path-followup/sync.json:2-3` 把用户名与机器布局写进了**被跟踪**的文件。另有 **8 个工具**通过 `from compile_glsl import DEFAULT_MC_ROOT` 共享该 D: 默认值。
- **无 CI、无 `.github/`、无顶层 README**：既然已有带明确退出码契约的校验器，一个 ~5 行的 CI 任务本可拦住本次全部 4 个 FAIL。
- **`_analysis/` 根目录 6 个 handoff 脚本未跟踪且无人引用**（`finalize_handoff.py` 等）→ 克隆即丢失；`qa/tools/__pycache__` 未提交（合规）；有 1 个孤儿 `.pyc`（源已删）。
- **QA 日志规模**：`qa/` 根 283 个 `.log` 共 1.45 MB，**213 个（75%）小于 1 KB 但并非空文件**——每个是一行 attestation（GPU/驱动 + `RESULT linked=… failed=…`），这是**好实践**。但 **148 个（52%）文件名在任何被跟踪文档中都不出现** → 属"未索引的倾倒"，虽可 grep。

### 3.7 【P2｜校验器设计】校验器自身的方法论缺口

值得项目维护者知道，因为它们决定"门能拦住什么"：

1. **`walk_shader_files()` 不扫 `.properties`**（只看 `.vsh .fsh .glsl .csh .json`），而 `shaders.properties` 由另一条原始文本路径 `parse_properties()` 读取。后果：#11 的 SC-28 扫描**只看着色器文件**。本次结论不受影响（因为包内根本没有 `#ifdef`，两个方向都成立），但**若有人把修复写在 `shaders.properties` 里**，`#11` 仍会 FAIL 并把人带偏。建议让 #11 同时扫 `.properties`。
2. **`#include` 图是纯文本遍历**（`build_include_graph` 用未去注释的原始文本），且 `closure()` 不评估预处理器。因此**在恒假的 `#if` 臂里的模块仍被算作"可达"**——文档记录的 `sky_minishita.glsl`（"默认配置下每个入口都编译一份不可达的物理大气代码"）正是此例，check #4 报它是可达的并保持沉默。
3. **`layers` 排除 `.csh`**（`is_entry` 只认 `.vsh/.fsh`）→ 全部 **10 个 `.csh`**（含 9 个 `world-1/shadowcomp*.csh` 与 `program/nether_light.csh`）**既不在入口集也不在孤儿集**，因此 #4 的"0 unwired-and-unregistered"有 **10 个文件的空洞**（部分由 #11 的 SC-30 缓解）。
4. **`PENDING_CONSUMERS`（33 条硬编码）没有陈旧性断言**，而同文件的 `GUARD_SYMBOL_SOURCES` **有**（`:1243-1246`）。C5 接完 voxy 之后，那两条会变成永远没人提醒删除的死配置。
5. **`check_pack` 从不读取 `compile_glsl` 的结果** → "check_pack exit 0"**永远不蕴含**"能编译"。两门必须同时跑。（本次两门我都跑了。）
6. **`BUILTIN_UNIFORM_TYPES` 的 151 个名字来自单一 jar 版本的采集**（`check_pack.py:1588-1635`）→ Iris 升级会静默使其失效。**我原本想独立复核 #17 的"0 mismatches"，但自建反汇编器在真实 jar 上只匹配到 1 个注册名（可靠性不足），故已删除该脚本、放弃此路复核**——**#17 的结果本轮未获独立证实**，请按"未验证"对待。

### 3.8 【P2】其他已核实的小问题

- `block.properties` 头部 ID 分配表未列 `block.10017=minecraft:obsidian`（实际在 `:47`）→ 文件内自相矛盾（低）。
- `global/dimension/nether.glsl:9-10` 注释与 `:11` 代码矛盾（已在 F-1 记录）。
- `qa/tools/` 中 8 个脚本**既无 argparse 也无 `__main__` 守卫**，无法直接运行。
- `size.buffer.colortex8=294 1` 是末地 294 帧（128×128）横向图集，与 `shaders.properties:355-358` 的自述一致 —— 已核实**正常**，非缺陷。

---

## 4. 未完成 / 无法本轮验证的事项（明确边界）

1. **GLSL 算法级正确性深审未完成**：我已派出一路专门审查（未定义行为、矩阵空间、采样核、读写冒险等），**该路在报告交付时仍在运行**，其结果未纳入本文。**这是本次全量审查唯一未闭合的主要维度**，建议作为后续第一项。
2. **无实机加载验证**：本机有 Iris 1.8.12（1.21.1）与 1.11.2（26.2）实例，但本轮**未启动游戏**。因此以下无法判定：
   - F-1 的**具体症状**究竟是"体素光被强制常开"还是"下界相关门全部静默关闭"——这取决于 Iris 的 `program.*.enabled` 表达式求值器遇到**未注册标识符**时是抛错、告警还是静默取假。**这需要一次带日志的实机加载。**
3. **`shaders.properties` 是否参与 `ShaderPackOptions` 的 `IncludeGraph`** 未能确定（未定位到相关类）→ §3.7 第 1 条的盲区仅限"前向未定"，"包内无 `#ifdef`"这一反向结论是确定的。
4. **`#17`（内置 uniform 类型面）未获独立复核**（见 §3.7 第 6 点）。
5. **102 个提交的逐版追溯未做**（仅核到 HEAD 与被引用的少数历史日志）。

---

## 5. 建议行动顺序

**第一批（P0，直接消除风险）**
1. **修 F-1**：加真 `#ifdef NETHER_VOXEL_LIGHT` 引导站点 + 修 `nether.glsl:9-10` 注释。**这是唯一"用户可感知功能错误"级别的问题**（GUI 无开关 + 低配档关不掉 9 阶段 compute 链）。
2. **修 F-2**：`shaders.properties:104` → `program.world1/deferred.enabled`（一行）；并给 check #16 增加"pass 名必须存在"断言。
3. **让门在干净克隆上可跑**（§3.1）：check #8 对缺失 `_analysis/` 降级为 FAIL-with-message 或 SKIP，**不要 traceback**。
4. **修元测试**（§3.2）：更新 `test_gate_sensitivity.py:127` 的锚点；把两个 control 场景的期望从"零 FAIL"改为"不含自身 FAIL"；加 try/finally 保证 `rmtree` 执行。**否则每次运行泄漏 64.5 MB。**

**第二批（P1，恢复可信度）**
5. **更新 README**（§3.5）：优先改 4 条**反向误导**——`:39` 的"0 FAIL"、`:40` 的"水模块无人认领"、`:41`/`:49` 的"无截图"、`:20` 的"可发现可关"；行号引用改为符号名。
6. **修 F-3 + §3.4**：台账 27→35、49→57；补 `blocklight.glsl`/`lib/colors.glsl` 两行；修正与文件头矛盾的 4 行；消除 `:374` 与 `:195` 的内部矛盾。
7. **决策 F-4**：把 `SHADOW_FILTER_SOFTWARE` 加进 `ENUM_ARM_TOKENS`（**不要删除 token**）。
8. **更新 `design.md`**：三档→四档；§3.5 列出的 6 处量化漂移。
9. **仓库卫生**：`git rm --cached` 那 35 个 f32/npy（72.8 MB）+ 对齐 `.gitignore` + `git gc`；`main` 快进到 HEAD；删 5 个已合并的 `codex-*` 分支；给 `inspect_iris_properties.py` 加 `--minecraft-root`。

**第三批（P2，防复发）**
10. 补 CI（哪怕只是 `python qa/tools/check_pack.py` + `compile_glsl.py`），本次 4 个 FAIL 全部本可被拦住。
11. 补齐 check #12 的锚点（遍历 `set(opts)` 而非 `prof["BALANCED"]`）；给 `program.*.enabled` 的标识符加"必须是已发现选项"校验（这条能从 properties 侧独立于 SC-28 推理抓住 F-1 同类问题）。
12. 执行发布门（§3.3）：13 个 GPL 文件 + 3 个 Refrax 专有派生**必须重写或整包转 GPL**，且 `Astra/LICENSE` 与实际许可状态对齐。

---

## 6. 附：本轮实跑命令与原始结果

```text
python qa/tools/check_pack.py
  → 17 checks: 4 FAIL, 1 WARN, 12 PASS        [exit 1]

python qa/tools/compile_glsl.py
  → OPENGL_RENDERER NVIDIA GeForce RTX 4050 Laptop GPU
    OPENGL_VERSION  4.6.0 NVIDIA 572.83
    RESULT linked=270 failed=0 compute=27 compute_capable=true

python qa/tools/provenance_steadfast.py --quiet
  → verbatim=14 literal-suffix=2 rewritten=6 astra-only=35 total=57

python qa/tools/test_gate_sensitivity.py
  → 9 PASS / 2 MISFIRE / AssertionError at s11 (anchor found 0x)   [exit 1]
    （并在 %TEMP% 泄漏 64.5 MB 副本，已清理）

自写复核（已删除，结论并入本文）：
  - profile×settings 一致性：70/70 token 与原始默认零偏差；3 个选项不在任何 profile
  - Iris jar 字节码反汇编（1.8.12 + 1.11.2 双版本）：
      OptionAnnotatedSource.parseLine 仅识别 #define / const / #ifdef / #ifndef
      常量池中不存在 "#if " 或 "defined"
      仅 #ifdef/#ifndef 流入 parseIfdef（booleanDefineReferences 的唯一写入者）
```

**审查期间未改动任何 `Astra/` 源码**；为清理副作用已还原 `qa/bloom-lod-probe/results.json`，并删除本次临时编写的分析脚本与泄漏的临时目录。
