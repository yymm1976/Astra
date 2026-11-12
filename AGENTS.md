# Astra 项目指引

遵守当前用户要求及适用的上级指引。本文件规定 Astra 的项目阅读、审查与参考查阅方式，不授予安装、代码移植、Git 写入或发布权限。

## 输出要求：详细讲解、避免术语、通俗耐心

用户不是渲染专业出身，正在通过本项目学习。输出要让用户**看懂并跟上推理**，而不是只给结论。以下四条适用于每一次回答、报告和记录。

- **结论先行，然后讲清怎么得到的。** 先一句话说结果，再展开依据。不要只写"不采用""已实现"就结束——用户需要知道为什么，才能判断这个结论是否可信、要不要推翻它。
- **专业术语首次出现时用日常语言解释。** 例如不要只写"PCF 半径按纹元标定"，而是写"阴影过滤的模糊范围按阴影贴图的像素大小来算（一个'纹元'就是阴影贴图上的一格）"。术语可以保留（源码和文档里就是这些词），但要让用户能对上号。不要用箭头链、缩写和自造代号代替完整句子。
- **说清证据的强度，把"实测"和"推断"分开。** 写明这是跑了工具的结果、读了源码的结论、还是推测。没验证的事就说没验证；取不到证据就说缺口在哪。本轮已出现两次教训：一是把未验证的假设（切档比较）当建议给出，二是误读了一份比源码更早的编译日志。**宁可说"不知道"，不要给一个听起来合理但没核实的答案。**
- **耐心解释，不嫌问题基础。** 用户追问"这是什么意思""为什么"时，用更具体的例子重讲，不要重复原话或让用户自己去查。可以指出源码位置让用户核对，但不以"看源码就知道"代替解释。

记录类文档（`docs/`、`qa/` 的说明与报告）同样遵守：写给下一个接手的人，包含判断依据和未确认项，不写只有当时对话参与者才懂的省略语。（理由：项目由用户驱动决策，结论不可核验时用户无法行使判断；含糊的"已修复""不采用"还会让后续轮次重复调查同一问题）

## 当前项目依据

- 接续项目先读 `docs/当前工作.md` 的相关事项；功能边界看 `Astra/README.md`，实现依据按 `docs/README.md` 定位。已读且状态未变的内容不重复通读；已退出的旧审查和归档不作为并行入口。
- 以当前源码判断行为。根层、`world-1/`、`world1/` 是维度入口，共享实现位于 `Astra/shaders/program/`、`global/`、`lib/`。（理由：文档会落后于源码，本轮已发现门槛值与语言描述两处不一致；源码是最终依据）
- 查本机实例路径用 `qa/local_paths.json`。配置保存的光影包名称不等于运行中实际加载的包；读取实际画面或 GPU 信息时确认来源。（理由：实例目录 `shaderpacks/Astra` 与游戏内选择是两件事，误认会得到"改了没生效"的假结论）

## 审查前必读

- 开始代码审查、核验外部审查报告或依据报告修复前，必须阅读 [docs/审查指引.md](docs/审查指引.md)，再按问题读取现行说明和源码。同一任务已读且内容未变时直接沿用。
- 派发独立审查时，主Agent必须把该文档路径、适用范围与当前授权边界交给执行者，要求其在审查前阅读；不因此新增派工。
- 按其中的证据要求判断作用域、可达分支、写读顺序、单位与实际后果。复杂问题才列组合表或赋值摘录，不强制每轮生成额外台账或报告，也不扩展当前任务授权。

## 参考项目按问题查阅

处理下列问题、确需外部依据时，Agent 应浏览对应 GitHub 源码或官方说明；只读相关文件与必要调用方，不每轮通读全部仓库。优先在线读取，不为查阅 clone 整仓库（理由：参考包仓库体积大而每次只需少量文件；本地已有 Photon 副本可免下载）。已有 Photon 副本直接沿用，需了解上游变化时再在线读取对应文件。

