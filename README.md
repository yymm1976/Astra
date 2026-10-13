# Astra 光影开发工作区

Minecraft 光影源码、实现记录与参考调研集中在本工作区。

**接续开发先看 [当前工作：待办、技术债与规划](docs/当前工作.md)。** 它负责当前排期与未完成事项；[Astra/README.md](Astra/README.md) 负责安装、设置与功能边界，[docs/README.md](docs/README.md) 负责按需寻找依据。默认不通读历史报告。

| 位置 | 内容 |
|---|---|
| `Astra/` | 可加载的光影包；包含着色器、纹理、语言与第三方来源登记 |
| `docs/` | 固定现行文档与专题意见；已有审查资料从文档索引进入，历史资料在 `docs/archive/` |
| `shader_research/` | 自写参考光影调研与批次汇总，入口见其 README |
| `qa/tools/` | 开发工具源码与本机路径配置说明 |
| `qa/` | 历史开发输出及本地画面资料，入口见其 README |
| `.specs/`、`.workbuddy/` | 既有项目约定与开发记录 |

## 本地资料

`reference_shaderpacks/` 与 `_analysis/` 保存第三方参考包和提取材料，不进入版本控制。根目录原有参考压缩包已整理到 `_analysis/archives/`。这些资料可继续供本机调研使用；正式借用出处以 `Astra/THIRD-PARTY.md` 为准。

2026-10-06，`reference_shaderpacks/` 已按用户要求精简到 Solas、Complementary Reimagined、Photon、Rethinking Voxels、MakeUp、Mellow、Arc 七个典型包，重复压缩包已移除；[当前清单](reference_shaderpacks/README.md) 说明用途。ITT / Steadfast 等直接上游与引擎材料继续保留在 `_analysis/` 原位置。后续新版本优先在线阅读，见 [近期更新调研](shader_research/2026-10-06-recent-online-shader-updates.md)。

`qa/local_paths.json`、`qa/runtime-feedback-*/`、新生成的原始 `.f32`／`.npy` 数据及 `.zcode/` 会话文件保持本地。实现文档、调研报告、正式纹理和文档 PNG 纳入版本控制。已纳入历史提交的开发输出继续保留原路径与版本记录；历史输出不代表当前源码的画面或帧率。
