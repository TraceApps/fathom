import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/youtube_comment.dart';
import '../models/youtube_video.dart';
import '../routing/route_observer.dart';
import '../services/tv_mode.dart';
import '../services/youtube_streams.dart';
import '../state/audio_player.dart';
import '../state/youtube_providers.dart';
import '../widgets/add_to_youtube_playlist.dart';
import '../widgets/animated_control.dart';
import '../widgets/youtube_actions.dart';
import '../widgets/app_spinner.dart';

/// A vertical, swipeable Shorts viewer — one Short per full-screen page, swipe
/// up/down to move. Scoped to the list it was opened from (e.g. a channel's
/// Shorts tab), paging in more of that list on demand. Endless cross-channel
/// discovery (YouTube's reel sequence) is a planned follow-up; this stays within
/// the source list.
///
/// Only current ± 1 pages hold a live player (a small pool that recycles as you
/// swipe); everything else is just its thumbnail, so memory stays flat.
class YoutubeShortsScreen extends ConsumerStatefulWidget {
  final List<YoutubeVideo> shorts;
  final int startIndex;

  /// Continuation token for the source list, to page in more Shorts.
  final String? continuation;

  const YoutubeShortsScreen({
    super.key,
    required this.shorts,
    this.startIndex = 0,
    this.continuation,
  });

  @override
  ConsumerState<YoutubeShortsScreen> createState() =>
      _YoutubeShortsScreenState();
}

