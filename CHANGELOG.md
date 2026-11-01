# Changelog

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
