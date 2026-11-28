import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../services/tv_mode.dart';
import 'clapper_icon.dart';
import 'media_image.dart';

/// A Price-Is-Right-style prize wheel: labeled wedges, a fixed pointer at the
/// top, and a spin that decelerates into a landing with a peg-tick as each
/// wedge boundary passes. The outcome is chosen before the animation starts;
/// the deceleration curve just makes a predetermined stop feel like real
/// momentum and friction.
///
/// The wheel keeps its own state across changes to [items]: a removed title's
/// wedge shrinks away while its neighbours close the gap (and a re-added one
/// grows back), with the wedge under the pointer held steady throughout.
class SpinWheel extends StatefulWidget {
  final List<BaseItemDto> items;
  final double size;

  /// Called once the wheel has fully stopped, with the index into [items]
  /// the pointer landed on.
  final ValueChanged<int> onLanded;

  /// Called when wedges finish shrinking away or growing in after [items]
  /// changed.
  final VoidCallback? onSettled;

  /// Called each time a peg passes under the pointer (the tick sound).
  final VoidCallback? onTick;

  /// Landings per item id, drawn as stars on that wedge.
  final Map<String, int> marks;

  /// Holds the remote's focus (TV): draws the focus ring around the wheel
  /// itself, since the generic rectangular ring doesn't fit a circle.
  final bool focused;

  const SpinWheel({
    super.key,
    required this.items,
    required this.onLanded,
    this.onSettled,
    this.onTick,
    this.size = 320,
    this.marks = const {},
    this.focused = false,
  });

  @override
  State<SpinWheel> createState() => SpinWheelState();
}

class _Entry {
  _Entry(this.item, this.color, {this.from = 1, this.to = 1});
  BaseItemDto item;
  final Color color;
  double from;
  double to;
  double weight(double t) => from + (to - from) * t;
}

class _Geometry {
  const _Geometry(this.starts, this.sweeps);
  final List<double> starts;
  final List<double> sweeps;
}

class SpinWheelState extends State<SpinWheel> with TickerProviderStateMixin {
  static const _pointerAngle = -math.pi / 2; // top, in canvas convention

