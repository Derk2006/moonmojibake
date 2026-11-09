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
/// 用法错误（读不到文件、编码名写错、参数缺值）的退出码。
///
/// 单独列出来是因为「命令写错了」和「仓库不合规」必须能分开：前者是调用
/// 方的问题，后者是要修的代码。任何一条错误路径都必须返回非零，否则脚本
/// 里的 `moonmojibake convert ...` 失败了也当成功，等于把错误值传给了下
/// 一步。
const EXIT_USAGE : Int = 1

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
///
/// 平局的候选都算通过：它们解码出的文本逐字相同，只是名字不同，把一个
/// 纯假名文件判成「不是 gbk」只会让 CI 报一个修不了的错。
fn gate_single(
  expected : String?,
  source : String,
  rows : Array[@mojibake.Detection],
) -> Unit {
  match expected {
    Some(name) =>
      match canonical_charset(name) {
        Some(wanted) => {
          let actual = if rows.length() == 0 {
            "empty"
          } else {
            rows[0].charset().name()
          }
          let mut accepted = actual == wanted
          if !accepted {
            for candidate in @mojibake.ambiguous_candidates(rows) {
              if candidate.name() == wanted {
                accepted = true
              }
            }
          }
          if !accepted {
            println("error: \{source} reads as \{actual}, expected \{wanted}")
            set_exit_code(EXIT_ASSERT)
          }
        }
        None => {
          println("error: unknown encoding \{name}")
          set_exit_code(EXIT_USAGE)
        }
      }
    None => ()
  }
}
