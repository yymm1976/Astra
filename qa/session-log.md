# Astra — 测试会话记录（Z7）

> 每次跑游戏冒烟/跑分后追加一节；原始日志放 `session-log/`（大文件不入库时可只留摘要与行号）。
> 截图存 `qa/screenshots/<Milestone>/<date>-<场景>.png`。

## 模板

```
## YYYY-MM-DD — <目的：冒烟/跑分/回归>
- 环境：MC <ver> / Iris <ver> / <loader> / 渲染距离 <n> / Voxy <on|off>
- 变更范围：<自上次会话以来合入的任务号>
- 结果：
  - 编译：<零错误 | 错误清单（文件:行 + 日志行）>
  - 回归清单：<通过的 # 项列表；失败项附证据>
  - 帧率：<qa/benchmarks.md 已更新？Y/N>
- 截图：<相对路径列表>
- 遗留问题：<转 tasks-advanced/top 的条目，或"无">
```

## 记录

### 2026-09-05 — B1–B5 离线交付（无实机，SC-6 ⏸）
- 环境：无实机（SC-6：本机无可运行 Iris 实例）。本节为**离线静态验收记录**，不是冒烟记录。
- 变更范围：tasks-advanced-1.md B1–B5（模块主体 + 各自拥有的 pass 程序；E1 未冻结，lit/final 一律未接线）。
- 结果：
  - 编译：无实机编译证据。静态层面 `python qa/tools/check_pack.py` = **11 项 9 PASS / 1 WARN / 1 FAIL**，
    与 B 系开工前基线一致；唯一 FAIL 仍是 #10（M1 最小 final 链，归 E1），唯一 WARN 是 #4
    （include 分层图：可达模块 **1 → 8**，待接线 32 → 25，0 项未登记）。
  - 回归清单（qa/regression-checklist.md）：实机项 #1–#20 **全部 ➖ 待 SC-6**。可离线核对的接口项：
    - #6（影内外过渡/彩影/玻璃不投影）：`shadow_mapping()` 的 5 格交叉淡化 + `shadow_map_fade()`
      已按 Steadfast 移植；`block.10010` 玻璃在 shadow.vsh 被剔除出 clip space；染色玻璃走
      shadowtex0/shadowtex1 差值 + shadowcolor0.GBA。**渲染层语义（染色玻璃是否落在 shadowtex1
      的不透明层）只能实机确认**，已列为 SC-6 冒烟重点。
    - #8（雾六情境）：大气/边界/洞穴/失明/熔岩/水下六分支在 `fog_v2()` 内齐全；
      `skyFogStrength` 输出已接 SKY_FOG_STRENGTH 并保留低值跳过优化。
    - #17（godrays）：曝光≤0 整 pass 早退在 `program/composite.fsh`；默认关由
      `program.composite.enabled=GODRAYS` + BALANCED profile `!GODRAYS` 双重保证。
    - #18（bloom）：软阈值 knee + BLOOM_SOURCE_CLAMP=16 抗无 TAA 火花；多级合成权重递减
      （0.40/0.30/0.20/0.10）+ additive 合成防灰雾。
  - 帧率：N/A（无实机）。
- 截图：无（`qa/screenshots/` 仍为空，SC-6 解除后按 B1–B5 验收标准各场景补拍）。
- 遗留问题：
  - `entityShadowDistanceMul = ENTITY_SHADOW_DISTANCE * (1.0 / SHADOW_DISTANCE)` 的 const
    表达式是否被 Iris 接受 —— SC-6 冒烟确认，不接受则退化为字面量 0.5（SC-13 已预案）。
  - 染色玻璃在 shadowtex0/shadowtex1 两层中的归属（决定彩影是否生效）—— SC-6 冒烟确认。
  - final 链两段（godray 平滑上采样、bloom 合成）归 E1/C6，接口契约已写在
    `program/composite.fsh` / `global/post/bloom.glsl` 文件头。

（暂无实机记录 —— 等待首次冒烟。首次冒烟建议在 E1/D1 之后进行，覆盖 M1 验收：
"Iris 在 1.21.x 与 26.1 加载零报错，三维度显示原版画面"。）

## 2026-09-06 E1/E2 接线交付

- E1：lit统一宏入口，18+4+10位逐面打包，9标量varying；root/world-1/world1完整20对几何壳。新增scene组合器复用B/C模块，final接既有C6并确保唯一sRGB编码。
- E2：五个水模块全部消费；deferred写raw背景副本与施加介质后的显示场景；透明链、深度归一、焦散足迹/退出、阴影原点修复；天空反射来自D2。HAND投影信息通过colortex3高bit传到deferred。
- 驱动结果：RTX4050/NVIDIA572.83/OpenGL4.6 compatibility；225组链接成功、0失败；水选项全关的三维度另3组成功、0失败。日志为glsl-compile.log、glsl-water-options.log。独立驱动结果不包含Iris注入/资源绑定/实际渲染。
- E2数学记录：water-stability.md；E3逻辑带宽账：bandwidth.md；E4九项材料退回：.specs/astra-shader/visual-verdicts.md。
- 用户环境已定位：MC26.2/Iris1.11.2/Voxy0.2.18-beta及4050；兄弟实例有1.21.x。已交付shaderpacks/Astra，实际选择/进入世界待用户操作，当前无本轮运行画面/FPS。
- C5仅解决默认加载阻断：按本地Voxy字节码语义清空voxy.json，不注册尚未完成的patch；完整适配仍未交付。SC-14的发布决策不在本次私人部署范围。
