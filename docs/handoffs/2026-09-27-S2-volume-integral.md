# S2 体积散射与透射积分模块 —— 交接记录

- 状态：已完成（模块代码完成；H3 的步进 / 缓冲 / 透明层 / 旧雾整合未完成，见「主任务待接入」）
- 认领 / 完成：ZCode 会话，2026-09-27
- 对应父项：H3 主世界体积雾；提示词见 [agent-task-prompts](../archive/2026-09-27-agent-task-prompts.md)
- 实际改动路径：新增 `Astra/shaders/lib/volume_integral.glsl`（唯一新增文件，未改动任何现有文件）

## 最终签名（与提示词一致，未改名）

```glsl
vec4 astra_volume_identity();
vec4 astra_volume_segment(vec3 sourcePerLength, float extinctionPerLength, float distanceBlocks);
vec4 astra_volume_compose(vec4 nearSegment, vec4 farSegment);
vec3 astra_volume_apply(vec3 background, vec4 volume);
```

无 sampler / image / uniform / 帧状态依赖，include guard 为 `ASTRA_LIB_VOLUME_INTEGRAL_GLSL`。

## 段表示与单位

- 一段介质用 vec4：`.rgb = S`（到达该段近端的积分散射辐亮度），`.a = T`（整段透射比，落在 [0,1]）。
- 空段 = S=0、T=1 = `astra_volume_identity()`。**不是** alpha=不透明度的约定。
- `distanceBlocks`：格（blocks）；`extinctionPerLength`：每格；`sourcePerLength`：每格的散射源项（辐亮度/格）。

## 源项约定（关键，接入时不要重复乘）

`sourcePerLength` 是「调用方已经乘入散射系数与入射光 / 相位加权辐亮度」的每单位长度源项。
本模块只把它乘以一个**积分长度**，不会再乘一次密度。接入步进时传入 `scatteringCoefficient * phaseWeightedIncidentRadiance`；步长只通过 `distanceBlocks` 传入，不预先乘进源项。若密度已经包含在散射系数中，也不重复乘入。

## 公式与稳定性契约

均匀段（长度 L、消光 sigma、源项 J）：

- `T = exp(-sigma * L)`
- `S = ∫₀^L J·exp(-sigma·s) ds = J·(1 - exp(-sigma·L)) / sigma`

解析行为（写入模块注释，供接入依赖）：

- L=0 → S=0、T=1（恒等段）。
- J=0 → S=0、T 不变（纯吸收仍会经由 `apply` 压暗背景）。
- sigma=0、J≠0 → S=J·L、T=1。极限按解析式取，**没有**把 sigma 钳到 epsilon；因此零消光但源项非零的段不会被硬加上消光底。
- 极大光学厚度 → T→0、S→J/sigma，均有限；T 恒在 [0,1]。
- 小光学厚度：令 `tau = sigma*L`，用 `f(tau) = (1-exp(-tau))/tau`，tau < 1e-3 时改用泰勒式 `1 - tau/2 + tau²/6`，避免 `1-exp(-tau)` 的消减损失；tau=0 时精确为 1。

退化输入（温和处理，已写入注释）：

- 负 `distanceBlocks` → 钳为 0，即恒等段（不反向积分）。
- 负 `extinctionPerLength` → 钳为 0，不衰减也不放大（T 不会 >1）。
- `sourcePerLength` 不钳制、不改写（预期非负，钳制会掩盖调用方错误）。

## 组合顺序

`astra_volume_compose(near, far)`：`S = S_near + T_near*S_far`，`T = T_near*T_far`。
近端段（观察者一侧）先传；远端散射被近端衰减，近端散射不被远端衰减。传入顺序反过来会错误地压暗前段。
最终合成 `astra_volume_apply(background, volume) = background * T + S`，散射只加一次。

## 验证

- 数值自检（awk，非工程运行工具）：分段公式 vs 高阶泰勒参考，tau∈[0,1e6] 上 f 的最大相对误差 4.2e-11；tau=0 精确得 S=J·L；极大 tau 输出有限且 T∈[0,1]。
- compose 顺序与「近段→远段」的 40 万步数值二重积分对比，S 偏差 6.2e-12（相对 ~1.6e-12），确认顺序正确。
- 工程内未安装 GLSL 校验器（glslangValidator / glslc 均不在 PATH 与仓库内），语法由人工复核；调用方接入编译时才可获得真正编译证据。

## 主任务待接入（本任务未做，均不在白名单内）

1. H3 的射线步进本身：采样高度密度、地形阴影、云影、日月 / 天空入射，为每段算出 `sourcePerLength` 与 `extinctionPerLength`。模块不含噪声、密度场、阴影、云影、深度重建或相位函数。
2. 散射 / 透射缓冲（colortex）与分辨率选择；未引入任何新缓冲。
3. 透明层、水面与云的介质前后顺序，以及与世界距离雾（`fog_v2`）、`nether_volume.glsl` 单次散射合成、水下介质的整合，避免重复消光。
4. 现有雾的消光与 GODRAYS / rainy_air 重复散射的合并；设置开关与默认值；`settings.glsl` / `uniforms.glsl` / 阶段入口。
5. colortex4 继续承担未施加观察介质的场景，接入时不要重复消光。


## 主任务源码复核补正（2026-09-27）

已修正大光学厚度下的计算路径。原实现所有非小量情况都算 `L * ((1-exp(-tau))/tau)`；有限的 sigma 与 L 乘积若溢出，会把积分长度算成零，丢掉应保留的 `1/sigma` 极限。现在仅小 tau 使用级数，其余路径直接采用 `(1-T)/sigma`，并在零长度时立即返回恒等段。透射只计算一次。

接口限定输入为有限数、所需输出在浮点范围内；不承诺任意无限源项也能得到有限颜色。交接中的源项示例已移除含义不清的 `stepWeight`，避免主任务再乘一遍步长。S2 模块可供接入，H3 整体仍未实现。
