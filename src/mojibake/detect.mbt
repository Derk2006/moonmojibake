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
/// The four wide-encoding tests, answered from one pass over the bytes.
///
/// UTF-16 and UTF-32 have no way to prove themselves without a BOM: any
/// even-length stream decodes into *something*, and arbitrary pairs land in
/// Hangul or in the CJK blocks, where they look surprisingly plausible.  So
/// instead of trusting the score, they have to show evidence — at least half
/// of the UTF-16 code units should have a zero high byte, and at least half of
/// the UTF-32 code units should have both high bytes zero.  That is what keeps
/// a GBK file from being read as pairs of Hangul syllables.
///
/// These were four full scans of the input, each looking at the same bytes
/// from a different angle.  Folding them into one loop over four bytes at a
/// time is the same arithmetic on the same values — `detect_wbtest.mbt` holds
/// the single-purpose versions and asserts the two agree byte for byte,
/// including the 2- and 3-byte tails where the two shapes disagree about how
/// much of the input is a code unit.
priv struct WideEvidence {
  utf16_le : Bool
  utf16_be : Bool
  utf32_le : Bool
  utf32_be : Bool
}

///|
fn wide_evidence(bytes : Bytes) -> WideEvidence {
  let length = bytes.length()
  let mut u16_units = 0
  let mut u16le_ascii = 0
  let mut u16be_ascii = 0
  let mut u32_units = 0
  let mut u32le_zero = 0
  let mut u32be_zero = 0
  let mut index = 0
  let quads = length - length % 4
  while index < quads {
    let b0 = bytes[index].to_int()
    let b1 = bytes[index + 1].to_int()
    let b2 = bytes[index + 2].to_int()
    let b3 = bytes[index + 3].to_int()
    if b1 == 0 && b0 != 0 {
      u16le_ascii = u16le_ascii + 1
    }
    if b0 == 0 && b1 != 0 {
      u16be_ascii = u16be_ascii + 1
    }
    if b3 == 0 && b2 != 0 {
      u16le_ascii = u16le_ascii + 1
    }
    if b2 == 0 && b3 != 0 {
      u16be_ascii = u16be_ascii + 1
    }
    u16_units = u16_units + 2
    if b2 + b3 == 0 {
      u32le_zero = u32le_zero + 1
    }
    if b0 + b1 == 0 {
      u32be_zero = u32be_zero + 1
    }
    u32_units = u32_units + 1
    index = index + 4
  }
  // A trailing pair, when the length is 2 mod 4.  A length of 3 mod 4 leaves
  // a pair plus a byte; the pair is still counted here and then discarded by
  // the even-length gate below, exactly as the per-encoding scan discarded it.
  if index + 1 < length {
    let b0 = bytes[index].to_int()
    let b1 = bytes[index + 1].to_int()
    if b1 == 0 && b0 != 0 {
      u16le_ascii = u16le_ascii + 1
    }
    if b0 == 0 && b1 != 0 {
      u16be_ascii = u16be_ascii + 1
    }
    u16_units = u16_units + 1
  }
  let even = length % 2 == 0
  let quad = length % 4 == 0
  {
    utf16_le: length >= 4 &&
      even &&
      u16_units > 0 &&
      u16le_ascii * 2 >= u16_units,
    utf16_be: length >= 4 &&
      even &&
      u16_units > 0 &&
      u16be_ascii * 2 >= u16_units,
    utf32_le: length >= 8 &&
      quad &&
      u32_units > 0 &&
      u32le_zero * 2 >= u32_units,
    utf32_be: length >= 8 &&
      quad &&
      u32_units > 0 &&
      u32be_zero * 2 >= u32_units,
  }
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
/// True when any byte falls in windows-1252's C1 range.
///
/// That range is the only place the page differs from ISO-8859-1, so its
/// absence means one decode can answer for both labels.
fn has_c1_byte(bytes : Bytes) -> Bool {
  let length = bytes.length()
  let mut index = 0
  while index < length {
    let byte = bytes[index].to_int()
    if byte >= 0x80 && byte <= 0x9F {
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
      equivalent: [],
    })
    return results
  }
  // One pass answers all four wide-encoding tests; see `wide_evidence`.
  let wide = wide_evidence(bytes)
  // Two labels can share one decode, and both cases are *proved* rather than
  // assumed:
  //
  //   * windows-1252 and ISO-8859-1 differ only inside 0x80..0x9F, so a stream
  //     with no byte in that range decodes identically under both.
  //   * every mapping GBK defines is the same mapping in GB18030 (checked slot
  //     by slot in `detect_wbtest.mbt`; GB18030 only adds 2149 slots GBK leaves
  //     empty).  A GBK decode with zero errors therefore cannot have touched a
  //     GB18030 four-byte form either — that form needs a digit after the lead
  //     byte, and a digit is not a legal GBK trail, so it would have been an
  //     error.
  //
  // Reusing the result is not a shortcut that changes the answer; it is the
  // same answer, computed once.
  let c1_present = has_c1_byte(bytes)
  let mut gbk_decoded : Decoded? = None
  let mut gbk_score = 0
  let mut gbk_reusable = false
  let mut cp1252_decoded : Decoded? = None
  let mut cp1252_score = 0
  for charset in Charset::all() {
    // Reusing the decode means the score is the same number too, so it is
    // carried over with it rather than recomputed over the same text.
    let carried : (Decoded?, Int) = if charset == Charset::Gb18030 &&
      gbk_reusable {
      (gbk_decoded, gbk_score)
    } else if charset == Charset::Latin1 && !c1_present {
      (cp1252_decoded, cp1252_score)
    } else {
      (None, 0)
    }
    let (decoded, base_score) = match carried {
      (Some(previous), previous_score) => (previous, previous_score)
      _ => {
        let fresh = decode(bytes, charset)
        (fresh, score_decoded(fresh))
      }
    }
    if charset == Charset::Gbk {
      gbk_decoded = Some(decoded)
      gbk_score = base_score
      gbk_reusable = decoded.errors == 0
    }
    if charset == Charset::Cp1252 {
      cp1252_decoded = Some(decoded)
      cp1252_score = base_score
    }
    let mut score = base_score
    if charset == Charset::Utf8 {
      if decoded.errors == 0 && has_multibyte_utf8_lead(bytes) {
        score = 100
      }
    }
    if charset == Charset::Utf16Le && !wide.utf16_le {
      score = score / 2
    }
    if charset == Charset::Utf16Be && !wide.utf16_be {
      score = score / 2
    }
    if charset == Charset::Utf32Le && !wide.utf32_le {
      score = score / 2
    }
    if charset == Charset::Utf32Be && !wide.utf32_be {
      score = score / 2
    }
    results.push({
      charset,
      text: decoded.text,
      score,
      errors: decoded.errors,
      confidence: 0,
      equivalent: [],
    })
  }
  // UTF-16 is halved above unless it can prove itself with an ASCII pattern,
  // because any even-length stream decodes into *something*.  That test is
  // written for Latin text: correct CJK prose in UTF-16 has no zero high byte
  // at all, so it gets halved to a score in the forties and loses to the
  // Latin-1 reading of the same bytes — the one case where the conservative
  // rule produces a wrong answer rather than a cautious one.
  //
  // Reinstating the full score is gated on every 8-bit reading being clearly
  // worse, not on the UTF-16 score alone.  A GBK stream read as UTF-16 also
  // lands in plausible blocks, so "it looks like text as UTF-16" is on its own
  // no evidence at all; what distinguishes the real case is that nothing else
  // explains the bytes nearly as well.
  let mut best_eight_bit = 0
  for row in results {
    let is_wide = row.charset == Charset::Utf16Le ||
      row.charset == Charset::Utf16Be ||
      row.charset == Charset::Utf32Le ||
      row.charset == Charset::Utf32Be
    if !is_wide && row.score > best_eight_bit {
      best_eight_bit = row.score
    }
  }
  let mut wide_index = 0
  while wide_index < results.length() {
    let row = results[wide_index]
    if row.charset == Charset::Utf16Le || row.charset == Charset::Utf16Be {
      let full = text_score(row.text, row.errors)
      if row.errors == 0 &&
        full >= best_eight_bit + 20 &&
        scripted_share(row.text) >= 80 {
        results[wide_index] = {
          charset: row.charset,
          text: row.text,
          score: full,
          errors: row.errors,
          confidence: 0,
          equivalent: [],
        }
      }
    }
    wide_index = wide_index + 1
  }
  // Insertion sort: every candidate, and stability matters for tie-breaking.
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
  // Two labels that decode the bytes to byte-identical text at the same score
  // are one reading, not two candidates.  Listing both was a real defect: a
  // short Latin-1 file produced "windows-1252" and "latin1" as separate rows,
  // which pushed the actual runner-up out of the top three and made the count
  // of candidates a function of how many aliases a byte range happens to have.
  //
  // The GBK / GB18030 case is deliberately *not* a merge.  GB18030 is a strict
  // superset, so when a file never leaves GBK's range the wider label has no
  // evidence at all; recording it as an equivalent would be claiming the bytes
  // are indifferent when they are simply narrower than the decoder.
  let ranked : Array[Detection] = []
  for row in results {
    let mut absorbed = false
    let mut index = 0
    while index < ranked.length() && !absorbed {
      let kept = ranked[index]
      if kept.text == row.text && kept.score == row.score {
        if kept.charset.narrows(row.charset) || row.charset.narrows(kept.charset) {
          // Same text, one byte range inside the other: the wider label has no
          // evidence, so the row is dropped rather than recorded as an alias.
          absorbed = true
        } else if kept.errors == 0 && row.errors == 0 {
          // Only clean decodes are readings.  Two decoders that both failed
          // and salvaged the same prefix are not evidence that the bytes are
          // indifferent between them, and folding them together would hide
          // the fact that both wide readers rejected the stream.
          let aliases = kept.equivalent.copy()
          aliases.push(row.charset)
          ranked[index] = {
            charset: kept.charset,
            text: kept.text,
            score: kept.score,
            errors: kept.errors,
            confidence: kept.confidence,
            equivalent: aliases,
          }
          absorbed = true
        }
      }
      index = index + 1
    }
    if !absorbed {
      ranked.push(row)
    }
  }
  if ranked.length() > 1 {
    let top = ranked[0].score
    let second = ranked[1].score
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
    if ranked[0].errors == 0 && exclusive_script(ranked[0].text) && top > second {
      if confidence < 85 {
        confidence = 85
      }
    }
    // Confidence is confidence in the *label*, and a label that another code
    // page reproduces exactly is a convention, not a finding.  The text is
    // certain; the name is a coin flip, so the number has to say so.
    if ranked[0].equivalent.length() > 0 {
      confidence = 0
    }
    ranked[0] = {
      charset: ranked[0].charset,
      text: ranked[0].text,
      score: top,
      errors: ranked[0].errors,
      confidence,
      equivalent: ranked[0].equivalent,
    }
  }
  ranked
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
  let wide = wide_evidence(bytes)
  if wide.utf16_le || wide.utf16_be || wide.utf32_le || wide.utf32_be {
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
