import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../api/jellyfin_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../services/tv_mode.dart';
import 'animated_control.dart';
import 'glass.dart';
import 'playback_stats.dart';
import 'trickplay_thumb.dart';
import 'app_spinner.dart';

/// Fathom's own auto-hiding player chrome: a cinematic top bar, a centered
/// transport with 10s-back / 30s-forward skips, and a bottom bar with a custom
/// seek bar (trickplay preview), track pickers, volume and fullscreen.
/// A tick on the seek bar: a chapter start, an intro, a credits roll.
///
/// Deliberately generic. This bar is hand-written precisely because media_kit's
/// built-in one has no marker API, and both players want ticks for different
/// reasons — YouTube chapters here, Jellyfin chapters and media segments there.
typedef PlayerMarker = ({Duration position, String label});

/// Material only ships numbered replay/forward icons for 5, 10 and 30. For any
/// other interval the plain arrows are used rather than an icon that states a
/// number the button doesn't do.
IconData _replayIcon(int seconds) => switch (seconds) {
      5 => Icons.replay_5_rounded,
      10 => Icons.replay_10_rounded,
      30 => Icons.replay_30_rounded,
      _ => Icons.fast_rewind_rounded,
    };

IconData _forwardIcon(int seconds) => switch (seconds) {
      5 => Icons.forward_5_rounded,
      10 => Icons.forward_10_rounded,
      30 => Icons.forward_30_rounded,
      _ => Icons.fast_forward_rounded,
    };

class FathomPlayerControls extends StatefulWidget {
  final Player player;
  final String? trickItemId;
  final String title;

  /// Live channel number, shown as a small pill beside the channel name in the
  /// top bar. Null/empty hides it.
  final String? channelNumber;
  final bool isLive;
  final bool loading;
  final VoidCallback onBack;
  final void Function(int seconds) onSeekBy;

  /// Jumps a live stream to the live edge. Powers the LIVE button; null for VOD.
  final VoidCallback? onJumpToLive;
  final VoidCallback? onSubtitles;
  final VoidCallback? onAudio;
  final VoidCallback? onSpeed;
  final VoidCallback? onSleepTimer;
  final VoidCallback? onQuality;
  final String qualityLabel;
  final VoidCallback? onChapters;

  /// When both are non-null, a "Playback Info" entry appears in the settings
  /// gear that toggles a read-only stats overlay showing [statsPlayMethod] as
  /// the Play Method. The overlay renders inside the controls so it survives the
  /// fullscreen route, and its open state is a shared [ValueNotifier] (owned by
  /// the player screen) so it stays open across the windowed⇄fullscreen swap —
  /// each route has its own controls instance, but both watch the same notifier.
  final String? statsPlayMethod;
  final ValueNotifier<bool>? statsOpen;

  /// Live TV record control. Lives in the bottom bar with the other actions,
  /// not floating in the title bar.
  final Widget? recordButton;
  final VoidCallback onToggleMute;
  final TrickplayInfo? trickplay;
  final int? trickplayWidth;

  /// Ticks drawn on the seek bar. Empty draws none.
  final List<PlayerMarker> markers;

  /// The video's chapters, in order. The seek bar splits into a segment per
  /// chapter, scrubbing names the chapter under the pointer, and the current
  /// one sits beside the transport in a pill that opens [onChapters], the way
  /// YouTube shows them. Empty shows none of that.
  final List<PlayerMarker> chapters;

  /// How far the skip buttons jump. Defaulted to the industry-standard 10/30,
  /// which is what the Jellyfin player uses; only the YouTube player overrides
  /// them, from its own settings. These controls are shared, so a setting
  /// applied in here would reach across to Jellyfin.
  final int seekBackSeconds;
  final int seekForwardSeconds;
  final String? baseUrl;
  final JellyfinClient? client;
  final Map<String, String>? headers;

  /// Full-screen players hide their chrome after a few seconds of stillness.
  /// An embedded player (the watch page) keeps it up: the pointer spends most
  /// of its time outside the video, so there'd be no way to reach pause.
  final bool autoHide;

  /// Control-bar chrome, chosen in Player settings and passed in by the caller
  /// (the shared controls never read prefs themselves): 'none' | 'glass' | 'dark'.
  final String barStyle;

  /// Hides the top bar (title + back) when the surrounding page already shows
  /// that context.
  final bool showTopBar;

  /// Whether to offer a fullscreen toggle (the bar button and the double-tap-
  /// centre gesture). Off on a phone, where the player route already fills the
  /// screen and orientation handles the rest, so media_kit's own fullscreen
  /// doesn't fight the forced-landscape lock.
  final bool showFullscreen;

  /// Enables the phone swipe gestures: vertical drag on the left half changes
  /// screen brightness, on the right half changes volume (each with a HUD).
  /// Off on desktop, where there's no touch and no per-app brightness.
  final bool touchGestures;

  /// Minimizes the video into the floating mini player. Null hides the button.
  final VoidCallback? onMinimize;

  /// Fired when the control chrome shows (true) or auto-hides (false), so the
  /// host screen can fade its own sibling overlays (e.g. the cast button) in
  /// step with the controls.
  final ValueChanged<bool>? onVisibilityChanged;

  /// Toggles theater mode (a wider in-page player with the side rail hidden).
  /// Null hides the button; shown only outside fullscreen, like YouTube.
  final VoidCallback? onToggleTheater;

  /// Whether theater mode is currently on (tints the theater button).
  final bool theaterActive;

  /// Advances to the next video/episode. Null hides the Next button.
  final VoidCallback? onNext;

  /// Goes to the previous episode. Null hides the Previous button (only the
  /// Jellyfin episode player provides it).
  final VoidCallback? onPrevious;

  /// Whether to show the hover scrub-preview thumbnail (user setting). Governs
  /// both the Jellyfin trickplay bubble and the YouTube storyboard bubble.
  final bool showThumbnailPreview;

  /// A rich "now playing" panel (live TV channel/show/description), shown
  /// lower-left and fading with the controls. Rendered inside the chrome, so it
  /// appears in fullscreen too. Null for non-live content.
  final Widget? infoPanel;

  /// Live TV program block (show title, description, program timeline with a
  /// LIVE edge) rendered inside the frosted bottom bar, in place of the
  /// meaningless live-buffer scrubber. Null for non-live content.
  final Widget? liveBottomInfo;

  /// A badge shown top-right (e.g. the live REC indicator). Rendered inside the
  /// chrome, so it fades in and out with the rest of the controls and appears in
  /// fullscreen too. Null hides it.
  final Widget? overlayBadge;

