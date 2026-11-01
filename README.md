# MoonMojibake — Encoding Forensics & Mojibake Repair for MoonBit

[![CI](https://github.com/Derk2006/moonmojibake/actions/workflows/ci.yml/badge.svg)](https://github.com/Derk2006/moonmojibake/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![MoonBit](https://img.shields.io/badge/MoonBit-zero%20FFI-purple.svg)](https://www.moonbitlang.com/)

**Given bytes with no declared encoding, work out what they are. Given text that
is already ruined, work out how it was ruined and undo it.**

MoonMojibake does two things the MoonBit ecosystem did not have:

1. **Detection** — it answers *"what encoding is this file?"* without being told.
   It decodes the same bytes under every code page it knows, scores how much
   each result looks like a real language, and ranks them with a confidence.
2. **Repair** — it answers *"this text is mojibake, what happened?"* It searches
   for the re-encode/decode step that turns the garbage back into text, applies
   it, and repeats, because files really do travel through more than one broken
   tool. The result comes with the chain that produced it, e.g.
   `windows-1252 -> utf-8`.

Existing packages such as `LL728/moon_encoding` and `f4ah6o/encoding_sjis` solve
a different problem: they map a *known* label to a decoder. MoonMojibake is what
you reach for when there is no label, or when the label is wrong.

---

## Status

| Area | State |
|---|---|
| Code pages — GBK, Big5, Shift_JIS, EUC-KR | ✅ 50 605 two-byte mappings, generated from CPython codecs |
| Code pages — UTF-8, UTF-16LE/BE, Latin-1, windows-1252 | ✅ |
| Detection — ranking, confidence, BOM handling | ✅ 9 candidates per call |
| Repair — chained mojibake, up to 4 layers | ✅ returns the re-encode chain |
| CLI — `detect` / `repair` / `convert` | ✅ js backend (Node), library works on every backend |
| Unit tests | ✅ 31 passing (`moon test`) |
| Cross-check against CPython | ✅ 192/192 (`scripts/e2e_check.py`) |
| Dependencies | ✅ MoonBit core only, zero FFI |
| License | ✅ Apache-2.0 |

---

## Quick start

### As a command

```sh
moon build --target js
node _build/js/debug/build/cmd/moonmojibake/moonmojibake.js detect samples/gbk.txt
```

```
samples/gbk.txt (36 bytes)

  #  encoding        score  conf  errors  sample
  1  gbk                86    51       0  我们把这件事说清楚，然后开始写代码。
  2  euc-kr             73     0       0  乖쳬겉侶숭慤綱헌뇝，횔빈역迦畇덜쯤。
  3  shift_jis          68     0       5  ﾎﾒﾃﾇｰﾑﾕ箴�ﾊﾂﾋｵﾇ蟲�｣ｬﾈｻｺ�ｿｪ
  ...

guess: gbk  (confidence 51%, score 86)
```

```sh
node .../moonmojibake.js repair samples/moji_latin1.txt
```

```
samples/moji_latin1.txt
score 48 -> 90
chain: latin1 -> utf-8

我们把这件事说清楚，然后开始写代码。
```

```sh
node .../moonmojibake.js convert samples/utf8.txt --to gbk -o out.bin
node .../moonmojibake.js detect --text "中文测试"
```

### As a library

```moonbit
// Detect: which code page produced these bytes?
let rows = @mojibake.detect(bytes)
let best = rows[0]
println(best.charset().name())      // "gbk"
println(best.confidence())          // 0..100
println(best.text())                // the decoded text

// Repair: undo the accident layer by layer.
let fixed = @mojibake.repair(mojibake_text)
println(fixed.text())               // the recovered text
println(@mojibake.render_chain(fixed))  // "windows-1252 -> utf-8"

// Direct control when you already know both ends.
let decoded = @mojibake.decode(bytes, @mojibake.Charset::Big5)
let encoded = @mojibake.encode("繁體中文", @mojibake.Charset::Big5)
```

---

## How detection works

The naive approach — "try each code page, keep the result that does not fail" —
does not work, because several East Asian code pages overlap. EUC-KR byte
ranges sit inside GBK; Big5 and GBK both happily consume the same byte pairs.
Everything decodes; only one reading is *text*.

So each candidate is decoded and scored on five signals that fail in different
ways (full breakdown in [`docs/FORMAT_NOTES.md`](docs/FORMAT_NOTES.md)):

| Signal | Weight | What it catches |
|---|---|---|
| Clean decode | 30 | A wrong code page leaves malformed sequences behind |
| Script coherence | 15 | Garbage mixes scripts; real text does not |
| Character frequency | 35 | Wrong decodes produce rare characters, never common ones |
| Printability | 10 | Control characters and private-use code points |
| Script exclusivity | 10 | Hangul is Korean, full-width kana is Japanese, and neither is Chinese |

Two rules sit outside the score because they are evidence rather than
plausibility:

- **Valid multi-byte UTF-8 is close to proof.** A legacy code page forming a
  well-shaped UTF-8 sequence across a whole file is astronomically unlikely,
  while UTF-8 read as a legacy code page happens daily.
- **BOM-less UTF-16 has to prove itself** by showing the alternating-zero
  pattern. Without a BOM, any even-length stream decodes into *something*, and
  arbitrary byte pairs land in Hangul, where they look deceptively plausible.

The character-frequency signal does not ship a corpus. Membership in GB2312
level 1 (3 755 frequent simplified characters) or Big5 level 1 (5 495 frequent
traditional characters) is used as a free, defensible "is this character in
common use" test covering both scripts, giving 9 157 characters total.

## How repair works

Mojibake is a round trip that went through the wrong door: bytes were really
UTF-8, something decoded them as windows-1252, and the result was saved as
UTF-8 again. Undoing one layer means encoding the text back into the code page
that was wrongly applied, then decoding the recovered bytes with the right one.

Repair runs that search over every plausible `(wrong, right)` pair, accepts a
candidate only when it decodes with zero errors *and* improves the score by a
margin, then repeats — up to four layers, which covers every real chain the
authors have seen. Chains that cannot be undone are reported honestly: if the
wrong code page had undefined bytes, the information was destroyed at that
moment and no amount of search brings it back.

---

## What it covers

| Code page | Two-byte mappings | Notes |
|---|---|---|
| GBK | 21 791 | includes GB2312 and the GBK extension area |
| Big5 | 13 710 | includes the HKSCS lead-byte range |
| Shift_JIS | 6 879 | half-width katakana computed, not tabulated |
| EUC-KR | 8 225 | KS X 1001 |
| UTF-8 / UTF-16LE / UTF-16BE | — | via `moonbitlang/core/encoding` |
| ISO-8859-1 / windows-1252 | — | the 0x80–0x9F difference is modelled exactly |

Tables are generated by [`scripts/gen_tables.py`](scripts/gen_tables.py) from
CPython's own codecs and committed, so the data is reproducible, diffable, and
free of third-party licence questions.

---

## Testing

```sh
moon test                        # 31 unit tests
moon build --target js
python scripts/e2e_check.py      # 192 cross-checks against CPython
```

The end-to-end script encodes known text in every supported code page, decodes
it back through the MoonBit implementation, and compares byte-for-byte with
CPython — plus a randomised fuzz pass over valid byte pairs for the four
double-byte pages. Detection is checked against the label the text was encoded
with.

---

## Limitations, stated plainly

- The CLI reads and writes files only on the js backend; on other backends the
  library still works, and `--text` still runs, but file IO is not available.
  MoonBit core has no portable filesystem API.
- Western text shorter than a sentence is genuinely ambiguous: Latin-1 and
  windows-1252 are identical for anything that does not use 0x80–0x9F, and both
  look plausible under several code pages. The confidence value says so instead
  of pretending otherwise.
- BOM-less UTF-16 holding CJK text cannot be proven and is deliberately
  discounted; UTF-16 with a BOM is detected exactly.
- Healing is bounded by information loss. Once a byte became U+FFFD, the
  original is gone.

## Documentation

- [`docs/USAGE.md`](docs/USAGE.md) — CLI and library reference
- [`docs/FORMAT_NOTES.md`](docs/FORMAT_NOTES.md) — table layout, scoring weights, design reasoning

## License

Apache-2.0. See [`LICENSE`](LICENSE).
