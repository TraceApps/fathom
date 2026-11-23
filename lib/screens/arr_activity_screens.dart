import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../services/tv_mode.dart';
import '../state/arr_providers.dart';
import '../state/seerr_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_actions.dart';
import '../widgets/arr_bulk.dart';
import '../widgets/arr_pane.dart';
import '../widgets/arr_skeletons.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/context_menu.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/tv_focus.dart';
import '../widgets/ui_common.dart';
import 'arr_import_screen.dart';
import 'discover_screen.dart' show SeerrRequestTile;
import 'arr_releases_screen.dart';

// ------------------------------------------------------------------ Wanted

/// Monitored episodes and movies that are missing, or below their quality
/// cutoff, from both apps, newest first.
class ArrWantedTab extends ConsumerStatefulWidget {
  const ArrWantedTab({super.key});

  @override
  ConsumerState<ArrWantedTab> createState() => _ArrWantedTabState();
}

class _ArrWantedTabState extends ConsumerState<ArrWantedTab> {
  ArrWantedList _list = ArrWantedList.missing;
  int _limit = arrPageSize;

  /// Monitored titles (the apps' default), or the unmonitored ones.
  bool _monitored = true;

  // The list last shown, kept while Load More fetches a longer one (a new
  // key has no previous value of its own).
  ArrMerged<ArrWantedItem>? _last;
  (ArrWantedList, bool)? _lastFor;

  // Picking several, by app and episode, movie or album id. Null: not
  // picking.
  Set<String>? _picked;
  bool _busy = false;

  static String _key(ArrWantedItem w) => '${w.kind.name}:${w.itemId}';

  (ArrWantedList, int, bool) get _arg => (_list, _limit, _monitored);

