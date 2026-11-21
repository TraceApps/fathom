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
import '../theme/app_theme.dart';
import '../widgets/app_spinner.dart';
import '../widgets/context_menu.dart';
import 'arr_activity_screens.dart';
import 'arr_import_screen.dart';
import '../widgets/arr_actions.dart';
import '../widgets/arr_bulk.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/media_cards.dart';
import '../widgets/motion.dart';
import '../widgets/search_field.dart';

/// The Manage section: Sonarr and Radarr in one place. The Library they
/// manage comes first, then what's coming up (Calendar), what's downloading
/// and what happened (Activity), and what's still missing (Wanted).
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
          title: Text(l.appNavManage),
        ),
        body: EmptyState(
          icon: kManageIcon,
          title: l.arrConnectTitle,
          message: l.arrConnectMessage,
          action: FilledButton(
            onPressed: () => context.push('/arr-settings'),
            child: Text(l.browseSetUp),
          ),
        ),
      );
    }
    // Four tabs fit a phone side by side; on a wide window they'd stretch
    // across it, so they keep their own width there.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return DefaultTabController(
      length: 4,
      // The Activity tab's count stays current while the section is open.
      child: _QueuePoll(
        countOnly: true,
        every: const Duration(seconds: 30),
        child: Scaffold(
          appBar: AppBar(
            leading: mobileDrawerLeading(context),
            title: Text(l.appNavManage),
            actions: [
              // Add opens on the kind of library it's pressed from; from the
              // other tabs it searches movies and shows together.
              Builder(
                builder: (context) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilledButton.tonalIcon(
                    style: kInlineButtonStyle,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(l.arrAdd),
                    onPressed: () {
                      final onLibrary =
                          DefaultTabController.of(context).index == 0;
                      final kind = !onLibrary
                          ? null
                          : _libraryKind(ref, sonarr: sonarr, radarr: radarr);
                      context.push(switch (kind) {
                        ArrKind.radarr => '/arr/add/movie',
                        ArrKind.sonarr => '/arr/add/series',
                        null => '/arr/add',
                      });
                    },
                  ),
                ),
              ),
              ArrHealthButton(onTap: () => context.push('/arr/health')),
              IconButton(
                tooltip: l.browseSettings,
                icon: const Icon(Icons.settings_rounded),
                onPressed: () => context.push('/arr-settings'),
              ),
            ],
            bottom: TabBar(
              isScrollable: !narrow,
              tabAlignment: narrow ? TabAlignment.fill : TabAlignment.start,
              // Four tabs share a phone's width: the usual side padding
              // would cut "Activity" short once its count shows.
              labelPadding: narrow
                  ? const EdgeInsets.symmetric(horizontal: 4)
                  : null,
              tabs: [
                Tab(text: l.arrLibrary),
                Tab(text: l.arrCalendar),
                Tab(
                  // A long count on a small phone shrinks the pair a little
                  // instead of cutting the name short.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Text(l.arrActivity), const _QueueCount()],
                    ),
                  ),
                ),
                Tab(text: l.arrWanted),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              RepaintBoundary(child: _LibraryTab()),
              RepaintBoundary(child: _CalendarTab()),
              RepaintBoundary(child: _ActivityTab()),
              RepaintBoundary(child: ArrWantedTab()),
            ],
          ),
        ),
      ),
    );
  }
}

/// The library on show: the one picked when both apps are connected,
/// otherwise the one that is.
ArrKind _libraryKind(WidgetRef ref, {required bool sonarr, required bool radarr}) =>
    sonarr && radarr
    ? ref.read(arrLibraryKindProvider)
    : radarr
    ? ArrKind.radarr
    : ArrKind.sonarr;

