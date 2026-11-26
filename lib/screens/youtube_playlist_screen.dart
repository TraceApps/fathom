import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/error_text.dart';
import '../services/tv_mode.dart';
import '../state/audio_player.dart';
import '../state/youtube_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/mini_player.dart';
import '../widgets/youtube_actions.dart';
import '../widgets/youtube_cards.dart';
import '../widgets/youtube_skeletons.dart';
import '../models/youtube_playlist.dart';
import '../l10n/generated/app_localizations.dart';

/// A playlist's videos, in playlist order.
class YoutubePlaylistScreen extends ConsumerWidget {
  final String playlistId;
  final String? title; // shown while the playlist loads

  /// The video count the playlist card advertised. Used only to note, quietly,
  /// when fewer load than that — YouTube counts age-restricted/private videos it
  /// then won't hand an anonymous client, so the two numbers legitimately differ.
  final int? expectedCount;

  const YoutubePlaylistScreen({
    super.key,
    required this.playlistId,
    this.title,
    this.expectedCount,
  });

  /// Saving keeps a reference, not the contents: the playlist belongs to
  /// someone else and keeps changing, so it's refetched when opened.

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final videos = ref.watch(youtubePlaylistProvider(playlistId));
    final saved = ref.watch(youtubeSavedPlaylistsProvider).asData?.value
            .any((p) => p.id == playlistId) ??
        false;

    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? l.ytPlaylistFallback),
        actions: [
          // Play the whole playlist as background audio: the first item plays and
          // the rest become the shared up-next queue. Phone/desktop only.
          if (!isTvDevice)
            IconButton(
              tooltip: l.ytListenAll,
              icon: const Icon(Icons.headset_rounded),
              onPressed: () {
                final list = videos.asData?.value ?? const [];
                if (list.isEmpty) return;
                ref
                    .read(youtubeQueueProvider.notifier)
                    .playAll(list.sublist(1));
                ref
                    .read(audioControllerProvider.notifier)
                    .playYoutubeAudio(youtubeAudioItemOf(list.first));
              },
            ),
          IconButton(
            tooltip: saved ? l.ytSaved : l.ytSavePlaylist,
            color: saved ? Theme.of(context).colorScheme.primary : null,
            icon: Icon(saved
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded),
            onPressed: () => ref
                .read(youtubeSavedPlaylistsProvider.notifier)
                .toggle(YoutubePlaylist(
                  id: playlistId,
                  title: title ?? l.ytPlaylistFallback,
                  thumbnailUrl:
                      videos.asData?.value.firstOrNull?.thumbnailUrl ?? '',
                  author: videos.asData?.value.firstOrNull?.author ?? '',
                )),
          ),
        ],
      ),
      // Dock the background-audio bar here: this screen is a root route outside
      // the app shell, so it wouldn't otherwise show the mini-player. Collapses
      // to nothing when nothing's playing and is hidden on TV.
      bottomNavigationBar: const MiniPlayer(),
      body: videos.when(
        loading: () => const YoutubeVideosSkeleton(),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorView(
            message: errorText(e),
            onRetry: () => ref.invalidate(youtubePlaylistProvider(playlistId)),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.playlist_remove_rounded,
              title: l.ytNothingInPlaylist,
            );
          }
          final expected = expectedCount;
          final incomplete = expected != null && list.length < expected;
          final listView = ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => YoutubeVideoRow(
              video: list[i],
              // Start the playlist from this item: play it and make the rest the
              // up-next queue, so Next/autoplay walk the playlist (NewPipe-style).
              onTap: () {
                ref
                    .read(youtubeQueueProvider.notifier)
                    .playAll(list.sublist(i + 1));
                context.push('/youtube/watch',
                    extra: (videoId: list[i].id, title: list[i].title));
              },
            ),
          );
          if (!incomplete) return listView;
          final scheme = Theme.of(context).colorScheme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 15, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l.ytSomeUnavailable,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: listView),
            ],
          );
        },
      ),
    );
  }
}
