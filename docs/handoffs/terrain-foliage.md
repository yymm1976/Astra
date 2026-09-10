# terrain-foliage → 主任务：公共接入交接单

本文件是 `terrain-foliage` worktree 向主任务（水体 / 公共照明 / 阴影 / 合成）申请公共接入的唯一出口。
任务范围见 `docs/parallel-development/terrain-foliage.md`。**不通过直接编辑共享文件绕过边界。**

⚠ 树叶投射与可见模型必须保持一致；已修好的阴影数据输出禁止修改。新增材质模块放 `global/materials/`，主入口接入由主任务处理。

## 填写字段（与任务书一致，不得省略）

- **接口**：需要主任务提供的函数 / uniform / 变量名，写准确名称
- **调用位置**：文件路径 + 行号 或 shader 阶段
- **参数**：类型、取值范围、单位、语义
- **原因**：不这么做会怎样；为什么无法在本 worktree 内解决
- **本侧已完成**：`terrain-foliage` 侧已经改动的文件（仅限 `global/lighting/wind.glsl`、`global/lighting/sss.glsl` 及 `global/materials/` 下新增模块）
- **主任务侧待办**：需要对方具体改什么

## 本侧已完成（2026-09-10 摆动与透光微调轮）

仅改动两个授权文件，未新增 `global/materials/` 模块：

1. `Astra/shaders/global/lighting/wind.glsl` — 摆动形状整体换为 Complementary r5.9 逐字移植：
   `wind_wave_shape()` = GetRawWave（wavingBlocks.glsl:5-16 系数 verbatim）；
   树叶分支 = DoWave_Leaves（:52-67，位置压缩 vec3(0.75,0.375,0.75) + 分量 mix vec3(4,3,8) + 0.1）；
   地面植被分支 = DoWave_Foliage（:35-50，y*0.5 相位拉伸 + x*3、y=0、z*8 形状，地面竖直位移由参考自身归零）；
   强度链 = GetWave（:18-33），`WAVING_I` ← `WAVING_FOLIAGE_STRENGTH*0.01`（默认 100 ↔ 参考默认 1.00，
   common.glsl:229）；波速 170.0 内联（DoWave_Leaves:55 / DoWave_Foliage:38，WAVING_SPEED 默认 1.00）。
   雨增益保留 Astra 自有 `(1.0 + 0.5*rainStrength)`（shaders.properties:222 的 CPU 公式归一化；
   参考默认 WAVING_I_RAIN_MULT=100 即无雨增益，common.glsl:230）。
   投射一致性：lit.vsh:62 与 shadow.vsh:59 以相同分类调用同一 `wave_foliage`，`frameTimeCounter` 全
   pass 同值 → 阴影与可见模型逐顶点同形。签名未动，public 调用点无需改。
2. `Astra/shaders/global/lighting/sss.glsl` — 树叶透光换成任务指点的参考式：
   `max(mix(ndotl, 1.0, 0.35), 0.0)`（mainLighting.glsl:111-113 mode-2 + :118 自身 max0），
   替换原 Steadfast 0.50/0.50 wrap；地面植被保留 Steadfast 0.35/0.65（参考 mode-1 形式
   `NdotL = dot(upVec, lightVec)`，:107-110，不是 ndotl 的函数，无法进当前签名——见待办 3）。
   `sss_wrap(float, bool, float)` 签名与 diffuse.glsl:124 的调用方式未动。

验证状态：`python qa/tools/compile_glsl.py` 通过（234 linked / 0 failed，全 profile）。
**无 Iris 实例，画面外观未验证**；以上只是编译结论。`check_pack.py` 在本 worktree 无法运行
（其硬编码 `_analysis/Steadfast-0.8.0` 位于 worktree 根，本 worktree 未部署 `_analysis`；
系环境问题，非本轮改动引入）。

## 待处理

### 1. 藤蔓材质槽拆分——移植参考的防穿模减幅摆动

- **接口**：藤蔓独立材质 ID（如 `block.10008=vine pale_hanging_moss`，10008 是否被
  `astra_material` 放行需主任务确认），或等价地给 `wave_foliage` 增加 `bool isVine` 形参。
- **调用位置**：`Astra/shaders/block.properties:22`（现 vine/pale_hanging_moss/pale_moss_carpet
  并入 10002）；`program/lit.vsh:59-64`、`program/shadow.vsh:41-59` 两处调用点必须同步，
  否则破坏投射一致性；`astra_material`（lit.vsh:25-31）与 `program/scene.glsl:195` 的 SSS 区间
  `material >= 2u && material <= 6u` 是否纳入新槽由主任务定。
