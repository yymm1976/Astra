# 2026-09-10 参考效果逐项对应

后续更正：用户反馈波浪退化和树叶阴影缺失后，发现本轮新增噪声的注册写法有误，且阴影 GBA 数据被 Iris 当作透明度再次裁剪。现已修正这两处接线，详见 [波浪采样与树叶阴影调查](2026-09-10-wave-sampler-leaf-shadow.md)。下文记录此前这轮的实现范围；其中“已接入”不能作为当时噪声已正确绑定或视觉已修复的依据。

本次输入：1 为 Solas 水下，2 为 Astra 水面，3 为 Steadfast 水面，4 为 Astra 水下。下面的“已接入”仅表示源码及依赖已经接入，不能据此宣称截图逐像素一致。陆地阴影近处圆圈仍未解决。

| 效果 | 本轮实际实现 | 代码位置（shaders 下） | 状态与差异 |
|---|---|---|---|
| 水面波浪形状 | Steadfast 六层波场、解析梯度、0.45–0.55 抗锯齿区间、四步视差和 48 格视差范围 | global/water/surface.glsl | 已接入；移除额外波浪距离淡出、视差乘 0.15 和额外粗糙度。水面选项仍由 Astra 提供 |
| 波浪扭曲水底方块 | incident + normalDelta，按背景深度推进，32 格上限，屏幕边缘淡出，四点深度拒绝 | global/water/refraction.glsl、program/water.glsl | 已接入 Steadfast 方向与推进链；颜色消费仍保留 Astra 的逐点界面侧判断 |
| 青色水体 | 按垂直深度加一格、16 格封顶，使用 Steadfast 的 (16,3,1) 吸收比例 | global/water/absorption.glsl、global/lighting/diffuse.glsl | 已接入；取消床面上游的第二次偏蓝入射吸收。最终颜色仍受天空、床面照明、后处理影响 |
| 水面反射比例 | 空气侧 F0=0.1 并乘天空光，反射方向进入水内时采用几何法线 | program/water.glsl | 已接入 Steadfast 比例；SSR 追踪器和天空尚为 Astra，不能称完全还原远处反光 |
| 水底波纹光斑 | Solas 噪声的五点差分，将焦散写入水面投射颜色；水下床面读取同一投射颜色 | global/water/caustics.glsl、program/shadow.fsh、global/lighting/diffuse.glsl | 已接入 Solas 水下焦散链。空气侧没有同时移植 Steadfast 独立的 caustics_noise 光斑，须与水面折射扭曲区分 |
| 水下整体亮度 | 环境项乘天空光平方，再与直射项混合；地形与水面采用 Solas 各自的光强分支 | lib/solas_water.glsl、global/lighting/diffuse.glsl | 已接入环境／直射公式；局部灯光、AO、材质高光仍有 Astra 差异 |
| 水下雾色和浓度 | Solas 雾色、距离指数、太阳方向 glare；平方根域混合后再添加光束并转回线性 | lib/solas_water.glsl、program/final.fsh、program/scene.glsl | 主世界已接入，并统一到最终相机段；雨天用 rainStrength 适配，尚未复制 wetness 平滑及 LPV 雾 |
| 太阳侧光束、靠近减弱 | Solas 的 VoU/VoL、距离采样权重、128 格上限，读取同一焦散投射；四次根编码、四点重建 | global/water/light_shafts.glsl、program/scattering.fsh、program/final.fsh | 已接入参考表达式，移除 HG、自写聚光及 4–16 格人为包络；保留全分辨率静态噪声，没有 Solas 的 TAA。源码本身没有实体圆环 |
| 水下水面波纹与反射 | Solas 四步法线视差、切线空间差分，Fresnel 最大 0.5、alpha 从 0.70 混合 | global/water/caustics.glsl、program/lit.vsh、program/lit.fsh、program/water.glsl | 主世界已接入法线和界面混合适配；天空、SSR、透射背景的组织仍有差异 |
| 水下明暗映射 | Solas Uncharted2 曲线及 4.7/15.2 默认曝光与白点 | lib/solas_water.glsl、program/final.fsh | 主世界水下已接入；Astra 的 bloom、后续调色和颗粒仍保留，所以整个后处理不是 Solas 原样 |
| 太阳与阴影方向 | 两个参考均为 sunPathRotation=-40；由 Iris 同时生成太阳向量与阴影矩阵 | lib/settings.glsl | 已设置同一轨道；未将 Solas 调制时间生成的光向量强行混入另一套阴影矩阵 |
| 陆地阴影覆盖 | 当前仍为 Steadfast 配套径向投影和法线偏移，以及 Astra 的深度／投射颜色读取 | lib/distort.glsl、global/lighting/shadowmap.glsl、program/shadow.vsh | 未确认十几格圆圈的根因，本轮不宣称已修复，也没有继续调整距离或偏移来掩盖它 |

