# Astra 光影 · 全面代码审查报告（2026-09-20）

审查代理：Qoder 审查代理（本会话，只读模式）
> 说明：你要求署名"由 Qwen3.8flash 审查"。Qoder 不对外暴露、也不由我代为声明底层模型身份，所以我用了中立的署名方式。审查内容与结论不受影响；如果你需要在文档里标记来源，可以自行改成你想要的字样。

约束执行情况：**全程未修改任何代码文件**。本次审查产生的唯一文件是本文档。核验方式：直接读取 + 逐行引用 + `grep` 交叉调用者计数 + Python 离线复算数值（无 GPU 写入、无 git 写操作）。

---

## 1. 审查总结

架构分层（`lib/` 声明 → `global/` 功能 → `program/` pass → 维度壳）在包内是真被执行的，不是文档话术；类型正确性、坐标系契约（SC-35）、单位与缓冲格式的显式声明都做得比多数同类包扎实。**但当前状态不可发布**。

核心问题高度集中在一处：**代码注释所断言的行为与代码实际行为不符，而校验工具链只验证"能否编译"，不验证"是否生效"**。你提出的两个"一直没有实现"的需求（水下光束、俯视水体的青绿→深蓝）都不是缺代码，而是各自有一条**完整的死链**和一处**数学上不成立的项**，其中水体颜色还是**蓝图层面的分工遗漏**——所以无论怎么调滑块都不会出现。

分级口径：P0 = 挂死/崩溃；P1 = 逻辑错误、控制项无效、契约被破坏；P2 = 可移植性/性能；P3 = 卫生项。

| 级别 | 数量 | 判定 |
|---|---|---|
| P0 | 0 | 未发现新的挂死/崩溃路径（09-11 的 End 黑洞挂死已修，见 commit 7e3b1e7） |
| P1 | 14 | 阻塞发布 |
| P2 | 22 | 影响可移植性与帧率 |
| P3 | 15 | 记录待处理 |

数量为**交叉核验后的终值**：原始审查交出 12 / 12 / 13，交叉核验新增 2 / 10 / 3（F-40 … F-54），另有 1 条（F-38）被我自己的复算推翻并从 P3 中撤回，因此 P3 是 15 而不是 16。新增的 15 条里，出处并不全在外部报告：F-40、F-51、F-53 是我在复核过程中补算出来的，F-41、F-47 只有一半来自外部，其余来自 `docs/2026-09-20-glm53flash-full-review.md` 与 `docs/2026-09-20-hunyuan-full-review.md`。逐条判定、采纳理由与分档分歧见 §10。

**用本报告行号前必读**：审查收尾期间工作树被另一条执行线推进（HEAD `7e3f51c` → `ef90edb` + 未提交修复），上表的**分级与条数不受影响**，但若干行号已漂移、若干条目已修 —— 状态表与漂移清单在 §9.1。

**先做三件事**：① 修 `program/lit.fsh:362`（一条语句同时废掉 colortex5/colortex6 两条链）；② 删掉 `global/water/light_shafts.glsl:54` 的相位项或改为与观测方向解耦；③ 重写 `global/water/absorption.glsl:16-31` 的光谱次序并给空气侧加体散射项。三处都是可验证的小改动，且分别对应"两个未实现需求"的主因。

---

## 2. 架构评估

**成立的部分**

- 三层依赖方向没有发现**反向** include（`global/*` 不 include `program/*`，唯一的 program 级 include 是 `lit.fsh:8/:12`，且注释 `:6-7` 明确声明了这是程序级例外）。
  **更正（交叉核验后）**：这条原表述把两件事合成了一件。`design.md:209` 冻结的完整条款是"新增 program/scene.glsl 作为 program 内共用组合器，**global 不 include 其他 global**"。前半句成立，后半句被违反 8 次（`clouds_planar.glsl:48`、`stars.glsl:29`、`end.glsl:3`、`end_blackhole.glsl:20`、`end_ring.glsl:3`、`end_system.glsl:5`、`nether.glsl:13`、`light_shafts.glsl:27`）。见 F-51。
- 缓冲契约集中声明：格式在 `lib/water_buffer_formats.glsl`，尺寸/清除色在 `lib/settings.glsl:336-361` 与 `shaders.properties:8-20`，并带交叉引用注释。这是 Iris 包里少见的纪律。
- 维度壳复用同一套 `global/`，靠 `DIMENSION_*` 宏分派（`program/scene.glsl:39-52`），三个维度的差异集中在 `global/dimension/*`，没有复制粘贴出第二份水面/大气实现。
- 坐标契约（SC-35）实测一致：`shadow.vsh:85,113` 与 `lib/transforms.glsl:94-101` 吻合，全包无 `cameraPosition` 绝对坐标混入 `shadowModelView`；显式 `[3].xyz` 只出现在 `global/dimension/nether_volume.glsl:63-64,102`。

**结构性风险（按严重程度）**

1. **主管线契约建立在一组互斥的 pass 顺序断言上**（P1，见 F-01 的姊妹项 F-02）。`design.md:90/:493` 与 `docs/2026-09-13-astra-full-audit.md:698` 断言"deferred 先于半透明"，而 `program/deferred.fsh:107-108` 消费的 HAND 高 1bit 由 `gbuffers_hand` 写入——手部在所有半透明之后绘制。两者不可能同时为真。这是全包唯一一处"架构级未决前提"，它决定了 colortex4 是本帧还是上一帧、决定了天空回填是否会出黑条。
2. **一条语句承载三种语义**：`gl_FragData[1]` 在不同 `#ifdef` 分支下分别指向 colortex3 与 colortex5（`lit.fsh:23/27`），于是 `:362` 与 `:374` 看起来是同一段代码的复制，实际写到两个不同缓冲。这是本次最严重的两处缺陷的共同成因。
3. **循环体内使用隐式 LOD 采样**（见 F-14，本条引证已在交叉核验中重做）：对全部 245 个着色器文件做花括号配平扫描，循环体内的裸 `texture()` 只有 4 处，其中**唯一落在开了 mipmap 的缓冲上**的是 `global/water/bloom_capture.glsl:21` 采 `colortex0`（`program/water_bloom.fsh:5` 声明了 `colortex0MipmapEnabled = true`），且它处在逐像素 `if` 的分支内 —— 同包 `global/post/bloom.glsl:107` 对同一语义已写成 `textureLod(…, 0.0)`，属可实现而未实现。其余 3 处采的是未开 mipmap 的缓冲，只在跨驱动行为上有风险。

---

## 3. 专项一：水下光束为什么一直没实现

代码是齐的（`global/water/light_shafts.glsl` 有 march 与 resolve、`program/scattering.fsh:39` 在 `isEyeInWater==1` 时调用、`program/water_composite.fsh:19` 把结果合成），选项门控也正确（`lib/settings.glsl:344-348` 派生 `ASTRA_UNDERWATER_SHAFTS`，三个 profile 都开着）。失效来自五处叠加，按影响从大到小：

### 3.1 相位项在数学上互斥（P1，决定性）

`global/water/light_shafts.glsl:47-54`：

```glsl
float VoU = 1.0 - pow(clamp(ray.y, 0.0, 1.0), 1.5);          // :47  要求视线朝下
float VoL = pow(clamp(dot(ray, normalize(view_player(lightVector))), 0.0, 1.0), 1.5); // :48 要求视线朝太阳
visibility *= pow(VoU, 1.5);                                  // :53
visibility *= mix(0.25 + VoL * 0.25, VoL * 0.45, time);       // :54
```

`time = astraSolasTimeBrightness`，其定义为 `max(sin(astraSolasTimeAngle * 2π), 0)`（`shaders.properties:304`），**正午 = 1，晨昏 = 0**（已核对 `astraSolasTimeAngle` 的构造，`:298-303`）。于是正午时 `:54` 退化为 `0.45 * VoL`：光束强度要求 `ray` 指向太阳。而能看到光束的像素是海底方向（`ray.y < 0`），此时 `dot(ray, sun) ≤ 0` → `VoL = 0` → **visibility 精确等于 0**。

反方向也不行：直视太阳时 `ray.y = sin(elev)`，`pow(VoU,1.5)` 把它压掉。太阳仰角 60° 时整组相位因子 ≈ `0.45 × 0.086 = 0.039`；仰角 20° ≈ `0.27`。也就是说：**唯一能出光束的时间窗是"低太阳 + 朝地平线方向平视"**，正午低头看海底恒为 0。这正是你看到的"没有实现"。

蓝图 `design.md:292`（SC-33）要求的是前向散射相位，没有要求"视线必须指向太阳"这一硬约束——`:54` 的实现方式是把相位写成了乘性硬门，属于实现偏差，不是需求如此。

**交叉核验后补强（两条）**

1. **正午向下不是"很暗"，是精确等于 0，并且整个 march 被跳过。** `time=1` 时 `:54` 化为 `VoL*0.45`，向下视线 `dot(ray, sun) < 0` → `VoL = 0` → `:56` 的 `if (visibility <= 0.0) return …` 直接早退。所以"正午潜水看不到光束"和"正午潜水不消耗光束成本"是同一件事的两面——这条也解释了为什么历史上任何一次"把 `UNDERWATER_SHAFT_STRENGTH` 调大"的尝试都无效：滑块乘在一个已经被判为零的分支之后。
2. **同一个函数里两个相位窗口互相矛盾。** `:48` 的门用**空气**太阳向量，`:112-114` 的相位用**折射后**的太阳向量（`refractSun`）。门说"正午向下没有光束"，相位说"正午向下光束最强（≥0.35 地板）"。二者只有在低太阳角才近似一致。

**并且要修正 GLM 报告的修法。** `docs/2026-09-20-glm53flash-full-review.md` 8.2.1-1 建议"把 `refractSun` 提前到循环前，`VoL` 门改用它"。诊断我完全采纳，**修法我算过之后不成立**：正午时 `refractSun ≈ (0, +1, 0)` 的折射结果仍指向上半球，向下视线 `dot(refractSun, ray)` 同样为负 → 换成 `refractSun` 之后 `VoL` 依然是 0。把 `refractSun` 提前只解决"两个窗口用两套方向"的一致性问题，不解决零。真正要动的是**门的形状**（去硬门、给地板，见 §3.7 Step 2 的柔和相位写法），这一步不可省略。

### 3.2 逐样本衰减链把剩余信号压到 1% 量级（P1）

`:79-106` 的乘积（默认 `UNDERWATER_SHAFT_SAMPLES=7`、`maxDist=40`）：

| 环节 | 行 | 量级 |
|---|---|---|
| 距离权重 `pow((d/40)/N, 1-time*0.5)` | `:79-80` | ≤ 0.38，典型 0.02–0.14 |
| 阴影二值判定 `(tex.r - pos.z) * 65536` | `:95` | 0 或 1（任何 >1/65536 的深度差直接判全暗） |
| 硬跳过 `if (shade <= 0.0) continue;` | `:100` | 与 `:29-35` 的头注释直接矛盾 |
| 焦散 `c³` | `:101` | 水下 `c∈[0.2,1.64]`，立方后典型 0.06–0.5 |
| 距离衰减 `/ max(3.0, d*0.1)` | `:104` | ≤ 1/3 |
| 二次相位 `mix(0.35, 1.0, …)` | `:114` | ≥ 0.35 |

把这些与 3.1 的 0.039 相乘，再乘 `(4 + sun*8)`（`:115`），得到的 `integral` 最好情况约 5e-3～1e-2。然后 `:118` 编码为 `pow(clamp(integral/128,0,1), 0.25)`。

**同时注意 `:29-35` 的注释**："the previous version HARD-SKIPPED fully shadowed samples … The reference does neither" —— `:100` 又把它写回来了。这已经是本包第 N 次出现"注释描述的是想要的行为，代码是旧行为"。

### 3.3 RGBA8 编码把可用码字压到前 ~20 级（P2）

`shaders.properties:8-13` 只在开启光束时把 colortex1 提到 1.0 分辨率，**没有声明格式**，因此是 Iris 默认 RGBA8。上面 1e-2 量级的信号经 `/128` 后是 8e-5，开四次方 ≈ 0.087，落到 22/255；`resolve`（`:129`）再 `pow(…,4)*128`。整个可见动态范围只用了缓冲区最低的 ~9% 码字，而 `pow(…,4)` 会把 1 个量化级的误差放大 4 倍 → 抖动先于信号出现。

### 3.4 resolve 丢掉了距离信息（P2，蓝图偏差）

`:121` 的签名带 `float rayLength`，函数体（`:122-130`）从未使用；4 个 tap（`:124-128`）等权平均。`design.md:292` 明确要求"距离加权重建"。结果：光束在深度不连续处（海底边缘、鱼群、方块边界）会跨深度糊在一起。

### 3.5 合成端把光束加在雾之后（P1）

`program/water_composite.fsh`：

- `:13` 读 `colortex0`，`:11` `RENDERTARGETS: 0` —— **同一 pass 读写同一缓冲**，GL 语义下未定义（多数驱动可用，AMD/移动 GPU 上会出脏像素）。
- `:23` `clamp(color, 0.0, 1.0)` 把线性 HDR 截成 [0,1]，注释自己承认"in reference order … Preserve that bound"。而 colortex0 的格式是 `R11F_G11F_B10F`（`lib/water_buffer_formats.glsl`），此时体积雾（`lib/solas_water.glsl:91-100`）已经算进去了，`solas_water.glsl:110` 又做 `color*color + shafts`：**光束是加在已含雾的亮度上，而不是被雾消光**，所以它即使有值也表现为"贴在雾上的一层白斑"，而不是穿过水体的光柱。

### 3.6 蓝图要求的验证链整条是死的（P1，连带需求）

`design.md:292` 要求先用"水面透光率"验证再谈光束。这条数据链每一环都断：

```
lit.fsh:362  gl_FragData[1].a = …        → 水 pass 的 gl_FragData[1] 是 colortex5（:23），不是 colortex3
water_state.fsh:19  if (data.a < 0.5) continue;  → 240 个网格样本全部跳过
water_state.fsh:35  water_volume_state()         → colortex6 唯一读者是它自己（读上一帧），无下游
shadowmap.glsl:217  shadow_water_depth()         → 全包 0 个调用者
```

更糟的是叠加 `shaders.properties:54-56` 的 `blend.gbuffers_water.colortex5 = SRC_ALPHA …`：水 pass 写出的 `src.a = 0` 会让 **colortex5.rgb 整条不写入**，水表面高度编码（`lit.fsh:354-356` 的 `water_pack_surface_height`）全部丢失。而 `lit.fsh:341` 的注释"Nothing reads colortex3.a"、`:346-347`"the water pass: 0 … where .a currently holds a constant 1.0 that has no reader"、`:348-349`"translucents and weather: 0, via the else-branch" —— **三条断言全部为假**：`:362` 写的是 colortex5；消费者是 `water_state.fsh:19/:33`；透明与 weather 在 `#ifndef ASTRA_TRANSLUCENT`（`:364`）下根本不执行该分支，全包只有 `:374` 一名写者。

### 3.7 实现建议（按顺序执行，每步都能单独验证）

**Step 1 — 恢复数据链（先让它可测）**
把 `:362` 的水面合法性/遮罩移出 colortex5.a。三种可选，代价从低到高：
- 让水 pass 用第三槽：`lit.fsh:23` → `/* RENDERTARGETS: 0,5,3 */`，`gl_FragData[2].a` 承载遮罩（需要给 colortex3 的不透明写者同步加一槽）；
- 或水 pass 完全不写 `gl_FragData[1].a`，把水面有效性编码到 colortex5.b（`lightLevel.y` 目前只占 8bit，可与 validity 共位打包）；
- 顺带修 `shaders.properties:54-56`：colortex5 的 blend 用 `SRC_ALPHA` 却期望 alpha=0 时仍写 rgb，逻辑自相矛盾，应改为 `blend.gbuffers_water.colortex5 = off`。

同时删除 `lit.fsh:341/346-349` 三条伪断言，并把 `#ifndef ASTRA_TRANSLUCENT` 分支的注释改成"仅地形 writer"。

**Step 2 — 修相位**
删除 `:54` 中朝太阳的硬门，改成前向散射的柔和相位（HG 形式，g≈0.6）并与"视线朝下"解耦：

```glsl
float cosTheta = dot(ray, normalize(view_player(lightVector)));
float g = 0.6;
float phase = (1.0 - g*g) / (4.0 * 3.14159 * pow(1.0 + g*g - 2.0*g*cosTheta, 1.5));
visibility *= mix(0.35, 1.0, clamp(phase * 6.0, 0.0, 1.0));   // 归一并留地板
```
并给 `:51` 的 `sunGate` 加一条独立的月亮路径（夜间 `visibility` 现在恒 0，月亮光束虽少见但不该是硬 0）。同时删掉 `:112-114` 的第二套相位——两套折射方向不一致（`:113` 用 `(0,-1,0)` 界面法线，而 `:82` 的焦散用的是另一套），保留一套即可。

