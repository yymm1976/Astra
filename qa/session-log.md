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

## 2026-09-08 阴影-水修复轮（回退点 + 四修复项 + 编译验证）

- 应杨间要求先提交回退点：`6fcb0fd`（chore: checkpoint water/shadow visual-round work for rollback，
  196 文件 +5188/−1183，覆盖 SC-33..SC-35 全部未提交工作；回退 `git reset --hard 6fcb0fd`）。
- 提交前 check_pack：0 FAIL / 2 WARN / 9 PASS（WARN 为既有 VOXY_SUPPORT 未接线项）。
- 参考源码精读（只读）：Steadfast 0.8.0 单跳折射 + 单指数吸收 (16,3,1)/16m、
  Solas 水下雾色 glare×16 与 VL 4-12x 增益；确定本轮数值口径（自写等效曲线，无 Solas 表达式移植）。
- 新增 `qa/tools/shadow_frustum_probe.py`：接收端世界纹素/PCF 宽度/bias/fade 距离表；
  修复前后对比见 docs/2026-09-08-shadow-water-fix-round.md 第 2 节。
- 修复 A（阴影）：settings SHADOW_DISTANCE 128→256、SHADOW_SOFTNESS 4→2、
  shadowIntervalSize 0.5；profiles 三档同步（PERF 96→192 / BALANCED 256 / ULTRA 256+SOFTNESS 8）；
  shadowmap fade (d−24,d−8)、bias clamp 0.35。
- 修复 B（水色）：absorption 界面吸收三档改 Steadfast 口径（BALANCED (1.0,0.1875,0.0625)）；
  water_sun_focus 基准 0.12→1.0。
- 修复 C（断层）：refraction.glsl 重写为单跳投影（|Δz|、32m、10% 屏幕边缘淡出）；
  water.glsl maxDistance 96→32；REFRACTION_STRENGTH 100→60（三档 profile 同步）。
- 修复 D（水下阳光）：scene.glsl 新增自写 water_sun_glare（exp 窄峰 + daylight*(1-rain)，
  Nether/End 宏保护）+ WATER_SUN_GLARE_BOOST 2.5，接入 astra_underwater_color 与
  water_medium 入射；water_phase g 0.60→0.40；light_shafts WATER_SHAFT_GAIN 2.0 +
  UNDERWATER_SHAFT_STRENGTH 100→150（settings + 三档 profile）。
- 驱动编译（RTX 4050 / NVIDIA 572.83 / GL 4.6）：BALANCED / PERFORMANCE / ULTRA 各
  linked=76 failed=0（日志 qa/glsl-shadow-water-fix-{balanced,performance,ultra}.log）。
  首轮 world-1 编译发现 `astra_direct_light` 在 Nether/End 未定义 → 辉光项加维度宏保护后全绿。
- check_pack 复跑：0 FAIL / 2 WARN / 9 PASS。
- 状态：未修改任何视觉裁决；无本轮游戏画面。待杨间按 docs 第 7 节机位复测
  （阴影三连截图法、水色/断层俯仰扫描、水下机位对照图 2 参考）。

## 2026-09-10 晚 — 接替轮：交接复核 + N3 可行性修复 + W4

- 复核交接清单（docs/2026-09-10-next-agent-dimensions-weather.md）发现 7 处自述与代码不符，
  全部记入交接文档“复查结论”节；其中 3 处会导致功能完全失效或整包被禁：
  1) `world-1/shadowcomp1..8.csh` 数字后缀 → Iris compute 数组只读 `<name>A..Z`（`ProgramSet.readComputeArray`
     27 槽），8 个传播步从未加载；已改名 `shadowcompA..H.csh`。
  2) `NETHER_VOXEL_LIGHT` 为全局选项但 `shadow.vsh` 的 `uimage3D` 无名次守卫 → 主世界/末地阴影
     编译失败（离线编译 3 处 FAIL）；已加 `DIMENSION_NETHER &&`。
  3) `iris.features.required=CUSTOM_IMAGES` + 无守卫 image 指令 → 特性缺失时 Iris 弹
     FeatureMissingErrorScreen 并整体禁用光影；改 `optional` 且 image 指令入 `#ifdef`。
- 离线编译工具 preamble 的 `MC_RENDER_STAGE_*` 与 Iris 1.11.2 `WorldRenderingPhase` 枚举不符
  （SUN 3/4、MOON 4/5、CUSTOM_SKY 7/3），会让 program/sky.fsh 的日/月/星分支永久不命中；
  按枚举全量重写，并新增 SC-31 防漂移校验。
