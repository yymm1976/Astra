# Astra 未提交改动检查点审查报告（2026-10-04）

> 2026-10-04 接续处理说明：选项解析、配置补漏、旧工具引用、入口分层、共用缓冲格式、许可存放与来源台账已作源码修复，详见 [接续修复](2026-10-04-review-followup-fixes.md)。本文其余内容保留审查时点记录；当时的工具输出不代表修改后的状态。本轮未新增游戏画面或帧率结论。

基线 HEAD = `9f1a931`（2026-09-26），审查对象为全部未提交工作区改动。本报告只审查、不修改；所有结论来自本次实际执行的命令输出与当前文件内容。范围：`Astra/` 已跟踪改动 88 文件（+4163/−2045）+ 1 删除（`lib/water_light_field.glsl`）+ 90 项未跟踪新模块，另含 docs 17 个删除、`docs/README.md` 与 `qa/tools` 三个工具的修改。排除 `reference_shaderpacks/`、`shader_research/`、`_analysis/`、qa 日志（参考资料，另行处理）。上一份同范围审查为 [2026-10-02 未提交改动审查](2026-10-02-uncommitted-changes-review.md)，其 33 条 findings 已逐条对账（见下）。

## 判定

**需修后复查**（3 Important / 0 Critical；依据「0 Critical + 0 Important 才可通过」）。

核心理由：项目自带静态门禁 `check_pack.py` 仍为红灯（7 FAIL，退出码 7）；编译门禁彻底不可用且 10-02 审查 F-0 指出的工具根因**未修**（当前被缺 LWJGL 的环境错误掩盖），全批改动自 10-01 以来没有任何编译证据；已删除的 `water_light_field.glsl` 在 `qa/tools/underwater_light_probe.py` 存在一处悬挂引用。渲染接线本身（prepare 链 / deferred 槽位表 / TAA / 下界 SSR / SH9 / effect_history）经逐链核查**未发现断裂点**。

快照窗口声明：审查开始 2026-10-04 12:22:59（109 文件 +4348/−3989，status 296 条），结束 12:44:03（**110 文件 +4477/−4009，status 299 条**）。窗口内 25 个文件被并发改写（含新增 `Astra/shaders/deferred3.fsh`/`deferred3.vsh` 与 `lit.vsh`、`shaders.properties`、`deferred.fsh/1/2`、`taa_resolve.fsh` 等已下结论文件），故本报告行号对应 12:44 左右快照；对关键结论点（F-2 末地阴影、deferred 槽位表、门禁结果）已在窗口末的当前内容上二次复核，`check_pack.py` 也在窗口末重跑一次，FAIL 集合不变。

## Standards

### [Important] 项目静态门禁 7 FAIL 未清零（阻塞提交前置条件）
位置：`qa/tools/check_pack.py`（退出码 7；两轮运行 12:26 与 12:46 FAIL 集合一致）
证据：`[FAIL] #2`（`sunPathRotation` 出现在 `screen.SKY` 与四档 profile 但非 settings.glsl 选项；四档另缺 `PURKINJE_STRENGTH`、`ROUGH_SKY_REFLECTIONS`、`STAR_AMOUNT` 三个质量选项）、`[FAIL] #3`（两种语言各 1 个 `sunPathRotation` key 无对应选项）、`[FAIL] #4`（`global/dimension/nether_volume.glsl` 孤儿且未登记 PENDING_CONSUMERS；`deferred.fsh`/`deferred1.fsh`/`deferred2.fsh`/`prepare2.fsh` 四个 layer-1 壳直接 include `lib/settings.glsl` 违反 design 3.2）、`[FAIL] #8`（THIRD-PARTY.md verbatim 计 14 vs 表达式差 12；astra-only 计 35 vs 表达式差 135）、`[FAIL] #11`（`colortex9Format` 在 `program/end_sky_buffer.fsh:10` 与 `program/nether_reflection.fsh:16` 重复声明）、`[FAIL] #12`（四档 profile 与 settings.glsl 默认值差 3 个选项）、`[FAIL] #15`（`global/post/fxaa.glsl` 在 `lib/vendor/` 之外携带许可全文）。
影响：这是项目自订的合入门禁，10-02 报告已要求「提交前先清零」，当前仍红。
机制：多为「包侧接线走在工具/账本前面」的登记缺口，不是运行时损坏；但按本次验收口径「门禁 FAIL = 缺口」计 Important。
建议：#2/#3/#12 需决策「教工具识别 `const float … // [取值]` 型 Iris 内建选项」（10-02 F-0 的原建议）或撤接线；#8 重跑 `provenance_steadfast.py` 后重写台账计数；#11 二选一删除重复声明；#4 给 `nether_volume.glsl` 登记归属或接线，壳分层违规要么改设计 3.2 条款要么把选择宏下沉；#15 将许可文本移入 vendor 或登记豁免。