  const FathomPlayerControls({
    super.key,
    required this.player,
    this.trickItemId,
    required this.title,
    this.channelNumber,
    required this.isLive,
    required this.loading,
    required this.onBack,
    required this.onSeekBy,
    this.onJumpToLive,
    required this.onToggleMute,
    this.autoHide = true,
    this.barStyle = 'glass',
    this.showTopBar = true,
    this.showFullscreen = true,
    this.touchGestures = false,
    this.onMinimize,
    this.onVisibilityChanged,
    this.onToggleTheater,
    this.theaterActive = false,
    this.onNext,
    this.onPrevious,
    this.onSubtitles,
    this.onAudio,
    this.onSpeed,
    this.onSleepTimer,
    this.onQuality,
    this.qualityLabel = '',
    this.onChapters,
    this.statsPlayMethod,
    this.statsOpen,
    this.recordButton,
    this.trickplay,
    this.trickplayWidth,
    this.markers = const [],
    this.chapters = const [],
    this.seekBackSeconds = 10,
    this.seekForwardSeconds = 30,
    this.baseUrl,
    this.client,
    this.headers,
    this.showThumbnailPreview = true,
    this.infoPanel,
    this.liveBottomInfo,
    this.overlayBadge,
  });

  @override
  State<FathomPlayerControls> createState() => _FathomPlayerControlsState();
}

