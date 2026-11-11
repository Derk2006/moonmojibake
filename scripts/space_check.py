#!/usr/bin/env python3
"""Exhaustive differential check of the double-byte decoders.

`e2e_check.py` samples the code pages: real sentences plus a few dozen random
pairs per encoding.  Sampling cannot answer the question a reviewer actually
asks — "is every row of the table mapped, and does every row decode to the
character CPython says it does?"  This script answers it by walking the whole
byte space: every lead/trail pair that CPython accepts, every JIS X 0212 cell,
every half-width katakana spelling.

The pairs are concatenated with a 0x00 separator and decoded in a single
process, so the check covers tens of thousands of sequences per encoding
without paying process startup for each one.  0x00 is safe as a separator:
no double-byte trail byte is below 0x40, and no code page maps a pair to
U+0000.

Usage:
    python scripts/space_check.py [--codec gbk ...]
"""

import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CLI = os.path.join(
    ROOT, "_build", "js", "debug", "build", "cmd", "moonmojibake", "moonmojibake.js"
)

SEP = b"\x00"

# (python codec, moonbit name)
CASES = [
    ("gbk", "gbk"),
    ("gb18030", "gb18030"),
    ("big5", "big5"),
    ("shift_jis", "shift_jis"),
    ("euc_jp", "euc-jp"),
    ("euc_kr", "euc-kr"),
]


def pairs(codec):
    """Every byte sequence CPython decodes to exactly one character."""
    out = []
    for lead in range(0x81, 0xFF):
        for trail in range(0x40, 0xFF):
            if trail == 0x7F:
                continue
            seq = bytes([lead, trail])
            try:
                text = seq.decode(codec)
            except UnicodeDecodeError:
                continue
            if len(text) == 1 and text != "\ufffd":
                out.append((seq, text))
    return out


def eucjp_extra():
    """The two EUC-JP forms the pair sweep cannot reach."""
    out = []
    for tail in range(0xA1, 0xE0):
        seq = bytes([0x8E, tail])
        try:
            text = seq.decode("euc_jp")
        except UnicodeDecodeError:
            continue
        if len(text) == 1:
            out.append((seq, text))
    for second in range(0xA1, 0xFF):
        for third in range(0xA1, 0xFF):
            seq = bytes([0x8F, second, third])
            try:
                text = seq.decode("euc_jp")
            except UnicodeDecodeError:
                continue
            if len(text) == 1:
                out.append((seq, text))
    return out


def run(args):
    result = subprocess.run(["node", CLI] + args, capture_output=True, cwd=ROOT)
    return result.returncode, result.stdout, result.stderr


def check(codec, name, limit=None):
    items = pairs(codec)
    if codec == "euc_jp":
        items += eucjp_extra()
    if limit is not None:
        items = items[:limit]

    payload = SEP.join(seq for seq, _ in items) + SEP
    expected = [text for _, text in items]

    path = os.path.join(ROOT, "_build", "_space.bin")
    with open(path, "wb") as fh:
        fh.write(payload)

    code, out, err = run(["convert", path, "--from", name])
    os.remove(path)
    if code != 0:
        print(f"FAIL {name}: exit {code} {err.decode('utf-8', 'replace')[:200]}")
        return 1, len(items)

    # `println` appends one newline after the whole stream.
    text = out.decode("utf-8", "replace")
    if text.endswith("\n"):
        text = text[:-1]
    got = text.split("\x00")
    if got and got[-1] == "":
        got.pop()

    if len(got) != len(expected):
        print(
            f"FAIL {name}: {len(got)} segments decoded, expected {len(expected)}"
            " (a sequence was skipped or merged)"
        )
        return 1, len(items)

    failures = 0
    for index, (seq, want) in enumerate(items):
        have = got[index]
        if have != want:
            failures += 1
            if failures <= 10:
                print(
                    f"FAIL {name} {seq.hex()} offset {index}: "
                    f"expected U+{ord(want):04X} got {have!r}"
                )
    if failures:
        return failures, len(items)
    return 0, len(items)


