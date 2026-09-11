# 下界与性能优化接续

用户分工：本轮负责下界与性能，雨天、黑洞由另一个 Agent 负责。未改水体、主世界阴影参数和末地实现。

## 源码阅读与采用范围

- Complementary Reimagined r5.9：`lib/common.glsl` 的五群系调色板、`lib/colors/lightAndAmbientColors.glsl`、`lib/lighting/mainLighting.glsl`、`lib/atmospherics/fog/mainFog.glsl`。保留原环境照明和两次方向平方，统一雾/天空与环境色输入；不是再给整屏加曝光。
- Bliss：`_analysis/latest-2026-09-10/bliss-shader/shaders/lib/nether_fog.glsl`。保留世界空间烟柱、侵蚀噪声、高度分层和 16 点指数采样。顶层烟雾采用群系色，避免统一白幕削弱群系差异。
- Solas：`programs/shadowcomp.glsl`、`lib/vx/voxelization.glsl`、`lib/lighting/gbuffersLighting.glsl`。保留已修复的“清空即空气”、实体阻挡和熔岩向外发光；按参考把体素光用于方块光混合，手持光独立加入，发光表面不再被自身方块光重复照亮。
- Steadfast 0.8.0：`program/post/copy_and_fog.fsh`、`environment/fog.glsl`、`shaders.properties`。采用按消费者启用程序、消除重复数据读取的方向。本轮没有复制其水体/天空代码，避免干扰另一任务及现有水体。
- Mellow 3.4：`global/atmosphere/fog.glsl`、`shaders.properties`。参考维度分支、无消费者关闭整段程序和直接运算的思路，不引入额外时域依赖。
- ITT 3.2：`Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl` 和 shaders.properties。参考有界距离/步数；不复制 LUT 或时间蓝噪声。此前文档把外部 33 MiB 3D 大气数据及 2.0 倍缓冲解释为廉价半分辨率 LUT，不据此决策。

## 实现

1. `nether.glsl`：雾/天空不再单独对 Complementary 调色板做 sRGB 解码。原照明直接使用调色板，但雾独自解码，同一群系的红色 0.4 会在雾侧变成约 0.133，造成远景暗层；现在共享同一输入。
2. 彩色光移到方块光组合阶段，不再加在最终 diffuse 后。采用 Solas 的 0.95 混合上限；Astra 只有八格传播，因此用实际体素亮度作可用度渐变，未覆盖的光源仍保留普通方块光。这是明确的 Astra 适配，不声称与 Solas 全尺寸体积一致。
3. `nether_volume.glsl`：保留 Bliss 烟柱结构，白色顶层改为群系照明色；增加零长度射线返回恒等透射；指数采样点用代数递推，样点数、噪声场、步进范围保持原定义。
4. `nether_light.csh`：邻居只读取光场。非发光实体在 step 0 为零，后续又不接收传播，所以每次重读其材质并跳过，与读取其零光值后取 max 完全等价。熔岩等实体光源仍有自身光值，能正常向外传播。
5. `shaders.properties`：下界 shadow 程序跟随 NETHER_VOXEL_LIGHT；关闭体素光时，下界没有阴影纹理消费者，故无需继续绘制投射体。主世界和末地 shadow 条件未改。
6. 更新过期的帧戳注释，以及体素模型的实际快速路径；增加逐格逐 pass 与原邻居读取路径的比较。

## 数值与性能边界

- 16 个 Bliss 样点、五种 dither、float32 递推与原 pow 表达式最大归一化距离差约 1.02e-7；192 格内位置差小于 0.000020 格。不是用降低样本数换速度。
- 体素原路径每个可传播单元每步最多 6 次邻居材质读取 + 6 次光场读取；改后去掉前者。64³、八次传播理论上限少 12,582,912 次纹理读取/帧，实际取决于实体比例与边界。不能直接换算成 FPS。
- 普通实体保持零光、不穿透；熔岩仍发光；step 0 必须先重建全体积，不能省略，否则上帧残留将破坏上述等价性。
- 体素捕获来自实际提交的几何，并不拥有区块加载图。零值表示空气或未捕获区域，不能声称它能区分未加载区块。没有重引入错误帧戳来掩盖这一限制。
- 仍为 64³、八次传播、三档配置、无 TAA。没有更改硬件 PCF、阴影距离倍数或稳定间隔；这些需要独立证据。

## 状态

渲染入口编译 261 linked / 0 failed（compute 27）；静态校验 0 FAIL / 1 WARN / 10 PASS，WARN 为原有 Voxy 接口占位。关闭态、体素模型与实例同步结果在本轮 session-log 记录。所有视觉改善仍需用户游戏画面确认；编译和数值结果不替代视觉结论。
