import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/base_item.dart';
import '../state/audio_player.dart';
import '../state/downloads.dart';
import '../widgets/context_menu.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/glass.dart';
import '../widgets/media_cards.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/app_shell.dart';
import 'album_screen.dart';
import 'detail_screen.dart';
import '../widgets/app_spinner.dart';
import '../widgets/ui_common.dart';

/// Offline downloads. A segmented control switches between the downloaded
/// library (posters, Movies + TV Shows) and the in-progress queue; the queue
/// tab only appears while something is downloading or has failed.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  int _seg = 0; // 0 = Downloaded (library), 1 = Downloading (queue)

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final downloads = ref.watch(downloadsProvider);
    final controller = ref.read(downloadsProvider.notifier);
    final all =
        downloads.asData?.value.values.toList() ?? const <DownloadEntry>[];
    final active =
        all.where((e) => e.status != DownloadStatus.complete).toList();
    final complete =
        all.where((e) => e.status == DownloadStatus.complete).toList();
    final showQueue = active.isNotEmpty;
    // No queue tab when nothing's in flight, so pin the view to the library.
    final seg = showQueue ? _seg : 0;
    final hasActiveTransfer =
        active.any((e) => e.status == DownloadStatus.downloading);

    return Scaffold(
      appBar: AppBar(
        leading: mobileLeading(context),
        title: Text(l.ytDownloads),
        actions: [
          if (seg == 1 && hasActiveTransfer)
            TextButton.icon(
              onPressed: () => _confirmCancelAll(context, controller),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: Text(l.downloadsCancelAll),
            ),
        ],
      ),
      body: downloads.when(
        loading: () => const Center(child: AppSpinner()),
        error: (e, _) => ErrorView(
          message: '$e',
          onRetry: () => ref.invalidate(downloadsProvider),
        ),
        data: (map) {
          if (map.isEmpty) {
            return EmptyState(
              icon: Icons.download_rounded,
              title: l.ytNoDownloadsTitle,
              message: l.ytDownloadsScreenEmptyMessage,
            );
          }
          return Column(
            children: [
              if (showQueue)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 0,
                        icon: const Icon(Icons.download_done_rounded, size: 18),
                        label: Text(l.detailDownloaded),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: const Icon(Icons.downloading_rounded, size: 18),
                        label:
                            Text('${l.detailDownloading} (${active.length})'),
                      ),
                    ],
                    selected: {seg},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _seg = s.first),
                  ),
                ),
              Expanded(
                child: seg == 1
                    ? _DownloadQueue(items: active)
                    : _DownloadedLibrary(items: complete),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmCancelAll(
      BuildContext context, DownloadsController controller) async {
    final l = AppLocalizations.of(context);
    final ok = await confirm(context,
        title: l.downloadsCancelAll,
        message: l.downloadsCancelAllConfirm,
        confirmLabel: l.downloadsCancelAll,
        destructive: true);
    if (ok) await controller.cancelActive();
  }
}

/// The in-progress/failed queue: a series' episodes grouped under one header,
/// movies and other single items on their own.
class _DownloadQueue extends StatelessWidget {
  final List<DownloadEntry> items;
  const _DownloadQueue({required this.items});

  @override
  Widget build(BuildContext context) {
    final series = <String, List<DownloadEntry>>{};
    final singles = <DownloadEntry>[];
    for (final e in items) {
      if (e.seriesId != null) {
        series.putIfAbsent(e.seriesId!, () => []).add(e);
      } else {
        singles.add(e);
      }
    }
    final rows = <Widget>[
      for (final g in series.entries)
        _SeriesGroupTile(seriesId: g.key, episodes: g.value),
      for (final e in singles) _DownloadTile(entry: e),
    ];
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => rows[i],
    );
  }
}

/// The downloaded-media library, split into Movies / TV Shows / Recordings /
/// Music sections (each a wrap of posters), mirroring the main library. A single
/// item plays or opens its detail on tap; a show opens its episodes.
class _DownloadedLibrary extends ConsumerWidget {
  final List<DownloadEntry> items;
  const _DownloadedLibrary({required this.items});

