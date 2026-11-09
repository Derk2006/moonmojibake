# Usage

## Command line

The CLI needs Node, because MoonBit core has no portable filesystem API.
Everything except file IO works on every backend.

```sh
moon build --target js
alias mm="node _build/js/debug/build/cmd/moonmojibake/moonmojibake.js"
```

### `mm detect`

```sh
mm detect <file>
mm detect --text "中文测试"
cat file | mm detect -
```

Prints every candidate with its score, confidence and error count, then the
guess. `confidence` is 0 when the input cannot be told apart — plain ASCII is
the usual reason, since every ASCII-compatible code page decodes it identically.

```
  #  encoding        score  conf  errors  sample
  1  gbk                86    51       0  我们把这件事说清楚，然后开始写代码。
  2  euc-kr             69     0       0  乖쳬겉侶숭慤綱헌뇝，횔빈역迦畇덜쯤。
  3  euc-jp             66     0       2  厘断委宸周並傍賠萱��隼朔蝕兵亟旗鷹。
```

### `mm repair`

```sh
mm repair <file>              # print the repaired text plus the chain
mm repair <file> -o fixed.txt # write only the repaired text
```

```
samples/moji_latin1.txt
score 40 -> 86
chain: latin1 -> utf-8

我们把这件事说清楚，然后开始写代码。
```

`score` is the text-likeness score before and after, 0–100. If no chain is
found, the text is printed unchanged with `no mojibake chain found`.

Repair works on text, not bytes: the input is read as UTF-8 when it is valid
UTF-8 (mojibake usually is), and through detection otherwise.

### `mm convert`

```sh
mm convert <file>                            # decode with detection, print text
mm convert <file> --from gbk                 # decode with a known code page
mm convert <file> --from gbk --to big5 -o out.bin
```

`--from` defaults to detection, `--to` defaults to `utf-8`. Without `-o` the
decoded text goes to stdout; with `-o` the re-encoded bytes go to the file.

### `mm scan`

```sh
mm scan <dir>                 # this directory only
mm scan <dir> -r              # recurse
mm scan <dir> --json
```

Walks the directory and prints a tally by encoding, then one line per file:

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

Files that are not text are reported as `binary` instead of being force-decoded.
The test is a NUL byte in the first 8 KiB, waived for UTF-16/UTF-32 shaped files,
because a directory walk that confidently labels a PNG as `gbk` is worse than
useless.

`scan` never modifies anything and never fails on an unreadable file — that file
is counted as an error and skipped, so one bad path does not abort a tree walk.

### `mm fix`

```sh
mm fix <dir>                  # this directory only; dry run
mm fix <dir> -r               # recurse
mm fix <dir> -r --write       # rewrite the files
mm fix <dir> -r --json
```

The same walk as `scan`, but it converts instead of only reporting. Dry run is
the default: the premise of the tool is that nobody knows what these files are,
and rewriting a tree on a guess is not something a forgotten flag should cause.
`--write` is the opt-in, and it writes UTF-8 bytes.

```
fix samples (recursive) (8 files, dry run)

  path                                    read as       change
  samples/big5.txt                        big5          transcode
  samples/moji_latin1.txt                 utf-8         repair: latin1 -> utf-8  40 -> 86

7 of 8 text files would change; nothing written. Re-run with --write to apply.
```

Three outcomes, labelled separately because they are different operations:

| column | meaning |
|---|---|
| `transcode` | bytes were valid in another encoding; they are re-encoded as UTF-8 |
| `repair: A -> B` | bytes were already UTF-8 but held mojibake; a layer is peeled off |
| `transcode + A -> B` | both: the file was in another encoding *and* carried mojibake |

Binary files are counted in the header and left untouched. A second run reports
`no file needs changing`; CI asserts that, because a repair that is not a fixed
point would rewrite the same file forever.

File mode bits and line endings are not touched — this writes bytes, not text
with a policy.

### Exit codes

| code | meaning |
|---|---|
| `0` | success; with `--fail-if-not`, every file matched |
| `1` | the command was called wrong: unknown encoding, missing directory, a path that cannot be read, a flag without a value, or a target encoding that cannot represent the text |
| `2` | `--fail-if-not` did not hold |

Every failure path returns non-zero. Nothing prints `error:` and then exits 0 —
a caller that only looks at the status can trust it.