### [Important] 编译门禁不可用，且 10-02 F-0 的工具根因未修、只是被掩盖
位置：`qa/tools/compile_glsl.py:206-231`（`apply_profile_settings` 仅认 `DEFINE_RE` 即 `#define` 形式选项）、`:451`（`lwjgl_classpath` 在 main 中先于选项展开执行）；`Astra/shaders/lib/settings.glsl:341`
证据：`python qa/tools/compile_glsl.py --profiles BALANCED` → 退出码 2，报 `missing LWJGL files … lwjgl-3.3.3.jar` 等 6 个 jar；实际核查 `C:\Users\杨铭\AppData\Roaming\.minecraft\libraries\org\lwjgl\` 目录不存在（另查了桌面 .minecraft 根，同样没有）。同时源码级确认：`shaders.properties:501` 的 `profile.BALANCED` 含 `sunPathRotation=-40.0` token，`parse_profiles`（:187-203）原样透传，而 `apply_profile_settings` 的 `DEFINE_RE` 匹配不到 `settings.glsl:341` 的 `const float sunPathRotation = -40.0; // [...]`——一旦补齐 LWJGL，预检会再次抛 `option not found in settings.glsl: sunPathRotation`（10-02 F-0 原样复现）。
影响：与 10-02 结论一致且更实——本批全部改动（含并发会话仍在写的 25 个文件）没有任何编译证据；LWJGL 缺失是环境限制，但工具根因是代码事实。
建议：先修 `compile_glsl.py`/`check_pack.py` 对 Iris 内建 const-float 选项的识别，再补齐 LWJGL 3.3.3（或用 `--minecraft-root` 指向含该库的实例），跑通 `--profiles BALANCED` 后本批才有合入资格。

### [Important] 已删除模块在探针工具中的悬挂引用
位置：`qa/tools/underwater_light_probe.py:17`
证据：该文件仍 `#include "/lib/water_light_field.glsl"`，`:28` 调用 `astra_water_phase(...)`，`:93` 仍断言 `astra_water_phase/_beam_tint/_beam_limit` 存在于 shaft 源码；`grep -r water_light_field Astra/shaders/` 为 0 命中，函数名在全包亦无定义。
影响：`Astra/shaders` 包内确无残留，但唯一残留正在探针工具：该工具已无法编译，作为 10-03 水下系列的行为取证手段已失效。
建议：按现行 `shadow_water_transmission`/光束实现重写探针，或在工具头声明退役并从 qa 工具清单摘除。

### [Minor] `Astra/shaders/python` 是 0 字节杂散文件
位置：`Astra/shaders/python`（未跟踪，0 字节，mtime 10-02 19:38）
证据：`ls -la` 与 `file` 确认为空文件而非目录。
影响：随包分发毫无意义，且疑似某次 shell 误重定向产物；提交前应删除。

### [Minor] 换行符噪声混入改动（约 145 行/侧）
位置：`git diff HEAD --ignore-all-space` = +4203/−3844 vs 全量 +4348/−3989
证据：差值 ≈145/145 行为纯空白（CRLF→LF 提示覆盖 57 文件）。
影响：干扰逐行对账与后续 blame；仓库无 `.gitattributes` 归一化规则。
建议：提交前决定统一换行策略（加 `.gitattributes` 或按文件 `--ignore-all-space` 分解提交）。

