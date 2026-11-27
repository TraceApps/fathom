import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../state/downloads.dart';
import '../state/library_providers.dart';
import '../state/preferences.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../state/audio_player.dart' show audioControllerProvider;
import '../state/watchlist.dart';
import 'watchlist_toggle.dart';
import 'add_to_playlist.dart';
import 'context_menu.dart';
import 'series_download_sheet.dart';
import 'app_snack.dart';
import 'ui_common.dart';
import '../api/jellyfin_client.dart';

/// Shared per-item context menu (the "hamburger"), the same surface Jellyfin and
/// Fladder expose on a poster, in a detail page, and on an individual episode.
/// Reached off TV by long-press / right-click / a hover hamburger, and on TV by
/// the episode row's visible three-dot stop (grids on TV use the detail
/// overflow instead, keeping the card's D-pad path untouched).
///
/// Presented via [showContextMenu] (a dropdown on a mouse-driven desktop, a
/// bottom sheet on touch/TV), so it always matches every other item menu in
/// the app instead of rolling its own look.
///
/// [at] anchors the desktop dropdown to where the click/tap happened.
/// [fromGrid] adds a "Show Details" row (pointless on a page that already shows
/// them). [onOpenDetails] performs that navigation (usually the card's own tap).
/// [onDeleted] runs after a successful delete (e.g. pop the detail route); when
/// null the caller relies on provider invalidation to refresh a list in place.
Future<void> showItemActionsMenu(
  BuildContext context,
  WidgetRef ref,
  BaseItemDto item, {
  required Offset at,
  bool fromGrid = false,
  VoidCallback? onOpenDetails,
  VoidCallback? onDeleted,
  // Overrides the stored kind for a download (e.g. 'Recording' when the item is
  // reached from the recordings context), so it classifies correctly.
  String? downloadAsType,
  /// Starts multi-select on the grid this item came from. Only grids that can
  /// act on a whole selection pass it, so the row is absent elsewhere.
  VoidCallback? onSelect,
  /// Opened from a Continue Watching card, where every entry can be removed,
  /// including a waiting episode that has no resume point of its own.
  bool inContinueWatching = false,
}) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // The app-wide container, not the caller's `ref`: actions run after the menu
  // closes, and a grid card can be recycled by a scroll (or the route popped)
  // in the meantime, which would make the caller's `ref` throw.
  final container = ProviderScope.containerOf(context, listen: false);
  final cs = Theme.of(context).colorScheme;
  final user = container.read(currentUserProvider).asData?.value;
  final session = container.read(sessionControllerProvider).asData?.value;
  // Mirror the detail overflow's gate exactly (session fallback included) so
  // the same admin sees the same rows from a poster, an episode, or detail.
  final canDelete = (user?.enableContentDeletion ?? false) ||
      (user?.isAdministrator ?? false) ||
      (session?.canDelete ?? false);
  final canRefresh =
      (user?.isAdministrator ?? false) || (session?.isAdmin ?? false);

  final isPlayable = item.isEpisode ||
      item.type == 'Movie' ||
      item.type == 'Video' ||
      item.type == 'MusicVideo' ||
      item.type == 'Audio' ||
      item.type == 'Recording' ||
      item.type == 'TvChannel';
  // Downloadable for offline: a single video (movie/episode/recording), a
  // whole series/season (which queues its episodes), or music: a track, or an
  // album/artist (which queues its tracks). Live channels use their own flow.
  final isDownloadable = item.isEpisode ||
      item.type == 'Movie' ||
      item.type == 'Video' ||
      item.type == 'MusicVideo' ||
      item.type == 'Recording' ||
      item.type == 'Audio' ||
      item.type == 'MusicAlbum' ||
      item.type == 'MusicArtist' ||
      item.isSeries ||
      item.type == 'Season';

  String deleteLabel() {
    if (item.isSeries) return l.actionDeleteSeries;
    if (item.isEpisode) return l.actionDeleteEpisode;
    if (item.type == 'Season') return l.actionDeleteSeason;
    if (item.type == 'Movie') return l.actionDeleteMovie;
    return l.commonDelete;
  }

  final actions = <ContextMenuAction>[];
  if (isPlayable) {
    actions.add(ContextMenuAction(
      icon: item.canResume
          ? Icons.play_circle_outline_rounded
          : Icons.play_arrow_rounded,
      label: item.canResume ? l.detailResume : l.commonPlay,
      // A song goes to the music player, not the video one.
      onTap: item.isAudio
          ? () => container
              .read(audioControllerProvider.notifier)
              .playQueue([item], 0)
          : () => context.push('/player', extra: item),
    ));
  }
  if (fromGrid && onOpenDetails != null) {
    actions.add(ContextMenuAction(
      icon: Icons.info_outline_rounded,
      label: l.actionShowDetails,
      onTap: onOpenDetails,
    ));
  }
  if (onSelect != null) {
    actions.add(ContextMenuAction(
      icon: Icons.checklist_rounded,
      label: l.actionSelect,
      onTap: onSelect,
    ));
  }
  // People, artists and playlists aren't watched or added to a playlist:
  // only favorited. Music isn't "watched" either.
  final isMedia =
      !const {'Person', 'MusicArtist', 'Playlist'}.contains(item.type);
  final isWatched =
      isMedia && !item.isAudio && !const {'MusicAlbum'}.contains(item.type);
  if (isWatched) {
    actions.add(ContextMenuAction(
      icon: item.userData.played
          ? Icons.check_circle_rounded
          : Icons.check_circle_outline_rounded,
      label:
          item.userData.played ? l.detailMarkUnwatched : l.detailMarkWatched,
      onTap: () => _mutate(messenger, () async {
        final s = container.read(sessionControllerProvider).asData?.value;
        if (s == null) return;
        await container.read(jellyfinClientProvider).setPlayed(
              baseUrl: s.baseUrl,
              userId: s.userId,
              token: s.accessToken,
              itemId: item.id,
              played: !item.userData.played,
            );
        _invalidateLists(container, item);
      }),
    ));
  }
  // From the row itself, anything in it can go. Elsewhere, only something that
  // actually has a resume point (live channels carry a position too, but they
  // aren't in that row).
  final canRemoveFromRow = inContinueWatching ||
      (item.resumePositionTicks > 0 && item.type != 'TvChannel');
  if (canRemoveFromRow) {
    actions.add(ContextMenuAction(
      icon: Icons.remove_circle_outline_rounded,
      label: l.actionRemoveFromContinueWatching,
      onTap: () => _mutate(messenger, () async {
        final s = container.read(sessionControllerProvider).asData?.value;
        if (s == null) return;
        // Clear the server's resume point where there is one, so Jellyfin's
        // own apps agree the title isn't in progress any more.
        if (item.resumePositionTicks > 0) {
          await container.read(jellyfinClientProvider).clearResumePosition(
                baseUrl: s.baseUrl,
                userId: s.userId,
                token: s.accessToken,
                itemId: item.id,
              );
        }
        // And remember the removal. Clearing a resume point alone wasn't
        // enough once the row merged in Next Up: the show came straight back
        // as its waiting episode, so Remove looked like it did nothing.
        await _dismissFromContinueWatching(container, s.userId, item);
        _invalidateLists(container, item);
      }),
    ));
  }
  actions.add(ContextMenuAction(
    icon: item.userData.isFavorite
        ? Icons.favorite_rounded
        : Icons.favorite_border_rounded,
    label:
        item.userData.isFavorite ? l.detailRemoveFavorite : l.detailAddFavorite,
    color: item.userData.isFavorite ? Colors.redAccent : null,
    onTap: () => _mutate(messenger, () async {
      final s = container.read(sessionControllerProvider).asData?.value;
      if (s == null) return;
      await container.read(jellyfinClientProvider).setFavorite(
            baseUrl: s.baseUrl,
            userId: s.userId,
            token: s.accessToken,
            itemId: item.id,
            favorite: !item.userData.isFavorite,
          );
      _invalidateLists(container, item);
      showSnackOn(
        messenger,
        item.userData.isFavorite ? l.favoriteRemoved : l.favoriteAdded,
        kind: SnackKind.success,
      );
    }),
  ));
  final watchlist =
      container.read(watchlistProvider).asData?.value ?? const <BaseItemDto>[];
  if (hasWatchlistToggle(watchlist, item)) {
    final inWatchlist = inWatchlistFor(watchlist, item);
    actions.add(ContextMenuAction(
      icon:
          inWatchlist ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
      label: watchlistToggleLabel(l, watchlist, item),
      color: inWatchlist ? cs.primary : null,
      onTap: () => toggleWatchlist(messenger, l,
          container.read(watchlistProvider.notifier), watchlist, item),
    ));
  }
  if (isMedia) {
    actions.add(ContextMenuAction(
      icon: Icons.playlist_add_rounded,
      label: l.detailAddToPlaylist,
      onTap: () => showAddToPlaylistSheet(context, ref,
          itemIds: [item.id], label: item.name),
    ));
  }
  if (isDownloadable) {
    final downloads =
        container.read(downloadsProvider).asData?.value ?? const {};
    final isFolder = item.isSeries || item.type == 'Season';
    if (isFolder) {
      // A series offers a scope choice (All / a season); a season is already
      // one scope, so it downloads directly.
      actions.add(ContextMenuAction(
        icon: Icons.download_rounded,
        label: l.detailDownload,
        onTap: () => item.isSeries
            ? showSeriesDownloadSheet(context, item, asType: downloadAsType)
            : container
                .read(downloadsProvider.notifier)
                .download(item, asType: downloadAsType),
      ));
      final hasDownloads = item.isSeries
          ? downloads.values.any((e) => e.seriesId == item.id)
          : downloads.values.any((e) =>
              e.seriesId == item.seriesId &&
              e.seasonNumber == item.indexNumber);
      if (hasDownloads) {
        actions.add(ContextMenuAction(
          icon: Icons.download_done_rounded,
          label: l.detailRemoveDownload,
          onTap: () async {
            final d = container.read(downloadsProvider.notifier);
            if (item.isSeries) {
              await d.deleteSeries(item.id);
            } else {
              await d.deleteSeason(item.seriesId ?? '', item.indexNumber);
            }
          },
        ));
      }
    } else {
      final entry = downloads[item.id];
      if (entry?.status == DownloadStatus.complete) {
        actions.add(ContextMenuAction(
          icon: Icons.download_done_rounded,
          label: l.detailRemoveDownload,
          onTap: () =>
              container.read(downloadsProvider.notifier).delete(item.id),
        ));
      } else if (entry == null || entry.status == DownloadStatus.failed) {
        actions.add(ContextMenuAction(
          icon: Icons.download_rounded,
          label: l.detailDownload,
          onTap: () => container
              .read(downloadsProvider.notifier)
              .download(item, asType: downloadAsType),
        ));
      }
    }
  }
  if (canRefresh) {
    actions.add(ContextMenuAction(
      icon: Icons.refresh_rounded,
      label: l.detailRefreshMetadata,
      onTap: () async {
        final started = l.detailMetadataRefreshStarted;
        await _mutate(messenger, () async {
          final s = container.read(sessionControllerProvider).asData?.value;
          if (s == null) return;
          await container.read(jellyfinClientProvider).refreshItem(
                baseUrl: s.baseUrl,
                token: s.accessToken,
                itemId: item.id,
              );
          showSnackOn(messenger, started, kind: SnackKind.success);
        });
      },
    ));
  }
  if (canDelete) {
    actions.add(ContextMenuAction(
      icon: Icons.delete_outline_rounded,
      label: deleteLabel(),
      color: cs.error,
      onTap: () =>
          _confirmAndDelete(context, container, messenger, item, onDeleted),
    ));
  }

  await showContextMenu(context, at: at, actions: actions, title: item.name);
}

