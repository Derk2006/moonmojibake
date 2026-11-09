// --fail-if-not —— 把「这个目录里不该有非 UTF-8 文件」变成一条可执行的断言。
//
// 检测工具只在报告里说「这个文件是 gbk」，而真正想阻止的事是「它进了主
// 干」。退出码让 shell 和 CI 能接住这条判断：0 表示符合预期，2 表示文件
// 不符合预期，1 留给人写错了参数——两种情况混成同一个数字，调用方就没法
// 区分是仓库有问题还是自己命令敲错了。

///|
/// 断言失败时的退出码。
const EXIT_ASSERT : Int = 2

///|
/// 把用户写的编码名归一化成规范名，别名（`UTF8`、`shift-jis`）也认。
fn canonical_charset(name : String) -> String? {
  match @mojibake.Charset::parse(name) {
    Some(charset) => Some(charset.name())
    None => None
  }
}

///|
/// 单文件断言：`expected` 为 None 时什么都不做。
fn gate_single(expected : String?, source : String, actual : String) -> Unit {
  match expected {
    Some(name) =>
      match canonical_charset(name) {
        Some(wanted) =>
          if wanted != actual {
            println("error: \{source} reads as \{actual}, expected \{wanted}")
            set_exit_code(EXIT_ASSERT)
          }
        None => {
          println("error: unknown encoding \{name}")
          set_exit_code(1)
        }
      }
    None => ()
  }
}
