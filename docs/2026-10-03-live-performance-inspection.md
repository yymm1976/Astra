# 10-02 至 10-03：自主实机核查与性能修正

本轮按用户授权直接操作已打开的 Minecraft：进入维度、传送、调整视角和选项、重新加载光影、读取截图与客户端日志。截图保存在 `qa/runtime-feedback-2026-10-02/`，目录日期取本轮开始日期。本记录接续两份 10-02 审查报告及[模块修复说明](2026-10-02-module-performance-refinements.md)。

## 实际环境与加载方式

- Minecraft 26.2，Fabric Loader 0.19.3，Iris 1.11.2+mc26.2，XPlus PerioTable v7.2.8。
- 实例目录为 `D:/zhenhebao/.minecraft/versions/生电优化整合包 (Fabric)`，当前世界为「创造光影」，实际使用 `shaderpacks/Astra` 目录。
- 截图来自 Minecraft 客户区，1920×1081。使用当前正式源码更新实例目录；通过 Iris 菜单应用设置，依据随后出现的维度 pipeline 日志和新画面确认加载。自动发送 R 仍未触发重载，未将按键发送当作成功。
- 始于末地，后进入主世界海洋／森林和下界。固定正午期间暂时关闭 `minecraft:advance_time`；观察结束已重新开启。观察模式仅用于找机位，正式水下贡献图使用创造模式。
- 命令输入最初的 Unicode 键事件触发整合包输入模块的 `65539: Invalid mouse button 99`，改用窗口字符消息后，后续命令正常执行且未继续产生该报错。这个报错不作为着色器编译故障。

## 已写入正式源码的修正

### 数值启停条件必须先预处理

第一次加载当前包时，Iris 多次报告 `Tried to get boolean value for unknown option: 100>0, defaulting to true!`。属性文件中的 `program.*.enabled` 运行时表达式不能直接承载数值比较；强度被替换为数值后，被当成未知布尔选项，默认真值使停用配置仍可能调度。

现将数值判断放在 `#if` 中，两种结果均输出明确的 `true`／`false`：

- 主世界 composite1／3／4 和下界、末地对应 Bloom 阶段；
- 主世界水下光束历史 composite9；
- 下界 shadow 捕获及九个 shadowcomp 传播阶段。

纯布尔选项的启停条件继续沿用。没有改变活跃效果的采样数量、纹理精度、波幅、雾曲线、光源强度或颜色。后续实际加载没有再出现上述未知数值选项警告。

相关原始加载行保存在[客户端日志摘录](../qa/runtime-feedback-2026-10-02/shader-load-excerpts.log)，同时包含修复前的警告及后续维度加载。结束时日志明确为 `Profile: BALANCED (+0 options changed by user)`；Iris 已移除没有覆盖值的 `Astra.txt`。

实际菜单把 `BLOOM_STRENGTH` 设为 0 后，水下完整画面继续显示，水雾仍正常施加；把 `BLOCKLIGHT_STRENGTH` 设为 0 后，下界完整画面及发光材质仍正常显示。截图和日志支持这些配置能加载及画面可用；本轮没有 GPU 调度捕获，因此不将截图当作每个阶段耗时或实际 dispatch 数量的证据。

### 完全滤平的水下法线直接返回

`solas_water_normal` 的两层解析权重均为 0 时，四个视差高度和四个差分高度都是同一个常量，差分为 0，最后法线仍为原面法线。现直接返回 `face`，跳过视差与差分运算。原有 0.5→2.0 足迹过滤范围、噪声尺度、近处波幅、焦散与反射链路保留。

## 已读取的实际画面

| 场景与设置 | 证据 | 直接观察与限制 |
|---|---|---|
| 末地，TAA | [末地画面](../qa/runtime-feedback-2026-10-02/14-taa-end-live.png) | 黑洞、盘面、星场、岛屿及实体成功显示；不能据一张图判定整个盘面动画的质量 |
| 主世界海面，正午 | [海面](../qa/runtime-feedback-2026-10-02/24-surface-noon.png) | 云、岸线、水面反射及水下珊瑚可见；细小反射边缘仍有明显复杂图案 |
| 创造模式水下，原贡献分屏 | [分屏](../qa/runtime-feedback-2026-10-02/33-water-contributions.png)、[后续画面](../qa/runtime-feedback-2026-10-02/34-water-contributions-next.png) | 密集白纹已存在于原场景；独立光束层没有对应的密集白纹 |
| 泛光开关保持开启、强度 0，FXAA | [选项](../qa/runtime-feedback-2026-10-02/45-zero-bloom-option.png)、[完整水下](../qa/runtime-feedback-2026-10-02/46-zero-bloom-water.png) | 零强度配置成功加载，完整画面及水雾可见；临时分屏已撤除 |
| TAA＋方向性天光＋SSAO | [选项](../qa/runtime-feedback-2026-10-02/49-ao-sh-enabled.png)、[森林](../qa/runtime-feedback-2026-10-02/50-forest-taa-ao-sh.png) | 三个组合选项成功加载；地形、树叶、阴影及水面显示正常 |
| 树叶附近横移 | `52-foliage-motion-00.png` 至 `-03.png` 及 [移动后](../qa/runtime-feedback-2026-10-02/52-foliage-motion.png) | 已读取移动中的画面及停止后的画面，未看到整片旧画面残留；短段截图不证明所有风速、视角均无拖影 |
| 下界，TAA | [下界](../qa/runtime-feedback-2026-10-02/54-nether-live.png) | 岩壁、岩浆、萤石、反射与远处雾层可见 |
| 下界方块光强度 0 | [选项](../qa/runtime-feedback-2026-10-02/55-zero-blocklight-option.png)、[画面](../qa/runtime-feedback-2026-10-02/56-nether-zero-blocklight.png) | 完整画面仍显示，发光材质保留；没有新增着色器错误或未知数值条件警告 |

## 水下反射细纹仍未消除

临时贡献显示位于水体合成阶段，四屏从同一帧完整原场景重采样：左上为施加水雾前的场景，右上为场景＋水雾，左下为独立光束，右下为完整合成。各屏使用同一水下显示曲线；光束从其参考颜色域转为线性后送入显示。后续 Bloom 与粒子仍会影响诊断显示，因此此图用于定位密集细纹来源，不用于严格的分量相减。

暂时移除水面背面的 SSR 命中后，[固定正午图](../qa/runtime-feedback-2026-10-02/38-no-ssr-noon.png) 中密集白纹消失。临时[命中覆盖图](../qa/runtime-feedback-2026-10-02/42-underwater-hit-coverage.png) 则出现对应的细碎明暗切换，支持问题位于水面反射命中覆盖。

随后观察了反射颜色足迹过滤、更早的法线过滤和反射未命中时的水体介质替代。颜色过滤没有明显解决覆盖断续，其他两项会改变当前水面外观且仍未消除细纹，均未保留。正式版保留现有波幅、过滤参数、天空替代与反射预算，只有上述等价提前返回。本轮不把这个现象写成已经修好。

## 交付范围

正式源码已更新到运行实例，临时分屏及反射隔离代码已撤除。临时 TAA／AO／方向天光和零强度选项结束后，实例恢复均衡默认效果。最后画面见 [下界正式画面](../qa/runtime-feedback-2026-10-02/60-final-nether.png)。

本轮截图中的瞬时帧率有明显波动，混合了场景、相机、世界加载和选项变化，不据此报告固定百分比的性能提升。尚未穷尽所有画质档、天气、介质和版本；水面反射覆盖的细纹仍是接续开发事项。
