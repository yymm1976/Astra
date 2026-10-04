# 参考包批次（2026-09-24）与 Codex 分析任务提示词

本文件登记 2026-09-24 下载的 10 个参考光影包，以及交给 Codex 的分析/整改提示词。

用途：Astra 有若干长期未收敛的薄弱环节（水下链路、主世界性能、下界光照质感、末地石发光），
此前只研读过 Complementary / Solas / Mellow / Steadfast / IterationT 五家。本批次补充 10 家，
扩大可借鉴的技术面。

## 一、下载清单

来源：Modrinth API，下载日 2026-09-24。
存放：`_analysis/refs-2026-09-24/`（已解包，每个含 `shaders/` 子目录，可直接读源码）。

| 目录 | 版本 | program 数 | 代码行数 | 许可 | 选择理由 |
|---|---|---|---|---|---|
| `photon-shader/` | v1.3b | 402 | 25,003 | 自定义（SixthSurge，保留所有权利） | 工程标杆。**Astra 的 `lib/pow.glsl:11` 已引用它的 `include/util/common.glsl`**，但从未系统研读。水面/大气/天空 |
| `bliss-shader/` | 2.1.2 | 294 | 19,527 | Chocapic13 派生许可（保留所有权利） | **Astra 的 `global/dimension/nether_volume.glsl:3` 已从其 `lib/nether_fog.glsl` 改编**，同样未系统研读。性能+奇幻定位 |
| `shrimple/` | v0.12 | 537 | 41,023 | 保留所有权利（Joshua Miller） | 本批次最大包，性能工程取向明确 |
| `kappa-shader/` | 5.3 | 316 | 27,380 | 保留所有权利（RRe36） | 写实+风格化的高质量工程 |
| `fastpbr/` | 2.0 | 278 | 16,980 | 保留所有权利（RRe36） | "快速 + 高质量 PBR"，正对性能/画质平衡痛点 |
| `miniature-shader/` | 2.19 | **94** | **1,574** | 未声明（默认版权） | **轻量极限**：94 个 program、1574 行，却仍有阴影与反射。对性能优化启发最大 |
| `visual-vibrance/` | 0.3.5a | 212 | 7,794 | 自定义（jbritain，保留所有权利） | 复刻官方 Vibrant Visuals，是"新原版标准"的参照 |
| `nostalgia-shader/` | 5.1 | 312 | 22,672 | 保留所有权利（RRe36） | 明确的老式风格取向，色彩/大气思路与主流不同 |
| `super-duper-vanilla/` | 1.3.8 | 246 | 12,296 | FlameRender Studios 自定义（保留所有权利） | 复刻已取消的官方 Super Duper 包，独立美术方向 |
| `astralex/` | 93.0 | 202 | 20,988 | 未声明（默认版权） | 以"极高可定制性"为卖点，选项架构值得看 |

**许可状态**：10 个全部为"保留所有权利"或自定义专有许可，与已研读的
Complementary / Solas / Mellow / Refrax 同性质。按 `design.md` §9.2 与
`THIRD-PARTY.md` 的既有政策处理：**允许借鉴思路；逐行移植必须逐处登记并保留正确持有人署名。**

## 二、Astra 当前的薄弱环节（供分析定位用）

1. **水下链路从未真正工作过**。焦散改过 3 轮（5-tap 噪声曲率 → 解析雅可比场 → 6 列波表）；
   光束 resolve 曾结构性恒为 0（用 `depthtex0` 重建距离、天空记 `1e5` → 权重下溢）；
   从未实机确认。相关：`global/water/*.glsl`、`program/water.glsl`、
   `program/scattering.fsh`、`program/water_composite.fsh`、`lib/solas_water.glsl`。
2. **主世界性能**：同场景帧数低于 IterationT 3.2（更重的包）。已定位冗余见
   `deferred.fsh` 的全分辨率 MRT 写、平面云 64 步 march、阴影链开销。
3. **下界光照质感**：netherrack 的"泛光"改过 3 轮仍不确定；顶点 AO 已接但可能空转
   （未验证 `gl_Color.a` 是否真的携带 AO）。
4. **末地石发光**：两次尝试失败（按 albedo 门控导致沙子一起过曝，被用户否决）。
   目前末地石无任何发光。
5. **末地阴影条纹**：23° 掠射角下的阴影自遮蔽，已补斜率 bias 但未实机验证。

