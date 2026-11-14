# MoonMojibake 验收对照表

> 按「2026 MoonBit 黑客松」验收标准逐条对照（MoonBit 为主 / 仓库公开 / 能够运行 /
> 工作有效 / 开源合规 / AI 可解释）。所有命令均在仓库根目录执行，使用
> `moon 0.1.20261104` / `moonc v0.10.20+65efd5b93`。
>
> 仓库：<https://github.com/Derk2006/moonmojibake> · 当前版本 **0.6.2**（mooncakes
> `build_status: success`）· 35 个以上提交，日期覆盖 2026-11-01 至 2026-11-14。

## 一、验收标准逐条对照

| # | 验收标准 | 状态 | 证据 |
|---|---|---|---|
| 1 | **MoonBit 为主** | 通过 | 全部实现为 MoonBit，13 661 行 `.mbt`（其中非测试代码 11 895 行）；唯一依赖是 MoonBit core，**零 FFI**；`moonc v0.10.20+65efd5b93` 编译通过 |
| 2 | **仓库公开、提交连续可追踪** | 通过 | <https://github.com/Derk2006/moonmojibake> 公开仓库；35 个以上提交分布在 6 个开发日（11-01 / 11-06 / 11-09 / 11-11 / 11-13 / 11-14），每次提交对应一个可说明的改动，见 `CHANGELOG.md` |
| 3 | **能够运行：README、可运行示例、必要测试** | 通过 | README 给出安装、命令行、库三套用法；`examples/detect_and_repair` 一条命令可跑；72 个单元测试在 4 个目标上全部通过；CLI 五个子命令带冒烟测试 |
| 4 | **工作有效：本期完成的实质新增** | 通过 | 11 月内从 0.1.0 迭代到 0.6.1：UTF-32、EUC-JP、四类「错误答案」修复、真正的 GB18030 四字节形式（1 087 996 条序列）、新工具链迁移。见第四节 |
| 5 | **开源合规** | 通过 | Apache-2.0（`LICENSE`）；编码表由仓库内 `scripts/gen_tables.py` 从 CPython 3.12 codecs 生成，脚本与结果一并入库、CI 校验可重现；未复用任何第三方实现；生态对照见 README「Prior art」与 `查重报告_MoonMojibake.md` |
| 6 | **AI 可解释** | 通过 | `docs/DEVELOPMENT.md` 记录开发历程、AI 使用边界、关键取舍与失败案例；每个判定规则的权重与理由在 `docs/FORMAT_NOTES.md` 逐条公开 |

## 二、五分钟复现

```sh
git clone https://github.com/Derk2006/moonmojibake && cd moonmojibake

moon version --all          # 记录工具链
moon check --deny-warn      # 零警告（警告即失败）
moon test                   # 72 passed
moon build --target js
moon run examples/detect_and_repair    # 可运行示例，见下
```

示例输出（固定输入，逐字可复现）：

```
decode
  gbk bytes -> 中文期刊

detect
  1. gbk  score=90 conf=27 errors=0  中文期刊
  2. euc-jp  score=81 conf=0 errors=0  嶄猟豚侵
  3. euc-kr  score=70 conf=0 errors=0  櫓匡퍅엷
  guess: gbk (confidence 27%)

repair
  broken: ä¸­æ–‡æµ‹è¯•
  fixed : 中文测试
  score : 45 -> 90
  chain : windows-1252 -> utf-8

ties
  pure kana ties: gbk / euc-jp  (confidence 0%)
  the text is correct under both; no label is invented
```

命令行与真实文件：

```sh
node _build/js/debug/build/cmd/moonmojibake/moonmojibake.js detect samples/gbk.txt
node _build/js/debug/build/cmd/moonmojibake/moonmojibake.js repair samples/moji_latin1.txt
python scripts/e2e_check.py       # 303/303
python scripts/space_check.py     # 2 351 159 项全字节空间差分
```

## 三、评分维度对照

| 维度 | 本项目的落点 | 可检查的位置 |
|---|---|---|
| **工程深度与实现强度** | 十三种编码双向编解码；GB18030 四字节 1 087 996 条；EUC-JP 三种形态；五信号打分；四层乱码回溯；目录扫描与批量修复；CLI + 库 + JSON 输出 | `src/mojibake/`、`cmd/moonmojibake/`、`docs/FORMAT_NOTES.md` |
| **技术贡献与攻关** | 东亚编码「都能解码成功」导致的判定难题：用文种证据、常用字比例、排他性与惩罚项组合判定；平局如实上报；GBK/GB18030 包含关系处理；乱码链的文种互斥保护 | README「Prior art」、`docs/FORMAT_NOTES.md`、第五节 |
| **可解释性与文档** | 权重与算法公开；每个限制写明而非隐藏；开发历程与 AI 使用说明；错误答案清单与回归测试对应 | `docs/FORMAT_NOTES.md`、`docs/DEVELOPMENT.md`、`docs/TEST_RECORD.md` |
| **用户体验** | 一条命令完成检测/修复/转码；`--json` 稳定字段；`--fail-if-not` 退出码可直接进 CI；错误码区分「仓库坏了」与「命令写错了」 | `docs/USAGE.md`、README Quick start |

