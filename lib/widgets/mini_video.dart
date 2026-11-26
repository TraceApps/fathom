import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/pip_controller.dart';
import '../state/popout_controller.dart';
import '../state/preferences.dart';

/// Gap between the mini player and the window edges.
const double _margin = 16;

/// The mini player is a single fixed 16:9 size (the largest we offer).
const double _miniW = 416;
const double _miniH = 234;

/// A floating mini-video (picture-in-picture) shown in the shell when a video is
/// minimized, so it keeps playing while you browse. Tap it to return to the full
/// watch page; drag it anywhere (it stays where you drop it); the X closes it.
class MiniVideo extends ConsumerStatefulWidget {
  const MiniVideo({super.key});

  @override
  ConsumerState<MiniVideo> createState() => _MiniVideoState();
}

class _MiniVideoState extends ConsumerState<MiniVideo> {
  /// Top-left while actively dragging; null means resolved from the saved
  /// fractional position.
  Offset? _dragPos;

  /// The horizontal/vertical travel available to the card's top-left. Clamped to
  /// at least 1 so the fraction maths never divides by zero in a tiny window.
  double _freeW(Size bounds, double w) =>
      (bounds.width - w - _margin * 2).clamp(1, double.infinity);
  double _freeH(Size bounds, double h) =>
      (bounds.height - h - _margin * 2).clamp(1, double.infinity);

  /// Top-left for a saved 0..1 position within a [bounds]-sized area.
  Offset _posFor(double fx, double fy, Size bounds, double w, double h) =>
      Offset(_margin + fx.clamp(0, 1) * _freeW(bounds, w),
          _margin + fy.clamp(0, 1) * _freeH(bounds, h));