  static bool _isMusic(String? t) =>
      t == 'Audio' || t == 'MusicAlbum' || t == 'MusicVideo';
  static bool _isRecording(String? t) => t == 'Recording';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // Split by TYPE first (music, then recordings) so a recording that carries a
    // seriesId — a recorded episode — lands in Recordings, not TV Shows. Only
    // what's left splits into TV Shows (episodes grouped by series) and Movies.
    final music = items.where((e) => _isMusic(e.type)).toList();
    final recordings = items
        .where((e) => !_isMusic(e.type) && _isRecording(e.type))
        .toList();
    final rest = items
        .where((e) => !_isMusic(e.type) && !_isRecording(e.type))
        .toList();
    final movies = rest.where((e) => e.seriesId == null).toList();
    final shows = <String, List<DownloadEntry>>{};
    for (final e in rest.where((e) => e.seriesId != null)) {
      shows.putIfAbsent(e.seriesId!, () => []).add(e);
    }
    // A recorded series' episodes group under it; standalone recordings are flat.
    final recShows = <String, List<DownloadEntry>>{};
    final recSingles = <DownloadEntry>[];
    for (final e in recordings) {
      if (e.seriesId != null) {
        recShows.putIfAbsent(e.seriesId!, () => []).add(e);
      } else {
        recSingles.add(e);
      }
    }
    final albums = <String, List<DownloadEntry>>{};
    final musicSingles = <DownloadEntry>[];
    for (final e in music) {
      if (e.seriesId != null) {
        albums.putIfAbsent(e.seriesId!, () => []).add(e);
      } else {
        musicSingles.add(e);
      }
    }

    final sections = <Widget>[];
    void addSection(String title, List<Widget> cards) {
      if (cards.isEmpty) return;
      if (sections.isNotEmpty) sections.add(const SizedBox(height: 20));
      sections.add(_SectionHeader(title));
      sections.add(_PosterGrid(children: cards));
    }

