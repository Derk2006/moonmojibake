# Format and design notes

Everything here is an implementation decision with a reason attached, so that
the next person can change a number knowing what it was holding up.

## Table layout

All four double-byte code pages share one flat indexing scheme:

```
index = (lead - 0x81) * 191 + (trail - 0x40)
```

`191 = 0xFE - 0x40 + 1`, so the table covers lead bytes `0x81..0xFE` and trail
bytes `0x40..0xFE` — 24 066 slots per code page, of which most are zero.
A zero means "this pair is not mapped", which is unambiguous because U+0000 is
never a two-byte code-page character.

Sharing the layout across code pages means one lookup function, one reverse-
index builder, and one set of bounds checks instead of four. The cost is that
sparse pages (EUC-KR maps only `0xA1..0xFE` × `0xA1..0xFE`) waste slots: EUC-KR
uses 8 225 of 24 066.

Why not a hash map or a sorted array of pairs? Because a table index is a single
multiply and add, the whole thing is `const`-ish data the compiler can place in
a data segment, and no allocation happens per character. Detection decodes the
same bytes nine times, so per-character cost matters.

Shift_JIS half-width katakana (`0xA1..0xDF`, single bytes) are computed —
`U+FF61 + (byte - 0xA1)` — rather than tabulated. They are a linear range; a
table would be 63 redundant entries and one more thing to get wrong.

## Generation

`scripts/gen_tables.py` reads CPython's own codecs and writes
`src/mojibake/tables_gen.mbt`. Nothing is copied from a third-party library, and
the script is committed so the tables can be regenerated and diffed. The header
of the generated file says so.

Byte pairs that CPython rejects are left as 0. This is a deliberate choice to
track CPython exactly, and it means one real-world quirk is *not* modelled:
Microsoft's CP936 maps the single byte `0x80` to `€`, while Python's `gbk` codec
rejects it. MoonMojibake follows Python. If a file relies on the Microsoft
behaviour, that byte is reported as an error and counted.

## Common-character set

The frequency signal needs a notion of "characters people actually write". The
obvious approach — ship a frequency corpus — costs hundreds of kilobytes and
raises a licensing question.

Instead the generator derives the set from the standards themselves:

- GB2312 level 1, lead `0xB0..0xD7`, trail `0xA1..0xFE` — 3 755 frequent
  **simplified** characters, ordered by pinyin precisely because they are the
  common ones.
- Big5 level 1, lead `0xA4..0xC6` — 5 495 frequent **traditional** characters,
  same reasoning.

The union is 9 157 characters. Membership is a free, defensible, script-neutral
"is this in common use" test, and it is symmetric across simplified and
traditional, which matters: if only GB2312 level 1 were used, every traditional
character would look rare and Big5 would lose to GBK on its own text.

Measured on the test corpus, real Chinese hits this set at ~100% and a wrong
code page's output at ~0%. That gap is what the 35-point frequency signal
exploits.

## Scoring

`text_score(text, errors) -> Int` in `0..100`. Five weighted signals:

| Signal | Max | Computation |
|---|---|---|
| Clean decode | 30 | 30 if no errors; otherwise `30 - 30*errors/chars - 8`, floored at 0 |
| Script coherence | 15 | `15 * (dominant_script + neutral) / chars` |
| Character frequency | 35 | scaled by the CJK share, see below |
| Printability | 10 | `10 * (chars - noise) / chars` |
| Script exclusivity | 10 | 10 when ≥90% Hangul or ≥40% full-width kana, and no errors |

Then a penalty: `-12` when Hangul is mixed with ideographs or kana beyond a
third of the scripted characters.

### Why the error penalty is not proportional

`30 - 30*errors/chars` alone is too weak. One bad sequence in a 32-character
stream costs one point, which is less than the frequency bonus GBK earns from
almost-parsing Western text. The extra flat `-8` encodes the actual prior: a
code page that cannot consume the whole stream is the wrong code page, and one
failure is already strong evidence.

### Why frequency scales with the CJK share

Without the `* scripted / chars` factor, a Western sentence containing two
accented characters that Shift_JIS reads as two common kanji would earn the full
35 points for those two characters — as much as a page of Chinese. Scaling by
the share means the frequency evidence only counts for the part of the text it
explains. This single line is what stopped Latin-1 text from being detected as
Shift_JIS.

