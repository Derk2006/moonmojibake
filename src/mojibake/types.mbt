///|
/// A character encoding MoonMojibake can decode, detect or repair.
pub(all) enum Charset {
  Utf8
  Utf16Le
  Utf16Be
  Utf32Le
  Utf32Be
  Gbk
  Gb18030
  Big5
  ShiftJis
  EucJp
  EucKr
  Latin1
  Cp1252
} derive(Eq, Debug)

///|
pub impl Show for Charset with output(self, logger) {
  logger.write_string(self.name())
}

///|
pub fn Charset::name(self : Charset) -> String {
  match self {
    Charset::Utf8 => "utf-8"
    Charset::Utf16Le => "utf-16le"
    Charset::Utf16Be => "utf-16be"
    Charset::Utf32Le => "utf-32le"
    Charset::Utf32Be => "utf-32be"
    Charset::Gbk => "gbk"
    Charset::Gb18030 => "gb18030"
    Charset::Big5 => "big5"
    Charset::ShiftJis => "shift_jis"
    Charset::EucJp => "euc-jp"
    Charset::EucKr => "euc-kr"
    Charset::Latin1 => "latin1"
    Charset::Cp1252 => "windows-1252"
  }
}

///|
/// Human readable family, used by the report renderer.
pub fn Charset::family(self : Charset) -> String {
  match self {
    Charset::Utf8
    | Charset::Utf16Le
    | Charset::Utf16Be
    | Charset::Utf32Le
    | Charset::Utf32Be => "Unicode"
    Charset::Gbk | Charset::Gb18030 | Charset::Big5 => "Chinese"
    Charset::ShiftJis | Charset::EucJp => "Japanese"
    Charset::EucKr => "Korean"
    Charset::Latin1 | Charset::Cp1252 => "Single-byte"
  }
}

///|
/// Whether the code page uses two-byte sequences for non-ASCII characters.
pub fn Charset::is_double_byte(self : Charset) -> Bool {
  match self {
    Charset::Gbk
    | Charset::Gb18030
    | Charset::Big5
    | Charset::ShiftJis
    | Charset::EucJp
    | Charset::EucKr => true
    _ => false
  }
}

///|
/// True when `self` accepts strictly less than `outer`: every byte sequence
/// that reads as `self` also reads as `outer`, with the same text.
///
/// Only GBK and GB18030 are related this way among the supported pages.
/// GB18030 keeps GBK's two-byte table byte for byte and adds four-byte
/// sequences plus a block of private-use two-byte slots, so a file that never
/// leaves GBK's range is not evidence of GB18030.  Detection uses this to
/// avoid calling every Chinese file "ambiguous: gbk and gb18030".
pub fn Charset::narrows(self : Charset, outer : Charset) -> Bool {
  self == Charset::Gbk && outer == Charset::Gb18030
}

///|
/// Every encoding the analyser knows about, in preference order for ties.
///
/// EUC-JP sits immediately after EUC-KR because the two share the 0xA1..0xFE
/// byte range: whichever is tried first takes any tie that the script
/// tie-breaker cannot settle, and Korean text is the one that can be read as
/// kana, never the other way round.
pub fn Charset::all() -> Array[Charset] {
  [
    Charset::Utf8,
    Charset::Gbk,
    Charset::Gb18030,
    Charset::Big5,
    Charset::ShiftJis,
    Charset::EucKr,
    Charset::EucJp,
    Charset::Cp1252,
    Charset::Latin1,
    Charset::Utf16Le,
    Charset::Utf16Be,
    Charset::Utf32Le,
    Charset::Utf32Be,
  ]
}

