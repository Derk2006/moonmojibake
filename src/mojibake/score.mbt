///|
/// Text plausibility scoring.
///
/// Detection compares several decodings of the same bytes, so all that
/// matters is that a *correct* decoding outranks a *wrong* one.  Five
/// independent signals, each failing differently:
///
///   * 30 points — the decode was clean (no replacement characters, and no
///     private-use characters, which are a slot with no assigned meaning)
///   * 15 points — one script accounts for most of the text
///   * 35 points — the CJK characters are ones that ordinary prose uses
///   * 10 points — the text is printable
///   * 10 points — the text uses a script only one language can produce
///
/// The frequency signal is the important one.  A wrong code page usually
/// keeps the first two — Big5 and GBK happily consume the same byte pairs,
/// and the junk still lands in CJK blocks — but it cannot fake producing
/// characters people actually write.  The level-1 sets in `tables_gen.mbt`
/// exist to recognise exactly that.
///
/// The last signal breaks the remaining tie: EUC-KR byte ranges sit inside
/// GBK, so Korean text always decodes cleanly as Chinese too, and only the
/// presence of Hangul says which reading is the real one.

///|
/// Characters no honest text contains: controls, private use, surrogates and
/// the replacement character itself.
fn is_noise_char(codepoint : Int) -> Bool {
  if codepoint == 0 || codepoint == 0xFFFD || codepoint == 0xFFFE {
    return true
  }
  if codepoint == 0xFFFF {
    return true
  }
  if codepoint >= 0xD800 && codepoint <= 0xDFFF {
    return true
  }
  if codepoint >= 0xE000 && codepoint <= 0xF8FF {
    return true
  }
  if codepoint < 0x20 {
    if codepoint == 0x09 || codepoint == 0x0A || codepoint == 0x0D {
      return false
    }
    return true
  }
  if codepoint == 0x7F {
    return true
  }
  false
}

///|
/// Script-neutral characters: ASCII, CJK punctuation and fullwidth forms.
/// They belong to whatever script dominates, so they should not drag the
/// consistency signal down.
fn is_neutral_char(codepoint : Int) -> Bool {
  if codepoint >= 0x20 && codepoint <= 0x7E {
    return true
  }
  if codepoint == 0x09 || codepoint == 0x0A || codepoint == 0x0D {
    return true
  }
  if codepoint >= 0x2000 && codepoint <= 0x206F {
    return true
  }
  if codepoint >= 0x3000 && codepoint <= 0x303F {
    return true
  }
  if codepoint >= 0xFF00 && codepoint <= 0xFFEF {
    // Half-width katakana is excluded: it is exactly what a Chinese code page
    // turns into when it is read as Shift_JIS, so counting it as neutral
    // would let that accident look like ordinary punctuation.
    if codepoint >= 0xFF61 && codepoint <= 0xFF9F {
      return false
    }
    return true
  }
  false
}

///|
/// True when the text is written in a script only one supported language uses:
/// Hangul belongs to Korean, full-width kana to Japanese.  Chinese uses
/// neither, so a text that is mostly Hangul cannot be Chinese.  The inference
/// only holds in this one direction, which is what makes it a usable
/// tie-breaker between a code page and its byte-range-compatible neighbour.
fn exclusive_script(text : String) -> Bool {
  let mut ideographs = 0
  let mut hangul = 0
  let mut kana = 0
  for ch in text {
    let codepoint = ch.to_int()
    if codepoint >= 0x4E00 && codepoint <= 0x9FFF {
      ideographs = ideographs + 1
    } else if codepoint >= 0xAC00 && codepoint <= 0xD7AF {
      hangul = hangul + 1
    } else if codepoint >= 0x3040 && codepoint <= 0x30FF {
      kana = kana + 1
    }
  }
  // Spaces and punctuation carry no script, so the share is measured against
  // the characters that do.
  let scripted = ideographs + hangul + kana
  if scripted == 0 {
    return false
  }
  if hangul * 10 >= scripted * 9 {
    return true
  }
  kana * 100 >= scripted * 40
}

