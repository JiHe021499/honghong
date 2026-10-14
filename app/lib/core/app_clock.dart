/// 全局时钟。生产代码一律用 [AppClock.now] 取当前时间，
/// 截图测试把它换成固定起点 + 测试的假时间，让基准图与运行时刻无关。
abstract final class AppClock {
  static DateTime Function() source = DateTime.now;
  static DateTime now() => source();
}
