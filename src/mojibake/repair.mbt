///|
/// Encoding, and mojibake repair.
///
/// Repair reverses the classic accident: bytes that were really UTF-8 got
/// decoded with a legacy code page, and the result was saved as UTF-8 again.
/// Undoing it means encoding the text back into the code page that was
/// wrongly applied, then decoding the recovered bytes with the right one.
/// One pass fixes one mistake; a few passes fix chains, which do happen when
/// a file travels through more than one broken tool.

///|
fn encode_latin1(text : String) -> Bytes? {
  let buffer = Buffer()
  for ch in text {
    let codepoint = ch.to_int()
    if codepoint > 0xFF {
      return None
    }
    buffer.write_byte(codepoint.to_byte())
  }
  Some(buffer.to_bytes())
}

///|
fn encode_cp1252(text : String) -> Bytes? {
  let buffer = Buffer()
  for ch in text {
    let codepoint = ch.to_int()
    if codepoint < 0x80 {
      buffer.write_byte(codepoint.to_byte())
    } else if codepoint >= 0xA0 && codepoint <= 0xFF {
      buffer.write_byte(codepoint.to_byte())
    } else {
      let mut slot = -1
      let mut index = 0
      while index < 32 {
        if cp1252_high[index] == codepoint {
          slot = index
          break
        }
        index = index + 1
      }
      if slot < 0 {
        return None
      }
      buffer.write_byte((0x80 + slot).to_byte())
    }
  }
  Some(buffer.to_bytes())
}

///|
fn encode_double_byte(text : String, charset : Charset) -> Bytes? {
  let reverse = double_byte_reverse(charset)
  let buffer = Buffer()
  for ch in text {
    let codepoint = ch.to_int()
    if codepoint < 0x80 {
      buffer.write_byte(codepoint.to_byte())
    } else if charset == Charset::ShiftJis &&
      codepoint >= 0xFF61 &&
      codepoint <= 0xFF9F {
      buffer.write_byte((0xA1 + codepoint - 0xFF61).to_byte())
    } else if codepoint < 0x10000 && reverse[codepoint] != 0 {
      let pair = reverse[codepoint]
      buffer.write_byte((pair >> 8).to_byte())
      buffer.write_byte((pair & 0xFF).to_byte())
    } else {
      return None
    }
  }
  Some(buffer.to_bytes())
}

///|
/// Encode `text` into `charset`, or `None` when some character has no
/// representation there.  A failure is meaningful: text that cannot be
/// encoded in a code page was never produced by that code page.
pub fn encode(text : String, charset : Charset) -> Bytes? {
  match charset {
    Charset::Utf8 => Some(@utf8.encode(text))
    Charset::Utf16Le =>
      Some(@utf16.encode(text, endianness=@utf16.Endian::Little))
    Charset::Utf16Be => Some(@utf16.encode(text, endianness=@utf16.Endian::Big))
    Charset::Latin1 => encode_latin1(text)
    Charset::Cp1252 => encode_cp1252(text)
    Charset::Gbk | Charset::Big5 | Charset::ShiftJis | Charset::EucKr =>
      encode_double_byte(text, charset)
  }
}

///|
/// Code pages that broken pipelines actually mix up.  UTF-16 is left out on
/// purpose: when UTF-16 goes wrong the result is unreadable at the byte level
/// rather than mojibake, and there is nothing to recover.
fn repair_sources() -> Array[Charset] {
  [
    Charset::Cp1252,
    Charset::Latin1,
    Charset::Gbk,
    Charset::Big5,
    Charset::ShiftJis,
    Charset::EucKr,
  ]
}

///|
/// Code pages a repair can land on.  UTF-16 is excluded even though the
/// detector understands it: nobody re-encodes a file to UTF-16 by accident
/// and then calls the result mojibake, and allowing it here makes the search
/// "repair" Chinese into Hangul, which decodes cleanly and scores well.
fn repair_targets() -> Array[Charset] {
  [
    Charset::Utf8,
    Charset::Gbk,
    Charset::Big5,
    Charset::ShiftJis,
    Charset::EucKr,
    Charset::Cp1252,
    Charset::Latin1,
  ]
}

///|
/// How many chained mistakes repair is willing to undo.
const REPAIR_MAX_ROUNDS : Int = 4

///|
/// Minimum score gain before a round is considered a success.  Without a
/// margin the search happily "repairs" already-correct text into something
/// marginally more frequent.
const REPAIR_MIN_GAIN : Int = 4

///|
/// One repair round: return the best improvement, or `None`.
fn repair_round(text : String, current : Int) -> (String, Int, FixStep)? {
  let mut best_text = text
  let mut best_score = current
  let mut best : FixStep? = None
  for wrong in repair_sources() {
    let recovered = encode(text, wrong)
    if recovered is Some(bytes) {
      for right in repair_targets() {
        if right == wrong {
          continue
        }
        let decoded = decode(bytes, right)
        if decoded.errors > 0 {
          continue
        }
        let score = score_decoded(decoded)
        if score > best_score + REPAIR_MIN_GAIN {
          best_score = score
          best_text = decoded.text
          best = Some({ wrong, right })
        }
      }
    }
  }
  match best {
    Some(step) => Some((best_text, best_score, step))
    None => None
  }
}

///|
/// Undo as much mojibake as can be undone, one layer at a time.
///
/// `before` and `after` are text-likeness scores in 0..100, so a caller can
/// tell whether anything actually happened.
pub fn repair(text : String) -> FixResult {
  let steps : Array[FixStep] = []
  let mut current = text
  let mut current_score = text_score(current, 0)
  let before = current_score
  let mut round = 0
  while round < REPAIR_MAX_ROUNDS {
    let attempt = repair_round(current, current_score)
    if attempt is Some((next_text, next_score, step)) {
      steps.push(step)
      current = next_text
      current_score = next_score
      round = round + 1
    } else {
      break
    }
  }
  { text: current, steps, before, after: current_score }
}

///|
/// `true` when repair found at least one layer to undo.
pub fn was_repaired(result : FixResult) -> Bool {
  result.steps.length() > 0
}

///|
/// Render the chain as `windows-1252 -> utf-8`, or an empty string when the
/// text was already fine.  Multiple steps are joined with `, then `.
pub fn render_chain(result : FixResult) -> String {
  if result.steps.length() == 0 {
    return ""
  }
  let out = StringBuilder()
  let mut index = 0
  while index < result.steps.length() {
    let step = result.steps[index]
    if index > 0 {
      out.write_string(", then ")
    }
    out.write_string(step.wrong.name())
    out.write_string(" -> ")
    out.write_string(step.right.name())
    index = index + 1
  }
  out.to_string()
}