Future<void> _mutate(
  ScaffoldMessengerState messenger,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    showErrorOn(messenger, e);
  }
}

Future<void> _confirmAndDelete(
  BuildContext context,
  ProviderContainer container,
  ScaffoldMessengerState messenger,
  BaseItemDto item,
  VoidCallback? onDeleted,
) async {
  final l = AppLocalizations.of(context);
  final s = container.read(sessionControllerProvider).asData?.value;
  if (s == null) return;
  final ok = await confirm(context,
      title: l.detailDeleteItem,
      message: l.detailDeleteConfirm(item.name),
      confirmLabel: l.commonDelete,
      destructive: true);
  if (!ok) return;
  try {
    await container.read(jellyfinClientProvider).deleteItem(
          baseUrl: s.baseUrl,
          token: s.accessToken,
          itemId: item.id,
        );
    _invalidateLists(container, item);
    if (item.isEpisode) {
      final sid = item.seriesId;
      if (sid != null) {
        container.invalidate(episodesProvider(sid));
        container.invalidate(nextUpProvider(sid));
      }
    }
    onDeleted?.call();
    showSnackOn(messenger, l.detailDeleted(item.name), kind: SnackKind.success);
  } catch (e) {
    showErrorOn(messenger, e);
  }
}

/// Takes a show (or film) off the Continue Watching row until it's watched
/// again. Keeps the most recent 200, so a long-lived account's list can't grow
/// without bound.
Future<void> _dismissFromContinueWatching(
    ProviderContainer container, String userId, BaseItemDto item) async {
  final key = '$userId|${continueWatchingKey(item)}';
  final now = DateTime.now().toUtc().toIso8601String();
  await container.read(preferencesProvider.notifier).edit((p) {
    final next = {...p.continueWatchingDismissed, key: now};
    if (next.length > 200) {
      final newest = next.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      next
        ..clear()
        ..addEntries(newest.take(200));
    }
    return p.copyWith(continueWatchingDismissed: next);
  });
}

void _invalidateLists(ProviderContainer container, BaseItemDto item) {
  container.invalidate(itemDetailProvider(item.id));
  container.invalidate(resumeItemsProvider);
  container.invalidate(latestItemsProvider);
  container.invalidate(favoriteItemsProvider);
  // Next Up is where a just-watched episode is most visibly wrong: without
  // this the row keeps offering the episode, and its checkmark only appears
  // after a manual refresh. An episode also changes its series' progress and
  // its place in the episode list, so refresh those from the series id.
  container.invalidate(nextUpItemsProvider);
  final seriesId = item.isSeries ? item.id : item.seriesId;
  if (seriesId != null) {
    container.invalidate(itemDetailProvider(seriesId));
    container.invalidate(episodesProvider(seriesId));
    container.invalidate(nextUpProvider(seriesId));
  }
}