**明确不要动**：末地 Kerr 黑洞实现（`global/dimension/end_kerr.glsl` 等）是刻意设计；
不要引入 TAA / 帧间累积（全包无 TAA 是既定取舍，加了会牵动所有抖动设计）。

## 三、给 Codex 的提示词

以下为可直接复制使用的完整提示词。

```
# 任务：研读 10 个参考光影包，提炼独到技术并应用到 Astra

## 项目背景

工作区：C:\Users\杨铭\Desktop\MC模组开发\Astra光影开发
Astra 是一个 Minecraft Iris 光影包（源码在 `Astra/shaders/`）。定位：中高画质、性能敏感、
有若干"大场面"特性（末地 Kerr 黑洞、下界体素彩色光、SSR、体积雾、类 labPBR）。

### Astra 已知的薄弱环节（优先在这里找答案，不要在已经做好的地方浪费预算）

1. **水下链路从未真正工作过**。焦散改过 3 轮（5-tap 噪声曲率 → 解析雅可比场 → 6 列波表），
   光束 resolve 曾结构性恒为 0（用 depthtex0 重建距离、天空记 1e5 → 权重下溢）。
   至今没有实机确认过效果。相关文件：`global/water/*.glsl`、`program/water.glsl`、
   `program/scattering.fsh`、`program/water_composite.fsh`、`lib/solas_water.glsl`。
2. **主世界性能**：同场景帧数低于 IterationT 3.2（一个更重的包）。已知冗余：
   `program/deferred.fsh` 的全分辨率 MRT 写、平面云 64 步 march、阴影链开销大。
3. **下界光照质感**：netherrack 的"泛光"改过 3 轮仍不确定；顶点 AO 接了但可能空转
   （未验证 `gl_Color.a` 是否真的携带 AO）。
4. **末地石泛光**：两次尝试都失败（按 albedo 门控导致沙子一起过曝，被用户否决）。
   目前末地石没有任何发光。
5. **末地阴影条纹**：23° 掠射角下阴影自遮蔽，已补斜率 bias 但未实机验证。

### 明确不要动的地方
- 末地黑洞的 Kerr 实现（`global/dimension/end_kerr.glsl` 等）是刻意设计的，不要按参考包重做。
- 不要引入 TAA / 帧间累积（Astra 全包无 TAA，这是既定取舍，加了会牵动所有抖动设计）。

## 参考包位置

`_analysis/refs-2026-09-24/` 下已解包 10 个包，每个都有 `shaders/` 子目录：

| 目录 | 版本 | 定位 |
|---|---|---|
| photon-shader | v1.3b | 工程标杆；水面/大气/天空 |
| bliss-shader | 2.1.2 | 性能+奇幻；Astra 下界体雾已引用它 |
| shrimple | v0.12 | 41k 行；性能工程取向 |
| kappa-shader | 5.3 | 写实+风格化，RRe36 |
| fastpbr | 2.0 | 快速 + 高质量 PBR |
| miniature-shader | 2.19 | 只有 94 个 program 却有阴影和反射（轻量极限） |
| visual-vibrance | 0.3.5a | 复刻官方 Vibrant Visuals |
| nostalgia-shader | 5.1 | 老式风格取向 |
| super-duper-vanilla | 1.3.8 | 复刻已取消的官方包 |
| astralex | 93.0 | 极高可定制性，选项架构 |

另有两个已研读过的参考包可作对照（不重复劳动）：
`_analysis/Complementary r5.9/`、`_analysis/Solas Shader V2.2b/`、
`_analysis/Mellow Shader v3.4/`、`_analysis/Steadfast-0.8.0/`、
`_analysis/latest-2026-09-10/iterationT-3.2.0/`。

## 第一步：逐包分析独到之处（不要做泛泛的通读）

对每个包，回答：
1. **它的核心独到技术是什么**？不是"它用了什么效果"，而是"它用什么手法达到了别人达不到的
   效果/性能"。给出 `文件:行号` 与关键参数值。
2. **它的性能取舍是什么**？（哪些效果默认关、哪些降采样、循环几次、有无 temporal）
3. **它解决了 Astra 上面哪一条薄弱环节**？给具体做法，不要给"它做得更好"这种结论。
4. **它的成本是多少**？（采样次数、pass 数、带宽；能量化就量化）

按"对 Astra 的价值"排序输出，**最有价值的最先写**。不要按包名顺序平铺。
miniature-shader 只有 1574 行，请完整读；shrimple 有 41k 行，请抽样读
（用 `qa/tools/cost_census.py` 之类的手段先定位高开销点，再针对性读）。

## 第二步：差距对照

对 Astra 的每个薄弱环节，列出：
- 参考做法（哪个包、哪个文件、行号、关键数值）
- Astra 现状（哪个文件、行号）
- **差距的性质**：是"参数不对"、"结构不对"、还是"Astra 架构上不支持"？
- 若需要新 pass / 新 buffer，明确说出来（那是个决策点，不是调参）

## 第三步：整改（按收益/风险排序，一轮只做 1-2 项）

硬性约束：
- **只学思路，不要复制代码**。这些包全部是"保留所有权利"许可
  （Photon = SixthSurge 自定义许可，Bliss = Chocapic13 派生许可，
  Kappa/Nostalgia/FastPBR = RRe36 保留所有权利，Shrimple/SuperDuperVanilla/VisualVibrance = 各自自定义）。
  若确实要逐行移植（像 Astra 已有的做法那样），必须**逐处登记进 `Astra/THIRD-PARTY.md`**，
  并保留正确的持有人署名。优先自己重写实现。
- **改完必须过编译门禁**：`python qa/tools/compile_glsl.py --profiles PERFORMANCE BALANCED ULTRA`
  → 期望 `linked=270 failed=0 compute=27`。
- **不要一次改很多文件**。上一轮有人一次性改了 14 个文件同步进游戏，导致主世界白天像黑夜、
  水面消失、末地石过曝，全部回退重做。**一次一项，改完验证再下一项。**

## 第四步：验证（这一节最重要，请认真读）

**Astra 只有末地天空有离线渲染通道**：
```
python qa/tools/render_end_design.py --view blackhole|island|jet --width 1600 --height 900 \
    --seconds 24 --output <path> [--foreground] [--panorama]
```
**主世界 / 下界 / 水下无法离线出图。** 这意味着：
- 对这三处的任何改动，你**只能给出代码级与数值级的论证**，
  并且**必须在交付里明确声明"需实机确认"**。
- **绝对不要把"探针数值通过"当成"效果达成"**。有实际教训：曾用亮度（Rec.601）做标定，
  而 bloom 实际看的是 max 通道，导致标定偏了 2.5 倍，靠审查才发现。
  标定前先确认消费端真正读的是什么量。

可用的验证工具在 `qa/tools/`：`compile_glsl.py`（编译门禁）、`check_pack.py`（包级检查）、
`cost_census.py`（开销清点）、`block_reflect_probe.py`（岩石泛光响应表）、
`end_universe_probe.py`（末地天空）、`render_end_design.py`（末地出图）。

注意：`underwater_light_probe.py` 与 `underwater_shaft_gate_probe.py` 的锚点指向已被删除的
表达式，**运行即断言失败**。水下目前没有可用的自动化门禁。如果你要改水下，
**先修复或重建这两个探针**，否则你没有验证手段。

## 交付格式

1. **逐包独到技术清单**（按对 Astra 的价值排序，每条带 `文件:行号`）
2. **差距对照表**（薄弱环节 × 参考做法 × Astra 现状 × 差距性质）
3. **整改清单**（按收益/风险排序，每条含：改什么、预期收益、风险、参考依据）
4. **本轮实际改了什么的证据**（编译结果、探针数值、出图）
5. **明确列出"必须实机确认"的项**，以及哪些结论你无法验证

不要用"应该会更好"、"理论上"这类措辞给结论。给不出证据就说给不出。
```

## 四、建议的优先顺序

若预算有限，按此顺序深读：

1. **`miniature-shader/`** —— 1574 行做到阴影+反射，是"性能下限"的活证据，对第 2 条薄弱环节最直接。
2. **`fastpbr/`** —— "快速 + 高质量 PBR"的平衡做法，同样针对第 2 条。
3. **`photon-shader/`** —— 水面与大气；Astra 已引用其 `pow.glsl`，系统研读可补齐第 1 条。
4. **`bliss-shader/`** —— 下界体雾的原始出处，且性能取向，同时覆盖第 2、3 条。
5. 其余按需。

## 五、维护备注

- 本批次为 Modrinth 下载的发布版；若后续需要更高版本，从
  `https://api.modrinth.com/v2/project/<slug>/version` 取 `version_type == "release"` 的最新项。
- `_analysis/refs-2026-09-24/*.zip` 与解包目录并存；解包目录是研读入口，zip 是原始存档。
- 注意 `shaderpacks/` 下已累积多个 `Astra-backup-*` 目录（属游戏实例，不在本仓库）。