/// How many downloads are in the queue, beside the Activity tab's name, as
/// on the apps' own Activity entry. Orange when one needs a look, or when an
/// app didn't answer (a "!" then stands in if nothing else is counted).
class _QueueCount extends ConsumerWidget {
  const _QueueCount();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The last answer stays up while the next one is on its way.
    final status = ref.watch(arrQueueStatusProvider).value;
    if (status == null || (status.count == 0 && !status.unreachable)) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final problem = status.problem || status.unreachable;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(
        color: problem ? arrWarningColor : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.count == 0 ? '!' : '${status.count}',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: kAppFontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: problem ? Colors.black : scheme.onSecondaryContainer,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Asks for the queue again every [every] while the window is showing: the
/// whole queue, or with [countOnly] just the Activity tab's count.
///
/// Under a page opened over this one (a title, the settings) nothing is
/// asked for: a page that isn't showing stops listening, so the reload waits
/// and runs once, on the way back.
class _QueuePoll extends ConsumerStatefulWidget {
  final Duration every;
  final bool countOnly;
  final Widget child;
  const _QueuePoll({
    required this.every,
    this.countOnly = false,
    required this.child,
  });

  @override
  ConsumerState<_QueuePoll> createState() => _QueuePollState();
}

class _QueuePollState extends ConsumerState<_QueuePoll>
    with WidgetsBindingObserver {
  Timer? _timer;

  /// An answer is still on its way.
  bool _waiting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _reload() => widget.countOnly
      ? ref.invalidate(arrQueueStatusProvider)
      : ref.invalidate(arrQueueProvider);

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.every, (_) {
      // Asking again before a slow server has answered would throw its
      // answer away, and so never show one.
      if (mounted && !_waiting) _reload();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Back from out of sight: catch up at once.
        if (_timer == null) {
          _start();
          _reload();
        }
      case AppLifecycleState.inactive:
        // Still showing (a desktop window that isn't the active one, a
        // split screen): keep going.
        break;
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _timer?.cancel();
        _timer = null;
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
    _waiting = widget.countOnly
        ? ref.watch(arrQueueStatusProvider.select((a) => a.isLoading))
        : ref.watch(arrQueueProvider.select((a) => a.isLoading));
    return widget.child;
  }
}

// ---------------------------------------------------------------- Library

/// Movies and Shows behind one switch. The search box is shared, so a title
/// typed once can be looked for in both.
class _LibraryTab extends ConsumerStatefulWidget {
  const _LibraryTab();

  @override
  ConsumerState<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<_LibraryTab> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sonarr = ref.watch(sonarrClientProvider) != null;
    final radarr = ref.watch(radarrClientProvider) != null;
    final both = sonarr && radarr;
    final kind = both
        ? ref.watch(arrLibraryKindProvider)
        : radarr
        ? ArrKind.radarr
        : ArrKind.sonarr;
    // With one app connected there's nothing to switch between.
    final switcher = both
        ? ArrSwitch<ArrKind>(
            options: [
              (ArrKind.radarr, l.arrMovies),
              (ArrKind.sonarr, l.arrShows),
            ],
            value: kind,
            onChanged: ref.read(arrLibraryKindProvider.notifier).set,
          )
        : null;
    return kind == ArrKind.radarr
        ? _MoviesTab(search: _search, switcher: switcher)
        : _ShowsTab(search: _search, switcher: switcher);
  }
}

// ---------------------------------------------------------------- Activity

/// The queue, the history and the blocklist behind one switch, as under the
/// apps' own Activity. Only the list on show is built, so the queue stops
/// refreshing while another is up.
class _ActivityTab extends ConsumerWidget {
  const _ActivityTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final view = ref.watch(arrActivityViewProvider);
    final lead = ArrSwitch<ArrActivityView>(
      options: [
        (ArrActivityView.queue, l.arrQueue),
        (ArrActivityView.history, l.arrHistory),
        (ArrActivityView.blocklist, l.arrBlocklist),
      ],
      value: view,
      onChanged: ref.read(arrActivityViewProvider.notifier).set,
    );
    return switch (view) {
      ArrActivityView.queue => _QueueTab(lead: lead),
      ArrActivityView.history => ArrHistoryTab(lead: lead),
      ArrActivityView.blocklist => ArrBlocklistView(lead: lead),
    };
  }
}

