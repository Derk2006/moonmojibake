///|
/// Encoding detection: try every known code page, decode, score, rank.
///
/// This is the part the MoonBit ecosystem did not have.  Existing packages
/// such as `moon_encoding` map a *known* label to a decoder; detection has to
/// work without a label, so it runs the decoders and compares how plausible
/// the results look.

///|
fn starts_with_bytes(bytes : Bytes, first : Int, second : Int, third : Int) -> Bool {
  if bytes.length() < 3 {
    return false
  }
  bytes[0].to_int() == first &&
  bytes[1].to_int() == second &&
  bytes[2].to_int() == third
}

///|
fn starts_with_pair(bytes : Bytes, first : Int, second : Int) -> Bool {
  if bytes.length() < 2 {
    return false
  }
  bytes[0].to_int() == first && bytes[1].to_int() == second
}

///|
fn starts_with_quad(
  bytes : Bytes,
  first : Int,
  second : Int,
  third : Int,
  fourth : Int,
) -> Bool {
  if bytes.length() < 4 {
    return false
  }
  bytes[0].to_int() == first &&
  bytes[1].to_int() == second &&
  bytes[2].to_int() == third &&
  bytes[3].to_int() == fourth
}

///|
/// A byte order mark is the one case where detection is not a guess.
///
/// Order matters here: the UTF-32LE mark (FF FE 00 00) starts with the whole
/// UTF-16LE mark (FF FE), so a two-byte test first would claim every LE
/// UTF-32 file and then decode it as pairs of CJK / Hangul syllables.
fn bom_charset(bytes : Bytes) -> Charset? {
  if starts_with_bytes(bytes, 0xEF, 0xBB, 0xBF) {
    return Some(Charset::Utf8)
  }
  if starts_with_quad(bytes, 0xFF, 0xFE, 0x00, 0x00) {
    return Some(Charset::Utf32Le)
  }
  if starts_with_quad(bytes, 0x00, 0x00, 0xFE, 0xFF) {
    return Some(Charset::Utf32Be)
  }
  if starts_with_pair(bytes, 0xFF, 0xFE) {
    return Some(Charset::Utf16Le)
  }
  if starts_with_pair(bytes, 0xFE, 0xFF) {
    return Some(Charset::Utf16Be)
  }
  None
}

///|
/// Look for the alternating-zero pattern that UTF-16 produces for Latin text.
///
/// UTF-16 has no way to prove itself without a BOM: any even-length byte
/// stream decodes into *something*, and arbitrary pairs land in Hangul or in
/// the CJK blocks, where they look surprisingly plausible.  So instead of
/// trusting the score, UTF-16 has to show evidence — at least half of its
/// code units should have a zero high byte.
fn utf16_evidence(bytes : Bytes, little_endian : Bool) -> Bool {
  let length = bytes.length()
  if length < 4 || length % 2 != 0 {
    return false
  }
  let mut ascii_units = 0
  let mut units = 0
  let mut index = 0
  while index + 1 < length {
    let first = bytes[index].to_int()
    let second = bytes[index + 1].to_int()
    let high = if little_endian { second } else { first }
    let low = if little_endian { first } else { second }
    if high == 0 && low != 0 {
      ascii_units = ascii_units + 1
    }
    units = units + 1
    index = index + 2
  }
  units > 0 && ascii_units * 2 >= units
}

///|
/// UTF-32 is even easier to fake than UTF-16: any stream whose length is a
/// multiple of four decodes into code points, and the plausible ones (ASCII,
/// CJK, Hangul) all live in the low 16 bits.  Real UTF-32 text therefore has
/// to *show* it: at least half of the code units must have zero high bytes.
fn utf32_evidence(bytes : Bytes, little_endian : Bool) -> Bool {
  let length = bytes.length()
  if length < 8 || length % 4 != 0 {
    return false
  }
  let mut zero_high = 0
  let mut units = 0
  let mut index = 0
  while index + 3 < length {
    let b0 = bytes[index].to_int()
    let b1 = bytes[index + 1].to_int()
    let b2 = bytes[index + 2].to_int()
    let b3 = bytes[index + 3].to_int()
    let high = if little_endian { b2 + b3 } else { b0 + b1 }
    if high == 0 {
      zero_high = zero_high + 1
    }
    units = units + 1
    index = index + 4
  }
  units > 0 && zero_high * 2 >= units
}

///|
/// True when the bytes contain at least one multi-byte UTF-8 lead byte.
///
/// This matters because UTF-8 is self-validating: a legacy code page that
/// happens to form a well-shaped UTF-8 sequence across a whole file is a
/// coincidence on the order of one in billions, while the reverse — UTF-8
/// bytes read as a legacy code page — happens every day.  Valid multi-byte
/// UTF-8 is therefore close to proof, and it is what keeps a mojibake file
/// (which is valid UTF-8 of garbage) from being attributed to GBK.
fn has_multibyte_utf8_lead(bytes : Bytes) -> Bool {
  let length = bytes.length()
  let mut index = 0
  while index < length {
    if bytes[index].to_int() >= 0xC2 {
      return true
    }
    index = index + 1
  }
  false
}

