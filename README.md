# MoonMojibake — Encoding Forensics & Mojibake Repair for MoonBit

[![CI](https://github.com/Derk2006/moonmojibake/actions/workflows/ci.yml/badge.svg)](https://github.com/Derk2006/moonmojibake/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![MoonBit](https://img.shields.io/badge/MoonBit-zero%20FFI-purple.svg)](https://www.moonbitlang.com/)
[![mooncakes](https://img.shields.io/badge/mooncakes-Derk2006%2Fmoonmojibake%400.5.0-blue)](https://mooncakes.io/docs/#/Derk2006/moonmojibake)

**Given bytes with no declared encoding, work out what they are. Given text that
is already ruined, work out how it was ruined and undo it.**

MoonMojibake does two things the MoonBit ecosystem has not put in a library of
its own:

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

Detection does exist elsewhere in the ecosystem, but only in two shapes. Parsers
sniff a BOM or a container-declared charset (`bobzhang/html_parser`,
`bobzhang/mbtexcel`, `cp15695540483/moontag`) — there the answer is dictated by a
specification, not inferred from the bytes. And `R00TK17/moonreader`, a
twelve-format file reader, exports `detect_encoding` as a helper: one enum and
no score, no Shift_JIS or EUC-KR, and its own docs note that GBK and Big5 cannot
be told apart, so double-byte text defaults to GBK. MoonMojibake returns ranked
candidates with confidence behind them, covers Japanese and Korean, and repairs
text that was already decoded wrongly.

---

## Status

| Area | State |
|---|---|
| Code pages — GBK, Big5, Shift_JIS, EUC-JP, EUC-KR | ✅ 63 551 two-byte mappings, generated from CPython codecs |
| Code pages — EUC-JP three-byte form (JIS X 0212) | ✅ 6 067 mappings in their own 94×94 table |
| Code pages — UTF-8, UTF-16LE/BE, UTF-32LE/BE, Latin-1, windows-1252 | ✅ |
| Detection — ranking, confidence, BOM handling | ✅ 12 candidates per call |
| Detection — Chinese/Japanese disambiguation | ✅ JIS X 0208 level-1 test on kana texts |
| Detection — ties | ✅ reported as ties (`ambiguous`, `tied`), never as a confident guess |
| Repair — chained mojibake, up to 4 layers | ✅ returns the re-encode chain |
| Repair — script guard | ✅ never swaps Chinese for Hangul or kana |
| CLI — `detect` / `repair` / `convert` / `scan` / `fix` | ✅ js backend (Node), library works on every backend |
| CLI — `fix` over a tree | ✅ dry run by default, `--write` to apply, idempotent |
| CLI — `--json` on every subcommand | ✅ stable field names, for pipelines |
| CLI — `--fail-if-not` | ✅ exit 2, so CI can reject a non-UTF-8 tree |
| CLI — exit codes | ✅ 0 success, 1 usage/IO error, 2 assertion failed |
| Unit tests | ✅ 67 passing (`moon test`) |
| Cross-check against CPython | ✅ 257/257 (`scripts/e2e_check.py`) |
| Exhaustive byte-space check | ✅ 127 287/127 287, both directions (`scripts/space_check.py`) |
| Dependencies | ✅ MoonBit core only, zero FFI |
| License | ✅ Apache-2.0 |

---

## Quick start

### As a command

```sh
moon build --target js
alias mm="node _build/js/debug/build/cmd/moonmojibake/moonmojibake.js"

mm detect samples/gbk.txt
```

```
samples/gbk.txt (36 bytes)

  #  encoding        score  conf  errors  sample
  1  gbk                86    51       0  我们把这件事说清楚，然后开始写代码。
  2  euc-kr             69     0       0  乖쳬겉侶숭慤綱헌뇝，횔빈역迦畇덜쯤。
  3  euc-jp             66     0       2  厘断委宸周並傍賠萱��隼朔蝕兵亟旗鷹。
  4  big5               54     0       2  扂蠅參涴璃岈佽ь奠ㄛ�遣騜羌標斐�鎢﹝
  ...
 10  utf-8               3     0      19  ���ǰ������˵�����Ȼ��ʼд���
 12  utf-32be            0     0       9  ���������

guess: gbk  (confidence 51%, score 86)
```

Every candidate is shown, including the ones that lost badly, because the
ranking is the evidence: twelve readings, one of which is text and eleven of
which are not.

```sh
mm repair samples/moji_latin1.txt
```

```
samples/moji_latin1.txt
score 40 -> 86
chain: latin1 -> utf-8

我们把这件事说清楚，然后开始写代码。
```

```sh
mm convert samples/utf8.txt --to gbk -o out.bin
mm detect --text "中文测试"
```

Point it at a tree instead of a file — it walks the directory and flags the
things that are not text at all:

```sh
mm scan samples -r
```

```
scan samples (8 files)

  encoding   files
  big5           1
  euc-jp         1
  euc-kr         1
  gbk            1
  utf-8          3
  shift_jis      1

  samples/big5.txt                    big5
  samples/eucjp.txt                   euc-jp
  samples/euckr.txt                   euc-kr
  samples/gbk.txt                     gbk
  samples/moji_cp1252.txt             utf-8
  samples/moji_latin1.txt             utf-8
  samples/sjis.txt                    shift_jis
  samples/utf8.txt                    utf-8
```

Files that are not text at all are reported as `binary` rather than being
force-decoded into nonsense, and `-r` recurses into subdirectories.

`scan` only reports. `fix` is the other half — it converts the files it finds,
and previews unless you say otherwise:

```sh
mm fix samples -r            # dry run: what would change
mm fix samples -r --write    # actually rewrite them as UTF-8
```

```
fix samples (recursive) (8 files, dry run)

  path                                    read as       change
  samples/big5.txt                        big5          transcode
  samples/eucjp.txt                       euc-jp        transcode
  samples/euckr.txt                       euc-kr        transcode
  samples/gbk.txt                         gbk           transcode
  samples/moji_cp1252.txt                 utf-8         repair: windows-1252 -> utf-8  45 -> 90
  samples/moji_latin1.txt                 utf-8         repair: latin1 -> utf-8  40 -> 86
  samples/sjis.txt                        shift_jis     transcode

7 of 8 text files would change; nothing written. Re-run with --write to apply.
```

The three outcomes are labelled separately, because they are different things:
a **transcode** re-reads bytes in another encoding, a **repair** peels mojibake
off bytes that were already valid UTF-8, and both can apply to one file. Binary
files are counted and left alone — a PNG passing through a text decoder produces
replacement characters, and a repair that "succeeds" on one must not be allowed
to touch it.

A second run finds nothing to do, which is the property that makes this safe to
put in a loop.

`detect`, `repair` and `scan` all take `--json`, so the same answers compose
with `jq` and the rest of a pipeline:

```sh
mm detect samples/gbk.txt --json | jq -r '.guess, .confidence'
mm repair samples/moji_latin1.txt --json | jq -r '.chain[0].wrong + " -> " + .chain[0].right'
mm scan . -r --json | jq -r '.entries[] | select(.binary or .charset != "utf-8") | .path'
```

The last line is the one that earns its keep: point it at a repository and get
back exactly the files whose encoding will bite you. The document shape is
fixed (see [`docs/USAGE.md`](docs/USAGE.md#json-output)), so scripts can rely on
it.

### In CI

Reports are for humans; a build needs a number. `--fail-if-not` turns the same
walk into an assertion:

```sh
mm scan . -r --fail-if-not utf-8
```

```
error: docs/legacy.txt reads as gbk, expected utf-8
```

Exit code is `2` when a file reads as anything else, `1` when the command itself
was wrong (unknown encoding, missing directory), `0` when everything matches.
Two different numbers, because "the repository is broken" and "your command line
is broken" are not the same failure, and a script cannot tell them apart if both
come back as `1`.

`--json` carries the verdict as data too — `fail_if_not` and `assert_ok` sit at
the top level of the `scan` object.

### Install

```sh
moon add Derk2006/moonmojibake@0.5.0
```

That writes the module dependency into `moon.mod`. The alias belongs to the
package, though, so one line goes in *your* `src/moon.pkg`, next to the code
that uses it:

```
import {
  "Derk2006/moonmojibake/src/mojibake" @mojibake,
}
```

Then `@mojibake.detect(…)` resolves:

```moonbit
fn main {
  let rows = @mojibake.detect(b"\xd6\xd0\xce\xc4")
  println(rows[0].charset().name())   // gbk
  println(rows[0].text())             // 中文
}
```

The first `moon add` in a fresh checkout also pulls the registry index, which
is large; later runs read it from `~/.moon/registry`.

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
common use" test covering both scripts, giving 9 156 characters total.

Japanese needs a different rule, because the byte ranges nest: every EUC-JP
stream is also a valid GBK stream, and GBK reserves the very same 0xA4/0xA5
rows for kana, so a Japanese file read as GBK keeps its kana and scores well.
The tell is the kanji. JIS X 0208 level 1 is a frequency set of 2 965
characters, and a Chinese reading of Japanese bytes lands outside it often
enough to cost up to 30 points — measured against the ideographs only, since
kana and punctuation say nothing about which language the kanji belong to.
Testing against the full JIS repertoire instead does not work: it holds about
7 000 ideographs and therefore most Chinese hanzi as well.

## How repair works

Mojibake is a round trip that went through the wrong door: bytes were really
UTF-8, something decoded them as windows-1252, and the result was saved as
UTF-8 again. Undoing one layer means encoding the text back into the code page
that was wrongly applied, then decoding the recovered bytes with the right one.

Repair runs that search over every plausible `(wrong, right)` pair, accepts a
candidate only when it decodes with zero errors *and* improves the score by a
margin, then repeats — up to four layers, which covers every real chain the
authors have seen. A round is additionally refused if it would swap one CJK
script for another: encoding accidents move bytes between code pages, they never
translate Chinese into Korean. Without that veto, the greedy search really did
turn 你好 into 콱봤 on a second pass. Chains that cannot be undone are reported
honestly: if the wrong code page had undefined bytes, the information was
destroyed at that moment and no amount of search brings it back.

---

## What it covers

| Code page | Two-byte mappings | Notes |
|---|---|---|
| GBK | 21 791 | includes GB2312 and the GBK extension area |
| Big5 | 13 710 | includes the HKSCS lead-byte range |
| Shift_JIS | 6 879 | half-width katakana computed, not tabulated |
| EUC-JP | 6 879 (+6 067 three-byte) | JIS X 0208 in the pair table, JIS X 0212 behind 0x8F |
| EUC-KR | 8 225 | KS X 1001 |
| UTF-8 / UTF-16LE / UTF-16BE / UTF-32LE / UTF-32BE | — | self-validating; BOM handled exactly |
| ISO-8859-1 / windows-1252 | — | the 0x80–0x9F difference is modelled exactly |

Tables are generated by [`scripts/gen_tables.py`](scripts/gen_tables.py) from
CPython's own codecs and committed, so the data is reproducible, diffable, and
free of third-party licence questions.

---

## Testing

```sh
moon test                        # 67 unit tests
moon build --target js
python scripts/e2e_check.py      # 257 cross-checks against CPython
python scripts/space_check.py    # 127 287 exhaustive checks, both directions
```

The end-to-end script encodes known text in every supported code page, decodes
it back through the MoonBit implementation, and compares byte-for-byte with
CPython — plus a randomised fuzz pass over valid byte pairs for the five
double-byte pages, and a set of CLI contract checks (a failed command must
exit non-zero, and a directory is not a file).

The exhaustive script does not sample. It walks every lead/trail pair CPython
accepts for GBK, Big5, Shift_JIS and EUC-KR, every JIS X 0212 cell and every
half-width katakana spelling for EUC-JP, and checks both directions: what the
bytes decode to, and what each character encodes back to. That is the check
that answers "is any row of the table missing or pointing at the wrong
character" instead of "does the sample happen to pass".

---

## Limitations, stated plainly

- The CLI reads and writes files only on the js backend; on other backends the
  library still works, and `--text` still runs, but file IO is not available.
  MoonBit core has no portable filesystem API.
- Some byte strings are genuinely ambiguous, and the tool says so rather than
  guessing. A kana-only EUC-JP file lives in the JIS X 0208 rows that GBK keeps
  for the same characters, so both names decode it to identical text; `detect`
  prints `ambiguous — gbk and euc-jp …`, `--json` carries `ambiguous` and
  `tied`, and `--fail-if-not` accepts either name. Pure ASCII is the same
  situation by construction: every ASCII-compatible page agrees.
- Western text shorter than a sentence is ambiguous for the same reason:
  Latin-1 and windows-1252 are identical for anything that does not use
  0x80–0x9F, and both look plausible under several code pages.
- BOM-less UTF-16 holding CJK text cannot be proven and is deliberately
  discounted; UTF-16 with a BOM is detected exactly.
- Healing is bounded by information loss. Once a byte became U+FFFD, the
  original is gone.

## Documentation

- [`docs/USAGE.md`](docs/USAGE.md) — CLI and library reference
- [`docs/FORMAT_NOTES.md`](docs/FORMAT_NOTES.md) — table layout, scoring weights, design reasoning

## License

Apache-2.0. See [`LICENSE`](LICENSE).