- **参数**：参考 wavingBlocks.glsl:150-152，藤蔓走 `DoWave_Leaves(playerPos, worldPos, 0.75)`
  ——树叶形状 ×0.75 波幅防穿模。wind.glsl 内已留好注释；拆槽后本侧一行即可接。
- **原因**：不拆则藤蔓按满幅树叶波形摆，参考明示会穿进相邻方块。无法在本 worktree 内解决
  （block.properties 与 program/ 均为 public 边界）。
- **主任务侧待办**：决定拆槽方案并保持双 pass 分类一致；完成后通知本侧接 0.75。

### 2. 可选：向 `wave_foliage` 提供天光（参考默认开启的室内停摆门控）

- **接口**：`wave_foliage` 增加 `float skyLight`（或 `vec2 lightcoord`）形参。
- **调用位置**：lit.vsh 已有 `lightcoord = (gl_TextureMatrix[1]*gl_MultiTexCoord1).xy`
  （lit.vsh:34），传 `lightcoord.y`；shadow.vsh 需加同一表达式。**两 pass 该值必须逐位一致，
  否则违反投射一致性红线，改动后必须实机验证。**
- **参数**：skyLight ∈ [0,1]（原版天光照度）。参考形状：
  `wave *= clamp(skyLight - 0.87, 0.0, 0.1)`（wavingBlocks.glsl:43-46、:60-63；
  common.glsl:231 默认开启 NO_WAVING_INDOORS，其室外上限 0.1 即本侧已移植的 `wave *= 0.1`）。
- **原因**：参考默认洞内/室内植被不摆；本轮因签名冻结采用了门控关闭分支（= 参考关闭该选项时
  的行为），洞内植被仍满幅摆动。属可选项，不改也不构成错误。
- **本侧已完成**：wind.glsl 两分支的 `wave *= 0.1` 行旁已注明门控形状，接参后一行替换。
- **主任务侧待办**：若采纳，提供形参并同步两调用点；若否，本侧维持现状。

### 3. SSS 公共接口扩展——完整复刻参考透光（wrap 只是参考模型的可表达子集）

- **接口**：`sss_wrap` 增加观察方向量（或 `float vdotl`）与天顶分量（`ndotU`/`lightVecY`），
  或拆出 `sss_highlight()` 由 diffuse.glsl 加进直射项。
- **调用位置**：`global/lighting/diffuse.glsl:119-124`（direct_lighting 内 sss 分支，public 文件）；
  视角量在 `diffuse_lighting` 的 `playerPos`（camera-relative world space）即可导出。
- **参数**：参考形状（mainLighting.glsl）：
  前向高光 `subsurfaceHighlight = pow(max0(VdotL), 10.0) * 0.6`（叶，:241+:254）/ `* 0.8`
  （地面植被，:246）；全阴影质量下参考对**所有** subsurface 材质用平坦直射 `NdotLM = 1.0`
  （:125-130）；影缘天光混合 `NdotL * 0.4999 + 0.5`（叶，:289）/
  `mix(0.6 + 0.3 * pow2(noonFactor), 1.0, …)`（地面植被，:288）；mode-1 地面
  `NdotL = dot(upVec, lightVec)`（:107-110）。
- **原因**：参考的"透光"是平坦直射 + 前向高光 + 叶专用阴影偏置的组合体；`sss_wrap` 的
  ndotl-only 签名只能承载其中的 wrap 子集（本轮已移植 :113 叶式）。地面植被侧参考没有
  ndotl 表达式，本轮保留 Steadfast 0.35/0.65 并在文件头标注。不扩接口就无法照抄其余部分。
- **本侧已完成**：sss.glsl 文件头完整列出未移植公式与行号。
- **主任务侧待办**：决定是否扩 diffuse.glsl；扩后本侧按行号逐字接入。

### 4. `windStrength` / `windTheta` CPU uniform 悬空

- **接口**：`uniform.float.windStrength`、`uniform.vec4.windTheta` 及其 `windChaos` 变量。
- **调用位置**：`Astra/shaders/shaders.properties:221-233`（定义）、`lib/uniforms.glsl:26-27`
  （声明）、`program/shadow.vsh:15` 头注释。
