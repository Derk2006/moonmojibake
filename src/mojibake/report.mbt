///|
/// Report rendering.
///
/// Kept in the library rather than the CLI so the output format is testable
/// and so other tools can embed the same tables.

///|
/// Drop one trailing newline so callers can use a line-oriented printer.
fn trim_end_newline(text : String) -> String {
  let chars : Array[Char] = []
  for ch in text {
    chars.push(ch)
  }
  let length = chars.length()
  if length > 0 && chars[length - 1] == '\n' {
    let _ = chars.pop()
  }
  String::from_array(chars)
}

///|
fn visible_length(text : String) -> Int {
  let mut count = 0
  for _ch in text {
    count = count + 1
  }
  count
}

///|
fn pad_right(text : String, width : Int) -> String {
  let out = StringBuilder()
  out.write_string(text)
  let mut width_now = visible_length(text)
  while width_now < width {
    out.write_char(' ')
    width_now = width_now + 1
  }
  out.to_string()
}

///|
fn pad_left(text : String, width : Int) -> String {
  let out = StringBuilder()
  let mut width_now = visible_length(text)
  while width_now < width {
    out.write_char(' ')
    width_now = width_now + 1
  }
  out.write_string(text)
  out.to_string()
}

///|
/// First `limit` characters of `text`, with control characters blanked so a
/// broken decode cannot wreck the terminal.
fn preview(text : String, limit : Int) -> String {
  let out = StringBuilder()
  let mut taken = 0
  for ch in text {
    if taken >= limit {
      break
    }
    let codepoint = ch.to_int()
    if codepoint < 0x20 || codepoint == 0x7F {
      out.write_char(' ')
    } else {
      out.write_char(ch)
    }
    taken = taken + 1
  }
  out.to_string()
}

///|
/// Render the ranked candidate table.
pub fn render_detection(source : String, byte_count : Int, rows : Array[Detection]) -> String {
  let out = StringBuilder()
  out.write_string(source)
  out.write_string(" (")
  out.write_string(byte_count.to_string())
  out.write_string(" bytes)\n\n")
  if rows.length() == 0 {
    out.write_string("empty input")
    return out.to_string()
  }
  out.write_string("  #  encoding        score  conf  errors  sample\n")
  let mut index = 0
  while index < rows.length() {
    let row = rows[index]
    out.write_string(pad_left((index + 1).to_string(), 3))
    out.write_string("  ")
    out.write_string(pad_right(row.charset.name(), 14))
    out.write_string("  ")
    out.write_string(pad_left(row.score.to_string(), 5))
    out.write_string("  ")
    out.write_string(pad_left(row.confidence.to_string(), 4))
    out.write_string("  ")
    out.write_string(pad_left(row.errors.to_string(), 6))
    out.write_string("  ")
    out.write_string(preview(row.text, 24))
    out.write_string("\n")
    index = index + 1
  }
  out.write_string("\n")
  let best = rows[0]
  out.write_string("guess: ")
  out.write_string(best.charset.name())
  out.write_string("  (confidence ")
  out.write_string(best.confidence.to_string())
  out.write_string("%, score ")
  out.write_string(best.score.to_string())
  out.write_string(")\n")
  if best.confidence < 30 {
    out.write_string(
      "note: the input is ambiguous. Plain ASCII decodes identically in every ASCII-compatible code page, so there is nothing to tell them apart.\n",
    )
  }
  if best.errors > 0 {
    out.write_string(
      "note: the best candidate still had malformed sequences; the input may be truncated or double-corrupted.",
    )
  }
  trim_end_newline(out.to_string())
}

///|
/// Render a repair result.
pub fn render_fix(result : FixResult) -> String {
  let out = StringBuilder()
  if result.steps.length() == 0 {
    out.write_string("no mojibake chain found (score ")
    out.write_string(result.before.to_string())
    out.write_string("/100)")
    return out.to_string()
  }
  out.write_string("score ")
  out.write_string(result.before.to_string())
  out.write_string(" -> ")
  out.write_string(result.after.to_string())
  out.write_string("\nchain: ")
  out.write_string(render_chain(result))
  out.write_string("\n\n")
  out.write_string(result.text)
  trim_end_newline(out.to_string())
}
