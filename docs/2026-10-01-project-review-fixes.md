# 2026-10-01 项目源码审查与修复

本轮围绕主世界、下界和末地的渲染入口、共享光照与介质模块、独立历史、资源引用、材质映射及设置配置展开。修改依据为当前工作区源码；游戏中的最终画面、帧率和驱动兼容性尚未确认。

## 已修复的问题

| 问题 | 修复及源码位置 |
|---|---|
| 平面云历史把普通颜色当成预乘颜色 | `program/cloud_screen.fsh` 将颜色乘覆盖率后交给历史模块；当前帧输出和历史输出统一使用预乘语义。 |
| 平面云重投影缺少前帧 TAA 抖动 | `global/atmosphere/cloud_temporal.glsl` 将前帧抖动加回云缓存所在的场景网格。 |
| 下界颜色历史缺少浮点格式声明 | `program/nether_reflection.fsh` 明确声明 `colortex9Format=RGBA16F`，不依赖只在末地入口存在的声明。 |
| 反射历史深度转换使用了错误的区间 | `lib/effect_history.glsl` 先将深度从 `[0,1]` 转成 NDC `[-1,1]`，再求相对远平面的线性视深；帧状态标记同步升至 4。 |
| 下界反射先插值法线、深度，再判断历史归属 | `program/nether_reflection.fsh` 分别读取四个贡献纹素的颜色及元数据，按各自法线、深度计算历史权重；无效贡献保留当前帧颜色和覆盖率。 |
| 水下光束先插值射线长度，可能形成虚构的中间长度 | `global/water/shaft_history.glsl` 逐纹素判断长度差，拒绝非有限数据和无效投影；缺失历史不重新归一化为完整覆盖。 |
| AO 的方向性天光替换重复乘入 SH 亮度 | `global/lighting/diffuse.glsl` 将 `directionalCoef` 改为天光的材质及访问系数，供 `ao_resolve.glsl` 乘一次方向响应差。 |
| 体积雾接口重复乘散射的透明度 | `program/scene.glsl` 把已积分的散射转换成普通雾色后返回，使接口调用的 `mix` 与 `scene*T+S` 一致。 |
| 体积雾的渲染距离边界只改变 T，导致趋向黑色 | `global/atmosphere/volume_fog.glsl` 新增 `astra_volume_border`，同时合成边界散射和透射；缓冲场景与透明介质查询共用该函数。 |
| 水下界面反射视角响应被钳在 0.5 | `program/water.glsl` 使用相机朝向法线计算 Fresnel 近似，移除错误的法线取反。 |
| 水面反射足迹在材质分支和片元丢弃之后求导 | `program/lit.fsh` 提前求反射方向的屏幕导数，再将足迹传入 `astra_water`。 |
| 末地反射及介质查询在分支内对天空方向求导 | `global/dimension/end_blackhole.glsl` 为原生非缓冲查询使用投影及视口推导的角足迹；全屏末地天空继续使用提前计算的真实方向导数。 |
| 下界 SSR 第一段与后续射线使用不同起点 | `global/dimension/nether_reflection.glsl` 从偏移后的 `start` 开始第一段，保持整条追踪路径连续。 |
| Darkness 在末地和水下光束中重复叠加 | `global/dimension/end.glsl`、`program/deferred.fsh`、`global/water/light_shafts.glsl` 移除局部 Darkness 衰减，由 `program/display.fsh` 对完整画面统一处理；Blindness 保留其介质路径。 |
| 未点亮火把和营火被体素光当作实心方块 | `block.properties` 新增 `10033`；`program/lit.vsh` 映射为无发光普通材质，`program/shadow.vsh` 将该身份写成非实心、无发光体素。 |

## 范围与边界

设置配置的四个预设均有显式选项覆盖，中英文标签及自定义纹理引用未发现缺项；着色器 include 引用未发现悬空路径。

反射仍受屏幕空间可见信息限制；光束历史的中点代表位置仍是体积近似。末地非缓冲天空查询的角足迹使用投影估计，不含波浪对反射方向的额外放大。水面反射足迹在雨滴扰动之前计算，雨滴细节仍由原有涟漪过滤处理。

