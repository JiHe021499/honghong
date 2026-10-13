enum CareLogType {
  feed('喂奶'),
  sleep('睡觉'),
  diaper('换尿布'),
  burp('拍嗝');

  const CareLogType(this.label);
  final String label;
}
