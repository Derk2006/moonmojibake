test "json escapes quotes, backslashes and newlines" {
  assert_eq(json_escape("a\"b\\c\nd"), "a\\\"b\\\\c\\nd")
  // A tab and a NUL become the JSON control escapes.
  assert_eq(json_escape("\t"), "\\t")
  assert_eq(json_escape("\u{0001}"), "\\u0001")
  // Non-ASCII is left alone; UTF-8 is valid JSON.
  assert_eq(json_escape("中文"), "中文")
}

///|
test "detection json carries the winner and every candidate" {
  let rows = detect(b"\xd6\xd0\xce\xc4")
  let text = detection_json("zh.txt", 4, rows)
  assert_true(text.contains("\"source\":\"zh.txt\""))
  assert_true(text.contains("\"guess\":\"gbk\""))
  assert_true(text.contains("\"candidates\":["))
  // The UTF-32 candidates are ranked too, so they must appear in the list.
  assert_true(text.contains("\"charset\":\"utf-32be\""))
  // Metadata only: the decoded body stays out of a summary.
  assert_true(!text.contains("\"text\":"))
}

///|
test "detection json reports a tie honestly" {
  // あいうえお in EUC-JP: GBK reads the same bytes as the same characters.
  let rows = detect(b"\xa4\xa2\xa4\xa4\xa4\xa6\xa4\xa8\xa4\xaa")
  let text = detection_json("kana.txt", 10, rows)
  assert_true(text.contains("\"ambiguous\":true"))
  assert_true(text.contains("\"tied\":[\"gbk\",\"euc-jp\"]"))
  assert_true(text.contains("\"confidence\":0"))
}

///|
test "detection json is empty-safe" {
  let rows : Array[Detection] = []
  let text = detection_json("empty.txt", 0, rows)
  assert_eq(
    text,
    "{\"source\":\"empty.txt\",\"bytes\":0,\"guess\":null,\"ambiguous\":false,\"tied\":[],\"candidates\":[]}",
  )
}

///|
test "fix json reports the chain and the recovered text" {
  let bytes = @utf8.encode("你好")
  let broken = decode(bytes, Charset::Latin1).text()
  let result = repair(broken)
  let text = fix_json("broken.txt", result)
  assert_true(text.contains("\"repaired\":true"))
  assert_true(text.contains("\"right\":\"utf-8\""))
  assert_true(text.contains("\"text\":\"你好\""))
}

///|
test "fix json reports an untouched text as not repaired" {
  let result = repair("hello world")
  let text = fix_json("ok.txt", result)
  assert_true(text.contains("\"repaired\":false"))
  assert_true(text.contains("\"chain\":[]"))
}
