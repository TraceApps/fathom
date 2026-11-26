import 'package:flutter/material.dart';
import '../api/error_text.dart';
import '../widgets/cached_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/youtube_channel.dart';
import '../state/youtube_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/mini_player.dart';
import '../widgets/subscribe_button.dart';
import '../widgets/tv_focus.dart';
import '../widgets/youtube_video_collection.dart';
import '../widgets/youtube_skeletons.dart';
import '../models/youtube_playlist.dart';
import '../services/youtube_innertube.dart';
import '../services/tv_mode.dart';
import '../l10n/generated/app_localizations.dart';
import '../widgets/app_spinner.dart';

/// A YouTube channel page: banner + avatar header, a subscribe toggle, and the
/// channel's content split by tab.
///
/// Uploads keep their own paginating provider (youtube_explode, which pages
/// properly); the other tabs come from the InnerTube browse endpoint. Only tabs
/// the channel actually has are shown — YouTube answers a request for a missing
/// tab with the Home feed rather than an error, so offering all four would put
/// ordinary videos under a Live heading.
class YoutubeChannelScreen extends ConsumerStatefulWidget {
  final String channelId;
  final String? title; // shown while the channel details load

  const YoutubeChannelScreen({super.key, required this.channelId, this.title});

  @override
  ConsumerState<YoutubeChannelScreen> createState() =>
      _YoutubeChannelScreenState();
}

class _YoutubeChannelScreenState extends ConsumerState<YoutubeChannelScreen> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // The Videos tab doubles as the probe for which tabs exist AND carries the
    // channel header (name/avatar/banner/subs). That replaces a separate
    // multi-megabyte channel-page scrape that used to stall this screen.
    final probe = ref.watch(youtubeChannelTabProvider(
        (channelId: widget.channelId, kind: YtChannelTabKind.videos)));
    final channel = probe.asData?.value.channel;
    final available = probe.asData?.value.availableTabs ?? const <String>{};

    final tabs = <YtChannelTabKind>[
      YtChannelTabKind.videos,
      for (final k in [
        YtChannelTabKind.shorts,
        YtChannelTabKind.live,
        YtChannelTabKind.playlists,
      ])
        if (available.contains(k.title)) k,
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        // Root route outside the shell, so dock the background-audio bar here
        // too (collapses when idle, hidden on TV).
        bottomNavigationBar: const MiniPlayer(),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              pinned: true,
              title: Text(channel?.title ?? widget.title ?? l.ytChannelFallback),
            ),
            SliverToBoxAdapter(
              child: probe.when(
                loading: () => const SizedBox(
                  height: 140,
                  child: Center(child: AppSpinner()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: ErrorView(
                    message: errorText(e),
                    onRetry: () => ref.invalidate(youtubeChannelTabProvider(
                        (channelId: widget.channelId,
                        kind: YtChannelTabKind.videos))),
                  ),
                ),
                data: (tab) => _Header(
                  channel: tab.channel ??
                      YoutubeChannel(
                        id: widget.channelId,
                        title: widget.title ?? '',
                        logoUrl: '',
                      ),
                  fallbackName: widget.title,
                ),
              ),
            ),
            if (tabs.length > 1)
              SliverToBoxAdapter(
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [for (final t in tabs) Tab(text: t.title)],
                ),
              ),
          ],
          body: TabBarView(
            children: [
              for (final t in tabs)
                t == YtChannelTabKind.videos
                    ? _UploadsTab(channelId: widget.channelId)
                    : _BrowseTab(channelId: widget.channelId, kind: t),
            ],
          ),
        ),
      ),
    );
  }
}

/// The channel's uploads, paged through the InnerTube browse endpoint (full
/// metadata, one request per page).
class _UploadsTab extends ConsumerWidget {
  final String channelId;
  const _UploadsTab({required this.channelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final uploads = ref.watch(youtubeChannelUploadsProvider(channelId));
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        final res = uploads.asData?.value;
        if (res != null &&
            res.hasMore &&
            !res.loadingMore &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 600) {
          ref.read(youtubeChannelUploadsProvider(channelId).notifier).loadMore();
        }
        return false;
      },
      child: uploads.when(
        loading: () => const YoutubeVideosSkeleton(),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorView(
            message: errorText(e),
            onRetry: () =>
                ref.invalidate(youtubeChannelUploadsProvider(channelId)),
          ),
        ),
        data: (res) {
          if (res.videos.isEmpty) {
            return EmptyState(
                icon: Icons.videocam_off_rounded, title: l.ytNoUploads);
          }
          // The channel is already in the header, so don't repeat it.
          return YoutubeVideoCollection(
            videos: res.videos,
            showAuthor: false,
            loadingMore: res.hasMore,
          );
        },
      ),
    );
  }
}