### [Minor] `colortex9Format` 双重声明
位置：`Astra/shaders/program/end_sky_buffer.fsh:10`、`Astra/shaders/program/nether_reflection.fsh:16`
证据：两处均为 `RGBA16F`，取值一致故无冲突（check_pack #11）。
影响：改格式时只改一处会静默失配。
建议：留一处（如 end_sky_buffer），另一处删除或注释指向。

## Spec

**需求遗漏**：未发现 12 份 docs 声明与代码的矛盾点。抽查均吻合：README:23 现已如实写明「默认水反射宽过滤最多 20 角点、高档 36，相对最近提交版本 16 是增加」——10-02 F-12 指出的口径反向问题已修正；`water.glsl:83-89`（maxFootprints 1/5/9、`radius > 0.35`）与之一致。README:86/88 的方向性天光/AO/云历史开关描述在 F-3 修复后已可执行。THIRD-PARTY.md:566-567 对 musk-rose（CC0-1.0，`lib/vendor/musk-rose/LICENSE.txt` 随包）与 ：317 对自生成末地纹理（`astra-end-flow-mips.png` 已注册 `customTexture.astraEndFlowMips`，properties:471）登记在案。
**Scope creep**：未发现越出白名单的行为；并发窗口新增的 `deferred3` 槽位是既有 deferred 槽位表的补全（PLANAR+AO+VOLUME 三开时的场景合成位），已正确写入 properties 门控（:243-251），未产生新门禁失败。
**实现偏差**：未发现。注意 10-02 报告自身有两处结论被后续 docs 纠正且本次独立复核证实（见下表 F-2、F-5）。
**限制**：12 份行为文档为抽样核对（纠正小节全文 + README 关键声明 + 门禁/接线全查），未逐行核对每份 docs 的每个数字；Spec 轴结论在该限度内成立。

## 10-02 审查 findings 逐条对账

