// moonmojibake —— 编码检测与乱码修复的命令行入口。
//
//   detect  <file>                列出每种编码的得分，给出最可能的结果
//   repair  <file> [-o out]       逐层还原乱码，给出还原链
//   convert <file> --from X --to Y [-o out]
//
// 没有文件系统时（非 js 后端）可以用 `--text "..."` 直接喂一段文本。

///|
struct Options {
  mut text : String?
  mut path : String?
  mut output : String?
  mut from : String?
  mut to : String?
  mut use_stdin : Bool
  mut json : Bool
}

///|
fn new_options() -> Options {
  {
    text: None,
    path: None,
    output: None,
    from: None,
    to: None,
    use_stdin: false,
    json: false,
  }
}

///|
fn option_value(args : Array[String], index : Int) -> String? {
  if index + 1 < args.length() {
    Some(args[index + 1])
  } else {
    None
  }
}

///|
fn parse_options(args : Array[String], start : Int) -> Options {
  let options = new_options()
  let mut index = start
  while index < args.length() {
    let arg = args[index]
    if arg == "--text" || arg == "-t" {
      options.text = option_value(args, index)
      index = index + 2
    } else if arg == "--output" || arg == "-o" {
      options.output = option_value(args, index)
      index = index + 2
    } else if arg == "--from" || arg == "-f" {
      options.from = option_value(args, index)
      index = index + 2
    } else if arg == "--to" {
      options.to = option_value(args, index)
      index = index + 2
    } else if arg == "--json" {
      options.json = true
      index = index + 1
    } else if arg == "-" || arg == "--stdin" {
      options.use_stdin = true
      index = index + 1
    } else if options.path == None {
      options.path = Some(arg)
      index = index + 1
    } else {
      index = index + 1
    }
  }
  options
}

///|
/// Resolve the input to (label, bytes), or print the reason it failed.
fn load_input(options : Options) -> (String, Bytes)? {
  if options.text is Some(text) {
    return Some(("<text>", @utf8.encode(text)))
  }
  if options.use_stdin {
    return Some(("<stdin>", read_stdin()))
  }
  if options.path is Some(path) {
    match read_file(path) {
      Some(bytes) => return Some((path, bytes))
      None => {
        println("error: cannot read \{path}")
        return None
      }
    }
  }
  println("error: nothing to read; pass a file path, `--text \"...\"`, or `-` for stdin")
  None
}

///|
fn version_line() -> String {
  "moonmojibake 0.3.0"
}

///|
fn usage() -> String {
  let lines : Array[String] = [
    "moonmojibake — encoding detection and mojibake repair",
    "",
    "usage:",
    "  moonmojibake detect  <file> [--json]     rank every code page for a file",
    "  moonmojibake detect  --text \"...\"       ... for a string instead",
    "  moonmojibake repair  <file> [-o out] [--json]  undo mojibake layer by layer",
    "  moonmojibake convert <file> --from gbk --to utf-8 [-o out]",
    "  moonmojibake scan    <dir> [-r] [--json]  report the encoding of every file",
    "  moonmojibake --version",
    "",
    "  --json          emit machine-readable JSON instead of a table",
    "  -r, --recursive descend into sub-directories (scan)",
    "",
    "inputs:",
    "  <file>          read raw bytes from a file (js backend)",
    "  --text STR      treat STR as UTF-8 bytes",
    "  -               read raw bytes from stdin (js backend)",
    "",
    "encodings:",
    "  utf-8, utf-16le, utf-16be, utf-32le, utf-32be,",
    "  gbk, big5, shift_jis, euc-jp, euc-kr, latin1, windows-1252",
  ]
  let out = StringBuilder()
  let mut index = 0
  while index < lines.length() {
    if index > 0 {
      out.write_char('\n')
    }
    out.write_string(lines[index])
    index = index + 1
  }
  out.to_string()
}

///|
fn cmd_detect(args : Array[String], start : Int) -> Unit {
  let options = parse_options(args, start)
  let input = load_input(options)
  if input is Some((source, bytes)) {
    let rows = @mojibake.detect(bytes)
    if options.json {
      println(@mojibake.detection_json(source, bytes.length(), rows))
    } else {
      println(@mojibake.render_detection(source, bytes.length(), rows))
    }
  }
}

///|
fn cmd_repair(args : Array[String], start : Int) -> Unit {
  let options = parse_options(args, start)
  let input = load_input(options)
  if input is Some((source, bytes)) {
    // 乱码文本本身通常是合法的 UTF-8，先按 UTF-8 读；读不通再交给检测。
    let probe = @mojibake.decode(bytes, @mojibake.Charset::Utf8)
    let decoded = if probe.errors() == 0 {
      probe
    } else {
      let charset = @mojibake.detect_charset_or(bytes, @mojibake.Charset::Utf8)
      @mojibake.decode(bytes, charset)
    }
    let result = @mojibake.repair(decoded.text())
    match options.output {
      Some(path) => {
        write_text_file(path, result.text)
        if options.json {
          println(@mojibake.fix_json(source, result))
        } else {
          println("wrote \{path}")
          if @mojibake.was_repaired(result) {
            println(
              "chain: \{@mojibake.render_chain(result)}  (score \{result.before()} -> \{result.after()})",
            )
          }
        }
      }
      None =>
        if options.json {
          println(@mojibake.fix_json(source, result))
        } else {
          println(source)
          println(@mojibake.render_fix(result))
        }
    }
  }
}

