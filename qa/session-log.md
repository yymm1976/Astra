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

## 2026-09-06 Z 系收尾（选项注册规则 + 防回归 + 截图归档）

- SC-28（选项注册规则实证）：反编译 iris-fabric-1.11.2 常量池确认 OptionAnnotatedSource 仅解析
  #define/const/#ifdef/#ifndef——布尔选项必须在着色器源中存在 #ifdef/#ifndef 引用才注册，
  `#if defined NAME` 不可见，孤儿选项被丢弃。据此修复 GODRAYS：program/final.fsh 两处
  `#if defined GODRAYS && !defined ...` 重构为嵌套 #ifdef/#ifndef（语义等价），同步实例。
- 预期 WARN×2（非缺陷）：UNDERWATER_PARTICLES（C2 接线后自消）、VOXY_SUPPORT（C5 接线后自消）。
- check_pack.py #11 新增 SC-28 检查：70/25 布尔选项已接线，GODRAYS 通过。
- 截图归档：qa/screenshots/2026-09-06/ 共 9 张（01-05 Astra 现状，06-07 Steadfast 水面参考，
  08-09 Solas 水下参考）+ README。注意：06/07 实际视角为水下、08/09 为水面，E4 裁决时须
  同时写明用户标签与实际视角。
- 遗留：#6 custom uniform 顺序（astraBlocklightSuppression 引用后置的 skyVisibilityDay）与
  #8 provenance 计数（SC-14 待拍板）为既有 FAIL，归 Z6/E 系后续处理。
- 并行会话提示：global/water/ 三模块（absorption/caustics/refraction）工作区与实例出现差异，
  系高级Ⅱ SC-24 换源重写进行中，归 C2 会话所有与同步，Z 系不触碰。

## 2026-09-06 Z 系验证续行（顶级Ⅰ 额度耗尽后的编译与静态验证）

- 顶级Ⅰ 交付：14 个着色器文件的 P0/P1 修复（fog/sky_minishita/surface/absorption/caustics/
  refraction/settings/deferred/final/lit/scene/water/shaders.properties）+ p01_sky_diagnosis.py
  诊断工具 + check_pack.py 扩展（+154 行）。
- Z 验证结果：check_pack 11 项 0 FAIL / 2 WARN（VOXY_SUPPORT 待 C5、include graph 待 C5）/
  9 PASS；compile_glsl.py 在 RTX 4050 驱动（OpenGL 4.6, 572.83）上 linked=225 failed=0。
- 同步：顶级Ⅰ 未同步实例，Z 传播 7 个过期文件，diff 校验两份完全一致。
- 待用户：按 docs/2026-09-06-first-visual-round-fix-order.md 的顺序重载验收
  （P0 天空 → P0 远山 → P1 水 → P1 水下/粒子 → P2 帧率），每步同机位截图对照。

## 2026-09-07 整体审查（SC-32）

- 用户最新安排：禁止下放及子代理，当前模型独立修改；集中交付后再由用户提供画面，覆盖上述逐项中断要求。
- 完成原生/Voxy矩阵隔离、低仰角天空与远雾同源、PCF去重复提亮、折射完整光路混合、视差幅度/足迹修正、SSR无效追踪跳过、颗粒移到final并采用世界晶格，以及godrays数值边界修复。
- 现有check_pack：11项，0 FAIL / 2 WARN；两条仍为C5映射/VOXY_SUPPORT未接线，未用空引用消除。
- RTX4050驱动编译225组链接成功、0失败，记录于glsl-compile.log；随后针对水面粗糙度的相位无关改动编译9组水程序，0失败，记录于glsl-water-sc32.log。此记录不等同于Iris重新加载或游戏画面。
- Astra目录已复制到指定26.2实例，工作区与实例diff无差异。
- E4仍保留三对标退回；水下角向散射不等于遮挡分束。第二轮143–170仅为截图瞬时FPS，不能用于认定本次性能或持续达标。架构与责任见design.md及visual-verdicts.md的SC-32记录。

## 2026-09-07 水下分束续作（SC-33）

