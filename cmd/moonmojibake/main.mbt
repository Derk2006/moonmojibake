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
  mut fail_if_not : String?
  /// 第一个「写了但没给值」的选项，比如结尾孤零零的 `--from`。
  mut bad_option : String?
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
    fail_if_not: None,
    bad_option: None,
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
/// Read a flag's value, remembering the flag when it is missing.
///
/// Returning `None` silently would make `--from` at the end of the command
/// line look like "no encoding was given", and the tool would fall back to
/// detection — a wrong answer where the user asked for a specific one.
fn take_value(args : Array[String], index : Int, options : Options, flag : String) -> String? {
  match option_value(args, index) {
    Some(value) => Some(value)
    None => {
      options.bad_option = Some(flag)
      None
    }
  }
}

///|
fn parse_options(args : Array[String], start : Int) -> Options {
  let options = new_options()
  let mut index = start
  while index < args.length() {
    let arg = args[index]
    if arg == "--text" || arg == "-t" {
      options.text = take_value(args, index, options, arg)
      index = index + 2
    } else if arg == "--output" || arg == "-o" {
      options.output = take_value(args, index, options, arg)
      index = index + 2
    } else if arg == "--from" || arg == "-f" {
      options.from = take_value(args, index, options, arg)
      index = index + 2
    } else if arg == "--to" {
      options.to = take_value(args, index, options, arg)
      index = index + 2
    } else if arg == "--json" {
      options.json = true
      index = index + 1
    } else if arg == "--fail-if-not" {
      options.fail_if_not = take_value(args, index, options, arg)
      index = index + 2
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
/// Report a missing option value, if any.  Returns true when the caller
/// should stop.
fn reject_missing_value(options : Options) -> Bool {
  match options.bad_option {
    Some(flag) => {
      println("error: \{flag} needs a value")
      set_exit_code(EXIT_USAGE)
      true
    }
    None => false
  }
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
        set_exit_code(EXIT_USAGE)
        return None
      }
    }
  }
  println("error: nothing to read; pass a file path, `--text \"...\"`, or `-` for stdin")
  set_exit_code(EXIT_USAGE)
  None
}

///|
fn version_line() -> String {
  "moonmojibake 0.5.0"
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
    "  moonmojibake fix     <dir> [-r] [--write] [--json]",
    "                                          rewrite non-UTF-8 / mojibake files",
    "  moonmojibake --version",
    "",
    "  --json          emit machine-readable JSON instead of a table",
    "  -r, --recursive descend into sub-directories (scan, fix)",
    "  --write         actually rewrite files (fix; default is a dry run)",
    "  --fail-if-not X exit 2 when a file reads as anything but X (detect, scan)",
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
  if reject_missing_value(options) {
    return
  }
  let input = load_input(options)
  if input is Some((source, bytes)) {
    let rows = @mojibake.detect(bytes)
    if options.json {
      println(@mojibake.detection_json(source, bytes.length(), rows))
    } else {
      println(@mojibake.render_detection(source, bytes.length(), rows))
    }
    gate_single(options.fail_if_not, source, rows)
  }
}

///|
fn cmd_repair(args : Array[String], start : Int) -> Unit {
  let options = parse_options(args, start)
  if reject_missing_value(options) {
    return
  }
  let input = load_input(options)
  if input is Some((source, bytes)) {
    // 编码判定与修复搜索的顺序由库里的 repair_auto 决定，命令行不再重复一遍。
    let result = @mojibake.repair_auto(bytes).result()
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
  if reject_missing_value(options) {
    return
  }
  let input = load_input(options)
  if input is Some((source, bytes)) {
    // `--text` carries Unicode already, so its bytes are always UTF-8.  Reading
    // them as GBK would turn good text into mojibake and print it with a zero
    // exit code, which is the worst possible answer: wrong and confident.
    if options.text is Some(_) {
      if options.from is Some(name) {
        match @mojibake.Charset::parse(name) {
          Some(charset) =>
            if charset != @mojibake.Charset::Utf8 {
              println(
                "error: --text is always UTF-8; pass a file to read \{charset.name()} bytes",
              )
              set_exit_code(EXIT_USAGE)
              return
            }
          None => {
            println("error: unknown encoding \{name}")
            set_exit_code(EXIT_USAGE)
            return
          }
        }
      }
    }
    let from = match options.from {
      Some(name) =>
        match @mojibake.Charset::parse(name) {
          Some(charset) => Some(charset)
          None => {
            println("error: unknown encoding \{name}")
            set_exit_code(EXIT_USAGE)
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
            set_exit_code(EXIT_USAGE)
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
            None => {
              println("error: text cannot be represented in \{target_charset.name()}")
              set_exit_code(EXIT_USAGE)
            }
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
      arg == "fix" ||
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
    set_exit_code(EXIT_USAGE)
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
  } else if command == "fix" {
    cmd_fix(args, start)
  } else if command == "scan" {
    let mut dir = ""
    let mut want_json = false
    let mut recursive = false
    let mut gate : String? = None
    let mut scan_index = start
    while scan_index < args.length() {
      let arg = args[scan_index]
      if arg == "--json" {
        want_json = true
      } else if arg == "-r" || arg == "--recursive" {
        recursive = true
      } else if arg == "--fail-if-not" {
        if scan_index + 1 < args.length() {
          gate = Some(args[scan_index + 1])
          scan_index = scan_index + 1
        }
      } else if dir == "" {
        dir = trim_trailing_separator(arg)
      }
      scan_index = scan_index + 1
    }
    if dir == "" {
      println("error: scan needs a directory")
      set_exit_code(EXIT_USAGE)
      return
    }
    if !is_dir(dir) {
      println("error: not a directory: \{dir}")
      set_exit_code(EXIT_USAGE)
      return
    }
    let wanted = match gate {
      Some(name) =>
        match canonical_charset(name) {
          Some(canonical) => Some(canonical)
          None => {
            println("error: unknown encoding \{name}")
            set_exit_code(EXIT_USAGE)
            return
          }
        }
      None => None
    }
    let scan_files : Array[String] = []
    collect_files(dir, recursive, scan_files)
    let scan_entries : Array[ScanEntry] = []
    let scan_counts : Array[Tally] = []
    let gate_misses : Array[String] = []
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
            match wanted {
              Some(expected) => {
                // A tie is not a miss: the tied readings produce identical
                // text, so either name is a correct description of the file.
                let mut matches = name == expected
                if !matches {
                  for candidate in @mojibake.ambiguous_candidates(rows) {
                    if candidate.name() == expected {
                      matches = true
                    }
                  }
                }
                if !matches {
                  gate_misses.push(
                    "error: \{scan_path} reads as \{name}, expected \{expected}",
                  )
                }
              }
              None => ()
            }
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
      println(
        scan_json(dir, scan_entries, scan_counts, wanted, gate_misses.length() == 0),
      )
    } else {
      println(render_scan(dir, scan_entries, scan_counts))
      // 断言失败的原因放在表后面，JSON 模式下则靠 assert_ok 字段，不往 stdout 掺文本。
      for message in gate_misses {
        println(message)
      }
    }
    if gate_misses.length() > 0 {
      set_exit_code(EXIT_ASSERT)
    }
  } else if command == "--version" || command == "-V" || command == "version" {
    println(version_line())
  } else {
    println(usage())
  }
}
