import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../routing/app_shell.dart';
import '../services/tv_mode.dart';
import '../state/arr_providers.dart';
import '../state/download_providers.dart';
import '../state/seerr_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/context_menu.dart';
import 'arr_activity_screens.dart';
import 'download_clients_screen.dart';
import 'prowlarr_screen.dart';
import 'arr_calendar_tab.dart';
import 'arr_detail_screens.dart';
import 'arr_import_screen.dart';
import 'arr_releases_screen.dart';
import '../widgets/arr_actions.dart';
import '../widgets/arr_bulk.dart';
import '../widgets/arr_pane.dart';
import '../widgets/arr_queue_poll.dart';
import '../widgets/arr_skeletons.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/media_cards.dart';
import '../widgets/motion.dart';
import '../widgets/search_field.dart';
import '../widgets/tv_focus.dart';
import '../widgets/window_frame.dart';

/// [bar] as the furniture it is on a TV (see [TvChrome]); as it is elsewhere.
PreferredSizeWidget _tvChromeTabs(TabBar bar) => isTvDevice
    ? PreferredSize(
        preferredSize: bar.preferredSize,
        child: TvChrome(child: bar),
      )
    : bar;

/// The Manage section: Sonarr and Radarr in one place. The Library they
/// manage comes first, then what's coming up (Calendar), what's downloading
/// and what happened (Activity), and what's still missing (Wanted).
///
/// On a window wide enough, a title opens in a pane beside the lists rather
/// than on a page over them, and stays there from tab to tab.
class ArrScreen extends ConsumerStatefulWidget {
  /// The tab to open on, by name: `calendar`, `activity` or `wanted`.
  /// Anything else is the Library. Home's rows open the tab they are from.
  final String? tab;
  const ArrScreen({super.key, this.tab});

  @override
  ConsumerState<ArrScreen> createState() => _ArrScreenState();
}

class _ArrScreenState extends ConsumerState<ArrScreen> {
  /// The title in the pane. Kept while the window is too narrow to show
  /// one, so widening it again brings the pane back.
  ArrTitleRef? _open;

  /// Whether the window is wide enough for the pane, as last laid out.
  bool _paneFits = false;

  /// The Library's search box, for the keyboard's way to it.
  final _searchFocus = FocusNode(debugLabel: 'Manage search');

  /// The section itself, which the shortcuts hang on.
  final _keysFocus = FocusNode(debugLabel: 'Manage');

  // Built once: opening or closing the pane then lays the tabs out again
  // without building them again.
  late final _tabs = TabBarView(
    children: [
      RepaintBoundary(child: _LibraryTab(searchFocus: _searchFocus)),
      const RepaintBoundary(child: ArrCalendarTab()),
      const RepaintBoundary(child: _ActivityTab()),
      const RepaintBoundary(child: ArrWantedTab()),
    ],
  );

  @override
  void dispose() {
    _searchFocus.dispose();
    _keysFocus.dispose();
    super.dispose();
  }

  void _show(ArrKind kind, int id) =>
      setState(() => _open = (kind: kind, id: id));

  void _close() => setState(() => _open = null);

  /// A title opened as a page, the window too narrow for the pane: the one
  /// kept for a wider window is no longer the last one looked at.
  void _forget() => _open = null;

  /// A title deleted (from its page, the pane, or with others picked in the
  /// library) leaves its list when that reloads: the pane goes with it.
  /// Only a title the list had and then lost counts. One the list never had
  /// may just be newer than the list.
  void _closeWhenGone<T>(
    ArrTitleRef open,
    ProviderListenable<AsyncValue<List<T>>> list,
    int Function(T) idOf,
  ) {
    ref.listen(list, (prev, next) {
      if (next.isLoading || next.hasError || !next.hasValue) return;
      final had = prev?.value?.any((t) => idOf(t) == open.id) ?? false;
      final has = next.requireValue.any((t) => idOf(t) == open.id);
      if (had && !has && mounted && _open == open) _close();
    });
  }

