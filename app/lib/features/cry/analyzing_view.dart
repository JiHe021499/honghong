import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';

/// 分析中的过渡（手绘风）：宝宝头像轻轻上下浮动，两侧手绘声波一圈圈荡开。
/// 系统开启"减少动态效果"时静止显示。
class AnalyzingView extends StatefulWidget {
  const AnalyzingView({super.key});
  static const text = '正在听听宝宝在说什么…';

  @override
  State<AnalyzingView> createState() => _AnalyzingViewState();
}

class _AnalyzingViewState extends State<AnalyzingView> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _a.stop();
      _a.value = .25;
    } else if (!_a.isAnimating) {
      _a.repeat();
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Semantics(
      liveRegion: true,
      label: AnalyzingView.text,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 220,
          height: 150,
          child: AnimatedBuilder(
            animation: _a,
            builder: (_, _) {
              final t = _a.value;
              return Stack(alignment: Alignment.center, children: [
                CustomPaint(size: const Size(220, 150), painter: _Waves(t, c.peach2)),
                Transform.translate(
                  offset: Offset(0, -6 * math.sin(2 * math.pi * t)),
                  child: Transform.rotate(angle: .05 * math.sin(2 * math.pi * t + 1), child: const HhIcon(AppIcon.avatarBaby, size: 84)),
                ),
              ]);
            },
          ),
        ),
        const SizedBox(height: 18),
        Text(AnalyzingView.text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
      ]),
    );
  }
}

/// 左右各三道略带抖动的弧线，从里往外依次变淡
class _Waves extends CustomPainter {
  _Waves(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1.0; // 0→1 往外走
      final r = 52 + 46 * phase;
      final alpha = (1 - phase) * (phase < .12 ? phase / .12 : 1);
      final paint = Paint()
        ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      for (final side in [-1.0, 1.0]) {
        final path = Path();
        const sweep = .9;
        const steps = 14;
        for (var k = 0; k <= steps; k++) {
          final a = (side < 0 ? math.pi : 0) - sweep / 2 + sweep * k / steps;
          final wobble = 1.2 * math.sin(k * .55 + i * 2.1); // 手绘感的轻微抖动
          final p = center + Offset(math.cos(a), math.sin(a)) * (r + wobble);
          k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Waves old) => old.t != t || old.color != color;
}