- 工具链扩展：compile_glsl.py 支持 `.csh`（4.3 上下文 + `compute_capable` 报告）、`--no-compute`、
  修正 `--undef` 对默认开启选项的处理；check_pack.py 新增 SC-29/30/31、纳入 `.csh`、
  第 6 项改为扫描整棵 include 树（修掉 lib/solas_water.glsl 声明漏看导致的误报）。
- N3 正确性：占用编码 bit0-7 种类 / bit8 固体 / bit16 帧戳；空单元才扩散、固体阻挡、
  邻居无本帧帧戳则跳过（防跨未加载区块漏光），消费端忽略过期单元。
- N2 比对结论：`result*volume.a + volume.rgb` 即单次散射，双雾层各自持透射率属预期分层；
  加三个密度标度（plume 0.55 / haze 0.30 / ceiling 0.35）并写进注释防止下轮误修。
- N3 素材核对：textures/bliss-nether-noise.png 与 Bliss Stable texture/noises.png sha256 前缀
  一致（77d1aa0c2195a4f6，512×512 RGBA8）；因 noisetex 已占用改用 customTexture 绑定，
  过滤参数与参考不同，已记入 THIRD-PARTY.md 为已知保真差异。
- W4：确认引擎无粒子类型 ID（Iris 无 particle.properties）→ 按图集精灵区域识别
  （splash.json 四帧 8×8，位于粒子表最外行/列，取 UV>0.875 的 6%），蓝色偏置换中性冷灰、
  alpha 降 55%，只改该区域以免误伤药水/水下/灵魂粒子；待实机确认命中与无误伤。
- 驱动编译（RTX 4050 / NVIDIA 572.83 / GL 4.6）：`linked=261 failed=0 compute=27`
  （234 vsh/fsh 对 + 9 步 × 3 档 compute），日志 qa/glsl-2026-09-10-p0-final.log 与
  ...-w4-particle.log；关闭态回退 `--undef NETHER_VOXEL_LIGHT --no-compute` → linked=234 failed=0。
- check_pack 复跑：0 FAIL / 2 WARN / 9 PASS（历史 4 项 FAIL 全清：texture2D 拼写、
  自定义 uniform 误报、colortex*Format 误判、台账 16≠22）。
- 同步：qa/tools/sync_to_instance.py 已把 Astra 全量同步到实例（缺失 0 / 内容差异 0）。
- 状态：编译与静态校验全绿，**无本轮游戏画面**。待用户实机按交接文档“下一步”第 2-5 条复测；
  W4 区域命中与否、下界体积光遮挡与残留、雨滴/积水/雨环观感、末地恒星尺度均需画面裁决。

## 2026-09-10 深夜 — N3 逻辑仿真：抓到 2 个编译无法发现的缺陷

新增 `qa/tools/nether_voxel_model.py`：把 `program/shadow.vsh` 的占用编码与 `program/nether_light.csh`
的九步传播在 Python 里逐规则复刻，断言四条不变量（墙阻挡/未渲染失效/空气不写成固体/八步有界）。
它一次就抓到两个**GLSL 编译与静态校验都不可能发现**的问题：

1. **传播循环从未执行（致命）**：写入端对普通不发光方块也写 `kind=1`，而传播判据是 `id==0`，
   两者永不相等 → 8 步扩散全是死代码，彩色光只停在光源自己那一格。这就是"下界缺乏光影空间感"
   的直接原因。修法：捕获到空气的格子写 `kind=0`（固体写 1），传播判据改为
   `(id == 0u) && !solid`。
2. **帧戳在偶数帧等于 0**：持久图像初始值也是 0（"从未写入"），于是偶数帧所有未渲染格子都被
   当成"本帧捕获的空气"，扩散会穿过未加载区域。修法：帧戳改为 `(1 - (frameCounter & 1)) << 16`，
   在 0b01/0b11 间交替，永不为 0。

修后仿真：`wall blocks light ... behind=0.0000`、`air_lit=1.0800`、距离衰减 d1=1.0800 → d8=0.1083 →
d9=0.0000，四条不变量全 PASS。

同时修掉实机日志里的真实报错：`latest.log` 有
`Unable to resolve shader pack option menu element "VOXY_SUPPORT"`——该选项只在 settings.glsl 声明，
Iris 的选项扫描跳过该文件，故被丢弃。已在 `lib/uniforms.glsl` 加引导引用（注释写明 C5 落地后替换）；
`check_pack` 第 11 项由 WARN 转 PASS。

