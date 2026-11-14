# Development notes

What was built, in what order, which decisions were hard, and where AI helped
and where it was not allowed to decide. Written for reviewers who want to know
how the project arrived at its current shape rather than only what it does.

## Timeline

| Date | Version | Work |
|---|---|---|
| 2026-11-01 | 0.1.0 | Six code pages (UTF-8, UTF-16LE/BE, GBK, Big5, Shift_JIS, EUC-KR), a no-throw decoder, five-signal scoring, `detect` / `repair` / `convert`, first CPython cross-check |
| 2026-11-06 | 0.2.0 | UTF-32LE/BE with BOM ordering and surrogate/range validation; `scan` / `fix` over a directory tree |
| 2026-11-09 | 0.5.0 | Four wrong-answer fixes (exit codes, directory-as-file, missing option value, tie confidence); exhaustive byte-space check added to CI |
| 2026-11-11 | 0.6.0 | GB18030 promoted from an alias of GBK to a real code page: four-byte form, 206-run BMP table, arithmetic supplementary planes, private-use scoring fix |
| 2026-11-13 | 0.6.1 | Toolchain migration (`#derive`, explicit `pub extend`, qualified test imports), CI hardened to `--deny-warn`, scope statement |
| 2026-11-14 | — | Acceptance checklist, test record, runnable example, this document |

The order was not planned top-down. Each version started from a concrete
question a reviewer or a user could ask, and ended with a command that answers
it:

- "Is every table row correct?" → `scripts/space_check.py`, 2 351 159 checks.
- "Does it agree with a reference implementation?" → `scripts/e2e_check.py`, 303 checks.
- "Can a script use it?" → exit codes, `--json`, `--fail-if-not`.
- "Does the package actually install?" → empty-project `moon add` test each release.

## AI usage

AI was used as a writing and exploration tool, not as the source of truth.

**Where it helped**

- Drafting decoder skeletons and the table generator from the CPython codecs API.
- Writing documentation drafts, then checking every number against a command.
- Diagnosing toolchain errors (deprecated syntax, new package manifest format)
  and proposing migration patterns that were then verified by compiling.
- Generating test *candidates* — edge cases such as truncated sequences, BOM
  ordering, private-use characters.

**Where it was not allowed to decide**

- **Ground truth.** Every expected value comes from CPython's `codecs`, not from
  a model's memory. When AI "remembered" a mapping, the mapping was checked and
  often wrong in the details (GB18030 private-use slots, JIS X 0212 cells).
- **Special-casing.** Suggestions of the form "if the text looks Chinese, pick
  GBK" were rejected: that is the wrong-answer pattern the project exists to
  avoid. The replacement is measurable signals with published weights.
- **Claims.** A statement ships only with a command that reproduces it. This is
  why the README has a command-result table rather than adjectives.

The concrete lesson: AI is good at enumerating the space of cases and bad at
knowing which answer is right. The project therefore spends its effort on
differential testing against a reference, which is exactly the part a model
cannot fake.

## Decisions that shaped the code

| Decision | Alternative rejected | Why |
|---|---|---|
| Decoders never throw; bad bytes become U+FFFD and are counted | Return `Result` per sequence | Detection must decode the same bytes under every candidate and compare. An exception aborts the comparison; an error count is a signal |
| Score "does this look like language" with five independent signals | Try each code page and take the first that decodes cleanly | In East Asian pages almost everything decodes cleanly — EUC-KR's range sits inside GBK's, Big5 and GBK share thousands of pairs. "No error" carries almost no information |
| Report ties as ties | Pick the higher-scoring label | Pure kana decodes to the same five characters under GBK and EUC-JP with the same score. A label there is a coin flip dressed as a conclusion |
| GB18030 is a real code page, not an alias | Keep the alias and document the gap | The alias made `--to gb18030` reject emoji and rare hanzi — a documented capability that does not work is worse than an absent one |
| Narrower page wins when both explain the bytes | Prefer the wider page (it "contains" the narrower) | A file that never leaves GBK's range is not evidence of GB18030; claiming otherwise inflates the answer without adding information |
| Repair refuses to cross scripts | Pure score search | Greedy search happily turns Chinese into Hangul: clean decode, higher score, wrong text. A hard veto beats a penalty because a four-point threshold loses to a ninety-point temptation |
| Zero FFI; file IO only on the js backend | Native file APIs behind FFI | Portability is the point of a MoonBit library. `--text` keeps every backend usable; only `scan` / `fix` need Node |
| Generated tables are committed | Generate at build time | Reviewers can read every mapping; CI regenerates and requires an empty diff, so drift is caught |

## Mistakes found by testing, not by reading

- **Exit code 0 on failure.** The CLI printed `error:` and exited 0. A script
  cannot tell that from success. Fixed in 0.5.0: 1 for usage/IO, 2 for a failed
  assertion.
- **Directory passed to `detect`.** `read_file` checked existence but not type,
  so Node raised `EISDIR` with a stack trace. Fixed by validating the path first.
- **Missing option value treated as absent.** `--from` at end of line meant
  "auto-detect", which produced a plausible-looking but meaningless answer.
- **Confidence on a tie.** The script-exclusivity bonus pushed a 50/50 case to
  85%. The bonus now only applies when the top score is strictly greater.
- **Private-use characters counted as clean.** A wrong decode that lands in the
  private-use area scored as zero errors. It now counts toward the error total.
- **GB18030 alias.** Documented as supported, refused anything GBK lacked.
- **Toolchain deprecations.** `} derive(...)`, implicit trait-method promotion,
  and implicit imports in blackbox tests all became warnings that `--deny-warn`
  turns into errors. Migrated in 0.6.1 rather than pinning an old compiler.

## What is deliberately unfinished

- **UTF-16 without a BOM** is under-weighted, not "solved". Proving it requires
  evidence the bytes may not contain.
- **Latin-1 vs windows-1252** on short Western text is genuinely undecidable;
  the detector says so with low confidence instead of guessing.
- **Streaming decode** is not implemented. The current API takes `Bytes`; a
  chunked API is the next natural step and would need state carried across
  chunks for all thirteen code pages.
- **`moon fmt`** is not in CI. On this codebase it rewrites `Int` to `Int32` and
  `indent?` to `indent~`, changing the public API. Formatting is reviewed by
  hand; the trade-off is documented in `docs/TEST_RECORD.md`.
