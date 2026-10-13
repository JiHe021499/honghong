import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_api.dart';

class SupabaseCloudApi implements CloudApi {
  SupabaseCloudApi(this._c);
  final SupabaseClient _c;

  @override
  String? get userId => _c.auth.currentUser?.id;

  @override
  Future<String> ensureSignedIn() async {
    final u = _c.auth.currentUser;
    if (u != null) return u.id;
    final r = await _c.auth.signInAnonymously();
    return r.user!.id;
  }

  Future<T> _rpc<T>(String fn, [Map<String, dynamic>? params]) async {
    await ensureSignedIn();
    try {
      return await _c.rpc(fn, params: params) as T;
    } on PostgrestException catch (e) {
      throw CloudException(switch (e.code) {
        'P0001' => '这台手机已经在一个家庭里了',
        'P0002' => '邀请码不对或已过期，请让家人刷新一下',
        'P0003' => '只有创建者可以移除成员',
        _ => '服务器出错：${e.message}',
      });
    }
  }

  @override
  Future<String?> myFamilyId() async {
    final uid = await ensureSignedIn();
    final r = await _c.from('family_members').select('family_id').eq('user_id', uid).maybeSingle();
    return r?['family_id'] as String?;
  }

  @override
  Future<String> createFamily({required String babyId, required String nickname, required DateTime birthDate, required String name, required String avatar}) =>
      _rpc<String>('create_family', {
        'p_baby_id': babyId,
        'p_nickname': nickname,
        'p_birth_date': birthDate.toIso8601String().substring(0, 10),
        'p_display_name': name,
        'p_avatar': avatar,
      });

  @override
  Future<String> joinFamily({required String code, required String name, required String avatar}) =>
      _rpc<String>('join_family', {'p_code': code, 'p_display_name': name, 'p_avatar': avatar});

  @override
  Future<String?> inviteCode() async {
    await ensureSignedIn();
    final r = await _c.from('family_invites').select('code').gt('expires_at', DateTime.now().toUtc().toIso8601String()).limit(1);
    return r.isEmpty ? null : r.first['code'] as String;
  }

  @override
  Future<String> refreshInvite() => _rpc<String>('refresh_invite');

  @override
  Future<List<FamilyMember>> members() async {
    await ensureSignedIn();
    final r = await _c.from('family_members').select('user_id, role, display_name, avatar').order('joined_at');
    return [
      for (final m in r)
        FamilyMember(userId: m['user_id'], role: m['role'], name: m['display_name'], avatar: m['avatar']),
    ];
  }

  @override
  Future<void> leaveFamily() => _rpc<dynamic>('leave_family');

  @override
  Future<void> removeMember(String userId) => _rpc<dynamic>('remove_member', {'p_user_id': userId});

  @override
  Future<Map<String, dynamic>?> pullBaby(String familyId) =>
      _c.from('shared_babies').select().eq('family_id', familyId).maybeSingle();

  @override
  Future<void> pushBaby(Map<String, dynamic> b) => _rpc<dynamic>('push_baby', {
        'p_id': b['id'],
        'p_nickname': b['nickname'],
        'p_birth_date': b['birth_date'],
        'p_updated_at': b['updated_at'],
      });

  @override
  Future<void> pushCareLogs(List<Map<String, dynamic>> rows) => _rpc<dynamic>('push_care_logs', {'rows': rows});

  @override
  Future<void> pushCryEvents(List<Map<String, dynamic>> rows) => _rpc<dynamic>('push_cry_events', {'rows': rows});

  Future<List<Map<String, dynamic>>> _pull(String table, String familyId, String? since) async {
    var q = _c.from(table).select().eq('family_id', familyId);
    if (since != null) q = q.gt('server_updated_at', since);
    return List<Map<String, dynamic>>.from(await q.order('server_updated_at').limit(1000));
  }

  @override
  Future<List<Map<String, dynamic>>> pullCareLogs(String familyId, String? since) => _pull('shared_care_logs', familyId, since);

  @override
  Future<List<Map<String, dynamic>>> pullCryEvents(String familyId, String? since) => _pull('shared_cry_events', familyId, since);

  @override
  Future<void> upsertDevice({required String appVersion, required DateTime consentAt}) async {
    final uid = await ensureSignedIn();
    await _c.from('devices').upsert({'id': uid, 'app_version': appVersion, 'consent_at': consentAt.toUtc().toIso8601String()});
  }

  @override
  Future<void> upsertResearchBaby({required String id, required double ageMonths}) async {
    final uid = await ensureSignedIn();
    await _c.from('babies').upsert({'id': id, 'device_id': uid, 'age_months_at_upload': double.parse(ageMonths.toStringAsFixed(1))});
  }

  @override
  Future<String> uploadClip(String eventId, Uint8List wav) async {
    final uid = await ensureSignedIn();
    final path = '$uid/$eventId.wav';
    await _c.storage.from('cry-clips').uploadBinary(path, wav,
        fileOptions: const FileOptions(upsert: true, contentType: 'audio/wav'));
    return path;
  }

  @override
  Future<void> upsertResearchEvent(Map<String, dynamic> row) async {
    final uid = await ensureSignedIn();
    await _c.from('cry_events').upsert({...row, 'device_id': uid});
  }

  @override
  Future<void> upsertResearchFeedback(Map<String, dynamic> row) async {
    final uid = await ensureSignedIn();
    await _c.from('feedbacks').upsert({...row, 'device_id': uid});
  }

  @override
  Future<void> deleteMyResearchData() async {
    final uid = await ensureSignedIn();
    final bucket = _c.storage.from('cry-clips');
    while (true) {
      final files = await bucket.list(path: uid, searchOptions: const SearchOptions(limit: 100));
      if (files.isEmpty) break;
      await bucket.remove([for (final f in files) '$uid/${f.name}']);
      if (files.length < 100) break;
    }
    await _rpc<dynamic>('delete_my_research_data');
  }
}