- 编译：`linked=261 failed=0 compute=27`（日志 qa/glsl-2026-09-10-n3-fixed.log）；
  关闭态 `linked=234 failed=0`（...-n3-fixed-off.log）。
- 校验：`check_pack.py` → **0 FAIL / 1 WARN / 10 PASS**。
- 待用户实机裁决：体积光遮挡与残留、雨滴/积水/雨环观感、溅水粒子命中与否、末地恒星尺度。

## 2026-09-11 — 实机第一轮反馈（雨滴/水色/光束/末地/下界雾）

用户实机反馈 5 条，逐条定位：

1. **"雨滴直接消失"**（最严重）：上一轮我给雨滴加了 `drop * tint.a * 0.17`，系数只有场景
   `alphaTestRef`(0.1) 的 1.7 倍，且 `nearFade` 从 1.8 才开始到 5.5 —— 近处大片区域直接归零；
   同时垂直频率 `×1.8` 使每格高达 0.55 格，格内出现率极低。已重写：世界锚定的稳定哈希
   （哈希不含移动的时间项，避免逐帧重掷导致闪烁）、密度判据 `alive < 0.78` 丢弃、透明度改为
   `0.55 + 0.45*astraRainFactor` 驱动、基色 0.86→1.25、近距淡出改为 0.6→1.7。
2. **水色偏黑偏蓝**：量化用户两张截图（同机位）——Astra 近景 v=0.27/s=0.70，Steadfast v=0.31/s=0.49，
   **色相几乎一致**（209° vs 206°），所以是吸收过强而非染色错误。`water_surface_absorption`
   三档系数按 ~0.62 缩放并提高绿蓝比（平衡档 1.000/0.1875/0.0625 → 1.000/0.1320/0.0800），
   散射同步上调（0.008/0.023/0.055 → 0.011/0.032/0.076）把损失的通透度补回为水色。
3. **水下光束不可见**（根因找到）：`light_shafts.glsl` 用
   `if (shadow0 >= 1.0) continue;` 采样 **shadowtex0（含半透明）**，而水下采样点位于水面之下，
   水面自身把它判为完全遮挡 → 每个采样点被跳过 → 积分恒为 0。改用 **shadowtex1（仅不透明）**
   作遮挡判据；同时移除 `float(depthtex0.r > 0.56)` 硬截断（它删掉了 6 格内的所有光柱，
   正是参考图有明显光柱的距离段），改为 smoothstep(1.0,3.5) 近距淡出，并提高方向权重。
4. **末地太简陋**：用户指向 IterationT 3.2（其末地以超大质量黑洞为核心卖点，见
   minecraftstorage.com/shaders/iterationt-320）。把原来的"亮盘+日冕"改成紧凑黑洞模型：
   0.055 rad 真黑质量影（会吞掉背景星云/星空，这是"质量感"的来源）、0.082 rad 光子环、
   吸积带按方位做相对论束流（迎向相机更亮且偏暖、背离偏冷蓝）、外层引力透镜晕。
5. **下界雾偏多**：`NETHER_FOG_DENSITY` 100 → 70（三档 profile 同步）。体积 plume/haze 层保留，
   因为用户要的"空间感"来自它，砍的是均质层。

验证：`linked=261 failed=0 compute=27`（qa/glsl-2026-09-11-feedback1.log）；
`check_pack` 0 FAIL / 1 WARN / 10 PASS。已同步实例。

## 2026-09-11 第二轮反馈（漏项纠正 + 黑洞返工）

用户指出上一轮漏掉了雨滴相关的另外两条要求，并质疑黑洞做得太快。承认属实，本轮补齐：

1. **溅水蓝色粒子未删除（我上一轮只做了"中性化"且识别未命中）**。本轮查实路径：
   26.2 的 `WaterDropParticle.getLayer()` 返回 `SingleQuadParticle$Layer.OPAQUE` →
   不透明粒子层 → Iris 由 `gbuffers_particles` 提供（回退 `gbuffers_textured_lit`），
   两者都已定义 `ASTRA_PARTICLE`。
   上一轮"猜图集格子"的做法必然失败：stitcher 把 `8px + 2*padding` 向上取整到 2 的幂，
   且 mip 每级 padding 翻倍，溅水格根本不在表角。
   改为**与图集/资源包无关**的判据：单四边形粒子把 8x8 精灵铺在几个像素上，其纹理坐标导数
   远大于方块/物品表面（约 0.1–0.4 / 像素 vs 0.0x）。组合蓝色偏置后直接 `discard`。
   这样不会误伤药水、sculk 灵魂、滴水等更大精灵的蓝色粒子。
