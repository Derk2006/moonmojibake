///|
/// Decoders.
///
/// Every decoder is *total*: instead of raising, an undecodable sequence is
/// replaced by U+FFFD and counted in `Decoded::errors`.  That is what makes
/// the detector work — a wrong guess produces a high error count, and a right
/// guess produces zero.

///|
/// windows-1252 differs from ISO-8859-1 only in 0x80..0x9F.  A zero entry is
/// a byte windows-1252 leaves undefined.
let cp1252_high : Array[Int] = [
  0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017D, 0, //
  0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, //
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0, 0x017E, 0x0178, //
]

///|
/// True when the code page uses a lead byte here.
fn is_lead_byte(charset : Charset, byte : Int) -> Bool {
  match charset {
    Charset::Gbk | Charset::Big5 => byte >= 0x81 && byte <= 0xFE
    Charset::EucKr => byte >= 0xA1 && byte <= 0xFE
    Charset::ShiftJis =>
      (byte >= 0x81 && byte <= 0x9F) || (byte >= 0xE0 && byte <= 0xEF)
    _ => false
  }
}

///|
fn replacement_char() -> Char {
  (0xFFFD).unsafe_to_char()
}

///|
/// Decode a two-byte code page.  ASCII passes through, Shift_JIS half-width
/// katakana are computed, everything else goes through the tables.
fn decode_double_byte(bytes : Bytes, charset : Charset) -> Decoded {
  let out = StringBuilder(size_hint=bytes.length() + 8)
  let length = bytes.length()
  let mut index = 0
  let mut errors = 0
  let mut chars = 0
  while index < length {
    let byte = bytes[index].to_int()
    if byte < 0x80 {
      out.write_char(byte.unsafe_to_char())
      chars = chars + 1
      index = index + 1
    } else if charset == Charset::ShiftJis && byte >= 0xA1 && byte <= 0xDF {
      out.write_char((0xFF61 + byte - 0xA1).unsafe_to_char())
      chars = chars + 1
      index = index + 1
    } else if is_lead_byte(charset, byte) && index + 1 < length {
      let trail = bytes[index + 1].to_int()
      let codepoint = table_lookup(charset, byte, trail)
      if codepoint != 0 {
        out.write_char(codepoint.unsafe_to_char())
        chars = chars + 1
        index = index + 2
      } else {
        out.write_char(replacement_char())
        chars = chars + 1
        errors = errors + 1
        index = index + 1
      }
    } else {
      out.write_char(replacement_char())
      chars = chars + 1
      errors = errors + 1
      index = index + 1
    }
  }
  { text: out.to_string(), errors: errors, chars: chars }
}

///|
/// Count U+FFFD in a lossy decode, plus the total number of characters.
fn count_lossy(text : String) -> (Int, Int) {
  let mut errors = 0
  let mut chars = 0
  for ch in text {
    chars = chars + 1
    if ch == replacement_char() {
      errors = errors + 1
    }
  }
  (errors, chars)
}

///|
fn decode_utf8(bytes : Bytes) -> Decoded {
  let text = @utf8.decode_lossy(bytes, ignore_bom=true)
  let (errors, chars) = count_lossy(text)
  { text: text, errors: errors, chars: chars }
}

///|
fn decode_utf16(bytes : Bytes, little_endian : Bool) -> Decoded {
  let endianness = if little_endian {
    @utf16.Endian::Little
  } else {
    @utf16.Endian::Big
  }
  let text = @utf16.decode_lossy(bytes, ignore_bom=true, endianness=endianness)
  let (errors, chars) = count_lossy(text)
  { text: text, errors: errors, chars: chars }
}

