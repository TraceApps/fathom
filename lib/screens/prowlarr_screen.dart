import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/error_text.dart';
import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../services/tv_mode.dart';
import '../state/arr_providers.dart';
import '../state/download_providers.dart';
import '../widgets/checked_menu_item.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_actions.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/search_field.dart';
import '../widgets/tv_focus.dart';
import 'arr_releases_screen.dart';

/// Rows of a list, each a sliver.
List<Widget> _boxes(List<Widget> rows) => [
  for (final r in rows) SliverToBoxAdapter(child: r),
];

/// What the Indexers page shows.
enum ProwlarrView { indexers, search, stats, history }

/// Prowlarr, in the Manage section: its indexers (on or off, failing,
/// tested), a search across them, how each has done, and what it did.
class ProwlarrScreen extends ConsumerStatefulWidget {
  const ProwlarrScreen({super.key});

  @override
  ConsumerState<ProwlarrScreen> createState() => _ProwlarrScreenState();
}

class _ProwlarrScreenState extends ConsumerState<ProwlarrScreen> {
  ProwlarrView _view = ProwlarrView.indexers;

  /// The last test of each indexer, by id: null when it worked, or what's
  /// wrong. Kept while the page is open, across its tabs.
  final Map<int, List<String>?> _tested = {};

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final client = ref.watch(prowlarrClientProvider);
    if (client == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.prowlarrIndexers)),
        body: EmptyState(
          icon: Icons.travel_explore_rounded,
          title: l.prowlarrNotConnected,
        ),
      );
    }
    final switcher = ArrSwitch<ProwlarrView>(
      options: [
        (ProwlarrView.indexers, l.prowlarrIndexers),
        (ProwlarrView.search, l.prowlarrSearch),
        (ProwlarrView.stats, l.prowlarrStats),
        (ProwlarrView.history, l.arrHistory),
      ],
      value: _view,
      onChanged: (v) => setState(() => _view = v),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l.prowlarrIndexers),
        actions: [
          // Opened as the whole section (only Prowlarr and the download
          // clients connected), the way to the clients is here.
          if (ref.watch(arrLibraryKindsProvider).isEmpty) ...[
            if (ref.watch(bazarrClientProvider) != null)
              IconButton(
                tooltip: l.bzSubtitles,
                icon: const Icon(Icons.subtitles_rounded),
                onPressed: () => context.push('/arr/subtitles'),
              ),
            if (ref.watch(downloadClientsProvider).isNotEmpty)
              IconButton(
                tooltip: l.dlClients,
                icon: const Icon(Icons.downloading_rounded),
                onPressed: () => context.push('/arr/clients'),
              ),
          ],
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArrListColumn(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              // A TV opens the page on its list, not on the switch above it.
              child: TvChrome(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: switcher,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: switch (_view) {
              ProwlarrView.indexers => _Indexers(
                client: client,
                tested: _tested,
              ),
              ProwlarrView.search => _Search(client: client),
              ProwlarrView.stats => const _Stats(),
              ProwlarrView.history => const _History(),
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Indexers

class _Indexers extends ConsumerStatefulWidget {
  final ProwlarrClient client;

  /// The page's test results, kept above this tab.
  final Map<int, List<String>?> tested;
  const _Indexers({required this.client, required this.tested});

  @override
  ConsumerState<_Indexers> createState() => _IndexersState();
}

class _IndexersState extends ConsumerState<_Indexers> {
  Map<int, List<String>?> get _tested => widget.tested;
  final Set<int> _testing = {};
  bool _testingAll = false;

  /// Asks again when the soonest held-back indexer is due back, so its
  /// "Failing" goes when Prowlarr tries it again.
  Timer? _due;

  @override
  void dispose() {
    _due?.cancel();
    super.dispose();
  }

  /// What an action changes besides the list: Prowlarr's health warning
  /// about failing indexers, behind the Health button's count.
  void _changed() {
    ref.invalidate(prowlarrIndexersProvider);
    ref.invalidate(arrHealthProvider);
  }

  void _wakeAt(List<ProwlarrIndexerRow> rows, DateTime now) {
    _due?.cancel();
    final next = [
      for (final r in rows)
        if (r.status?.disabledAt(now) ?? false) r.status!.disabledTill!,
    ]..sort();
    if (next.isEmpty) return;
    _due = Timer(next.first.difference(now) + const Duration(seconds: 2), () {
      if (mounted) _changed();
    });
  }

  Future<void> _test(ProwlarrIndexer i) async {
    final l = AppLocalizations.of(context);
    setState(() => _testing.add(i.id));
    try {
      final problems = await widget.client.test(i);
      if (!mounted) return;
      setState(() => _tested[i.id] = problems);
      // A test can put a failing indexer back in use.
      _changed();
      showSnack(
        context,
        problems == null ? l.prowlarrTestWorks(i.name) : problems.first,
        kind: problems == null ? SnackKind.success : SnackKind.error,
      );
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), kind: SnackKind.error);
    } finally {
      if (mounted) setState(() => _testing.remove(i.id));
    }
  }

  Future<void> _testAll() async {
    final l = AppLocalizations.of(context);
    setState(() => _testingAll = true);
    try {
      final results = await widget.client.testAll();
      if (!mounted) return;
      setState(() {
        for (final r in results) {
          _tested[r.id] = r.ok ? null : r.problems;
        }
      });
      final failed = results.where((r) => !r.ok).length;
      showSnack(
        context,
        failed == 0
            ? l.prowlarrTestAllWorks(results.length)
            : l.prowlarrTestAllFailed(failed, results.length),
        kind: failed == 0 ? SnackKind.success : SnackKind.error,
      );
      // A test can put an indexer back in use, or out of it.
      _changed();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), kind: SnackKind.error);
    } finally {
      if (mounted) setState(() => _testingAll = false);
    }
  }

  Future<void> _setEnabled(ProwlarrIndexer i, bool on) async {
    final l = AppLocalizations.of(context);
    if (await arrRun(
      context,
      () => widget.client.setEnabled([i.id], on),
      done: on ? l.prowlarrTurnedOn(i.name) : l.prowlarrTurnedOff(i.name),
    )) {
      _changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(prowlarrIndexersProvider);
    final bar = ArrToolbar(
      lead: const SizedBox.shrink(),
      tools: [
        ArrTool(
          Icons.fact_check_rounded,
          l.prowlarrTestAll,
          _testingAll ? null : _testAll,
          labeled: true,
        ),
        ArrTool(
          Icons.sync_rounded,
          l.prowlarrSyncApps,
          () => arrRun(
            context,
            widget.client.syncApps,
            done: l.prowlarrSyncStarted,
          ),
        ),
      ],
    );
    return RefreshIndicator(
      onRefresh: () => ref.refresh(prowlarrIndexersProvider.future),
      child: async.when(
        loading: () => const Center(child: AppSpinner()),
        error: (e, _) => ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(prowlarrIndexersProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return EmptyState(
              icon: Icons.travel_explore_rounded,
              title: l.prowlarrNoIndexers,
              message: l.prowlarrNoIndexersHint,
            );
          }
          final now = DateTime.now();
          _wakeAt(rows, now);
          return ArrListView(
            slivers: _boxes([
              ArrListColumn(child: bar),
              for (final r in rows)
                _IndexerRow(
                  key: ValueKey(r.indexer.id),
                  row: r,
                  now: now,
                  // Prowlarr's Test All tests only the indexers that are on.
                  testing:
                      (_testingAll && r.indexer.enable) ||
                      _testing.contains(r.indexer.id),
                  tested: _tested.containsKey(r.indexer.id),
                  problems: _tested[r.indexer.id],
                  onTest: () => _test(r.indexer),
                  onEnable: (on) => _setEnabled(r.indexer, on),
                ),
            ]),
          );
        },
      ),
    );
  }
}