2. **雨滴打到水方块上的效果太弱**：`astra_puddle_normal` 振幅 0.018 → 0.055、水面叠加系数
   2.6 → 4.0；同时发现 `astra_rain_exposure` 用 `pow(..,16)`，要求 skyLight > 0.95（正午完全
   露天）——这正是阴雨天下积水和雨环全部消失的原因，放宽为 `pow(..,7.5)`，积水法线门限
   0.94 → 0.86。
3. **黑洞返工**：第一版只是"亮环+黑心"，仍偏简陋。第二版按四个真正决定观感的特征建模：
   纯黑阴影盘（吞掉背景）、紧贴阴影的光子环、**投影平面吸积盘**（宽度由盘面法向与视线决定，
   自然呈现椭圆，含内侧高温、多普勒束流、蓝移/红移配色）、沿盘轴的电离喷流 + 透镜晕。
   盘面法向 (0.72,1,0.20)，湍流细节用 solasWaterNoise 在盘面坐标采样。

验证：`linked=261 failed=0 compute=27`（qa/glsl-2026-09-11-feedback2-full.log）；
`check_pack` 0 FAIL / 1 WARN / 10 PASS。已同步实例。

## 2026-09-11 第三轮反馈（水下颗粒/焦散/光束方向 + 黑洞全面返工）

1. **水下悬浮颗粒大幅调低**：`PARTICLE_DENSITY` 0.16 → 0.055、`PARTICLE_CELL` 2.0 → 2.6、
   `PARTICLE_RADIUS` 0.24 → 0.18、`PARTICLE_INTENSITY` 0.045 → 0.016，并把
   `UNDERWATER_PARTICLES` **默认关闭**（三档 profile 均为 `!UNDERWATER_PARTICLES`，选项与中英
   说明保留，需要时可开）。理由：参考观感（Solas 清透水下）与用户"大幅调低"都指向让体积光与
   焦散承载水下氛围，而不是靠颗粒层。
2. **焦散之前几乎看不见（数值已证）**：把 `solas_water_height` 压到 ×0.4、导数偏移减半，
   实测（用 solas-water-noise.png 复算）焦散场 p90 只有 0.06、max 0.18、85% 低于 0.05 ——
   等于把参考的亮网磨成一层平光。已恢复参考口径（完整高度场 + 单位偏移 + ×96 曲率），
   复算得 p50 0.085 / p90 0.46 / p99 0.93 / max 1.52、30% 落在暗底，明暗对比恢复。
   `program/shadow.fsh` 的着色映射同步重调（水下底色 0.30 + focus×1.5）。
3. **光束不要糊脸**：原权重 `0.35 + 0.35*VoL` 保留了与视线无关的底量，整屏都是光束。
   改为只保留方向项 `pow(VoL, 2.6)`，光束集中在太阳侧、背离太阳自然消失，近距淡出保留。
4. **黑洞按用户给的画面描述全面返工**：
   - **引力透镜**：点质量偏折 θ_E²/θ 解二次式得到背景方向，**同时作用于星云与星场**——
     星光因此在爱因斯坦环附近被压缩拉成弧线（`starArc` 增益 5.5×），而不是只加一圈装饰环。
   - **事件视界**：0.052 rad 纯黑、硬边（一个像素级 smoothstep），`sky *= horizon` 真正吞掉背景。
   - **光子环**：0.80/0.90/1.30 冷白蓝，exp 衰减 220，极细极亮。
   - **吸积盘**：远场投影椭圆模型（沿盘轴分量按 1/|axis·n| 放大），只画近侧半；内侧炽白偏蓝
     → 金橙 → 暗红三段渐变，多普勒束流（迎向侧 1.27×，背离 0.22×），噪声湍流颗粒。
   - **上弧**：远侧被透镜翻折到阴影上方，用爱因斯坦半径处的高斯带表示（含湍流）。
   - **冷暖对比**：星场冷蓝 (0.62,0.78,1.20) vs 盘面暖金；盘外冷蓝晕 0.17。
   - **电影感**：末尾二次对比曲线 `sky*sky*0.60 + sky*0.50`（提亮高光、压暗背景）。
   注：胶片颗粒与暗角属后处理，当前只在末地天空局部做了对比提升；全局颗粒/暗角未动，
   因为主世界要保持"清爽不抢戏"。

