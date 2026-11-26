import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'media_keys.dart';
import '../api/error_text.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/youtube_caption.dart';
import '../models/youtube_chapter.dart';
import '../models/youtube_video.dart';
import '../services/sponsorblock.dart';
import '../state/audio_player.dart';
import '../services/youtube_streams.dart';
import '../state/preferences.dart';
import '../state/youtube_providers.dart';
import 'animated_control.dart';
import 'exo_stats_panel.dart';
import 'exo_video.dart';
import 'glass.dart';
import 'app_snack.dart';
import 'app_spinner.dart';

/// Width of one Up Next card (thumbnail). Cards are 16:9.
const double _upNextCardWidth = 200;

/// Plays a YouTube video on the native Media3 ExoPlayer backend (Android TV),
/// merging YouTube's separate video-only + audio-only adaptive streams so >720p
/// plays smoothly — media_kit's texture/copy-back path jitters on low-power TV
/// SoCs.
///
/// The control bar mirrors the Jellyfin ExoPlayer screen (same [ExoSeekBar],
/// same deterministic D-pad nav, same glass panel), so the two players match.
/// YouTube adds a Quality menu (its resolutions), chapter markers + a chapter
/// menu, and SponsorBlock auto-skip. Captions come in a later pass (they need
/// native subtitle sideloading on the Media3 side).
class YoutubeExoPlayer extends ConsumerStatefulWidget {
  const YoutubeExoPlayer({
    super.key,
    required this.url,
    this.title = '',
    this.chapters = const [],
    this.queue = const [],
    this.related = const [],
    this.onPlayVideo,
    this.seekBackSeconds = 10,
    this.seekForwardSeconds = 30,
    this.resumeAt,
    this.onBack,
    this.onProgress,
    this.onEnded,
    this.onNext,
    this.onShowActions,
  });

  /// A YouTube watch URL (streams are resolved here).
  final String url;
  final String title;

  /// Chapter markers (from the video's innertube watch details). Empty hides the
  /// chapter marks and the Chapters menu entry.
  final List<YoutubeChapter> chapters;

  /// Explicitly queued videos ("Up Next" — play these first) and the video's
  /// related list. Both feed the Up Next panel; empty hides its button.
  final List<YoutubeVideo> queue;
  final List<YoutubeVideo> related;

  /// Plays a chosen Up Next / related video (swaps the current one in place).
  final void Function(YoutubeVideo)? onPlayVideo;
  final int seekBackSeconds;
  final int seekForwardSeconds;

  /// Resolved lazily (a resume lookup); awaited before the first load.
  final Future<Duration?>? resumeAt;
  final VoidCallback? onBack;
  final void Function(Duration position, Duration duration)? onProgress;
  final VoidCallback? onEnded;
  final VoidCallback? onNext;

  /// Opens the lean-back actions sheet (Subscribe / Add to playlist / Channel).
  /// Null hides the Actions button.
  final VoidCallback? onShowActions;

  @override
  ConsumerState<YoutubeExoPlayer> createState() => _YoutubeExoPlayerState();
}

class _YoutubeExoPlayerState extends ConsumerState<YoutubeExoPlayer> {
  final _controller = ExoVideoController();
  StreamSubscription<String>? _errSub;
  YtStreams? _streams;
  int _qi = 0; // index into _streams.qualities (0 = highest)
  double _speed = 1.0;
  bool _loading = true;
  String? _error;
  bool _statsOpen = false;
  bool _controlsVisible = false;
  bool _endedFired = false;
  Timer? _hideTimer;
  IconData? _flashIcon;
  Timer? _flashTimer;

  // SponsorBlock: crowdsourced skippable segments, and the ones already jumped
  // (each is skipped once, else a slow seek re-triggers the same skip).
  List<SponsorSegment> _sponsors = const [];
  final _skippedSponsors = <String>{};

  // Captions: YouTube's subtitle tracks (sideloaded WebVTT). ExoPlayer bakes a
  // sideloaded subtitle into the MediaSource at load, so switching one reloads
  // the current stream at the same position. Null = off.
  List<YoutubeCaption> _captions = const [];
  YoutubeCaption? _caption;

  // Up Next overlay: a single bottom carousel, YouTube-TV style. Pressing DOWN
  // from playback reveals it — the queue/playlist first (what plays next), then
  // the video's related list. LEFT/RIGHT move, OK plays, UP/Back dismisses.
  bool _upNextVisible = false;
  int _upNextIndex = 0;
  final _upNextScroll = ScrollController();
  List<YoutubeVideo>? _upNextCache;

