// Benchmarks for the public entry points.
//
// Run with `moon bench bench --release` (or `moon bench bench`). These exist so
// the throughput numbers in docs/BENCHMARK.md are reproducible by anyone with a
// checkout, and so a regression in the hot paths shows up as a number rather
// than as a feeling.
//
// The fixtures are built once, outside the timed closure: `encode` is not part
// of what is being measured. Each test name is the benchmark name.

///|
fn repeat(text : String, times : Int) -> String {
  let mut out = ""
  for _ in 0..<times {
    out += text
  }
  out
}

///|
let sample_zh : String = "中文期刊编码检测与乱码修复是一个真实存在的问题，" +
  "网页抓取、日志归档、老系统迁移都会遇到。\n"

///|
let gbk_1k : Bytes = match @mojibake.encode(
  repeat(sample_zh, 12),
  @mojibake.Charset::Gbk,
) {
  Some(bytes) => bytes
  None => abort("bench: gbk fixture failed to encode")
}

///|
let gbk_32k : Bytes = match @mojibake.encode(
  repeat(sample_zh, 380),
  @mojibake.Charset::Gbk,
) {
  Some(bytes) => bytes
  None => abort("bench: gbk fixture failed to encode")
}

///|
let utf8_1k : Bytes = match @mojibake.encode(
  repeat(sample_zh, 12),
  @mojibake.Charset::Utf8,
) {
  Some(bytes) => bytes
  None => abort("bench: utf8 fixture failed to encode")
}

///|
let mojibake_1k : String = repeat("ä¸­æ–‡æµ‹è¯• ç¼–ç   ", 120)

///|
let mixed_zh : String = repeat("中文测试 😀 龦 编码 ", 40)

///|
test "bench: decode gbk 1KiB" (it : @bench.T) {
  it.bench(fn() { it.keep(@mojibake.decode_text(gbk_1k, @mojibake.Charset::Gbk)) })
}

///|
test "bench: detect 1KiB gbk" (it : @bench.T) {
  it.bench(fn() { it.keep(@mojibake.detect(gbk_1k)) })
}

///|
test "bench: detect 32KiB gbk" (it : @bench.T) {
  it.bench(fn() { it.keep(@mojibake.detect(gbk_32k)) })
}

///|
test "bench: detect 1KiB utf8" (it : @bench.T) {
  it.bench(fn() { it.keep(@mojibake.detect(utf8_1k)) })
}

///|
test "bench: repair 1KiB" (it : @bench.T) {
  it.bench(fn() { it.keep(@mojibake.repair(mojibake_1k)) })
}

///|
test "bench: encode gb18030" (it : @bench.T) {
  it.bench(fn() { it.keep(@mojibake.encode(mixed_zh, @mojibake.Charset::Gb18030)) })
}