///|
/// Decode UTF-32.  Each code unit is a full code point, so the only thing a
/// strict decoder has to reject is a value outside Unicode: above U+10FFFF,
/// or inside the surrogate range (which UTF-32 must never carry).
///
/// The length check matters more than it looks.  UTF-32 is fixed-width, so a
/// stream whose length is not a multiple of four is not UTF-32 at all, yet a
/// lossy decoder would happily produce text from the prefix.  Counting the
/// leftover bytes as errors keeps such a stream from winning detection.
fn decode_utf32(bytes : Bytes, little_endian : Bool) -> Decoded {
  let out = StringBuilder(size_hint=bytes.length() / 2 + 8)
  let length = bytes.length()
  let mut index = 0
  let mut errors = 0
  let mut chars = 0
  let mut first = true
  while index + 3 < length {
    let b0 = bytes[index].to_int()
    let b1 = bytes[index + 1].to_int()
    let b2 = bytes[index + 2].to_int()
    let b3 = bytes[index + 3].to_int()
    // The high byte decides whether the value can be in range at all; check it
    // before shifting so the arithmetic never has to rely on wrapping.
    let mut codepoint = -1
    if little_endian {
      if b3 <= 0x10 {
        codepoint = b0 + (b1 << 8) + (b2 << 16) + (b3 << 24)
      }
    } else if b0 <= 0x10 {
      codepoint = b3 + (b2 << 8) + (b1 << 16) + (b0 << 24)
    }
    let valid = codepoint >= 0 &&
      codepoint <= 0x10FFFF &&
      !(codepoint >= 0xD800 && codepoint <= 0xDFFF)
    if valid {
      // Drop a leading byte-order mark, matching what the UTF-8 and UTF-16
      // decoders do with `ignore_bom`.
      if !(first && codepoint == 0xFEFF) {
        out.write_char(codepoint.unsafe_to_char())
        chars = chars + 1
      }
    } else {
      out.write_char(replacement_char())
      chars = chars + 1
      errors = errors + 1
    }
    first = false
    index = index + 4
  }
  // A trailing partial unit can never be valid UTF-32.
  while index < length {
    out.write_char(replacement_char())
    chars = chars + 1
    errors = errors + 1
    index = index + 1
  }
  { text: out.to_string(), errors: errors, chars: chars }
}

///|
fn decode_latin1(bytes : Bytes) -> Decoded {
  let out = StringBuilder(size_hint=bytes.length() + 8)
  let length = bytes.length()
  let mut index = 0
  while index < length {
    out.write_char(bytes[index].to_int().unsafe_to_char())
    index = index + 1
  }
  { text: out.to_string(), errors: 0, chars: length }
}

///|
fn decode_cp1252(bytes : Bytes) -> Decoded {
  let out = StringBuilder(size_hint=bytes.length() + 8)
  let length = bytes.length()
  let mut index = 0
  let mut errors = 0
  while index < length {
    let byte = bytes[index].to_int()
    if byte >= 0x80 && byte <= 0x9F {
      let codepoint = cp1252_high[byte - 0x80]
      if codepoint == 0 {
        out.write_char(replacement_char())
        errors = errors + 1
      } else {
        out.write_char(codepoint.unsafe_to_char())
      }
    } else {
      out.write_char(byte.unsafe_to_char())
    }
    index = index + 1
  }
  { text: out.to_string(), errors: errors, chars: length }
}

///|
/// Decode `bytes` under `charset`, replacing and counting malformed input.
pub fn decode(bytes : Bytes, charset : Charset) -> Decoded {
  match charset {
    Charset::Utf8 => decode_utf8(bytes)
    Charset::Utf16Le => decode_utf16(bytes, true)
    Charset::Utf16Be => decode_utf16(bytes, false)
    Charset::Utf32Le => decode_utf32(bytes, true)
    Charset::Utf32Be => decode_utf32(bytes, false)
    Charset::Latin1 => decode_latin1(bytes)
    Charset::Cp1252 => decode_cp1252(bytes)
    Charset::Gbk | Charset::Big5 | Charset::ShiftJis | Charset::EucKr =>
      decode_double_byte(bytes, charset)
  }
}

///|
/// Convenience wrapper that only returns the text.
pub fn decode_text(bytes : Bytes, charset : Charset) -> String {
  decode(bytes, charset).text
}
