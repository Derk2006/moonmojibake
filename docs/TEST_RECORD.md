# Test record — 0.6.2

Recorded on 2026-11-14 on Windows (Git Bash), from a clean `_build`.

## Toolchain

```
$ moon version --all
moon 0.1.20261104 (940aa18 2026-11-04)
moonc v0.10.20+65efd5b93 (2026-11-05)
moonrun 0.1.20261104 (940aa18 2026-11-04)

Feature flags enabled: rr_moon_mod,rr_moon_pkg
```

## Type check — warnings are errors

```
$ moon check --deny-warn
Finished. moon: ran 8 tasks, now up to date
```

Zero warnings. This is the gate CI runs; a deprecation warning fails the build.

## Unit tests — four targets

```
$ moon test                    Total tests: 72, passed: 72, failed: 0.
$ moon test --target js        Total tests: 72, passed: 72, failed: 0.
$ moon test --target wasm      Total tests: 72, passed: 72, failed: 0.
$ moon test --target wasm-gc   Total tests: 72, passed: 72, failed: 0.
```

## Builds — three backends

```
$ moon build --target js       cmd/moonmojibake/moonmojibake.js
$ moon build --target wasm     cmd/moonmojibake/moonmojibake.wasm
$ moon build --target wasm-gc  cmd/moonmojibake/moonmojibake.wasm
```

## Differential check against CPython

```
$ python scripts/e2e_check.py
303/303 checks passed
```

Samples: real sentences in simplified/traditional Chinese, Japanese, Korean and
Western text; random double-byte pairs per code page; the EUC-JP `0x8F` and
`0x8E` forms. Every case is encoded by CPython, decoded by MoonBit, and the text
compared byte for byte.

## Exhaustive byte-space check

```
$ python scripts/space_check.py
euc-jp        13072 sequences  ok
euc-jp        13009 characters ok
euc-kr         8225 sequences  ok
euc-kr         8225 characters ok

2351159/2351159 checks matched CPython
```

Not a sample: every lead/trail pair CPython accepts for GBK, GB18030, Big5,
Shift_JIS, EUC-KR; every JIS X 0212 cell and half-width katakana spelling for
EUC-JP; every one of the 1 087 996 four-byte GB18030 pointers. Each side is
decoded, encoded back and compared in both directions.

## Runnable example

```
$ moon run examples/detect_and_repair
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
```

Output is deterministic: fixed inputs, no file IO, no randomness.

## CLI smoke

```
$ node _build/js/debug/build/cmd/moonmojibake/moonmojibake.js detect samples/gbk.txt
samples/gbk.txt (36 bytes)
  1  gbk                86    51       0  我们把这件事说清楚，然后开始写代码。
  ...
guess: gbk  (confidence 51%, score 86)

$ node _build/js/debug/build/cmd/moonmojibake/moonmojibake.js repair samples/moji_latin1.txt
score 40 -> 86
chain: latin1 -> utf-8
我们把这件事说清楚，然后开始写代码。
```

## Install from mooncakes

`mooncakes.io` reports `Derk2006/moonmojibake` at `0.6.2`, `build_status:
success`. In an empty project:

```
$ moon add Derk2006/moonmojibake@0.6.2
$ moon test        # decode, detect and repair assertions all pass
Total tests: 1, passed: 1, failed: 0.
```

The consuming `src/moon.pkg` needs the package path, not the module root:

```
import {
  "Derk2006/moonmojibake/src/mojibake" @mojibake,
}
```

## What is *not* asserted

- No test asserts a particular confidence number for ambiguous input beyond
  "confidence 0" — the score is a ranking device, not a probability.
- No test claims UTF-16 without a BOM can be proven; the limitation is
  documented and the detector deliberately under-weighs it.
- `moon fmt` is not part of CI: on this codebase it rewrites `Int` to `Int32`
  and `indent?` to `indent~`, which changes the public API. Formatting is
  reviewed by hand instead.
