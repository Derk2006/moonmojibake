# Changelog

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
