# MoonMojibake 验收对照表

> 按「2026 MoonBit 黑客松」验收标准逐条对照（MoonBit 为主 / 仓库公开 / 能够运行 /
> 工作有效 / 开源合规 / AI 可解释）。所有命令均在仓库根目录执行，使用
> `moon 0.1.20261117` / `moonc v0.10.21+06da1ed44`。
>
> 仓库：<https://github.com/Derk2006/moonmojibake> · 当前版本 **0.7.1**（mooncakes
> 已发布、未 yanked；空项目 `moon add` 实测 1/1 通过）· 69 个提交，分布在
> 2026-11-01 至 2026-11-23 的 13 个开发日。

## 一、验收标准逐条对照

| # | 验收标准 | 状态 | 证据 |
|---|---|---|---|
| 1 | **MoonBit 为主** | 通过 | 全部实现为 MoonBit，14 308 行 `.mbt`（其中非测试代码 13 402 行）；唯一依赖是 MoonBit core，**零 FFI**；`moonc v0.10.21+06da1ed44` 编译通过 |
| 2 | **仓库公开、提交连续可追踪** | 通过 | <https://github.com/Derk2006/moonmojibake> 公开仓库；69 个提交分布在 13 个开发日（11-01 / 11-06 / 11-09 / 11-11 / 11-13 / 11-14 / 11-15 / 11-16 / 11-17 / 11-18 / 11-21 / 11-22 / 11-23，`git log --format=%ad --date=short \| sort -u` 可复核），每次提交对应一个可说明的改动，见 `CHANGELOG.md`；未完成事项以 Issue 记录（#1 拉丁-1 与 windows-1252 的平局由 0.7.0 关闭、#2 detect 的全量解码上界由 0.7.1 关闭，均附验证说明），已完成的改动走分支和 PR 合并（#4 JSON schema），Issue #3 由该 PR 关闭 |
| 3 | **能够运行：README、可运行示例、必要测试** | 通过 | README 给出安装、命令行、库三套用法；`examples/detect_and_repair` 一条命令可跑；84 个单元测试在 4 个目标上全部通过；CLI 五个子命令带冒烟测试 |
| 4 | **工作有效：本期完成的实质新增** | 通过 | 11 月内从 0.1.0 迭代到 0.7.1：UTF-32、EUC-JP、四类「错误答案」修复、真正的 GB18030 四字节形式（1 087 996 条序列）、新工具链迁移、性能基准与准确率基准（后者找出并修掉无 BOM UTF-16 中文被误判）、`--json` schema 版本、等价标签合并、`detect` 三处重复工作消除。见第四节 |
| 5 | **开源合规** | 通过 | Apache-2.0（`LICENSE`）；编码表由仓库内 `scripts/gen_tables.py` 从 CPython 3.12 codecs 生成，脚本与结果一并入库、CI 校验可重现；未复用任何第三方实现；生态对照见 README「Prior art」与 `查重报告_MoonMojibake.md` |
| 6 | **AI 可解释** | 通过 | `docs/DEVELOPMENT.md` 记录开发历程、AI 使用边界、关键取舍与失败案例；每个判定规则的权重与理由在 `docs/FORMAT_NOTES.md` 逐条公开 |

## 二、五分钟复现

```sh
git clone https://github.com/Derk2006/moonmojibake && cd moonmojibake

moon version --all          # 记录工具链
moon check --deny-warn      # 零警告（警告即失败）
moon test                   # 84 passed
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

aliases
  guess: windows-1252  score=52
  same reading under: latin1
  confidence: 0% — the text is certain, the name is not
```

命令行与真实文件：

```sh
node _build/js/debug/build/cmd/moonmojibake/moonmojibake.js detect samples/gbk.txt
node _build/js/debug/build/cmd/moonmojibake/moonmojibake.js repair samples/moji_latin1.txt
python scripts/e2e_check.py       # 303/303
python scripts/space_check.py     # 2 351 159 项全字节空间差分
```

## 三、评分维度对照

官方季度赛评分准则为四项、每项 25 分，按「一般 / 良好 / 优秀」三档评估。下表左列
是官方对「优秀」档的原文描述，右列是本项目的落点与可检查的证据。

