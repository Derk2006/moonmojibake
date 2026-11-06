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
extern "js" fn fs_list_dir(path : String) -> Array[String] =
  "(p) => require('fs').readdirSync(p, { withFileTypes: true }).map((d) => d.isDirectory() ? d.name + '/' : d.name)"

extern "js" fn fs_is_dir(path : String) -> Bool =
  "(p) => { try { return require('fs').statSync(p).isDirectory() } catch (e) { return false } }"

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
  fs_list_dir(path)
}

///|
fn is_dir(path : String) -> Bool {
  fs_is_dir(path)
}
