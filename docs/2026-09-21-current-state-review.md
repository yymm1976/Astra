# Astra 当前状态审查（2026-09-21）

**基准 commit**：`b20abd0`（2026-09-21 01:09，"Anchor the shadow distortion core to the shadow distance"）
**审查方式**：只读。跑地面真值工具（`check_pack.py` + `compile_glsl.py`）+ 对账 git 历史与 backlog 文档。
**性质**：不修改任何代码。目的是给出"此刻项目到底健康与否、re-audit 轮做到哪、还剩什么"的一张干净快照。

> **历史快照说明（2026-09-21 卡 D 轮加注）**
>
> 本文是一份**时间点快照**，不是当前状态。所审旧报告的基线是 **T5 `b20abd0`**；
> 截至本文加注时，仓库 HEAD 已推进至 **`d3ea2d9`（B 轮收尾）**，共 31 个提交之后。
> 对本文 58 项事实性断言逐条复核的结果为：**30 条确认 / 23 条已失效 / 5 条当时亦不成立（驳回）**
> （逐条表见 `qa/b9-current-state-review-verify-2026-09-21.log`）。
> 典型失效项：§1 的 `linked=267` 现为 **270**、§2 的 67 选项/182 入口现为 **71/186**、
> §5.1 的「session-log 断更」已被 T 轮收尾补齐。
>
> **因此：引用本文时只可引用其方法（地面真值工具 + 对账 git 与 backlog）与分类，
> 不可引用其数字；当前数字请以 `qa/checkpack-2026-09-21-t17-final.log`、
> `qa/glsl-2026-09-21-t17-default.log` 与 `docs/2026-09-21-full-review.md` 为准。**
> 保留原样的理由是：§5「流程与文档缺口」一节里有 survey 未覆盖的独立观察（其中一条促成了 T 轮收尾补齐）。


---

## 0. 一句话结论

**代码健康、双绿、无回归；真正的短板不在代码而在"实证"与"收尾纪律"**——全项目至今零帧率数据，且上一轮（09-20 re-audit）的 8 个执行 commit 没有一条写进 `qa/session-log.md`。

---

## 1. 地面真值（本次实跑，非引述）

| 工具 | 结果 |
|---|---|
| `qa/tools/check_pack.py` | **16 项检查：0 FAIL / 1 WARN / 15 PASS**。唯一 WARN = Voxy C5 未接线（长期已知、非阻塞） |
| `qa/tools/compile_glsl.py` | **RTX 4050 Laptop / NVIDIA 572.83 / GL 4.6 → linked=267, failed=0, compute=27, compute_capable=true**，三档 profile（PERFORMANCE..ULTRA）全编译通过 |
| `git status` | 工作树**干净**（0 未提交） |

> 与 09-20 汇总报告锚定的 `9df32df`（同样 267/0/27、0 FAIL/1 WARN）一致——**修复没有回退，反而在干净树上前进了 11 个 commit**。

---

## 2. 规模与成熟度快照

- **246 个着色器文件 / ~9,800 GLSL 行 / 381 最长行 / 0.451 注释比**（survey：行数约为一线包中位数的 55%，最长行全场最短一档，注释比全场第二）。
- **67 个选项**（27 bool + 40 slider/enum），7 大分类，zh_CN + en_US 双语全覆盖。
- **182 个编译入口**，3 档 profile 各 67 token。
- **10 个 compute 阶段**（world-1 下界体素彩色光 shadowcomp + A–H 共 9 个 + `nether_light.csh`）——这是 design.md "零 compute" 的**唯一已登记例外**（README:20 已如实标注）。
- **10 张 colortex（0–9）+ shadowcolor0**；4 种 tonemap 算子；6 个 enum 选项。

结论：这已是一个**功能完整、组织干净、可编译、可配置**的成熟 v1 包，不是半成品。

---

## 3. 09-20 re-audit 轮执行盘点（本次审查的核心增量）

`9df32df`（三方审查修复）之后，`main` 又前进了 **9 个 commit**，执行的是 `docs/2026-09-20-shader-pack-design-survey.md` §6 列出的 P0/P1/P2 工单中**"低风险、可静态验证"的前段**。

### 已落地（有 commit + check_pack 新增项佐证）

| 工单 | commit | 落地内容 | 验证 |
|---|---|---|---|
| P2-10 上游隔离 | `e1f5304` | 建 `lib/vendor/` + README，许可文本不外溢 | check #15 |
| P2-11 缓冲声明治理 | `e1f5304` | 60 条活跃声明覆盖 10 缓冲，注释里 0 隐藏声明 | check #14 |
| P2-12 选项穷举编译 | `b7b2aff` | 每个选项两值都编译；删 84 个无人读的 marker define；83 行矩阵 | check #13 |
| P2-18 维度裁剪 | `452f460` | 下界 compute 按维度门控；删 Iris 从不读的 key | check #16 |
| P1-5 / P1-9 阴影扭曲锚定 | `b20abd0` | `SHADOW_DISTORT_CORE=25.6` 固定格半径 + 解析逆（已核 `distort.glsl`，工程扎实） | 源码 |
| P0-1 档位梯子（**部分**） | `f952887` | 救活 DITHERING；随档变化 token 13→19 | check #12 |
| P1-16 前置（LOD 约定） | `cc18b33` | 清理 re-audit 注释腐烂 + 重锚 LOD 前提 | 源码 |

