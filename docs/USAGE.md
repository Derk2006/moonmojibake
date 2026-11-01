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
  2  euc-kr             73     0       0  乖쳬겉侶숭慤綱헌뇝，횔빈역迦畇덜쯤。
```

### `mm repair`

```sh
mm repair <file>              # print the repaired text plus the chain
mm repair <file> -o fixed.txt # write only the repaired text
```

```
samples/moji_latin1.txt
score 48 -> 90
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

### Encodings accepted by `--from` / `--to`

| Name | Aliases |
|---|---|
| `utf-8` | `utf8` |
| `utf-16le` | `utf16le` |
| `utf-16be` | `utf16be` |
| `gbk` | `cp936`, `gb2312`, `gb18030` |
| `big5` | `big-5`, `cp950` |
| `shift_jis` | `shift-jis`, `shiftjis`, `sjis`, `cp932` |
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
