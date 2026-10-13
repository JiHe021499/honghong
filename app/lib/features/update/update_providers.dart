import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/prefs.dart';
import '../../services/update/update_service.dart';

/// 只有安卓支持应用内更新（iOS 走 App Store / TestFlight）
bool get inAppUpdateSupported => !kIsWeb && Platform.isAndroid;

final packageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

final updateServiceProvider = FutureProvider<UpdateService>((ref) async {
  final info = await ref.watch(packageInfoProvider.future);
  return UpdateService(
    dio: Dio(BaseOptions(connectTimeout: const Duration(seconds: 8))),
    prefs: ref.watch(prefsProvider),
    currentCode: int.tryParse(info.buildNumber) ?? 0,
  );
});
