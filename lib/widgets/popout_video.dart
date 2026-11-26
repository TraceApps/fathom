import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/pip_controller.dart';
import '../state/popout_controller.dart';
import 'glass.dart';

/// The desktop pop-out: shown filling the (shrunken, always-on-top) window when
/// pop-out mode is on. Drag anywhere on the video to move the window across
/// monitors; grab any edge/corner to resize (the compositor handles that on
/// Wayland, and 16:9 is locked at the window level); controls fade in on hover.
class PopoutVideo extends ConsumerStatefulWidget {
  const PopoutVideo({super.key});

  @override
  ConsumerState<PopoutVideo> createState() => _PopoutVideoState();
}

class _PopoutVideoState extends ConsumerState<PopoutVideo> {
  bool _visible = true;
  Timer? _hideTimer;

  // Reveal the controls on any pointer activity, then fade them after a short
  // idle even while the cursor rests over the window (mouse-leave alone left
  // them pinned open). Movement or re-entry brings them back.
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
    _show(); // brief reveal on open, then auto-hide
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final notifier = ref.read(pipProvider.notifier);
    final controller = notifier.controller;
    final player = notifier.player;
    // The video went away (closed elsewhere): drop back to the normal window.
    if (controller == null || player == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(popoutProvider.notifier).exit();
      });
      return const ColoredBox(color: Colors.black);
    }

    return MouseRegion(
      onEnter: (_) => _show(),
      onHover: (_) => _show(),
      onExit: (_) {
        _hideTimer?.cancel();
        if (_visible) setState(() => _visible = false);
      },
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Drag anywhere on the picture to move the window (Wayland-friendly).
            DragToMoveArea(
              child: Video(
                controller: controller,
                controls: NoVideoControls,
                fit: BoxFit.contain,
              ),
            ),
            // Only the buttons intercept pointers, so everywhere else (the whole
            // picture, top included) drags the window. Edge/corner resize is the
            // compositor's job on Wayland, so there's no custom grip.
            AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: IgnorePointer(
                ignoring: !_visible,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Frosted pill for the window buttons, matching the player
                    // and live HUD glass.
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GlassSurface(
                        blur: 14,
                        color: Colors.black.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10)),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _dot(
                                icon: Icons.close_fullscreen_rounded,
                                tooltip: l.playerBackToApp,
                                onTap: () =>
                                    ref.read(popoutProvider.notifier).exit(),
                              ),
                              _dot(
                                icon: Icons.close_rounded,
                                tooltip: l.commonClose,
                                onTap: () {
                                  notifier.close();
                                  ref.read(popoutProvider.notifier).exit();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: StreamBuilder<bool>(
                        stream: player.stream.playing,
                        initialData: player.state.playing,
                        builder: (_, snap) {
                          final playing = snap.data ?? false;
                          return Semantics(button: true, label: playing ? l.commonPause : l.commonPlay, child: _CircleButton(
                            icon: playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            onTap: player.playOrPause,
                          ));
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) =>
      IconButton(
        tooltip: tooltip,
        iconSize: 18,
        padding: const EdgeInsets.all(4),
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(),
        color: Colors.white,
        onPressed: onTap,
        icon: Icon(icon),
      );
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 30, color: Colors.white),
      ),
    );
  }
}
