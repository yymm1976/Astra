# ui-language → 主任务：公共接入交接单

本文件是 `ui-language` worktree 向主任务（水体 / 公共照明 / 阴影 / 合成）申请公共接入的唯一出口。
任务范围见 `docs/parallel-development/ui-language.md`。**不通过直接编辑共享文件绕过边界。**

⚠ 菜单结构改动一律走本文件，由主任务接入 `Astra/shaders/shaders.properties`。
禁止调整默认参数、禁止删除现有选项。

## 填写字段（与任务书一致，不得省略）

- **接口**：需要主任务提供的选项键名 / uniform 名，写准确名称
- **调用位置**：`shaders.properties` 中的位置 或 对应 shader 阶段
- **参数**：类型、取值范围、默认值（默认值只报不改，由主任务执行）
- **原因**：不这么做会怎样；为什么无法在本 worktree 内解决
- **本侧已完成**：`ui-language` 侧已经改动的文件（仅限 `Astra/shaders/lang/zh_CN.lang`、`en_US.lang`）
- **主任务侧待办**：需要对方具体改什么

## 待处理

### 1. `UNDERWATER_SHAFT_SAMPLES` 的 value 文案与滑块取值范围不匹配

- **接口**：`option.UNDERWATER_SHAFT_SAMPLES` 及其 `value.UNDERWATER_SHAFT_SAMPLES.<n>` 显示文案
- **调用位置**：`Astra/shaders/lang/zh_CN.lang` / `en_US.lang` 已有文案；取值范围由 `Astra/shaders/lib/settings.glsl` 第 121 行的滑块列表定义
- **参数**：实际滑块为 `[4 5 6 7 8 9 10]`（默认 7；profile 中 PERFORMANCE/BALANCED=7，ULTRA=10）。但两个 lang 中现存的 value 文案是 `16=流畅/Fast、24=均衡/Balanced、32=精细/Fine`，与取值范围完全不相交，游戏内不会显示这三条文案，玩家只会看到数字。
- **原因**：本 worktree 禁止删除现有选项与 value 条目，也禁止修改 settings.glsl，无法在不越界的前提下让二者一致。若长期保留会留下永不生效的死文案。
- **本侧已完成**：`zh_CN.lang` / `en_US.lang` 中该选项的 comment 已按真实范围改写为"每条水面光线沿程的阴影采样数（4–10）"，名称与说明中英一致；16/24/32 三条 value 文案原样保留未删。
- **主任务侧待办**：二选一——(a) 若采样数范围将回到 16/24/32 一档，则改回 `settings.glsl` 的滑块列表（含三个 profile 对应值）；(b) 若维持 [4–10] 范围，请删除两个 lang 中的死 value 条目，或补充与范围一致的档位文案（如 `value.UNDERWATER_SHAFT_SAMPLES.4=流畅` / `7=均衡` / `10=精细`，本侧无权删除故未添加）。

## 已接入

无。

---
本文件由 `docs/parallel-development/ui-language.md` 第 10 行、第 16 行要求建立。
