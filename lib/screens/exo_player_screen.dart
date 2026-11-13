import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/jellyfin_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../models/media_segment.dart';
import '../models/session.dart';
import '../services/live_streams.dart';
import '../services/tv_mode.dart';
import '../state/cast.dart';
import '../state/library_providers.dart';
import '../state/preferences.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../state/syncplay.dart';
import '../state/syncplay_session.dart';
import '../widgets/animated_control.dart';
import '../widgets/cast_button.dart';
import '../widgets/cast_remote.dart';
import '../widgets/player_prompts.dart';
import '../widgets/exo_stats_panel.dart';
import '../widgets/glass.dart';
import '../widgets/exo_video.dart';
import '../widgets/live_info_panel.dart';
import '../widgets/live_record_button.dart';
import '../state/sleep_timer.dart';
import '../widgets/sleep_timer_sheet.dart';
import '../widgets/app_spinner.dart';
import '../services/system_pip_controls.dart';

/// Whether the native Media3 ExoPlayer backend should handle playback, given the
/// user's `playerBackend` preference. Android only.
bool exoBackendActive(String backendPref) {
  if (!isAndroidPlatform) return false;
  switch (backendPref) {
    case 'exoplayer':
      return true;
    case 'mediakit':
      return false;
    default: // 'auto' — ExoPlayer on a TV, media_kit elsewhere.
      return isTvDevice;
  }
}

/// Full-screen playback on the native Media3 ExoPlayer backend (tunneled 4K/HDR).
/// Fathom's own D-pad transport is drawn over the native surface. Track pickers,
/// trickplay and SyncPlay come in a later stage; this screen covers render +
/// resume + transport + progress reporting.
class ExoPlayerScreen extends ConsumerStatefulWidget {
  final BaseItemDto item;
  final bool resume;
  const ExoPlayerScreen({super.key, required this.item, this.resume = true});

  @override
  ConsumerState<ExoPlayerScreen> createState() => _ExoPlayerScreenState();
}

class _ExoPlayerScreenState extends ConsumerState<ExoPlayerScreen> {
  VoidCallback? _unregisterSleep;
  // Player-agnostic native PiP channel: `setActive` tells the Activity a video
  // is playing (so leaving the app floats it into a PiP window) and the native
  // side calls back `pipModeChanged` on enter/exit. Same channel the media_kit
  // player uses; only one player is active at a time.
  static const _pipChannel = MethodChannel('app.fathom.player/pip');
  final _controller = ExoVideoController();
  Session? _session;
  // Cached so dispose() can report stopped / close the live stream without
  // ref.read (using ref during dispose throws "used after unmount").
  JellyfinClient? _client;
  // Start hidden: opening the player should show just the video, not the control
  // chrome over the still-transitioning home/hero. Any D-pad key reveals it.
  bool _controlsVisible = false;
  bool _started = false;
  String? _error;
  Timer? _hideTimer;
  Timer? _reportTimer;
  StreamSubscription<String>? _errSub;
  IconData? _flashIcon;
  Timer? _flashTimer;
  double _speed = 1.0;
  int _bitrate = 0; // 0 = Auto
  bool _statsOpen = false;
  // Media Segments (Skip Intro / Skip Credits). Empty until fetched; the active
  // segment drives the on-screen skip button. _autoSkipped dedups a segment we
  // already handled so its button doesn't re-flash after we jump past it.
  List<MediaSegment> _segments = const [];
  MediaSegment? _activeSkip;
  final Set<int> _autoSkipped = {};
  // The focus target the remote lands on while a skip button is showing (TV),
  // and whatever had focus before so we can hand it back when the button clears.
  final _fSkip = FocusNode(debugLabel: 'exoSkip');
  FocusNode? _preSkipFocus;
  // Up Next prompt (credits of an episode that has a next one). Mirrors the
  // media_kit player: replaces the Skip Credits pill and advances to the next
  // episode. Null when not shown.
  ({BaseItemDto item, int? remaining, int total})? _upNext;
  bool _upNextHidden = false; // user pressed Hide for this episode
  bool _advancingNext = false; // guards the auto-advance from double-firing
  int? _upNextSegTicks; // the credits segment currently driving Up Next
  Duration? _upNextAnchor; // where the card appeared (credits start or seek-in)
  bool _upNextCounted = false; // the countdown ran down via playback (not a seek)
  bool _upNextSuppressed = false; // seeked back in the credits: hide until forward
  bool _upNextFocused = false; // D-pad landed on the Up Next card (TV), captured once
  final _fUpNextPlay = FocusNode(debugLabel: 'exoUpNextPlay');
  final _fUpNextHide = FocusNode(debugLabel: 'exoUpNextHide');
  // Trickplay scrub-preview geometry (VOD only). Null until loaded / if absent.
  TrickplayInfo? _trickplay;
  int? _trickWidth;
  // SyncPlay ("watch together"). This player joins the group when one is active;
  // the transport drives it and incoming group commands drive the transport.
  // _groupSuppress stops an applied command (or a programmatic seek) echoing
  // back; _deactivated gates _inGroup during teardown; the cue drives the
  // syncing/skip-to-sync overlay. State transitions are diffed off ExoState, so
  // we cache the last playing/buffering to detect edges.
  bool _groupSuppress = false;
  bool _deactivated = false;
  bool _disposed = false;
  Timer? _groupSuppressTimer;
  bool _reportedBuffering = false;
  Timer? _buffDebounce;
  String? _syncCue; // 'sync' | 'fwd' | 'back' | null
  Timer? _syncCueTimer;
  Duration _lastPos = Duration.zero;
  bool _wasPlaying = false;
  bool _wasBuffering = false;
  // The target of a seek we applied FROM the group. On this backend an HLS seek
  // re-buffers and can settle after the suppress window; without tracking it, the
  // settling position-jump gets re-broadcast as a fresh seek and the group
  // ping-pongs (the stutter). Cleared once the position reaches it.
  Duration? _appliedSeekTarget;
  SyncPlaySession? _syncSessionRef;
  // True while the system has floated us into a Picture-in-Picture window; the
  // control chrome and overlays hide so the OS draws its own compact controls.
  bool _inPip = false;
  // Live TV: the ids that hand the tuner back on exit (see LiveStreams).
  String? _liveStreamId;
  String? _livePlaySessionId;
  bool get _isLive => widget.item.isLiveChannel;
  // Sibling episodes for previous/next (TV episodes only).
  List<BaseItemDto> _episodes = const [];
  int _epIndex = -1;
  // Deterministic focus targets — the remote steps through these explicitly
  // (Flutter's geometric traversal mis-scores the full-width seek bar + gaps),
  // so ◀/▶ always reaches every visible button and never cycles.
  final _fSeek = FocusNode(debugLabel: 'exoSeek');
  final _fPlay = FocusNode(debugLabel: 'exoPlay');
  final _fBack = FocusNode(debugLabel: 'exoBack');
  final _fFwd = FocusNode(debugLabel: 'exoFwd');
  final _fPrev = FocusNode(debugLabel: 'exoPrev');
  final _fNext = FocusNode(debugLabel: 'exoNext');
  final _fSubs = FocusNode(debugLabel: 'exoSubs');
  final _fAudio = FocusNode(debugLabel: 'exoAudio');
  final _fRecord = FocusNode(debugLabel: 'exoRecord');
  final _fSettings = FocusNode(debugLabel: 'exoSettings');

