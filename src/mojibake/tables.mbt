///|
/// Access to the generated code-page tables.
///
/// The data lives in `tables_gen.mbt` (regenerate with
/// `python scripts/gen_tables.py`).  Every table is indexed by
///
///     (lead - 0x81) * 191 + (trail - 0x40)
///
/// covering lead bytes 0x81..0xFE and trail bytes 0x40..0xFE.  A slot holds
/// 0 when the byte pair is unmapped, which is safe because U+0000 is never a
/// two-byte code-page character.

///|
/// Table for a double-byte code page, or an empty array for everything else.
fn double_byte_table(charset : Charset) -> Array[Int] {
  match charset {
    Charset::Gbk => gbk_table
    Charset::Big5 => big5_table
    Charset::ShiftJis => sjis_table
    Charset::EucKr => euckr_table
    Charset::EucJp => eucjp_table
    _ => {
      let empty : Array[Int] = []
      empty
    }
  }
}

///|
/// Codepoint for one two-byte sequence, or 0 when the pair is not mapped.
fn table_lookup(charset : Charset, lead : Int, trail : Int) -> Int {
  if lead < TABLE_LEAD_MIN || lead > 0xFE {
    return 0
  }
  if trail < TABLE_TRAIL_MIN || trail > 0xFE {
    return 0
  }
  let table = double_byte_table(charset)
  if table.length() == 0 {
    return 0
  }
  table[(lead - TABLE_LEAD_MIN) * TABLE_SPAN + (trail - TABLE_TRAIL_MIN)]
}

///|
/// Build a codepoint -> byte-pair index from an expanded table.
///
/// The result is a flat array of 0x10000 slots; 0 means "not encodable" and
/// anything else packs the pair as `(lead << 8) | trail`.  The first mapping
/// wins, which matches the decoder for the duplicate entries that exist in
/// Big5 and Shift_JIS.
fn build_reverse(table : Array[Int]) -> Array[Int] {
  let reverse : Array[Int] = Array::make(0x10000, 0)
  let mut index = 0
  let slots = table.length()
  while index < slots {
    let codepoint = table[index]
    if codepoint > 0 && codepoint < 0x10000 && reverse[codepoint] == 0 {
      let lead = index / TABLE_SPAN + TABLE_LEAD_MIN
      let trail = index % TABLE_SPAN + TABLE_TRAIL_MIN
      reverse[codepoint] = (lead << 8) | trail
    }
    index = index + 1
  }
  reverse
}

///|
/// Membership test set for the frequency table, one slot per BMP codepoint.
fn build_common_set() -> Array[Bool] {
  let set : Array[Bool] = Array::make(0x10000, false)
  for ch in common_chars {
    let codepoint = ch.to_int()
    if codepoint >= 0 && codepoint < 0x10000 {
      set[codepoint] = true
    }
  }
  set
}

///|
/// Characters that appear in ordinary Chinese prose, used as a language
/// plausibility signal by the scorer.
let common_set : Array[Bool] = build_common_set()

///|
/// Membership set for JIS X 0208 level 1, the 2965 kanji Japanese newspapers
/// are expected to stick to.  The scorer uses it the other way round from
/// `common_set`: it is evidence that a text full of kana is really Japanese,
/// and that its kanji are not a Chinese reading of the same bytes.
fn build_jis_level1_set() -> Array[Bool] {
  let set : Array[Bool] = Array::make(0x10000, false)
  for ch in jis_level1_chars {
    let codepoint = ch.to_int()
    if codepoint >= 0 && codepoint < 0x10000 {
      set[codepoint] = true
    }
  }
  set
}

///|
let jis_level1_set : Array[Bool] = build_jis_level1_set()

///|
let gbk_reverse : Array[Int] = build_reverse(gbk_table)

///|
let big5_reverse : Array[Int] = build_reverse(big5_table)

///|
let sjis_reverse : Array[Int] = build_reverse(sjis_table)

///|
let euckr_reverse : Array[Int] = build_reverse(euckr_table)

///|
let eucjp_reverse : Array[Int] = build_reverse(eucjp_table)

///|
/// Reverse index for a double-byte code page, or an empty array.
fn double_byte_reverse(charset : Charset) -> Array[Int] {
  match charset {
    Charset::Gbk => gbk_reverse
    Charset::Big5 => big5_reverse
    Charset::ShiftJis => sjis_reverse
    Charset::EucKr => euckr_reverse
    Charset::EucJp => eucjp_reverse
    _ => {
      let empty : Array[Int] = []
      empty
    }
  }
}

///|
/// JIS X 0212 is the part of EUC-JP that needs three bytes: 0x8F followed by
/// two cells of the 94x94 grid.  It cannot share the two-byte table, so it
/// gets its own lookup keyed by the cell coordinates.
fn jis0212_lookup(second : Int, third : Int) -> Int {
  if second < 0xA1 || second > 0xFE || third < 0xA1 || third > 0xFE {
    return 0
  }
  eucjp_0212_table[(second - 0xA1) * JIS_CELLS + (third - 0xA1)]
}

///|
/// Reverse index for the 0x8F half of EUC-JP.  A hit packs `(second << 8) |
/// third`, the same shape the two-byte reverse index uses.
let eucjp_0212_reverse : Array[Int] = {
  let reverse : Array[Int] = Array::make(0x10000, 0)
  let mut index = 0
  while index < eucjp_0212_table.length() {
    let codepoint = eucjp_0212_table[index]
    if codepoint > 0 && reverse[codepoint] == 0 {
      let second = index / JIS_CELLS + 0xA1
      let third = index % JIS_CELLS + 0xA1
      reverse[codepoint] = (second << 8) | third
    }
    index = index + 1
  }
  reverse
}
