# Changelog

## 0.6.0 — 2026-11-11

`gb18030` was listed as an alias of `gbk`. It is not one: GB18030 defines a
four-byte form that reaches every code point in Unicode, and GBK has no idea
what those bytes are. The alias promised a standard the decoder did not
implement, and `--to gb18030` refused every character GBK lacks — an emoji, a
rare hanzi, a CJK extension character. That is the same class of problem as a
documented feature that returns the wrong answer, so it is fixed here rather
than documented as a limit.

### Added

- **GB18030's four-byte form, both directions.** 1 087 996 sequences: the BMP
  is a 206-run table generated from CPython by decoding, and the supplementary
  planes are the arithmetic the standard specifies. `--to gb18030` now encodes
  any text at all, including characters outside the BMP.
- **`Charset::Gb18030`**, a real code page rather than an alias: its own
  two-byte table (GBK's, plus 2 149 private-use slots), its own reverse index,
  and the four-byte branch in both directions.
- **Exhaustive check of the four-byte space.** `space_check.py` walks every
  pointer the standard maps, decodes it through MoonBit, encodes it back, and
  compares both directions with CPython. The suite went from 127 287 checks to
  2 351 159.
- **Six new unit tests**: the four-byte form, the shared two-byte form, a round
  trip of text GBK cannot encode, an unmapped pointer, and the detection rule
  below.

### Fixed

- **A private-use character no longer buys a clean decode.** GB18030's 2 149
  private-use slots let it consume a byte pair GBK rejects, which earned the
  full "no errors" bonus. A windows-1252 sentence then scored 53 as GB18030
  against 52 as windows-1252 — the wrong page won by one point. Such a
  character now counts as a near miss, the same as an undecodable sequence.
- **GBK is reported for files that never leave GBK.** Without a rule, every
  Chinese file would be `ambiguous — gbk and gb18030`, since GB18030 decodes all
  of it to the same text. A wider page is now dropped when a narrower one
  produces byte-identical text, and only then.

## 0.5.0 — 2026-11-09

This release is about the answers a tool gives when it cannot give a good one.
Three of them were wrong, and wrong in the worst way: plausible, quiet, and
exiting 0.

### Fixed

- **Every failure path now exits non-zero.** `detect`, `repair` and `convert`
  printed `error: …` and returned 0, so a missing file, a misspelled encoding
  or an unrepresentable target all looked like success to a shell or CI job.
  Exit codes are now 0 success, 1 usage/IO error, 2 assertion failed.
- **Reading a directory no longer leaks a Node stack trace.** The js FFI tested
  `exists` only, and `readFileSync` on a directory throws EISDIR, so
  `mm detect some-dir/` printed `node:fs:736` instead of a diagnostic.
  `read_file` now reports "not a file" and each command owns its message.
- **A missing option value is an error, not a silent fallback.** `--from` at
  the end of a command line used to parse as "no encoding given", so detection
  ran and printed a confident answer to a question the user never asked.
  `--text` combined with a non-UTF-8 `--from` is rejected for the same reason:
  `--text` bytes are UTF-8 by construction, and reading them as GBK can only
  produce mojibake.
- **Tied readings are reported as ties.** EUC-JP hiragana occupies the JIS X
  0208 rows GBK keeps for the same characters, so kana-only bytes decode to
  identical text under both names. Detection named `gbk` at 85% confidence —
  a coin flip dressed as a finding — because the `exclusive_script` floor
  fired without checking whether the tie had actually been broken. It now
  requires `top > second`; the confidence is 0, `detect` prints the tied
  candidates, `--json` carries `ambiguous` and `tied`, and `--fail-if-not`
  accepts either name.

### Added

- `is_ambiguous(rows)`, `ambiguous_candidates(rows)` and `is_ascii_text(text)`
  in the library, so callers can act on a tie instead of inheriting one label.
- [`scripts/space_check.py`](scripts/space_check.py) — an exhaustive
  differential test against CPython in both directions: every lead/trail pair
  for GBK, Big5, Shift_JIS and EUC-KR, every JIS X 0212 cell, every half-width
  katakana spelling, and every character encoded back. 63 677 decodes and
  63 610 encodes, 127 287 checks, no missing rows, no wrong code points.
- CLI contract checks in `e2e_check.py`: 257 checks now, including exit codes
  and the "a directory is not a file" case.
- Unit tests 61 → 67.

## 0.4.0 — 2026-11-09

### Added

- **`repair_auto(bytes)`** — reads bytes nobody labelled and returns the encoding
  it settled on plus the repair result: UTF-8 when it decodes cleanly, detection
  otherwise, then the same repair search as `repair`. The sequence previously
  lived inline in `cmd_repair`, where no test could reach it. `AutoFix::changed()`
  answers whether writing the result back would change anything.
- **`mm fix <dir>`** — repairs a whole tree, which is the half `scan` was
  missing. Dry run by default; `--write` applies. Each file is reported as
  `transcode`, `repair: A -> B`, or both, and binary files are counted and left
  alone. A second run finds nothing to change.
- **`--fail-if-not <encoding>`** on `detect` and `scan` — turns the walk into an
  assertion for CI. Exits `2` when a file reads as anything else, `1` when the
  command itself was called wrong. `--json` carries `fail_if_not` and
  `assert_ok`.
- `--json` support for `fix`, and `fail_if_not` / `assert_ok` fields on `scan`.
- CI steps for both: the dry-run → write → re-run sequence must be idempotent and
  leave every file readable as UTF-8, and the gate must return `2` for `samples`
  and `0` for a directory holding only UTF-8.

### Changed

- `cmd repair` now calls `repair_auto` instead of repeating the read-then-repair
  sequence.
- Unit tests 57 → 61.

## 0.3.0 — 2026-11-09

### Added

- **EUC-JP**, in both directions, so the candidate set is now twelve and
  Japanese is no longer reachable only through Shift_JIS. Three forms are
  handled: JIS X 0208 in the shared pair table (6 879 mappings), JIS X 0212
  behind the `0x8F` prefix in a separate 94×94 table (6 067 mappings), and
  half-width katakana as `0x8E` + `0xA1..0xDF`, computed rather than tabulated.
  Encoding consults the pair table first, so a character mapped in both levels
  keeps its standard two-byte spelling and round trips are stable. Aliases:
  `eucjp`, `ujis`, `hp-ux-euc`.
- **JIS X 0208 level-1 char set** (2 965 characters) in `tables_gen.mbt`, used
  as the frequency model for Japanese. Generated from CPython like the rest.

### Fixed

- **Japanese files were attributed to GBK.** EUC-JP's byte range nests inside
  GBK's, and GBK reserves the same `0xA4`/`0xA5` rows for kana, so a Japanese
  file decoded as GBK with zero errors *and kept its kana* — a 55-byte sample
  tied at 88/88 and lost only on candidate order. The first attempt at a fix,
  "are these kanji in the JIS repertoire at all", does not work: JIS holds about
  7 000 ideographs and therefore most Chinese hanzi too. The scorer now checks
  the kanji against JIS level 1 and subtracts up to 30 points, measured over the
  ideographs only, and only when the text contains kana. Text without kana is
  untouched, so GBK / Big5 / EUC-KR detection is unchanged.

### Changed

- `Charset::family()` is no longer one "CJK" bucket: Shift_JIS and EUC-JP report
  `Japanese`, EUC-KR reports `Korean`. The JSON output carries the new values.

## 0.2.0 — 2026-11-06

### Added

- **UTF-32LE / UTF-32BE** — decoding, encoding, detection and BOM handling, so
  the candidate set is now eleven. UTF-32 needs its own evidence rule (at least
  half of the code units must have a zero high half) and a BOM check that runs
  *before* UTF-16, because `FF FE 00 00` starts with the UTF-16LE BOM.
- **`scan`** — walks a directory, tallies every file by encoding, and reports
  non-text files as `binary` instead of force-decoding them into nonsense.
  Accepts `-r` to recurse. Unreadable and empty files are reported, not fatal.
- **`--json`** on `detect`, `repair` and `scan` — one compact object per run,
  stable field names, CJK emitted as-is. `repair.chain` is an array of
  `{wrong, right}` steps rather than a rendered string, so callers can inspect
  individual layers.
- **`looks_binary`** — public NUL-byte test, waived for UTF-16/32 shaped input.

### Fixed

- **Repair could translate Chinese into Korean.** The greedy search is allowed
  four rounds, and a later round could take already-correct 你好, re-encode it as
  EUC-KR, decode it back as Hangul, and call that an improvement — zero errors
  and a higher score, because Hangul has no frequency model to hold it back.
  Fixing the symptom by removing UTF-16 as a target was not enough. Each round
  now computes the dominant script of its input and refuses a step that swaps
  Han, Hangul or kana for a different one. Latin and script-less input may still
  go anywhere; that is the case repair exists for. Caught by the new JSON test,
  not by any of the existing ones.

- **CI was red from the first commit, and the cause was a reproducibility bug.**
  The "regenerated tables are up to date" job hashed differently on CI than on
  the author's machine, because `gen_tables.py` topped up the common-character
  set from a corpus file that sat outside the repository. That file existed
  locally and not in CI, so the committed table held one character CI could not
  reproduce. The generator now reads nothing but the codecs and the standards,
  the set is exactly 9 156 characters, and CI pins Python 3.12 because the codec
  tables themselves are part of the input.

### Changed

- 31 → 48 unit tests.
- CLI usage text lists `scan`, `-r` and `--json`.

## 0.1.0 — 2026-11-01

First release.

### Added

- **Decoders** for UTF-8, UTF-16LE/BE, GBK, Big5, Shift_JIS, EUC-KR, ISO-8859-1
  and windows-1252. Every decoder is total: malformed input becomes U+FFFD and
  is counted, never raised, so candidate readings can be compared.
- **`detect`** — ranks all nine candidates by a five-signal text-likeness score,
  with a confidence derived from the gap to the runner-up. Handles BOMs
  exactly, treats valid multi-byte UTF-8 as proof, and requires BOM-less UTF-16
  to show the alternating-zero pattern.
- **`repair`** — searches `(wrong, right)` re-encode/decode pairs, accepts only
  zero-error candidates with a real score gain, and chains up to four layers.
  Returns the chain, not just the result.
- **`encode`** — reverse lookup for all supported code pages; `None` when a
  character has no representation, which repair uses to prune its search.
- **CLI** with `detect`, `repair` and `convert`, plus `--text` so the tool still
  runs on backends without a filesystem.
- **Generated tables** — 50 605 two-byte mappings built from CPython codecs by
  `scripts/gen_tables.py`, committed for reproducibility.
- **Common-character set** — 9 157 characters derived from the GB2312 and Big5
  level-1 ranges, used as the frequency signal without shipping a corpus.
- 31 unit tests and a 192-check end-to-end comparison against CPython.

### Design notes worth keeping

- Sorting ties keep `Charset::all()` order, so ASCII resolves to UTF-8.
- Half-width katakana is excluded from script-neutral characters; otherwise a
  Chinese code page read as Shift_JIS looks like ordinary punctuation.
- UTF-16 is deliberately absent from repair targets; allowing it made repair
  turn Chinese into Hangul.
