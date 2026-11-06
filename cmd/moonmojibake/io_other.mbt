// 非 js 后端（native / llvm / wasm / wasm-gc）没有可移植的文件系统接口。
// 这里保持同样的函数签名，只给出明确的错误信息，保证 `moon check` 与
// `moon build` 在所有后端都能通过；真正读写文件请用 js 后端。

///|
fn read_file(_path : String) -> Bytes? {
  abort(
    "file IO needs the js backend: build with `moon build --target js` and run with node",
  )
}

///|
fn write_file(_path : String, _data : Bytes) -> Unit {
  abort(
    "file IO needs the js backend: build with `moon build --target js` and run with node",
  )
}

///|
fn write_text_file(_path : String, _text : String) -> Unit {
  abort(
    "file IO needs the js backend: build with `moon build --target js` and run with node",
  )
}

///|
fn read_stdin() -> Bytes {
  abort(
    "stdin needs the js backend: build with `moon build --target js` and run with node",
  )
}

///|
fn list_dir(_path : String) -> Array[String] {
  abort(
    "directory scanning needs the js backend: build with `moon build --target js` and run with node",
  )
}

///|
fn is_dir(_path : String) -> Bool {
  abort(
    "directory scanning needs the js backend: build with `moon build --target js` and run with node",
  )
}
