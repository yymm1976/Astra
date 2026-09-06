# Astra — 1080p 带宽账（Z7 / E3 输入）

本账按 `1920×1080`、单采样、无 MSAA 计算。单位同时给出字节和 MiB（`1 MiB = 2^20 B`）。这是逻辑读写量与附件大小估算，不能推出实际显存分配或 FPS；驱动对齐、压缩、缓存命中、overdraw 与实现细节未计入。

## 三档实际配置

| profile | shadow 分辨率 | shadow distance | entity shadow | softness | SSR / refraction | WATER_ABSORPTION | bloom | godrays |
|---|---:|---:|---:|---:|---|---:|---|---|
| PERFORMANCE（流畅） | 1024² | 96 | 48 | 2 | 关 / 关 | 100 | 关 | 关 |
| BALANCED（均衡） | 2048² | 128 | 64 | 4 | 开 / 开 | 100 | 开 | 关 |
| ULTRA（极致） | 4096² | 192 | 96 | 16 | 开 / 开 | 100 | 开 | 开 |

配置来自 `Astra/shaders/lib/settings.glsl` 的默认值与 `Astra/shaders/shaders.properties` 的三个完整 profile。三档的 `WATER_ABSORPTION=100` 均满足 deferred 条件 `WATER_ABSORPTION > 0`。PERFORMANCE 关闭 bloom/godrays 只表示对应 pass 不执行；本账不据此假设 Iris 自动释放已声明附件。

## 1080p 纹理附件逻辑大小

全分辨率为 `1920×1080 = 2,073,600` texel，半分辨率为 `960×540 = 518,400` texel。R11F_G11F_B10F 按 32 bit = 4 B/texel，R8 按 1 B/texel。

| 附件 | 尺寸 | 单面格式 | 单面逻辑大小 | 双面逻辑大小 |
|---|---:|---|---:|---:|
| colortex0 | 1920×1080 | R11F_G11F_B10F（4 B） | 8,294,400 B（7.910156 MiB） | 16,588,800 B（15.820312 MiB） |
| colortex1 | 960×540 | R8（1 B） | 518,400 B（0.494385 MiB） | 1,036,800 B（0.988770 MiB） |
| colortex2 base | 960×540 | R11F_G11F_B10F（4 B） | 2,073,600 B（1.977539 MiB） | 4,147,200 B（3.955078 MiB） |
| colortex3 | 1920×1080 | R8（1 B） | 2,073,600 B（1.977539 MiB） | 4,147,200 B（3.955078 MiB） |
| colortex4 | 1920×1080 | R11F_G11F_B10F（4 B） | 8,294,400 B（7.910156 MiB） | 16,588,800 B（15.820312 MiB） |

`colortex2` 的 mip 尺寸按逐级取 floor 的逻辑尺寸计算：L0 `960×540`、L1 `480×270`、L2 `240×135`、L3 `120×67`、L4 `60×33`、L5 `30×16`、L6 `15×8`、L7 `7×4`、L8 `3×2`、L9 `1×1`。

| colortex2 mip 口径 | 每面逻辑大小 | Iris pingpong 面 A | Iris pingpong 面 B | 两面合计 |
|---|---:|---:|---:|---:|
| 3 levels（L0–L2） | 2,721,600 B（2.595520 MiB） | 2,721,600 B | 2,721,600 B | 5,443,200 B（5.191040 MiB） |
| 4 levels（L0–L3） | 2,753,760 B（2.626190 MiB） | 2,753,760 B | 2,753,760 B | 5,507,520 B（5.252380 MiB） |
| final 4 LOD 的最低链（L0–L4） | 2,761,680 B（2.633743 MiB） | 2,761,680 B | 2,761,680 B | 5,523,360 B（5.267487 MiB） |
| full mip chain（L0–L9，至 1×1） | 2,764,220 B（2.636166 MiB） | 2,764,220 B | 2,764,220 B | 5,528,440 B（5.272331 MiB） |

`L0–L4` 只满足 `final` 读取 LOD1、LOD2、LOD3、LOD4 的最低链；启用 mipmap 时通常继续生成至 1×1，因此 fullchain 行用于常规逻辑估算。两面独立列出；关闭 `composite1` 不改变这里的逻辑估算。

