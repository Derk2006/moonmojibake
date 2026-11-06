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

///|
test "utf32 little endian round trip" {
  let encoded = encode("中文 abc", Charset::Utf32Le).unwrap()
  // Four bytes per code point, no prefix, no BOM.
  assert_eq(encoded.length(), 24)
  let decoded = decode(encoded, Charset::Utf32Le)
  assert_eq(decoded.text(), "中文 abc")
  assert_eq(decoded.errors(), 0)
}

///|
test "utf32 big endian round trip" {
  let encoded = encode("日本語", Charset::Utf32Be).unwrap()
  let decoded = decode(encoded, Charset::Utf32Be)
  assert_eq(decoded.text(), "日本語")
  assert_eq(decoded.errors(), 0)
}

///|
test "utf32 bom wins over the utf16 reading" {
  // The LE UTF-32 mark starts with the complete UTF-16LE mark, so this is a
  // regression test for the order of the BOM tests.
  let body = encode("中文", Charset::Utf32Le).unwrap()
  let buffer = Buffer()
  buffer.write_byte(b'\xff')
  buffer.write_byte(b'\xfe')
  buffer.write_byte(b'\x00')
  buffer.write_byte(b'\x00')
  for b in body {
    buffer.write_byte(b)
  }
  let rows = detect(buffer.to_bytes())
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].charset(), Charset::Utf32Le)
  assert_eq(rows[0].text(), "中文")
  assert_eq(rows[0].confidence(), 100)
}

///|
test "utf32 big endian bom is detected" {
  let body = encode("中文", Charset::Utf32Be).unwrap()
  let buffer = Buffer()
  buffer.write_byte(b'\x00')
  buffer.write_byte(b'\x00')
  buffer.write_byte(b'\xfe')
  buffer.write_byte(b'\xff')
  for b in body {
    buffer.write_byte(b)
  }
  let rows = detect(buffer.to_bytes())
  assert_eq(rows[0].charset(), Charset::Utf32Be)
  assert_eq(rows[0].text(), "中文")
}

///|
test "utf32 counts a trailing partial unit as an error" {
  let decoded = decode(b"\x2d\x4e\x00", Charset::Utf32Le)
  assert_true(decoded.errors() > 0)
}

///|
test "utf32 rejects code points outside unicode" {
  // 0x00110000 is one past the last code point.
  let decoded = decode(b"\x00\x11\x00\x00", Charset::Utf32Be)
  assert_eq(decoded.errors(), 1)
  assert_eq(decoded.text(), "\u{FFFD}")
}

///|
test "utf32 rejects a surrogate code point" {
  // U+D800, which UTF-32 must never carry.
  let decoded = decode(b"\x00\x00\xd8\x00", Charset::Utf32Be)
  assert_eq(decoded.errors(), 1)
}

///|
test "detect picks utf32 for chinese without a bom" {
  let encoded = encode("中文测试内容比较长一些", Charset::Utf32Le).unwrap()
  let rows = detect(encoded)
  assert_eq(rows[0].charset(), Charset::Utf32Le)
}

///|
test "repair does not flip a fixed text into another script" {
  // The mojibake of 你好 was already restored to Chinese, but the second
  // round used to "improve" it into Hangul: the Hangul reading scores high
  // because the frequency model does not penalise nonsense syllables.
  let bytes = @utf8.encode("你好")
  let broken = decode(bytes, Charset::Latin1).text()
  let result = repair(broken)
  assert_eq(result.text(), "你好")
  assert_eq(result.steps().length(), 1)
  assert_eq(result.steps()[0].right(), Charset::Utf8)
}


///|
test "looks_binary flags a png header" {
  assert_true(looks_binary(b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"))
}

///|
test "looks_binary accepts text without nul bytes" {
  assert_true(!looks_binary(b"\xd6\xd0\xce\xc4"))
  assert_true(!looks_binary(b"plain ascii"))
  assert_true(!looks_binary(b""))
}

///|
test "looks_binary accepts utf16 and utf32 text that carries nul bytes" {
  let wide = encode("中文", Charset::Utf32Le).unwrap()
  assert_true(!looks_binary(wide))
  // UTF-16 of Latin text is half zero bytes by construction.
  let latin = encode("hello", Charset::Utf16Le).unwrap()
  assert_true(!looks_binary(latin))
}