///|
fn cmd_convert(args : Array[String], start : Int) -> Unit {
  let options = parse_options(args, start)
  let input = load_input(options)
  if input is Some((source, bytes)) {
    let from = match options.from {
      Some(name) =>
        match @mojibake.Charset::parse(name) {
          Some(charset) => Some(charset)
          None => {
            println("error: unknown encoding \{name}")
            None
          }
        }
      None => @mojibake.detect_charset(bytes)
    }
    let to = match options.to {
      Some(name) =>
        match @mojibake.Charset::parse(name) {
          Some(charset) => Some(charset)
          None => {
            println("error: unknown encoding \{name}")
            None
          }
        }
      None => Some(@mojibake.Charset::Utf8)
    }
    if from is Some(source_charset) && to is Some(target_charset) {
      let text = @mojibake.decode_text(bytes, source_charset)
      match options.output {
        Some(path) =>
          match @mojibake.encode(text, target_charset) {
            Some(encoded) => {
              write_file(path, encoded)
              println(
                "\{source}: \{source_charset.name()} -> \{target_charset.name()}, \{encoded.length()} bytes written to \{path}",
              )
            }
            None => println("error: text cannot be represented in \{target_charset.name()}")
          }
        None => println(text)
      }
    }
  }
}

///|
/// Find the subcommand in argv.
///
/// Node prepends the executable and the script path, other backends do not,
/// so scanning for a known verb is more reliable than assuming an offset.
fn find_command(args : Array[String]) -> Int {
  let mut index = 0
  while index < args.length() {
    let arg = args[index]
    if arg == "detect" ||
      arg == "repair" ||
      arg == "convert" ||
      arg == "scan" ||
      arg == "help" ||
      arg == "--help" ||
      arg == "-h" ||
      arg == "version" ||
      arg == "--version" ||
      arg == "-V" {
      return index
    }
    index = index + 1
  }
  -1
}

fn main {
  let args = @env.args()
  let command_index = find_command(args)
  if command_index < 0 {
    println(usage())
    return
  }
  let command = args[command_index]
  let start = command_index + 1
  if command == "detect" {
    cmd_detect(args, start)
  } else if command == "repair" {
    cmd_repair(args, start)
  } else if command == "convert" {
    cmd_convert(args, start)
  } else if command == "scan" {
    let mut dir = ""
    let mut want_json = false
    let mut recursive = false
    let mut scan_index = start
    while scan_index < args.length() {
      let arg = args[scan_index]
      if arg == "--json" {
        want_json = true
      } else if arg == "-r" || arg == "--recursive" {
        recursive = true
      } else if dir == "" {
        dir = trim_trailing_separator(arg)
      }
      scan_index = scan_index + 1
    }
    if dir == "" {
      println("error: scan needs a directory")
      return
    }
    if !is_dir(dir) {
      println("error: not a directory: \{dir}")
      return
    }
    let scan_files : Array[String] = []
    collect_files(dir, recursive, scan_files)
    let scan_entries : Array[ScanEntry] = []
    let scan_counts : Array[Tally] = []
    for scan_path in scan_files {
      let data = read_file(scan_path)
      if data is Some(bytes) {
        if @mojibake.looks_binary(bytes) {
          scan_entries.push(
            { path: scan_path, charset: "", confidence: 0, binary: true },
          )
          bump_count(scan_counts, "binary")
        } else {
          let rows = @mojibake.detect(bytes)
          if rows.length() == 0 {
            scan_entries.push(
              { path: scan_path, charset: "empty", confidence: 0, binary: false },
            )
            bump_count(scan_counts, "empty")
          } else {
            let winner = rows[0]
            let name = winner.charset().name()
            scan_entries.push(
              {
                path: scan_path,
                charset: name,
                confidence: winner.confidence(),
                binary: false,
              },
            )
            bump_count(scan_counts, name)
          }
        }
      } else {
        scan_entries.push(
          { path: scan_path, charset: "unreadable", confidence: 0, binary: false },
        )
        bump_count(scan_counts, "unreadable")
      }
    }
    if want_json {
      println(scan_json(dir, scan_entries, scan_counts))
    } else {
      println(render_scan(dir, scan_entries, scan_counts))
    }
  } else if command == "--version" || command == "-V" || command == "version" {
    println(version_line())
  } else {
    println(usage())
  }
}
