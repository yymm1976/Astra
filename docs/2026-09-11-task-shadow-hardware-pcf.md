# 任务：阴影采样改硬件 PCF（可选路径）+ 数值等价性回归测试

**规模**：中等。**风险**：低（默认不改变行为）。**无需实机即可验收。**

---

## 一、要解决的问题

Astra 现在的阴影过滤是**纯软件的双线性**，代价极高：

- `global/lighting/shadowmap.glsl:106-118` 的 `shadow_filter_uv()` 用 **4 个波瓣 × 4 个角 = 16 次**
  循环，每次手工算双线性权重（`mix(1-f, f, c)`）。
- `shadow_read_tap()` 每次抽头要取 **3 张纹理**：`shadowtex0`、`shadowtex1`、`shadowcolor0`。
- 合计 **每个受影像素 48 次 `texelFetch`**。
- 只有 `COLORED_SHADOWS` 打开时才会用到 `shadowcolor0` 的 gba，但取样是无条件的。

对比：
- **Steadfast** `environment/lighting/shadowmap.glsl:64-82`：`shadowHardwareFiltering0/1 = true`
  + `sampler2DShadow`，**4 次抽头**，每次由硬件做 2×2 PCF，注释自述
  *"Make 4 taps on the shadowmap, where each tap is itself a hardware accelerated 2x2 PCF tap,
  ending up with sampling up to 16 different texels"*。
- **Mellow** `lib/all_the_uniforms.glsl:61-62` + `global/configurations.glsl:17`
  （`shadowHardwareFiltering = true`）+ `global/lighting/shadows.glsl:22-52`：同样 4/8 次抽头。

Astra 目前 `lib/settings.glsl:230` 是 `const bool shadowHardwareFiltering = false;`，
且 `shadowmap.glsl:37-38` 把两张图都声明为 `sampler2D`。**这是我们最大的一笔性能欠账。**

## 二、交付物（关键：**必须做成可选路径，默认不变**）

**必须新增一个选项，默认保持现有的软件路径。** 理由：硬件 PCF 是"比较后过滤"，
软件路径是"过滤可见性"，两者结果**不完全相同**（硬件更干净、更软）。
在无法实机对拍的前提下，不能改变默认行为。

```glsl
// lib/settings.glsl
// 0 = software bilinear (16 texelFetch, current behaviour, default)
// 1 = hardware PCF (4 comparison taps, needs shadowHardwareFiltering + sampler2DShadow)
#define SHADOW_FILTER_MODE 0 // [0 1]
```

选项要按仓库惯例接齐：`settings.glsl` 的枚举表、`shaders.properties` 的 `screen.SHADOWS`、
三档 `profile.*`、`lang/zh_CN.lang` 与 `en_US.lang` 的 `option.*` / `comment.*` / `value.*`。
`check_pack` 会逐项校验，漏一处就 FAIL。

## 三、要改的文件

| 文件 | 改动 |
|---|---|
| `lib/settings.glsl` | 新增 `SHADOW_FILTER_MODE`；`shadowHardwareFiltering` 需按模式给出 true/false |
| `global/lighting/shadowmap.glsl` | 采样器声明按模式切换 `sampler2D` / `sampler2DShadow`；`shadow_filter_uv` 与 `shadow_read_tap` 分模式实现；`shadow_opaque_visibility`（:89-105）也要处理 |
| `global/water/light_shafts.glsl` | 它用 `texture(shadowtex1, pos.xy).r` 取深度（:88 附近）—— `sampler2DShadow` 下 **不能** `texelFetch`，必须改成比较采样 |
| `shaders.properties` / 三档 profile / 两个 lang | 接选项 |

## 四、必须处理的两个坑