class _IndexerRow extends StatelessWidget {
  final ProwlarrIndexerRow row;
  final DateTime now;
  final bool testing;
  final bool tested;
  final List<String>? problems;
  final VoidCallback onTest;
  final ValueChanged<bool> onEnable;

  const _IndexerRow({
    super.key,
    required this.row,
    required this.now,
    required this.testing,
    required this.tested,
    required this.problems,
    required this.onTest,
    required this.onEnable,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final i = row.indexer;
    final held = row.status?.disabledAt(now) ?? false;
    final about = [
      ?i.definitionName,
      ?switch (i.privacy) {
        'public' => l.prowlarrPublic,
        'semiPrivate' => l.prowlarrSemiPrivate,
        'private' => l.prowlarrPrivate,
        _ => null,
      },
      l.prowlarrPriority(i.priority),
    ].join(' · ');
    return ArrListColumn(
      child: ArrRowInk(
        onTap: onTest,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  i.protocol == 'torrent'
                      ? Icons.hub_rounded
                      : Icons.dns_rounded,
                  color: i.enable ? scheme.primary : scheme.outline,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: i.enable ? null : scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      about,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (i.categories.isNotEmpty)
                      Text(
                        i.categories.join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ArrChip(
                          label: i.protocol == 'torrent'
                              ? l.arrTorrent
                              : l.arrUsenet,
                          color: i.protocol == 'torrent'
                              ? arrQueuedColor
                              : arrUnreleasedColor,
                        ),
                        if (!i.enable)
                          ArrChip(label: l.prowlarrOff, color: scheme.outline)
                        else if (held)
                          ArrChip(
                            label: _failingLabel(
                              context,
                              row.status!.disabledTill!,
                              now,
                            ),
                            color: arrWarningColor,
                          ),
                        if (testing)
                          ArrChip(label: l.prowlarrTesting, color: scheme.outline)
                        else if (tested && problems == null)
                          ArrChip(
                            label: l.prowlarrWorks,
                            color: arrDownloadedColor,
                          ),
                      ],
                    ),
                    if (!testing && problems != null)
                      for (final p in problems!)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            p,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: arrMissingColor,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
              TvRowActions(
                child: IconButton(
                  tooltip: l.prowlarrTest,
                  icon: const Icon(Icons.fact_check_rounded),
                  onPressed: testing ? null : onTest,
                ),
              ),
              TvRowActions(
                child: Switch(
                  value: i.enable,
                  onChanged: onEnable,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Failing, back at 7:25 PM", or with its day when that isn't today: a
/// failing indexer can be held back for half a day or more.
String _failingLabel(BuildContext context, DateTime until, DateTime now) {
  final l = AppLocalizations.of(context);
  final time = arrTime(context, until);
  final today =
      until.year == now.year &&
      until.month == now.month &&
      until.day == now.day;
  return today
      ? l.prowlarrFailingUntil(time)
      : l.prowlarrFailingUntilDay(arrDate(context, until), time);
}

// ------------------------------------------------------------------ Search

/// The kinds of release a search can keep to, by Newznab's top categories.
const _categories = <(int?, String Function(AppLocalizations))>[
  (null, _all),
  (2000, _movies),
  (5000, _tv),
  (3000, _audio),
  (7000, _books),
];
String _all(AppLocalizations l) => l.browseAll;
String _movies(AppLocalizations l) => l.arrMovies;
String _tv(AppLocalizations l) => l.arrShows;
String _audio(AppLocalizations l) => l.arrMusic;
String _books(AppLocalizations l) => l.prowlarrBooks;

enum _Sort { newest, size, seeders }

class _Search extends ConsumerStatefulWidget {
  final ProwlarrClient client;
  const _Search({required this.client});

  @override
  ConsumerState<_Search> createState() => _SearchState();
}

class _SearchState extends ConsumerState<_Search> {
  final _query = TextEditingController();
  int? _category;
  _Sort _sort = _Sort.newest;
  Future<List<ProwlarrRelease>>? _results;
  final _grabbing = <String>{};
  final _grabbed = <String>{};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _run() {
    final q = _query.text.trim();
    if (q.isEmpty) {
      // Nothing to look for: no results from an earlier search, which the
      // chips may no longer match.
      setState(() => _results = null);
      return;
    }
    setState(() {
      _results = widget.client.search(
        q,
        categories: [?_category],
      );
    });
  }

  Future<void> _grab(ProwlarrRelease r) async {
    final l = AppLocalizations.of(context);
    final key = _key(r);
    setState(() => _grabbing.add(key));
    final ok = await arrRun(
      context,
      () => widget.client.grab(r),
      done: l.prowlarrGrabbed,
    );
    if (!mounted) return;
    setState(() {
      _grabbing.remove(key);
      if (ok) _grabbed.add(key);
    });
  }

  /// Two indexers can hand back the same guid: a release is both.
  static String _key(ProwlarrRelease r) => '${r.indexerId}:${r.guid}';

  List<ProwlarrRelease> _sorted(List<ProwlarrRelease> all) => arrStableSorted(
    all,
    switch (_sort) {
      _Sort.newest => (a, b) => (a.ageHours ?? double.infinity).compareTo(
        b.ageHours ?? double.infinity,
      ),
      _Sort.size => (a, b) => b.size.compareTo(a.size),
      _Sort.seeders => (a, b) => (b.seeders ?? -1).compareTo(a.seeders ?? -1),
    },
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final head = ArrListColumn(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SearchField(
                    controller: _query,
                    hint: l.prowlarrSearchHint,
                    onSubmitted: (_) => _run(),
                  ),
                ),
                PopupMenuButton<_Sort>(
                  tooltip: l.arrSort,
                  icon: const Icon(Icons.sort_rounded),
                  initialValue: _sort,
                  onSelected: (s) => setState(() => _sort = s),
                  itemBuilder: (_) => [
                    for (final s in _Sort.values)
                      CheckedMenuItem(
                        value: s,
                        checked: s == _sort,
                        child: Text(switch (s) {
                          _Sort.newest => l.prowlarrSortNewest,
                          _Sort.size => l.arrSortSize,
                          _Sort.seeders => l.arrSortSeeders,
                        }),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (id, name) in _categories)
                  ChoiceChip(
                    label: Text(name(l)),
                    selected: _category == id,
                    onSelected: (_) {
                      setState(() => _category = id);
                      _run();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    final results = _results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        Expanded(
          child: results == null
              ? EmptyState(
                  icon: Icons.travel_explore_rounded,
                  title: l.prowlarrSearch,
                  message: l.prowlarrSearchTip,
                )
              : FutureBuilder<List<ProwlarrRelease>>(
                  future: results,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const AppSpinner(),
                            const SizedBox(height: 12),
                            Text(l.prowlarrSearching),
                          ],
                        ),
                      );
                    }
                    if (snap.hasError) {
                      return ErrorView(
                        message: errorText(snap.error!),
                        onRetry: _run,
                      );
                    }
                    final list = _sorted(snap.data ?? const []);
                    if (list.isEmpty) {
                      return EmptyState(
                        icon: Icons.search_off_rounded,
                        title: l.arrNoReleases,
                      );
                    }
                    return ArrListView(
                      slivers: _boxes([
                        ArrListColumn(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                            child: Text(
                              l.prowlarrResultCount(list.length),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        for (final r in list)
                          _ReleaseRow(
                            key: ValueKey(_key(r)),
                            release: r,
                            busy: _grabbing.contains(_key(r)),
                            grabbed: _grabbed.contains(_key(r)),
                            onGrab: () => _grab(r),
                          ),
                      ]),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ReleaseRow extends StatelessWidget {
  final ProwlarrRelease release;
  final bool busy;
  final bool grabbed;
  final VoidCallback onGrab;

  const _ReleaseRow({
    super.key,
    required this.release,
    required this.busy,
    required this.grabbed,
    required this.onGrab,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = release;
    final facts = [
      r.indexer,
      if (r.size > 0) arrSize(r.size),
      if (r.ageHours != null) arrAge(r.ageHours!),
      if (r.categories.isNotEmpty) r.categories.first,
      if (r.isTorrent && r.seeders != null)
        l.prowlarrPeers(r.seeders!, r.leechers ?? 0)
      else if (r.grabs != null && r.grabs! > 0)
        l.prowlarrGrabs(r.grabs!),
    ].join(' · ');
    final info = r.infoUrl;
    return ArrListColumn(
      child: ArrRowInk(
        onTap: info == null || isTvDevice
            ? null
            : () => launchUrl(
                Uri.parse(info),
                mode: LaunchMode.externalApplication,
              ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      facts,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TvRowActions(
                child: IconButton(
                  tooltip: grabbed ? l.prowlarrGrabbedShort : l.arrGrab,
                  onPressed: busy || grabbed ? null : onGrab,
                  icon: busy
                      ? const AppSpinner.inline()
                      : Icon(
                          grabbed
                              ? Icons.check_circle_rounded
                              : Icons.file_download_rounded,
                          color: grabbed ? arrDownloadedColor : null,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- Stats

class _Stats extends ConsumerWidget {
  const _Stats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final async = ref.watch(prowlarrStatsProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(prowlarrStatsProvider.future),
      child: async.when(
        loading: () => const Center(child: AppSpinner()),
        error: (e, _) => ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(prowlarrStatsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.insights_rounded,
              title: l.prowlarrNoStats,
            );
          }
          return ArrListView(
            slivers: _boxes([
              for (final s in list)
                ArrListColumn(
                  child: TvReadStop(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.name,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            [
                              l.prowlarrQueries(s.queries),
                              l.prowlarrGrabs(s.grabs),
                              if (s.rssQueries > 0) l.prowlarrRss(s.rssQueries),
                              l.prowlarrAverageResponse(s.averageResponseMs),
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (s.failures > 0)
                            Text(
                              l.prowlarrFailures(s.failures),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: arrWarningColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------------------- History

class _History extends ConsumerStatefulWidget {
  const _History();

  @override
  ConsumerState<_History> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<_History> {
  int _limit = arrPageSize;

  /// The last page shown: it stays while Load More asks for a bigger one,
  /// which is another provider with nothing of its own yet.
  ArrPage<ProwlarrHistoryItem>? _last;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final async = ref.watch(prowlarrHistoryProvider(_limit));
    final names = {
      for (final r
          in ref.watch(prowlarrIndexersProvider).asData?.value ??
              const <ProwlarrIndexerRow>[])
        r.indexer.id: r.indexer.name,
    };
    final page = async.asData?.value ?? _last;
    if (async.hasValue) _last = async.value;
    if (page == null) {
      return async.hasError
          ? ErrorView(
              message: errorText(async.error!),
              onRetry: () => ref.invalidate(prowlarrHistoryProvider),
            )
          : const Center(child: AppSpinner());
    }
    if (page.items.isEmpty) {
      return EmptyState(icon: Icons.history_rounded, title: l.arrNoHistory);
    }
    return RefreshIndicator(
      onRefresh: () => ref.refresh(prowlarrHistoryProvider(_limit).future),
      child: ArrListView(
        slivers: _boxes([
          for (final h in page.items)
            ArrListColumn(
              child: TvReadStop(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        switch (h.eventType) {
                          'releaseGrabbed' => Icons.file_download_rounded,
                          'indexerRss' => Icons.rss_feed_rounded,
                          'indexerAuth' => Icons.key_rounded,
                          _ => Icons.search_rounded,
                        },
                        size: 20,
                        color: h.successful
                            ? scheme.onSurfaceVariant
                            : arrMissingColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              switch (h.eventType) {
                                'releaseGrabbed' =>
                                  h.grabTitle ?? l.prowlarrEventGrab,
                                'indexerRss' => l.prowlarrEventRss,
                                'indexerAuth' => l.prowlarrEventAuth,
                                _ => h.query ?? l.prowlarrEventQuery,
                              },
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              [
                                ?names[h.indexerId],
                                ?h.source,
                                if (h.results != null)
                                  l.prowlarrResultCount(h.results!),
                                if (!h.successful) l.prowlarrFailed,
                                if (h.date != null)
                                  '${arrDate(context, h.date!)} ${arrTime(context, h.date!)}',
                              ].join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: h.successful
                                    ? scheme.onSurfaceVariant
                                    : arrMissingColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (page.items.length < page.total)
            ArrListColumn(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: TextButton(
                    onPressed: () => setState(() => _limit += arrPageSize),
                    child: Text(l.arrLoadMore),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