  /// F5 and Ctrl+R: every list in the section, and the title in the pane.
  void _refresh() {
    ref.invalidate(radarrMoviesProvider);
    ref.invalidate(sonarrSeriesListProvider);
    ref.invalidate(lidarrArtistsProvider);
    ref.invalidate(arrCalendarProvider);
    ref.invalidate(arrQueueProvider);
    ref.invalidate(arrQueueStatusProvider);
    ref.invalidate(arrWantedProvider);
    ref.invalidate(arrRecentHistoryProvider);
    ref.invalidate(arrBlocklistProvider);
    ref.invalidate(seerrPendingRequestsProvider);
    ref.invalidate(arrHealthProvider);
    final open = _open;
    if (open == null) return;
    // Whether the library has it now is asked again too.
    ref.invalidate(arrLibraryItemProvider);
    switch (open.kind) {
      case ArrKind.radarr:
        arrMovieChanged(ref, open.id);
      case ArrKind.sonarr:
        arrSeriesChanged(ref, open.id);
      case ArrKind.lidarr:
        arrArtistChanged(ref, open.id);
    }
  }

  /// The narrowest window whose top bar still names its Add button.
  static const double _addNamedFrom = 400;

  /// The keyboard's part, where there is one: a desktop window.
  Widget _withKeys(BuildContext context, Widget child) {
    if (!isDesktopWindowFrame) return child;
    final tabs = DefaultTabController.of(context);
    void search() {
      tabs.animateTo(0);
      // The box may not be there yet, coming from another tab: the request
      // then waits for it.
      _searchFocus.requestFocus();
    }

    void back() {
      // The search box gives up the keyboard first. The section takes it,
      // so the shortcuts go on working.
      if (_searchFocus.hasFocus) return _keysFocus.requestFocus();
      if (_open != null && _paneFits) return _close();
      // Nothing to close: Esc ends picking, as Back does, and never leaves
      // the section.
      if (ModalRoute.of(context)?.popDisposition ==
          RoutePopDisposition.doNotPop) {
        Navigator.maybePop(context);
      }
    }

    const keyR = LogicalKeyboardKey.keyR;
    const keyF = LogicalKeyboardKey.keyF;
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): _refresh,
        const SingleActivator(keyR, control: true): _refresh,
        const SingleActivator(keyR, meta: true): _refresh,
        const SingleActivator(keyF, control: true): search,
        const SingleActivator(keyF, meta: true): search,
        const SingleActivator(LogicalKeyboardKey.escape): back,
        for (var i = 0; i < digits.length; i++) ...{
          SingleActivator(digits[i], control: true): () => tabs.animateTo(i),
          SingleActivator(digits[i], meta: true): () => tabs.animateTo(i),
        },
      },
      // Never a stop for Tab: nothing would show the keyboard is there.
      child: Focus(
        focusNode: _keysFocus,
        autofocus: true,
        skipTraversal: true,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final kinds = ref.watch(arrLibraryKindsProvider);
    // Prowlarr on its own: the section is its indexers (with a way to the
    // download clients); without it, the download clients alone.
    if (kinds.isEmpty && ref.watch(prowlarrClientProvider) != null) {
      return const ProwlarrScreen();
    }
    if (kinds.isEmpty && ref.watch(downloadClientsProvider).isNotEmpty) {
      return const DownloadClientsScreen();
    }
    if (kinds.isEmpty) {
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
    final open = _open;
    if (open != null) {
      switch (open.kind) {
        case ArrKind.radarr:
          _closeWhenGone(open, radarrMoviesProvider, (ArrMovie m) => m.id);
        case ArrKind.sonarr:
          _closeWhenGone(
            open,
            sonarrSeriesListProvider,
            (ArrSeries s) => s.id,
          );
        case ArrKind.lidarr:
          _closeWhenGone(open, lidarrArtistsProvider, (ArrArtist a) => a.id);
      }
    }
    // Four tabs fit a phone side by side; on a wide window they'd stretch
    // across it, so they keep their own width there.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return DefaultTabController(
      length: 4,
      initialIndex: switch (widget.tab) {
        'calendar' => 1,
        'activity' => 2,
        'wanted' => 3,
        _ => 0,
      },
      // The Activity tab's count stays current while the section is open.
      child: ArrQueuePoll(
        countOnly: true,
        every: const Duration(seconds: 30),
        child: Builder(
          builder: (context) => _withKeys(
            context,
            Scaffold(
              appBar: AppBar(
                leading: mobileDrawerLeading(context),
                // Never cut short: on the narrowest phones it's set smaller.
                title: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(l.appNavManage),
                ),
                actions: [
                  // Add opens on the kind of library it's pressed from; from
                  // the other tabs it searches every app together.
                  Builder(
                    builder: (context) {
                      void add() {
                        final onLibrary =
                            DefaultTabController.of(context).index == 0;
                        final kind = !onLibrary
                            ? null
                            : arrShownLibrary(
                                ref.read(arrLibraryKindsProvider),
                                ref.read(arrLibraryKindProvider),
                              );
                        context.push(switch (kind) {
                          ArrKind.radarr => '/arr/add/movie',
                          ArrKind.sonarr => '/arr/add/series',
                          ArrKind.lidarr => '/arr/add/artist',
                          null => '/arr/add',
                        });
                      }

                      // A small phone has no room for the word beside the
                      // section's name: the button alone, named to a reader.
                      if (MediaQuery.sizeOf(context).width < _addNamedFrom) {
                        return IconButton.filledTonal(
                          tooltip: l.arrAdd,
                          icon: const Icon(Icons.add_rounded),
                          onPressed: add,
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilledButton.tonalIcon(
                          style: kInlineButtonStyle,
                          icon: const Icon(Icons.add_rounded),
                          label: Text(l.arrAdd),
                          onPressed: add,
                        ),
                      );
                    },
                  ),
                  // Prowlarr's indexers, behind the apps.
                  if (ref.watch(prowlarrClientProvider) != null)
                    IconButton(
                      tooltip: l.prowlarrIndexers,
                      icon: const Icon(Icons.travel_explore_rounded),
                      onPressed: () => context.push('/arr/indexers'),
                    ),
                  // The download clients, behind them too.
                  if (ref.watch(downloadClientsProvider).isNotEmpty)
                    IconButton(
                      tooltip: l.dlClients,
                      icon: const Icon(Icons.downloading_rounded),
                      onPressed: () => context.push('/arr/clients'),
                    ),
                  ArrHealthButton(onTap: () => context.push('/arr/health')),
                  IconButton(
                    tooltip: l.browseSettings,
                    icon: const Icon(Icons.settings_rounded),
                    onPressed: () => context.push('/arr-settings'),
                  ),
                ],
                // A TV opens a tab on its list, not on the tabs above it.
                bottom: _tvChromeTabs(TabBar(
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
                      // A long count on a small phone shrinks the pair a
                      // little instead of cutting the name short.
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
                )),
              ),
              // On a TV the remote stays put when what it was on goes: a
              // download that finished, a list swapped for another.
              body: TvFocusKeeper(child: LayoutBuilder(builder: _body)),
            ),
          ),
        ),
      ),
    );
  }

  /// The tabs, and beside them the pane when a title is open and the
  /// section is wide enough for both. The tabs keep their place in the tree
  /// either way, so nothing in them starts over as the pane comes and goes.
  Widget _body(BuildContext context, BoxConstraints box) {
    // A TV keeps to pages: a pane would be a second place for the remote's
    // focus to get lost in.
    final width = isTvDevice ? null : arrPaneWidth(box.maxWidth);
    _paneFits = width != null;
    final open = width == null ? null : _open;
    return ArrPaneScope(
      shown: open,
      open: width == null ? null : _show,
      onPage: _forget,
      // Back closes the pane before it leaves the section: a tablet's Back
      // button or gesture, where there's no Escape.
      child: PopScope(
        canPop: open == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _paneFits && _open != null) _close();
        },
        child: Row(
          children: [
            Expanded(child: _tabs),
            if (open != null && width != null) ...[
              const VerticalDivider(width: 1),
              SizedBox(
                width: width,
                child: _Pane(
                  // Another title is another page: nothing of the last
                  // one's scroll or open seasons carries over.
                  key: ValueKey(open),
                  title: open,
                  width: width,
                  onClose: _close,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A title's page, beside the lists. The page lays itself out for the
/// pane's width, not the window's.
class _Pane extends StatelessWidget {
  final ArrTitleRef title;
  final double width;
  final VoidCallback onClose;

  const _Pane({
    super.key,
    required this.title,
    required this.width,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return ArrPaneHost(
      close: onClose,
      openPage: () => arrOpenTitlePage(context, title.kind, title.id),
      child: MediaQuery(
        data: media.copyWith(size: Size(width, media.size.height)),
        child: switch (title.kind) {
          ArrKind.radarr => ArrMovieScreen(id: title.id),
          ArrKind.sonarr => ArrSeriesScreen(id: title.id),
          ArrKind.lidarr => ArrArtistScreen(id: title.id),
        },
      ),
    );
  }
}

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

// ---------------------------------------------------------------- Library

/// Movies, Shows and Music behind one switch. The search box is shared, so
/// a title typed once can be looked for in each.
class _LibraryTab extends ConsumerStatefulWidget {
  /// The search box's focus, held by the section for Ctrl+F.
  final FocusNode searchFocus;
  const _LibraryTab({required this.searchFocus});

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
    final kinds = ref.watch(arrLibraryKindsProvider);
    final kind =
        arrShownLibrary(kinds, ref.watch(arrLibraryKindProvider)) ??
        ArrKind.radarr;
    // With one app connected there's nothing to switch between.
    final switcher = kinds.length > 1
        ? ArrSwitch<ArrKind>(
            options: [
              for (final k in kinds)
                (
                  k,
                  switch (k) {
                    ArrKind.radarr => l.arrMovies,
                    ArrKind.sonarr => l.arrShows,
                    ArrKind.lidarr => l.arrMusic,
                  },
                ),
            ],
            value: kind,
            onChanged: ref.read(arrLibraryKindProvider.notifier).set,
          )
        : null;
    final focus = widget.searchFocus;
    return switch (kind) {
      ArrKind.radarr => _MoviesTab(
        search: _search,
        searchFocus: focus,
        switcher: switcher,
      ),
      ArrKind.sonarr => _ShowsTab(
        search: _search,
        searchFocus: focus,
        switcher: switcher,
      ),
      ArrKind.lidarr => _ArtistsTab(
        search: _search,
        searchFocus: focus,
        switcher: switcher,
      ),
    };
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
    // Seerr's requests that wait for an answer, for whoever gives them: a
    // request is the first step of a download.
    final requests = ref.watch(seerrCanManageRequestsProvider);
    final waiting = requests
        ? ref.watch(seerrPendingRequestsProvider).value?.total ?? 0
        : 0;
    final chosen = ref.watch(arrActivityViewProvider);
    final view = chosen == ArrActivityView.requests && !requests
        ? ArrActivityView.queue
        : chosen;
    final lead = ArrSwitch<ArrActivityView>(
      options: [
        (ArrActivityView.queue, l.arrQueue),
        (ArrActivityView.history, l.arrHistory),
        (ArrActivityView.blocklist, l.arrBlocklist),
        if (requests)
          (
            ArrActivityView.requests,
            waiting > 0 ? l.arrRequestsWaiting(waiting) : l.browseRequests,
          ),
      ],
      short: {ArrActivityView.requests: l.browseRequests},
      value: view,
      onChanged: ref.read(arrActivityViewProvider.notifier).set,
    );
    return switch (view) {
      ArrActivityView.queue => _QueueTab(lead: lead),
      ArrActivityView.history => ArrHistoryTab(lead: lead),
      ArrActivityView.blocklist => ArrBlocklistView(lead: lead),
      ArrActivityView.requests => ArrRequestsView(lead: lead),
    };
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
        // Picking several is for a phone or a desktop, not a remote.
        if (!isTvDevice && items.isNotEmpty && picked == null)
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
        ArrQueuePoll(every: const Duration(seconds: 5), child: child);
    if (merged == null) {
      return polled(
        Column(
          children: [
            ArrListColumn(child: toolbar),
            Expanded(
              child: async.hasError
                  ? ErrorView(
                      message: async.error.toString(),
                      onRetry: () => ref.invalidate(arrQueueProvider),
                    )
                  : const ArrRowsSkeleton(cards: true),
            ),
          ],
        ),
      );
    }
    final list = RefreshIndicator(
      onRefresh: () => ref.refresh(arrQueueProvider.future),
      child: ArrListView(
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
                    onSelect: isTvDevice
                        ? null
                        : () => setState(() => _picked = {k}),
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

  /// Starts picking, with this one picked: the menu's Select.
  final VoidCallback? onSelect;

  const _QueueCard({
    required this.item,
    this.picked,
    this.onPick,
    this.onSelect,
  });

  /// From this width the card has room for a bigger poster.
  static const double roomyFrom = 560;

  // By the card's own width: the pane beside the list narrows it.
  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, box) =>
        _card(context, ref, roomy: box.maxWidth >= roomyFrom),
  );

  Widget _card(BuildContext context, WidgetRef ref, {required bool roomy}) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final client = arrWatchClient(ref, item.kind);
    final (String status, Color color) = arrQueueStanding(l, scheme, item);
    final eta = item.estimatedCompletion?.difference(DateTime.now());
    final left = eta != null && !eta.isNegative && item.status == 'downloading'
        ? l.arrTimeLeft(arrDuration(eta))
        : null;
    final heading = [
      item.mediaTitle ?? item.title,
      ?item.episodeCode,
      // An artist's download is an album.
      if (item.mediaTitle != null) ?item.albumTitle,
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
    final titleId = item.titleId;
    // Saying which show, movie or album a download is takes a keyboard and
    // a pointer: not on a TV.
    final importable =
        !isTvDevice && client != null && item.canManualImport;
    final held = item.status == 'delay';
    // What the card's buttons do, by name, on a right-click or a long press.
    void menu(Offset at) => showContextMenu(
      context,
      at: at,
      title: heading,
      actions: [
        ...arrOpenActions(context, item.kind, titleId),
        if (importable)
          ContextMenuAction(
            icon: Icons.download_done_rounded,
            label: l.arrManualImport,
            onTap: () => _manualImport(context, ref),
          ),
        if (client != null && held)
          ContextMenuAction(
            icon: Icons.file_download_rounded,
            label: l.arrGrabNow,
            onTap: () => _grab(context, ref, client),
          ),
        if (onSelect != null)
          ContextMenuAction(
            icon: Icons.check_circle_outline_rounded,
            label: l.arrSelect,
            onTap: onSelect!,
          ),
        if (client != null)
          ContextMenuAction(
            icon: Icons.close_rounded,
            label: l.arrRemoveFromQueue,
            color: scheme.error,
            onTap: () => _remove(context, ref, client),
          ),
      ],
    );
    final shown = ArrPaneScope.shows(context, item.kind, titleId);
    final plain = theme.cardTheme.color ?? scheme.surfaceContainer;
    // Tinted while the pane beside the list shows its title.
    final cardColor = shown
        ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.14), plain)
        : plain;
    // The title's wide picture behind the card. A download the app
    // couldn't match has none.
    final fanart = client?.imageUrl(item.images, 'fanart') != null;
    final card = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: cardColor,
      child: ArrCardWash(
        color: cardColor,
        quiet: !roomy,
        picture: fanart
            ? (width) => ArrArt(
                client: client,
                images: item.images,
                type: 'fanart',
                width: 780,
                decodeWidth: width,
                alignment: const Alignment(0, -0.4),
                bare: true,
              )
            : null,
        // Its own ink, over the picture.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: picked != null
                ? onPick
                // A download the app couldn't match has no page: open what
                // fixes it instead.
                : titleId == null && importable
                ? () => _manualImport(context, ref)
                // On a TV, what can still be done with it.
                : titleId == null && isTvDevice && client != null
                ? () => menu(Offset.zero)
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
                      width: roomy ? 64 : 52,
                      height: roomy ? 96 : 78,
                      child: ArrArt(
                        client: client,
                        images: item.images,
                        width: roomy ? 342 : 185,
                        placeholderIcon: arrKindIcon(item.kind),
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
                            // One line that gives way at its end, however
                            // narrow the card: the time left first, as
                            // what's asked of a download most.
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    if (left != null)
                                      TextSpan(
                                        text: left,
                                        style: TextStyle(
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                    if (left != null && meta.isNotEmpty)
                                      const TextSpan(text: ' · '),
                                    TextSpan(text: meta),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
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
                  if (client != null && picked == null && held)
                    TvRowActions(
                      child: IconButton(
                        tooltip: l.arrGrabNow,
                        icon: const Icon(Icons.file_download_rounded),
                        onPressed: () => _grab(context, ref, client),
                      ),
                    ),
                  if (client != null && picked == null)
                    TvRowActions(
                      child: IconButton(
                        tooltip: l.arrRemoveFromQueue,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => _remove(context, ref, client),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // While picking, a press picks: no menu to get in its way.
    if (picked != null) return card;
    return GestureDetector(
      onSecondaryTapUp: (d) => menu(d.globalPosition),
      onLongPressStart: (d) => menu(d.globalPosition),
      child: card,
    );
  }

  Future<void> _grab(
    BuildContext context,
    WidgetRef ref,
    ArrClient client,
  ) async {
    final done = AppLocalizations.of(context).arrGrabbed;
    if (await arrRun(context, () => client.grabFromQueue(item.id), done: done)) {
      ref.invalidate(arrQueueProvider);
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ArrClient client,
  ) async {
    if (await showArrQueueRemoveDialog(context, client: client, item: item)) {
      ref.invalidate(arrQueueProvider);
    }
  }

  Future<void> _manualImport(BuildContext context, WidgetRef ref) async {
    if (await arrOpenDownloadImport(context, item)) {
      ref.invalidate(arrQueueProvider);
    }
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
      if (!didPop && !ArrPaneScope.takesBack(context)) selection.stop();
    },
    child: child,
  );

  /// A poster's long-press / right-click menu: start picking from it, or
  /// search for it straight away.
  void posterMenu(
    Offset at, {
    required ArrKind kind,
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
        ...arrOpenActions(context, kind, id),
        ContextMenuAction(
          icon: Icons.search_rounded,
          label: searchLabel,
          onTap: () => arrRun(context, search, done: done),
        ),
        // A movie is one release to choose; a show's are chosen a season
        // or an episode at a time, on its page.
        if (kind == ArrKind.radarr)
          ContextMenuAction(
            icon: Icons.manage_search_rounded,
            label: l.arrInteractiveSearch,
            onTap: () => context.push(ArrReleaseTarget.movie(id).location),
          ),
        ContextMenuAction(
          icon: Icons.check_circle_outline_rounded,
          label: l.arrSelect,
          onTap: () => selection.start(id),
        ),
      ],
    );
  }
}

class _MoviesTab extends ConsumerStatefulWidget {
  /// The Library tab's search box, shared with the other library.
  final TextEditingController search;
  final FocusNode searchFocus;

  /// The Movies and Shows switch; null with only one of the apps connected.
  final Widget? switcher;

  const _MoviesTab({
    required this.search,
    required this.searchFocus,
    this.switcher,
  });

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
      searchFocus: widget.searchFocus,
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
        // Folders to go through and match: not with a remote.
        if (!isTvDevice)
          _LibraryTool(
            Icons.library_add_rounded,
            l.arrLibraryImport,
            () => context.push('/arr/library-import?app=radarr'),
          ),
      ],
      onSelect: isTvDevice || shownIds.isEmpty || selection.active
          ? null
          : selection.start,
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
        loading: () => const ArrPosterGridSkeleton(
          gridDelegate: _PosterGrid.cells,
          padding: _PosterGrid.padding,
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
                shownAs: (kind: ArrKind.radarr, id: m.id),
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
                    : arrOpenTitle(context, ArrKind.radarr, m.id),
                onMenu: client == null || selection.active
                    ? null
                    : (at) => posterMenu(
                        at,
                        kind: ArrKind.radarr,
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
  final FocusNode searchFocus;

  /// The Movies and Shows switch; null with only one of the apps connected.
  final Widget? switcher;

  const _ShowsTab({
    required this.search,
    required this.searchFocus,
    this.switcher,
  });

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
      searchFocus: widget.searchFocus,
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
        // Folders to go through and match: not with a remote.
        if (!isTvDevice)
          _LibraryTool(
            Icons.library_add_rounded,
            l.arrLibraryImport,
            () => context.push('/arr/library-import?app=sonarr'),
          ),
      ],
      onSelect: isTvDevice || shownIds.isEmpty || selection.active
          ? null
          : selection.start,
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
        loading: () => const ArrPosterGridSkeleton(
          gridDelegate: _PosterGrid.cells,
          padding: _PosterGrid.padding,
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
                shownAs: (kind: ArrKind.sonarr, id: s.id),
                client: client,
                images: s.images,
                title: s.title,
                subtitle: l.arrEpisodesOf(s.episodeFileCount, s.episodeCount),
                bar: ArrPosterBar(color: color, fraction: s.progress),
                icon: Icons.live_tv_rounded,
                selected: selection.active ? selection.contains(s.id) : null,
                onTap: () => selection.active
                    ? selection.toggle(s.id)
                    : arrOpenTitle(context, ArrKind.sonarr, s.id),
                onMenu: client == null || selection.active
                    ? null
                    : (at) => posterMenu(
                        at,
                        kind: ArrKind.sonarr,
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

class _ArtistsTab extends ConsumerStatefulWidget {
  /// The Library tab's search box, shared with the other libraries.
  final TextEditingController search;
  final FocusNode searchFocus;

  /// The library switch; null with only one of the apps connected.
  final Widget? switcher;

  const _ArtistsTab({
    required this.search,
    required this.searchFocus,
    this.switcher,
  });

  @override
  ConsumerState<_ArtistsTab> createState() => _ArtistsTabState();
}

class _ArtistsTabState extends ConsumerState<_ArtistsTab>
    with _Picking<_ArtistsTab> {
  TextEditingController get _search => widget.search;
  _Sort _sort = _Sort.title;
  _Filter _filter = _Filter.all;

  List<ArrArtist> _apply(List<ArrArtist> all) {
    final q = _search.text.trim().toLowerCase();
    final list = all.where((a) {
      if (q.isNotEmpty && !a.name.toLowerCase().contains(q)) return false;
      return switch (_filter) {
        _Filter.monitored => a.monitored,
        _Filter.unmonitored => !a.monitored,
        _Filter.missing => a.monitored && a.missingTracks > 0,
        _ => true,
      };
    }).toList();
    // By Lidarr's sort name: "Beatles, The" files under B.
    int byName(ArrArtist a, ArrArtist b) =>
        (a.sortName ?? a.name.toLowerCase()).compareTo(
          b.sortName ?? b.name.toLowerCase(),
        );
    list.sort(switch (_sort) {
      _Sort.added => (a, b) => (b.added ?? DateTime(0)).compareTo(
        a.added ?? DateTime(0),
      ),
      _Sort.size => (a, b) => b.sizeOnDisk.compareTo(a.sizeOnDisk),
      _ => byName,
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final client = ref.watch(lidarrClientProvider);
    final async = ref.watch(lidarrArtistsProvider);
    final shown = async.whenData(_apply);
    final scheme = Theme.of(context).colorScheme;
    final shownIds = [
      for (final a in shown.asData?.value ?? const <ArrArtist>[]) a.id,
    ];
    trimTo(shown.hasValue ? shownIds : null);
    void reshown() => keepShown([
      for (final a in _apply(async.asData?.value ?? const [])) a.id,
    ]);
    return backEndsPicking(
      _LibraryFrame(
        addRow: shown.asData?.value.isNotEmpty ?? false,
        switcher: widget.switcher,
        search: _search,
        searchFocus: widget.searchFocus,
        hint: l.arrSearchArtists,
        onSearch: () {
          setState(() {});
          reshown();
        },
        sort: _sort,
        // An artist has no year of its own.
        sorts: const [_Sort.title, _Sort.added, _Sort.size],
        onSort: (s) => setState(() => _sort = s),
        filter: _filter,
        filters: const [
          _Filter.all,
          _Filter.monitored,
          _Filter.unmonitored,
          _Filter.missing,
        ],
        onFilter: (f) {
          setState(() => _filter = f);
          reshown();
        },
        onRefresh: () => ref.refresh(lidarrArtistsProvider.future),
        onSelect: isTvDevice || shownIds.isEmpty || selection.active
            ? null
            : selection.start,
        bar: client == null || !selection.active
            ? null
            : ArrBulkBar(
                client: client,
                selection: selection,
                all: shownIds,
                sizes: {
                  for (final a in async.asData?.value ?? const <ArrArtist>[])
                    a.id: a.sizeOnDisk,
                },
                onChanged: () => ref.invalidate(lidarrArtistsProvider),
              ),
        kind: ArrKind.lidarr,
        body: async.when(
          loading: () => const ArrPosterGridSkeleton(
            gridDelegate: _PosterGrid.cells,
            padding: _PosterGrid.padding,
          ),
          error: (e, _) => SliverFillRemaining(
            hasScrollBody: true,
            child: ErrorView(
              message: e.toString(),
              onRetry: () => ref.invalidate(lidarrArtistsProvider),
            ),
          ),
          data: (all) {
            final list = shown.asData?.value ?? const [];
            if (list.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: true,
                child: EmptyState(
                  icon: Icons.library_music_rounded,
                  title: all.isEmpty ? l.arrNoArtists : l.arrNoMatches,
                  action: all.isEmpty
                      ? FilledButton.icon(
                          icon: const Icon(Icons.add_rounded),
                          label: Text(l.arrAddArtist),
                          onPressed: () => context.push('/arr/add/artist'),
                        )
                      : _search.text.trim().isEmpty
                      ? null
                      : FilledButton.icon(
                          icon: const Icon(Icons.add_rounded),
                          label: Text(l.arrAddTerm(_search.text.trim())),
                          onPressed: () => context.push(
                            Uri(
                              path: '/arr/add/artist',
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
                final a = list[i];
                // Lidarr's bar: green when every wanted track is there, red
                // when some are missing, grey when the artist isn't
                // monitored.
                final color = !a.monitored
                    ? scheme.outline
                    : a.missingTracks > 0
                    ? arrMissingColor
                    : arrDownloadedColor;
                return _ArrPosterCard(
                  key: ValueKey('la${a.id}'),
                  shownAs: (kind: ArrKind.lidarr, id: a.id),
                  client: client,
                  images: a.images,
                  title: a.name,
                  subtitle: l.arrTracksOf(a.trackFileCount, a.trackCount),
                  bar: ArrPosterBar(color: color, fraction: a.progress),
                  icon: Icons.library_music_rounded,
                  selected: selection.active ? selection.contains(a.id) : null,
                  onTap: () => selection.active
                      ? selection.toggle(a.id)
                      : arrOpenTitle(context, ArrKind.lidarr, a.id),
                  onMenu: client == null || selection.active
                      ? null
                      : (at) => posterMenu(
                          at,
                          kind: ArrKind.lidarr,
                          id: a.id,
                          title: a.name,
                          searchLabel: l.arrSearchMonitored,
                          search: () => client.searchArtist(a.id),
                          done: l.arrSearchStarted(client.kind.appName),
                        ),
                );
              },
            );
          },
        ),
      ),
    );
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
  final FocusNode searchFocus;
  final String hint;
  final VoidCallback onSearch;
  final _Sort sort;

  /// The orders this library offers.
  final List<_Sort> sorts;
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
    required this.searchFocus,
    required this.hint,
    required this.onSearch,
    required this.sort,
    this.sorts = _Sort.values,
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
      focusNode: searchFocus,
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
        for (final s in sorts)
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
              // A TV opens the library on its first poster.
              child: TvChrome(
                child: LayoutBuilder(
                  builder: (context, c) => _toolbar(context, c.maxWidth),
                ),
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
    final path = switch (kind) {
      ArrKind.sonarr => 'series',
      ArrKind.radarr => 'movie',
      ArrKind.lidarr => 'artist',
    };
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

  /// Shared with the grid's skeleton, so the posters arrive where their
  /// placeholders stood.
  static const padding = EdgeInsets.fromLTRB(16, 12, 16, 24);
  static const cells = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 168,
    mainAxisSpacing: 18,
    crossAxisSpacing: 14,
    childAspectRatio: 0.52,
  );

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: padding,
      sliver: SliverGrid.builder(
        gridDelegate: cells,
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

  /// The title this is the poster of: it's ringed while the pane shows it.
  final ArrTitleRef shownAs;

  const _ArrPosterCard({
    super.key,
    required this.shownAs,
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
    final shown =
        selected == null &&
        ArrPaneScope.shows(context, shownAs.kind, shownAs.id);
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
              if (shown)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 3,
                        ),
                      ),
                    ),
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
