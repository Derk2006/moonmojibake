///|
test "gbk decode ascii passthrough" {
  let decoded = decode(b"hello", Charset::Gbk)
  assert_eq(decoded.text(), "hello")
  assert_eq(decoded.errors(), 0)
}

///|
test "gbk decodes zhongwen" {
  // 中文 in GBK
  let decoded = decode(b"\xd6\xd0\xce\xc4", Charset::Gbk)
  assert_eq(decoded.text(), "中文")
  assert_eq(decoded.errors(), 0)
  assert_eq(decoded.chars(), 2)
}

///|
test "big5 decodes zhongwen" {
  // 中文 in Big5
  let decoded = decode(b"\xa4\xa4\xa4\xe5", Charset::Big5)
  assert_eq(decoded.text(), "中文")
  assert_eq(decoded.errors(), 0)
}

///|
test "shift_jis decodes nihongo" {
  // 日本語 in Shift_JIS
  let decoded = decode(b"\x93\xfa\x96\x7b\x8c\xea", Charset::ShiftJis)
  assert_eq(decoded.text(), "日本語")
  assert_eq(decoded.errors(), 0)
}

///|
test "shift_jis half width katakana" {
  let decoded = decode(b"\xb1", Charset::ShiftJis)
  assert_eq(decoded.text(), "ｱ")
  assert_eq(decoded.errors(), 0)
}

///|
test "euc kr decodes hangul" {
  // 한국어 in EUC-KR
  let decoded = decode(b"\xc7\xd1\xb1\xb9\xbe\xee", Charset::EucKr)
  assert_eq(decoded.text(), "한국어")
  assert_eq(decoded.errors(), 0)
}

///|
test "latin1 maps every byte" {
  let decoded = decode(b"\xe9\xff", Charset::Latin1)
  assert_eq(decoded.text(), "éÿ")
  assert_eq(decoded.errors(), 0)
}

///|
test "cp1252 quotes differ from latin1" {
  let decoded = decode(b"\x93\x94", Charset::Cp1252)
  assert_eq(decoded.text(), "“”")
  assert_eq(decoded.errors(), 0)
  let latin = decode(b"\x93\x94", Charset::Latin1)
  assert_eq(latin.text(), "\u{93}\u{94}")
}

///|
test "cp1252 undefined byte is an error" {
  let decoded = decode(b"\x81", Charset::Cp1252)
  assert_eq(decoded.errors(), 1)
}

///|
test "gbk stray lead byte is an error" {
  let decoded = decode(b"\xd6", Charset::Gbk)
  assert_eq(decoded.errors(), 1)
  assert_eq(decoded.text(), "�")
}

///|
test "gbk unmapped trail byte resyncs" {
  // 0xd6 0x20: lead byte followed by a space, which is not a valid trail.
  let decoded = decode(b"\xd6 x", Charset::Gbk)
  assert_eq(decoded.errors(), 1)
  assert_eq(decoded.text(), "� x")
}

///|
test "utf8 decodes and reports clean" {
  let decoded = decode(b"\xe4\xb8\xad\xe6\x96\x87", Charset::Utf8)
  assert_eq(decoded.text(), "中文")
  assert_eq(decoded.errors(), 0)
  assert_eq(decoded.chars(), 2)
}

///|
test "utf8 reports malformed sequences" {
  let decoded = decode(b"\xff\xfe", Charset::Utf8)
  assert_eq(decoded.errors(), 2)
}

///|
test "utf16 little endian round trip" {
  let encoded = @utf16.encode("中文", endianness=@utf16.Endian::Little)
  let decoded = decode(encoded, Charset::Utf16Le)
  assert_eq(decoded.text(), "中文")
  assert_eq(decoded.errors(), 0)
}

///|
test "utf16 big endian round trip" {
  let encoded = @utf16.encode("中文", endianness=@utf16.Endian::Big)
  let decoded = decode(encoded, Charset::Utf16Be)
  assert_eq(decoded.text(), "中文")
}

///|
test "bom is stripped and detected" {
  let detection = detect(b"\xef\xbb\xbfhello")
  assert_eq(detection.length(), 1)
  assert_eq(detection[0].charset(), Charset::Utf8)
  assert_eq(detection[0].confidence(), 100)
  assert_eq(detection[0].text(), "hello")
}

