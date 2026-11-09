// js 后端（node）的真实 IO：文件、标准输入、标准输出都走 Node 的 fs 模块。

extern "js" fn fs_exists(path : String) -> Bool =
  "(p) => { try { require('fs').accessSync(p); return true } catch (e) { return false } }"

extern "js" fn fs_read(path : String) -> Bytes =
  "(p) => new Uint8Array(require('fs').readFileSync(p))"

extern "js" fn fs_write(path : String, data : Bytes) -> Unit =
  "(p, d) => require('fs').writeFileSync(p, Buffer.from(d))"

extern "js" fn fs_write_text(path : String, text : String) -> Unit =
  "(p, t) => require('fs').writeFileSync(p, t, 'utf8')"

extern "js" fn fs_read_stdin() -> Bytes =
  "() => new Uint8Array(require('fs').readFileSync(0))"

// 目录项：子目录名以 `/` 结尾，便于上层区分文件与目录。
// 返回 FixedArray：JS FFI 里 Array 已弃用，转成 Array 的活儿放在 list_dir 里，
// 让上层照旧用可变数组。
extern "js" fn fs_list_dir(path : String) -> FixedArray[String] =
  "(p) => require('fs').readdirSync(p, { withFileTypes: true }).map((d) => d.isDirectory() ? d.name + '/' : d.name)"

extern "js" fn fs_is_dir(path : String) -> Bool =
  "(p) => { try { return require('fs').statSync(p).isDirectory() } catch (e) { return false } }"

// 设 process.exitCode 而不是调 process.exit()：进程正常返回时 Node 仍会把
// 缓冲区刷完，管道下游不会拿到半行输出。
extern "js" fn set_exit_code(code : Int) -> Unit =
  "(c) => { process.exitCode = c }"

///|
fn read_file(path : String) -> Bytes? {
  if fs_exists(path) {
    Some(fs_read(path))
  } else {
    None
  }
}

///|
fn write_file(path : String, data : Bytes) -> Unit {
  fs_write(path, data)
}

///|
fn write_text_file(path : String, text : String) -> Unit {
  fs_write_text(path, text)
}

///|
fn read_stdin() -> Bytes {
  fs_read_stdin()
}

///|
fn list_dir(path : String) -> Array[String] {
  let names : Array[String] = []
  for name in fs_list_dir(path) {
    names.push(name)
  }
  names
}

///|
fn is_dir(path : String) -> Bool {
  fs_is_dir(path)
}
