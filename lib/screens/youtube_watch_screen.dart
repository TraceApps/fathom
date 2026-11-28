import 'dart:math' as math;
import '../api/error_text.dart';
import '../widgets/reorder.dart';
import '../widgets/cached_image.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/youtube_channel.dart';
import '../models/youtube_comment.dart';
import '../models/youtube_watch.dart';
import '../services/tv_mode.dart';
import '../services/fold.dart';
import '../state/preferences.dart';
import '../state/youtube_providers.dart';
import '../widgets/context_menu.dart';
import '../widgets/error_view.dart';
import '../widgets/subscribe_button.dart';
import '../widgets/tv_focus.dart';
import '../widgets/youtube_exo_player.dart';
import '../widgets/youtube_cards.dart';
import '../models/youtube_video.dart';
import '../widgets/add_to_youtube_playlist.dart';
import '../widgets/youtube_actions.dart';
import '../widgets/youtube_skeletons.dart';
import '../l10n/generated/app_localizations.dart';
import 'youtube_player_screen.dart';
import '../widgets/app_spinner.dart';
import '../widgets/ui_common.dart';

/// The watch page: the player, what you're watching, who made it, and where to
/// go next. Related videos sit beside the player on wide windows and below it
/// on narrow ones.
class YoutubeWatchScreen extends ConsumerStatefulWidget {
  final String videoId;
  final String? title; // shown while details load

  const YoutubeWatchScreen({super.key, required this.videoId, this.title});

  @override
  ConsumerState<YoutubeWatchScreen> createState() => _YoutubeWatchScreenState();
}

class _YoutubeWatchScreenState extends ConsumerState<YoutubeWatchScreen> {
  bool _descExpanded = false;

  /// Theater mode: a wider in-page player with the Up Next rail hidden (related
  /// videos flow below instead), toggled from the player's control bar.
  bool _theater = false;

  /// The video on screen. Owned here rather than read from the route, because
  /// hopping to a related video swaps this in place instead of navigating.
  late String _videoId = widget.videoId;
  late String? _title = widget.title;

  /// Captured while alive. The player reports its final position from dispose(),
  /// and touching ref there throws, which would abort the teardown and leave the
  /// player running.
  late final YoutubeHistory _history =
      ref.read(youtubeHistoryProvider.notifier);
  YoutubeWatchDetails? _lastDetails;

  /// The player's latest reported position (sub-second, in-memory), so the
  /// "Listen" hand-off to background audio resumes exactly where the video is —
  /// fresher than watch history, which is whole-second and persisted async.
  Duration _livePos = Duration.zero;
  // How long the video is, once the player knows: what's saved to a
  // playlist from here needs it, or it reads as a live stream ("LIVE").
  Duration? _length;

  /// Lets description timestamps seek the player.
  final _playerHandle = YoutubePlayerHandle();

  /// Resolved per video. History comes from storage, so this has to wait for
  /// that load rather than reading whatever is in memory at first build.
  late Future<Duration?> _resumeAt = _resolveResume();

  String get _url => 'https://www.youtube.com/watch?v=$_videoId';

  /// Where to pick this video up, or null to start from the beginning. A
  /// finished video starts over rather than resuming at the credits.
  Future<Duration?> _resolveResume() async {
    await ref.read(youtubeHistoryProvider.future);
    final prefs = ref.read(preferencesProvider).asData?.value;
    if (prefs != null && !prefs.youtubeResumePlayback) return null;
    final seen = ref.read(youtubeHistoryProvider.notifier).entryFor(_videoId);
    return (seen == null || seen.finished) ? null : seen.position;
  }

  /// Swap the video in place instead of navigating.
  ///
  /// This used to call pushReplacement on /youtube/watch. Replacing the same
  /// path repeatedly made go_router mint colliding page keys, so the Navigator
  /// then threw '!keyReservation.contains(key)' on the next push — the channel
  /// page silently never opened — and pops started failing the null check in
  /// _handlePopPage, which broke Back for the rest of the session. Swapping
  /// state keeps the back stack shallow (the reason for pushReplacement in the
  /// first place) without touching the navigator at all, and it's what YouTube
  /// and NewPipe do: Back leaves the watch page rather than walking back
  /// through every video you sampled.
  void _open(String videoId, String? title) {
    if (videoId == _videoId) return;
    setState(() {
      _videoId = videoId;
      _title = title;
      _lastDetails = null;
      _descExpanded = false;
      _resumeAt = _resolveResume();
    });
  }

