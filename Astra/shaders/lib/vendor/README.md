# `lib/vendor/` — 第三方文件物理隔离目录

依据 `.specs/astra-shader/design.md` §9.2 与借鉴调研 P2-10 建立。
本目录是全包**唯一**存放第三方原始文件与许可证原文的地方。机械检查见 `python qa/tools/check_pack.py` 第 15 项。

## 目录形状

一个上游一个目录，目录名 = 上游包的小写名：

```
lib/vendor/renderpearl/
    LICENSE.txt          许可证原文；上游归档不带许可证时，写该许可证的标准全文，
                         并在 README.md 里给出来源 URL 与版本（P2-13 的 Miniature 条目就是这种）
    README.md            登记：取自哪个版本、哪个文件、Astra 侧改了什么、按什么条款使用
    compat.glsl.orig     （可选）上游源码原件，逐字保留，`.orig` 后缀使编译与静态检查都不把它当代码
```

取用方式两种，都合法：

- **A · 改写进正常分层**：本目录只放许可证与原件备查；Astra 实际使用的文件按正常分层放在 `lib/`、`global/`、`program/` 里，文件头写 1–3 行出处短注，并在 `Astra/THIRD-PARTY.md` 登记一行。`THIRD-PARTY.md` 登记表里的既有借用行全部是这种。
- **B · 原样编译进包**：上游模块直接放本目录（不带 `.orig`），由包内 `#include "/lib/vendor/<up>/x.glsl"` 引用。此时它就是普通模块，`check_pack.py` 的 include 图、符号声明、选项消费、穷举编译各项一律适用——没人 include 的 vendor 模块就是孤儿，会 FAIL。

## 登记规则

1. 每个目录必须在 `Astra/THIRD-PARTY.md` 有登记行：目录本身写 `shaders/lib/vendor/<upstream>/`，
   其中**除 README.md 外**的每个文件按全路径 `shaders/lib/vendor/<upstream>/<file>` 单独登记。
   README.md 是 Astra 自写文本，由其所在目录行覆盖。
2. 每个目录必须带许可证原文（文件名以 `LICENSE` / `LICENCE` / `COPYING` 开头）。缺这一条即 FAIL。
3. 许可证正文**只存在于本目录**。包内任何其他文件出现 MIT / BSD / GPL 正文段落即为 FAIL。

## 反规范：许可声明绝不乘以文件数

本目录存在的另一半理由是防止参照包里同一个错误——把许可头逐文件复制：

| 包 | 内嵌许可头的文件数 | 行数 | 占全包 |
|---|---|---|---|
| VanillaPlus | 224 | 4,384 | 38.5% |
| Sildur's | 109 | 1,526 | 8.2% |
| LIGHT | 72 | 1,461 | 11.3% |

Astra 的文件头惯例是 1–3 行短注：来源包 + 版本 + SPDX 标识 + 指向本目录与 `THIRD-PARTY.md`。
署名条款（MIT 要求保留版权行与许可声明）由**该声明出现在 THIRD-PARTY.md 与本目录各一次**满足，不由乘以文件数满足。
