# 批次二汇总的落地改动（2026-10-02）

依据 [SUMMARY-batch2.md](../shader_research/SUMMARY-batch2.md) 的 ⑤-2 收敛结论、③ 来源约束和相应单包报告，将当前项目尚未覆盖、适合保留现有画面路线的三项建议写入 Astra。索引与总账作为来源上下文，批次一 [SUMMARY.md](../shader_research/SUMMARY.md) 和已有实施记录用于区分既有功能。报告中的 `A:` 行号是旧快照，本次按当前函数及调用位置定位。

## 时间跳变时停止沿用旧历史

对应 UShader 报告 ③2 / 汇总 ⑤-3 第 2 项。`shaders.properties` 在 CPU 端计算世界时钟的正弦、余弦与各自短时平滑值，将偏差合成整数 uniform `astraTimeDiscontinuity`。采用周期坐标是为了保持午夜跨日的连续性，也避免太阳路径角度、昼夜阴影光源交接影响判断。平滑 ID 85、86 与现有天气、群系 ID 分开。

半衰期参数按 [Iris SmoothFloat 实现](https://github.com/IrisShaders/Iris/blob/26.1/common/src/main/java/net/irisshaders/iris/parsing/SmoothFloat.java) 的内部 `×0.1` 秒换算：使用 `20 × frameTime` 对应约两帧半衰期，并限制极端帧时的窗口，避免把过短的平滑参数当成秒数，使突变信号消失。

出现明显的 `/time set` 或睡眠跳时后，以下入口改用当帧结果：

- `lib/taa_state.glsl`：场景 TAA 与依赖该状态的植被运动历史。
- `global/atmosphere/cloud_temporal.glsl`：屏幕云独立历史，关闭 TAA 时同样生效。
- `lib/effect_history.glsl`：下界反射及水下光束共用的历史有效性判断。
- `global/post/exposure.glsl`：空气侧曝光直接采用当前计量目标，避免沿用另一时段的增益。

这是照明时钟的突变信号，并非逐帧存储完整世界日期：很小的时间调整、整天的同相位跳转不会由它单独识别；默认游戏速度下正常走时的短时偏差由阈值容纳。已有帧编号、分辨率、介质、相机与投影判断继续共同决定历史是否可用。水下曝光仍沿用原有冻结规则。

仅采用报告的 CPU 判别思路，周期坐标、阈值与接口由 Astra 编写，没有复制 UShader 的表达式。没有新增历史附件或渲染阶段。

## 体积雾的平行阴影空间射线

对应 UShader 报告的体积雾空间行进建议 / 汇总 ⑤-2 第 4 项。`global/atmosphere/volume_fog.glsl` 在每条射线开始时变换原点与方向，采样点由 `shadowOrigin + shadowRay * t` 得到。

原来每个采样点各做一次阴影视图与投影矩阵变换，现在有直射光且需要阴影图的射线在循环外做四次原点 / 方向变换。循环内仍保留齐次除法、非线性阴影畸变、深度偏置、范围淡出、云影、真实高度密度和分段积分；自适应与固定步长共用同一参数 `t`。解析远端与仅云影的前缀路径不会查询阴影图。

该重组在数学上使用原来的仿射坐标关系；浮点运算顺序改变，阴影边界可能存在舍入差异。源码层面的重复矩阵运算减少不能直接换算为帧率提升。

## 可选粗糙天空反射：mip 与环境 BRDF 同时接入

对应汇总 ⑤-2 第 1 项及 Glimmer ③2、Musk Rose ③2 / ③8。新增水体菜单选项 `ROUGH_SKY_REFLECTIONS`，中文名“粗糙天空反射”，**默认关闭**，保留现有水面、冰面与雨天积水的默认外观。

开启且使用平面云时：

1. 天空 / 云缓存仍为 `R11F_G11F_B10F` HDR，尺寸改为 256×128。写端按完整周期生成经度，不将原来的两列窄边框直接下采样。
2. 在既有 `prepare2` 开始前生成缓存 mip，此时 `prepare` 已完成天空和云写入，后续不再重写该缓存。没有新建渲染阶段。此调度依据 [Iris mip 指令说明](https://shaders.properties/current/reference/constants/colortex_mipmaps/) 及 [Iris CompositeRenderer](https://github.com/IrisShaders/Iris/blob/26.1/common/src/main/java/net/irisshaders/iris/pipeline/CompositeRenderer.java)：指令在所在阶段之前生成，采样状态在当帧后续阶段保留。
3. 按平方粗糙度对应的纹理足迹选择连续 LOD，限制到最高一行纬度层。经度内部使用硬件过滤，接缝处对末列 / 首列分别取样并插值，相邻 mip 也按各自尺寸处理。SH 天光积分继续取第 0 层。
4. 水面、透明冰、不透明冰与积水的天空退路同时应用环境 BRDF 的相对粗糙度响应；SSR 命中的场景颜色沿用原有合成。原表面已经乘 Fresnel，因此新项以同视角的零粗糙度拟合值归一化，并限制在 0–1，避免再次乘 Fresnel 或提高原有镜面能量。

`lib/environment_brdf.glsl` 的标量拟合改编自本地 Musk Rose 4.1（Rin，包内 CC0-1.0）的 `getEnvironmentBRDF`，保留其 UE4 mobile BRDF 来源链接。共享指数、归一化、上限、材质输入及接线为 Astra 适配。Glimmer / Voyager 只采用缓存与粗糙度的组织思路；没有移入其实现，也没有引入参考包图片、LUT、SSDO 或阴影代码。

这是一项可选外观改进：增加每帧 mip 生成及 BRDF 运算；接缝附近最多需要四次取样，其余区域通常一次纹理查询。它不是性能提升项。经纬度 box mip 也不是严格按立体角预积分的 GGX 环境图，归一化拟合服务于现有非完整 PBR 材质体系。

关闭选项时仍使用 258×128 双边框缓存与原第 0 层取样，不生成新的缓存 mip，环境增益返回 1。无平面云以及下界 / 末地维度沿用原有环境路径。

## 其余建议的采用边界

- 棋盘格云需要新的年龄 / 重建机制，当前每帧半分辨率云保持现状，避免直接减少细碎云边缘的有效采样。
- 静态大气 LUT、额外 POM、GI、运动模糊、DoF 和新增彩光管线不纳入本轮性能修复，以保留天气、四种颜色方案与现有材质路线。
- CPU 天气参数、湿面 / 涟漪、TAA 色调空间统计、阴影范围判断和质量档位已有实现，本轮不重复登记为新增。
- 对来源有保留权利、NC / SA 或包内协议冲突的内容，仅研读方法；本轮直接改编的范围限于上述 Musk Rose 环境拟合。Astra 各原文件的既有来源登记仍适用。

上述改动已保存源码、设置与语言项，来源补充至 `Astra/THIRD-PARTY.md`。运行中的帧时、阈值反应和实际画面效果尚无确认数据。
