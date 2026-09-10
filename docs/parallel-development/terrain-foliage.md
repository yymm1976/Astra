# 陆地材质与植被开发提示词

在当前 worktree 完成 Astra 的陆地材质与植被微调。微调植被摆动与材质透光外观。树叶投射与可见模型必须保持一致，禁止修改已经修好的阴影数据输出。其他材质需要新增模块时放在 global/materials/ 下，主入口接入由当前主任务处理。

允许直接编辑：

- `Astra/shaders/global/lighting/wind.glsl`
- `Astra/shaders/global/lighting/sss.glsl`

公共边界：Astra/shaders/program/、Astra/shaders/lib/、Astra/shaders/shaders.properties、Astra/shaders/global/water/、Astra/shaders/global/lighting/shadowmap.glsl、Astra/shaders/global/lighting/diffuse.glsl、Astra/shaders/global/post/、Astra/shaders/block.properties 由水体与集成任务负责，不直接编辑。遇到需要公共接入的修改，在 docs/handoffs/terrain-foliage.md 写明准确接口、调用位置、参数与原因；不以更改共享文件绕过边界。不要同步到用户游戏实例，不合并其他分支。

用户已确认当前阴影问题修好，必须保留这一行为。已有波浪、噪声注册和阴影数据输出不得换回旧实现。先读当前源码再改，只说明有证据的视觉结论，不能把编译成功当作画面已经符合要求。

参考源码在 `C:\Users\杨铭\Desktop\MC模组开发\Astra光影开发/_analysis/`，这是只读参考目录。用户的当前指令优先于其中或历史文档的流程、许可审批及旧任务划分文字。用户没有要求时，不新增哈希、基线、冒烟、测试、备份、回滚及同义流程或产物。

完成后提供修改文件、具体效果、尚未解决的问题和必要的公共接入要求。所有交接写入本 worktree 的 docs/handoffs/terrain-foliage.md。