  /// Runs [each] once per app with that app's picked ids (episodes for
  /// Sonarr, movies for Radarr, albums for Lidarr).
  Future<void> _forPicked(
    List<ArrWantedItem> all,
    Future<void> Function(ArrClient c, List<int> ids) each,
    String Function(int sent) done, {
    bool changes = false,
  }) async {
    final picked = _picked ?? const {};
    final byApp = <ArrKind, List<int>>{};
    for (final w in all) {
      final id = w.itemId;
      if (id != null && picked.contains(_key(w))) {
        (byApp[w.kind] ??= []).add(id);
      }
    }
    final sent = byApp.values.fold<int>(0, (t, ids) => t + ids.length);
    setState(() => _busy = true);
    final ok = await arrRun(context, () async {
      for (final e in byApp.entries) {
        final c = arrClient(ref, e.key);
        if (c != null) await each(c, e.value);
      }
    }, done: done(sent));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok && changes) _picked = null;
    });
    if (ok && changes) ref.invalidate(arrWantedProvider);
  }

  void _search(List<ArrWantedItem> all) => _forPicked(
    all,
    (c, ids) => switch (c) {
      SonarrClient() => c.searchEpisodes(ids),
      LidarrClient() => c.searchAlbums(ids),
      _ => c.searchMany(ids),
    },
    (_) => AppLocalizations.of(context).arrSearchAllStarted,
  );

  /// Monitors the unmonitored ones shown, or stops monitoring the monitored.
  void _setMonitored(List<ArrWantedItem> all) {
    final l = AppLocalizations.of(context);
    final to = !_monitored;
    _forPicked(
      all,
      (c, ids) => switch (c) {
        SonarrClient() => c.setEpisodesMonitored(ids, to),
        LidarrClient() => c.setAlbumsMonitored(ids, to),
        _ => c.editMany(ids, {'monitored': to}),
      },
      (n) => to ? l.arrNowMonitoredCount(n) : l.arrNowUnmonitoredCount(n),
      changes: true,
    );
  }

  Future<void> _searchAll(ArrMerged<ArrWantedItem> merged) async {
    final l = AppLocalizations.of(context);
    final missing = _list == ArrWantedList.missing;
    final ok = await confirm(
      context,
      title: missing ? l.arrSearchAllMissing : l.arrSearchAllCutoff,
      message: l.arrSearchAllMessage(merged.total),
      confirmLabel: l.arrSearchAll,
    );
    if (!ok || !mounted) return;
    final clients = <ArrClient>[
      ?ref.read(sonarrClientProvider),
      ?ref.read(radarrClientProvider),
      ?ref.read(lidarrClientProvider),
    ];
    await arrRun(context, () async {
      await Future.wait([
        for (final c in clients)
          missing ? c.searchAllMissing() : c.searchAllCutoffUnmet(),
      ]);
    }, done: l.arrSearchAllStarted);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(arrWantedProvider(_arg));
    final fresh = async.asData?.value ?? async.unwrapPrevious().asData?.value;
    if (fresh != null) {
      _last = fresh;
      _lastFor = (_list, _monitored);
    }
    final merged =
        fresh ?? (_lastFor == (_list, _monitored) ? _last : null);
    final bar = ArrToolbar(
      lead: ArrSwitch<ArrWantedList>(
        options: [
          (ArrWantedList.missing, l.arrMissing),
          (ArrWantedList.cutoffUnmet, l.arrCutoffUnmet),
        ],
        value: _list,
        onChanged: (v) => setState(() {
          _list = v;
          _limit = arrPageSize;
          _picked = null;
        }),
      ),
      // On a phone these go under More: beside the switch there's room for
      // two buttons, not five.
      tools: [
        // Search All only on the monitored list: Radarr's search-all
        // always covers monitored movies (MissingMoviesSearch takes no
        // monitored setting), so on the unmonitored list it would search
        // the wrong ones. Picked titles can still be searched.
        if (merged != null && merged.total > 0 && _monitored)
          ArrTool(
            Icons.manage_search_rounded,
            l.arrSearchAll,
            () => _searchAll(merged),
            labeled: true,
          ),
        // Files on the server that never came through the queue, as
        // on the apps' Wanted page.
        // Not on a TV: going through folders, and picking several, take a
        // keyboard and a pointer.
        if (!isTvDevice && _picked == null)
          ArrTool(
            Icons.drive_folder_upload_rounded,
            l.arrManualImport,
            () => arrOpenFolderImport(context),
          ),
        if (!isTvDevice &&
            merged != null &&
            merged.items.isNotEmpty &&
            _picked == null)
          ArrTool(
            Icons.checklist_rounded,
            l.arrSelect,
            () => setState(() => _picked = {}),
          ),
      ],
      actions: [
        PopupMenuButton<bool>(
          tooltip: l.arrShowing,
          icon: Icon(
            _monitored
                ? Icons.filter_list_rounded
                : Icons.filter_alt_rounded,
          ),
          initialValue: _monitored,
          onSelected: (v) => setState(() {
            _monitored = v;
            _limit = arrPageSize;
            _picked = null;
          }),
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: true,
              checked: _monitored,
              child: Text(l.arrFilterMonitored),
            ),
            CheckedPopupMenuItem(
              value: false,
              checked: !_monitored,
              child: Text(l.arrUnmonitored),
            ),
          ],
        ),
      ],
    );
    if (merged == null) {
      return Column(
        children: [
          ArrListColumn(child: bar),
          Expanded(
            child: async.hasError
                ? ErrorView(
                    message: async.error.toString(),
                    onRetry: () => ref.invalidate(arrWantedProvider),
                  )
                : const ArrRowsSkeleton(),
          ),
        ],
      );
    }
    final items = merged.items;
    final live = {for (final w in items) _key(w)};
    final picked = _picked?.where(live.contains).toSet();
    final view = RefreshIndicator(
      onRefresh: () => ref.refresh(arrWantedProvider(_arg).future),
      child: ArrListView(
        slivers: [
          SliverToBoxAdapter(child: bar),
          SliverToBoxAdapter(child: ArrErrorBanner(errors: merged.errors)),
          if (merged.items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: true,
              child: EmptyState(
                icon: Icons.task_alt_rounded,
                title: !_monitored && _list == ArrWantedList.missing
                    ? l.arrWantedUnmonitoredEmpty
                    : _list == ArrWantedList.missing
                    ? l.arrWantedMissingEmpty
                    : l.arrWantedCutoffEmpty,
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(
                  l.arrWantedCount(merged.total),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            SliverList.builder(
              itemCount: merged.items.length,
              itemBuilder: (context, i) {
                final w = merged.items[i];
                final k = _key(w);
                return _WantedRow(
                  item: w,
                  cutoff: _list == ArrWantedList.cutoffUnmet,
                  picked: picked?.contains(k),
                  onPick: () => setState(() {
                    final p = {...?_picked};
                    if (!p.remove(k)) p.add(k);
                    _picked = p;
                  }),
                  onSelect: isTvDevice
                      ? null
                      : () => setState(() => _picked = {k}),
                );
              },
            ),
            if (merged.hasMore)
              SliverToBoxAdapter(
                child: _LoadMore(
                  loading: async.isLoading,
                  onTap: () => setState(() => _limit += arrPageSize),
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
    if (picked == null) return view;
    final l2 = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || ArrPaneScope.takesBack(context)) return;
        setState(() => _picked = null);
      },
      child: Column(
        children: [
          ArrPickBar(
            count: picked.length,
            busy: _busy,
            onCancel: () => setState(() => _picked = null),
            onSelectAll: () => setState(() => _picked = live),
            actions: [
              ArrPickAction(
                Icons.search_rounded,
                l2.arrSearchPicked,
                () => _search(items),
              ),
              ArrPickAction(
                _monitored
                    ? Icons.bookmark_border_rounded
                    : Icons.bookmark_rounded,
                _monitored ? l2.arrUnmonitor : l2.arrMonitor,
                () => _setMonitored(items),
              ),
            ],
          ),
          Expanded(child: view),
        ],
      ),
    );
  }
}

class _WantedRow extends ConsumerWidget {
  final ArrWantedItem item;
  final bool cutoff;

  /// While picking, whether this one is picked (null: not picking).
  final bool? picked;
  final VoidCallback? onPick;

  /// Starts picking, with this one picked: the menu's Select.
  final VoidCallback? onSelect;

  const _WantedRow({
    required this.item,
    required this.cutoff,
    this.picked,
    this.onPick,
    this.onSelect,
  });

  Future<void> _search(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return arrRun(context, () async {
      final id = item.itemId;
      final c = arrClient(ref, item.kind);
      if (id == null) return;
      await switch (c) {
        SonarrClient() => c.searchEpisodes([id]),
        RadarrClient() => c.searchMovie(id),
        LidarrClient() => c.searchAlbums([id]),
        _ => Future<void>.value(),
      };
    }, done: l.arrSearchStarted(item.kind.appName));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sub = switch (item.kind) {
      ArrKind.sonarr => [
        item.episodeCode,
        item.episodeTitle,
      ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
      ArrKind.radarr => item.year?.toString() ?? '',
      ArrKind.lidarr => item.albumTitle ?? '',
    };
    final date = item.date;
    final titleId = item.titleId;
    final searchLabel = switch (item.kind) {
      ArrKind.sonarr => l.arrSearchEpisode,
      ArrKind.radarr => l.arrSearchMovie,
      ArrKind.lidarr => l.arrSearchAlbum,
    };
    // Where the releases for this one are chosen by hand.
    final releases = switch (item.kind) {
      ArrKind.sonarr =>
        item.seriesId == null || item.episodeId == null
            ? null
            : ArrReleaseTarget.episode(item.seriesId!, item.episodeId!),
      ArrKind.radarr =>
        item.movieId == null ? null : ArrReleaseTarget.movie(item.movieId!),
      ArrKind.lidarr =>
        item.albumId == null ? null : ArrReleaseTarget.album(item.albumId!),
    };
    return _ArtRow(
      kind: item.kind,
      titleId: titleId,
      images: item.images,
      title: item.title,
      subtitle: sub,
      onTap: picked != null
          ? onPick!
          : () => arrOpenTitle(context, item.kind, titleId),
      // While picking, a press picks: no menu to get in its way.
      menu: picked != null
          ? null
          : (at) => showContextMenu(
              context,
              at: at,
              title: item.title,
              actions: [
                ...arrOpenActions(context, item.kind, titleId),
                if (item.available)
                  ContextMenuAction(
                    icon: Icons.search_rounded,
                    label: searchLabel,
                    onTap: () => _search(context, ref),
                  ),
                if (releases != null)
                  ContextMenuAction(
                    icon: Icons.manage_search_rounded,
                    label: l.arrInteractiveSearch,
                    onTap: () => context.push(releases.location),
                  ),
                if (onSelect != null)
                  ContextMenuAction(
                    icon: Icons.check_circle_outline_rounded,
                    label: l.arrSelect,
                    onTap: onSelect!,
                  ),
              ],
            ),
      leading: picked == null
          ? null
          : Checkbox(value: picked, onChanged: (_) => onPick?.call()),
      chips: [
        if (!item.available)
          ArrChip(label: l.arrNotReleased, color: arrUnreleasedColor)
        else if (cutoff)
          ArrChip(label: l.arrCutoffUnmet, color: arrWarningColor)
        else
          ArrChip(label: l.arrMissing, color: arrMissingColor),
        if (cutoff && item.quality != null)
          ArrChip(label: item.quality!, color: scheme.outline),
        if (date != null)
          ArrChip(
            label: item.kind == ArrKind.sonarr
                ? l.arrAired(arrDate(context, date))
                : arrDate(context, date),
            color: scheme.outline,
          ),
      ],
      trailing: picked != null
          ? null
          : IconButton(
              tooltip: searchLabel,
              onPressed: item.available ? () => _search(context, ref) : null,
              icon: const Icon(Icons.search_rounded),
            ),
    );
  }
}

// ----------------------------------------------------------------- History

/// What both apps have done lately: grabs, imports, failures, deletions.
class ArrHistoryTab extends ConsumerStatefulWidget {
  /// The Activity switch, at the left of the row above the list.
  final Widget lead;
  const ArrHistoryTab({super.key, required this.lead});

  @override
  ConsumerState<ArrHistoryTab> createState() => _ArrHistoryTabState();
}

class _ArrHistoryTabState extends ConsumerState<ArrHistoryTab> {
  int _limit = arrPageSize;
  ArrHistoryFilter _only = ArrHistoryFilter.all;

  String _label(AppLocalizations l, ArrHistoryFilter f) => switch (f) {
    ArrHistoryFilter.all => l.browseAll,
    ArrHistoryFilter.grabbed => l.arrEventGrabbed,
    ArrHistoryFilter.imported => l.arrEventImported,
    ArrHistoryFilter.failed => l.arrEventFailed,
    ArrHistoryFilter.deleted => l.arrEventDeleted,
    ArrHistoryFilter.renamed => l.arrEventRenamed,
    ArrHistoryFilter.ignored => l.arrEventIgnored,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(arrRecentHistoryProvider((_limit, _only)));
    final merged = async.asData?.value ?? async.unwrapPrevious().asData?.value;
    // Which events: the apps' History filter, shown as what's picked. On a
    // phone the switch leaves no room to name it: the filter's icon fills
    // in instead, and its menu has the tick.
    final filter = LayoutBuilder(
      builder: (context, box) => ArrToolbar(
        lead: widget.lead,
        actions: [
          if (_only != ArrHistoryFilter.all &&
              box.maxWidth >= ArrToolbar.foldBelow)
            InputChip(
              label: Text(_label(l, _only)),
              onDeleted: () => setState(() {
                _only = ArrHistoryFilter.all;
                _limit = arrPageSize;
              }),
            ),
          PopupMenuButton<ArrHistoryFilter>(
            tooltip: l.arrFilter,
            icon: Icon(
              _only == ArrHistoryFilter.all
                  ? Icons.filter_list_rounded
                  : Icons.filter_alt_rounded,
            ),
            initialValue: _only,
            onSelected: (f) => setState(() {
              _only = f;
              _limit = arrPageSize;
            }),
            itemBuilder: (_) => [
              for (final f in ArrHistoryFilter.values)
                CheckedPopupMenuItem(
                  value: f,
                  checked: f == _only,
                  child: Text(_label(l, f)),
                ),
            ],
          ),
        ],
      ),
    );
    if (merged == null) {
      return Column(
        children: [
          ArrListColumn(child: filter),
          Expanded(
            child: async.hasError
                ? ErrorView(
                    message: async.error.toString(),
                    onRetry: () => ref.invalidate(arrRecentHistoryProvider),
                  )
                : const ArrRowsSkeleton(),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: () =>
          ref.refresh(arrRecentHistoryProvider((_limit, _only)).future),
      child: ArrListView(
        slivers: [
          SliverToBoxAdapter(child: filter),
          SliverToBoxAdapter(child: ArrErrorBanner(errors: merged.errors)),
          if (merged.items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: true,
              child: EmptyState(
                icon: Icons.history_rounded,
                title: _only == ArrHistoryFilter.all
                    ? l.arrNoHistory
                    : l.arrHistoryEmptyFiltered,
              ),
            )
          else ...[
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverList.builder(
              itemCount: merged.items.length,
              itemBuilder: (context, i) =>
                  _HistoryEventRow(item: merged.items[i]),
            ),
            if (merged.hasMore)
              SliverToBoxAdapter(
                child: _LoadMore(
                  loading: async.isLoading,
                  onTap: () => setState(() => _limit += arrPageSize),
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _HistoryEventRow extends ConsumerWidget {
  final ArrHistoryItem item;
  const _HistoryEventRow({required this.item});

  Future<void> _markFailed(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final kind = item.kind;
    if (kind == null) return;
    final ok = await confirm(
      context,
      title: l.arrMarkFailedTitle,
      message: l.arrMarkFailedMessage(item.sourceTitle ?? '', kind.appName),
      confirmLabel: l.arrMarkFailed,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final c = arrClient(ref, kind);
    if (c == null) return;
    if (await arrRun(
      context,
      () => c.markFailed(item.id),
      done: l.arrMarkedFailed,
    )) {
      arrListsChanged(ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final kind = item.kind ?? ArrKind.sonarr;
    final (label, icon, color) = arrHistoryEvent(l, scheme, item.eventType);
    // The episode, or the album and its track.
    final sub = [
      item.episodeCode,
      item.episodeTitle,
      item.albumTitle,
      item.trackTitle,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final date = item.date;
    final titleId = item.titleId;
    // The row's menu, from its button or a right-click or long press.
    void menu(Offset at) => showContextMenu(
      context,
      at: at,
      title: item.title,
      actions: [
        ...arrOpenActions(context, kind, titleId),
        if (item.canMarkFailed)
          ContextMenuAction(
            icon: Icons.report_rounded,
            label: l.arrMarkFailed,
            color: scheme.error,
            onTap: () => _markFailed(context, ref),
          ),
      ],
    );
    return _ArtRow(
      kind: kind,
      titleId: titleId,
      menu: titleId == null && !item.canMarkFailed ? null : menu,
      images: item.images,
      title: item.title ?? item.sourceTitle ?? '',
      subtitle: sub,
      detail: [
        if (item.title != null) ?item.sourceTitle,
        [
          if (date != null)
            '${arrDate(context, date)} ${arrTime(context, date)}',
          ?item.detail,
        ].join(' · '),
      ].where((s) => s.isNotEmpty).join('\n'),
      onTap: () => arrOpenTitle(context, kind, titleId),
      chips: [
        ArrChip(label: label, color: color, icon: icon),
        if (item.quality != null)
          ArrChip(label: item.quality!, color: scheme.outline),
      ],
      trailing: item.canMarkFailed
          ? Builder(
              builder: (anchor) => IconButton(
                tooltip: l.arrMore,
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () {
                  final box = anchor.findRenderObject() as RenderBox?;
                  menu(
                    box == null
                        ? Offset.zero
                        : box.localToGlobal(box.size.bottomCenter(Offset.zero)),
                  );
                },
              ),
            )
          : null,
    );
  }
}

// ------------------------------------------------------------------ Health

/// What each app's health check says, and which version it runs.
class ArrHealthScreen extends ConsumerWidget {
  const ArrHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(arrHealthProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.arrHealth),
        actions: [
          IconButton(
            tooltip: l.commonRefresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(arrHealthProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: AppSpinner()),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(arrHealthProvider),
        ),
        data: (apps) => RefreshIndicator(
          onRefresh: () => ref.refresh(arrHealthProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [for (final a in apps) _AppHealth(app: a)],
          ),
        ),
      ),
    );
  }
}

class _AppHealth extends StatelessWidget {
  final ArrAppHealth app;
  const _AppHealth({required this.app});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = app.name;
    final issues = app.issues;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            app.version == null ? name : '$name ${app.version}',
            style: arrSectionStyle(theme),
          ),
          const SizedBox(height: 8),
          if (app.error != null)
            _HealthLine(
              icon: Icons.cloud_off_rounded,
              color: arrMissingColor,
              message: app.error!,
            )
          else if (issues.isEmpty)
            _HealthLine(
              icon: Icons.check_circle_rounded,
              color: arrDownloadedColor,
              message: l.arrHealthOk,
            )
          else
            for (final i in issues)
              _HealthLine(
                icon: switch (i.type) {
                  'error' => Icons.error_rounded,
                  'warning' => Icons.warning_rounded,
                  _ => Icons.info_rounded,
                },
                color: switch (i.type) {
                  'error' => arrMissingColor,
                  'warning' => arrWarningColor,
                  _ => scheme.outline,
                },
                message: i.message,
                wikiUrl: i.wikiUrl,
              ),
        ],
      ),
    );
  }
}

class _HealthLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  final String? wikiUrl;
  const _HealthLine({
    required this.icon,
    required this.color,
    required this.message,
    this.wikiUrl,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final wiki = wikiUrl == null ? null : Uri.tryParse(wikiUrl!);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: theme.textTheme.bodyMedium),
                if (wiki != null)
                  TextButton(
                    style: kInlineButtonStyle.merge(
                      TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    onPressed: () =>
                        launchUrl(wiki, mode: LaunchMode.externalApplication),
                    child: Text(l.arrLearnMore),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Health button in the Manage section's toolbar, with the number of
/// warnings and errors on it.
class ArrHealthButton extends ConsumerWidget {
  final VoidCallback onTap;
  const ArrHealthButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final problems = ref.watch(arrHealthProblemsProvider);
    return IconButton(
      tooltip: problems > 0 ? l.arrHealthProblems(problems) : l.arrHealth,
      onPressed: onTap,
      icon: Badge(
        isLabelVisible: problems > 0,
        backgroundColor: arrWarningColor,
        textColor: Colors.black,
        label: Text('$problems'),
        child: Icon(
          problems > 0
              ? Icons.health_and_safety_rounded
              : Icons.health_and_safety_outlined,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Shared

/// A list row with a small poster: title, a subtitle, chips, and an action.
class _ArtRow extends ConsumerWidget {
  final ArrKind kind;
  final List<ArrImage> images;
  final String title;
  final String subtitle;
  final String? detail;
  final List<Widget> chips;
  final Widget? trailing;
  final VoidCallback onTap;

  /// The show or movie the row is about, where the app knows it: the row
  /// is tinted while the pane beside the list shows it.
  final int? titleId;

  /// Opens the row's menu, on a right-click or a long press.
  final void Function(Offset at)? menu;

  /// Before the picture: a tick box while picking.
  final Widget? leading;

  const _ArtRow({
    required this.kind,
    this.titleId,
    this.menu,
    required this.images,
    required this.title,
    required this.subtitle,
    required this.chips,
    required this.onTap,
    this.detail,
    this.trailing,
    this.leading,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final client = arrWatchClient(ref, kind);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final detailed = detail != null && detail!.isNotEmpty;
    return LayoutBuilder(
      builder: (context, box) => _row(
        context,
        client,
        muted,
        // A row that says more is taller: on a list with the room, its
        // picture grows to match.
        big: detailed && box.maxWidth >= roomyFrom,
      ),
    );
  }

  /// From this width a row with more to say has a bigger picture.
  static const double roomyFrom = 560;

  Widget _row(
    BuildContext context,
    ArrClient? client,
    TextStyle? muted, {
    required bool big,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ArrRowInk(
      kind: kind,
      titleId: titleId,
      onTap: onTap,
      onMenu: menu,
      child: Padding(
        // With the row's own inset: 16 from the list's edge to the picture.
        padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null)
              Padding(
                padding: const EdgeInsets.only(right: 4, top: 14),
                child: leading,
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: big ? 56 : 46,
                height: big ? 84 : 69,
                child: ArrArt(
                  client: client,
                  images: images,
                  width: 185,
                  placeholderIcon: arrKindIcon(kind),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: chips),
                  if (detail != null && detail!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                  ],
                ],
              ),
            ),
            // On a TV the remote goes row to row, and RIGHT steps onto a
            // row's own button.
            if (trailing != null)
              TvRowActions(child: trailing!)
            else
              const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

class _LoadMore extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _LoadMore({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: loading
            ? const AppSpinner()
            : OutlinedButton(
                style: kInlineButtonStyle,
                onPressed: onTap,
                child: Text(l.arrLoadMore),
              ),
      ),
    );
  }
}

// --------------------------------------------------------------- Blocklist

/// Activity's Requests: what people asked for in Seerr that waits for a yes
/// or no, with the same rows and buttons as Discover's own Requests tab.
/// Approving one hands it to Sonarr or Radarr, and it's in the queue next.
class ArrRequestsView extends ConsumerStatefulWidget {
  /// The Activity switch, at the left of the row above the list.
  final Widget lead;
  const ArrRequestsView({super.key, required this.lead});

  @override
  ConsumerState<ArrRequestsView> createState() => _ArrRequestsViewState();
}

class _ArrRequestsViewState extends ConsumerState<ArrRequestsView> {
  SeerrPendingLimit? _limit;

  @override
  void dispose() {
    // What Load More brought goes with the list: the section's count asks
    // for one page from here on. Once the tree is done coming down, as no
    // provider may change before.
    final limit = _limit;
    if (limit != null) scheduleMicrotask(limit.reset);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lead = widget.lead;
    final limit = ref.watch(seerrPendingLimitProvider.notifier);
    _limit = limit;
    final async = ref.watch(seerrPendingRequestsProvider);
    // An answer given reloads the list; the rows stay meanwhile.
    final list = async.value?.requests;
    final more = (async.value?.total ?? 0) > (list?.length ?? 0);
    final toolbar = ArrToolbar(lead: lead);
    if (list == null) {
      return Column(
        children: [
          ArrListColumn(child: toolbar),
          Expanded(
            child: async.hasError
                ? ErrorView(
                    message: async.error.toString(),
                    onRetry: () => ref.invalidate(seerrPendingRequestsProvider),
                  )
                : const ArrRowsSkeleton(),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.refresh(seerrPendingRequestsProvider.future),
      child: ArrListView(
        slivers: [
          SliverToBoxAdapter(child: toolbar),
          if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: true,
              child: EmptyState(
                icon: Icons.inbox_rounded,
                title: l.arrRequestsEmpty,
                message: l.arrRequestsEmptyHint,
              ),
            )
          else ...[
            SliverList.builder(
              itemCount: list.length,
              itemBuilder: (context, i) => SeerrRequestTile(
                key: ValueKey(list[i].id),
                request: list[i],
              ),
            ),
            // More wait than were asked for: the count says so, and this
            // brings the next of them.
            if (more)
              SliverToBoxAdapter(
                child: _LoadMore(
                  loading: async.isLoading,
                  onTap: limit.more,
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

/// Releases Sonarr and Radarr won't grab again, newest first: remove one so
/// it can be grabbed, pick several, or clear the lot. The apps' Activity >
/// Blocklist, and one of the lists under the Activity tab here.
class ArrBlocklistView extends ConsumerStatefulWidget {
  /// The Activity switch, at the left of the row above the list.
  final Widget lead;
  const ArrBlocklistView({super.key, required this.lead});

  @override
  ConsumerState<ArrBlocklistView> createState() => _ArrBlocklistViewState();
}

class _ArrBlocklistViewState extends ConsumerState<ArrBlocklistView> {
  int _limit = arrPageSize;
  ArrMerged<ArrBlocklistItem>? _last; // kept while Load More fetches
  Set<String>? _picked;
  bool _busy = false;

  static String _key(ArrBlocklistItem b) => '${b.kind.name}:${b.id}';

  /// Takes [items] off the blocklist, one call per app.
  Future<void> _remove(List<ArrBlocklistItem> items) async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    final ok = await arrRun(context, () async {
      for (final kind in {for (final b in items) b.kind}) {
        await arrClient(ref, kind)?.removeFromBlocklist([
          for (final b in items)
            if (b.kind == kind) b.id,
        ]);
      }
    }, done: l.arrRemovedFromBlocklist(items.length));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _picked = null;
    });
    // Even after a failure: one app may have removed its part already.
    ref.invalidate(arrBlocklistProvider);
  }

  Future<void> _clear() async {
    final l = AppLocalizations.of(context);
    final ok = await confirm(
      context,
      title: l.arrClearBlocklistTitle,
      message: l.arrClearBlocklistMessage,
      confirmLabel: l.arrClearBlocklist,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final clients = <ArrClient>[
      ?ref.read(sonarrClientProvider),
      ?ref.read(radarrClientProvider),
      ?ref.read(lidarrClientProvider),
    ];
    setState(() => _busy = true);
    // Each app on its own, so one failing doesn't stop the other.
    Object? failure;
    await arrRun(context, () async {
      for (final c in clients) {
        try {
          await c.clearBlocklist();
        } catch (e) {
          failure ??= e;
        }
      }
      if (failure != null) throw failure!;
    }, done: l.arrBlocklistCleared);
    // The clear runs as a task on the server; give it a moment.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(arrBlocklistProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(arrBlocklistProvider(_limit));
    final merged =
        async.asData?.value ?? async.unwrapPrevious().asData?.value ?? _last;
    if (merged != null) _last = merged;
    final items = merged?.items ?? const <ArrBlocklistItem>[];
    final live = {for (final b in items) _key(b)};
    final picked = _picked?.where(live.contains).toSet();
    final toolbar = ArrToolbar(
      lead: widget.lead,
      // Under More on a phone: the switch takes the row.
      tools: [
        if (items.isNotEmpty && picked == null) ...[
          // Picking several is for a phone or a desktop, not a remote.
          if (!isTvDevice)
            ArrTool(
              Icons.checklist_rounded,
              l.arrSelect,
              () => setState(() => _picked = {}),
            ),
          ArrTool(
            Icons.delete_sweep_rounded,
            l.arrClearBlocklist,
            _busy ? null : _clear,
            danger: true,
          ),
        ],
      ],
    );
    Widget body;
    if (merged == null) {
      body = Column(
        children: [
          ArrListColumn(child: toolbar),
          Expanded(
            child: async.hasError
                ? ErrorView(
                    message: async.error.toString(),
                    onRetry: () => ref.invalidate(arrBlocklistProvider),
                  )
                : const ArrRowsSkeleton(),
          ),
        ],
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => ref.refresh(arrBlocklistProvider(_limit).future),
        child: ArrListView(
          slivers: [
            SliverToBoxAdapter(child: toolbar),
            SliverToBoxAdapter(child: ArrErrorBanner(errors: merged.errors)),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: true,
                child: EmptyState(
                  icon: Icons.block_rounded,
                  title: l.arrBlocklistEmpty,
                  message: l.arrBlocklistEmptyHint,
                ),
              )
            else ...[
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final b = items[i];
                  final k = _key(b);
                  final p = picked?.contains(k);
                  void pick() => setState(() {
                    final s = {...?_picked};
                    if (!s.remove(k)) s.add(k);
                    _picked = s;
                  });
                  final titleId = b.titleId;
                  final title = b.title ?? b.sourceTitle;
                  return _ArtRow(
                    kind: b.kind,
                    titleId: titleId,
                    images: b.images,
                    title: title,
                    subtitle: b.sourceTitle,
                    detail: b.message,
                    leading: p == null
                        ? null
                        : Checkbox(value: p, onChanged: (_) => pick()),
                    onTap: p != null
                        ? pick
                        : () => arrOpenTitle(context, b.kind, titleId),
                    // While picking, a press picks: no menu in its way.
                    menu: p != null
                        ? null
                        : (at) => showContextMenu(
                            context,
                            at: at,
                            title: title,
                            actions: [
                              ...arrOpenActions(context, b.kind, titleId),
                              // Picking several is for a phone or a desktop:
                              // on a TV this menu is only reached with a
                              // pointer plugged in.
                              if (!isTvDevice)
                                ContextMenuAction(
                                  icon: Icons.check_circle_outline_rounded,
                                  label: l.arrSelect,
                                  onTap: () => setState(() => _picked = {k}),
                                ),
                              if (!_busy)
                                ContextMenuAction(
                                  icon: Icons.close_rounded,
                                  label: l.arrRemoveFromBlocklist,
                                  color: theme.colorScheme.error,
                                  onTap: () => _remove([b]),
                                ),
                            ],
                          ),
                    chips: [
                      if (b.quality != null)
                        ArrChip(
                          label: b.quality!,
                          color: theme.colorScheme.outline,
                        ),
                      if (b.indexer?.isNotEmpty ?? false)
                        ArrChip(
                          label: b.indexer!,
                          color: theme.colorScheme.outline,
                        ),
                      if (b.date != null)
                        ArrChip(
                          label: arrDate(context, b.date!),
                          color: theme.colorScheme.outline,
                        ),
                    ],
                    trailing: p != null
                        ? null
                        : IconButton(
                            tooltip: l.arrRemoveFromBlocklist,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: _busy ? null : () => _remove([b]),
                          ),
                  );
                },
              ),
              if (merged.hasMore)
                SliverToBoxAdapter(
                  child: _LoadMore(
                    loading: async.isLoading,
                    onTap: () => setState(() => _limit += arrPageSize),
                  ),
                ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      );
    }
    if (picked == null) return body;
    // Back ends picking first, rather than leaving the section.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || ArrPaneScope.takesBack(context)) return;
        setState(() => _picked = null);
      },
      child: Column(
        children: [
          ArrPickBar(
            count: picked.length,
            busy: _busy,
            onCancel: () => setState(() => _picked = null),
            onSelectAll: () => setState(() => _picked = live),
            actions: [
              ArrPickAction(
                Icons.remove_done_rounded,
                l.arrRemoveFromBlocklist,
                () => _remove([
                  for (final b in items)
                    if (picked.contains(_key(b))) b,
                ]),
                danger: true,
              ),
            ],
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