  /// What plays when this video ends.
  ///
  /// The queue wins over autoplay: it's an explicit instruction, where autoplay
  /// is a guess. Queued videos play even with autoplay off, for the same
  /// reason — you asked for them.
  /// Jump to an Up Next (queue) item: play it and keep the ones after it as the
  /// remaining queue. Skips the items before it in the playlist.
  void _playQueueItem(int index) {
    final q = ref.read(youtubeQueueProvider);
    if (index < 0 || index >= q.length) return;
    final item = q[index];
    ref.read(youtubeQueueProvider.notifier).playAll(q.sublist(index + 1));
    _open(item.id, item.title);
  }

  void _playNext(YoutubeWatchDetails d) {
    final queued = ref.read(youtubeQueueProvider.notifier).takeNext();
    if (queued != null) {
      _open(queued.id, queued.title);
      return;
    }
    final autoplay =
        ref.read(preferencesProvider).asData?.value.youtubeAutoplay ?? true;
    if (!autoplay || d.related.isEmpty) return;
    final next = d.related.first;
    _open(next.id, next.title);
  }

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(youtubeWatchProvider(_videoId));
    final prefs = ref.watch(preferencesProvider).asData?.value;
    final queue = ref.watch(youtubeQueueProvider);
    // The rail decision is made in _Body from the box it actually gets. The
    // window is only the same thing while this is a root route with no sidebar.
    _lastDetails = details.asData?.value ?? _lastDetails;

    // The Next button only exists when there's actually a next to go to: a
    // queued video, or autoplay on with a related video to fall back to. This
    // mirrors exactly what _playNext would do, so the button never no-ops.
    final autoplayOn = prefs?.youtubeAutoplay ?? true;
    final hasNext = ref.watch(youtubeQueueProvider).isNotEmpty ||
        (autoplayOn && (details.asData?.value.related.isNotEmpty ?? false));

    // Bare, with no AspectRatio: _Body gives it an exact height and the player
    // letterboxes itself inside that. Sizing it from its own aspect ratio is
    // what made it shrink-wrap unpredictably and overlap the title.
    final player = YoutubeVideoPlayer(
      // Rebuild the player only when the video changes. The page layout is kept
      // stable across the loading -> loaded transition (see _Body), so this
      // element never moves in the tree and its State (live playback) is never
      // torn down and rebuilt.
      key: ValueKey(_videoId),
      url: _url,
      title: details.asData?.value.title ?? _title,
      channel: details.asData?.value.channelName,
      artUrl: 'https://i.ytimg.com/vi/$_videoId/hqdefault.jpg',
      // On a TV the video is fullscreen and immersive (like the Jellyfin
      // player), so it runs NON-embedded: it owns the top bar/back button and
      // grabs focus for the D-pad. On desktop/mobile it stays embedded in the
      // watch page.
      embedded: !isTvDevice,
      chapters: details.asData?.value.chapters ?? const [],
      handle: _playerHandle,
      seekBackSeconds: prefs?.youtubeSeekBackSeconds ?? 10,
      seekForwardSeconds: prefs?.youtubeSeekForwardSeconds ?? 30,
      resumeAt: _resumeAt,
      // Theater mode is a windowed-desktop concept; on a TV the video is
      // already fullscreen.
      onToggleTheater:
          isTvDevice ? null : () => setState(() => _theater = !_theater),
      theaterActive: _theater,
      // No ref in here: this fires from a timer and from the player's
      // dispose(), and touching ref once the widget is gone throws, which
      // aborts teardown and leaves the player running.
      onProgress: (position, duration) {
        _livePos = position;
        // Once, when it's first known: the page is drawn again with it.
        if (_length == null && duration > Duration.zero && mounted) {
          setState(() => _length = duration);
        }
        final d = _lastDetails;
        _history.record(
            videoId: _videoId,
            title: d?.title ?? _title ?? '',
            author: d?.channelName ?? '',
            channelId: d?.channelId,
            position: position,
            duration: duration,
            now: DateTime.now(),
          );
      },
      onEnded: () {
        if (!mounted) return;
        final d = _lastDetails;
        if (d != null) _playNext(d);
      },
      onNext: hasNext
          ? () {
              if (!mounted) return;
              final d = _lastDetails;
              if (d != null) _playNext(d);
            }
          : null,
    );

