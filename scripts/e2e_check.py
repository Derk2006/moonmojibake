#!/usr/bin/env python3
"""Cross-check MoonMojibake against CPython's codecs.

The MoonBit tables were generated from CPython, so agreeing with CPython is
not proof of correctness on its own — but it is proof that the table layout,
the byte-range handling and the Shift_JIS half-width shortcuts all survived
the trip into MoonBit.  Detection is checked separately against the label we
encoded with.

Usage:
    python scripts/e2e_check.py [--rounds N]
"""

import argparse
import os
import random
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CLI = os.path.join(ROOT, "_build", "js", "debug", "build", "cmd", "moonmojibake", "moonmojibake.js")

# (python codec, moonbit charset name, label the detector should return)
#
# latin1 and windows-1252 differ only in 0x80..0x9F, which ordinary Western
# text does not use, so the two are genuinely the same answer there.  Those
# two are checked on the decoded text instead of on the label.
CASES = [
    ("gbk", "gbk", "gbk"),
    ("big5", "big5", "big5"),
    ("shift_jis", "shift_jis", "shift_jis"),
    ("euc_jp", "euc-jp", "euc-jp"),
    ("euc_kr", "euc-kr", "euc-kr"),
    ("cp1252", "windows-1252", None),
    ("latin1", "latin1", None),
]

SAMPLES = {
    "gbk": [
        "我们把这件事说清楚，然后开始写代码。",
        "编码检测是这次项目的核心功能，欢迎试用。",
        "简体中文，标点符号，数字 12345。",
    ],
    "big5": [
        "我們把這件事說清楚，然後開始寫程式。",
        "編碼偵測是這次專案的核心功能。",
        "繁體中文，標點符號，數字 12345。",
    ],
    "shift_jis": [
        "これは日本語のテキストです。文字コードの判定を試します。",
        "日本語の文章と、カタカナ、ひらがな、漢字。",
        "テスト用の文字列です。",
    ],
    "euc_jp": [
        "これは日本語のテキストです。文字コードの判定を試します。",
        "日本語の文章と、カタカナ、ひらがな、漢字。",
        "ﾊﾝｶｸｶﾀｶﾅ と 全角カナ と 漢字。",
        "三バイト形式（JIS X 0212）の丂を含む文。",
    ],
    "euc_kr": [
        "이것은 한국어 텍스트입니다. 문자 인코딩을 확인합니다.",
        "인코딩 감지는 이번 프로젝트의 핵심 기능입니다.",
        "한국어 문장, 숫자 12345.",
    ],
    "cp1252": [
        "Café crème, naïve façade, “quoted” and — dashes.",
        "Grüße aus München, Œuvre, Škoda.",
    ],
    "latin1": [
        "Café naïve, àéîõü, ç and ñ.",
        "Grüße, Ærø, Þingvellir.",
    ],
}


def run(args):
    result = subprocess.run(
        ["node", CLI] + args,
        capture_output=True,
        cwd=ROOT,
    )
    return result.returncode, result.stdout.decode("utf-8", "replace"), result.stderr.decode(
        "utf-8", "replace"
    )


def ensure_build():
    if os.path.exists(CLI):
        return True
    print("building the js target ...")
    result = subprocess.run(["moon", "build", "--target", "js"], cwd=ROOT)
    return result.returncode == 0 and os.path.exists(CLI)


def random_bytes(rng, codec, count):
    """Byte strings that are valid for `codec`, built from its own repertoire."""
    pool = []
    for lead in range(0x81, 0xFF):
        for trail in list(range(0x40, 0xFF)) + list(range(0xA1, 0xFF)):
            pair = bytes([lead, trail])
            try:
                pair.decode(codec)
            except UnicodeDecodeError:
                continue
            pool.append(pair)
    if codec == "euc_jp":
        # EUC-JP has two forms the generic pair loop cannot reach: half-width
        # katakana behind 0x8E, and JIS X 0212 behind 0x8F.  Sampling only the
        # two-byte range would leave the branches that took the longest to get
        # right as the ones never exercised.
        for tail in range(0xA1, 0xE0):
            seq = bytes([0x8E, tail])
            try:
                seq.decode(codec)
            except UnicodeDecodeError:
                continue
            pool.append(seq)
        for second in range(0xA1, 0xFF):
            for third in range(0xA1, 0xFF):
                seq = bytes([0x8F, second, third])
                try:
                    seq.decode(codec)
                except UnicodeDecodeError:
                    continue
                pool.append(seq)
    picked = [rng.choice(pool) for _ in range(count)]
    return b"".join(picked)