class _YoutubeShortsScreenState extends ConsumerState<YoutubeShortsScreen>
    with RouteAware {
  late final PageController _pageController;
  late List<YoutubeVideo> _shorts;
  late int _index;
  String? _continuation;
  bool _loadingMore = false;
  bool _muted = false;

  // Windowed player pool: index -> player. Only current ± 1 are kept alive.
  final Map<int, Player> _players = {};
  final Map<int, VideoController> _controllers = {};
  // Resolved muxed URL per video id (null = resolve failed), so re-entering a
  // page never re-hits the network.
  final Map<String, String?> _urlCache = {};
  // Video ids whose stream couldn't be resolved — shown as a fallback rather
  // than an endless spinner.
  final Set<String> _failed = {};
  // Video ids already logged to watch history this session, so a swipe records
  // a view once rather than on every rebuild.
  final Set<String> _recorded = {};

  bool get _mobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _shorts = List.of(widget.shorts);
    _index = widget.startIndex.clamp(0, _shorts.isEmpty ? 0 : _shorts.length - 1);
    _continuation = widget.continuation;
    _pageController = PageController(initialPage: _index);
    // Shorts are vertical: hold portrait and go immersive on a phone while the
    // viewer is up. No-op on desktop/TV.
    if (_mobile && !isTvDevice) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky,
          overlays: const []);
      SystemChrome.setPreferredOrientations(
          const [DeviceOrientation.portraitUp]);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateWindow());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void>) routeObserver.subscribe(this, route);
  }

  // Covered by a full route (e.g. tapping the channel) — pause so the Short's
  // audio doesn't keep playing out of sight; resume when it's revealed again.
  @override
  void didPushNext() => _players[_index]?.pause();

  @override
  void didPopNext() => _players[_index]?.play();

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
    _controllers.clear();
    _pageController.dispose();
    if (_mobile && !isTvDevice) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);
      SystemChrome.setPreferredOrientations(const []);
    }
    super.dispose();
  }

  /// Bring the pool in line with the current index: create players for the
  /// current ± 1 window, dispose any outside it, and play the current one while
  /// the neighbours sit preloaded and paused.
  void _updateWindow() {
    final keep = <int>{
      for (var d = -1; d <= 1; d++) _index + d,
    }.where((i) => i >= 0 && i < _shorts.length).toSet();

    for (final i in _players.keys.toList()) {
      if (!keep.contains(i)) {
        _controllers.remove(i);
        _players.remove(i)?.dispose();
      }
    }
    for (final i in keep) {
      if (!_players.containsKey(i)) {
        final player = Player();
        _players[i] = player;
        _controllers[i] = VideoController(player);
        unawaited(_open(player, i));
      }
    }
    for (final entry in _players.entries) {
      if (entry.key == _index) {
        unawaited(entry.value.play());
        unawaited(entry.value.setVolume(_muted ? 0 : 100));
      } else {
        unawaited(entry.value.pause());
      }
    }
    if (mounted) setState(() {});
    _recordHistory();
    unawaited(_maybeLoadMore());
  }

  /// Log the current Short as watched (once per session), so it shows in History
  /// and the feed's watched/dedup logic stays consistent with the watch page.
  void _recordHistory() {
    final v = _shorts[_index];
    if (!_recorded.add(v.id)) return;
    final dur = v.duration ?? Duration.zero;
    ref.read(youtubeHistoryProvider.notifier).record(
          videoId: v.id,
          title: v.title,
          author: v.author,
          position: dur,
          duration: dur,
          now: DateTime.now(),
        );
  }

  Future<void> _open(Player player, int index) async {
    try {
      await player.setPlaylistMode(PlaylistMode.single); // loop the Short
      final url = await _resolveUrl(_shorts[index].id);
      // Bail if this player was recycled out of the window while resolving.
      if (!_players.containsValue(player)) return;
      if (url == null) {
        if (mounted) setState(() => _failed.add(_shorts[index].id));
        return;
      }
      await player.open(Media(url), play: index == _index);
      await player.setVolume(_muted ? 0 : 100);
    } catch (_) {
      if (mounted) setState(() => _failed.add(_shorts[index].id));
    }
  }

  Future<String?> _resolveUrl(String videoId) async {
    if (_urlCache.containsKey(videoId)) return _urlCache[videoId];
    try {
      final s = await resolveYoutubeStreams(
          'https://www.youtube.com/watch?v=$videoId');
      // Prefer the self-contained muxed stream (has audio); Shorts are low-res
      // so it almost always exists. Fall back to the best video-only rendition.
      final url =
          s.muxedUrl ?? (s.qualities.isNotEmpty ? s.qualities.first.url : null);
      _urlCache[videoId] = url;
      return url;
    } catch (_) {
      _urlCache[videoId] = null;
      return null;
    }
  }

  Future<void> _maybeLoadMore() async {
    if (_loadingMore ||
        _continuation == null ||
        _index < _shorts.length - 2) {
      return;
    }
    _loadingMore = true;
    try {
      final more =
          await ref.read(youtubeInnerTubeProvider).channelTabMore(_continuation!);
      final seen = {for (final v in _shorts) v.id};
      final fresh = more.videos.where((v) => !seen.contains(v.id)).toList();
      if (!mounted) return;
      setState(() {
        _shorts = [..._shorts, ...fresh];
        _continuation = more.videos.isEmpty ? null : more.continuation;
      });
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  void _onPageChanged(int i) {
    _index = i;
    _updateWindow();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _players[_index]?.setVolume(_muted ? 0 : 100);
  }

  @override
  Widget build(BuildContext context) {
    if (_shorts.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: _onPageChanged,
            itemCount: _shorts.length,
            itemBuilder: (context, i) => _ShortPage(
              short: _shorts[i],
              player: i == _index ? _players[i] : null,
              controller: _controllers[i],
              muted: _muted,
              failed: _failed.contains(_shorts[i].id),
            ),
          ),
          // Top overlay: back + volume, clear of the status bar.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              child: Row(
                children: [
                  AnimatedIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  // A clean mute toggle on every platform. A floating volume
                  // slider over the video read as out of place, and desktop has
                  // OS volume anyway.
                  AnimatedIconButton(
                    icon: _muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    onTap: _toggleMute,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One full-screen Short: the video (or its thumbnail until a player is bound),
/// tap-to-pause, a bottom metadata scrim, a right-side action rail, and a slim
/// progress bar.
class _ShortPage extends ConsumerStatefulWidget {
  final YoutubeVideo short;
  final Player? player;
  final VideoController? controller;
  final bool muted;
  final bool failed;

  const _ShortPage({
    required this.short,
    required this.player,
    required this.controller,
    required this.muted,
    required this.failed,
  });

  @override
  ConsumerState<_ShortPage> createState() => _ShortPageState();
}

class _ShortPageState extends ConsumerState<_ShortPage> {
  void _tap() => widget.player?.playOrPause();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final short = widget.short;
    final controller = widget.controller;
    final stack = Stack(
      fit: StackFit.expand,
      children: [
          // A Short that wouldn't resolve: its thumbnail, dimmed, with a note —
          // rather than an endless spinner.
          if (widget.failed) ...[
            Image.network(
              short.thumbnailUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
            ),
            const ColoredBox(color: Colors.black54),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Colors.white70, size: 40),
                  const SizedBox(height: 8),
                  Text(l.ytShortUnavailable,
                      style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ]
          // Video with a blurred fill behind it, so a Short that isn't a clean
          // 9:16 sits on a soft backdrop rather than dead black bars.
          else if (controller != null) ...[
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Image.network(
                short.thumbnailUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
              ),
            ),
            const ColoredBox(color: Colors.black26),
            Video(
              controller: controller,
              controls: NoVideoControls,
              fit: BoxFit.contain,
              fill: Colors.transparent,
            ),
          ]
          else
            Image.network(
              short.thumbnailUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
            ),

          // Spinner while the current Short buffers to its first frame, so a
          // slow resolve reads as loading rather than frozen.
          if (widget.player != null && !widget.failed)
            StreamBuilder<bool>(
              stream: widget.player!.stream.buffering,
              initialData: true,
              builder: (context, snap) => (snap.data ?? false)
                  ? const Center(
                      child: AppSpinner(color: Colors.white))
                  : const SizedBox.shrink(),
            ),

          // Persistent play glyph while paused (not just a flash), so a
          // tapped-pause reads clearly. Hidden while buffering.
          if (widget.player != null && !widget.failed)
            StreamBuilder<bool>(
              stream: widget.player!.stream.playing,
              initialData: widget.player!.state.playing,
              builder: (context, snap) {
                final playing = snap.data ?? true;
                if (playing || widget.player!.state.buffering) {
                  return const SizedBox.shrink();
                }
                return Center(
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 76,
                    color: Colors.white.withValues(alpha: 0.9),
                    shadows: const [
                      Shadow(blurRadius: 16, color: Colors.black54)
                    ],
                  ),
                );
              },
            ),

          // Bottom + right controls.
          _Overlay(short: short),

          // Scrubber, lifted clear of the bottom gesture area so it's easy to
          // grab (with a tall transparent hit strip above the thin bar).
          if (widget.player != null && !widget.failed)
            Positioned(
              left: 8,
              right: 8,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 18),
                child: _Progress(player: widget.player!),
              ),
            ),
      ],
    );
    return GestureDetector(
      onTap: _tap,
      // Android TV stretches the portrait Short across the widescreen panel;
      // constrain it to a centered 9:16 column with black sides. isTvDevice-gated
      // so desktop/phone/tablet (which render correctly) stay untouched.
      child: isTvDevice
          ? Stack(
              fit: StackFit.expand,
              children: [
                // Full-screen blurred ambiance behind the portrait column — the
                // same soft-backdrop look the app uses elsewhere, not black bars.
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                  child: Image.network(
                    short.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Colors.black),
                  ),
                ),
                const ColoredBox(color: Colors.black38),
                Center(
                  child: AspectRatio(aspectRatio: 9 / 16, child: stack),
                ),
              ],
            )
          : stack,
    );
  }
}

