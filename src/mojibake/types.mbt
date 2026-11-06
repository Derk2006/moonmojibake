///|
/// A character encoding MoonMojibake can decode, detect or repair.
pub(all) enum Charset {
  Utf8
  Utf16Le
  Utf16Be
  Utf32Le
  Utf32Be
  Gbk
  Big5
  ShiftJis
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
    Charset::Big5 => "big5"
    Charset::ShiftJis => "shift_jis"
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
    Charset::Gbk | Charset::Big5 => "Chinese"
    Charset::ShiftJis | Charset::EucKr => "CJK"
    Charset::Latin1 | Charset::Cp1252 => "Single-byte"
  }
}

///|
/// Whether the code page uses two-byte sequences for non-ASCII characters.
pub fn Charset::is_double_byte(self : Charset) -> Bool {
  match self {
    Charset::Gbk | Charset::Big5 | Charset::ShiftJis | Charset::EucKr => true
    _ => false
  }
}

///|
/// Every encoding the analyser knows about, in preference order for ties.
pub fn Charset::all() -> Array[Charset] {
  [
    Charset::Utf8,
    Charset::Gbk,
    Charset::Big5,
    Charset::ShiftJis,
    Charset::EucKr,
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
pub fn Charset::parse(name : String) -> Charset? {
  let key = ascii_lower(name)
  match key {
    "utf-8" | "utf8" => Some(Charset::Utf8)
    "utf-16le" | "utf16le" => Some(Charset::Utf16Le)
    "utf-16be" | "utf16be" => Some(Charset::Utf16Be)
    "utf-32le" | "utf32le" | "ucs-4le" | "ucs4le" => Some(Charset::Utf32Le)
    "utf-32be" | "utf32be" | "ucs-4be" | "ucs4be" => Some(Charset::Utf32Be)
    "gbk" | "cp936" | "gb2312" | "gb18030" => Some(Charset::Gbk)
    "big5" | "big-5" | "cp950" => Some(Charset::Big5)
    "shift-jis" | "shiftjis" | "sjis" | "cp932" => Some(Charset::ShiftJis)
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