  final _fRoot = FocusNode(debugLabel: 'ytRoot');
  final _fSeek = FocusNode(debugLabel: 'ytSeek');
  final _fPlay = FocusNode(debugLabel: 'ytPlay');
  final _fBack = FocusNode(debugLabel: 'ytBack');
  final _fFwd = FocusNode(debugLabel: 'ytFwd');
  final _fNext = FocusNode(debugLabel: 'ytNext');
  final _fCaption = FocusNode(debugLabel: 'ytCaption');
  final _fActions = FocusNode(debugLabel: 'ytActions');
  final _fSettings = FocusNode(debugLabel: 'ytSettings');

  /// Queue/playlist first (what plays next), then the video's related list; the
  /// current video and dupes dropped. Cached — inputs are fixed per instance.
  List<YoutubeVideo> get _upNextList {
    if (_upNextCache != null) return _upNextCache!;
    final currentId = youtubeVideoId(widget.url);
    final seen = <String>{?currentId};
    final list = <YoutubeVideo>[];
    for (final v in [...widget.queue, ...widget.related]) {
      if (seen.add(v.id)) list.add(v);
    }
    return _upNextCache = list;
  }

  bool get _hasUpNext => widget.onPlayVideo != null && _upNextList.isNotEmpty;

  List<FocusNode> _buttonOrder() => [
        _fPlay,
        _fBack,
        _fFwd,
        if (widget.onNext != null) _fNext,
        // Subtitles (CC) is a dedicated bar button like the Jellyfin player, so
        // the two players read the same; the gear keeps Quality/Speed/Chapters.
        if (_captions.isNotEmpty) _fCaption,
        if (widget.onShowActions != null) _fActions,
        _fSettings,
      ];