验证：`linked=261 failed=0 compute=27`（qa/glsl-2026-09-11-round2-full.log）；
`check_pack` 0 FAIL / 1 WARN / 10 PASS。已同步实例。

## 2026-09-11 第四轮（六图反馈：黑洞灾难 + 水下焦散/蓝滤镜 + 水面质感）

三个根因，全部是我的错误：

1. **黑洞"另一侧也有半截"** —— 透镜用了二次式求根 `cosDest=(R·cosA+2E²)/q`，当 R < E 时它选的根会把
   光线映射到**对侧**：实测把指向黑洞中心的光线映射到 81° 外，于是天空被镜像复制，同时星场被抹掉。
   改为**局部、单值**的矢量：只把 `angle` 按 `pull = E·lensT·0.70` 拉近（`lensT` 在爱因斯坦半径到
   0.34 rad 之间平滑归零），已用 Python 验证 4000 点**严格单调、无折叠**，因此不会再有第二像。
   星云与星场改回用原始 `dir`（"之前的星空保留"），并去掉末尾 `sky*sky` 的爆亮曲线（它把盘面烧成白团）。
   盘改为**居中倾斜椭圆环**（a=0.150, b=0.26a，倾角 0.22），不再是"半盘"。
2. **水下没有焦散 + 蓝色滤镜** —— `sceneLight` 的直射混合被乘了 `astraSolasShadowFade`，而该式是
   地平线眩光因子：`sunAngle=0.5`（正午）时为 **0**、日出日落时为 1。所以正午水下直接光**整项归零**，
   `shadow`（含焦散染色）完全不起作用 → 只剩环境光，既没有焦散也是均匀蓝。
   改为用太阳高度角 `smoothstep(-0.02, 0.16, worldSunVector.y)` 门控；`astraSolasShadowFade` 只留给
   `solas_water_fog` 的眩光项（它的本职）。同时把水下雾系数 6.0 → 3.0（10 格处 45% → 26%），
   让海床保留自身颜色与焦散对比。
3. **光束方向反了 + 黄昏最强** —— 权重写成 `(1.0 - VoL)`，于是**背向太阳时最亮**（正是用户描述的
   "背向光源方向拍摄却异常亮"）；另有 `(2.0 - sun)*0.5`，在太阳高度 0 时取 1.0、正午取 0.5，
   所以黄昏最强。改为 `* VoL`（前向散射），加太阳高度门控，删除黄昏增益。

水面三项（用户：太阳反射弱、波浪不丝滑、水下看水面破碎多、海带反射不明显）：
- `astra_water` 增加**窄镜面太阳高光**：`pow(reflectedWorld·worldSunVector, mix(340,70,roughness*6))`，
  因为参考的 Mie 瓣很宽，在水面上只呈现为一层弱光晕；高光受太阳高度门控，强度 2.6×。
- 水下界面反射率上限 0.5 → 0.88（参考在上限处截断，导致海带反射"不明显"）。
- `WATER_WAVE_HEIGHT` 默认 100 → 62（枚举表同步补 62），坡度场变缓，兼顾"丝滑"与少破碎。

验证：`linked=261 failed=0 compute=27`（qa/glsl-2026-09-11-round3-full.log）；
`check_pack` 0 FAIL / 1 WARN / 10 PASS（枚举校验成功拦下 62 未登记的问题）。已同步实例。

## 2026-09-11 第五轮（黑洞仍像月亮 + 高光过曝 + 我越界改了波浪）

1. **黑洞"看起来只像个大月亮"** —— 这是设计错误，不是参数问题。我上一版给阴影外面套了一圈
   **对称的亮环**（`photonRing * 1.35` 加同心晕），"亮环包黑盘"正是月食/月亮的形状。黑洞之所以
   像黑洞，靠的是**倾斜的盘从阴影前面穿过** + **远侧被透镜翻折成上弧**，这两件事对称环给不了。
   已重做：删掉对称环与同心晕（光子环降为 420 衰减、0.40 强度的发丝），改为
   - 近侧盘带（`Y0=-0.009`，从下往上穿过阴影**前面**，在 `sky *= horizon` 之后相加，所以正确遮挡）
   - 远侧弧（抬到 `Y0+1.55*shadow` 贴着阴影顶部）
   - 多普勒不对称 `mix(0.14, 1.0, ...)`：一侧亮 7 倍，这是最强的"非月亮"线索
   - 内热蓝白 → 金 → 深红外缘
   用离线 ASCII 渲染验证了形状：实心黑盘 + 左上亮带 + 贴顶弧，右下为空（不对称成立）。
