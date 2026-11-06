///|
/// How many files a given encoding accounted for.
struct Tally {
  name : String
  mut count : Int
}

///|
/// One file visited by `scan`.
struct ScanEntry {
  path : String
  charset : String
  confidence : Int
  binary : Bool
}

///|
fn ends_with_slash(name : String) -> Bool {
  let mut last = ' '
  for ch in name {
    last = ch
  }
  last == '/'
}

///|
fn drop_last_char(text : String) -> String {
  let out = StringBuilder()
  let mut index = 0
  let length = text.length()
  for ch in text {
    if index + 1 < length {
      out.write_char(ch)
    }
    index = index + 1
  }
  out.to_string()
}

///|
fn trim_trailing_separator(dir : String) -> String {
  let chars : Array[Char] = []
  for ch in dir {
    chars.push(ch)
  }
  let mut end = chars.length()
  while end > 1 && chars[end - 1] == '/' {
    end = end - 1
  }
  let kept : Array[Char] = []
  let mut index = 0
  while index < end {
    kept.push(chars[index])
    index = index + 1
  }
  String::from_array(kept)
}

///|
fn collect_files(dir : String, recursive : Bool, out : Array[String]) -> Unit {
  for name in list_dir(dir) {
    if ends_with_slash(name) {
      // Sub-directories arrive with a trailing slash, so a file named "x/" is
      // impossible and the distinction never has to stat the entry again.
      if recursive {
        collect_files(dir + "/" + drop_last_char(name), recursive, out)
      }
    } else {
      out.push(dir + "/" + name)
    }
  }
}

///|
fn bump_count(counts : Array[Tally], key : String) -> Unit {
  let mut index = 0
  while index < counts.length() {
    if counts[index].name == key {
      counts[index].count = counts[index].count + 1
      return
    }
    index = index + 1
  }
  counts.push({ name: key, count: 1 })
}

///|
fn pad_right(text : String, width : Int) -> String {
  let out = StringBuilder()
  out.write_string(text)
  let mut now = 0
  for _ch in text {
    now = now + 1
  }
  while now < width {
    out.write_char(' ')
    now = now + 1
  }
  out.to_string()
}

///|
fn pad_left(text : String, width : Int) -> String {
  let out = StringBuilder()
  let mut now = 0
  for _ch in text {
    now = now + 1
  }
  while now < width {
    out.write_char(' ')
    now = now + 1
  }
  out.write_string(text)
  out.to_string()
}

///|
fn render_scan(dir : String, entries : Array[ScanEntry], counts : Array[Tally]) -> String {
  let out = StringBuilder()
  out.write_string("scan ")
  out.write_string(dir)
  out.write_string(" (")
  out.write_string(entries.length().to_string())
  out.write_string(" files)\n\n  encoding")
  out.write_string(pad_left("files", 8))
  out.write_string("\n")
  let mut index = 0
  while index < counts.length() {
    let tally = counts[index]
    out.write_string("  ")
    out.write_string(pad_right(tally.name, 10))
    out.write_string(pad_left(tally.count.to_string(), 6))
    out.write_string("\n")
    index = index + 1
  }
  out.write_string("\n")
  index = 0
  while index < entries.length() {
    let entry = entries[index]
    let label = if entry.binary { "binary" } else { entry.charset }
    out.write_string("  ")
    out.write_string(pad_right(entry.path, 34))
    out.write_string("  ")
    out.write_string(label)
    out.write_string("\n")
    index = index + 1
  }
  out.to_string()
}

///|
fn json_quote(text : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  out.write_string(@mojibake.json_escape(text))
  out.write_char('"')
  out.to_string()
}

///|
fn scan_json(dir : String, entries : Array[ScanEntry], counts : Array[Tally]) -> String {
  let out = StringBuilder()
  out.write_char('{')
  out.write_string("\"dir\":")
  out.write_string(json_quote(dir))
  out.write_string(",\"files\":")
  out.write_string(entries.length().to_string())
  out.write_string(",\"encodings\":[")
  let mut index = 0
  while index < counts.length() {
    if index > 0 {
      out.write_string(",")
    }
    let tally = counts[index]
    out.write_char('{')
    out.write_string("\"charset\":")
    out.write_string(json_quote(tally.name))
    out.write_string(",\"files\":")
    out.write_string(tally.count.to_string())
    out.write_char('}')
    index = index + 1
  }
  out.write_string("],\"entries\":[")
  index = 0
  while index < entries.length() {
    if index > 0 {
      out.write_string(",")
    }
    let entry = entries[index]
    out.write_char('{')
    out.write_string("\"path\":")
    out.write_string(json_quote(entry.path))
    out.write_string(",\"binary\":")
    if entry.binary {
      out.write_string("true")
      out.write_string(",\"charset\":null")
    } else {
      out.write_string("false")
      out.write_string(",\"charset\":")
      out.write_string(json_quote(entry.charset))
      out.write_string(",\"confidence\":")
      out.write_string(entry.confidence.to_string())
    }
    out.write_char('}')
    index = index + 1
  }
  out.write_char(']')
  out.write_char('}')
  out.to_string()
}
