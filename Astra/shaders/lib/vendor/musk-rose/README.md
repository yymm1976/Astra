# `lib/vendor/musk-rose/` — Musk Rose Shaders 4.1（作者 Rin，CC0-1.0）

来源（历史）：Musk Rose Shaders 4.1 的 `shaders/programmes/utils/musk_rose_pbr.glsl` 中的
`getEnvironmentBRDF`，以及该包随附的许可正文。相关本地参考副本已不在仓库内，因此这一出处按
**历史来源**记录，不再作为当前可复核的本地路径。本次只整理本目录已有的许可文件与
`Astra/THIRD-PARTY.md` 的既有登记，没有重新核读上游包，也没有因此新增任何代码或素材。

| 文件 | 作用 |
|---|---|
| `LICENSE.txt` | 该包随附的许可正文：CC0 1.0 Universal（Creative Commons） |

Astra 侧改动：`Astra/shaders/lib/environment_brdf.glsl` 的标量环境拟合改编自
`musk_rose_pbr.glsl::getEnvironmentBRDF`（作者 Rin，CC0-1.0）。文件头保留原来源指向的 UE4 mobile
环境 BRDF 拟合链接。共享指数、零粗糙度归一化、0–1 限幅，以及水 / 冰 / 积水的天空退路接线为
Astra 适配；原表面 Fresnel 不重复相乘。运行代码在 `lib/environment_brdf.glsl`，本目录不重复存放。

登记行见 `Astra/THIRD-PARTY.md` 登记表的 `shaders/lib/vendor/musk-rose/` 目录行与本目录
`LICENSE.txt` 的文件行。