## 四、本期（2026 年 11 月）的实质新增

| 版本 | 内容 | 为什么算实质工作 |
|---|---|---|
| 0.2.0 | UTF-32LE/BE 检测、解码、编码；BOM 顺序与代理区校验 | 补齐 13 种编码中的 Unicode 家族 |
| 0.3.0 | EUC-JP：两字节、`0x8F` 三字节（JIS X 0212）、`0x8E` 半角假名 | 日语不是只有 Shift_JIS |
| 0.5.0 | 四类「错误答案」修复：退出码语义、目录当文件、缺值参数、平局置信度 | 直接把「会返回错误答案」的路径堵死 |
| 0.6.0 | GB18030 从「GBK 的别名」改为真正的编码：四字节形式双向、206 段 BMP 表、增补平面算术映射 | 此前 `--to gb18030` 会拒绝 emoji 与生僻字，属于「列了但没做到」 |
| 0.6.1 | 迁移到 `moon 0.1.20261104`：`#derive`、显式 `pub extend`、测试显式包名；CI 改为 `--deny-warn` 并构建三后端 | 适配新工具链的真实 API 变化，而不是只换编译器 |

## 五、错误答案自查（对应此前终审反馈的同类问题）

此前另一个项目在终审被指出「报错、漏行或返回错误值」。本项目按同一标准逐条自查，
以下问题均已修复并有回归测试：

| 曾经的错误答案 | 现在的行为 | 回归测试 / 证据 |
|---|---|---|
| CLI 出错也返回 0，脚本无法判断 | 1 = 用法/IO 错误，2 = 断言失败，0 = 通过 | README「In CI」、CI 的退出码断言 |
| `detect <目录>` 抛 Node EISDIR 堆栈 | 参数校验先排除目录，返回用法错误 | CLI 冒烟与参数路径 |
| `--from` 缺值被当成「未指定」而自动检测 | 缺值即用法错误，不再猜一个看似合理的答案 | CLI 参数测试 |
| 纯假名在 GBK 与 EUC-JP 下解出同一文本，旧逻辑报「gbk，85% 置信」 | 报平局：`ambiguous` / `tied`，置信度 0，`--fail-if-not` 接受任一平局名 | `pure kana is ambiguous, not a confident gbk` |
| 宽的 GB18030 抢走只属于 GBK 的文件 | 窄编码覆盖宽编码：文件没用到四字节区就报 GBK | `detection only claims gb18030 when the bytes use its extra room` |
| `gb18030` 只是 `gbk` 的别名，编码 emoji 直接失败 | 真正的四字节编码，全部 Unicode 标量值可往返 | `gb18030 decodes the four-byte form` 等 5 个测试 |
| 私用区字符被算作「干净解码」，乱码得分虚高 | 私用区字符计入有效错误数 | `score prefers clean text over replacement characters` |
| 贪心修复把已修好的中文再转成谚文 | 文种互斥保护：汉字/谚文/假名只允许同文种内修复 | `repair does not flip a fixed text into another script` |

## 六、范围声明（回应「COSE/CBOR」驳回意见）

本项目是**字符编码检测与乱码修复**工具，不涉及 COSE、CBOR 或 RFC 9052，也不
解析或生成 CBOR 编码的消息。可直接核验：

```sh
grep -ri "cose\|cbor\|9052" --include="*.mbt" --include="*.md" .   # 无命中
```

该边界同时写在 README 的 `Scope` 节与 `docs/USAGE.md` 开头，避免再次被误认。

## 七、已知边界

短西文在 Latin-1 与 windows-1252 之间不可区分、无 BOM 的 UTF-16 中文无法举证、
纯假名平局、乱码修复受上游信息损失约束——每一条都写在 README「Limitations」中，
不做「看起来都能做」的承诺。

## 八、开源合规与来源

- 许可证：Apache-2.0，见 `LICENSE`。
- 编码表来源：`scripts/gen_tables.py` 从 CPython 3.12 标准库 codecs 导出，脚本与
  生成结果同时入库；CI 重新生成后要求 `git diff` 为空，任何人可复核每一条映射。
- 未移植、未复制任何现有实现；README 的「Prior art」逐项说明与生态中
  `LL728/moon_encoding`、`R00TK17/moonreader` 等项目的边界。
