# 2026-09-13 Complementary 晨昏源码对照与 Astra 调整

## 已阅读的来源

本地 `_analysis/Complementary r5.9/` 的 Reimagined、Unbound，以及游戏实例中 `ComplementaryUnbound_r5.8.1 + EuphoriaPatches_1.9.3` 的直射/环境光配色。后者仍使用同一组核心晨昏光色公式。

- `lib/common.glsl`：noonFactor、日夜与太阳可见性。
- `lib/colors/lightAndAmbientColors.glsl`：晨昏直射光与环境光分别变化。
- `lib/lighting/mainLighting.glsl`：SIDE_SHADOWING、露天环境光、方向遮蔽、AO 与最终照明组合。
- `lib/materials/materialHandling/terrainIPBR.glsl`：草方块材质处理；常规草色并非靠晨昏更换草纹理，而是乘上场景照明。
- `lib/colors/skyColors.glsl`、`lib/atmospherics/sky.glsl`：上/中/下天空、太阳方向暖带与辉光。
- `lib/atmospherics/fog/mainFog.glsl`：随高度、距离和太阳方向变化的空气透视，天空作为雾色来源。
- `lib/colors/cloudColors.glsl`、`lib/atmospherics/clouds/reimaginedClouds.glsl`、`unboundClouds.glsl`：光色与环境色分离、密度尺度、云体高度明暗、透光边缘与天空融合。
- `lib/materials/specificMaterials/translucents/water.glsl`、`materialMethods/reflectionBackground.glsl`：保留水底色，反射共享天空和云，太阳高光乘阴影。
- `program/gbuffers_skytextured.glsl`：太阳亮度/颜色随晨昏变化，日月绘制与天空分离。

## 上轮效果弱的具体原因

1. 晨昏权重到太阳 +20° 已归零，用户看到的低太阳画面可能已退出晨昏；sunProgress 与参考 noonFactor 的曲线也不同。
2. 低角度光同时经过太阳高度衰减与近 Lambert 响应，暖光贡献太小；额外冷环境光让草地继续偏阴天绿。
3. 天空在原有浅色散射上继续加亮；近云至少掺入约一半天空色，主体层次被冲淡。
4. Astra 使用 Reimagined 的窄云层、硬密度轮廓；太阳默认仍是原版方形纹理，晴天云没有遮挡后绘制的太阳。
5. 波浪分支强制粗糙度为零，远处反射容易形成硬亮条带；河床照明另走水体参考光色。

## 最终实现

- 晨昏暖色延续到太阳升起之后，再平滑退出；修正天空 noonFactor 的曲线映射。
- 重分配晨昏直射/环境光能量，暖直射光采用适合 Astra 线性颜色管线的红绿比例。参考包裹法线响应，让草地顶面和树冠在低角度真正吃到暖光；保留阴影与独立局部光源。
- 天空用方向性晨昏配色替换宽泛白区域，配合原有高亮压缩；雾复用同一天空，去掉晨昏额外叠加的第二份太阳辉光。
- 云层加厚、轮廓变软，加入一个旋转的小尺度密度项；云体保留更多自身明暗，太阳/天空/云之间使用一致的晨昏颜色。仍采用首次命中的有界路径，没有移植 Unbound 的多层三维噪声步进。
- 默认及预设选择圆形日月。太阳角半径 0.028 弧度，晴天也由同一可见云层遮挡。
- 水面反射共享晨昏天空，并加入两次密度采样的云色近似；远波法线适当收敛、恢复少量粗糙度；太阳高光乘可见性。青蓝吸收系数不变，浅水河床接入晨昏光色。

所有 shader 修改随批次同步至游戏实例 Astra。这里记录的是源码与实现结论，不代表已经获得修改后的游戏截图或帧率。