**Step 2b（一致性收尾，不能替代 Step 2）**：把 `:112-113` 的 `sunWorld` / `refractSun` 上提到 `:48` 之前，让门与相位共用同一个折射方向。我复核过 Snell 代数：`refract(sunWorld, vec3(0,-1,0), 1/1.2)` 虽然法线取向与常规相反，但结果 `= (η·sinθ, √(1−η²sin²θ), 0)` 与正确折射线一致，无需为此改动。此步只消除"两处方向不一致"，**不改变正午向下为 0 的结论**（见 §3.1 补强 2 末尾）。

**Step 3 — 修衰减**
`:100` 的 `continue` 换成软衰减（`shade = smoothstep(0.0, 0.02, shade)` 或直接乘）；`:95` 的 `*65536` 换成与 `SHADOW_FILTER_MODE==1` 相同的 PCF 通路（三个 profile 都设 `SHADOW_FILTER_MODE=0`，所以现在永远走硬判定那条）；`:104` 的 `max(3.0, …)` 改 `max(1.0, …)`；焦散改为 `pow(c, 1.5)` 或直接 `c`（立方在 7 个样本上是 504 次纹理取样的代价换 0.06–0.5 的衰减，性价比极差，见 §7）。

**Step 4 — 修编码与重建**
`shaders.properties` 增加 `colortex1Format = R16F`（光束与 godrays 都受益），或者在 RGBA8 前提下把 `:118` 的 `/128` 改成 `/ max(integralMax, 1.0)` 的动态归一。`:121-130` 使用 `rayLength` 做深度感知加权：`weight = exp(-abs(sampleRayLength - rayLength) * 4.0)`。

**Step 5 — 修合成**
`water_composite.fsh`：把 `:11` 改成写入一张独立的拷贝缓冲（或把源改成 `colortex4` 一类只读源）以消除同缓冲读写；删除 `:23` 的 `clamp(color, 0, 1)`，并把光束合成移到 `solas_water_composite` 的**雾计算之前**（即先 `radiance + shafts` 再做雾/吸收，让光束被水体消光），或在 `solas_water.glsl:91-100` 内部把 shafts 作为 in-scatter 源项参与 `(1-T)` 分配。

**验收方式（不要靠肉眼）**：在 `scattering.fsh` 临时输出 `gl_FragData[0] = vec4(visibility, …)` 并把 colortex1 接到 debug view，扫三个时刻（日出/正午/黄昏）与三个视角（俯视海底/平视/直视太阳），确认 `visibility` 在"俯视海底"时非零；再确认 `water_state.fsh` 的 `best` 不再恒为 `vec4(0)`。

---

## 4. 专项二：俯视水体的"青绿→深蓝"为什么一直没实现

**结论：当前实现无法通过调参达到该效果，且蓝图明确把蓝色划给了"潜水相机"，空气侧根本没安排蓝色。** 这是遗漏需求的规格，不是没写完的代码。

### 4.1 分工遗漏（根因）

- `design.md:79`：空气侧呈现为青色，蓝色只属于水下相机。
- `global/water/absorption.glsl:55-57` 注释：`// Air-side appearance … Do not add the blue underwater volume source to this branch.`

也就是说，"从空气侧看到的水体变蓝"在规格里就不存在。任何后续实现都必须先改这条分工，否则改完还会被"遵守蓝图"的理由回退。

### 4.2 光谱次序决定：空气侧极限色是绿，不是蓝

`absorption.glsl:16-31` 默认（`WATER_CHARACTER=1`，也是三个 profile 的设定值）：

```glsl
vec3 coefficient = vec3(1.000, 0.0600, 0.1000);   // c_R, c_G, c_B
```

`water_surface_medium`（`:58-62`）只做 `radiance * exp(-appearanceDepth * c)`。因为 **c_G(0.06) < c_B(0.10)**，绿衰减得比蓝慢 → 越深 G/B 越高 → 极限方向是绿色。离线复算（`WATER_ABSORPTION=100`，即系数 ×1.0）：

| 垂直深度 | R | G | B | G/B |
|---|---|---|---|---|
| 0 | 0.3679 | 0.9418 | 0.9048 | 1.04 |
| 2 | 0.0498 | 0.8353 | 0.7408 | 1.13 |
| 6 | 0.0009 | 0.6571 | 0.4966 | 1.32 |
| 10 | 0.00002 | 0.5169 | 0.3329 | 1.55 |
| 14 | ~0 | 0.4066 | 0.2231 | 1.82 |
| ≥15 | 0 | 0.3829 | 0.2019 | **1.90（冻结）** |

三个致命细节：
1. **G/B 单调上升到 1.9**，全程没有一次交叉 → 永远不可能变蓝。
2. **c_R = 1.0/方块**：深度 1 方块时红色只剩 13.5%，2 方块剩 5%。青绿色带被压缩到约 2 方块内，肉眼看到的是"浅滩直接跳绿"。
3. `:60` `clamp(depth + 1.0, 0.0, 16.0)`：15 方块以下像素值完全相同（表中 15/20/40 行一致），深海是一条常数带。

补充事实：`WATER_CHARACTER=0`（COLD，`:22` 的 `(1.000, 0.2200, 0.0800)`）确实会让 G/B 从 0.87 降到 0.11 —— **包内已经存在一条通往蓝色的路径，只是默认值和全部三个 profile 都不是它**（`shaders.properties:166-168` 一律 `WATER_CHARACTER=1`）。这说明"没实现"不是能力问题，是默认配置 + 规格遗漏。但 COLD 仍然有 `c_R=1.0` 与 16 方块 clamp 两个毛病，所以它也不是最终答案。

### 4.3 空气侧没有体散射项

真实水体从空气侧看变蓝，主因是**水面以下介质的前向/各向同性内散射把天空的蓝色带回视线**，而不是透射本身偏蓝。`water_surface_medium`（`:58-62`）只有透射项，没有任何 in-scatter 源项，因此深海不可能出现"像天空一样蓝"。这也是 `:55-57` 那条注释禁止的东西。对照：水下相机分支 `water_transport`（`:45-51`）有 `incidentLight * scatteringAlbedo * (1-T)`，是正确的形式——只是空气侧被明确排除在外。

**交叉核验后补一条可代入算证的极端情形（对应 F-40）**：床不可见的地方（深湖、远海，`program/water.glsl:37-38` 对 `anchorDepth >= 0.999999` 直接拒绝）会走空气侧回退分支

```glsl
// program/water.glsl:293-297
vec3 deepFallback = belowWater
    ? astra_water_air_sky(transmittedWorld)                       // 水下：有天空回退
    : astra_water_segment(vec3(0.0), playerPos,                   // 空气侧：入射亮度 = 0
                          playerPos + transmittedWorld * 96.0, skylight);
```

而 `astra_water_segment` 在 `isEyeInWater == 0` 时（`program/scene.glsl:105-107`）只做 `return water_surface_medium(radiance, …)`，即 `radiance * exp(-depth*c)`。**把 `radiance = vec3(0.0)` 代进去，结果与深度、光谱、`WATER_ABSORPTION` 全部无关，恒等于 `vec3(0.0)`。** 也就是说开阔深水在这一支里透射项是纯黑，画面只剩 Fresnel×天空反射——深水读作"黑色的镜子"，不是"深蓝的水体"。同一处 `belowWater` 三元表达式的两个分支不对称（水下有 `astra_water_air_sky`，空气侧没有等价物），正是 §4.1 那条"分工遗漏"在代码里的形状。

### 4.4 修改建议（含数值）

**核心三招**：把光谱次序改成 R>G>B（透射极限变蓝）、加空气侧内散射 tint（青绿→深蓝的色相梯子）、把 clamp 换成真饱和曲线。

```glsl
vec3 water_surface_absorption() {
    // R 衰减最快、B 最慢：透射极限色因此是蓝，不再是绿。
    #if WATER_CHARACTER == WATER_COLD
        vec3 coefficient = vec3(0.28, 0.11, 0.045);
    #elif WATER_CHARACTER == WATER_TROPICAL
        vec3 coefficient = vec3(0.36, 0.075, 0.030);   // 红移除最强、绿作用最长 → 加勒比青
    #else
        vec3 coefficient = vec3(0.32, 0.095, 0.040);
    #endif
    return coefficient * (WATER_ABSORPTION * 0.01);
}

// 新增：水体自身颜色，浅处青绿、深处深蓝，由深度饱和曲线驱动
vec3 water_body_tint(float depth) {
    float hue = 1.0 - exp(-depth * 0.12);          // 0→1，约 12 方块走完色相行程
    vec3 shallow = vec3(0.10, 0.62, 0.55);         // 青绿
    vec3 deep    = vec3(0.02, 0.13, 0.32);         // 深蓝
    return mix(shallow, deep, hue);
}

vec3 water_surface_medium(vec3 radiance, float verticalDepth, vec3 incidentLight) {
    float depth = max(verticalDepth, 0.0);
    vec3 transmission = exp(-depth * water_surface_absorption());   // 去掉 +1 与 16 的 clamp
    float coverage = 1.0 - exp(-depth * 0.18);                      // 床体被水色接管的比例，~12 方块 88%
    return radiance * transmission + water_body_tint(depth) * coverage * incidentLight;
}
```

签名新增 `incidentLight`：调用点 `program/water.glsl:80` 与 `:95` 已经持有 `skylight` 并在使用 `astra_water_incident(skylight)`（`:81` 就用了），因此是零额外成本的改动。

离线复算该方案（`incidentLight=(0.55,0.75,1.0)`）：

| 深度 | R | G | B | B/R | B/G | coverage | hue |
|---|---|---|---|---|---|---|---|
| 0 | 1.00 | 1.00 | 1.00 | 1.0 | 1.00 | 0.00 | 0.00 |
| 1 | 0.73 | 0.97 | 1.00 | 1.4 | 1.03 | 0.16 | 0.11 |
| 3 | 0.40 | 0.89 | 1.00 | 2.5 | 1.13 | 0.42 | 0.30 |
| 8 | 0.10 | 0.63 | 1.00 | 10.4 | 1.58 | 0.76 | 0.62 |
| 12 | 0.04 | 0.47 | 0.92 | 23.8 | 1.96 | 0.88 | 0.76 |
| 20 | 0.015 | 0.26 | 0.75 | 50.6 | 2.83 | 0.97 | 0.91 |

即：浅处红退、青绿留下（1–3 方块）；中段仍带绿（5–8 方块）；深处蓝独存且**没有上限冻结**（B/G 持续上升到 4.4@40 方块）。

**必须一并处理的配套项**，否则改了也看不全：
1. 删除 `absorption.glsl:55-57` 的禁止注释，并在 `design.md:79` 更新分工（写成"空气侧 = 青绿→深蓝的色相行程 + 菲涅尔反射叠加"）。
2. `program/water.glsl:73-81` 与 `:93-96` 的 SSR/折射背景采样也走 `water_surface_medium`：它们传的是 `dot(origin - point, faceNormal)`，改签名后需要同样传 `incidentLight`。
3. 水下相机的雾色来自 `lib/solas_water.glsl:91-100`，与 `WATER_CHARACTER` 无关——这是 SC-34 的既定分工，但意味着"水类型滑块不影响水下雾"。建议在 UI 上标注，或让水下雾至少共享 `water_scattering_coefficient()`。
4. 验收：用固定种子建一个 20 方块深的水池，`WATER_ABSORPTION` 取 30/100/200 三档，各截一张俯视正交图，比较逐深度带的色相角（HSL 的 H 通道）。期望 H 从 ~170°（青绿）单调移到 ~215°（深蓝）。这张表当前不可能通过——它是 §5 里"证据缺口"的具体补法。

---

## 5. 发现清单

### P1（提交前必须修）

**F-01 水坑/validity 遮罩写错缓冲，同时摧毁 colortex5**
`program/lit.fsh:362` 在 `ASTRA_WATER_PASS` 分支内写 `gl_FragData[1].a`，而该分支的 `gl_FragData[1]` 是 **colortex5**（`:23`）。后果：① `water_state.fsh:19` 的 `if (data.a < 0.5) continue;` 对 240 个样本恒真，整个中值搜索被跳过，colortex6 永不更新；② 叠加 `shaders.properties:54-56` 的 `SRC_ALPHA` 混合，colortex5.rgb 完全不写。`lit.fsh:341/346-349` 的注释断言与代码相反。
为什么重要：一条语句同时废掉两个缓冲、一条 blend 与三处注释，并且直接导致 §3.6 的验证链不可能建成。
建议：见 §3.7 Step 1。

**F-02 管线契约建立在互斥的 pass 顺序断言上**
`design.md:90/:493`、`audit:698` 称"deferred 先于半透明"；`deferred.fsh:107-108` 却消费 `gbuffers_hand` 写的 HAND 位（手在半透明之后）。二者不可同时成立。若 deferred 实际在后，则 `program/water.glsl:66,78,93,125,145` 在 `gbuffers_water` 里读的 colortex4 是**上一帧**副本却与本帧 `depthtex1` 配对（折射/SSR 背景滞后一帧）；同时 `deferred.fsh:170-178` 的天空回填门控用含半透明的 `depthtex0`，而 `sky.fsh:136-139` 在 `CLOUD_MODE != CLOUD_VANILLA`（BALANCED/ULTRA 默认）时输出纯黑 → 雨幕/信标/半透明粒子/对天水面拿到黑天空。
建议：实机探针一次定论（deferred 写已知图案 → `gbuffers_water` 读回打印），再据结果决定：不透明副本改由 `lit.fsh` 不透明变体多写一槽；天空回填改用不透明专用深度（全包未声明 `depthtex2`）。

**F-03 水下光束相位项在正午恒为 0**
`global/water/light_shafts.glsl:54`（详见 §3.1）。
建议：改柔和相位，见 §3.7 Step 2。

**F-04 光束衰减链把信号压到不可见**
`light_shafts.glsl:95,100,104,79-80` + `:29-35` 注释与 `:100` 矛盾（详见 §3.2）。
建议：见 §3.7 Step 3。

**F-05 水体空气侧透射极限色是绿，且 15 方块后冻结**
`global/water/absorption.glsl:28`（c_G<c_B）、`:60`（clamp 16）（详见 §4.2）。
建议：见 §4.4。

**F-06 空气侧无内散射源项**
`absorption.glsl:55-62`，且被注释明确禁止（详见 §4.3）。
建议：见 §4.4；同时更新 `design.md:79`。

**F-07 composite3 对线性 HDR 施加 Solas gamma 界（附带一处同缓冲读写的规范性争议）**
`program/water_composite.fsh:13`（读 colortex0）→ `:26`（写 colortex0，`RENDERTARGETS: 0` 在 `:11`）；`:23` 的 `clamp(color,0,1)`；`lib/solas_water.glsl:110` 的 `color*color + shafts` 把光束加在已含雾的结果之后。
为什么重要（主体）：`:23` 的 gamma 界在 `R11F_G11F_B10F` 线性流程里把所有 >1 的 radiance 截平，随后 `water_bloom` 与 tonemap 都拿不到被截的信息 —— 水下画面里亮部（阳光斑、光束、发光方块）的能量在 bloom 之前就被削掉，这是可复现的视觉后果。
次要（规范性，非缺陷）：本 pass 在同一绘制命令里读写 colortex0。GL 框架的 framebuffer feedback 条款把这种用法列为未定义行为，而 `docs/2026-09-13-astra-full-audit.md` §12.9 的缓冲契约矩阵对同一处给出的结论是"无同 pass 反馈；flip 由引擎按'写入才翻转'管理"。两说并存，我无法在读码层面裁定，因此**不把它算作缺陷、也不据它提级别**；需要实机确认（把 `:23` 的 clamp 去掉后看水下亮部是否回归，即可同时验证 F-07 主体与这条反馈是否真的无害）。
建议：见 §3.7 Step 5。

**F-08 叶片/草的透光项是变暗**
`global/lighting/diffuse.glsl:185-193`：`visibility *= mix(vec3(mix(0.30,0.62,t)), vec3(1.0), t)`，展开后乘子 = `0.30 + 1.02t - 0.32t²`，`t=0` 时 0.30 —— 没有背光时叶片被压到 30%，而 `SSS_STRENGTH` 越高（t→1）反而是 1.0。语义与"透光增益"相反，且与 `design.md` 的 SSS 描述不符。
建议：`visibility *= mix(vec3(1.0), 1.0 + gain, t)`，让 t 只加不减。

**F-09 高度雾表与实现不一致 + 晨雾方向反了**
`global/atmosphere/fog.glsl:58-70`（表 vs 代码）、`:71-80`（`fog_morning_air_weight` 的时间窗与日出相反）。
建议：以 `:58-70` 的表为准重写插值；晨雾权重改为随 `sunProgress` 上升段。

**F-10 colortex5/colortex6 整链无消费者**
`water_state.fsh:35` 是 `water_volume_state()` 唯一调用点，且它读的是自己上一帧；colortex5 只被 `water_state.fsh` 读。`shaders.properties:45-46` 声称"Water state also supplies terrain lighting/caustics"为假。
建议：要么接上（`shadowmap.glsl:217 shadow_water_depth()` 正是为这条链准备的，0 调用者），要么删掉一个 pass + 两个缓冲 + 三条 blend 指令。二者都行，别留着。