// ---------------------------------------------------------------- Calendar

class _CalendarTab extends ConsumerWidget {
  const _CalendarTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(arrCalendarProvider);
    // Show Unmonitored reloads it: keep showing the list (and the chip)
    // meanwhile rather than blanking the tab.
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: AppSpinner()),
      error: (e, _) => ErrorView(
        message: e.toString(),
        onRetry: () => ref.invalidate(arrCalendarProvider),
      ),
      data: (merged) {
        final days = _byDay(merged.items);
        final unmonitored = ref.watch(arrCalendarUnmonitoredProvider);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(arrCalendarProvider.future),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: ArrErrorBanner(errors: merged.errors)),
              // Monitored only by default, as in the apps; unmonitored ones
              // then show greyed with their Unmonitored chip.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilterChip(
                      label: Text(l.arrShowUnmonitored),
                      selected: unmonitored,
                      onSelected: (v) => ref
                          .read(arrCalendarUnmonitoredProvider.notifier)
                          .set(v),
                    ),
                  ),
                ),
              ),
              if (days.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: true,
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
      onTap: () => arrOpenTitle(
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

// ---------------------------------------------------------------- Queue

class _QueueTab extends ConsumerStatefulWidget {
  /// The Activity switch, at the left of the row above the list.
  final Widget lead;
  const _QueueTab({required this.lead});

  @override
  ConsumerState<_QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends ConsumerState<_QueueTab> {
  // Picking several downloads, by app and id ("sonarr:12"). Null: not picking.
  Set<String>? _picked;
  bool _busy = false;

  static String _key(ArrQueueItem i) => '${i.kind.name}:${i.id}';

  ArrClient? _clientFor(ArrKind k) => arrClient(ref, k);

  List<ArrQueueItem> _pickedIn(List<ArrQueueItem> all) => [
    for (final i in all)
      if (_picked?.contains(_key(i)) ?? false) i,
  ];

  Future<void> _removePicked(List<ArrQueueItem> all) async {
    if (await showArrQueueRemoveManyDialog(
      context,
      items: _pickedIn(all),
      clientFor: _clientFor,
    )) {
      if (mounted) setState(() => _picked = null);
      ref.invalidate(arrQueueProvider);
    }
  }

  Future<void> _grabPicked(List<ArrQueueItem> all) async {
    final l = AppLocalizations.of(context);
    final held = [for (final i in _pickedIn(all)) if (i.status == 'delay') i];
    setState(() => _busy = true);
    final ok = await arrRun(context, () async {
      for (final i in held) {
        await _clientFor(i.kind)?.grabFromQueue(i.id);
      }
    }, done: l.arrGrabbed);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _picked = null;
    });
    ref.invalidate(arrQueueProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(arrQueueProvider);
    // A refresh keeps showing the last list instead of flashing a spinner.
    final merged = async.asData?.value ?? async.unwrapPrevious().asData?.value;
    final items = merged?.items ?? const <ArrQueueItem>[];
    // Finished downloads leave the queue; they leave the picks too.
    final live = {for (final i in items) _key(i)};
    final picked = _picked?.where(live.contains).toSet();
    final heldPicked = items.any(
      (i) => (picked?.contains(_key(i)) ?? false) && i.status == 'delay',
    );
    final toolbar = ArrToolbar(
      lead: widget.lead,
      actions: [
        if (items.isNotEmpty && picked == null)
          IconButton(
            tooltip: l.arrSelect,
            icon: const Icon(Icons.checklist_rounded),
            onPressed: () => setState(() => _picked = {}),
          ),
      ],
    );
    // Every few seconds while the queue is the list on show; switching to
    // another list or tab ends it.
    Widget polled(Widget child) =>
        _QueuePoll(every: const Duration(seconds: 5), child: child);
    if (merged == null) {
      return polled(
        Column(
          children: [
            toolbar,
            Expanded(
              child: async.hasError
                  ? ErrorView(
                      message: async.error.toString(),
                      onRetry: () => ref.invalidate(arrQueueProvider),
                    )
                  : const Center(child: AppSpinner()),
            ),
          ],
        ),
      );
    }
    final list = RefreshIndicator(
      onRefresh: () => ref.refresh(arrQueueProvider.future),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: toolbar),
          SliverToBoxAdapter(child: ArrErrorBanner(errors: merged.errors)),
          if (merged.items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: true,
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
                itemBuilder: (context, i) {
                  final item = merged.items[i];
                  final k = _key(item);
                  return _QueueCard(
                    item: item,
                    picked: picked?.contains(k),
                    onPick: () => setState(() {
                      final p = {...?_picked};
                      if (!p.remove(k)) p.add(k);
                      _picked = p;
                    }),
                  );
                },
              ),
            ),
        ],
      ),
    );
    if (picked == null) return polled(list);
    return polled(
      PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _picked = null);
        },
        child: Column(
          children: [
            ArrPickBar(
              count: picked.length,
              busy: _busy,
              onCancel: () => setState(() => _picked = null),
              onSelectAll: () => setState(() => _picked = live),
              actions: [
                if (heldPicked)
                  ArrPickAction(
                    Icons.file_download_rounded,
                    l.arrGrabNow,
                    () => _grabPicked(items),
                  ),
                ArrPickAction(
                  Icons.delete_rounded,
                  l.arrRemove,
                  () => _removePicked(items),
                  danger: true,
                ),
              ],
            ),
            Expanded(child: list),
          ],
        ),
      ),
    );
  }
}