    // Sections in alphabetical order: Movies, Music, Recordings, TV Shows.
    addSection(l.detailMovies,
        [for (final e in movies) _singleCard(context, ref, e)]);
    addSection(l.browseMusic, [
      for (final g in albums.entries) _groupCard(context, ref, g, l, 'MusicAlbum'),
      for (final e in musicSingles) _musicSingleCard(context, ref, e),
    ]);
    addSection(l.extraTabRecordings, [
      for (final g in recShows.entries) _groupCard(context, ref, g, l, 'Series'),
      for (final e in recSingles) _singleCard(context, ref, e),
    ]);
    addSection(l.downloadsTvShows, [
      for (final g in shows.entries) _groupCard(context, ref, g, l, 'Series'),
    ]);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: sections,
    );
  }

  /// A lone downloaded track (no album): plays in the music player on tap.
  Widget _musicSingleCard(
          BuildContext context, WidgetRef ref, DownloadEntry e) =>
      PosterCard(
        item: BaseItemDto(
          id: e.itemId,
          name: e.name,
          type: 'Audio',
          userData: UserItemData(played: e.played ?? false),
        ),
        localPosterPath: e.posterPath,
        contextActions: false,
        onMenu: (at) => _musicSingleMenu(context, ref, e, at),
        onTap: () => ref.read(audioControllerProvider.notifier).playQueue([
          BaseItemDto(
            id: e.itemId,
            name: e.name,
            type: 'Audio',
            runTimeTicks: e.runTimeTicks,
          ),
        ], 0),
      );

  void _musicSingleMenu(
      BuildContext context, WidgetRef ref, DownloadEntry e, Offset at) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    showContextMenu(context, at: at, title: e.name, actions: [
      ContextMenuAction(
        icon: Icons.play_arrow_rounded,
        label: l.commonPlay,
        onTap: () => ref.read(audioControllerProvider.notifier).playQueue([
          BaseItemDto(
              id: e.itemId,
              name: e.name,
              type: 'Audio',
              runTimeTicks: e.runTimeTicks),
        ], 0),
      ),
      ContextMenuAction(
        icon: Icons.delete_outline_rounded,
        label: l.detailRemoveDownload,
        color: cs.error,
        onTap: () => ref.read(downloadsProvider.notifier).delete(e.itemId),
      ),
    ]);
  }

  /// A poster for one standalone download (movie, recording, or music item).
  Widget _singleCard(BuildContext context, WidgetRef ref, DownloadEntry e) =>
      PosterCard(
        item: BaseItemDto(
          id: e.itemId,
          name: e.name,
          type: e.type ?? 'Movie',
          productionYear: e.year,
          communityRating: e.communityRating,
          criticRating: e.criticRating,
          userData: UserItemData(played: e.played ?? false),
        ),
        localPosterPath: e.posterPath,
        contextActions: false,
        onMenu: (at) => _movieMenu(context, ref, e, at),
        onTap: () => context.push('/downloads/detail', extra: e.itemId),
      );

  /// A poster for one downloaded group: a series (episodes grouped under it) or
  /// a music album (its tracks grouped under it).
  Widget _groupCard(BuildContext context, WidgetRef ref,
      MapEntry<String, List<DownloadEntry>> g, AppLocalizations l, String type) {
    final first = g.value.first;
    final name = first.seriesName ?? (type == 'Series' ? l.detailSeries : first.name);
    return PosterCard(
      item: BaseItemDto(
        id: g.key,
        name: name,
        type: type,
        productionYear: first.year,
        communityRating: first.communityRating,
        criticRating: first.criticRating,
        userData: UserItemData(
          unplayedItemCount: first.unplayedItemCount ?? 0,
          played: first.played ?? false,
        ),
      ),
      localPosterPath: first.posterPath,
      contextActions: false,
      onMenu: (at) => _showMenu(context, ref, g.key, name, at),
      onTap: () => context.push('/downloads/detail', extra: g.key),
    );
  }

  void _movieMenu(
      BuildContext context, WidgetRef ref, DownloadEntry e, Offset at) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    showContextMenu(context, at: at, title: e.name, actions: [
      ContextMenuAction(
        icon: Icons.info_outline_rounded,
        label: l.actionShowDetails,
        onTap: () => context.push('/downloads/detail', extra: e.itemId),
      ),
      ContextMenuAction(
        icon: Icons.play_arrow_rounded,
        label: l.commonPlay,
        onTap: () =>
            context.push('/player', extra: BaseItemDto(id: e.itemId, name: e.name)),
      ),
      ContextMenuAction(
        icon: Icons.delete_outline_rounded,
        label: l.detailRemoveDownload,
        color: cs.error,
        onTap: () => ref.read(downloadsProvider.notifier).delete(e.itemId),
      ),
    ]);
  }

  void _showMenu(BuildContext context, WidgetRef ref, String seriesId,
      String name, Offset at) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    showContextMenu(context, at: at, title: name, actions: [
      ContextMenuAction(
        icon: Icons.info_outline_rounded,
        label: l.actionShowDetails,
        onTap: () => context.push('/downloads/detail', extra: seriesId),
      ),
      ContextMenuAction(
        icon: Icons.delete_outline_rounded,
        label: l.detailRemoveDownload,
        color: cs.error,
        onTap: () async {
          final ok = await confirm(context,
              title: l.detailRemoveDownload,
              message: l.detailRemoveOfflineCopy(name),
              confirmLabel: l.commonRemove,
              destructive: true);
          if (ok) {
            await ref.read(downloadsProvider.notifier).deleteSeries(seriesId);
          }
        },
      ),
    ]);
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

/// the downloaded library looks identical to browsing.
class _PosterGrid extends StatelessWidget {
  final List<Widget> children;
  const _PosterGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 18,
      children: [
        for (final c in children) SizedBox(height: 308, child: c),
      ],
    );
  }
}

/// A downloaded item's cached full metadata (overview, cast, ratings, backdrop),
/// loaded from the file stashed at download time so the detail page works
/// offline. Null when it wasn't cached (older downloads).
final downloadDetailProvider =
    FutureProvider.family.autoDispose<BaseItemDto?, String>((ref, key) async {
  return ref.read(downloadsProvider.notifier).loadDetail(key);
});