/// Bottom-left metadata + right-side Fathom action rail. The rail is the video
/// action set (add to playlist, listen, copy link) laid out vertically — the
/// same actions the watch page offers, since Fathom has no account to like with.
class _Overlay extends ConsumerWidget {
  final YoutubeVideo short;
  const _Overlay({required this.short});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    const shadow = [Shadow(blurRadius: 5, color: Colors.black87)];
    return Stack(
      children: [
        // Right rail.
        Positioned(
          right: 6,
          bottom: 96,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RailButton(
                  icon: Icons.mode_comment_outlined,
                  label: l.ytComments,
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    builder: (_) => _ShortsCommentsSheet(videoId: short.id),
                  ),
                ),
                const SizedBox(height: 18),
                _RailButton(
                  icon: Icons.playlist_add_rounded,
                  label: l.ytAddToPlaylist,
                  onTap: () => showAddToYoutubePlaylist(context, short),
                ),
                const SizedBox(height: 18),
                if (!isTvDevice)
                  _RailButton(
                    icon: Icons.headset_rounded,
                    label: l.ytListen,
                    // Leave the viewer first (disposing the players stops the
                    // video's audio), then hand off to background audio — the
                    // same round-trip the watch page does, so audio isn't doubled.
                    onTap: () {
                      Navigator.of(context).maybePop();
                      ref
                          .read(audioControllerProvider.notifier)
                          .playYoutubeAudio(youtubeAudioItemOf(short));
                    },
                  ),
                if (!isTvDevice) const SizedBox(height: 18),
                // Everything else (Play Next, Add to Queue, Download, Copy Link,
                // Open in Browser) via the same action sheet the rest of the app
                // uses, so the rail matches the watch page.
                _RailButton(
                  icon: Icons.more_horiz_rounded,
                  label: l.commonMore,
                  onTap: () => YoutubeActions.showTvActionSheet(
                      context, ref, short,
                      includePlaylist: false),
                ),
              ],
            ),
          ),
        ),

        // Bottom-left metadata over a scrim. The scrim spans the FULL width so
        // there's no lighter right-hand seam; the text is padded clear of the
        // action rail on the right instead.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 40, 88, 52),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (short.author.isNotEmpty)
                    GestureDetector(
                      onTap: (short.channelId?.isEmpty ?? true)
                          ? null
                          : () => context.push('/youtube/channel', extra: (
                                channelId: short.channelId!,
                                title: short.author,
                              )),
                      child: Text(
                        short.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: shadow,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    short.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white, shadows: shadow),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A rail action: a plain white glyph over the video that springs and warms to
/// the accent on press/hover — the app's shared control animation, no backing.
class _RailButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RailButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedControl(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // No colour set -> inherits AnimatedControl's white -> accent tween.
          Icon(icon, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim progress bar that doubles as a scrubber: tap or drag horizontally to
/// seek. A taller transparent hit area makes it easy to grab; the bar itself
/// stays pinned thin at the very bottom so it never covers the video.
class _Progress extends StatefulWidget {
  final Player player;
  const _Progress({required this.player});

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  double? _drag; // 0..1 while scrubbing, else null

  void _seek(double fraction) {
    final dur = widget.player.state.duration;
    if (dur > Duration.zero) {
      widget.player.seek(dur * fraction.clamp(0.0, 1.0));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      double frac(double dx) => width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          final f = frac(d.localPosition.dx);
          _seek(f);
          setState(() => _drag = f);
        },
        onTapUp: (_) => setState(() => _drag = null),
        onHorizontalDragStart: (d) =>
            setState(() => _drag = frac(d.localPosition.dx)),
        onHorizontalDragUpdate: (d) =>
            setState(() => _drag = frac(d.localPosition.dx)),
        onHorizontalDragEnd: (_) {
          if (_drag != null) _seek(_drag!);
          setState(() => _drag = null);
        },
        child: SizedBox(
          height: 30,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: StreamBuilder<Duration>(
              stream: widget.player.stream.position,
              initialData: widget.player.state.position,
              builder: (context, snap) {
                final accent = Theme.of(context).colorScheme.primary;
                final dur = widget.player.state.duration.inMilliseconds;
                final pos = (snap.data ?? Duration.zero).inMilliseconds;
                final live = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
                return LinearProgressIndicator(
                  value: _drag ?? live,
                  minHeight: _drag != null ? 5 : 3,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation(accent),
                  borderRadius: BorderRadius.circular(3),
                );
              },
            ),
          ),
        ),
      );
    });
  }
}