class _QueueCard extends ConsumerWidget {
  final ArrQueueItem item;

  /// While picking, whether this one is picked (null: not picking).
  final bool? picked;
  final VoidCallback? onPick;
  const _QueueCard({required this.item, this.picked, this.onPick});

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
    final titleId = item.kind == ArrKind.sonarr ? item.seriesId : item.movieId;
    final importable = client != null && item.canManualImport;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: picked != null
            ? onPick
            // A download the app couldn't match has no page: open what
            // fixes it instead.
            : titleId == null && importable
            ? () => _manualImport(context, ref)
            : () => arrOpenTitle(context, item.kind, titleId),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (picked != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4, top: 22),
                  child: Checkbox(
                    value: picked,
                    onChanged: (_) => onPick?.call(),
                  ),
                ),
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
                    // The release name, unless it's already the heading (a
                    // download the app couldn't match to a title).
                    if (item.mediaTitle != null)
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
                    // What the apps' own queue offers for these: say which
                    // show and episode (or movie) it is, and bring it in.
                    if (importable && picked == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.download_done_rounded),
                          label: Text(l.arrManualImport),
                          onPressed: () => _manualImport(context, ref),
                        ),
                      ),
                  ],
                ),
              ),
              // Held back by a delay profile: send it now.
              if (client != null && picked == null && item.status == 'delay')
                IconButton(
                  tooltip: l.arrGrabNow,
                  icon: const Icon(Icons.file_download_rounded),
                  onPressed: () async {
                    if (await arrRun(
                      context,
                      () => client.grabFromQueue(item.id),
                      done: l.arrGrabbed,
                    )) {
                      ref.invalidate(arrQueueProvider);
                    }
                  },
                ),
              if (client != null && picked == null)
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

  Future<void> _manualImport(BuildContext context, WidgetRef ref) async {
    if (await arrOpenDownloadImport(context, item)) {
      ref.invalidate(arrQueueProvider);
    }
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

/// Picking several titles in a library tab: the selection, keeping it to
/// what's on screen when the search or filter changes, and a poster's
/// long-press menu.
mixin _Picking<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  final selection = ArrSelection();

  @override
  void initState() {
    super.initState();
    selection.addListener(_onPick);
  }

  void _onPick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    selection.removeListener(_onPick);
    selection.dispose();
    super.dispose();
  }

  /// After a search or filter change: titles no longer shown are dropped, so
  /// a bulk action never reaches ones out of sight.
  void keepShown(Iterable<int> shown) {
    if (selection.active) selection.keepOnly(shown.toSet());
  }

  /// After the list reloads (a title deleted elsewhere, a refresh), picks
  /// that are gone are dropped. After this frame: the selection notifies,
  /// which can't happen mid-build.
  void trimTo(List<int>? shown) {
    if (shown == null || !selection.active) return;
    if (selection.ids.every(shown.contains)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) keepShown(shown);
    });
  }

  /// Back ends picking first, as it would in the apps' select mode, rather
  /// than leaving the Manage section.
  Widget backEndsPicking(Widget child) => PopScope(
    canPop: !selection.active,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) selection.stop();
    },
    child: child,
  );

  /// A poster's long-press / right-click menu: start picking from it, or
  /// search for it straight away.
  void posterMenu(
    Offset at, {
    required int id,
    required String title,
    required String searchLabel,
    required Future<void> Function() search,
    required String done,
  }) {
    final l = AppLocalizations.of(context);
    showContextMenu(
      context,
      at: at,
      title: title,
      actions: [
        ContextMenuAction(
          icon: Icons.check_circle_outline_rounded,
          label: l.arrSelect,
          onTap: () => selection.start(id),
        ),
        ContextMenuAction(
          icon: Icons.search_rounded,
          label: searchLabel,
          onTap: () => arrRun(context, search, done: done),
        ),
      ],
    );
  }
}

