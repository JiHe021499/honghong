import 'package:drift/drift.dart';

class Babies extends Table {
  TextColumn get id => text()(); // uuid
  TextColumn get nickname => text()();
  DateTimeColumn get birthDate => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // 家庭同步（schema v3）
  DateTimeColumn get updatedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  /// 性别：'boy' | 'girl' | null（未填/跳过，D5 可跳过）（schema v5）。不发给 AI。
  TextColumn get gender => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

/// 照护记录：feed / sleep / diaper / burp
class CareLogs extends Table {
  TextColumn get id => text()();
  TextColumn get babyId => text().references(Babies, #id)();
  TextColumn get type => text()(); // feed|sleep|diaper|burp
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()(); // 睡眠/喂奶时长
  TextColumn get detail => text().nullable()(); // JSON：奶量、侧别、尿/便等
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  /// 最后修改人（家人同步下来的记录才有，本机写入为空）（schema v4）
  TextColumn get updatedBy => text().nullable()();
  // 家庭同步（schema v3）：最后修改时间、软删除、待推送
  DateTimeColumn get updatedAt => dateTime().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
  /// 来源：quick（首页快捷记录）| diary（妈咪日记）| backfill（补记）（schema v5）
  TextColumn get source => text().withDefault(const Constant('quick'))();
  /// 来自日记时指向 diary_cards.id（schema v5）
  TextColumn get diaryCardId => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

/// 哭声事件：训练数据的核心表
class CryEvents extends Table {
  TextColumn get id => text()();
  TextColumn get babyId => text().references(Babies, #id)();
  DateTimeColumn get startedAt => dateTime()();
  IntColumn get durationMs => integer()();
  TextColumn get audioPath => text().nullable()(); // 本地相对路径
  RealColumn get cryConfidence => real().withDefault(const Constant(0))();
  TextColumn get contextJson => text()(); // CryContext 快照
  TextColumn get predictionJson => text()(); // 排序后的原因与概率
  TextColumn get predictorVersion => text()();
  BoolColumn get autoTriggered => boolean().withDefault(const Constant(false))();
  TextColumn get syncState => text().withDefault(const Constant('local'))(); // 参与改进上传：local|synced
  // 家庭同步（schema v3）：最后修改时间、软删除、待推送
  DateTimeColumn get updatedAt => dateTime().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

/// 家长反馈：最后是什么起作用了
class Feedbacks extends Table {
  TextColumn get id => text()();
  TextColumn get cryEventId => text().references(CryEvents, #id)();
  TextColumn get resolvedCause => text()(); // CryCause.name 或 unknown
  IntColumn get minutesToSoothe => integer().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class ModelVersions extends Table {
  TextColumn get version => text()();
  TextColumn get kind => text()(); // detector|classifier
  TextColumn get localPath => text()();
  TextColumn get sha256 => text()();
  BoolColumn get active => boolean().withDefault(const Constant(false))();
  DateTimeColumn get installedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {version};
}

// ───────── 妈咪日记（schema v5，只存本地，不同步） ─────────

/// 一次输入（一句话）
class DiaryInputs extends Table {
  TextColumn get id => text()();
  TextColumn get babyId => text().references(Babies, #id)();
  TextColumn get inputType => text()(); // voice|text
  TextColumn get rawText => text()();
  IntColumn get ageInDays => integer()();
  TextColumn get parseStatus => text()(); // ok|partial|failed
  TextColumn get promptVersion => text()();
  TextColumn get modelVersion => text().nullable()();
  IntColumn get latencyMs => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

/// 日记卡片：所有已保存的 AI 卡片都有一行（含已写入 care_logs 的，作溯源）
class DiaryCards extends Table {
  TextColumn get id => text()();
  TextColumn get inputId => text().nullable().references(DiaryInputs, #id)();
  TextColumn get babyId => text().references(Babies, #id)();
  TextColumn get category => text()(); // feeding|sleep|diaper|mood|other
  TextColumn get kind => text()(); // event|aggregate
  TextColumn get careLogId => text().nullable()();
  DateTimeColumn get eventTime => dateTime().nullable()();
  TextColumn get timePeriod => text().nullable()(); // morning|afternoon|evening|night|all_day
  DateTimeColumn get sortTime => dateTime()();
  DateTimeColumn get diaryDate => dateTime()(); // 归属日期（本地日 00:00）
  TextColumn get attributes => text()(); // JSON
  TextColumn get intensity => text().nullable()();
  TextColumn get note => text().nullable()();
  RealColumn get confidence => real().nullable()();
  BoolColumn get editedByUser => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

/// 今日小结：每宝宝每日一条
class DailySummaries extends Table {
  TextColumn get id => text()();
  TextColumn get babyId => text().references(Babies, #id)();
  DateTimeColumn get date => dateTime()(); // 本地日 00:00
  TextColumn get status => text()(); // pending|ready|empty|failed
  TextColumn get content => text().nullable()();
  TextColumn get sourceIds => text()(); // JSON
  TextColumn get statsJson => text()();
  TextColumn get promptVersion => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get generatedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {babyId, date}
      ];
}
