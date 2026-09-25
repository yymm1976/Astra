# 未决前提台账（open premises）

三份审查（2026-09-20）之后仍未闭环、需要一次实机动作或引擎源码取证的前提。每项结论一旦落定，把证据写回对应文件的注释。

| # | 前提 | 现状 | 关闭方式 |
|---|---|---|---|
| P-1 | hand（gbuffers_hand）与 deferred 的真实相对绘制顺序 | design.md:90/493 断言 deferred 先于半透明；deferred.fsh 的 HAND 位消费与该断言可能互斥（Qoder F-02）。三方均未定论 | 实机探针：deferred 把已知图案写进 colortex4 空像素 → gbuffers_water 读回打印；一次游戏内实验定论，然后据结果决定 colortex4 写入方与天空回填深度源 |
| P-2 | entityShadowDistanceMul 的完整乘链含 renderMul | **引擎乘链已确认（2026-09-25）**：Iris 1.11.2 ShadowRenderer.renderShadows 在指令 837–849 将 renderDistanceMultiplier 与 entityShadowDistanceMultiplier 相乘，传入 createShadowFrustum；该函数指令 28–32 再乘 halfPlaneLength，构造器从 PackShadowDirectives.getDistance 读取该长度。Astra 字面量表与 1.5 配套，三个画质档名义实体影距为 48/64/96 格。NO_SHADOWS 的阴影阶段关闭 | 源码问题已关闭；游戏渲染距离及视锥裁剪可能进一步限制可见范围，本结论不宣称目视边界已确认。对应上游方法见下方链接。 |
| P-3 | 跨驱动编译（AMD/Intel/Mesa） | 267 项编译证据全部来自 RTX 4050 + NVIDIA 572.83；N2/T1 类可移植性问题已修（srgb_decode 钳位、负底数 pow 清零、全局初始化器局部化） | 任意一台他厂驱动机器跑一次 qa/tools/compile_glsl.py |
| P-4 | 实机画面与帧率（design §8 第 1/2/3 项） | 09-12 起六轮改动（晨昏/雨景/SC-39×2/性能轮/本次修复）全部无画面与帧率证据；qa/benchmarks.md 为空 | 按修复清单标注"需实机对拍"的项逐项出图 + 跑一次三档基准填表 |
| P-5 | sunAngle 约定（0=日出、0.25=正午、0.5=日落、0.75=午夜） | 由 Solas 参考语义钉死（GLM r2 §1，高置信），未实机直接观测 | 正午/日落各截一帧看 astraSolasTimeBrightness 门控效果，然后把约定写进 shaders.properties Solas uniform 段注释 |
| P-6 | 源内 `colortexNClearColor` 常量被 Iris 识别为清屏指令 | 风险极低：colortex3 旧清屏 `.r=0.498` 的效果（天空像素 skylight=127）长期可观察，说明机制生效；check_pack #11 亦将 `*ClearColor` 纳入 SC-23 字面量校验 | 修 F-42（colortex3.a=0）后的首次实机出图顺带确认：天空/半透明像素不再进入积水门 |

P-2 上游定位：[Iris ShadowRenderer.java](https://github.com/IrisShaders/Iris/blob/26.1/common/src/main/java/net/irisshaders/iris/shadows/ShadowRenderer.java)，方法 `renderShadows`、`createShadowFrustum` 与构造器；本地版本依据为已安装 Iris 1.11.2 的字节码，`_analysis/iris-runtime/ShadowRenderer.txt` 为可选本地摘录。