`--fail-if-not` makes the walk an assertion instead of a report:

```sh
mm scan . -r --fail-if-not utf-8
mm detect samples/gbk.txt --fail-if-not utf-8
```

The encoding name goes through the same parser as `--from`, so `UTF8`, `cp936`
and `shift-jis` are accepted and reported in canonical form. In text mode the
mismatches are printed one per line after the table; in `--json` mode they stay
out of stdout and the verdict is carried by `assert_ok`.

A tie counts as a match. When two code pages decode the bytes to identical
text, either name is a correct description of the file, so
`mm detect kana.bin --fail-if-not euc-jp` passes even when `gbk` was listed
first. Rejecting it would fail a build over a distinction the bytes do not
contain.

Only `detect` and `scan` take this flag. `fix` does not: it already changes the
files, and an assertion about what they were before would be a different
question.

### Ambiguous input

Detection is allowed to answer "this is a tie" instead of picking a winner.
Two cases produce one:

- **Pure ASCII.** Every ASCII-compatible code page produces and accepts the
  same bytes; the top of the ranking is a convention, not evidence.
- **Kana-only EUC-JP.** JIS X 0208 rows 0xA4 and 0xA5 hold the same kana in
  GBK, so `あいうえお` has one spelling that both code pages read the same way.

In both cases `detect` prints the tied names and `--json` sets `ambiguous` to
`true` with the tied list in `tied`. `rows[0]` is still a valid answer — it is
just not the only one — so library callers that need a single name can keep
using `detect_charset`.

### `--json`

`detect`, `repair`, `scan` and `fix` accept `--json` and print one compact
object per run. Field names are part of the interface.

`detect`:

```json
{"source":"samples/gbk.txt","bytes":36,"guess":"gbk","confidence":51,
 "ambiguous":false,"tied":["gbk"],"score":86,"errors":0,
 "candidates":[{"charset":"gbk","family":"Chinese","score":86,
                "confidence":51,"errors":0}, ...]}
```

`candidates` is the full ranking, best first, same order as the table. `tied`
holds every candidate that decodes the bytes to the same text with the same
score; it always contains `guess`, and has more than one entry only when the
input is genuinely ambiguous.

`repair`:

```json
{"source":"samples/moji_latin1.txt","repaired":true,"before":40,"after":86,
 "chain":[{"wrong":"latin1","right":"utf-8"}],
 "text":"我们把这件事说清楚，然后开始写代码。"}
```

`chain` is an array of steps, not a string, so a caller can inspect individual
layers. `repaired` is false with an empty chain when nothing was found.

`scan`:

```json
{"dir":"samples","files":8,"fail_if_not":"utf-8","assert_ok":false,
 "encodings":[{"charset":"utf-8","files":3}, ...],
 "entries":[{"path":"samples/gbk.txt","binary":false,
             "charset":"gbk","confidence":51}, ...]}
```

`entries` sets `"binary":true` and `"charset":null` for non-text files.
`confidence` is present only for decoded files. Paths that cannot be read are
reported as `unreadable` rather than aborting the walk, and empty files as
`empty`.

`fail_if_not` is `null` when no assertion was requested, and `assert_ok` is
`true` in that case — an absent assertion has not failed.

`fix`:

```json
{"dir":"samples","recursive":true,"write":false,"files":8,"binary":0,
 "changed":7,"written":0,
 "entries":[{"path":"samples/moji_latin1.txt","read_as":"utf-8",
             "chain":"latin1 -> utf-8","repaired":true,
             "score_before":40,"score_after":86}, ...]}
```

`changed` counts files that would be (or were) rewritten, `written` counts what
actually happened — the two are equal only with `--write`. `chain` is empty for
a pure transcode.

### Encodings accepted by `--from` / `--to`

| Name | Aliases |
|---|---|
| `utf-8` | `utf8` |
| `utf-16le` | `utf16le` |
| `utf-16be` | `utf16be` |
| `utf-32le` | `utf32le`, `ucs-4le`, `ucs4le` |
| `utf-32be` | `utf32be`, `ucs-4be`, `ucs4be` |
| `gbk` | `cp936`, `gb2312`, `gb18030` |
| `big5` | `big-5`, `cp950` |
| `shift_jis` | `shift-jis`, `shiftjis`, `sjis`, `cp932` |
| `euc-jp` | `eucjp`, `ujis`, `hp-ux-euc` |
| `euc-kr` | `euckr`, `ks-c-5601` |
| `latin1` | `latin-1`, `iso-8859-1` |
| `windows-1252` | `cp1252`, `win1252` |

