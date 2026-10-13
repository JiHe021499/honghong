import 'dart:typed_data';

/// 家庭成员
class FamilyMember {
  const FamilyMember({required this.userId, required this.role, required this.name, required this.avatar});
  final String userId;
  final String role; // owner | member
  final String name;
  final String avatar; // mom | dad | grandma | baby
  bool get isOwner => role == 'owner';
}

/// 云端接口。真实实现是 [SupabaseCloudApi]，测试里用内存假实现。
/// 时间统一用 UTC ISO8601 字符串。
abstract class CloudApi {
  String? get userId;
  Future<String> ensureSignedIn();

  // 家庭
  Future<String?> myFamilyId();
  Future<String> createFamily({required String babyId, required String nickname, required DateTime birthDate, required String name, required String avatar});
  Future<String> joinFamily({required String code, required String name, required String avatar});
  Future<String?> inviteCode();
  Future<String> refreshInvite();
  Future<List<FamilyMember>> members();
  Future<void> leaveFamily();
  Future<void> removeMember(String userId);

  // 同步（行是 snake_case 的 Map，和 Postgres 表一致）
  Future<Map<String, dynamic>?> pullBaby(String familyId);
  Future<void> pushBaby(Map<String, dynamic> baby);
  Future<void> pushCareLogs(List<Map<String, dynamic>> rows);
  Future<void> pushCryEvents(List<Map<String, dynamic>> rows);
  Future<List<Map<String, dynamic>>> pullCareLogs(String familyId, String? since);
  Future<List<Map<String, dynamic>>> pullCryEvents(String familyId, String? since);

  // 参与改进（研究数据，按设备隔离）
  Future<void> upsertDevice({required String appVersion, required DateTime consentAt});
  Future<void> upsertResearchBaby({required String id, required double ageMonths});
  Future<String> uploadClip(String eventId, Uint8List wav);
  Future<void> upsertResearchEvent(Map<String, dynamic> row);
  Future<void> upsertResearchFeedback(Map<String, dynamic> row);
  Future<void> deleteMyResearchData();
}

/// 友好的错误（直接显示给用户）
class CloudException implements Exception {
  CloudException(this.message);
  final String message;
  @override
  String toString() => message;
}