/// Comments for a Short, in a bottom sheet. Fetches the video's comments token
/// (via the watch provider) and reuses the shared comments provider.
class _ShortsCommentsSheet extends ConsumerWidget {
  final String videoId;
  const _ShortsCommentsSheet({required this.videoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget unavailable() => Center(
          child: Text(l.ytCommentsUnavailable,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        );
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: ref.watch(youtubeWatchProvider(videoId)).when(
            loading: () => const Center(child: AppSpinner()),
            error: (_, _) => unavailable(),
            data: (d) {
              final token = d.commentsToken;
              if (token == null) return unavailable();
              return ref.watch(youtubeCommentsProvider(token)).when(
                    loading: () =>
                        const Center(child: AppSpinner()),
                    error: (_, _) => unavailable(),
                    data: (page) {
                      if (page.comments.isEmpty) return unavailable();
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        children: [
                          Text(
                            page.countLabel.isEmpty
                                ? l.ytComments
                                : l.ytCommentsCount(page.countLabel),
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          for (final c in page.comments)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _ShortsCommentRow(comment: c),
                            ),
                          if (page.hasMore)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: page.loadingMore
                                  ? const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: AppSpinner.inline(),
                                    )
                                  : TextButton.icon(
                                      onPressed: () => ref
                                          .read(youtubeCommentsProvider(token)
                                              .notifier)
                                          .loadMore(),
                                      icon:
                                          const Icon(Icons.expand_more_rounded),
                                      label: Text(l.ytShowMoreComments),
                                    ),
                            ),
                        ],
                      );
                    },
                  );
            },
          ),
    );
  }
}

class _ShortsCommentRow extends StatelessWidget {
  final YoutubeComment comment;
  const _ShortsCommentRow({required this.comment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = comment;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: scheme.surfaceContainerHigh,
          foregroundImage:
              c.avatarUrl.isEmpty ? null : NetworkImage(c.avatarUrl),
          child: const Icon(Icons.person_rounded, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(c.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  if (c.publishedLabel.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(c.publishedLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant, fontSize: 11)),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(c.text, style: theme.textTheme.bodyMedium),
              if (c.likeLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.thumb_up_outlined,
                        size: 13, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(c.likeLabel,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
