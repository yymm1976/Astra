# 2026-09-08 阴影-水修复轮：四图实测后的源码修复记录

本轮依据：用户最新实机对比四图（图 1/2 = 规范光影参考，图 3/4 = Astra）。
用户判定三项：水上水体颜色不对（且存在随视角上下移动而变换的断层，图 4）；
水下阳光感明显不强（图 3 vs 图 2）。另有持续五六轮的阴影 bug：
玩家周围十几个方块半径内阴影正常，圈外阴影疑似未完全加载，玩家移动时同一棵树的影子会发生变化。

用户明确要求：先精读 Solas 水下与 Steadfast 水面的参考源码再定修复方案；
先为当前工作区建立回退点（commit），再实施修复。

## 0. 回退点

- 提交：`6fcb0fd`（chore: checkpoint water/shadow visual-round work for rollback），
  含 SC-33..SC-35 全部未提交工作（196 文件，+5188/−1183）。
- 回退命令：`git reset --hard 6fcb0fd`。

## 1. 参考源码精读结论（决定数值口径）

### Steadfast 0.8.0（水面，`_analysis/Steadfast-0.8.0/shaders/`）
- 折射为**单跳投影**（`environment/water/refraction.glsl:98-164`）：
  背景深度取当前像素 2x2 gather 的 min/max 足印，`travel = min(|Δz|, 32m)`，
  沿折射方向推进一次后投影；命中比水面更近 → 回退原始 UV；屏幕外 10% 淡出。
  无 4 步迭代振荡，因此无"随俯仰移动的断层"。
- 吸收为**单指数向量**（`environment/water/absorption.glsl:19-34`）：
  `exp(-d_norm * (16,3,1))`，16 米为全深（含 1/16 偏置）；
  1 米透射 ≈ (0.135, 0.687, 0.882)（浅滩青绿），16 米 ≈ (0, 0.05, 0.368)（深蓝）。
  无独立散射系数；teal 与深蓝由同一个指数向量产生。

### Solas V2.2b（水下，`_analysis/Solas Shader V2.2b/shaders/`）
- 水色常量（common.glsl:237-241）：`waterColorSqrt=(0.361,0.627,0.784)`，线性 `(0.130,0.394,0.615)`。
- 水下雾色增益（`lib/water/waterFog.glsl:9-15`）：
  `*=(0.1+0.4*sunVisibility)`；`waterFogColor *= (0.5+0.5*eBS) + glare*16.0*timeBrightness*eBS`，
  其中 `glare = 0.01/(1-0.99*clamp(VoL*0.5+0.5))-0.01`（朝太阳最大约 16.8x）。
- 体积光水下增益（`lib/atmosphere/volumetricLight.glsl:125`）：
  `finalVL *= mix(waterColorSqrt, waterColorSqrt*weatherCol, wetness) * (4.0 + sunVisibility*8.0)`（4~12x）。
- 水下 VL 把硬阴影项清零（`float(isEyeInWater==0)`），只保留彩色透射（shadowcolor0 中焦散图案）。
- 焦散（`lib/water/waterCaustics.glsl`）：双 octave 噪声求导数交叉积 ×48，强度 `0.25+caustics*4.0`。

许可红线：Solas 许可证未声明，表达式级移植此前被判定违规（见 .workbuddy/memory/2026-09-07.md）；
本轮所有对标都是**自写等效曲线**，仅引用数值目标。

## 2. 修复项 A：阴影"圈外未加载 + 移动时树影变化"

### 根因（复合）
1. `lib/distort.glsl:16` `shadow_map_bias = 1 - 25.6/shadowDistance`：透视扭曲网格把纹素集中
   在 25.6 块内区（地面斜边可视半径约 12-19 块），这正是用户看到的"十几个方块正常圈"。