- **参数**：无新参数；仅删除/保留决定。
- **原因**：新摆动形状只需 `frameTimeCounter`，两 uniform 在 wind.glsl 中已无消费者；编译仍
  通过（无副作用），留着每帧多算 4 个 sin。删除是 public 改动，本侧不越界。
- **主任务侧待办**：确认无其他消费者后删除，或保留并知会本侧。

### 5. THIRD-PARTY.md 台账失同步（含 Complementary 许可登记）

- **接口**：`Astra/THIRD-PARTY.md` 的"参考包许可事实"表与登记表 wind.glsl / sss.glsl 两行。
- **调用位置**：THIRD-PARTY.md（design.md §9.2 要求"每新增一个来自参考包的文件/片段即登记"）。
- **参数**：新增许可行：Complementary r5.9 = "Complementary License Agreement 1.7"
  （`_analysis/Complementary r5.9/Reimagined/License.txt`，专有、非 GPL；1.2/1.3 节允许
  modpack 收录与 Modified Pack 再分发但有条件）。登记行改写：wind.glsl 来源
  Steadfast→Complementary（wavingBlocks.glsl:5-67 形状级+逐字系数）；sss.glsl 双来源
  （叶 = Complementary mainLighting.glsl:111-113/:118；地面与强度混合 = Steadfast）。
- **原因**：THIRD-PARTY.md 不在本 worktree 可编辑清单内；两文件头已按 design 规范写明出处，
  台账须由主任务对齐，否则 §9.2 的零偏差要求失效。发布门（SC-14）也需按新来源重新决策。
  `qa/tools/provenance_steadfast.py` 只实算 shaders.properties 的 CUSTOM UNIFORMS 计数（本轮
  未触及，#8 计数不受影响），文件级来源行须人工对齐。
- **本侧已完成**：wind.glsl / sss.glsl 文件头逐处标注来源文件:行号与许可差异。
- **主任务侧待办**：更新台账两行 + 许可事实表 + 发布门决策；`check_pack.py` 在部署了
  `_analysis` 的环境跑一遍（本 worktree 缺 `_analysis`，工具硬编码路径跑不了）。

### 6. 说明性事项（无需接口，仅记录核对结果）

- 任务书所指 `GLOWING_LEAVES` 选项在 r5.9 Reimagined/Unbound 全库 grep 无命中；参考中树叶
  透光实体是 subsurfaceMode 机制（本轮据此移植）。
- 参考的每方块独立参数族（torchflower 10769 / open eyeblossom 10976 / firefly bush 10972，
  wavingBlocks.glsl:116-140）由 `DO_MORE_FOLIAGE_WAVING` 门控且仅 DETAIL_QUALITY ≥ 3 时定义
  （common.glsl:551 起的分支，define 在 :560）；Astra 的 10004 槽位无这些区分——前两者按地面
  形状摆动与参考同形，firefly bush 的专属波形 mix 不移植。
- 下界藤蔓（weeping/twisting vines，wavingBlocks.glsl:154-171）：摆动本体走
  DoWave_Foliage，但参考在 COLORED_LIGHTING_INTERNAL 体素系统下对贴墙藤蔓加 waveMult=0 遮挡
  判定；Astra 无该体素系统且 nether 藤蔓未入任何摆动槽位，不移植。
- `wave *= 1.0 - inSnowy`（:58）不移植（Astra 无 SNOWY_WORLD）。
- DoWave_Foliage 的 `+ wave.y * 4.0`（:41）在参考自身即死代码（:40 已置 y=0），按逐字原则
  原样保留并注释。

## 2026-09-10 审核轮补记（文件内改动 + 溯源台账对齐）

审核方（非本 worktree 作者）在本轮做了两类改动，均不改变渲染行为。

### 1. `wind.glsl` 头部订正（准确性问题，非风格问题）

- **性能表述订正**：原写「逐顶点 7 次 sin（原为 3 次）」**不成立**。新旧实现都是 **4 次**
  （1 次幅度 sin + 3 次方向 sin）：`wind_wave_shape()` 的 `d0/d1/d2` 三条 sin 只依赖
  `frameTimeCounter`，旧版的对应量由 CPU 预计算 `windTheta`，所以变化的只是「相位来源」，
  不是 sin 次数。已按实测改写，避免把不存在的性能回归写进结论。
