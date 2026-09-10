# 并行开发目录与边界

当前主目录负责水体颜色、水下光感、公共照明、阴影与最终合成。五个 worktree 为互相独立的开发目录；提示词见同目录文件，可复制到对应目录的新任务中。创建目录不等于已经启动自动开发。

|目录|分支|负责范围|提示词|
|---|---|---|---|
|`C:\Users\杨铭\Desktop\MC模组开发\Astra并行开发\sky-clouds`|`codex/sky-clouds`|天空与云|[sky-clouds.md](sky-clouds.md)|
|`C:\Users\杨铭\Desktop\MC模组开发\Astra并行开发\terrain-foliage`|`codex/terrain-foliage`|陆地材质与植被|[terrain-foliage.md](terrain-foliage.md)|
|`C:\Users\杨铭\Desktop\MC模组开发\Astra并行开发\nether`|`codex/nether`|下界|[nether.md](nether.md)|
|`C:\Users\杨铭\Desktop\MC模组开发\Astra并行开发\end`|`codex/end`|末地|[end.md](end.md)|
|`C:\Users\杨铭\Desktop\MC模组开发\Astra并行开发\ui-language`|`codex/ui-language`|界面与配置文案|[ui-language.md](ui-language.md)|

各分支只提交自己负责的文件。公共文件接入由主任务逐项处理；任何分支都不得覆盖游戏实例。参考素材使用主目录 _analysis 的绝对路径。