class _MoviesTab extends ConsumerStatefulWidget {
  /// The Library tab's search box, shared with the other library.
  final TextEditingController search;

  /// The Movies and Shows switch; null with only one of the apps connected.
  final Widget? switcher;

  const _MoviesTab({required this.search, this.switcher});

  @override
  ConsumerState<_MoviesTab> createState() => _MoviesTabState();
}

class _MoviesTabState extends ConsumerState<_MoviesTab>
    with _Picking<_MoviesTab> {
  TextEditingController get _search => widget.search;
  _Sort _sort = _Sort.title;
  _Filter _filter = _Filter.all;

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
    final shown = async.whenData(_apply);
    final shownIds = [for (final m in shown.asData?.value ?? const <ArrMovie>[]) m.id];
    trimTo(shown.hasValue ? shownIds : null);
    void reshown() => keepShown([
      for (final m in _apply(async.asData?.value ?? const [])) m.id,
    ]);
    return backEndsPicking(_LibraryFrame(
      addRow: shown.asData?.value.isNotEmpty ?? false,
      switcher: widget.switcher,
      search: _search,
      hint: l.arrSearchMovies,
      onSearch: () {
        setState(() {});
        reshown();
      },
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
      onFilter: (f) {
        setState(() => _filter = f);
        reshown();
      },
      onRefresh: () => ref.refresh(radarrMoviesProvider.future),
      tools: [
        // Radarr's Collections: film series, and monitoring them.
        _LibraryTool(
          Icons.collections_bookmark_rounded,
          l.arrCollections,
          () => context.push('/arr/collections'),
        ),
        _LibraryTool(
          Icons.library_add_rounded,
          l.arrLibraryImport,
          () => context.push('/arr/library-import?app=radarr'),
        ),
      ],
      onSelect: shownIds.isEmpty || selection.active ? null : selection.start,
      bar: client == null || !selection.active
          ? null
          : ArrBulkBar(
              client: client,
              selection: selection,
              all: shownIds,
              sizes: {
                for (final m in async.asData?.value ?? const <ArrMovie>[])
                  m.id: m.sizeOnDisk,
              },
              onChanged: () {
                ref.invalidate(radarrMoviesProvider);
                ref.invalidate(arrCalendarProvider);
              },
            ),
      kind: ArrKind.radarr,
      body: async.when(
        loading: () => const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: AppSpinner()),
        ),
        error: (e, _) => SliverFillRemaining(
          hasScrollBody: true,
          child: ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(radarrMoviesProvider),
          ),
        ),
        data: (all) {
          final list = shown.asData?.value ?? const [];
          if (list.isEmpty) {
            return SliverFillRemaining(
              hasScrollBody: true,
              child: EmptyState(
                icon: Icons.movie_rounded,
                title: all.isEmpty ? l.arrNoMovies : l.arrNoMatches,
                action: all.isEmpty
                    ? FilledButton.icon(
                        icon: const Icon(Icons.add_rounded),
                        label: Text(l.arrAddMovie),
                        onPressed: () => context.push('/arr/add/movie'),
                      )
                    : _search.text.trim().isEmpty
                    ? null
                    : FilledButton.icon(
                        icon: const Icon(Icons.add_rounded),
                        label: Text(l.arrAddTerm(_search.text.trim())),
                        onPressed: () => context.push(
                          Uri(
                            path: '/arr/add/movie',
                            queryParameters: {'term': _search.text.trim()},
                          ).toString(),
                        ),
                      ),
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
                selected: selection.active ? selection.contains(m.id) : null,
                onTap: () => selection.active
                    ? selection.toggle(m.id)
                    : context.push('/arr/movie/${m.id}'),
                onMenu: client == null || selection.active
                    ? null
                    : (at) => posterMenu(
                        at,
                        id: m.id,
                        title: m.title,
                        searchLabel: l.arrSearchMovie,
                        search: () => client.searchMovie(m.id),
                        done: l.arrSearchStarted(client.kind.appName),
                      ),
              );
            },
          );
        },
      ),
    ));
  }
}