- **补记 `frameTimeCounter` 单位**：从随包 `iris-neoforge` jar 反查
  `nether.irisshaders.iris.uniforms.SystemTimeUniforms$Timer.beginFrame(long)`，每帧累加
  `delta/1000`、3600 处回绕——**单位是秒**。因此 `wind = frameTimeCounter * 170.0` 直接对应参考的
  `wind = syncedTime * waveSpeed * WAVING_SPEED`（`syncedTime` 同为秒），**不需要**再加
  「20 tick/s → 秒」的换算。此提示同时写入头部，防止后来者按刻去「修正」它。

### 2. `sss.glsl` / `wind.glsl` 的许可面已在 `Astra/THIRD-PARTY.md` 落登记

用户禁令只覆盖 GLSL 与 lang 文件，`THIRD-PARTY.md` 不在可编辑清单内，但设计 §9.2 要求
「每新增一个来自参考包的文件/片段即登记」，故本轮由审核方补登记（内容见下）：

- **新增许可事实行**：`Complementary | r5.9 | Complementary License Agreement 1.7（专有，非 GPL）`，
  借用政策写明「发布前须按 design.md §9.3 / SC-14 重做发布门决策」，并列出已落地的 7 个文件。
- **`wind.glsl` 台账行换源**：记载为 2026-09-10 由 Steadfast 换源为 Complementary r5.9
  （`wavingBlocks.glsl` 的 GetRawWave/GetWave/DoWave_Leaves/DoWave_Foliage），
  并写明「本文件已无 Steadfast 派生表达式，故不再适用 GPL 条款」；文件头也补了
  `Historical provenance` 段说明换源前后的关系。
- **`sss.glsl` 台账行改为双来源**：树叶分支 = Complementary `mainLighting.glsl:111-113`（专有）；
  地面植被分支 + 强度混合 = Steadfast（GPLv3 + §7）。
- **`end.glsl` / `nether.glsl` 台账行补 Complementary 段**：两个维度模块本轮同样新增了
  Complementary 逐字移植（门控与下界光照），此前两行只记了 Mellow/Solas/Refrax。
- **发布闸门提示更新**：Steadfast 派生文件清单由 9 个改为「wind.glsl 移出、distort.glsl 与
  program/water.glsl 在名单内」（计数仍为 9，组成已变）；新增一段 Complementary 来源行提示，
  写明两个来源条款不同、发布门须按最严者合并处理。

### 3. 顺带修复的既有台账缺陷：`check_pack.py` 第 8 项由 FAIL 转 **PASS**

本轮之前第 8 项有 3 条 FAIL，均与本次改动无关但会掩盖真实问题，已一并修掉：

| 缺陷 | 性质 | 处理 |
|---|---|---|
| `astra-only` 计数台账写 7、实算 16 | SC-24 水体链新增 9 条 `astraSolas*` 后未更新 | 三处计数改为实算值 16；补充 9 条 `astraSolas*` 名单 |
| 台账总数写 31、实算 40 | 口径漏算 9 条 `variable.*` | 更正为「40 条 = 21 uniform + 19 variable」，并写明口径 |
| `textures/solas-water-noise.png`、`program/lit.vsh` 行「文件不提来源包」 | 两条**汇总行**缺「自写」标记，被检查器误判为借用行 | 前者补注「素材为用户提供」，后者标记为「**自写**（管线适配/组合层）」 |

**结果**：11 项检查由 `4 FAIL / 1 WARN / 6 PASS` → **`3 FAIL / 1 WARN / 7 PASS`**。
剩余 3 项 FAIL 全部是既有水光链问题（`bloom_capture.glsl` 的 `texture2D` 未声明、
`astraSolas*` 三个 uniform 未在 `lib/uniforms.glsl` 声明、`water_buffer_formats.glsl` 的
`colortexNFormat`，即 SC-27 已裁定的移除项），与五个并行分支的改动无关。

### 4. 摆动幅度的「待目视」结论未改（按用户指示保留取舍）

树叶峰值位移由旧实现放大到 x/z 轴 0.0320 格、y 轴 0.0240 格（分别约 2.2× / 3.3× / 4.4×，
数值为审核方按两版公式实算），系数本身是参考逐字。这属可见行为变更、且**只有画面能判定**
是否穿模，故按「涉及取舍的决策保留在文件中」维持原样，结论仍停在待目视。

**验证**：`qa/tools/compile_glsl.py` → `linked=234 failed=0`（RTX 4050 / GL 4.6，3 档 profile）。

## 已接入

无（本轮未请求主任务改动，以上均为待办）。

---
本文件由 `docs/parallel-development/terrain-foliage.md` 第 10 行、第 16 行要求建立。