查阅结论应注明文件或函数、版本/分支及适用条件。分支源码、发布版本和本地副本分别表述；取不到内容就说明缺口，不能用搜索摘要或 AI 报告代替源码。参考项目的建议不自动成为 Astra 缺陷或实施要求。（理由：各包设计前提不同，例如 Photon 公式不同不等于 Astra 缺畸变补偿）

### 阴影矩阵、Bias 与过滤

- [Iris 仓库](https://github.com/IrisShaders/Iris)：按安装版本查阴影矩阵生成、着色器转换及采样器绑定；从仓库实际分支/标签定位，不能把其他版本直接当成本机行为。
- [Iris 调试说明](https://shaders.properties/current/reference/miscellaneous/debugging_shaders/)与[矩阵说明](https://shaders.properties/current/reference/uniforms/matrices/)：需要理解引擎处理后的程序时，优先利用已有 Iris 的 debug 输出。光影选择界面的 `Ctrl+D`、`enableDebugOptions` 和实例内 `patched_shaders` 按安装版本确认；启用时遵循该版本的重启要求。输出行号不直接对应原源码（理由：Iris 补丁会插入宏与 include 展开，行号会漂移）；输出不包含运行时 uniform 数值，也不证明矩阵或 Bias 正确。
- [ShaderDoc](https://github.com/IrisShaders/ShaderDoc)：作为格式背景补充，按需查 `uniforms.md`、`const-directives.md`、`iris-features.md`；它覆盖不完整，缺项及版本冲突回到当前 Iris 文档与源码。
- [Photon 阴影源码](https://github.com/sixthsurge/photon/tree/main/shaders/include/lighting/shadows)：重点查 `distortion.glsl`、`pcss.glsl` 和必要调用方，了解偏移、过滤半径、遮挡提前结束和彩色阴影的分工。
- 对应 Astra 的 `lib/transforms.glsl`、`lib/distort.glsl`、`program/shadow.vsh/fsh`、`program/lit.vsh/fsh`、`global/lighting/shadowmap.glsl`、`global/lighting/diffuse.glsl`。分别判断投射物、原生表面、水面、体积与不同维度的路径；固定管线偏移、GLSL 法线偏移和深度余量分别分析。
- Astra 已有径向畸变对应的世界纹元宽度换算及过滤半径限制。不能仅因 Photon 公式不同就断言缺少畸变补偿，也不能照搬它的 Bias 数值、投影比例或漏光修正。

### 白色边缘伪影

- 先沿当前实现定位白边首次出现的阶段：原场景、阴影/折射接受结果、HDR 合成、Bloom、抗锯齿或显示变换。沿用 `Astra/README.md` 中已有分量显示方法；显示尺度和颜色域保持可解释。
- 阴影白边查上述投射/接收链；水岸或物体边缘查 `program/water.glsl`、`global/water/refraction.glsl`、`raytrace.glsl` 的颜色与深度配对、接受与未命中处理；高亮扩散查实际后处理消费链。
- 不把白边默认归因于 Bias，不用扩大偏移、加雾或压暗全图代替定位来源。

### 水体吸收散射与水下体积光

- 已有参考位置：`reference_shaderpacks/photon-shader/`。重点读 `shaders/include/fog/water_fog_vl.glsl`、`simple_fog.glsl`、`include/utility/phase_functions.glsl`，需要确认消费方式时读 `program/c0_vl.fsh`、`c1_blend_layers.fsh`。
- [Photon 水下体积源码](https://github.com/sixthsurge/photon/blob/main/shaders/include/fog/water_fog_vl.glsl)：参考散射/透射分开输出、入射光与观察方向的消光、水中距离换算及相位处理。其噪声焦散、多重散射近似和艺术调整不当作精确物理标准；系数不直接作为 Astra 参数。
- 对应 Astra 的 `global/water/absorption.glsl`、`light_shafts.glsl`、`lib/solas_water.glsl`、`program/scattering.fsh`、`water_composite.fsh`、`display.fsh`。普通水下雾的颜色域混合与线性光束叠加分别分析；保留已认可的 ITT 波面光量机制和分段积分，不整套移植 Photon 体积雾。
- 诊断波面光量、独立光束、介质传输与最终合成时，按实际生产者/消费者确认附件。现有 `prepare4`、`composite2` 及水下合成入口可作定位线索；Bloom 开关会改变合成落点，附件编号与含义随源码确认，不能固定认定 `colortex4` 总是水下最终图。
- 表面自遮挡修正不是水中光程，blocker 平均厚度不是可靠水体厚度；不得将它们直接代入吸收。生物群系水色转换、其他相位函数等仅在当前要求和具体问题需要时研究，不因外部报告提出就新增功能。
- 代码级借用查 [Photon 许可](https://github.com/sixthsurge/photon/blob/main/LICENSE)及片段上游出处，并维护 `Astra/THIRD-PARTY.md` 中对应事项。该许可允许研读及一定范围的再分发，对收费和提供创作者收益的平台另有限制；不能概括成任何发布均需书面许可（理由：该许可是有条件再分发，不是全场景书面许可），也不能假定 Photon 的许可覆盖其中全部第三方片段。

### 编辑器辅助

- [vscode-mcshader](https://github.com/GeForceLegend/vscode-mcshader)：需要改善 VS Code 中的 include 导航、入口展开或编辑期诊断时查阅，优先利用现有编辑器和可用扩展包，不为它搭建整套开发工具链。
- 能力依据读 `README.md`、`server/main/src/opengl.rs`、`server/main/src/constant.rs` 及必要预处理实现（两个路径 2026-10-13 经 GitHub 目录核对存在）。当前所查实现通过本机 OpenGL 编译诊断，不依赖额外的 `glslangValidator`。
- 内置 Iris/MC 版本宏可能与实例不一致，条件 include 也有行号限制；诊断不复现 Iris 补丁，不替代实际引擎行为。不要为消除扩展报错改写 Astra 的正确代码或宏分支。

### 需要实际 GPU 状态时的后续方案

- [renderdoc-skill](https://github.com/rudybear/renderdoc-skill)、[rdc-cli](https://github.com/BANANASJIM/rdc-cli)和[RenderDoc](https://github.com/baldurk/renderdoc)分别是 Agent 指引/MCP 包装、自动读取 CLI、调试器本体。该 skill 原面向 Claude Code，不能原样套用其安装命令及通用 Vulkan 配方。
- 只有当前问题确需运行时矩阵、纹理绑定、管线状态或逐事件输出时，才研究抓帧接入。优先确认本体和 Minecraft Java 启动/抓帧条件；能取得可回放帧之后，再按重复读取需求考虑 CLI 或 MCP，不预先安装整条依赖链。
- 按[官方 OpenGL 支持说明](https://github.com/baldurk/renderdoc/blob/v1.x/docs/behind_scenes/opengl_support.rst)确认回放与调试能力。OpenGL 逐行调试受驱动扩展及 GLSL 到 SPIR-V 转换条件限制；Astra 原始 compatibility GLSL 不等于 Iris 补丁后的实际程序，不能据原文件直接断言支持或不支持。不得为满足调试器而重构 Astra（理由：调试工具适配不该反向改变交付物结构）。
- 按实际程序、事件顺序和资源绑定定位阶段，自动推断的 pass 名仅作线索。像素多次写入不是重复施雾的充分证据；需要结合具体传输表达式和前后结果判断。
- CLI 接入还需匹配 RenderDoc Python 模块和解释器版本；Windows 安装器、CLI 与 skill README 的说法有差异时查实际文件，不假定本体安装即具备 Python 接口。当前环境未确认具备此链，不把候选方案写成已接入。
