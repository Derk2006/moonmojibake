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
    } else if (charset == Charset::ShiftJis || charset == Charset::EucJp) &&
      codepoint >= 0xFF61 &&
      codepoint <= 0xFF9F {
      // Same half-width katakana block, two different spellings: one bare
      // byte for Shift_JIS, an 0x8E prefix for EUC-JP.
      if charset == Charset::ShiftJis {
        buffer.write_byte((0xA1 + codepoint - 0xFF61).to_byte())
      } else {
        buffer.write_byte(b'\x8e')
        buffer.write_byte((0xA1 + codepoint - 0xFF61).to_byte())
      }
    } else if codepoint < 0x10000 && reverse[codepoint] != 0 {
      let pair = reverse[codepoint]
      buffer.write_byte((pair >> 8).to_byte())
      buffer.write_byte((pair & 0xFF).to_byte())
    } else if charset == Charset::Gb18030 &&
      gb18030_codepoint_ptr(codepoint) >= 0 {
      // Everything GBK cannot spell, GB18030 spells in four bytes — including
      // emoji and the rest of the supplementary planes, which is the whole
      // reason `--to gb18030` has to be a real code page and not an alias.
      let pointer = gb18030_codepoint_ptr(codepoint)
      buffer.write_byte((pointer / 12600 + 0x81).to_byte())
      buffer.write_byte(((pointer / 1260) % 10 + 0x30).to_byte())
      buffer.write_byte(((pointer / 10) % 126 + 0x81).to_byte())
      buffer.write_byte((pointer % 10 + 0x30).to_byte())
    } else if charset == Charset::EucJp &&
      codepoint < 0x10000 &&
      eucjp_0212_reverse[codepoint] != 0 {
      // JIS X 0212 characters have no JIS X 0208 spelling, so they only ever
      // take this branch.  The two-byte branch above is tried first because a
      // character mapped in both levels should keep its standard form.
      let pair = eucjp_0212_reverse[codepoint]
      buffer.write_byte(b'\x8f')
      buffer.write_byte((pair >> 8).to_byte())
      buffer.write_byte((pair & 0xFF).to_byte())
    } else {
      return None
    }
  }
  Some(buffer.to_bytes())
}

///|
/// UTF-32 is fixed-width: every code point is one 32-bit unit, so encoding
/// can never fail and needs no reverse table.
fn encode_utf32(text : String, little_endian : Bool) -> Bytes {
  let buffer = Buffer()
  for ch in text {
    let codepoint = ch.to_int()
    if little_endian {
      buffer.write_byte((codepoint & 0xFF).to_byte())
      buffer.write_byte(((codepoint >> 8) & 0xFF).to_byte())
      buffer.write_byte(((codepoint >> 16) & 0xFF).to_byte())
      buffer.write_byte(((codepoint >> 24) & 0xFF).to_byte())
    } else {
      buffer.write_byte(((codepoint >> 24) & 0xFF).to_byte())
      buffer.write_byte(((codepoint >> 16) & 0xFF).to_byte())
      buffer.write_byte(((codepoint >> 8) & 0xFF).to_byte())
      buffer.write_byte((codepoint & 0xFF).to_byte())
    }
  }
  buffer.to_bytes()
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
    Charset::Utf32Le => Some(encode_utf32(text, true))
    Charset::Utf32Be => Some(encode_utf32(text, false))
    Charset::Latin1 => encode_latin1(text)
    Charset::Cp1252 => encode_cp1252(text)
    Charset::Gbk
    | Charset::Gb18030
    | Charset::Big5
    | Charset::ShiftJis
    | Charset::EucJp
    | Charset::EucKr => encode_double_byte(text, charset)
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
    Charset::Gb18030,
    Charset::Big5,
    Charset::ShiftJis,
    Charset::EucJp,
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
    Charset::Gb18030,
    Charset::Big5,
    Charset::ShiftJis,
    Charset::EucJp,
    Charset::EucKr,
    Charset::Cp1252,
    Charset::Latin1,
  ]
}

///|
/// Coarse script tags.  Repair uses them to refuse a step that would swap one
/// CJK script for another.
const SCRIPT_NONE : Int = 0
const SCRIPT_LATIN : Int = 1
const SCRIPT_HAN : Int = 2
const SCRIPT_HANGUL : Int = 3
const SCRIPT_KANA : Int = 4

///|
fn dominant_script(text : String) -> Int {
  let mut latin = 0
  let mut han = 0
  let mut hangul = 0
  let mut kana = 0
  for ch in text {
    let codepoint = ch.to_int()
    if codepoint >= 0x4E00 && codepoint <= 0x9FFF {
      han = han + 1
    } else if codepoint >= 0xAC00 && codepoint <= 0xD7AF {
      hangul = hangul + 1
    } else if codepoint >= 0x3040 && codepoint <= 0x30FF {
      kana = kana + 1
    } else if (codepoint >= 0x41 && codepoint <= 0x5A) ||
      (codepoint >= 0x61 && codepoint <= 0x7A) ||
      (codepoint >= 0xC0 && codepoint <= 0x24F) {
      latin = latin + 1
    }
  }
  if han >= hangul && han >= kana && han >= latin && han > 0 {
    SCRIPT_HAN
  } else if hangul >= kana && hangul >= latin && hangul > 0 {
    SCRIPT_HANGUL
  } else if kana >= latin && kana > 0 {
    SCRIPT_KANA
  } else if latin > 0 {
    SCRIPT_LATIN
  } else {
    SCRIPT_NONE
  }
}

///|
/// Whether a repair step is allowed to turn `from` into `to`.
///
/// The classic case is single-byte garbage turning into real text, so Latin
/// and script-less input may go anywhere.  But once the text is already
/// Chinese, Japanese or Korean, a later round that lands in a *different* one
/// of those scripts is not undoing an encoding mistake — it is re-reading
/// perfectly good characters as another language.  A short Chinese string
/// whose mojibake was already fixed can otherwise be "improved" into Hangul,
/// which scores high because Hangul has no frequency model to hold it back.
fn script_step_allowed(from : Int, to : Int) -> Bool {
  if from == SCRIPT_HAN || from == SCRIPT_HANGUL || from == SCRIPT_KANA {
    return to == from
  }
  true
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
  let from_script = dominant_script(text)
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
        if !script_step_allowed(from_script, dominant_script(decoded.text)) {
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
/// Read bytes whose encoding is not known, then repair the text.
///
/// UTF-8 is tried first and accepted when it decodes without a single error.
/// That is the only reading under which the file needs no conversion at all;
/// every other code page is a guess, and a wrong guess that happens to decode
/// cleanly is the exact failure mode detection exists to weigh.  So the
/// cheap, exact answer is taken when it is available, and detection only
/// decides when UTF-8 cannot read the bytes.
///
/// The decoded text then goes through the same repair search as `repair`,
/// because a file can be both non-UTF-8 *and* mojibake: cp1252 bytes carrying
/// UTF-8 Chinese decode to a plausible string that is still wrong.
pub fn repair_auto(bytes : Bytes) -> AutoFix {
  let probe = decode(bytes, Charset::Utf8)
  let charset = if probe.errors() == 0 {
    Charset::Utf8
  } else {
    detect_charset_or(bytes, Charset::Utf8)
  }
  let text = if charset == Charset::Utf8 {
    probe.text()
  } else {
    decode(bytes, charset).text()
  }
  { charset, result: repair(text) }
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