class _ShowsTab extends ConsumerStatefulWidget {
  /// The Library tab's search box, shared with the other library.
  final TextEditingController search;

  /// The Movies and Shows switch; null with only one of the apps connected.
  final Widget? switcher;

  const _ShowsTab({required this.search, this.switcher});

  @override
  ConsumerState<_ShowsTab> createState() => _ShowsTabState();
}

class _ShowsTabState extends ConsumerState<_ShowsTab>
    with _Picking<_ShowsTab> {
  TextEditingController get _search => widget.search;
  _Sort _sort = _Sort.title;
  _Filter _filter = _Filter.all;

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
    final shown = async.whenData(_apply);
    final scheme = Theme.of(context).colorScheme;
    final shownIds = [for (final s in shown.asData?.value ?? const <ArrSeries>[]) s.id];
    trimTo(shown.hasValue ? shownIds : null);
    void reshown() => keepShown([
      for (final s in _apply(async.asData?.value ?? const [])) s.id,
    ]);
    return backEndsPicking(_LibraryFrame(
      addRow: shown.asData?.value.isNotEmpty ?? false,
      switcher: widget.switcher,
      search: _search,
      hint: l.arrSearchShows,
      onSearch: () {
        setState(() {});
        reshown();
      },
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
      onFilter: (f) {
        setState(() => _filter = f);
        reshown();
      },
      onRefresh: () => ref.refresh(sonarrSeriesListProvider.future),
      tools: [
        // Sonarr's Library Import: shows already on disk, all at once.
        _LibraryTool(
          Icons.library_add_rounded,
          l.arrLibraryImport,
          () => context.push('/arr/library-import?app=sonarr'),
        ),
      ],
      onSelect: shownIds.isEmpty || selection.active ? null : selection.start,
      bar: client == null || !selection.active
          ? null
          : ArrBulkBar(
              client: client,
              selection: selection,
              all: shownIds,
              sizes: {
                for (final s in async.asData?.value ?? const <ArrSeries>[])
                  s.id: s.sizeOnDisk,
              },
              onChanged: () {
                ref.invalidate(sonarrSeriesListProvider);
                ref.invalidate(arrCalendarProvider);
              },
            ),
      kind: ArrKind.sonarr,
      body: async.when(
        loading: () => const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: AppSpinner()),
        ),
        error: (e, _) => SliverFillRemaining(
          hasScrollBody: true,
          child: ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(sonarrSeriesListProvider),
          ),
        ),
        data: (all) {
          final list = shown.asData?.value ?? const [];
          if (list.isEmpty) {
            return SliverFillRemaining(
              hasScrollBody: true,
              child: EmptyState(
                icon: Icons.live_tv_rounded,
                title: all.isEmpty ? l.arrNoShows : l.arrNoMatches,
                action: all.isEmpty
                    ? FilledButton.icon(
                        icon: const Icon(Icons.add_rounded),
                        label: Text(l.arrAddShow),
                        onPressed: () => context.push('/arr/add/series'),
                      )
                    : _search.text.trim().isEmpty
                    ? null
                    : FilledButton.icon(
                        icon: const Icon(Icons.add_rounded),
                        label: Text(l.arrAddTerm(_search.text.trim())),
                        onPressed: () => context.push(
                          Uri(
                            path: '/arr/add/series',
                            queryParameters: {'term': _search.text.trim()},
                          ).toString(),
                        ),
                      ),
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
                selected: selection.active ? selection.contains(s.id) : null,
                onTap: () => selection.active
                    ? selection.toggle(s.id)
                    : context.push('/arr/series/${s.id}'),
                onMenu: client == null || selection.active
                    ? null
                    : (at) => posterMenu(
                        at,
                        id: s.id,
                        title: s.title,
                        searchLabel: l.arrSearchMonitored,
                        search: () => client.searchSeries(s.id),
                        done: l.arrSearchStarted(client.kind.appName),
                      ),
              );
            },
          );
        },
      ),
    ));
  }
}

