# ref-sources：本轮在线抓取的参考源码

用途：为 2026-10-17 的 Astra 缺口调研提供可核验的源码出处。只保留文本源码，二进制贴图（*.png）未复制。

## grindstone/
- 来源：https://github.com/Luracasmus/grindstone （Modrinth slug smaa-mc，项目名 Grindstone）
- 抓取方式：codeload.github.com tar.gz，2026-10-17。
- 许可：根 LICENSE 为 MIT；assets/grindstone/shaders/include/redmean.glsl 自身声明为 CC BY-SA 3.0（基于 compuphase Colour metric）。
- 内容：SMAA 1x（edge detect / blend weights / blend）四 pass 与 CAS 锐化，以及原版 26.3 的 post_effect 接线 JSON。
- 注意：本项目为**原版资源包**形式（assets/minecraft/post_effect/end_of_frame.json），不是 Iris 光影包。

## contour-outline/
- 来源：https://github.com/Eleeterrr/Contour-Shaders （截取其中 contour shaders/ 目录）
- 抓取方式：codeload.github.com tar.gz，2026-10-17。
- 许可：包内 LICENSE 与 README 明确写：outline 系统保留所有权利，修改/再分发/复用需事先书面许可；Complementary 基底另有 CLA 1.7。
- 用途：仅作机制阅读，**不可搬代码**。