    // On a TV, play through the native ExoPlayer backend: YouTube's >720p adaptive
    // streams (video-only + audio-only, merged natively) render smoothly on the
    // SurfaceView, where media_kit's texture/copy-back path jitters. Fullscreen,
    // no page app bar. Desktop/mobile keep the embedded media_kit `player` below.
    if (isTvDevice) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: YoutubeExoPlayer(
            key: ValueKey('exo-$_videoId'),
            url: _url,
            title: details.asData?.value.title ?? _title ?? '',
            chapters: details.asData?.value.chapters ?? const [],
            queue: queue,
            related: details.asData?.value.related ?? const [],
            onPlayVideo: (v) => _open(v.id, v.title),
            seekBackSeconds: prefs?.youtubeSeekBackSeconds ?? 10,
            seekForwardSeconds: prefs?.youtubeSeekForwardSeconds ?? 30,
            resumeAt: _resumeAt,
            onBack: () => Navigator.of(context).maybePop(),
            onProgress: (position, duration) {
              final d = _lastDetails;
              _history.record(
                videoId: _videoId,
                title: d?.title ?? _title ?? '',
                author: d?.channelName ?? '',
                channelId: d?.channelId,
                position: position,
                duration: duration,
                now: DateTime.now(),
              );
            },
            onEnded: () {
              if (!mounted) return;
              final d = _lastDetails;
              if (d != null) _playNext(d);
            },
            onNext: hasNext
                ? () {
                    if (!mounted) return;
                    final d = _lastDetails;
                    if (d != null) _playNext(d);
                  }
                : null,
            onShowActions: details.asData?.value == null
                ? null
                : () =>
                    showYoutubeTvActions(context, ref, details.asData!.value,
                        length: _length),
          ),
        ),
      );
    }

    // Read here, not inside the page: the Scaffold strips the status bar
    // padding from its body's MediaQuery.
    final pageTop = MediaQuery.paddingOf(context).top +
        (Theme.of(context).appBarTheme.toolbarHeight ?? kToolbarHeight);
    return Scaffold(
      // No title here: it sits under the player, so repeating it just wastes
      // the row and truncates.
      appBar: AppBar(title: const Text('YouTube')),
      body: details.when(
        loading: () => _Body(
          player: player,
          pageTop: pageTop,
          details: null,
          theater: _theater,
          descExpanded: _descExpanded,
          onToggleDesc: () => setState(() => _descExpanded = !_descExpanded),
          onOpen: _open,
          onSeek: _playerHandle.seek,
          queue: queue,
          onPlayQueueItem: _playQueueItem,
          showComments: prefs?.youtubeShowComments ?? true,
          showRelated: prefs?.youtubeShowRelated ?? true,
          showDescription: prefs?.youtubeShowDescription ?? true,
        ),
        error: (e, _) => ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(youtubeWatchProvider(_videoId)),
        ),
        data: (d) => _Body(
          length: _length,
          player: player,
          pageTop: pageTop,
          details: d,
          theater: _theater,
          descExpanded: _descExpanded,
          onToggleDesc: () => setState(() => _descExpanded = !_descExpanded),
          onOpen: _open,
          onSeek: _playerHandle.seek,
          currentPosition: () => _livePos,
          queue: queue,
          onPlayQueueItem: _playQueueItem,
          showComments: prefs?.youtubeShowComments ?? true,
          showRelated: prefs?.youtubeShowRelated ?? true,
          showDescription: prefs?.youtubeShowDescription ?? true,
        ),
      ),
    );
  }
}

