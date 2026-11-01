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
    picked = [rng.choice(pool) for _ in range(count)]
    return b"".join(picked)


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