1. **`sampler2DShadow` 不能 `texelFetch`**。`shadow_opaque_visibility()` 现在用
   `texelFetch(shadowtex1, pixel, 0).r` 做 2×2 手工双线性。切换后必须改为
   `texture(shadowtex1, vec3(uv, shadowPos.z))` 逐点比较，让硬件做过滤。
   **注意**：函数的契约是"过滤可见性、绝不过滤原始深度"（注释已说明，防止整列光柱被一个纹素切换），
   硬件 PCF 天然满足这一点，但要在注释里确认。
2. **`shadowcolor0` 保持 `sampler2D`**，且**只在需要时取**。它给水体染色和焦散用，
   与深度过滤无关。如果 `COLORED_SHADOWS` 关闭且不在水里，应当能完全跳过这 16 次取样
   （现在是无条件取的）—— 这一条本身就是一项独立收益。

## 五、验收标准（全部离线可验，不需要游戏）

1. **`python qa/tools/compile_glsl.py` → `failed=0`**，且 compute 数不变（27）。
2. **`python qa/tools/check_pack.py` → `0 FAIL`**（可保留既有的 1 个 Voxy WARN）。
3. **两条路径都要编译**：`--undef` 关掉新选项跑一次，确认默认路径未被破坏。
4. **新增一个数值回归工具** `qa/tools/shadow_filter_equiv.py`，要求：
   - 造一个合成的阴影图深度场（含硬边、斜面、随机噪声三种图案）
   - 用 Python 独立实现**两条**过滤路径：
     - 路径 0：现有的 4 波瓣 × 4 角软件双线性
     - 路径 1：硬件 PCF（2×2 比较后线性过滤，即对 4 个纹素各做 `step` 再按双线性加权）
   - 对同一批接收点，输出两者的可见度分布（p10/p50/p90/均值）与**最大绝对差**
   - **判定**：路径 1 的均值与路径 0 的差应在一个明确容差内（建议 ±0.03），
     且路径 1 的标准差应**不大于**路径 0（硬件 PCF 更平滑），否则报 FAIL
   - 工具要能一键运行、退出码非 0 表示不通过，并写进 `qa/session-log.md`
5. 更新 `qa/session-log.md` 与 `docs/2026-09-11-full-audit-and-optimization-plan.md` 第七节的状态表。

## 六、明确不要做的

- **不要把默认值改成硬件 PCF。** 默认必须是 0，保持现有画面。
- **不要顺手改阴影的其他参数**（`SHADOW_SOFTNESS`、分辨率、距离、`shadowDistanceRenderMul`）。
- **不要动 `shadow_map_position()` 的扭曲逻辑**（`SHADOW_DISTORT_FACTOR`）——
  那是另一套机制，混在一起会无法定位问题。
- 不要引入新的缓冲或新 pass。

## 七、参考实现（可直接对照，但**不要复制资产**）

- Steadfast：`_analysis/Steadfast-0.8.0/shaders/environment/lighting/shadowmap.glsl:28-29, 64-82`；
  `shaders.properties:70-79`（它明确不做多级阴影 cascade 的理由）
- Mellow：`_analysis/Mellow Shader v3.4/shaders/lib/all_the_uniforms.glsl:61-62`；
  `global/configurations.glsl:17`；`global/lighting/shadows.glsl:22-52`

**授权边界**：只能借鉴**做法**。不得复制任何第三方光影的代码文本或美术资产；
若某段表达式确需照搬，必须按仓库惯例登记进 `Astra/THIRD-PARTY.md`。

## 八、预期收益

| | 现状 | 改后 |
|---|---|---|
| 受影像素的纹理取样 | 16 抽头 × 3 张 = **48 次** | 4 抽头 × 2 张（比较采样）+ 按需的染色 = **8～9 次** |
| 阴影边缘质量 | 软件双线性 | 硬件 2×2 PCF，更平滑，且天然满足"只过滤可见性"的契约 |

这一项在阴影吃重的场景（大片阴影、水面、体积光）里应有可感收益，
且**因为默认关闭，不会影响你尚未实机确认的那批画面改动**。