/// Shorts / Live / Playlists, from the browse endpoint.
class _BrowseTab extends ConsumerWidget {
  final String channelId;
  final YtChannelTabKind kind;
  const _BrowseTab({required this.channelId, required this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tab = ref
        .watch(youtubeChannelTabProvider((channelId: channelId, kind: kind)));
    return tab.when(
      loading: () => const YoutubeVideosSkeleton(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(
              youtubeChannelTabProvider((channelId: channelId, kind: kind))),
        ),
      ),
      data: (t) {
        // isRequestedTab guards the Home fallback: without it this would show
        // the channel's ordinary videos under a Live heading.
        if (!t.isRequestedTab || t.isEmpty) {
          return EmptyState(
            icon: Icons.videocam_off_rounded,
            title: l.ytNothingInTab(kind.title),
          );
        }
        if (t.playlists.isEmpty) {
          return YoutubeVideoCollection(
            videos: t.videos,
            showAuthor: false,
            // Tapping a Short opens the vertical swipe viewer over this list
            // (paging in more of the channel's Shorts on demand) instead of the
            // regular watch page. Other tabs keep the default watch navigation.
            onTap: kind == YtChannelTabKind.shorts && !isTvDevice
                ? (v) => context.push('/youtube/shorts', extra: (
                      shorts: t.videos,
                      startIndex: t.videos
                          .indexWhere((x) => x.id == v.id)
                          .clamp(0, t.videos.length - 1),
                      continuation: t.continuation,
                    ))
                : null,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: t.playlists.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _ChannelPlaylistRow(playlist: t.playlists[i]),
        );
      },
    );
  }
}

class _ChannelPlaylistRow extends StatelessWidget {
  final YoutubePlaylist playlist;
  const _ChannelPlaylistRow({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return TvFocusRing(
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/youtube/playlist',
            extra: (
              playlistId: playlist.id,
              title: playlist.title,
              count: playlist.videoCount
            )),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 140,
                  height: 79,
                  child: playlist.thumbnailUrl.isEmpty
                      ? Container(color: scheme.surfaceContainerHigh)
                      : CachedImage(
                          url: playlist.thumbnailUrl,
                          errorBuilder: (_) =>
                              Container(color: scheme.surfaceContainerHigh)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(playlist.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (playlist.videoCountLabel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(playlist.videoCountLabel,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Not a ConsumerWidget: the subscriptions provider is watched inside
/// [SubscribeButton] alone, so the header renders regardless of its state.
class _Header extends StatelessWidget {
  final YoutubeChannel channel;

  /// The name we already knew (from the video row). Used when the channel
  /// listing comes back without a title, which it sometimes does.
  final String? fallbackName;

  const _Header({required this.channel, this.fallbackName});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (channel.bannerUrl != null)
          SizedBox(
            height: 140,
            width: double.infinity,
            child: CachedImage(
              url: channel.bannerUrl!,
              errorBuilder: (_) =>
                  Container(color: scheme.surfaceContainerHigh),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: scheme.surfaceContainerHigh,
                foregroundImage: channel.logoUrl.isEmpty
                    ? null
                    : cachedImageProvider(channel.logoUrl),
                child: const Icon(Icons.person_rounded),
              ),
              const SizedBox(width: 16),
              // Keep the name and Subscribe together: an Expanded here strands
              // the button at the far edge of a wide window.
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.title.isNotEmpty
                          ? channel.title
                          : (fallbackName ?? l.ytChannelFallback),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (channel.subscribersLabel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        channel.subscribersLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 20),
              SubscribeButton(channel: channel),
              const Spacer(),
            ],
          ),
        ),
      ],
    );
  }
}