## 症状对应的渲染链条与历史失败

1. 水面扭曲：波场 → 法线 → 折射方向 → 背景深度推进 → 取色。前轮把推进替换为 25 厘米薄层，并进一步缩短视差、抹平波浪；这些修改会直接损失用户要求的方块边缘扭曲。继续只调法线强度不能补齐取色位移。
2. 水体颜色：床面照明 → 入射吸收 → 界面吸收 → 反射混合 → 后处理。此前只改界面吸收，床面上游仍先经历另一套偏蓝吸收；重复调最终 RGB 无法消除上游影响。本轮删除该上游项。
3. 水下亮度：床面环境／直射 → 水面混合 → 相机水雾 → 光束 → 明暗映射。旧 waterAmbient 分支用完整户外环境光替代已衰减的天空光；只改光束消隐不能解决整面发亮。本轮接入 Solas 的环境／直射混合，并在最终相机段统一处理水雾。
4. 光斑和光束：Solas 噪声 → 水面五点差分 → shadowcolor → 床面照明／视线积分 → 合成。此前用整片水域的自写噪声代替投射颜色，再用近处包络补救，始终不是同一套链条。本轮移除这些替代函数，床面与光束读取同一焦散结果。
5. 噪声依赖：Solas 除 noise.png 外还依赖其 blur=true、clamp=false 元数据，两者一同接入。Steadfast 请求 64×64 Iris 噪声；本机 Iris 1.11.2 实际使用 NativeImageBackedNoiseTexture、Random(0)、先 x 后 y 的填充次序。本轮独立生成相同 64×64 数据并绑定到水面，其他 Astra 噪声模块保持各自纹理。
6. 方向：两套参考的太阳轨道都为 -40°，Astra 此前未声明。仅修改水下折射光方向不会改变引擎太阳和阴影轨道。本轮补上引擎轨道声明，但该差异不能解释近处圆圈。

## 阴影调查中已排除的简单解释

- 源码接收距离淡出发生于 shadowDistance-24 到 shadowDistance-8；当前默认 256，不是十几格的显式半径。
- 本机 Minecraft 26.2 主视图是纯旋转，步行晃动施加于投影；Sodium 区域偏移已经扣除完整相机位置。此前“缺少主视图平移就是唯一根因”的结论不能成立。
- renderDistance=12，为 192 格。256×1.5 进入 Iris NonCullingFrustum；该类对 Sodium 的可见性查询返回可见，不能把它直接解释成十几格裁切。
- Iris 配置 maxShadowRenderDistance=32，并非 1 个区块的限制。
- 已读到的 Voxy 可见区段收集注入会在 irisShadowActive 时跳过自身收集；仅凭 Voxy 正在加载不能认定它就是根因。

尚缺出问题运行帧的阴影图、实际矩阵和投射物范围。当前无运行中的 Minecraft 进程；上述源码证据不足以区分“投射物未进入图”与“接收坐标读到了错误区域”。该问题保持未解决，不将更换公式或完成编译写成视觉修复成功。

## 本轮交付范围

三档配置的 228 对着色程序经本机 NVIDIA OpenGL 编译链接，失败数为 0。修改代码、两组噪声数据及采样元数据同步到现有整合包的 shaderpacks/Astra；没有修改实例的模组或 Iris 配置。

用户要求的“完全、一模一样”尚未达到。上表明确区分已接入的具体表达式、仍有差异的模块及未解决的阴影问题。