- 当前模型独立读取五份交接、Git 与工作区，确认 SC-32 只有角向亮晕；新增 light_shafts.glsl，复用 composite/final 实现视线阴影积分与距离约束合成。
- 三档水下阳光束默认开启，16/24/32 段；独立于空气 GODRAYS。双语与三档设置、出处和 design.md 决议已更新。
- 默认相关程序 45 组、选项组合 12 组在 RTX4050 驱动编译链接成功；对应 glsl-shafts-*-sc33.log。选项和模块登记无新增未接线项，仍保留既有 Voxy 提示。
- 10 个包内文件已同步指定 26.2 实例，复制后文件内容一致。未发现运行中的 Minecraft，尚无 SC-33 游戏画面／本次帧率。
- 下一步按 docs/2026-09-07-underwater-shafts-handoff.md 集中提供修改后的画面；E2/E4 视觉与 E3 帧率不据源码或驱动编译判为通过。

## 2026-09-07 水体/阴影/光照重构续作（SC-34，额度耗尽后由当前模型续行验证）

- 续行前提：以磁盘与 Git 为唯一事实来源，未重做也未回滚 SC-34 既有修改（水体传播、阴影坐标/偏移、
  火把光色、水下光照、光束衔接）。`.specs` 与 docs 内无 SC-34 条目，说明上一轮未及落档。
- 时间戳核查发现旧日志已过期：`qa/glsl-water-shadow-sc34.log`（19:50:50，225 组）早于最后一批源码改动
  （19:53:06 的 colors/raytrace/light_shafts/caustics/shadowmap），故 BALANCED 结论不能直接沿用。
- 驱动编译（RTX 4050 / NVIDIA 572.83 / OpenGL 4.6，独立上下文，不含 Iris 注入与实际渲染），全部 0 失败：
  - BALANCED 默认 75 组 → qa/glsl-water-shadow-balanced-sc34.log
  - 极端组合 A（水/阴影/光束/后处理全关 + 强度取 0）75 组 → qa/glsl-water-shadow-extremeA-sc34.log
  - 极端组合 B（全开 + 阴影/吸收/光束/雾取上限）75 组 → qa/glsl-water-shadow-extremeB-sc34.log
- check_pack 11 项：1 FAIL / 2 WARN / 8 PASS；`git diff --check` 无空白错误。
  新增 FAIL 为 #8：`global/water/absorption.glsl` 经 SC-34 重写后不再带 `From <来源包>` 出处头，
  而 THIRD-PARTY.md 仍记为派生行。不阻断加载，属 SC-14 发布门禁，处置待用户拍板：
  (A) 补回出处头（保守，维持派生标记）；(B) 台账改记 Astra 自写。SW-2 未擅自改出处。
  两条 WARN 仍为既有 C5/Voxy 未接线项。
- 新增 qa/tools/sync_to_instance.py：哈希比对 + 复制 + 复制后复校（取代此前无回显的 robocopy 调用）。
  本次同步 19 个文件到 `D:\zhenhebao\.minecraft\versions\生电优化整合包 (Fabric)\shaderpacks\Astra`，
  复制后逐文件复校 Content differences after copy: 0，Missing 0，Extras 0；复跑 Copied 0（幂等）。
- 状态：未改任何视觉参数，无本轮游戏画面。SC-34 第一轮实测待用户提供，重点六项见用户清单
  （晴天浅水水下地形、水面上下切换、岸边/树荫水下光与光束、洞穴火把色偏、移动时阴影跳变、转视角稳定性）。

## 2026-09-07 SC-34-F1 新四图光路续修

- 新截图依据：`qa/screenshots/2026-09-07-sc34-followup/01–04`；旧工作区含 SC-34 与后续代码，保留已有坐标、阴影及光源谱改动。
- 修正水下反射命中/折射天空丢失、界面方向与 Fresnel、逐点颜色/深度/水程、SSR 命中重建、散射光源分工、焦散直射范围与沙色 bloom 外溢。
- GPU 人工几何诊断结果：`qa/water-path-followup/results.json`。普通白色以下 bloom=0，朝相机返回的反射命中有效，分段传播误差约 1.64e-7；不属于游戏画面。
- 最终 600 组驱动编译成功；用户要求的默认档位及五个关闭/零值配置均各自覆盖。`check_pack.py` 无失败、两条既有 Voxy 提示；`git diff --check` 无空白错误。
- 已同步指定实例，12 个包内文件更新；214 个文件逐一比较，差异/缺失/额外均为 0，见 sync.json。
- 详细数据流与实现边界：`docs/2026-09-07-water-path-followup.md`。下一步重新加载 Astra，集中实测七类场景；水面、水下、halo、阴影和火把颜色不标视觉通过。