  // A fixed, high-contrast palette, independent of the theme accent. Each
  // title keeps its colour for the whole session, even as others drop out.
  static const _palette = [
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFF22C55E),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
  ];

  final _angle = ValueNotifier<double>(0);
  final _random = math.Random();
  final List<_Entry> _entries = [];
  final Map<String, Color> _colors = {};

  // Rasterizes the wheel while it spins (see the SnapshotWidget below).
  final _snapshot = SnapshotController();

  late final AnimationController _spinCtl;
  Animation<double>? _spinAnim;
  bool _spinning = false;

  late final AnimationController _layoutCtl;
  late final CurvedAnimation _layoutCurve;
  int? _pinned;
  double _pinFraction = 0.5;
  double _pinBase = 0;

  late final AnimationController _highlightCtl;
  int? _highlighted;

  late final AnimationController _flapCtl;
  late final Animation<double> _flap;
  late final AnimationController _hourglassCtl;

  bool _dragging = false;
  double _lastDragAngle = 0;
  Offset _lastDragPos = Offset.zero;

  int _lastSegment = -1;
  double _speed = 0; // rad/s, smoothed
  double _speedAngle = 0;
  int _speedMicros = 0;
  int _hapticMicros = -1000000;
  final _clock = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    for (final item in widget.items) {
      _entries.add(_Entry(item, _colorFor(item.id)));
    }
    _spinCtl = AnimationController(vsync: this)
      ..addListener(() {
        final a = _spinAnim;
        if (a != null) _angle.value = a.value;
      });
    _layoutCtl = AnimationController(vsync: this)
      ..addListener(_onLayoutTick)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _finishLayout();
      });
    _layoutCurve =
        CurvedAnimation(parent: _layoutCtl, curve: Curves.easeInOutCubic);
    _highlightCtl = AnimationController(vsync: this);
    _flapCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    // Knocked up fast, springs back past rest and settles, like a real
    // spring-loaded flapper rather than a linear snap.
    _flap = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -0.45)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -0.45, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 65,
      ),
    ]).animate(_flapCtl);
    _hourglassCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _angle.addListener(_onAngleChanged);
  }

  @override
  void dispose() {
    _angle.dispose();
    _spinCtl.dispose();
    _snapshot.dispose();
    _layoutCurve.dispose();
    _layoutCtl.dispose();
    _highlightCtl.dispose();
    _flapCtl.dispose();
    _hourglassCtl.dispose();
    super.dispose();
  }

  Color _colorFor(String id) =>
      _colors.putIfAbsent(id, () => _palette[_colors.length % _palette.length]);

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// True while spinning, highlighting a landing, or reshaping wedges.
  bool get isBusy =>
      _spinning || _layoutCtl.isAnimating || _highlightCtl.isAnimating;

  _Geometry _geometry() {
    final t = _layoutCurve.value;
    final weights = [for (final e in _entries) e.weight(t)];
    final total = weights.fold<double>(0, (a, b) => a + b);
    final starts = <double>[];
    final sweeps = <double>[];
    var acc = 0.0;
    for (final w in weights) {
      final sweep = total <= 0 ? 0.0 : w / total * 2 * math.pi;
      starts.add(acc);
      sweeps.add(sweep);
      acc += sweep;
    }
    return _Geometry(starts, sweeps);
  }

  /// The wedge under the fixed top pointer for a wheel rotation [theta].
  int _segmentAt(double theta, _Geometry g) {
    final a = (_pointerAngle - theta) % (2 * math.pi);
    for (var i = 0; i < g.starts.length; i++) {
      if (g.sweeps[i] <= 0) continue;
      if (a >= g.starts[i] && a < g.starts[i] + g.sweeps[i]) return i;
    }
    return g.starts.length - 1;
  }

  // ---- Reshaping when items change ----

  @override
  void didUpdateWidget(covariant SpinWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final byId = {for (final i in widget.items) i.id: i};
    for (final e in _entries) {
      final fresh = byId[e.item.id];
      if (fresh != null) e.item = fresh;
    }
    final newIds = [for (final i in widget.items) i.id];
    final liveIds = [for (final e in _entries) if (e.to > 0) e.item.id];
    if (listEquals(newIds, liveIds)) return;
    _reshape(newIds, byId);
  }

  void _reshape(List<String> newIds, Map<String, BaseItemDto> byId) {
    // Settle wherever a previous reshape had got to, then start fresh.
    final t = _layoutCurve.value;
    _pinned = null;
    for (final e in _entries) {
      final w = e.weight(t);
      e.from = w;
      e.to = w;
    }
    _entries.removeWhere((e) => e.from <= 0.0001 && !byId.containsKey(e.item.id));
    _layoutCtl.stop();
    _layoutCtl.value = 0;

    for (final e in _entries) {
      e.to = byId.containsKey(e.item.id) ? 1 : 0;
    }
    for (var k = 0; k < newIds.length; k++) {
      final id = newIds[k];
      if (_entries.any((e) => e.item.id == id)) continue;
      final prev = k == 0
          ? -1
          : _entries.indexWhere((e) => e.item.id == newIds[k - 1]);
      _entries.insert(prev + 1, _Entry(byId[id]!, _colorFor(id), from: 0, to: 1));
    }

    // Hold whichever wedge is under the pointer steady, at the same spot
    // within it, so a knocked-out wedge shrinks away right under the pointer
    // and a sole survivor grows out from it.
    final g = _geometry();
    if (g.starts.isNotEmpty) {
      final k = _segmentAt(_angle.value, g);
      if (k >= 0 && g.sweeps[k] > 0) {
        final a = (_pointerAngle - _angle.value) % (2 * math.pi);
        _pinned = k;
        _pinFraction = ((a - g.starts[k]) / g.sweeps[k]).clamp(0.0, 1.0);
        _pinBase = _angle.value -
            (_pointerAngle - (g.starts[k] + _pinFraction * g.sweeps[k]));
      }
    }
    _layoutCtl.duration = Duration(milliseconds: _reduceMotion ? 200 : 700);
    _layoutCtl.forward(from: 0);
  }

  void _onLayoutTick() {
    final k = _pinned;
    if (k == null || k >= _entries.length) return;
    final g = _geometry();
    _angle.value = _pinBase +
        _pointerAngle -
        (g.starts[k] + _pinFraction * g.sweeps[k]);
  }

  void _finishLayout() {
    _entries.removeWhere((e) => e.to <= 0);
    for (final e in _entries) {
      e.from = 1;
      e.to = 1;
    }
    _pinned = null;
    _lastSegment = _entries.isEmpty ? -1 : _segmentAt(_angle.value, _geometry());
    if (mounted) setState(() {});
    widget.onSettled?.call();
  }

  // ---- Ticks, speed, sound ----

  void _onAngleChanged() {
    final now = _clock.elapsedMicroseconds;
    final dt = (now - _speedMicros) / 1e6;
    if (dt > 0) {
      final inst = (_angle.value - _speedAngle).abs() / dt;
      _speed = dt > 0.2 ? inst : _speed * 0.6 + inst * 0.4;
    }
    _speedMicros = now;
    _speedAngle = _angle.value;

    if (_layoutCtl.isAnimating || _entries.length < 2) return;
    final seg = _segmentAt(_angle.value, _geometry());
    if (seg != _lastSegment) {
      _lastSegment = seg;
      // A fast spin crosses wedges dozens of times a second, and on a phone
      // every haptic is a platform round trip plus a real vibration: firing one
      // per crossing was enough to cost frames (and buzz continuously). The
      // pegs still tick and flap at full rate; only the buzz is rationed, which
      // is also closer to how a real wheel feels.
      if (now - _hapticMicros >= 60000) {
        _hapticMicros = now;
        HapticFeedback.selectionClick();
      }
      _flapCtl.forward(from: 0);
      widget.onTick?.call();
    }
  }

  // ---- Spinning ----

  /// Spins to a random wedge. [velocity] (rad/s, sign = direction) comes
  /// from a flick: a harder flick means more turns and a longer spin. A tap
  /// or the remote's Select spins clockwise at normal strength.
  Future<void> spin({double? velocity}) async {
    if (isBusy || _dragging || _entries.length < 2) return;
    final reduce = _reduceMotion;
    final dir = (velocity ?? 1) >= 0 ? 1.0 : -1.0;
    final strength =
        velocity == null ? 1.0 : (velocity.abs() / 14).clamp(0.55, 1.4);
    setState(() => _spinning = true);
    _snapshot.allowSnapshotting = true;
    if (!reduce) _hourglassCtl.repeat();

    final g = _geometry();
    final target = _random.nextInt(_entries.length);
    // Land within the middle 70% of the wedge, never right on a boundary.
    final frac = 0.5 + (_random.nextDouble() - 0.5) * 0.7;
    final point = g.starts[target] + g.sweeps[target] * frac;
    final start = _angle.value;
    var rest = (_pointerAngle - point - start) % (2 * math.pi);
    if (dir < 0) rest -= 2 * math.pi;
    final turns = reduce ? 2 : (9 * strength).round() + _random.nextInt(3);
    final ms = reduce
        ? 1600
        : ((7000 + _random.nextInt(1000)) * (0.75 + 0.25 * strength)).round();

    _lastSegment = _segmentAt(start, g);
    _spinCtl.duration = Duration(milliseconds: ms);
    _spinAnim = Tween<double>(
      begin: start,
      end: start + rest + dir * 2 * math.pi * turns,
    ).animate(CurvedAnimation(parent: _spinCtl, curve: Curves.easeOutQuint));
    await _spinCtl.forward(from: 0);
    _snapshot.allowSnapshotting = false;
    _spinAnim = null;
    _hourglassCtl
      ..stop()
      ..reset();
    _speed = 0;
    if (!mounted) return;

    setState(() {
      _spinning = false;
      _highlighted = target;
    });
    HapticFeedback.mediumImpact();
    _highlightCtl.duration = Duration(milliseconds: reduce ? 450 : 1150);
    await _highlightCtl.forward(from: 0);
    if (!mounted) return;
    setState(() => _highlighted = null);
    final id = _entries[target].item.id;
    final index = widget.items.indexWhere((e) => e.id == id);
    if (index >= 0) widget.onLanded(index);
  }

  // ---- Flick to spin ----

  Offset get _center => Offset(widget.size / 2, 24 + widget.size / 2);

  double _angleOf(Offset p) => math.atan2(p.dy - _center.dy, p.dx - _center.dx);

  void _onPanStart(DragStartDetails d) {
    if (isBusy || _entries.length < 2) return;
    _dragging = true;
    _lastDragPos = d.localPosition;
    _lastDragAngle = _angleOf(d.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    final a = _angleOf(d.localPosition);
    var delta = a - _lastDragAngle;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    _lastDragAngle = a;
    _lastDragPos = d.localPosition;
    _angle.value += delta;
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    // Angular velocity from the release: the tangential part of the finger's
    // velocity over its distance from the hub (clamped so a release right
    // on the hub can't read as an absurd spin).
    final r = _lastDragPos - _center;
    final dist2 = math.max(r.distanceSquared, 60.0 * 60.0);
    final v = d.velocity.pixelsPerSecond;
    final omega = (r.dx * v.dy - r.dy * v.dx) / dist2;
    if (omega.abs() >= 3) spin(velocity: omega);
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final reduce = _reduceMotion;
    // Measured on a 120Hz phone (2026-09-12): the blur costs nothing there, so
    // it stays on everywhere but TV. The first spin after launch is the janky
    // one with or without it, which is warm-up, not the filter.
    final blurAllowed = !reduce && !isTvDevice;
    final l = AppLocalizations.of(context);
    // One screen-reader stop that names the wheel and its titles, and spins
    // on the reader's activate gesture (the drawing itself says nothing).
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: '${l.a11yWheel(_entries.length)}: '
          '${_entries.map((e) => e.item.name).join(', ')}',
      onTapHint: l.a11ySpin,
      onTap: isBusy ? null : () => spin(),
      child: GestureDetector(
      onTap: isBusy ? null : () => spin(),
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onPanCancel: () => _dragging = false,
      child: SizedBox(
        width: size,
        height: size + 24,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            // A soft shadow under the wheel; it doesn't turn with it.
            Positioned(
              top: 24,
              child: IgnorePointer(
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 24,
              child: AnimatedBuilder(
                animation: _angle,
                builder: (context, child) {
                  // A light blur while it's really moving, fading out as it
                  // slows, like a camera catching a fast-spinning wheel.
                  // Quantized: a sigma that drifts by a hair every frame is a
                  // different filter every frame, so nothing downstream can be
                  // reused. In quarter steps it holds still for a stretch of
                  // frames at a time, and the streak looks identical.
                  final raw = blurAllowed && _spinning
                      ? ((_speed - 10) / 8).clamp(0.0, 3.0)
                      : 0.0;
                  final sigma = (raw * 4).roundToDouble() / 4;
                  return Transform.rotate(
                    angle: _angle.value,
                    child: ClipOval(
                      child: ImageFiltered(
                        enabled: sigma > 0.05,
                        imageFilter:
                            ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                        child: child,
                      ),
                    ),
                  );
                },
                // The wheel's painting doesn't change while it turns, only
                // its angle does, yet every frame was repainting each wedge's
                // clipped poster, the fills and the labels: measured at ~4.4ms
                // a frame on a 120Hz phone, against an 8.3ms budget. Snapshot
                // it for the duration of the spin instead, so those frames
                // rotate one texture. Switched off again the moment the wheel
                // stops, since the landing highlight really does repaint.
                child: SnapshotWidget(
                  controller: _snapshot,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_layoutCtl, _highlightCtl]),
                    builder: (context, _) => _content(),
                  ),
                ),
              ),
            ),
            // A glossy highlight fixed to the screen, not the wheel, so it
            // reads as light catching a physical spinning surface.
            Positioned(
              top: 24,
              child: IgnorePointer(
                child: ClipOval(
                  child: Container(
                    width: size,
                    height: size,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0x30FFFFFF),
                          Color(0x0CFFFFFF),
                          Color(0x00000000),
                          Color(0x1F000000),
                        ],
                        stops: [0, 0.32, 0.6, 1],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.focused)
              Positioned(
                top: 24,
                child: IgnorePointer(
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.75),
                          blurRadius: 22,
                          spreadRadius: 1,
                          // Outside the ring only. A shadow is a filled
                          // shape, and this ring has nothing inside it to
                          // cover one: the glow washed over the whole wheel,
                          // posters and titles with it.
                          blurStyle: BlurStyle.outer,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Fixed pointer; flaps on its own each time a peg passes.
            Positioned(top: 0, child: _Pointer(flap: _flap)),
            Positioned(
              top: 24 + size / 2 - 34,
              child: _Hub(
                spinning: _spinning,
                hourglass: _hourglassCtl,
                animate: !reduce,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _content() {
    final size = widget.size;
    final g = _geometry();
    final t = _layoutCurve.value;
    final hl = _highlighted;
    // Posters request one resolution per wheel size, stepped so a window
    // resize doesn't refetch on every pixel and a wedge reshaping never
    // changes the URL mid-animation.
    final reqHeight = ((size * 1.6 / 240).ceil() * 240).clamp(480, 1200);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Palette fill, the fallback behind each poster while it loads.
          CustomPaint(
            size: Size.square(size),
            painter: _WheelFillPainter(
              starts: g.starts,
              sweeps: g.sweeps,
              colors: [for (final e in _entries) e.color],
            ),
          ),
          for (var i = 0; i < _entries.length; i++)
            if (g.sweeps[i] > 0.002)
              Positioned.fill(
                key: ValueKey('poster-${_entries[i].item.id}'),
                child: ClipPath(
                  clipper: _WedgeClipper(start: g.starts[i], sweep: g.sweeps[i]),
                  // A fresh Stack so the poster's own Positioned (placed in
                  // full-wheel coordinates) has a direct Stack ancestor.
                  child: Stack(
                    children: [
                      _WedgePoster(
                        item: _entries[i].item,
                        start: g.starts[i],
                        sweep: g.sweeps[i],
                        wheelSize: size,
                        requestHeight: reqHeight,
                      ),
                    ],
                  ),
                ),
              ),
          // Center-to-rim darkening so titles and lines stay legible.
          IgnorePointer(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
          ),
          if (hl != null && hl < _entries.length)
            CustomPaint(
              size: Size.square(size),
              painter: _HighlightPainter(
                start: g.starts[hl],
                sweep: g.sweeps[hl],
                t: _highlightCtl.value,
              ),
            ),
          CustomPaint(
            size: Size.square(size),
            painter: _WheelLinesPainter(starts: g.starts, sweeps: g.sweeps),
          ),
          for (var i = 0; i < _entries.length; i++)
            if (g.sweeps[i] > 0.05)
              _WedgeTitle(
                key: ValueKey('title-${_entries[i].item.id}'),
                item: _entries[i].item,
                start: g.starts[i],
                sweep: g.sweeps[i],
                wheelSize: size,
                opacity: _entries[i].weight(t).clamp(0.0, 1.0),
                marks: widget.marks[_entries[i].item.id] ?? 0,
              ),
        ],
      ),
    );
  }
}

class _Pointer extends StatelessWidget {
  final Animation<double> flap;
  const _Pointer({required this.flap});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: flap,
      builder: (context, child) => Transform.rotate(
        // Pivots from the top, like it's hinged there.
        alignment: Alignment.topCenter,
        angle: flap.value,
        child: child,
      ),
      child: CustomPaint(
        size: const Size(28, 30),
        painter: _PointerPainter(),
      ),
    );
  }
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFD54A));
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Hub extends StatelessWidget {
  final bool spinning;
  final Animation<double> hourglass;
  final bool animate;
  const _Hub({
    required this.spinning,
    required this.hourglass,
    required this.animate,
  });

  static const _sand = Color(0xFFFFD54A);

  BoxDecoration _decoration({double glow = 0}) => BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF16151A),
        border: Border.all(
          color: Color.lerp(Colors.white24, _sand, glow * 0.8)!,
          width: 3,
        ),
        boxShadow: [
          const BoxShadow(
              color: Colors.black54, blurRadius: 10, offset: Offset(0, 3)),
          if (glow > 0)
            BoxShadow(
              color: _sand.withValues(alpha: 0.18 + 0.32 * glow),
              blurRadius: 14 + 12 * glow,
              spreadRadius: 1 + 3 * glow,
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (!spinning || !animate) {
      return Container(
        width: 68,
        height: 68,
        decoration: _decoration(glow: spinning ? 0.6 : 0),
        alignment: Alignment.center,
        child: spinning
            ? const Icon(Icons.hourglass_top_rounded, color: _sand, size: 30)
            : const ClapperIcon(size: 28, color: Colors.white),
      );
    }
    return AnimatedBuilder(
      animation: hourglass,
      builder: (context, _) {
        // One loop is a real hourglass cycle: the sand runs from the top
        // bulb to the bottom (a smooth crossfade top -> both -> bottom),
        // then the glass is turned over. A bottom-filled hourglass rotated
        // 180deg IS a top-filled one, so the loop restarts seamlessly.
        final t = hourglass.value;
        const runEnd = 0.7;
        var angle = 0.0;
        var scale = 1.0;
        double top, full, bottom;
        if (t < runEnd) {
          final p = Curves.easeInOut.transform(t / runEnd);
          top = (1 - p * 2).clamp(0.0, 1.0);
          bottom = (p * 2 - 1).clamp(0.0, 1.0);
          full = 1 - top - bottom;
        } else {
          final p = (t - runEnd) / (1 - runEnd);
          angle = Curves.easeInOutCubic.transform(p) * math.pi;
          scale = 1 + 0.18 * math.sin(p * math.pi);
          top = 0;
          full = 0;
          bottom = 1;
        }
        // The rim glow breathes once per cycle, brightest mid-flip.
        final glow = 0.5 + 0.5 * math.cos(2 * math.pi * (t - 0.85));
        Widget layer(IconData icon, double opacity) => Opacity(
              opacity: opacity,
              child: Icon(icon, color: _sand, size: 30),
            );
        return Container(
          width: 68,
          height: 68,
          decoration: _decoration(glow: glow),
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scale: scale,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (top > 0) layer(Icons.hourglass_top_rounded, top),
                  if (full > 0) layer(Icons.hourglass_full_rounded, full),
                  if (bottom > 0) layer(Icons.hourglass_bottom_rounded, bottom),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Path _wedgePath(Offset center, double radius, double start, double sweep) {
  if (sweep >= 2 * math.pi - 1e-6) {
    return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  }
  return Path()
    ..moveTo(center.dx, center.dy)
    ..arcTo(Rect.fromCircle(center: center, radius: radius), start, sweep, false)
    ..close();
}

/// Flat palette fill per wedge, painted first as the fallback behind each
/// poster, visible while it's still loading.
class _WheelFillPainter extends CustomPainter {
  final List<double> starts;
  final List<double> sweeps;
  final List<Color> colors;
  const _WheelFillPainter({
    required this.starts,
    required this.sweeps,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    for (var i = 0; i < starts.length; i++) {
      if (sweeps[i] <= 0) continue;
      canvas.drawPath(
        _wedgePath(center, radius, starts[i], sweeps[i]),
        Paint()..color = colors[i],
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Dividers, rim, and pegs, painted on top of the poster art so they stay
/// crisp regardless of what's underneath.
class _WheelLinesPainter extends CustomPainter {
  final List<double> starts;
  final List<double> sweeps;
  const _WheelLinesPainter({required this.starts, required this.sweeps});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final visible = sweeps.where((s) => s > 0).length;

    if (visible > 1) {
      final divider = Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = 2;
      for (var i = 0; i < starts.length; i++) {
        if (sweeps[i] <= 0) continue;
        final a = starts[i];
        canvas.drawLine(
          center,
          center + Offset(math.cos(a), math.sin(a)) * radius,
          divider,
        );
      }
    }

    // Rim as a filled ring path, not a stroked drawCircle: on Impeller a
    // stroked circle past a certain radius renders as a thick opaque band
    // that buried everything painted under it.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: center, radius: radius))
        ..addOval(Rect.fromCircle(center: center, radius: radius - 4)),
      Paint()..color = const Color(0xFF16151A),
    );

    if (visible > 1) {
      final pegPaint = Paint()..color = const Color(0xFFFFD54A);
      for (var i = 0; i < starts.length; i++) {
        if (sweeps[i] <= 0) continue;
        final a = starts[i];
        canvas.drawCircle(
          center + Offset(math.cos(a), math.sin(a)) * (radius - 4),
          4,
          pegPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// The landed wedge pulsing gold while everything else dims, for a beat
/// before the result is announced.
class _HighlightPainter extends CustomPainter {
  final double start;
  final double sweep;
  final double t;
  const _HighlightPainter({
    required this.start,
    required this.sweep,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final env = t < 0.15 ? t / 0.15 : (t > 0.85 ? (1 - t) / 0.15 : 1.0);
    final pulse = 0.5 + 0.5 * math.sin(t * 4 * math.pi - math.pi / 2);
    final wedge = _wedgePath(center, radius, start, sweep);

    // Everything but the landed wedge: the circle with the wedge cut out.
    final others = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..addPath(wedge, Offset.zero);
    canvas.drawPath(
        others, Paint()..color = Colors.black.withValues(alpha: 0.5 * env));
    canvas.drawPath(
      wedge,
      Paint()..color = Colors.white.withValues(alpha: 0.22 * pulse * env),
    );
    canvas.drawPath(
      wedge,
      Paint()
        ..color = const Color(0xFFFFD54A).withValues(alpha: env)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5 + 3 * pulse
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _HighlightPainter oldDelegate) => true;
}

/// Clips a child to one wedge's pie-slice shape, matching the painters.
class _WedgeClipper extends CustomClipper<Path> {
  final double start;
  final double sweep;
  const _WedgeClipper({required this.start, required this.sweep});

  @override
  Path getClip(Size size) =>
      _wedgePath(size.center(Offset.zero), size.width / 2, start, sweep);

  @override
  bool shouldReclip(covariant _WedgeClipper oldClipper) =>
      oldClipper.start != start || oldClipper.sweep != sweep;
}

/// The wedge's poster art in the smallest 2:3 box that still covers the
/// wedge, so as much of the art as possible shows. In the wedge's own frame
/// (bisector pointing outward) its bounding rect runs from the hub (or, for a
/// wedge wider than a half circle, from behind it) to the rim, and
/// +-r*sin(sweep/2) across. The small margin keeps anti-aliased clip edges
/// from showing a hairline.
class _WedgePoster extends StatelessWidget {
  final BaseItemDto item;
  final double start;
  final double sweep;
  final double wheelSize;
  final int requestHeight;
  const _WedgePoster({
    required this.item,
    required this.start,
    required this.sweep,
    required this.wheelSize,
    required this.requestHeight,
  });

  @override
  Widget build(BuildContext context) {
    final mid = start + sweep / 2;
    final half = sweep / 2;
    final radius = wheelSize / 2;
    final radialMin = half <= math.pi / 2 ? 0.0 : radius * math.cos(half);
    final rectW = half <= math.pi / 2 ? 2 * radius * math.sin(half) : 2 * radius;
    final rectH = radius - radialMin;
    final boxW = math.max(rectW, rectH * 2 / 3) * 1.04 + 2;
    final boxH = boxW * 1.5;
    final along = (radius + radialMin) / 2;
    final cx = radius + math.cos(mid) * along;
    final cy = radius + math.sin(mid) * along;
    return Positioned(
      left: cx - boxW / 2,
      top: cy - boxH / 2,
      width: boxW,
      height: boxH,
      child: Transform.rotate(
        angle: mid + math.pi / 2,
        child: MediaImage(
          item: item,
          maxHeight: requestHeight,
          // Medium (bilinear + mipmaps), not high (bicubic): the posters are
          // drawn at roughly their own size, so the two are hard to tell apart
          // even at rest, and bicubic is resampled per poster per frame while
          // the wheel turns, which a phone GPU feels and a desktop one doesn't.
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

/// The wedge's title near the outer rim, rotated to point outward like the
/// poster beneath it, sized to the room its wedge has.
class _WedgeTitle extends StatelessWidget {
  final BaseItemDto item;
  final double start;
  final double sweep;
  final double wheelSize;
  final double opacity;
  final int marks;
  const _WedgeTitle({
    super.key,
    required this.item,
    required this.start,
    required this.sweep,
    required this.wheelSize,
    required this.opacity,
    required this.marks,
  });

  @override
  Widget build(BuildContext context) {
    final mid = start + sweep / 2;
    final radius = wheelSize / 2;
    final share = sweep / (2 * math.pi);
    final labelRadius = radius * 0.76;
    // The text runs across the wedge, so its room is the wedge's actual
    // width at the label's distance from the hub. A fixed pixel cap cut long
    // titles short on a big wheel with plenty of space, and the cut moved
    // around as other titles dropped out.
    final chord = sweep >= math.pi
        ? 2 * labelRadius
        : 2 * labelRadius * math.sin(sweep / 2);
    final labelWidth = (chord * 0.8).clamp(56.0, radius * 1.2);
    final fontSize = ((12.0 + 36.0 * share) * (radius / 200).clamp(0.9, 1.6))
        .clamp(10.0, 28.0);
    const shadows = [
      Shadow(color: Colors.black, blurRadius: 4),
      Shadow(color: Colors.black87, blurRadius: 8),
    ];
    return Positioned(
      left: radius + math.cos(mid) * labelRadius - labelWidth / 2,
      top: radius + math.sin(mid) * labelRadius - fontSize,
      width: labelWidth,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: mid + math.pi / 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (marks > 0)
                Text(
                  '★' * marks,
                  style: TextStyle(
                    color: const Color(0xFFFFD54A),
                    fontSize: fontSize,
                    shadows: shadows,
                  ),
                ),
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  shadows: shadows,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
