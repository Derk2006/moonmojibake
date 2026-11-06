///|
/// Machine-readable output.
///
/// The terminal report is for humans; anything that wants to act on a
/// detection result — a migration script, a CI gate, another language —
/// needs a stable shape instead of a padded table.  These renderers emit
/// JSON built by hand, which keeps the package free of a dependency and
/// keeps the field order fixed.

///|
fn hex_digit(value : Int) -> Char {
  if value < 10 {
    (0x30 + value).unsafe_to_char()
  } else {
    (0x61 + value - 10).unsafe_to_char()
  }
}

///|
/// Append `\u00XX` for a control character.
fn write_control_escape(out : StringBuilder, codepoint : Int) -> Unit {
  out.write_char('\\')
  out.write_char('u')
  out.write_char('0')
  out.write_char('0')
  out.write_char(hex_digit(codepoint / 16))
  out.write_char(hex_digit(codepoint % 16))
}

///|
/// Escape a string for a JSON string literal.
///
/// Only the characters JSON requires are escaped.  Non-ASCII text stays as
/// UTF-8, which is valid JSON and keeps Chinese samples readable in the
/// output instead of turning them into a wall of `\u` escapes.
pub fn json_escape(text : String) -> String {
  let out = StringBuilder()
  for ch in text {
    let codepoint = ch.to_int()
    if ch == '"' {
      out.write_string("\\\"")
    } else if ch == '\\' {
      out.write_string("\\\\")
    } else if ch == '\n' {
      out.write_string("\\n")
    } else if ch == '\r' {
      out.write_string("\\r")
    } else if ch == '\t' {
      out.write_string("\\t")
    } else if codepoint < 0x20 {
      write_control_escape(out, codepoint)
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
fn quoted(text : String) -> String {
  "\"" + json_escape(text) + "\""
}

///|
/// JSON for a detection report: the winner first, then every candidate.
///
/// `text` is deliberately absent — a candidate list is metadata, and a
/// multi-megabyte decoded body does not belong in a summary.  Use
/// `convert` when the text itself is wanted.
pub fn detection_json(source : String, byte_count : Int, rows : Array[Detection]) -> String {
  let out = StringBuilder()
  out.write_string("{\"source\":")
  out.write_string(quoted(source))
  out.write_string(",\"bytes\":")
  out.write_string(byte_count.to_string())
  if rows.length() == 0 {
    out.write_string(",\"guess\":null,\"candidates\":[]}")
    return out.to_string()
  }
  let best = rows[0]
  out.write_string(",\"guess\":")
  out.write_string(quoted(best.charset.name()))
  out.write_string(",\"confidence\":")
  out.write_string(best.confidence.to_string())
  out.write_string(",\"score\":")
  out.write_string(best.score.to_string())
  out.write_string(",\"errors\":")
  out.write_string(best.errors.to_string())
  out.write_string(",\"candidates\":[")
  let mut index = 0
  while index < rows.length() {
    if index > 0 {
      out.write_string(",")
    }
    let row = rows[index]
    out.write_string("{\"charset\":")
    out.write_string(quoted(row.charset.name()))
    out.write_string(",\"family\":")
    out.write_string(quoted(row.charset.family()))
    out.write_string(",\"score\":")
    out.write_string(row.score.to_string())
    out.write_string(",\"confidence\":")
    out.write_string(row.confidence.to_string())
    out.write_string(",\"errors\":")
    out.write_string(row.errors.to_string())
    out.write_string("}")
    index = index + 1
  }
  out.write_string("]}")
  out.to_string()
}

///|
/// JSON for a repair result, including the recovered text and the chain.
pub fn fix_json(source : String, result : FixResult) -> String {
  let out = StringBuilder()
  out.write_string("{\"source\":")
  out.write_string(quoted(source))
  out.write_string(",\"repaired\":")
  out.write_string(if result.steps.length() > 0 { "true" } else { "false" })
  out.write_string(",\"before\":")
  out.write_string(result.before.to_string())
  out.write_string(",\"after\":")
  out.write_string(result.after.to_string())
  out.write_string(",\"chain\":[")
  let mut index = 0
  while index < result.steps.length() {
    if index > 0 {
      out.write_string(",")
    }
    let step = result.steps[index]
    out.write_string("{\"wrong\":")
    out.write_string(quoted(step.wrong.name()))
    out.write_string(",\"right\":")
    out.write_string(quoted(step.right.name()))
    out.write_string("}")
    index = index + 1
  }
  out.write_string("],\"text\":")
  out.write_string(quoted(result.text))
  out.write_string("}")
  out.to_string()
}
