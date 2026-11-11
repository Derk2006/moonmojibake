#!/usr/bin/env python3
"""Generate MoonBit lookup tables for the legacy East Asian code pages.

Data source: CPython's own codec implementations (gbk, big5, shift_jis, euc_kr,
euc_jp).  Nothing is copied from a third-party library; the script is committed
so the tables can be regenerated and diffed.

The interpreter is part of the input: a codec table can change between CPython
releases, so `scripts/gen_tables.py` is meant to be run with the same Python CI
uses (3.12).  Everything else the script reads is inside this repository — it
must stay that way, or the output stops being reproducible.

Layout
------
Every two-byte table is indexed by

    (lead - 0x81) * 191 + (trail - 0x40)

which covers lead bytes 0x81..0xFE and trail bytes 0x40..0xFE.  Unmapped slots
hold 0.  Shift_JIS half-width katakana (single bytes 0xA1..0xDF) are handled
algorithmically in codec.mbt, not in the table.

EUC-JP needs a second table because its 0x8F prefix introduces a three-byte
form (JIS X 0212), which cannot live in a two-byte slot:

    (second - 0xA1) * 94 + (third - 0xA1)

covering the 94x94 JIS cell grid.  EUC-JP half-width katakana (0x8E + 0xA1..0xDF)
are algorithmic, like Shift_JIS'.

Usage:  python scripts/gen_tables.py
"""

import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "src", "mojibake", "tables_gen.mbt")

LEAD_MIN = 0x81
TRAIL_MIN = 0x40
SPAN = 191
LEADS = 0xFE - 0x81 + 1

# JIS X 0212 sits behind the 0x8F prefix: 94x94 cells, indexed from 0xA1.
JIS_CELLS = 94

# GB18030's four-byte form counts its own pointer space: 126 lead bytes, ten
# second bytes, 126 third bytes, ten fourth bytes.  Pointers below this limit
# address the rest of the BMP through a run table; pointers above it address
# U+10000..U+10FFFF arithmetically.
GB18030_BMP_PTR_LIMIT = 189000
GB18030_MAX_PTR = 1237575


def build(codec, leads, trails):
    table = [0] * (LEADS * SPAN)
    for lead in leads:
        for trail in trails:
            try:
                ch = bytes([lead, trail]).decode(codec)
            except UnicodeDecodeError:
                continue
            if len(ch) != 1:
                continue
            cp = ord(ch)
            if cp == 0 or cp > 0xFFFF:
                continue
            table[(lead - LEAD_MIN) * SPAN + (trail - TRAIL_MIN)] = cp
    return table


def build_jis0212(codec="euc_jp"):
    """The 0x8F-prefixed half of EUC-JP."""
    table = [0] * (JIS_CELLS * JIS_CELLS)
    for second in range(0xA1, 0xFF):
        for third in range(0xA1, 0xFF):
            try:
                ch = bytes([0x8F, second, third]).decode(codec)
            except UnicodeDecodeError:
                continue
            if len(ch) != 1:
                continue
            cp = ord(ch)
            if cp == 0 or cp > 0xFFFF:
                continue
            table[(second - 0xA1) * JIS_CELLS + (third - 0xA1)] = cp
    return table


def gb18030_ptr_bytes(pointer):
    """Spell a four-byte pointer as the four bytes GB18030 defines."""
    fourth = pointer % 10 + 0x30
    pointer //= 10
    third = pointer % 126 + 0x81
    pointer //= 126
    second = pointer % 10 + 0x30
    pointer //= 10
    return bytes([pointer + 0x81, second, third, fourth])


def gb18030_bmp_ranges():
    """Run starts of the four-byte mapping, below the supplementary plane.

    GB18030-2005 spends most of its four-byte pointer space on the rest of the
    BMP: pointer 0 is U+0080, and from there the mapping advances one code point
    per pointer, skipping the characters that already have a two-byte spelling.
    The skips are what make this a table of runs rather than a formula, and the
    pointers above U+FFFF are the only ones the standard maps arithmetically.

    Derived by decoding, not copied from a table: CPython is the reference the
    rest of this project is checked against, and a hand-typed 206-entry table
    would be one transposition away from being wrong in a way no test could
    explain.
    """
    runs = []
    previous = None
    for pointer in range(0, GB18030_BMP_PTR_LIMIT):
        try:
            ch = gb18030_ptr_bytes(pointer).decode("gb18030")
        except UnicodeDecodeError:
            previous = None
            continue
        cp = ord(ch)
        if previous is None or cp != previous + 1:
            runs.append((pointer, cp))
        previous = cp
    return runs


def emit_array(name, table):
    out = [f"let {name} : Array[Int] = ["]
    row = []
    for value in table:
        row.append(str(value))
        if len(row) == 16:
            out.append("  " + ", ".join(row) + ",")
            row = []
    if row:
        out.append("  " + ", ".join(row) + ",")
    out.append("]")
    return "\n".join(out)


