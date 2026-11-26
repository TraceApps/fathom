import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../services/tv_mode.dart';
import '../state/audio_player.dart';
import '../state/downloads.dart';
import '../state/library_providers.dart';
import '../widgets/context_menu.dart';
import '../widgets/equalizer_bars.dart';
import '../widgets/media_image.dart';
import '../widgets/tv_focus.dart';
import '../widgets/hover_pill_button.dart';
import '../widgets/app_spinner.dart';
import '../widgets/ui_common.dart';
import '../widgets/error_view.dart';

/// Album detail: cover, artist, a play button, and the track list. Rendered by
/// DetailScreen when the item is a MusicAlbum online; in [downloadScoped] mode
/// it's the download folder's copy — only downloaded tracks, playing locally,
/// with Remove instead of Download.
class AlbumView extends ConsumerWidget {
  final BaseItemDto album;
  final bool downloadScoped;
  const AlbumView({super.key, required this.album, this.downloadScoped = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final playing = ref.watch(audioControllerProvider).current;
    final shuffleOn =
        ref.watch(audioControllerProvider.select((s) => s.shuffle));
    // Online: the server's track list. Download mode: the downloaded tracks.
    final tracksAsync =
        downloadScoped ? null : ref.watch(albumTracksProvider(album.id));
    final tracks =
        downloadScoped ? _downloadedTracks(ref) : (tracksAsync!.asData?.value ?? const []);
    final controller = ref.read(audioControllerProvider.notifier);

    // Nothing left after a remove: leave the page.
    if (downloadScoped && tracks.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }

    Future<void> shufflePlay() async {
      if (tracks.isEmpty) return;
      await controller.playQueue(tracks, 0, shuffle: true);
    }

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: Colors.transparent,
          title: Text(album.name),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 168,
                      height: 168,
                      child: MediaImage(
                          item: album, placeholderIcon: Icons.album_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(album.name,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      if (album.artistLine != null)
                        Text(album.artistLine!,
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text(_albumMeta(l, tracks, album.productionYear),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      // Icon pills matching the rest of the app: they expand to
                      // the label on hover (desktop) or press (touch). Wrapped so
                      // they never overflow beside the cover art.
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          HoverPillButton(
                            icon: Icons.play_arrow_rounded,
                            label: l.commonPlay,
                            primary: true,
                            // On TV the remote lands on Play as soon as the album
                            // opens (no hunting for focus). onTap stays non-null so
                            // the button is focusable even while the track list is
                            // still loading — a null onTap disables the InkWell and
                            // autofocus would no-op.
                            autofocus: isTvDevice,
                            onTap: () {
                              if (tracks.isNotEmpty) {
                                controller.playQueue(tracks, 0);
                              }
                            },
                          ),
                          HoverPillButton(
                            icon: Icons.shuffle_rounded,
                            label: l.browseShuffle,
                            // Accent wash while shuffle is on, so the button
                            // reads as an active toggle, not a dead press.
                            tinted: shuffleOn,
                            onTap: tracks.isEmpty ? null : shufflePlay,
                          ),
                          if (tracks.isNotEmpty)
                            _albumDownloadButton(context, ref, l, tracks.length),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (downloadScoped)
          _trackList(context, ref, tracks, playing, l, theme)
        else
          tracksAsync!.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: AppSpinner()),
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: SectionError(
                message: '$e',
                onRetry: () => ref.invalidate(albumTracksProvider(album.id)),
              ),
            ),
            data: (t) => _trackList(context, ref, t, playing, l, theme),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  /// The album's downloaded tracks as playable items (local files), sorted by
  /// disc then track. Used in download mode instead of the server track list.
  List<BaseItemDto> _downloadedTracks(WidgetRef ref) {
    final map = ref.watch(downloadsProvider).asData?.value ??
        const <String, DownloadEntry>{};
    final entries = map.values
        .where((e) =>
            e.status == DownloadStatus.complete && e.seriesId == album.id)
        .toList()
      ..sort((a, b) {
        final s = (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0);
        return s != 0
            ? s
            : (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
      });
    return [
      for (final e in entries)
        BaseItemDto(
          id: e.itemId,
          name: e.name,
          type: 'Audio',
          albumId: e.seriesId,
          album: e.seriesName,
          indexNumber: e.episodeNumber,
          parentIndexNumber: e.seasonNumber,
          runTimeTicks: e.runTimeTicks,
        ),
    ];
  }

  /// The shared track list. Tapping a track plays the whole album queue from
  /// there (local files in download mode); the overflow menu adds Play Next /
  /// Add to Queue, plus Remove download when scoped to downloads.
  Widget _trackList(BuildContext context, WidgetRef ref,
      List<BaseItemDto> tracks, BaseItemDto? playing, AppLocalizations l,
      ThemeData theme) {
    return SliverList.builder(
      itemCount: tracks.length,
      itemBuilder: (context, i) {
        final track = tracks[i];
        final isCurrent = playing?.id == track.id;
        void openMenu(Offset at) => _trackMenu(context, ref, l, track, at);
        final tile = TvFocusRing(
          borderRadius: BorderRadius.circular(8),
          child: ListTile(
            dense: true,
            leading: SizedBox(
              width: 28,
              child: Center(
                child: isCurrent
                    ? StreamBuilder<bool>(
                        stream: ref.read(audioPlayerProvider).stream.playing,
                        initialData: ref.read(audioPlayerProvider).state.playing,
                        builder: (_, snap) => EqualizerBars(
                          playing: snap.data ?? false,
                          color: theme.colorScheme.primary,
                          size: 18,
                        ),
                      )
                    : Text('${track.indexNumber ?? i + 1}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
              ),
            ),
            title: Text(track.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: isCurrent
                    ? TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600)
                    : null),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (track.runTimeTicks != null)
                  Text(_fmtDuration(track.runTimeTicks!),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                Builder(builder: (btnContext) {
                  return IconButton(
                    tooltip: l.commonMore,
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    onPressed: () {
                      final box = btnContext.findRenderObject() as RenderBox?;
                      openMenu(box == null
                          ? Offset.zero
                          : box.localToGlobal(box.size.center(Offset.zero)));
                    },
                  );
                }),
              ],
            ),
            onTap: () => ref
                .read(audioControllerProvider.notifier)
                .playQueue(tracks, i),
          ),
        );
        if (isTvDevice) return tile;
        return GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onLongPressStart: (d) => openMenu(d.globalPosition),
          onSecondaryTapUp: (d) => openMenu(d.globalPosition),
          child: tile,
        );
      },
    );
  }

  void _trackMenu(BuildContext context, WidgetRef ref, AppLocalizations l,
      BaseItemDto track, Offset at) {
    final c = ref.read(audioControllerProvider.notifier);
    showContextMenu(context, at: at, title: track.name, actions: [
      ContextMenuAction(
        icon: Icons.playlist_play_rounded,
        label: l.browsePlayNext,
        onTap: () => c.playNext(track),
      ),
      ContextMenuAction(
        icon: Icons.queue_music_rounded,
        label: l.browseAddToQueue,
        onTap: () => c.addToQueue(track),
      ),
      if (downloadScoped)
        ContextMenuAction(
          icon: Icons.delete_outline_rounded,
          label: l.detailRemoveDownload,
          color: Theme.of(context).colorScheme.error,
          onTap: () => ref.read(downloadsProvider.notifier).delete(track.id),
        ),
    ]);
  }

  /// Download / progress / remove pill for the whole album, reflecting how many
  /// of its [trackCount] tracks are already downloaded.
  Widget _albumDownloadButton(
      BuildContext context, WidgetRef ref, AppLocalizations l, int trackCount) {
    final map =
        ref.watch(downloadsProvider).asData?.value ?? const <String, DownloadEntry>{};
    final entries = map.values.where((e) => e.seriesId == album.id).toList();
    final done =
        entries.where((e) => e.status == DownloadStatus.complete).length;
    final active =
        entries.where((e) => e.status == DownloadStatus.downloading).toList();

    if (active.isNotEmpty) {
      final progress =
          (done + active.fold<double>(0, (a, e) => a + e.progress)) / trackCount;
      return HoverPillButton(
        icon: Icons.download_rounded,
        label: l.detailDownloading,
        onTap: null,
        iconWidget: AppSpinner.inline(value: progress > 0 ? progress : null),
      );
    }
    if (done >= trackCount && trackCount > 0) {
      return HoverPillButton(
        icon: Icons.download_done_rounded,
        label: l.detailDownloaded,
        onTap: () async {
          final ok = await confirm(context,
              title: l.detailRemoveDownload,
              message: l.detailRemoveOfflineCopy(album.name),
              confirmLabel: l.commonRemove,
              destructive: true);
          if (ok) {
            await ref.read(downloadsProvider.notifier).deleteSeries(album.id);
          }
        },
      );
    }
    return HoverPillButton(
      icon: Icons.download_rounded,
      label: l.detailDownload,
      onTap: () => ref.read(downloadsProvider.notifier).download(album),
    );
  }
}

String _albumMeta(AppLocalizations l, List<BaseItemDto> tracks, int? year) {
  final count = tracks.length;
  final totalMin = tracks.fold<int>(0, (s, t) => s + (t.runTimeTicks ?? 0)) ~/
      600000000; // ticks (100ns) per minute
  return [
    if (year != null) '$year',
    l.browseSongsCount(count),
    if (totalMin > 0) l.browseMinutesShort(totalMin),
  ].join('  ·  ');
}

String _fmtDuration(int ticks) {
  final total = ticks ~/ 10000000;
  final m = total ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
