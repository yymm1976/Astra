# Arc v0.15.2

来源：本地 Arc v0.15.2 归档的根 LICENSE 与 shaders/lib/fxaa_2.glsl。LICENSE.txt 保留原 MIT 许可正文与版权行。

Astra 的实际实现位于 global/post/fxaa.glsl，保留邻域边缘搜索结构，改用显示颜色与 alpha 亮度、限制采样边界、降低亚像素平滑权重，并为水下几何提供深度轮廓门。这里不重复存放运行代码。