### 仍未落地（backlog 仍在）

- **P0-2 云阴影**（现 0 命中，19 款参照里 8 款有）——需真实现，survey 判定"必须是廉价 2D 形态"。
- **P0-3 自动曝光**——**与 design §4.1 直接冲突**（§4.1 已决"用日光压制取代自动曝光"）。采纳前须先翻案 §4.1 并写修订理由（survey:711 自标）。
- **P1-6 太阳/云遮蔽全局强度**——现为解析量，不采深度（survey 三大可核实缺口之一）。
- **P1-7 焦散烘焙进 shadow pass**、**P1-16 时域滤波水下光束主体**、**P1-17 水体吸收侧面/实时项**。
- **P2-13 MIT 复用清单**、**P2-19 分辨率旋钮**（`RENDER_SCALE` 目前是死的——滑杆在 properties 里被注释）。
- **P2-20 水下光束标定**——需实机对拍。

> ⚠ **P0-1 只算"部分完成"**：check #12 结构上 PASS，但差量密度只有 22%/10%/28%、可变 token 19/67，**远未达 survey §9.4 的验收线（≥35 token / ≥50% 密度）**。且这道落差**没有任何文档记录**，自动化门禁也看不见（check #12 只报告密度，不设阈值）。

---

## 4. 未决前提台账（`qa/open-premises.md` P-1..P-6，全部仍未闭环）

| # | 前提 | 卡在 |
|---|---|---|
| **P-4** | **实机画面 + 帧率** | **`qa/benchmarks.md` 是空模板（所有 FPS 单元格空白）**；09-12 起六轮改动（晨昏/雨景/SC-39×2/性能轮/09-20 修复）**全无画面与帧率证据** |
| P-1 | hand 与 deferred 真实绘制顺序 | 需一次游戏内探针 |
| P-3 | 跨驱动编译 | 全部证据来自 NVIDIA 4050；AMD/Intel/Mesa 零验证 |
| P-2 / P-5 / P-6 | 阴影乘链 / sunAngle 约定 / ClearColor 识别 | 各需一次 grep + 实机目测 |

**P-4 是总闸**：它一关，09-20 批次里标注"需实机对拍"的四项（光束标定、水色、植被透光、晨雾方向）+ P-1/P-5/P-6 + P2-20 全部无法从"源码正确"升级为"画面正确"。

---

## 5. 流程与文档缺口（本次审查**新发现**）

1. **session-log 断更**：`qa/session-log.md` 最后一条是 `9df32df`（"09-20 三方审查汇总修复"）；其后 **9 个 commit（`3b5ac22`…`b20abd0`，即整个 re-audit 执行轮）无一条会话记录**。re-audit 目前只存在于 survey §6 和 commit message 里，破坏了"每轮必登 session-log"的既定纪律。
2. **benchmarks.md 仍空**（P-4 持续）：全项目零帧率数据，任何性能优化都无法证明收益。
3. **`lib/vendor/` 只有 README**：P2-10 的"隔离结构"已就位，但上游代码实际搬入被推迟到 T16。
4. **P0-1 的半成状态无记录**：commit 做了部分、check 结构 PASS、但离 survey 目标一半的落差既没进 open-premises 也没进任何文档。

---

## 6. 需用户拍板的决策点

- **P0-3 自动曝光**：翻案 design §4.1（引进自动曝光）还是维持"日光压制替代"？（survey 已把冲突写明，倾向维持 §4.1、把 P0-3 降级。）
- **P0-1 档位语义**：是否投入把可变 token 推到 ≥35 / 密度 ≥50%，让三档真正拉开成本？（当前 19/28%。）
- **P-4 排期**：是否安排一次实机会话，一次性关掉帧率基线 + 4 项"需对拍" + 跨驱动冒烟？这是性价比最高的单点动作。

---

## 7. 建议的下一步（按性价比排序）

1. **补登 session-log**（5 分钟）：把 re-audit 执行轮（`46fafab`..`b20abd0`）按模板补一节，恢复纪律；同时把 P0-1 半成、vendor T16 推迟写进 `open-premises.md`。
2. **安排一次实机会话**（最高价值）：加载冒烟 → 填 `benchmarks.md` 三档帧率基线 → 出 4 张"需对拍"图（光束/水色/植被透光/晨雾）→ 若有无印厂机器则跑一次跨驱动编译。可一次性关闭 P-4、P-1、P-5、P-6、P-3 与 P2-20。
3. **随后做低风险视觉缺口**：P0-2 云阴影、P1-6 太阳遮蔽（survey 判定廉价且 Astra 现无）。
4. **P0-3 先决策再动手**，避免与 §4.1 撞车。

---

## 附：本次引用的地面真值命令

```
python qa/tools/check_pack.py        # 16 checks: 0 FAIL / 1 WARN / 15 PASS
python qa/tools/compile_glsl.py      # linked=267 failed=0 compute=27 (RTX4050/572.83/GL4.6)
git log --oneline -12 ; git status   # clean tree, HEAD b20abd0
```