/// Something more a library offers beside Sort and Filter (Collections,
/// Import Library): a button on a wide window, a line of the More menu on a
/// phone.
class _LibraryTool {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _LibraryTool(this.icon, this.label, this.onTap);
}

/// The Movies and Shows switch, the search box and the Sort and Filter
/// menus, above a scrolling grid.
class _LibraryFrame extends StatelessWidget {
  /// The Movies and Shows switch; null with only one of the apps connected.
  final Widget? switcher;
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

  /// Starts picking several titles; null hides Select (nothing to pick, or
  /// already picking).
  final VoidCallback? onSelect;

  /// The bar for the picked titles, above the grid while picking.
  final Widget? bar;

  /// What else this library offers (Movies: Collections, Import Library).
  final List<_LibraryTool> tools;

  /// The app new titles are added to, for the "Add" row under a search.
  final ArrKind kind;

  /// Whether to show that row: not when the empty state already offers it.
  final bool addRow;

  const _LibraryFrame({
    required this.kind,
    required this.addRow,
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
    this.switcher,
    this.onSelect,
    this.bar,
    this.tools = const [],
  });

  /// The row above the grid. A window wide enough takes everything on one
  /// line, each tool as its own button. A phone gets the switch and the menus
  /// on one line and the search box, full width, on the next; what doesn't
  /// fit there (the tools, Select) goes under More.
  Widget _toolbar(BuildContext context, double width) {
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
    final searchBox = SearchField(
      controller: search,
      hint: hint,
      onChanged: (_) => onSearch(),
    );
    final filterMenu = PopupMenuButton<_Filter>(
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
    );
    final sortMenu = PopupMenuButton<_Sort>(
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
    );
    if (width >= 720) {
      return Row(
        children: [
          if (switcher != null) ...[switcher!, const SizedBox(width: 12)],
          // The box stops growing: a search field across a whole desktop
          // window reads as a banner, not a field.
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: searchBox,
              ),
            ),
          ),
          filterMenu,
          sortMenu,
          for (final t in tools)
            IconButton(
              tooltip: t.label,
              icon: Icon(t.icon),
              onPressed: t.onTap,
            ),
          if (onSelect != null)
            IconButton(
              tooltip: l.arrSelect,
              icon: const Icon(Icons.checklist_rounded),
              onPressed: onSelect,
            ),
        ],
      );
    }
    final more = [
      ...tools,
      if (onSelect != null)
        _LibraryTool(Icons.checklist_rounded, l.arrSelect, onSelect!),
    ];
    final moreMenu = more.isEmpty
        ? null
        : PopupMenuButton<_LibraryTool>(
            tooltip: l.arrMore,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (t) => t.onTap(),
            itemBuilder: (_) => [
              for (final t in more)
                PopupMenuItem(
                  value: t,
                  child: Row(
                    children: [
                      Icon(t.icon, size: 20),
                      const SizedBox(width: 14),
                      Flexible(child: Text(t.label)),
                    ],
                  ),
                ),
            ],
          );
    if (switcher == null) {
      return Row(
        children: [
          Expanded(child: searchBox),
          filterMenu,
          sortMenu,
          ?moreMenu,
        ],
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: switcher!,
              ),
            ),
            filterMenu,
            sortMenu,
            ?moreMenu,
          ],
        ),
        const SizedBox(height: 8),
        // The row's own right edge is 8 in, for the icon buttons; the box
        // lines up with the grid instead.
        Padding(padding: const EdgeInsets.only(right: 8), child: searchBox),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final frame = RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: LayoutBuilder(
                builder: (context, c) => _toolbar(context, c.maxWidth),
              ),
            ),
          ),
          body,
          // Typed something? Offer to look it up online, whether or not the
          // library had it: "Dune" may match the 1984 film you own when you
          // were after the new one.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: search,
            builder: (context, v, _) {
              final term = v.text.trim();
              if (term.isEmpty || !addRow) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: _AddTermRow(kind: kind, term: term),
                ),
              );
            },
          ),
        ],
      ),
    );
    if (bar == null) return frame;
    return Column(children: [bar!, Expanded(child: frame)]);
  }
}