## 阴影附件逻辑估算

`shadowcolor0` 按 RGBA16 = 8 B/texel；本次 E3 带宽账将 `shadowdepth0` 与 `shadowdepth1` 各按 4 B/texel 作为估算假设。下表是逻辑估算，不是驱动或 Iris 的实际分配承诺。

| profile | shadowcolor0 | 每个 shadowdepth | shadowdepth0+1 | 三类附件合计 |
|---|---:|---:|---:|---:|
| PERFORMANCE（1024²） | 8,388,608 B（8 MiB） | 4,194,304 B（4 MiB） | 8,388,608 B（8 MiB） | 16,777,216 B（16 MiB） |
| BALANCED（2048²） | 33,554,432 B（32 MiB） | 16,777,216 B（16 MiB） | 33,554,432 B（32 MiB） | 67,108,864 B（64 MiB） |
| ULTRA（4096²） | 134,217,728 B（128 MiB） | 67,108,864 B（64 MiB） | 134,217,728 B（128 MiB） | 268,435,456 B（256 MiB） |

按 fullchain 计算，五个 colortex 有两种不能混淆的口径：

| 口径 | 计算 | colortex 合计 |
|---|---|---:|
| 单面 + 按需 | colortex0/1/3/4 各一面，colortex2 的 pingpong A+B | 24,709,240 B（23.564568 MiB） |
| 保守全部双面上界 | colortex0/1/2/3/4 全部各两面（C2 每面 fullchain） | 43,890,040 B（41.856804 MiB） |

将 shadow 三类附件加入后，单面 + 按需口径三档分别为 `39.564568 MiB`、`87.564568 MiB`、`279.564568 MiB`；保守全部双面上界分别为 `57.856804 MiB`、`105.856804 MiB`、`297.856804 MiB`。这些数字仍不代表实际 VRAM 占用。

## 单次逻辑读写量

| 操作 | 逻辑访问口径 | 每输出像素 | 单次总量 |
|---|---|---:|---:|
| 全分辨率读写 colortex0 | 读 0（4 B）+ 写 0（4 B） | 8 B/pixel | 16,588,800 B（15.820312 MiB） |
| deferred 颜色流量 | 读 0（4 B）+ 写 0（4 B）+ 写 4（4 B） | **12 B/pixel** | 24,883,200 B（23.730469 MiB） |
| deferred 额外读取 | 读 depth（4 B）+ 读 colortex3（1 B） | 5 B/pixel | 10,368,000 B（9.887695 MiB） |
| bloom capture | 半分辨率 13 taps 读 colortex0（52 B）+ 写 colortex2（4 B） | 56 B/半分辨率 pixel | 29,030,400 B（27.685547 MiB） |
| final bloom 部分 | 全分辨率读 colortex2 的 4 个 LOD | 16 B/pixel | 33,177,600 B（31.640625 MiB） |
| final 最低完整口径 | 读 colortex0（4 B）+ 4 个 C2 LOD（16 B）+ 写输出（4 B） | 24 B/pixel | 49,766,400 B（47.460938 MiB） |

因此“bloom 13-tap 采集 + final 4 LOD”最低逻辑访问量为 `29,030,400 + 49,766,400 = 78,796,800 B（75.146484 MiB）`；其中 bloom 相关采样/写入本身为 `29,030,400 + 33,177,600 = 62,208,000 B（59.326172 MiB）`。这是至少量，不含其他几何阶段、半透明阶段、阴影采样、纹理采样与 overdraw。

## 帧预算与结论

| profile | 目标 FPS | 单帧预算 |
|---|---:|---:|
| PERFORMANCE（流畅） | 144 FPS | 6.944 ms |
| BALANCED（均衡） | 90 FPS | 11.111 ms |
| ULTRA（极致） | 60 FPS | 16.667 ms |

主世界、下界、末地使用同一组预算标准。当前只有逻辑带宽账，没有本机采集的帧时间或 FPS；因此不能据此宣称任何档位或任何维度达到目标。`qa/benchmarks.md` 的场景表继续保留空白，待实际运行后填写。