### Why half-width katakana is not "neutral"

`is_neutral_char` counts ASCII, CJK punctuation and fullwidth forms as belonging
to whatever script dominates. Half-width katakana (`U+FF61..U+FF9F`) lives in
the same fullwidth block and had to be excluded explicitly, because a Chinese
code page read as Shift_JIS produces exactly that and nothing else. Counting it
as neutral made that accident look like ordinary punctuation.

## Detection

Candidates come from `Charset::all()`, in this order:

```
utf-8, gbk, big5, shift_jis, euc-kr, windows-1252, latin1, utf-16le, utf-16be
```

Sorting is a stable insertion sort over nine elements, so ties resolve to this
order. That is why plain ASCII comes back as UTF-8 rather than as whichever code
page was tried last.

`confidence = clamp((top - second) * 3, 0, 100)`, scaled down when the top score
is below 40, and floored at 85 when the winner's text satisfies the script-
exclusivity test with zero errors. A confidence of 0 means "the candidates are
indistinguishable", which is the honest answer for ASCII.

### The UTF-8 rule

If the bytes decode as UTF-8 with zero errors **and** contain a byte ≥ `0xC2`,
the UTF-8 candidate is forced to 100.

This is not a heuristic in the same family as the others; it is close to proof.
A legacy code page that happens to form valid multi-byte UTF-8 across an entire
file is astronomically unlikely, while UTF-8 read as a legacy code page is
routine. The rule is also what makes mojibake files work: a mojibake file *is*
valid UTF-8, of garbage, and without this rule the detector would attribute it
to GBK and hide the problem.

The `≥ 0xC2` condition keeps pure ASCII out of it — ASCII is valid UTF-8 but
proves nothing, and forcing it to 100 would fabricate confidence.

### The UTF-16 rule

BOM-less UTF-16 is halved unless it shows the alternating-zero pattern: at least
half of its code units have a zero high byte.

Without this rule UTF-16 wins everything. Any even-length byte stream decodes
into something, and arbitrary pairs land in Hangul (EUC-KR/GBK byte pairs are
in the `0xB0..0xFE` range, which is exactly the Hangul block), where they score
90+ because Hangul is a plausible script and we have no Korean frequency model.

The cost is that a genuine BOM-less UTF-16 file holding CJK text is discounted
too. That is the right trade: UTF-16 without a BOM is rare, UTF-16 with a BOM is
detected exactly, and a false positive here poisons every other result.

## Repair

`repair(text)` runs at most four rounds. Each round tries every
`(wrong, right)` pair from:

- `wrong` ∈ {windows-1252, latin1, gbk, big5, shift_jis, euc-kr} — the code
  pages that actually get applied by mistake.
- `right` ∈ {utf-8, gbk, big5, shift_jis, euc-kr, windows-1252, latin1} — every
  code page a file could really be in.

A candidate is accepted only when it decodes with **zero errors** and improves
the score by more than 4 points. The zero-error requirement is what keeps the
search honest: a mojibake reversal that leaves malformed bytes behind is not a
reversal. The 4-point margin stops the search from "repairing" text that was
already fine into something marginally more frequent.

UTF-16 is absent from both lists. Nobody re-encodes a file to UTF-16 by
accident, and allowing it as a target made the search turn Chinese into Hangul,
which decodes cleanly and scores well. That was a real bug, and the fix was to
remove the option rather than to tune around it.

Chains are reported, not just results: `render_chain` gives
`windows-1252 -> utf-8`, and `steps()` gives the individual pairs. A caller can
audit the reasoning instead of trusting the output.

## Known limits

- Mojibake that passed through a code page with undefined bytes is partially
  destroyed: those bytes became U+FFFD somewhere upstream and cannot be
  recovered.
- Short Western text is ambiguous by construction. Latin-1 and windows-1252 are
  byte-identical outside `0x80..0x9F`; no detector can separate them, so the
  confidence says so.
- Korean byte ranges are a subset of GBK, so Korean text decodes cleanly as
  Chinese too. Script exclusivity breaks that tie, but a short Korean string
  with no Hangul-dominant majority would still be misread.
- The frequency model covers Han characters only. Kana and Hangul get a fixed
  score because there is no frequency data behind them, which makes Japanese and
  Korean detection weaker than Chinese detection.
