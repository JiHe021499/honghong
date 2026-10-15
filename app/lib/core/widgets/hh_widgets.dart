import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icon.dart';

/// 白色圆角卡片（设计稿 .card）
class HhCard extends StatelessWidget {
  const HhCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.onTap, this.radius = 20});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Container(
      decoration: BoxDecoration(
        color: color ?? c.card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [BoxShadow(color: c.shadow, blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// 分段选择（设计稿 .seg）
class HhSegmented<T> extends StatelessWidget {
  const HhSegmented({super.key, required this.values, required this.label, required this.selected, required this.onChanged});
  final List<T> values;
  final String Function(T) label;
  final T? selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.seg, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        for (final v in values)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: v == selected ? c.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: v == selected ? const [BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2))] : null,
                ),
                alignment: Alignment.center,
                child: Text(label(v),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: v == selected ? FontWeight.w700 : FontWeight.w400,
                        color: v == selected ? c.peach2 : c.ink)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// 小圆角选项（设计稿 .chips）
class HhChip extends StatelessWidget {
  const HhChip({super.key, required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: on ? c.peachL : c.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? c.peach : c.line),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 13, color: on ? c.peachDeep : c.ink, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }
}

/// 主按钮（蜜桃色）/ 次按钮（白底描边）
class HhButton extends StatelessWidget {
  const HhButton({super.key, required this.label, required this.onPressed, this.primary = true});
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: primary ? c.dnShadows(const [BoxShadow(color: Color(0x47FF7850), blurRadius: 18, offset: Offset(0, 6))], null) : null,
        ),
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: primary ? c.endBg : c.card,
            foregroundColor: primary ? c.endInk : c.ink,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: primary ? BorderSide.none : BorderSide(color: c.line, width: 1.5),
            ),
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

/// 进行中的脉冲点
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, this.size = 8});
  final double size;
  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 减少动态：停在静态实心点；否则 1.6s 一次脉冲（<3 次/秒，不闪烁）
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.hh.peach2;
    final dot = SizedBox.square(dimension: widget.size);
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return Container(
        key: const Key('pulse-dot-static'),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = (_c.value / .7).clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: .45 * (1 - t)), spreadRadius: 10 * t)],
          ),
          child: child,
        );
      },
      child: dot,
    );
  }
}

/// 底部面板顶部的小横条
class SheetGrab extends StatelessWidget {
  const SheetGrab({super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 5,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(color: const Color(0xFFDDD3C9), borderRadius: BorderRadius.circular(3)),
        ),
      );
}

/// 圆角方形底 + 手绘图标
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 30, this.bg, this.radius = 10, this.fontSize = 16});
  final AppIcon icon;
  final double size;
  final Color? bg;
  final double radius;
  final double fontSize;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg ?? context.hh.peachL, borderRadius: BorderRadius.circular(radius)),
        child: HhIcon(icon, size: fontSize * 1.4),
      );
}

Color typeTint(Hh c, String type) => switch (type) {
      'sleep' => c.blueL,
      'diaper' => c.greenL,
      _ => c.peachL,
    };