/// The download detail page. It reuses the library detail layout verbatim
/// via [DetailScreen] in download-scoped mode, so it looks identical to a
/// show/movie page but is walled to the download folder: only downloaded
/// episodes appear and every action is local (never touches the server copy).
class DownloadDetailScreen extends ConsumerWidget {
  final String itemKey; // a movie's id, or a series' id
  const DownloadDetailScreen({super.key, required this.itemKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final map = ref.watch(downloadsProvider).asData?.value ??
        const <String, DownloadEntry>{};
    final entries = map.values
        .where((e) =>
            e.status == DownloadStatus.complete &&
            (e.itemId == itemKey || e.seriesId == itemKey))
        .toList();
    if (entries.isEmpty) {
      // Everything for this item was removed while the page was open.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    final first = entries.first;
    final isMusic = _DownloadedLibrary._isMusic(first.type);
    final isSeries = !isMusic && first.seriesId != null;
    // Prefer the full metadata cached at download time; fall back to a minimal
    // item so the page still renders for older downloads.
    final detail = ref.watch(downloadDetailProvider(itemKey)).asData?.value;
    final item = detail ??
        BaseItemDto(
          id: itemKey,
          name: isMusic
              ? (first.seriesName ?? first.name)
              : isSeries
                  ? (first.seriesName ?? l.detailSeries)
                  : first.name,
          type: isMusic
              ? 'MusicAlbum'
              : isSeries
                  ? 'Series'
                  : (first.type ?? 'Movie'),
          productionYear: first.year,
          communityRating: first.communityRating,
          criticRating: first.criticRating,
        );
    // Music uses the album (music-player) layout; everything else the
    // show/movie detail layout — both scoped to downloads, with the same
    // blurred-cover backdrop as the server view.
    if (isMusic) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: BackdropBackground(
          item: item,
          child: AlbumView(album: item, downloadScoped: true),
        ),
      );
    }
    return DetailScreen(item: item, downloadScoped: true);
  }
}