def check_encode(codec, name, limit=None):
    """Round-trip every decodable character through MoonMojibake's encoder.

    Decoding correctly is only half of a codec: if `encode` picks a byte pair
    that CPython reads back as a different character, `convert --to` silently
    writes the wrong file.  The characters are fed in as one UTF-8 document
    and read back with CPython's decoder, which is an independent oracle for
    "what did those bytes actually mean".
    """
    chars = []
    seen = set()
    for _, text in pairs(codec) + (eucjp_extra() if codec == "euc_jp" else []):
        if text not in seen:
            seen.add(text)
            chars.append(text)
    if limit is not None:
        chars = chars[:limit]

    src = os.path.join(ROOT, "_build", "_space_in.txt")
    dst = os.path.join(ROOT, "_build", "_space_out.bin")
    with open(src, "w", encoding="utf-8", newline="") as fh:
        fh.write("\n".join(chars))

    code, out, err = run(["convert", src, "--from", "utf-8", "--to", name, "-o", dst])
    if code != 0 or not os.path.exists(dst):
        print(f"FAIL encode {name}: exit {code} {err.decode('utf-8', 'replace')[:200]}")
        for path in (src, dst):
            if os.path.exists(path):
                os.remove(path)
        return 1, len(chars)

    with open(dst, "rb") as fh:
        written = fh.read()
    for path in (src, dst):
        if os.path.exists(path):
            os.remove(path)

    try:
        got = written.decode(codec)
    except UnicodeDecodeError as exc:
        print(f"FAIL encode {name}: output is not valid {codec}: {exc}")
        return 1, len(chars)
    got_chars = got.split("\n")

    if len(got_chars) != len(chars):
        print(
            f"FAIL encode {name}: {len(got_chars)} characters came back, "
            f"expected {len(chars)}"
        )
        return 1, len(chars)

    failures = 0
    for index, want in enumerate(chars):
        if got_chars[index] != want:
            failures += 1
            if failures <= 10:
                print(
                    f"FAIL encode {name} U+{ord(want):04X} offset {index}: "
                    f"bytes read back as {got_chars[index]!r}"
                )
    return failures, len(chars)


# GB18030's four-byte form has its own pointer space: 126 leads x 10 digits x
# 126 leads x 10 digits.  Pointers below the limit share the BMP with the
# two-byte table and are mapped by a run table; from the limit upwards the
# standard maps them arithmetically onto the supplementary planes.
GB18030_BMP_PTR_LIMIT = 189000
GB18030_MAX_PTR = 1237575


def gb18030_ptr_bytes(pointer):
    fourth = pointer % 10 + 0x30
    pointer //= 10
    third = pointer % 126 + 0x81
    pointer //= 126
    second = pointer % 10 + 0x30
    pointer //= 10
    return bytes([pointer + 0x81, second, third, fourth])