Matching ignores ASCII case and treats `_` as `-`.

## Library

### Decode

```moonbit
let decoded = @mojibake.decode(bytes, @mojibake.Charset::Gbk)
decoded.text()    // best-effort text, malformed input replaced with U+FFFD
decoded.errors()  // how many sequences could not be decoded
decoded.chars()   // character count
```

Decoding never raises. That is deliberate: a wrong guess has to produce a
number, not an exception, or detection cannot compare candidates.

### Detect

```moonbit
let rows = @mojibake.detect(bytes)      // ranked, best first; empty for empty input
let best = rows[0]
best.charset()      // Charset
best.text()         // the decoded text
best.score()        // 0..100 text plausibility
best.confidence()   // 0..100, how far ahead of the runner-up
best.errors()       // malformed sequences under this reading

@mojibake.detect_charset(bytes)                     // Charset?
@mojibake.detect_charset_or(bytes, Charset::Utf8)   // Charset
@mojibake.detect_text(bytes)                        // String
```

`detect` returns exactly one row when a BOM settles the question, and an empty
array when there are no bytes.

Two helper functions answer the question a single label cannot:

```moonbit
@mojibake.is_ambiguous(rows)              // Bool
@mojibake.ambiguous_candidates(rows)      // Array[Charset], winner included
@mojibake.is_ascii_text(text)             // Bool
```

`is_ambiguous` is true when the runner-up decodes the bytes to the same text
and scores the same — not a worse guess, the same guess. `rows[0]` remains a
valid answer, which is why `detect_charset` keeps returning it; a caller that
reports confidence should report the tie instead.

### Binary check

```moonbit
@mojibake.looks_binary(bytes)   // Bool
```

True when the first 8 KiB contain a NUL byte, unless the data is UTF-16 or
UTF-32 shaped. `scan` uses it to avoid labelling a PNG as `gbk`; callers walking
a filesystem should use it too.

### Repair

```moonbit
let result = @mojibake.repair(text)
result.text()          // the recovered text
result.steps()         // Array[FixStep], each with wrong() / right()
result.before()        // score of the input
result.after()         // score of the result
@mojibake.was_repaired(result)   // Bool
@mojibake.render_chain(result)   // "windows-1252 -> utf-8"
```

A repair step is refused when it would move text from Han, Hangul or kana into a
different one of those scripts. Encoding mistakes do not translate languages, so
such a step is a wrong answer no matter how well it scores.

### Encode

```moonbit
@mojibake.encode("中文", @mojibake.Charset::Gbk)   // Bytes? — None if unmappable
```

`None` is meaningful: text that cannot be represented in a code page was never
produced by that code page, and repair uses exactly that to prune its search.

### Charset helpers

```moonbit
@mojibake.Charset::all()               // Array[Charset], preference order for ties
@mojibake.Charset::parse("CP936")      // Charset?
charset.name()                         // "gbk"
charset.family()                       // "Chinese"
charset.is_double_byte()               // Bool
```

`all()` returns twelve entries, in this order — the order is the tie-break, so
plain ASCII resolves to UTF-8:

```
utf-8, gbk, big5, shift_jis, euc-kr, euc-jp, windows-1252, latin1,
utf-16le, utf-16be, utf-32le, utf-32be
```

### Report rendering

```moonbit
@mojibake.render_detection(source, byte_count, rows)   // the CLI table
@mojibake.render_fix(result)                           // the CLI repair report
```

Both return text without a trailing newline, so they compose with a
line-oriented printer.

## Tests

```sh
moon test
python scripts/e2e_check.py            # needs the js build; 257 checks
python scripts/e2e_check.py --rounds 200
python scripts/space_check.py          # 127 287 checks, both directions
```

`e2e_check.py` samples: real sentences plus random valid pairs, and a set of
CLI contract checks. `space_check.py` does not sample — it walks every
lead/trail pair each code page accepts, every JIS X 0212 cell, and every
half-width katakana spelling, then encodes every decodable character back.
Use it when a table or a byte-range branch changes; it is what catches a
missing row, which sampling reliably misses.
