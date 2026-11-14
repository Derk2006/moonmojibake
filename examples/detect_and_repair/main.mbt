///|
/// A runnable tour of the three things this library does.  No file IO, so it
/// runs on every backend:
///
///   moon run examples/detect_and_repair
///
fn main {
  // 1. Decode — bytes plus a label is the easy case.
  let gbk_bytes : Bytes = b"\xd6\xd0\xce\xc4\xc6\xda\xbf\xaf"
  println("decode")
  println(
    "  gbk bytes -> \{@mojibake.decode_text(gbk_bytes, @mojibake.Charset::Gbk)}",
  )

  // 2. Detect — no label, so rank every code page and show the evidence.
  println("")
  println("detect")
  let ranked = @mojibake.detect(gbk_bytes)
  for i in 0..<3 {
    let row = ranked[i]
    println(
      "  \{i + 1}. \{row.charset().name()}  score=\{row.score()} conf=\{row.confidence()} errors=\{row.errors()}  \{row.text()}",
    )
  }
  println(
    "  guess: \{ranked[0].charset().name()} (confidence \{ranked[0].confidence()}%)",
  )

  // 3. Repair — text that was already decoded with the wrong label.
  println("")
  println("repair")
  let broken = "ä¸­æ–‡æµ‹è¯•"
  let fixed = @mojibake.repair(broken)
  println("  broken: \{broken}")
  println("  fixed : \{fixed.text()}")
  println("  score : \{fixed.before()} -> \{fixed.after()}")
  for step in fixed.steps() {
    println("  chain : \{step.wrong().name()} -> \{step.right().name()}")
  }

  // 4. Ties — when two labels explain the bytes equally well, say so.
  println("")
  println("ties")
  let kana : Bytes = b"\xa4\xa2\xa4\xa4\xa4\xa6\xa4\xa8\xa4\xaa"
  let kana_rows = @mojibake.detect(kana)
  if @mojibake.is_ambiguous(kana_rows) {
    let tied = @mojibake.ambiguous_candidates(kana_rows)
    println(
      "  pure kana ties: \{tied[0].name()} / \{tied[1].name()}  (confidence \{kana_rows[0].confidence()}%)",
    )
    println("  the text is correct under both; no label is invented")
  } else {
    println("  unexpected: this sample is supposed to be a tie")
  }
}
