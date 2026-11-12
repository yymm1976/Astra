# 共享任务书（Astra 参考包调研 · C 组：第五批逐包深挖）

## 任务
逐包深挖 `_analysis/batch5_unpack/<包>/` 的着色器源码，找出 **Astra 现在完全没有的机制**。只读，禁止修改 `Astra/` 与 `reference_shaderpacks/`。

## 硬规则
1. 每条结论必须给相对路径 `_analysis/batch5_unpack/<包名>/...:行号`（含起止行）。禁止凭包名、README 描述或搜索摘要下结论；必须读到源码行。
2. 每条先对 `Astra/shaders` grep 确认未实现，**写明实际用的关键词与命中数**（工具用 `ops_grep`，参数 `{path:"Astra/shaders", pattern:"...", caseInsensitive:true, outputMode:"count"}`，读返回的 `total`）。Astra 已有的直接删掉不报。
3. 标注 `〔读源码〕` 或 `〔推断〕`；没验证的写"未验证"。
4. 术语首次出现用日常中文解释一句（例如"半影=阴影边缘由全黑到全亮的过渡带"）。
5. 每条写清六项：**机制 / 出处 / Astra 现状证据（关键词+命中数） / 迁移落点与代价 / 风险 / 许可**。
6. 已否决方向不得当新建议（见下）；与旧结论不同必须显式写 **"与旧结论冲突及新证据"** 并给 file:line。
7. 关键词命中不等于机制存在（本批已有两次假阳性：wispy 的 DOF/SMAA 是空 #ifdef；luster 的 SMAA 只有出处注释）。必须追到 **pass 入口与消费者**。

## Astra 现状基线（主代理已实测，可引用；其它关键词自行 grep）
| 关键词 | 命中数 | 说明 |
|---|---|---|
| pcss\|penumbra\|blocker | 3 | 全是注释/选项文案 |
| shadowcolor | 6 | 只有 shadowcolor0 在用 |
| RSM\|reflective shadow | 0 | 无反射阴影图 |
| DDGI\|VXGI\|irradianceProbe | 0 | 无探针 GI |
| atrous\|bilateral\|SVGF\|denois | 0 | 无边缘保持降噪 |
| pixel_age\|pixelAge\|historyLength | 0 | 无像素年龄 |
| smaa\|areaTex\|searchTex\|T2x | 0 | 无 SMAA |
| catmull | 0 | 无 Catmull-Rom 历史采样 |
| localExposure\|local_exposure | 0 | 无局部曝光 |
| histogram\|percentile\|cdf | 0 | 无直方图测光 |
| daltonize\|color_blind | 0 | 无色盲校正 |
| textRenderer\|debugText | 0 | 无屏幕文字 |
| contactShadow\|ss_shadow | 0 | 无接触阴影 |
| halfRes\|half_res\|HALF_RES | 0 | 无半分辨率档位 |
| gl_VertexID\|gl_InstanceID\|billboard | 0 | 无程序化粒子层 |
| foam\|whitecap | 0 | 无浪沫 |
| 极光 aurora | 1 | 仅 NOT PORTED 注释 |
| 热浪 heatHaze | 0 | 无屏幕空间热浪 |
| 镜头光晕 lensFlare\|ghost | 2 | 仅注释 |
| 云影 cloudShadow | 16 | **已有云影缓存**（cloud_shadow_cache.glsl） |
| 时域重投影 reproject | 8 | 已有云与水的时间重投影 |
| size.buffer | 5 | 已有分档使用 |
| program.*.enabled | 1 | 使用极少 |
| textureGatherOffsets | 0 | |
| TEXTURE_3D\|sampler3D | 3 | 仅下界体素 compute 写入，无静态 3D 素材 |
| 球谐 SH9\|sphericalHarmonic | 4 | 已有天空 SH9 |
| bentNormal | 1 | ao_resolve 里一处 |

## 已否决 / 已有裁决（不要重新提议）
FSR、TAAU、自动调档、棋盘格替代四射线、共享粗深度、SSR 共享搜索、单像素倒影取色、纹元跳变（TexelSnap）、世界弯曲、POM 作为独立立项、HDR/宽色域显示决策、极光、发光实体描边（照抄不生效）、Photon 每帧搜索加历史、MakeUp 固定距离投影、LUT 调色、完整多层透明、独立水面历史、体素压缩、Voxy 远景、水下颗粒分层、`sky/weather/sun/moon=off` 引擎开关（会关掉 Astra 自己的绘制）。
详见 `docs/参考与取舍.md` 与 `shader_research/SUMMARY-batch5.md` §⑦⑧。

## 输出模板（严格遵守，中文，详细但每条 ≤ 250 字）
```
## <包名>（<文件数> 文件 / <着色器行数> 行）
**结构**：入口与程序列表（实际读到的文件名）、关键 include、shaders.properties 关键配置（profile/features/size.buffer/program.enabled）。
**许可**：<LICENSE/README 文件名>:<行号> 原文摘录 → 能否代码级借鉴 + 义务。
**Astra 完全没有的机制**
1. <机制名（通俗解释）>〔读源码〕
   - 出处：<相对路径>:<起止行>
   - 关键代码：<1-3 行原文>
   - Astra 现状：grep `<关键词>` → 0 命中（或 N 命中且为注释）
   - 迁移落点与代价：<Astra 哪个文件/pass；新缓冲/新 pass/采样数>
   - 风险：<…>
   - 许可：<…>
**已复核为"无机制"的假阳性**：<关键词 → 实际是空 #ifdef / 注释 / 死代码，给行号>
**与旧结论冲突**：<无 / 写明>
```
