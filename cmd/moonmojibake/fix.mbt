// fix —— 批量修复：走一遍目录，把不是 UTF-8 或带乱码的文件转成 UTF-8。
//
// 默认只预览，落盘要显式 --write。理由很直接：这个工具的用途是「我不知
// 道这些文件是什么编码」，而在不知道的前提下自动改写文件是不可接受的；
// 先把结果摆出来，人看过再决定，失败模式才可控。

///|
struct FixEntry {
  path : String
  read_as : String
  chain : String
  before : Int
  after : Int
  repaired : Bool
}

///|
fn render_fix_tree(
  dir : String,
  recursive : Bool,
  write : Bool,
  scanned : Int,
  binary : Int,
  entries : Array[FixEntry],
  written : Int,
) -> String {
  let out = StringBuilder()
  out.write_string("fix ")
  out.write_string(dir)
  if recursive {
    out.write_string(" (recursive)")
  }
  out.write_string(" (")
  out.write_string(scanned.to_string())
  out.write_string(" files")
  if binary > 0 {
    out.write_string(", ")
    out.write_string(binary.to_string())
    out.write_string(" binary skipped")
  }
  if !write {
    out.write_string(", dry run")
  }
  out.write_string(")\n\n  ")
  out.write_string(pad_right("path", 38))
  out.write_string("  ")
  out.write_string(pad_right("read as", 12))
  out.write_string("  change\n")
  for entry in entries {
    out.write_string("  ")
    out.write_string(pad_right(entry.path, 38))
    out.write_string("  ")
    out.write_string(pad_right(entry.read_as, 12))
    out.write_string("  ")
    if entry.repaired {
      // 字节本来就合法 UTF-8 时没有转码，只有修复，别把两件事写成一件。
      if entry.read_as == "utf-8" {
        out.write_string("repair: ")
      } else {
        out.write_string("transcode + ")
      }
      out.write_string(entry.chain)
      out.write_string("  ")
      out.write_string(entry.before.to_string())
      out.write_string(" -> ")
      out.write_string(entry.after.to_string())
    } else {
      out.write_string("transcode")
    }
    out.write_string("\n")
  }
  out.write_string("\n")
  let text_files = scanned - binary
  if entries.length() == 0 {
    out.write_string("no file needs changing: all ")
    out.write_string(text_files.to_string())
    out.write_string(" text files already read as UTF-8.")
  } else if write {
    out.write_string(entries.length().to_string())
    out.write_string(" of ")
    out.write_string(text_files.to_string())
    out.write_string(" text files changed; ")
    out.write_string(written.to_string())
    out.write_string(" written as UTF-8.")
  } else {
    out.write_string(entries.length().to_string())
    out.write_string(" of ")
    out.write_string(text_files.to_string())
    out.write_string(" text files would change; nothing written. Re-run with --write to apply.")
  }
  out.to_string()
}

///|
fn fix_json(
  dir : String,
  recursive : Bool,
  write : Bool,
  scanned : Int,
  binary : Int,
  entries : Array[FixEntry],
  written : Int,
) -> String {
  let out = StringBuilder()
  out.write_char('{')
  out.write_string("\"dir\":")
  out.write_string(json_quote(dir))
  out.write_string(",\"recursive\":")
  out.write_string(if recursive { "true" } else { "false" })
  out.write_string(",\"write\":")
  out.write_string(if write { "true" } else { "false" })
  out.write_string(",\"files\":")
  out.write_string(scanned.to_string())
  out.write_string(",\"binary\":")
  out.write_string(binary.to_string())
  out.write_string(",\"changed\":")
  out.write_string(entries.length().to_string())
  out.write_string(",\"written\":")
  out.write_string(written.to_string())
  out.write_string(",\"entries\":[")
  let mut index = 0
  while index < entries.length() {
    if index > 0 {
      out.write_string(",")
    }
    let entry = entries[index]
    out.write_char('{')
    out.write_string("\"path\":")
    out.write_string(json_quote(entry.path))
    out.write_string(",\"read_as\":")
    out.write_string(json_quote(entry.read_as))
    out.write_string(",\"chain\":")
    out.write_string(json_quote(entry.chain))
    out.write_string(",\"repaired\":")
    out.write_string(if entry.repaired { "true" } else { "false" })
    out.write_string(",\"score_before\":")
    out.write_string(entry.before.to_string())
    out.write_string(",\"score_after\":")
    out.write_string(entry.after.to_string())
    out.write_char('}')
    index = index + 1
  }
  out.write_char(']')
  out.write_char('}')
  out.to_string()
}

///|
fn cmd_fix(args : Array[String], start : Int) -> Unit {
  let mut dir = ""
  let mut recursive = false
  let mut write = false
  let mut want_json = false
  let mut index = start
  while index < args.length() {
    let arg = args[index]
    if arg == "--json" {
      want_json = true
    } else if arg == "-r" || arg == "--recursive" {
      recursive = true
    } else if arg == "--write" {
      write = true
    } else if dir == "" {
      dir = trim_trailing_separator(arg)
    }
    index = index + 1
  }
  if dir == "" {
    println("error: fix needs a directory")
    set_exit_code(EXIT_USAGE)
    return
  }
  if !is_dir(dir) {
    println("error: not a directory: \{dir}")
    set_exit_code(EXIT_USAGE)
    return
  }
  let files : Array[String] = []
  collect_files(dir, recursive, files)
  let entries : Array[FixEntry] = []
  let mut scanned = 0
  let mut binary = 0
  let mut written = 0
  for path in files {
    scanned = scanned + 1
    match read_file(path) {
      Some(bytes) =>
        if @mojibake.looks_binary(bytes) {
          binary = binary + 1
        } else {
          let fixed = @mojibake.repair_auto(bytes)
          if fixed.changed() {
            let result = fixed.result()
            entries.push(
              {
                path,
                read_as: fixed.charset().name(),
                chain: @mojibake.render_chain(result),
                before: result.before(),
                after: result.after(),
                repaired: @mojibake.was_repaired(result),
              },
            )
            if write {
              write_text_file(path, fixed.text())
              written = written + 1
            }
          }
        }
      None => ()
    }
  }
  if want_json {
    println(fix_json(dir, recursive, write, scanned, binary, entries, written))
  } else {
    println(render_fix_tree(dir, recursive, write, scanned, binary, entries, written))
  }
}