2. `lib/settings.glsl:59` SHADOW_DISTANCE=128，而实例渲染距离 16 chunk=256 块：
   124 块外 `shadow_map_fade=0` → `diffuse.glsl` 覆盖回退 `static_shadow(skyLight)`
   （正午 15 级 ≈1.0 = 无影）→ "圈外阴影未完全加载"。
   此问题在 `docs/2026-09-08-fourth-round-rootcause-and-fixplan.md` P2 已诊断，
   `docs/2026-09-08-codex-halfdone-review.md:76-83` 确认"完全没修"，本轮才落地。
3. 圈外 texel 世界尺寸 0.25→0.63 块（128 距离），叠加 SHADOW_SOFTNESS=4（16 tap PCF）
   → 边缘糊边 1.0-2.5 块；Iris 默认 `shadowIntervalSize=2.0` 每跨 2 格 cell 网格量化
   → 玩家移动时影边缘按当地 texel 跳格（0.4-0.6 块），即"影子在变"。

### 改动
| 文件 | 变更 |
|---|---|
| `lib/settings.glsl` | SHADOW_DISTANCE 128→256；SHADOW_SOFTNESS 4→2；新增 `const float shadowIntervalSize = 0.5;` |
| `shaders.properties` | 三档同步：PERF 96→192（SOFTNESS 2 不变）、BALANCED 128→256 / SOFTNESS 4→2、ULTRA 192→256 / SOFTNESS 16→8 |
| `global/lighting/shadowmap.glsl` | `shadow_map_fade` 渐变带 (d−16,d−4)→(d−24,d−8)；bias 上限 0.12→0.35（256 距离下圈外 texel 0.5-2.5 块，旧上限过早截断） |

### 诊断工具（新增）
`qa/tools/shadow_frustum_probe.py`：按 distort 公式重现接收端的世界纹素尺寸、PCF 宽度、
自适应 bias 与 map fade，输出距离表。修复前后对比：

| 位置 | 修复前 texel / PCF 宽 | 修复后 texel / PCF 宽 |
|---|---|---|
| 25.6 块（内区边） | 0.081 / 0.32 | 0.090 / 0.18 |
| 64 块 | 0.225 / 0.90 | 0.264 / 0.53 |
| 96 块 | 0.400 / 1.60 | 0.479 / 0.96 |
| 112 块 | 0.506 / 2.03 | 0.609 / 1.22 |
| 124-128 块 | fade 0→影消失 | 正常阴影（fade 移至 240-252） |

interval 跨格步进：修复前 96-128 块处 0.4-0.6 块/跳（肉眼可见）；修复后 0.24-0.34 块/跳（约 4 倍改善）。

## 3. 修复项 B：水上水体颜色（浅滩青绿 / 深水蓝）

- `global/water/absorption.glsl` `water_surface_absorption` 三档改为 Steadfast 单指数口径（每格系数 = (16,3,1)/16）：
  - BALANCED `(0.26,0.022,0.026)` → `(1.0, 0.1875, 0.0625)`
  - COLD → `(1.0, 0.3125, 0.0625)`（Steadfast COLD (16,5,1)/16）
  - TROPICAL → `(2.0, 0.125, 0.03125)`（Steadfast TROPICAL (32,2,0.5)/16）
  1 米透射 ≈ (0.37, 0.83, 0.94)（青绿浅滩），16 米 ≈ (0, 0.05, 0.37)（深蓝）。
  旧值红色保留过多（1 米 0.77）读作灰蓝。
- `global/water/optics.glsl` `water_sun_focus`：`0.12 + 6.0*crest²` → `1.0 + 6.0*crest²`。
  旧基准 E[focus]≈0.62 < 1，把床面直射光（caustics 乘数 (focus−1) 平均 −0.38）和
  光柱源平均压暗；新基准使均值 ≈1.5，仅保留窄亮脊的 6 倍增益。

## 4. 修复项 C：随视角上下移动的断层

- `global/water/refraction.glsl`：4 步不动点投影重写为**单跳投影**（Steadfast 方案）：
  取当前像素深度 → `travel = clamp(|sceneZ − viewPos.z|, 0, maxDistance)` → 投影一次；
  屏幕外 10% 淡出（混回原 UV）。旧式的每 texel 深度平面在 1 格台阶处 travel 跳
  Δh/sin(pitch)（俯仰越低越大），4 步迭代可跳到台阶另一侧，即俯仰滑动的断层线。
