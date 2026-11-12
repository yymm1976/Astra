# `lib/vendor/bakinglab/` — MJP，BakingLab `ACES.hlsl`（MIT）

来源：`TheRealMJP/BakingLab`，文件 `BakingLab/ACES.hlsl` 与仓库根 `LICENSE`。
仓库无版本号发布，按 jsDelivr 的 `@master` 取件（2026-09-21 抓取，同日复抓一次逐字节一致）：

```
https://cdn.jsdelivr.net/gh/TheRealMJP/BakingLab@master/BakingLab/ACES.hlsl   1322 B  sha256 0dab4dbfbd748dd4d6a3f38cef00155cfa4ffb5f6a8dddf4b3368aff52e4b23f
https://cdn.jsdelivr.net/gh/TheRealMJP/BakingLab@master/LICENSE               1060 B  sha256 751878625007bd944c6f0b8b43e1bbdf47da639975d49c358832043a31f1f3e8
```

| 文件 | 作用 |
|---|---|
| `LICENSE.txt` | 仓库 `LICENSE` 原文：MIT / `Copyright (c) 2016 MJP` |
| `ACES.hlsl.orig` | 上游原件，逐字保留（HLSL，`.orig` 后缀使包内编译与静态检查不把它当代码） |

原件头部即自证归属：`Baking Lab by MJP and David Neubelt … All code licensed under the MIT license`；
`RRTAndODTFit` 上方的注释把该 fit 署名给 Stephen Hill（`@self_shadow`）。

Astra 侧改动：`Astra/shaders/lib/tonemap.glsl` 的 `aces_input_mat`/`aces_output_mat`/
`rrt_and_odt_fit`/`aces_tonemap` 四件套是这份 HLSL 的机械转写加逐字移植——`float3`→`vec3`、
`static const`→`const`、去数值 `f` 后缀、`mul(M, v)`→`M * v`、`saturate(x)`→`clamp(x, 0, 1)`，
HLSL 行主序 `float3x3` 写成 GLSL 列主序 `mat3()`（同一线性映射，不是转置数值）。矩阵数值与函数体
已逐值复算，除上述机械差异外无改动。复算命令 `python qa/tools/verify_tonemap_chain.py`。

移植路径不是直接从 GitHub 抄的：Astra 经 Mellow v3.4 `lib/tonemap_operators.glsl:23-60` 中继，
Mellow 在该处只留了一行指向本文件的 URL 注释、未登记持有人，Astra 沿用了同一行注释同样未登记，
本轮补上。登记行见 `Astra/THIRD-PARTY.md` 的 2026-09-21 T16 节。