/// One download row: status glyph, name, progress/status, and a Cancel (while
/// downloading) / Remove (once done) button. A complete item plays on tap.
class _DownloadTile extends ConsumerWidget {
  final DownloadEntry entry;
  final bool indented;
  const _DownloadTile({required this.entry, this.indented = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final controller = ref.read(downloadsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final downloading = entry.status == DownloadStatus.downloading;
    final complete = entry.status == DownloadStatus.complete;
    final statusColor =
        entry.status == DownloadStatus.failed ? scheme.error : scheme.primary;
    return ListTile(
      contentPadding: EdgeInsets.only(left: indented ? 32 : 20, right: 12),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          switch (entry.status) {
            DownloadStatus.complete => Icons.download_done_rounded,
            DownloadStatus.downloading => Icons.downloading_rounded,
            DownloadStatus.failed => Icons.error_outline_rounded,
          },
          color: statusColor,
          size: 22,
        ),
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: switch (entry.status) {
        DownloadStatus.downloading => LinearProgressIndicator(
            value: entry.progress > 0 ? entry.progress : null),
        DownloadStatus.failed => Text(l.ytFailed),
        DownloadStatus.complete => Text(l.ytAvailableOffline),
      },
      trailing: IconButton(
        tooltip: downloading ? l.downloadCancel : l.commonRemove,
        icon: Icon(
            downloading ? Icons.close_rounded : Icons.delete_outline_rounded),
        onPressed: () => _removeAsking(
          context,
          running: downloading,
          name: entry.name,
          remove: () => controller.delete(entry.itemId),
        ),
      ),
      onTap: complete
          ? () => context.push('/player',
              extra: BaseItemDto(id: entry.itemId, name: entry.name))
          : null,
    );
  }
}

/// A series' episodes collapsed under one header: aggregate progress, a single
/// Cancel/Remove for the whole set, and the episodes revealed on expand.
class _SeriesGroupTile extends ConsumerWidget {
  final String seriesId;
  final List<DownloadEntry> episodes;
  const _SeriesGroupTile({required this.seriesId, required this.episodes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final controller = ref.read(downloadsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final total = episodes.length;
    final done =
        episodes.where((e) => e.status == DownloadStatus.complete).length;
    final active =
        episodes.where((e) => e.status == DownloadStatus.downloading).toList();
    final name = episodes.first.seriesName ?? l.detailSeries;
    final double? progress = active.isEmpty
        ? null
        : (done + active.fold<double>(0, (a, e) => a + e.progress)) / total;
    return ExpansionTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          active.isNotEmpty
              ? Icons.downloading_rounded
              : (done == total
                  ? Icons.download_done_rounded
                  : Icons.download_rounded),
          color: scheme.primary,
          size: 22,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: active.isNotEmpty ? l.downloadCancel : l.commonRemove,
            icon: Icon(active.isNotEmpty
                ? Icons.close_rounded
                : Icons.delete_outline_rounded),
            onPressed: () => _removeAsking(
              context,
              running: active.isNotEmpty,
              name: name,
              remove: () => controller.deleteSeries(seriesId),
            ),
          ),
        ],
      ),
      subtitle: active.isNotEmpty
          ? LinearProgressIndicator(value: progress)
          : Text('$done/$total'),
      tilePadding: const EdgeInsets.only(left: 20, right: 4),
      children: _seasonRows(context, l, controller),
    );
  }

  /// The expanded body: episodes grouped by season, each under a small season
  /// header ("Season 1"), so it's clear which season(s) are downloading. A
  /// single unnamed/unknown season is listed without a header. When a download
  /// spans more than one season, each header also carries a cancel/remove for
  /// just that season.
  List<Widget> _seasonRows(
    BuildContext context,
    AppLocalizations l,
    DownloadsController controller,
  ) {
    final bySeason = <int, List<DownloadEntry>>{};
    for (final e in episodes) {
      bySeason.putIfAbsent(e.seasonNumber ?? -1, () => []).add(e);
    }
    final seasons = bySeason.keys.toList()..sort();
    final realSeasons = seasons.where((s) => s >= 0).length;
    final showHeaders =
        realSeasons > 1 || (realSeasons == 1 && seasons.any((s) => s > 0));
    final perSeasonCancel = realSeasons > 1;
    final rows = <Widget>[];
    for (final s in seasons) {
      final eps = bySeason[s]!
        ..sort(
            (a, b) => (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0));
      if (showHeaders && s >= 0) {
        final active = eps.any((e) => e.status == DownloadStatus.downloading);
        rows.add(_SeasonSubheader(
          label: s == 0 ? l.detailSpecials : l.detailSeasonNumber(s),
          active: active,
          onCancel: perSeasonCancel
              ? () => _removeAsking(
                  context,
                  running: active,
                  name: s == 0 ? l.detailSpecials : l.detailSeasonNumber(s),
                  remove: () => controller.deleteSeason(seriesId, s),
                )
              : null,
        ));
      }
      rows.addAll(eps.map((e) => _DownloadTile(entry: e, indented: true)));
    }
    return rows;
  }
}

/// A small season label between a series' episode groups on the Downloads
/// screen, with an optional per-season cancel/remove.
class _SeasonSubheader extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onCancel;
  const _SeasonSubheader(
      {required this.label, this.active = false, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(32, 10, onCancel != null ? 4 : 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: scheme.primary,
              ),
            ),
          ),
          if (onCancel != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: active ? l.downloadCancel : l.commonRemove,
              icon: Icon(
                  active ? Icons.close_rounded : Icons.delete_outline_rounded,
                  size: 18),
              onPressed: onCancel,
            ),
        ],
      ),
    );
  }
}

/// A download's own remove button. One still coming down is canceled at once
/// (it can be started again); one that's complete is asked about first, as
/// the same row's menu does: the button used to delete an episode, a season
/// or a whole show's offline copies on one press.
Future<void> _removeAsking(
  BuildContext context, {
  required bool running,
  required String name,
  required Future<void> Function() remove,
}) async {
  if (!running) {
    final l = AppLocalizations.of(context);
    final ok = await confirm(
      context,
      title: l.detailRemoveDownload,
      message: l.detailRemoveOfflineCopy(name),
      confirmLabel: l.commonRemove,
      destructive: true,
    );
    if (!ok) return;
  }
  await remove();
}
