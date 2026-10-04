# S4 植被显式时间形变接口 —— 交接记录

- 状态：S4 代码完成；主任务已接入植被历史形变与 TAA 消费，见文末续记
- 认领：ZCode 会话，2026-09-27
- 对应父项：T3 动态累积增强；提示词见 [agent-task-prompts](../archive/2026-09-27-agent-task-prompts.md)
- 实际改动：`Astra/shaders/global/lighting/wind.glsl`（仅此一个源文件；本记录本身）
- 未改动：`program/lit.vsh`、`program/shadow.vsh`、uniforms、历史缓冲、TAA 遮罩、`shaders.properties`

## 最终接口（`global/lighting/wind.glsl`）

```glsl
// 显式求值：输入未形变世界位置，返回世界轴向位移，不写回输入。
vec3 astra_foliage_displacement(
    vec3 undeformedWorldPosition,  // 未形变的绝对世界位置（pristine，形变前）
    float timeSeconds,             // 秒（与 frameTimeCounter 同单位）
    float rainAmount,              // 沿用 rainStrength 语义，通常 [0,1]
    float strengthScale,           // 1.0 == 100%；不再读取强度选项
    bool isLeaves,
    bool isGroundFoliage,
    bool topOfFoliage
);

// 显式核心：只做 形状 × 雨量 × 强度，所有帧状态由参数给出，不读 uniform。
vec3 astra_wind_wave(vec3 pos, float wind, float rainAmount, float strengthScale);

// 兼容入口（保留旧签名），仅用于当前帧，内部读 frameTimeCounter / rainStrength。
vec3 wind_wave(vec3 pos, float waveSpeed);

// 包装入口，签名与 S4 之前完全一致，调用方无需改动。
void wave_foliage(bool isLeaves, bool isGroundFoliage, bool topOfFoliage, inout vec3 playerPos);
```

- `astra_wind_wave` 与 `astra_foliage_displacement` 内部不读取 `frameTimeCounter`、`cameraPosition`、`rainStrength`；它们只依赖显式参数及形状常量，不读取 `WAVING_FOLIAGE_STRENGTH`。仅 `wind_wave`（兼容）与 `wave_foliage`（当前帧包装）读 uniform。
- `wind_wave_shape(vec3 pos, float wind)` 未改，仍是纯函数。
- 所有艺术常量逐字保留：170.0 时间缩放、叶片空间 `vec3(0.75,0.375,0.75)` 与 `vec3(4,3,8)`、草 `y*0.5` 与 `(3, 0, 8)`、根部锚定 `wave.y=0`、`*0.1`、雨量 `(1.0 + 0.5*rainAmount)`。来源 / 许可声明（Complementary r5.9 转写、许可未决）保留。

## 输入单位

| 参数 | 单位 / 范围 | 说明 |
|---|---|---|
| `undeformedWorldPosition` | 方块，绝对世界坐标 | 与 `playerPos + cameraPosition` 同空间；必须是形变前位置 |
| `timeSeconds` | 秒 | 与 `frameTimeCounter` 直接可比；接口内部乘 170.0 |
| `rainAmount` | 无量纲，沿用 `rainStrength`，通常 [0,1] | 幅度系数 `(1.0 + 0.5*rainAmount)` |
| `strengthScale` | 标量，1.0 = 当前 100% | 最终强度由 `strengthScale` 独立决定；当前帧包装函数传入 `WAVING_FOLIAGE_STRENGTH * 0.01` |
| 三个 bool | 分类 | 与现有 `lit.vsh:128-129`、`shadow.vsh:90-96` 解码一致 |

零位移语义：分类不通过（非植被、或草未“顶部”）返回 `vec3(0.0)`；显式接口在 `strengthScale=0` 时为零；当前帧包装函数在 `WAVING_FOLIAGE_STRENGTH=0` 时传入零。判定优先级与原来一致：`isLeaves` 为真时走叶片分支。

## 包装函数怎样传参

```glsl
void wave_foliage(bool isLeaves, bool isGroundFoliage, bool topOfFoliage, inout vec3 playerPos) {
    vec3 undeformedWorldPos = playerPos + cameraPosition;   // camera-relative -> 绝对世界
    playerPos += astra_foliage_displacement(
        undeformedWorldPos,
        frameTimeCounter,   // 已是秒
        rainStrength,
        WAVING_FOLIAGE_STRENGTH * 0.01, // 当前选项转换一次
        isLeaves, isGroundFoliage, topOfFoliage);
}
```

现行调用链（均未改动）：`program/lit.vsh:130` 与 `program/shadow.vsh:110` → `wave_foliage` → `astra_foliage_displacement` → `astra_wind_wave` → `wind_wave_shape`。主视图与阴影继续共用同一算法。

## 主任务必须补齐的数据（本次未做）

1. **未形变世界位置**：`lit.vsh` 里 `playerPos` 在调用 `wave_foliage` 之前已被雨水帘（`lit.vsh:101-126`，`ASTRA_WEATHER`）等改动过；若要做历史重投影，主任务需在植被形变前保存一份 pristine 世界位置（绝对或 camera-relative 均可，接口要绝对世界）。
2. **前帧时间**：真实上一帧的秒值，不能用「当前时间 − 固定帧长」冒充；S4 未新增 uniform，后续状态载体由主任务选择。
3. **前帧雨量**：上一帧 `rainStrength`（或接受当前雨量近似时明确说明）。
4. **分类与顶点同一性**：前帧求值必须用同一顶点的同一组 `isLeaves / isGroundFoliage / topOfFoliage`；`topOfFoliage` 依赖 `at_midBlock`，主任务需保证历史侧同源。
5. **TAA 运动链**：把（当前顶点 − 用前帧参数对同一未形变位置求出的前帧顶点）作为植被运动矢量接入；在此之前不要取消 TAA 的植被 reactive 标记。
6. **限制**：本接口只覆盖风的水平/竖直位移形状，不含雨水帘、实体、水、云的运动。

## 验证与缺口

- 语法级检查：`wind.glsl` 花括号/圆括号配平；无重复符号；`lit.vsh`/`shadow.vsh` 调用签名未变，无需编辑。
- 未运行 GLSL 编译器，未进入游戏取帧，因此没有画面/帧时间证据；不声称效果或性能已改善。
- 未新增 uniform、未新增设置、未改默认画质参数。


## 主任务源码复核补正（2026-09-27）

已修正显式强度语义：原 `astra_wind_wave` 把传入的 `strengthScale` 再乘一次全局强度。若选项为 50%，调用方按接口传入 0.5，会得到 25% 而非 50%。现在显式核心只消费传入比例；兼容 `wind_wave` 与 `wave_foliage` 两个当前帧入口负责将选项百分比转换一次。现有可见植被和阴影仍获得原来的当前帧强度。

补正后的接口可供后续运动链消费。前帧参数保存、未形变位置传递、历史投影和 TAA 遮罩调整仍未完成；本次没有开放植被历史累积。


## 主任务接入续记（2026-09-27）

上文未接线说明仅对应 S4 交付时刻。当前 `program/taa_state.fsh` 在 colortex17 版本 2 中保存真实前帧时间、雨量及强度比例；`program/lit.vsh` 在当前形变之前用同一世界顶点求前帧形变。`lit.fsh` 写入 colortex22 的 UV 位移、预期对数深度及有效性，`taa_resolve.fsh` 已消费；仅在有效时开放植被历史，保留原历史拒绝和邻域约束。实体、水和云仍未完成。当前与阴影的形变包装入口保持原语义；没有本轮游戏画面或帧时记录。完整布局和剩余 R4–R6 见持续待办第 6 节。
