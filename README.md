# Astra 光影开发工作区

Minecraft 光影源码、实现记录与参考调研集中在本工作区。光影包说明与设置入口见 [Astra/README.md](Astra/README.md)，近期模块改动见 [docs/README.md](docs/README.md)。

| 位置 | 内容 |
|---|---|
| `Astra/` | 可加载的光影包；包含着色器、纹理、语言与第三方来源登记 |
| `docs/` | 开发与审查记录；早期材料集中在 `docs/archive/`，交接材料在 `docs/handoffs/` |
| `shader_research/` | 自写参考光影调研与批次汇总，入口见其 README |
| `qa/tools/` | 开发工具源码与本机路径配置说明 |
| `qa/` | 历史开发输出及本地画面资料，入口见其 README |
| `.specs/`、`.workbuddy/` | 既有项目约定与开发记录 |

## 本地资料

`reference_shaderpacks/` 与 `_analysis/` 保存第三方参考包和提取材料，不进入版本控制。根目录原有参考压缩包已整理到 `_analysis/archives/`。这些资料可继续供本机调研使用；正式借用出处以 `Astra/THIRD-PARTY.md` 为准。

`qa/local_paths.json`、`qa/runtime-feedback-*/`、新生成的原始 `.f32`／`.npy` 数据及 `.zcode/` 会话文件保持本地。实现文档、调研报告、正式纹理和文档 PNG 纳入版本控制。已纳入历史提交的开发输出继续保留原路径与版本记录；历史输出不代表当前源码的画面或帧率。