///|
fn ascii_lower(text : String) -> String {
  let out = StringBuilder()
  for ch in text {
    let codepoint = ch.to_int()
    if codepoint >= 0x41 && codepoint <= 0x5A {
      out.write_char((codepoint + 32).unsafe_to_char())
    } else if codepoint == 0x5F {
      out.write_char('-')
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// Parse a code page name, ignoring ASCII case and treating `_` as `-`.
///
/// Accepts the aliases people actually type: `cp936` and `gb2312` for GBK,
/// `sjis` for Shift_JIS, `iso-8859-1` for Latin-1, and so on.
///
/// `gb18030` used to be an alias for GBK here, which was wrong twice over: it
/// promised a standard GBK cannot read, and it made `convert --to gb18030`
/// fail on every character outside GBK.  The two are separate code pages; see
/// `Charset::narrows` for how detection chooses between them.
pub fn Charset::parse(name : String) -> Charset? {
  let key = ascii_lower(name)
  match key {
    "utf-8" | "utf8" => Some(Charset::Utf8)
    "utf-16le" | "utf16le" => Some(Charset::Utf16Le)
    "utf-16be" | "utf16be" => Some(Charset::Utf16Be)
    "utf-32le" | "utf32le" | "ucs-4le" | "ucs4le" => Some(Charset::Utf32Le)
    "utf-32be" | "utf32be" | "ucs-4be" | "ucs4be" => Some(Charset::Utf32Be)
    "gbk" | "cp936" | "gb2312" => Some(Charset::Gbk)
    "gb18030" | "gb-18030" | "cp54936" => Some(Charset::Gb18030)
    "big5" | "big-5" | "cp950" => Some(Charset::Big5)
    "shift-jis" | "shiftjis" | "sjis" | "cp932" => Some(Charset::ShiftJis)
    "euc-jp" | "eucjp" | "ujis" | "hp-ux-euc" => Some(Charset::EucJp)
    "euc-kr" | "euckr" | "ks-c-5601" => Some(Charset::EucKr)
    "latin1" | "latin-1" | "iso-8859-1" | "iso8859-1" => Some(Charset::Latin1)
    "windows-1252" | "cp1252" | "win1252" => Some(Charset::Cp1252)
    _ => None
  }
}

///|
/// Result of decoding a byte string with one encoding.
pub struct Decoded {
  text : String
  errors : Int
  chars : Int
}

///|
pub fn Decoded::text(self : Decoded) -> String {
  self.text
}

///|
/// Number of byte sequences that could not be decoded strictly.
pub fn Decoded::errors(self : Decoded) -> Int {
  self.errors
}

///|
pub fn Decoded::chars(self : Decoded) -> Int {
  self.chars
}

///|
/// One row of a `detect` report.
pub struct Detection {
  charset : Charset
  text : String
  score : Int
  errors : Int
  confidence : Int
}

///|
pub fn Detection::charset(self : Detection) -> Charset {
  self.charset
}

///|
pub fn Detection::text(self : Detection) -> String {
  self.text
}

///|
pub fn Detection::score(self : Detection) -> Int {
  self.score
}

///|
pub fn Detection::errors(self : Detection) -> Int {
  self.errors
}

///|
/// 0..100, how far ahead of the runner-up this candidate is.
pub fn Detection::confidence(self : Detection) -> Int {
  self.confidence
}

///|
/// True when the runner-up is not a worse guess but the *same* guess: it
/// decodes the bytes to byte-identical text and scores the same.
///
/// This is not a rare corner.  EUC-JP's kana live in rows 0xA4 and 0xA5 of
/// JIS X 0208, and GBK keeps the same rows for the same characters, so a run
/// of hiragana has one spelling that both code pages agree on.  Reporting the
/// first of the two as "the" answer would be reporting a coin flip as a
/// finding; callers that need one name can still take `rows[0]`, but a caller
/// that reports confidence should say the input is ambiguous instead.
pub fn is_ambiguous(rows : Array[Detection]) -> Bool {
  if rows.length() < 2 {
    return false
  }
  rows[0].score == rows[1].score && rows[0].text == rows[1].text
}

///|
/// True when every character is below U+0080.  Such text carries no evidence
/// about which ASCII-compatible code page produced it, because they all
/// produce the same bytes and decode them back to the same string.
pub fn is_ascii_text(text : String) -> Bool {
  for ch in text {
    if ch.to_int() >= 0x80 {
      return false
    }
  }
  true
}

///|
/// Every candidate that is indistinguishable from the winner, in rank order.
///
/// The winner is always included, so the result has at least one entry for
/// non-empty input.  An ASCII-only file returns every ASCII-compatible code
/// page, which is the literal truth: nothing in the bytes prefers one.
pub fn ambiguous_candidates(rows : Array[Detection]) -> Array[Charset] {
  let out : Array[Charset] = []
  if rows.length() == 0 {
    return out
  }
  let top = rows[0]
  for row in rows {
    if row.score == top.score && row.text == top.text {
      out.push(row.charset)
    }
  }
  out
}

///|
/// One re-encode/decode step in a repair chain.
pub struct FixStep {
  wrong : Charset
  right : Charset
}

///|
pub fn FixStep::wrong(self : FixStep) -> Charset {
  self.wrong
}

///|
pub fn FixStep::right(self : FixStep) -> Charset {
  self.right
}

///|
/// A repaired text plus the chain that produced it.
pub struct FixResult {
  text : String
  steps : Array[FixStep]
  before : Int
  after : Int
}

///|
pub fn FixResult::text(self : FixResult) -> String {
  self.text
}

///|
pub fn FixResult::steps(self : FixResult) -> Array[FixStep] {
  self.steps
}

///|
pub fn FixResult::before(self : FixResult) -> Int {
  self.before
}

///|
pub fn FixResult::after(self : FixResult) -> Int {
  self.after
}

///|
/// The result of reading bytes whose encoding nobody declared: which reading
/// was used, and what repair managed to undo from there.
pub struct AutoFix {
  charset : Charset
  result : FixResult
}

///|
pub fn AutoFix::charset(self : AutoFix) -> Charset {
  self.charset
}

///|
pub fn AutoFix::result(self : AutoFix) -> FixResult {
  self.result
}

///|
pub fn AutoFix::text(self : AutoFix) -> String {
  self.result.text
}

///|
/// `true` when writing the result back would change the file: either the bytes
/// were not UTF-8 to begin with, or a layer of mojibake was peeled off.
pub fn AutoFix::changed(self : AutoFix) -> Bool {
  self.charset != Charset::Utf8 || self.result.steps.length() > 0
}