  @override
  void initState() {
    super.initState();
    // Video and library music must not play at once: pause any library audio
    // when this player opens, same as the media_kit YouTube player does.
    final audio = ref.read(audioPlayerProvider);
    if (audio.state.playing) {
      unawaited(audio.pause());
    }
    _errSub = _controller.errors.listen((e) {
      if (mounted) setState(() => _error = e);
    });
    _controller.state.addListener(_onState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _onState() {
    if (!mounted) return;
    final s = _controller.state.value;
    widget.onProgress?.call(s.position, s.duration);
    _maybeSkipSponsor(s.position);
    if (s.ended && !_endedFired) {
      _endedFired = true;
      widget.onEnded?.call();
    }
    setState(() {}); // keep the scrubber/time live
  }

  Future<void> _start() async {
    try {
      final s = await resolveYoutubeStreams(widget.url);
      final resume = (await widget.resumeAt) ?? Duration.zero;
      if (!mounted) return;
      _streams = s;
      await _waitForAttach();
      if (!mounted) return;
      await _loadQuality(0, resume: resume);
      if (mounted) setState(() => _loading = false);
      _loadSponsors();
      _loadCaptions();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _waitForAttach() async {
    for (var i = 0; i < 100 && !_controller.isAttached; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _loadQuality(int i, {Duration? resume}) async {
    final s = _streams;
    if (s == null) return;
    final pos = resume ?? _controller.state.value.position;
    final c = _caption;
    if (s.qualities.isNotEmpty && (s.audioUrl?.isNotEmpty ?? false)) {
      _qi = i.clamp(0, s.qualities.length - 1);
      await _controller.load(s.qualities[_qi].url,
          audioUrl: s.audioUrl,
          subtitleUrl: c?.vttUrl,
          subtitleLang: c?.code,
          subtitleLabel: c?.label,
          start: pos,
          play: true);
    } else if (s.muxedUrl != null) {
      await _controller.load(s.muxedUrl!,
          subtitleUrl: c?.vttUrl,
          subtitleLang: c?.code,
          subtitleLabel: c?.label,
          start: pos,
          play: true);
    } else if (mounted) {
      setState(() => _error = 'No playable stream');
    }
  }

  Future<void> _loadCaptions() async {
    final id = youtubeVideoId(widget.url);
    if (id == null) return;
    final caps = await resolveYoutubeCaptions(id);
    if (!mounted || caps.isEmpty) return;
    setState(() => _captions = caps);
  }

  String get _qualityLabel {
    final s = _streams;
    if (s == null || s.qualities.isEmpty) return 'Auto';
    return s.qualities[_qi.clamp(0, s.qualities.length - 1)].label;
  }

  // ---- SponsorBlock ---------------------------------------------------------

  Future<void> _loadSponsors() async {
    final id = youtubeVideoId(widget.url);
    if (id == null) return;
    // The provider returns nothing unless the feature is enabled, so this is a
    // no-op request when SponsorBlock is off.
    final segments = await ref.read(youtubeSponsorSegmentsProvider(id).future);
    if (!mounted || segments.isEmpty) return;
    setState(() => _sponsors = segments);
  }

  /// Jumps past a sponsor segment the playhead has entered. Mirrors the media_kit
  /// player: each segment skips once, and by default it says what it did with an
  /// Undo, since a silent jump is indistinguishable from a bug.
  void _maybeSkipSponsor(Duration position) {
    for (final seg in _sponsors) {
      if (_skippedSponsors.contains(seg.uuid) || !seg.contains(position)) {
        continue;
      }
      _skippedSponsors.add(seg.uuid);
      _controller.seekTo(seg.end);

      final notify = ref.read(preferencesProvider).asData?.value
              .youtubeSponsorBlockNotify ??
          true;
      if (notify && mounted) {
        final l = AppLocalizations.of(context);
        showSnack(
          context,
          l.playerSkippedSegment(
              seg.category.label.toLowerCase(), seg.length.inSeconds),
          duration: const Duration(seconds: 4),
          actionLabel: l.playerUndo,
          onAction: () => _controller.seekTo(seg.start),
        );
      }
      return;
    }
  }

  // ---- chapters -------------------------------------------------------------

  YoutubeChapter? get _currentChapter {
    if (widget.chapters.isEmpty) return null;
    final pos = _controller.state.value.position;
    YoutubeChapter? found;
    for (final c in widget.chapters) {
      if (c.start <= pos) {
        found = c;
      } else {
        break;
      }
    }
    return found;
  }

  // ---- transport ------------------------------------------------------------

  void _show() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller.state.value.playing) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _flash(IconData icon) {
    setState(() => _flashIcon = icon);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 500),
        () => mounted ? setState(() => _flashIcon = null) : null);
  }

  void _togglePlay() {
    final playing = _controller.state.value.playing;
    _flash(playing ? Icons.pause_rounded : Icons.play_arrow_rounded);
    _controller.playOrPause();
    _show();
  }

  void _seekBy(int seconds) {
    final s = _controller.state.value;
    var t = s.position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (s.duration > Duration.zero && t > s.duration) t = s.duration;
    _controller.seekTo(t);
    _flash(seconds < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded);
    _show();
  }

  void _scrubSeek(int sign) {
    final s = _controller.state.value;
    final durMs = s.duration.inMilliseconds;
    if (durMs <= 0) return;
    final stepMs = (durMs * 0.02).clamp(5000, 120000).toInt();
    final t = (s.position.inMilliseconds + sign * stepMs).clamp(0, durMs);
    _controller.seekTo(Duration(milliseconds: t));
    _show();
  }

  void _focusPlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controlsVisible) _fPlay.requestFocus();
    });
  }

  FocusNode? _menuReturn;
  void _restoreMenuFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) (_menuReturn ?? _fSettings).requestFocus();
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    final isBack =
        k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape;
    final isSelect = k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.gameButtonA;

    // Up Next carousel owns the remote while it's open.
    if (_upNextVisible) {
      if (isBack || k == LogicalKeyboardKey.arrowUp) {
        _closeUpNext();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowLeft) {
        _moveUpNext(-1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        _moveUpNext(1);
        return KeyEventResult.handled;
      }
      if (isSelect) {
        _playUpNext();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled; // swallow the rest while it's up
    }

    if (isBack) {
      if (_controlsVisible) {
        setState(() => _controlsVisible = false);
        _hideTimer?.cancel();
        return KeyEventResult.handled;
      }
      final back = widget.onBack;
      if (back != null) {
        back();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored; // let the route pop
    }
    if (handleMediaKey(
      k,
      playing: _controller.state.value.playing,
      held: event is KeyRepeatEvent,
      toggle: _togglePlay,
      back: () => _seekBy(-widget.seekBackSeconds),
      forward: () => _seekBy(widget.seekForwardSeconds),
      next: widget.onNext,
    )) {
      return KeyEventResult.handled;
    }
    if (!_controlsVisible) {
      // DOWN from playback opens the Up Next carousel (YouTube-TV style); any
      // other key brings up the transport controls.
      if (k == LogicalKeyboardKey.arrowDown && _hasUpNext) {
        _openUpNext();
        return KeyEventResult.handled;
      }
      _show();
      _focusPlay();
      return KeyEventResult.handled;
    }
    _scheduleHide();

    final pf = FocusManager.instance.primaryFocus;
    if (k == LogicalKeyboardKey.arrowUp) {
      if (pf != _fSeek) _fSeek.requestFocus();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      // From the scrubber, DOWN drops to the control row; from the control row,
      // DOWN opens Up Next (so it's reachable with the controls up too).
      if (pf == _fSeek) {
        _fPlay.requestFocus();
      } else if (_hasUpNext) {
        _openUpNext();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight) {
      final right = k == LogicalKeyboardKey.arrowRight;
      if (pf == _fSeek) {
        _scrubSeek(right ? 1 : -1);
        return KeyEventResult.handled;
      }
      final order = _buttonOrder();
      final idx = order.indexOf(pf ?? _fPlay);
      if (idx < 0) {
        _fPlay.requestFocus();
        return KeyEventResult.handled;
      }
      final next = idx + (right ? 1 : -1);
      if (next >= 0 && next < order.length) order[next].requestFocus();
      return KeyEventResult.handled;
    }
    if (isSelect) {
      if (pf == _fSeek) {
        _togglePlay();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored; // let the focused button's ActivateIntent run
    }
    return KeyEventResult.ignored;
  }

  // ---- menus ----------------------------------------------------------------

  Future<void> _showSettings() async {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: scheme.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            // Same items and order as the media_kit player's gear (Quality,
            // Chapters, Speed, Playback Info) so the two players read the same on
            // TV. Subtitles (CC) is a dedicated bar button, not a gear item.
            ListTile(
              autofocus: true,
              leading: const Icon(Icons.high_quality_rounded),
              title: Text(l.playerQuality),
              trailing: Text(_qualityLabel,
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              onTap: () => Navigator.of(ctx).pop('quality'),
            ),
            if (widget.chapters.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.list_rounded),
                title: Text(l.playerChapters),
                trailing: Text(_currentChapter?.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                onTap: () => Navigator.of(ctx).pop('chapters'),
              ),
            ListTile(
              leading: const Icon(Icons.speed_rounded),
              title: Text(l.playerPlaybackSpeed),
              trailing: Text(_speed == 1.0 ? 'Normal' : '${_speed}x',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              onTap: () => Navigator.of(ctx).pop('speed'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(AppLocalizations.of(context).playerPlaybackInfo),
              onTap: () => Navigator.of(ctx).pop('stats'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'quality') {
      await _pickQuality();
    } else if (choice == 'speed') {
      await _pickSpeed();
    } else if (choice == 'chapters') {
      await _pickChapter();
    } else if (choice == 'stats') {
      setState(() => _statsOpen = !_statsOpen);
      _show();
      _restoreMenuFocus();
    } else {
      _show();
      _restoreMenuFocus();
    }
  }

  Future<void> _pickCaption() async {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    // Off, then each track. Selecting reloads the current quality with (or
    // without) the sideloaded subtitle — ExoPlayer bakes it in at load time.
    final options = <YoutubeCaption?>[null, ..._captions];
    final choice = await showModalBottomSheet<_CaptionChoice>(
      context: context,
      backgroundColor: scheme.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(l.playerSubtitles,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            for (final c in options)
              ListTile(
                autofocus: c?.code == _caption?.code,
                title: Text(c?.displayLabel ?? l.commonOff),
                trailing: c?.code == _caption?.code
                    ? Icon(Icons.check_rounded, color: scheme.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(_CaptionChoice(c)),
              ),
          ],
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (choice != null && choice.caption?.code != _caption?.code) {
      setState(() => _caption = choice.caption);
      await _loadQuality(_qi);
    }
    _show();
    _restoreMenuFocus();
  }

  Future<void> _pickChapter() async {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final current = _currentChapter;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(l.playerChapters,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            for (final c in widget.chapters)
              ListTile(
                autofocus: c == current,
                title: Text(c.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                leading: Text(c.startLabel,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                trailing: c == current
                    ? Icon(Icons.check_rounded, color: scheme.primary)
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _controller.seekTo(c.start);
                  _show();
                },
              ),
          ],
        ),
      ),
    );
    _show();
    _restoreMenuFocus();
  }

  // ---- Up Next / related carousel -------------------------------------------

  void _openUpNext() {
    if (!_hasUpNext) return;
    _hideTimer?.cancel();
    setState(() {
      _controlsVisible = false;
      _upNextVisible = true;
      _upNextIndex = 0;
    });
    // Reclaim the root focus: opening from the control row hides (and excludes)
    // the button that had focus, so the root Focus must take over to keep
    // receiving the D-pad for the carousel.
    _fRoot.requestFocus();
    _scrollUpNextTo(0);
  }

  void _closeUpNext() {
    if (!_upNextVisible) return;
    setState(() => _upNextVisible = false);
  }

  void _moveUpNext(int delta) {
    final n = _upNextList.length;
    if (n == 0) return;
    final next = (_upNextIndex + delta).clamp(0, n - 1);
    if (next == _upNextIndex) return;
    setState(() => _upNextIndex = next);
    _scrollUpNextTo(next);
  }

  void _scrollUpNextTo(int index) {
    if (!_upNextScroll.hasClients) return;
    const cardExtent = _upNextCardWidth + 12;
    final target = (index * cardExtent - 40)
        .clamp(0.0, _upNextScroll.position.maxScrollExtent);
    _upNextScroll.animateTo(target,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  void _playUpNext() {
    final list = _upNextList;
    if (_upNextIndex < 0 || _upNextIndex >= list.length) return;
    // Swaps the video in place; this player rebuilds for the new id.
    widget.onPlayVideo?.call(list[_upNextIndex]);
  }

  Future<void> _pickQuality() async {
    final s = _streams;
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    if (s == null || s.qualities.isEmpty) {
      _show();
      _restoreMenuFocus();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(l.playerQuality,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            for (var i = 0; i < s.qualities.length; i++)
              ListTile(
                autofocus: i == _qi,
                title: Text(s.qualities[i].label),
                trailing: i == _qi
                    ? Icon(Icons.check_rounded, color: scheme.primary)
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _loadQuality(i);
                },
              ),
          ],
        ),
      ),
    );
    _show();
    _restoreMenuFocus();
  }

  Future<void> _pickSpeed() async {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(l.playerPlaybackSpeed,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            for (final sp in speeds)
              ListTile(
                autofocus: _speed == sp,
                title: Text(sp == 1.0 ? 'Normal' : '${sp}x'),
                trailing: _speed == sp
                    ? Icon(Icons.check_rounded, color: scheme.primary)
                    : null,
                onTap: () {
                  setState(() => _speed = sp);
                  _controller.setSpeed(sp);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
    _show();
    _restoreMenuFocus();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    _errSub?.cancel();
    _upNextScroll.dispose();
    for (final f in [
      _fRoot,
      _fSeek,
      _fPlay,
      _fBack,
      _fFwd,
      _fNext,
      _fCaption,
      _fActions,
      _fSettings
    ]) {
      f.dispose();
    }
    _controller.state.removeListener(_onState);
    _controller.dispose();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = _controller.state.value;
    final busy = _loading || (s.buffering && _error == null);
    return Focus(
      focusNode: _fRoot,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeFocus(child: ExoVideo(controller: _controller)),
            if (busy)
              const Center(
                  child: AppSpinner(color: Colors.white)),
            if (_flashIcon != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_flashIcon, color: Colors.white, size: 48),
                ),
              ),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70)),
                ),
              ),
            // Playback Info panel (parity with the media_kit player). Top-left so
            // it clears the bottom control bar; stays up until closed.
            if (_statsOpen)
              Positioned(
                left: 24,
                top: 24 + MediaQuery.paddingOf(context).top,
                child: ExoStatsPanel(
                  controller: _controller,
                  onClose: () => setState(() => _statsOpen = false),
                ),
              ),
            // Subtitle overlay. The native player has no SubtitleView (we own the
            // surface), so it forwards cue text and we draw it — styled to match
            // the Jellyfin player: the user's subtitle colour/scale/background
            // prefs, no box by default (just a soft shadow for contrast). Nudged
            // up while the controls are visible so the bar doesn't cover it.
            ValueListenableBuilder<String>(
              valueListenable: _controller.cues,
              builder: (context, text, _) {
                if (text.isEmpty) return const SizedBox.shrink();
                final prefs = ref.watch(preferencesProvider).asData?.value;
                final bgOpacity = prefs?.subtitleBackgroundOpacity ?? 0.0;
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(
                        left: 24,
                        right: 24,
                        bottom: _controlsVisible ? 150 : 48),
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(prefs?.subtitleTextColor ?? 0xFFFFFFFF),
                        fontSize: 32.0 * (prefs?.subtitleScale ?? 1.0),
                        fontWeight: FontWeight.normal,
                        backgroundColor:
                            Colors.black.withValues(alpha: bgOpacity),
                        shadows: bgOpacity > 0.05
                            ? const []
                            : const [Shadow(blurRadius: 6, color: Colors.black)],
                      ),
                    ),
                  ),
                );
              },
            ),
            AnimatedOpacity(
              opacity: _controlsVisible && _error == null ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: ExcludeFocus(
                excluding: !_controlsVisible,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: _controls(s),
                ),
              ),
            ),
            if (_upNextVisible)
              Align(
                alignment: Alignment.bottomCenter,
                child: _upNextCarousel(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _upNextCarousel() {
    final list = _upNextList;
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.94),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.ytUpNext,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(
            height: _upNextCardWidth * 9 / 16 + 46,
            child: ListView.separated(
              controller: _upNextScroll,
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) =>
                  _upNextCard(list[i], i == _upNextIndex, l),
            ),
          ),
        ],
      ),
    );
  }

  Widget _upNextCard(YoutubeVideo v, bool focused, AppLocalizations l) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: _upNextCardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: focused ? scheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      v.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          ColoredBox(color: scheme.surfaceContainerHighest),
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          child: Text(v.durationLabel(l),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(v.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: focused ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          Text(v.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _controls(ExoState s) {
    final dur = s.duration;
    final remaining = dur > s.position ? dur - s.position : Duration.zero;
    final l = AppLocalizations.of(context);
    final bar = Padding(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          if (_currentChapter != null) ...[
            const SizedBox(height: 2),
            Text(_currentChapter!.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(_fmt(s.position),
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(width: 12),
              Expanded(
                  child: ExoSeekBar(
                      focusNode: _fSeek,
                      controller: _controller,
                      markers:
                          widget.chapters.map((c) => c.start).toList())),
              const SizedBox(width: 12),
              Text('-${_fmt(remaining)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _ctlButton(
                focusNode: _fPlay,
                icon:
                    s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                tooltip: l.playerPlayPause,
                onTap: _togglePlay,
              ),
              _ctlButton(
                focusNode: _fBack,
                icon: Icons.replay_10_rounded,
                tooltip: l.playerSeekBack(widget.seekBackSeconds),
                onTap: () => _seekBy(-widget.seekBackSeconds),
              ),
              _ctlButton(
                focusNode: _fFwd,
                icon: Icons.forward_30_rounded,
                tooltip: l.playerSeekForward(widget.seekForwardSeconds),
                onTap: () => _seekBy(widget.seekForwardSeconds),
              ),
              const Spacer(),
              if (widget.onNext != null)
                _ctlButton(
                  focusNode: _fNext,
                  icon: Icons.skip_next_rounded,
                  tooltip: l.commonNext,
                  onTap: () => widget.onNext!(),
                ),
              // Dedicated Subtitles (CC) button, matching the Jellyfin player's
              // one-tap track control (its own gear keeps Quality/Speed/Chapters).
              if (_captions.isNotEmpty)
                _ctlButton(
                  focusNode: _fCaption,
                  icon: Icons.closed_caption_rounded,
                  tooltip: l.playerSubtitles,
                  onTap: () {
                    _menuReturn = _fCaption;
                    _pickCaption();
                  },
                ),
              if (widget.onShowActions != null)
                _ctlButton(
                  focusNode: _fActions,
                  icon: Icons.more_vert_rounded,
                  tooltip: l.commonMore,
                  onTap: () {
                    _menuReturn = _fActions;
                    widget.onShowActions!();
                  },
                ),
              _ctlButton(
                focusNode: _fSettings,
                icon: Icons.settings_rounded,
                tooltip: l.playerSettings,
                onTap: () {
                  _menuReturn = _fSettings;
                  _showSettings();
                },
              ),
            ],
          ),
        ],
      ),
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: Stack(
        children: [
          Positioned.fill(
            child: GlassSurface(
              blur: 7,
              color: Colors.black.withValues(alpha: 0.18),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.26),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          bar,
        ],
      ),
    );
  }

  Widget _ctlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required FocusNode focusNode,
  }) {
    // Shared spring/press/focus-ring animation, matching the media_kit bar.
    return AnimatedIconButton(
      icon: icon,
      tooltip: tooltip,
      onTap: onTap,
      focusNode: focusNode,
    );
  }
}

/// Wraps a caption picker result so "Off" (a null caption) is distinguishable
/// from dismissing the sheet (which returns null).
class _CaptionChoice {
  const _CaptionChoice(this.caption);
  final YoutubeCaption? caption;
}
