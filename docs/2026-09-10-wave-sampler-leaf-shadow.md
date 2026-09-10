# 2026-09-10 波浪退化与树叶阴影缺失

针对最新反馈：“波浪变成偶尔平推的一条直线；树叶阴影缺失，靠近才出现一部分”。本次定位到两个源码与 Iris 接口之间的具体错误。已修改源文件并编译阴影程序；视觉结果仍须与实际运行画面区分，不能据此宣称所有历史问题或参考效果已经完全还原。

## 1. 波场读错了纹理

上一轮在 `Astra/shaders/shaders.properties` 中声明了 `texture.gbuffers.steadfastWaterNoise`、`texture.gbuffers.solasWaterNoise` 和 `texture.composite.solasWaterNoise`。这是上一轮引入的接线错误。

本机 Iris 1.11.2 的实现区别如下：

- `texture.<stage>.<name>` 的 PNG 进入按阶段划分的 `customTextures`。`ProgramSamplers.CustomTextureSamplerInterceptor.getOverride` 只在引擎注册已有采样器名称时查找替换对象，并不会遍历这些条目来注册任意新名称。
- `customTexture.<name>` 的 PNG 进入 `irisCustomTextures`。`IrisRenderingPipeline.addGbufferOrShadowSamplers` 等路径调用 `IrisSamplers.addCustomTextures`，后者逐项调用 `addDynamicSampler`，才会注册这里新增的名称。
- Astra GLSL 已经使用了这两个新名称，但旧属性写法没有为它们完成注册。未赋值的 sampler uniform 默认指向纹理单元 0；具体误读的是哪张图取决于当前程序绑定，不能仅凭截图指定它始终是哪张图。

渲染链条：错误注册 → 波场采样器读取错误内容 → 六层波场的高度与梯度失去噪声输入 → 法线和折射位移异常。错误内容的平坦区或大尺度边界，能够解释大片平水和偶尔平推的直线。复制参考波浪函数、扩大折射距离，都无法补上缺失的输入绑定。

修复：改用 `customTexture.steadfastWaterNoise` 与 `customTexture.solasWaterNoise`，并移除重复属性。保留参考波场的六层参数、梯度和视差公式。Solas 的水下法线、焦散及光束输入也通过同一注册修复接通。

Steadfast 本身使用引擎已有的 `noisetex`；Solas 也通过自己的噪声配置消费 `noisetex`。Astra 为两套不同噪声增加独立名称时，需要同时适配引擎注册接口，不能只改 GLSL 变量名称。

## 2. Iris 把投射颜色当作树叶透明度裁剪

`Astra/shaders/program/shadow.fsh` 的数据格式是 `vec4(waterHeight, shadowTint)`：R 为水高，GBA 为投射颜色 RGB。因此输出 A 实际上是颜色的蓝色分量。

旧程序先按纹理 `albedo.a < alphaTestRef` 做镂空裁剪，再通过 `gl_FragData[0]` 写入上述数据。本机 Iris 的实际路径如下：

1. `ShaderKey.SHADOW_SODIUM_TERRAIN_CUTOUT` 默认使用 `HALF_ALPHA`；`ShaderCreator.createShadow` 在没有属性覆盖时沿用该配置。
2. `SodiumTransformer` 调用 `CommonTransformer.transform(..., false)`。
3. `CommonTransformer` 收集旧式 `gl_FragData` 的输出索引；索引包含 0 且需要透明度裁剪时，在主函数末尾追加对 `iris_FragData0.a` 的裁剪。
4. `IrisInternalUniforms` 为 `alphaTestRef` 和 `iris_currentAlphaTest` 提供同一个捕获阈值。因此源码对纹理做完一次正确裁剪之后，引擎又对蓝色数据做了一次不正确的裁剪。

距离相关症状的链条：树叶纹理随投射分辨率进入缩小层级 → 边缘像素 alpha 下降 → Astra 的 `1-smoothstep(0.9,1.0,albedo.a)` 增加深绿色染色 → 输出 A 变成较小的蓝色值 → 引擎追加的裁剪删除该片元 → 阴影深度未写入。靠近后更多像素 alpha 接近 1，输出 A 恢复为 1，阴影才逐渐出现。

例如纹理 alpha=0.8、解码后的蓝色=0.05：原本能通过 0.5 的覆盖阈值，打包后的输出 A 却为 0.05，会被第二次裁掉。这个缺陷发生在投射端，接收端扩大距离、更改偏移或替换过滤方式都不能恢复已经丢弃的树叶。

参考差异：Steadfast 输出 `vec4(waterHeight,1,1,1)`，A 恒为 1；Solas 输出保留原始 alpha 的 `albedo`。它们都没有 Astra 的“蓝色数据被当作透明度”冲突。

修复：使用 `layout(location=0) out vec4 shadowData` 写入同一个目标，明确它是数据输出。Iris 这条旧式颜色输出转换路径不再对其追加透明度裁剪。源码仍按纹理 alpha 和引擎的 `alphaTestRef` 裁剪，保留树叶镂空；没有把阈值关成 0，也没有引入替代阈值。水高和 GBA 格式保留，现有阴影、焦散和光束消费者继续按原格式读取。

## 3. 与历史失败及各效果的对应

| 效果或历史处理 | 本次结论 |
|---|---|
| 波浪形状、波浪造成的水底扭曲 | 修复它们共同的噪声采样输入。前轮只接入公式，属性注册有误，不能算有效接通 |
| 水底波纹光斑 | 修复 Solas 噪声注册；阴影数据输出也不再被蓝色值误裁。光斑仍来自水面焦散投射 |
| 太阳侧光束 | 修复其共用的噪声和投射数据入口；方向与距离权重仍采用上一轮接入的 Solas 公式 |
| 树叶阴影随距离缺失 | 去掉投射数据被二次裁剪的具体路径，保留真实覆盖裁剪 |
| 9 月 8 日至 9 日的距离、interval、投影及接收深度修改 | 都没有处理投射端的输出透明度冲突，不能修复本次定位的树叶深度缺失 |
| 走一格整片明暗翻转等更早现象 | 本次没有对应运行帧的证据，不把所有不同现象强行归为同一根因 |
| 青色水体、整体水下亮度及与参考完全一致 | 本次未新增调色。上一轮效果对应表中的其他差异仍存在，不能宣称逐像素一致 |

修改的阴影入口在 PERFORMANCE、BALANCED、ULTRA 三档下，共 9 对程序经本机 NVIDIA OpenGL 编译链接，失败数为 0。普通 GLSL 编译不会执行 Iris 的纹理注册和运行时源码改写，这正是此前编译成功仍漏掉这两个接口错误的原因。

本次游戏文件改动限于 `shaders.properties` 和 `program/shadow.fsh`，同步目标为现有整合包 `D:/zhenhebao/.minecraft/versions/生电优化整合包 (Fabric)/shaderpacks/Astra/shaders`。