**F-11 水面距离 LOD 完全失效**
`global/water/surface.glsl:201,213,233,258` 四处 `float fade = 1.0;`。所有依赖 fade 的分段细节恒为最高档。
建议：接上 `smoothstep(32, 96, viewDistance)` 一类的真实曲线，或删掉这些分支（现在是纯死重）。

**F-27 末地强制暗角与抖动，用户关不掉**
`global/post/grading.glsl:157-160`：`apply_vignette` 的 `#if defined DIMENSION_END` 排在 `#elif defined VIGNETTE`（`:161`）之前并直接 `return displayColor*(1.0-0.08*falloff)`；`apply_output_dither` 的 `:181-185` 是同构写法，排在 `#elif defined DITHERING` 之前。后果：末地暗角强度固定 0.08（`VIGNETTE_STRENGTH`/`VIGNETTE_FALLOFF` 全部失效），抖动固定开启且不吃 `GRADING_DITHER_STRENGTH`。`shaders.properties:166-168` 三档 profile 都是 `!VIGNETTE`，`settings.glsl:193` 亦然 —— 即在末地"关闭"这个选项不是关闭，而是换成一个写死的值。
为什么重要：本包对 P1 的定义就是"控制项无效"，这是配置层最干净的一例。
建议：把 End 分支降为对选项结果的叠加（`apply_vignette` 先按选项算，再 `#ifdef DIMENSION_END` 追加最小暗角），而不是抢占 `#elif` 链。

### P2（继续前建议修）

**F-12 光束开启会把 colortex1 提到全分辨率，从而 4× 空气侧 godrays 成本**
`shaders.properties:8-13`。空气 godrays（`scattering.fsh:61`）与水下 march 共用一张缓冲，分辨率选项却由水下功能决定。
建议：拆成两张（godrays 0.5、shafts 1.0），或整体固定 0.5 并把 `:118` 的编码改为对低分辨率更鲁棒的归一。

**F-13 光束 resolve 忽略 rayLength、四 tap 等权**
`light_shafts.glsl:121-130`。与 `design.md:292` 相悖。
建议：见 §3.7 Step 4。

**F-14 发散控制流内的隐式 LOD 采样**
全包只有 4 处 `texture()` 落在循环体内（对 `Astra/shaders/**` 全部 245 个 `.glsl/.fsh/.vsh/.csh` 做花括号配平扫描得到），逐处核对控制流是否一致、所读缓冲是否开 mipmap：
1. **`global/water/bloom_capture.glsl:21` `texture(colortex0, sampleCoord)` —— 唯一真正危险的一处。** 它在 `:15` 的逐像素 `if (abs(bloomCoord.x - 0.5) < padding.x && abs(bloomCoord.y - 0.5) < padding.y)` 里套 6×6 循环，控制流按像素发散；而 `colortex0` 是全包**唯一显式开启 mipmap 生成的场景缓冲**（`program/water_bloom.fsh:5 const bool colortex0MipmapEnabled = true;`）。同一操作的另一个实现 `global/post/bloom.glsl:107` 写的是 `textureLod(src, coord, 0.0)` —— 包里对同一件事存在两种写法，走偏的那一份恰好压在唯一有 mip 链的缓冲上。
2. `program/final.fsh:57`（3×3 邻域取 `colortex1`，包在 `:52` 的 `if (isEyeInWater == 0 && godraysExposure > 0.0)` 里）、`program/end_sky_buffer.fsh:24`（`:21` 的 `if` + `:26`/`:28` 的数据依赖 `break`）、`global/water/light_shafts.glsl:110,125`（march 循环内，`:112` 有 `continue`）—— 同样非一致，但 `colortex1`/`depthtex0`/`shadowtex1`/`shadowcolor0` 均未开 mipmap，今天在画面上不可见。
为什么重要：GLSL 规定隐式 LOD 的偏导数只在**整个 2×2 quad 控制流一致**时才有定义。第 1 处驱动可以选到非 0 层级 ⇒ 跨厂商/跨驱动可能出现不一致的水下 bloom（而 `water_bloom.fsh:10` 的 `if (isEyeInWater != 1) discard;` 意味着这条路径只在潜水中跑，日常截图看不到）。第 2 类今天只是规范违规，但谁给那些缓冲加上 mipmap，谁就立刻复制同一个 bug。
建议：四处统一 `textureLod(..., 0.0)`，范式就在 `global/post/bloom.glsl:107`，不需要另立风格。
**引证订正**：本条原稿写的是 `deferred.fsh:36,45,51` + `end_sky_buffer.fsh:63`，两处都错 —— `deferred.fsh:36/45/51` 本来就是 `textureLod(depthtex0,...,0.0)`，`end_sky_buffer.fsh` 全文 34 行、`:63` 不存在。GLM 第二轮指出引证不成立是对的，我采纳并重推。但 GLM 据此降级的理由（"所涉目标均未开 mipmap"）不成立：`water_bloom.fsh:5` 就写在包里。重推后的站点保住 P2。判定全文见 §10。

**F-15 积水反射门控只有 1/4 真正生效**
`deferred.fsh:146-147`：`puddle_reflection()` 是函数实参，在 `if` 外无条件求值；`:140/:144/:145` 三个因子只乘进 `mix` 权重。`session-log.md:811` 的"96 步回到稀疏水坑"只对 `standingWater>0.15` 成立。
建议：把三个条件合入 `if` 再调用。这是全包最容易做、收益最直接的性能修复之一。

**F-16 门控的"第二重独立确认"不存在**
`global/atmosphere/weather.glsl:108` 让涟漪振幅成为 `puddle` 的单调函数，而 `rippled` 读的就是同一个 `puddle`；`lit.fsh:170-171`"干地也带微弱涟漪"反向为假。`deferred.fsh:131-133` 的论证随之失效。
建议：删掉这层伪独立性，或改用与 `puddle` 无关的掩码来源（`lit.fsh:47` 的 `rippleFootprint` 目前只流向 `astra_rain_ripple`，正好可以复用）。

**F-17 `rainy_air` 逐像素成本**
`deferred.fsh:81-93` 每个户外像素 10 次（云采样 + `shadow_coverage` + `shadow_opaque_visibility` PCF），雨天满屏。
建议：0.25 分辨率预计算到一张缓冲，或在 `astraRainFactor < 0.01` 时整段跳过（现在只靠 `rain` 乘权重）。

**F-18 colortex1 分配与 skytextured blend 不按维度收窄**
`shaders.properties:8-13`、`:74`：下界/末地中 `composite2` 恒关（`:57-58,62-63`），colortex1 从不被写，却仍按光束选项分配全分辨率。
建议：维度化 `size.buffer.colortex1`。

**F-19 `caustics.glsl` include guard 提前闭合**
`global/water/caustics.glsl:37` 的 `#endif` 关闭了 `:2` 的 guard，而文件到 119 行才结束 —— `:55-119` 未被保护。当前恰好没事（`lit.fsh:5-12` 两个分支互斥、`shadow.fsh:26`、`light_shafts.glsl:27` 各自单次），但任何后续二次 include 都会变成重定义错误。
建议：把 `#endif` 移到 `:119`。

**F-28 群系色调的"CPU 时间平滑"从未接进着色器**
`lib/uniforms.glsl:30-31` 声明 `biomeTemperatureSmooth` / `biomeHumiditySmooth`，`shaders.properties:293-294` 每帧用 `smooth(temperature, 30, 30)` / `smooth(rainfall, 30, 30)` 求值，**全包零消费者**（grep 仅命中这两处）。而 `global/atmosphere/fog.glsl:225-226` 的注释断言"Temperature/humidity are already temporally smoothed on the CPU (Z3), so the caller only has to hand over the resolved colour" —— 实际调用点 `program/scene.glsl:173-174` 传的是裸 `fogColor`（经 `srgb_decode(max(...))`）。
为什么重要：注释承诺的 30 tick 防跳变从未生效，跨群系边界仍可能整片跳色；同时白做两份 CPU 平滑。这又是一条"注释描述期望行为"的实例（§8）。
建议：要么把 `fog_biome_tint` 改成接收平滑后的标量并在包内重算雾色，要么删掉两个 uniform 与注释里的那句承诺。

**F-29 第三张涟漪 flipbook 上传并绑定，但从不采样**
`shaders.properties:323-326` 的注释说"layers 2 and 3 fade in as the downfall mask deepens"，`lib/uniforms.glsl:41` 声明 `astraRipple3`，`:326` 绑定纹理；但 `global/atmosphere/weather.glsl:113-115` 只合成 1、2 两层，且同文件 `:105` 自己写的是"the second sheet still only joins in heavy rain"。每张 128×7680（≈3.9 MB 未压缩），意味着一次纯亏的显存占用与上传。
建议：接上第三层（按 `strength` 的更高阈值），或删掉 uniform/绑定/纹理三处并改注释。

**F-30 "raw defaults = BALANCED" 的基线声明不成立**
`shaders.properties:163-164` 注释称"raw defaults above = BALANCED (the 4050 baseline default profile)"，但 `SSS_STRENGTH` 默认 `100`（`lib/settings.glsl:76`）而三档 profile 全是 `60`（`shaders.properties:166-168`）。
为什么重要：这条注释正是 §7.0 基准测试要用的锚点 —— 若按它直接用默认配置测"BALANCED 基线"，得到的是 SSS 高 67% 的配置，数字不可比。
建议：把默认值对齐 profile，或在注释里列出全部偏离项；更稳的做法是加一条 `check_pack` 规则：逐选项比对 settings.glsl 默认值与 `profile.BALANCED` 的显式赋值。

**F-31 `entityShadowDistanceMul` 表依赖两条未证实的 Iris 语义**（本次唯一未闭环的技术前提之一）
`lib/settings.glsl:210-211` 断言"`const = MACRO` 由 Iris 在加载期解析"，`:224` 断言"Iris 用 `shadowDistance * shadowDistanceRenderMul * 本比值`"。40 支比值我逐条手算均等于 `ESD/(SD×1.5)`，**算术全对**；但若 Iris 的实体距离不含 `renderMul`，实体阴影距离会缩为设定值的 2/3。本会话无实机工件可佐证（`qa/iris-properties-resolved.txt` 未在本次只读范围内确认存在内容）。
建议：实机一次性确认（站定 128 格边缘看实体阴影是否在设定边界出现），把结论写进 `settings.glsl:224` 的注释替代现在的推断语气。

### P3（记录后续处理）

- **F-20** `lib/settings.glsl:23` `SUN_MOON_DISCS` 全包零引用（脚本交叉核对：82 个 `#define` 中唯一无消费者的选项型宏），也不在任何 screen 上 → 死选项。
- **F-21** `program/lit.fsh:371` 的 `surfaceWet` 写入 `.a` 后立刻被 `:374` 覆写 = 死写；`weather.glsl:56-60` 声称的 "gloss change" 无消费者。
- **F-22** 下界天空算两遍：`sky.fsh:142` + `deferred.fsh:165`。
- **F-23** `world-1/shadow.vsh:1` 用 `#version 430`，root/`world1` 用 400（同一 program 三个版本）。
- **F-24** `shaders.properties:166-168` 三个 profile 全部 `SUN_MOON_MODE=0`、`WATER_CHARACTER=1`，与 §4.2 的"默认即绿色极限"叠加，使可见问题被固化到默认配置里。
- **F-32** 死 CPU uniform `sunrise` / `moonrise`：`shaders.properties:217`、`:219` 每帧跑 `pow`/`abs` 链，`lib/uniforms.glsl:21`、`:23` 声明，全包仅在注释里出现（`global/dimension/overworld.glsl:6` 甚至把 `sunrise` 列为本文件使用的 uniform），实际着色器侧已改用 `astraTwilightFactor` / `lib/twilight.glsl:8`。
- **F-33** `lib/noise.glsl` 整文件死链：`noise` / `noise_water` / `fbm_fast` 在文件外零调用（grep 交叉确认），却仍被 `global/atmosphere/weather.glsl:3` 与 `global/dimension/nether.glsl:9` include。相关三处描述互不相同：`lib/uniforms.glsl:44` 写 "`texture.noisetex`, 256x256"、`lib/settings.glsl:221` 写 "matches textures/noise.png"，而 `shaders.properties` 中没有任何 `texture.noisetex` / `customTexture.noisetex` 指令 —— 也就是说 `shaders/textures/noise.png` 是随包发布但从未被绑定使用的文件，`noisetex` 走的是引擎内建别名。不是编译失败点（该采样器目前不被任何活跃代码路径采样），但三处描述都在指向一个不存在的绑定关系。
- **F-34** 晨昏包络注释偏小：`shaders.properties:213` 写 "~ ±4 degrees"，按 `:214-215` 手算实为 **−9° .. +14°**（`astraTwilightRise` 在 y=−0.156→−0.070 即 −8.97°→−4.01° 升满，`astraTwilightFade` 在 y=0.070→0.242 即 +4.01°→+14.0° 归零），±4° 只是"升满"与"开始下降"两个拐点。GLSL 侧注释反而精确。
- **F-35** `lib/colors.glsl:45-47`："default 5 = 0.05" 与实现不符（默认 `MIN_AMBIENT=8`、`:49` 乘 `0.001` → 0.008），"exactly at MIN_AMBIENT = 5" 在默认值下是所引 Steadfast 值的 1.6 倍。
- **F-36** `lib/pow.glsl:47` 注释 "9 multiplies in total" 与代码不符：`pow100` 的写法要 15 次乘（`pow32` 未共享中间量），只有编译器 CSE 后才接近 9。同时 `:31` 声明的规则未在树内执行。**计数更正（交叉核验后）**：原报告写"残留 6 处"是漏计。用"剥注释 + 括号配平 + 第二参数为整数值字面量（含 `vec3(n)`）且 n≥2"的扫描器重跑 `Astra/shaders/**`，实为 **38 处 / 16 个文件**：`lib/twilight.glsl` 7、`global/atmosphere/fog.glsl` 4、`global/dimension/end_system.glsl` 4、`global/dimension/nether_volume.glsl` 4、`global/dimension/nether.glsl` 3、`program/lit.fsh` 3、其余 9 个文件各 1–2（`light_shafts.glsl` 2、`solas_water.glsl` 2、`deferred.fsh` 2、`weather.glsl`/`end.glsl`/`end_geometry.glsl`/`overworld.glsl`/`bloom_resolve.glsl`/`shadow.fsh`/`water.glsl` 各 1）。指数直方图（指数×出现次数）：2×10、3×6、4×5、5×5、8×4、16×1、20×1、24×2、32×2、180×1、1400×1。原报告点到的 6 处（`fog.glsl:127,210`、`end_system.glsl:28,29`、`bloom_resolve.glsl:9`）全部为真，只是不完整；GLM 报告的"23 处"同样是漏计——正则类扫描会漏掉跨行写法的 `pow(\n x,\n 3.0)`。迁移可行性注意两点：180/1400 两个指数（`twilight.glsl:50,51`）超出 `pow.glsl` 现有链范围，需先补助手；`shadow.fsh:65` 的 `pow(albedo.a, 32.0)` 在阴影 pass 每个 caster 像素上执行，属高优先级。**扫描方法本身也踩了一次坑，记下来免得下次复算再掉进去**：先剥 `/* */` 再剥 `//`，会把行注释里的字样（`shadow.fsh:16` 写的 `program/* is the only lib entry`）当成块注释起点，吞掉后面半个文件，第一次跑因此少计 1 处（38→37）。正确顺序：先剥 `//`（保留换行以维持行号准确），再在剩余文本里标 `/* */` 区间。该文件目前仍未跟踪（`git status` 里的 `?? lib/pow.glsl`）。
- **F-37** `Astra/THIRD-PARTY.md` 台账漂移：缺 `lib/pow.glsl` 行；`:40` 仍把 N1 写法记为 `ENTITY_SHADOW_DISTANCE * (1.0 / SHADOW_DISTANCE)`（已被 `settings.glsl:227-323` 的字面量表取代）；`:86` 把 `astraRainFactor` 记为 `smooth(71, rainStrength, 3, 3)`，实际 `shaders.properties:307` 是 `..., 3, 0.8)`；条数与表头也不一致。注意 `qa/tools/check_pack.py:603-680` 的台账规则只匹配 `// From ` 前缀，因此没有该行的文件（如 pow.glsl）天然逃过校验 —— 这是工具盲区，不是巧合。
- **F-38（交叉核验后撤销，不计入统计）** `lib/water_buffer_formats.glsl:6-11` 我原记为"`#ifndef R11F_G11F_B10F / RGBA16` 空守卫永真，`= 0` 分支从不参与求值"。复算结果与结论相反：`grep -rn "define R11F_G11F_B10F"` / `"define RGBA16\b"` 全包 0 命中 ⇒ 守卫**恒成立**，`:7`/`:10` 的 `const int … = 0;` 恰恰是必执行分支。而这正是 `:3-5` 注释写明的用意 —— Iris 按**标识符文本**读 `const int colortex0Format = R11F_G11F_B10F;` 的格式名，GLSL 端却要求该标识符有声明，`0` 这个数值永不参与语义。`program/end_sky_buffer.fsh:6-9` 对 `RGBA16F` 用的是同一套写法，说明这是包内一致的约定而不是漏写。原描述里"永真"为真、"从不参与求值"为假，两句自相矛盾 ⇒ **整条撤回**，P3 由 16 减为 15。判定全文见 §10。
- **F-39** `lib/encoding.glsl:19-21` 的 `srgb_decode` 未钳负底数（`pow((c+0.055)/1.055, 2.4)`），而同文件 `:16` 的 `srgb_encode` 有 `max(c, vec3(0.0))`。当前不构成可见缺陷：`mix` 会同时求值两侧但负底数分支的结果被丢弃，且唯一调用点 `program/scene.glsl:174` 自带 `max(fogColor, vec3(0.0))`。风险在于这依赖"调用方自觉钳位"，任何新调用点漏写就走到驱动相关的 UB。建议函数内钳，删调用点的外层 `max`。