class _FathomPlayerControlsState extends State<FathomPlayerControls>
    with SingleTickerProviderStateMixin {
  bool _visible = true;
  bool? _lastEmittedVisible; // so onVisibilityChanged fires only on real changes
  bool _playing = true;
  Timer? _hideTimer;
  StreamSubscription<bool>? _playSub;
  StreamSubscription<double>? _volSub;

  // The seek bar's D-pad focus (TV only). The remote lands here on wake; LEFT/
  // RIGHT scrub while it holds focus, and UP/DOWN move focus off it to the
  // button row (Flutter's directional traversal), so every bar control is
  // reachable — the same idea as the Jellyfin/Exo TV player.
  final FocusNode _seekFocus = FocusNode(debugLabel: 'tvSeekBar');

  // The play/pause button's focus, the anchor for the seek-bar <-> button-row
  // jump: geometric UP/DOWN traversal across the full-width seek bar is
  // unreliable (Flutter mis-scores it), so those jumps are done deterministically
  // by focusing this node / the seek node. LEFT/RIGHT between buttons still use
  // Flutter's (reliable) horizontal traversal within the button row.
  final FocusNode _playFocus = FocusNode(debugLabel: 'tvPlayBtn');

  // The root D-pad key handler's focus (TV only). The chrome's focusable buttons
  // are only in the tree while it's visible, so when it auto-hides the focused
  // seek/play node is removed and focus escapes to the route root — after which
  // no D-pad press reaches _onTvKey and the chrome can never be summoned back.
  // Giving the handler its own node lets us reclaim focus the moment the chrome
  // hides, so the very next remote press always wakes it (matters most for live
  // TV, which has nothing else on screen to hold focus).
  final FocusNode _tvRootFocus = FocusNode(debugLabel: 'tvPlayerRoot');

  // A translucent play/pause silhouette flashed in the centre when the picture
  // is clicked to toggle playback (the only feedback the video itself needs).
  late final AnimationController _flashCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
  IconData? _flashIcon;

  // A transient top-centre HUD flashed on volume change or a double-click seek,
  // so those actions give feedback even when the chrome is hidden.
  bool _hudVisible = false;
  IconData? _hudIcon;
  String _hudText = '';
  Timer? _hudTimer;
  double _lastVolume = 0;

  // Current per-app screen brightness (0..1), seeded from the OS on first drag.
  // Only touched on mobile, where [widget.touchGestures] is on.
  double? _brightness;
  bool _brightnessChanged = false;

  Player get _p => widget.player;

  @override
  void initState() {
    super.initState();
    _playing = _p.state.playing;
    _lastVolume = _p.state.volume;
    if (widget.touchGestures) {
      ScreenBrightness()
          .application
          .then((b) => _brightness = b)
          .catchError((_) => _brightness = 0.5);
    }
    _playSub = _p.stream.playing.listen((v) {
      if (!mounted) return;
      _playing = v;
      if (!v) {
        // Paused: keep the chrome up so the user can see where they are.
        _hideTimer?.cancel();
        if (!_visible) setState(() => _visible = true);
      } else {
        _scheduleHide();
      }
    });
    _volSub = _p.stream.volume.listen((v) {
      // Flash only on a real change. _lastVolume is seeded from the current
      // volume in initState, so the magnitude gate alone handles the initial
      // value without swallowing the user's first real change.
      if (!mounted || (v - _lastVolume).abs() < 0.5) return;
      _lastVolume = v;
      final icon = v <= 0
          ? Icons.volume_off_rounded
          : (v < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded);
      _flashHud(icon, '${v.round()}%');
    });
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hudTimer?.cancel();
    _flashCtrl.dispose();
    _playSub?.cancel();
    _volSub?.cancel();
    _seekFocus.dispose();
    _playFocus.dispose();
    _tvRootFocus.dispose();
    // Hand brightness back to the system so a manual level doesn't stick after
    // leaving the player.
    if (_brightnessChanged) {
      ScreenBrightness().resetApplicationScreenBrightness().catchError((_) {});
    }
    super.dispose();
  }

  /// Vertical drag on the left half: screen brightness. [dy] is the per-event
  /// delta in logical pixels (positive = downward = dimmer).
  void _dragBrightness(double dy) {
    final next = ((_brightness ?? 0.5) - dy * 0.003).clamp(0.0, 1.0);
    _brightness = next;
    _brightnessChanged = true;
    ScreenBrightness()
        .setApplicationScreenBrightness(next)
        .catchError((_) {});
    _flashHud(
      next < 0.34
          ? Icons.brightness_low_rounded
          : (next < 0.67
              ? Icons.brightness_medium_rounded
              : Icons.brightness_high_rounded),
      '${(next * 100).round()}%',
    );
    _show();
  }

  /// Vertical drag on the right half: playback volume (positive dy = quieter).
  void _dragVolume(double dy) {
    final next = (_p.state.volume - dy * 0.35).clamp(0.0, 100.0);
    _p.setVolume(next);
    _lastVolume = next;
    _flashHud(
      next <= 0
          ? Icons.volume_off_rounded
          : (next < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
      '${next.round()}%',
    );
    _show();
  }

  void _flashHud(IconData icon, String text) {
    if (!mounted) return;
    setState(() {
      _hudIcon = icon;
      _hudText = text;
      _hudVisible = true;
    });
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _hudVisible = false);
    });
  }

  /// Double-click-a-side seek, with a flashed HUD. Negative seconds = back.
  void _seekZone(int seconds) {
    widget.onSeekBy(seconds);
    _flashHud(
      seconds < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
      '${seconds > 0 ? '+' : ''}${seconds}s',
    );
    _show();
  }

  void _show() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.autoHide) return;
    // Only while playing: a paused video keeps its controls up, because
    // "paused" is exactly when you want the transport in reach.
    //
    // TV gets a longer window: a remote is deliberate and slow, and a viewer
    // often pauses to read a control before pressing again. At 3s the chrome
    // hid mid-navigation and the next press only re-summoned it (landing back on
    // the seek bar), which read as "I can't move across to the other buttons".
    final hideAfter = Duration(seconds: isTvDevice ? 6 : 3);
    _hideTimer = Timer(hideAfter, () {
      if (mounted && _playing) {
        setState(() => _visible = false);
        // The focused bar button is about to leave the tree; pull focus back to
        // the root key handler so the next remote press still wakes the chrome.
        if (isTvDevice) _tvRootFocus.requestFocus();
      }
    });
  }

  /// Clicking the picture plays or pauses, as it does in every other player.
  ///
  /// It used to mean "toggle the chrome" whenever the chrome auto-hid, so the
  /// same click did different things depending on where the player was
  /// embedded. There's nothing to reveal by clicking anyway: moving the pointer
  /// already brings the chrome back, and it takes itself away again.
  void _toggle() {
    // Flash the icon of the action taken: pausing shows pause, resuming play.
    _flashIcon = _playing ? Icons.pause_rounded : Icons.play_arrow_rounded;
    _flashCtrl.forward(from: 0);
    _p.playOrPause();
    _show();
  }

  /// D-pad control on a TV remote. The remote has no mouse to reveal the chrome
  /// and no way to press the on-screen buttons directly, so handle the transport
  /// here: any key reveals the controls; SELECT plays/pauses; LEFT/RIGHT seek;
  /// UP/DOWN change volume; BACK hides the controls (and only exits once they're
  /// already hidden). Menu buttons (subtitles/audio/quality) remain reachable by
  /// focus traversal when the chrome is up.
  // Whether the D-pad is currently on the seek bar (vs. a bar button). Used to
  // decide if LEFT/RIGHT scrub or step buttons, and if SELECT plays/pauses or
  // activates the focused control.
  bool get _seekHasFocus => _seekFocus.hasFocus;

  // Bounds D-pad LEFT/RIGHT (next/previousFocus) to the button row on TV so it
  // can't wander up to the full-width seek bar. Pass-through off TV.
  Widget _tvButtonGroup(Widget child) =>
      isTvDevice ? FocusTraversalGroup(child: child) : child;

  KeyEventResult _onTvKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    // BACK / Escape: first press hides the chrome; only exit when already hidden.
    if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape) {
      if (_visible) {
        setState(() => _visible = false);
        _hideTimer?.cancel();
        // Keep the key handler focused so BACK-to-hide doesn't strand the remote.
        _tvRootFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored; // let the route pop / exit
    }
    // Media play/pause always toggles, wherever focus is.
    if (k == LogicalKeyboardKey.mediaPlayPause) {
      _show();
      _toggle();
      return KeyEventResult.handled;
    }
    final wasHidden = !_visible;
    _show();
    // A press that only wakes the chrome shouldn't also act; land the remote on
    // the seek bar so it has an obvious spot.
    if (wasHidden) {
      _seekFocus.requestFocus();
      return KeyEventResult.handled;
    }
    final onSeek = _seekHasFocus;
    // SELECT: on the seek bar it plays/pauses; on a focused button it activates
    // that button; on nothing it plays/pauses.
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.gameButtonA) {
      final pf = FocusManager.instance.primaryFocus;
      if (!onSeek && pf != null && pf != node && pf.context != null) {
        Actions.maybeInvoke(pf.context!, const ActivateIntent());
      } else {
        _toggle();
      }
      return KeyEventResult.handled;
    }
    final pf = FocusManager.instance.primaryFocus;
    final onButton = !onSeek && pf != null && pf != node;
    // UP/DOWN jump between the seek bar and the button row DETERMINISTICALLY:
    // geometric traversal across the full-width seek bar is unreliable, so anchor
    // the jump on the play button / the seek node instead.
    if (k == LogicalKeyboardKey.arrowUp) {
      if (onButton) _seekFocus.requestFocus();
      return KeyEventResult.handled; // on the seek bar there's nothing above
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (onSeek || pf == node) _playFocus.requestFocus();
      return KeyEventResult.handled; // on a button there's nothing below
    }
    // LEFT/RIGHT: scrub on the seek bar; otherwise step between the bar buttons.
    if (onSeek) {
      if (k == LogicalKeyboardKey.arrowLeft) {
        _seekZone(-widget.seekBackSeconds);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        _seekZone(widget.seekForwardSeconds);
        return KeyEventResult.handled;
      }
    }
    // Focus still on the bare container: seed the play button so a step lands
    // somewhere visible.
    if (pf == node &&
        (k == LogicalKeyboardKey.arrowLeft ||
            k == LogicalKeyboardKey.arrowRight)) {
      _playFocus.requestFocus();
      return KeyEventResult.handled;
    }
    // On a bar button: step to the neighbouring control ourselves and CONSUME
    // the key. The player screen binds LEFT/RIGHT to seek as a global shortcut;
    // if we returned `ignored` here that shortcut would fire and scrub instead
    // of moving to the next button, which is exactly why the remote could only
    // ever seek and never reach CC / audio / settings.
    //
    // The button row is its own FocusTraversalGroup (see _chrome), so order-based
    // next/previousFocus walks it left-to-right and, crucially, stays WITHIN the
    // buttons — it won't wander up to the full-width seek bar. Geometric traversal
    // can't be used here: the live-TV bar has a wide Spacer between Play and CC,
    // and the directional beam either can't bridge the gap or grabs the seek bar
    // (which sits above and spans the whole width) instead of the next button.
    if (onButton && k == LogicalKeyboardKey.arrowLeft) {
      pf.previousFocus();
      return KeyEventResult.handled;
    }
    if (onButton && k == LogicalKeyboardKey.arrowRight) {
      pf.nextFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Tell the host when the chrome shows/hides so it can fade its own sibling
    // overlays (cast button) in step. Deferred a frame — no setState in build.
    if (_lastEmittedVisible != _visible) {
      _lastEmittedVisible = _visible;
      final visible = _visible;
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => widget.onVisibilityChanged?.call(visible));
    }
    final Widget content = MouseRegion(
      // Only blank the pointer once the chrome has actually hidden itself.
      cursor: (_visible || !widget.autoHide)
          ? MouseCursor.defer
          : SystemMouseCursors.none,
      onHover: (_) => _show(),
      child: Stack(
        children: [
          // Tap surface, behind the chrome. Single tap anywhere plays/pauses;
          // double-tap the left/right third seeks (with a HUD), the centre third
          // toggles fullscreen. Live has no seek, so its sides fall back to
          // fullscreen too.
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    onDoubleTap: widget.isLive
                        ? (widget.showFullscreen
                            ? () => toggleFullscreen(context)
                            : null)
                        : () => _seekZone(-widget.seekBackSeconds),
                    onVerticalDragUpdate: widget.touchGestures
                        ? (d) => _dragBrightness(d.primaryDelta ?? 0)
                        : null,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    onDoubleTap: widget.showFullscreen
                        ? () => toggleFullscreen(context)
                        : null,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    onDoubleTap: widget.isLive
                        ? (widget.showFullscreen
                            ? () => toggleFullscreen(context)
                            : null)
                        : () => _seekZone(widget.seekForwardSeconds),
                    onVerticalDragUpdate: widget.touchGestures
                        ? (d) => _dragVolume(d.primaryDelta ?? 0)
                        : null,
                  ),
                ),
              ],
            ),
          ),
          if (widget.loading)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppSpinner(),
                      const SizedBox(height: 16),
                      Text(widget.isLive ? l.playerTuningIn : l.playerLoading,
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_visible,
              child: AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: _chrome(context),
              ),
            ),
          ),
          // Transient volume/seek HUD, above the chrome so it shows even when
          // the controls are hidden.
          Positioned(
            top: 28,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _hudVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: _HudChip(icon: _hudIcon, text: _hudText),
                ),
              ),
            ),
          ),
          // Playback-details panel: above the fading chrome so it persists once
          // opened, and inside the controls so it survives the fullscreen route.
          // A ValueListenableBuilder on the shared notifier keeps it open across
          // the windowed⇄fullscreen swap. Bounded to the video area (top clears
          // the title bar, bottom clears the control bar) so a tall panel scrolls
          // instead of getting clipped, but grows to fit where there's room.
          if (widget.statsOpen != null && widget.statsPlayMethod != null)
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: widget.statsOpen!,
                builder: (context, open, _) {
                  if (!open) return const SizedBox.shrink();
                  final pad = MediaQuery.of(context).padding;
                  return Padding(
                    padding: EdgeInsets.only(
                      top: (widget.showTopBar ? 64 : 14) + pad.top,
                      left: 14 + pad.left,
                      bottom: 96 + pad.bottom,
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: PlaybackStatsOverlay(
                        player: _p,
                        playMethod: widget.statsPlayMethod!,
                        onClose: () => widget.statsOpen!.value = false,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
    if (!isTvDevice) return content;
    // On a TV the remote drives everything through this key handler; autofocus so
    // the first press is caught even before any button takes focus. The traversal
    // group lets the arrow keys walk the (already focusable) bar buttons.
    return FocusTraversalGroup(
      child: Focus(
        focusNode: _tvRootFocus,
        autofocus: true,
        onKeyEvent: _onTvKey,
        child: content,
      ),
    );
  }

  Widget _chrome(BuildContext context) {
    final l = AppLocalizations.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Stack(
      children: [
        // Live "now playing" panel, lower-left above the transport. Ignores
        // pointers so a tap in its area still falls through to play/pause.
        if (widget.infoPanel != null)
          Positioned(
              left: 24,
              bottom: 104,
              child: IgnorePointer(child: widget.infoPanel!)),
        // Top-right badge (e.g. REC), fading with the rest of the chrome.
        if (widget.overlayBadge != null)
          Positioned(
              top: 14, right: 16, child: IgnorePointer(child: widget.overlayBadge!)),
        // Top scrim + title bar.
        // No top bar on TV: the Jellyfin/Exo TV player has none (title moves into
        // the bottom chrome, back is the remote's BACK key). Desktop/mobile keep it.
        if (widget.showTopBar && !isTvDevice)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.only(bottom: 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.62), Colors.transparent],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 12, 0),
                child: Row(
                  children: [
                    AnimatedIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: l.commonBack,
                      onTap: widget.onBack,
                    ),
                    const SizedBox(width: 6),
                    if ((widget.channelNumber ?? '').isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          widget.channelNumber!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // A translucent play/pause silhouette that scales up and fades when the
        // picture is clicked. The transport itself lives in the bottom bar now,
        // so nothing is parked over the middle of the video.
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: AnimatedBuilder(
                animation: _flashCtrl,
                builder: (context, _) {
                  final t = _flashCtrl.value;
                  if (t == 0 || t == 1 || _flashIcon == null) {
                    return const SizedBox.shrink();
                  }
                  return Opacity(
                    opacity: (1 - t) * 0.9,
                    child: Transform.scale(
                      scale: 0.7 + 0.6 * t,
                      child: Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.4),
                        ),
                        child: Icon(_flashIcon, size: 54, color: Colors.white),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        // Bottom scrim + seek bar + controls.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BottomChrome(
            isLive: widget.isLive,
            // TV uses the app's frosted-glass bar (same as everywhere else), not a
            // scrim — the media_kit video is a Flutter texture, so the blur is a
            // real frost of the picture.
            style: widget.barStyle,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // On TV the title lives in the bottom chrome above the seek bar
                  // (matching the Exo player), since there's no top bar. Live TV
                  // already shows its own info block below, so skip it there.
                  if (isTvDevice && widget.liveBottomInfo == null) ...[
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Live TV: the program info block (title, air window,
                  // description) sits above the transport in the frosted bar.
                  if (widget.liveBottomInfo != null) ...[
                    widget.liveBottomInfo!,
                    const SizedBox(height: 12),
                  ],
                  // Transport bar: position, seek bar, and (for live) a LIVE
                  // button in place of the trailing remaining time.
                  Row(
                    children: [
                      _PositionText(player: _p, remaining: false),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TvSeekFocus(
                          node: _seekFocus,
                          accent: accent,
                          child: _FathomSeekBar(
                            player: _p,
                            accent: accent,
                            onInteract: _show,
                            trickplay: widget.isLive ? null : widget.trickplay,
                            trickplayWidth:
                                widget.isLive ? null : widget.trickplayWidth,
                            markers: widget.isLive ? const [] : widget.markers,
                            chapters:
                                widget.isLive ? const [] : widget.chapters,
                            baseUrl: widget.baseUrl,
                            itemId: widget.trickItemId ?? '',
                            client: widget.client,
                            headers: widget.headers,
                            showThumbnailPreview: widget.isLive
                                ? false
                                : widget.showThumbnailPreview,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (widget.isLive)
                        _LiveButton(
                          player: _p,
                          onJumpToLive: widget.onJumpToLive,
                          onInteract: _show,
                        )
                      else
                        _PositionText(player: _p, remaining: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // The bar carries up to eight controls plus a 90px volume
                  // slider — about 470px of fixed width with only a Spacer
                  // between them. A Spacer cannot shrink below zero, so in a
                  // narrow window the Row overflowed and painted the striped
                  // overflow warning. Shed the slider first, then fold the
                  // optional controls into a menu, so it fits at any width.
                  //
                  // On TV the button row is its own traversal group so the D-pad
                  // LEFT/RIGHT (next/previousFocus) steps through the buttons and
                  // stops at the ends instead of jumping up to the full-width seek
                  // bar. A no-op wrapper off TV.
                  _tvButtonGroup(LayoutBuilder(builder: (context, c) {
                    final w = c.maxWidth;
                    final compactVolume = w < 560;
                    final folded = w < 460;

                    // Convention over balance: Volume anchors the LEFT (where
                    // every player puts it), and the track/stream pickers
                    // (Subtitles, Audio, Quality) + playback nav (Chapters,
                    // Speed) cluster on the RIGHT beside Theater/Fullscreen,
                    // where settings-style controls live. Matches YouTube/VLC
                    // muscle memory rather than evening out the bar for its own
                    // sake.
                    // The track pickers you toggle mid-watch keep their one-tap
                    // spot on the bar.
                    final tracks = <(IconData, String, VoidCallback)>[
                      if (widget.onSubtitles != null)
                        (
                          Icons.closed_caption_rounded,
                          l.playerSubtitles,
                          widget.onSubtitles!
                        ),
                      if (widget.onAudio != null)
                        (
                          Icons.multitrack_audio_rounded,
                          l.playerAudio,
                          widget.onAudio!
                        ),
                    ];
                    // The settings gear (⚙) holds the occasional / settings-ish
                    // items, in order: Quality, Chapters, Speed, Sleep Timer,
                    // then the diagnostic Playback Info toggle. Mirrors
                    // YouTube's gear.
                    final overflow = <(IconData, String, VoidCallback)>[
                      if (widget.onQuality != null)
                        (
                          Icons.high_quality_rounded,
                          l.playerQualityLabel(widget.qualityLabel),
                          widget.onQuality!
                        ),
                      if (widget.onChapters != null)
                        (Icons.format_list_numbered_rounded, l.playerChapters,
                            widget.onChapters!),
                      if (widget.onSpeed != null)
                        (Icons.speed_rounded, l.playerPlaybackSpeed,
                            widget.onSpeed!),
                      if (widget.onSleepTimer != null)
                        (Icons.bedtime_outlined, l.sleepTimer,
                            widget.onSleepTimer!),
                      if (widget.statsPlayMethod != null &&
                          widget.statsOpen != null)
                        (
                          Icons.info_outline_rounded,
                          l.playerPlaybackInfo,
                          () => widget.statsOpen!.value = !widget.statsOpen!.value
                        ),
                    ];
                    // A narrow bar folds everything (tracks + overflow) into the
                    // single ⋮ menu.
                    final optional = [...tracks, ...overflow];

                    if (folded) {
                      return Row(
                        children: [
                          // Play/pause + Volume on the left; the skip circles
                          // fold away on a narrow bar (double-tap the sides still
                          // seeks). Next joins the right group.
                          ?widget.recordButton,
                          _BarPlayPause(
                              player: _p,
                              onTap: () {
                                _p.playOrPause();
                                _show();
                              }),
                          if (!isTvDevice)
                            _VolumeControl(
                              player: _p,
                              accent: accent,
                              onToggleMute: widget.onToggleMute,
                              onInteract: _show,
                              compact: true,
                            ),
                          // The pill takes the spare room but hugs its left
                          // edge, so the right group stays flush right. (A
                          // Flexible beside a Spacer split the room 3:1.)
                          if (!widget.isLive && widget.chapters.isNotEmpty)
                            Expanded(
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: _ChapterPill(
                                  player: _p,
                                  chapters: widget.chapters,
                                  onTap: widget.onChapters == null
                                      ? null
                                      : () {
                                          widget.onChapters!();
                                          _show();
                                        },
                                ),
                              ),
                            )
                          else
                            const Spacer(),
                          if (widget.onPrevious != null)
                            _BarButton(
                                icon: Icons.skip_previous_rounded,
                                tooltip: l.commonPrevious,
                                onTap: () {
                                  widget.onPrevious!();
                                  _show();
                                }),
                          if (widget.onNext != null)
                            _BarButton(
                                icon: Icons.skip_next_rounded,
                                tooltip: l.commonNext,
                                onTap: () {
                                  widget.onNext!();
                                  _show();
                                }),
                          if (optional.isNotEmpty)
                            PopupMenuButton<VoidCallback>(
                              tooltip: l.playerMore,
                              icon: const Icon(Icons.more_vert_rounded,
                                  color: Colors.white, size: 22),
                              onSelected: (fn) {
                                fn();
                                _show();
                              },
                              itemBuilder: (_) => [
                                for (final o in optional)
                                  PopupMenuItem(
                                    value: o.$3,
                                    child: Row(children: [
                                      Icon(o.$1, size: 18),
                                      const SizedBox(width: 12),
                                      Text(o.$2),
                                    ]),
                                  ),
                              ],
                            ),
                          // Theater mode is a non-fullscreen concept, so the
                          // button hides in fullscreen, like YouTube.
                          if (widget.onToggleTheater != null &&
                              !isFullscreen(context))
                            _TheaterButton(
                                active: widget.theaterActive,
                                onTap: widget.onToggleTheater!,
                                onInteract: _show),
                          // No picture-in-picture while fullscreen: minimizing
                          // there would hand the player to the dock from behind
                          // the fullscreen route and strand it. Exit fullscreen
                          // first, as the YouTube player does.
                          if (widget.onMinimize != null &&
                              !isFullscreen(context))
                            _MinimizeButton(
                                onMinimize: widget.onMinimize!,
                                onInteract: _show),
                          if (widget.showFullscreen && !isTvDevice)
                            _FullscreenButton(onInteract: _show),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        // Left transport: play/pause, then the skip back/forward
                        // circles, then Volume. Record leads it for live.
                        ?widget.recordButton,
                        _BarPlayPause(
                            player: _p,
                            focusNode: isTvDevice ? _playFocus : null,
                            onTap: () {
                              _p.playOrPause();
                              _show();
                            }),
                        if (!widget.isLive) ...[
                          _CircleTransport(
                            icon: _replayIcon(widget.seekBackSeconds),
                            size: 22,
                            spinForward: false,
                            onTap: () {
                              widget.onSeekBy(-widget.seekBackSeconds);
                              _show();
                            },
                          ),
                          _CircleTransport(
                            icon: _forwardIcon(widget.seekForwardSeconds),
                            size: 22,
                            spinForward: true,
                            onTap: () {
                              widget.onSeekBy(widget.seekForwardSeconds);
                              _show();
                            },
                          ),
                        ],
                        // No volume on TV: the remote owns volume, matching the
                        // Jellyfin/Exo player. (UP/DOWN on the seek bar no longer
                        // touch volume either.)
                        if (!isTvDevice)
                          _VolumeControl(
                            player: _p,
                            accent: accent,
                            onToggleMute: widget.onToggleMute,
                            onInteract: _show,
                            compact: compactVolume,
                          ),
                        // The pill takes the spare room but hugs its left
                        // edge, so the right group stays flush right. (A
                        // Flexible beside a Spacer split the room 3:1.)
                        if (!widget.isLive && widget.chapters.isNotEmpty)
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: _ChapterPill(
                                player: _p,
                                chapters: widget.chapters,
                                onTap: widget.onChapters == null
                                    ? null
                                    : () {
                                        widget.onChapters!();
                                        _show();
                                      },
                              ),
                            ),
                          )
                        else
                          const Spacer(),
                        // Right cluster: Previous/Next lead it, then the
                        // track/nav pickers and view controls.
                        if (widget.onPrevious != null)
                          _BarButton(
                              icon: Icons.skip_previous_rounded,
                              tooltip: l.commonPrevious,
                              onTap: () {
                                widget.onPrevious!();
                                _show();
                              }),
                        if (widget.onNext != null)
                          _BarButton(
                              icon: Icons.skip_next_rounded,
                              tooltip: l.commonNext,
                              onTap: () {
                                widget.onNext!();
                                _show();
                              }),
                        for (final o in tracks)
                          _BarButton(icon: o.$1, tooltip: o.$2, onTap: o.$3),
                        // Occasional items live behind a single "More" (⋮) menu,
                        // like YouTube's settings gear, so the bar stays lean.
                        if (overflow.isNotEmpty)
                          PopupMenuButton<VoidCallback>(
                            tooltip: l.playerSettings,
                            icon: const Icon(Icons.settings_rounded,
                                color: Colors.white, size: 22),
                            onSelected: (fn) {
                              fn();
                              _show();
                            },
                            itemBuilder: (_) => [
                              for (final o in overflow)
                                PopupMenuItem(
                                  value: o.$3,
                                  child: Row(children: [
                                    Icon(o.$1, size: 18),
                                    const SizedBox(width: 12),
                                    Text(o.$2),
                                  ]),
                                ),
                            ],
                          ),
                        // Theater mode is a non-fullscreen concept, so the
                        // button hides in fullscreen, like YouTube.
                        if (widget.onToggleTheater != null &&
                            !isFullscreen(context))
                          _TheaterButton(
                              active: widget.theaterActive,
                              onTap: widget.onToggleTheater!,
                              onInteract: _show),
                        // Hidden while fullscreen (see the folded branch above).
                        if (widget.onMinimize != null && !isFullscreen(context))
                          _MinimizeButton(
                              onMinimize: widget.onMinimize!,
                              onInteract: _show),
                        if (widget.showFullscreen && !isTvDevice)
                          _FullscreenButton(onInteract: _show),
                      ],
                    );
                  })),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The bottom control-bar background. The user picks the chrome from Player
/// settings (playerBarStyle), and the caller passes it in as [style]:
///  - 'none'  a plain darkening gradient, no blur (lightest on the GPU);
///  - 'glass' a subdued frosted panel (blurred, translucent, hairline top edge);
///  - 'dark'  a heavier, darker frosted panel.
/// For 'glass'/'dark', VOD/YouTube also lay a soft wash over the glass so the
/// position text and hovering trickplay thumbnail stay readable against bright
/// video; live has no seek preview, so it keeps the cleaner glass alone.
class _BottomChrome extends StatelessWidget {
  final bool isLive;

  /// Chrome style, passed in by the caller (not read from prefs here, so the
  /// shared controls stay settings-agnostic): 'none' | 'glass' | 'dark'.
  final String style;
  final Widget child;
  const _BottomChrome(
      {required this.isLive, required this.style, required this.child});

  @override
  Widget build(BuildContext context) {
    final padded = Padding(
      // TV matches the Exo player's roomier bar insets; desktop/mobile unchanged.
      padding: isTvDevice
          ? const EdgeInsets.fromLTRB(28, 40, 28, 20)
          : EdgeInsets.fromLTRB(18, style == 'none' ? 30 : 14, 18, 8),
      child: child,
    );

    // No glass: just a darkening gradient behind the controls, no BackdropFilter.
    if (style == 'none') {
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.82),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          padded,
        ],
      );
    }

    final dark = style == 'dark';
    // The frosted glass is a BACKGROUND layer, not a wrapper: the interactive
    // controls (and their fullscreen inherited dependency) must NOT be
    // descendants of the BackdropFilter. media_kit reparents the video subtree
    // on a fullscreen toggle, and descending the fullscreen-dependent controls
    // under a blur that gets reparented broke fullscreen and asserted on
    // teardown ("_dependents.isEmpty"). Keeping the blur as a sibling behind the
    // content mirrors the isolated BackdropFilter the info card used.
    return Stack(
      children: [
        Positioned.fill(
          child: GlassSurface(
            blur: dark ? 13 : 7,
            color: Colors.black.withValues(alpha: dark ? 0.40 : 0.18),
            border: Border(
              top: BorderSide(
                  color: Colors.white.withValues(alpha: dark ? 0.10 : 0.06)),
            ),
            child: const SizedBox.expand(),
          ),
        ),
        // Readability wash for VOD/YouTube (trickplay + times over the picture).
        if (!isLive)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: dark ? 0.20 : 0.26),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        padded,
      ],
    );
  }
}

/// The live-edge button. It lights solid red when you're at (or near) the live
/// edge, and shows a tappable outline when you've scrubbed behind live; tapping
/// snaps back to the edge. Whether there's any room to be "behind" at all is
/// governed entirely by the player's seekable range, i.e. the server's buffer.
class _LiveButton extends StatelessWidget {
  final Player player;
  final VoidCallback? onJumpToLive;
  final VoidCallback onInteract;
  const _LiveButton({
    required this.player,
    required this.onInteract,
    this.onJumpToLive,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const red = Color(0xFFE53935);
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? Duration.zero;
        final dur = player.state.duration;
        // "At live" when within a few seconds of the seekable edge, or when the
        // stream exposes no rewindable window at all.
        final atLive = dur <= Duration.zero ||
            (dur - pos) <= const Duration(seconds: 10);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: atLive
              ? null
              : () {
                  onJumpToLive?.call();
                  onInteract();
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: atLive ? red : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                  color:
                      atLive ? red : Colors.white.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle,
                    size: 7,
                    color: atLive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.6)),
                const SizedBox(width: 5),
                Text(l.playerBadgeLive,
                    style: TextStyle(
                        color: atLive
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.78),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A round transport button (skip back/forward) whose icon spins a full turn on
/// each tap, in the direction of the skip, so the seek is felt as well as seen.
class _CircleTransport extends StatefulWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  /// Clockwise for a forward skip, counter-clockwise for a rewind.
  final bool spinForward;
  const _CircleTransport(
      {required this.icon,
      required this.size,
      required this.onTap,
      required this.spinForward});

  @override
  State<_CircleTransport> createState() => _CircleTransportState();
}

class _CircleTransportState extends State<_CircleTransport>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final turns = Tween<double>(begin: 0, end: widget.spinForward ? 1 : -1)
        .animate(CurvedAnimation(parent: _spin, curve: Curves.easeOutCubic));
    return AnimatedControl(
      onTap: () {
        _spin.forward(from: 0);
        widget.onTap();
      },
      // No resting circle: just the icon, matching the other bar controls (only
      // a hover halo appears, like them).
      child: RotationTransition(
        turns: turns,
        // Inherits the hover accent tint from AnimatedControl.
        child: Icon(widget.icon, size: widget.size),
      ),
    );
  }
}

class _PositionText extends StatelessWidget {
  final Player player;
  final bool remaining; // false = elapsed, true = -remaining
  const _PositionText({required this.player, required this.remaining});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (_, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = player.state.duration;
        final value = remaining ? pos - dur : pos;
        return Text(
          dur <= Duration.zero && remaining ? '--:--' : fmtTime(value),
          style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w500),
        );
      },
    );
  }
}

/// The shared player-control button: grows on hover (no circular highlight or
/// halo), and springs inward on press. Every transport and bar control uses it
/// so hover and click feel alive rather than static.
class _BarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  const _BarButton(
      {required this.icon,
      required this.tooltip,
      required this.onTap,
      this.focusNode});

  @override
  Widget build(BuildContext context) {
    return AnimatedIconButton(
        icon: icon, tooltip: tooltip, onTap: onTap, focusNode: focusNode);
  }
}

/// A compact play/pause for the bottom bar; tracks the player's own state so its
/// icon flips whether the toggle came from here, the centre tap, or a hotkey.
class _BarPlayPause extends StatefulWidget {
  final Player player;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  const _BarPlayPause(
      {required this.player, required this.onTap, this.focusNode});

  @override
  State<_BarPlayPause> createState() => _BarPlayPauseState();
}

class _BarPlayPauseState extends State<_BarPlayPause> {
  late bool _playing = widget.player.state.playing;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.player.stream.playing.listen((v) {
      if (mounted && v != _playing) setState(() => _playing = v);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _BarButton(
      icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
      tooltip: _playing ? l.commonPause : l.commonPlay,
      onTap: widget.onTap,
      focusNode: widget.focusNode,
    );
  }
}

class _VolumeControl extends StatelessWidget {
  final Player player;
  final Color accent;
  final VoidCallback onToggleMute;
  final VoidCallback onInteract;

  /// Drops the 90px slider and keeps just the mute toggle. The bar runs out of
  /// room before the video does, and a slider is the first thing worth losing.
  final bool compact;

  const _VolumeControl(
      {required this.player,
      required this.accent,
      required this.onToggleMute,
      required this.onInteract,
      this.compact = false});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (_, snap) {
        final vol = snap.data ?? 100;
        final icon = vol <= 0
            ? Icons.volume_off_rounded
            : (vol < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedIconButton(
              tooltip: l.playerMute,
              icon: icon,
              onTap: () {
                onToggleMute();
                onInteract();
              },
            ),
            if (!compact)
              SizedBox(
              width: 90,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: accent,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: vol.clamp(0, 100),
                  max: 100,
                  onChanged: (v) {
                    player.setVolume(v);
                    onInteract();
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The transient volume/seek feedback pill.
class _HudChip extends StatelessWidget {
  final IconData? icon;
  final String text;
  const _HudChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: Colors.white),
            const SizedBox(width: 8),
          ],
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

class _MinimizeButton extends StatelessWidget {
  final VoidCallback onMinimize;
  final VoidCallback onInteract;
  const _MinimizeButton({required this.onMinimize, required this.onInteract});

  @override
  Widget build(BuildContext context) {
    return AnimatedIconButton(
      tooltip: AppLocalizations.of(context).playerMiniplayer,
      icon: Icons.picture_in_picture_alt_rounded,
      onTap: () {
        onMinimize();
        onInteract();
      },
    );
  }
}

/// Theater-mode toggle (YouTube's wide-player-without-rail view). Tints to the
/// accent colour while active.
class _TheaterButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onInteract;
  const _TheaterButton({
    required this.active,
    required this.onTap,
    required this.onInteract,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return AnimatedControl(
      tooltip: active ? l.playerDefaultView : l.playerTheaterMode,
      onTap: () {
        onTap();
        onInteract();
      },
      // A wide screen glyph to go theater, a narrower one to come back, like
      // YouTube's two-state button; accent while active, otherwise inherits the
      // hover tint from AnimatedControl (null = white at rest, accent on hover).
      child: Icon(
          active ? Icons.crop_7_5_rounded : Icons.crop_landscape_rounded,
          size: 22,
          color: active ? accent : null),
    );
  }
}

class _FullscreenButton extends StatelessWidget {
  final VoidCallback onInteract;
  const _FullscreenButton({required this.onInteract});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final full = isFullscreen(context);
    return AnimatedIconButton(
      tooltip: full ? l.playerExitFullscreen : l.playerFullscreen,
      icon: full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
      onTap: () {
        toggleFullscreen(context);
        onInteract();
      },
    );
  }
}

/// Makes the seek bar a D-pad focus stop on TV and rings it when focused, so the
/// remote can sit on it (LEFT/RIGHT scrub, handled by the parent) or move off it
/// (UP/DOWN → directional traversal to the buttons). A no-op off TV, and the
/// padding is constant (only the border colour changes) so nothing reflows.
class _TvSeekFocus extends StatefulWidget {
  final FocusNode node;
  final Color accent;
  final Widget child;
  const _TvSeekFocus(
      {required this.node, required this.accent, required this.child});

  @override
  State<_TvSeekFocus> createState() => _TvSeekFocusState();
}

class _TvSeekFocusState extends State<_TvSeekFocus> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.node.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted && widget.node.hasFocus != _focused) {
      setState(() => _focused = widget.node.hasFocus);
    }
  }

  @override
  void dispose() {
    widget.node.removeListener(_onFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return widget.child;
    return Focus(
      focusNode: widget.node,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _focused ? widget.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Custom seek bar with a buffered underlay, a draggable thumb, and a
/// trickplay scrub-preview bubble that follows the cursor on hover.
class _FathomSeekBar extends StatefulWidget {
  final Player player;
  final Color accent;
  final VoidCallback onInteract;
  final TrickplayInfo? trickplay;
  final int? trickplayWidth;
  final String? baseUrl;
  final String itemId;
  final JellyfinClient? client;
  final Map<String, String>? headers;
  final List<PlayerMarker> markers;
  final List<PlayerMarker> chapters;

  /// When false, the hover scrub-preview bubble is suppressed (user setting).
  final bool showThumbnailPreview;

  const _FathomSeekBar({
    required this.player,
    required this.accent,
    required this.onInteract,
    required this.trickplay,
    required this.trickplayWidth,
    required this.baseUrl,
    required this.itemId,
    required this.client,
    required this.headers,
    this.markers = const [],
    this.chapters = const [],
    this.showThumbnailPreview = true,
  });

  @override
  State<_FathomSeekBar> createState() => _FathomSeekBarState();
}

class _FathomSeekBarState extends State<_FathomSeekBar> {
  double? _dragFrac; // active drag position (0..1)
  double? _hoverFrac; // trickplay hover position (0..1)
  double? _hoverX;

  Player get _p => widget.player;

  void _seekToFrac(double frac, Duration dur) {
    if (dur <= Duration.zero) return;
    final f = frac.clamp(0.0, 1.0);
    _p.seek(dur * f);
    widget.onInteract();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: _p.stream.position,
      initialData: _p.state.position,
      builder: (_, snap) {
        final dur = _p.state.duration;
        final durMs = dur.inMilliseconds;
        final pos = snap.data ?? Duration.zero;
        final playedFrac = _dragFrac ??
            (durMs > 0 ? (pos.inMilliseconds / durMs).clamp(0.0, 1.0) : 0.0);
        final bufFrac = durMs > 0
            ? (_p.state.buffer.inMilliseconds / durMs).clamp(0.0, 1.0)
            : 0.0;
        final info = widget.trickplay;
        final tWidth = widget.trickplayWidth;
        final base = widget.baseUrl;
        const double thumbH = 96;
        final double thumbW = (info != null && info.height > 0)
            ? thumbH * info.width / info.height
            : 160;

        return LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return MouseRegion(
              opaque: false,
              onHover: (e) {
                if (info == null && widget.chapters.isEmpty) return;
                setState(() {
                  _hoverX = e.localPosition.dx.clamp(0.0, w);
                  _hoverFrac = (e.localPosition.dx / w).clamp(0.0, 1.0);
                });
              },
              onExit: (_) {
                if (_hoverFrac != null) {
                  setState(() {
                    _hoverFrac = null;
                    _hoverX = null;
                  });
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _seekToFrac(d.localPosition.dx / w, dur),
                onHorizontalDragStart: (d) {
                  setState(
                      () => _dragFrac = (d.localPosition.dx / w).clamp(0.0, 1.0));
                  widget.onInteract();
                },
                onHorizontalDragUpdate: (d) {
                  setState(
                      () => _dragFrac = (d.localPosition.dx / w).clamp(0.0, 1.0));
                  widget.onInteract();
                },
                onHorizontalDragEnd: (_) {
                  final f = _dragFrac;
                  if (f != null) _seekToFrac(f, dur);
                  setState(() => _dragFrac = null);
                },
                child: SizedBox(
                  height: 26,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // Base, buffered and played, cut into one segment per
                      // chapter like YouTube's bar. The gaps are real gaps
                      // (clipped out), so the video shows through them.
                      SizedBox(
                        width: w,
                        height: 5,
                        child: ClipPath(
                          clipper: _ChapterGaps(
                            fractions: [
                              if (durMs > 0)
                                for (final c in widget.chapters)
                                  if (c.position > Duration.zero &&
                                      c.position < dur)
                                    c.position.inMilliseconds / durMs,
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Base track.
                              Container(
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              // Buffered. Anchored left with an explicit width: a
                              // FractionallySizedBox sizes to its fraction and the
                              // center-aligned Stack then centred it, so the fill grew
                              // out from the middle instead of from the start.
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  width: w * bufFrac,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.38),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                              // Played.
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  width: w * playedFrac,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: widget.accent,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Chapter / segment ticks. Above the played bar so they
                      // stay legible once passed, below the thumb so they never
                      // cover the handle you're dragging.
                      if (dur.inMilliseconds > 0)
                        for (final m in widget.markers)
                          if (m.position > Duration.zero &&
                              m.position < dur)
                            Positioned(
                              left: ((m.position.inMilliseconds /
                                              dur.inMilliseconds) *
                                          w -
                                      1)
                                  .clamp(0.0, w - 2),
                              child: Tooltip(
                                message: m.label,
                                child: Container(
                                  width: 2,
                                  height: 11,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                            ),
                      // Thumb.
                      Positioned(
                        left: (playedFrac * w - 7).clamp(0.0, w - 14),
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: widget.accent,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 4,
                                  offset: Offset(0, 1)),
                            ],
                          ),
                        ),
                      ),
                      // Chapter bubble: the chapter under the pointer while
                      // hovering, or under your finger while dragging. Only
                      // where there's no trickplay thumbnail to carry a label.
                      if (widget.chapters.isNotEmpty &&
                          durMs > 0 &&
                          (_dragFrac != null || _hoverFrac != null) &&
                          !(widget.showThumbnailPreview &&
                              info != null &&
                              _dragFrac == null))
                        Builder(builder: (context) {
                          final frac = _dragFrac ?? _hoverFrac!;
                          final at = dur * frac;
                          final title = chapterAt(widget.chapters, at)?.label;
                          const bubbleW = 220.0;
                          return Positioned(
                            bottom: 26,
                            left: (frac * w - bubbleW / 2)
                                .clamp(-8.0, (w - bubbleW + 8.0).clamp(-8.0, w)),
                            width: bubbleW,
                            child: IgnorePointer(
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.78),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (title != null)
                                        Text(
                                          title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      Text(
                                        fmtTime(at),
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                            fontFeatures: [
                                              FontFeature.tabularFigures()
                                            ]),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      // Trickplay preview bubble.
                      if (widget.showThumbnailPreview &&
                          info != null &&
                          tWidth != null &&
                          base != null &&
                          widget.client != null &&
                          widget.headers != null &&
                          _hoverFrac != null &&
                          _hoverX != null &&
                          durMs > 0)
                        Positioned(
                          bottom: 26,
                          left: (_hoverX! - thumbW / 2)
                              .clamp(-8.0, (w - thumbW + 8.0).clamp(-8.0, w)),
                          child: TrickplayThumb(
                            client: widget.client!,
                            baseUrl: base,
                            itemId: widget.itemId,
                            info: info,
                            resolutionWidth: tWidth,
                            headers: widget.headers!,
                            positionMs: (dur * _hoverFrac!).inMilliseconds,
                            thumbWidth: thumbW,
                            thumbHeight: thumbH,
                            label: fmtTime(dur * _hoverFrac!),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// The chapter playing at [at]: the last one that has started. Null before the
/// first one starts (a video whose first chapter isn't at 0:00).
PlayerMarker? chapterAt(List<PlayerMarker> chapters, Duration at) {
  PlayerMarker? found;
  for (final c in chapters) {
    if (c.position <= at) {
      found = c;
    } else {
      break;
    }
  }
  return found;
}

/// Cuts a 2px gap into the seek bar at each chapter start.
class _ChapterGaps extends CustomClipper<Path> {
  const _ChapterGaps({required this.fractions});

  /// Where each chapter after the first starts, 0..1 along the bar.
  final List<double> fractions;

  static const double gap = 2;

  @override
  Path getClip(Size size) {
    final bar = Path()..addRect(Offset.zero & size);
    if (fractions.isEmpty) return bar;
    final gaps = Path();
    for (final f in fractions) {
      final x = (f * size.width).clamp(0.0, size.width);
      gaps.addRect(Rect.fromLTWH(x - gap / 2, 0, gap, size.height));
    }
    return Path.combine(PathOperation.difference, bar, gaps);
  }

  @override
  bool shouldReclip(_ChapterGaps old) => !listEquals(old.fractions, fractions);
}

/// The current chapter's title beside the transport, YouTube's chapter pill.
/// Follows playback, and opens the chapter list when tapped.
class _ChapterPill extends StatelessWidget {
  const _ChapterPill({
    required this.player,
    required this.chapters,
    required this.onTap,
  });

  final Player player;
  final List<PlayerMarker> chapters;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // Too narrow to say anything useful: leave the room to the buttons.
      if (c.maxWidth < 72) return const SizedBox.shrink();
      return StreamBuilder<Duration>(
        stream: player.stream.position,
        initialData: player.state.position,
        builder: (context, snap) {
          final title =
              chapterAt(chapters, snap.data ?? Duration.zero)?.label;
          if (title == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Material(
              color: Colors.white.withValues(alpha: 0.14),
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (onTap != null)
                        const Icon(Icons.chevron_right_rounded,
                            color: Colors.white, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }
}

