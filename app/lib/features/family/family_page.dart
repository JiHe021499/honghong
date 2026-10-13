import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../insights/insights_page.dart';

/// 家庭（第二阶段才做同步，先占位）
class FamilyPage extends StatelessWidget {
  const FamilyPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Text('家庭', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.ink)),
            const SizedBox(height: 16),
            const FamilyCard(),
            const SizedBox(height: 14),
            Text('以后可以邀请爸爸、妈妈、老人一起记录，交班不用口头说。', style: TextStyle(fontSize: 13, color: c.sub, height: 1.6)),
          ],
        ),
      ),
    );
  }
}
