import 'dart:math';

import 'package:flutter/material.dart';

import 'motion.dart';

/// Three little bars that bounce while audio plays and hold still when paused —
/// the "now playing" indicator on a track row. [playing] drives the animation.
class EqualizerBars extends StatefulWidget {
  final bool playing;
  final Color color;
  final double size;
  const EqualizerBars({
    super.key,
    required this.playing,
    required this.color,
    this.size = 18,
  });

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// Reduced motion: the bars stand still, at a height that still reads
  /// as "playing".
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = stillIfReduced(context, _c, at: 0.35);
    if (!_still && widget.playing && !_c.isAnimating) _c.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (_still) return;
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barW = widget.size / 5;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) SizedBox(width: barW * 0.6),
              _bar(i, barW),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bar(int i, double barW) {
    // Each bar oscillates on its own phase; paused holds a steady mid height.
    final phase = i * (pi / 2.2);
    final frac = widget.playing
        ? 0.3 + 0.7 * (0.5 + 0.5 * sin(_c.value * 2 * pi + phase))
        : 0.5;
    return Container(
      width: barW,
      height: widget.size * frac,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(barW / 2),
      ),
    );
  }
}