### 交叉核验后新增（F-40 … F-54）

这 15 条不在我第一轮清单里，来自两份外部报告**与我自己在复核过程中补算的算术**（F-40、F-51、F-53 全部来自后者；F-41、F-47 各有一半来自后者），全部经我逐条读源码确认后收录（判定与出处映射见 §10）。分档与 §1 的 **14 / 22 / 15** 一致：本小节新增 P1 2 条、P2 10 条、P3 3 条；P3 的 15 是原集合里的 F-38 在交叉核验中被我撤回后的数字。

#### P1

- **F-40 空气侧深水回退恒为 0（§4.3 的算术延伸）** ｜`program/water.glsl:293-297` → `program/scene.glsl:105-107` → `global/water/surface.glsl:37-38`
  空气侧光线没有命中几何时走两条回退：`astra_water_air_sky(transmittedWorld)` 的入射项最终经 `water_surface_medium(0, …)`，而 `absorption.glsl:58-62` 是纯 `exp(-d·c)` 乘法，`d=0` ⇒ `vec3(0)`；另一条 `astra_water_segment(vec3(0), …)` 的第一步就是 `surface.glsl:37-38` 的 `anchorDepth >= 0.999999 → return 0.0`。**两条都是恒零**。
  为什么重要：这是"深水与远处水面"唯一的着色路径。§4.4 的系数改法只修好了命中几何的分支，远处水面与地平线交界仍会按这条零值路径出图 —— 换句话说，只按 §4 改 `absorption.glsl` 不会让"青绿→深蓝"走完。
  建议：空气侧回退不该 march、也不该走 segment，应直接 `astra_sky_radiance(transmittedWorld)` × 一次沿射线的解析吸收（与 `water_surface_medium` 同一系数，长度取 `min(96, 到水下几何时)`），并显式加一条内散射项（§4.4 的 `water_body_tint`）。
  来源：本次补算（两份外部报告都停在"回退链存在"，没有定位到恒零）。

