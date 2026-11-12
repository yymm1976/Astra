# 2026-10-06 近期光影更新：线上研读

## 范围与日期口径

重点筛选北京时间 10-04 至 10-06 的近期发布，同时核对 Astra 常用参考包。先用 Modrinth 官方 `v2/search` 的 shader / updated 排序找项目，再用 `v2/project/<slug>/version` 按 `date_published` 排序核实版本、实际发版日期和作者 changelog。项目的 `date_modified` 可能只是改介绍，未用它代替发布日期。下表全部是北京时间，例如 Reverie 的 UTC 10-04 20:06 转换后为 10-05。

只查看公开元数据、网页和几份原始文本源码，没有下载 ZIP、克隆仓库或落盘新增包。此表是筛选结果，不是全网完整清单。发布事实来自上述 [Modrinth 官方 API](https://docs.modrinth.com/api/)；作者的性能描述与已读取的实现分开记录。

## 已核实近期发布

| 包 / 官方版本入口 | 版本 / 北京时间日期 | 作者说明与本次判断 | 源码情况 |
|---|---|---|---|
| [MakeUp Ultra Fast](https://modrinth.com/shader/makeup-ultra-fast-shaders/versions) | 9.5g / 10-04 | 新 Iris 附魔 glint 机制适配、末地传送门绘制；是兼容性更新，不能据此认定一般场景更快 | [作者 GitHub](https://github.com/javiergcim/MakeUpUltraFast) README 已标 9.5g；本地仍为 9.5f |
| [Reverie](https://modrinth.com/shader/reverie_shader/versions) | 1.0 / 10-05 | 正式脱离 beta，作者称改动众多，未给完整清单；可关注 Iris 特性与暖雾风格，但不猜具体算法变化 | 官方 `source_url` 为 null，公开问题入口不等于公开源 |
| [Luster](https://modrinth.com/shader/luster-shaders/versions) | 5.4 / 10-06 | Photon 派生写实向包；本版说明仅链接许可，不能把 README 全部功能称为 5.4 新增 | [作者 GitHub](https://github.com/FourthEcho/Luster)，已直接读云影、覆盖、配置及许可 |
| [Super-Duper-Vanilla-2](https://modrinth.com/shader/super-duper-vanilla-2/versions) | 2.1 / 10-04 | 此项目作者称重点改进日月、天空、雾及环境光连续过渡；未确认与原作者仓库逐项一致，不作实现背书 | 项目指向 [Eldeston 仓库](https://github.com/Eldeston/Super-Duper-Vanilla)；来源关系尚未闭合 |
| [Firmament](https://modrinth.com/shader/firmament-shaders/versions) | 0.2 / 10-04 | 作者称取消其他维度无用太阳影图、云影缓存、遮挡云/星光延后、AO 无遮挡退出；与 Astra 近期方向相近。其倍数是作者的独立阶段计时说明，不是 Astra FPS | `source_url` 为 null；MIT 元数据不等于已读到源 |
| [Velocity](https://modrinth.com/shader/velocity-shaders/versions) | velo-12 / 10-05 | 作者称重写 hybrid / realtime 阴影、优化 raycasting、修末地加载与传送门纹理；未公开具体计时证据 | `source_url` 为 null，未证实宣传的优化程度 |
| [RAY TRACING POTATO](https://modrinth.com/shader/ray-tracing-potato/versions) | 2.2.0 / 10-06 | 作者列出移动时反射偏移、雾遮挡反射白块、浅水颜色/折射与波速修正；问题类型与 Astra 水体关注点相似 | `source_url` 为 null，ARR；未阅读或采用实现 |
| [Aetherglow](https://modrinth.com/shader/aetherglow/versions) | 1.1 / 10-06 | 作者只说改变部分视觉、修错误，无具体机制 | `source_url` 为 null |
| [Incredible Graphics](https://modrinth.com/shader/incredible-graphics/versions) | 1.2.2 / 10-06 | 作者说明增加版本兼容，不当作算法更新 | `source_url` 为 null |
| [Cloud Shaders](https://modrinth.com/shader/cloud-shaders/versions) | 0.3beta / 10-06 | 作者说明主要适配 26.1.2，仍是 beta；包名不证明有新云算法 | `source_url` 为 null |
| [Potato Lite](https://modrinth.com/shader/potato-lite-shader/versions) | 4.1 / 10-06 | 无 changelog，不清楚具体修改 | `source_url` 为 null |
| [Kourin](https://modrinth.com/shader/kourin-shaders/versions) | 1 / 10-04 | 无 changelog，不据版本号猜测技术变化 | `source_url` 为 null；CC-BY-NC-SA-4.0 元数据 |

## 常用参考包并非这几天刚发版

| 包 | 官方最新版本 / 北京时间日期 | 判断 |
|---|---|---|
| [Photon](https://modrinth.com/shader/photon-shader/versions) | 1.3b / 2026-04-15 | 未查到近期新发布；开发分支与 release 分开看 |
| [Solas](https://modrinth.com/shader/solas-shader/versions) | 3.7b / 2026-08-23 | 当前本地参考已经是这个版本 |
| [Complementary Reimagined](https://modrinth.com/shader/complementary-reimagined/versions) | r5.9.3 / 2026-09-15 | 当前保留包已是该版；[作者 changelog](https://www.complementary.dev/changelogs/) 同样列出 9 月 r5.9 系列 |

## GitHub 源码阅读

MakeUp：直接读 master 的 `shaders/gbuffers_armor_glint.fsh`、`common/glint_blocks_fragment.glsl`、`common/glint_blocks_vertex.glsl`、`src/basiccoords_vertex.glsl` 和配置。已读到的 glint 包装器及公共片元与本地 9.5f 对应内容一致，仍为贴图 × tintColor / 曝光并接原写缓冲。因此没有把这些文件冒充 9.5g 新机制的具体改动锚点；新附魔机制完整落点和传送门新链尚未闭合，本轮未移植。

可继续在线查看：[glint 片元](https://github.com/javiergcim/MakeUpUltraFast/blob/master/shaders/common/glint_blocks_fragment.glsl)、[配置](https://github.com/javiergcim/MakeUpUltraFast/blob/master/shaders/shaders.properties)。许可为 LGPL-3.0-or-later，真正复用时另按台账登记。

Luster：亲自读 main 的文件与许可，确认下面的机制已存在；缺少版本前后材料，不能认定都在 5.4 刚引入：

- [cloud_shadows.glsl](https://github.com/FourthEcho/Luster/blob/main/shaders/include/lighting/cloud_shadows.glsl)：第 7 行 512² 云影目标，第 34 行开始消费者、第 41 行范围拒绝、第 52 行地平线衰减、第 55 行 bicubic 读取。Astra 已有独立云影缓存，不能重复再加一条相同用途的链。
- [cumulus.glsl](https://github.com/FourthEcho/Luster/blob/main/shaders/include/sky/clouds/cumulus.glsl)：第 40–56 行局部覆盖图/原函数分支，第 221–222 行零覆盖提前退出，后部还有覆盖图边缘衰减。值得进一步读边界和场景条件，不能仅因其有时域放大就提高 Astra 的放大倍数；后者可能加重用户已反馈的云边缘噪点和模糊。
- [shaders.properties](https://github.com/FourthEcho/Luster/blob/main/shaders/shaders.properties)：第 41 行 CUSTOM_IMAGES / ENTITY_TRANSLUCENT，第 114 / 147 行取消下界 shadow / shadowcomp，第 247 行起云影配置，第 251–260 行按时域档分配云目标，第 310–313 行按 MC 版本处理 glint 混合。下界完全取消 shadow 不能照搬到 Astra，Astra 还在此阶段捕获体素彩光。
- [LICENSE](https://github.com/FourthEcho/Luster/blob/main/LICENSE)：Luster 原创部分保留权利，允许研读和个人修改，公开再分发衍生内容需书面许可；Photon 上游许可另有作用范围。本轮未复制源码或素材。

GitHub 匿名 API 返回 `403 (rate limit exceeded)`。部分提交网页只给旧缓存或没有日期，没有把它们作为 10-06 实时最新提交的证据。后续改用 `raw.githubusercontent.com` 在内存中查看以上文件，未克隆或保存新包。Modrinth 的实际发布日期查询成功，与 GitHub 访问限制分开记录。

下一步优先关注 MakeUp 的 Iris 兼容性和 Luster 的云覆盖边界。Reverie 1.0 可作为观感参考，但没有确认可公开在线读取的官方源。本轮不把源码未核实的宣传方案实施进 Astra，也没有为调查新增一批占空间的包。