  // The visible button focus nodes, left-to-right (matches the rendered row).
  // Live TV drops the skip/quality/episode controls (a broadcast has no seek
  // ladder or siblings) and leads with Record, mirroring the media_kit live bar.
  List<FocusNode> _buttonOrder() {
    if (_isLive) {
      return [
        if (widget.item.currentProgram != null) _fRecord,
        _fPlay,
        if (_controller.textTracks.value.isNotEmpty) _fSubs,
        if (_controller.audioTracks.value.isNotEmpty) _fAudio,
        _fSettings,
      ];
    }
    return [
      _fPlay,
      _fBack,
      _fFwd,
      if (_epIndex > 0) _fPrev,
      if (_epIndex >= 0 && _epIndex < _episodes.length - 1) _fNext,
      if (_controller.textTracks.value.isNotEmpty) _fSubs,
      if (_controller.audioTracks.value.isNotEmpty) _fAudio,
      _fSettings,
    ];
  }

  @override
  void initState() {
    super.initState();
    _errSub = _controller.errors.listen((e) {
      if (mounted) setState(() => _error = e);
    });
    _controller.state.addListener(_onState);
    _controller.textTracks.addListener(_onTracks);
    _controller.audioTracks.addListener(_onTracks);
    // Sleep timer: fade out and pause. ExoPlayer's volume is its own 0-1 gain
    // (never the remembered app volume), so it simply goes back to full.
    _unregisterSleep =
        ref.read(sleepTimerProvider.notifier).register((fade) async {
      if (!_controller.state.value.playing) return;
      const stepEvery = Duration(milliseconds: 250);
      final steps = (fade.inMilliseconds / stepEvery.inMilliseconds).ceil();
      for (var i = 1; i <= steps; i++) {
        await Future<void>.delayed(stepEvery);
        if (!mounted || !_controller.state.value.playing) break;
        await _controller.setVolume(1 - i / steps);
      }
      if (!mounted) return;
      await _controller.pause();
      await _controller.setVolume(1);
    });
    // Register for SyncPlay follow: increments the open-player count so a group
    // item-switch REPLACES this route instead of stacking a second player.
    final syncSession = ref.read(syncPlaySessionProvider);
    _syncSessionRef = syncSession;
    syncSession.notifyPlayerOpened();
    _enterImmersiveLandscape();
    _enableSystemPip();
    // Controls start hidden; the root Focus (autofocus) holds focus so the first
    // D-pad key reveals them (see _onKey). No hide timer needed up front.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Re-assert the landscape lock once we're in the tree, in case the
      // initState call landed before the engine applied it.
      _enterImmersiveLandscape();
      _start();
    });
  }

  // System Picture-in-Picture (Android phone/tablet). PiP is a phone/desktop
  // paradigm, so it stays off on TV. The native side is player-agnostic, so
  // this just mirrors the media_kit wiring.
  void _enableSystemPip() {
    if (!isAndroidPlatform || isTvDevice) return;
    _pipChannel.setMethodCallHandler((call) async {
      if (call.method == 'pipModeChanged' && mounted) {
        final inPip = call.arguments == true;
        setState(() => _inPip = inPip);
        // The OS owns sizing/orientation inside a PiP window; drop our immersive
        // landscape lock while floating and restore it when the window expands.
        inPip ? _restoreSystemUi() : _enterImmersiveLandscape();
      }
      return null;
    });
    _pipChannel.invokeMethod('setActive', true);
    SystemPipControls.claimPip(this);
    // The PiP window's own buttons (same skips as the on-screen ones).
    // Labels need the localizations, which aren't readable in initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      SystemPipControls.bind(
        owner: this,
        playing: _controller.state.value.playing,
        onPlay: () async => _safePlay(),
        onPause: () async => _safePause(),
        onSeekBy: _seekBy,
        backSeconds: 10,
        forwardSeconds: 30,
        playPauseLabel: l.playerPlayPause,
        backLabel: l.playerSeekBack(10),
        forwardLabel: l.playerSeekForward(30),
      );
    });
  }

  void _disableSystemPip() {
    if (!isAndroidPlatform || isTvDevice) return;
    SystemPipControls.unbind(this);
    // The next episode's screen already took PiP over: leave it on.
    if (!SystemPipControls.releasePip(this)) return;
    _pipChannel.invokeMethod('setActive', false);
    _pipChannel.setMethodCallHandler(null);
  }

  // Phone/tablet only: lock landscape and hide the system bars while playing, so
  // the video fills the screen and never rotates into a stretched portrait. TV is
  // already fixed-landscape fullscreen, so this stays off there (zero TV change).
  bool get _managesOrientation => isAndroidPlatform && !isTvDevice;

  void _enterImmersiveLandscape() {
    if (!_managesOrientation) return;
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _restoreSystemUi() {
    if (!_managesOrientation) return;
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _focusPlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controlsVisible) _fPlay.requestFocus();
    });
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

  // The bar button a menu was opened from, so closing it returns focus there
  // instead of snapping back to Play.
  FocusNode? _menuReturn;
  void _restoreMenuFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) (_menuReturn ?? _fPlay).requestFocus();
    });
  }

  Future<void> _start() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    _session = session;
    final client = ref.read(jellyfinClientProvider);
    _client = client; // for dispose()
    try {
      // Live TV opens a tuner (which must be handed back on exit) and never
      // resumes or reports progress; VOD opens a normal stream and does both.
      if (_isLive) {
        final handle = await client.openLiveStream(
          baseUrl: session.baseUrl,
          userId: session.userId,
          token: session.accessToken,
          channelId: widget.item.id,
        );
        _liveStreamId = handle.liveStreamId;
        _livePlaySessionId = handle.playSessionId;
        // Registered so quitting the app mid-channel still frees the tuner.
        if (handle.liveStreamId != null) {
          LiveStreams.register(OpenLiveStream(
            client: client,
            session: session,
            liveStreamId: handle.liveStreamId!,
            playSessionId: handle.playSessionId,
          ));
        }
        await _waitForAttach();
        if (!mounted) return;
        await _controller.load(handle.url, play: true);
        _started = true;
        // Live TV in a SyncPlay group: broadcast the channel so members follow to
        // it; it plays at the live edge, so report ready-and-playing once loaded.
        if (_inGroup) {
          final syncSession = ref.read(syncPlaySessionProvider);
          unawaited(syncSession
              .setNewQueue([widget.item.id], 0, Duration.zero).then((_) {
            _reportReadyWhenLoaded(Duration.zero, playing: true);
          }));
        } else {
          ref.read(syncPlaySessionProvider).setLocalItem(widget.item.id);
        }
        return;
      }
      final url = await client.openVideoStream(
        baseUrl: session.baseUrl,
        userId: session.userId,
        token: session.accessToken,
        itemId: widget.item.id,
      );
      // Resume ticks are 100ns units; ExoPlayer wants milliseconds.
      final resumeMs = widget.resume
          ? (widget.item.resumePositionTicks ~/ 10000)
          : 0;
      // SyncPlay: a FOLLOWER (opened because the group switched to this item)
      // starts PAUSED at the group's position and waits for the server's
      // synchronized Unpause; an INITIATOR (or solo playback) plays from its own
      // resume point. Either way we report Ready and let the server drive play.
      final syncSession = ref.read(syncPlaySessionProvider);
      final inGroupVod = _inGroup;
      final syncing = inGroupVod && syncSession.isFollowOpen(widget.item.id);
      var startAt = Duration(milliseconds: resumeMs);
      if (syncing && syncSession.groupStartPosition > Duration.zero) {
        startAt = syncSession.groupStartPosition;
      }
      // Wait for the platform view to bind its channel, then load.
      await _waitForAttach();
      if (!mounted) return;
      // The initial seek to startAt isn't a user action; don't let it broadcast.
      if (inGroupVod) _suppressGroup();
      _lastPos = startAt;
      await _controller.load(url, start: startAt, play: !syncing);
      _started = true;
      unawaited(client.reportPlaybackStart(
        baseUrl: session.baseUrl,
        token: session.accessToken,
        itemId: widget.item.id,
        positionTicks: startAt.inMilliseconds * 10000,
      ));
      if (inGroupVod) {
        // Broadcast the context queue (a no-op echo for followers), then report
        // Ready once loaded; the server auto-broadcasts Unpause when every member
        // is ready. A follower shows the syncing cue until then.
        final (queue, pos) = await _buildGroupQueue(session);
        unawaited(syncSession.setNewQueue(queue, pos, startAt).then((_) {
          _reportReadyWhenLoaded(startAt, playing: !syncing);
        }));
        if (syncing) _setSyncCue('sync');
      } else {
        syncSession.setLocalItem(widget.item.id);
      }
      _reportTimer = Timer.periodic(
          const Duration(seconds: 10), (_) => _reportProgress());
      // Media Segments (intro/credits) for the Skip button. Degrades to an empty
      // list when the server has no Media Segments provider, so it's best-effort.
      unawaited(client
          .getMediaSegments(
            baseUrl: session.baseUrl,
            token: session.accessToken,
            itemId: widget.item.id,
          )
          .then((segs) {
        if (mounted) _segments = segs;
      }));
      unawaited(_loadTrickplay(client, session));
      // Load sibling episodes for the previous/next buttons.
      if (widget.item.isEpisode &&
          (widget.item.seriesId?.isNotEmpty ?? false)) {
        try {
          final eps = await client.getEpisodes(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            seriesId: widget.item.seriesId!,
          );
          if (mounted) {
            setState(() {
              _episodes = eps;
              _epIndex = eps.indexWhere((e) => e.id == widget.item.id);
            });
          }
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  // Trickplay geometry usually isn't on the list item, so refetch the full item
  // when it's missing. Best-effort: a server without trickplay just leaves the
  // preview off. Mirrors the media_kit player's loader.
  Future<void> _loadTrickplay(JellyfinClient client, Session session) async {
    var info = widget.item.trickplayInfo;
    var width = widget.item.trickplayWidth;
    if (info == null) {
      try {
        final full = await client.getItem(
          baseUrl: session.baseUrl,
          userId: session.userId,
          token: session.accessToken,
          itemId: widget.item.id,
        );
        info = full.trickplayInfo;
        width = full.trickplayWidth;
      } catch (_) {
        return;
      }
    }
    if (info != null && width != null && mounted) {
      setState(() {
        _trickplay = info;
        _trickWidth = width;
      });
    }
  }

  void _goEpisode(int i) {
    if (i < 0 || i >= _episodes.length) return;
    context.pushReplacement('/player',
        extra: (item: _episodes[i], resume: false));
  }

  // Chromecast (phone/tablet). Resolves what to hand the chosen target: a
  // direct-play file when its codecs fit the receiver, else an HLS transcode.
  Future<({String url, String contentType})?> _castMedia() async {
    final session = _session;
    if (session == null) return null;
    try {
      return await ref.read(jellyfinClientProvider).castStream(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            itemId: widget.item.id,
          );
    } catch (_) {
      return null;
    }
  }

  String _castTitle() => (_epIndex >= 0 && _epIndex < _episodes.length)
      ? _episodes[_epIndex].name
      : widget.item.name;

  String? _castArtworkUrl() {
    final session = _session;
    if (session == null || widget.item.primaryImageTag == null) return null;
    return ref.read(jellyfinClientProvider).imageUrl(
          baseUrl: session.baseUrl,
          itemId: widget.item.id,
          type: 'Primary',
          tag: widget.item.primaryImageTag,
        );
  }

  Future<void> _castEpisodeAt(int i) async {
    if (i < 0 || i >= _episodes.length) return;
    final ep = _episodes[i];
    final session = _session;
    if (session == null) return;
    try {
      final media = await ref.read(jellyfinClientProvider).castStream(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            itemId: ep.id,
          );
      await ref.read(castControllerProvider.notifier).loadMedia(
            url: media.url,
            contentType: media.contentType,
            title: ep.name,
          );
      if (mounted) setState(() => _epIndex = i);
    } catch (_) {}
  }

  Future<void> _reloadAtBitrate(int bitrate) async {
    final s = _session;
    if (s == null) return;
    _bitrate = bitrate;
    final pos = _controller.state.value.position;
    try {
      final url = await ref.read(jellyfinClientProvider).openVideoStream(
            baseUrl: s.baseUrl,
            userId: s.userId,
            token: s.accessToken,
            itemId: widget.item.id,
            maxBitrate: bitrate > 0 ? bitrate : null,
          );
      await _controller.load(url, start: pos, play: true);
    } catch (_) {}
  }

  /// The desktop player's overflow (⋮) menu: quality, chapters, speed. Returns a
  /// choice and opens the chosen sub-menu AFTER this one closes (never nested —
  /// a sheet-over-a-sheet loses the remote's focus).
  Future<void> _showSettings() async {
    final scheme = Theme.of(context).colorScheme;
    // Quality, Chapters and Speed are meaningless on a live broadcast (no
    // transcode ladder, no chapters, always 1x), so the live gear shows only
    // Playback Info — same as the media_kit live player. Playback Info is now in
    // every player's gear, so all three read the same.
    final hasChapters = !_isLive && widget.item.chapters.isNotEmpty;
    final l = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: scheme.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(l.playerSettings,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (!_isLive)
              ListTile(
                autofocus: true,
                leading: const Icon(Icons.high_quality_rounded),
                title: Text(l.playerQuality),
                subtitle: Text(_qualityOptions
                    .firstWhere((o) => o.$1 == _bitrate,
                        orElse: () => _qualityOptions.first)
                    .$2),
                onTap: () => Navigator.of(ctx).pop('quality'),
              ),
            if (hasChapters)
              ListTile(
                leading: const Icon(Icons.bookmarks_rounded),
                title: Text(l.playerChapters),
                onTap: () => Navigator.of(ctx).pop('chapters'),
              ),
            if (!_isLive)
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: Text(l.playerPlaybackSpeed),
                subtitle: Text(_speed == 1.0 ? 'Normal' : '${_speed}x'),
                onTap: () => Navigator.of(ctx).pop('speed'),
              ),
            ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: Text(l.sleepTimer),
              onTap: () => Navigator.of(ctx).pop('sleep'),
            ),
            ListTile(
              autofocus: _isLive,
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(l.playerPlaybackInfo),
              onTap: () => Navigator.of(ctx).pop('stats'),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'quality':
        await _pickQuality();
      case 'chapters':
        await _pickChapter();
      case 'speed':
        await _pickSpeed();
      case 'sleep':
        if (!mounted) return;
        await showSleepTimerSheet(context,
            endOfItemLabel: _isLive
                ? null
                : widget.item.isEpisode
                    ? l.sleepTimerEndOfEpisode
                    : l.sleepTimerEndOfVideo);
        if (mounted) _restoreMenuFocus();
      case 'stats':
        setState(() => _statsOpen = !_statsOpen);
        _show();
        _restoreMenuFocus();
      default:
        _restoreMenuFocus(); // dismissed without choosing
    }
  }

  // The desktop player's quality ladder, verbatim.
  static const _qualityOptions = <(int, String)>[
    (0, 'Auto'),
    (120000000, '4K - 120 Mbps'),
    (60000000, '1080p - 60 Mbps'),
    (40000000, '1080p - 40 Mbps'),
    (20000000, '1080p - 20 Mbps'),
    (15000000, '1080p - 15 Mbps'),
    (10000000, '1080p - 10 Mbps'),
    (8000000, '720p - 8 Mbps'),
    (6000000, '720p - 6 Mbps'),
    (4000000, '720p - 4 Mbps'),
    (3000000, '480p - 3 Mbps'),
    (1500000, '480p - 1.5 Mbps'),
    (720000, '480p - 720 kbps'),
    (420000, '360p - 420 kbps'),
  ];

  Future<void> _pickQuality() async {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
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
            for (final (bitrate, label) in _qualityOptions)
              ListTile(
                autofocus: _bitrate == bitrate,
                title: Text(label),
                trailing: _bitrate == bitrate
                    ? Icon(Icons.check_rounded, color: scheme.primary)
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _reloadAtBitrate(bitrate);
                },
              ),
          ],
        ),
      ),
    );
    _show();
    _restoreMenuFocus();
  }

  Future<void> _pickChapter() async {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final chapters = widget.item.chapters;
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
            for (var i = 0; i < chapters.length; i++)
              ListTile(
                autofocus: i == 0,
                title: Text(chapters[i].name ?? 'Chapter ${i + 1}'),
                trailing: Text(_fmt(chapters[i].start),
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _controller.seekTo(chapters[i].start);
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

  Future<void> _waitForAttach() async {
    for (var i = 0; i < 100 && !_controller.isAttached; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  void _onState() {
    if (!mounted) return;
    final s = _controller.state.value;
    SystemPipControls.update(owner: this, playing: s.playing);
    // A live broadcast never "ends"; only VOD auto-closes on completion.
    if (s.ended && _started && !_isLive) {
      _started = false;
      // Closing is also the stop the sleep timer wanted, if it was set to
      // the end of this one.
      ref.read(sleepTimerProvider.notifier).consumeEndOfItem();
      Navigator.of(context).maybePop();
      return;
    }
    if (!_isLive && _segments.isNotEmpty) _checkSegments(s.position);
    _onSyncState(s);
    // No blanket setState here: the position/time, play icon and buffering
    // spinner each rebuild through their own ValueListenableBuilder on
    // _controller.state, so the control BUTTONS aren't rebuilt ~10x/second (which
    // reset their focus + press/scale animation). Track/episode changes and the
    // discrete UI flags (controls shown, skip, cue) drive their own setState.
  }

  void _onTracks() {
    // The audio/subtitle buttons (and D-pad order) depend on the track lists,
    // which arrive a beat after load. Rebuild when they change.
    if (mounted) setState(() {});
  }

  // SyncPlay outgoing side: turn ExoState edges into group drives. media_kit
  // gets separate playing/buffering/position streams; here we diff the merged
  // ExoState against the last values to spot the same transitions.
  void _onSyncState(ExoState s) {
    // Play/pause edge → drive the group (only a real user flip, hence _started
    // and !_groupSuppress; the initial-load flips and applied commands are out).
    if (s.playing != _wasPlaying) {
      _wasPlaying = s.playing;
      if (s.playing && _syncCue == 'sync') _clearSyncCue();
      if (_started && !_groupSuppress && _inGroup) {
        final session = ref.read(syncPlaySessionProvider);
        s.playing ? session.unpause() : session.pause();
      }
    }
    // Buffering edge → report to the group so everyone waits for a slow member.
    // Debounced so media_kit-style transient toggles don't yo-yo the group.
    if (s.buffering != _wasBuffering) {
      _wasBuffering = s.buffering;
      if (!_isLive && _inGroup) {
        final session = ref.read(syncPlaySessionProvider);
        if (session.currentPlaylistItemId != null) {
          _buffDebounce?.cancel();
          if (s.buffering) {
            _buffDebounce = Timer(const Duration(milliseconds: 350), () {
              if (!_inGroup || !_controller.state.value.buffering) return;
              _reportedBuffering = true;
              session.reportBuffering(_controller.state.value.position,
                  playing: _controller.state.value.playing);
            });
          } else if (_reportedBuffering) {
            _reportedBuffering = false;
            session.reportReady(_controller.state.value.position,
                playing: _controller.state.value.playing);
          }
        }
      }
    }
    // Position jump = a user seek → drive the group. But NOT while buffering
    // (position is unreliable then) and NOT when the local player is just
    // converging on a seek we applied from the group (which on this backend can
    // settle after the suppress window and would otherwise re-broadcast, making
    // the whole group ping-pong seeks — the reported stutter).
    if (!_isLive && _inGroup && !_groupSuppress && !s.buffering) {
      final jumped =
          (s.position - _lastPos).abs() > const Duration(milliseconds: 2500);
      final settling = _appliedSeekTarget != null &&
          (s.position - _appliedSeekTarget!).abs() <
              const Duration(seconds: 3);
      if (settling) {
        _appliedSeekTarget = null; // reached the applied target; not a user seek
      } else if (jumped) {
        ref.read(syncPlaySessionProvider).seek(s.position);
      }
    }
    _lastPos = s.position;
  }

  // The playing/buffering/position callbacks can fire once more while the screen
  // is being torn down; reading a provider from a deactivated element throws, so
  // gate on both flags (mounted alone is still true in deactivate()).
  bool get _inGroup =>
      mounted && !_deactivated && ref.read(syncPlayControllerProvider);

  /// Ignore player-state edges for a beat so an applied group command (or our
  /// own auto-skip / initial seek) isn't echoed back to the group.
  void _suppressGroup() {
    _groupSuppress = true;
    _groupSuppressTimer?.cancel();
    // Longer than the media_kit player's 900ms: a native HLS seek on a low-power
    // TV settles slower, and re-broadcasting mid-settle is what stuttered the
    // group. _appliedSeekTarget is the backstop once this window lapses.
    _groupSuppressTimer = Timer(
        const Duration(milliseconds: 1500), () => _groupSuppress = false);
  }

  // Applies an incoming group command to the local transport without echoing it.
  void _applySyncCommand(SyncCommand? c) {
    if (c == null || _disposed) return;
    if (!ref.read(syncPlayControllerProvider)) return;
    final isLive = _isLive;
    _suppressGroup();
    if (c.position > Duration.zero) _lastPos = c.position;
    switch (c.command) {
      case 'Unpause':
        if (!isLive && c.position > Duration.zero) {
          _appliedSeekTarget = c.position;
          _safeSeek(c.position);
        }
        _safePlay();
        _clearSyncCue();
      case 'Pause':
        _safePause();
        if (!isLive && c.position > Duration.zero) {
          _appliedSeekTarget = c.position;
          _safeSeek(c.position);
        }
        _setSyncCue('sync');
      case 'Seek':
        if (isLive) break;
        final here = _controller.state.value.position;
        _flashSyncCue(c.position > here + const Duration(seconds: 1)
            ? 'fwd'
            : c.position < here - const Duration(seconds: 1)
                ? 'back'
                : 'sync');
        _appliedSeekTarget = c.position;
        _safeSeek(c.position);
      case 'Stop':
        _safePause();
        _setSyncCue('sync');
    }
  }

  void _safeSeek(Duration d) => _controller.seekTo(d).catchError((_) {});
  void _safePlay() => _controller.play().catchError((_) {});
  void _safePause() => _controller.pause().catchError((_) {});

  void _setSyncCue(String cue) {
    _syncCueTimer?.cancel();
    if (_syncCue != cue && mounted) setState(() => _syncCue = cue);
  }

  void _flashSyncCue(String cue) {
    _syncCueTimer?.cancel();
    if (mounted) setState(() => _syncCue = cue);
    _syncCueTimer = Timer(const Duration(milliseconds: 1100), _clearSyncCue);
  }

  void _clearSyncCue() {
    _syncCueTimer?.cancel();
    if (_syncCue != null && mounted) setState(() => _syncCue = null);
  }

  /// The context queue to broadcast when INITIATING group playback: for an
  /// episode, the whole series in order; otherwise a single-item queue.
  /// Followers skip this (setNewQueue is a no-op echo for them).
  Future<(List<String>, int)> _buildGroupQueue(Session session) async {
    final item = widget.item;
    if (item.isEpisode &&
        (item.seriesId?.isNotEmpty ?? false) &&
        !ref.read(syncPlaySessionProvider).isFollowOpen(item.id)) {
      try {
        final eps = await ref.read(jellyfinClientProvider).getEpisodes(
              baseUrl: session.baseUrl,
              userId: session.userId,
              token: session.accessToken,
              seriesId: item.seriesId!,
            );
        final ids = [for (final e in eps) e.id];
        final idx = ids.indexOf(item.id);
        if (idx >= 0) return (ids, idx);
      } catch (_) {}
    }
    return ([item.id], 0);
  }

  // Report Ready to the group, but only once the media has loaded AND the
  // server's PlaylistItemId is known — a Ready sent too early is rejected and
  // stalls the whole group.
  Future<void> _reportReadyWhenLoaded(Duration position,
      {required bool playing}) async {
    final session = ref.read(syncPlaySessionProvider);
    for (var i = 0;
        i < 200 && !_disposed && _controller.state.value.duration <= Duration.zero;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    for (var i = 0;
        i < 50 && !_disposed && session.currentPlaylistItemId == null;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (_disposed || !_inGroup) return;
    unawaited(session.reportReady(position, playing: playing));
  }

  // Matches the current position to a skippable segment and drives the Skip
  // button. Auto-skips when the per-category preference is on. Mirrors the
  // media_kit player's logic; setState is handled by the caller (_onState).
  void _checkSegments(Duration pos) {
    // A late state event during teardown must not read providers after unmount.
    if (_disposed || _deactivated || !mounted) return;
    // Up Next seek detection (uses the still-previous _lastPos; _onState updates
    // it after this call). A jump back hides the card; forward progress shows it.
    final backSeek = pos < _lastPos - const Duration(seconds: 2);
    final forwardProgress = pos > _lastPos;
    MediaSegment? active;
    for (final seg in _segments) {
      if (seg.isSkippable && seg.contains(pos)) {
        active = seg;
        break;
      }
    }
    if (active != null) {
      final prefs = ref.read(preferencesProvider).asData?.value;
      final auto = (active.isIntro && (prefs?.autoSkipIntro ?? false)) ||
          (active.isCredits && (prefs?.autoSkipCredits ?? false));
      if (auto && !_autoSkipped.contains(active.startTicks)) {
        _autoSkipped.add(active.startTicks);
        _suppressGroup(); // an auto-skip isn't a user seek; don't broadcast it
        _controller.seekTo(active.end);
        active = null;
      }
    }
    // Credits of an episode with a next episode → the Up Next prompt takes over
    // (its action goes to the NEXT episode); the Skip Credits pill is suppressed.
    final hasNext = widget.item.isEpisode &&
        _epIndex >= 0 &&
        _epIndex + 1 < _episodes.length;
    final inCredits = active != null && active.isCredits && hasNext;
    if (inCredits) {
      final seg = active;
      active = null;
      if (!_upNextHidden) {
        if (backSeek) {
          // Seeked back inside the credits: hide the prompt.
          _upNextSuppressed = true;
        } else if (_upNextSuppressed && forwardProgress) {
          // Playing forward again: bring it back with a fresh countdown.
          _upNextSuppressed = false;
          _upNextAnchor = pos;
          _upNextCounted = false;
        }
      }
      if (_upNextHidden || _upNextSuppressed) {
        _dismissUpNext();
      } else {
        _handleUpNext(seg, pos);
      }
    } else {
      // Left the credits entirely → clear the back-seek suppression so re-entering
      // (by playing forward) shows the card again.
      _upNextSuppressed = false;
      _dismissUpNext();
    }
    if (active?.startTicks != _activeSkip?.startTicks) {
      final wasNull = _activeSkip == null;
      if (mounted) setState(() => _activeSkip = active);
      // On TV the button is the only reachable control while it shows, so pull
      // the remote onto it and hand focus back to wherever it was afterwards.
      if (isTvDevice) {
        if (active != null && wasNull) {
          _preSkipFocus = FocusManager.instance.primaryFocus;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _activeSkip != null) _fSkip.requestFocus();
          });
        } else if (active == null && !wasNull) {
          _preSkipFocus?.requestFocus();
        }
      }
    }
  }

  void _doSkip() {
    final seg = _activeSkip;
    if (seg == null) return;
    _autoSkipped.add(seg.startTicks); // stop the position tick re-flashing it
    _suppressGroup();
    _controller.seekTo(seg.end);
    setState(() => _activeSkip = null);
    if (isTvDevice) _preSkipFocus?.requestFocus();
  }

  /// Type-aware skip label (Recap vs Intro vs Credits).
  String _exoSkipLabel(MediaSegment seg) {
    final l = AppLocalizations.of(context);
    switch (seg.type) {
      case 'Recap':
        return l.playerSkipRecap;
      case 'Outro':
        return l.playerSkipCredits;
      case 'Intro':
        return l.playerSkipIntro;
      default:
        return l.playerSkipSegment(seg.categoryLabel(l));
    }
  }

  /// Drives the Up Next prompt during credits. Timing: 0 = Full (counts down to
  /// the real end of the credits); N = a fixed N-second countdown from where the
  /// card appears (_upNextAnchor: the credits start when played through, or the
  /// seek target when you jump in). Autoplay next = whether it auto-advances.
  /// Mirrors the media_kit path.
  void _handleUpNext(MediaSegment seg, Duration pos) {
    final prefs = ref.read(preferencesProvider).asData?.value;
    // No countdown into the next episode when the sleep timer is set to stop
    // at the end of this one.
    final autoplayOn = (prefs?.autoplayNext ?? true) &&
        !ref.read(sleepTimerProvider.notifier).stopsAtEndOfItem;
    final lead = prefs?.upNextLeadSeconds ?? 20;
    final segId = seg.startTicks;
    if (_upNextSegTicks != segId) {
      _upNextSegTicks = segId;
      _upNextCounted = false;
      // Anchor the countdown to WHERE the card first appears this segment: the
      // credits start when played through, or the seek target when you jump in.
      // So seeking into the credits gets a fresh countdown instead of one
      // already eaten by the skipped-over seconds.
      _upNextAnchor = pos;
    }
    final creditsLen = (seg.end - seg.start).inSeconds;
    final int total;
    int remainingSecs;
    if (lead <= 0) {
      // Full: run to the real end of the credits (position-based).
      total = creditsLen < 1 ? 1 : creditsLen;
      remainingSecs = (seg.end - pos).inSeconds;
    } else {
      // Fixed N seconds, measured from the anchor (appearance / seek-in).
      total = lead;
      remainingSecs = lead - (pos - (_upNextAnchor ?? seg.start)).inSeconds;
    }
    if (remainingSecs < 0) remainingSecs = 0;
    if (remainingSecs > total) remainingSecs = total; // never grow past the length
    final int? remaining = autoplayOn ? remainingSecs : null;
    if (autoplayOn && remainingSecs > 0) _upNextCounted = true;

    // Only auto-advance on a genuine run-down, not a manual seek straight to the
    // end (which would otherwise jump to the next episode).
    if (autoplayOn && remainingSecs <= 0 && _upNextCounted && !_advancingNext) {
      _advancingNext = true;
      _goEpisode(_epIndex + 1);
      return;
    }

    final next = _episodes[_epIndex + 1];
    final value = (item: next, remaining: remaining, total: total);
    if (_upNext != value && mounted) {
      setState(() => _upNext = value);
      // Capture the pre-card focus ONCE per appearance (a re-show after a
      // back-seek must not overwrite it with the now-removed card node).
      if (isTvDevice && !_upNextFocused) {
        _upNextFocused = true;
        _preSkipFocus = FocusManager.instance.primaryFocus;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _upNext != null) _fUpNextPlay.requestFocus();
        });
      }
    }
  }

  // Clears the Up Next card and, on TV, hands the D-pad back to wherever it was
  // before the card grabbed it (captured once per appearance in _handleUpNext).
  void _dismissUpNext() {
    if (_upNext != null && mounted) setState(() => _upNext = null);
    if (isTvDevice && _upNextFocused) {
      _upNextFocused = false;
      _preSkipFocus?.requestFocus();
    }
  }

  void _upNextPlayNow() {
    if (_advancingNext) return;
    _advancingNext = true;
    _upNextFocused = false;
    setState(() => _upNext = null);
    _goEpisode(_epIndex + 1);
  }

  void _upNextHide() {
    setState(() {
      _upNextHidden = true;
      _upNext = null;
    });
    if (isTvDevice && _upNextFocused) {
      _upNextFocused = false;
      _preSkipFocus?.requestFocus();
    }
  }

  String? _upNextSubtitle(BaseItemDto item) {
    if (!widget.item.isEpisode) return null;
    final show = widget.item.seriesName;
    final s = item.parentIndexNumber, e = item.indexNumber;
    final code = (s != null && e != null) ? 'S$s:E$e' : null;
    final parts = [if (show != null && show.isNotEmpty) show, ?code];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? _upNextArtUrl(BaseItemDto item) {
    final session = _session;
    if (session == null) return null;
    final tag = item.primaryImageTag ?? widget.item.primaryImageTag;
    if (tag == null) return null;
    final id = item.primaryImageTag != null ? item.id : widget.item.id;
    return '${session.baseUrl}/Items/$id/Images/Primary'
        '?api_key=${session.accessToken}&maxHeight=300&tag=$tag';
  }

  void _reportProgress() {
    final s = _session;
    if (s == null) return;
    ref.read(jellyfinClientProvider).reportPlaybackProgress(
          baseUrl: s.baseUrl,
          token: s.accessToken,
          itemId: widget.item.id,
          positionTicks: _controller.state.value.position.inMilliseconds * 10000,
        );
  }

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
    var target = s.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (s.duration > Duration.zero && target > s.duration) target = s.duration;
    _controller.seekTo(target);
    _flash(seconds < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded);
    _show();
  }

  // Root key handler. The visible control bar is a row of focusable buttons the
  // remote traverses with ◀/▶ (Select activates). This handler only: exits on
  // BACK, always honours the media play/pause key, and wakes the chrome on any
  // key (focusing Play) — then lets button traversal/activation run. The video
  // surface is excluded from focus, so the remote can never get stranded.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape) {
      if (_controlsVisible) {
        setState(() => _controlsVisible = false);
        _hideTimer?.cancel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored; // pop
    }
    if (k == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    // The Skip button lives outside the auto-hiding chrome, so handle it before
    // the "any key wakes the bar" branch: Select fires it; an arrow steps off it
    // into the transport (waking the chrome as usual).
    if (_activeSkip != null &&
        FocusManager.instance.primaryFocus == _fSkip) {
      if (k == LogicalKeyboardKey.select ||
          k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.gameButtonA) {
        _doSkip();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown) {
        _show();
        _fSeek.requestFocus(); // step down into the transport
        return KeyEventResult.handled;
      }
      // Up / Left / Right keep focus on the Skip pill (a single stop).
      if (k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight) {
        return KeyEventResult.handled;
      }
    }
    // The Up Next prompt also lives outside the chrome: Select fires the focused
    // button, Left/Right toggle between Play Now and Hide, Up/Down step into the
    // transport (waking the chrome).
    final upPf = FocusManager.instance.primaryFocus;
    if (_upNext != null && (upPf == _fUpNextPlay || upPf == _fUpNextHide)) {
      final onPlay = upPf == _fUpNextPlay;
      if (k == LogicalKeyboardKey.select ||
          k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.gameButtonA) {
        onPlay ? _upNextPlayNow() : _upNextHide();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight) {
        (onPlay ? _fUpNextHide : _fUpNextPlay).requestFocus();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown) {
        _show();
        _fSeek.requestFocus(); // step down into the transport
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        return KeyEventResult.handled; // nothing above the prompt
      }
    }
    if (!_controlsVisible) {
      _show();
      _focusPlay();
      return KeyEventResult.handled; // first press only wakes the chrome
    }
    _scheduleHide(); // keep chrome alive while interacting

    final pf = FocusManager.instance.primaryFocus;
    // ▲/▼ move between the seek bar and the button row.
    if (k == LogicalKeyboardKey.arrowUp) {
      if (pf == _fSeek) {
        // Above the seek bar sits the Skip / Up Next prompt when it's showing.
        if (_upNext != null) {
          _fUpNextPlay.requestFocus();
        } else if (_activeSkip != null) {
          _fSkip.requestFocus();
        }
      } else {
        _fSeek.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (pf == _fSeek) _fPlay.requestFocus();
      return KeyEventResult.handled;
    }
    // ◀/▶ scrub on the seek bar, else step through the buttons in order (clamped
    // — no wrap — so it can't cycle over the same few controls).
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
    // Select on the seek bar toggles playback; on a button it activates it
    // (handled by the framework's ActivateIntent).
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.gameButtonA) {
      if (pf == _fSeek) {
        _togglePlay();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _pickTrack(bool subtitle) async {
    final tracks =
        subtitle ? _controller.textTracks.value : _controller.audioTracks.value;
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(subtitle ? l.playerSubtitles : l.playerAudio,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (subtitle)
              ListTile(
                autofocus: tracks.every((t) => !t.selected),
                title: Text(l.commonOff),
                trailing: tracks.every((t) => !t.selected)
                    ? Icon(Icons.check_rounded, color: scheme.primary)
                    : null,
                onTap: () {
                  _controller.setSubtitleTrack(-1);
                  Navigator.of(ctx).pop();
                },
              ),
            for (final t in tracks)
              ListTile(
                autofocus: t.selected,
                title: Text(t.label.isEmpty ? t.language : t.label),
                trailing: t.selected
                    ? Icon(Icons.check_rounded, color: scheme.primary)
                    : null,
                onTap: () {
                  subtitle
                      ? _controller.setSubtitleTrack(t.index)
                      : _controller.setAudioTrack(t.index);
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
  void deactivate() {
    // Leaving the player: let the phone rotate freely and show the system bars
    // again. Done here (not just dispose) because dispose isn't guaranteed to run
    // promptly on the way out.
    _restoreSystemUi();
    // From here the element is inactive: block provider reads in state callbacks.
    // Set _groupSuppress so the teardown pause doesn't broadcast to the group.
    _deactivated = true;
    _groupSuppress = true;
    _groupSuppressTimer?.cancel();
    _syncCueTimer?.cancel();
    super.deactivate();
  }

  @override
  void dispose() {
    _disposed = true;
    _unregisterSleep?.call();
    _disableSystemPip();
    // Decrement the SyncPlay open-player count (mirrors notifyPlayerOpened).
    _syncSessionRef?.notifyPlayerClosed();
    _groupSuppressTimer?.cancel();
    _buffDebounce?.cancel();
    _syncCueTimer?.cancel();
    _hideTimer?.cancel();
    _reportTimer?.cancel();
    _flashTimer?.cancel();
    _errSub?.cancel();
    for (final f in [
      _fSeek,
      _fPlay,
      _fBack,
      _fFwd,
      _fPrev,
      _fNext,
      _fSubs,
      _fAudio,
      _fRecord,
      _fSettings,
      _fSkip,
      _fUpNextPlay,
      _fUpNextHide,
    ]) {
      f.dispose();
    }
    _controller.state.removeListener(_onState);
    _controller.textTracks.removeListener(_onTracks);
    _controller.audioTracks.removeListener(_onTracks);
    final s = _session;
    final client = _client;
    if (s != null && client != null) {
      // Live: report stopped WITH the live ids and close the stream so Jellyfin
      // frees the tuner (miss this and the next tune-in 500s). VOD: report the
      // resume position so "continue watching" is accurate.
      final liveStreamId = _liveStreamId;
      if (_isLive) {
        if (_started) {
          client.reportPlaybackStopped(
            baseUrl: s.baseUrl,
            token: s.accessToken,
            itemId: widget.item.id,
            positionTicks: 0,
            liveStreamId: liveStreamId,
            playSessionId: _livePlaySessionId,
          );
        }
        if (liveStreamId != null) {
          client.closeLiveStream(
            baseUrl: s.baseUrl,
            token: s.accessToken,
            liveStreamId: liveStreamId,
            playSessionId: _livePlaySessionId,
          );
          LiveStreams.unregister(liveStreamId);
        }
      } else {
        client.reportPlaybackStopped(
          baseUrl: s.baseUrl,
          token: s.accessToken,
          itemId: widget.item.id,
          positionTicks:
              _controller.state.value.position.inMilliseconds * 10000,
        );
      }
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Follow SyncPlay commands from the group (play/pause/seek).
    ref.listen(syncCommandProvider, (_, next) => _applySyncCommand(next));
    // Hand off to a Chromecast: while a session is connected, local playback
    // stays paused (no double audio); on cast end, resume locally where the
    // receiver left off. Mirrors the media_kit player.
    ref.listen(castControllerProvider.select((s) => s.casting), (prev, next) {
      if (next == true) {
        _controller.pause();
      } else if (prev == true) {
        final c = ref.read(castControllerProvider);
        if (c.positionMs > 0) {
          _controller.seekTo(Duration(milliseconds: c.positionMs));
        }
        if (c.playing) _controller.play();
      }
    });
    final castStatus = ref.watch(castControllerProvider);
    if (castStatus.casting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && !_deactivated) _controller.pause();
      });
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The native surface. Excluded from focus so D-pad navigation can
            // never land on the video view itself (which would strand the remote).
            if (isAndroidPlatform)
              ExcludeFocus(child: ExoVideo(controller: _controller)),
            // Tap layer (phone/tablet): a tap on the video plays/pauses (and
            // flashes the icon + wakes the chrome), exactly like the media_kit
            // player. Sits above the bare video but below the controls/skip
            // button (added later in this Stack), so their taps aren't swallowed.
            if (!isTvDevice && !_inPip)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _togglePlay,
                ),
              ),
            // Buffering spinner (rebuilds itself on state, not via the screen).
            if (_error == null)
              ValueListenableBuilder<ExoState>(
                valueListenable: _controller.state,
                builder: (_, s, _) => s.buffering
                    ? const Center(
                        child: AppSpinner(color: Colors.white))
                    : const SizedBox.shrink(),
              ),
            // Center play/pause flash.
            if (_flashIcon != null && !_inPip)
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
            if (_error != null) _errorView(),
            // Caption overlay. The native SurfaceView has no SubtitleView, so
            // ExoPlayer forwards cue text here and we draw it — styled to match
            // the Jellyfin player (user's colour/scale/background prefs, a soft
            // shadow by default). This is what renders live CEA-608 captions on
            // TV, which the media_kit path couldn't. Nudged up while the controls
            // are visible so the bar doesn't cover it.
            ValueListenableBuilder<String>(
              valueListenable: _controller.cues,
              builder: (context, text, _) {
                if (text.isEmpty || _inPip) return const SizedBox.shrink();
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
            // Playback Info panel (toggled from the gear), top-left so it clears
            // the bottom bar. Same panel the YouTube ExoPlayer uses.
            if (_statsOpen && !_inPip)
              Positioned(
                left: 24,
                top: 24 + MediaQuery.paddingOf(context).top,
                child: ExoStatsPanel(
                  controller: _controller,
                  onClose: () => setState(() => _statsOpen = false),
                ),
              ),
            // SyncPlay status: a pulsing "syncing" glyph or a brief skip-to-sync
            // flash, centered. Hidden in a PiP window.
            if (!_inPip) Positioned.fill(child: _SyncCueOverlay(cue: _syncCue)),
            // (Up Next / Skip prompt is rendered LAST — above the chrome — so
            // its Play Now / Hide / Skip buttons actually receive taps.)
            // Chromecast entry point (phone/tablet; the button hides itself where
            // Cast is unavailable). Off on TV, which is a cast target not a
            // source. Adapts the stream to the chosen receiver.
            if (!isTvDevice && !_isLive && !_inPip)
              Positioned(
                top: MediaQuery.of(context).padding.top + 4,
                right: 8,
                // Fade with the rest of the chrome so it doesn't stay floating
                // over the video after the controls hide.
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: CastButton(
                      resolve: _castMedia,
                      title: widget.item.name,
                      position: () =>
                          _controller.state.value.position.inMilliseconds,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            // While casting, local playback is paused and this covers the video
            // so it's clear playback moved to the receiver, with a way to stop.
            if (castStatus.casting && !_inPip)
              Positioned.fill(
                child: CastRemote(
                  artworkUrl: _castArtworkUrl(),
                  title: _castTitle(),
                  onPrevious:
                      _epIndex > 0 ? () => _castEpisodeAt(_epIndex - 1) : null,
                  onNext: (_epIndex >= 0 && _epIndex < _episodes.length - 1)
                      ? () => _castEpisodeAt(_epIndex + 1)
                      : null,
                ),
              ),
            // Bottom control chrome. Excluded from focus while hidden so focus
            // falls back to the root handler (any key re-wakes + refocuses Play).
            AnimatedOpacity(
              opacity: _controlsVisible && !_inPip ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: ExcludeFocus(
                excluding: !_controlsVisible || _inPip,
                child: IgnorePointer(
                  ignoring: !_controlsVisible || _inPip,
                  child: _controls(),
                ),
              ),
            ),
            // Up Next / Skip prompt ABOVE the chrome so its buttons receive
            // taps (the visible controls would otherwise intercept them).
            if (!_inPip && _upNext != null)
              Positioned(
                right: 28,
                bottom: (ref.watch(preferencesProvider).asData?.value
                                .upNextStyle ??
                            'card') ==
                        'card'
                    ? 96
                    : 116,
                child: UpNextPrompt(
                  style: ref
                          .watch(preferencesProvider)
                          .asData
                          ?.value
                          .upNextStyle ??
                      'card',
                  title: _upNext!.item.name,
                  subtitle: _upNextSubtitle(_upNext!.item),
                  artUrl: _upNextArtUrl(_upNext!.item),
                  imageHeaders: ref.read(imageHeadersProvider),
                  remaining: _upNext!.remaining,
                  total: _upNext!.total,
                  onPlayNow: _upNextPlayNow,
                  onHide: _upNextHide,
                  playFocus: _fUpNextPlay,
                  hideFocus: _fUpNextHide,
                  tv: isTvDevice,
                ),
              )
            else if (!_inPip && _activeSkip != null)
              Positioned(
                right: 28,
                bottom: 116,
                child: SkipPill(
                  key: ValueKey(_activeSkip!.type),
                  label: _exoSkipLabel(_activeSkip!),
                  onTap: _doSkip,
                  focusNode: _fSkip,
                  tv: isTvDevice,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white70, size: 48),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );

  Widget _controls() {
    final l = AppLocalizations.of(context);
    final hasSubs = _controller.textTracks.value.isNotEmpty;
    final hasAudio = _controller.audioTracks.value.isNotEmpty;
    final bar = Padding(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Live shows the channel + now-playing block (same as the media_kit
            // live bar); VOD shows the item title.
            if (_isLive)
              LiveBottomInfo(
                channelName: widget.item.name,
                program: widget.item.currentProgram,
              )
            else
              Text(
                widget.item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
            const SizedBox(height: 8),
            // Scrub row: focusable seek bar between the two time labels. Each
            // time label rebuilds itself on state (not the whole bar).
            Row(
              children: [
                ValueListenableBuilder<ExoState>(
                  valueListenable: _controller.state,
                  builder: (_, s, _) => Text(_fmt(s.position),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ExoSeekBar(
                    focusNode: _fSeek,
                    controller: _controller,
                    // Chapter + segment ticks (VOD only; live has no ladder).
                    markers: _isLive
                        ? const []
                        : [
                            for (final c in widget.item.chapters) c.start,
                            for (final seg in _segments) seg.start,
                          ],
                    // Trickplay scrub-preview (VOD only; live has no seek ladder).
                    client: _isLive ? null : ref.read(jellyfinClientProvider),
                    baseUrl: _session?.baseUrl,
                    itemId: widget.item.id,
                    trickplay: _isLive ? null : _trickplay,
                    trickplayWidth: _isLive ? null : _trickWidth,
                    headers: ref.watch(imageHeadersProvider),
                    showThumbnailPreview: ref
                            .watch(preferencesProvider)
                            .asData
                            ?.value
                            .previewThumbnailsWhileSeeking ??
                        true,
                  ),
                ),
                const SizedBox(width: 12),
                // Live shows a red LIVE badge in place of the trailing time
                // (a broadcast has no fixed duration), matching the shared bar.
                if (_isLive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.fiber_manual_record_rounded,
                            size: 10, color: Colors.white),
                        const SizedBox(width: 5),
                        Text(l.playerBadgeLive,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5)),
                      ],
                    ),
                  )
                else
                  ValueListenableBuilder<ExoState>(
                    valueListenable: _controller.state,
                    builder: (_, s, _) => Text(
                        // Time-remaining on TV, matching the app's shared bar.
                        isTvDevice
                            ? '-${_fmt(s.duration > s.position ? s.duration - s.position : Duration.zero)}'
                            : _fmt(s.duration),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // Button row. Left = transport, right = options (desktop-style split
            // with real spacing); ◀/▶ step across it by index (see _onKey), so
            // the gap is purely visual and always traversable.
            Row(
              children: [
                // Live leads with Record (like the media_kit live bar); it has no
                // 10s/30s skip (a broadcast has no seek ladder).
                if (_isLive && widget.item.currentProgram != null)
                  LiveRecordButton(
                    focusNode: _fRecord,
                    programId: widget.item.currentProgram!.id,
                  ),
                // Play/pause: the AnimatedControl stays stable (so its focus +
                // press/scale animation isn't reset) while only the icon swaps.
                AnimatedControl(
                  focusNode: _fPlay,
                  tooltip: l.playerPlayPause,
                  onTap: _togglePlay,
                  child: ValueListenableBuilder<ExoState>(
                    valueListenable: _controller.state,
                    builder: (_, s, _) => Icon(
                      s.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: isTvDevice ? 22 : 40,
                    ),
                  ),
                ),
                if (!_isLive)
                  _ctlButton(
                    focusNode: _fBack,
                    icon: Icons.replay_10_rounded,
                    tooltip: l.playerSeekBack(10),
                    onTap: () => _seekBy(-10),
                  ),
                if (!_isLive)
                  _ctlButton(
                    focusNode: _fFwd,
                    icon: Icons.forward_30_rounded,
                    tooltip: l.playerSeekForward(30),
                    onTap: () => _seekBy(30),
                  ),
                const Spacer(),
                if (!_isLive && _epIndex > 0)
                  _ctlButton(
                    focusNode: _fPrev,
                    icon: Icons.skip_previous_rounded,
                    tooltip: l.commonPrevious,
                    onTap: () => _goEpisode(_epIndex - 1),
                  ),
                if (!_isLive && _epIndex >= 0 && _epIndex < _episodes.length - 1)
                  _ctlButton(
                    focusNode: _fNext,
                    icon: Icons.skip_next_rounded,
                    tooltip: l.commonNext,
                    onTap: () => _goEpisode(_epIndex + 1),
                  ),
                if (hasSubs)
                  _ctlButton(
                    focusNode: _fSubs,
                    icon: Icons.closed_caption_rounded,
                    tooltip: l.playerSubtitles,
                    onTap: () {
                      _menuReturn = _fSubs;
                      _pickTrack(true);
                    },
                  ),
                if (hasAudio)
                  _ctlButton(
                    focusNode: _fAudio,
                    icon: Icons.multitrack_audio_rounded,
                    tooltip: l.playerAudio,
                    onTap: () {
                      _menuReturn = _fAudio;
                      _pickTrack(false);
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
      child: isTvDevice
          // Match the app's frosted-glass bar. The native video SurfaceView can't
          // be sampled by the blur, so this reads as a translucent panel rather
          // than a true frost (closest the platform allows); the readability wash
          // keeps the times legible over bright video, like the shared bar.
          ? Stack(
              children: [
                Positioned.fill(
                  child: GlassSurface(
                    blur: 7,
                    color: Colors.black.withValues(alpha: 0.18),
                    border: Border(
                      top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.06)),
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
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.88),
                  ],
                ),
              ),
              child: bar,
            ),
    );
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

  Widget _ctlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    FocusNode? focusNode,
    bool big = false,
  }) {
    // Same spring/press/focus-ring animation as the media_kit bar (shared
    // AnimatedIconButton). On TV every control is the 22px bar glyph; the
    // phone/desktop Exo path keeps the larger sizes.
    return AnimatedIconButton(
      icon: icon,
      tooltip: tooltip,
      onTap: onTap,
      focusNode: focusNode,
      size: isTvDevice ? 22 : (big ? 40 : 30),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final sec = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

/// The SyncPlay status overlay, matching the media_kit player: a pulsing
/// "syncing/waiting" glyph, or a brief SkipToSync flash (clock-forward to catch
/// up, clock-back to wait) framed by letterbox brackets.
class _SyncCueOverlay extends StatefulWidget {
  final String? cue; // 'sync' | 'fwd' | 'back' | null
  const _SyncCueOverlay({required this.cue});

  @override
  State<_SyncCueOverlay> createState() => _SyncCueOverlayState();
}

class _SyncCueOverlayState extends State<_SyncCueOverlay>
    with SingleTickerProviderStateMixin {
  static const _teal = Color(0xFF00A4DC);
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cue = widget.cue;
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: cue == null
            ? const SizedBox.shrink(key: ValueKey('none'))
            : Center(key: ValueKey(cue), child: _glyph(cue)),
      ),
    );
  }

  Widget _glyph(String cue) {
    if (cue == 'sync') {
      return FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1).animate(_pulse),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.08).animate(_pulse),
          child:
              _bubble(const Icon(Icons.sync_rounded, color: _teal, size: 46)),
        ),
      );
    }
    // Skip-to-sync: clock-forward (catch up) or clock-back (wait), bracketed.
    final icon = cue == 'fwd' ? Icons.update_rounded : Icons.history_rounded;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('[',
            style: TextStyle(
                color: Colors.white38,
                fontSize: 46,
                height: 1,
                fontWeight: FontWeight.w200)),
        const SizedBox(width: 26),
        _bubble(Icon(icon, color: _teal, size: 48)),
        const SizedBox(width: 26),
        const Text(']',
            style: TextStyle(
                color: Colors.white38,
                fontSize: 46,
                height: 1,
                fontWeight: FontWeight.w200)),
      ],
    );
  }

  Widget _bubble(Widget child) => Container(
        width: 92,
        height: 92,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.38),
        ),
        child: child,
      );
}