| 官方维度（25 分）与「优秀」档原文 | 本项目的落点 | 可检查的位置 |
|---|---|---|
| **01 工程深度与实现强度**：核心成果完整且具有足够强度，关键场景得到验证，范围变化和未完成事项交代清楚，整体达到或超过预期 | 十三种编码双向编解码；GB18030 四字节 1 087 996 条；EUC-JP 三种形态；五信号打分；四层乱码回溯；目录扫描与批量修复；CLI + 库 + JSON。关键场景有基准验证（31 条标注语料 top-1 100%、三后端 84 测试全过）；未完成事项与边界在第七节和 README `Limitations` 中逐条写明 | `src/mojibake/`、`cmd/moonmojibake/`、`docs/BENCHMARK.md`、`docs/FORMAT_NOTES.md` |
| **02 技术贡献与攻关**：解决了实质性难题，对约束、取舍和边界有深入掌握，并形成高质量的 MoonBit 原生设计或技术突破 | 东亚编码「都能解码成功」导致的判定难题：文种证据、常用字比例、排他性与惩罚项组合判定；平局如实上报而非猜一个标签；GBK/GB18030 包含关系的窄覆盖宽；乱码链的文种互斥保护；无 BOM UTF-16 的「仅当别无可解释」复核规则及其反向护栏 | README `Prior art`、`docs/FORMAT_NOTES.md`、`docs/BENCHMARK.md` 第三节 |
| **03 生态增量**：通过数据、场景、采用或独立验证证明了显著改进，为 MoonBit 带来重要的新能力、平台适配或广泛复用价值 | 生态里的检测有三种形态：解析器按 BOM/规格嗅探（答案是规范给的）、文件读取库的辅助函数（单结果、无置信度、自承分不清 GBK/Big5）、以及 2026-10 出现的 `mbchardet`（chardetng 的移植，带分数与 WHATWG 嗅探）。第三种是目前唯一正面重叠的实现，边界写在 README `Prior art`：它是浏览器「猜网页编码」的移植，本项目做的是取证与逆变换——候选表 + 置信度 + 平局语义 + 无 BOM 的 UTF-16/32 + 乱码还原，这四项它都不提供。同一套 31 条标注语料上，本项目 top-1 100%（31/31），`mbchardet` 27/31（失手为 3 条无 BOM 的 UTF-16 与 1 条短日文），读文件式检测退化后的两条兜底基线各 12.9%。项目已发布 mooncakes，可在任意新项目中 `moon add` 直接复用 | README `Prior art`、`docs/BENCHMARK.md`、`查重报告_MoonMojibake.md` 第 8 节、第五节 |
| **04 开发与验证能力**：形成稳定、可重复的任务拆解和验证闭环，综合使用 Harness、回归、基准、自动化及 AI 校验，并能展示其实际发现和防止错误的效果 | Harness：`e2e_check.py`（303 项对 CPython）、`space_check.py`（2 351 159 项全字节空间差分）、`accuracy_check.py`（准确率基准 + CI 下限）；回归：84 个单元测试 + 每个已修错误都有一条钉住它的测试；基准：`benches/`（六项吞吐，wasm/js 双后端）；自动化：CI 跑零警告检查、四目标测试、三后端构建、可重现性校验、示例断言、退出码语义、幂等性；AI 校验：AI 生成的编码表与判定规则一律用 CPython 与全空间差分复核，不采信「看起来对」 | `scripts/`、`benches/`、`.github/workflows/ci.yml`、`docs/BENCHMARK.md`、`docs/DEVELOPMENT.md` |

第四节记「本期实质新增」，第五节记「错误答案自查」——后者正是维度四所要求的
「展示其实际发现和防止错误的效果」。

## 四、本期（2026 年 11 月）的实质新增

| 版本 | 内容 | 为什么算实质工作 |
|---|---|---|
| 0.2.0 | UTF-32LE/BE 检测、解码、编码；BOM 顺序与代理区校验 | 补齐 13 种编码中的 Unicode 家族 |
| 0.3.0 | EUC-JP：两字节、`0x8F` 三字节（JIS X 0212）、`0x8E` 半角假名 | 日语不是只有 Shift_JIS |
| 0.5.0 | 四类「错误答案」修复：退出码语义、目录当文件、缺值参数、平局置信度 | 直接把「会返回错误答案」的路径堵死 |
| 0.6.0 | GB18030 从「GBK 的别名」改为真正的编码：四字节形式双向、206 段 BMP 表、增补平面算术映射 | 此前 `--to gb18030` 会拒绝 emoji 与生僻字，属于「列了但没做到」 |
| 0.6.1 | 迁移到 `moon 0.1.20261104`：`#derive`、显式 `pub extend`、测试显式包名；CI 改为 `--deny-warn` 并构建三后端 | 适配新工具链的真实 API 变化，而不是只换编译器 |
| 0.6.2 | 六个基准（`benches/`）、31 例标注语料 + 两条外部基线的准确率基准、`docs/BENCHMARK.md` | 把「更快」「更准」从形容词变成可复跑的数字 |
| 0.6.3 | 准确率基准当场抓出无 BOM UTF-16 中文被判 latin1，修复并补三条反向护栏 | 度量本身发现了错误答案，而不是为已有结论背书 |
| 0.6.4 | `--json` 每个对象的首键 `"schema":1`，四个写出点共用同一常量 | 外部消费者可以判断自己读的是哪一版契约 |
| 0.7.0 | 一个候选行 = 一种「读法」而不是一个「名字」：等价标签合并为一行（`equivalent` / `also`），置信度在标签不可判时归零 | 同一个读数被当成两个候选，会把真正的第二名挤出候选表；这也是 Issue #1 记录的问题 |
| 0.7.1 | 去掉 `detect` 里的三处重复工作（四次宽编码证据扫描合为一次；`text_score` 复用已数好的文种计数；GBK 零错误时 GB18030 复用其解码与分数，无 C1 字节时 ISO-8859-1 复用 windows-1252）；32 KiB 3.18 ms → 2.20 ms | 性能上界是 Issue #2 记录的真实问题；三处改动都用「与旧二进制逐字节对比」+ 两条表/扫描等价性测试钉住，加速不以改变答案为代价 |

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
| 短西文把 `windows-1252` 和 `latin1` 当成两个候选，占掉候选表前两行，真正的第二名被挤出前三 | 同一读数只占一行，别名进 `equivalent` / `also`；标签不可判时置信度为 0 | `latin-1 and windows-1252 are one candidate, not two`、`a byte only windows-1252 defines keeps the two labels apart` |

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
  `LL728/moon_encoding`、`R00TK17/moonreader`、`Fyx-9998/mbchardet` 等项目的边界；
  `查重报告_MoonMojibake.md` 第 8 节记录 2026-11-21 的第三轮复核与结论修正。

