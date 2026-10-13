/// 哭的原因。新增原因时同步更新规则和模型标签表。
enum CryCause {
  hungry('饿'),
  sleepy('困'),
  gas('胀气'),
  diaper('不舒服/尿布'),
  holdMe('要抱');

  const CryCause(this.label);
  final String label;
}