///|
/// Rank every candidate, best first.  Ties keep `Charset::all()` order, so
/// plain ASCII resolves to UTF-8 rather than to whichever code page happened
/// to be tried last.
///
/// Returns an empty array when there is nothing to look at.
pub fn detect(bytes : Bytes) -> Array[Detection] {
  let results : Array[Detection] = []
  if bytes.length() == 0 {
    return results
  }
  let bom = bom_charset(bytes)
  if bom is Some(charset) {
    let decoded = decode(bytes, charset)
    results.push({
      charset,
      text: decoded.text,
      score: 100,
      errors: 0,
      confidence: 100,
    })
    return results
  }
  for charset in Charset::all() {
    let decoded = decode(bytes, charset)
    let mut score = score_decoded(decoded)
    if charset == Charset::Utf8 {
      if decoded.errors == 0 && has_multibyte_utf8_lead(bytes) {
        score = 100
      }
    }
    if charset == Charset::Utf16Le || charset == Charset::Utf16Be {
      let little_endian = charset == Charset::Utf16Le
      if !utf16_evidence(bytes, little_endian) {
        score = score / 2
      }
    }
    if charset == Charset::Utf32Le || charset == Charset::Utf32Be {
      let little_endian = charset == Charset::Utf32Le
      if !utf32_evidence(bytes, little_endian) {
        score = score / 2
      }
    }
    results.push({
      charset,
      text: decoded.text,
      score,
      errors: decoded.errors,
      confidence: 0,
    })
  }
  // Insertion sort: twelve candidates, and stability matters for tie-breaking.
  let mut i = 1
  while i < results.length() {
    let item = results[i]
    let mut j = i - 1
    while j >= 0 && results[j].score < item.score {
      results[j + 1] = results[j]
      j = j - 1
    }
    results[j + 1] = item
    i = i + 1
  }
  if results.length() > 1 {
    let top = results[0].score
    let second = results[1].score
    let mut confidence = (top - second) * 3
    if confidence > 100 {
      confidence = 100
    }
    if confidence < 0 {
      confidence = 0
    }
    if top < 40 {
      confidence = confidence * top / 40
    }
    // A script tie-breaker can only raise confidence when it actually broke
    // a tie.  A run of hiragana is "exclusively" Japanese and still decodes
    // identically under GBK, so without the `top > second` guard this would
    // report 85% confidence in a label that is a coin flip.
    if results[0].errors == 0 && exclusive_script(results[0].text) && top > second {
      if confidence < 85 {
        confidence = 85
      }
    }
    results[0] = {
      charset: results[0].charset,
      text: results[0].text,
      score: top,
      errors: results[0].errors,
      confidence,
    }
  }
  results
}

///|
/// Cheap gate for batch scanning: does this look like a binary file rather
/// than text?
///
/// A NUL byte is the signal.  UTF-16 and UTF-32 text legitimately contain
/// them, so a stream that shows either structure (or a BOM) is text; for
/// everything else, a NUL in the first 8 KiB means an image, an archive or
/// an object file, and ranking code pages for it would only produce noise.
/// This is a heuristic for reporting, not a classifier.
pub fn looks_binary(bytes : Bytes) -> Bool {
  if bom_charset(bytes) is Some(_) {
    return false
  }
  if utf16_evidence(bytes, true) || utf16_evidence(bytes, false) {
    return false
  }
  if utf32_evidence(bytes, true) || utf32_evidence(bytes, false) {
    return false
  }
  let limit = if bytes.length() < 8192 { bytes.length() } else { 8192 }
  let mut index = 0
  while index < limit {
    if bytes[index].to_int() == 0 {
      return true
    }
    index = index + 1
  }
  false
}

///|
/// Just the winner, or `None` for empty input.
pub fn detect_charset(bytes : Bytes) -> Charset? {
  let ranked = detect(bytes)
  if ranked.length() == 0 {
    None
  } else {
    Some(ranked[0].charset)
  }
}

///|
/// The winner's decoded text, or an empty string for empty input.
pub fn detect_text(bytes : Bytes) -> String {
  let ranked = detect(bytes)
  if ranked.length() == 0 {
    ""
  } else {
    ranked[0].text
  }
}

///|
/// The winner, or `fallback` when there is nothing to analyse.
pub fn detect_charset_or(bytes : Bytes, fallback : Charset) -> Charset {
  match detect_charset(bytes) {
    Some(charset) => charset
    None => fallback
  }
}