| # | 状态 | 当前证据 |
|---|---|---|
| F-0 工具链 | **仍在** | `compile_glsl.py:206-231` 仅认 `#define`；settings.glsl:341 为 const float；现被 LWJGL 缺失掩盖（退出码 2） |
| F-1 焦散夹平 | **已修（换方案）** | `shadowmap.glsl:67-79` `shadow_water_transmission`→`shadow_water_caustic_gain` 标量增益，峰值可 >1（渐近 1+contrast/0.6），`shadow.fsh` 仍 RGBA16F；无 clamp |
| F-2 末地阴影失效 | **不成立（10-02 误读）** | `lit.vsh:184` 条件 `SHADOWS && !NETHER && !ASTRA_WEATHER` 在末地走第一分支；内层 `!defined DIMENSION_END`（:186）只管主世界 receiver 早退，末地无条件调 `shadow_map_position`；`scene.glsl:254`→`end.glsl:43-45` 正常消费。docs/2026-10-02-module-performance-refinements.md:46 的反驳正确，本次两次独立复核证实 |
| F-3 三选项未注册 | **已修** | 裸 `#ifdef`：`program/deferred.fsh:6`、`global/lighting/diffuse.glsl:4`、`program/cloud_screen.fsh:8`；实际消费走带维度守卫的 `ASTRA_*` 宏（settings.glsl:471-494） |
| F-4 体素共享内存 | 未判定 | 性能取舍需实机；`nether_light.csh` 在窗口内仍被改写 |
| F-5 一维 PCF | **部分不成立** | `diffuse.glsl:286` `vec2(标量)` 同时填 X/Y（对角两中心），「offset.y 恒 0」是误读；2 lobe vs 4 lobe 的核数减少为真，属已登记取舍 |
| F-6 雨滴颜色猜测 | **仍在（已登记）** | `rain_particles.glsl:10-11` `b > 0.74` 阈值；README:19 与 THIRD-PARTY 10-03 条目均登记该局限 |
| F-7 下界雾入 BORDER_FOG | **仍在** | `nether.glsl:74-79` `fogFactor = 0.0` 仅在 `#ifdef BORDER_FOG` 内赋值 |
| F-8 掠射云影反转 | 仍在（有意已登记） | 维持 |
| F-9 colortex9=1.0 | **仍在** | `shaders.properties:51`；refinements 文档明确保留（colortex9 末地也在用） |
| F-10 colortex1 条件异源 | **仍在（方向安全）** | `properties:17-24` 无维度条件 vs `settings.glsl:504-508` `ASTRA_UNDERWATER_SHAFTS` 带 `!NETHER && !END`；消费者 `display.fsh:21-24` 守卫正确，不会读到未初始化数据 |
| F-11 死代码 6 处 | **大体已修** | 死定义已删（#13 PASS）；`windStrength/windTheta` 已从 properties 移除；`ASTRA_CLOUD_SHADOW_TEXEL` 已删；sky_sh9 三函数现有消费者（`sky_irradiance.fsh:32`、`sky_directional.glsl:17`）；`temporal.glsl` 已登记 PENDING_CONSUMERS。唯一残留：`nether_volume.glsl` 仍孤儿（FAIL #4） |
| F-12 反射角点净增 | **仍在（口径已修正）** | `water.glsl:83-89`；README:23 现如实声明相对 HEAD 增加 |
| F-13 unshiftedPath 死分支 | **仍在** | `water.glsl:452-474`；docs 声明为有意保守选择 |
| F-14 探针悬挂引用 | **仍在** | `qa/tools/underwater_light_probe.py:17,28,93`（上列 Important） |
| F-15 temporal.glsl 附件冲突 | **已按建议处理** | 已登记 PENDING_CONSUMERS 并注明「附件号已由 28/29 复用」；README:90 同步说明 |
| F-16 光束距离衰减 | 仍在（对齐 Solas，有意） | 维持 |
| F-17 TAA 常数权重 | **仍在** | `taa_resolve.fsh:155` `mix(0.92,0.70,motion)`，无 frameTime；refinements 文档部分反驳后保留现状 |
| F-18/F-19 reactive 粗判 | **仍在** | `deferred.fsh:168-175`；已登记为有意保留 |
| F-20 TAA 开销 | opt-in 特性，关闭路径已核为零成本 | `properties:88-116`（关闭时 15/16/22/17 全缩 1×1、composite6/7 全维度停用） |
| F-21 无编译证据 | **仍在且更实** | LWJGL 缺失已实锤 + 工具根因未修 |
| F-22~F-25 SSAO 细节 | opt-in 特性，未重算账目 | 关闭路径已核（19/20/21/26/27 缩 1×1、deferred2 停用） |
| F-26 AO 附件全局分配 | **仍在（已登记保留）** | refinements 文档明确本轮不回收 |
| F-27 colortex27 alpha | **已闭（口径澄清）** | refinements 文档区分存储 alpha 与源 alpha；README:86 已按 R11F_G11F_B10F 记载 |
| F-28 rockSmoothness | **已修** | `lit.fsh:473` `gl_FragData[1].a = rockSmoothness` 有消费者；`block.properties:63` 注释已更新 |
| F-29 CLOUD_TEMPORAL 不可发现 | **已修** | 见 F-3；README:88 已载明开关 |
| F-30 云生产者 1e20 | **仍在（反驳成立）** | `cloud_screen.fsh:26` 仍传 `1e20`；refinements 文档指出 prepare1 先于地形光栅、用深度裁剪会引入缺失，理由成立 |
| F-31 采样账目 | 未重核 | 文档记账类 |
| F-32 TEXEL 无读者 | **已修** | 全仓 0 命中（定义已删） |
| F-33 原版云逐片元 discard | **仍在** | `program/clouds.fsh:26-31`；无 `.enabled=false`，属可选性能项 |

## 新增模块三维度与关闭路径接线完整性