def check_cli_contract(workdir):
    """Exit codes are part of the interface.

    A command that prints `error:` and returns 0 is worse than one that
    crashes: the shell, the CI job and the next tool in the pipeline all read
    that 0 as "this worked".  Every failure path is checked here, including
    the two that used to leak a Node stack trace.
    """
    checks = 0
    failures = 0

    def expect(args, want, note, forbidden=None):
        nonlocal checks, failures
        code, out, err = run(args)
        checks += 1
        if code != want:
            failures += 1
            print(
                f"FAIL cli {note}: expected exit {want}, got {code} "
                f"({out.strip()[:90]!r} {err.strip()[:90]!r})"
            )
        if forbidden and forbidden in out + err:
            failures += 1
            print(f"FAIL cli {note}: leaked a runtime stack trace")

    missing = os.path.join(workdir, "missing.txt")
    present = os.path.join(workdir, "present.txt")
    with open(present, "wb") as fh:
        fh.write(b"hello")

    expect(["detect", missing], 1, "detect on a missing file")
    expect(["repair", missing], 1, "repair on a missing file")
    expect(["convert", missing, "--from", "gbk"], 1, "convert on a missing file")
    expect(["detect", workdir], 1, "detect on a directory", "node:fs")
    expect(["scan", present], 1, "scan on a file")
    expect(["fix", present], 1, "fix on a file")
    expect(["convert", present, "--from", "nope"], 1, "unknown --from")
    expect(["convert", present, "--to", "nope"], 1, "unknown --to")
    expect(["detect", present, "--from"], 1, "flag without a value")
    expect(
        ["convert", present, "--text", "hi", "--from", "gbk"],
        1,
        "--text with a legacy --from",
    )

    expect(["convert", present, "--from", "gbk", "--to", "gbk"], 0, "convert works")
    expect(["detect", present, "--fail-if-not", "utf-8"], 0, "gate passes")
    expect(["detect", present, "--fail-if-not", "utf-16le"], 2, "gate asserts")

    # あいうえお in EUC-JP decodes identically under GBK.  Both names are
    # correct, so the gate must accept either — and the JSON must say so
    # instead of claiming confidence in one of them.
    kana = os.path.join(workdir, "kana.bin")
    with open(kana, "wb") as fh:
        fh.write("あいうえお".encode("euc_jp"))
    expect(["detect", kana, "--fail-if-not", "euc-jp"], 0, "gate accepts a tie")
    expect(["detect", kana, "--fail-if-not", "gbk"], 0, "gate accepts the tie's other name")
    expect(["detect", kana, "--fail-if-not", "big5"], 2, "gate rejects a non-tie")

    checks += 1
    _code, out, _err = run(["detect", kana, "--json"])
    if '"ambiguous":true' not in out or '"tied":["gbk","euc-jp"]' not in out:
        failures += 1
        print(f"FAIL cli json: the tie is not reported: {out[:120]!r}")

    return checks, failures


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=40)
    args = parser.parse_args()

    if not ensure_build():
        print("error: could not build the js target (is `moon` on PATH?)")
        return 1

    workdir = tempfile.mkdtemp(prefix="moonmojibake-")
    failures = 0
    checks = 0
    try:
        for codec, name, label in CASES:
            for text in SAMPLES.get(codec, []):
                payload = text.encode(codec)
                path = os.path.join(workdir, "case.bin")
                with open(path, "wb") as fh:
                    fh.write(payload)

                checks += 1
                code, out, err = run(["convert", path, "--from", name])
                expected = payload.decode(codec)
                if code != 0 or out.strip("\n") != expected:
                    failures += 1
                    print(f"FAIL decode {name}: expected {expected!r} got {out!r} {err.strip()}")

                checks += 1
                code, out, err = run(["detect", path])
                guess = ""
                for line in out.splitlines():
                    if line.startswith("guess:"):
                        guess = line.split()[1]
                        break
                if label is not None and guess != label:
                    failures += 1
                    print(f"FAIL detect {name}: expected {label} got {guess!r}")
                else:
                    # The label is allowed to differ only when the readings
                    # are byte-identical; check that the text really is.
                    code, out, err = run(["convert", path])
                    if out.strip("\n") != expected:
                        failures += 1
                        print(f"FAIL detect-text {name}: got {out!r}")

        c, f = check_cli_contract(workdir)
        checks += c
        failures += f

        rng = random.Random(20261101)
        for codec, name, _label in CASES:
            if codec in ("cp1252", "latin1"):
                continue
            for _ in range(args.rounds):
                payload = random_bytes(rng, codec, 8)
                try:
                    expected = payload.decode(codec)
                except UnicodeDecodeError:
                    continue
                path = os.path.join(workdir, "rand.bin")
                with open(path, "wb") as fh:
                    fh.write(payload)
                checks += 1
                code, out, err = run(["convert", path, "--from", name])
                if code != 0 or out.strip("\n") != expected:
                    failures += 1
                    if failures < 20:
                        print(
                            f"FAIL random {name} {payload.hex()}: "
                            f"expected {expected!r} got {out!r} {err.strip()}"
                        )
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    print(f"{checks - failures}/{checks} checks passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
