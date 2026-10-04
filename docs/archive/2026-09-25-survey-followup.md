# 阴影审查与低配横向报告的后续处理

针对 DeepSeek 的四项问题及 `2026-09-25-lowend-cross-pack-survey.md`，本轮处理如下。

## 已修改的渲染代码

1. 删除 `shadowmap.glsl` 中无调用者的 `ShadowTap`、`shadow_read_tap`、`SHADOW_FILTER_TAPS` 和 `shadow_filter_uv`。旧交接记录只完成了列出的旧代码删除，确实遗漏了这些阴影脚手架。
2. 硬件表面阴影改用 `textureGather(sampler2DShadow, uv, referenceDepth).wzxy`。每张深度图、每波瓣从四次读取降至一次，保留各角独立比较及材质配对。软件模式也是一次 gather，但比较在 GLSL 中执行。体积的硬件路径仍用单次双线性比较采样。中英文选项去掉过时的“中心染色近似”说法，不承诺硬件必然更快。接口依据：[GLSL 规范的 shadow gather](https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.4.60.html)。
3. 移除末地 `fract(worldPos)` 格线倒角。缩小幅度和范围无法辨别共面内部接缝；现在直接使用材质法线，保留粗糙度、GGX 高光和末地石发光。同步去掉仅为倒角设置的额外阴影查询与像素足迹，并调整离线预览调用。真实外轮廓倒角仍未实现。
4. 采用横向报告 A2 的预计算思路，将五组仅依赖天空颜色、天气的量搬到 Iris custom uniform：`astraSkyColorM`、`astraSkyNoonBase`、`astraSkyNightUp`、`astraSkyNightMiddle`、`astraCloudNoonAmbient`。日间天空原有的原始 `rainStrength` 和夜间的平滑 `astraRainFactor` 保持各自语义，负天空颜色的保护也保留。

天空调色函数不再逐次计算六个标量非整数幂及六个平方根，云环境色另省三个标量非整数幂。新增五个 vec3 uniform、三个 CPU 中间变量；调用点及云、反射的采样位置没有改变。这是 ALU 工作迁移，不能换算成固定 FPS 增幅。

custom uniform 的标量函数、分量访问与依赖符合 [Iris 表达式规则](https://shaders.properties/current/reference/shadersproperties/custom_uniforms/)。人工昼夜、雨强、颜色输入下，属性文件表达式所得颜色与原 GLSL 调色公式最大通道差约 `1.2e-7`；这不是 Minecraft 画面结论，也不是已启动游戏读取绑定结果。软件与硬件表面阴影的混合水/玻璃输入保持逐通道一致。相关 shader 三档驱动编译完成。

## 横向报告中不能直接采用的结论

- **A1 分帧传播不是当前实现的低风险替换。** 占用图每帧清空，step 0 重建光源，再扩散八轮。减少每帧轮数会缩短当帧传播距离；保留上帧结果则需要历史光场、相机重定位、失效区域及移动光源处理，与同帧传播约束不同。没有采用。
- **“九个 compute 是全包最大固定支出”没有计时依据。** 前一轮仅针对该 64³ 链的局部 GPU 计时约 0.12 ms，尚无与整帧其他阶段同场景的比较；不能据 dispatch 数排列耗时。
- **“主世界八个全屏”混淆了绘制类型和尺寸。** shadow 是几何投影，composite 的水状态目标为 1×1；散射和 bloom 也不是全分辨率。49 次太阳遮挡读取只在开关开启时由一个 texel 执行，不能作为每屏幕像素的循环负担。默认 BALANCED 还关闭该开关。
- **MRT 表中有实际解析错误。** `DRAWBUFFERS:067` 是三个附件，原脚本按逗号分割得到一个。已改为逐数字计数；例如 Miniature 的表面路径确实输出 0、6、7。附件位数、分辨率、几何覆盖和读写次数都要计入带宽，不能因附件附着在已有几何阶段就忽略其成本。
- **固定尺寸与降采样被混为一谈。** 294×1 轨道查找表不应计入分数分辨率缓冲。已修正脚本筛选；当前 Astra 的比例降采样目标是 colortex1、2、7、9，共四张。
- **“只有 Astra 降采样但无 TAA”不成立。** 本地 Steadfast 的光束是半分辨率；Mellow 的 FANCY 预设同样关闭 TAA，同时使用缩小的 bloom 缓冲。FXAA 本身也不做时间累积。Astra 的水状态及可选曝光保存少量跨帧状态，所以“没有任何历史缓冲”也不准确；它与禁止引入图像时间累积、彩光历史不是同一件事。
- **TAA 不是消除所有高采样循环的唯一途径。** 不引入 TAA 的现有约束继续有效，没有再要求用户为这份报告改决策。
- **不能无条件关闭 composite/composite3。** 水状态和水显示仍有消费者；配置启停无法由运行时 `isEyeInWater` 自动决定。没有将空中 fragment 的快速返回冒充整个阶段卸载。
- **没有降低云和 SSR 上限，也没有改变阴影宽度。** 这些会改变覆盖和外观，不是报告中所称的零风险常量优化。

机器普查依然只是源码定位器：不展开宏，不能从入口种类、最大附件数、字面循环上限推出默认运行时成本。比例尺寸计数只覆盖直接写出的 `size.buffer` 数值；零条不代表没有 custom image、缩小 viewport 或其他降分辨率路径。原横向报告保留，本记录说明本轮采用与否的依据。

## 实例同步

仓库最终源码已同步至 `D:/zhenhebao/.minecraft/versions/生电优化整合包 (Fabric)/shaderpacks/Astra/shaders`，本次更新 15 个文件，包括水下重建、云的地形终点截断、上一轮四项优化以及本轮阴影、地表和颜色预计算。若游戏仍在运行，需要重新加载 Astra 才会使用新程序；没有宣称已在运行中的游戏自动生效。
