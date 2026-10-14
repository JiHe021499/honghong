import 'dart:typed_data';

import 'package:honghong/services/cloud/cloud_api.dart';

/// 内存里的"服务器"，规则和 0002_family.sql 一致：按 updated_at 最后写入者胜出，按序号增量拉取。
class FakeServer {
  final families = <String, Map<String, String>>{}; // fid -> {uid: role}
  final invites = <String, String>{}; // code -> fid
  final babies = <String, Map<String, dynamic>>{};
  final logs = <String, Map<String, dynamic>>{};
  final cries = <String, Map<String, dynamic>>{};
  final research = <String, Map<String, dynamic>>{};
  final clips = <String, Uint8List>{};
  final models = <String, Uint8List>{}; // storage path -> bytes
  Map<String, dynamic>? eligible; // eligible_model('classifier') 的返回
  /// 模拟线上未跑 0004：带 gender 的 push_baby 报 PGRST202
  bool rejectGenderInPush = false;
  int _seq = 0, _n = 0;
  String _stamp() => (++_seq).toString().padLeft(12, '0');

  void upsertLww(Map<String, Map<String, dynamic>> t, Map<String, dynamic> r) {
    final old = t[r['id']];
    if (old != null && DateTime.parse(old['updated_at']).isAfter(DateTime.parse(r['updated_at']))) return;
    t[r['id']] = {...r, 'server_updated_at': _stamp()};
  }
}

class FakeCloud implements CloudApi {
  FakeCloud(this.s, this.uid);
  final FakeServer s;
  final String uid;
  bool offline = false;

  String? get _fid {
    for (final e in s.families.entries) {
      if (e.value.containsKey(uid)) return e.key;
    }
    return null;
  }

  void _net() {
    if (offline) throw CloudException('offline');
  }

  @override
  String? get userId => uid;
  @override
  Future<String> ensureSignedIn() async => uid;
  @override
  Future<String?> myFamilyId() async => _fid;

  @override
  Future<String> createFamily({required String babyId, required String nickname, required DateTime birthDate, required String name, required String avatar}) async {
    _net();
    if (_fid != null) throw CloudException('这台手机已经在一个家庭里了');
    final fid = 'fam${++s._n}';
    s.families[fid] = {uid: 'owner'};
    s.babies[fid] = {'id': babyId, 'nickname': nickname, 'birth_date': birthDate.toIso8601String().substring(0, 10), 'updated_at': DateTime.now().toUtc().toIso8601String()};
    s.invites['ABC23${s._n}'] = fid;
    return fid;
  }

  @override
  Future<String> joinFamily({required String code, required String name, required String avatar}) async {
    _net();
    final fid = s.invites[code];
    if (fid == null) throw CloudException('邀请码不对或已过期，请让家人刷新一下');
    s.families[fid]![uid] = 'member';
    return fid;
  }

  @override
  Future<String?> inviteCode() async => s.invites.entries.where((e) => e.value == _fid).map((e) => e.key).firstOrNull;
  @override
  Future<String> refreshInvite() async => (await inviteCode())!;
  @override
  Future<List<FamilyMember>> members() async => [
        for (final e in s.families[_fid]!.entries) FamilyMember(userId: e.key, role: e.value, name: e.key, avatar: 'dad'),
      ];
  @override
  Future<void> leaveFamily() async => s.families[_fid]?.remove(uid);
  @override
  Future<void> removeMember(String userId) async => s.families[_fid]?.remove(userId);

  void _check(String fid) {
    if (s.families[fid]?.containsKey(uid) != true) throw CloudException('rls');
  }

  @override
  Future<Map<String, dynamic>?> pullBaby(String familyId) async {
    _net();
    _check(familyId);
    return s.babies[familyId];
  }

  @override
  Future<void> pushBaby(Map<String, dynamic> baby) async {
    _net();
    if (s.rejectGenderInPush && baby.containsKey('gender') && baby['gender'] != null) {
      throw CloudException('服务器出错：Could not find the function public.push_baby', code: 'PGRST202');
    }
    final b = s.babies[_fid]!;
    if (!DateTime.parse(b['updated_at']).isAfter(DateTime.parse(baby['updated_at']))) {
      final row = Map<String, dynamic>.of(baby);
      if (s.rejectGenderInPush) row.remove('gender');
      s.babies[_fid!] = row;
    }
  }

  @override
  Future<void> pushCareLogs(List<Map<String, dynamic>> rows) async {
    _net();
    for (final r in rows) {
      _check(r['family_id']);
      s.upsertLww(s.logs, {...r, 'updated_by': uid});
    }
  }

  @override
  Future<void> pushCryEvents(List<Map<String, dynamic>> rows) async {
    _net();
    for (final r in rows) {
      _check(r['family_id']);
      s.upsertLww(s.cries, {...r, 'updated_by': uid});
    }
  }

  List<Map<String, dynamic>> _pull(Map<String, Map<String, dynamic>> t, String fid, String? since) {
    _net();
    _check(fid);
    final out = t.values.where((r) => r['family_id'] == fid && (since == null || (r['server_updated_at'] as String).compareTo(since) > 0)).toList()
      ..sort((a, b) => (a['server_updated_at'] as String).compareTo(b['server_updated_at']));
    return out;
  }

  @override
  Future<List<Map<String, dynamic>>> pullCareLogs(String familyId, String? since) async => _pull(s.logs, familyId, since);
  @override
  Future<List<Map<String, dynamic>>> pullCryEvents(String familyId, String? since) async => _pull(s.cries, familyId, since);

  @override
  Future<void> upsertDevice({required String appVersion, required DateTime consentAt}) async => _net();
  @override
  Future<void> upsertResearchBaby({required String id, required double ageMonths}) async => _net();
  @override
  Future<String> uploadClip(String eventId, Uint8List wav) async {
    _net();
    s.clips['$uid/$eventId.wav'] = wav;
    return '$uid/$eventId.wav';
  }

  @override
  Future<void> upsertResearchEvent(Map<String, dynamic> row) async {
    _net();
    s.research[row['id']] = row;
  }

  @override
  Future<void> upsertResearchFeedback(Map<String, dynamic> row) async => _net();
  @override
  Future<void> deleteMyResearchData() async {
    _net();
    s.research.clear();
    s.clips.removeWhere((k, _) => k.startsWith('$uid/'));
  }

  @override
  Future<Map<String, dynamic>?> eligibleModel(String kind) async {
    _net();
    return s.eligible;
  }

  @override
  Future<Uint8List> downloadModel(String storagePath) async {
    _net();
    final b = s.models[storagePath];
    if (b == null) throw CloudException('not found');
    return b;
  }
}
