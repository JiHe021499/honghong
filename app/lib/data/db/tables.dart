import 'package:drift/drift.dart';

class Babies extends Table {
  TextColumn get id => text()(); // uuid
  TextColumn get nickname => text()();
  DateTimeColumn get birthDate => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
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
  TextColumn get syncState => text().withDefault(const Constant('local'))(); // local|pending|synced
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