///|
/// Score `text` in 0..100.  `errors` is the decoder's malformed-sequence
/// count for the same bytes.
pub fn text_score(text : String, errors : Int) -> Int {
  let mut chars = 0
  let mut ideographs = 0
  let mut common = 0
  let mut kana = 0
  let mut hangul = 0
  let mut neutral = 0
  let mut noise = 0
  let mut rare_kanji = 0
  let mut private_use = 0
  for ch in text {
    chars = chars + 1
    let codepoint = ch.to_int()
    if codepoint >= 0x4E00 && codepoint <= 0x9FFF {
      ideographs = ideographs + 1
      if common_set[codepoint] {
        common = common + 1
      }
      if !jis_level1_set[codepoint] {
        rare_kanji = rare_kanji + 1
      }
    } else if codepoint >= 0x3040 && codepoint <= 0x30FF {
      kana = kana + 1
    } else if codepoint >= 0xAC00 && codepoint <= 0xD7AF {
      hangul = hangul + 1
    } else if is_neutral_char(codepoint) {
      neutral = neutral + 1
    }
    if codepoint >= 0xE000 && codepoint <= 0xF8FF {
      private_use = private_use + 1
    }
    if is_noise_char(codepoint) {
      noise = noise + 1
    }
  }
  if chars == 0 {
    if errors > 0 {
      return 0
    }
    return 50
  }
  // A private-use mapping is a near miss, not a character: the code page has a
  // slot there, but no standard assigns it a meaning, and a font cannot show
  // one the reader is expected to know.  Counting it as an error is what keeps
  // a page with a large private-use block from buying a clean decode.  GB18030
  // has 2149 such two-byte slots, and without this they were enough to make a
  // windows-1252 sentence look "cleaner" than the correct reading.
  let mut effective_errors = errors + private_use
  if effective_errors > chars {
    effective_errors = chars
  }
  let clamped_errors = effective_errors
  let clean_part = if clamped_errors == 0 {
    30
  } else {
    // A code page that cannot consume the whole stream is the wrong code
    // page.  One bad sequence has to cost more than its share of the text,
    // otherwise a stream that GBK almost-parses can outrank the Latin-1
    // reading that actually fits it.
    let mut part = 30 - 30 * clamped_errors / chars - 8
    if part < 0 {
      part = 0
    }
    part
  }
  let dominant = if ideographs >= kana && ideographs >= hangul {
    ideographs
  } else if kana >= hangul {
    kana
  } else {
    hangul
  }
  let mut coherent = dominant + neutral
  if coherent > chars {
    coherent = chars
  }
  let script_part = 15 * coherent / chars
  let scripted = ideographs + kana + hangul
  let raw_frequency = if ideographs > 0 && ideographs * 2 >= scripted {
    35 * common / ideographs
  } else if hangul > 0 || kana > 0 {
    35
  } else if ideographs > 0 {
    35 * common / ideographs
  } else {
    8
  }
  // Frequency evidence only counts for the part of the text it explains.
  // Without this, two stray kanji in an otherwise Latin sentence — exactly
  // what a Western text looks like when it is read as Shift_JIS — would earn
  // the same 35 points as a whole page of Chinese.
  let frequency_part = raw_frequency * scripted / chars
  let printable_part = 10 * (chars - noise) / chars
  let exclusive_part = if clamped_errors == 0 && exclusive_script(text) {
    10
  } else {
    0
  }
  let mut score = clean_part +
    script_part +
    frequency_part +
    printable_part +
    exclusive_part
  // Modern Korean is written in Hangul; a text that mixes Hangul with
  // ideographs or kana in quantity is a decoding accident, not a language.
  if hangul > 0 && (ideographs + kana) * 3 > scripted {
    score = score - 12
  }
  // Kana text carrying kanji that are not Japanese level-1 kanji is probably
  // not Japanese — it is Japanese bytes read as a Chinese code page.  The byte
  // ranges nest (EUC-JP's 0xA1..0xFE sits inside GBK's 0x81..0xFE with trail
  // 0x40..0xFE), and GBK keeps the 0xA4/0xA5 kana block, so both readings stay
  // clean and keep their kana; the kanji are the only place the difference
  // shows.  The whole JIS repertoire is too generous to test against — it
  // holds most Chinese hanzi as well — but level 1 is a frequency set, and a
  // Chinese reading of Japanese bytes fails it almost every time.
  if kana > 0 && rare_kanji > 0 {
    let mut penalty = 30 * rare_kanji / ideographs
    if penalty > 30 {
      penalty = 30
    }
    score = score - penalty
  }
  if score < 0 {
    return 0
  }
  if score > 100 {
    return 100
  }
  score
}

///|
/// Score a decoded result, taking its own error count into account.
pub fn score_decoded(decoded : Decoded) -> Int {
  text_score(decoded.text, decoded.errors)
}
