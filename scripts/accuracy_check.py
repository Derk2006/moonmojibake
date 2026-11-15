#!/usr/bin/env python3
"""Measure detection accuracy against a labelled corpus, and against baselines.

Why this exists
---------------
The hackathon rubric asks a project to show, *with data*, what it adds over
what the ecosystem already does. "It supports more encodings" is a claim; a
number on a fixed corpus is evidence. So: encode known text with a known
codec, hand the bytes to `moonmojibake detect`, and count how often the answer
is right.

Two baselines are reported next to the tool:

    always-gbk      every input answers "gbk" (what a detector without a
                    scoring model degrades to for East Asian bytes)
    bom-then-gbk    use the BOM when there is one, otherwise "gbk" (what a
                    spec-driven sniffer such as a container/HTML parser does)

Both are honest baselines, not strawmen: on Chinese-dominated input the first
one is already right a lot of the time, which is exactly why the gap has to be
measured rather than asserted.

What counts as correct
----------------------
Some byte strings are genuinely identical under two code pages. Chinese text
that never leaves the GBK subset encodes to the same bytes in GBK and in
GB18030; Western text without 0x80..0x9F encodes identically in Latin-1 and
windows-1252. No detector can tell those apart, so each case carries an
`accept` set instead of a single label, and the report says so.

Pure-ASCII input is a separate floor: it is *every* encoding at once. Those
cases are counted in their own bucket and never folded into the accuracy
figure.

Usage
-----
    python scripts/accuracy_check.py            # human-readable report
    python scripts/accuracy_check.py --json out.json
    python scripts/accuracy_check.py --min-top1 0.70   # CI gate

The gate is deliberately a floor, not a target: it exists so a change that
trades accuracy for speed cannot land silently.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CLI = os.path.join(
    ROOT, "_build", "js", "debug", "build", "cmd", "moonmojibake", "moonmojibake.js"
)

# ---------------------------------------------------------------------------
# Corpus
# ---------------------------------------------------------------------------
# Each entry: (group, text, [(python codec, [accepted labels])]).
# Labels are the names `detect --json` prints (`euc-jp`, `shift_jis`, ...).

ZH_S = "我们把这件事说清楚，然后开始写代码。编码检测是这次项目的核心功能，欢迎试用。"
ZH_S_SHORT = "中文期刊"
ZH_S_LONG = ZH_S * 6
ZH_T = "這是一段繁體中文，用來測試編碼判定是否準確。請把結果告訴我，謝謝。"
ZH_T_SHORT = "繁體中文"
JA = "これは日本語のテキストです。文字コードの判定を試すために書いています。"
JA_SHORT = "日本語"
JA_LONG = JA * 4
KO = "이것은 한국어 텍스트입니다. 인코딩 감지를 시험하기 위해 작성했습니다."
KO_SHORT = "한국어"
FR = "L'\u00e9t\u00e9 o\u00f9 je suis n\u00e9, \u00e0 Paris, \u00e9tait tr\u00e8s chaud."
FR_SHORT = "caf\u00e9 na\u00efve"

CORPUS = [
    # --- Chinese, simplified -------------------------------------------------
    ("zh-hans", ZH_S_SHORT, [("gbk", ["gbk", "gb18030"])]),
    ("zh-hans", ZH_S, [("gbk", ["gbk", "gb18030"])]),
    ("zh-hans", ZH_S_LONG, [("gbk", ["gbk", "gb18030"])]),
    ("zh-hans", ZH_S, [("gb18030", ["gbk", "gb18030"])]),
    ("zh-hans", "中文测试 😀 龦 编码", [("gb18030", ["gb18030"])]),
    ("zh-hans", ZH_S_SHORT, [("utf-8", ["utf-8"])]),
    ("zh-hans", ZH_S, [("utf-8", ["utf-8"])]),
    ("zh-hans", ZH_S_LONG, [("utf-8", ["utf-8"])]),
    ("zh-hans", ZH_S, [("utf-16-le", ["utf-16le"])]),
    ("zh-hans", ZH_S, [("utf-16-be", ["utf-16be"])]),
    ("zh-hans", ZH_S_LONG, [("utf-16-le", ["utf-16le"])]),
    # --- Chinese, traditional ------------------------------------------------
    ("zh-hant", ZH_T_SHORT, [("big5", ["big5"])]),
    ("zh-hant", ZH_T, [("big5", ["big5"])]),
    ("zh-hant", ZH_T * 4, [("big5", ["big5"])]),
    ("zh-hant", ZH_T, [("utf-8", ["utf-8"])]),
    # --- Japanese ------------------------------------------------------------
    ("ja", JA_SHORT, [("shift_jis", ["shift_jis"])]),
    ("ja", JA, [("shift_jis", ["shift_jis"])]),
    ("ja", JA_LONG, [("shift_jis", ["shift_jis"])]),
    ("ja", JA, [("euc_jp", ["euc-jp"])]),
    ("ja", JA_LONG, [("euc_jp", ["euc-jp"])]),
    ("ja", JA, [("utf-8", ["utf-8"])]),
    ("ja", JA_LONG, [("utf-8", ["utf-8"])]),
    # --- Korean --------------------------------------------------------------
    ("ko", KO_SHORT, [("euc_kr", ["euc-kr"])]),
    ("ko", KO, [("euc_kr", ["euc-kr"])]),
    ("ko", KO * 4, [("euc_kr", ["euc-kr"])]),
    ("ko", KO, [("utf-8", ["utf-8"])]),
    # --- Western -------------------------------------------------------------
    ("western", FR_SHORT, [("utf-8", ["utf-8"])]),
    ("western", FR, [("utf-8", ["utf-8"])]),
    ("western", FR, [("latin1", ["latin1", "windows-1252"])]),
    ("western", FR, [("cp1252", ["latin1", "windows-1252"])]),
    ("western", "café naïve résumé — 20 €", [("cp1252", ["windows-1252"])]),
]

# ASCII is every encoding at once; measured separately, never scored.
ASCII_CASES = [
    ("ascii", "The quick brown fox jumps over the lazy dog, again and again.", "utf-8"),
    ("ascii", "2026-11-15T10:00:00Z INFO boot ok", "utf-8"),
    ("ascii", "id,name,value\n1,alpha,2.5\n2,beta,3.5\n", "utf-8"),
]


def run_detect(path):
    """Return the parsed JSON from `detect --json`, or None on failure."""
    proc = subprocess.run(
        ["node", CLI, "detect", path, "--json"],
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if proc.returncode != 0:
        return None
    line = proc.stdout.strip().splitlines()
    if not line:
        return None
    try:
        return json.loads(line[0])
    except json.JSONDecodeError:
        return None


def predict_baseline(blob, mode):
    """The two baselines described in the module docstring."""
    if mode == "always-gbk":
        return "gbk"
    # bom-then-gbk
    if blob.startswith(b"\xef\xbb\xbf"):
        return "utf-8"
    if blob.startswith(b"\xff\xfe\x00\x00"):
        return "utf-32le"
    if blob.startswith(b"\x00\x00\xfe\xff"):
        return "utf-32be"
    if blob.startswith(b"\xff\xfe"):
        return "utf-16-le"
    if blob.startswith(b"\xfe\xff"):
        return "utf-16-be"
    return "gbk"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", metavar="PATH", help="write raw results here")
    ap.add_argument(
        "--min-top1",
        type=float,
        default=None,
        help="exit non-zero if top-1 accuracy falls below this fraction",
    )
    args = ap.parse_args()

    if not os.path.exists(CLI):
        sys.exit(
            "missing %s\nrun `moon build --target js` first" % CLI
        )

    rows = []
    tmpdir = tempfile.mkdtemp(prefix="moonmojibake-acc-")
    try:
        index = 0
        for group, text, encodings in CORPUS:
            for codec, accept in encodings:
                index += 1
                try:
                    blob = text.encode(codec)
                except UnicodeEncodeError:
                    continue  # the codec cannot represent this text; not a case
                path = os.path.join(tmpdir, "case-%03d.bin" % index)
                with open(path, "wb") as fh:
                    fh.write(blob)

                result = run_detect(path)
                if result is None:
                    rows.append(
                        {
                            "group": group,
                            "codec": codec,
                            "bytes": len(blob),
                            "accept": accept,
                            "guess": None,
                            "top3": [],
                            "ambiguous": False,
                            "error": "detect failed",
                        }
                    )
                    continue

                guess = result.get("guess")
                ranking = [c["charset"] for c in result.get("candidates", [])]
                rows.append(
                    {
                        "group": group,
                        "codec": codec,
                        "bytes": len(blob),
                        "accept": accept,
                        "guess": guess,
                        "top3": ranking[:3],
                        "ambiguous": bool(result.get("ambiguous")),
                        "tied": result.get("tied", []),
                        "confidence": result.get("confidence"),
                        "bom_guess": predict_baseline(blob, "bom-then-gbk"),
                        "error": None,
                    }
                )

        # ASCII floor.
        ascii_rows = []
        for group, text, codec in ASCII_CASES:
            index += 1
            blob = text.encode(codec)
            path = os.path.join(tmpdir, "case-%03d.bin" % index)
            with open(path, "wb") as fh:
                fh.write(blob)
            result = run_detect(path)
            ascii_rows.append(
                {
                    "group": group,
                    "codec": codec,
                    "bytes": len(blob),
                    "guess": result.get("guess") if result else None,
                    "ambiguous": bool(result.get("ambiguous")) if result else False,
                }
            )
    finally:
        for name in os.listdir(tmpdir):
            os.unlink(os.path.join(tmpdir, name))
        os.rmdir(tmpdir)

    scored = [r for r in rows if r["error"] is None]
    total = len(scored)
    top1 = sum(1 for r in scored if r["guess"] in r["accept"])
    top3 = sum(1 for r in scored if set(r["top3"]) & set(r["accept"]))
    abstained = sum(1 for r in scored if r["ambiguous"])
    errors = len(rows) - total

    base = {
        "always-gbk": sum(1 for r in scored if "gbk" in r["accept"]),
        "bom-then-gbk": sum(1 for r in scored if r["bom_guess"] in r["accept"]),
    }

    # Per-group breakdown.
    groups = {}
    for r in scored:
        g = groups.setdefault(r["group"], {"n": 0, "top1": 0, "top3": 0})
        g["n"] += 1
        g["top1"] += 1 if r["guess"] in r["accept"] else 0
        g["top3"] += 1 if set(r["top3"]) & set(r["accept"]) else 0

    def pct(a, b):
        return 0.0 if b == 0 else 100.0 * a / b

    print("MoonMojibake detection accuracy")
    print("=" * 62)
    print("corpus        %d labelled cases (%d scored, %d detect errors)"
          % (total + errors, total, errors))
    print("")
    print("  %-22s %7s %7s %7s" % ("", "top-1", "top-3", "n"))
    print("  %-22s %7s %7s %7s" % ("-" * 22, "-" * 7, "-" * 7, "-" * 7))
    print("  %-22s %6.1f%% %6.1f%% %7d"
          % ("moonmojibake", pct(top1, total), pct(top3, total), total))
    for mode in ("always-gbk", "bom-then-gbk"):
        print("  %-22s %6.1f%% %7s %7d"
              % (mode, pct(base[mode], total), "-", total))
    print("")
    print("  abstained (reported as a tie): %d / %d (%.1f%%)"
          % (abstained, total, pct(abstained, total)))
    print("")
    print("  by script group")
    print("  %-12s %7s %7s %5s" % ("group", "top-1", "top-3", "n"))
    for name in sorted(groups):
        g = groups[name]
        print("  %-12s %6.1f%% %6.1f%% %5d"
              % (name, pct(g["top1"], g["n"]), pct(g["top3"], g["n"]), g["n"]))
    print("")
    print("  ASCII floor (all encodings at once, not scored): %d cases, guesses: %s"
          % (len(ascii_rows), ", ".join(str(r["guess"]) for r in ascii_rows)))
    print("")
    print("  worst cases")
    misses = [r for r in scored if r["guess"] not in r["accept"]]
    for r in misses[:10]:
        print("    %-10s %-12s expected %-22s got %-12s (top3 %s)"
              % (r["group"], r["codec"], ",".join(r["accept"]), r["guess"],
                 ",".join(r["top3"])))
    tied = [r for r in scored if r["ambiguous"]]
    if tied:
        print("")
        print("  reported as a tie (abstained rather than guessed):")
        for r in tied[:10]:
            print("    %-10s %-12s tied %s"
                  % (r["group"], r["codec"], ",".join(r.get("tied") or [])))

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(
                {
                    "total": total,
                    "top1": top1,
                    "top3": top3,
                    "abstained": abstained,
                    "baselines": base,
                    "groups": groups,
                    "ascii": ascii_rows,
                    "cases": rows,
                },
                fh,
                ensure_ascii=False,
                indent=2,
            )
        print("\nraw results -> %s" % args.json)

    if args.min_top1 is not None:
        actual = pct(top1, total) / 100.0
        if actual < args.min_top1:
            print(
                "\nFAIL: top-1 %.1f%% is below the %.1f%% floor"
                % (actual * 100, args.min_top1 * 100)
            )
            return 1
        print("\nOK: top-1 %.1f%% is at or above the %.1f%% floor"
              % (actual * 100, args.min_top1 * 100))
    return 0


if __name__ == "__main__":
    sys.exit(main())
