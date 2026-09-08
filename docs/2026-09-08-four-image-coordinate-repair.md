# 四张新图再次退回：主相机平移串入阴影相机

最新图 1/2 为 Astra 水面/水下，图 3/4 为参考水下/水面。用户指出飞过树林时所有树影不断变化、水面不够青、水下没有光束。视觉裁决保持 **false**。

## 阴影坐标的确定错误

本轮继续读取实例实际的 Iris 1.11.2 与 Sodium 0.9.1 字节码，而不是沿用前几轮关于 T 的解释：

1. `SodiumTransformer.getVertexPosition` 用局部顶点 + u_RegionOffset + section offset。
2. `Sodium GLDrawContext.updateData` 的 region offset 已减去相机整数与小数位置。
3. `Iris ShadowRenderer.renderShadows` 将独立构造的 MODELVIEW 直接放入 Sodium ChunkRenderMatrices。它不包含主相机 gbufferModelViewInverse 的额外平移。

因此，`player_shadow` 加 `gbufferModelViewInverse[3].xyz` 是错误的。它使 opaque lit 里的每个阴影接收点随主相机平移偏移，水面和散射也共用这个错误。shadow 顶点把同一个 T 减掉后计算水高和风动，同样用了错误的世界位置。

现在接收端直接 shadowProjection × shadowModelView × cameraRelativePosition；生成端直接从 shadowModelViewInverse 还原相机相对位置。没有改 bias、阴影距离、接收端渐隐来掩盖这一错误。上一轮距离裁剪仍保留，但它没有解决这一坐标问题。

本地证据：`_analysis/iris-runtime/ShadowRenderer.txt`、`SodiumGLDrawContext.txt`，以及 `_analysis/astra-sc34/SodiumTransformer.txt`。对照 Steadfast 的 ShadowMapPosition 与 Mellow 的 shadow.vsh，两者也没有将主相机逆矩阵平移混进 shadow。

## 水面与水下的外观职责

前一轮统一追求绿色长程传播，把整个水下染青，却没有建立参考浅滩的外观。本轮将艺术化 WATER_CHARACTER 放到从空气侧看水底的界面透射支路：`water_interface_medium` 使用随水程增长的选择性吸收，保持零距离透明、保留床面纹理、不染色反射。

入水照明及水下相机视线使用较清澈的体积吸收与偏蓝散射。两条支路的光程、散射权重和回退都使用各自完整的传输公式；这是一项明确的艺术化外观分工，不宣称不同观察介质下具有严格相同的物理消光系数。没有在 final 全局改色。

## 光束与焦散

旧体积光用宽噪声提亮，床面焦散用另一套独立图案。现在 `water_sun_focus` 给两者提供同一个水面聚光场：窄亮纹与暗间隔沿折射太阳方向投射成光柱，遮挡仍由修正后的 shadow 坐标采样。床面的亮纹和暗谷只调制直射光，环境光和手持灯不受影响。光束均匀覆盖可见水程，避免远段步距增大而跳过聚光带。删除已不使用的旧焦散图案函数，保留历史来源。

## 校验边界

投影校验增加了非零主相机平移、旋转及负坐标区段跨越，共 33 次移动。固定世界接收点误差为零；之前的单位矩阵输入会漏掉这个缺陷。现有生成端平面和独立水体遮挡校验也通过。

这些结果确认源码中的坐标错误已被消除，不替代实机画面。目标保持 active，视觉裁决仍为 false；本轮完成必要编译、同步实例后等待新的实际画面。

交付记录：RTX 4050 三档共 228 对 GLSL 链接成功；BALANCED 同时关闭 SHADOWS/WATER_CAUSTICS 的 76 对也成功。日志为 `qa/glsl-four-image-coordinate-profiles.log` 与 `qa/glsl-four-image-disabled.log`。基本源码校验无失败，保留既有 Voxy 提示。219 个 Astra 文件已复制到指定 Fabric 实例 shaderpacks/Astra；没有改变用户当前选择的参考光影。