Voxy 的适配骨架、实体运动历史及已经退役的水面历史链，仍按项目现有功能边界记录。本轮修复不将这些未完成功能改写为已实现。

## 同日继续审查与修复

继续审查当前工作区的渲染调度、几何输出、独立历史、反射滤波、体积介质、材质身份及末地数值边界。本节记录后续改动，与上面的修复累积生效。

| 问题 | 修复及源码位置 |
|---|---|
| 体积雾把手持物压缩深度当作普通地形深度 | `program/volume_main.fsh` 不再把手持物写入地形体积缓存；`program/deferred.fsh` 对手持物按已还原的端点单独积分，`global/atmosphere/volume_fog.glsl` 排除邻域手持物样本，避免它影响背景雾。 |
| 水面反射的空气段丢失界面起点 | 体积雾新增带起点的步进核心及 `astra_volume_path_medium(start, finish)`；`program/water.glsl` 从真实界面到反射代表端点查询密度与云影，而非把相同长度的空气移到相机位置。失明仍走原介质分支。 |
| 下界反射空间滤波先混合材质、法线和颜色，再判断是否同一表面 | `program/nether_reflection_resolve.fsh` 对每个双线性贡献纹素分别读取材质、深度、法线、颜色和覆盖率，通过表面判断后再累积，避免岩石与前景边缘之间产生虚构的匹配。 |
| 云历史保存了代表距离，却未用于历史匹配 | `global/atmosphere/cloud_temporal.glsl` 逐纹素比较历史代表距离与重投影特征距离，检查有效性、时间和视口标记，并以有效覆盖率限制历史权重；大幅相机位移直接使用当前云。 |
| 云历史半精度秒数标记在高帧率下可能舍入到当前时间之后 | 同一模块改用半精度可精确保存的模 2048 帧序号判断连续性，以 Iris `frameTime` 重建风位移，不再以量化秒数相减决定历史年龄。 |
| 原版云几何没有写入 TAA 动态标记 | `program/clouds.fsh` 写入 `colortex16`；`shaders.properties` 为该附件关闭颜色混合，原版云的可见区域按当前帧处理。 |
| 完整发光方块被体素捕获标记为非实心 | `block.properties` 将完整不透明发光方块分入 `10034..10040` 对应颜色组；`program/lit.vsh` 保持其发光材质，`program/shadow.vsh` 保留体素实心位。发光单元向邻近空气提供自身光，但不再传递其他光源穿过该方块。 |
| 离水海泡菜被归为发光材质 | `block.properties` 仅将 `waterlogged=true` 归入发光组；离水形态进入无发光、非实心组。 |
| 未充能重生锚被归为发光材质 | `block.properties` 仅将 `charges=1..4` 的状态归入发光组；零充能状态保留普通实心材质。 |
| 水下 Bloom 已改为线性 HDR，目标仍用归一化 RGBA16 | `lib/water_buffer_formats.glsl` 将 `colortex7` 改为 `R11F_G11F_B10F`，与当前捕获及合成的 RGB 语义一致，保留超过 1 的亮度；每纹素由 8 字节降为 4 字节。 |
| AO bent normal 的加权方向可能相消 | `lib/ao_resolve.glsl` 在归一化前判断方向长度，退化时使用几何法线。 |
| 末地星空在极点计算 `atan(0,0)` | `global/dimension/end_system.glsl` 为极点提供确定的经度，避免未定义角度参与星体索引。 |

本次新增材质组沿用既有七种体素光颜色及增益，未新增菜单选项或渲染阶段。水下 Bloom 格式变更同时适用于所有读取该目标的显示分支。清除了 `shaders.properties` 中已退役水历史留下的空条件块。

这些结论来自源码审查。当前游戏画面、帧时及驱动编译结果尚未确认。下界反射每个滤波足迹最多分别处理四个纹素，实际开销需要游戏运行数据支持；水面反射空气段仍以滤波后的代表端点积分，云仍采用单个代表位置，二者保留已有近似。Voxy、实体运动历史和退役水面历史链的未完成范围不变。