**未发现断裂点。** 逐链核查结果（全部基于当前文件内容）：
- **prepare 链**：根 `prepare`(sky_reflection_cache→11)/`prepare1`(cloud_screen→24,25｜12)/`prepare2`(cloud_shadow_cache→14)/`prepare3`(sky_irradiance→18) 仅主世界：world-1 四者全 `enabled=false`；world1 `prepare`=end_illumination(→8)，prepare1/2/3 停用；prepare3 另受 `DIRECTIONAL_SKYLIGHT` 门（properties:118-127，colortex18=9×1）。云历史关闭时 cloud_screen 内部切 RENDERTARGETS 12，`CLOUD_MODE != 1` 时 24/25 缩 1×1。
- **deferred 槽位表**：`deferred`(PLANAR→cloud_screen｜SSAO→ssao→21,26｜VOLUME→volume_main→23｜否则 program/deferred→0,4,16)、`deferred1`、`deferred2`、新 `deferred3`（AO+VOLUME 同开时的场景合成位）互相覆盖四种组合无重叠漏位；world-1 `deferred1/2/3` 停用且 `world-1/deferred` 直通 program/deferred；world1 `deferred`=end_sky_buffer(→9)、`deferred1`=program/deferred（DIMENSION_END）、deferred2/3 停用。AO/VOLUME 任一关闭时对应附件缩 1×1、阶段停用、消费端由 `ASTRA_SSAO`/`ASTRA_VOLUME_FOG` 编译期剔除。
- **TAA**：composite6(taa_resolve→0,15)/composite7(taa_state→17,0) 由 `ANTIALIASING==2 && DEBUG_VERTEX_AO==0` 门控且**三维度同步开合**（properties:88-104）；composite8(display→13) 为 FXAA 路径三维度同步；关闭时 15/16/22/17 全缩 1×1、9 处门与 settings.glsl 宏一致。
- **effect_history（colortex30）**：唯一消费者 `lib/effect_history.glsl`；生产者 composite9 根门=水下光束选项、world-1 门=SCREENSPACE_REFLECTIONS（下界 SSR 的 28 号历史）、world1 恒关——与「colortex29 仅主世界消费、colortex28 仅下界消费、末地无历史消费者」精确互补，不存在读未初始化历史。
- **下界 SSR**：world-1/composite(nether_reflection→9,28)与 composite1(nether_reflection_resolve→0)同受 SCREENSPACE_REFLECTIONS 门；composite2=program/composite1（Bloom 捕获→2，受 BLOOM 门）补上下界因 composite1 被 SSR 占用后的捕获位；display 在 NETHER/END 只读 colortex2、不读 colortex7（`display.fsh:34-37`），与下界无 water_bloom 一致。
- **sky_sh9**：生产者 `sky_irradiance.fsh`（定义 `ASTRA_SKY_SH_WRITE`，调 `astra_sh9_basis`）↔ 消费者 `sky_directional.glsl:17`（`ASTRA_DIRECTIONAL_SKYLIGHT && !ASTRA_SKY_SH_WRITE`）；10-02 的「accumulate 契约无执行点」已消除。
- **独立佐证**：check_pack #14「32 buffer / 110 声明全部活且唯一」与 #4「241 编译入口、84 可达、仅 1 个未登记孤儿（nether_volume.glsl，已知）」与本审查抽样一致。12:44 后新增的 deferred3 亦已正确登记门控，12:46 复跑门禁未产生新 FAIL。

## 覆盖声明

**已审**：改动总账对账（Astra 88 文件 +4163/−2045、1 删除、90 未跟踪，与任务书逐项对平）；两轮 `check_pack.py` 全量输出；`compile_glsl.py` 退出码与根因源码级确认；10-02 报告 33 条 findings 逐条取证；点名新模块（prepare 链、taa_resolve/state、ssao、nether_reflection、volume 链、sky_sh9、effect_history）在三维度与关闭路径的接线；README 关键声明（15-90 行抽样）；THIRD-PARTY/musk-rose/astra-end-flow-mips 登记；docs 纠正小节（refinements、batch4 全文，batch3/nightsky 定位）；并发改写检测（首尾快照 + 窗口内文件清单 + 关键点二次复核）。
**未覆盖**：实机加载、画面比照与帧率（从未做）；GLSL 编译验证（工具因 LWJGL 缺失不可用，且工具本身待修）；12 份行为 docs 的逐行数字对账（抽样）；F-4/F-22~F-25/F-31 的性能账目重算；末地 `end_geometry`/`end_kerr` 等文件深审（10-02 亦仅抽查）；`reference_shaderpacks/`、`shader_research/`（按任务排除）；12:44 快照之后的进一步变动。
**因缺材料未能审**：无——但「本批可编译」这一命题在本环境下无证据，属门禁缺口而非审查遗漏。

