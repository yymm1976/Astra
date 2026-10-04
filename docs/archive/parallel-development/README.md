# 并行开发目录与边界

当前主目录负责水体颜色、水下光感、公共照明、阴影与最终合成。五个 worktree 为互相独立的开发目录；提示词见同目录文件，可复制到对应目录的新任务中。创建目录不等于已经启动自动开发。

|目录|分支|负责范围|提示词|
|---|---|---|---|
|`C:\Users\杨铭\Desktop\MC模组开发\Astra并行开发\sky-clouds`|`codex-sky-clouds`|天空与云|[sky-clouds.md](sky-clouds.md)|
|`C:\Users\杨铭\Desktop\MC模组开发\Astra并行开发\terrain-foliage`|`codex-terrain-foliage`|陆地材质与植被|[terrain-foliage.md](terrain-foliage.md)|
|`C:\Users\杨铭\Desktop\MC模组开发\Astra并行开发\nether`|`codex-nether`|下界|[nether.md](nether.md)|
|`C:\Users\杨铭\Desktop\MC模组开发\Astra并行开发\end`|`codex-end`|末地|[end.md](end.md)|
|`C:\Users\杨铭\Desktop\MC模组开发\Astra并行开发\ui-language`|`codex-ui-language`|界面与配置文案|[ui-language.md](ui-language.md)|

各分支只提交自己负责的文件。公共文件接入由主任务逐项处理；任何分支都不得覆盖游戏实例。参考素材使用主目录 _analysis 的绝对路径。

## 分支命名约束（不要改回带斜杠的名字）

**本仓库里分支名不得包含斜杠。** 曾用名 `codex/nether` 等在被 git 写入时会触发一个已复现的问题：
写 `refs/heads/codex/<任意名>` 会把整个 `refs/heads/codex/` 目录递归删除，一次性带走该命名空间下
的全部分支。git 返回 exit 0 且无任何报错，五个 worktree 会同时变成 unborn HEAD。

- 复现：`git update-ref refs/heads/codex/<name> <sha>` → 目录消失、`show-ref` 引用数归 0
- 两个 git 版本均可复现：2.55.0.windows.3、2.52.0.windows.1
- 对照实验排除了 git 版本、非 ASCII 路径、链接 worktree、后台清理进程四种可能
- 一级命名（`codex-nether`）完全正常

因此**所有并行 worktree 分支一律使用 `codex-<职责>` 形式**。若哪天分支又消失，用
`printf '<sha>\n' > .git/refs/heads/<branch>` 可直接手工恢复引用（git 能正常读取手工写入的引用）。
