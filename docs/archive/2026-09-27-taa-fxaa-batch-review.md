# TAA/FXAA 批次审查报告（2026-09-27）

审查对象：另一会话已完成的 A1–A3、B1–B3、T1–T3 批次（工作区未提交改动，HEAD `9f1a931`；28 个修改 + 39 个新增代码文件）。审查者独立取证对账：总账与 `git status` 逐文件对平，S1–S4 批次文件确认无混入。

**判定：需修后复查（0 Critical / 1 Important / 2 Minor）→ Important 已由审查方修复（纯文档改动），按审查者注记「改后可过」。**

## Findings

| 判级 | 问题 | 位置 | 处置 |
|---|---|---|---|
| Important | **「旧 FXAA 布尔选项已迁移」失实**：全 Git 历史（`git log --all -S "FXAA"`）不存在该选项，迁移无对象；契约与 README 向用户描述了一条从未存在的设置的迁移指引 | `docs/2026-09-26-itt32-initial-implementation.md:55`、`Astra/README.md:7` | **已修（2026-09-27，审查方）**：两句改写为「抗锯齿为本包新增的三选一设置，不存在被迁移的旧选项」 |
| Minor | `ANTIALIASING` 的源码描述注释错位（define 的上一行是 DITHERING 的描述，lang 缺失回退时会串文本） | `lib/settings.glsl:214-216` | 遗留，建议把描述行移到 define 之上 |
| Minor | colortex17 的 identity.y/z（前帧投影参数）写而不读（每帧 8 字节死数据；投影变化判定已由逐元素比较覆盖且更完整） | `program/taa_state.fsh:17`、`lib/taa_state.glsl:16-20` | 遗留，可留可删 |

## 三个核对问题结论

1. **TAA 数学与失效**：jitter 与 `screen_view`/`view_screen` 严格互逆（同一 `astra_jitter_uv()` 加减对）；全部 21 个 gbuffers vsh 经 lit.vsh 统一抖动；手动投影点全部收敛到 transforms；重投影不加前帧抖动（历史在未抖动网格）；T2 失效清单（帧序/视口/介质/维度/首帧/位移>8格/失明黑暗闪电/帧间隔>0.25s/投影逐元素/旋转>60°）逐条在 `lib/taa_state.glsl` 找到对应，无遗漏无超出。
2. **选项迁移**：无残留死路径、无档位缺口；AA=0/1/2 门控矩阵完整（6/7/8 与 colortex13/15/16/17 联动正确，AO 调试互斥正确），四档 profile 与 lang 双语一致。唯一问题即上表 Important（已修）。
3. **缓冲预算与索引**：35.596/31.641 MiB、colortex14 256 KiB 与声称逐位吻合；colortex13/15/16/17 在 HEAD 无占用冲突，blend 键 17 个与 lit/unlit wrapper 一一对应，渲染目标索引映射逐分支核对无错位。**运行时分配与跨帧保留需实机确认。**

## 其余验收抽查（全部通过）

A1 五群系权重与双消费者共用 ✓；A2 faceData 两位分类与四组参数逐字一致 ✓；A3 colortex11 258×128 双接缝 gutter 写读自洽 ✓；B1 colortex12 预乘 + 近距局部步进 ✓；B2 256² R16、512 格范围、边缘回落、`ASTRA_CLOUD_SHADOW_WRITE` 防自采样 ✓；THIRD-PARTY 的 Arc MIT 出处与 LICENSE 原文、常量吻合 ✓；维度门控（含 5 个新增文件夹 false 门）逐个核对无错误 ✓；T3 首版限制的文档表述与代码如实一致，无夸大 ✓。

## 移交主任务的待办（审查遗留）

1. check_pack **#12**：`ANTIALIASING` 加入 TIER_MONOTONE/NonCOST 分类（check_pack.py 正由主任务编辑中，避免并发未代改）。
2. check_pack **#15**：`global/post/fxaa.glsl` 许可文本挪入 `lib/vendor/`（或按包内既有 vendor 约定处理）。
3. 两条 Minor（settings.glsl 注释位置、colortex17 死字段）修不修自定。
4. 实机验证清单：colortex16/17 扩展索引运行时行为、CLOUD_VANILLA 云像素深度标记、文件夹 false 门在 Iris 的解析、TAA 画面质量（斜坡深度拒绝、0.65 下界权重、抖动柔化）。编译证据已有：RTX 4050 `linked=306 failed=0 compute=27`。

## 覆盖声明

已审：范围内 71 个代码文件全部逐文件/diff 审读，五条验收线（阶段表、历史资源、设置迁移、THIRD-PARTY、维度门控）。未审：S1–S4 批次（已另审通过）、docs 类文件。因缺材料未审：check_pack #16 原始报告、一切运行时行为。
