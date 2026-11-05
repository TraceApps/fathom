import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../routing/app_shell.dart';
import '../state/arr_providers.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_actions.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/media_cards.dart';
import '../widgets/motion.dart';
import '../widgets/search_field.dart';

/// Sonarr and Radarr in one place: what's coming up, what's downloading, and
/// the movies and shows each one manages. Tabs only appear for what's
/// connected.
class ArrScreen extends ConsumerWidget {
  const ArrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sonarr = ref.watch(sonarrClientProvider) != null;
    final radarr = ref.watch(radarrClientProvider) != null;
    if (!sonarr && !radarr) {
      return Scaffold(
        appBar: AppBar(
          leading: mobileDrawerLeading(context),
          title: const Text('Arr'),
        ),
        body: EmptyState(
          icon: Icons.dns_rounded,
          title: l.arrConnectTitle,
          message: l.arrConnectMessage,
          action: FilledButton(
            onPressed: () => context.push('/arr-settings'),
            child: Text(l.browseSetUp),
          ),
        ),
      );
    }
    final tabs = <(String, Widget)>[
      (l.arrCalendar, const _CalendarTab()),
      (l.arrQueue, const _QueueTab()),
      if (radarr) (l.arrMovies, const _MoviesTab()),
      if (sonarr) (l.arrShows, const _ShowsTab()),
    ];
    return DefaultTabController(
      // A different set of tabs is a different controller.
      key: ValueKey('arr-tabs-$sonarr-$radarr'),
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          leading: mobileDrawerLeading(context),
          title: const Text('Arr'),
          actions: [
            IconButton(
              tooltip: l.browseSettings,
              icon: const Icon(Icons.settings_rounded),
              onPressed: () => context.push('/arr-settings'),
            ),
          ],
          bottom: TabBar(tabs: [for (final t in tabs) Tab(text: t.$1)]),
        ),
        body: TabBarView(
          children: [for (final t in tabs) RepaintBoundary(child: t.$2)],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Calendar

class _CalendarTab extends ConsumerWidget {
  const _CalendarTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(arrCalendarProvider);
    return async.when(
      loading: () => const Center(child: AppSpinner()),
      error: (e, _) => ErrorView(
        message: e.toString(),
        onRetry: () => ref.invalidate(arrCalendarProvider),
      ),
      data: (merged) {
        final days = _byDay(merged.items);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(arrCalendarProvider.future),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: ArrErrorBanner(errors: merged.errors)),
              if (days.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.event_available_rounded,
                    title: l.arrCalendarEmpty,
                  ),
                )
              else
                for (final day in days.entries) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                      child: Text(
                        _dayLabel(context, l, day.key),
                        style: arrSectionStyle(Theme.of(context)),
                      ),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: day.value.length,
                    itemBuilder: (context, i) =>
                        _CalendarRow(entry: day.value[i]),
                  ),
                ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }

  static Map<DateTime, List<ArrCalendarEntry>> _byDay(
    List<ArrCalendarEntry> items,
  ) {
    final out = <DateTime, List<ArrCalendarEntry>>{};
    for (final e in items) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      (out[d] ??= []).add(e);
    }
    return out;
  }

  static String _dayLabel(
    BuildContext context,
    AppLocalizations l,
    DateTime d,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = d.difference(today).inDays;
    if (diff == 0) return l.arrToday;
    if (diff == 1) return l.arrTomorrow;
    if (diff == -1) return l.arrYesterday;
    return DateFormat.MMMEd(
      Localizations.localeOf(context).toString(),
    ).format(d);
  }
}