- **F-41 `Astra/README.md` 与出厂配置互相矛盾，且含无出处数值** ｜逐行判定见下表
  我独立枚举（不采信外部报告的"七处"计数），复核结论：

  | README | 声称 | 实测 | 证据 |
  |---|---|---|---|
  | `:5` 效果三对标 | 水下 ≈ Steadfast、水面 ≈ Solas | 方向已被 SC-24 更正为**水面 ≈ Steadfast、水下 ≈ Solas** | `design.md` §0 |
  | `:20` | 零 compute | **下界有 9 个已注册 compute 阶段**（`world-1/shadowcomp[A-H].csh`，共享 `program/nether_light.csh` 65 行本体），BALANCED/ULTRA 开启 | `shaders.properties:339-347`、`settings.glsl:165` |
  | `:22` | 大气 = Minishita | 默认与三档 profile 全部 `SKY_MODE=1` = **SKY_GRADIENT**，Minishita 是需手动切换的备选 | `settings.glsl:20-21,80`、`overworld.glsl:11-15`、`properties:166-168` |
  | `:24` | 出厂分级 饱和 112 / 自然饱和 115 / 对比 104 | 实际 **100 / 100 / 102**，且 `grading.glsl` 内不存在 112/115 任何字面量 | `settings.glsl:177,179,181`、三档 profile 同值 |
  | `:31` 流畅 | 阴影 1024/**96 格** | `SHADOW_DISTANCE=192`、`ENTITY_SHADOW_DISTANCE=48` | `properties:166` |
  | `:32` 均衡 | "其余全开" | 该档 `!UNDERWATER_PARTICLES`、`!VOXY_SUPPORT`、`!GODRAYS`、`!VIGNETTE`；且"默认"与 F-30 冲突 | `properties:167` |
  | `:33` 极致 | **192 格** / **16 texel** 软化、"平面云"（暗示均衡不是） | `SHADOW_DISTANCE=256`、`SHADOW_SOFTNESS=8`；`CLOUD_MODE=1`（平面云）**均衡档同为 1** | `properties:167-168` |
  | `:39` | 33 模块仅 8 可达、lit/final 未接线（E1 未冻结） | 与同文件 `:58`"lit/final 已接线"自相矛盾 | `README.md:39` vs `:58` |
  | `:40` | `surface.glsl` / `raytrace.glsl` 无人认领 | 两者已被 `program/water.glsl:12`、`:13` include 并接线 | 源码 |

  另经我核对为**真**、不该被算作错误的两条：`:12` 的"七分类"（`properties` 里 `^screen.` 恰 7 条）、`lang/` 下 `zh_CN.lang` 与 `en_US.lang` 均存在。
  为什么重要：README 是唯一面向用户的发布物。除了"构建是否健康"这一条可以留给工具兜底，其余每一行都是包在对外的承诺；承诺与出厂配置不符，用户按 README 验收就会判错 —— `:24` 是验收口径，`:5` 是色调裁决的靶子，这两行风险最高。

  **修复后复测（工单 F4 执行后，我重新读了一遍 README 与 `properties`）**：9 行里 **6 行已改对** —— `:5` 三对标方向已按 SC-24 更正（水面 ≈ Steadfast、水下 ≈ Solas）、`:20` 已写"9 个 compute 阶段 + 3 张自定义图像"、`:24` 已改为实值 100/100/102、`:31` 流畅档已写 192 格（实体 48）、`:33` 极致档已写 256 格 / 8 texel 并补注"均衡档同为平面云"、`:39` 状态段已重写成"182 个编译入口、52/54 模块可达 + lit/final 已接线"。**仍有 3 行失实**：

  | 仍失实的行 | 现文本 | 实测 | 证据 |
  |---|---|---|---|
  | `:22` | "大气：Minishita 迷你物理大气（≈200 FLOPs）" | 默认与三档 profile 全是 `SKY_MODE=1` = SKY_GRADIENT，Minishita 仍需手动切 | `settings.glsl:81`、`properties:171-173` |
  | `:32` | 均衡档"godrays 关，其余全开" | 均衡档另有 `!UNDERWATER_PARTICLES`、`!VOXY_SUPPORT`、`!VIGNETTE` | `properties:172` |
  | `:40` | "`surface.glsl` 与 `raytrace.glsl` 无人认领" | 两者已被 `program/water.glsl:12`、`:13` include 并接线出图 | 源码 |

  另记一条：`:39` 新写入的"52/54 模块可达"里的 **54 与我自己的静态复算对不上**（我复算 53，见 §10.5 的口径仲裁表），这个数字现在被 README 当作对外口径，需要用 `check_pack.py` 实际跑一遍确认，不要停在"抄报告"。
  建议：整节重写"特性 / 三档 Profile / 已知问题 / 开发状态"四节，并把每条数值改成从 `properties` 抄来的实值（可让 `check_pack.py` 加一条 README↔profile 交叉断言，见 §7.2#3）。
  来源：hunyuan A2 提出（其计数为 7 处 + 1 次要），本表为我逐条独立复算的结果，条目集合与出处均与其不完全相同。

#### P2

- **F-42 colortex3 的清屏 alpha=1.0 打开积水门控，水面与全部半透明像素各付一次 96 步射线步进、结果被丢弃** ｜`lib/settings.glsl:357` + `program/deferred.fsh:106/111/136/146` + `program/lit.fsh:22-28`
  完整证据链（每步都可直接读源码确认）：
  1. `settings.glsl:357` `const vec4 colortex3ClearColor = vec4(0.498, 0.0, 0.0, 1.0);` —— colortex3.a 在 `deferred.fsh:112-114` 的注释里就是"the sparse standing-water mask"，而**这张掩码的清屏值是它量程的最大值 1.0**。
  2. `lit.fsh:22-28` 的 `#ifdef` 分配写者：水面 pass 写 `0,5`、半透明 pass 只写 `0`，**只有其余（地形/方块/实体/手）写 `0,3`**。所以水面像素与所有 `ASTRA_TRANSLUCENT` 像素（weather 雨丝、particles、glass、beaconbeam、entities_translucent）在 colortex3 上保持清屏值。
  3. `deferred.fsh:136` 的门是三个条件：`standingWater > 0.15 && isEyeInWater == 0 && (lightData & 128u) == 0u`。`:135` 是 `clamp(surface.a,0,1)` ⇒ 这些像素 **1.0 > 0.15 成立**。外层 `:111` 只有维度判断（`!NETHER && !END`），**没有任何选项开关**；`:106` 的 `depth < 0.999999` 只挡住纯天空。`isEyeInWater == 0` 挡掉了水下视角，`(lightData & 128u)` 也挡不住：这些像素的 `colortex3.r` 同样是清屏值 0.498 → `round(0.498·255)=127` → 高位为 0。⇒ **空气侧看水时的水面像素，加上户外全部半透明像素，三门全过。**
  4. `:137` `n = decode_unit_vector(surface.gb*2.0-1.0) = decode_unit_vector((-1,-1)) = (0,0,-1)` ⇒ `n.y = 0` ⇒ `:140` `upFacing = smoothstep(0.55,0.92,0.0) = 0` ⇒ `:147` 的 mix 权重恒 0，**视觉结果确实正确**。
  5. 但 `:146` 是 `mix(source, puddle_reflection(playerPos,n), 0.0)` —— GLSL 先求值实参，`puddle_reflection()`（`:14` 的 `astra_reflection_sky` + `:32` 的最多 96 次 `depthtex0` 取样 + `:41-48` 的 6 步细化）整条**已经跑完**。循环有两个与几何相关的早退点（`:24` 的 `reach <= 0.05 || start.z >= -0.06`、`:27` 的 `pixels < 1.0`、`:34` 的出屏 break），**它们在水面像素上是否真的触发无法靠读码断定**，只能实测；能静态确定的是：`:14` 的 `astra_reflection_sky` 在任何路径下都执行（它本身是一次天顶积分 + `:20` 的 `smoothstep`），而分支进入与否完全由那个 1.0 的清屏 alpha 决定。
  6. **这不是"没人想到"，是"想到了、修法无效"**。`lit.fsh:344-349` 的注释逐字列出计划：`the water pass: 0 (its own branch of gl_FragData[1] below)`、`translucents and weather: 0, via the else-branch below`。两条都不成立：`gbuffers_water.fsh:3-4` **同时**定义 `ASTRA_TRANSLUCENT` 与 `ASTRA_WATER_PASS`，于是水面 pass 走 `RENDERTARGETS: 0,5` —— `:362` 的 `gl_FragData[1].a = …` 落在 **colortex5** 而不是 colortex3；而 `:364` 的 `#ifndef ASTRA_TRANSLUCENT` 块又因为水面无条件定义了 `ASTRA_TRANSLUCENT` 而被整块跳过。七个纯半透明程序（`gbuffers_weather`、`_particles_translucent`、`_entities_translucent`、`_block_translucent`、`_beaconbeam`、`_clouds`、`_hand_water`，各自 `:3` 只定义 `ASTRA_TRANSLUCENT`）只声明一个目标，`gl_FragData[1]` 根本不绑定任何缓冲。**"把非地形的掩码归零"这一意图 100% 落空。** 成因与 F-01 完全同一个机制：Iris 按 `RENDERTARGETS` 列表重映射 `gl_FragData[i]` 的下标，写者以为自己在写第三张缓冲。其中"水面 pass 的 `:362` 写到 colortex5"这条**就是 F-01 本身**，不重复计项；本条只补 F-01 没写的两点：水面块整体被 `:364` 的 `#ifndef ASTRA_TRANSLUCENT` 跳过（因为 `ASTRA_TRANSLUCENT` 与 `ASTRA_WATER_PASS` 同时定义），以及七个纯半透明程序在 `RENDERTARGETS: 0` 下**根本没有第二个输出**，注释里"translucents and weather: 0, via the else-branch below"指的那条分支对它们不存在。
  7. 同一段里两处注释与代码直接相反：`deferred.fsh:128` "whose alpha no consumer reads"、`lit.fsh:341` "Nothing reads colortex3.a"，而**同一函数体的 `:135` 就是那个读者**、也是全包唯一读者。F-42 的门之所以开着，恰恰因为有人读了它 —— 两句断言若成立，这个缺陷反而不会存在。
  为什么重要：这是本次核验中**量级最大的一项确定性浪费**，且不依赖天气、不依赖选项：空气侧看水时，每个水面像素与每个户外半透明像素（雨丝、云、粒子、半透明实体、信标、玻璃）都在做一次注定被丢弃的屏幕空间反射 —— `astra_reflection_sky` 部分无条件执行，march 部分的迭代次数待实测。水下视角被 `isEyeInWater == 0` 排除在外，所以这一条与 §3 的水下光束问题是两回事。README:32 承诺的"均衡 ≥90 FPS @1080p"正是在这条路径上测的。更深一层的代价是**证据可信度**：SC-39 那一轮三次返工全在调门控的语义（读错了掩码），最后一次改的是"掩码搬到哪张缓冲"，没有一次检查门控的默认值，也没有一次核对"归零写到底写进了哪张缓冲"，而新加的注释还把不成立的结论又写成了前提。
  建议：三选一，代价从低到高——① `colortex3ClearColor.a` 改 `0.0`（掩码的"无覆盖"本就该是 0，`.r` 的 127 标记不动）；② 把 `:140` 的 `upFacing` 提到 `:136` 的门控里（先解法线再决定要不要 march）；③ 两者都做，并给"清屏值必须等于该通道语义的零值"加一条 `check_pack` 规则（§7.2#3）。注意 ① 需要先确认没有其他读取点把 colortex3.a==0 当成"未知"以外的含义 —— 目前全包唯一读者是 `:135`。无论选哪个，第 6、7 三步都要一起处理：`lit.fsh:344-349` 的"三条写入路径"清单必须按 `RENDERTARGETS` 实际重映射改写（水面 pass 的 `.a` 落在 colortex5，纯半透明 pass 无第二目标），`deferred.fsh:128` 与 `lit.fsh:341` 的"无读者"断言要删 —— 否则下一轮审查仍会按这两句话把门控判成安全的。
  来源：GLM F2 指出该门控不防天空清屏 alpha，方向正确；**影响面我做了扩大与重算**：不止雨天，而是空气侧的全部水面 + 全部户外半透明像素（GLM 原判为 Important，我按"无视觉缺陷、纯性能"定为 P2，同时把它排在 §7.1 首位）。第 6、7 两步（归零写实际落到 colortex5、两处"无读者"注释与 `:135` 相反）是本阶段新查出的，GLM 与 hunyuan 都停在"门控会进"这一层，没有追到写者侧。

- **F-43 `lit.fsh:231` 在非一致控制流内取屏幕导数** ｜`lit.fsh:189` `if (material == 11u)` → `:231` `length(dFdx(texcoord))`
  `material` 是 flat varying，同一 quad 内末地石与相邻方块可以不同，分支内 `dFdx/dFdy` 按规范未定义。后果是末地石边界 quad 上 `footprint` 跳变 → `gloss` 突变（`:232`），且本包无 TAA，边界噪声会一直留在画面上。
  为什么重要：项目已经用同一手法修好过两处同类缺陷（`deferred.fsh:101`、`lit.fsh:44-48`），这是漏网的第三处 —— 说明缺的是规则而不是能力。
  建议：沿用 `lit.fsh:44-48` 的既有做法，把 footprint 提到 `if` 之外、alpha 丢弃之后计算。
  来源：GLM F3 / hunyuan A4（两份都独立给出，判级 P2 与我一致）。

- **F-44 假 `visibility = 1.0` 让夜间背光面吃到最大失色** ｜`global/lighting/diffuse.glsl:341-346`（背光面跳过阴影采样并置 `visibility=1.0`）→ `:232-242`、`:376-379`、`:450-451`
  夜间失色把 `visibility` 当作"被遮挡程度"使用，而背光面被人为设成 1.0 —— 于是**背对太阳的面拿到满额夜色去饱和**，正对太阳的面反而更少。语义上正好反了。
  为什么重要：夜间观感的整体偏灰来自这一条，不是来自 `MOONLIGHT_STRENGTH`；用户因此调高月光强度会同时把该问题放大。
  建议：跳过采样时置 `visibility` 为该分支的**中性值**（不参与失色），或把失色改成读 `sunGate`/`facingAway` 而不是读 `visibility`。
  来源：GLM F4（其判级 Minor，我升为 P2：它改变的是夜间主光语义，不是风格）。

- **F-45 水下时四档 tonemap 整体失效且无用户提示** ｜`program/final.fsh:88-91`
  `:88` 无条件算完 `apply_exposure → apply_tonemap → srgb_encode`，`:90` 在水下用 `solas_water_display(apply_exposure(hdr))` **整体覆盖** —— 既白算一次全屏 tonemap（1080p ≈ 207 万像素/帧，两份外部报告都点名，我也复算通过），又使 `TONEMAP_OPERATOR` 四档与 `EXPOSURE` 曲线在水下悄悄不生效。
  为什么重要：这是"假旋钮 + 确定性浪费"叠加。用户在水下切色调算子没有任何反馈。
  建议：改二选一结构（分支本来互斥，行为不变，纯消除冗余）；若要保留水下的独立显示曲线，也应在其上调 `TONEMAP_OPERATOR`，并在 `lang` 里写明水下走独立曲线。
  来源：GLM F7 / hunyuan A1（hunyuan 判 P1；我按本项目分级口径把"无数据丢失、无逻辑错误、纯浪费+可用性瑕疵"定为 P2，见 §10）。

- **F-46 水下光束与 `WATER_CAUSTICS` 隐性耦合** ｜`global/water/light_shafts.glsl:101`
  光束的每个样本乘 `astra_water_caustics_shaft_at()`，而该函数受 `WATER_CAUSTICS` 守卫。关掉焦散 ⇒ 光束一并变黑，UI 上两者是两个互不相干的选项。
  为什么重要：这既是一条隐藏依赖（关掉 A 会让 B 消失，用户无法定位原因），也是 §7.1#1 那个 504 取样/像素的来源 —— 同一个调用点承担两件事。
  建议：把光束的焦散调制改为独立开关（或低频复用场），关焦散时该乘子退化为 1.0 而不是 0。
  来源：GLM §8.2 提出（R-D 项），我按 `caustics.glsl` 的守卫确认。

- **F-47 蓝图主路径天空实际走备选档；Minishita 编译进闭包但默认不可达** ｜`properties:166-168` `SKY_MODE=1` + `overworld.glsl:11-15` + `scene.glsl:31`
  `design.md:249` 把 Minishita 定为天空（"≈200 FLOPs；备选简单渐变模式"），出厂默认与三档 profile 全部选了备选。同时 `sky_minishita.glsl` 被无条件 `#include`，即默认配置下每个入口都编译一份不可达的物理大气代码。
  为什么重要：一是 README:22 与 `:5` 的卖点建立在一个用户看不到的模式上（F-41）；二是反向风险 —— 一旦有人按蓝图把默认改回 `SKY_MODE=0`，`scene.glsl:160` 的 `astra_sky_radiance(direction)` 会对**每个雾化的户外像素**跑完整 2 视采样 + 1 光采样积分，当前没有任何缓存/LUT。
  建议：二选一并写进 `design.md`：要么正式承认渐变是出厂天空、把 Minishita 标为实验档；要么默认切回 Minishita 并**同时**补一张低分辨率天穹 LUT（§7.1 新增行）。现状"蓝图说 A、出厂用 B、代码两份都带"是三份报告一致认定的偏离。
  来源：hunyuan §5 一致性表 + 我自己对 `sky_minishita.glsl` 可达性与 `scene.glsl:155-160` 门控的复算。

- **F-48 composite2/3/4 的空转代价被低估：全分辨率 + 强制 mipmap** ｜`water_bloom.fsh:1-11`、`properties` 无 `size.buffer.colortex7`
  三点复算确认：(1) `water_bloom.fsh:11` 的 `if (isEyeInWater != 1) discard;` —— 空气侧该 pass 逐像素 discard，仍然是全屏调度；(2) 它写 `colortex7` 而 `shaders.properties` **从未声明 colortex7 尺寸** ⇒ 按全分辨率 RGBA16 分配（1080p ≈ 每帧 62 MB 带宽级别的写侧）；(3) `water_bloom.fsh:1` 的 `colortex0MipmapEnabled = true` 会迫使 colortex0 每帧重建完整 mip 链，只为了该 pass 的一次采样。
  为什么重要：这三项都是"空气侧也在付钱"的固定成本，而空气侧正是 README 承诺 ≥90 FPS 的场景。
  建议：`size.buffer.colortex7=0.25 0.25`；把 mipmap 需求改到已经 0.25 的 `colortex2` 上（或显式 `allocStage`），空气侧用 `program.*.enabled` 条件化整条 pass（与 F-18 的 colortex1 维度化一起做）。
  来源：hunyuan §12（其"单 pass 性能黑洞"表述含 144 抽头一项，我对其抽头数做了更正，见 §10）。

- **F-49 末地黑洞每像素构造 73 槽数组并动态索引** ｜`end_geometry.glsl:17` `const int END_BODY_COUNT = 73;` → `end_blackhole.glsl:79-81`、`:175`
  每像素声明 `vec4 bodies[73]` + `int bodyIndices[73]`（73×4 + 73 = 365 个标量），`:81` 与 `:175` 各做一次全量填充，`end_scene_segment` 按值接收（再复制一份），`:141` 一带用 `bodyIndices[j]` 动态索引 `bodies[...]`。
  为什么重要：动态索引的函数级数组通常落本地内存/寄存器溢出，末地天空是全屏像素都走的路径；`git log` 显示 7e3f51c 之前该文件曾因 512 次几何扫描把 GPU 挂死，说明这条路径的历史成本被低估过。
  建议：把候选集从"每像素重建"改为一次性、只读的 `const` 全局表或 `shared`/UBO；`:175` 那次重排如果只是恢复顺序，应删除。
  来源：hunyuan §12.x 提出，我逐行确认数组声明位置与填充次数。

- **F-50 冻结条款被突破但未登记例外（varying 预算 / 天空主路径）** ｜`.specs/astra-shader/design.md:199-209`、`:249`
  `:199-209` 明文冻结 lit 的 varying 预算（地形 9 / 其他 4，且"无位置、无切线、无 shadowPos"）。当前 `program/lit.vsh:12-24` 已声明 `waterTangent`、`waterBinormal`、`waterViewVector`、`waterViewDistance`、`cameraRelativePosition`、`surfaceShadowPosition`、`faceData`、`lightcoord`、`texcoord`、`tint`（按 pass 组合最高约 15 个），且 `at_tangent` 与位置类 varying 都在其中。
  为什么重要：冻结条款的意义在于它是"改之前要过闸门"的地方。现在改动已经发生、没有例外登记（F-37 的台账漂移是同一现象），下一轮审查无法区分"经批准的演进"与"越界"。
  建议：把这两项写进 `design.md` §12 的决议流水（SC-4x：lit varying 预算重定为 9/15/25 的按 pass 上限），或者收缩实现。**不建议**只做重命名而不改文档。
  来源：GLM §1 架构 + 我按 `lit.vsh:1-24` 与 `design.md:199-209` 的逐条对表。

- **F-51 `global → global` include 8 处，与 §3.2 决议冲突且校验器不覆盖** ｜`clouds_planar.glsl:48`、`stars.glsl:29`、`end.glsl:3`、`end_blackhole.glsl:20`、`end_ring.glsl:3`、`end_system.glsl:5`、`nether.glsl:13`、`light_shafts.glsl:27`
  `design.md:209` 写"global 不 include 其他 global"。8 处全部实测存在，`end_*` 已形成 `end → end_blackhole → end_system → end_ring → end_geometry` 单向链（无环，我复核过 include 图）。`check_pack.py` 的层规则只查 lib/program 方向，所以恒 PASS。
  为什么重要：这是**校验器盲区**，不是"8 处违规"本身 —— 只要规则不加，下一轮还会新增。
  建议：二选一（承认大气/末地两个子分层并更新决议，或把 `end_*` 收进 `global/dimension/end/`），同时给 `check_pack.py` 加一条 global 内部边规则。我原先在 §2 写的"无反向 include"结论过强，已就地拆分修正。
  来源：GLM 与 hunyuan A6 均给出同一份 8 处清单（与我枚举一致）。

#### P3

- **F-52 死参数与永真分支（三处，一次提交可清完）** ｜`scattering.fsh` 的 `dither2` 未被使用；`end_sky(voidTint, time)` 形参在函数体内无消费；`fog.glsl` 内层 `#ifndef ReflectedFog` 恒真（全包无该宏定义点）。
  建议：删形参/删守卫，或补上真正的使用点。**不要**用 `_unused` 之类改名保留（项目分级口径里那属反模式）。来源：GLM F6，我逐条 grep 确认。

- **F-53 枚举 token 半数零引用，比较处直接写字面量** ｜`settings.glsl:20,23,28,30,31` 的 `SKY_MINISHITA`、`SUN_MOON_DISCS`、`WATER_BALANCED`、`SHADOW_FILTER_SOFTWARE` 等定义后全包零引用；同时 `light_shafts.glsl:92` 等 **7 处**判断写成 `#if SHADOW_FILTER_MODE == 1` 字面量而非 `SHADOW_FILTER_HARDWARE`。
  为什么重要：命名常量与字面量混用正是 F-20（`SUN_MOON_DISCS` 死选项）能长期存活的原因 —— 读代码的人无法从 token 判断哪条分支在用。
  建议：把 7 处字面量比较换成已定义的 token，并给"定义了但零引用"的 token 加一条 `check_pack` 规则。来源：hunyuan A8（其计数 5 个与我一致），字面量比较的 7 处由我另算。

- **F-54 文档与实跑记录漂移** ｜`docs/` 缺 09-16 / 09-17 两轮归档（源码最后修改 09-17 00:58，最新文档 09-16）；`design.md:474-487`（§12）状态停在 09-07；`docs/` 平铺 53 份未分目录。
  为什么重要：SC-39 那轮"三次返工 + 一条编造的断言"目前只存在于未入库日志里，下一个人拿不到教训。
  建议：补 `docs/2026-09-17-sc39-puddle-reflection.md` 并回填 `design.md` §12；`docs/` 按 `rounds/ reviews/ research/` 分目录（09-13 报告已建议两次）。来源：hunyuan A5/A10/A12。

---

## 6. 蓝图一致性核对

| 蓝图条款 | 位置 | 实现状态 | 证据 |
|---|---|---|---|
| 空气侧=青、蓝只给水下相机 | `design.md:79` | **一致，但正是该条款遗漏了用户需求** | `absorption.glsl:16-31`、`:55-57` |
| 水面高度 UNORM16 `0.5 - worldY/2048` | `design.md:92` | **已被实现取代，文档未更新** | `shadowmap.glsl:28-35` 改成 R8 ±64 方块窗口 |
| SC-33 光束：16/24/32 步、48 方块、`shadowcolor0.R` 验证、距离加权重建 | `design.md:292` | **四项全不符** | `:67`（4–10 步）、`:66`（40 方块）、`:105`（只读 .gba）、`:121-130`（rayLength 未用） |
| 吸收按方块、无 32 方块平台、无二次雾 | `design.md:269` / SC-34 | 一致 | `absorption.glsl:6-8,42-51` |
| deferred 启用条件 | `design.md:90` | **蓝图内部两条款互斥，实现与后者一致** | `:90` 要求"开启条件为 `SCREENSPACE_REFLECTIONS \|\| SCREENSPACE_REFRACTION \|\| WATER_ABSORPTION > 0`"，而 `:493`（SC-34-F1，2026-09-07）明文废止它："旧'由三个水效果开关决定副本'的文字不再描述实际行为……`ASTRA_SCENE_COPY` 与三维度 deferred 已在接手时常开"。实现按 `:493`（`shaders.properties:68-70` 无条件启用）。**我原记为"不符"是错的** —— 不符的是文档自己，不是代码。判定见 §10 |
| colortex3 负载冻结 | `design.md:92` + `:115` | **实现扩了负载，文档未更新** | `:92`"colortex3 只由不透明 lit 写 skylight+HAND标识"、`:115`（SC-35 R8 位域决议）"其余用途仍为 skylight，不加缓冲或 varying"。实际 `lit.fsh:378` 还写了 `.gb` 八面体涟漪法线，SC-39 又加了 `.a` 积水掩码（`deferred.fsh:135` 读）。三项都不需要新 varying，所以没有触发 SC-14 的冻结条款，但"只写 skylight"这句话已经不等成立于默认配置 |
| 水体状态供给地形光照/焦散 | `shaders.properties:45-46`、`design.md:81` | **假** | F-10 |
| 反射 28–96 方块淡出 | `design.md:286` | **未生效** | `surface.glsl:201,213,233,258` `fade=1.0` |
| 焦散 0.15–0.75 强度带 | `design.md:509` | 一致 | `caustics.glsl:72`（0.70）、`:109` |
| SC-35 坐标契约 | `docs/2026-09-13-astra-full-audit.md` | 一致 | `shadow.vsh:85,113`、`transforms.glsl:94-101` |
| 144/90/60 FPS 硬指标 | `design.md` 性能条款 | **从未测量** | `qa/benchmarks.md` 全部表格为空 |

---

## 7. 整体性能优化建议

### 7.0 前置：没有测量就没有优化（P1 级流程缺陷）

`qa/benchmarks.md` 的所有表格是空的。也就是说全包 144/90/60 FPS 目标一次都没被测过，`cost_census.py` 也没接成门禁。任何排序在实测前都只是先验。

**第一步（半天，收益最高）**：用现成的 `qa/tools/compile_glsl.py` + 一组固定场景（开阔水面俯视、正午潜水、雨天平原、末地、下界）跑一次带 GPU 计时器的基准，把数字填进 `qa/benchmarks.md`。若使用 RenderDoc/NSight，直接抓 per-pass 时间，就能立刻验证下面 §7.1 的先验排序。同时把 `cost_census.py` 的每像素取样数接进 `check_pack.py` 作为门禁（超阈值即失败），这样"注释说不算就不算"不再可能蒙混过关。

### 7.1 高确定性收益（按预估性价比排序）

**排序更正（交叉核验后）**：新增的 **F-42** 排在**首位**，下表 #1–#9 序号相应顺延（不逐行改写，以本段为准）。它的优先级高于下表任何一项，理由是三项其他候选都不满足的条件：不依赖天气、不依赖用户选项、无需重设计、修改面是一行清屏常量。

> **F-42 ｜colortex3 掩码的清屏值是量程最大值** ｜`lib/settings.glsl:357` → `deferred.fsh:136/146` ｜水面 pass 与半透明 pass 都不写 colortex3（`lit.fsh:22-28`），这些像素因此以 `standingWater = 1.0` 通过门控，进而在**每个水面像素、每个雨丝/粒子/玻璃像素**上求值一次注定被丢弃的 `puddle_reflection()`（`astra_reflection_sky` 确定执行，march 的迭代次数待实测）｜改 `colortex3ClearColor.a = 0.0` 或把 `upFacing` 提进门控 ｜预估：BALANCED/ULTRA 档有水场景的 deferred 直接减负，且不需要任何画质取舍。**这是本次唯一"零风险 + 大覆盖面"的单项。**

新增的两行标了（新）。另外提醒：下表所有"预估"都是先验，`qa/benchmarks.md` 仍然一个数字都没有（§7.0），拿到基线后请重排。

| # | 项目 | 位置 | 代价来源 | 建议 | 预估 |
|---|---|---|---|---|---|
| 1 | **焦散被放进光束循环** | `light_shafts.glsl:101` → `caustics.glsl:94-107` | 一次 `astra_water_caustics_focus` = 3×3 网格 × `astra_wave_normal_at`(4 次 `solas_water_height`) × 2 次 `textureLod` = **72 次纹理取样**；×7 样本 = **504 次/像素**，×10 样本 = **720 次/像素**，且此时 colortex1 是全分辨率 | 光束用一次性、单 tap 的近似：`c = solas_water_caustics(point)`（5 次高度 = 10 tap），或直接复用 `resolve` 后的低频场 | 潜水时该 pass 的纹理流量下降约 7×。**潜水场景取样流量的最大单项**（覆盖面不及 F-42） |
| 2 | **colortex1 全分辨率** | `shaders.properties:8-13` | 光束选项把 godrays pass 从 0.5 提到 1.0 = 4× 像素 | 拆两张缓冲或整体回 0.5（见 F-12） | 空气侧 scattering pass 成本 ÷4 |
| 3 | **`fade = 1.0` 使水面 LOD 空转** | `surface.glsl:201,213,233,258` | 远处水面永远按最近档计算 | 接真实曲线 | 远处水面像素成本约 ÷2–3（视场景） |
| 4 | **`puddle_reflection()` 无条件求值** | `deferred.fsh:146-147` | 96 步 + 6 步细化反射（`:32,:42`）在每个像素执行，门控只乘进权重 | 条件合并进 `if`（F-15） | 地面像素成本随水坑覆盖率下降；平原场景 deferred 明显变轻 |
| 5 | **colortex5/6 链无消费者** | F-10 | `water_state.fsh` 每帧 240 样本网格 + 1 个 composite pass + 2 张缓冲 | 接上 `shadow_water_depth()`，或整链删除 | 删除即省一个全屏 pass 与两张 RT |
| 6 | **`rainy_air` 10 次云/阴影查询** | `deferred.fsh:81-93` | 雨天户外像素全量 | 低分辨率预计算或 `astraRainFactor` 早退 | 雨天 ÷2 左右的 deferred |
| 7 | **次表面/透光乘子算反** | `diffuse.glsl:285-290`（4-lobe = 16 次比较）、`:185-193` | 语义错误导致需要更高 SSS 才能"看见"，用户于是调高滑块 | 修 F-08 | 间接：允许下调 SSS 档 |
| 8 | **阴影过滤在光束里走硬判定** | `light_shafts.glsl:95` | 三个 profile 全 `SHADOW_FILTER_MODE=0` | 硬件 PCF 常开（commit 2c8e5dd 已完成该通路），删掉软件分支 | 少一次纹理取样 + 质量提升 |
| 9 | **纯带宽/显存浪费（三项）** | `weather.glsl:113-115` + `uniforms.glsl:41`、`shaders.properties:217/219`、`shaders.properties:8-13` | 从不采样的 128×7680 flipbook（F-29）、每帧算完就丢的 `sunrise`/`moonrise`（F-32）、两维度中恒不写却按光束档位分配的 colortex1（F-18） | 删绑定 / 删 uniform / 维度化尺寸 | 数 MB 显存与一次纹理上传；无画质损失，属零风险清理 |
| 10（新） | **colortex7 未声明尺寸 + 被迫的 colortex0 mipmap** | `water_bloom.fsh:1`、`:11`；`shaders.properties` 无 `size.buffer.colortex7` | 全分辨率 RGBA16 的水下 bloom 目标（1080p 写侧 ≈ 62 MB/帧量级）；`colortex0MipmapEnabled` 让主 HDR 缓冲每帧建整条 mip 链，只服务一次采样 | `size.buffer.colortex7=0.25 0.25`；mipmap 需求移到 `colortex2`（已 0.25）；空气侧用 `program.*.enabled` 关掉整条 pass | 空气侧也受益（该 pass 目前在空气里逐像素 discard 但仍是全屏调度），F-48 |
| 11（新） | **天穹无 LUT：`astra_sky_radiance` 逐像素重算** | `scene.glsl:160`（`deferred.fsh`/`lit.fsh` 两侧的雾都走它） | 当前默认 `SKY_MODE=1`（渐变）成本可控；**但 `design.md:249` 要求的主路径是 Minishita，切回后每个雾化的户外像素都要跑 2 视采样 + 1 光采样积分**，且它同时是 F-42 里 `astra_reflection_sky` 的被调函数 | 按方位+天顶角建一张 64×32 或 128×64 的 sky LUT（每帧一次、`deferred` 里填），雾与反射都查表 | 是"切回 Minishita"的前置条件：没有 LUT 就不要动 `SKY_MODE` 默认值（F-47） |

### 7.2 结构性（需要设计决策，不是一次提交）

1. **给光束一条自己的低频缓冲**。光束本质上是一个 40 方块范围、极低频的体信号，不需要全分辨率、也不需要每像素重算 72-tap 焦散。合理形态：0.25 分辨率、4–6 步 march、双边上采样（把现在的 4-tap 等权换成深度感知权重，同时满足 `design.md:292`）。这一条同时解决 §3.3、§3.4、7.1#1、7.1#2。
2. **把"水色"从三处合一**。目前 `WATER_CHARACTER` 只影响空气侧吸收（`absorption.glsl:16-31`），水下雾来自 Solas 常量（`solas_water.glsl:91-100`），入射光又来自 `astra_water_incident`。三者不共享色相，导致水色滑块"调了但只改一部分"。建议：一处定义"水色三元组（浅/中/深）"，其余全部由它派生 —— 这也让 §4 的色相行程可以单点验收。
3. **建立"控制项必须可观测"的门禁**。`check_pack.py` 增加一项：对每个 screen 上的选项，要求存在至少一个 `#ifdef/#if` 或数值消费点，并对"写了但立刻被覆写"（`lit.fsh:371` → `:374` 这种）做检测。F-20/F-11/F-15 全部属于这一类，工具化之后不再依赖人工复查。
4. **注释纪律**：任何"现在 X"的断言必须带一个可运行的检查（一行 `#error`、一条 `check_pack` 规则，或 `qa/` 下的一条断言脚本）。本包的反复失败模式不是写错，而是**改了代码没改注释，下一次审查按注释判断**（09-16 抓到 3 个、09-17 修复又抓到 4 个、本次再抓到 F-01/F-04/F-16 等）。

### 7.3 明确不建议做的事

- 不要再靠降低 `UNDERWATER_SHAFT_SAMPLES` 换帧率：它现在 7 档的视觉输出接近 0（§3.1），降档等于"少花钱买看不见的东西"，反而掩盖了真问题。
- 不要在修 F-19/F-21/F-23 之前做大规模重命名或风格统一 —— 那些是噪声，会让下一次 diff 审查失效。

---

## 8. 顽固问题模式

四类反复出现的模式，本次仍在产生新实例。左列是既往记录，右列是本次新增。

| 模式 | 既往 | 本次新增实例 |
|---|---|---|
| **注释断言 ↔ 代码相反** | 09-16 抓到 3 个、09-17 修复时又抓到 4 个 | F-01（`lit.fsh:341/346-349` 三句全伪）、F-04（`:29-35` 说"参考实现不做硬跳过"，`:100` 做了）、F-28（`:225-226` 承诺 CPU 平滑，无人消费）、F-29（properties 说 3 层，代码 2 层）、F-30/F-34/F-35/F-36/F-37（注释与数值/台账不符）、**GLM N-1（`diffuse.glsl:357-359` HEAD 版把 `astraSolasShadowFade` 的正午与晨昏整个说反；我按 `properties:311` 的表达式独立复算：`sunAngle=0.25`→1.0、`0.0/0.5`→0.0，注释声称的"ZERO at noon / 1 at sunrise"两处皆反）** |
| **控制项不生效（假旋钮）** | `SHADOW_FILTER_MODE` 双分支长期只跑一支 | F-27（末地吃掉 VIGNETTE/DITHERING）、F-11（`fade=1.0` 使 LOD 分支永不进入）、F-20（`SUN_MOON_DISCS` 零引用）、F-24（profile 把不达标的默认值固化） |
| **死链（写了没人读 / 该有人读没人写）** | `shadow_water_depth()` 长期 0 调用者 | F-10（colortex5→water_state→colortex6 整链断裂）、F-32（两个 CPU uniform 每帧算完就丢）、F-33（`lib/noise.glsl` 整文件 + 一张未绑定的 png）、F-21（`:371` 死写）。（原列在此处的 F-38 已撤回，理由见 §5 该条与 §10） |
| **证据缺口** | `qa/benchmarks.md` 全空 | 仍是全空；新增：F-31 的两条 Iris 语义前提无实机工件、F-02 的 pass 顺序无实机探针、§4 的水色无逐深度色相表 |

一条判断：**这个包的瓶颈不是写代码的手速，是没有"生效性"证据。** 现有校验链 `compile_glsl.py` → `check_pack.py`(11 项) → `cost_census.py`（两个自陈盲区、且未接门禁）只回答"能不能编译"，从不回答"这条语句有没有产生它声称的结果"。§9 里的每一条 P1 都不是"没实现"，而是"实现了但接错"——后者恰恰是编译类工具永远抓不到的。因此 §7.2#3/#4 提的两条工具化建议（控制项必须有消费点；带数值的注释必须配一条可运行断言）优先级高于任何新增视觉特性。

---

## 9. 核验回执（哪些结论是我亲自复算的）

**逐行读源码直接确认**：`lit.fsh:23/27/336-380`、`water_state.fsh:1-40`、`absorption.glsl` 全文、`caustics.glsl` 全文（含 `:14-15` 的 2 次 `textureLod`、`:56-57` 的 4 次高度、`:94-107` 的 3×3）、`light_shafts.glsl` 全文、`scattering.fsh` 全文、`water_composite.fsh` 全文、`settings.glsl:23/66/120-135/227-323/336-361`、`shaders.properties:8-20/45-56/68-70/155/166-173/197-238/287-304`、`surface.glsl` 的四处 `fade=1.0`、`shadowmap.glsl:28-35/217`、`diffuse.glsl:185-193/285-290`、`fog.glsl:58-82/146`。

**调用者计数用 grep 交叉验证**：`shadow_water_depth()` 0 调用者；`water_volume_state()` 唯一调用者是自己所在 pass；`rippleFootprint` 仅流向 `astra_rain_ripple`；`SUN_MOON_DISCS` 全包仅 1 处（定义处）；`astraSolasTimeBrightness` 的消费点。

**Python 离线复算**：§4.2 与 §4.4 的两张色相表、§3.1 的相位积、§3.2 的衰减链量级、`ENTITY_SHADOW_DISTANCE` 8×5 比值表（全部算术正确）。

**配置层子审查的结论经我逐条复核后纳入**（F-27/F-28/F-29/F-30/F-32/F-33/F-34/F-35/F-36/F-39；F-38 当时一并纳入、在交叉核验阶段被我自己的复算推翻并撤回，见 §5 与 §10），其中我修正了子报告的两处：
- F-34：子报告给"包络 −14°..+14°"，我按 `properties:214-215` 重算为 **−9°..+14°**（`asin(-0.156)=-8.97°`、`asin(0.242)=+14.0°`），±4° 是拐点而非端点。
- F-33：子报告判"若引擎无别名则为编译期失败点"，实际该采样器不被任何活跃代码路径使用（`lib/noise.glsl` 三个函数零调用），因此不构成编译风险，降级为 P3 卫生项。
- 我另将子报告的 F-39 由 P2 降为 P3：`mix` 两侧虽都求值，但负底数分支的结果被丢弃，且唯一调用点已钳位 —— 属"依赖调用方自觉"的可移植性风险，非当前缺陷。
- **未纳入**：子报告称 `shadowmap.glsl:162-196` 的软件分支 `shadow_filter_uv` 为死代码，但我 grep 到 `diffuse.glsl:267` 有一个真实调用点，且该函数定义在 `shadowmap.glsl:178`。二者矛盾且我无法在不改代码的前提下确定其预处理归属，故该条整体剔除，不作为结论。

**交叉核验阶段新增的复算（第二轮）**：`lit.fsh:22-28` 的三种 `RENDERTARGETS` 分配与 `deferred.fsh:136` 门控的组合（F-42 的关键，两份外部报告都只推了一半）；`settings.glsl:357` 的 `colortex3ClearColor`；`decode_unit_vector((-1,-1))` 与 `((0,0))` 两种输入的手工展开（后者对应 `shaders.properties` 无 `clear.` 指令时的默认行为差异）；`program/nether_light.csh` 全文 65 行与 `compile_glsl.py:113-121/293-300/370` 的计数逻辑（用于解释 "27"）；`SKY_MODE`→`SKY_GRADIENT` 的宏求值链（`settings.glsl:20-21,80` → `overworld.glsl:11-15` → 三档 profile）；README 九行的逐条对表（F-41）；`END_BODY_COUNT=73` 与 `end_blackhole.glsl:79-81/175` 的数组构造次数；8 处 `global → global` include 的行号；`water_bloom.fsh:1/11` 与 `size.buffer.colortex7` 缺失。

**第三轮（F-42 写者侧追证）**：`lit.fsh:336-378` 全段注释与两条 `gl_FragData[1]` 写入点、`deferred.fsh:124-150` 的完整门控与读取、`grep -rn "ASTRA_WATER_PASS\|ASTRA_TRANSLUCENT" Astra/shaders/` 的 define 归属扫描（`gbuffers_water.fsh:3-4` 两者皆定义，其余七个半透明程序只定义 `ASTRA_TRANSLUCENT`）、`check_pack.py:747-822` 的引擎常量规则。

**第四轮（外部报告判定 + 自我更正）**：`find Astra/shaders \( -name '*.glsl' -o -name '*.fsh' -o -name '*.vsh' -o -name '*.csh' \)`（245 个文件）+ 花括号配平的"循环体内 `texture()`"扫描（F-14 重推，得 4 个站点）；`grep -rn "MipmapEnabled" Astra/shaders/`（3 处：`water_bloom.fsh:5` colortex0、`composite1.fsh:20` 与 `final.fsh:23` colortex2）；`git show HEAD:Astra/shaders/global/lighting/diffuse.glsl`（验证 GLM F4 在 HEAD 上成立）；`python` 复算 `properties:311` 的 `astraSolasShadowFade` 曲线（GLM N-1）；`grep -rn "define R11F_G11F_B10F"`（0 命中，F-38 撤回的依据）；`.specs/astra-shader/design.md:88-93/113-116/488-495`（§6 两行更正）。

**计数口径差异的澄清（9 vs 10，三方都说过、都不算错）**：`find` 到的 `.csh` **文件**是 10 个 —— `world-1/shadowcomp.csh` + `shadowcompA–H.csh`（9 个 Iris 注册入口）再共享同一份 65 行本体 `program/nether_light.csh`。我说"9 个已注册 compute 阶段"数的是**入口**，外部报告说"10 个 .csh"数的是**文件**；`compile_glsl.py` 按 profile 计数，所以"27 compute"= 9 × 3 档。README `:20` 的"零 compute"这个断言本身仍然为假（F-41）。

### 9.1 审查期间工作树发生变动（引证漂移，务必先读这一节再用本报告的行号）

本报告主体写于 HEAD `7e3f51c`。收尾阶段（同一台机器、同一工作目录）工作树被另一条执行线推进：HEAD 变为 **`ef90edb` "Checkpoint the September 16-17 shader rounds and the review reports before consolidated fixes"**，其上有 **36 个已跟踪文件改动（+386 / −272）+ 3 个未跟踪新文件**（`docs/2026-09-20-final-consolidated-review.md`、`qa/open-premises.md`、`qa/glsl-consolidated-fixes.log`），内容正是三方审查清单的落地。实测文件 mtime 窗口为 **01:49–02:04 且在我复核期间仍在推进**（最后一次观察到 `program/final.fsh` 于 02:04:50 被改，晚于我上一版报告落盘 17 秒）。我未修改任何代码文件（本次全程只写 `docs/2026-09-20-qoder-full-review.md`），但**我的行号与"是否已修"两件事因此同时过期**。实测到的影响：

| 条目 | 当前工作树状态 | 我怎么确认的 |
|---|---|---|
| F-01 | **已修** | `lit.fsh:355-356` 注释已改为承认 colortex5.a 是 validity 标志，`:367` 的写法换成分支内三元 |
| F-03 | **已修** | `light_shafts.glsl:57` 改用 `refractSun`，`:62` 变成 `mix(0.25+VoL*0.25, VoL*0.45, time)`，`:61` 新增 `sunGate` |
| F-14 站点 1（GLM F3 同类） | F-3 类已修：`lit.fsh:50-51` 把 footprint 提到 material 分支外、`:240` 改用 `endStoneFootprint`；F-14 的四个站点在未触碰文件里，**仍开放** | `git status` 未列 `bloom_capture.glsl`/`end_sky_buffer.fsh`；重读源码 |
| F-15 / F-42 | **已修** | `settings.glsl:362` 现为 `colortex3ClearColor = vec4(0.498,0,0,**0.0**)`（正是我给的两个方案之一）；`deferred.fsh:147` 起注释"Every factor gates the CALL, not just the mix weight" |
| F-27 | **已修** | `grading.glsl` 的 End 分支不再抢占 `#elif` 链，改为叠加在选项结果之上 |
| F-33 | **已修（连文件一起删）** | `lib/noise.glsl` 与 `shaders/textures/noise.png` 在工作树中为 ` D` |
| F-44（GLM F4） | **已修** | `diffuse.glsl:380`/`:457` 现为 `facingAway ? 0.0 : night_desaturation(...)` |
| F-45（GLM F7 / hunyuan A1） | **已修** | `final.fsh:89-95` 改成互斥分支，注释直接署名"consolidated review D4 / Hunyuan A1" |
| GLM N-1（shadowFade 注释反向） | **已修** | `diffuse.glsl:359-364` 新注释语义正确，并自述"an earlier comment here had the two backwards" |
| F-05 / F-06 / F-40 | **已修**（终态；我观察时 `absorption.glsl` 尚未落盘） | `absorption.glsl` 谱序反转 + `:74` 深度上限 `clamp(depth+1.0,0.0,24.0)` + `:72-78` 受控 in-scatter，逐项见 §10.7 C1/C2 |
| F-07 / F-11 | **开放，有意不改**（工单 §3 裁决，我接受） | `surface.glsl` 四处 `fade = 1.0;` 逐字仍在；`water_composite.fsh:23` 的 `clamp(color,0.0,1.0)` 逐字仍在。裁决理由见 §10.6 |

**已知的行号漂移点**（当前树实测，供后续引用改正文时用）：`colortex3ClearColor` 由 `settings.glsl:357` → **`:362`**；`astraSolasTimeBrightness` 由 `properties:304` → **`:310`**、`astraSolasShadowFade` → **`:311`**、`astraRainFactor` 由 `:307` → **`:314`**。本报告 §3.1、F-37 与 §9 首轮回执里引用的旧行号是那之前的树，**结论不变、定位需用新行号**。

**这条记录本身也是一个发现**：三方审查报告与代码注释现在互相引用（代码里已出现 "Qoder F-04 #1"、"consolidated review B3/B4/D4/F-16"、"Hunyuan A1"），但没有任何一处记录"修的是哪个 commit 的代码"。审查报告若不以 commit 为锚，修复进行中被引用的行号就会静默失效 —— 这正是本包"注释断言 ↔ 代码相反"模式的文档版。建议：`qa/session-log.md` 的每条修复带上 base commit，报告类文件在页眉写"审于 <commit>"。

### 9.2 本报告自身的更正记录（被推翻的三条，保留在此以便复算者对照）
- "colortex3 的清屏值来自 `shaders.properties`"——这个前提只存在于我的草稿笔记，**发布文本里没有这句**，因此它不构成"报告自我更正"，只记为一次避免：写 F-42 前实查 `grep "^clear\." shaders.properties` = 零条指令，值在 `lib/settings.glsl:357`。旁证：`qa/tools/check_pack.py:747-751` 的 `ENGINE_CONST_NAMES` 与 `:810` 的 `name.endswith("ClearColor")` 把所有 `*ClearColor` 源内常量纳入 SC-23"必须归约为字面量"的引擎常量校验，说明本包把源内 `const vec4` 当作唯一的清屏机制。这条前提若被推翻（即 Iris 不识别源内 `colortexNClearColor`），F-42 的第 1 步不成立、门不会开 —— 属于需要实机确认的两处之一，已在 §10 的"待实机"清单里。
- 我曾判定 GLM F2 的 `n.y = 0` 是数值错误、"实际应为 −1"。复算 `decode_unit_vector((-1,-1)) = (0,0,-1)` 后确认：**y 分量确实是 0，GLM 无误**，我这条"更正"本身是错的，已删除。真正的差异在影响面（不止雨丝，见 F-42 第 2、3 步），不在符号。
- 我曾把 hunyuan 的"`linked=267 / compute=27` 本次实跑"视为可疑（与 09-13 03:14 的 `qa/glsl-audit-fixes.log` 首行逐字相同，而 `docs/` 下没有 09-20 的工件）。复核计数逻辑后撤回该怀疑：入口清单自 09-13 起未增删文件，重跑**必然**得到同一组数字，因此这条相同**不能**作为"未实跑"的证据。我在 §10 里把它降级为"无法证伪的来源声明"，并保留"缺工件、建议把日志与报告同批入库"这一条。

**只读约束的自证（本节已按实测重写，第一版在此处写错过）**：我第一版写的是"`Astra/` 下按 mtime 排序的最新文件是 `weather.glsl`（09-17 00:58），早于本次审查三天"。这句现在是**错的**：`find Astra .specs qa docs -type f -newermt "2026-09-20 01:40"` 实测出 30+ 个 `Astra/` 文件，外加 `.specs/astra-shader/design.md`、`Astra/README.md`、`Astra/THIRD-PARTY.md`、`qa/` 下两个新日志，全部落在 **01:49–02:04**。原因是另一条执行线在我收尾期间按 `docs/2026-09-20-final-consolidated-review.md` 的工单落地修复（详见 §9.1），不是本次审查的动作。可复算的判别方式只有一条：**本次会话我唯一写过、也是唯一新增的普通文件是 `docs/2026-09-20-qoder-full-review.md`**（其余两轮补充同样只改这一个路径）；`Astra/`、`.specs/`、`qa/` 下的每一个改动都能在 `ef90edb` 之上的未提交 diff 里找到对应的工单编号（A1…G2）。会话开始时工作区即已有 38 个着色器文件处于已修改状态（见会话初始 `git status` 快照），那批改动同样不来自本次审查。

**未覆盖范围（诚实声明）**
1. 未做 GPU 实机验证：本机验证链只有 NVIDIA（RTX 4050 / 572.83），F-02 的 pass 顺序、AMD/Intel 上的同缓冲读写行为都**必须靠实机探针定论**，我给的是"该做哪个实验"，不是结论。
2. compute 部分**本轮已补做**：本包只有 **9 个 compute 入口**（`world-1/shadowcomp.csh` 与 `shadowcompA–H.csh`，每个 3 行，都 `#include "/program/nether_light.csh"`，本体 65 行）。我原先写的"27 个 compute 程序"是把 `compile_glsl.py` 的 `compute=27` 当成了文件数 —— 该计数按 profile 累加（`entry_sources()` 只在 `shaders/`、`world-1/`、`world1/` 三处 `glob("*.csh")`，得 9 个；`main():370` 再对每个 profile 各跑一遍），9×3=27、89 入口×3=267 与日志完全吻合。**逐行读完 `nether_light.csh` 后我未发现缺陷**：64³ 与 `workGroups=ivec3(8,8,8)` 严格对齐，`ASTRA_LIGHT_STEP % 2` 的奇偶让"读 A 写 B / 读 B 写 A"从不重叠，没有同帧读写依赖。仍未覆盖的是它的 image 绑定声明与 `shadow.vsh` 的原子写入侧。
3. `global/post/*` 的完整 bloom 链、末地烘焙（`colortex8/9`）未逐行审查，只核对了它们与光束/水色的接口。
4. `docs/2026-09-16-*.md` 两份研究文档作为背景阅读，未逐条核对其中引用的外部包数据。
5. F-02 的四种后果中，(a)(b) 是条件推断（取决于 deferred 的真实位置），已在正文标注；(c)(d) 是代码可直接读出的重复作用。

**工作区状态提示（本节已按终态重写）**：我上一版写的是"`git status --porcelain` = 74 项未提交变更"。该状态在 02:05–02:12 之间被另一条执行线收束：修复批次提交为 **`9df32df` "Fix the defects from the three-way shader review"**（40 文件 / +440 / −276），随后 **`3b5ac22` "Anchor the consolidated report to the fix commit and close Qoder's provisional items"** 给合并工单加了 §3 落地状态节。当前实测：HEAD = `3b5ac22`，`git status --porcelain` 只剩 ` M docs/2026-09-20-qoder-full-review.md`（本报告），`qa/*.log` 160 份、`qa/` 共 172 项 —— 日志堆积这条仍然成立，只是不再与"半程改动"混在一起。

---

## 10. 交叉核验：两份外部审查 + 由它们派生的合并工单

### 10.0 核验方法与纪律

**被审对象是四份产物，不是两份**：GLM 第一轮、混元四、GLM 第二轮核验（176 行）、由它们派生的**合并工单**（`2026-09-20-final-consolidated-review.md`）。后两份是在读到我第一版报告之后写的，所以它们既是被核验对象，也包含对我主张的裁判 —— 我不接受"两份外部报告互相印证"当作证据，每条主张都必须落到源码、工具输出或 git 对象上。

三条纪律：

1. **回到源码，不回到报告**。复算全部用 `grep`/`sed`/`git show <commit>:<path>`/实跑 `check_pack.py` 完成，结论随附可复算手段。
2. **"已修"一律当作待核验主张**。合并工单 §3 声明"26 项全部落地"，本节逐项开文件验，验不过的写进 10.7。
3. **对自己用同一把尺**。交叉核验推翻了我 1 条（F-38）、换掉了 1 条的论据（F-14）、修正了 1 条的机制描述（F-01 的 blend 部分），全部记在 10.5，不做静默替换。

本轮新增的实测手段（前两版没有）：`python qa/tools/check_pack.py` 全量实跑（先确认该脚本零写入：全文无 `open(` 与 `write_text`）；`git log` / `git show --stat` 定位修复 commit 与其文件清单；对 245 个着色器文件做花括号配平的"循环体内隐式 LOD 采样"扫描。

### 10.1 三份外部产物的可信度

| 产物 | 主张密度 | 我实测的准确率 | 独有价值（我原来缺的） | 缺陷 |
|---|---|---|---|---|
| GLM r2 | 高：39 行判决表 + 4 处外部包取证 | 复核其中 36 行，**35 行同意**，1 行判错（F-14） | `sunAngle` 约定取证（Solas `shaders.properties:92-101` + `lib/atmosphere/volumetricLight.glsl:86`）；`astraSolasShadowFade` 曲线数值反驳（N-1） | 给我 F-14 的旧引证打了"属实 ✓"却没打开那三行；降级理由"目标均未开 mipmap"为假 |
| 混元四 | 高：每条带文件:行，自带"我不采信"清单 | 抽查 20+ 条无捏造；`#version` 普查 10/159 精确复算通过 | `design.md:306` + `:425` 蓝图证据链（决定 F-27 分档）；主动撤回自己 §12.6 与"理论可见"两处判断 | 焦散 72 次/样本略低（我复算 74–76）；模块数 54 与工具实测 53 不符 |
| 合并工单 | 中：结论 8 条 + 工单 26 项 + §3 落地声明 | 26 项里 **25 项实测落地**、1 项名义落地（E9）；README 更正 6/9 行 | 三方收敛的执行载体；**采纳了我的 4 条撤回**（composite3 非 UB、`#ifndef` 格式守卫非"永真无意义"、关焦散不会黑光束、deferred 恒开已在 `design.md:493` 登记）—— 核验真的发生了 | E9 目标文件选错；修复提交里未记 base commit（它 §3 已承认并归因于我的元建议） |

**总评**：三方都是实测而非捏造。分歧集中在**分档**与**口径**，不在事实本身 —— 这恰好是"无 P0、构建健康"结论的可信度来源。

### 10.2 数字与口径仲裁

| 主张 | 各方数值 | 我实测 | 裁决 |
|---|---|---|---|
| 编译入口数 | 我 182 / 工单 267 | `check_pack.py` 实跑：`182 compiled entries`；267 = 89 个参与 profile 编译的入口 × 3 档 | **都对，口径不同**。182 = `is_entry`（`check_pack.py:286-292`：`.vsh/.fsh` 且顶层目录 ∉ {lib,global}）；267 = 按 profile 展开的链接数 |
| compute 数 | 9（我）/ 10（混元）/ 27（日志） | `find` 得 10 个 `.csh`：9 个 Iris 注册入口（`world-1/shadowcomp.csh` + `shadowcomp[A-H].csh`）共享 65 行本体 `program/nether_light.csh`；日志 `compute=27` = 9×3 | **都对，三方各数一层**（入口 / 文件 / 档） |
| lib/global 模块数 | 54（GLM、混元、README `:39`）/ 我静态复算 53 | 工具实跑：`53 lib/global modules, 51 reachable, 2 waiting on their owner task, 0 unwired-and-unregistered` | **53 成立，54 是错的**。README 新写的"52/54"两个数都不对，应为 **51/53**；2 个 pending 是 `voxy_opaque.glsl` / `voxy_translucent.glsl`（owner C5） |
| 每样本焦散采样 | GLM r1 18 → 更正 72（我 + 混元） | `astra_water_caustics_focus` = 3×3 循环 × `astra_wave_normal_at`（4 次 `solas_water_height`）× 每次 2 个 `textureLod` = **72**；加焦点自身基准高度 2 次 = **74**；march 样本再加 `shadowtex1` + `shadowcolor0` = **76/样本** | 72 基本对（漏基准 2 次）；**GLM 的 18 确认漏算**，三方已共同更正 |
| 每像素总采样 | 工单 §1.7 "504–720" | 7 样本档峰值 7×76 = **532**、10 样本档 **760**；循环内两处 `continue` + 一处 `break` 使**均值低于峰值** | 方向对、端点略偏低。宜写"约 0.53–0.76 k 峰值，均值受剔除影响更小" |
| `pow()` 站点 | 我 6 / GLM 23 / 混元 ~30 | 未做第四次普查 | **不裁决**：这是 grep 口径差（是否含 `pow(vec3,…)`、注释、`pow.glsl` 内部）。实质问题已由 E7 收口：整数幂迁移完成，`twilight.glsl:53-54` 的 180/1400 保留 `pow` 并在 `:22` 注明"无折叠链" |
| `#version` 分布 | 混元：10 个 430、其余 159 个 400 | `grep -rl "^#version 430"` = **10**、`400` = **159**；相加 169 而带版本行的文件是 170，差的一个是 `program/lit_voxy.fsh:1 #version 460 core` | 混元精确。补两条它没说的：这是**全包唯一的 `core` profile**，且 `192 − 22 = 170`（22 个无版本行的都是 `program/` 下由维度壳提供 `#version` 的共享本体）。`460 core` 归入 10.8 的 P-3 追加项 |
| `decode_unit_vector((-1,-1)).y` | GLM 说 0，我第一版说"应为 −1" | 复算确认 **0** | GLM 对，我的"更正"是错的（§9.2 已记） |
| 出厂分级值 | README 原称 112/115/104 | `settings.glsl` = 100/100/102，三档 profile 同值 | README 已改对 |

### 10.3 对 GLM r2 的判定

**采信（它补上我缺的东西）**

- §1 `sunAngle` 约定取证。本轮唯一一条"用外部包源码钉死本项目隐式约定"的证据，直接支撑 `light_shafts.glsl:53-54` 现在写进注释的"sunAngle 0.25 = noon"。它进 `qa/open-premises.md` P-5 时被标为"高置信、未实机直接观测"，这个定性我认同。
- §6 N-1（`astraSolasShadowFade` 注释把正午/晨昏写反）。我用 `python` 复算 `properties:311` 表达式：0.5 处为 1.0、两处地平线为 0.0，注释语义确实反向。我原来把它归在 F-34/F-35 那类"注释失实"里，**GLM 单独拎出来是对的**，修复见 `diffuse.glsl:359-364`。
- §0.1 对我 39 条的判决（33 成立 / 3 部分 / 1 表述错误 / 2 与既往裁决重合）。逐条回判：那"1 条表述错误"指 F-38，与我自己的撤回一致；"2 条重合"指 F-11 与 deferred 恒开类，我接受；3 条"部分成立"我认为是影响面描述偏保守，不算错。

**不采信（三条）**

- §2 F-14 行的"属实 ✓"：它照抄我给的 `deferred.fsh:36,45,51` 而未打开文件 —— `git show ef90edb:Astra/shaders/program/deferred.fsh` 显示那三行在修复前**已是** `textureLod(…, 0.0)`。
- 同条的降级前提"所涉目标（`depthtex0` / `colortex0`）均未开 mipmap"：`colortex0` 开了 —— `program/water_bloom.fsh:5` 有 `const int colortex0MipmapEnabled = true;`，而 `global/water/bloom_capture.glsl:21` 正是在循环里裸 `texture(colortex0, …)`。**正确结论是"站点从 4 缩到 1，那 1 处成立"**，不是"无 mipmap 所以无意义"。两方各错一次，落点见 10.5#1。
- §7 第一批"properties colortex5 blend 改 off"：机制描述对，但 A1 删除 `lit.fsh:362` 后**已非必要**，见 10.5#2。

### 10.4 对混元四的判定

- **C2（我的 F-27，判 P1）**：**采纳，且是决定性的**。`design.md:306` 把"暗角（默认）"列入"明确不做"、`:425` 再写"默认无暗角/颗粒/色差"，末地硬编码 0.08 暗角因而不只是"旋钮失灵"，而是与蓝图决议冲突 —— GLM 降它为 Minor 时缺的正是这条。裁决见 10.6。
- **C1（blend 表）**：机制正确（src.a=0 时连 rgb 一起丢），但和我一样只在 `:362` 存在的前提下成立。修正见 10.5#2。
- **C3（我的 F-08 二次曲线，并声明不是 09-16 方向修复的重复）**：采信。它主动排除"重复计数"，是核验表里少见的自觉。
- **C4（我的 F-15）+ 撤回自己 §12.6 的"受控"结论**：认可。
- **`:773` 把自己"理论可见"降为"不可见边缘"**：接受，与我给的 0.06–0.5 区间一致。
- **`:804` 对我 F-07 判"❌ 不采信 UB → P3"**：接受，与我自己的撤回同向。
- **`:808` 的 `#version` 普查**：精确复算通过（10 / 159），见 10.2。

### 10.5 我自己被推翻或需要修正的（按重要性）

1. **F-14 引证是错的**（§2 第 3 条与 §5 原条目已按实测重写）。我发布的是 `deferred.fsh:36,45,51` + `end_sky_buffer.fsh:63`，前者早已是 `textureLod`，后者位于一个 34 行的文件里、根本不存在。重推：245 文件花括号配平扫描得循环体内裸 `texture()` 仅 4 处，唯一落在开了 mipmap 缓冲上的是 `global/water/bloom_capture.glsl:21`；同包 `global/post/bloom.glsl:107` 对同一语义已写成 `textureLod(…, 0.0)`。⇒ 论据整体替换，严重度维持 P3。**根因与 §8 同源：我没有打开自己引用的行。**
2. **F-01 关于 blend 的爆炸半径描述过头**（三方都沿用了这句话）。实测：`lit.fsh:367-369` 的有效分支写 `vec4(高度, lightLevel.y, 1.0)`，**src.a = 1.0 ⇒ `SRC_ALPHA` 退化为恒等写入**；无效分支写 `vec4(0.0)` ⇒ rgb 保留 dst、a = 0，而唯一读者 `program/water_state.fsh:19` 的 `if (data.a < 0.5) continue;` 正好筛掉它。所以"rgb 一起丢"只在 `:362` 那次错误覆写的前提下成立（该前提当时确实成立）；A1 之后 `properties:59` 的 blend 已是**惰性的**。⇒ 该子项 P1 → P3，处方从"blend 改 off"改成"要么 `= off` 一次性了结，要么在 `lit.fsh:367` 注明这个 `1.0` 是契约不是取值"。
3. **F-38 撤回**。Iris 按**标识符文本**读取 `const int colortexNFormat = R11F_G11F_B10F;`，`#ifndef` 垫片只为让 GLSL 编译通过；`grep -rn "define R11F_G11F_B10F"` = 0 命中即证。合并工单已把这条写进"已否决主张"。
4. **§9 的只读自证第一版为假**（"Astra/ 最新文件 mtime = 09-17 00:58"），已按 `find … -newermt "2026-09-20 01:40"` 重写，并给出可复算判别式：本次会话我唯一写过的文件是 `docs/2026-09-20-qoder-full-review.md`。
5. **"合并工单没留验证工件"这条撤回一半**。我上一轮看到 `qa/glsl-consolidated-fixes.log` 是 0 字节，据此写"修完没留证据"。该文件在 **02:10:49** 落盘为 192 字节：`linked=267 / failed=0 / compute=27`，`OPENGL_RENDERER = NVIDIA RTX 4050 Laptop / 4.6.0 NVIDIA 572.83`。观测在当时为真、结论已过期 ⇒ 改记为：**工件存在，且与我实跑的 `check_pack.py`（0 FAIL / 1 WARN / 10 PASS）互洽**。

### 10.6 分档分歧与裁决

| 条目 | 我 | GLM | 混元 | 终判 | 依据 |
|---|---|---|---|---|---|
| F-27 末地抢占暗角/抖动 | P1 | Minor | P1（C2） | **P1** | `design.md:306/:425` 属蓝图"明确不做"；假旋钮 + 契约破坏双成立 |
| F-01 blend 子项 | P1 | 必修 | 必修 | **拆档**：写错缓冲 = P1（已修）；blend = P3（惰性，留探针） | 10.5#2 的恒等性证明 |
| F-42 colortex3 清屏 alpha | P2 | F2 的扩大版 | C4 | **P2，已修** | 实效是性能不是画面：`settings.glsl:362` 现 `.a=0.0`、`deferred.fsh:155-157` 权重进门控 |
| F-11 `fade = 1.0` | P2 | 既往已裁决保留 | P2（`:806` 引我的论据） | **维持"记录在案、本轮不改"** | 09-13 §13.3 已裁决保留来源结构；重开需要新论据，我没有 |
| F-02 pass 顺序 | P1 未决 | 需探针 | ⚠️ 需实机 | **不动代码，等探针** | 三方一致；`open-premises` P-1 |
| F-07 水合成域 | P2 | — | ❌ 不采信 UB → P3 | **P3，有意不改** | Iris flip 机制；`clamp` 是注释声明的 Solas 域取舍 |
| §7.1 优化排序 | 先关掩码门 | C6 主张先做别的 | — | **先门控后重构** | 工单实际执行顺序即如此（A2/A3 先于 deferred 条件化），且 A3 是零行为风险的 |

### 10.7 合并工单 26 项的实测落地台账

逐项开文件核对（HEAD `3b5ac22`；`9df32df` 的文件清单来自 `git show --stat`）：

| 项 | 判定 | 我看到的证据 |
|---|---|---|
| A1 | ✅ | `lit.fsh:339-365` 注释重写为承认 colortex5.a 是 validity 标志；`:367-369` 改分支内三元；surfaceWet 死存储已删 |
| A2 | ✅ | `settings.glsl:362` `colortex3ClearColor = vec4(0.498,0,0,0.0)` |
| A3 | ✅ | `deferred.fsh:155-157` `float weight = standingWater*upFacing*rippled*fresnel; if (weight > 0.001)` |
| B1 | ✅ | `light_shafts.glsl:55-57` `refractSun` 前置、`VoL` 用折射后方向；循环后的第二段相位项与 `pow(VoU,1.5)` 已删（`:129-131` 注记） |
| B2 | ✅ | `:78` `minDist = maxDist / samples`（`×0.5` 去掉）；`:92` 内切圆改方形判据 |
| B3 | ✅ | `:118-119` 改用 `solas_water_caustics` + `mix(0.25,1.0,caustic)`；`caustics.glsl:114` 注释确认 `astra_water_caustics_shaft_at` 已删（全包 grep 零命中） |
| B4 | ✅ | `:124` `shade /= max(2.0, currentDist * 0.06)`；`:133` `* (6.0 + sun * 14.0)` |
| B5 | ✅ | `:139` `water_shafts_resolve(…, float rayLength)` 形参启用，`:153` `exp(-abs(tapDist - rayLength) * 0.25)` |
| B6 | ✅ | `shaders.properties:14` `size.buffer.colortex1=0.5 0.5` |
| C1 | ✅ | `absorption.glsl` 谱序反转（BALANCED `(1.000,0.100,0.060)`、TROPICAL `(2.000,0.080,0.055)`）；`:74` 深度上限 `clamp(depth+1.0, 0.0, 24.0)` |
| C2 | ✅ | `:48-56` `water_transport/water_medium` 增 `incidentLight`；`:67` `water_body_color()`；`:72-78` `+ water_body_color()*clamp(incidentLight,0,2)*(1-T)` —— 这正是 F-40 的恒零回退被填上 |
| C3 | ✅ | `design.md:511` 起 "SC-40 决议补登（2026-09-20 三方审查汇总）" |
| C4 | ◐ | 我只验到 `check_pack` #3：`zh_CN.lang` / `en_US.lang` 各 67 titles + 67 comments 全覆盖；**三档水性格文案的具体措辞我未逐字核对** |
| D1 | ✅ | `diffuse.glsl:344-345` `facingAway` 判据 + visibility 只加不减 |
| D2 | ✅ | `fog.glsl:79` `fog_morning_air_weight` 端点、`scene.glsl:148` 直接消费该权重 |
| D3 | ✅ | `diffuse.glsl:380`/`:457` `facingAway ? 0.0 : night_desaturation(...)`；`:359-364` 注释重写 |
| D4 | ✅ | `final.fsh:89+` 互斥分支，注释署名"consolidated review D4 / Hunyuan A1" |
| D5 | ✅ | `grading.glsl:156-175` End 分支改为叠加在选项结果之上（`:170` 注记"the option now does what it says"） |
| D6 | ✅ | `sky.fsh:138` 注记"full-screen double evaluation (consolidated review D6 / Qoder F-22)" |
| E1 | ✅ | `caustics.glsl` 守卫 `#endif` 移到文件尾（tail 可见） |
| E2/E3 | ✅ | `biomeTemperatureSmooth` / `biomeHumiditySmooth` / `sunrise` / `moonrise` 全包 grep 零命中 |
| E4 | ✅ | `lib/noise.glsl` 与 `textures/noise.png` 在 `9df32df` 中删除；`THIRD-PARTY.md:29/:92` 同步登记 |
| E5 | ✅ | `nether_volume.glsl:52` 注记 `dither2` 已删；全包 grep 仅剩该注释 |
| E6 | ✅ | `SHADOW_FILTER_HARDWARE` 7 处命中，字面量 `== 1` 已替 |
| E7 | ✅ | `lib/pow.glsl` 已接线（`final.fsh:5`、`scene.glsl:11`），`THIRD-PARTY.md:25` 登记；`twilight.glsl:22` 注明 180/1400 保留 `pow` 的理由 |
| **E9** | **❌ 名义落地** | 工单点名 `deferred.fsh` / `end_sky_buffer.fsh`，但 `deferred.fsh:36/45/51` 在 `9df32df` **之前**已是 `textureLod`（`git show ef90edb` 可证）、`end_sky_buffer.fsh:18/24` 仍是裸 `texture(depthtex0,…)`；而唯一真正的站点 `global/water/bloom_capture.glsl:21`（采 `colortex0`，该缓冲开了 mipmap）**未改，且该文件不在 `9df32df` 的 40 个文件里**。⇒ 该项改的是已经正确的行，漏了唯一需要改的行。实际影响：P3（`depthtex0` 无 mipmap，故 `end_sky_buffer` 那两处只是风格；`bloom_capture` 那一处才是 F-14 的全部内容） |
| E8/E10/E11 | ✅ | `encoding.glsl:19-22` `srgb_decode` 函数内 `max(...,0.0)`；`world-1/shadow.vsh:2-4` 补了 `#version 430` 的理由注释（`imageAtomicMax` 需 420+） |
| F1–F3、F5 | ✅ | `properties:25` `size.buffer.colortex7=0.25 0.25`；`settings.glsl:76` `SSS_STRENGTH 60`（对齐 BALANCED，即 F-30）；`THIRD-PARTY.md:25/:29/:92` 三处漂移修正 + `pow.glsl` 行；`design.md:511` 汇总决议 |
| F4 | ◐ | README 9 行里 6 行改对、3 行仍失实，另新引入 1 个错数（"52/54" 应为 51/53）。逐行见 F-41 的"修复后复测"表 |
| G1/G2 | ✅ | `docs/2026-09-17-sc39-puddle-reflection.md` 存在；`qa/open-premises.md` 存在且已扩到 P-6 |

**溯源密度**：源码与配置里现在有 **39 处** `"consolidated review"` 注释把改动回连到工单编号（`grep -rn "consolidated review" Astra/shaders | wc -l`）。这是我本轮见到的**最有效的流程改进** —— 上一节说的"注释断言 ↔ 代码相反"模式，至少在被修的这批里已经可追溯。

**修复自身引入的两条新失实**（属于 F-41 那类问题在源码层的复现，P3）：`light_shafts.glsl:67` 仍以现在时写着"the 1/max(3, d*0.1) attenuation below"，而 `:124` 实际是 `max(2.0, currentDist*0.06)`；`:69-73` 仍以现在时描述"step of maxDist/samples*0.5 … about 17 blocks"，而 `:78` 已去掉 `*0.5`。两处注释描述的正是本次修掉的旧行为。

### 10.8 未决前提：对 `qa/open-premises.md` P-1…P-6 的复核与追加

三方一致认可的 6 条我逐条看过，判定为**都是真未决、没有一条是凑数的**。其中 **P-6 正是我 §9.2 第一条留的"需实机确认"**（源内 `colortexNClearColor` 是否被 Iris 识别为清屏指令），已被采纳并给出了比我更好的判据：旧清屏 `.r=0.498` 造成的"天空像素 skylight=127"长期可观察，说明机制生效 ⇒ 风险极低。该条闭环。

我要追加 4 条（按证伪成本从低到高）：

| 编号 | 未决前提 | 最便宜的证伪手段 |
|---|---|---|
| **P-7** | `blend.gbuffers_water.colortex5`（`properties:59`）与 `lit.fsh:367` 那个字面 `1.0` 之间的隐式契约：一旦有人把有效分支的 `.a` 改成任意分数，packed 水面高度会静默与 dst 混合 | 静态即可判定，无需实机；修法两选一（`= off` 或加注释），成本 < 1 分钟 |
| **P-8** | README `:39` 对外口径"52/54 模块可达"与工具实测"51/53"不符（另 3 行 profile 事实仍失实） | 跑一次 `check_pack.py` 即可关闭 —— **不该挂"待实机"** |
| **P-9** | B4 的重标定（`/max(2.0,d*0.06)` 与 `×(6+14·sun)`）只有编译证据、无画面证据；`UNDERWATER_SHAFT_SAMPLES` 按三方共识未降档 ⇒ 水下最贵单项的量级改了、代价没改 | 实机 A/B 一帧（与 P-4 同批） |
| **P-10** | E9 未落地 ⇒ F-14 的唯一站点（`bloom_capture.glsl:21` 采开了 mipmap 的 `colortex0`）仍开放 | 改成 `textureLod(…, 0.0)`，一行；或与 `global/post/bloom.glsl:107` 对齐 |
| **P-3 追加** | 267 项编译证据全部来自 NVIDIA 4.6/572.83；`program/lit_voxy.fsh:1` 是唯一的 `#version 460 core`，且 `VOXY_SUPPORT` 在全部三档 profile 都是 `!VOXY_SUPPORT`、`voxy.json` 为空占位 | 他厂驱动跑一次 `compile_glsl.py`；顺带确认该 460 入口在非 Voxy 路径下是否也必须通过 |

**对这些台账的一条元建议**：给 `open-premises.md` 加一列"证伪成本"。P-7/P-8/P-10 都是"跑一条命令或改一行就能关掉"的，混在 P-1/P-4 这类必须实机的条目里，会让整张表看起来比实际更重。

### 10.9 必要性权衡：明确不该做的事

交叉核验的另一半是否定。以下 6 条我不建议执行，理由各自给出：

1. **不要照 GLM §7 / 混元 §13 去把 colortex5 的 blend 改成 `off`**（当作"必修"那种改法）。10.5#2 已证明它在 A1 之后是惰性的；改了不会有任何画面变化，反而抹掉一条能暴露"字面 1.0 契约"被破坏的回归探针。要做的是加注释，不是改配置。
2. **不要在拿到帧率基线之前动 deferred 条件化、composite3 并入 final、rainy_air 降采样、天空 LUT**。工单已把它们推到下一批，我认为这个判断是对的：这四项都涉及行为取舍，而本包至今 `qa/benchmarks.md` 全空 —— 没有基线的优化只能靠猜测排序。
3. **不要再加 `pow` 助手去追"混元 ~30 站点"**。整数幂已经迁完，剩下的是 `180.0` / `1400.0` 这类非折叠链指数，`pow.glsl` 帮不上；`twilight.glsl:22` 已经把这个决定写下来了。
4. **不要降 `UNDERWATER_SHAFT_SAMPLES`**。三方一致：先修量级再看采样数。B4 的画面证据（P-9）没拿到之前降采样，等于用未知换未知。
5. **不要给 F-11 补"修复"**。09-13 §13.3 已裁决保留来源结构；我的性能论据已记录在案，重开需要新信息（比如未来做远水面 LOD）。
6. **不要再出第四份汇总报告**。三方收敛已完成、26 项工单已落地 25 项 —— 现在缺的是画面和帧数，不是文档。下一份产出应该是 `qa/benchmarks.md` 的实数和 A/B 截图，任何新的审查文档在这个包里的边际价值已经低于一次实机。

### 10.10 合并后的唯一下一步顺序

把 10.7 的缺口、10.8 的未决、10.9 的禁区压成一条队列（每条都能单独验证，且不需要新的决议）：

1. **关零风险项**（一次提交）：P-10 `bloom_capture.glsl:21` → `textureLod(…, 0.0)`；P-7 `lit.fsh:367` 的 `1.0` 契约注释；P-8 README 三行 profile 事实 + "51/53"；清掉 `light_shafts.glsl:67/69-73` 两段与代码相反的注释。
2. **拿基线**：跑三档各一次基准，把数字填进 `qa/benchmarks.md`。这一步决定 §7.1 里所有结构性优化的排序，**在它之前不要动管线**。
3. **实机对拍**（与 2 同批出图）：B4 光束量级、C1/C2 水色青绿→深蓝、D1 植被透光、D2 晨雾端点 —— 这四项在工单里就标了"需实机对拍"，是本轮唯一没有画面证据的行为改动。
4. **一次会话做三个探针**：P-1 hand/deferred 真实顺序（F-02）、P-6 关 colortex3 掩码后门是否真的不再进积水门、P-9 的水下 A/B。
5. 拿到 2/3 的数字之后，再决定是否执行 §7.1 的结构性优化与 `UNDERWATER_SHAFT_SAMPLES` 降档。

### 10.11 计数收口

§5 实际列出 **52 条** F-编号条目（F-01…F-54 中 F-25、F-26 未使用），分档 14 P1 / 22 P2 / 15 P3 = 51 条有效主张 + F-38 撤回后正文保留作对照。经交叉核验：**维持 51 条中 48 条**；修正论据 2 条（F-14 换站点、F-01 拆档）；撤回 1 条（F-38）；由外部报告补强或升档 3 条（F-27 经混元 C2 钉在 P1、F-01 经 GLM/混元补出 blend 机制、F-08 经混元 C3 排除重复计数）。截至 `3b5ac22`，51 条中**已由工单执行关闭 24 条**，余下 27 条中约半数是本轮明确"有意不改"（F-07/F-11/F-02 与 deferred 条件化一类），真正需要新动作的集中在 10.10 的第 1 步（4 项，零风险）与第 2、3 步（测量，不改代码）。

**三方审查的净结论未变：无 P0；构建健康（`linked=267 / failed=0 / compute=27` + `check_pack` 0 FAIL / 1 WARN / 10 PASS，均本轮实测或复核工件）；两个长期未实现的水效果已按 §3/§4 的根因改到源码里，但没有任何一条改动经过实机验证。** 该说的到此说完。若需要，我可以按 §3.7 与 §4.4 出一份"实机对拍清单"（每步看什么、什么算通过），那份清单的优先级现在高于任何新的静态审查。