## 已核对的关键点（含所用命令）

1. 对账：`git rev-parse HEAD`、`git diff HEAD --stat/--ignore-all-space --stat`、`git status --porcelain`（首尾各一次）、`git diff HEAD --name-status -- Astra | grep ^D`、`git status --porcelain Astra | grep '^??'`（90 项）。
2. 门禁：`python qa/tools/check_pack.py`（3 次：退出码 7/7/7，FAIL 集合一致）；`python qa/tools/compile_glsl.py --profiles BALANCED`（退出码 2）；`ls C:\Users\杨铭\AppData\Roaming\.minecraft\libraries\org\lwjgl\`（不存在）。
3. F-0 根因：读 `compile_glsl.py:26,187-203,206-231,384-451`，`grep profile.BALANCED` 确认 token 含 `sunPathRotation=-40.0`。
4. F-2/F-1：`grep/sed lit.vsh:184-203`、`scene.glsl:237-254`、`end.glsl:37-60`、`shadowmap.glsl:55-110`、`shadow.fsh:20-45`、`grep define ASTRA_WEATHER`（仅 gbuffers_weather）。
5. F-3/关闭路径：`grep -E "#(ifdef|ifndef) (SCREENSPACE_AO|DIRECTIONAL_SKYLIGHT|CLOUD_TEMPORAL)"`（排除 settings.glsl 后各 1 处）；读 `settings.glsl:468-508` 宏守卫。
6. 接线：枚举 29 个 stage 壳的 `RENDERTARGETS`/include 映射；读 `shaders.properties:84-330` 全部门控；读 `deferred.fsh/1/2/3`、`volume_slot.fsh`、`world-1/composite{,1,2}.fsh`、`clouds.fsh`、`display.fsh` 头部；`grep colortex30/colortex11/colortex7` 消费者；`grep astra_sh9_` 消费者。
7. F-11/F-28/F-32 残留：`grep ASTRA_CLOUD_SHADOW_TEXEL`（0）、`grep windStrength/windTheta properties`（0）、`grep rockSmoothness lit.fsh`（:180,336,473）。
8. F-12/README 口径：`grep maxFootprints water.glsl`、读 `Astra/README.md` 15-90 行。
9. 许可：`ls lib/vendor/musk-rose/`、`grep -i musk THIRD-PARTY.md`、`grep customTexture properties`。
10. 悬挂引用：`grep -rn water_light_field Astra/shaders/`（0）与 `qa/tools/underwater_light_probe.py`（3 处）。
11. `Astra/shaders/python`：`ls -la`、`file`（0 字节文件）。
12. 并发改写：`git diff --shortstat HEAD` 首尾对比、`find -newermt "2026-10-04 12:20"`（25 文件）、窗口末重读 `lit.vsh`/`deferred*.fsh`/`shaders.properties` 复核关键结论。

**门禁原始输出摘要**：`check_pack.py` 末轮 `17 checks: 7 FAIL, 0 WARN, 10 PASS`（FAIL=#2,#3,#4,#8,#11,#12,#15）；`compile_glsl.py` 输出全文仅 `missing LWJGL files; use --minecraft-root or set ASTRA_MC_ROOT to a Minecraft root with LWJGL 3.3.3` 加 6 个缺失 jar 路径，退出码 2。

## 修复白名单建议（供下一轮使用）

`qa/tools/compile_glsl.py:206-231`（const-float 选项识别）、`qa/tools/underwater_light_probe.py:17-93`、`Astra/shaders/program/nether_reflection.fsh:16` 或 `end_sky_buffer.fsh:10`（二选一删）、`Astra/shaders/global/post/fxaa.glsl`（许可文本归位）、`Astra/THIRD-PARTY.md`（重跑 provenance_steadfast.py 后更新计数）、`Astra/shaders/shaders.properties:501` 区域 + `lib/settings.glsl:341`（sunPathRotation/STAR_AMOUNT/PURKINJE/ROUGH 的 profile 覆盖与工具识别，需先做方向决策）、`Astra/shaders/global/dimension/nether_volume.glsl`（登记或删除）、`Astra/shaders/python`（删除）。