def level1_chars(codec, leads, trails):
    """Characters in the first level of a Chinese standard.

    GB2312 level 1 (0xB0A1..0xD7F9) is the 3755 most frequent simplified
    characters, and Big5 level 1 (0xA440..0xC67E) plays the same role for
    traditional characters.  Membership is therefore a free, defensible
    "is this character in common use" test that covers both scripts without
    shipping a corpus.
    """
    chars = []
    for lead in leads:
        for trail in trails:
            try:
                ch = bytes([lead, trail]).decode(codec)
            except UnicodeDecodeError:
                continue
            if len(ch) == 1 and 0x4E00 <= ord(ch) <= 0x9FFF and ch not in chars:
                chars.append(ch)
    return chars


def jis_level1_chars():
    """JIS X 0208 level 1: the 2965 kanji Japanese newspapers may use.

    Rows 16..47 of the standard, which EUC-JP spells with lead bytes 0xB0..0xCF.
    The whole JIS repertoire is a poor test — it holds about 7000 ideographs and
    therefore most Chinese hanzi too — but the *first* level is a genuine
    frequency set, and it is what tells a Japanese reading of a file apart from
    the Chinese reading of the same bytes.
    """
    chars = []
    for lead in range(0xB0, 0xD0):
        for trail in range(0xA1, 0xFF):
            try:
                ch = bytes([lead, trail]).decode("euc_jp")
            except UnicodeDecodeError:
                continue
            if len(ch) == 1 and 0x4E00 <= ord(ch) <= 0x9FFF and ch not in chars:
                chars.append(ch)
    return chars


def common_chars():
    """Union of both level-1 sets.

    Nothing else goes in.  An earlier version topped the set up from a corpus
    that lived *outside* the repository, so the output depended on which machine
    ran the script: CI regenerated a different table than the one committed, and
    the reproducibility check could never pass.  The set is a property of the
    two standards, so it is computed from the standards alone.
    """
    common = level1_chars("gbk", range(0xB0, 0xD8), range(0xA1, 0xFF))
    common += level1_chars(
        "big5", range(0xA4, 0xC7), list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF))
    )
    return "".join(common)


def main():
    gbk = build("gbk", range(0x81, 0xFF), range(0x40, 0xFF))
    gb18030 = build("gb18030", range(0x81, 0xFF), range(0x40, 0xFF))
    big5 = build("big5", range(0x81, 0xFF), range(0x40, 0xFF))
    sjis = build(
        "shift_jis",
        list(range(0x81, 0xA0)) + list(range(0xE0, 0xF0)),
        range(0x40, 0xFD),
    )
    euckr = build("euc_kr", range(0xA1, 0xFF), range(0xA1, 0xFF))
    eucjp = build("euc_jp", range(0xA1, 0xFF), range(0xA1, 0xFF))
    jis0212 = build_jis0212()
    ranges = gb18030_bmp_ranges()
    # The BMP run table stops at the last pointer it can explain; above that,
    # up to the supplementary plane, the standard leaves the space unmapped.
    bmp_end = ranges[-1][0] + (0xFFFF - ranges[-1][1] + 1)
    flat_ranges = [value for run in ranges for value in run]
    common_text = common_chars()
    common_count = len(common_text)
    jis1_text = "".join(jis_level1_chars())
    jis1_count = len(jis1_text)

    parts = [
        "// Generated by scripts/gen_tables.py — DO NOT EDIT.",
        "// Data source: CPython codecs (gbk / gb18030 / big5 / shift_jis / euc_kr / euc_jp).",
        "",
        f"const TABLE_SPAN : Int = {SPAN}",
        f"const TABLE_LEAD_MIN : Int = {LEAD_MIN}",
        f"const TABLE_TRAIL_MIN : Int = {TRAIL_MIN}",
        f"const JIS_CELLS : Int = {JIS_CELLS}",
        f"const GB18030_BMP_END : Int = {bmp_end}",
        f"const GB18030_BMP_PTR_LIMIT : Int = {GB18030_BMP_PTR_LIMIT}",
        f"const GB18030_MAX_PTR : Int = {GB18030_MAX_PTR}",
        "",
        emit_array("gbk_table", gbk),
        "",
        emit_array("gb18030_table", gb18030),
        "",
        "///|",
        "/// Flat (pointer, codepoint) pairs: where each run of the four-byte BMP",
        "/// mapping starts.  The run ends where the next one begins.",
        emit_array("gb18030_ranges", flat_ranges),
        "",
        emit_array("big5_table", big5),
        "",
        emit_array("sjis_table", sjis),
        "",
        emit_array("euckr_table", euckr),
        "",
        emit_array("eucjp_table", eucjp),
        "",
        emit_array("eucjp_0212_table", jis0212),
        "",
        f'let common_chars : String = "{common_text}"',
        "",
        f'let jis_level1_chars : String = "{jis1_text}"',
        "",
    ]
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(parts))
    print(f"wrote {OUT}")
    print(f"gbk={sum(1 for v in gbk if v)} gb18030={sum(1 for v in gb18030 if v)}"
          f" big5={sum(1 for v in big5 if v)}"
          f" sjis={sum(1 for v in sjis if v)} euckr={sum(1 for v in euckr if v)}"
          f" eucjp={sum(1 for v in eucjp if v)} jis0212={sum(1 for v in jis0212 if v)}"
          f" common={common_count} jis_level1={jis1_count}")


if __name__ == "__main__":
    main()
