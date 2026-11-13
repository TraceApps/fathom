import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/arr_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_actions.dart';
import '../widgets/arr_tags.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';

/// Radarr's collections (film series): which of their movies you have,
/// monitoring one so Radarr adds the rest, and the settings it adds them
/// with. Radarr's Collections page.
class ArrCollectionsScreen extends ConsumerStatefulWidget {
  const ArrCollectionsScreen({super.key});

  @override
  ConsumerState<ArrCollectionsScreen> createState() =>
      _ArrCollectionsScreenState();
}

class _ArrCollectionsScreenState extends ConsumerState<ArrCollectionsScreen> {
  bool _missingOnly = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final client = ref.watch(radarrClientProvider);
    final async = ref.watch(radarrCollectionsProvider);
    final all = async.asData?.value ?? async.unwrapPrevious().asData?.value;
    final shown = [
      for (final c in all ?? const <ArrCollection>[])
        if (!_missingOnly || c.missing > 0) c,
    ];
    Widget body;
    if (all == null) {
      body = async.hasError
          ? ErrorView(
              message: async.error.toString(),
              onRetry: () => ref.invalidate(radarrCollectionsProvider),
            )
          : const Center(child: AppSpinner());
    } else if (shown.isEmpty) {
      body = EmptyState(
        icon: Icons.collections_bookmark_rounded,
        title: all.isEmpty ? l.arrCollectionsEmpty : l.arrNoMatches,
        message: all.isEmpty ? l.arrCollectionsEmptyHint : null,
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => ref.refresh(radarrCollectionsProvider.future),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: shown.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) =>
              _CollectionCard(client: client, collection: shown[i]),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l.arrCollections),
        actions: [
          PopupMenuButton<bool>(
            tooltip: l.arrFilter,
            icon: Icon(
              _missingOnly
                  ? Icons.filter_alt_rounded
                  : Icons.filter_list_rounded,
            ),
            initialValue: _missingOnly,
            onSelected: (v) => setState(() => _missingOnly = v),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: false,
                checked: !_missingOnly,
                child: Text(l.browseAll),
              ),
              CheckedPopupMenuItem(
                value: true,
                checked: _missingOnly,
                child: Text(l.arrCollectionMissingOnly),
              ),
            ],
          ),
          if (client != null)
            IconButton(
              tooltip: l.arrRefreshCollections,
              icon: const Icon(Icons.sync_rounded),
              onPressed: () async {
                if (await arrRun(
                  context,
                  client.refreshCollections,
                  done: l.arrRefreshingCollections,
                )) {
                  if (context.mounted) _reloadSoon(context);
                }
              },
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: body,
    );
  }
}

/// Radarr refreshes collections (and adds movies) as a task: look again
/// after it's had a moment, then once more for slower servers. Through the
/// app's container, which outlives this page (leaving it meanwhile is fine).
void _reloadSoon(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  for (final s in const [4, 12]) {
    Future<void>.delayed(Duration(seconds: s), () {
      container.invalidate(radarrCollectionsProvider);
      container.invalidate(radarrMoviesProvider);
    });
  }
}