## 九、验收自查实跑记录（2026-11-22 复跑）

验收不应该是「应该能过」，而应该是「今天在这台机器上跑过」。本节把
`.github/workflows/ci.yml` 的每一步在本地逐步执行一遍，不挑步骤、不改断言。
2026-11-21 首次执行，2026-11-22 在同一工具链上复跑，结果一致；2026-11-23 又
复核了 `moon test`（84 / 84）与空项目安装（见 `docs/TEST_RECORD.md`）。

- 环境：Windows 11 + Git Bash；`moon 0.1.20261117` / `moonc v0.10.21+06da1ed44`；
  **Python 3.12.15**（与 CI 钉住的 3.12 一致，编码表可重现性依赖解释器版本）；
  Node v22.22.2。
- 方法：以 CI 的 YAML 为准逐条执行，命令与断言原样照搬。
- 路径说明：Windows 原生 `python` 不解析 MSYS 的 `/tmp`（会去找 `C:\tmp`），
  因此第 14、15 步把输出文件放在 `$TEMP` 下复跑，断言逐字不变；其余步骤不受影响。

| # | CI 步骤 | 结果 | 关键输出 |
|---|---|---|---|
| 1 | 工具链 | 通过 | `moon 0.1.20261117` / `moonc v0.10.21+06da1ed44` |
| 2 | `moon check --deny-warn` | 通过 | 0 warning（警告即失败） |
| 3 | `moon test` | 通过 | **84 / 84**（default；js / wasm / wasm-gc 三个后端补跑亦各 84 / 84） |
| 4 | 可运行示例 | 通过 | 四条 `grep` 断言全部命中（gbk、windows-1252→utf-8、假名平局、latin1 别名） |
| 5 | `moon build --target js` | 通过 | CLI 产物生成，后续步骤依赖它 |
| 6 | `moon build --target wasm` | 通过 | |
| 7 | `moon build --target wasm-gc` | 通过 | |
| 8 | 编码表可重现 | 通过 | `gen_tables.py` 重跑后 `git diff` 为空 |
| 9 | 与 CPython 对照 | 通过 | **303 / 303** |
| 10 | 准确率下限 | 通过 | top-1 **100.0%**，门槛 95% |
| 11 | 全字节空间差分 | 通过 | **2 351 159 / 2 351 159** 与 CPython 一致 |
| 12 | 等价标签合并 | 通过 | `also == ["latin1"]`、`ambiguous == true`、候选表无重复行、`--fail-if-not` 两名字都接受 |
| 13 | CLI 冒烟 | 通过 | `guess: gbk`；`latin1 -> utf-8` |
| 14 | `--json` schema 版本 | 通过 | `detect` / `repair` / `scan` / `fix` 四个子命令首键均为 `schema: 1` |
| 15 | 目录修复幂等 | 通过 | 预览 7 改 0 写 → 落盘 7 改 7 写 → 再跑 0 改；七个文件均可按 UTF-8 读回 |
| 16 | UTF-8 门禁退出码 | 通过 | 目录不符 2、文件不符 2、符合 0 |

补充证据：

- 远端 CI 在 `main` 的最新提交上全部通过（2026-11-23；
  <https://github.com/Derk2006/moonmojibake/actions>）。
- 0.7.1 已发布至 mooncakes，空项目 `moon add` 安装与运行验证记在
  `docs/TEST_RECORD.md`「安装验证」一节。
- 本节 16 步 **无失败项**；六条验收标准因此都有可执行的证据，而不是描述。