///|
test "detect picks gbk for chinese" {
  let rows = detect(b"\xd6\xd0\xce\xc4\xba\xba\xc3")
  assert_eq(rows[0].charset(), Charset::Gbk)
}

///|
test "detect picks big5 for traditional chinese" {
  // 繁體中文 in Big5
  let rows = detect(b"\xc1c\xc5\xe9\xa4\xa4\xa4\xe5")
  assert_eq(rows[0].charset(), Charset::Big5)
}

///|
test "detect picks shift_jis for japanese" {
  let rows = detect(b"\x93\xfa\x96\x7b\x8c\xea\x82\xcc\x83e\x83L\x83X\x83g")
  assert_eq(rows[0].charset(), Charset::ShiftJis)
}

///|
test "detect picks euc kr for korean" {
  // 한국어를 배우는 것은 정말 재미있습니다
  let rows = detect(
    b"\xc7\xd1\xb1\xb9\xbe\xee\xb8\xa6\x20\xb9\xe8\xbf\xec\xb4\xc2\x20\xb0\xcd\xc0\xba\x20\xc1\xa4\xb8\xbb\x20\xc0\xe7\xb9\xcc\xc0\xd6\xbd\xc0\xb4\xcf\xb4\xd9",
  )
  assert_eq(rows[0].charset(), Charset::EucKr)
}

///|
test "detect reports no confidence for ascii" {
  let rows = detect(b"hello world")
  assert_eq(rows[0].charset(), Charset::Utf8)
  assert_eq(rows[0].confidence(), 0)
}

///|
test "detect of empty input is empty" {
  let rows = detect(b"")
  assert_eq(rows.length(), 0)
}

///|
test "repair undoes utf8 read as cp1252" {
  let utf8 = @utf8.encode("中文测试")
  let broken = decode_text(utf8, Charset::Cp1252)
  assert_true(broken != "中文测试")
  let fixed = repair(broken)
  assert_eq(fixed.text(), "中文测试")
  assert_eq(fixed.steps().length(), 1)
  assert_eq(fixed.steps()[0].wrong(), Charset::Cp1252)
  assert_eq(fixed.steps()[0].right(), Charset::Utf8)
}

///|
test "repair undoes utf8 read as latin1" {
  let utf8 = @utf8.encode("你好，世界")
  let broken = decode_text(utf8, Charset::Latin1)
  let fixed = repair(broken)
  assert_eq(fixed.text(), "你好，世界")
}

///|
test "repair undoes gbk read as latin1" {
  let gbk = encode("中文测试", Charset::Gbk).unwrap()
  let broken = decode_text(gbk, Charset::Latin1)
  let fixed = repair(broken)
  assert_eq(fixed.text(), "中文测试")
}

///|
test "repair leaves clean text alone" {
  let fixed = repair("这是一段正常的中文文本，不需要修复。")
  assert_eq(fixed.steps().length(), 0)
  assert_eq(fixed.text(), "这是一段正常的中文文本，不需要修复。")
}

///|
test "encode round trips every double byte code page" {
  let samples : Array[(Charset, String)] = [
    (Charset::Gbk, "中文测试"),
    (Charset::Big5, "繁體中文"),
    (Charset::ShiftJis, "日本語のテスト"),
    (Charset::EucKr, "한국어"),
  ]
  for sample in samples {
    let (charset, text) = sample
    let encoded = encode(text, charset).unwrap()
    assert_eq(decode_text(encoded, charset), text)
  }
}

///|
test "encode refuses characters outside the code page" {
  assert_true(encode("中文", Charset::Latin1) is None)
  assert_true(encode("😀", Charset::Gbk) is None)
}

///|
test "score prefers clean text over replacement characters" {
  let clean = text_score("这是一段正常的中文", 0)
  let broken = text_score("������", 6)
  assert_true(clean > broken)
}

///|
test "charset names and parsing round trip" {
  for charset in Charset::all() {
    assert_eq(Charset::parse(charset.name()).unwrap(), charset)
  }
  assert_eq(Charset::parse("CP936").unwrap(), Charset::Gbk)
  assert_eq(Charset::parse("Shift_JIS").unwrap(), Charset::ShiftJis)
  assert_true(Charset::parse("no-such-thing") is None)
}

///|
test "report renders a table with the winner first" {
  let rows = detect(b"\xd6\xd0\xce\xc4")
  let report = render_detection("sample.txt", 4, rows)
  assert_true(report.contains("gbk"))
  assert_true(report.contains("guess:"))
}