class _CollectionCard extends ConsumerWidget {
  final RadarrClient? client;
  final ArrCollection collection;
  const _CollectionCard({required this.client, required this.collection});

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final c = client;
    if (c == null) return;
    final col = collection;
    if (!col.monitored) {
      // Turning it on adds movies: say how many and with what settings first.
      if (await showArrCollectionDialog(
        context,
        client: c,
        collection: col,
        monitor: true,
      )) {
        if (context.mounted) _reloadSoon(context);
      }
      return;
    }
    if (await arrRun(context, () async {
      final raw = await c.collectionRaw(col.id);
      raw['monitored'] = false;
      await c.updateCollection(raw);
    }, done: l.arrCollectionUnmonitored)) {
      ref.invalidate(radarrCollectionsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final col = collection;
    final library =
        ref.watch(radarrMoviesProvider).asData?.value ?? const <ArrMovie>[];
    final byTmdb = {for (final m in library) m.tmdbId: m.id};
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        col.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            l.arrInLibraryCount(
                              col.inLibrary,
                              col.movies.length,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (col.missing > 0)
                            ArrChip(
                              label: l.arrMissingCount(col.missing),
                              color: col.monitored
                                  ? arrMissingColor
                                  : theme.colorScheme.outline,
                            ),
                          if (!col.monitored)
                            ArrChip(
                              label: l.arrUnmonitored,
                              color: theme.colorScheme.outline,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (client != null) ...[
                  IconButton(
                    tooltip: col.monitored ? l.arrUnmonitor : l.arrMonitor,
                    icon: Icon(
                      col.monitored
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: col.monitored ? theme.colorScheme.primary : null,
                    ),
                    onPressed: () => _toggle(context, ref),
                  ),
                  IconButton(
                    tooltip: l.arrEdit,
                    icon: const Icon(Icons.edit_rounded),
                    onPressed: () async {
                      if (await showArrCollectionDialog(
                        context,
                        client: client!,
                        collection: col,
                        monitor: false,
                      )) {
                        ref.invalidate(radarrCollectionsProvider);
                      }
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // A 92-wide poster (138 tall) with its title and year below,
            // which grow with the text size.
            SizedBox(
              height:
                  150 +
                  MediaQuery.textScalerOf(context).scale(
                    (theme.textTheme.bodySmall?.fontSize ?? 12) * 1.4 +
                        (theme.textTheme.labelSmall?.fontSize ?? 11) * 1.4,
                  ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: col.movies.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final m = col.movies[i];
                  final id = byTmdb[m.tmdbId];
                  return _MoviePoster(
                    client: client,
                    movie: m,
                    // In Radarr: open it (looked up if the library list
                    // isn't loaded yet). Missing: add it (the add form opens
                    // on its own for an exact tmdb: match).
                    onTap: id != null
                        ? () => context.push('/arr/movie/$id')
                        : m.inLibrary
                        ? () async {
                            final found = await client?.movieByTmdb(m.tmdbId);
                            if (found != null && context.mounted) {
                              context.push('/arr/movie/${found.id}');
                            }
                          }
                        : m.excluded
                        ? null
                        : () => context.push(
                            Uri(
                              path: '/arr/add/movie',
                              queryParameters: {'term': 'tmdb:${m.tmdbId}'},
                            ).toString(),
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

class _MoviePoster extends StatelessWidget {
  final ArrClient? client;
  final ArrCollectionMovie movie;
  final VoidCallback? onTap;
  const _MoviePoster({
    required this.client,
    required this.movie,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final have = movie.inLibrary;
    return SizedBox(
      width: 92,
      child: Semantics(
        button: onTap != null,
        onTap: onTap,
        label: [
          movie.title,
          if (movie.year != null) '${movie.year}',
          have ? l.arrInLibrary : (movie.excluded ? l.arrExcluded : l.arrAddTo('Radarr')),
        ].join(', '),
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Opacity(
                        // Missing ones are dimmed, the way Radarr greys them.
                        opacity: have ? 1 : 0.45,
                        child: ArrArt(
                          client: client,
                          images: movie.images,
                          width: 185,
                          placeholderIcon: Icons.movie_rounded,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Icon(
                        have
                            ? Icons.check_circle_rounded
                            : movie.excluded
                            ? Icons.block_rounded
                            : Icons.add_circle_rounded,
                        size: 22,
                        color: have
                            ? arrDownloadedColor
                            : movie.excluded
                            ? theme.colorScheme.outline
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                movie.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                movie.excluded
                    ? l.arrExcluded
                    : movie.year?.toString() ?? '',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A collection's settings: what Radarr adds its movies with. With
/// [monitor], it's the step that turns monitoring on: it says how many movies
/// that adds, saves, and has Radarr add them now. True when saved.
Future<bool> showArrCollectionDialog(
  BuildContext context, {
  required RadarrClient client,
  required ArrCollection collection,
  required bool monitor,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _CollectionDialog(
      client: client,
      collection: collection,
      monitor: monitor,
    ),
  );
  return ok ?? false;
}

class _CollectionDialog extends ConsumerStatefulWidget {
  final RadarrClient client;
  final ArrCollection collection;
  final bool monitor;
  const _CollectionDialog({
    required this.client,
    required this.collection,
    required this.monitor,
  });

  @override
  ConsumerState<_CollectionDialog> createState() => _CollectionDialogState();
}

class _CollectionDialogState extends ConsumerState<_CollectionDialog> {
  late int? _profile = widget.collection.qualityProfileId;
  late String? _root = widget.collection.rootFolderPath;
  late String _availability =
      widget.collection.minimumAvailability ?? 'released';
  late bool _search = widget.collection.searchOnAdd;
  late List<int> _tags = [...widget.collection.tags];
  bool _busy = false;

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final c = widget.client;
    final col = widget.collection;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    var addingNow = false;
    var ok = false;
    try {
      final raw = await c.collectionRaw(col.id);
      raw
        ..['qualityProfileId'] = _profile
        ..['rootFolderPath'] = _root
        ..['minimumAvailability'] = _availability
        ..['searchOnAdd'] = _search
        ..['tags'] = _tags;
      if (widget.monitor) raw['monitored'] = true;
      await c.updateCollection(raw);
      ok = true;
      if (widget.monitor) {
        // Radarr would add the movies at its next scheduled refresh; now.
        // Saved either way: a refresh that can't start isn't a failed save.
        try {
          await c.refreshCollections([col.id]);
          addingNow = true;
        } catch (_) {}
      }
    } catch (e) {
      showSnackOn(messenger, e.toString(), kind: SnackKind.error);
    }
    if (ok) {
      showSnackOn(
        messenger,
        !widget.monitor
            ? l.arrSaved
            : !addingNow
            ? l.arrCollectionMonitoredLater(col.title)
            : col.addableNow > 0
            ? l.arrCollectionMonitored(col.title)
            : l.arrCollectionMonitoredOnly(col.title),
        kind: SnackKind.success,
      );
    }
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final col = widget.collection;
    final profiles =
        ref.watch(arrQualityProfileListProvider(ArrKind.radarr)).asData?.value ??
        const <ArrQualityProfile>[];
    final roots =
        ref.watch(arrRootFoldersProvider(ArrKind.radarr)).asData?.value ??
        const <ArrRootFolder>[];
    // A collection Radarr made on its own may have no profile or folder yet
    // (0 or empty), or one deleted since: start on the first real one so
    // Save never sends a bad value.
    if (profiles.isNotEmpty && !profiles.any((p) => p.id == _profile)) {
      _profile = profiles.first.id;
    }
    if (roots.isNotEmpty && !roots.any((r) => r.path == _root)) {
      _root = roots.first.path;
    }
    final profileOk = profiles.any((p) => p.id == _profile);
    final rootOk = roots.any((r) => r.path == _root);
    final ready = !_busy && profileOk && rootOk;
    return ArrDialogFrame(
      client: widget.client,
      images: col.images,
      heading: widget.monitor ? l.arrMonitorCollection : l.arrEdit,
      title: col.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.monitor) ...[
            if (col.addableNow > 0) ...[
              Text(l.arrCollectionAddsNow(col.addableNow)),
              const SizedBox(height: 6),
            ],
            Text(l.arrCollectionAddsLater),
            const SizedBox(height: 16),
          ],
          ArrDropdownField<int>(
            label: l.arrQualityProfile,
            value: _profile,
            options: {for (final p in profiles) p.id: p.name},
            onChanged: _busy ? null : (v) => setState(() => _profile = v),
          ),
          ArrDropdownField<String>(
            label: l.arrRootFolder,
            value: _root,
            options: {
              for (final r in roots)
                r.path: r.freeSpace == null
                    ? r.path
                    : '${r.path}  ·  ${l.arrFree(arrSize(r.freeSpace!))}',
            },
            onChanged: _busy ? null : (v) => setState(() => _root = v),
          ),
          ArrDropdownField<String>(
            label: l.arrMinimumAvailability,
            value: _availability,
            options: {
              ...arrAvailabilities(l),
              if (!arrAvailabilities(l).containsKey(_availability))
                _availability: _availability,
            },
            onChanged: _busy
                ? null
                : (v) => setState(() => _availability = v ?? _availability),
          ),
          ArrTagPicker(
            client: widget.client,
            selected: _tags,
            onChanged: _busy ? null : (ids) => setState(() => _tags = ids),
          ),
          ArrCheck(
            label: l.arrSearchOnAdd,
            value: _search,
            onChanged: _busy ? null : (v) => setState(() => _search = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: ready ? _save : null,
          child: _busy
              ? const AppSpinner.inline()
              : Text(widget.monitor ? l.arrMonitorCollection : l.commonSave),
        ),
      ],
    );
  }
}