/// A lean-back actions sheet for the TV watch screen: Subscribe, Add to
/// playlist, and Go to channel — the couch-worthy actions (comments and
/// download are deliberately left to phone/desktop). D-pad friendly (ListTiles).
Future<void> showYoutubeTvActions(
    BuildContext context, WidgetRef ref, YoutubeWatchDetails d,
    {Duration? length}) {
  final l = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  final channelId = d.channelId;
  final channel = channelId == null
      ? null
      : YoutubeChannel(
          id: channelId,
          title: d.channelName,
          logoUrl: d.channelAvatarUrl ?? '',
          subscribersText: d.subscribersLabel,
        );
  final video = YoutubeVideo(
    id: d.id,
    duration: length,
    title: d.title,
    author: d.channelName,
    channelId: channelId,
    url: 'https://www.youtube.com/watch?v=${d.id}',
    thumbnailUrl: 'https://i.ytimg.com/vi/${d.id}/mqdefault.jpg',
  );
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: scheme.surfaceContainerHigh,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text(d.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (channel != null)
            Consumer(builder: (context, ref, _) {
              final subs =
                  ref.watch(youtubeSubscriptionsProvider).asData?.value ??
                      const <YoutubeChannel>[];
              final subscribed = subs.any((c) => c.id == channel.id);
              return ListTile(
                autofocus: true,
                leading: Icon(
                    subscribed ? Icons.check_rounded : Icons.add_rounded,
                    color: subscribed ? scheme.primary : null),
                title: Text(subscribed ? l.ytSubscribed : l.ytSubscribe,
                    style:
                        subscribed ? TextStyle(color: scheme.primary) : null),
                onTap: () {
                  ref
                      .read(youtubeSubscriptionsProvider.notifier)
                      .toggle(channel);
                  Navigator.of(ctx).pop();
                },
              );
            }),
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded),
            title: Text(l.ytAddToPlaylist),
            onTap: () {
              Navigator.of(ctx).pop();
              showAddToYoutubePlaylist(context, video);
            },
          ),
          if (channelId != null)
            ListTile(
              leading: const Icon(Icons.person_rounded),
              title: Text(l.ytGoToChannel),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/youtube/channel',
                    extra: (channelId: channelId, title: d.channelName));
              },
            ),
        ],
      ),
    ),
  );
}

/// Width of the Up Next rail on wide windows. A touch wider than a bare minimum
/// so the video column sits at roughly YouTube's proportions and the rail
/// thumbnails have room.
const double _railWidth = 440;

class _Body extends StatelessWidget {
  final Widget player;
  /// Where the page starts on screen, below the status bar and app bar, so a
  /// fold reported in screen coordinates can be placed within the page.
  final double pageTop;
  final YoutubeWatchDetails? details;

  /// Theater mode hides the rail and enlarges the player.
  final bool theater;
  final bool descExpanded;
  final VoidCallback onToggleDesc;
  final void Function(String videoId, String? title) onOpen;
  final void Function(Duration)? onSeek;

  /// The player's current position, for the "Listen" background hand-off.
  final Duration Function()? currentPosition;

  /// The video's length once the player knows it.
  final Duration? length;

  /// The current play queue (a playlist you started). When non-empty it drives
  /// the Up Next rail instead of related videos, and [onPlayQueueItem] jumps to
  /// one of them.
  final List<YoutubeVideo> queue;
  final void Function(int index)? onPlayQueueItem;

  /// Watch-page sections, from the YouTube settings.
  final bool showComments;
  final bool showRelated;
  final bool showDescription;

  const _Body({
    required this.player,
    this.pageTop = 0,
    required this.details,
    this.theater = false,
    required this.descExpanded,
    required this.onToggleDesc,
    required this.onOpen,
    this.onSeek,
    this.currentPosition,
    this.length,
    this.queue = const [],
    this.onPlayQueueItem,
    this.showComments = true,
    this.showRelated = true,
    this.showDescription = true,
  });