- `program/water.glsl`：`refract_trace(..., 96.0)` → `32.0`（匹配 Steadfast 的 32 米上限）。
- `lib/settings.glsl` + `shaders.properties` 三档：REFRACTION_STRENGTH 100→60
  （保留物理 Snell 方向的 60%，40% 与入射混合，避免块状地形被 1.5 倍放大错位）。
- `water_sample_path` 的 ±0.02 侧带与回退到未偏移光路的机制保持（SC-35 已定）。

## 5. 修复项 D：水下阳光感

- `program/scene.glsl` 新增自写 `water_sun_glare(direction)`：
  `exp(-(1−VoL)*6)`（窄峰）× `daylight × (1−rainStrength)`；Nether/End 返回 0
  （`astra_direct_light` 仅 Overworld 定义，须宏保护，首次编译即发现此问题）。
  常量 `WATER_SUN_GLARE_BOOST = 2.5`。
- 接入 `astra_underwater_color`（雾色目标）与 `astra_apply_medium` 水下分支的
  `water_medium` 入射光：`incident = astra_water_incident(eyeSky) + astra_direct_light()*glare*BOOST`。
  对应 Solas 目标"雾色朝太阳最多 ~16.8x"（数值目标，公式自写）。
- `global/water/optics.glsl` `water_phase`：g=0.60→0.40（各向异性 25x→9x；
  旧 g 使正午看水底/平视的相位低到 0.03，光柱几乎归零）。
- `global/water/light_shafts.glsl` 新增 `WATER_SHAFT_GAIN = 2.0`，
  `water_shafts_resolve` 乘上；`UNDERWATER_SHAFT_STRENGTH` 默认 100→150（settings + 三档 profile）。
  对应 Solas"VL 水下 4~12x"的保守下限。
- 不动：水下雾密度曲线（`fog.glsl:106-107` 保持 0.06）、UNDERWATER_SHAFT_SAMPLES、
  bloom 管线顺序（SC-34-F1 像素精确契约禁止光柱进 bloom 平滑）。

## 6. 验证

- 驱动编译（RTX 4050 / NVIDIA 572.83 / OpenGL 4.6，独立上下文）：
  - BALANCED `qa/glsl-shadow-water-fix-balanced.log`：linked=76 failed=0
  - PERFORMANCE `qa/glsl-shadow-water-fix-performance.log`：linked=76 failed=0
  - ULTRA `qa/glsl-shadow-water-fix-ultra.log`：linked=76 failed=0
  - 首轮编译在 Nether/End 失败（`astra_direct_light` 未定义），已加维度宏保护后全绿。
- `check_pack.py`：0 FAIL / 9 PASS / 2 WARN（既有 VOXY_SUPPORT 等，非本轮）。
- `shadow_frustum_probe.py` 数值表见第 2 节。

## 7. 待用户实测（不宣称视觉通过）

与视觉裁决约定一致：离线编译/数值验证 ≠ 视觉通过。复测方法：

1. 阴影：`/time set noon` + `/weather clear`，固定视角；原地截图 A → 右移 2 格截图 B
   → 移 8 格回原位截图 C；比较同树影（B 查 interval 跳变，C 查回归）。
   圈内 <20 块与圈外 60-200 块各一树。
2. 水色/断层：原四张机位复拍；俯仰扫 −10°~−45° 确认断层不随视角移动。
3. 水下：原图 3 机位复拍（亮蓝、朝太阳方向光柱、床面光斑）；对照图 2。

备选微调参数（如需第二轮）：REFRACTION_STRENGTH 60→40；focus crest 6.0→5.0；
WATER_SHAFT_GAIN 2.0→3.0；WATER_SUN_GLARE_BOOST 2.5→5.0；
水色 BALANCED (1.0,0.1875,0.0625)→(1.2,0.24,0.08) 区间内。