/// "Add “Dune”: look it up in Radarr", under a library search.
class _AddTermRow extends StatelessWidget {
  final ArrKind kind;
  final String term;
  const _AddTermRow({required this.kind, required this.term});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final path = kind == ArrKind.sonarr ? 'series' : 'movie';
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.secondaryContainer.withValues(alpha: 0.5),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(Icons.add_circle_rounded, color: scheme.primary),
        title: Text(l.arrAddTerm(term), overflow: TextOverflow.ellipsis),
        subtitle: Text(l.arrLookUpIn(kind.appName)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push(
          Uri(
            path: '/arr/add/$path',
            queryParameters: {'term': term},
          ).toString(),
        ),
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

  /// While picking, whether this one is picked (null: not picking).
  final bool? selected;

  /// Long-press / right-click menu.
  final void Function(Offset at)? onMenu;

  const _ArrPosterCard({
    super.key,
    required this.client,
    required this.images,
    required this.title,
    required this.bar,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.selected,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: HoverPosterArt(
                  onTap: onTap,
                  onMenu: onMenu,
                  art: ArrArt(
                    client: client,
                    images: images,
                    placeholderIcon: icon,
                  ),
                  overlay: bar,
                ),
              ),
              // The same tick as the Jellyfin library's picking, announced
              // to screen readers as picked or not.
              if (selected != null)
                Positioned.fill(
                  child: Semantics(
                    selected: selected,
                    child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: selected!
                            ? theme.colorScheme.primary.withValues(alpha: 0.28)
                            : Colors.black.withValues(alpha: 0.28),
                        border: selected!
                            ? Border.all(
                                color: theme.colorScheme.primary,
                                width: 3,
                              )
                            : null,
                      ),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            selected!
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            color: selected!
                                ? theme.colorScheme.primary
                                : Colors.white70,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                  ),
                ),
            ],
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