  @override
  Widget build(BuildContext context) {
    final d = details;
    // A started playlist becomes the Up Next list (NewPipe-style); otherwise
    // fall back to the video's related list.
    final upNextIsQueue = queue.isNotEmpty;
    final upNext =
        upNextIsQueue ? queue : (d?.related ?? const <YoutubeVideo>[]);

    // One LayoutBuilder decides every size on this page, from the box actually
    // available rather than from MediaQuery (which doesn't know about the app
    // bar or a sidebar) and rather than from the player's own aspect ratio.
    return LayoutBuilder(builder: (context, box) {
      // Rail visibility from window width and the theater toggle, NOT from
      // whether details have loaded. Keeping the tree shape stable across the
      // loading -> loaded transition (and across a theater toggle) is what keeps
      // the player in a fixed spot: the Row below is ALWAYS present and the
      // player ALWAYS lives inside `main`, so nothing ever reparents the (live)
      // player, which media_kit can't survive. The rail simply collapses to
      // zero width when hidden, and the related list moves below the video.
      final railVisible =
          box.maxWidth >= 1100 && (showRelated || upNextIsQueue) && !theater;
      final railW = railVisible ? _railWidth : 0.0;
      final contentWidth = box.maxWidth - railW;
      // The video sits inset from the column edges (like YouTube's watch page)
      // rather than full-bleed, so its 16:9 height comes from the inset width.
      // Theater mode lets it grow taller; otherwise it's capped so it doesn't
      // swallow the title and channel row.
      const videoMargin = 16.0;
      final videoWidth = contentWidth - videoMargin * 2;
      // Tabletop: the video fills the standing half, down to just above the
      // crease, and the title, comments and Up Next scroll on the flat half,
      // the way YouTube's own app does it. The page sits under the app bar, so
      // the crease (in screen coordinates) is moved into the page's own.
      final fold = tabletopFold(context);
      final creaseInPage = fold == null ? null : fold.position - pageTop;
      final playerHeight = creaseInPage != null && creaseInPage > 120
          ? creaseInPage - 16 - 8
          : math.min(
              videoWidth * 9 / 16, box.maxHeight * (theater ? 0.82 : 0.6));

      // The player is pinned OUTSIDE the scroll view on purpose: a Scrollable
      // gives mouse pointers a 1px drag slop, so it wins the gesture arena and
      // swallows clicks meant for the player controls.
      final main = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // An exact height, so the Column has no say in where the next child
          // goes. ClipRect is belt and braces: media_kit's Video sets
          // clipBehavior: none, and this makes it impossible for the video to
          // paint over the title again whatever it does internally.
          // Inset with rounded corners, matching YouTube's watch page, instead
          // of a full-bleed square-cornered video. ClipRRect also keeps
          // media_kit's Video (clipBehavior: none) from painting past its box.
          Padding(
            padding: const EdgeInsets.fromLTRB(videoMargin, 16, videoMargin, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: playerHeight,
                child: ColoredBox(color: Colors.black, child: player),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (d == null)
                  const YoutubeWatchSkeleton()
                else ...[
                  _Meta(details: d),
                  const SizedBox(height: 16),
                  LayoutBuilder(builder: (context, c) {
                    final actions = YoutubeVideoActionBar(
                      video: _asVideo(d, length),
                      currentPosition: currentPosition,
                      leading: AddToPlaylistButton(video: _asVideo(d, length)),
                      onShowQueue: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) => const _QueueSheet(),
                      ),
                    );
                    // Roomy row: the compact action pills ride on the channel
                    // line to the right of Subscribe (like YouTube). Tight row:
                    // they drop to their own line below so nothing crams.
                    if (c.maxWidth >= 620) {
                      return _ChannelRow(details: d, trailing: actions);
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ChannelRow(details: d),
                        const SizedBox(height: 8),
                        actions,
                      ],
                    );
                  }),
                  if (d.description.isNotEmpty && showDescription) ...[
                    const SizedBox(height: 16),
                    _Description(
                      text: d.description,
                      expanded: descExpanded,
                      onToggle: onToggleDesc,
                      onSeek: onSeek,
                    ),
                  ],
                  // Without the rail (narrow window or theater mode), the Up Next
                  // list (queue or related) goes under the description.
                  if (!railVisible &&
                      upNext.isNotEmpty &&
                      (showRelated || upNextIsQueue)) ...[
                    const SizedBox(height: 24),
                    const _UpNextHeader(),
                    const SizedBox(height: 8),
                    for (final (i, v) in upNext.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: YoutubeVideoRow(
                          video: v,
                          onTap: upNextIsQueue
                              ? () => onPlayQueueItem?.call(i)
                              : () => onOpen(v.id, v.title),
                        ),
                      ),
                  ],
                  if (d.commentsToken != null && showComments) ...[
                    const SizedBox(height: 24),
                    _Comments(token: d.commentsToken!),
                  ],
                ],
              ],
            ),
          ),
        ],
      );

      // Always a Row (never an early `return main`), so the player's tree slot
      // is identical whether or not the rail shows. Toggling theater only
      // collapses `railW` to 0 and resizes the video; the player never moves.
      return Row(
        // stretch, not start: `main` is a Column with an Expanded(ListView) in
        // it, and that needs a tight height. With start it gets loose
        // constraints, the Expanded collapses, and everything under the player
        // silently disappears.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: main),
          SizedBox(
            width: railW,
            // Zero-width with no child when the rail is hidden (narrow window or
            // theater); the related list then renders below the video in `main`.
            // The heading is outside the scroll view: scrolling a long Up Next
            // list shouldn't take its own label away with it.
            child: !railVisible
                ? null
                : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  // Top matches the video's inset (16) minus the header's own
                  // vertical breathing room, so its top edge lines up with the
                  // top of the video player rather than sitting under it.
                  padding: EdgeInsets.fromLTRB(12, 12, 16, 8),
                  child: _UpNextHeader(),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 16, 24),
                    children: [
                      // The queue shows immediately; related fills in once the
                      // page's details load (the rail stays present regardless).
                      for (final (i, v) in upNext.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: YoutubeVideoRow(
                            video: v,
                            compact: true,
                            onTap: upNextIsQueue
                                ? () => onPlayQueueItem?.call(i)
                                : () => onOpen(v.id, v.title),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) => Text(text,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w700));
}

/// The "Up Next" heading with a quick Autoplay toggle on the right, wired to the
/// same youtubeAutoplay preference as Settings, so the two stay in sync.
class _UpNextHeader extends ConsumerWidget {
  const _UpNextHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final autoplay = ref.watch(preferencesProvider
        .select((a) => a.asData?.value.youtubeAutoplay ?? true));
    return Row(
      children: [
        _SectionLabel(text: l.ytUpNext),
        const Spacer(),
        Text(l.ytAutoplay,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(width: 2),
        Transform.scale(
          scale: 0.8,
          child: Switch(
            value: autoplay,
            // Shed the default 48px tap-target height so the header row is short
            // enough to sit level with the top of the video, not below it.
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => ref
                .read(preferencesProvider.notifier)
                .edit((x) => x.copyWith(youtubeAutoplay: v)),
          ),
        ),
      ],
    );
  }
}

/// Abbreviates a count, e.g. 1234567 -> "1.2M".
String _compactCount(int n) {
  if (n >= 1000000000) {
    return '${(n / 1e9).toStringAsFixed(n >= 1e10 ? 0 : 1)}B';
  }
  if (n >= 1000000) return '${(n / 1e6).toStringAsFixed(n >= 1e7 ? 0 : 1)}M';
  if (n >= 1000) return '${(n / 1e3).toStringAsFixed(n >= 1e4 ? 0 : 1)}K';
  return '$n';
}

class _Meta extends ConsumerWidget {
  final YoutubeWatchDetails details;
  const _Meta({required this.details});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final line = [details.viewsLabel, details.dateLabel]
        .where((s) => s.isNotEmpty)
        .join('  ·  ');
    final votes = ref.watch(returnYtDislikesProvider(details.id)).asData?.value;
    final deArrow =
        ref.watch(deArrowTitleProvider(details.id)).asData?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(deArrow ?? details.title,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (line.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(line,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
        if (votes != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.thumb_up_rounded, size: 15, color: scheme.onSurface),
              const SizedBox(width: 5),
              Text(_compactCount(votes.likes),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              Icon(Icons.thumb_down_rounded, size: 15, color: scheme.onSurface),
              const SizedBox(width: 5),
              Text(_compactCount(votes.dislikes),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ],
    );
  }
}

/// The watch details as a YoutubeVideo, for the actions that take one.
YoutubeVideo _asVideo(YoutubeWatchDetails d, Duration? length) => YoutubeVideo(
      id: d.id,
      duration: length,
      title: d.title,
      author: d.channelName,
      url: 'https://www.youtube.com/watch?v=${d.id}',
      thumbnailUrl: 'https://i.ytimg.com/vi/${d.id}/hqdefault.jpg',
      channelId: d.channelId,
    );

/// Channel avatar, name, subscriber count, and a Subscribe toggle.
///
/// Channel avatar, name/subscribers, and Subscribe. On a wide row the video's
/// action pills ([trailing]) ride to the right of Subscribe; on a tight one the
/// caller drops them to their own line, so the labelled-button overflow that
/// once forced a permanent second line (304px over at 420px wide) can't happen.
class _ChannelRow extends StatelessWidget {
  final YoutubeWatchDetails details;

  /// The video's action pills, placed to the right of Subscribe when the row is
  /// wide enough; null puts them on their own line below (see the caller).
  final Widget? trailing;
  const _ChannelRow({required this.details, this.trailing});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final channelId = details.channelId;
    final name =
        details.channelName.isNotEmpty ? details.channelName : l.ytChannelFallback;
    final avatar = details.channelAvatarUrl;

    final openChannel = channelId == null
        ? null
        : () => context.push('/youtube/channel',
            extra: (channelId: channelId, title: name));

    Widget tappable = GestureDetector(
      onTap: openChannel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: scheme.surfaceContainerHigh,
            foregroundImage:
                (avatar == null) ? null : cachedImageProvider(avatar),
            child: const Icon(Icons.person_rounded, size: 18),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (details.subscribersLabel.isNotEmpty)
                  Text(details.subscribersLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
    // On TV a bare GestureDetector isn't a D-pad stop; make it focusable and
    // ringed so the remote can open the channel. Only when there's a channel to
    // open (otherwise the row has no tap).
    if (isTvDevice && openChannel != null) {
      tappable = TvFocusable(
        onTap: openChannel,
        borderRadius: BorderRadius.circular(12),
        scale: 1.03,
        child: tappable,
      );
    }

    // A long channel name ellipsizes rather than pushing Subscribe off the edge.
    final channel = Flexible(
      child: MouseRegion(
        cursor:
            channelId == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: tappable,
      ),
    );

    // The channel cluster + Subscribe, left-aligned.
    final left = <Widget>[
      channel,
      const SizedBox(width: 16),
      if (channelId != null)
        SubscribeButton(
          channel: YoutubeChannel(
            id: channelId,
            title: name,
            logoUrl: avatar ?? '',
          ),
        ),
    ];

    if (trailing == null) return Row(children: left);

    // Actions pinned to the far right: the left cluster takes the slack via
    // Expanded, so the pills sit at the row's right edge (flush with the video
    // above), not stranded in the middle.
    return Row(
      children: [
        Expanded(child: Row(children: left)),
        const SizedBox(width: 16),
        trailing!,
      ],
    );
  }
}

/// The queue: reorder it, drop things from it, or jump straight to one.
class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final queue = ref.watch(youtubeQueueProvider);
    final notifier = ref.read(youtubeQueueProvider.notifier);
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
              child: Row(
                children: [
                  Text(l.ytUpNextInQueue,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  TextButton(
                    onPressed: queue.isEmpty
                        ? null
                        : () async {
                            final needsConfirm = ref
                                    .read(preferencesProvider)
                                    .asData
                                    ?.value
                                    .youtubeConfirmClearQueue ??
                                true;
                            if (needsConfirm) {
                              final ok = await confirm(context,
                                  title: l.ytClearQueueTitle,
                                  message: l.ytClearQueueConfirm(queue.length),
                                  confirmLabel: l.commonClear,
                                  destructive: true);
                              if (!ok) return;
                            }
                            notifier.clear();
                            if (context.mounted) Navigator.pop(context);
                          },
                    child: Text(l.commonClear),
                  ),
                ],
              ),
            ),
            Flexible(
              child: queue.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      child: Text(l.ytNothingQueued),
                    )
                  : ReorderableListView.builder(
                      shrinkWrap: true,
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: queue.length,
                      onReorderItem: notifier.reorder,
                      itemBuilder: (context, i) {
                        final v = queue[i];
                        return dragAnywhere(
                          key: ValueKey(v.id),
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(Icons.drag_indicator,
                                    color: dragGripColor(context)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: YoutubeVideoRow(
                                    video: v,
                                    compact: true,
                                    showMenu: false,
                                    onTap: () {
                                      notifier.remove(v.id);
                                      Navigator.pop(context);
                                      context.push('/youtube/watch',
                                          extra: (
                                            videoId: v.id,
                                            title: v.title
                                          ));
                                    },
                                    extraMenuItems: [
                                      ContextMenuAction(
                                        icon: Icons
                                            .remove_circle_outline_rounded,
                                        label: l.ytRemoveFromQueue,
                                        onTap: () => notifier.remove(v.id),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top-level comments for the video.
class _Comments extends ConsumerWidget {
  final String token;
  const _Comments({required this.token});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(youtubeCommentsProvider(token));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: AppSpinner()),
      ),
      // Comments failing shouldn't shout; the video is the point.
      error: (e, _) => const SizedBox.shrink(),
      data: (page) {
        if (page.comments.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                child: _CommentRow(comment: c),
              ),
            if (page.hasMore)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: page.loadingMore
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: AppSpinner.inline(),
                        )
                      : TextButton.icon(
                          onPressed: () => ref
                              .read(youtubeCommentsProvider(token).notifier)
                              .loadMore(),
                          icon: const Icon(Icons.expand_more_rounded),
                          label: Text(l.ytShowMoreComments),
                        ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CommentRow extends ConsumerStatefulWidget {
  final YoutubeComment comment;
  final bool isReply;
  const _CommentRow({required this.comment, this.isReply = false});

  @override
  ConsumerState<_CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends ConsumerState<_CommentRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = widget.comment;
    final isReply = widget.isReply;
    final canExpand = !isReply && c.replyToken != null && c.replyCount > 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: isReply ? 12 : 16,
          backgroundColor: scheme.surfaceContainerHigh,
          foregroundImage:
              c.avatarUrl.isEmpty ? null : cachedImageProvider(c.avatarUrl),
          child: Icon(Icons.person_rounded, size: isReply ? 11 : 14),
        ),
        SizedBox(width: isReply ? 10 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: c.isCreator
                          ? const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2)
                          : EdgeInsets.zero,
                      decoration: c.isCreator
                          ? BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            )
                          : null,
                      child: Text(
                        c.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: c.isCreator
                              ? scheme.onPrimary
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  if (c.isVerified) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.check_circle,
                        size: 13, color: scheme.onSurfaceVariant),
                  ],
                  if (c.publishedLabel.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(c.publishedLabel,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              SelectableText(c.text,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
              if (c.likeLabel.isNotEmpty || (!isReply && c.replyCount > 0)) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (c.likeLabel.isNotEmpty) ...[
                      Icon(Icons.thumb_up_outlined,
                          size: 13, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 5),
                      Text(c.likeLabel,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                    if (!isReply && c.replyCount > 0) ...[
                      if (c.likeLabel.isNotEmpty) const SizedBox(width: 8),
                      if (canExpand)
                        TvFocusRing(
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            onTap: () =>
                                setState(() => _expanded = !_expanded),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                      _expanded
                                          ? Icons.keyboard_arrow_up_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                      size: 18,
                                      color: scheme.primary),
                                  const SizedBox(width: 2),
                                  Text(l.ytReplies(c.replyCount),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                              l.ytReplies(c.replyCount),
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ),
                    ],
                  ],
                ),
              ],
              if (_expanded && c.replyToken != null)
                _replies(c.replyToken!, theme, scheme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _replies(String token, ThemeData theme, ColorScheme scheme) {
    final async = ref.watch(youtubeCommentRepliesProvider(token));
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 2),
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: AppSpinner.inline(),
        ),
        error: (_, _) => Text(AppLocalizations.of(context).ytCouldNotLoadReplies,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
        data: (replies) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in replies)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _CommentRow(comment: r, isReply: true),
              ),
          ],
        ),
      ),
    );
  }
}

/// Collapsed description with a show more/less toggle.
/// Matches the timestamps creators write into descriptions: 1:23, 01:23,
/// 1:02:03. Anchored so it doesn't match inside a longer run of digits and
/// colons, which is what turns "1234:56" into a bogus link.
final _timestampPattern =
    RegExp(r'(?<![\d:])(\d{1,2}:)?\d{1,2}:\d{2}(?![\d:])');

Duration? _parseTimestamp(String s) {
  final parts = s.split(':').map(int.tryParse).toList();
  if (parts.any((p) => p == null)) return null;
  return switch (parts.length) {
    2 => Duration(minutes: parts[0]!, seconds: parts[1]!),
    3 => Duration(hours: parts[0]!, minutes: parts[1]!, seconds: parts[2]!),
    _ => null,
  };
}

class _Description extends StatelessWidget {
  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  /// Seeks the player. Null leaves timestamps as plain text.
  final void Function(Duration)? onSeek;

  const _Description({
    required this.text,
    required this.expanded,
    required this.onToggle,
    this.onSeek,
  });

  /// The description with its timestamps turned into tappable spans, which is
  /// how creators actually index a long video.
  List<InlineSpan> _spans(BuildContext context) {
    final seek = onSeek;
    final theme = Theme.of(context);
    if (seek == null) return [TextSpan(text: text)];

    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _timestampPattern.allMatches(text)) {
      final at = _parseTimestamp(m.group(0)!);
      if (at == null) continue;
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(0),
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
        recognizer: TapGestureRecognizer()..onTap = () => seek(at),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: Text.rich(
              TextSpan(children: _spans(context)),
              maxLines: expanded ? null : 3,
              overflow: expanded ? TextOverflow.clip : TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onToggle,
              child: Text(expanded ? l.ytShowLess : l.ytShowMore),
            ),
          ),
        ],
      ),
    );
  }
}