class _CalendarRow extends ConsumerWidget {
  final ArrCalendarEntry entry;
  const _CalendarRow({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ArrClient? client = entry.kind == ArrKind.sonarr
        ? ref.watch(sonarrClientProvider)
        : ref.watch(radarrClientProvider);
    final now = DateTime.now();
    final aired = !entry.date.isAfter(now);
    final (String status, Color color) = entry.hasFile
        ? (l.arrDownloaded, arrDownloadedColor)
        : !entry.monitored
        ? (l.arrUnmonitored, scheme.outline)
        : aired
        ? (l.arrMissing, arrMissingColor)
        : entry.kind == ArrKind.sonarr
        ? (l.arrUnaired, arrUnreleasedColor)
        : (l.arrNotReleased, arrUnreleasedColor);
    final subtitle = entry.kind == ArrKind.sonarr
        ? [
            entry.episodeCode,
            entry.episodeTitle,
          ].whereType<String>().where((s) => s.isNotEmpty).join(' · ')
        : switch (entry.release) {
            ArrRelease.cinemas => l.arrInCinemas,
            ArrRelease.digital => l.arrDigitalRelease,
            ArrRelease.physical => l.arrPhysicalRelease,
            null => '',
          };
    return InkWell(
      onTap: () => _openTitle(
        context,
        entry.kind,
        entry.kind == ArrKind.sonarr ? entry.seriesId : entry.movieId,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 46,
                height: 69,
                child: ArrArt(
                  client: client,
                  images: entry.images,
                  width: 185,
                  placeholderIcon: entry.kind == ArrKind.sonarr
                      ? Icons.live_tv_rounded
                      : Icons.movie_rounded,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
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
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ArrChip(label: status, color: color),
                      if (entry.finale)
                        ArrChip(label: l.arrFinale, color: arrQueuedColor),
                    ],
                  ),
                ],
              ),
            ),
            if (entry.kind == ArrKind.sonarr) ...[
              const SizedBox(width: 10),
              Text(
                arrTime(context, entry.date),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

void _openTitle(BuildContext context, ArrKind kind, int? id) {
  if (id == null) return;
  context.push(kind == ArrKind.sonarr ? '/arr/series/$id' : '/arr/movie/$id');
}

// ---------------------------------------------------------------- Queue

class _QueueTab extends ConsumerStatefulWidget {
  const _QueueTab();

  @override
  ConsumerState<_QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends ConsumerState<_QueueTab>
    with WidgetsBindingObserver {
  Timer? _timer;

  // Refreshes every few seconds while the tab is on screen and the app is in
  // front; the tab view disposes it when another tab shows.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) ref.invalidate(arrQueueProvider);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
      ref.invalidate(arrQueueProvider);
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(arrQueueProvider);
    // A refresh keeps showing the last list instead of flashing a spinner.
    final merged = async.asData?.value ?? async.unwrapPrevious().asData?.value;
    if (merged == null) {
      if (async.hasError) {
        return ErrorView(
          message: async.error.toString(),
          onRetry: () => ref.invalidate(arrQueueProvider),
        );
      }
      return const Center(child: AppSpinner());
    }
    return RefreshIndicator(
      onRefresh: () => ref.refresh(arrQueueProvider.future),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: ArrErrorBanner(errors: merged.errors)),
          if (merged.items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.download_done_rounded,
                title: l.arrQueueEmpty,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              sliver: SliverList.separated(
                itemCount: merged.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _QueueCard(item: merged.items[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _QueueCard extends ConsumerWidget {
  final ArrQueueItem item;
  const _QueueCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ArrClient? client = item.kind == ArrKind.sonarr
        ? ref.watch(sonarrClientProvider)
        : ref.watch(radarrClientProvider);
    final (String status, Color color) = _status(l, scheme);
    final eta = item.estimatedCompletion?.difference(DateTime.now());
    final heading = [
      item.mediaTitle ?? item.title,
      if (item.episodeCode != null) item.episodeCode!,
    ].join(' · ');
    final meta = [
      ?item.quality,
      if (item.size > 0) arrSize(item.size),
      ?item.downloadClient,
    ].join(' · ');
    final problems = [
      if (item.errorMessage?.isNotEmpty ?? false) item.errorMessage!,
      ...item.messages,
    ];
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openTitle(
          context,
          item.kind,
          item.kind == ArrKind.sonarr ? item.seriesId : item.movieId,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 52,
                  height: 78,
                  child: ArrArt(
                    client: client,
                    images: item.images,
                    width: 185,
                    placeholderIcon: item.kind == ArrKind.sonarr
                        ? Icons.live_tv_rounded
                        : Icons.movie_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: item.progress,
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ArrChip(label: status, color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (eta != null &&
                            !eta.isNegative &&
                            item.status == 'downloading')
                          Text(
                            l.arrTimeLeft(arrDuration(eta)),
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                    for (final p in problems.toSet())
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          p,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: arrWarningColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (client != null)
                IconButton(
                  tooltip: l.arrRemoveFromQueue,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () async {
                    if (await showArrQueueRemoveDialog(
                      context,
                      client: client,
                      item: item,
                    )) {
                      ref.invalidate(arrQueueProvider);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  (String, Color) _status(AppLocalizations l, ColorScheme scheme) {
    if (item.status == 'failed' || item.trackedDownloadState == 'failed') {
      return (l.arrFailed, arrMissingColor);
    }
    switch (item.trackedDownloadState) {
      case 'importBlocked':
        return (l.arrImportBlocked, arrWarningColor);
      case 'importPending':
        return (l.arrWaitingToImport, arrDownloadedColor);
      case 'importing':
        return (l.arrImporting, arrDownloadedColor);
      case 'failedPending':
        return (l.arrFailed, arrMissingColor);
    }
    if (item.trackedDownloadStatus == 'warning' ||
        item.trackedDownloadStatus == 'error' ||
        item.status == 'warning') {
      return (l.arrNeedsAttention, arrWarningColor);
    }
    return switch (item.status) {
      'paused' => (l.arrPaused, scheme.outline),
      'queued' => (l.arrQueued, arrQueuedColor),
      'delay' => (l.arrDelayed, scheme.outline),
      'completed' => (l.arrWaitingToImport, arrDownloadedColor),
      _ => (l.arrDownloading, arrUnreleasedColor),
    };
  }
}

// ---------------------------------------------------------------- Libraries

enum _Sort { title, added, year, size }

enum _Filter {
  all,
  monitored,
  unmonitored,
  missing,
  downloaded,
  continuing,
  ended,
}

class _MoviesTab extends ConsumerStatefulWidget {
  const _MoviesTab();

  @override
  ConsumerState<_MoviesTab> createState() => _MoviesTabState();
}

class _MoviesTabState extends ConsumerState<_MoviesTab> {
  final _search = TextEditingController();
  _Sort _sort = _Sort.title;
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ArrMovie> _apply(List<ArrMovie> all) {
    final q = _search.text.trim().toLowerCase();
    final list = all.where((m) {
      if (q.isNotEmpty && !m.title.toLowerCase().contains(q)) return false;
      return switch (_filter) {
        _Filter.monitored => m.monitored,
        _Filter.unmonitored => !m.monitored,
        _Filter.missing => m.state == ArrState.missing,
        _Filter.downloaded => m.hasFile,
        _ => true,
      };
    }).toList();
    int byTitle(ArrMovie a, ArrMovie b) =>
        (a.sortTitle ?? a.title).compareTo(b.sortTitle ?? b.title);
    list.sort(switch (_sort) {
      _Sort.title => byTitle,
      _Sort.added => (a, b) => (b.added ?? DateTime(0)).compareTo(
        a.added ?? DateTime(0),
      ),
      _Sort.year => (a, b) => (b.year ?? 0).compareTo(a.year ?? 0),
      _Sort.size => (a, b) => b.sizeOnDisk.compareTo(a.sizeOnDisk),
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final client = ref.watch(radarrClientProvider);
    final async = ref.watch(radarrMoviesProvider);
    return _LibraryFrame(
      search: _search,
      hint: l.arrSearchMovies,
      onSearch: () => setState(() {}),
      sort: _sort,
      onSort: (s) => setState(() => _sort = s),
      filter: _filter,
      filters: const [
        _Filter.all,
        _Filter.monitored,
        _Filter.unmonitored,
        _Filter.missing,
        _Filter.downloaded,
      ],
      onFilter: (f) => setState(() => _filter = f),
      onRefresh: () => ref.refresh(radarrMoviesProvider.future),
      addLabel: l.arrAddMovie,
      onAdd: () => context.push('/arr/add/movie'),
      body: async.when(
        loading: () => const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: AppSpinner()),
        ),
        error: (e, _) => SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(radarrMoviesProvider),
          ),
        ),
        data: (all) {
          final list = _apply(all);
          if (list.isEmpty) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.movie_rounded,
                title: all.isEmpty ? l.arrNoMovies : l.arrNoMatches,
              ),
            );
          }
          return _PosterGrid(
            count: list.length,
            builder: (i) {
              final m = list[i];
              return _ArrPosterCard(
                key: ValueKey('rm${m.id}'),
                client: client,
                images: m.images,
                title: m.title,
                subtitle: m.year?.toString(),
                bar: ArrPosterBar(
                  color: arrStateColor(m.state, Theme.of(context).colorScheme),
                ),
                icon: Icons.movie_rounded,
                onTap: () => context.push('/arr/movie/${m.id}'),
              );
            },
          );
        },
      ),
    );
  }
}

class _ShowsTab extends ConsumerStatefulWidget {
  const _ShowsTab();

  @override
  ConsumerState<_ShowsTab> createState() => _ShowsTabState();
}

class _ShowsTabState extends ConsumerState<_ShowsTab> {
  final _search = TextEditingController();
  _Sort _sort = _Sort.title;
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ArrSeries> _apply(List<ArrSeries> all) {
    final q = _search.text.trim().toLowerCase();
    final list = all.where((s) {
      if (q.isNotEmpty && !s.title.toLowerCase().contains(q)) return false;
      return switch (_filter) {
        _Filter.monitored => s.monitored,
        _Filter.unmonitored => !s.monitored,
        _Filter.missing => s.monitored && s.missingEpisodes > 0,
        _Filter.continuing => !s.ended,
        _Filter.ended => s.ended,
        _ => true,
      };
    }).toList();
    int byTitle(ArrSeries a, ArrSeries b) =>
        (a.sortTitle ?? a.title).compareTo(b.sortTitle ?? b.title);
    list.sort(switch (_sort) {
      _Sort.title => byTitle,
      _Sort.added => (a, b) => (b.added ?? DateTime(0)).compareTo(
        a.added ?? DateTime(0),
      ),
      _Sort.year => (a, b) => (b.year ?? 0).compareTo(a.year ?? 0),
      _Sort.size => (a, b) => b.sizeOnDisk.compareTo(a.sizeOnDisk),
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final client = ref.watch(sonarrClientProvider);
    final async = ref.watch(sonarrSeriesListProvider);
    final scheme = Theme.of(context).colorScheme;
    return _LibraryFrame(
      search: _search,
      hint: l.arrSearchShows,
      onSearch: () => setState(() {}),
      sort: _sort,
      onSort: (s) => setState(() => _sort = s),
      filter: _filter,
      filters: const [
        _Filter.all,
        _Filter.monitored,
        _Filter.unmonitored,
        _Filter.missing,
        _Filter.continuing,
        _Filter.ended,
      ],
      onFilter: (f) => setState(() => _filter = f),
      onRefresh: () => ref.refresh(sonarrSeriesListProvider.future),
      addLabel: l.arrAddShow,
      onAdd: () => context.push('/arr/add/series'),
      body: async.when(
        loading: () => const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: AppSpinner()),
        ),
        error: (e, _) => SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(sonarrSeriesListProvider),
          ),
        ),
        data: (all) {
          final list = _apply(all);
          if (list.isEmpty) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.live_tv_rounded,
                title: all.isEmpty ? l.arrNoShows : l.arrNoMatches,
              ),
            );
          }
          return _PosterGrid(
            count: list.length,
            builder: (i) {
              final s = list[i];
              // Sonarr's bar: green when every aired episode is there, red when
              // some are missing, blue while a show still airs, grey when it
              // isn't monitored.
              final color = !s.monitored
                  ? scheme.outline
                  : s.missingEpisodes > 0
                  ? arrMissingColor
                  : s.ended
                  ? arrDownloadedColor
                  : arrContinuingColor;
              return _ArrPosterCard(
                key: ValueKey('ss${s.id}'),
                client: client,
                images: s.images,
                title: s.title,
                subtitle: l.arrEpisodesOf(s.episodeFileCount, s.episodeCount),
                bar: ArrPosterBar(color: color, fraction: s.progress),
                icon: Icons.live_tv_rounded,
                onTap: () => context.push('/arr/series/${s.id}'),
              );
            },
          );
        },
      ),
    );
  }
}

/// The search box with Sort and Filter menus, above a scrolling grid.
class _LibraryFrame extends StatelessWidget {
  final TextEditingController search;
  final String hint;
  final VoidCallback onSearch;
  final _Sort sort;
  final ValueChanged<_Sort> onSort;
  final _Filter filter;
  final List<_Filter> filters;
  final ValueChanged<_Filter> onFilter;
  final Future<void> Function() onRefresh;
  final Widget body; // a sliver
  final String addLabel;
  final VoidCallback onAdd;

  const _LibraryFrame({
    required this.addLabel,
    required this.onAdd,
    required this.search,
    required this.hint,
    required this.onSearch,
    required this.sort,
    required this.onSort,
    required this.filter,
    required this.filters,
    required this.onFilter,
    required this.onRefresh,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    String sortLabel(_Sort s) => switch (s) {
      _Sort.title => l.arrSortTitle,
      _Sort.added => l.arrSortAdded,
      _Sort.year => l.arrSortYear,
      _Sort.size => l.arrSortSize,
    };
    String filterLabel(_Filter f) => switch (f) {
      _Filter.all => l.browseAll,
      _Filter.monitored => l.arrFilterMonitored,
      _Filter.unmonitored => l.arrUnmonitored,
      _Filter.missing => l.arrMissing,
      _Filter.downloaded => l.arrDownloaded,
      _Filter.continuing => l.arrContinuing,
      _Filter.ended => l.arrEnded,
    };
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: SearchField(
                      controller: search,
                      hint: hint,
                      onChanged: (_) => onSearch(),
                    ),
                  ),
                  PopupMenuButton<_Filter>(
                    tooltip: l.arrFilter,
                    icon: Icon(
                      filter == _Filter.all
                          ? Icons.filter_list_rounded
                          : Icons.filter_alt_rounded,
                    ),
                    initialValue: filter,
                    onSelected: onFilter,
                    itemBuilder: (_) => [
                      for (final f in filters)
                        CheckedPopupMenuItem(
                          value: f,
                          checked: f == filter,
                          child: Text(filterLabel(f)),
                        ),
                    ],
                  ),
                  PopupMenuButton<_Sort>(
                    tooltip: l.arrSort,
                    icon: const Icon(Icons.sort_rounded),
                    initialValue: sort,
                    onSelected: onSort,
                    itemBuilder: (_) => [
                      for (final s in _Sort.values)
                        CheckedPopupMenuItem(
                          value: s,
                          checked: s == sort,
                          child: Text(sortLabel(s)),
                        ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: addLabel,
                    icon: const Icon(Icons.add_rounded),
                    onPressed: onAdd,
                  ),
                ],
              ),
            ),
          ),
          body,
        ],
      ),
    );
  }
}

class _PosterGrid extends StatelessWidget {
  final int count;
  final Widget Function(int i) builder;
  const _PosterGrid({required this.count, required this.builder});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 168,
          mainAxisSpacing: 18,
          crossAxisSpacing: 14,
          childAspectRatio: 0.52,
        ),
        itemCount: count,
        itemBuilder: (context, i) => EntranceFade(index: i, child: builder(i)),
      ),
    );
  }
}

class _ArrPosterCard extends StatelessWidget {
  final ArrClient? client;
  final List<ArrImage> images;
  final String title;
  final String? subtitle;
  final Widget bar;
  final IconData icon;
  final VoidCallback onTap;

  const _ArrPosterCard({
    super.key,
    required this.client,
    required this.images,
    required this.title,
    required this.bar,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: HoverPosterArt(
            onTap: onTap,
            art: ArrArt(client: client, images: images, placeholderIcon: icon),
            overlay: bar,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
