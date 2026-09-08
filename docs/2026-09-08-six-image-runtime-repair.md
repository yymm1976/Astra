# 最新六图退回后：实例渲染路径续修

用户裁决仍为阴影、水色、水下阳光全部不通过。本次针对该裁决继续实现，未取得修改后的游戏画面。

## 发现与实现

- 阴影：图 4/5 中目标树在近景，不能直接归因于 128 格接收距离。读取实例 Iris 1.11.2 类确认，默认 AdvancedShadowCullingFrustum 使用相机视锥；`shadow.culling=false` 切换为距离裁剪。现关闭该高级裁剪，并令投影物范围为接收范围的 1.5 倍，保留可能从视野外投影到画面内的树。修改发生在 shadow 生成之前。没有游戏 pass 抓取，尚不能证明它是截图中缺失树影的唯一原因。
- 水下：旧太阳源要求最近 caster 的 R 通道恰好是水高，同时以 opaqueVisibility−allVisibility 决定有无太阳。这个条件把水体身份与第一投影物耦合；缺少水面标记时，即使已知采样点在水中、没有不透明遮挡，源也直接归零。增加独立界面状态后，太阳源、地形入水照明和焦散共享水高，shadowtex1 仅负责不透明遮挡。错误先影响 opaque lit 的入水照明，后影响水面路径及散射 pass，不在 final 补亮。
- 水色：仍使用米制为方块单位的 Beer–Lambert 传输，修正入射太阳被切断的来源，同时减轻光入水和回到眼睛这两段光程的过量吸收。默认吸收从 (0.240,0.035,0.060) 改为 (0.135,0.012,0.028)，散射从 (0.014,0.045,0.035) 改为 (0.012,0.030,0.040)，各选项百分比仍只应用一次。绿色透射最长、短波散射参与水柱亮度；这些数值是候选外观，不能宣称已接近参考图。

状态路径：gbuffers_water → 全分辨率 colortex5（界面 metadata）→ composite → 1×1 colortex6 → composite2（原散射）。opaque 照明与焦散读取上一帧状态。本帧看不到水面时保留已观察到的世界水高；第一次直接出现在水下且看不到界面、阴影水高也无效时仍有局限。没有固定海平面猜测。

## 对两份其他模型意见的核对

采用“水高闸门错误”、上一帧状态依赖需说明、缓冲登记和接口契约需补充等意见。以下未照做：

- `1 1` 被怀疑为全屏：实际 Iris TextureScaleOverride 以字符串是否带小数点区分比例，实例类返回 1×1；`1.0 1.0` 才是全分辨率。
- 删除 `SKYLIGHT_STRENGTH×0.01`：默认强度 100%，这里结果为 1，不是 0.01。
- 通过把 SHADOW_DISTANCE 改为 256 解释近树跳影：截图目标距离不支持此结论，先修生成前裁剪。
- 无遮挡判断的朝太阳 glare：不采用；方向亮区继续由真正太阳源、相函数与遮挡积分提供。
- 把水体状态 pass 随 shafts 关闭：地形入水照明、焦散也使用它，不能绑到光束开关。

本地参考仍为 Steadfast shadow/translucent/absorption、Solas volumetricLight/waterFog、Mellow transformations；只据其光路判断接线，不机械移植色值。必要编译、Iris 参数解析与基本校验另记日志。完成同步后停止，等待用户新的实机裁决。

## 本轮交付校验

- RTX 4050 / OpenGL 4.6：PERFORMANCE、BALANCED、ULTRA 共 228 对 GLSL 链接成功；关闭 SHADOWS 的 BALANCED 另 76 对成功。见 `qa/glsl-six-image-profiles.log`、`qa/glsl-six-image-no-shadows.log`。
- 实例 Iris 的 include/option/properties 预处理确认 composite 状态、composite2 散射均启用；原始 TextureScaleOverride 类解析 colortex6 为 1×1。工具为 `qa/tools/inspect_iris_properties.py`，预处理输出为 `qa/iris-properties-resolved.txt`。这不等于启动了 Minecraft。
- 独立水体身份、最近 caster 全为非水的驱动输入：太阳源无遮挡侧大于零、不透明遮挡侧为零；阴影平面深度与照明边缘校验也通过。见 `qa/render-path-verification.log`。该数值输入不证明六张实机图已解决。
- 基本源码校验无失败；既有 Voxy 接线及 VOXY_SUPPORT 未引用提示仍在。差异空白校验通过。
- 同步目标为 `D:/zhenhebao/.minecraft/versions/生电优化整合包 (Fabric)/shaderpacks/Astra`。同步后停止；本轮没有游戏画面或帧率数据，不把三项视觉裁决改为通过。