def gb18030_four_byte():
    """Sweep the four-byte space in both directions, without a per-item list.

    A million pointers is too many to keep as tuples, and it does not have to
    be: every sequence decodes to exactly one character, so the expected text
    is just `payload.decode()` and the comparison is one string against
    another.  The same text encoded back must reproduce the payload byte for
    byte — which also proves the encoder picks the canonical spelling rather
    than merely *a* spelling.
    """
    payload = bytearray()
    for pointer in range(0, GB18030_BMP_PTR_LIMIT):
        seq = gb18030_ptr_bytes(pointer)
        try:
            seq.decode("gb18030")
        except UnicodeDecodeError:
            # A hole in the run table: the standard leaves these pointers
            # unmapped, and so must the implementation.
            continue
        payload += seq
    for pointer in range(GB18030_BMP_PTR_LIMIT, GB18030_MAX_PTR + 1):
        payload += gb18030_ptr_bytes(pointer)
    payload = bytes(payload)
    expected = payload.decode("gb18030")

    checks = 0
    failures = 0

    path = os.path.join(ROOT, "_build", "_space4.bin")
    with open(path, "wb") as fh:
        fh.write(payload)
    code, out, err = run(["convert", path, "--from", "gb18030"])
    os.remove(path)
    checks += 1
    if code != 0:
        print(f"FAIL gb18030 four-byte: exit {code} {err.decode('utf-8', 'replace')[:200]}")
        return 1, checks
    text = out.decode("utf-8", "replace")
    if text.endswith("\n"):
        text = text[:-1]
    if text != expected:
        failures += 1
        print(f"FAIL gb18030 four-byte decode: {describe_difference(text, expected)}")

    src = os.path.join(ROOT, "_build", "_space4_in.txt")
    dst = os.path.join(ROOT, "_build", "_space4_out.bin")
    with open(src, "w", encoding="utf-8", newline="") as fh:
        fh.write(expected)
    code, out, err = run(
        ["convert", src, "--from", "utf-8", "--to", "gb18030", "-o", dst]
    )
    checks += 1
    if code != 0 or not os.path.exists(dst):
        print(f"FAIL gb18030 four-byte encode: exit {code} {err.decode('utf-8', 'replace')[:200]}")
        for leftover in (src, dst):
            if os.path.exists(leftover):
                os.remove(leftover)
        return 1, checks
    with open(dst, "rb") as fh:
        written = fh.read()
    for leftover in (src, dst):
        if os.path.exists(leftover):
            os.remove(leftover)
    if written != payload:
        failures += 1
        index = 0
        while index < min(len(written), len(payload)) and written[index] == payload[index]:
            index += 1
        print(
            f"FAIL gb18030 four-byte encode: {len(written)} bytes for "
            f"{len(payload)} expected, first difference at byte {index} "
            f"({written[index:index + 4].hex()} vs {payload[index:index + 4].hex()})"
        )

    # Each sequence is checked twice: decoded and encoded back.  Counting both
    # keeps the total comparable with the pair sweeps, which also count a
    # decode and an encode per sequence.
    return failures, len(expected) * 2


def describe_difference(got, expected):
    index = 0
    while index < min(len(got), len(expected)) and got[index] == expected[index]:
        index += 1
    if index == min(len(got), len(expected)):
        return f"{len(got)} characters, expected {len(expected)}"
    return (
        f"first difference at character {index}: "
        f"expected U+{ord(expected[index]):04X} got U+{ord(got[index]):04X}"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--codec",
        action="append",
        choices=[codec for codec, _ in CASES],
        help="restrict the sweep to one codec (repeatable)",
    )
    parser.add_argument("--limit", type=int, help="only the first N sequences")
    parser.add_argument(
        "--encode-only", action="store_true", help="skip the decode sweep"
    )
    args = parser.parse_args()

    if not os.path.exists(CLI):
        print("error: build the js target first (moon build --target js)")
        return 1

    total = 0
    failures = 0
    for codec, name in CASES:
        if args.codec and codec not in args.codec:
            continue
        if not args.encode_only:
            bad, count = check(codec, name, args.limit)
            total += count
            failures += bad
            print(f"{name:12} {count:6} sequences  {'ok' if bad == 0 else f'{bad} bad'}")

        if codec == "gb18030":
            bad, count = gb18030_four_byte()
            total += count
            failures += bad
            print(
                f"{'gb18030 4B':12} {count // 2:6} sequences  "
                f"{'ok' if bad == 0 else f'{bad} bad'}"
            )

        bad, count = check_encode(codec, name, args.limit)
        total += count
        failures += bad
        print(f"{name:12} {count:6} characters {'ok' if bad == 0 else f'{bad} bad'}")

    print(f"\n{total - failures}/{total} checks matched CPython")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
