# S3 彩光体素坐标与范围约定集中 —— 交接记录

- 状态：S3 代码完成；B4 布局优化未完成
- 认领：ZCode 会话，2026-09-27
- 对应父项：B4 彩光布局的前置整理；提示词见 [agent-task-prompts](../archive/2026-09-27-agent-task-prompts.md)
- 接续点：已完成。新增 `lib/nether_voxel_grid.glsl` 并接回 `program/shadow.vsh`、`program/nether_light.csh`、`global/dimension/nether_colored_light.glsl`

## 实际改动路径

- 新增 `Astra/shaders/lib/nether_voxel_grid.glsl`：仅常量与坐标 / 边界 / 归一化函数，include guard，不含 sampler / image / uniform。
- `Astra/shaders/program/shadow.vsh`：在原 `#if defined DIMENSION_NETHER && defined NETHER_VOXEL_LIGHT && defined SHADOWS` 块内引入模块（line 34），捕获格与边界改用模块函数（line 56-57）。
- `Astra/shaders/program/nether_light.csh`：引入模块（line 12），传播邻居边界改用模块函数（line 52）。
- `Astra/shaders/global/dimension/nether_colored_light.glsl`：在 guard 内引入模块（line 3），显示采样坐标、边界与归一化改用模块函数（line 14-23）。

## 替换的坐标表达式（原 → 新）

- `shadow.vsh:56` `ivec3(floor(center + fract(cameraPosition) + vec3(32.0)))` → `astra_nether_voxel_cell(center, fract(cameraPosition))`
- `shadow.vsh:57` `any(lessThan(cell,ivec3(0))) || any(greaterThanEqual(cell,ivec3(64)))` → `!astra_nether_voxel_in_bounds(cell)`
- `nether_light.csh:52` 同上式（作用于 `q`）→ `!astra_nether_voxel_in_bounds(q)`
- `nether_colored_light.glsl:14` `playerPos+fract(cameraPosition)+vec3(32.0)` → `astra_nether_voxel_position(playerPos,fract(cameraPosition))`
- `nether_colored_light.glsl:15` `min(min(p.x,p.y),min(p.z,min(64.0-p.x,min(64.0-p.y,64.0-p.z))))` → `astra_nether_voxel_edge(p)`
- `nether_colored_light.glsl:23` `p/64.0` → `astra_nether_voxel_normalized(p)`

## 集中后的常量与接口

```
#define ASTRA_NETHER_VOXEL_SIZE 64               // 每轴格数 / texel 数
#define ASTRA_NETHER_VOXEL_HALF_EXTENT 32.0      // 体积中心到面的格数（中心偏移）
#define ASTRA_NETHER_VOXEL_INV_SIZE (1.0 / 64.0) // 体积索引 -> 归一化采样坐标

vec3  astra_nether_voxel_position(vec3 cameraRelativePosition, vec3 cameraFraction);
ivec3 astra_nether_voxel_cell(vec3 cameraRelativePosition, vec3 cameraFraction);
bool  astra_nether_voxel_in_bounds(ivec3 cell);
float astra_nether_voxel_edge(vec3 voxelPosition);
vec3  astra_nether_voxel_normalized(vec3 voxelPosition);
```

坐标约定（生产者与消费者共用）：`体积世界索引 = camera-relative position + fract(cameraPosition) + vec3(half extent)`。捕获对该连续索引取 `floor` 得整格；传播在整数格上用 `texelFetch`；显示把连续索引乘 `1/64` 交给 LINEAR 采样器。相机小数部分由调用方以参数传入，模块不读取 `cameraPosition`，不新建 uniform。

## 刻意保留的不同单位常数（未替换）

- `shadow.vsh:55` `at_midBlock/64.0`：这是属性单位换算（属性以 1/64 格为单位），不是体积尺寸，保留原样。
- `nether_colored_light.glsl` 法线偏移 `0.65` 与边缘阈值 `1.0`：非尺寸常量，保留在消费者内。
- `nether_light.csh` 中 `0.72` 衰减、`emission` 的颜色分量（如 `0.32` / `0.64`）、编码位（`&255u`、`&256u`）：非尺寸常量，未改。
- `workGroups ivec3(8,8,8)`、`layout(local_size_*)`、`image.* 64 64 64`：外部接口字面量，保持原样。

## 外部尺寸声明（必须与固定尺寸一致，不能由模块推导）

- `shaders.properties`：`image.astraVoxelImage` / `astraLightA` / `astraLightB` 均为 `... 64 64 64`。
- `program/nether_light.csh`：`layout(local_size_x=8,local_size_y=8,local_size_z=8)` 与 `workGroups ivec3(8,8,8)`，8 × 8 = 每轴 64 texel。
- 这些字面量分属外部接口与调度，改体积尺寸必须同步修改它们；仅改 `ASTRA_NETHER_VOXEL_SIZE` 不支持任意尺寸。本次未改这些声明，也未声称支持可调尺寸。

## 未覆盖 / 风险

- 未运行编译或游戏内验证：本任务禁止运行 Python 工具（`qa/tools/compile_glsl.py` 不可用），环境无其他可调用的 GLSL 编译入口；仅做静态替换与 diff 核对。
- 未改 `wind.glsl`（S4 负责）、`shaders.properties`、compute 入口。

## B4 尚未处理的格式 / 存储 / 调度问题

- 格式：`astraVoxelImage` 仍为 R32UI（bit 8 solid + bits 0-7 种类）、`astraLightA/B` 仍为 RGBA16F；无格式压缩。
- 存储：无体积历史 / 时间复用，仍每帧清零、同帧 9 步；无布局压缩或降分辨率。
- 调度：仍为 8×8×8 workGroups × 9 个 compute 阶段、固定 64³、无跨帧或自适应调度。
- 本次仅集中约定，不降低显存、不提高帧率，B4 的布局 / 格式 / 调度优化仍未完成。
