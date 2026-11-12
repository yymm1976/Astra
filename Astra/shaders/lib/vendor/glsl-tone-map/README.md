# `lib/vendor/glsl-tone-map/` — Damien Seguin, glsl-tone-map 2.3.1（MIT）

来源：npm 包 `glsl-tone-map@2.3.1`（仓库 `dmnsgn/shaders-tone-map`，`Copyright (C) 2019 Damien Seguin`）。
取件方式：`https://registry.npmjs.org/glsl-tone-map/-/glsl-tone-map-2.3.1.tgz`，
tarball 13228 字节，`sha256 = 106d5d84e22ee37023f862aa22bacfd6699582518b3721ad947bbc0fa3f666e5`，
`sha1(shasum) = fae727df7a09227c8621b54deba18084c30c0889`；本目录六个文件逐字节取自该 tarball。

| 文件 | 作用 |
|---|---|
| `LICENSE.md` | 上游 MIT 原文（唯一一份，包内其他文件不再复制许可正文） |
| `uchimura.glsl.orig` | Astra `lib/tonemap.glsl` 的 `uchimura_tonemap*()` 原件 |
| `agx.glsl.orig` | `agx_cdl()`/`agx_punchy()`/`agx_tonemap()` 与 AgX 常数、两张 inset/outset 矩阵原件 |
| `aces.glsl.orig` | **未移植**的旁证：Narkowicz 亮度曲线版 ACES |
| `acesHill.glsl.orig` | **未移植**的旁证：Seguin 对同一份 BakingLab fit 的 GLSL 移植 |
| `reinhardJodie.glsl.orig` | **未移植**的旁证：Rec.709 版 Reinhard-Jodie |

Astra 侧改动：只有 `agx_cdl()` 多一处 `max(..., vec3(0.0))` 防 NaN（分数指数对负底数），其余逐字相同，
仅按 design.md 3.2 改 snake_case 命名。`.orig` 后缀使 `check_pack.py` 的编译与静态检查不把它当代码。

后三个 `.orig` 是审计证据，不是待办：包内 `lib/tonemap.glsl` 的 ACES 块究竟抄自哪一份，
靠两个旁证文件不共享的注释判定；复算命令 `python qa/tools/verify_tonemap_chain.py`。
登记行见 `Astra/THIRD-PARTY.md` 的 2026-09-21 T16 节。
