---
name: jetbrains-context
description: 在 Astra 中按语义定位尚不知道路径的代码，调用本机 JetBrains Context CLI；已知文件或符号直接读取或文本检索。
---

# JetBrains Context

复用 Codex 已安装的 CLI 和同一项目云端索引，不安装额外插件或数据库。参考：https://github.com/JetBrains/context 。这是 DSH 的 Shell 适配，不是官方 DSH 原生集成。

在 PowerShell 中执行：

```powershell
& 'C:/Users/杨铭/AppData/Local/Programs/JBContext/bin/jbcontext_binary.exe' search --project-path 'C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发' --limit 5 '描述所需行为及相关实现'
```

主代理先整理当前问题，将独立的相关查询放在同一批 Shell 调用中；不为一个关键词、一个文件或再次搜索派子代理。读取命中的真实源码及相邻实现，再决定是否需要按相对项目路径 `-p Astra/shaders` 缩小查询。已知路径不重复语义查询，搜索摘要不能代替源码判断。

需要账户登录及已完成的项目索引。认证、权限或索引缺失时明确报告，继续用本地源码完成可独立部分；不要声称已经接通，不自行反复登录或上传代码。用户要求更新索引时使用同一程序的 `index --project-path 'C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发'`。不修改项目 AGENTS.md，不启用固定模型或额外派工规则。
