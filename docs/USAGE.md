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

### `--json`

`detect`, `repair` and `scan` accept `--json` and print one compact object per
run. Field names are part of the interface.

`detect`:

```json
{"source":"samples/gbk.txt","bytes":36,"guess":"gbk","confidence":51,
 "score":86,"errors":0,
 "candidates":[{"charset":"gbk","family":"Chinese","score":86,
                "confidence":51,"errors":0}, ...]}
```

`candidates` is the full ranking, best first, same order as the table.

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
{"dir":"samples","files":7,
 "encodings":[{"charset":"utf-8","files":3}, ...],
 "entries":[{"path":"samples/gbk.txt","binary":false,
             "charset":"gbk","confidence":51}, ...]}
```

`entries` sets `"binary":true` and `"charset":null` for non-text files.
`confidence` is present only for decoded files. Paths that cannot be read are
reported as `unreadable` rather than aborting the walk, and empty files as
`empty`.

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
python scripts/e2e_check.py            # needs the js build
python scripts/e2e_check.py --rounds 200
```
