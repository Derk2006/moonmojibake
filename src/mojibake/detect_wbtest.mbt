// Whitebox checks for the merged wide-encoding scan.
//
// `wide_evidence` replaced four full passes over the input with one.  The
// thing that can go wrong is not speed but arithmetic: a tail of 2 or 3 bytes
// handled differently from the per-encoding scans would change a score, and a
// changed score is a changed detection.  So the single-purpose versions are
// kept here, as the reference the merged one is checked against.

///|
/// The UTF-16 evidence test, one encoding at a time.
fn reference_utf16_evidence(bytes : Bytes, little_endian : Bool) -> Bool {
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
/// The UTF-32 evidence test, one encoding at a time.
fn reference_utf32_evidence(bytes : Bytes, little_endian : Bool) -> Bool {
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
/// `detect` skips the GB18030 decode when the GBK decode had no errors, on the
/// grounds that the two tables agree wherever GBK maps anything.  That is a
/// property of the generated tables, not of the code, so it is checked here:
/// a regeneration that broke it would otherwise make the detector label a
/// GB18030 file as GBK with the wrong text.
test "gb18030 keeps every mapping gbk defines" {
  assert_eq(gbk_table.length(), gb18030_table.length())
  let mut index = 0
  let mut shared = 0
  while index < gbk_table.length() {
    let codepoint = gbk_table[index]
    if codepoint != 0 {
      assert_eq(gb18030_table[index], codepoint)
      shared = shared + 1
    }
    index = index + 1
  }
  assert_eq(shared, 21791)
}

///|
/// The other half of the proof: GB18030 only *adds* slots, and exactly the
/// 2149 private-use ones the decoder already treats as near-misses.
test "gb18030 adds only slots gbk leaves empty" {
  let mut index = 0
  let mut added = 0
  while index < gbk_table.length() {
    if gbk_table[index] == 0 && gb18030_table[index] != 0 {
      added = added + 1
    }
    index = index + 1
  }
  assert_eq(added, 2149)
}

///|
test "wide evidence matches the four single-purpose scans" {
  let mut seed = 20261118
  for length in 0..<25 {
    for _ in 0..<40 {
      let buffer = Buffer()
      for _ in 0..<length {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        buffer.write_byte((seed / 65536 % 256).to_byte())
      }
      let bytes = buffer.to_bytes()
      let wide = wide_evidence(bytes)
      assert_eq(wide.utf16_le, reference_utf16_evidence(bytes, true))
      assert_eq(wide.utf16_be, reference_utf16_evidence(bytes, false))
      assert_eq(wide.utf32_le, reference_utf32_evidence(bytes, true))
      assert_eq(wide.utf32_be, reference_utf32_evidence(bytes, false))
    }
  }
}

///|
test "wide evidence recognises real UTF-16 and UTF-32 padding" {
  // "abcd" as UTF-16LE: every code unit has a zero high byte.
  let utf16_le = b"\x61\x00\x62\x00\x63\x00\x64\x00"
  let wide = wide_evidence(utf16_le)
  assert_true(wide.utf16_le)
  // The same bytes read big-endian put the zero in the low byte, which is not
  // the pattern the test looks for.
  assert_false(wide.utf16_be)
  // "ab" as UTF-32LE.
  let utf32_le = b"\x61\x00\x00\x00\x62\x00\x00\x00"
  let wide32 = wide_evidence(utf32_le)
  assert_true(wide32.utf32_le)
  assert_false(wide32.utf32_be)
}

///|
test "wide evidence rejects short and odd-length input" {
  // Under four bytes there is not enough to show a pattern.
  assert_false(wide_evidence(b"\x61\x00").utf16_le)
  assert_false(wide_evidence(b"\x61\x00\x00\x00").utf32_le)
  // An odd length cannot be UTF-16, even when the first units look right.
  assert_false(wide_evidence(b"\x61\x00\x62\x00\x63").utf16_le)
  // A length that is not a multiple of four cannot be UTF-32.
  assert_false(wide_evidence(b"\x61\x00\x00\x00\x62\x00").utf32_le)
}