  /// Reopen the source screen and reclaim the live player. Runs from this
  /// (persistent) State, not the card, whose context unmounts the moment the
  /// dock hides. Hides the dock first so the controller is free, then navigates
  /// on the next frame.
  void _reopen(String route, Object? extra, String matchId) {
    if (matchId.isEmpty) return;
    ref.read(pipProvider.notifier).beginReclaim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.push(route, extra: extra);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pip = ref.watch(pipProvider);
    final notifier = ref.read(pipProvider.notifier);
    final controller = notifier.controller;
    final player = notifier.player;
    if (!pip.active || pip.reclaiming || controller == null || player == null) {
      // Stay a *positioned* child even when hidden: a non-positioned child in an
      // otherwise all-positioned Stack collapses the Stack to zero size, which
      // blanks the whole shell.
      return const Positioned(right: 16, bottom: 16, child: SizedBox.shrink());
    }

    // Popped out to the desktop: that window shows the video, so the in-app mini
    // steps aside (two Video widgets can't share one controller cleanly).
    if (ref.watch(popoutProvider)) {
      return const Positioned(right: 16, bottom: 16, child: SizedBox.shrink());
    }

    final fx = ref.watch(
        preferencesProvider.select((p) => p.asData?.value.miniPlayerX)) ??
        1.0;
    final fy = ref.watch(
        preferencesProvider.select((p) => p.asData?.value.miniPlayerY)) ??
        1.0;
    const size = (w: _miniW, h: _miniH);

    // Fill the shell to get a coordinate space, then position the one card
    // inside. Empty areas of this Stack don't absorb pointers, so the rest of
    // the shell stays interactive.
    return Positioned.fill(
      child: LayoutBuilder(builder: (context, box) {
        final bounds = box.biggest;
        final pos = _dragPos ?? _posFor(fx, fy, bounds, size.w, size.h);
        return Stack(
          children: [
            Positioned(
              left: pos.dx,
              top: pos.dy,
              width: size.w,
              height: size.h,
              child: GestureDetector(
                // Drag to move freely; a plain tap (no drag) reopens the watch
                // page. It stays wherever you drop it.
                onPanUpdate: (d) {
                  final start =
                      _dragPos ?? _posFor(fx, fy, bounds, size.w, size.h);
                  final next = start + d.delta;
                  // Clamp within the margins, but guard the case where the card
                  // is wider/taller than the window (upper < lower) so clamp
                  // doesn't assert; then just pin to the margin.
                  final maxX = bounds.width - size.w - _margin;
                  final maxY = bounds.height - size.h - _margin;
                  setState(() {
                    _dragPos = Offset(
                      maxX <= _margin
                          ? _margin
                          : next.dx.clamp(_margin, maxX),
                      maxY <= _margin
                          ? _margin
                          : next.dy.clamp(_margin, maxY),
                    );
                  });
                },
                onPanEnd: (_) {
                  final dropped = _dragPos;
                  if (dropped == null) return;
                  // Persist as a 0..1 fraction of the free space so it holds its
                  // spot across window resizes.
                  final nfx =
                      ((dropped.dx - _margin) / _freeW(bounds, size.w))
                          .clamp(0.0, 1.0);
                  final nfy =
                      ((dropped.dy - _margin) / _freeH(bounds, size.h))
                          .clamp(0.0, 1.0);
                  ref.read(preferencesProvider.notifier).edit((p) =>
                      p.copyWith(miniPlayerX: nfx, miniPlayerY: nfy));
                  setState(() => _dragPos = null);
                },
                child: _MiniCard(
                  pip: pip,
                  notifier: notifier,
                  controller: controller,
                  player: player,
                  onReopen: () =>
                      _reopen(pip.route, notifier.routeExtra, pip.matchId),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _MiniCard extends ConsumerStatefulWidget {
  final PipState pip;
  final PipController notifier;
  final VideoController controller;
  final Player player;
  final VoidCallback onReopen;

  const _MiniCard({
    required this.pip,
    required this.notifier,
    required this.controller,
    required this.player,
    required this.onReopen,
  });

  @override
  ConsumerState<_MiniCard> createState() => _MiniCardState();
}

class _MiniCardState extends ConsumerState<_MiniCard> {
  bool _visible = true;
  Timer? _hideTimer;

  // Desktop reveals the chrome on pointer activity and fades it after a short
  // idle (even while the cursor rests over the card). Touch has no hover, so
  // there the chrome stays put and a tap still reopens the watch page.
  bool get _hoverPlatform =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  void _show() {
    if (!_visible) setState(() => _visible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void initState() {
    super.initState();
    if (_hoverPlatform) _show(); // brief reveal on open, then auto-hide
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final pip = widget.pip;
    final notifier = widget.notifier;
    final controller = widget.controller;
    final player = widget.player;
    final onReopen = widget.onReopen;
    final card = Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            // Reopen the source screen (YouTube watch page or Jellyfin player);
            // the live player carries over via reclaim instead of reloading.
            onTap: onReopen,
            child: Video(
              controller: controller,
              controls: NoVideoControls,
              fit: BoxFit.cover,
            ),
          ),
          // The top bar and center play/pause fade with the chrome; the bottom
          // progress line stays visible as a persistent, unobtrusive cue.
          AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: IgnorePointer(
              ignoring: !_visible,
              child: Stack(
                fit: StackFit.expand,
                children: [
          // Top gradient with title, size toggle, and close.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 4, 2, 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(pip.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  _IconDot(
                    icon: Icons.open_in_new_rounded,
                    tooltip: l.playerPopOut,
                    onTap: () => ref.read(popoutProvider.notifier).enter(),
                  ),
                  _IconDot(
                    icon: Icons.close_rounded,
                    tooltip: l.commonClose,
                    onTap: notifier.close,
                  ),
                ],
              ),
            ),
          ),
          // Center play/pause.
          Center(
            child: StreamBuilder<bool>(
              stream: player.stream.playing,
              initialData: player.state.playing,
              builder: (_, snap) {
                final playing = snap.data ?? false;
                return Semantics(button: true, label: playing ? l.commonPause : l.commonPlay, child: InkWell(
                  onTap: player.playOrPause,
                  customBorder: const CircleBorder(),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 28,
                        color: Colors.white),
                  ),
                ));
              },
            ),
          ),
                ],
              ),
            ),
          ),
          // Thin playback progress along the very bottom.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: StreamBuilder<Duration>(
              stream: player.stream.position,
              initialData: player.state.position,
              builder: (_, snap) {
                final dur = player.state.duration.inMilliseconds;
                final pos = (snap.data ?? Duration.zero).inMilliseconds;
                final frac = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
                return LinearProgressIndicator(
                  value: frac,
                  minHeight: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.22),
                  valueColor: AlwaysStoppedAnimation(
                      Theme.of(context).colorScheme.primary),
                );
              },
            ),
          ),
        ],
      ),
    );
    if (!_hoverPlatform) return card;
    return MouseRegion(
      onEnter: (_) => _show(),
      onHover: (_) => _show(),
      onExit: (_) {
        _hideTimer?.cancel();
        if (_visible) setState(() => _visible = false);
      },
      child: card,
    );
  }
}

/// A small circular tap target in the mini player's top bar.
class _IconDot extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconDot(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 18,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
      color: Colors.white,
      onPressed: onTap,
      icon: Icon(icon),
    );
  }
}