2. **水面太阳高光过曝** —— 上一版 340 指数 + 2.6 强度是个刺眼点。改为 `mix(150,42,roughness*6)`
   指数、0.85 强度（约原值 1/3，且更宽更柔）。
3. **我越界改了波浪** —— 用户明确说"之前的波浪我很满意不要动"，而我上一轮把
   `WATER_WAVE_HEIGHT` 从 100 降到 62 去追"丝滑"。已**完全回滚**（settings + 三档 profile +
   枚举表），并在注释里写明：不得再用降低波幅去追这个反馈。
4. **水下看水面破碎（与波浪无关）** —— 定位到 `solas_underwater_interface` 里的折射 UV：
   `if (water_depth_range(...) >= gl_FragCoord.z) uv = candidate;` 是**逐像素二值切换**，
   在"位移 UV / 未位移 UV"之间硬跳，边界就是撕裂感。改为按深度差 `smoothstep(±0.0015)`
   平滑混合，保留位移路径但消除撕裂。上一轮我把界面反射率上限 0.5→0.88 也一并保留（用户要
   更强的海带反射）。

验证：`linked=261 failed=0 compute=27`（qa/glsl-2026-09-11-round4-full.log）；
`check_pack` 0 FAIL / 1 WARN / 10 PASS。已同步实例。

## 2026-09-11 第六轮（月亮真因 + 光束重写 + 直算焦散）

用户语气已经很差（"你都干了什么"），三条都是我造成的，逐条认。

1. **"更像月亮"的真因终于找到**：光子环写成 `exp(-max(angle - SHADOW, 0) * k)`，
   而 `max()` 在**阴影内部把指数夹成 0**，于是环值在整个盘内恒等于 **1.0**；它又在
   `sky *= horizon` **之后**相加，所以整块事件视界被重新涂成一个均匀发光圆盘。
   这个错误我在 220 与 420 两版里**各犯了一次**，而且两次都没检查过阴影内的取值——
   这就是"一直是月亮"的原因。已改为以环半径为中心的**环带** `exp(-((angle-SHADOW)/w)²)`，
   两侧都衰减。数值验证：angle=0/0.02 处为 0.0000，0.042 处为 1.0。
2. **星空几乎不可见**：用真实 `end_noise` 实测，旧阈值 0.80 的命中率仅 0.155%
   （约 640 格一颗），峰值亮度约 0.16，等于没有。阈值改 0.74、增益 12、星云抑制基准 0.6，
   复算约 1 万颗覆盖半球、峰值约 1.7。
3. **物体尺寸过大**：盘半宽 0.150 rad（直径 17°）远超"远处天体"的合理尺度，会糊满天空。
   收紧为 shadow 0.038（直径 4.4°）、盘半宽 0.095（10.9°）、带厚 0.010，远侧弧高斯收窄到
   0.62×。用离线 ASCII 渲染确认：实心黑盘 + 细环 + 左侧多普勒亮带 + 贴顶弧，右侧暗。
4. **光束"像手电筒 / 固定实体"**：对照 Solas V2.2b `volumetricLight.glsl` 找到两处结构性差异：
   - 我从 `i=0`（距离 0）开始等权行进，近处介质被一路涂到眼前；**Solas 首个采样点在
     `maxDist/sampleCount*0.5` 之外**，且权重随距离增长——这正是"走近就消失"的原因。
   - 我用 `if (shadow1 >= 1.0) continue` **硬跳过**被完全遮挡的采样，4-10 个采样就把阴影边界
     变成硬楔形；Solas 是把遮挡**乘进去**累积。
   已按参考重写：最小起始距离 + 均匀间距 + 距离加权 + 平滑累积 + 保持前向散射与日照门控。
5. **焦散"还是没有"**：阴影贴图投射路径依赖水方块被写入 `shadowcolor0` 且染色正确，
   这些我离线无法验证（已连续两轮无效）。改为**直接在水下地形上求值同一套 Solas 高度场**
   （`solas_water_caustics(playerPos + cameraPosition)`），以保证图案必然出现，且仍随水面
   相位动画、受日照影响。以"中心接近 1 的乘数"形式接入（峰值提亮、暗格压暗），避免整体压暗。

验证：`linked=261 failed=0 compute=27`（qa/glsl-2026-09-11-round5-full.log）；
`check_pack` 0 FAIL / 1 WARN / 10 PASS。已同步实例。
